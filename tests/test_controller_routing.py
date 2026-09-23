"""Regressions: multi-row SDL DB and procps' 15-character process name."""
import ctypes
import ctypes.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "port/rufflehandheld/rufflehandheld/runtime/core"
LAUNCHERS = [CORE / "native_v020/Ruffle-Native-Launch.sh",
             CORE / "native_multifile/Ruffle-Native-Multifile-Launch.sh"]
GUID1 = "19003982010000008811000088010000"
GUID2 = "030000005e0400008e02000000000000"
DB = (f"{GUID1},r36s_Gamepad,a:b0,b:b1,rightshoulder:b5,dpup:h0.1,platform:Linux,\n"
      f"{GUID2},Second Controller,a:b2,b:b3,rightshoulder:b7,dpup:h0.1,platform:Linux,\n")

def route(launcher, mode, click, db):
    body = launcher.read_text()
    first = body.index("rh_route_profile_input")
    body = body[first:body.index("\nA_KEYCODE=", first)]
    result = subprocess.run(["bash", "-c", body+'\nrh_route_profile_input "$1" "$2" "$3"',
                             "route-test", mode, click, db], text=True, capture_output=True, check=True)
    return result.stdout

def fields(row):
    return dict(f.split(":", 1) for f in row.split(",")[2:] if ":" in f)

class ControllerRouting(unittest.TestCase):
    def test_each_controller_keeps_its_own_click(self):
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher.name):
                rows = route(launcher, "none", "r1", DB).strip().splitlines()
                self.assertEqual(len(rows), 2)
                for row, guid, click in zip(rows, [GUID1, GUID2], ["b5", "b7"]):
                    self.assertEqual(row.split(",")[0], guid)
                    self.assertEqual(fields(row).get("a"), click)
                    self.assertNotIn("rightshoulder", fields(row))
                    self.assertEqual(fields(row)["dpup"], "h0.1")

    def test_keyboard_a_and_mouse_a_stay_per_controller(self):
        for launcher in LAUNCHERS:
            rows = route(launcher, "keyboard", "r1", DB).strip().splitlines()
            for row, a, r1 in zip(rows, ["b0", "b2"], ["b5", "b7"]):
                self.assertEqual(fields(row).get("rightshoulder"), a)
                self.assertEqual(fields(row).get("a"), r1)
            rows = route(launcher, "none", "a", DB).strip().splitlines()
            for row, a in zip(rows, ["b0", "b2"]):
                self.assertEqual(fields(row).get("a"), a)

    def test_sdl_virtual_controller_click_is_delivered(self):
        library = ctypes.util.find_library("SDL2-2.0")
        if not library:
            self.skipTest("host SDL2 unavailable; requires host SDL2, never a console dependency")
        sdl = ctypes.CDLL(library)
        if not hasattr(sdl, "SDL_JoystickAttachVirtual"):
            self.skipTest("host SDL2 predates virtual joysticks")
        C = ctypes
        class Guid(C.Structure):
            _fields_ = [("data", C.c_uint8 * 16)]
        for name, args, result in [
            ("SDL_JoystickOpen", [C.c_int], C.c_void_p),
            ("SDL_JoystickGetGUID", [C.c_void_p], Guid),
            ("SDL_JoystickGetGUIDString", [Guid, C.c_char_p, C.c_int], None),
            ("SDL_GameControllerOpen", [C.c_int], C.c_void_p),
            ("SDL_GameControllerClose", [C.c_void_p], None),
            ("SDL_JoystickClose", [C.c_void_p], None),
            ("SDL_JoystickSetVirtualButton", [C.c_void_p, C.c_int, C.c_uint8], C.c_int),
            ("SDL_GameControllerGetButton", [C.c_void_p, C.c_int], C.c_uint8),
        ]:
            fn = getattr(sdl, name); fn.argtypes = args; fn.restype = result
        self.assertEqual(sdl.SDL_Init(0x2200), 0)
        try:
            sdl.SDL_SetHint(b"SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", b"1")
            index = sdl.SDL_JoystickAttachVirtual(1, 4, 12, 1)
            self.assertGreaterEqual(index, 0)
            joystick = sdl.SDL_JoystickOpen(index)
            guid = C.create_string_buffer(33)
            sdl.SDL_JoystickGetGUIDString(sdl.SDL_JoystickGetGUID(joystick), guid, 33)
            database = DB.replace(GUID1, guid.value.decode())
            for launcher in LAUNCHERS:
                for row in route(launcher, "none", "r1", database).strip().splitlines():
                    self.assertTrue(row.endswith(","), "SDL needs a delimiter before appended CRC metadata")
                    self.assertGreaterEqual(sdl.SDL_GameControllerAddMapping(row.encode()), 0)
                controller = sdl.SDL_GameControllerOpen(index)
                self.assertTrue(controller)
                for pressed in (1, 0):
                    self.assertEqual(sdl.SDL_JoystickSetVirtualButton(joystick, 5, pressed), 0)
                    sdl.SDL_PumpEvents(); sdl.SDL_JoystickUpdate()
                    self.assertEqual(sdl.SDL_GameControllerGetButton(controller, 0), pressed)
                sdl.SDL_GameControllerClose(controller)
            sdl.SDL_JoystickClose(joystick)
        finally:
            sdl.SDL_Quit()

    def test_kernel_process_name_is_truncated(self):
        # Run the check in a child so the test runner's process name is intact.
        code = '''import ctypes, os
libc=ctypes.CDLL(None)
assert libc.prctl(15, b"ruffle-native.aarch64", 0, 0, 0)==0
print(open("/proc/self/comm").read().strip())
'''
        result = subprocess.run(["python3", "-c", code], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "ruffle-native.a")

    def test_darkosre_helper_receives_select_and_kernel_process_name(self):
        body = (CORE / "launch.sh").read_text()
        functions = body[body.index("start_click_helper() {"):body.index("cleanup_runtime() {")]
        for cfw, flag, hotkey, target in [
            ("dArkOSRE", "-Z", "back", "ruffle-native.a"),
            ("EmuELEC", "-1", "guide", "ruffle-native.aarch64"),
            ("NextUI", "-1", "guide", "ruffle-native.aarch64"),
        ]:
            with self.subTest(cfw=cfw), tempfile.TemporaryDirectory(prefix="ruffle-hotkey-") as temp:
                folder = Path(temp)
                helper = folder / "gptokeyb2"
                capture = folder / "received.txt"
                helper.write_text('#!/bin/bash\nprintf "%s\\n" "$HOTKEY" "$@" > "$CAPTURE"\n')
                helper.chmod(0o755)
                control = folder / "control.txt"
                control.write_text('get_controls() { :; }\n')
                script = ('source "$1"\nPROFILEDIR="$2"; LOGDIR="$3"; ROMROOT="$3"; EARLY="$3/early.log"\n'
                          'RUFFLE_PORTMASTER_CONTROL="$3/control.txt"\n'
                          'GPTOKEYB2="$3/gptokeyb2 $5"; CFW_NAME="$4"; RUFFLE_CFW_NAME="$4"\n'
                          'export HOTKEY=guide CAPTURE="$3/received.txt"\n'
                          'INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""\n'+functions+
                          '\nstart_click_helper ruffle-native.aarch64 "$2/dad-n-me.profile"\n'
                          'wait "$INPUT_PID"; INPUT_PID=""; stop_click_helper\n')
                subprocess.run(["bash", "-c", script, "hotkey-test", str(CORE / "lib/control_profiles.sh"),
                                str(CORE.parents[1] / "profiles"), temp, cfw, flag],
                               check=True, capture_output=True, text=True)
                received = capture.read_text().splitlines()
                self.assertEqual(received[:3], [hotkey, flag, target])

    def test_blue_rabbit_click_uses_native_a_on_darkos(self):
        body = (CORE / "launch.sh").read_text()
        functions = body[body.index("start_click_helper() {"):body.index("cleanup_runtime() {")]
        with tempfile.TemporaryDirectory(prefix="ruffle-blue-rabbit-") as temp:
            folder = Path(temp)
            helper = folder / "gptokeyb2"
            helper.write_text("#!/bin/bash\nexit 0\n")
            helper.chmod(0o755)
            (folder / "control.txt").write_text("get_controls() { :; }\n")
            script = ('source "$1"\nPROFILEDIR="$2"; LOGDIR="$3"; ROMROOT="$3"; EARLY="$3/early.log"\n'
                      'RUFFLE_PORTMASTER_CONTROL="$3/control.txt"; GPTOKEYB2="$3/gptokeyb2 -Z"\n'
                      'CFW_NAME=dArkOSRE; RUFFLE_CFW_NAME=dArkOSRE\n'
                      'sdl_controllerconfig="03000000,R36S,a:b0,b:b1,rightshoulder:b5,platform:Linux,"\n'
                      'INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""\n'+functions+
                      '\nstart_click_helper ruffle-native.aarch64 "$2/blue-rabbit-s-climate-chaos.profile"\n'
                      'printf "%s\\n%s\\n" "$RUFFLE_NATIVE_CLICK_BUTTON" "$RUFFLE_CLICK_BUTTON"\n'
                      'wait "$INPUT_PID"; INPUT_PID=""; stop_click_helper\n')
            result = subprocess.run(["bash", "-c", script, "click-test", str(CORE / "lib/control_profiles.sh"),
                                     str(CORE.parents[1] / "profiles"), temp], check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.splitlines()[-2:], ["a", "native-a"])
            self.assertNotIn("mouse_left", (folder / "input-helper.log").read_text())

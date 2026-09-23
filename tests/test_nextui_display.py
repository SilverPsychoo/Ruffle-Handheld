"""Host-only test of the experimental SDL display adapter."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef union {
 struct { uint32_t type,time,id; uint8_t event,p1,p2,p3; int32_t w,h; } window;
 uint8_t bytes[56]; uint64_t alignment;
} Event;
extern int SDL_PollEvent(Event*);
extern void probe_dimensions(int,int), probe_window(int), probe_id(uint32_t), probe_queue(void), probe_resize(void);
static void resize(int w,int h) {
 Event e; assert(SDL_PollEvent(&e)==1);
 assert(e.window.type==0x200 && e.window.event==5 && e.window.time==42);
 assert(e.window.w==w && e.window.h==h);
 assert(SDL_PollEvent(&e)==0); /* no infinite synthetic event loop */
}
int main(void) {
 Event e;
 assert(SDL_PollEvent(NULL)==1); /* peek does not remove controller input */
 assert(SDL_PollEvent(&e)==1 && e.window.type==0x650);
 if (!getenv("RUFFLE_NEXTUI_DISPLAY")) {
   assert(SDL_PollEvent(&e)==0); puts("disabled passthrough"); return 0;
 }
 assert(SDL_PollEvent(NULL)==0);
 resize(1024,768); /* frozen consumer starts at 640x480; surface is larger */
 probe_queue();
 assert(SDL_PollEvent(&e)==1 && e.window.type==0x650); /* input still arrives */
 assert(SDL_PollEvent(&e)==0);
 probe_resize();
 assert(SDL_PollEvent(&e)==1 && e.window.type==0x200 && e.window.w==640);
 resize(1024,768); /* correct a later logical resize too */
 probe_dimensions(0,0); assert(SDL_PollEvent(&e)==0);
 probe_dimensions(1280,720); resize(1280,720);
 probe_window(0); assert(SDL_PollEvent(&e)==0);
 probe_window(1); resize(1280,720);
 probe_id(8); resize(1280,720);
 probe_dimensions(640,480); resize(640,480);
 puts("resize lifecycle and input preservation passed");
}
'''

class NextUIDisplayTests(unittest.TestCase):
    def test_packaged_arm64_abi(self):
        library = ROOT / "port/rufflehandheld/rufflehandheld/runtime/libruffle_nextui_display.aarch64.so"
        data = library.read_bytes()
        self.assertEqual(data[:6], b"\x7fELF\x02\x01")  # ELF64 little endian
        self.assertEqual(int.from_bytes(data[16:18], "little"), 3)  # shared object
        self.assertEqual(int.from_bytes(data[18:20], "little"), 183)  # AArch64
        result = subprocess.run(["readelf", "-d", "-V", "-Ws", str(library)],
                                check=True, capture_output=True, text=True)
        self.assertEqual(set(re.findall(r"GLIBC_[0-9.]+", result.stdout)), {"GLIBC_2.17"})
        self.assertEqual(set(re.findall(r"Shared library: \[(.*?)\]", result.stdout)),
                         {"libc.so.6", "libdl.so.2"})
        self.assertIn("SDL_PollEvent", result.stdout)

    def test_native_and_multifile_only_load_on_nextui(self):
        # Real launchers and host dynamic loader. Only the ARM executables and
        # .so files in this temporary copy become host probes; shipped files
        # stay unchanged. No claim of GPU/ARM or physical controller coverage.
        from test_v0827 import APP_SOURCE, base_env, run
        with tempfile.TemporaryDirectory(prefix="ruffle_display_") as temp:
            work = Path(temp)
            romroot = work / "SD CARD" / "ROM collection"
            app = romroot / "ports/rufflehandheld"
            shutil.copytree(APP_SOURCE, app)
            library = app / "runtime/libruffle_nextui_display.aarch64.so"
            run("cc", "-shared", "-fPIC", "-O2", ROOT / "tools/ruffle_nextui_display.c", "-ldl", "-o", library)
            run("cc", "-shared", "-fPIC", ROOT / "tests/fixtures/sdl_display_probe.c", "-o", work / "libfake_sdl.so")
            empty = work / "existing.c"
            empty.write_text("int existing_preload(void) { return 1; }\n")
            inherited = work / "existing.so"
            run("cc", "-shared", "-fPIC", empty, "-o", inherited)
            shutil.copy2(inherited, app / "runtime/core/native_v020/libruffle_cursorfix.aarch64.so")
            driver = work / "native.c"
            driver.write_text(r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef union {
 struct { uint32_t type,time,id; uint8_t event,p1,p2,p3; int32_t w,h; } window;
 uint8_t bytes[56]; uint64_t alignment;
} Event;
extern int SDL_PollEvent(Event*);
int main(void) {
 FILE *log=fopen(getenv("TEST_DISPLAY_MARKER"),"w"); assert(log);
 fprintf(log,"PRELOAD=%s\n",getenv("LD_PRELOAD"));
 Event e; int input=0, resized=0, count=0;
 while(SDL_PollEvent(&e)) {
   assert(++count<10);
   if(e.window.type==0x650) input++;
   if(e.window.type==0x200) {
     assert(e.window.w==1024 && e.window.h==768); resized++;
   }
 }
 assert(input==1);
 fprintf(log,"input=%d resize=%d\n",input,resized); fclose(log);
 assert(resized==atoi(getenv("TEST_EXPECT_RESIZE")));
 return 0;
}
''')
            probe = work / "probe"
            run("cc", driver, "-L"+temp, "-lfake_sdl", "-Wl,-rpath,"+temp, "-o", probe)
            for rel in ("native_v020/ruffle-native.aarch64", "native_multifile/ruffle-native-multifile.aarch64"):
                shutil.copy2(probe, app / "runtime/core" / rel)
            flash = romroot / "flash"
            flash.mkdir()
            simple = flash / "Simple Game.swf"
            multi = flash / "Garfield.swf"
            for game in (simple, multi):
                game.write_bytes(b"FWS-test")
            sidecar = romroot / "flash_data/Garfield.files"
            sidecar.mkdir(parents=True)
            (sidecar / "asset.dat").write_bytes(b"asset")
            marker = work / "native.marker"
            cases = [("NextUI", "1", False, 1), ("NextUI", "0", False, 0),
                     ("NextUI", "1", True, 0), ("EmuELEC", "1", False, 0),
                     ("ROCKNIX", "1", False, 0), ("dArkOSRE", "1", False, 0)]
            for cfw, setting, missing, expected in cases:
                for game in (simple, multi):
                    with self.subTest(cfw=cfw, setting=setting, missing=missing, game=game.name):
                        disabled = library.with_suffix(".disabled")
                        if missing:
                            library.rename(disabled)
                        env = base_env(RUFFLE_CFW_NAME=cfw, CFW_NAME=cfw,
                                       RUFFLE_NEXTUI_DISPLAY=setting, LD_PRELOAD=str(inherited),
                                       TEST_DISPLAY_MARKER=str(marker), TEST_EXPECT_RESIZE=str(expected))
                        try:
                            run("bash", app / "runtime/es-launch.sh", "--rom-root", romroot, game,
                                env=env, cwd=work)
                        finally:
                            if missing:
                                disabled.rename(library)
                        body = marker.read_text()
                        self.assertIn("input=1 resize="+str(expected), body)
                        preload = body.splitlines()[0].removeprefix("PRELOAD=").split(":")
                        self.assertEqual(preload[-1], str(inherited))
                        self.assertIn("libruffle_cursorfix.aarch64.so", preload[-2])
                        self.assertEqual(any("libruffle_nextui_display" in part for part in preload), bool(expected))
                        self.assertFalse(any(" " in part for part in preload))
                        log = app / "logs" / (game.name.replace(" ", "_")+".log")
                        text = log.read_text()
                        if expected:
                            self.assertIn("[nextui-display] hook active", text)
                            self.assertIn("window=640x480 drawable=1024x768; resize event=1024x768", text)
                        elif cfw != "NextUI":
                            self.assertNotIn("[nextui-display]", text)
                        if game == multi:
                            self.assertIn("Backend: native-multifile", text)
                            self.assertIn("flash_data/Garfield.files", text)
            self.assertEqual(sorted(p.name for p in (app / "logs").iterdir()),
                             ["Garfield.swf.log", "Simple_Game.swf.log"])

    def test_opt_in_resize_events_and_passthrough(self):
        with tempfile.TemporaryDirectory(prefix="nextui-display-") as temp:
            work = Path(temp)
            shim = work / "display.so"
            driver = work / "driver.c"
            driver.write_text(DRIVER)
            def run(*args, **kwargs):
                return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30, **kwargs)
            run("cc", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra", "-Werror",
                str(ROOT / "tools/ruffle_nextui_display.c"), "-ldl", "-o", str(shim))
            run("cc", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                str(ROOT / "tests/fixtures/sdl_display_probe.c"), "-o", str(work / "libfake_sdl.so"))
            run("cc", str(driver), "-L"+temp, "-lfake_sdl", "-Wl,-rpath,"+temp, "-o", str(work / "probe"))
            env = os.environ.copy()
            env["LD_PRELOAD"] = str(shim)
            env.pop("RUFFLE_NEXTUI_DISPLAY", None)
            off = run(str(work / "probe"), env=env)
            self.assertEqual(off.stderr, "")
            env["RUFFLE_NEXTUI_DISPLAY"] = "1"
            on = run(str(work / "probe"), env=env)
            self.assertIn("window=640x480 drawable=1024x768; resize event=1024x768", on.stderr)
            self.assertEqual(on.stderr.count("resize event="), 6)
            self.assertIn("input preservation passed", on.stdout)

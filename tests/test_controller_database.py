"""Full PortMaster databases must not prevent execve of the helper or player."""
import ctypes.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tests.test_controller_routing import fields
from tests.test_v0827 import APP_SOURCE, base_env, make_executable, run

GUID = '19000000010000000100000001010000'
MAPPING = GUID + ',Actual Brick,a:b0,b:b1,x:b2,y:b3,rightshoulder:b5,start:b9,back:b8,dpup:h0.1,platform:Linux,'

# Runs as real child executables. SDL loads the environment-selected file on
# initialization; checking only the shell's file contents would miss a broken
# handoff to the consumer or loss of the connected controller's later DB row.
PROBE = r'''#!/usr/bin/env python3
import ctypes as C, ctypes.util, json, os, pathlib, sys, time
role = 'helper' if '-c' in sys.argv else 'native'
for key in ('SDL_GAMECONTROLLERCONFIG', 'RUFFLE_CONTROLLER_DB',
            'sdl_controllerconfig', 'controller_db', 'RUFFLE_ES_CONTROLLER_DB'):
    assert not os.environ.get(key), (key, 'full DB must stay out of child environment')
database = pathlib.Path(os.environ['SDL_GAMECONTROLLERCONFIG_FILE'])
body = database.read_text()
assert len(body) > 131072
assert 'Actual Brick' in body
assert 'Unused controller 1999' in body
class Guid(C.Structure):
    _fields_ = [('data', C.c_uint8 * 16)]
sdl = C.CDLL(ctypes.util.find_library('SDL2-2.0'))
sdl.SDL_JoystickGetGUIDFromString.argtypes = [C.c_char_p]
sdl.SDL_JoystickGetGUIDFromString.restype = Guid
sdl.SDL_GameControllerMappingForGUID.argtypes = [Guid]
sdl.SDL_GameControllerMappingForGUID.restype = C.c_void_p
sdl.SDL_free.argtypes = [C.c_void_p]
assert sdl.SDL_Init(0x2000) == 0
ptr = sdl.SDL_GameControllerMappingForGUID(sdl.SDL_JoystickGetGUIDFromString(os.environ['PROBE_GUID'].encode()))
assert ptr, 'SDL did not load the connected controller from the full file'
mapping = C.string_at(ptr).decode()
sdl.SDL_free(ptr)
sdl.SDL_Quit()
assert ',Actual Brick,' in mapping
capture = pathlib.Path(os.environ['CAPTURE_' + role.upper()])
capture.write_text(json.dumps({'mapping': mapping, 'database': str(database), 'size': len(body)}))
if role == 'native':
    deadline = time.monotonic() + 5
    helper = pathlib.Path(os.environ['CAPTURE_HELPER'])
    while not helper.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert helper.exists(), 'quit/mouse helper did not reach SDL initialization'
'''


class ControllerDatabase(unittest.TestCase):
    @unittest.skipUnless(ctypes.util.find_library('SDL2-2.0'), 'requires host SDL2')
    def test_large_file_and_exported_portmaster_databases_reach_both_consumers(self):
        for source in ('file', 'exported'):
          for multifile in (False, True):
            with self.subTest(source=source, multifile=multifile), tempfile.TemporaryDirectory(prefix='ruffle large DB ') as temp:
                root = Path(temp); roms = root / 'Roms'
                app = roms / 'ports/rufflehandheld'
                shutil.copytree(APP_SOURCE, app)
                pm = roms / 'ports/PortMaster'; pm.mkdir()
                database = pm / 'gamecontrollerdb.txt'
                rows = [f'{i:032x},Unused controller {i},a:b2,b:b1,x:b3,y:b0,back:b9,dpup:h0.1,rightshoulder:b7,start:b8,platform:Windows,\n'
                        for i in range(2000)]
                # Same GUID on two platforms, with the Linux device after all
                # preview rows: loading the entire DB and SDL filtering matter.
                database.write_text(''.join(rows) + GUID + ',Wrong platform,a:b3,platform:Windows,\n' + MAPPING + '\n')
                self.assertGreater(database.stat().st_size, 131072)
                get_controls = ('get_controls() { :; }\n' if source == 'file' else
                                'get_controls() { export sdl_controllerconfig="$(cat "$controlfolder/gamecontrollerdb.txt")"; }\n')
                (pm / 'control.txt').write_text(
                    'CFW_NAME=TrimUI\nDEVICE_NAME="TrimUI Brick"\nDEVICE_CPU=a133plus\nANALOG_STICKS=0\n'
                    'export SDL_GAMECONTROLLERCONFIG_FILE="$controlfolder/gamecontrollerdb.txt"\n'
                    'GPTOKEYB2="$controlfolder/gptokeyb2 -1"\n' + get_controls)
                make_executable(pm / 'gptokeyb2', PROBE)
                binary = app / ('runtime/core/native_multifile/ruffle-native-multifile.aarch64' if multifile else
                                'runtime/core/native_v020/ruffle-native.aarch64')
                make_executable(binary, PROBE)
                (app / 'runtime/core/native_v020/libruffle_cursorfix.aarch64.so').unlink()
                game = roms / ('flash/Generic Space.swf' if multifile else "flash/McDonald's Videogame.swf")
                game.parent.mkdir(); game.write_bytes(b'FWS-host-probe')
                if multifile:
                    (roms / 'flash_data/Generic Space.files').mkdir(parents=True)
                native = root / 'native.json'; helper = root / 'helper.json'
                env = base_env(RUFFLE_CFW_NAME='NextUI', RUFFLE_NEXTUI_DISPLAY='0', PROBE_GUID=GUID,
                               CAPTURE_NATIVE=str(native), CAPTURE_HELPER=str(helper))
                log = app / 'logs' / (game.name.replace(' ', '_').replace("'", '_') + '.log')
                try:
                    result = run('bash', app / 'runtime/es-launch.sh', '--rom-root', roms, game, env=env)
                except AssertionError as error:
                    raise AssertionError(str(error) + '\n' + (log.read_text() if log.exists() else 'no game log')) from error
                received = json.loads(native.read_text())
                original = json.loads(helper.read_text())
                self.assertEqual(fields(original['mapping'])['a'], 'b0')
                self.assertEqual(fields(received['mapping'])['a'], 'b5' if multifile else 'b0')
                self.assertEqual(fields(received['mapping'])['rightshoulder'], 'b0' if multifile else 'b5')
                self.assertFalse(Path(received['database']).exists(), 'native DB should be removed after exit')
                self.assertFalse(Path(original['database']).exists(), 'helper DB should be removed after exit')
                text = log.read_text() + result.stdout
                self.assertIn('Controller database transport: file only', text)
                self.assertNotIn('Argument list too long', text)
                self.assertNotIn('Broken pipe', text)

"""Launch through the installed ES command and check both input consumers."""
import os
from pathlib import Path
import shlex
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

from tests.test_controller_routing import fields
from tests.test_frontend_arguments import es_escape
from tests.test_v0827 import APP_SOURCE, base_env, make_executable, run

GUID = '19000000010000000100000001010000'
MAPPING = GUID + ',One stick,a:b3,b:b4,rightshoulder:b8,leftx:a0,lefty:a1,dpup:h0.1,platform:Linux,'


class KnulliControls(unittest.TestCase):
    def test_frontend_mapping_reaches_native_and_helper(self):
        for multifile in (False, True):
          with self.subTest(multifile=multifile), tempfile.TemporaryDirectory(prefix='ruffle knulli input ') as temp:
            root = Path(temp)
            roms = root / 'roms'; app = roms / 'ports/rufflehandheld'
            shutil.copytree(APP_SOURCE, app)
            config = root / 'es_systems.cfg'
            env = base_env(RUFFLE_ES_CONFIG=str(config), RUFFLE_CFW_NAME='Knulli', CFW_NAME='Knulli')
            run('bash', app / 'core-install.sh', roms, app, 'Knulli', env=env)
            flash = ET.parse(config).getroot().find('system')
            self.assertIsNotNone(flash.find('emulators'))
            self.assertEqual(len(flash.find('emulators')), 0)
            command = flash.findtext('command')
            self.assertIn('%CONTROLLERSCONFIG%', command)
            # The firmware API is isolated here; a separate validation can use
            # upstream configgen. This checks all launch boundaries unchanged.
            package = root / 'configgen'; package.mkdir()
            (package / '__init__.py').write_text('')
            (package / 'controller.py').write_text(
                'class Controller:\n'
                '    @staticmethod\n'
                '    def load_for_players(count, args):\n'
                '        assert count == 8 and args.p1index == 0\n'
                f'        assert args.p1guid == {GUID!r}\n'
                '        assert args.p1name == "One stick" and args.p1nbaxes == 2\n'
                '        return {1: args}\n'
                f'def generate_sdl_game_controller_config(controllers):\n    return {MAPPING!r}\n')
            pm = roms / 'ports/PortMaster'; pm.mkdir()
            make_executable(pm / 'gptokeyb2', '#!/bin/bash\nprintf "%s" "$SDL_GAMECONTROLLERCONFIG" > "$HELPER_CAPTURE"\n')
            (pm / 'control.txt').write_text(
                'get_controls() { sdl_controllerconfig="00000000000000000000000000000000,Stale,a:b1,rightshoulder:b5,"; }\n'
                'GPTOKEYB2="$controlfolder/gptokeyb2"\n')
            game = roms / 'flash/Skywire test.swf'; game.write_bytes(b'FWS-probe')
            (app / 'profiles/custom').mkdir(exist_ok=True)
            (app / 'profiles/custom/skywire-test.profile').write_text('mouse_stick=left\n')
            if multifile:
                (roms / 'flash_data/Skywire test.files').mkdir(parents=True)
            binary = app / ('runtime/core/native_multifile/ruffle-native-multifile.aarch64' if multifile else 'runtime/core/native_v020/ruffle-native.aarch64')
            make_executable(binary, '#!/bin/bash\nprintf "%s" "$SDL_GAMECONTROLLERCONFIG" > "$NATIVE_CAPTURE"\n')
            (app / 'runtime/core/native_v020/libruffle_cursorfix.aarch64.so').unlink()
            native_capture = root / 'native.txt'; helper_capture = root / 'helper.txt'
            env.update(PYTHONPATH=str(root), NATIVE_CAPTURE=str(native_capture), HELPER_CAPTURE=str(helper_capture))
            args = f'-p1index 0 -p1guid {GUID} -p1name "One stick" -p1nbaxes 2 -p1nbbuttons 15 -p1nbhats 1'
            command = command.replace('%ROM%', es_escape(game)).replace('%CONTROLLERSCONFIG%', args)
            run('/bin/sh', '-c', command, env=env)
            mapping = fields(native_capture.read_text())
            self.assertEqual(mapping['rightx'], 'a0')
            self.assertEqual(mapping['righty'], 'a1')
            self.assertNotIn('leftx', mapping)
            self.assertEqual(mapping['dpup'], 'h0.1')
            self.assertEqual(mapping['a'], 'b8')  # profile R1 click
            self.assertEqual(mapping['rightshoulder'], 'b3')  # profile A key
            self.assertEqual(fields(helper_capture.read_text()), fields(MAPPING))
            log = (app / 'logs/Skywire_test.swf.log').read_text()
            self.assertIn('Knulli input: loaded 1 controller(s)', log)
            self.assertIn('Controller mapping source: EmulationStation/configgen', log)

    def test_restart_prefers_current_knulli_tool(self):
        source = (APP_SOURCE / 'setup.sh').read_text()
        body = source[source.index('restart_batocera_es() {'):source.index('\necho "[2/3]')]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            marker = root / 'restart'
            for name in ('knulli-es-swissknife', 'batocera-es-swissknife'):
                make_executable(root / name, '#!/bin/bash\nprintf "%s %s" "${0##*/}" "$1" > "$MARKER"\n')
            env = os.environ.copy(); env.update(PATH=str(root)+':'+env['PATH'], MARKER=str(marker))
            run('bash', '-c', 'frontend_pid() { if [ -f "$MARKER" ]; then echo 2; else echo 1; fi; }\n'+body+'\nrestart_batocera_es', env=env)
            self.assertEqual(marker.read_text(), 'knulli-es-swissknife --restart')
            marker.unlink(); (root / 'knulli-es-swissknife').unlink()
            run('bash', '-c', 'frontend_pid() { if [ -f "$MARKER" ]; then echo 2; else echo 1; fi; }\n'+body+'\nrestart_batocera_es', env=env)
            self.assertEqual(marker.read_text(), 'batocera-es-swissknife --restart')

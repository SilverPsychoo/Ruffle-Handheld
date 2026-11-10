"""Quit failures stay in the game log; older helpers keep their arguments."""
from pathlib import Path
import shutil
import tempfile
import unittest

from tests.test_v0827 import APP_SOURCE, base_env, make_executable, run


class QuitDiagnostics(unittest.TestCase):
    def probe(self, helper_body, cfw="dArkOSRE", pm_hotkey="guide", initial_hotkey="leftstick"):
        temp = tempfile.TemporaryDirectory(prefix='ruffle quit ')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name); roms = root / 'roms'
        app = roms / 'ports/rufflehandheld'; shutil.copytree(APP_SOURCE, app)
        pm = roms / 'ports/PortMaster'; pm.mkdir()
        (pm / 'control.txt').write_text(
            f'CFW_NAME={cfw}\n' + (f'HOTKEY={pm_hotkey}\n' if pm_hotkey else '') +
            'get_controls() { sdl_controllerconfig="19000000,Test,a:b0,rightshoulder:b5,start:b9,back:b8,guide:b10,"; }\n'
            'GPTOKEYB2="$controlfolder/gptokeyb2 -Z"\n')
        make_executable(pm / 'gptokeyb2', helper_body)
        game = roms / 'flash/Exit Test.swf'; game.parent.mkdir(); game.write_bytes(b'FWS-probe')
        make_executable(app / 'runtime/core/native_v020/ruffle-native.aarch64',
            '#!/bin/bash\n'
            'grep -q "\\[quit\\] Helper command=" "$RUFFLE_GAME_LOG" || exit 41\n'
            'python3 -c \'import ctypes,time; ctypes.CDLL(None).prctl(15,b"ruffle-native.aarch64",0,0,0); time.sleep(0.5)\'\n')
        (app / 'runtime/core/native_v020/libruffle_cursorfix.aarch64.so').unlink()
        capture = root / 'helper.args'
        env = base_env(RUFFLE_CFW_NAME=cfw, CAPTURE=str(capture))
        if initial_hotkey:
            env['HOTKEY'] = initial_hotkey
        else:
            env.pop('HOTKEY', None)
        run('bash', app / 'runtime/es-launch.sh', '--rom-root', roms, game, env=env)
        return (app / 'logs/Exit_Test.swf.log').read_text(), capture

    def test_helper_failure_is_visible_and_logged_with_status(self):
        log, _ = self.probe('#!/bin/bash\necho "SDL_Init failed: test error" >&2\nexit 23\n')
        self.assertIn('SDL_Init failed: test error', log)
        self.assertIn('[quit] Helper exit status=23', log)
        self.assertIn('Helper had already exited before cleanup', log)
        self.assertIn('HOTKEY before PortMaster=leftstick, after PortMaster=guide, effective=back', log)
        self.assertIn('start:b9 back:b8 guide:b10', log)
        self.assertIn('Target requested=ruffle-native.aarch64 effective=ruffle-native.a', log)

    def test_old_helper_keeps_quit_mode_and_no_unsupported_debug_flags(self):
        log, capture = self.probe('#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE"\nsleep 20\n')
        args = capture.read_text().splitlines()
        self.assertEqual(args[:2], ['-Z', 'ruffle-native.a'])
        self.assertNotIn('-D', args)
        self.assertIn('Button-event tracing: unavailable', log)
        self.assertIn('Native process observed:', log)
        self.assertIn('comm=ruffle-native.a', log)

    def test_supported_helper_gets_button_trace_and_preserves_output(self):
        log, capture = self.probe(
            '#!/bin/bash\n# comma separated debug output: states, gamepad\n'
            'printf "%s\\n" "$@" > "$CAPTURE"\n'
            'echo "back -> pressed"\necho "start -> pressed"\nexit 0\n')
        args = capture.read_text().splitlines()
        self.assertEqual(args[-2:], ['-D', 'gamepad'])
        self.assertIn('back -> pressed', log)
        self.assertIn('start -> pressed', log)
        self.assertIn('Helper exit status=0', log)

    def test_reported_darkos_name_with_unset_hotkey_uses_select_and_matchable_target(self):
        log, capture = self.probe(
            '#!/bin/bash\nprintf "%s\n" "$HOTKEY" "$@" > "$CAPTURE"\nexit 0\n',
            cfw='dArkOS', pm_hotkey=None, initial_hotkey=None)
        self.assertEqual(capture.read_text().splitlines()[:3], ['back', '-Z', 'ruffle-native.a'])
        self.assertIn('after PortMaster=unset, effective=back', log)
        self.assertIn('Generated native gamepad map:', log)
        self.assertIn('"east": 90', log)
        self.assertIn('Effective SDL controller bindings', log)

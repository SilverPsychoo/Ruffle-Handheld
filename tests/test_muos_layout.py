"""Run the installer from muOS's real split launcher/application layout."""
from pathlib import Path
import shutil
import tempfile
import unittest

from tests.test_v0827 import APP_SOURCE, PORT, base_env, make_executable, run


class MuosLayout(unittest.TestCase):
    def test_installer_and_game_launch_from_split_folders(self):
        for menu in ('roms/PORTS', 'ROMS/Ports', 'roms/Ports'):
          with self.subTest(menu=menu), tempfile.TemporaryDirectory(prefix='ruffle muos split ') as temp:
            root = Path(temp) / 'SD card'
            app = root / 'ports/rufflehandheld'
            shutil.copytree(APP_SOURCE, app)
            ports_menu = root / menu; ports_menu.mkdir(parents=True)
            installer = ports_menu / 'Ruffle Handheld.sh'
            shutil.copyfile(PORT / 'Ruffle Handheld.sh', installer)
            env = base_env(CFW_NAME='muOS', RUFFLE_CFW_NAME='muOS', HOME=temp)
            # Exercise the user's entrypoint, not setup.sh directly.
            run('bash', installer, env=env)
            self.assertTrue((root / 'flash').is_dir())
            self.assertFalse((ports_menu / 'rufflehandheld').exists())
            game = root / 'flash/Skywire.swf'; game.write_bytes(b'FWS-probe')
            run('bash', installer, env=env)
            games = list(ports_menu.glob('Flash - *.sh'))
            self.assertEqual(len(games), 1)
            self.assertFalse(list((root / 'ports').glob('Flash - *.sh')))
            marker = Path(temp) / 'game.path'
            make_executable(app / 'runtime/core/native_v020/ruffle-native.aarch64',
                            '#!/bin/bash\nreadlink -f ruffle_data/movie.swf > "$MARKER"\n')
            (app / 'runtime/core/native_v020/libruffle_cursorfix.aarch64.so').unlink()
            env['MARKER'] = str(marker)
            run('bash', games[0], env=env)
            self.assertEqual(marker.read_text().strip(), str(game))
            self.assertTrue((app / 'logs/Skywire.swf.log').is_file())

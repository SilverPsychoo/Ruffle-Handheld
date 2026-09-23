"""Exercise the installed XML command, including ES token substitution and sh.

Calling es-launch.sh directly bypasses the quoting bug reported on R36S V20.
The native process below is a host probe, never a claimed ARM execution.
"""
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

from tests.test_v0827 import APP_SOURCE, base_env, make_executable, run


def es_escape(path):
    # ES getEscapedPath uses backslash escapes on Unix (including spaces and
    # parentheses visible verbatim in the four supplied v0.8.28 logs).
    special = " \\\"'`$&()[]{};<>?!*#~"
    return "".join("\\" + char if char in special else char for char in str(path))


class FrontendArguments(unittest.TestCase):
    def test_generated_commands_through_shell(self):
        for cfw in ("ArkOS", "dArkOS", "Knulli", "ROCKNIX", "EmuELEC"):
            with self.subTest(cfw=cfw), tempfile.TemporaryDirectory(prefix="ruffle ES ") as temp:
                root = Path(temp)
                roms = root / "ROM collection"
                app = roms / "ports/rufflehandheld"
                shutil.copytree(APP_SOURCE, app)
                config = root / "es_systems.cfg"
                config.write_text('<systemList><system><name>other</name></system>\n</systemList>\n')
                env = base_env(RUFFLE_ES_CONFIG=str(config), RUFFLE_ES_LEGACY_CONFIG=str(config))
                # Clean install followed by an update must regenerate a single
                # correct Flash command, not keep an old broken registration.
                run("bash", app / "core-install.sh", roms, app, cfw, env=env)
                first = ET.parse(config).getroot().findall("system")[-1].findtext("command")
                if "%ROM%" in first:
                    # Recreate the shipped v3.3 registration before updating.
                    config.write_text(config.read_text().replace(
                        "%ROM%</command>", "&quot;%ROM%&quot;</command>"))
                run("bash", app / "core-install.sh", roms, app, cfw, env=env)
                systems = ET.parse(config).getroot().findall("system")
                flash = [s for s in systems if s.findtext("name") == "flash"]
                self.assertEqual(len(flash), 1)
                command = flash[0].findtext("command")
                self.assertEqual(first, command)
                marker = root / "received.path"
                make_executable(app / "runtime/core/native_v020/ruffle-native.aarch64",
                    '#!/bin/bash\nreadlink -f ruffle_data/movie.swf > "$TEST_NATIVE_MARKER"\n')
                (app / "runtime/core/native_v020/libruffle_cursorfix.aarch64.so").unlink()
                env.update(TEST_NATIVE_MARKER=str(marker), RUFFLE_CFW_NAME=cfw)
                names = ["Meat Boy (Original).swf", "Cereus Peashy.swf", "Newgrounds Rumble.swf",
                         "The Binding of Isaac (1).swf", "Simple.swf"]
                if "%ROM_RAW%" not in command:
                    names += ["McDonald's & Friends.swf", "Literal $HOME `false`;test.swf"]
                for name in names:
                    with self.subTest(game=name):
                        game = roms / "flash" / name
                        game.write_bytes(b"FWS-host-probe")
                        shell_command = command.replace("%ROM_RAW%", str(game)).replace("%ROM%", es_escape(game))
                        run("/bin/sh", "-c", shell_command, env=env, cwd=root)
                        self.assertEqual(marker.read_text().strip(), str(game))
                        marker.unlink()

    def test_breakingthebank_uses_mouse_profile(self):
        result = run("bash", "-c", 'source "$1"; rh_resolve_profile "$2" breakingthebank',
                     "profile-test", APP_SOURCE / "runtime/core/lib/control_profiles.sh", APP_SOURCE / "profiles")
        self.assertEqual(Path(result.stdout.strip()).name, "henry-stickmin-breaking-the-bank.profile")

    def test_blue_rabbit_profile_uses_a_only_for_mouse_click(self):
        for name in ("Blue Rabbit's Climate Chaos", "Blue Rabbit: Climate Chaos"):
            with self.subTest(name=name):
                result = run("bash", "-c", 'source "$1"; rh_resolve_profile "$2" "$3"',
                             "profile-test", APP_SOURCE / "runtime/core/lib/control_profiles.sh",
                             APP_SOURCE / "profiles", name)
                profile = Path(result.stdout.strip())
                self.assertEqual(profile.name, "blue-rabbit-s-climate-chaos.profile")
                self.assertIn("mouse_click=a", profile.read_text())
                self.assertIn("south=none", profile.read_text())

    def test_tuper_tario_controls_follow_published_keys(self):
        with tempfile.TemporaryDirectory(prefix="ruffle-tuper-") as temp:
            output = Path(temp) / "config.ron"
            result = run("bash", "-c",
                         'source "$1"; p="$(rh_resolve_profile "$2" "Tuper-Tario-Tros")"; '
                         'rh_write_config_ron "$p" "$2/default.profile" "$3"',
                         "profile-test", APP_SOURCE / "runtime/core/lib/control_profiles.sh",
                         APP_SOURCE / "profiles", output)
            self.assertEqual(result.returncode, 0)
            mapping = output.read_text()
            self.assertIn('"right-trigger": 88', mapping)  # A: X (jump)
            self.assertIn('"east": 32', mapping)  # B: Space (change mode)
            self.assertIn('"west": 67', mapping)  # X: C (speed up)

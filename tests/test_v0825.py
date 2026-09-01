from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "port" / "rufflehandheld" / "rufflehandheld"


def find_bash() -> str:
    candidates = [
        shutil.which("bash"),
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise unittest.SkipTest("Bash is required for installer integration tests")


def shell_path(path: Path) -> str:
    resolved = path.resolve()
    if os.name == "nt":
        drive = resolved.drive.rstrip(":").lower()
        tail = resolved.as_posix().split(":", 1)[1]
        return f"/{drive}{tail}"
    return resolved.as_posix()


class InstallerFixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ruffle handheld v0825 ")
        self.root = Path(self.temp.name)
        self.romroot = self.root / "roms"
        self.app = self.romroot / "ports" / "rufflehandheld"
        self.app.parent.mkdir(parents=True)
        shutil.copytree(APP_SOURCE, self.app)
        self.state = self.root / "state"
        self.state.mkdir()

    def close(self) -> None:
        self.temp.cleanup()

    def run_core(self, cfw: str, extra_env: dict[str, Path | str]) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "RUFFLE_INSTALL_STATE_DIR": shell_path(self.state),
                "RUFFLE_THEME_ROOT": shell_path(self.root / "no-theme"),
                "HOME": shell_path(self.root / "home"),
            }
        )
        for key, value in extra_env.items():
            env[key] = shell_path(value) if isinstance(value, Path) else value
        return subprocess.run(
            [
                find_bash(),
                shell_path(self.app / "core-install.sh"),
                shell_path(self.romroot),
                shell_path(self.app),
                cfw,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            timeout=90,
            check=False,
        )


class V0825InstallerTests(unittest.TestCase):
    def assert_installer_reached_platform_boundary(self, result: subprocess.CompletedProcess[str]) -> None:
        # NTFS does not expose the Linux executable bit for extensionless ARM64
        # payloads to Git Bash. On Windows, exit 26 after the final layout step
        # is therefore the expected host boundary; Linux must complete fully.
        expected = 26 if os.name == "nt" else 0
        self.assertEqual(result.returncode, expected, result.stdout)
        if os.name == "nt":
            self.assertIn("[5/5] Final layout checks", result.stdout)

    def test_amberelec_creates_owned_overlay_and_is_idempotent(self) -> None:
        fixture = InstallerFixture()
        self.addCleanup(fixture.close)
        overlay = fixture.root / "storage" / ".emulationstation" / "es_systems_rufflehandheld.cfg"
        amber_config_dir = fixture.root / "storage" / ".config" / "emulationstation"

        env = {
            "RUFFLE_AMBERELEC_ES_CONFIG": overlay,
            "RUFFLE_AMBERELEC_USER_DIR": overlay.parent,
            "RUFFLE_AMBERELEC_CONFIG_DIR": amber_config_dir,
        }
        first = fixture.run_core("AmberELEC", env)
        self.assert_installer_reached_platform_boundary(first)
        self.assertTrue(overlay.is_file(), first.stdout)
        xml = overlay.read_text(encoding="utf-8")
        self.assertEqual(xml.count("<name>flash</name>"), 1)
        self.assertIn("%ROM_RAW%", xml)
        self.assertIn("runtime/es-launch.sh", xml)
        self.assertIn("amberelec-overlay-verified", first.stdout)

        second = fixture.run_core("AmberELEC", env)
        self.assert_installer_reached_platform_boundary(second)
        xml = overlay.read_text(encoding="utf-8")
        self.assertEqual(xml.count("<name>flash</name>"), 1)

    def test_darkos_prefers_system_config_and_removes_only_owned_stale_block(self) -> None:
        fixture = InstallerFixture()
        self.addCleanup(fixture.close)
        system_dir = fixture.root / "etc" / "emulationstation"
        user_dir = fixture.root / "home" / "ark" / ".emulationstation"
        system_dir.mkdir(parents=True)
        user_dir.mkdir(parents=True)
        active = system_dir / "es_systems.cfg"
        active.write_text(
            "<?xml version=\"1.0\"?>\n<systemList>\n"
            "  <system><name>ports</name><path>/roms/ports</path></system>\n"
            "</systemList>\n",
            encoding="utf-8",
        )
        stale = user_dir / "es_systems_flash.cfg"
        stale.write_text(
            "<?xml version=\"1.0\"?>\n<systemList>\n"
            "  <system><name>flash</name><command>/bin/bash /old/rufflehandheld/runtime/es-launch.sh %ROM%</command></system>\n"
            "  <system><name>pico8</name><path>/roms/pico8</path></system>\n"
            "</systemList>\n",
            encoding="utf-8",
        )
        env = {
            "RUFFLE_ARKOS_SYSTEM_CONFIG": active,
            "RUFFLE_ARKOS_USER_CONFIG": user_dir / "es_systems.cfg",
            "RUFFLE_ARKOS_SYSTEM_DIR": system_dir,
            "RUFFLE_ARKOS_USER_DIR": user_dir,
        }

        result = fixture.run_core("dArkOSRE", env)
        self.assert_installer_reached_platform_boundary(result)
        active_xml = active.read_text(encoding="utf-8")
        stale_xml = stale.read_text(encoding="utf-8")
        self.assertIn("<name>ports</name>", active_xml)
        self.assertEqual(active_xml.count("<name>flash</name>"), 1)
        self.assertNotIn("<name>flash</name>", stale_xml)
        self.assertIn("<name>pico8</name>", stale_xml)
        self.assertIn("stale Ruffle Flash block removed", result.stdout)

    def test_ports_arguments_are_rejected_with_actionable_log(self) -> None:
        fixture = InstallerFixture()
        self.addCleanup(fixture.close)
        result = subprocess.run(
            [
                find_bash(),
                shell_path(fixture.app / "runtime" / "es-launch.sh"),
                "-Pports",
                "--core=",
                "--emulator=",
                "--controllers= -p1index 0",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 2, result.stdout)
        log = (fixture.app / "logs" / "launch-error.log").read_text(encoding="utf-8")
        self.assertIn("Ports/runemu arguments", log)
        self.assertIn("LAST-INSTALL.log", log)
        self.assertIn("no existing SWF received", log)

    def test_portmaster_kill_mode_is_not_overridden(self) -> None:
        launch = (APP_SOURCE / "runtime" / "core" / "launch.sh").read_text(encoding="utf-8")
        self.assertIn("Use its command exactly as exported", launch)
        self.assertIsNone(re.search(r"GPTOKEYB2[^\n]*\s-1(?:\s|\")", launch))


if __name__ == "__main__":
    unittest.main()

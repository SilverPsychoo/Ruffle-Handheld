from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
RELEASES = ROOT / "releases"
OFFLINE = RELEASES / f"Ruffle-Handheld-v{VERSION}-OFFLINE.zip"
SOURCE = RELEASES / f"Ruffle-Handheld-v{VERSION}-SOURCE.zip"


class ReleaseBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "build_release.py")],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(result.stdout)

    def test_offline_package_has_standard_port_layout(self) -> None:
        with ZipFile(OFFLINE) as archive:
            names = archive.namelist()
            self.assertIn("Ruffle Handheld.sh", names)
            self.assertIn("rufflehandheld/setup.sh", names)
            self.assertIn("rufflehandheld/core-install.sh", names)
            self.assertIn("rufflehandheld/runtime/es-launch.sh", names)
            self.assertFalse(any(name.startswith("releases/") for name in names))
            self.assertFalse(any("LAST-INSTALL.log" in name for name in names))

            for name in (
                "Ruffle Handheld.sh",
                "rufflehandheld/setup.sh",
                "rufflehandheld/runtime/es-launch.sh",
                "rufflehandheld/runtime/core/native_v020/ruffle-native.aarch64",
                "rufflehandheld/runtime/core/native_adaptive/ruffle-native-adaptive.aarch64",
            ):
                mode = archive.getinfo(name).external_attr >> 16
                self.assertNotEqual(mode & 0o111, 0, name)

    def test_source_package_is_versioned_and_complete(self) -> None:
        prefix = f"Ruffle-Handheld-v{VERSION}-SOURCE/"
        with ZipFile(SOURCE) as archive:
            names = archive.namelist()
            self.assertIn(prefix + "VERSION", names)
            self.assertIn(prefix + "CHANGELOG.md", names)
            self.assertIn(prefix + "tests/test_v0825.py", names)
            self.assertIn(prefix + "tests/test_v0826.py", names)
            self.assertIn(prefix + "engine/patches/ruffle4consoles-v0.8.26.patch", names)
            self.assertIn(prefix + "port/rufflehandheld/rufflehandheld/core-install.sh", names)
            self.assertFalse(any("/.git/" in name or name.endswith("/.git") for name in names))
            self.assertFalse(any("/releases/" in name for name in names))

    def test_release_scripts_report_the_new_version(self) -> None:
        with ZipFile(OFFLINE) as archive:
            setup = archive.read("rufflehandheld/setup.sh").decode("utf-8")
            core = archive.read("rufflehandheld/core-install.sh").decode("utf-8")
            es_launch = archive.read("rufflehandheld/runtime/es-launch.sh").decode("utf-8")
        self.assertIn(f'VERSION="{VERSION}"', setup)
        self.assertIn(f'"{VERSION}" > "$APP_DIR/installed-version"', core)
        self.assertIn(f"per-game log v{VERSION}", es_launch)


if __name__ == "__main__":
    unittest.main()

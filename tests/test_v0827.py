from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / "port" / "rufflehandheld"
APP_SOURCE = PORT / "rufflehandheld"

FROZEN = {
    "runtime/core/native_v020/ruffle-native.aarch64": "aa080b95afc09825dfa455094bc54c5a5171a6b3090ab7c2fae898cb0905e320",
    "runtime/core/native_multifile/ruffle-native-multifile.aarch64": "dfbdcbf83883f268eb9a1210a72c5997391ec82b508ce0c3d7f4373ea3005ab5",
    "runtime/core/native_v020/libruffle_cursorfix.aarch64.so": "269a60726e78f5a90405c987d296efe762793cd9a5b1a91917f5b3b10860edeb",
    "runtime/core/lib/performance.sh": "baa845c798ad834dc89c9c9c285b09479f0ae8e9cbbb2d67bb1d8db440861eba",
}


def run(*args: str | Path, env: dict[str, str] | None = None, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(arg) for arg in args],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=40,
        check=False,
    )
    if result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {' '.join(map(str, args))}\n{result.stdout}")
    return result


def make_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8", newline="\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def base_env(**updates: str) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "RUFFLE_ARCH": "aarch64",
            "RUFFLE_SKIP_RESTART": "1",
            "RUFFLE_SDL_AUDIODRIVER": "dummy",
        }
    )
    env.update(updates)
    return env


class ReleaseTests(unittest.TestCase):
    def test_frozen_core_and_profiles(self) -> None:
        for relative, expected in FROZEN.items():
            actual = hashlib.sha256((APP_SOURCE / relative).read_bytes()).hexdigest()
            self.assertEqual(actual, expected, relative)
        self.assertFalse((APP_SOURCE / "runtime/core/native_adaptive").exists())
        for profile in (APP_SOURCE / "profiles").glob("*.profile"):
            body = profile.read_text(encoding="utf-8")
            self.assertNotIn("engine=adaptive", body)
            self.assertNotIn("native_a_mode=", body)
        resolved = run(
            "bash",
            "-c",
            'source "$1"; rh_resolve_profile "$2" "161792_breaking-the-bank"',
            "ruffle-profile-test",
            APP_SOURCE / "runtime/core/lib/control_profiles.sh",
            APP_SOURCE / "profiles",
        ).stdout.strip()
        self.assertEqual(Path(resolved).name, "henry-stickmin-breaking-the-bank.profile")

    def test_nextui_pak_environment_reaches_native(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ruffle_nextui_") as temp:
            root = Path(temp) / "mnt" / "SD CARD"
            ports_rom = root / "Roms" / "2) Ports (PORTS)"
            app = ports_rom / "rufflehandheld"
            pak = root / "Emus" / "tg5040" / "PORTS.pak"
            shutil.copytree(APP_SOURCE, app)
            # This test executes a host Native stub; use a host copy of the
            # display hook too. The packaged ARM64 artifact is checked separately.
            run("cc", "-shared", "-fPIC", "-O2", ROOT / "tools/ruffle_nextui_display.c",
                "-ldl", "-o", app / "runtime/libruffle_nextui_display.aarch64.so")
            ports_rom.mkdir(parents=True, exist_ok=True)
            launcher = ports_rom / "Ruffle Handheld.sh"
            shutil.copy2(PORT / "Ruffle Handheld.sh", launcher)
            launcher.chmod(0o755)
            (pak / "bin").mkdir(parents=True)
            (pak / "PortMaster").mkdir()
            (pak / "lib").mkdir()
            (pak / "bin" / "bash").symlink_to(shutil.which("bash"))

            native_marker = Path(temp) / "native.marker"
            helper_args = Path(temp) / "gpt.args"
            helper_cfg = Path(temp) / "gpt.cfg"
            fake_gpt = Path(temp) / "gptokeyb2"
            make_executable(
                fake_gpt,
                "#!/bin/bash\nprintf '%s\\n' \"$@\" > \"$TEST_GPT_ARGS\"\n"
                "while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -c ]; then cp \"$2\" \"$TEST_GPT_CFG\"; break; fi; shift; done\n",
            )
            control = pak / "PortMaster" / "control.txt"
            control.write_text(
                "#!/bin/bash\n"
                "directory='mnt/SDCARD/.ports_temp'\n"
                "CFW_NAME=NextUI\nDEVICE_NAME='TrimUI Brick'\nDEVICE_CPU=A133P\nANALOG_STICKS=0\n"
                f"GPTOKEYB2='{fake_gpt} -1'\n"
                "get_controls() { sdl_controllerconfig='03000000,test,a:b0,b:b1,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2'; }\n"
                "pm_platform_helper() { :; }\npm_finish() { :; }\n",
                encoding="utf-8",
            )

            launcher_text = launcher.read_text(encoding="utf-8")
            gamedir_line = next(line for line in launcher_text.splitlines() if re.match(r"^GAMEDIR=", line))
            check = run(
                "bash",
                "-c",
                f"directory='mnt/SDCARD/.ports_temp'; PORTDIR='/{root.name}/.ports_temp/ports'; {gamedir_line}; test -n \"$GAMEDIR\"",
            )
            self.assertEqual(check.returncode, 0)

            env = base_env(
                SDCARD_PATH=str(root),
                PLATFORM="tg5040",
                PAK_DIR=str(pak),
                TEST_GPT_ARGS=str(helper_args),
                TEST_GPT_CFG=str(helper_cfg),
            )
            run("bash", launcher, env=env)
            flash_pak = root / "Emus" / "tg5040" / "FLASH.pak"
            self.assertTrue((flash_pak / "launch.sh").is_file())
            self.assertEqual((flash_pak / "ruffle-app.path").read_text().strip(), str(app))

            native = app / "runtime/core/native_v020/ruffle-native.aarch64"
            make_executable(
                native,
                "#!/bin/bash\nprintf 'native reached\\nSDL=%s\\nMAP=%s\\nMAPFILE=%s\\nEMU=%s\\n' \"${SDL_VIDEODRIVER:-auto}\" \"${SDL_GAMECONTROLLERCONFIG:-missing}\" \"${SDL_GAMECONTROLLERCONFIG_FILE:-missing}\" \"${EMU_DIR:-missing}\" > \"$TEST_NATIVE_MARKER\"\n",
            )
            (app / "runtime/core/native_v020/libruffle_cursorfix.aarch64.so").unlink()
            game = root / "Roms" / "Flash (FLASH)" / "Bejeweled 2.swf"
            game.write_bytes(b"FWS-test")
            env["TEST_NATIVE_MARKER"] = str(native_marker)
            run("bash", flash_pak / "launch.sh", game, env=env)
            marker_body = native_marker.read_text()
            self.assertIn("native reached", marker_body)
            self.assertIn("SDL=auto", marker_body)
            self.assertIn("a:b0", marker_body)
            self.assertIn("rightshoulder:b5", marker_body)
            self.assertEqual(helper_args.read_text().splitlines()[:2], ["-1", "ruffle-native.aarch64"])
            cfg = helper_cfg.read_text()
            self.assertNotIn("mouse_left", cfg)
            self.assertIn("dpad = mouse_movement", cfg)
            self.assertNotIn("mouse_movement_up", cfg)
            logs = list((app / "logs").glob("*.log"))
            self.assertEqual(sorted(path.name for path in logs), ["Bejeweled_2.swf.log", "LAST-INSTALL.log"])
            self.assertIn("Installation verified.", (app / "logs/LAST-INSTALL.log").read_text())
            self.assertFalse((app / "logs/native").exists())
            self.assertFalse(any(path.name.startswith("LAST-") and path.name != "LAST-INSTALL.log"
                                 for path in (app / "logs").iterdir()))

            # Hybrid default: physical A keeps its Space action through the
            # RightShoulder Ruffle slot while physical R1 becomes the one
            # profile-selected native click. No second uinput pointer clicks.
            generic = root / "Roms" / "Flash (FLASH)" / "Generic Hybrid.swf"
            generic.write_bytes(b"FWS-test")
            run("bash", flash_pak / "launch.sh", generic, env=env)
            marker_body = native_marker.read_text()
            self.assertIn("rightshoulder:b0", marker_body)
            self.assertIn("a:b5", marker_body)
            cfg = helper_cfg.read_text()
            self.assertNotIn("mouse_left", cfg)
            self.assertNotIn("dpad = mouse_movement", cfg)
            hybrid_log = app / "logs" / "Generic_Hybrid.swf.log"
            self.assertIn("click-route=native-r1", hybrid_log.read_text())
            self.assertEqual(
                sorted(path.name for path in (app / "logs").glob("*.log")),
                ["Bejeweled_2.swf.log", "Generic_Hybrid.swf.log", "LAST-INSTALL.log"],
            )

            # NextUI's reference control template uses a DB file and a no-op
            # get_controls(), not the mapping variable returned on ArkOS.
            # Exercise standalone FLASH.pak without PORTS.pak's parent env.
            database = pak / "PortMaster/gamecontrollerdb.txt"
            database.write_text("03000000,test,a:b0,b:b1\n")
            control.write_text(
                '#!/bin/bash\ncontrolfolder="${EMU_DIR:?}"\n'
                'directory="${TEMP_DATA_DIR:?}"\n'
                'export SDL_GAMECONTROLLERCONFIG_FILE="$controlfolder/gamecontrollerdb.txt"\n'
                "CFW_NAME=NextUI\nDEVICE_NAME='TrimUI Brick'\nANALOG_STICKS=0\n"
                f"GPTOKEYB2='{fake_gpt} -1'\n"
                "get_controls() { :; }\n"
                "pm_platform_helper() { :; }\npm_finish() { :; }\n"
            )
            for variable in ("EMU_DIR", "TEMP_DATA_DIR", "SDL_GAMECONTROLLERCONFIG", "SDL_GAMECONTROLLERCONFIG_FILE"):
                env.pop(variable, None)
            run("bash", flash_pak / "launch.sh", game, env=env, cwd=Path(temp))
            marker_body = native_marker.read_text()
            self.assertIn(f"MAPFILE={database}", marker_body)
            self.assertIn(f"EMU={pak / 'PortMaster'}", marker_body)
            self.assertIn("MAP=missing", marker_body)
            self.assertEqual(helper_args.read_text().splitlines()[:2], ["-1", "ruffle-native.aarch64"])
            # This checks the contract only, not physical cursor movement.
            self.assertIn("dpad = mouse_movement", helper_cfg.read_text())

    def test_emuelec_clean_update_migrates_data_profiles_and_deduplicates(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ruffle emuelec ") as temp:
            romroot = Path(temp) / "My ROMS"
            app = romroot / "ports" / "rufflehandheld"
            shutil.copytree(APP_SOURCE, app)
            flash = romroot / "flash"
            flash.mkdir(parents=True)
            old_sidecar = flash / "Garfield.files"
            old_sidecar.mkdir()
            (old_sidecar / "asset.dat").write_bytes(b"asset")
            legacy_profiles = romroot / "flash_profiles"
            legacy_profiles.mkdir()
            legacy_profile = legacy_profiles / "my-game.profile"
            legacy_profile.write_text("name=My Game\nmouse_click=a\nsouth=none\n", encoding="utf-8")
            custom = app / "profiles/custom/keep.profile"
            custom.parent.mkdir(exist_ok=True)
            custom.write_text("name=Keep Me\nmouse_click=r1\n", encoding="utf-8")
            config = Path(temp) / "emulationstation" / "es_systems.cfg"
            config.parent.mkdir()
            config.write_text(
                "<?xml version=\"1.0\"?>\n<systemList>\n"
                "<system><name>flash</name><command>/old/flash_runtime/launch.sh %ROM%</command></system>\n"
                "<system><name>flash</name><command>/older/ports/ruffle_r36s/run.sh %ROM%</command></system>\n"
                "</systemList>\n",
                encoding="utf-8",
            )
            state = Path(temp) / "state"
            state.mkdir()
            env = base_env(
                RUFFLE_ES_CONFIG=str(config),
                RUFFLE_ES_LEGACY_CONFIG=str(config),
                RUFFLE_INSTALL_STATE_DIR=str(state),
            )
            for _ in range(2):
                run("bash", app / "core-install.sh", romroot, app, "EmuELEC", env=env)
            xml = config.read_text(encoding="utf-8")
            self.assertEqual(xml.count("<name>flash</name>"), 1)
            self.assertIn("%ROM_RAW%", xml)
            self.assertTrue((romroot / "flash_data/Garfield.files/asset.dat").is_file())
            self.assertFalse(old_sidecar.exists())
            self.assertTrue((app / "profiles/my-game.profile").is_file())
            self.assertTrue(custom.is_file())
            self.assertFalse((romroot / "flash_runtime").exists())
            for relative, expected in FROZEN.items():
                self.assertEqual(hashlib.sha256((app / relative).read_bytes()).hexdigest(), expected)
            for executable in [
                app / "runtime/es-launch.sh",
                app / "runtime/core/native_v020/ruffle-native.aarch64",
                app / "runtime/core/native_multifile/ruffle-native-multifile.aarch64",
            ]:
                self.assertTrue(os.access(executable, os.X_OK), executable)

            setup = (app / "setup.sh").read_text(encoding="utf-8")
            self.assertIn('restart_service_adapter "EmuELEC" emustation.service', setup)
            self.assertIn('restart_service_adapter "ROCKNIX" essway.service', setup)

    def test_rocknix_symlink_update_spaces_wayland_and_no_duplicate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ruffle rocknix ") as temp:
            romroot = Path(temp) / "ROM collection"
            app = romroot / "ports" / "rufflehandheld"
            shutil.copytree(APP_SOURCE, app)
            system_cfg = Path(temp) / "read only" / "es_systems.cfg"
            system_cfg.parent.mkdir(parents=True)
            system_cfg.write_text('<?xml version="1.0"?>\n<systemList>\n</systemList>\n', encoding="utf-8")
            user_cfg = Path(temp) / "storage" / ".config" / "emulationstation" / "es_systems.cfg"
            user_cfg.parent.mkdir(parents=True)
            user_cfg.symlink_to(system_cfg)
            env = base_env(
                RUFFLE_ROM_ROOT=str(romroot),
                RUFFLE_CFW_NAME="ROCKNIX",
                RUFFLE_ROCKNIX_ES_CONFIG=str(user_cfg),
                RUFFLE_ROCKNIX_SYSTEM_CONFIG=str(system_cfg),
            )
            for _ in range(2):
                run("bash", app / "setup.sh", romroot / "ports", env=env)
            self.assertFalse(user_cfg.is_symlink())
            self.assertTrue(Path(str(user_cfg) + ".rufflehandheld-original-link").is_symlink())
            xml = user_cfg.read_text(encoding="utf-8")
            self.assertEqual(xml.count("<name>flash</name>"), 1)
            self.assertIn("%ROM_RAW%", xml)
            self.assertIn("<theme>flash</theme>", xml)
            self.assertIn(str(romroot / "flash"), xml)

            marker = Path(temp) / "rocknix.marker"
            native = app / "runtime/core/native_v020/ruffle-native.aarch64"
            make_executable(native, "#!/bin/bash\nprintf 'SDL=%s\\n' \"${SDL_VIDEODRIVER:-auto}\" > \"$TEST_NATIVE_MARKER\"\n")
            (app / "runtime/core/native_v020/libruffle_cursorfix.aarch64.so").unlink()
            game = romroot / "flash" / "Fancy Game With Spaces.swf"
            game.write_bytes(b"FWS-test")
            launch_env = base_env(
                RUFFLE_ROM_ROOT=str(romroot),
                RUFFLE_CFW_NAME="ROCKNIX",
                CFW_NAME="ROCKNIX",
                TEST_NATIVE_MARKER=str(marker),
            )
            run("bash", app / "runtime/es-launch.sh", "--rom-root", romroot, game, env=launch_env)
            self.assertEqual(marker.read_text().strip(), "SDL=wayland")
            log = app / "logs" / "Fancy_Game_With_Spaces.swf.log"
            self.assertIn(str(game), log.read_text())

    def test_knulli_h700_multifile_uses_mali(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ruffle knulli ") as temp:
            romroot = Path(temp) / "roms"
            app = romroot / "ports" / "rufflehandheld"
            shutil.copytree(APP_SOURCE, app)
            marker = Path(temp) / "knulli.marker"
            native = app / "runtime/core/native_multifile/ruffle-native-multifile.aarch64"
            make_executable(native, "#!/bin/bash\nprintf 'SDL=%s\\n' \"${SDL_VIDEODRIVER:-auto}\" > \"$TEST_NATIVE_MARKER\"\n")
            (app / "runtime/core/native_v020/libruffle_cursorfix.aarch64.so").unlink()
            game = romroot / "flash" / "Garfield.swf"
            sidecar = romroot / "flash_data" / "Garfield.files"
            game.parent.mkdir(parents=True)
            sidecar.mkdir(parents=True)
            game.write_bytes(b"FWS-test")
            (sidecar / "asset.dat").write_bytes(b"asset")
            env = base_env(
                RUFFLE_ROM_ROOT=str(romroot),
                RUFFLE_CFW_NAME="Knulli",
                CFW_NAME="Knulli",
                DEVICE_CPU="H700",
                TEST_NATIVE_MARKER=str(marker),
            )
            run("bash", app / "runtime/es-launch.sh", "--rom-root", romroot, game, env=env)
            self.assertEqual(marker.read_text().strip(), "SDL=mali")
            log = app / "logs" / "Garfield.swf.log"
            body = log.read_text()
            self.assertIn("Backend: native-multifile", body)
            self.assertIn("/flash_data/Garfield.files", body)

    def test_release_layout_permissions_and_lf(self) -> None:
        run("python3", ROOT / "tools/build_release.py", cwd=ROOT)
        version = (ROOT / "VERSION").read_text().strip()
        archive = ROOT / f"releases/Ruffle-Handheld-v{version}-OFFLINE.zip"
        with zipfile.ZipFile(archive) as release:
            names = release.namelist()
            self.assertIn("Ruffle Handheld.sh", names)
            self.assertTrue(any(name.startswith("rufflehandheld/") for name in names))
            self.assertFalse(any("native_adaptive" in name or "LAST-INSTALL.log" in name for name in names))
            roots = {name.split("/", 1)[0] for name in names}
            self.assertEqual(roots, {"Ruffle Handheld.sh", "rufflehandheld"})
            for info in release.infolist():
                data = release.read(info)
                if Path(info.filename).suffix.lower() in {".sh", ".profile", ".py", ".json", ".xml", ".txt", ".html"}:
                    self.assertNotIn(b"\r\n", data, info.filename)
                if info.filename.endswith(".sh") or info.filename.endswith(".aarch64"):
                    self.assertTrue((info.external_attr >> 16) & stat.S_IXUSR, info.filename)


if __name__ == "__main__":
    unittest.main(verbosity=2)

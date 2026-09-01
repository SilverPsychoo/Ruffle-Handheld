from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "port" / "rufflehandheld" / "rufflehandheld"
ENGINE_LIB = APP / "runtime" / "core" / "lib" / "engine.sh"
PROFILE_LIB = APP / "runtime" / "core" / "lib" / "control_profiles.sh"
PROFILES = APP / "profiles"


def find_bash() -> str:
    candidates = [
        shutil.which("bash"),
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise unittest.SkipTest("Bash is required for selector tests")


def shell_path(path: Path) -> str:
    resolved = path.resolve()
    if os.name == "nt":
        drive = resolved.drive.rstrip(":").lower()
        tail = resolved.as_posix().split(":", 1)[1]
        return f"/{drive}{tail}"
    return resolved.as_posix()


class EngineSelectorTests(unittest.TestCase):
    def run_selector(
        self,
        *,
        device: str,
        cfw: str,
        width: str,
        height: str,
        preference: str = "auto",
        adaptive_exists: bool = True,
    ) -> tuple[str, str]:
        with tempfile.TemporaryDirectory(prefix="ruffle-v0826-selector-") as temp:
            root = Path(temp)
            stable = root / "stable.aarch64"
            adaptive = root / "adaptive.aarch64"
            stable.touch()
            if adaptive_exists:
                adaptive.touch()
            command = (
                'source "$1"; '
                'DEVICE_NAME="$2"; CFW_NAME="$3"; DISPLAY_WIDTH="$4"; DISPLAY_HEIGHT="$5"; '
                'RUFFLE_HANDHELD_ENGINE="$6"; '
                'rh_select_engine "$7" "$8"; '
                'printf "%s|%s\\n" "$RH_ENGINE_MODE" "$RH_ENGINE_REASON"'
            )
            result = subprocess.run(
                [
                    find_bash(),
                    "-c",
                    command,
                    "selector-test",
                    shell_path(ENGINE_LIB),
                    device,
                    cfw,
                    width,
                    height,
                    preference,
                    shell_path(stable),
                    shell_path(adaptive),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            return tuple(result.stdout.strip().split("|", 1))  # type: ignore[return-value]

    def test_emuelec_keeps_stable_engine(self) -> None:
        mode, reason = self.run_selector(
            device="Amlogic-ng", cfw="EmuELEC", width="640", height="480"
        )
        self.assertEqual(mode, "stable")
        self.assertIn("default", reason)

    def test_trimui_brick_uses_adaptive_engine(self) -> None:
        mode, reason = self.run_selector(
            device="TrimUI Brick", cfw="TrimUI", width="1024", height="768"
        )
        self.assertEqual(mode, "adaptive")
        self.assertIn("TrimUI Brick", reason)

    def test_missing_adaptive_engine_falls_back_to_stable(self) -> None:
        mode, reason = self.run_selector(
            device="TrimUI Brick",
            cfw="TrimUI",
            width="1024",
            height="768",
            adaptive_exists=False,
        )
        self.assertEqual(mode, "stable")
        self.assertIn("fallback", reason)


class AdaptiveProfileTests(unittest.TestCase):
    def resolve_profile(self, game_name: str) -> str:
        command = 'source "$1"; rh_resolve_profile "$2" "$3"'
        result = subprocess.run(
            [
                find_bash(),
                "-c",
                command,
                "profile-test",
                shell_path(PROFILE_LIB),
                shell_path(PROFILES),
                game_name,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        return Path(result.stdout.strip()).name

    def test_reported_breaking_bank_filename_gets_adaptive_profile(self) -> None:
        self.assertEqual(
            self.resolve_profile("161792_breaking-the-bank"),
            "henry-stickmin-breaking-the-bank.profile",
        )

    def test_reported_mcdonalds_filename_gets_adaptive_profile(self) -> None:
        self.assertEqual(
            self.resolve_profile("McDonald_s_Videogame"),
            "mcdonald-s-videogame.profile",
        )

    def test_trimui_pointer_adapter_uses_supported_dpad_mouse_mapping(self) -> None:
        launch = (APP / "runtime" / "core" / "launch.sh").read_text(encoding="utf-8")
        self.assertIn('ANALOG_STICKS:-${ANALOGSTICKS:-2}', launch)
        self.assertIn('[ "$mouse_mode" = "mouse" ] && [ "$stick_count" = "0" ]', launch)
        self.assertIn("dpad = mouse_movement", launch)
        self.assertIn('RUFFLE_POINTER_MODE="dpad-mouse"', launch)
        self.assertIn('HELPER_PROCESS="ruffle-native-adaptive.aarch64"', launch)

    def test_click_helper_pins_the_portmaster_controller_map(self) -> None:
        launch = (APP / "runtime" / "core" / "launch.sh").read_text(encoding="utf-8")
        snapshot = 'export SDL_GAMECONTROLLERCONFIG_FILE="$INPUT_MAP"'
        helper_start = '$GPTOKEYB2 "$proc" -c "$cfg"'
        self.assertIn(snapshot, launch)
        self.assertIn('export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"', launch)
        self.assertLess(launch.index(snapshot), launch.index(helper_start))
        self.assertIn("controller-map=$controller_map_status", launch)
        self.assertIn("Helper shutdown: exited before game end", launch)

    def test_engine_patch_removes_navigator_panic_and_uses_real_display(self) -> None:
        patch = (ROOT / "engine" / "patches" / "ruffle4consoles-v0.8.26.patch").read_text(
            encoding="utf-8"
        )
        self.assertIn("External navigation ignored", patch)
        self.assertIn("current_display_mode", patch)
        self.assertIn("fullscreen_desktop", patch)
        self.assertIn("StageScaleMode::ShowAll", patch)


if __name__ == "__main__":
    unittest.main()

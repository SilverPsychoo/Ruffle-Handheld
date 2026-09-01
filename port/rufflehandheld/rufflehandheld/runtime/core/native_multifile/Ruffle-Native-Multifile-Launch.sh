#!/bin/bash
# Ruffle Handheld v0.7.7 - generic Native multi-file launcher with control profiles
# Uses the Native binary proven with Garfield, but nothing here is game-specific.
# The binary's local content root is patched from "ruffle_data" to "/tmp/gdata_".

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/roms2/ports/PortMaster/" ]; then
    controlfolder="/roms2/ports/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

[ -f "$controlfolder/control.txt" ] || { echo "ERROR: PortMaster control.txt not found: $controlfolder"; exit 1; }
# shellcheck disable=SC1090
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
type get_controls >/dev/null 2>&1 && get_controls >/dev/null 2>&1 || true

GAMEDIR="/${directory:-roms}/ports/ruffle_r36s"
[ -d "$GAMEDIR" ] || GAMEDIR="/roms/ports/ruffle_r36s"
STABLE_BIN="$GAMEDIR/runtime/ruffle-native-multifile.aarch64"
ADAPTIVE_BIN="$GAMEDIR/runtime/ruffle-native-adaptive.aarch64"
ENGINE_LIB="$GAMEDIR/lib/engine.sh"
[ -f "$ENGINE_LIB" ] || { echo "ERROR: engine selector missing: $ENGINE_LIB"; exit 3; }
# shellcheck disable=SC1090
source "$ENGINE_LIB"
rh_select_engine "$STABLE_BIN" "$ADAPTIVE_BIN"
BIN="$RH_ENGINE_BIN"
CURSOR_SO="$GAMEDIR/runtime/libruffle_cursorfix.aarch64.so"
LOGDIR="$GAMEDIR/logs/native"
FLASHLOG="/${directory:-roms}/flash_runtime/logs"
[ -d "$FLASHLOG" ] || FLASHLOG="/storage/roms/flash_runtime/logs"
mkdir -p "$LOGDIR" "$FLASHLOG"

SWF=""
for arg in "$@"; do
    case "$arg" in
        *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;;
    esac
done
[ -n "$SWF" ] || { echo "ERROR: no existing .swf path received"; exit 2; }

BASE="$(basename "$SWF")"
STEM="${BASE%.*}"
SAFE="$(printf '%s' "$BASE" | sed 's/[^A-Za-z0-9._-]/_/g')"
LOG="$LOGDIR/${SAFE}.log"
FLASH_LOG="$FLASHLOG/${SAFE}.multifile.log"
exec > >(tee "$LOG" "$FLASH_LOG") 2>&1

echo "=== Ruffle Native Multi-file v0.7.7 ==="
echo "Date: $(date)"
echo "CFW: ${CFW_NAME:-unknown} ${CFW_VERSION:-}"
echo "Device: ${DEVICE_NAME:-unknown} arch=${DEVICE_ARCH:-$(uname -m)}"
echo "Selected SWF: $SWF"
echo "Binary: $BIN"
echo "Engine: $RH_ENGINE_MODE ($RH_ENGINE_REASON)"
echo "Cursor shim: $CURSOR_SO"
echo "Content root: /tmp/gdata_"

[ -f "$BIN" ] || { echo "ERROR: generic multi-file Native binary missing"; exit 3; }
$ESUDO chmod +x "$BIN" 2>/dev/null || chmod +x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || { echo "ERROR: multi-file Native binary is not executable"; exit 4; }

# The dispatcher normally supplies the exact sidecar path. If not, discover it.
SIDE="${RUFFLE_SIDECAR:-}"
if [ -z "$SIDE" ] || [ ! -d "$SIDE" ]; then
    ROMROOT="/${directory:-roms}"
    [ -d "$ROMROOT/flash" ] || ROMROOT="/storage/roms"
    SWFDIR="$(CDPATH= cd -- "$(dirname -- "$SWF")" 2>/dev/null && pwd)"
    for candidate in \
        "$ROMROOT/flash_data/$STEM.files" \
        "$ROMROOT/flash_data/$BASE.files" \
        "$SWFDIR/$STEM.files" \
        "$SWFDIR/.$STEM.files" \
        "$SWFDIR/$BASE.files" \
        "$SWFDIR/.$BASE.files"; do
        [ -d "$candidate" ] && { SIDE="$candidate"; break; }
    done
fi
[ -n "$SIDE" ] && [ -d "$SIDE" ] || { echo "ERROR: multi-file sidecar folder not found"; exit 5; }

echo "Sidecar: $SIDE"
DATA_ROOT="/tmp/gdata_"
cleanup() {
    cd / 2>/dev/null || true
    rm -rf "$DATA_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
rm -rf "$DATA_ROOT"
mkdir -p "$DATA_ROOT/storage" || { echo "ERROR: cannot create $DATA_ROOT"; exit 6; }

# Stage all sidecar contents recursively, then expose the main SWF under both
# its original name and movie.swf (the frozen console frontend expects movie.swf).
cp -a "$SIDE"/. "$DATA_ROOT"/ 2>/dev/null || cp -R "$SIDE"/. "$DATA_ROOT"/ || exit 7
cp -f "$SWF" "$DATA_ROOT/$BASE" || exit 8
cp -f "$SWF" "$DATA_ROOT/movie.swf" || exit 9

echo "Staged top-level files:"
for f in "$DATA_ROOT"/*; do [ -f "$f" ] && echo "  $(basename "$f")"; done

PROFILE_LIB="$GAMEDIR/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || PROFILE_LIB="/${directory:-roms}/flash_runtime/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || PROFILE_LIB="/storage/roms/flash_runtime/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || { echo "ERROR: control profile library missing"; exit 11; }
# shellcheck disable=SC1090
source "$PROFILE_LIB"

ROMROOT="/${directory:-roms}"
[ -d "$ROMROOT/flash_profiles" ] || ROMROOT="/storage/roms"
DEFAULT_PROFILE="$ROMROOT/flash_profiles/default.profile"
PROFILE="${RUFFLE_PROFILE:-$DEFAULT_PROFILE}"
[ -f "$PROFILE" ] || PROFILE="$DEFAULT_PROFILE"
PROFILE_NAME="$(rh_profile_display_name "$PROFILE")"
echo "Control profile: $PROFILE_NAME"
echo "Profile file: $PROFILE"

# Remove the frozen frontend's stock A/South click. If the profile assigns a
# keyboard key to A, route the physical binding through SDL RightShoulder;
# config.ron then exposes it as Ruffle RightTrigger. Otherwise A remains
# available only to gptokeyb2 when mouse_click=a.
rh_route_profile_a() {
    route="$1"; mapping="$2"
    [ -n "$mapping" ] || { printf '%s' "$mapping"; return 0; }

    oldifs="$IFS"; IFS=','
    a_bind=""
    for field in $mapping; do
        case "$field" in
            a:*) a_bind="${field#a:}" ;;
        esac
    done

    # Without a discoverable physical A binding, fail safe and keep mapping.
    [ -n "$a_bind" ] || { IFS="$oldifs"; printf '%s' "$mapping"; return 0; }

    out=""; first=1
    for field in $mapping; do
        case "$field" in
            a:*) continue ;;
            rightshoulder:*)
                if [ "$route" = "keyboard" ]; then field="rightshoulder:$a_bind"; else continue; fi
                ;;
        esac
        if [ "$first" -eq 1 ]; then out="$field"; first=0; else out="$out,$field"; fi
    done
    IFS="$oldifs"

    # Some DB rows may not define rightshoulder. Add it for a keyboard action.
    if [ "$route" = "keyboard" ]; then
        case ",$out," in *,rightshoulder:*) ;; *) out="$out,rightshoulder:$a_bind" ;; esac
    fi
    printf '%s' "$out"
}

A_KEYCODE="$(rh_profile_value "$PROFILE" "$DEFAULT_PROFILE" south 2>/dev/null || true)"
[ "$(rh_profile_raw_value "$PROFILE" native_a_mode 2>/dev/null || true)" = "native" ] && A_KEYCODE="none"
A_ROUTE="none"
rh_valid_keycode "$A_KEYCODE" && A_ROUTE="keyboard"
if [ -n "${sdl_controllerconfig:-}" ]; then
    ORIGINAL_SDL_CONTROLLERCONFIG="$sdl_controllerconfig"
    sdl_controllerconfig="$(rh_route_profile_a "$A_ROUTE" "$sdl_controllerconfig")"
fi
rh_write_config_ron "$PROFILE" "$DEFAULT_PROFILE" "$DATA_ROOT/config.ron" "movie.swf" || { echo "ERROR: could not build config.ron"; exit 12; }
if [ "${RUFFLE_DEBUG:-0}" = "1" ]; then
    echo "Generated native gamepad map:"
    cat "$DATA_ROOT/config.ron"
else
    echo "Native gamepad profile: generated"
fi

type pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$BIN"
unset DISPLAY WAYLAND_DISPLAY
export SDL_VIDEODRIVER="${RUFFLE_SDL_VIDEODRIVER:-kmsdrm}"
export SDL_AUDIODRIVER="${RUFFLE_SDL_AUDIODRIVER:-alsa}"
if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
    printf '%s\n' "$sdl_controllerconfig" > "$DATA_ROOT/gamecontrollerdb.profile.txt"
    export SDL_GAMECONTROLLERCONFIG_FILE="$DATA_ROOT/gamecontrollerdb.profile.txt"
else
    export SDL_GAMECONTROLLERCONFIG_FILE="${SDL_GAMECONTROLLERCONFIG_FILE:-$controlfolder/gamecontrollerdb.txt}"
fi
if [ "${RUFFLE_DEBUG:-0}" = "1" ]; then
    export RUST_BACKTRACE=full
else
    export RUST_BACKTRACE=0
fi
if [ -f "$CURSOR_SO" ]; then
    export LD_PRELOAD="$CURSOR_SO${LD_PRELOAD:+:$LD_PRELOAD}"
fi

echo "Input: native gamepad profile | pointer=${RUFFLE_POINTER_MODE:-right-stick-mouse} | click-helper=${RUFFLE_CLICK_BUTTON:-r1}"
echo "Starting generic multi-file Native binary..."
cd /tmp || exit 10
"$BIN"
rc=$?
echo "Native Multi-file exit code: $rc"
type pm_finish >/dev/null 2>&1 && pm_finish
exit "$rc"

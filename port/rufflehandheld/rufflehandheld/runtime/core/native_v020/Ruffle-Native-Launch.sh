#!/bin/bash
# Ruffle Handheld Native v0.7.7 - optimized universal SWF launcher
# Per-game control profiles are translated to ruffle4consoles config.ron.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

[ -f "$controlfolder/control.txt" ] || { echo "ERROR: PortMaster control.txt not found: $controlfolder"; exit 1; }
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
type get_controls >/dev/null 2>&1 && get_controls

GAMEDIR="/${directory:-roms}/ports/ruffle_r36s"
[ -d "$GAMEDIR" ] || GAMEDIR="/roms/ports/ruffle_r36s"
BIN="$GAMEDIR/runtime/ruffle-native.aarch64"
CURSOR_SO="$GAMEDIR/runtime/libruffle_cursorfix.aarch64.so"
GAMESDIR="$GAMEDIR/games"
LOGDIR="$GAMEDIR/logs/native"
mkdir -p "$LOGDIR" "$GAMESDIR"

SWF=""
for arg in "$@"; do
    case "$arg" in
        *.swf|*.SWF)
            [ -f "$arg" ] && { SWF="$arg"; break; }
            ;;
    esac
done

if [ -z "$SWF" ]; then
    echo "ERROR: no existing .swf path received"
    exit 2
fi

BASE=$(basename "$SWF")
SAFE=$(printf '%s' "$BASE" | sed 's/[^A-Za-z0-9._-]/_/g')
LOG="$LOGDIR/${SAFE}.log"
exec > >(tee "$LOG") 2>&1

echo "=== Ruffle Handheld Native v0.7.7 ==="
echo "Date: $(date)"
echo "CFW: ${CFW_NAME:-unknown} ${CFW_VERSION:-}"
echo "Device: ${DEVICE_NAME:-unknown} arch=${DEVICE_ARCH:-$(uname -m)}"
echo "Display: ${DISPLAY_WIDTH:-?}x${DISPLAY_HEIGHT:-?}"
echo "Selected SWF: $SWF"
echo "Binary: $BIN"
echo "Cursor shim: $CURSOR_SO"

[ -f "$BIN" ] || { echo "ERROR: native binary missing"; exit 3; }
$ESUDO chmod +x "$BIN" 2>/dev/null || chmod +x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || { echo "ERROR: native binary is not executable"; exit 4; }

# ruffle4consoles currently expects ./ruffle_data/movie.swf.
# Use a per-launch tmp session so one game cannot contaminate another.
SESSION="/tmp/ruffle_r36s_native_$$"
rm -rf "$SESSION"
mkdir -p "$SESSION/ruffle_data/storage"

SWFDIR=$(dirname "$SWF")
# Bundle mode: if the SWF lives in its own subfolder under games/, bring sibling assets too.
case "$SWFDIR" in
    "$GAMESDIR")
        ln -s "$SWF" "$SESSION/ruffle_data/movie.swf" || cp -f "$SWF" "$SESSION/ruffle_data/movie.swf"
        echo "Content mode: single SWF (zero-copy symlink when supported)"
        ;;
    "$GAMESDIR"/*)
        echo "Content mode: bundle folder"
        cp -a "$SWFDIR"/. "$SESSION/ruffle_data/" 2>/dev/null || cp -R "$SWFDIR"/. "$SESSION/ruffle_data/"
        cp -f "$SWF" "$SESSION/ruffle_data/movie.swf"
        ;;
    *)
        ln -s "$SWF" "$SESSION/ruffle_data/movie.swf" || cp -f "$SWF" "$SESSION/ruffle_data/movie.swf"
        echo "Content mode: external single SWF (zero-copy symlink when supported)"
        ;;
esac

PROFILE_LIB="$GAMEDIR/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || PROFILE_LIB="/${directory:-roms}/flash_runtime/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || PROFILE_LIB="/storage/roms/flash_runtime/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || { echo "ERROR: control profile library missing"; exit 6; }
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
rh_write_config_ron "$PROFILE" "$DEFAULT_PROFILE" "$SESSION/ruffle_data/config.ron" "movie.swf" || { echo "ERROR: could not build config.ron"; exit 7; }
if [ "${RUFFLE_DEBUG:-0}" = "1" ]; then
    echo "Generated native gamepad map:"
    cat "$SESSION/ruffle_data/config.ron"
else
    echo "Native gamepad profile: generated"
fi

type pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$BIN"

unset DISPLAY WAYLAND_DISPLAY
export SDL_VIDEODRIVER="${RUFFLE_SDL_VIDEODRIVER:-kmsdrm}"
export SDL_AUDIODRIVER="${RUFFLE_SDL_AUDIODRIVER:-alsa}"
if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
    printf '%s\n' "$sdl_controllerconfig" > "$SESSION/gamecontrollerdb.profile.txt"
    export SDL_GAMECONTROLLERCONFIG_FILE="$SESSION/gamecontrollerdb.profile.txt"
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

echo "Input: native gamepad profile | right stick=mouse | click-helper=${RUFFLE_CLICK_BUTTON:-r1}"
echo "SDL video: $SDL_VIDEODRIVER"
echo "SDL audio: $SDL_AUDIODRIVER"
echo "Starting native binary..."

cd "$SESSION" || exit 5
"$BIN"
rc=$?
echo "Native exit code: $rc"
cd / 2>/dev/null || true
rm -rf "$SESSION"
type pm_finish >/dev/null 2>&1 && pm_finish
exit $rc

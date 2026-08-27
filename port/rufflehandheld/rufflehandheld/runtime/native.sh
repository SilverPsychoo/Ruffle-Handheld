#!/bin/bash
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PORTDIR="$(dirname "$RUNTIME_DIR")"
BIN="$PORTDIR/bin/ruffle-native.aarch64"
CURSOR_SO="$PORTDIR/bin/libruffle_cursorfix.aarch64.so"
LOGDIR="$PORTDIR/logs/native"; mkdir -p "$LOGDIR"
# shellcheck disable=SC1090
source "$RUNTIME_DIR/platform.sh" 2>/dev/null || true
rh_platform_init 2>/dev/null || true
# shellcheck disable=SC1090
source "$RUNTIME_DIR/controls.sh" || exit 6

SWF=""
for arg in "$@"; do case "$arg" in *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;; esac; done
[ -n "$SWF" ] || exit 2
BASE="$(basename "$SWF")"; SAFE="$(printf '%s' "$BASE" | sed 's/[^A-Za-z0-9._-]/_/g')"
exec > >(tee "$LOGDIR/${SAFE}.log") 2>&1
[ -f "$BIN" ] || { echo "Missing native runtime."; exit 3; }
${ESUDO:-} chmod +x "$BIN" 2>/dev/null || chmod +x "$BIN" 2>/dev/null || true

SESSION="/tmp/ruffle_handheld_$$"; rm -rf "$SESSION"; mkdir -p "$SESSION/ruffle_data/storage"
ln -s "$SWF" "$SESSION/ruffle_data/movie.swf" 2>/dev/null || cp -f "$SWF" "$SESSION/ruffle_data/movie.swf"
DEFAULT_PROFILE="$PORTDIR/profiles/default.profile"; PROFILE="${RUFFLE_PROFILE:-$DEFAULT_PROFILE}"; [ -f "$PROFILE" ] || PROFILE="$DEFAULT_PROFILE"

rh_apply_native_a_policy() {
    mode="$1"; mapping="$2"
    [ -n "$mapping" ] || { printf '%s' "$mapping"; return 0; }
    [ "$mode" = "native" ] && { printf '%s' "$mapping"; return 0; }
    oldifs="$IFS"; IFS=','; a_bind=""; out=""; first=1
    for field in $mapping; do case "$field" in a:*) a_bind="${field#a:}" ;; esac; done
    [ -n "$a_bind" ] || { IFS="$oldifs"; printf '%s' "$mapping"; return 0; }
    for field in $mapping; do
        case "$field" in
            a:*) continue ;;
            rightshoulder:*) [ "$mode" = "keyboard" ] && field="rightshoulder:$a_bind" || continue ;;
        esac
        [ "$first" -eq 1 ] && { out="$field"; first=0; } || out="$out,$field"
    done
    IFS="$oldifs"
    if [ "$mode" = "keyboard" ]; then case ",$out," in *,rightshoulder:*) ;; *) out="$out,rightshoulder:$a_bind" ;; esac; fi
    printf '%s' "$out"
}

MODE="$(rh_profile_value "$PROFILE" "$DEFAULT_PROFILE" native_a_mode 2>/dev/null || true)"; [ -n "$MODE" ] || MODE=keyboard
[ -n "${sdl_controllerconfig:-}" ] && sdl_controllerconfig="$(rh_apply_native_a_policy "$MODE" "$sdl_controllerconfig")"
rh_write_config_ron "$PROFILE" "$DEFAULT_PROFILE" "$SESSION/ruffle_data/config.ron" movie.swf || exit 7

type pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$BIN"
if [ -z "${SDL_VIDEODRIVER:-}" ]; then [ -n "${WAYLAND_DISPLAY:-}" ] && export SDL_VIDEODRIVER=wayland || export SDL_VIDEODRIVER=kmsdrm; fi
if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
    printf '%s\n' "$sdl_controllerconfig" > "$SESSION/gamecontrollerdb.txt"
    export SDL_GAMECONTROLLERCONFIG_FILE="$SESSION/gamecontrollerdb.txt"
elif [ -n "${RH_CONTROLFOLDER:-}" ] && [ -f "$RH_CONTROLFOLDER/gamecontrollerdb.txt" ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="$RH_CONTROLFOLDER/gamecontrollerdb.txt"
fi
export RUST_BACKTRACE="${RUFFLE_DEBUG:-0}"
[ -f "$CURSOR_SO" ] && export LD_PRELOAD="$CURSOR_SO${LD_PRELOAD:+:$LD_PRELOAD}"
cd "$SESSION" || exit 5
"$BIN"; rc=$?
cd / 2>/dev/null || true; rm -rf "$SESSION"
type pm_finish >/dev/null 2>&1 && pm_finish
exit "$rc"

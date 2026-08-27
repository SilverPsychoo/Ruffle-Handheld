#!/bin/bash
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PORTDIR="$(dirname "$RUNTIME_DIR")"
BIN="$PORTDIR/bin/ruffle-native-multifile.aarch64"; CURSOR_SO="$PORTDIR/bin/libruffle_cursorfix.aarch64.so"
LOGDIR="$PORTDIR/logs/native"; mkdir -p "$LOGDIR"
# shellcheck disable=SC1090
source "$RUNTIME_DIR/platform.sh" 2>/dev/null || true; rh_platform_init 2>/dev/null || true
# shellcheck disable=SC1090
source "$RUNTIME_DIR/controls.sh" || exit 6
SWF=""; for arg in "$@"; do case "$arg" in *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;; esac; done
[ -n "$SWF" ] || exit 2
BASE="$(basename "$SWF")"; SAFE="$(printf '%s' "$BASE" | sed 's/[^A-Za-z0-9._-]/_/g')"; exec > >(tee "$LOGDIR/${SAFE}.log") 2>&1
[ -f "$BIN" ] || { echo "Missing multi-file runtime."; exit 3; }; ${ESUDO:-} chmod +x "$BIN" 2>/dev/null || chmod +x "$BIN" 2>/dev/null || true
SIDE="${RUFFLE_SIDECAR:-}"; [ -d "$SIDE" ] || { echo "Multi-file data folder not found."; exit 4; }
DATA="/tmp/gdata_"; rm -rf "$DATA"; mkdir -p "$DATA/storage" || exit 5
trap 'cd / 2>/dev/null; rm -rf "$DATA"' EXIT INT TERM
cp -a "$SIDE"/. "$DATA"/ 2>/dev/null || cp -R "$SIDE"/. "$DATA"/ || exit 7
cp -f "$SWF" "$DATA/$BASE" || exit 8; cp -f "$SWF" "$DATA/movie.swf" || exit 9
DEFAULT_PROFILE="$PORTDIR/profiles/default.profile"; PROFILE="${RUFFLE_PROFILE:-$DEFAULT_PROFILE}"; [ -f "$PROFILE" ] || PROFILE="$DEFAULT_PROFILE"
# Same physical-A routing used by native.sh.
rh_apply_native_a_policy() {
    mode="$1"; mapping="$2"; [ -n "$mapping" ] || { printf '%s' "$mapping"; return; }; [ "$mode" = native ] && { printf '%s' "$mapping"; return; }
    oldifs="$IFS"; IFS=','; a_bind=""; out=""; first=1
    for field in $mapping; do case "$field" in a:*) a_bind="${field#a:}" ;; esac; done
    [ -n "$a_bind" ] || { IFS="$oldifs"; printf '%s' "$mapping"; return; }
    for field in $mapping; do case "$field" in a:*) continue ;; rightshoulder:*) [ "$mode" = keyboard ] && field="rightshoulder:$a_bind" || continue ;; esac; [ "$first" -eq 1 ] && { out="$field"; first=0; } || out="$out,$field"; done
    IFS="$oldifs"; if [ "$mode" = keyboard ]; then case ",$out," in *,rightshoulder:*) ;; *) out="$out,rightshoulder:$a_bind" ;; esac; fi; printf '%s' "$out"
}
MODE="$(rh_profile_value "$PROFILE" "$DEFAULT_PROFILE" native_a_mode 2>/dev/null || true)"; [ -n "$MODE" ] || MODE=keyboard
[ -n "${sdl_controllerconfig:-}" ] && sdl_controllerconfig="$(rh_apply_native_a_policy "$MODE" "$sdl_controllerconfig")"
rh_write_config_ron "$PROFILE" "$DEFAULT_PROFILE" "$DATA/config.ron" movie.swf || exit 10
type pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$BIN"
if [ -z "${SDL_VIDEODRIVER:-}" ]; then [ -n "${WAYLAND_DISPLAY:-}" ] && export SDL_VIDEODRIVER=wayland || export SDL_VIDEODRIVER=kmsdrm; fi
if [ -n "${sdl_controllerconfig:-}" ]; then export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"; printf '%s\n' "$sdl_controllerconfig" > "$DATA/gamecontrollerdb.txt"; export SDL_GAMECONTROLLERCONFIG_FILE="$DATA/gamecontrollerdb.txt"; elif [ -n "${RH_CONTROLFOLDER:-}" ] && [ -f "$RH_CONTROLFOLDER/gamecontrollerdb.txt" ]; then export SDL_GAMECONTROLLERCONFIG_FILE="$RH_CONTROLFOLDER/gamecontrollerdb.txt"; fi
[ -f "$CURSOR_SO" ] && export LD_PRELOAD="$CURSOR_SO${LD_PRELOAD:+:$LD_PRELOAD}"
export RUST_BACKTRACE="${RUFFLE_DEBUG:-0}"
cd /tmp || exit 11; "$BIN"; rc=$?
type pm_finish >/dev/null 2>&1 && pm_finish
exit "$rc"

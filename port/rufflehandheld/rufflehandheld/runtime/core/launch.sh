#!/bin/bash
# Ruffle Handheld v0.7.7 dispatcher
# Native controller input + per-game Ruffle profiles + click-only PortMaster helper.
# v0.8.21 policy: raw physical A is never passed directly to the frozen frontend.

ENGINE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
ROMROOT="$(dirname "$ENGINE_DIR")"
FLASHDIR="$ROMROOT/flash"
DATADIR="$ROMROOT/flash_data"
PROFILEDIR="$ROMROOT/flash_profiles"
LOGDIR="$ENGINE_DIR/logs"
mkdir -p "$LOGDIR" "$DATADIR" "$PROFILEDIR" 2>/dev/null || true
EARLY="$LOGDIR/FLASH-EARLY.log"
{
  echo "=== Ruffle Handheld v0.7.7 PERFORMANCE + NATIVE PROFILES ==="
  echo "Date: $(date 2>/dev/null)"
  echo "Script: $0"
  printf 'Args:'; for a in "$@"; do printf ' <%s>' "$a"; done; echo
} > "$EARLY" 2>&1

PROFILE_LIB="$ENGINE_DIR/lib/control_profiles.sh"
[ -f "$PROFILE_LIB" ] || { echo "ERROR: profile library missing: $PROFILE_LIB" >> "$EARLY"; exit 3; }
# shellcheck disable=SC1090
source "$PROFILE_LIB"

PERF_LIB="$ENGINE_DIR/lib/performance.sh"
if [ -f "$PERF_LIB" ]; then
    # shellcheck disable=SC1090
    source "$PERF_LIB"
fi

SWF=""
for arg in "$@"; do
    case "$arg" in *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;; esac
done
[ -n "$SWF" ] || { echo "ERROR: no existing SWF received" >> "$EARLY"; exit 2; }

BASE="$(basename "$SWF")"
STEM="${BASE%.*}"
SWFDIR="$(CDPATH= cd -- "$(dirname -- "$SWF")" 2>/dev/null && pwd)"
echo "Selected SWF: $SWF" >> "$EARLY"

PROFILE="$(rh_resolve_profile "$PROFILEDIR" "$STEM")"
PROFILE_NAME="$(rh_profile_display_name "$PROFILE")"
echo "Control profile: $PROFILE_NAME" >> "$EARLY"
echo "Profile file: $PROFILE" >> "$EARLY"

SIDE=""
for candidate in "$DATADIR/$STEM.files" "$DATADIR/$BASE.files"; do
    [ -d "$candidate" ] && { SIDE="$candidate"; break; }
done
if [ -z "$SIDE" ]; then
    for old in "$SWFDIR/$STEM.files" "$SWFDIR/.$STEM.files" "$SWFDIR/$BASE.files" "$SWFDIR/.$BASE.files"; do
        [ -d "$old" ] || continue
        target="$DATADIR/$STEM.files"
        mkdir -p "$DATADIR" 2>/dev/null || true
        if [ ! -e "$target" ]; then
            mv "$old" "$target" 2>/dev/null || { mkdir -p "$target" && cp -a "$old"/. "$target"/ 2>/dev/null && rm -rf "$old"; }
        else
            cp -a "$old"/. "$target"/ 2>/dev/null && rm -rf "$old"
        fi
        [ -d "$target" ] && { SIDE="$target"; echo "Migrated sidecar: $old -> $target" >> "$EARLY"; break; }
    done
fi

# Non-exclusive helper: ONLY injects the configured mouse click and watches the
# normal Select+Start quit combo. Ruffle itself keeps ownership of sticks, D-pad
# and all keyboard-profile buttons.
INPUT_PID=""; INPUT_CFG=""
start_click_helper() {
    proc="$1"; profile="$2"; defaults="$PROFILEDIR/default.profile"
    cfg="/tmp/ruffle_native_click_$$.gptk.ini"; ilog="$LOGDIR/input-helper.log"
    click="$(rh_profile_value "$profile" "$defaults" mouse_click 2>/dev/null || true)"
    legacy_a_mode="$(rh_profile_value "$profile" "$defaults" native_a_mode 2>/dev/null || true)"
    [ -n "$click" ] || click="r1"
    case "$click" in a|b|x|y|l1|l2|l3|r1|r2|r3|start|back) ;; none|NONE|None) click="" ;; *) click="r1" ;; esac
    # Old mouse-only profiles used raw Native A and therefore declared no
    # helper click. Native A is no longer allowed; preserve usability by moving
    # that old implicit click through the explicit helper during launch without
    # rewriting user files. A remains the expected click for mouse-only games,
    # but Ruffle itself no longer receives raw A/South.
    [ "$legacy_a_mode" = "native" ] && [ -z "$click" ] && click="a"
    {
        echo '[config]'
        echo 'deadzone_triggers = 3000'
        echo
        echo '[controls]'
        echo 'overlay = clear'
        echo 'exclusive = false'
        [ -n "$click" ] && printf '%s = mouse_left\n' "$click"
    } > "$cfg"
    : > "$ilog" 2>/dev/null || true
    { echo "=== v0.7.7 click-only map ==="; cat "$cfg"; echo "=== helper output ==="; } >> "$ilog" 2>&1

    PMCTRL=""
    for pm in /roms/ports/PortMaster /roms2/ports/PortMaster /storage/roms/ports/PortMaster /storage/roms2/ports/PortMaster; do
        [ -f "$pm/control.txt" ] && { PMCTRL="$pm/control.txt"; break; }
    done
    if [ -n "$PMCTRL" ]; then
        # shellcheck disable=SC1090
        source "$PMCTRL" 2>/dev/null || true
        [ -n "${CFW_NAME:-}" ] && [ -f "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" ] && source "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" 2>/dev/null || true
        type get_controls >/dev/null 2>&1 && get_controls >/dev/null 2>&1 || true
    fi
    if [ -n "${GPTOKEYB2:-}" ]; then
        # shellcheck disable=SC2086
        $GPTOKEYB2 "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
    elif [ -n "${GPTOKEYB:-}" ]; then
        # shellcheck disable=SC2086
        $GPTOKEYB "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
    elif command -v gptokeyb2 >/dev/null 2>&1; then
        gptokeyb2 "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
    fi
    INPUT_CFG="$cfg"
    RUFFLE_CLICK_BUTTON="${click:-none}"; export RUFFLE_CLICK_BUTTON
    [ -n "$INPUT_PID" ] && echo "Input helper: click-only PID=$INPUT_PID process=$proc click=${click:-none} exclusive=false" >> "$EARLY" || echo "Input helper: unavailable" >> "$EARLY"
}
stop_click_helper() {
    [ -n "$INPUT_PID" ] && kill "$INPUT_PID" 2>/dev/null || true
    [ -n "$INPUT_PID" ] && wait "$INPUT_PID" 2>/dev/null || true
    [ -n "$INPUT_CFG" ] && rm -f "$INPUT_CFG" 2>/dev/null || true
    INPUT_PID=""; INPUT_CFG=""
}

cleanup_runtime() {
    stop_click_helper
    type rh_perf_end >/dev/null 2>&1 && rh_perf_end "$EARLY" || true
}
trap cleanup_runtime EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

type rh_perf_begin >/dev/null 2>&1 && rh_perf_begin "$EARLY" || true

if [ -n "$SIDE" ]; then
    MULTI="/$([ -d /roms2/ports/ruffle_r36s ] && echo roms2 || echo roms)/ports/ruffle_r36s/Ruffle-Native-Multifile-Launch.sh"
    [ -f "$MULTI" ] || MULTI="$ENGINE_DIR/native_multifile/Ruffle-Native-Multifile-Launch.sh"
    chmod +x "$MULTI" 2>/dev/null || true
    echo "Backend: native-multifile" >> "$EARLY"; echo "Sidecar: $SIDE" >> "$EARLY"; echo "Launcher: $MULTI" >> "$EARLY"
    start_click_helper "ruffle-native-multifile.aarch64" "$PROFILE"
    RUFFLE_SIDECAR="$SIDE" RUFFLE_PROFILE="$PROFILE" /bin/bash "$MULTI" "$SWF"
    rc=$?; exit "$rc"
fi

NATIVE="/$([ -d /roms2/ports/ruffle_r36s ] && echo roms2 || echo roms)/ports/ruffle_r36s/Ruffle-Native-Launch.sh"
[ -f "$NATIVE" ] || NATIVE="$ENGINE_DIR/native_v020/Ruffle-Native-Launch.sh"
chmod +x "$NATIVE" 2>/dev/null || true
echo "Backend: native-v0.2.0-frozen" >> "$EARLY"; echo "Native launcher: $NATIVE" >> "$EARLY"
start_click_helper "ruffle-native.aarch64" "$PROFILE"
RUFFLE_PROFILE="$PROFILE" /bin/bash "$NATIVE" "$SWF"
rc=$?; exit "$rc"

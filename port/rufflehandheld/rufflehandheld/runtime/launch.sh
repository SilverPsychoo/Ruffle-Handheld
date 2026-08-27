#!/bin/bash
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PORTDIR="$(dirname "$RUNTIME_DIR")"
PORTS_DIR="$(dirname "$PORTDIR")"
RH_ROMROOT="${RH_ROMROOT:-$(dirname "$PORTS_DIR")}"; export RH_ROMROOT
FLASHDIR="$RH_ROMROOT/flash"
DATADIR="$RH_ROMROOT/flash_data"
PROFILEDIR="$PORTDIR/profiles"
LOGDIR="$PORTDIR/logs"
mkdir -p "$LOGDIR" "$DATADIR" 2>/dev/null || true
EARLY="$LOGDIR/launch.log"

# shellcheck disable=SC1090
source "$RUNTIME_DIR/platform.sh" 2>/dev/null || true
rh_platform_init 2>/dev/null || true
# shellcheck disable=SC1090
source "$RUNTIME_DIR/controls.sh" || exit 3
# shellcheck disable=SC1090
source "$RUNTIME_DIR/performance.sh" 2>/dev/null || true

SWF=""
for arg in "$@"; do
    case "$arg" in *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;; esac
done
[ -n "$SWF" ] || { echo "No SWF was received." > "$EARLY"; exit 2; }

BASE="$(basename "$SWF")"; STEM="${BASE%.*}"
PROFILE="$(rh_resolve_profile "$PROFILEDIR" "$STEM")"
SIDE=""
for candidate in "$DATADIR/$STEM.files" "$DATADIR/$BASE.files" "$(dirname "$SWF")/$STEM.files" "$(dirname "$SWF")/.$STEM.files"; do
    [ -d "$candidate" ] && { SIDE="$candidate"; break; }
done

{
    echo "Ruffle Handheld 0.8.1"
    echo "Game: $SWF"
    echo "Profile: $(rh_profile_display_name "$PROFILE")"
    [ -n "$SIDE" ] && echo "Mode: multi-file ($SIDE)" || echo "Mode: single SWF"
} > "$EARLY"

INPUT_PID=""; INPUT_CFG=""
start_click_helper() {
    proc="$1"; defaults="$PROFILEDIR/default.profile"
    click="$(rh_profile_value "$PROFILE" "$defaults" mouse_click 2>/dev/null || true)"
    [ -n "$click" ] || click="r1"
    case "$click" in a|b|x|y|l1|l2|l3|r1|r2|r3|start|back) ;; none|NONE|None) click="" ;; *) click="r1" ;; esac
    [ -n "$click" ] || { RUFFLE_CLICK_BUTTON=none; export RUFFLE_CLICK_BUTTON; return 0; }
    INPUT_CFG="/tmp/ruffle_handheld_click_$$.ini"
    cat > "$INPUT_CFG" <<EOF
[config]
deadzone_triggers = 3000

[controls]
overlay = clear
exclusive = false
$click = mouse_left
EOF
    if [ -n "${GPTOKEYB2:-}" ]; then
        # shellcheck disable=SC2086
        $GPTOKEYB2 "$proc" -c "$INPUT_CFG" >/dev/null 2>&1 & INPUT_PID=$!
    elif [ -n "${GPTOKEYB:-}" ]; then
        # shellcheck disable=SC2086
        $GPTOKEYB "$proc" -c "$INPUT_CFG" >/dev/null 2>&1 & INPUT_PID=$!
    elif command -v gptokeyb2 >/dev/null 2>&1; then
        gptokeyb2 "$proc" -c "$INPUT_CFG" >/dev/null 2>&1 & INPUT_PID=$!
    fi
    RUFFLE_CLICK_BUTTON="$click"; export RUFFLE_CLICK_BUTTON
}
cleanup() {
    [ -n "$INPUT_PID" ] && kill "$INPUT_PID" 2>/dev/null || true
    [ -n "$INPUT_CFG" ] && rm -f "$INPUT_CFG" 2>/dev/null || true
    type rh_perf_end >/dev/null 2>&1 && rh_perf_end "$EARLY" || true
}
trap cleanup EXIT INT TERM
type rh_perf_begin >/dev/null 2>&1 && rh_perf_begin "$EARLY" || true

export RUFFLE_PROFILE="$PROFILE" RH_ROMROOT
if [ -n "$SIDE" ]; then
    export RUFFLE_SIDECAR="$SIDE"
    start_click_helper "ruffle-native-multifile.aarch64"
    /bin/bash "$RUNTIME_DIR/multifile.sh" "$SWF"
else
    start_click_helper "ruffle-native.aarch64"
    /bin/bash "$RUNTIME_DIR/native.sh" "$SWF"
fi
exit $?

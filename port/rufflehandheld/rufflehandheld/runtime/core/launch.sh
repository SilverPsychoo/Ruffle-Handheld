#!/bin/bash
# Ruffle Handheld v0.7.7 dispatcher
# Native controller input + per-game Ruffle profiles + click-only PortMaster helper.
# v0.8.26 policy: raw physical A is never passed directly to the frontend.

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

PROFILE_ENGINE="$(rh_profile_value "$PROFILE" "$PROFILEDIR/default.profile" engine 2>/dev/null || true)"
PROFILE_SCALE="$(rh_profile_value "$PROFILE" "$PROFILEDIR/default.profile" force_scale 2>/dev/null || true)"
case "$PROFILE_ENGINE" in adaptive|stable) [ -n "${RUFFLE_HANDHELD_ENGINE:-}" ] || RUFFLE_HANDHELD_ENGINE="$PROFILE_ENGINE" ;; *) : ;; esac
case "$PROFILE_SCALE" in showall|show-all) [ -n "${RUFFLE_HANDHELD_FORCE_SCALE:-}" ] || RUFFLE_HANDHELD_FORCE_SCALE="showall" ;; *) : ;; esac
export RUFFLE_HANDHELD_ENGINE RUFFLE_HANDHELD_FORCE_SCALE
echo "Engine preference: ${RUFFLE_HANDHELD_ENGINE:-auto}" >> "$EARLY"
echo "Scale preference: ${RUFFLE_HANDHELD_FORCE_SCALE:-movie-default}" >> "$EARLY"

# Resolve the engine once here as well so gptokeyb2 follows the executable that
# will actually run. The inner launcher repeats this check before exec and keeps
# the same automatic fallback if the adaptive binary is unavailable.
ENGINE_SELECTOR="$ENGINE_DIR/lib/engine.sh"
[ -f "$ENGINE_SELECTOR" ] || { echo "ERROR: engine selector missing: $ENGINE_SELECTOR" >> "$EARLY"; exit 3; }
# shellcheck disable=SC1090
source "$ENGINE_SELECTOR"
rh_select_engine \
    "$ENGINE_DIR/native_v020/ruffle-native.aarch64" \
    "$ENGINE_DIR/native_adaptive/ruffle-native-adaptive.aarch64"
echo "Resolved engine: $RH_ENGINE_MODE ($RH_ENGINE_REASON)" >> "$EARLY"
if [ "$RH_ENGINE_MODE" = "adaptive" ]; then
    HELPER_PROCESS="ruffle-native-adaptive.aarch64"
else
    HELPER_PROCESS="ruffle-native.aarch64"
fi

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

# Non-exclusive helper injects the configured mouse click and watches the normal
# Select+Start quit combo. On devices without an analog stick, mouse-only
# profiles also use PortMaster's supported D-pad mouse mode.
INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""; INPUT_LOG=""; PM_FINISH_READY=0
start_click_helper() {
    proc="$1"; profile="$2"; defaults="$PROFILEDIR/default.profile"
    cfg="/tmp/ruffle_native_click_$$.gptk.ini"; ilog="$LOGDIR/input-helper.log"
    click="$(rh_profile_value "$profile" "$defaults" mouse_click 2>/dev/null || true)"
    mouse_mode="$(rh_profile_value "$profile" "$defaults" mouse_mode 2>/dev/null || true)"
    legacy_a_mode="$(rh_profile_value "$profile" "$defaults" native_a_mode 2>/dev/null || true)"
    [ -n "$click" ] || click="r1"
    case "$click" in a|b|x|y|l1|l2|l3|r1|r2|r3|start|back) ;; none|NONE|None) click="" ;; *) click="r1" ;; esac
    # Old mouse-only profiles used raw Native A and therefore declared no
    # helper click. Native A is no longer allowed; preserve usability by moving
    # that old implicit click through the explicit helper during launch without
    # rewriting user files. A remains the expected click for mouse-only games,
    # but Ruffle itself no longer receives raw A/South.
    [ "$legacy_a_mode" = "native" ] && [ -z "$click" ] && click="a"
    PMCTRL=""
    for pm in /opt/system/Tools/PortMaster /opt/tools/PortMaster \
        "${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/PortMaster" \
        /roms/ports/PortMaster /roms2/ports/PortMaster \
        /storage/roms/ports/PortMaster /storage/roms2/ports/PortMaster; do
        [ -f "$pm/control.txt" ] && { PMCTRL="$pm/control.txt"; break; }
    done
    if [ -n "$PMCTRL" ]; then
        # shellcheck disable=SC1090
        source "$PMCTRL" 2>/dev/null || true
        [ -n "${CFW_NAME:-}" ] && [ -f "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" ] && source "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" 2>/dev/null || true
        type get_controls >/dev/null 2>&1 && get_controls >/dev/null 2>&1 || true
        type pm_finish >/dev/null 2>&1 && PM_FINISH_READY=1
    fi

    # gptokeyb2 translates physical SDL button numbers (for example button 5
    # on the RG351MP) through SDL's controller database before it can apply a
    # logical mapping such as r1=mouse_left. Keep a private snapshot because
    # the inner native launcher also calls get_controls and PortMaster normally
    # reuses /tmp/gamecontrollerdb.txt for every process.
    controller_map_source="${SDL_GAMECONTROLLERCONFIG_FILE:-}"
    controller_map_snapshot="/tmp/ruffle_native_controller_$$.txt"
    if [ -n "${sdl_controllerconfig:-}" ]; then
        printf '%s\n' "$sdl_controllerconfig" > "$controller_map_snapshot" 2>/dev/null || true
    elif [ -n "${SDL_GAMECONTROLLERCONFIG:-}" ]; then
        printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" > "$controller_map_snapshot" 2>/dev/null || true
    elif [ -n "$controller_map_source" ] && [ -r "$controller_map_source" ]; then
        cp "$controller_map_source" "$controller_map_snapshot" 2>/dev/null || true
    fi
    if [ -s "$controller_map_snapshot" ]; then
        INPUT_MAP="$controller_map_snapshot"
        export SDL_GAMECONTROLLERCONFIG_FILE="$INPUT_MAP"
        if [ -z "${sdl_controllerconfig:-}" ]; then
            sdl_controllerconfig="$(cat "$INPUT_MAP" 2>/dev/null || true)"
        fi
        [ -n "${sdl_controllerconfig:-}" ] && export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
        controller_map_status="ready"
    else
        rm -f "$controller_map_snapshot" 2>/dev/null || true
        controller_map_status="missing"
    fi

    stick_count="${ANALOG_STICKS:-${ANALOGSTICKS:-2}}"
    device_key="$(printf '%s' "${DEVICE_NAME:-}" | tr '[:upper:]' '[:lower:]')"
    case "$device_key" in *trimui*brick*|tui-brick) stick_count=0 ;; esac
    dpad_mouse=false
    if [ "$mouse_mode" = "mouse" ] && [ "$stick_count" = "0" ]; then
        dpad_mouse=true
    fi

    {
        echo '[config]'
        echo 'deadzone_triggers = 3000'
        if [ "$dpad_mouse" = true ]; then
            echo 'mouse_scale = 5000'
            echo 'mouse_delay = 16'
            echo 'dpad_mouse_normalize = true'
        fi
        echo
        echo '[controls]'
        echo 'overlay = clear'
        echo 'exclusive = false'
        [ "$dpad_mouse" = true ] && echo 'dpad = mouse_movement'
        [ -n "$click" ] && printf '%s = mouse_left\n' "$click"
    } > "$cfg"
    : > "$ilog" 2>/dev/null || true
    INPUT_LOG="$ilog"
    {
        echo "=== v0.8.26 pointer map ==="
        cat "$cfg"
        echo "=== controller map ==="
        echo "status=$controller_map_status"
        echo "source=${controller_map_source:-none}"
        echo "snapshot=${INPUT_MAP:-none}"
        if [ -n "$INPUT_MAP" ]; then
            map_entries="$(grep -c '^[^#].*,' "$INPUT_MAP" 2>/dev/null || true)"
            echo "entries=${map_entries:-0}"
        fi
        echo "=== helper output ==="
    } >> "$ilog" 2>&1

    if [ -n "${GPTOKEYB2:-}" ]; then
        # PortMaster already selects the device-specific quit mode (for example
        # -Z on ArkOS). Use its command exactly as exported; adding -1 here can
        # override Select+Start and leave the handheld trapped in the game.
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
    if [ "$dpad_mouse" = true ]; then RUFFLE_POINTER_MODE="dpad-mouse"; else RUFFLE_POINTER_MODE="right-stick-mouse"; fi
    export RUFFLE_POINTER_MODE
    if [ -n "$INPUT_PID" ]; then
        echo "Input helper: pointer=$RUFFLE_POINTER_MODE PID=$INPUT_PID process=$proc click=${click:-none} exclusive=false controller-map=$controller_map_status" >> "$EARLY"
    else
        echo "Input helper: unavailable controller-map=$controller_map_status" >> "$EARLY"
    fi
}
stop_click_helper() {
    if [ -n "$INPUT_PID" ]; then
        if kill -0 "$INPUT_PID" 2>/dev/null; then
            echo "Helper shutdown: active at game exit" >> "$INPUT_LOG" 2>/dev/null || true
            kill "$INPUT_PID" 2>/dev/null || true
            wait "$INPUT_PID" 2>/dev/null || true
        else
            wait "$INPUT_PID" 2>/dev/null
            helper_rc=$?
            echo "Helper shutdown: exited before game end (code=$helper_rc)" >> "$INPUT_LOG" 2>/dev/null || true
        fi
    fi
    [ -n "$INPUT_CFG" ] && rm -f "$INPUT_CFG" 2>/dev/null || true
    [ -n "$INPUT_MAP" ] && rm -f "$INPUT_MAP" 2>/dev/null || true
    INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""; INPUT_LOG=""
}

cleanup_runtime() {
    stop_click_helper
    type rh_perf_end >/dev/null 2>&1 && rh_perf_end "$EARLY" || true
    [ "$PM_FINISH_READY" -eq 1 ] && pm_finish >/dev/null 2>&1 || true
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
    [ "$RH_ENGINE_MODE" = "adaptive" ] || HELPER_PROCESS="ruffle-native-multifile.aarch64"
    start_click_helper "$HELPER_PROCESS" "$PROFILE"
    RUFFLE_SIDECAR="$SIDE" RUFFLE_PROFILE="$PROFILE" /bin/bash "$MULTI" "$SWF"
    rc=$?; exit "$rc"
fi

NATIVE="/$([ -d /roms2/ports/ruffle_r36s ] && echo roms2 || echo roms)/ports/ruffle_r36s/Ruffle-Native-Launch.sh"
[ -f "$NATIVE" ] || NATIVE="$ENGINE_DIR/native_v020/Ruffle-Native-Launch.sh"
chmod +x "$NATIVE" 2>/dev/null || true
echo "Backend: native-v0.2.0-frozen" >> "$EARLY"; echo "Native launcher: $NATIVE" >> "$EARLY"
start_click_helper "$HELPER_PROCESS" "$PROFILE"
RUFFLE_PROFILE="$PROFILE" /bin/bash "$NATIVE" "$SWF"
rc=$?; exit "$rc"

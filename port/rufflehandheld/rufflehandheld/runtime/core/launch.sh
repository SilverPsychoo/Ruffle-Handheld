#!/bin/bash
# Ruffle Handheld v0.7.7 dispatcher
# Native controller input + per-game profiles + PortMaster hotkey/mouse helper.
# v0.8.28 policy: raw physical A is never passed directly to the frozen frontend.
# A profile-selected mouse button is routed to the frontend's own cursor click;
# this keeps the click at Ruffle's cursor position on Wayland.

ENGINE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
BASH_BIN="${RUFFLE_BASH:-${BASH:-/bin/bash}}"
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
echo "Engine: frozen-v0.7.7" >> "$EARLY"

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

# Non-exclusive helper: watches the CFW-defined quit combo and supplies D-pad
# mouse movement on devices without sticks. A mouse click is injected only as a
# compatibility fallback when no usable SDL binding is exposed by the CFW.
INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""
start_click_helper() {
    proc="$1"; profile="$2"; defaults="$PROFILEDIR/default.profile"
    cfg="/tmp/ruffle_native_click_$$.gptk.ini"; ilog="$LOGDIR/input-helper.log"
    click="$(rh_profile_value "$profile" "$defaults" mouse_click 2>/dev/null || true)"
    mouse_mode="$(rh_profile_raw_value "$profile" mouse_mode 2>/dev/null || true)"
    legacy_a_mode="$(rh_profile_value "$profile" "$defaults" native_a_mode 2>/dev/null || true)"
    [ -n "$click" ] || click="r1"
    case "$click" in a|b|x|y|l1|l2|l3|r1|r2|r3|start|back) ;; none|NONE|None) click="" ;; *) click="r1" ;; esac
    # Old mouse-only profiles used raw Native A and therefore declared no
    # explicit click. Preserve usability by treating that legacy declaration as
    # mouse_click=a without rewriting the user's file. Raw A still stays off for
    # every profile that does not explicitly request A as its click.
    [ "$legacy_a_mode" = "native" ] && [ -z "$click" ] && click="a"
    : > "$ilog" 2>/dev/null || true

    PMCTRL="${RUFFLE_PORTMASTER_CONTROL:-}"
    [ -f "$PMCTRL" ] || PMCTRL=""
    for pm in \
        "${controlfolder:-}" \
        /PortMaster \
        /opt/system/Tools/PortMaster \
        /opt/tools/PortMaster \
        "${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/PortMaster" \
        "$ROMROOT/ports/PortMaster" \
        "$ROMROOT/ports_scripts/PortMaster" \
        /roms/ports/PortMaster \
        /roms2/ports/PortMaster \
        /storage/roms/ports/PortMaster \
        /storage/roms2/ports/PortMaster; do
        [ -n "$PMCTRL" ] && break
        [ -n "$pm" ] && [ -f "$pm/control.txt" ] && PMCTRL="$pm/control.txt"
    done
    if [ -n "$PMCTRL" ]; then
        echo "PortMaster control: $PMCTRL" >> "$ilog"
        # shellcheck disable=SC1090
        source "$PMCTRL" 2>/dev/null || true
        [ -n "${CFW_NAME:-}" ] && [ -f "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" ] && source "$(dirname "$PMCTRL")/mod_${CFW_NAME}.txt" 2>/dev/null || true
        type get_controls >/dev/null 2>&1 && get_controls >/dev/null 2>&1 || true
    else
        echo "PortMaster control: unavailable; using executable fallback if present" >> "$ilog"
    fi

    # PortMaster may supply a mapping through get_controls(), an SDL variable,
    # or only SDL_GAMECONTROLLERCONFIG_FILE (notably on NextUI). Use the same
    # database to choose the click path and to configure the Native launcher.
    controller_db="${sdl_controllerconfig:-${SDL_GAMECONTROLLERCONFIG:-}}"
    if [ -z "$controller_db" ]; then
        controller_file="${SDL_GAMECONTROLLERCONFIG_FILE:-}"
        [ -n "$controller_file" ] || controller_file="${controlfolder:-$(dirname "$PMCTRL")}/gamecontrollerdb.txt"
        [ -f "$controller_file" ] && controller_db="$(cat "$controller_file")"
    fi
    if [ -n "$controller_db" ]; then
        export RUFFLE_CONTROLLER_DB="$controller_db"
        echo "Controller mapping: $(printf '%s\n' "$controller_db" | grep -c '[^[:space:]]' || true) row(s)" >> "$ilog"
    else
        unset RUFFLE_CONTROLLER_DB
        echo "Controller mapping: unavailable" >> "$ilog"
    fi

    # Prefer the frozen frontend's own click path whenever PortMaster exposed
    # the physical binding selected by the profile. On Wayland, a mouse click
    # injected by a second uinput pointer is reported at that pointer's stale
    # position (commonly 0,0), even though Ruffle's right stick moved its own
    # cursor elsewhere.
    native_click=""
    click_sdl=""
    case "$click" in
        a) click_sdl="a" ;;
        b) click_sdl="b" ;;
        x) click_sdl="x" ;;
        y) click_sdl="y" ;;
        l1) click_sdl="leftshoulder" ;;
        l2) click_sdl="lefttrigger" ;;
        l3) click_sdl="leftstick" ;;
        r1) click_sdl="rightshoulder" ;;
        r2) click_sdl="righttrigger" ;;
        r3) click_sdl="rightstick" ;;
        start) click_sdl="start" ;;
        back) click_sdl="back" ;;
    esac
    if [ -n "$click_sdl" ]; then
        case ",$controller_db," in
            *",$click_sdl:"*) native_click="$click" ;;
        esac
        # Without an explicit database row SDL still provides its normal A
        # mapping. Keeping this case native preserves mouse-only profiles on
        # installations that do not have PortMaster.
        [ -z "$controller_db" ] && [ "$click" = "a" ] && native_click="a"
    fi
    helper_click="$click"
    [ -n "$native_click" ] && helper_click=""
    RUFFLE_NATIVE_CLICK_BUTTON="${native_click:-none}"; export RUFFLE_NATIVE_CLICK_BUTTON

    dpad_mouse=0
    device_key="$(printf '%s %s' "${DEVICE_NAME:-}" "${DEVICE_CPU:-}" | tr '[:upper:]' '[:lower:]')"
    if [ "$mouse_mode" = "mouse" ]; then
        case "${ANALOG_STICKS:-unknown}:$device_key" in
            0:*|*:trimui\ brick*|*:brick*) dpad_mouse=1 ;;
        esac
    fi
    {
        echo '[config]'
        echo 'deadzone_triggers = 3000'
        [ "$dpad_mouse" -eq 1 ] && echo 'dpad_mouse_step = 7'
        echo
        echo '[controls]'
        echo 'overlay = clear'
        echo 'exclusive = false'
        if [ "$dpad_mouse" -eq 1 ]; then
            # The aggregate binding is supported by the gptokeyb2 build in
            # NextUI/PORTS.pak. Its parser rejects the four directional
            # mouse_movement_* bindings as unknown keys.
            echo 'dpad = mouse_movement'
        fi
        [ -n "$helper_click" ] && printf '%s = mouse_left\n' "$helper_click"
    } > "$cfg"
    { echo "=== v0.7.7 input map ==="; cat "$cfg"; echo "=== helper output ==="; } >> "$ilog" 2>&1

    # Give gptokeyb2 the exact controller database discovered by PortMaster.
    # Some CFWs expose only the variable and not a persistent file.
    if [ -n "$controller_db" ]; then
        INPUT_MAP="/tmp/ruffle_controller_$$.txt"
        printf '%s\n' "$controller_db" > "$INPUT_MAP"
        export SDL_GAMECONTROLLERCONFIG="$controller_db"
        export SDL_GAMECONTROLLERCONFIG_FILE="$INPUT_MAP"
    fi

    helper_proc="$proc"
    case "$(printf '%s %s' "${RUFFLE_CFW_NAME:-}" "${CFW_NAME:-}" | tr '[:upper:]' '[:lower:]')" in
        *darkosre*)
            # R36S device heuristics in control.txt may select L3 as HOTKEY.
            # This port promises Select+Start; change only this child context.
            export HOTKEY=back
            echo 'Quit combo: Select+Start (HOTKEY=back)' >> "$ilog"
            case " ${GPTOKEYB2:-} " in
                *' -Z '*)
                    # procps pkill without -f matches the 15-byte comm field.
                    # Keep PortMaster's sudo/-Z mode, but provide a matchable
                    # name for our two frozen executables.
                    helper_proc="$(printf '%.15s' "$proc")"
                    echo "Quit target: $helper_proc (kernel process name for $proc)" >> "$ilog"
                    ;;
            esac
            ;;
    esac

    if [ -n "${GPTOKEYB2:-}" ]; then
        echo "Helper command: PortMaster GPTOKEYB2 (native PortMaster kill mode preserved)" >> "$ilog"
        if [ -x "$GPTOKEYB2" ]; then
            "$GPTOKEYB2" "$helper_proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
        else
            # PortMaster may expose a command plus a device-specific option,
            # for example `-Z` on ROCKNIX. Execute it unchanged: appending `-1`
            # replaced/broke that CFW-specific Start+Select mode.
            # shellcheck disable=SC2086
            $GPTOKEYB2 "$helper_proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
        fi
    elif [ -n "${GPTOKEYB:-}" ]; then
        echo "Helper command: PortMaster GPTOKEYB (native PortMaster kill mode preserved)" >> "$ilog"
        if [ -x "$GPTOKEYB" ]; then
            "$GPTOKEYB" "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
        else
            # shellcheck disable=SC2086
            $GPTOKEYB "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
        fi
    elif command -v gptokeyb2 >/dev/null 2>&1; then
        echo "Helper command: gptokeyb2 -1 fallback" >> "$ilog"
        gptokeyb2 -1 "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
    elif command -v gptokeyb >/dev/null 2>&1; then
        echo "Helper command: gptokeyb -1 fallback" >> "$ilog"
        gptokeyb -1 "$proc" -c "$cfg" >> "$ilog" 2>&1 & INPUT_PID=$!
    fi
    INPUT_CFG="$cfg"
    if [ -n "$native_click" ]; then
        RUFFLE_CLICK_BUTTON="native-$native_click"
    elif [ -n "$helper_click" ]; then
        RUFFLE_CLICK_BUTTON="helper-$helper_click"
    else
        RUFFLE_CLICK_BUTTON="none"
    fi
    export RUFFLE_CLICK_BUTTON
    if [ -n "$INPUT_PID" ]; then
        echo "Input helper: PID=$INPUT_PID process=$proc click-route=$RUFFLE_CLICK_BUTTON dpad-mouse=$dpad_mouse exclusive=false" >> "$EARLY"
    else
        echo "Input helper: unavailable; click-route=$RUFFLE_CLICK_BUTTON" >> "$EARLY"
    fi
}
stop_click_helper() {
    [ -n "$INPUT_PID" ] && kill "$INPUT_PID" 2>/dev/null || true
    [ -n "$INPUT_PID" ] && wait "$INPUT_PID" 2>/dev/null || true
    [ -n "$INPUT_CFG" ] && rm -f "$INPUT_CFG" 2>/dev/null || true
    [ -n "$INPUT_MAP" ] && rm -f "$INPUT_MAP" 2>/dev/null || true
    INPUT_PID=""; INPUT_CFG=""; INPUT_MAP=""
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
    RUFFLE_SIDECAR="$SIDE" RUFFLE_PROFILE="$PROFILE" "$BASH_BIN" "$MULTI" "$SWF"
    rc=$?; exit "$rc"
fi

NATIVE="/$([ -d /roms2/ports/ruffle_r36s ] && echo roms2 || echo roms)/ports/ruffle_r36s/Ruffle-Native-Launch.sh"
[ -f "$NATIVE" ] || NATIVE="$ENGINE_DIR/native_v020/Ruffle-Native-Launch.sh"
chmod +x "$NATIVE" 2>/dev/null || true
echo "Backend: native-v0.2.0-frozen" >> "$EARLY"; echo "Native launcher: $NATIVE" >> "$EARLY"
start_click_helper "ruffle-native.aarch64" "$PROFILE"
RUFFLE_PROFILE="$PROFILE" "$BASH_BIN" "$NATIVE" "$SWF"
rc=$?; exit "$rc"

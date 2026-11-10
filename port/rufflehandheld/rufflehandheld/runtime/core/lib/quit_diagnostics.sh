#!/bin/bash
# Read-only diagnostics for PortMaster's quit helper. No controller grabs,
# extra quit bindings or signals to the game are introduced here.

rh_quit_log() {
    printf '[quit] %s\n' "$*" >> "${RUFFLE_GAME_LOG:-$LOGDIR/input-helper.log}"
}

rh_quit_prepare() {
    local original_hotkey="$1" target="$2" requested="$3" command_text="$4"
    local token helper_binary="" row
    RUFFLE_QUIT_DEBUG_ARGS=()
    rh_quit_log "CFW=${RUFFLE_CFW_NAME:-${CFW_NAME:-unknown}} device=${DEVICE_NAME:-unknown} uid=$(id -u)"
    rh_quit_log "HOTKEY before PortMaster=${INPUT_INITIAL_HOTKEY:-unset}, after PortMaster=$original_hotkey, effective=${HOTKEY:-helper default}"
    rh_quit_log "Expected shortcut: Select+Start; configured shortcut: ${HOTKEY:-helper default}+start"
    rh_quit_log "Target requested=$requested effective=$target kernel-name=$(printf '%.15s' "$requested")"
    rh_quit_log "Helper command=$command_text"
    rh_quit_log "Exit environment: ESUDOKILL=${ESUDOKILL:-unset} NO_PKILL=${NO_PKILL:-unset} PCKILLMODE=${PCKILLMODE:-unset}"
    if command -v pkill >/dev/null 2>&1; then
        rh_quit_log "pkill=$(command -v pkill)"
    else
        rh_quit_log 'WARNING: pkill is unavailable'
    fi
    if [ -e /dev/uinput ]; then
        rh_quit_log "uinput: present readable=$([ -r /dev/uinput ] && echo yes || echo no) writable=$([ -w /dev/uinput ] && echo yes || echo no)"
    else
        rh_quit_log 'uinput: missing (mouse/key injection may fail)'
    fi
    # Log every row's relevant bindings, including aliases of Select. Do not
    # infer that the first database row is the connected controller.
    awk -F, '
      NF >= 3 && !/^#/ {
        line="[quit] Controller " $1 " " $2 ":"
        start=0; back=0
        for (i=3; i<=NF; i++) {
          if ($i ~ /^(start|back|guide|leftstick|rightstick):/) line=line " " $i
          if ($i ~ /^start:/) start=1
          if ($i ~ /^back:/) back=1
        }
        print line
        if (!start || !back) print "[quit] WARNING: this row lacks Start or Select/back"
        if (++n == 8) exit
      }
    ' "${RUFFLE_CONTROLLER_DB_FILE:-/dev/null}" >> "${RUFFLE_GAME_LOG:-$LOGDIR/input-helper.log}"

    # Older gptokeyb2 builds reject -D. Enable button-event output only when
    # the executable advertises the known debug-category option.
    for token in $command_text; do
        case "${token##*/}" in
            gptokeyb2|gptokeyb2.aarch64|gptokeyb2.armhf)
                helper_binary="$(command -v "$token" 2>/dev/null || true)"; break ;;
        esac
    done
    if [ -n "$helper_binary" ] &&
       LC_ALL=C grep -aFq 'comma separated debug output: states, gamepad' "$helper_binary" 2>/dev/null; then
        RUFFLE_QUIT_DEBUG_ARGS=(-D gamepad)
        rh_quit_log 'Button-event tracing: requested from supported gptokeyb2 (-D gamepad)'
    else
        rh_quit_log 'Button-event tracing: unavailable in this helper build; lifecycle and mapping diagnostics remain active'
    fi
}

rh_quit_monitor() {
    local helper_pid="$1" process_name="$2" quit_target="$3"
    local native_pid="" comm="" found_native=0 state=""
    sleep 0.2
    while kill -0 "$helper_pid" 2>/dev/null; do
        if [ -r "/proc/$helper_pid/stat" ]; then
            state="$(sed 's/.*) //' "/proc/$helper_pid/stat" | cut -d ' ' -f 1)"
            [ "$state" = Z ] && break
        fi
        if [ "$found_native" -eq 0 ] && command -v pgrep >/dev/null 2>&1; then
            native_pid="$(pgrep -x "$(printf '%.15s' "$process_name")" 2>/dev/null | head -1)"
            if [ -n "$native_pid" ] && [ -r "/proc/$native_pid/comm" ]; then
                comm="$(cat "/proc/$native_pid/comm")"
                rh_quit_log "Native process observed: PID=$native_pid comm=$comm quit-target=$quit_target"
                if [ "${#quit_target}" -gt 15 ]; then
                    rh_quit_log 'WARNING: the target exceeds Linux comm length; pkill by name may fail in helper builds that do not shorten it'
                fi
                found_native=1
            fi
        fi
        sleep 2
    done
    rh_quit_log "Helper PID=$helper_pid ended while the launch was active; inspect its output and exit status"
}

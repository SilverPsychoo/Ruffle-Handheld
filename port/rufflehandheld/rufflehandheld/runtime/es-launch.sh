#!/bin/bash
# Ruffle Handheld v0.8.35 frontend boundary and per-game log adapter.

set -u
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 2
APP_DIR="$(dirname "$RUNTIME_DIR")"
BASH_BIN="${RUFFLE_BASH:-${BASH:-/bin/bash}}"
LOGDIR="$APP_DIR/logs"
mkdir -p "$LOGDIR" || exit 3
AUXDIR="/tmp/ruffle_handheld_logs_${UID:-0}_$$"

BASE="launch-error"
for arg in "$@"; do
    case "$arg" in
        *.swf|*.SWF) BASE="$(basename "$arg")"; break ;;
    esac
done
SAFE="$(printf '%s' "$BASE" | sed 's/[^A-Za-z0-9._-]/_/g')"
LOG="$LOGDIR/$SAFE.log"

cleanup_auxiliary_logs() {
    for auxiliary in \
        "$LOGDIR/FLASH-EARLY.log" \
        "$LOGDIR/input-helper.log" \
        "$LOGDIR/LAST-LAUNCH-MEMORY.log" \
        "$LOGDIR/LAST-SIGKILL-137.log" \
        "$LOGDIR/ES-LAUNCH.log"; do
        [ -f "$auxiliary" ] && rm -f "$auxiliary"
    done
    for duplicate in "$LOGDIR"/*.multifile.log "$LOGDIR/native"/*.log; do
        [ -f "$duplicate" ] && rm -f "$duplicate"
    done
    rmdir "$LOGDIR/native" 2>/dev/null || true
    [ -d "$AUXDIR" ] && rm -rf "$AUXDIR" 2>/dev/null || true
}

append_diagnostic() {
    diagnostic="$1"
    title="$2"
    [ -f "$diagnostic" ] || return 0
    {
        echo
        echo "=== $title ==="
        cat "$diagnostic"
    } >> "$LOG"
}

cleanup_auxiliary_logs
mkdir -p "$AUXDIR" || exit 3
export RUFFLE_AUX_LOG_DIR="$AUXDIR"

{
    echo "Ruffle Handheld per-game log v0.8.35"
    echo "Game: $BASE"
    echo "Date: $(date 2>/dev/null || echo unavailable)"
    echo "Script: $0"
    echo "PWD: $PWD"
    printf 'Args:'
    for arg in "$@"; do printf ' <%s>' "$arg"; done
    echo
} > "$LOG"

FINALIZED=0
ENTRYPOINT_RC=""
finalize_log() {
    [ "$FINALIZED" -eq 0 ] || return 0
    FINALIZED=1
    if [ -n "$ENTRYPOINT_RC" ]; then
        echo "Entrypoint exit code: $ENTRYPOINT_RC" >> "$LOG"
    else
        echo "Entrypoint interrupted before returning an exit code" >> "$LOG"
    fi

    append_diagnostic "$AUXDIR/FLASH-EARLY.log" "Dispatcher and profile"
    append_diagnostic "$AUXDIR/input-helper.log" "Input helper"
    append_diagnostic "$AUXDIR/LAST-LAUNCH-MEMORY.log" "Memory report"
    append_diagnostic "$AUXDIR/LAST-SIGKILL-137.log" "Exit 137 report"
    cleanup_auxiliary_logs
}
on_exit() {
    rc=$?
    trap - EXIT
    finalize_log
    exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$BASH_BIN" "$RUNTIME_DIR/entrypoint.sh" "$@" >> "$LOG" 2>&1
RC=$?
ENTRYPOINT_RC="$RC"
exit "$RC"

#!/bin/bash
# Ruffle Handheld v0.8.17 EmulationStation boundary and per-game log adapter.

set -u
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 2
APP_DIR="$(dirname "$RUNTIME_DIR")"
LOGDIR="$APP_DIR/logs"
mkdir -p "$LOGDIR" || exit 3

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

{
    echo "Ruffle Handheld per-game log v0.8.17"
    echo "Game: $BASE"
    echo "Date: $(date 2>/dev/null || echo unavailable)"
    echo "Script: $0"
    echo "PWD: $PWD"
    printf 'Args:'
    for arg in "$@"; do printf ' <%s>' "$arg"; done
    echo
} > "$LOG"

/bin/bash "$RUNTIME_DIR/entrypoint.sh" "$@" >> "$LOG" 2>&1
RC=$?
echo "Entrypoint exit code: $RC" >> "$LOG"

append_diagnostic "$LOGDIR/FLASH-EARLY.log" "Dispatcher and profile"
append_diagnostic "$LOGDIR/input-helper.log" "Input helper"
append_diagnostic "$LOGDIR/LAST-LAUNCH-MEMORY.log" "Memory report"
append_diagnostic "$LOGDIR/LAST-SIGKILL-137.log" "Exit 137 report"
cleanup_auxiliary_logs
exit "$RC"

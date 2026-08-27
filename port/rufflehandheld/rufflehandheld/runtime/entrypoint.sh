#!/bin/bash
# Ruffle Handheld v0.8.17 path adapter.
# The v0.7.7 dispatcher and Native launchers remain byte-identical under core/.

set -u
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 2
APP_DIR="$(dirname "$RUNTIME_DIR")"
ROMROOT="${RUFFLE_ROM_ROOT:-}"

if [ "${1:-}" = "--rom-root" ]; then
    [ "$#" -ge 3 ] || { echo "ERROR: --rom-root requires a ROM root and SWF path"; exit 2; }
    ROMROOT="$2"
    shift 2
fi

if [ -z "$ROMROOT" ]; then
    PORTS_DIR="$(dirname "$APP_DIR")"
    case "$(basename "$PORTS_DIR")" in
        ports|ports_scripts) ROMROOT="$(dirname "$PORTS_DIR")" ;;
    esac
fi
[ -n "$ROMROOT" ] && [ -d "$ROMROOT" ] || { echo "ERROR: ROM root not found"; exit 2; }
ROMROOT="$(CDPATH= cd -- "$ROMROOT" 2>/dev/null && pwd -P)" || exit 2

SWF=""
for arg in "$@"; do
    case "$arg" in *.swf|*.SWF) [ -f "$arg" ] && { SWF="$arg"; break; } ;; esac
done
[ -n "$SWF" ] || { echo "ERROR: no existing SWF received"; exit 2; }

mkdir -p "$APP_DIR/logs" "$ROMROOT/flash" "$ROMROOT/flash_data" || exit 3

# A no-space view keeps LD_PRELOAD safe even when Ports or a game path contains
# spaces. It also presents the exact directory names expected by the frozen
# v0.7.7 scripts without creating implementation folders beside the user's ROMs.
LAYOUT="/tmp/ruffle_handheld_${UID:-0}_$$"
cleanup() {
    cd / 2>/dev/null || true
    rm -rf "$LAYOUT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
mkdir -p "$LAYOUT/flash_runtime/native_v020" \
    "$LAYOUT/flash_runtime/native_multifile" \
    "$LAYOUT/ports/ruffle_r36s/runtime" || exit 3

ln -s "$APP_DIR" "$LAYOUT/app" || exit 3
ln -s "$ROMROOT/flash" "$LAYOUT/flash" || exit 3
ln -s "$ROMROOT/flash_data" "$LAYOUT/flash_data" || exit 3
ln -s "$LAYOUT/app/profiles" "$LAYOUT/flash_profiles" || exit 3
ln -s "$LAYOUT/app/logs" "$LAYOUT/flash_runtime/logs" || exit 3
ln -s "$LAYOUT/app/runtime/core/launch.sh" "$LAYOUT/flash_runtime/launch.sh" || exit 3
ln -s "$LAYOUT/app/runtime/core/lib" "$LAYOUT/flash_runtime/lib" || exit 3
ln -s "$LAYOUT/app/runtime/native-adapter.sh" \
    "$LAYOUT/flash_runtime/native_v020/Ruffle-Native-Launch.sh" || exit 3
ln -s "$LAYOUT/app/runtime/multifile-adapter.sh" \
    "$LAYOUT/flash_runtime/native_multifile/Ruffle-Native-Multifile-Launch.sh" || exit 3

COMPAT="$LAYOUT/ports/ruffle_r36s"
ln -s "$LAYOUT/app/runtime/core/native_v020/ruffle-native.aarch64" \
    "$COMPAT/runtime/ruffle-native.aarch64" || exit 3
ln -s "$LAYOUT/app/runtime/core/native_multifile/ruffle-native-multifile.aarch64" \
    "$COMPAT/runtime/ruffle-native-multifile.aarch64" || exit 3
ln -s "$LAYOUT/app/runtime/core/native_v020/libruffle_cursorfix.aarch64.so" \
    "$COMPAT/runtime/libruffle_cursorfix.aarch64.so" || exit 3
ln -s "$LAYOUT/app/runtime/core/lib" "$COMPAT/lib" || exit 3
ln -s "$LAYOUT/app/logs" "$COMPAT/logs" || exit 3
ln -s "$ROMROOT/flash" "$COMPAT/games" || exit 3

export RUFFLE_APP_DIR="$LAYOUT/app"
export RUFFLE_ROM_ROOT="$ROMROOT"
export RUFFLE_COMPAT_GAMEDIR="$COMPAT"
export RUFFLE_DEFAULT_PROFILE="$LAYOUT/flash_profiles/default.profile"
export RUFFLE_FLASH_LOG="$LAYOUT/app/logs"
export RUFFLE_ADAPTER_TMP="$LAYOUT"

find_portmaster_control() {
    for candidate in \
        /opt/system/Tools/PortMaster/control.txt \
        /opt/tools/PortMaster/control.txt \
        "${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/PortMaster/control.txt" \
        "$ROMROOT/ports/PortMaster/control.txt" \
        "$ROMROOT/ports_scripts/PortMaster/control.txt" \
        /roms/ports/PortMaster/control.txt \
        /roms2/ports/PortMaster/control.txt \
        /storage/roms/ports/PortMaster/control.txt \
        /storage/roms2/ports/PortMaster/control.txt; do
        [ -f "$candidate" ] && return 0
    done
    return 1
}

if ! find_portmaster_control; then
    export RUFFLE_STANDALONE_DIRECTORY="${ROMROOT#/}"
    export RUFFLE_STANDALONE_ROMROOT="$ROMROOT"
    export XDG_DATA_HOME="$LAYOUT/app/runtime/standalone"
fi

MEMORY_LOG="$APP_DIR/logs/LAST-LAUNCH-MEMORY.log"
{
    echo "Ruffle Handheld launch memory report"
    echo "Date: $(date 2>/dev/null || echo unavailable)"
    echo "SWF: $SWF"
    echo "Phase: before launch"
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null || true
} > "$MEMORY_LOG"

/bin/bash "$LAYOUT/flash_runtime/launch.sh" "$@"
LAUNCH_RC=$?

{
    echo
    echo "Phase: after launch"
    echo "Exit code: $LAUNCH_RC"
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null || true
} >> "$MEMORY_LOG"

if [ "$LAUNCH_RC" -eq 137 ]; then
    SIGKILL_LOG="$APP_DIR/logs/LAST-SIGKILL-137.log"
    {
        echo "Ruffle Handheld exit 137 diagnostic"
        echo "Exit 137 means SIGKILL; this report does not assume the cause."
        echo "SWF: $SWF"
        echo
        cat "$MEMORY_LOG"
        echo
        echo "Recent kernel messages mentioning memory, kills or Ruffle:"
        dmesg 2>/dev/null | tail -n 250 | \
            grep -Ei 'out of memory|oom|killed process|memory cgroup|ruffle' || \
            echo "No matching kernel message was readable."
    } > "$SIGKILL_LOG"
fi

exit "$LAUNCH_RC"

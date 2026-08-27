#!/bin/bash
# Optional PortMaster integration. Ruffle Handheld still launches without it.

rh_find_control() {
    for p in \
        /opt/system/Tools/PortMaster/control.txt \
        /opt/tools/PortMaster/control.txt \
        "${XDG_DATA_HOME:-$HOME/.local/share}/PortMaster/control.txt" \
        "${RH_ROMROOT:-/roms}/ports/PortMaster/control.txt" \
        /roms/ports/PortMaster/control.txt \
        /roms2/ports/PortMaster/control.txt \
        /storage/roms/ports/PortMaster/control.txt \
        /storage/roms2/ports/PortMaster/control.txt; do
        [ -f "$p" ] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

rh_platform_init() {
    RH_CONTROL="$(rh_find_control 2>/dev/null || true)"
    [ -n "$RH_CONTROL" ] || return 0
    RH_CONTROLFOLDER="$(dirname "$RH_CONTROL")"
    # shellcheck disable=SC1090
    source "$RH_CONTROL" 2>/dev/null || return 0
    [ -n "${CFW_NAME:-}" ] && [ -f "$RH_CONTROLFOLDER/mod_${CFW_NAME}.txt" ] && source "$RH_CONTROLFOLDER/mod_${CFW_NAME}.txt" 2>/dev/null || true
    type get_controls >/dev/null 2>&1 && get_controls >/dev/null 2>&1 || true
}

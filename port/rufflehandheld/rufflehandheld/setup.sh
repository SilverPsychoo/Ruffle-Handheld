#!/bin/bash
# Ruffle Handheld v0.8.27 offline installer wrapper.

VERSION="0.8.27"
APP_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)"
PORTS_DIR="${1:-$(dirname "$APP_DIR")}" 
PORTS_DIR="$(CDPATH= cd -- "$PORTS_DIR" 2>/dev/null && pwd -P)" || {
    echo "ERROR: cannot resolve the Ports directory: $PORTS_DIR"
    exit 1
}
CORE_INSTALLER="$APP_DIR/core-install.sh"
BASH_BIN="${RUFFLE_BASH:-${BASH:-/bin/bash}}"
export RUFFLE_BASH="$BASH_BIN"
INSTALL_STATE="/tmp/ruffle_handheld_install_${UID:-0}_$$"
mkdir -p "$INSTALL_STATE" || exit 1
cleanup_install_state() { rm -rf "$INSTALL_STATE" 2>/dev/null || true; }
trap cleanup_install_state EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

die() { echo "ERROR: $*"; exit 1; }

# NextUI/MinUI launches regular PortMaster scripts through PORTS.pak. Detect
# that environment before reading control.txt: its patched `directory` points
# at a temporary bind mount, not at the real SD-card ROM root.
NEXTUI_SD=""
NEXTUI_PLATFORM=""
if [ -n "${SDCARD_PATH:-}" ] && [ -d "$SDCARD_PATH/Roms" ] && [ -n "${PLATFORM:-}" ]; then
    if [ -d "$SDCARD_PATH/Emus/$PLATFORM/PORTS.pak" ]; then
        NEXTUI_SD="$SDCARD_PATH"
        NEXTUI_PLATFORM="$PLATFORM"
    fi
fi
if [ -z "$NEXTUI_SD" ]; then
    case "${PAK_DIR:-}" in
        */Emus/*/PORTS.pak)
            NEXTUI_PLATFORM="$(basename "$(dirname "$PAK_DIR")")"
            NEXTUI_SD="$(dirname "$(dirname "$(dirname "$PAK_DIR")")")"
            [ -d "$NEXTUI_SD/Roms" ] || { NEXTUI_SD=""; NEXTUI_PLATFORM=""; }
            ;;
    esac
fi
IS_NEXTUI=0
[ -n "$NEXTUI_SD" ] && [ -n "$NEXTUI_PLATFORM" ] && IS_NEXTUI=1

find_portmaster_control() {
    for candidate in \
        "${NEXTUI_SD:+$NEXTUI_SD/Emus/$NEXTUI_PLATFORM/PORTS.pak/PortMaster/control.txt}" \
        "$PORTS_DIR/PortMaster/control.txt" \
        "$(dirname "$PORTS_DIR")/ports/PortMaster/control.txt" \
        /opt/system/Tools/PortMaster/control.txt \
        /opt/tools/PortMaster/control.txt \
        "${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/PortMaster/control.txt" \
        /roms/ports/PortMaster/control.txt \
        /roms2/ports/PortMaster/control.txt \
        /storage/roms/ports/PortMaster/control.txt \
        /storage/roms2/ports/PortMaster/control.txt; do
        [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

root_from_ports_path() {
    cursor="$1"; depth=0
    while [ "$depth" -lt 4 ]; do
        case "$(basename "$cursor")" in
            ports|ports_scripts) dirname "$cursor"; return 0 ;;
        esac
        parent="$(dirname "$cursor")"
        [ "$parent" = "$cursor" ] && break
        cursor="$parent"; depth=$((depth + 1))
    done
    return 1
}

PM_CONTROL="$(find_portmaster_control 2>/dev/null || true)"
CFW_NAME="${RUFFLE_CFW_NAME:-}"
CFW_VERSION=""
PM_ROMROOT=""
if [ -n "$PM_CONTROL" ]; then
    PM_INFO="$(
        controlfolder="$(dirname "$PM_CONTROL")"
        # shellcheck disable=SC1090
        source "$PM_CONTROL" >/dev/null 2>&1 || true
        printf '%s\n%s\n%s\n' "${directory:-}" "${CFW_NAME:-}" "${CFW_VERSION:-}"
    )"
    PM_DIRECTORY="$(printf '%s\n' "$PM_INFO" | sed -n '1p')"
    [ -n "$CFW_NAME" ] || CFW_NAME="$(printf '%s\n' "$PM_INFO" | sed -n '2p')"
    CFW_VERSION="$(printf '%s\n' "$PM_INFO" | sed -n '3p')"
    if [ -n "$PM_DIRECTORY" ]; then
        case "$PM_DIRECTORY" in /*) PM_ROMROOT="$PM_DIRECTORY" ;; *) PM_ROMROOT="/$PM_DIRECTORY" ;; esac
    fi
fi

PATH_ROMROOT="$(root_from_ports_path "$PORTS_DIR" 2>/dev/null || true)"
if [ -n "${RUFFLE_ROM_ROOT:-}" ]; then
    ROMROOT="$RUFFLE_ROM_ROOT"; DETECT_METHOD="explicit RUFFLE_ROM_ROOT"
elif [ "$IS_NEXTUI" -eq 1 ]; then
    ROMROOT="$NEXTUI_SD/Roms"; DETECT_METHOD="NextUI PORTS.pak environment"
elif [ -n "$PM_ROMROOT" ] && [ -d "$PM_ROMROOT" ]; then
    ROMROOT="$PM_ROMROOT"; DETECT_METHOD="PortMaster control.txt"
elif [ -n "$PATH_ROMROOT" ]; then
    ROMROOT="$PATH_ROMROOT"; DETECT_METHOD="Ports path"
else
    die "cannot locate the ROM root from '$PORTS_DIR'"
fi
ROMROOT="$(CDPATH= cd -- "$ROMROOT" 2>/dev/null && pwd -P)" || die "ROM root does not exist: $ROMROOT"
case "$ROMROOT" in /|"${HOME:-/nonexistent}") die "refusing unsafe ROM root: $ROMROOT" ;; esac

OS_RELEASE=""
[ -f /etc/os-release ] && OS_RELEASE="$(sed -n 's/^\(ID\|NAME\|PRETTY_NAME\)=//p' /etc/os-release | tr -d '"' | tr '\n' ' ')"
if [ "$IS_NEXTUI" -eq 1 ]; then
    CFW_NAME="NextUI"
elif [ -z "$CFW_NAME" ]; then
    CFW_HINT="$(printf '%s' "$OS_RELEASE" | tr '[:upper:]' '[:lower:]')"
    if [ -f /storage/.config/EE_VERSION ] || [ -f /usr/bin/emustation-config ]; then
        CFW_NAME="EmuELEC"
    else
        case "$CFW_HINT" in
            *emuelec*) CFW_NAME="EmuELEC" ;;
            *arkos*|*darkos*) CFW_NAME="ArkOS/dArkOS" ;;
            *rocknix*) CFW_NAME="ROCKNIX" ;;
            *amberelec*|*351elec*) CFW_NAME="AmberELEC" ;;
            *muos*) CFW_NAME="muOS" ;;
            *knulli*) CFW_NAME="Knulli" ;;
            *batocera*) CFW_NAME="Batocera/Knulli-compatible" ;;
            *) CFW_NAME="${OS_RELEASE:-unknown}" ;;
        esac
    fi
fi
[ -n "$CFW_NAME" ] || CFW_NAME="unknown"

ARCH="${RUFFLE_ARCH:-$(uname -m 2>/dev/null || echo unknown)}"
case "$(printf '%s' "$ARCH" | tr '[:upper:]' '[:lower:]')" in
    aarch64|arm64) ;;
    *) die "the bundled runtime is ARM64/aarch64; detected architecture: $ARCH" ;;
esac

FRONTEND="none detected"
if [ "$IS_NEXTUI" -eq 1 ]; then
    FRONTEND="NextUI/MinUI PAK frontend"
elif command -v pidof >/dev/null 2>&1 && { pidof emulationstation >/dev/null 2>&1 || pidof emulationstation-oga >/dev/null 2>&1 || pidof emustation >/dev/null 2>&1; }; then
    FRONTEND="EmulationStation (running)"
elif command -v emulationstation >/dev/null 2>&1; then
    FRONTEND="EmulationStation (installed)"
elif [ -n "${RUFFLE_ES_CONFIG:-}" ] || find /storage /userdata "${HOME:-/tmp}" -maxdepth 4 -name es_systems.cfg -type f 2>/dev/null | head -1 | grep -q .; then
    FRONTEND="EmulationStation configuration detected"
fi

echo "=== Ruffle Handheld v$VERSION offline installer ==="
echo "Application: $APP_DIR"
echo "Ports: $PORTS_DIR"
echo "ROM root: $ROMROOT ($DETECT_METHOD)"
echo "Architecture: $ARCH"
echo "CFW: $CFW_NAME ${CFW_VERSION:-}"
echo "Frontend: $FRONTEND"
[ -n "$PM_CONTROL" ] && echo "PortMaster adapter: $PM_CONTROL" || echo "PortMaster adapter: bundled offline fallback"
echo "Network: not used; the selected ARM64 runtime is bundled"
echo

[ -f "$APP_DIR/runtime/core/launch.sh" ] || die "bundled runtime missing"
[ -f "$APP_DIR/profiles/default.profile" ] || die "bundled profiles missing"
[ -f "$CORE_INSTALLER" ] || die "core installer missing"

echo "[1/3] Registering the known-good v0.7.7 core from its clean internal layout..."
NEXTUI_PERSISTENT_APP="$APP_DIR"
if [ "$IS_NEXTUI" -eq 1 ]; then
    LAUNCH_DIR="${RUFFLE_LAUNCH_DIR:-}"
    if [ -n "$LAUNCH_DIR" ] && [ -d "$LAUNCH_DIR/.ports/rufflehandheld" ]; then
        NEXTUI_PERSISTENT_APP="$LAUNCH_DIR/.ports/rufflehandheld"
    elif [ -n "$LAUNCH_DIR" ] && [ -d "$LAUNCH_DIR/rufflehandheld" ]; then
        NEXTUI_PERSISTENT_APP="$LAUNCH_DIR/rufflehandheld"
    fi
fi
RUFFLE_INSTALL_STATE_DIR="$INSTALL_STATE" \
RUFFLE_NEXTUI_SD="$NEXTUI_SD" \
RUFFLE_NEXTUI_PLATFORM="$NEXTUI_PLATFORM" \
RUFFLE_NEXTUI_APP_DIR="$NEXTUI_PERSISTENT_APP" \
    "$BASH_BIN" "$CORE_INSTALLER" "$ROMROOT" "$APP_DIR" "$CFW_NAME" || die "core installer failed with code $?"
sync

frontend_pid() {
    if command -v pidof >/dev/null 2>&1; then
        for process_name in emulationstation emulationstation-oga emustation; do
            detected_pid="$(pidof "$process_name" 2>/dev/null | awk '{print $1}')"
            [ -n "$detected_pid" ] && { printf '%s\n' "$detected_pid"; return 0; }
        done
    fi
    if command -v pgrep >/dev/null 2>&1; then
        for process_name in emulationstation emulationstation-oga emustation; do
            detected_pid="$(pgrep -x "$process_name" 2>/dev/null | head -1)"
            [ -n "$detected_pid" ] && { printf '%s\n' "$detected_pid"; return 0; }
        done
    fi
    return 1
}

systemctl_query() {
    command -v systemctl >/dev/null 2>&1 || return 127
    systemctl "$@" 2>/dev/null && return 0
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n systemctl "$@" 2>/dev/null
}

systemctl_action() {
    command -v systemctl >/dev/null 2>&1 || return 127
    systemctl "$@" >/dev/null 2>&1 && return 0
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n systemctl "$@" >/dev/null 2>&1
}

service_exists() {
    unit="$1"
    load_state="$(systemctl_query show "$unit" -p LoadState --value 2>/dev/null || true)"
    case "$load_state" in loaded|masked) return 0 ;; esac
    return 1
}

service_main_pid() {
    unit="$1"
    systemctl_query show "$unit" -p MainPID --value 2>/dev/null | sed -n '1p'
}

service_is_active() {
    unit="$1"
    systemctl_action is-active --quiet "$unit"
}

restart_service_adapter() {
    adapter_name="$1"; shift
    old_frontend_pid="$(frontend_pid 2>/dev/null || true)"
    for unit in "$@"; do
        service_exists "$unit" || continue
        old_service_pid="$(service_main_pid "$unit")"
        echo "  $adapter_name adapter: $unit (old PID: ${old_service_pid:-${old_frontend_pid:-not visible}})"
        if ! systemctl_action restart "$unit"; then
            echo "  WARNING: restart failed for $unit."
            continue
        fi
        checks=0
        while [ "$checks" -lt 12 ]; do
            new_service_pid="$(service_main_pid "$unit")"
            new_frontend_pid="$(frontend_pid 2>/dev/null || true)"
            if service_is_active "$unit"; then
                if { [ -n "$old_service_pid" ] && [ "$old_service_pid" != "0" ] && [ -n "$new_service_pid" ] && [ "$new_service_pid" != "0" ] && [ "$new_service_pid" != "$old_service_pid" ]; } || \
                   { [ -n "$old_frontend_pid" ] && [ -n "$new_frontend_pid" ] && [ "$new_frontend_pid" != "$old_frontend_pid" ]; } || \
                   { [ -z "$old_service_pid" ] && [ -z "$old_frontend_pid" ]; }; then
                    echo "  EmulationStation reload verified (service: $unit, PID: ${new_service_pid:-${new_frontend_pid:-active}})."
                    return 0
                fi
            fi
            sleep 1
            checks=$((checks + 1))
        done
        echo "  WARNING: $unit returned but a new frontend process was not verified."
    done
    return 1
}

restart_process_fallback() {
    old_pid="$(frontend_pid 2>/dev/null || true)"
    [ -n "$old_pid" ] || return 1
    echo "  Fallback: requesting a clean EmulationStation exit (old PID: $old_pid)."
    kill -TERM "$old_pid" 2>/dev/null || return 1
    checks=0
    while [ "$checks" -lt 12 ]; do
        new_pid="$(frontend_pid 2>/dev/null || true)"
        if [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ]; then
            echo "  EmulationStation reload verified by process replacement (PID: $new_pid)."
            return 0
        fi
        sleep 1
        checks=$((checks + 1))
    done
    echo "  WARNING: the frontend process did not restart automatically."
    return 1
}

restart_batocera_es() {
    command -v batocera-es-swissknife >/dev/null 2>&1 || return 1
    old_pid="$(frontend_pid 2>/dev/null || true)"
    echo "  Knulli/Batocera adapter: batocera-es-swissknife --restart"
    batocera-es-swissknife --restart >/dev/null 2>&1 || return 1
    checks=0
    while [ "$checks" -lt 12 ]; do
        new_pid="$(frontend_pid 2>/dev/null || true)"
        if [ -n "$new_pid" ] && { [ -z "$old_pid" ] || [ "$new_pid" != "$old_pid" ]; }; then
            echo "  EmulationStation reload verified (PID: $new_pid)."
            return 0
        fi
        sleep 1
        checks=$((checks + 1))
    done
    return 1
}

echo "[2/3] Reloading the frontend..."
RELOAD_OK=0
if [ "${RUFFLE_SKIP_RESTART:-0}" = "1" ]; then
    echo "  Reload skipped by test/maintenance environment."
    RELOAD_OK=1
else
    case "$(printf '%s' "$CFW_NAME" | tr '[:upper:]' '[:lower:]')" in
        *emuelec*)
            restart_service_adapter "EmuELEC" emustation.service emulationstation.service || \
                restart_process_fallback
            [ "$?" -eq 0 ] && RELOAD_OK=1
            ;;
        *arkos*|*darkos*)
            restart_service_adapter "ArkOS/dArkOS" emulationstation.service emustation.service || \
                restart_process_fallback
            [ "$?" -eq 0 ] && RELOAD_OK=1
            ;;
        *amberelec*|*351elec*)
            restart_service_adapter "AmberELEC" emustation.service emulationstation.service || \
                restart_process_fallback
            [ "$?" -eq 0 ] && RELOAD_OK=1
            ;;
        *rocknix*)
            # ROCKNIX runs EmulationStation as essway.service beneath the Sway
            # compositor. Reload ES itself first; do not restart all of Sway.
            restart_service_adapter "ROCKNIX" essway.service emustation.service emulationstation.service || \
                restart_process_fallback
            [ "$?" -eq 0 ] && RELOAD_OK=1
            ;;
        *knulli*|*batocera*)
            restart_batocera_es || \
                restart_service_adapter "Knulli/Batocera" emulationstation.service emustation.service || \
                restart_process_fallback
            [ "$?" -eq 0 ] && RELOAD_OK=1
            ;;
        *nextui*) echo "  NextUI will rescan the new Flash PAK after returning to the menu."; RELOAD_OK=1 ;;
        *) echo "  No verified reload adapter for '$CFW_NAME'; restart the frontend manually." ;;
    esac
fi

echo "[3/3] Verifying the active frontend integration..."
if [ -e "$ROMROOT/flash_runtime" ]; then
    die "the obsolete root-level flash_runtime directory still exists"
fi

case "$(printf '%s' "$CFW_NAME" | tr '[:upper:]' '[:lower:]')" in
    *nextui*)
        NEXTUI_PAK_RECORD="$INSTALL_STATE/nextui-pak.path"
        [ -f "$NEXTUI_PAK_RECORD" ] || die "the installer did not record the NextUI Flash PAK"
        NEXTUI_PAK="$(sed -n '1p' "$NEXTUI_PAK_RECORD")"
        [ -f "$NEXTUI_PAK/launch.sh" ] || die "the NextUI Flash PAK launcher is missing"
        [ -f "$NEXTUI_PAK/ruffle-app.path" ] || die "the NextUI application pointer is missing"
        [ -d "$ROMROOT/Flash (FLASH)" ] || die "the NextUI Flash ROM folder is missing"
        grep -F 'runtime/es-launch.sh' "$NEXTUI_PAK/launch.sh" >/dev/null 2>&1 || \
            die "the NextUI Flash PAK does not call the launch bridge"
        ;;
    *emuelec*)
        ES_CONFIG_RECORD="$INSTALL_STATE/es-config.path"
        [ -f "$ES_CONFIG_RECORD" ] || die "the installer did not record the active EmulationStation configuration"
        ES_CONFIG="$(sed -n '1p' "$ES_CONFIG_RECORD")"
        [ -n "$ES_CONFIG" ] && [ -f "$ES_CONFIG" ] || die "the recorded EmulationStation configuration is missing: $ES_CONFIG"
        FLASH_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$ES_CONFIG" 2>/dev/null || true)"
        [ "$FLASH_COUNT" = "1" ] || die "the active EmulationStation configuration contains $FLASH_COUNT Flash entries"
        grep -F "$APP_DIR/runtime/es-launch.sh" "$ES_CONFIG" >/dev/null 2>&1 || \
            die "the active Flash command does not point to the installed launch bridge"
        DROPIN_RECORD="$INSTALL_STATE/es-dropins.paths"
        [ -s "$DROPIN_RECORD" ] || die "the installer did not record the EmuELEC Flash drop-ins"
        while IFS= read -r DROPIN; do
            [ -f "$DROPIN" ] || die "an EmuELEC Flash drop-in disappeared after reload: $DROPIN"
            DROPIN_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$DROPIN" 2>/dev/null || true)"
            [ "$DROPIN_COUNT" = "1" ] || die "the EmuELEC drop-in contains $DROPIN_COUNT Flash entries: $DROPIN"
            grep -F "$APP_DIR/runtime/es-launch.sh" "$DROPIN" >/dev/null 2>&1 || \
                die "the EmuELEC drop-in points to the wrong launch route: $DROPIN"
        done < "$DROPIN_RECORD"
        ;;
    *)
        ES_CONFIG_RECORD="$INSTALL_STATE/es-config.path"
        [ -f "$ES_CONFIG_RECORD" ] || die "the installer did not record the active EmulationStation configuration"
        ES_CONFIG="$(sed -n '1p' "$ES_CONFIG_RECORD")"
        [ -n "$ES_CONFIG" ] && [ -f "$ES_CONFIG" ] || die "the recorded EmulationStation configuration is missing: $ES_CONFIG"
        FLASH_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$ES_CONFIG" 2>/dev/null || true)"
        [ "$FLASH_COUNT" = "1" ] || die "the active EmulationStation configuration contains $FLASH_COUNT Flash entries"
        grep -F "$APP_DIR/runtime/es-launch.sh" "$ES_CONFIG" >/dev/null 2>&1 || \
            die "the active Flash command does not point to the installed launch bridge"
        DEDUP_RECORD="$INSTALL_STATE/es-deduplicated.paths"
        if [ -s "$DEDUP_RECORD" ]; then
            while IFS= read -r DEDUP_CFG; do
                DEDUP_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$DEDUP_CFG" 2>/dev/null || true)"
                [ "$DEDUP_COUNT" = "0" ] || die "a stale configuration still contains $DEDUP_COUNT Flash entries: $DEDUP_CFG"
            done < "$DEDUP_RECORD"
        fi
        ;;
esac

echo "Installation verified."
if [ "$IS_NEXTUI" -eq 1 ]; then
    echo "Games: $ROMROOT/Flash (FLASH)"
else
    echo "Games: $ROMROOT/flash"
fi
echo "Multi-file data: $ROMROOT/flash_data"
echo "Runtime: $APP_DIR/runtime"
echo "Control profiles: $APP_DIR/profiles"
echo "Visual profile maker: $APP_DIR/profile-maker.html"
echo "Per-game logs: $APP_DIR/logs"
if [ "$RELOAD_OK" -eq 1 ]; then
    echo "Frontend status: ready/reload requested successfully."
else
    echo "Frontend status: installation complete; manual frontend restart required."
fi
exit 0

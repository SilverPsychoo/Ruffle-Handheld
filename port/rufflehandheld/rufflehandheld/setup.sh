#!/bin/bash
# Ruffle Handheld v0.8.17 offline installer wrapper.

VERSION="0.8.17"
APP_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)"
PORTS_DIR="${1:-$(dirname "$APP_DIR")}" 
PORTS_DIR="$(CDPATH= cd -- "$PORTS_DIR" 2>/dev/null && pwd -P)" || {
    echo "ERROR: cannot resolve the Ports directory: $PORTS_DIR"
    exit 1
}
CORE_INSTALLER="$APP_DIR/core-install.sh"
INSTALL_STATE="/tmp/ruffle_handheld_install_${UID:-0}_$$"
mkdir -p "$INSTALL_STATE" || exit 1
cleanup_install_state() { rm -rf "$INSTALL_STATE" 2>/dev/null || true; }
trap cleanup_install_state EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

die() { echo "ERROR: $*"; exit 1; }

find_portmaster_control() {
    for candidate in \
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
if [ -z "$CFW_NAME" ]; then
    CFW_HINT="$(printf '%s' "$OS_RELEASE" | tr '[:upper:]' '[:lower:]')"
    if [ -f /storage/.config/EE_VERSION ] || [ -f /usr/bin/emustation-config ]; then
        CFW_NAME="EmuELEC"
    else
        case "$CFW_HINT" in
            *emuelec*) CFW_NAME="EmuELEC" ;;
            *arkos*) CFW_NAME="ArkOS" ;;
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
if command -v pidof >/dev/null 2>&1 && pidof emulationstation >/dev/null 2>&1; then
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
RUFFLE_INSTALL_STATE_DIR="$INSTALL_STATE" \
    /bin/bash "$CORE_INSTALLER" "$ROMROOT" "$APP_DIR" "$CFW_NAME" || die "core installer failed with code $?"
sync

frontend_pid() {
    if command -v pidof >/dev/null 2>&1; then
        pidof emulationstation 2>/dev/null | awk '{print $1}'
    elif command -v pgrep >/dev/null 2>&1; then
        pgrep -x emulationstation 2>/dev/null | head -1
    fi
}

restart_emuelec_es() {
    old_pid="$(frontend_pid)"
    echo "  EmuELEC adapter: emustation.service (old PID: ${old_pid:-not visible})"
    command -v systemctl >/dev/null 2>&1 || { echo "  WARNING: systemctl is unavailable."; return 1; }
    if ! systemctl restart emustation.service >/dev/null 2>&1; then
        echo "  WARNING: emustation.service restart failed."
        if [ -n "$old_pid" ] && kill -TERM "$old_pid" 2>/dev/null; then
            echo "  Fallback: requested a clean EmulationStation exit."
        else
            return 1
        fi
    fi
    checks=0
    while [ "$checks" -lt 12 ]; do
        new_pid="$(frontend_pid)"
        if systemctl is-active --quiet emustation.service 2>/dev/null; then
            if [ -z "$old_pid" ] || [ -z "$new_pid" ] || [ "$new_pid" != "$old_pid" ]; then
                echo "  EmulationStation reload verified (PID: ${new_pid:-service active})."
                return 0
            fi
        fi
        sleep 1
        checks=$((checks + 1))
    done
    echo "  WARNING: reload could not be verified."
    return 1
}

echo "[2/3] Reloading the frontend..."
RELOAD_OK=0
if [ "${RUFFLE_SKIP_RESTART:-0}" = "1" ]; then
    echo "  Reload skipped by test/maintenance environment."
    RELOAD_OK=1
else
    case "$(printf '%s' "$CFW_NAME" | tr '[:upper:]' '[:lower:]')" in
        *emuelec*) restart_emuelec_es && RELOAD_OK=1 ;;
        *) echo "  No verified reload adapter for '$CFW_NAME'; restart the frontend manually." ;;
    esac
fi

echo "[3/3] Verifying the active EmulationStation configuration..."
ES_CONFIG_RECORD="$INSTALL_STATE/es-config.path"
[ -f "$ES_CONFIG_RECORD" ] || die "the installer did not record the active EmulationStation configuration"
ES_CONFIG="$(sed -n '1p' "$ES_CONFIG_RECORD")"
[ -n "$ES_CONFIG" ] && [ -f "$ES_CONFIG" ] || die "the recorded EmulationStation configuration is missing: $ES_CONFIG"
FLASH_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$ES_CONFIG" 2>/dev/null || true)"
[ "$FLASH_COUNT" = "1" ] || die "the active EmulationStation configuration contains $FLASH_COUNT Flash entries"
EXPECTED_ES_SCRIPT="$APP_DIR/runtime/es-launch.sh"
grep -F "$EXPECTED_ES_SCRIPT" "$ES_CONFIG" >/dev/null 2>&1 || \
    die "the active Flash command does not point to the installed launch bridge"
if [ -e "$ROMROOT/flash_runtime" ]; then
    die "the obsolete root-level flash_runtime directory still exists"
fi

case "$(printf '%s' "$CFW_NAME" | tr '[:upper:]' '[:lower:]')" in
    *emuelec*)
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
esac

echo "Installation verified."
echo "Games: $ROMROOT/flash"
echo "Multi-file data: $ROMROOT/flash_data"
echo "Runtime: $APP_DIR/runtime"
echo "Control profiles: $APP_DIR/profiles"
echo "Per-game logs: $APP_DIR/logs"
if [ "$RELOAD_OK" -eq 1 ]; then
    echo "Frontend status: ready/reload requested successfully."
else
    echo "Frontend status: installation complete; manual frontend restart required."
fi
exit 0

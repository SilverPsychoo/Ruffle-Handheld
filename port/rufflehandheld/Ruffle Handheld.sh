#!/bin/bash
# Ruffle Handheld v0.8.26 universal installer/repair launcher.
# Some CFWs export PortMaster launchers to ports_scripts while keeping the
# application data in ports. Resolve the complete application, not merely a
# same-named directory which may contain only stale logs.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 1

valid_app_dir() {
    candidate="$1"
    [ -f "$candidate/setup.sh" ] &&
    [ -f "$candidate/core-install.sh" ] &&
    [ -f "$candidate/runtime/entrypoint.sh" ] &&
    [ -f "$candidate/runtime/core/launch.sh" ] &&
    [ -f "$candidate/profiles/default.profile" ]
}

ROMROOT_HINT=""
case "$(basename "$SCRIPT_DIR")" in
    ports|ports_scripts) ROMROOT_HINT="$(dirname "$SCRIPT_DIR")" ;;
esac

APP_DIR=""
for candidate in \
    "${ROMROOT_HINT:+$ROMROOT_HINT/ports/rufflehandheld}" \
    "$SCRIPT_DIR/rufflehandheld" \
    "${ROMROOT_HINT:+$ROMROOT_HINT/ports_scripts/rufflehandheld}" \
    /storage/roms/ports/rufflehandheld \
    /storage/roms2/ports/rufflehandheld \
    /roms/ports/rufflehandheld \
    /roms2/ports/rufflehandheld \
    /storage/roms/ports_scripts/rufflehandheld \
    /roms/ports_scripts/rufflehandheld; do
    [ -n "$candidate" ] || continue
    if valid_app_dir "$candidate"; then
        APP_DIR="$(CDPATH= cd -- "$candidate" 2>/dev/null && pwd -P)" || exit 1
        break
    fi
done

if [ -z "$APP_DIR" ]; then
    echo "Ruffle Handheld setup files were not found."
    echo "Checked complete installations under both ports/ and ports_scripts/."
    echo "On EmuELEC put this .sh in ports_scripts/ and the rufflehandheld folder in ports/."
    exit 1
fi

PORTS_DIR="$(dirname "$APP_DIR")"
echo "Ruffle Handheld application resolved at: $APP_DIR"
exec /bin/bash "$APP_DIR/setup.sh" "$PORTS_DIR"

#!/bin/bash
PORTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PORTDIR="$PORTS_DIR/rufflehandheld"
[ -f "$PORTDIR/runtime/setup.sh" ] || exit 1
/bin/bash "$PORTDIR/runtime/setup.sh"

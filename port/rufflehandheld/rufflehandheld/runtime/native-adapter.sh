#!/bin/bash
# Path-only adapter for the byte-identical v0.7.7 Native launcher.

set -u
CORE="${RUFFLE_APP_DIR:?}/runtime/core/native_v020/Ruffle-Native-Launch.sh"
TMP="${RUFFLE_ADAPTER_TMP:-/tmp}/native-launch-$$.sh"
[ -f "$CORE" ] || { echo "ERROR: known-good Native launcher missing"; exit 3; }

awk '
    /^GAMEDIR=/ && !gamedir { print "GAMEDIR=\"${RUFFLE_COMPAT_GAMEDIR:?}\""; gamedir=1; next }
    /^DEFAULT_PROFILE=/ && !profile { print "DEFAULT_PROFILE=\"${RUFFLE_DEFAULT_PROFILE:?}\""; profile=1; next }
    { print }
' "$CORE" > "$TMP" || exit 4
chmod +x "$TMP" || exit 4
/bin/bash "$TMP" "$@"
exit $?

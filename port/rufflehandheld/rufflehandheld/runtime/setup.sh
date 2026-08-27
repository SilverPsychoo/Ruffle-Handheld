#!/bin/bash
RUNTIME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
PORTDIR="$(dirname "$RUNTIME_DIR")"; PORTS_DIR="$(dirname "$PORTDIR")"; ROMROOT="$(dirname "$PORTS_DIR")"
# shellcheck disable=SC1090
source "$RUNTIME_DIR/platform.sh" 2>/dev/null || true
RH_ROMROOT="$ROMROOT"; export RH_ROMROOT; rh_platform_init 2>/dev/null || true
if [ -n "${directory:-}" ] && [ -d "/$directory" ]; then ROMROOT="/$directory"; fi
FLASHDIR="$ROMROOT/flash"; DATADIR="$ROMROOT/flash_data"
mkdir -p "$FLASHDIR" "$DATADIR" "$PORTDIR/logs" || exit 2

THEME=arcade; THEMESET=""
for settings in "$HOME/.emulationstation/es_settings.cfg" "$HOME/.config/emulationstation/es_settings.cfg" /storage/.emulationstation/es_settings.cfg /storage/.config/emulationstation/es_settings.cfg; do
    [ -f "$settings" ] || continue
    THEMESET="$(sed -n 's/.*<string name="ThemeSet" value="\([^"]*\)".*/\1/p' "$settings" | head -1)"
    [ -n "$THEMESET" ] && break
done
if [ -n "$THEMESET" ]; then
    for root in "$HOME/.emulationstation/themes" "$HOME/.config/emulationstation/themes" /storage/.emulationstation/themes /storage/.config/emulationstation/themes /etc/emulationstation/themes; do
        [ -f "$root/$THEMESET/flash/theme.xml" ] && { THEME=flash; break; }
    done
fi

SNIPPET="/tmp/ruffle_handheld_system_$$.xml"
cat > "$SNIPPET" <<EOF
  <system>
    <name>flash</name>
    <fullname>Flash Games</fullname>
    <path>$FLASHDIR</path>
    <extension>.swf .SWF</extension>
    <command>/bin/bash $PORTDIR/runtime/launch.sh "%ROM%"</command>
    <platform>flash</platform>
    <theme>$THEME</theme>
  </system>
EOF

patch_main() {
    file="$1"; [ -f "$file" ] && [ -w "$file" ] || return 1
    tmp="$file.rufflehandheld.tmp"
    awk '
      /<system>/ { in_system=1; block=$0 ORS; next }
      in_system { block=block $0 ORS; if (/<\/system>/) { if (block !~ /<name>[[:space:]]*flash[[:space:]]*<\/name>/) printf "%s", block; in_system=0; block="" } next }
      /<\/systemList>/ { while ((getline l < snip) > 0) print l; close(snip); print; next }
      { print }
    ' snip="$SNIPPET" "$file" > "$tmp" && mv "$tmp" "$file"
}

installed=0
for file in "$HOME/.emulationstation/es_systems.cfg" "$HOME/.config/emulationstation/es_systems.cfg" /storage/.emulationstation/es_systems.cfg /storage/.config/emulationstation/es_systems.cfg; do
    if patch_main "$file"; then installed=1; break; fi
done
if [ "$installed" -eq 0 ]; then
    for dir in "$HOME/.emulationstation" "$HOME/.config/emulationstation" /storage/.emulationstation /storage/.config/emulationstation; do
        [ -d "$dir" ] || continue
        cat > "$dir/es_systems_flash.cfg" <<EOF
<?xml version="1.0"?>
<systemList>
$(cat "$SNIPPET")
</systemList>
EOF
        installed=1; break
    done
fi
rm -f "$SNIPPET"

cat > "$PORTDIR/setup-info.txt" <<EOF
Ruffle Handheld setup completed.
Games: $FLASHDIR
Multi-file data: $DATADIR
Profiles: $PORTDIR/profiles
Theme entry: $THEME
Restart EmulationStation if the Flash system is not visible yet.
EOF

touch "$PORTDIR/.setup-complete"
echo "Ruffle Handheld setup completed."
echo "Games: $FLASHDIR"
echo "Multi-file data: $DATADIR"
echo "Restart EmulationStation if Flash is not visible yet."
type pm_finish >/dev/null 2>&1 && pm_finish

#!/bin/bash
# Ruffle Handheld v0.8.27 core installer.
# Registers the frozen v0.7.7 core in-place inside the Ruffle Handheld bundle.

ROMROOT="$1"
APP_DIR="$2"
CFW_NAME="${3:-unknown}"
[ -n "$ROMROOT" ] && [ -d "$ROMROOT" ] || { echo "ERROR: invalid ROM root"; exit 2; }
[ -d "$APP_DIR/runtime/core" ] || { echo "ERROR: bundled runtime missing"; exit 3; }
[ -f "$APP_DIR/profiles/default.profile" ] || { echo "ERROR: bundled profiles missing"; exit 4; }

CFW_KEY="$(printf '%s' "$CFW_NAME" | tr '[:upper:]' '[:lower:]')"
case "$CFW_KEY" in
    *nextui*) FLASHDIR="$ROMROOT/Flash (FLASH)" ;;
    *) FLASHDIR="$ROMROOT/flash" ;;
esac
DATADIR="$ROMROOT/flash_data"
PROFILEDIR="$APP_DIR/profiles"
ENGINE="$APP_DIR/runtime"
LOGDIR="$APP_DIR/logs"
MIGRATED="$APP_DIR/migrated"
STATE_DIR="${RUFFLE_INSTALL_STATE_DIR:-$APP_DIR/.install-state}"
mkdir -p "$FLASHDIR" "$DATADIR" "$PROFILEDIR/custom" "$LOGDIR" "$STATE_DIR" || exit 5

# v0.8.27 keeps only one persistent log per game. Remove diagnostic files and
# duplicate per-backend logs left by older releases; games and profiles are not
# touched. Current per-game logs directly under logs/ are preserved.
for obsolete_log in \
    "$APP_DIR/setup.log" \
    "$APP_DIR/install.log" \
    "$APP_DIR/bootstrap.log" \
    "$APP_DIR/Ruffle-Handheld-install.log" \
    "$APP_DIR/LAST-INSTALL.log" \
    "$LOGDIR/bootstrap.log" \
    "$LOGDIR/ES-LAUNCH.log" \
    "$LOGDIR/install.log" \
    "$LOGDIR/FLASH-EARLY.log" \
    "$LOGDIR/input-helper.log" \
    "$LOGDIR/LAST-LAUNCH-MEMORY.log" \
    "$LOGDIR/LAST-SIGKILL-137.log" \
    "$LOGDIR/es-config.path" \
    "$LOGDIR/es-dropins.paths"; do
    [ -f "$obsolete_log" ] && rm -f "$obsolete_log"
done
for duplicate_log in "$LOGDIR"/*.multifile.log "$LOGDIR/native"/*.log; do
    [ -f "$duplicate_log" ] && rm -f "$duplicate_log"
done
rmdir "$LOGDIR/native" 2>/dev/null || true
for migrated_log in \
    "$MIGRATED"/legacy-flash_runtime*/logs/*.log \
    "$MIGRATED"/legacy-flash_runtime*/logs/native/*.log \
    "$MIGRATED"/legacy-ruffle_r36s*/logs/*.log \
    "$MIGRATED"/legacy-ruffle_r36s*/logs/native/*.log; do
    [ -f "$migrated_log" ] && rm -f "$migrated_log"
done

echo "=== Core install: v0.7.7 binaries under v0.8.27 installer ==="
echo "ROM root: $ROMROOT"
echo "Application: $APP_DIR"
echo "CFW adapter: $CFW_NAME"

unique_target() {
    base="$1"; candidate="$base"; n=1
    while [ -e "$candidate" ]; do
        candidate="$base.$n"
        n=$((n + 1))
    done
    printf '%s\n' "$candidate"
}

echo "[1/5] Migrating multi-file data and legacy layouts..."
migrate_sidecar() {
    old="$1"
    [ -d "$old" ] || return 0
    name="$(basename "$old")"
    case "$name" in .*) name="${name#.}" ;; esac
    target="$DATADIR/$name"
    if [ ! -e "$target" ]; then
        mv "$old" "$target" || return 1
        echo "  moved sidecar: $old -> $target"
        return 0
    fi
    cp -a "$old"/. "$target"/ 2>/dev/null || cp -R "$old"/. "$target"/ || return 1
    backup="$(unique_target "$MIGRATED/sidecars/$name")"
    mkdir -p "$(dirname "$backup")" || return 1
    mv "$old" "$backup" || return 1
    echo "  merged sidecar; original preserved: $backup"
}
for sidecar in "$FLASHDIR"/*.files "$FLASHDIR"/.*.files; do
    [ -d "$sidecar" ] && migrate_sidecar "$sidecar" || true
done

# Profiles from v0.8.6 and earlier become the active profiles inside the app.
# A differing bundled profile is backed up before a user/legacy profile wins.
# Migrate the old packaged source first; profiles from the installed legacy
# directory are applied last so any user customization remains authoritative.
for LEGACY_PROFILES in "$APP_DIR/payload/flash_profiles" "$ROMROOT/flash_profiles"; do
  if [ -d "$LEGACY_PROFILES" ]; then
    for old_profile in "$LEGACY_PROFILES"/*.profile; do
        [ -f "$old_profile" ] || continue
        name="$(basename "$old_profile")"
        destination="$PROFILEDIR/$name"
        if [ -f "$destination" ] && ! cmp -s "$old_profile" "$destination"; then
            mkdir -p "$MIGRATED/replaced-bundled-profiles"
            backup="$(unique_target "$MIGRATED/replaced-bundled-profiles/$name")"
            cp -p "$destination" "$backup" || exit 10
        fi
        cp -p "$old_profile" "$destination" || exit 10
        cmp -s "$old_profile" "$destination" || exit 10
        rm -f "$old_profile" || exit 10
        echo "  profile moved inside Ruffle Handheld: $name"
    done
    rmdir "$LEGACY_PROFILES" 2>/dev/null || true
  fi
done

retire_identical() {
    old="$1"; current="$2"
    [ -f "$old" ] || return 0
    if [ -f "$current" ] && cmp -s "$old" "$current"; then
        rm -f "$old"
    fi
}

# Remove only byte-identical project files from the obsolete root-level runtime.
# Anything modified or unknown is moved inside migrated/ instead of deleted.
LEGACY_ENGINE="$ROMROOT/flash_runtime"
if [ -d "$LEGACY_ENGINE" ]; then
    # A repair/update may find the small compatibility bridge created by
    # v0.8.15. It is obsolete now that every EmuELEC drop-in is synchronized.
    if [ -f "$LEGACY_ENGINE/launch.sh" ] && \
        grep -F '# RUFFLE_HANDHELD_V077_ROUTE_BRIDGE' "$LEGACY_ENGINE/launch.sh" >/dev/null 2>&1; then
        rm -f "$LEGACY_ENGINE/launch.sh" || exit 11
    fi
    retire_identical "$LEGACY_ENGINE/launch.sh" "$ENGINE/core/launch.sh"
    retire_identical "$LEGACY_ENGINE/lib/control_profiles.sh" "$ENGINE/core/lib/control_profiles.sh"
    retire_identical "$LEGACY_ENGINE/lib/performance.sh" "$ENGINE/core/lib/performance.sh"
    retire_identical "$LEGACY_ENGINE/native_v020/Ruffle-Native-Launch.sh" "$ENGINE/core/native_v020/Ruffle-Native-Launch.sh"
    retire_identical "$LEGACY_ENGINE/native_v020/ruffle-native.aarch64" "$ENGINE/core/native_v020/ruffle-native.aarch64"
    retire_identical "$LEGACY_ENGINE/native_v020/libruffle_cursorfix.aarch64.so" "$ENGINE/core/native_v020/libruffle_cursorfix.aarch64.so"
    retire_identical "$LEGACY_ENGINE/native_multifile/Ruffle-Native-Multifile-Launch.sh" "$ENGINE/core/native_multifile/Ruffle-Native-Multifile-Launch.sh"
    retire_identical "$LEGACY_ENGINE/native_multifile/ruffle-native-multifile.aarch64" "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64"
    retire_identical "$LEGACY_ENGINE/theme_assets/system.png" "$APP_DIR/theme/system.png"
    retire_identical "$LEGACY_ENGINE/theme_assets/background_icon.png" "$APP_DIR/theme/background_icon.png"
    retire_identical "$LEGACY_ENGINE/standalone/PortMaster/control.txt" "$ENGINE/standalone/PortMaster/control.txt"
    for legacy_log in "$LEGACY_ENGINE/logs"/*.log "$LEGACY_ENGINE/logs/native"/*.log; do
        [ -f "$legacy_log" ] && rm -f "$legacy_log"
    done
    for dir in "$LEGACY_ENGINE/native_v020" "$LEGACY_ENGINE/native_multifile" \
        "$LEGACY_ENGINE/lib" "$LEGACY_ENGINE/theme_assets" \
        "$LEGACY_ENGINE/standalone/PortMaster" "$LEGACY_ENGINE/standalone" \
        "$LEGACY_ENGINE/logs/native" "$LEGACY_ENGINE/logs"; do
        rmdir "$dir" 2>/dev/null || true
    done
    rmdir "$LEGACY_ENGINE" 2>/dev/null || true
    if [ -d "$LEGACY_ENGINE" ]; then
        mkdir -p "$MIGRATED"
        legacy_target="$(unique_target "$MIGRATED/legacy-flash_runtime")"
        mv "$LEGACY_ENGINE" "$legacy_target" || exit 11
        echo "  non-identical legacy runtime data preserved: $legacy_target"
    fi
fi

# An in-place unzip over v0.8.6 can leave its old payload/ source tree. Retire
# byte-identical files and preserve any modified remainder inside migrated/.
LEGACY_PAYLOAD="$APP_DIR/payload"
if [ -d "$LEGACY_PAYLOAD/flash_runtime" ]; then
    OLD="$LEGACY_PAYLOAD/flash_runtime"
    retire_identical "$OLD/launch.sh" "$ENGINE/core/launch.sh"
    retire_identical "$OLD/lib/control_profiles.sh" "$ENGINE/core/lib/control_profiles.sh"
    retire_identical "$OLD/lib/performance.sh" "$ENGINE/core/lib/performance.sh"
    retire_identical "$OLD/native_v020/Ruffle-Native-Launch.sh" "$ENGINE/core/native_v020/Ruffle-Native-Launch.sh"
    retire_identical "$OLD/native_v020/ruffle-native.aarch64" "$ENGINE/core/native_v020/ruffle-native.aarch64"
    retire_identical "$OLD/native_v020/libruffle_cursorfix.aarch64.so" "$ENGINE/core/native_v020/libruffle_cursorfix.aarch64.so"
    retire_identical "$OLD/native_multifile/Ruffle-Native-Multifile-Launch.sh" "$ENGINE/core/native_multifile/Ruffle-Native-Multifile-Launch.sh"
    retire_identical "$OLD/native_multifile/ruffle-native-multifile.aarch64" "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64"
    retire_identical "$OLD/theme_assets/system.png" "$APP_DIR/theme/system.png"
    retire_identical "$OLD/theme_assets/background_icon.png" "$APP_DIR/theme/background_icon.png"
    retire_identical "$OLD/standalone/PortMaster/control.txt" "$ENGINE/standalone/PortMaster/control.txt"
    for dir in "$OLD/native_v020" "$OLD/native_multifile" "$OLD/lib" \
        "$OLD/theme_assets" "$OLD/standalone/PortMaster" "$OLD/standalone" "$OLD"; do
        rmdir "$dir" 2>/dev/null || true
    done
fi
if [ -d "$LEGACY_PAYLOAD" ]; then
    mkdir -p "$MIGRATED"
    legacy_target="$(unique_target "$MIGRATED/legacy-v086-payload")"
    mv "$LEGACY_PAYLOAD" "$legacy_target" || exit 11
    echo "  non-identical v0.8.6 payload data preserved: $legacy_target"
fi

LEGACY_PM="$ROMROOT/ports/ruffle_r36s"
if [ -d "$LEGACY_PM" ]; then
    retire_identical "$LEGACY_PM/Ruffle-Native-Launch.sh" "$ENGINE/core/native_v020/Ruffle-Native-Launch.sh"
    retire_identical "$LEGACY_PM/Ruffle-Native-Multifile-Launch.sh" "$ENGINE/core/native_multifile/Ruffle-Native-Multifile-Launch.sh"
    retire_identical "$LEGACY_PM/runtime/ruffle-native.aarch64" "$ENGINE/core/native_v020/ruffle-native.aarch64"
    retire_identical "$LEGACY_PM/runtime/ruffle-native-multifile.aarch64" "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64"
    retire_identical "$LEGACY_PM/runtime/libruffle_cursorfix.aarch64.so" "$ENGINE/core/native_v020/libruffle_cursorfix.aarch64.so"
    retire_identical "$LEGACY_PM/lib/control_profiles.sh" "$ENGINE/core/lib/control_profiles.sh"
    for legacy_log in "$LEGACY_PM/logs"/*.log "$LEGACY_PM/logs/native"/*.log; do
        [ -f "$legacy_log" ] && rm -f "$legacy_log"
    done
    for dir in "$LEGACY_PM/runtime" "$LEGACY_PM/lib" "$LEGACY_PM/logs/native" "$LEGACY_PM/logs"; do
        rmdir "$dir" 2>/dev/null || true
    done
    rmdir "$LEGACY_PM" 2>/dev/null || true
    if [ -d "$LEGACY_PM" ]; then
        mkdir -p "$MIGRATED"
        legacy_target="$(unique_target "$MIGRATED/legacy-ruffle_r36s")"
        mv "$LEGACY_PM" "$legacy_target" || exit 12
        echo "  non-identical legacy Native data preserved: $legacy_target"
    fi
fi

echo "[2/5] Verifying frozen runtime, profiles and permissions..."
for required in \
    "$ENGINE/core/launch.sh" \
    "$ENGINE/es-launch.sh" \
    "$ENGINE/core/lib/control_profiles.sh" \
    "$ENGINE/core/lib/performance.sh" \
    "$ENGINE/core/native_v020/Ruffle-Native-Launch.sh" \
    "$ENGINE/core/native_v020/libruffle_cursorfix.aarch64.so" \
    "$ENGINE/core/native_v020/ruffle-native.aarch64" \
    "$ENGINE/core/native_multifile/Ruffle-Native-Multifile-Launch.sh" \
    "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64" \
    "$APP_DIR/profile-maker.html" \
    "$APP_DIR/theme/background_icon.png" \
    "$APP_DIR/theme/system.png"; do
    [ -f "$required" ] || { echo "ERROR: bundled file missing: $required"; exit 13; }
done
chmod +x "$ENGINE/entrypoint.sh" "$ENGINE/es-launch.sh" "$ENGINE/native-adapter.sh" "$ENGINE/multifile-adapter.sh" \
    "$ENGINE/core/launch.sh" "$ENGINE/core/lib/performance.sh" \
    "$ENGINE/core/native_v020/Ruffle-Native-Launch.sh" \
    "$ENGINE/core/native_v020/ruffle-native.aarch64" \
    "$ENGINE/core/native_multifile/Ruffle-Native-Multifile-Launch.sh" \
    "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64" || exit 14
echo "  runtime stays in-place; no duplicate binary tree was created"

# NextUI does not use EmulationStation. Register Flash as a standalone emulator
# PAK, while leaving Ruffle and all profiles in the existing application folder.
# PORTS.pak supplies the Bash and PortMaster controller bridge already present
# on that frontend; the Ruffle release itself remains completely offline.
case "$CFW_KEY" in
    *nextui*)
        NEXTUI_SD="${RUFFLE_NEXTUI_SD:-}"
        NEXTUI_PLATFORM="${RUFFLE_NEXTUI_PLATFORM:-}"
        NEXTUI_APP_DIR="${RUFFLE_NEXTUI_APP_DIR:-$APP_DIR}"
        [ -n "$NEXTUI_SD" ] && [ -d "$NEXTUI_SD/Roms" ] || {
            echo "ERROR: invalid NextUI SD root: $NEXTUI_SD"; exit 20;
        }
        [ -n "$NEXTUI_PLATFORM" ] || { echo "ERROR: NextUI platform was not detected"; exit 20; }
        [ -f "$NEXTUI_APP_DIR/runtime/es-launch.sh" ] || {
            echo "ERROR: persistent NextUI application path is invalid: $NEXTUI_APP_DIR"; exit 20;
        }
        NEXTUI_PM="$NEXTUI_SD/Emus/$NEXTUI_PLATFORM/PORTS.pak"
        [ -x "$NEXTUI_PM/bin/bash" ] || {
            echo "ERROR: PORTS.pak Bash is missing: $NEXTUI_PM/bin/bash"; exit 20;
        }
        NEXTUI_PAK="$NEXTUI_SD/Emus/$NEXTUI_PLATFORM/FLASH.pak"
        mkdir -p "$NEXTUI_PAK" "$FLASHDIR" "$DATADIR" "$ROMROOT/.media" || exit 20
        printf '%s\n' "$NEXTUI_APP_DIR" > "$NEXTUI_PAK/ruffle-app.path" || exit 20
        cat > "$NEXTUI_PAK/launch.sh" <<'PAK_LAUNCH'
#!/bin/sh
# Ruffle Handheld NextUI standalone Flash PAK.
PAK_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)" || exit 1
ROM="${1:-}"
[ -n "$ROM" ] && [ -f "$ROM" ] || { echo "Ruffle Handheld: no valid SWF received"; exit 2; }
[ -f "$PAK_DIR/ruffle-app.path" ] || { echo "Ruffle Handheld: application pointer missing"; exit 3; }
APP_DIR="$(sed -n '1p' "$PAK_DIR/ruffle-app.path")"
[ -f "$APP_DIR/runtime/es-launch.sh" ] || { echo "Ruffle Handheld: installed runtime missing"; exit 3; }

SDCARD_ROOT="${SDCARD_PATH:-$(dirname "$(dirname "$(dirname "$PAK_DIR")")")}"
PLATFORM_NAME="${PLATFORM:-$(basename "$(dirname "$PAK_DIR")")}"
PORTS_PAK="$SDCARD_ROOT/Emus/$PLATFORM_NAME/PORTS.pak"
BASH_BIN="$PORTS_PAK/bin/bash"
[ -x "$BASH_BIN" ] || { echo "Ruffle Handheld: PORTS.pak Bash missing"; exit 4; }

export PATH="$PORTS_PAK/PortMaster:$PORTS_PAK/bin:$PATH"
export LD_LIBRARY_PATH="$PORTS_PAK/lib:/usr/trimui/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_HOME="$PORTS_PAK"
export RUFFLE_BASH="$BASH_BIN"
export RUFFLE_CFW_NAME="NextUI"
export CFW_NAME="NextUI"
export RUFFLE_ROM_ROOT="$SDCARD_ROOT/Roms"
export RUFFLE_FLASH_DIR="$SDCARD_ROOT/Roms/Flash (FLASH)"
export RUFFLE_DATA_DIR="$SDCARD_ROOT/Roms/flash_data"
exec "$BASH_BIN" "$APP_DIR/runtime/es-launch.sh" --rom-root "$RUFFLE_ROM_ROOT" "$ROM"
PAK_LAUNCH
        chmod +x "$NEXTUI_PAK/launch.sh" || exit 20
        # NextUI system artwork lives in Roms/.media. Preserve user artwork.
        [ -e "$ROMROOT/.media/Flash (FLASH).png" ] || \
            cp "$APP_DIR/theme/system.png" "$ROMROOT/.media/Flash (FLASH).png" || true
        [ -e "$NEXTUI_PAK/background_icon.png" ] || \
            cp "$APP_DIR/theme/background_icon.png" "$NEXTUI_PAK/background_icon.png" || true
        printf '%s\n' "$NEXTUI_PAK" > "$STATE_DIR/nextui-pak.path" || exit 20
        printf '%s\n' "0.8.27" > "$APP_DIR/installed-version"
        [ -x "$NEXTUI_PAK/launch.sh" ] || exit 26
        [ -d "$FLASHDIR" ] && [ -d "$DATADIR" ] || exit 27
        [ -f "$PROFILEDIR/default.profile" ] || exit 28
        [ ! -e "$ROMROOT/flash_runtime" ] || { echo "ERROR: obsolete root-level flash_runtime remains"; exit 28; }
        sync
        echo "  frontend adapter: nextui-standalone-pak-community-test"
        echo "  Flash PAK: $NEXTUI_PAK"
        echo "  Games: $FLASHDIR"
        echo "Core installation complete and verified."
        exit 0
        ;;
esac

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# ArkOS keeps its authoritative system list under /etc, while several other
# frontends keep it on writable storage.  PortMaster normally runs with enough
# privileges to update either location, but ArkOS requires its existing sudo
# bridge.  Never prompt for a password from a controller-only installer.
can_replace_config() {
    cfg="$1"
    [ -f "$cfg" ] || return 1
    [ -w "$cfg" ] && return 0
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n test -w "$cfg" >/dev/null 2>&1
}

replace_config() {
    source_cfg="$1"; destination_cfg="$2"
    destination_dir="$(dirname "$destination_cfg")"
    if [ -w "$destination_cfg" ]; then
        if [ -w "$destination_dir" ]; then
            mv "$source_cfg" "$destination_cfg"
            return $?
        fi
        cp "$source_cfg" "$destination_cfg" || return 1
        rm -f "$source_cfg" 2>/dev/null || true
        return 0
    fi
    command -v sudo >/dev/null 2>&1 || return 1
    privileged_tmp="$destination_cfg.ruffle-new.$$"
    sudo -n cp "$source_cfg" "$privileged_tmp" >/dev/null 2>&1 || return 1
    sudo -n chmod 644 "$privileged_tmp" >/dev/null 2>&1 || true
    sudo -n mv "$privileged_tmp" "$destination_cfg" >/dev/null 2>&1 || {
        sudo -n rm -f "$privileged_tmp" >/dev/null 2>&1 || true
        return 1
    }
    rm -f "$source_cfg" 2>/dev/null || true
    return 0
}

backup_config_once() {
    cfg="$1"; backup="$cfg.rufflehandheld-backup"
    [ -e "$backup" ] && return 0
    if [ -w "$(dirname "$cfg")" ]; then
        cp -p "$cfg" "$backup"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -n cp -p "$cfg" "$backup" >/dev/null 2>&1 && return 0
        cfg_id="$(printf '%s' "$cfg" | tr '/ ' '__')"
        fallback_backup="$MIGRATED/es-config-backups/$cfg_id"
        mkdir -p "$(dirname "$fallback_backup")" || return 1
        [ -e "$fallback_backup" ] || cp -p "$cfg" "$fallback_backup"
    else
        cfg_id="$(printf '%s' "$cfg" | tr '/ ' '__')"
        fallback_backup="$MIGRATED/es-config-backups/$cfg_id"
        mkdir -p "$(dirname "$fallback_backup")" || return 1
        [ -e "$fallback_backup" ] || cp -p "$cfg" "$fallback_backup"
    fi
}

# ROCKNIX ships the user configuration as a link to its read-only system
# image. Its documented customization route is to replace that link with a
# writable copy under /storage/.config/emulationstation. Preserve the original
# link once, then patch only the copy.
materialize_rocknix_config() {
    user_cfg="${RUFFLE_ROCKNIX_ES_CONFIG:-/storage/.config/emulationstation/es_systems.cfg}"
    system_cfg="${RUFFLE_ROCKNIX_SYSTEM_CONFIG:-/usr/config/emulationstation/es_systems.cfg}"
    user_dir="$(dirname "$user_cfg")"
    mkdir -p "$user_dir" || return 1

    if [ -L "$user_cfg" ]; then
        original_link="$user_cfg.rufflehandheld-original-link"
        [ -e "$original_link" ] || [ -L "$original_link" ] || cp -P "$user_cfg" "$original_link" || return 1
        writable_copy="$STATE_DIR/rocknix-es-systems.$$"
        cp -L "$user_cfg" "$writable_copy" 2>/dev/null || \
            cp "$system_cfg" "$writable_copy" 2>/dev/null || return 1
        chmod 644 "$writable_copy" 2>/dev/null || true
        mv "$writable_copy" "$user_cfg" || return 1
        echo "  ROCKNIX read-only configuration link replaced by a writable user copy"
    elif [ ! -f "$user_cfg" ]; then
        if [ -f "$system_cfg" ]; then
            cp "$system_cfg" "$user_cfg" || return 1
        else
            { echo '<?xml version="1.0"?>'; echo '<systemList>'; echo '</systemList>'; } > "$user_cfg" || return 1
        fi
    fi
    chmod u+w "$user_cfg" 2>/dev/null || true
    [ -f "$user_cfg" ] && [ -w "$user_cfg" ] || return 1
    ES_CFG="$user_cfg"
}

ES_CFG="${RUFFLE_ES_CONFIG:-}"
ES_ADAPTER="generic-existing"
if [ -z "$ES_CFG" ]; then
    case "$CFW_KEY" in
        *emuelec*)
            ES_ADAPTER="emuelec-verified"
            ES_CFG="/storage/.config/emulationstation/es_systems.cfg"
            if [ ! -f "$ES_CFG" ] && [ -f /usr/config/emulationstation/es_systems.cfg ]; then
                mkdir -p "$(dirname "$ES_CFG")" || exit 20
                cp /usr/config/emulationstation/es_systems.cfg "$ES_CFG" || exit 20
            fi
            ;;
        *knulli*|*batocera*)
            ES_ADAPTER="knulli-overlay-unverified"
            ES_CFG="${RUFFLE_KNULLI_ES_CONFIG:-/userdata/system/configs/emulationstation/es_systems_rufflehandheld.cfg}"
            ;;
        *arkos*|*darkos*)
            ES_ADAPTER="arkos-official-config-community-test"
            # ArkOS itself updates /etc/emulationstation/es_systems.cfg and
            # documents it as the active system list. Prefer it over a stale
            # per-user copy, using passwordless sudo only when already present.
            for candidate in \
                "${RUFFLE_ARKOS_SYSTEM_CONFIG:-${RUFFLE_ARKOS_ES_CONFIG:-/etc/emulationstation/es_systems.cfg}}" \
                "${RUFFLE_ARKOS_USER_CONFIG:-/home/ark/.emulationstation/es_systems.cfg}"; do
                can_replace_config "$candidate" && { ES_CFG="$candidate"; break; }
            done
            ;;
        *rocknix*)
            ES_ADAPTER="rocknix-user-copy-community-test"
            materialize_rocknix_config || {
                echo "ERROR: could not create the writable ROCKNIX EmulationStation configuration"
                exit 21
            }
            ;;
        *amberelec*|*351elec*)
            ES_ADAPTER="amberelec-overlay-unverified"
            ES_CFG="${RUFFLE_AMBERELEC_ES_CONFIG:-/storage/.emulationstation/es_systems_rufflehandheld.cfg}"
            ;;
        *muos*) ES_ADAPTER="muos-no-emulationstation-adapter" ;;
    esac
fi
if [ -z "$ES_CFG" ]; then
    for candidate in \
        "${HOME:-/tmp}/.config/emulationstation/es_systems.cfg" \
        "${HOME:-/tmp}/.emulationstation/es_systems.cfg" \
        /storage/.config/emulationstation/es_systems.cfg \
        /storage/.emulationstation/es_systems.cfg \
        /userdata/system/configs/emulationstation/es_systems.cfg; do
        can_replace_config "$candidate" && { ES_CFG="$candidate"; break; }
    done
fi

if [ ! -f "$ES_CFG" ]; then
    case "$ES_ADAPTER" in
        emuelec-verified|knulli-overlay-unverified|amberelec-overlay-unverified|generic-existing)
            [ -n "$ES_CFG" ] || { echo "ERROR: no EmulationStation configuration was found"; exit 21; }
            mkdir -p "$(dirname "$ES_CFG")" || exit 21
            { echo '<?xml version="1.0"?>'; echo '<systemList>'; echo '</systemList>'; } > "$ES_CFG" || exit 21
            ;;
        *)
            echo "ERROR: no writable EmulationStation configuration was found for '$CFW_NAME'"
            echo "Adapter status: $ES_ADAPTER"
            exit 21
            ;;
    esac
fi
can_replace_config "$ES_CFG" || { echo "ERROR: EmulationStation configuration cannot be updated safely: $ES_CFG"; exit 21; }

# EmuELEC's proven route uses the unescaped raw path token. ArkOS and the
# Batocera-family frontends use %ROM% in their system definitions. For an
# unknown existing config, follow the token style already present in that file.
case "$CFW_KEY" in
    *emuelec*|*rocknix*|*amberelec*|*351elec*) ROM_TOKEN="%ROM_RAW%" ;;
    *arkos*|*darkos*|*knulli*|*batocera*) ROM_TOKEN="%ROM%" ;;
    *)
        if grep -F '%ROM_RAW%' "$ES_CFG" >/dev/null 2>&1; then ROM_TOKEN="%ROM_RAW%"; else ROM_TOKEN="%ROM%"; fi
        ;;
esac

ES_LAUNCH="$ENGINE/es-launch.sh"
ES_COMMAND_STYLE="standard-escaped"
case "$CFW_KEY" in
    *emuelec*)
        ES_LAUNCH="$ENGINE/es-launch.sh"
        ES_COMMAND_STYLE="emuelec-v077-simple"
        ;;
esac

echo "[3/5] Integrating the active theme conservatively..."
# Keep the system identity as Flash even when a read-only theme cannot be
# extended. Using `arcade` here made Knulli group and label Flash as Arcade.
THEME_TAG="flash"
THEMESET=""
for settings in \
    "${RUFFLE_ES_SETTINGS:-}" \
    "$(dirname "$ES_CFG")/es_settings.cfg" \
    /storage/.config/emulationstation/es_settings.cfg \
    /storage/.emulationstation/es_settings.cfg \
    /userdata/system/configs/emulationstation/es_settings.cfg \
    "${HOME:-/tmp}/.config/emulationstation/es_settings.cfg" \
    "${HOME:-/tmp}/.emulationstation/es_settings.cfg"; do
    [ -n "$settings" ] && [ -f "$settings" ] || continue
    THEMESET="$(sed -n 's/.*<string name="ThemeSet" value="\([^"]*\)".*/\1/p' "$settings" | head -1)"
    [ -n "$THEMESET" ] && break
done

ACTIVE_THEME=""
if [ -n "$THEMESET" ]; then
    for theme_root in \
        "${RUFFLE_THEME_ROOT:-}" \
        "$(dirname "$ES_CFG")/themes" \
        /storage/.config/emulationstation/themes \
        /storage/.emulationstation/themes \
        /userdata/themes \
        /userdata/system/configs/emulationstation/themes \
        "${HOME:-/tmp}/.emulationstation/themes" \
        /etc/emulationstation/themes; do
        [ -n "$theme_root" ] || continue
        [ -f "$theme_root/$THEMESET/flash/theme.xml" ] && {
            ACTIVE_THEME="$theme_root/$THEMESET"; THEME_TAG="flash"; break;
        }
        [ -z "$ACTIVE_THEME" ] && [ -f "$theme_root/$THEMESET/arcade/theme.xml" ] && \
            ACTIVE_THEME="$theme_root/$THEMESET"
    done
fi
if [ -n "$ACTIVE_THEME" ] && [ -f "$ACTIVE_THEME/flash/theme.xml" ]; then
    echo "  existing Flash theme retained unchanged: $ACTIVE_THEME/flash"
elif [ -n "$ACTIVE_THEME" ] && [ -f "$ACTIVE_THEME/arcade/theme.xml" ] && [ -w "$ACTIVE_THEME" ]; then
    FLASH_THEME="$ACTIVE_THEME/flash"
    mkdir -p "$FLASH_THEME" || true
    [ -e "$FLASH_THEME/theme.xml" ] || cp "$ACTIVE_THEME/arcade/theme.xml" "$FLASH_THEME/theme.xml" || true
    [ -e "$FLASH_THEME/system.png" ] || cp "$APP_DIR/theme/system.png" "$FLASH_THEME/system.png" || true
    [ -e "$FLASH_THEME/background_icon.png" ] || cp "$APP_DIR/theme/background_icon.png" "$FLASH_THEME/background_icon.png" || true
    if [ -f "$FLASH_THEME/theme.xml" ] && [ -f "$FLASH_THEME/system.png" ] && [ -f "$FLASH_THEME/background_icon.png" ]; then
        THEME_TAG="flash"
        echo "  Flash theme created with the Adobe logo and chef artwork: $FLASH_THEME"
    fi
else
    echo "  active theme cannot be extended safely; Flash theme key retained"
fi

strip_flash_system() {
    cfg="$1"; out="$2"
    awk '
      /<system[[:space:]>]/ {
        in_system=1; buf=$0 ORS
        if (/<\/system>/) {
          if (buf !~ /<name>[[:space:]]*flash[[:space:]]*<\/name>/) printf "%s", buf
          in_system=0; buf=""
        }
        next
      }
      in_system {
        buf=buf $0 ORS
        if (/<\/system>/) {
          if (buf !~ /<name>[[:space:]]*flash[[:space:]]*<\/name>/) printf "%s", buf
          in_system=0; buf=""
        }
        next
      }
      { print }
      END { if (in_system && buf !~ /<name>[[:space:]]*flash[[:space:]]*<\/name>/) printf "%s", buf }
    ' "$cfg" > "$out"
}

patch_es_config() {
    cfg="$1"
    cfg_id="$(printf '%s' "$cfg" | tr '/ ' '__')"
    tmp="$STATE_DIR/$cfg_id.clean.$$"; final="$STATE_DIR/$cfg_id.final.$$"
    strip_flash_system "$cfg" "$tmp" || return 1
    flash_xml="$(xml_escape "$FLASHDIR")"
    entry_xml="$(xml_escape "$ES_LAUNCH")"
    root_xml="$(xml_escape "$ROMROOT")"
    awk -v flashdir="$flash_xml" -v entry="$entry_xml" -v romroot="$root_xml" -v romtoken="$ROM_TOKEN" -v themetag="$THEME_TAG" -v commandstyle="$ES_COMMAND_STYLE" '
      /<\/systemList>/ && !added {
        print "  <!-- RUFFLE_HANDHELD_FLASH -->"
        print "  <system>"
        print "    <name>flash</name>"
        print "    <fullname>Adobe Flash Player</fullname>"
        print "    <path>" flashdir "</path>"
        print "    <extension>.swf .SWF</extension>"
        if (commandstyle == "emuelec-v077-simple")
          print "    <command>/bin/bash &quot;" entry "&quot; &quot;" romtoken "&quot;</command>"
        else if (commandstyle == "standard-escaped")
          print "    <command>/bin/bash &quot;" entry "&quot; --rom-root &quot;" romroot "&quot; &quot;" romtoken "&quot;</command>"
        else
          print "    <command>/bin/bash \"" entry "\" --rom-root \"" romroot "\" \"" romtoken "\"</command>"
        print "    <platform>flash</platform>"
        print "    <theme>" themetag "</theme>"
        print "  </system>"
        added=1
      }
      { print }
      END { if (!added) exit 20 }
    ' "$tmp" > "$final" || { rm -f "$tmp" "$final"; return 1; }
    backup_config_once "$cfg" || { rm -f "$tmp" "$final"; return 1; }
    replace_config "$final" "$cfg" || { rm -f "$tmp" "$final"; return 1; }
    rm -f "$tmp"
}

is_ruffle_owned_config() {
    cfg="$1"
    grep -E 'RUFFLE_HANDHELD_FLASH|rufflehandheld/runtime/es-launch\.sh|/flash_runtime/launch\.sh|/ports/ruffle_r36s/' \
        "$cfg" >/dev/null 2>&1
}

remove_stale_ruffle_flash() {
    cfg="$1"
    [ -f "$cfg" ] || return 0
    [ "$cfg" = "$ES_CFG" ] && return 0
    is_ruffle_owned_config "$cfg" || return 0
    cfg_id="$(printf '%s' "$cfg" | tr '/ ' '__')"
    cleaned="$STATE_DIR/$cfg_id.dedup.$$"
    strip_flash_system "$cfg" "$cleaned" || return 1
    backup_config_once "$cfg" || { rm -f "$cleaned"; return 1; }
    replace_config "$cleaned" "$cfg" || { rm -f "$cleaned"; return 1; }
    stale_count="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$cfg" 2>/dev/null || true)"
    [ "$stale_count" = "0" ] || return 1
    printf '%s\n' "$cfg" >> "$STATE_DIR/es-deduplicated.paths" || return 1
    echo "  removed stale Ruffle Handheld Flash registration: $cfg"
}

write_emuelec_dropin() {
    config_dir="$1"
    [ -n "$config_dir" ] || return 1
    mkdir -p "$config_dir" || return 1
    dropin="$config_dir/es_systems_flash.cfg"
    if [ -f "$dropin" ] && [ ! -f "$dropin.rufflehandheld-backup" ]; then
        cp -p "$dropin" "$dropin.rufflehandheld-backup" || return 1
    fi
    flash_xml="$(xml_escape "$FLASHDIR")"
    launch_xml="$(xml_escape "$ES_LAUNCH")"
    cat > "$dropin" <<CFG
<?xml version="1.0"?>
<systemList>
  <system>
    <name>flash</name>
    <fullname>Adobe Flash Player</fullname>
    <path>$flash_xml</path>
    <extension>.swf .SWF</extension>
    <command>/bin/bash &quot;$launch_xml&quot; &quot;%ROM_RAW%&quot;</command>
    <platform>flash</platform>
    <theme>$THEME_TAG</theme>
  </system>
</systemList>
CFG
    chmod 644 "$dropin" 2>/dev/null || true
    printf '%s\n' "$dropin" >> "$STATE_DIR/es-dropins.paths" || return 1
    return 0
}

echo "[4/5] Registering exactly one Flash system..."
patch_es_config "$ES_CFG" || { echo "ERROR: could not update $ES_CFG"; exit 22; }
FLASH_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$ES_CFG" 2>/dev/null || true)"
[ "$FLASH_COUNT" = "1" ] || { echo "ERROR: Flash registration count is $FLASH_COUNT, expected 1"; exit 23; }
grep -F "<path>$(xml_escape "$FLASHDIR")</path>" "$ES_CFG" >/dev/null || exit 24
grep -F "$ROM_TOKEN" "$ES_CFG" >/dev/null || exit 25
grep -F "$ES_LAUNCH" "$ES_CFG" >/dev/null || exit 25

# Old releases could write the same Flash system into both the official and a
# per-user system list. Some EmulationStation builds merge those inputs, which
# makes one SWF appear several times in All Games. Remove only configurations
# that contain a Ruffle Handheld marker or one of its known legacy commands.
: > "$STATE_DIR/es-deduplicated.paths" || exit 25
case "$CFW_KEY" in
    *arkos*|*darkos*)
        for stale_cfg in \
            "${RUFFLE_ES_ALT_CONFIG:-}" \
            /home/ark/.emulationstation/es_systems.cfg \
            /home/ark/.emulationstation/es_systems_flash.cfg \
            /etc/emulationstation/es_systems_flash.cfg; do
            [ -n "$stale_cfg" ] || continue
            remove_stale_ruffle_flash "$stale_cfg" || {
                echo "ERROR: could not remove duplicate Flash registration from $stale_cfg"; exit 25;
            }
        done
        ;;
    *rocknix*|*amberelec*|*351elec*)
        for stale_cfg in \
            "${RUFFLE_ES_ALT_CONFIG:-}" \
            /storage/.config/emulationstation/es_systems_flash.cfg \
            /storage/.emulationstation/es_systems_flash.cfg; do
            [ -n "$stale_cfg" ] || continue
            remove_stale_ruffle_flash "$stale_cfg" || {
                echo "ERROR: could not remove duplicate Flash registration from $stale_cfg"; exit 25;
            }
        done
        ;;
esac
case "$CFW_KEY" in
    *emuelec*)
        grep -F "$ES_LAUNCH" "$ES_CFG" >/dev/null || exit 25
        ;;
    *)
        if grep -F '/flash_runtime/launch.sh' "$ES_CFG" >/dev/null 2>&1; then
            echo "ERROR: the active configuration still contains an obsolete Flash command"
            exit 25
        fi
        ;;
esac

# This EmuELEC build runs emustation-config before every frontend start. On the
# tested device that step can regenerate the active .config file from the
# .emulationstation copy. Keep one identical Flash block in both files; removing
# it from the latter makes Flash disappear immediately after a successful
# service restart. Preserve a one-time backup before synchronizing it.
case "$CFW_KEY" in
    *emuelec*)
        : > "$STATE_DIR/es-dropins.paths" || exit 25
        LEGACY_ES_CFG="${RUFFLE_ES_LEGACY_CONFIG:-/storage/.emulationstation/es_systems.cfg}"
        if [ -f "$LEGACY_ES_CFG" ] && [ "$LEGACY_ES_CFG" != "$ES_CFG" ]; then
            [ -w "$LEGACY_ES_CFG" ] || { echo "ERROR: EmuELEC persistent configuration is not writable: $LEGACY_ES_CFG"; exit 25; }
            [ -f "$LEGACY_ES_CFG.rufflehandheld-backup" ] || \
                cp -p "$LEGACY_ES_CFG" "$LEGACY_ES_CFG.rufflehandheld-backup" || exit 25
            patch_es_config "$LEGACY_ES_CFG" || { echo "ERROR: could not synchronize $LEGACY_ES_CFG"; exit 25; }
            LEGACY_FLASH_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$LEGACY_ES_CFG" 2>/dev/null || true)"
            [ "$LEGACY_FLASH_COUNT" = "1" ] || { echo "ERROR: persistent EmuELEC Flash count is $LEGACY_FLASH_COUNT"; exit 25; }
            grep -F "$ES_LAUNCH" "$LEGACY_ES_CFG" >/dev/null || exit 25
            echo "  persistent EmuELEC config synchronized: $LEGACY_ES_CFG"
        fi
        ACTIVE_ES_DIR="$(dirname "$ES_CFG")"
        LEGACY_ES_DIR="$(dirname "$LEGACY_ES_CFG")"
        write_emuelec_dropin "$ACTIVE_ES_DIR" || { echo "ERROR: could not write the active EmuELEC Flash drop-in"; exit 25; }
        if [ "$LEGACY_ES_DIR" != "$ACTIVE_ES_DIR" ]; then
            write_emuelec_dropin "$LEGACY_ES_DIR" || { echo "ERROR: could not write the persistent EmuELEC Flash drop-in"; exit 25; }
        fi
        while IFS= read -r dropin; do
            [ -f "$dropin" ] || { echo "ERROR: EmuELEC Flash drop-in is missing: $dropin"; exit 25; }
            DROPIN_COUNT="$(grep -c '<name>[[:space:]]*flash[[:space:]]*</name>' "$dropin" 2>/dev/null || true)"
            [ "$DROPIN_COUNT" = "1" ] || { echo "ERROR: EmuELEC drop-in Flash count is $DROPIN_COUNT: $dropin"; exit 25; }
            grep -F "$ES_LAUNCH" "$dropin" >/dev/null || { echo "ERROR: EmuELEC drop-in has the wrong launch route: $dropin"; exit 25; }
            echo "  EmuELEC Flash drop-in synchronized: $dropin"
        done < "$STATE_DIR/es-dropins.paths"
        ;;
esac

printf '%s\n' "$ES_CFG" > "$STATE_DIR/es-config.path" || exit 25
echo "  frontend adapter: $ES_ADAPTER"
echo "  active config: $ES_CFG"
if [ "$ES_COMMAND_STYLE" = "emuelec-v077-simple" ]; then
    echo "  command: /bin/bash \"$ES_LAUNCH\" \"$ROM_TOKEN\""
elif [ "$ES_COMMAND_STYLE" = "standard-escaped" ]; then
    echo "  command: /bin/bash \"$ES_LAUNCH\" --rom-root \"$ROMROOT\" $ROM_TOKEN"
else
    echo "  command: /bin/bash \"$ES_LAUNCH\" --rom-root \"$ROMROOT\" \"$ROM_TOKEN\""
fi

echo "[5/5] Final layout checks..."
for executable in "$ENGINE/entrypoint.sh" "$ENGINE/es-launch.sh" "$ENGINE/native-adapter.sh" \
    "$ENGINE/multifile-adapter.sh" "$ENGINE/core/launch.sh" \
    "$ENGINE/core/native_v020/ruffle-native.aarch64" \
    "$ENGINE/core/native_multifile/ruffle-native-multifile.aarch64"; do
    [ -x "$executable" ] || { echo "ERROR: not executable: $executable"; exit 26; }
done
[ -d "$FLASHDIR" ] && [ -d "$DATADIR" ] || exit 27
[ -f "$PROFILEDIR/default.profile" ] || exit 28
[ -d "$PROFILEDIR/custom" ] || exit 28
[ ! -e "$ROMROOT/flash_runtime" ] || { echo "ERROR: obsolete root-level flash_runtime remains"; exit 28; }
printf '%s\n' "0.8.27" > "$APP_DIR/installed-version"
sync
echo "Core installation complete and verified."
exit 0

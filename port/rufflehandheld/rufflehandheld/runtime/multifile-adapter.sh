#!/bin/bash
# Path and display adapter for the frozen v0.7.7 Native Multifile launcher.

set -u
CORE="${RUFFLE_APP_DIR:?}/runtime/core/native_multifile/Ruffle-Native-Multifile-Launch.sh"
TMP="${RUFFLE_ADAPTER_TMP:-/tmp}/multifile-launch-$$.sh"
BASH_BIN="${RUFFLE_BASH:-${BASH:-/bin/bash}}"
[ -f "$CORE" ] || { echo "ERROR: known-good Native Multifile launcher missing"; exit 3; }

awk '
    /^GAMEDIR=/ && !gamedir { print "GAMEDIR=\"${RUFFLE_COMPAT_GAMEDIR:?}\""; gamedir=1; next }
    /^FLASHLOG=/ && !flashlog { print "FLASHLOG=\"${RUFFLE_FLASH_LOG:?}\""; flashlog=1; next }
    /^DEFAULT_PROFILE=/ && !profile { print "DEFAULT_PROFILE=\"${RUFFLE_DEFAULT_PROFILE:?}\""; profile=1; next }
    /^PROFILE_LIB=/ && !saves {
        print "source \"${RUFFLE_APP_DIR:?}/runtime/save-storage.sh\" || exit 12"
        print "rh_prepare_save_storage \"$DATA_ROOT\" \"$SWF\" \"${RUFFLE_ROM_ROOT:?}\" || exit 12"
        saves=1
    }
    /^unset DISPLAY WAYLAND_DISPLAY/ && !videoenv {
        print "CFW_VIDEO_KEY=\"$(printf '\''%s %s'\'' \"${RUFFLE_CFW_NAME:-}\" \"${CFW_NAME:-}\" | tr '\''[:upper:]'\'' '\''[:lower:]'\'')\""
        print "if [ -n \"${RUFFLE_SDL_VIDEODRIVER:-}\" ]; then"
        print "  case \"$RUFFLE_SDL_VIDEODRIVER\" in"
        print "    auto|AUTO|Auto) unset SDL_VIDEODRIVER ;;"
        print "    *) export SDL_VIDEODRIVER=\"$RUFFLE_SDL_VIDEODRIVER\" ;;"
        print "  esac"
        print "else"
        print "  case \"$CFW_VIDEO_KEY\" in"
        print "    *nextui*|*trimui*) unset DISPLAY WAYLAND_DISPLAY SDL_VIDEODRIVER ;;"
        print "    *rocknix*) unset DISPLAY; export SDL_VIDEODRIVER=wayland ;;"
        print "    *knulli*|*batocera*|*muos*|*ubuntu*|*stock*mod*)"
        print "      CFW_DEVICE_KEY=\"$(printf '\''%s %s'\'' \"${DEVICE_CPU:-}\" \"${DEVICE_NAME:-}\" | tr '\''[:upper:]'\'' '\''[:lower:]'\'')\""
        print "      unset DISPLAY WAYLAND_DISPLAY"
        print "      case \"$CFW_DEVICE_KEY\" in *h700*) export SDL_VIDEODRIVER=mali ;; *) unset SDL_VIDEODRIVER ;; esac"
        print "      ;;"
        print "    *)"
        print "      if [ -n \"${WAYLAND_DISPLAY:-}\" ] && [ -n \"${XDG_RUNTIME_DIR:-}\" ]; then"
        print "        unset DISPLAY; export SDL_VIDEODRIVER=wayland"
        print "      else"
        print "        unset DISPLAY WAYLAND_DISPLAY; export SDL_VIDEODRIVER=kmsdrm"
        print "      fi"
        print "      ;;"
        print "  esac"
        print "fi"
        print "echo \"SDL video adapter: ${SDL_VIDEODRIVER:-auto}\""
        videoenv=1
        next
    }
    /^export SDL_VIDEODRIVER=/ && videoenv { next }
    /^"\$BIN"$/ {
        print "case \"${RUFFLE_CFW_NAME:-${CFW_NAME:-}}\" in"
        print "  [Nn][Ee][Xx][Tt][Uu][Ii])"
        print "    NEXTUI_DISPLAY_SO=\"${RUFFLE_APP_DIR:?}/runtime/libruffle_nextui_display.aarch64.so\""
        print "    if [ \"${RUFFLE_NEXTUI_DISPLAY:-1}\" = 0 ]; then"
        print "      echo '\''[nextui-display] disabled; using original display path'\''"
        print "      \"$BIN\""
        print "    elif [ -f \"$NEXTUI_DISPLAY_SO\" ]; then"
        print "      echo '\''[nextui-display] loading experimental drawable adapter'\''"
        print "      RUFFLE_NEXTUI_DISPLAY=1 LD_PRELOAD=\"$NEXTUI_DISPLAY_SO${LD_PRELOAD:+:$LD_PRELOAD}\" \"$BIN\""
        print "    else"
        print "      echo '\''[nextui-display] adapter missing; using original display path'\''"
        print "      \"$BIN\""
        print "    fi ;;"
        print "  *) \"$BIN\" ;;"
        print "esac"
        next
    }
    { print }
' "$CORE" > "$TMP" || exit 4
chmod +x "$TMP" || exit 4
"$BASH_BIN" "$TMP" "$@"
exit $?

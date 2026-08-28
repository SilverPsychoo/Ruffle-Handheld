#!/bin/bash
# Ruffle Handheld control profile library v0.7.7.
# Profiles are plain key=value files. No profile content is executed as shell code.
# This release targets the frozen ruffle4consoles frontend bundled with the project.

rh_normalize_name() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//'
}

rh_profile_raw_value() {
    file="$1"; key="$2"
    [ -f "$file" ] || return 1
    awk -F= -v k="$key" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { lhs=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
          if (lhs == k) { sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit } }
    ' "$file"
}

rh_profile_has_key() {
    file="$1"; key="$2"
    [ -f "$file" ] || return 1
    awk -F= -v k="$key" '
        /^[[:space:]]*#/ { next }
        { lhs=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs); if (lhs == k) { found=1; exit } }
        END { exit found ? 0 : 1 }
    ' "$file"
}

rh_profile_value() {
    profile="$1"; defaults="$2"; key="$3"
    if rh_profile_has_key "$profile" "$key"; then rh_profile_raw_value "$profile" "$key"; else rh_profile_raw_value "$defaults" "$key"; fi
}

rh_resolve_profile() {
    profiledir="$1"; game_name="$2"; norm="$(rh_normalize_name "$game_name")"
    # User-created profiles always win. The visual profile maker stores them
    # under profiles/custom/ so a release update can replace bundled profiles
    # without touching the user's mappings.
    for searchdir in "$profiledir/custom" "$profiledir"; do
        if [ -f "$searchdir/$norm.profile" ]; then
            printf '%s\n' "$searchdir/$norm.profile"
            return 0
        fi
        for file in "$searchdir"/*.profile; do
            [ -f "$file" ] || continue
            [ "$(basename "$file")" = "default.profile" ] && continue
            [ "$(basename "$file")" = "template.profile" ] && continue
            aliases="$(rh_profile_raw_value "$file" aliases 2>/dev/null || true)"
            oldifs="$IFS"; IFS='|'
            for alias in $aliases; do
                alias="$(rh_normalize_name "$alias")"
                if [ -n "$alias" ] && [ "$alias" = "$norm" ]; then
                    IFS="$oldifs"
                    printf '%s\n' "$file"
                    return 0
                fi
            done
            IFS="$oldifs"
        done
    done
    printf '%s\n' "$profiledir/default.profile"
}

rh_profile_display_name() {
    profile="$1"; name="$(rh_profile_raw_value "$profile" name 2>/dev/null || true)"
    [ -n "$name" ] || name="$(basename "$profile" .profile)"
    printf '%s\n' "$name"
}

rh_valid_keycode() {
    case "$1" in ''|none|NONE|None) return 1 ;; *[!0-9]*) return 1 ;; *) [ "$1" -ge 0 ] 2>/dev/null && [ "$1" -le 255 ] 2>/dev/null ;; esac
}

# Build config.ron using ONLY the button names accepted by the frozen frontend.
# Known-good names are inherited from the original working v0.5.x config.
# Frozen frontend uses lowercase/hyphenated GamepadButton names.
# Physical A is removed from its stock South binding before Ruffle starts.
# When a profile declares a numeric `south` key, the launcher routes physical A
# through RightTrigger and this config maps it to that key. With `south=none`, A
# is available only to an explicit mouse_click helper assignment.
rh_write_config_ron() {
    profile="$1"; defaults="$2"; output="$3"; swf_name="${4:-movie.swf}"
    [ -f "$defaults" ] || return 2
    [ -f "$profile" ] || profile="$defaults"

    emit_map() {
        ron_name="$1"; profile_key="$2"
        val="$(rh_profile_value "$profile" "$defaults" "$profile_key" 2>/dev/null || true)"
        rh_valid_keycode "$val" && printf '        "%s": %s,\n' "$ron_name" "$val"
    }

    {
        echo 'Config('
        echo '    gamepad_config: {'
        emit_map 'dpad-up' dpad_up
        emit_map 'dpad-down' dpad_down
        emit_map 'dpad-left' dpad_left
        emit_map 'dpad-right' dpad_right

        # The frozen frontend treats physical A/South as a native click. The
        # launcher always removes that raw binding. A numeric South action is
        # exposed through the safe RightTrigger route instead.
        legacy_mode="$(rh_profile_raw_value "$profile" native_a_mode 2>/dev/null || true)"
        if [ "$legacy_mode" = "native" ]; then
            val="none"
        else
            val="$(rh_profile_value "$profile" "$defaults" south 2>/dev/null || true)"
        fi
        if rh_valid_keycode "$val"; then
            printf '        "right-trigger": %s,\n' "$val"
        else
            emit_map 'right-trigger' right_trigger
        fi

        emit_map 'east' east
        emit_map 'west' west
        emit_map 'north' north
        emit_map 'start' start
        emit_map 'select' select
        emit_map 'left-trigger' left_trigger
        echo '    },'
        echo '    swf_url: None,'
        printf '    swf_name: Some("%s")\n' "$swf_name"
        echo ')'
    } > "$output"
}

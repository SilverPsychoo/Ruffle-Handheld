#!/bin/bash
# Ruffle Handheld v0.8.26 stable/adaptive engine selector.

rh_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

rh_is_trimui_brick() {
    device_key="$(rh_lower "${DEVICE_NAME:-}")"
    cfw_key="$(rh_lower "${CFW_NAME:-}")"
    case "$device_key" in
        *trimui*brick*|tui-brick) return 0 ;;
    esac
    [ "$cfw_key" = "trimui" ] && \
        [ "${DISPLAY_WIDTH:-}" = "1024" ] && \
        [ "${DISPLAY_HEIGHT:-}" = "768" ]
}

rh_select_engine() {
    stable_bin="$1"
    adaptive_bin="$2"
    preference="$(rh_lower "${RUFFLE_HANDHELD_ENGINE:-auto}")"
    RH_ENGINE_MODE="stable"
    RH_ENGINE_REASON="stable default"

    case "$preference" in
        adaptive|next|test)
            RH_ENGINE_MODE="adaptive"
            RH_ENGINE_REASON="profile or environment requested adaptive engine"
            ;;
        stable|legacy)
            RH_ENGINE_MODE="stable"
            RH_ENGINE_REASON="profile or environment requested stable engine"
            ;;
        *)
            if rh_is_trimui_brick; then
                RH_ENGINE_MODE="adaptive"
                RH_ENGINE_REASON="TrimUI Brick 1024x768 adapter"
            fi
            ;;
    esac

    if [ "$RH_ENGINE_MODE" = "adaptive" ] && [ ! -f "$adaptive_bin" ]; then
        RH_ENGINE_MODE="stable"
        RH_ENGINE_REASON="adaptive binary missing; stable fallback"
    fi

    if [ "$RH_ENGINE_MODE" = "adaptive" ]; then
        RH_ENGINE_BIN="$adaptive_bin"
        case "${DISPLAY_WIDTH:-}" in *[!0-9]*|'') ;; *) RUFFLE_HANDHELD_WIDTH="$DISPLAY_WIDTH"; export RUFFLE_HANDHELD_WIDTH ;; esac
        case "${DISPLAY_HEIGHT:-}" in *[!0-9]*|'') ;; *) RUFFLE_HANDHELD_HEIGHT="$DISPLAY_HEIGHT"; export RUFFLE_HANDHELD_HEIGHT ;; esac
    else
        RH_ENGINE_BIN="$stable_bin"
    fi

    export RH_ENGINE_MODE RH_ENGINE_REASON RH_ENGINE_BIN
}

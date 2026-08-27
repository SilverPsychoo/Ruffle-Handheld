#!/bin/bash
# Ruffle Handheld performance helper v0.8.0
# Safe governor boost for EmuELEC/RK3326-class devices.
# No overclocking: only selects the kernel's existing "performance" governor.

RH_PERF_STATE=""

rh_perf_begin() {
    log="${1:-}"
    [ "${RUFFLE_PERFORMANCE:-1}" = "0" ] && {
        [ -n "$log" ] && echo "Performance mode: disabled by RUFFLE_PERFORMANCE=0" >> "$log"
        return 0
    }

    RH_PERF_STATE="/tmp/ruffle_handheld_perf_$$.state"
    : > "$RH_PERF_STATE" 2>/dev/null || { RH_PERF_STATE=""; return 0; }

    changed=0
    rh_perf_set_one() {
        path="$1"
        [ -f "$path" ] || return 0
        old="$(cat "$path" 2>/dev/null | tr -d '\r\n')"
        [ -n "$old" ] || return 0
        if printf '%s\n' performance 2>/dev/null > "$path"; then
            printf '%s\t%s\n' "$path" "$old" >> "$RH_PERF_STATE"
            changed=$((changed + 1))
        fi
    }

    # Prefer cpufreq policy nodes. Use cpu0 only on kernels without policy nodes,
    # avoiding saving/restoring two aliases for the same CPU governor.
    have_policy=0
    for path in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
        [ -f "$path" ] || continue
        have_policy=1
        rh_perf_set_one "$path"
    done
    if [ "$have_policy" -eq 0 ]; then
        rh_perf_set_one /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    fi

    rh_perf_set_one /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/governor
    rh_perf_set_one /sys/devices/platform/dmc/devfreq/dmc/governor

    unset -f rh_perf_set_one 2>/dev/null || true

    if [ "$changed" -gt 0 ]; then
        [ -n "$log" ] && echo "Performance mode: enabled ($changed governors; originals saved)" >> "$log"
    else
        rm -f "$RH_PERF_STATE" 2>/dev/null || true
        RH_PERF_STATE=""
        [ -n "$log" ] && echo "Performance mode: unavailable/unchanged" >> "$log"
    fi
}
rh_perf_end() {
    log="${1:-}"
    [ -n "$RH_PERF_STATE" ] && [ -f "$RH_PERF_STATE" ] || return 0

    restored=0
    while IFS=$'\t' read -r path old; do
        [ -f "$path" ] || continue
        [ -n "$old" ] || continue
        if printf '%s\n' "$old" 2>/dev/null > "$path"; then
            restored=$((restored + 1))
        fi
    done < "$RH_PERF_STATE"

    rm -f "$RH_PERF_STATE" 2>/dev/null || true
    RH_PERF_STATE=""
    [ -n "$log" ] && echo "Performance mode: restored ($restored governors)" >> "$log"
}

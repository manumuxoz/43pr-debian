#!/bin/sh
# One value per line for the Quickshell Power page. Read-only.
# Every line is always printed: missing knobs become empty lines and the UI
# shows "—" instead of breaking the parser.
set -u

cpu=/sys/devices/system/cpu/cpu0

value() {
    printf '%s\n' "$(cat "$1" 2>/dev/null)"
}

value "$cpu/cpufreq/scaling_governor"
value "$cpu/cpufreq/energy_performance_preference"
value /sys/firmware/acpi/platform_profile
printf '%s\n' "$(systemctl is-active power-profiles-daemon 2>/dev/null)"
value /sys/devices/system/cpu/intel_pstate/no_turbo

fan=""
for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = "acpi_fan" ]; then
        fan="$(cat "$h/fan1_input" 2>/dev/null)"
        break
    fi
done
printf '%s\n' "$fan"

value "$cpu/thermal_throttle/package_throttle_count"

printf '%s\n' "$(awk 'NR > 1 { printf "%s ", $1 }' /proc/swaps 2>/dev/null | sed 's/ *$//')"

temp=""
for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ] && [ -r "$h/temp1_input" ]; then
        temp=$(( $(cat "$h/temp1_input") / 1000 ))
        break
    fi
done
printf '%s\n' "$temp"

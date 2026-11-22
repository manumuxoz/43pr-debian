#!/bin/sh
# One-time setup for the privileged controls in Settings → System / Power:
#
#   - CPU MODE selector (ACPI platform_profile)
#   - Turbo Boost toggle (intel_pstate/no_turbo)
#   - battery charge limit (charge_control_end_threshold)
#
# Installs a narrow sudoers rule that allows the current user to write those
# exact sysfs files through `sudo -n /usr/bin/tee <path>` without a password.
# The rule permits nothing else, and the kernel still validates every value.
#
# Run once with:
#   sudo bash scripts/install-power-sudoers.sh
# or, from a graphical session:
#   pkexec bash scripts/install-power-sudoers.sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo bash $0" >&2
    exit 1
fi

if [ -n "${SUDO_USER:-}" ]; then
    target_user="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    target_user="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
else
    echo "Cannot determine the target user." >&2
    echo "Run with sudo, or set SUDO_USER=your-user." >&2
    exit 1
fi

if [ -z "$target_user" ] || ! id "$target_user" >/dev/null 2>&1; then
    echo "Invalid target user: ${target_user:-<empty>}" >&2
    exit 1
fi

rule=/etc/sudoers.d/43pr-power
legacy=/etc/sudoers.d/43pr-cpu-profile
tmp="$(mktemp /etc/sudoers.d/.43pr-power.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<EOF
# 43pr-debian: passwordless power controls from Settings → System / Power.
$target_user ALL=(root) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile, \\
    /usr/bin/tee /sys/devices/system/cpu/intel_pstate/no_turbo, \\
    /usr/bin/tee /sys/class/power_supply/BAT0/charge_control_end_threshold
EOF

chmod 0440 "$tmp"
visudo -cf "$tmp" >/dev/null
chown root:root "$tmp"
mv "$tmp" "$rule"
trap - EXIT

# The single-purpose rule from older releases is superseded by 43pr-power.
if [ -e "$legacy" ]; then
    rm -f "$legacy"
    echo "Removed legacy $legacy."
fi

echo "Installed $rule for user $target_user."
echo "Controls enabled: CPU MODE, Turbo Boost and the battery charge limit."
echo "Re-run this script after moving the repository or changing your username."

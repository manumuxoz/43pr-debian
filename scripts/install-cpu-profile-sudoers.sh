#!/bin/sh
# One-time setup for the Settings → System CPU MODE selector.
#
# Installs a narrow sudoers rule so the current user can write the ACPI
# platform profile through `sudo -n /usr/bin/tee <profile>` without a
# password. The rule only permits that exact command and path; the kernel
# still validates the profile value.
#
# Run once with:
#   sudo bash scripts/install-cpu-profile-sudoers.sh
# or, from a graphical session:
#   pkexec bash scripts/install-cpu-profile-sudoers.sh

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

rule=/etc/sudoers.d/43pr-cpu-profile
tmp="$(mktemp /etc/sudoers.d/.43pr-cpu-profile.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<EOF
# 43pr-debian: passwordless CPU platform profile changes from Settings → System.
$target_user ALL=(root) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile
EOF

chmod 0440 "$tmp"
visudo -cf "$tmp" >/dev/null
chown root:root "$tmp"
mv "$tmp" "$rule"
trap - EXIT

echo "Installed $rule for user $target_user."

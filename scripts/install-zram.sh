#!/usr/bin/env bash
# 43pr-debian: compressed RAM swap (zram) through systemd-zram-generator.
# Usage: sudo bash scripts/install-zram.sh [--dry-run|--remove|--force|--help]
set -eu

CONF=/etc/systemd/zram-generator.conf
SYSCTL=/etc/sysctl.d/99-43pr-zram.conf
UNIT=systemd-zram-setup@zram0.service

dry_run=0 remove=0 force=0
usage() {
    cat <<'EOF'
Usage: sudo bash scripts/install-zram.sh [--dry-run] [--remove] [--force]

  --dry-run  Print every planned action; change nothing.
  --remove   Disable zram swap and remove the 43pr-debian config files.
  --force    Overwrite foreign config files (backed up first) and continue
             even if zram-tools is installed.
  --help     Show this help.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --remove) remove=1 ;;
        --force) force=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

say() { printf '%s\n' "$*"; }
plan() { printf 'DRY-RUN: %s\n' "$*"; }
installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# Refuse to replace a config we do not own unless --force. Foreign files are
# always backed up before being overwritten.
check_foreign() {
    file=$1
    [ -e "$file" ] || return 0
    grep -q '^# 43pr-debian' "$file" 2>/dev/null && return 0
    if [ "$force" -eq 0 ]; then
        echo "Refusing to overwrite foreign file: $file" >&2
        echo "Re-run with --force to back it up and replace it." >&2
        exit 1
    fi
    backup="$file.bak-$(date +%Y%m%d-%H%M%S)"
    if [ "$dry_run" -eq 1 ]; then
        plan "back up $file -> $backup"
    else
        cp -a "$file" "$backup"; say "Backed up $file -> $backup"
    fi
}

write_file() {
    file=$1 content=$2
    if [ -f "$file" ] && [ "$(cat "$file")" = "$content" ]; then
        say "Already up to date: $file"; return 0
    fi
    check_foreign "$file"
    if [ "$dry_run" -eq 1 ]; then
        plan "write $file:"; printf '%s\n' "$content" | sed 's/^/    /'
    else
        printf '%s\n' "$content" >"$file"; say "Wrote $file"
    fi
}

remove_mode() {
    if grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null; then
        if [ "$dry_run" -eq 1 ]; then
            plan "swapoff /dev/zram0"
        else
            if swapoff /dev/zram0; then say "Swap disabled: /dev/zram0"
            else echo "WARNING: could not swapoff /dev/zram0" >&2; fi
        fi
    else
        say "No active /dev/zram0 swap."
    fi
    if [ "$dry_run" -eq 1 ]; then
        plan "systemctl stop $UNIT"
    else
        systemctl stop "$UNIT" 2>/dev/null || true
        say "Stopped $UNIT (if it was active)."
    fi
    for file in "$CONF" "$SYSCTL"; do
        if [ ! -e "$file" ]; then say "Not present: $file"
        elif ! grep -q '^# 43pr-debian' "$file" 2>/dev/null; then say "Leaving foreign file untouched: $file"
        elif [ "$dry_run" -eq 1 ]; then plan "rm -f $file"
        else rm -f "$file"; say "Removed $file"; fi
    done
    if [ "$dry_run" -eq 1 ]; then
        plan "systemctl daemon-reload"; plan "sysctl --system"
        say "Dry run complete; nothing changed."; return 0
    fi
    systemctl daemon-reload
    sysctl --system >/dev/null || echo "WARNING: sysctl --system reported errors" >&2
    say "zram configuration removed; package systemd-zram-generator kept."
}

if [ "$remove" -eq 1 ]; then
    remove_mode; exit 0
fi

if installed zram-tools; then
    if [ "$force" -eq 1 ]; then
        say "WARNING: zram-tools is installed; continuing because of --force."
        say "         Its zramswap.service may compete for /dev/zram0."
    else
        echo "zram-tools is installed and conflicts with systemd-zram-generator." >&2
        echo "Remove it first (sudo apt-get remove zram-tools) or re-run with --force." >&2
        exit 1
    fi
fi

if ! installed systemd-zram-generator; then
    if ! apt-cache show systemd-zram-generator >/dev/null 2>&1; then
        echo "systemd-zram-generator is not available in the configured apt sources." >&2
        echo "Enable the Debian main repository, run apt update, and retry." >&2
        exit 1
    fi
    if [ "$dry_run" -eq 1 ]; then plan "apt-get install -y systemd-zram-generator"
    elif ! apt-get install -y systemd-zram-generator; then
        echo "Failed to install systemd-zram-generator; check network/apt sources (no apt update is run)." >&2
        exit 1
    fi
else
    say "systemd-zram-generator is already installed."
fi

if grep -qw disk /sys/power/state 2>/dev/null || grep -q 'resume=' /proc/cmdline 2>/dev/null; then
    say "WARNING: hibernation is configured; zram swap cannot hibernate. Keep a disk swap partition or disable it."
fi

conf_content='# 43pr-debian: compressed RAM swap (zram)
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap'

sysctl_content='# 43pr-debian: VM tuning for compressed RAM swap (zram)
vm.swappiness = 150
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125'

write_file "$CONF" "$conf_content"
write_file "$SYSCTL" "$sysctl_content"

if [ "$dry_run" -eq 1 ]; then
    plan "systemctl daemon-reload"; plan "sysctl --system"
    plan "systemctl start $UNIT"
    plan "verify /dev/zram0 in /proc/swaps and show zramctl output"
    say "Dry run complete; nothing changed."; exit 0
fi

systemctl daemon-reload
if ! sysctl --system >/dev/null; then
    echo "Failed to apply sysctl settings; inspect: sysctl --system" >&2
    exit 1
fi
if ! systemctl start "$UNIT"; then
    echo "Failed to start $UNIT. Inspect: journalctl -u $UNIT -b --no-pager" >&2
    exit 1
fi

i=0
while [ "$i" -lt 10 ]; do
    grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null && break
    sleep 0.5; i=$((i + 1))
done
if ! grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null; then
    echo "zram0 did not become active swap within 5 seconds." >&2
    echo "Inspect: journalctl -u $UNIT -b --no-pager; then: zramctl; cat /proc/swaps" >&2
    exit 1
fi

say "Active swap:"
grep -E '^(Filename|/dev/zram0)' /proc/swaps
if command -v zramctl >/dev/null 2>&1; then zramctl /dev/zram0
elif [ -x /usr/sbin/zramctl ]; then /usr/sbin/zramctl /dev/zram0; fi
say "zram is enabled for this boot and will start automatically at boot."

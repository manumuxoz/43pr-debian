#!/usr/bin/env bash
# uninstall.sh — restore the configuration backed up by install.sh.
#
# Works only inside your HOME. Current configs are not deleted: they are moved
# to <backup>/post-uninstall-removed/ before the backup is restored.
set -Eeuo pipefail

CONFIG_DIRS=(43pr dunst hypr kitty matugen quickshell rofi waybar wlogout wofi)
BACKUP_ROOT="$HOME/.config-backups"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [--yes|-y] [--dry-run] [backup-dir]

Restores the configuration that install.sh backed up.
Without arguments the most recent ~/.config-backups/43pr-debian-* is used.

  -y, --yes      do not ask for confirmation
  -n, --dry-run  show the plan, change nothing
  -h, --help     show this help
EOF
}

ASSUME_YES=0
DRY_RUN=0
BACKUP_ARG=""
for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           warn "Unknown option: $arg"; usage; exit 2 ;;
        *)            BACKUP_ARG="$arg" ;;
    esac
done

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    warn "Do not run this script as root: it works on your user's HOME."
    exit 1
fi

if [[ -n "$BACKUP_ARG" ]]; then
    BACKUP="$BACKUP_ARG"
else
    BACKUP="$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name '43pr-debian-*' \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2- || true)"
fi

if [[ -z "${BACKUP:-}" || ! -d "$BACKUP" ]]; then
    warn "No backup found under $BACKUP_ROOT (43pr-debian-*)."
    warn "Pass the backup dir explicitly: ./uninstall.sh /path/to/backup"
    exit 1
fi

REMOVED="$BACKUP/post-uninstall-removed"
say "Using backup: $BACKUP"

to_restore=()
to_remove=()
for d in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$BACKUP/config/$d" ]]; then
        to_restore+=("$d")
    elif [[ -e "$HOME/.config/$d" ]]; then
        to_remove+=("$d")
    fi
done

cat <<EOF
Planned actions:
  restore from backup: ${to_restore[*]:-(none)}
  move aside (new):    ${to_remove[*]:-(none)}
  moved dirs go to:    $REMOVED
EOF

if [[ $ASSUME_YES -eq 0 ]]; then
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] nothing was changed."
    exit 0
fi

mkdir -p "$REMOVED"
for d in "${to_remove[@]}"; do
    mv "$HOME/.config/$d" "$REMOVED/$d"
done
for d in "${to_restore[@]}"; do
    if [[ -e "$HOME/.config/$d" ]]; then
        mv "$HOME/.config/$d" "$REMOVED/$d"
    fi
    cp -a "$BACKUP/config/$d" "$HOME/.config/$d"
done

say "Restore done."
cat <<EOF

Notes:
  - Helpers installed by install.sh are left in place; remove them with:
      rm ~/.local/bin/awww ~/.local/bin/screen-record.sh
      rm -rf ~/.local/share/fonts/43pr && fc-cache -f
  - The post-install configs were moved to:
      $REMOVED
  - Restart your session for the restored configuration to load.
EOF

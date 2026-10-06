#!/usr/bin/env bash
# 43pr-debian — installer for the Debian 13 (trixie) adaptation of the 43PR rice.
#
# Run as your regular user (never with sudo/root):
#     ./install.sh          # interactive
#     ./install.sh --yes    # non-interactive
#
# It only touches your HOME:
#   ~/.config/{43pr,dunst,hypr,kitty,matugen,quickshell,rofi,waybar,wlogout,wofi}
#   ~/.local/bin/{awww,screen-record.sh}
#   ~/.local/share/fonts/43pr/
# Existing directories are backed up first under ~/.config-backups/43pr-debian-<date>/.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIRS=(43pr dunst hypr kitty matugen quickshell rofi waybar wlogout wofi)
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP="$HOME/.config-backups/43pr-debian-$STAMP"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    warn "Do not run this script as root: it installs into your user's HOME."
    exit 1
fi

if ! command -v start-hyprland >/dev/null 2>&1; then
    warn "Hyprland (start-hyprland) was not found. Install the packages first,"
    warn "see packages.txt / README.md (trixie-backports)."
fi

cat <<EOF
This will install the 43pr-debian configuration into:
  ~/.config/{$(IFS=,; echo "${CONFIG_DIRS[*]}")}
  ~/.local/bin/{awww,screen-record.sh}
  ~/.local/share/fonts/43pr/

Existing files are backed up to: $BACKUP
EOF

if [[ "${1:-}" != "-y" && "${1:-}" != "--yes" ]]; then
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --- backup -----------------------------------------------------------------
backed_up=0
mkdir -p "$BACKUP/config"
for d in "${CONFIG_DIRS[@]}"; do
    if [[ -e "$HOME/.config/$d" ]]; then
        cp -a "$HOME/.config/$d" "$BACKUP/config/$d"
        backed_up=1
    fi
done
if [[ $backed_up -eq 1 ]]; then
    say "Previous configs backed up to $BACKUP"
else
    rmdir "$BACKUP/config" "$BACKUP" 2>/dev/null || true
fi

# --- configs -----------------------------------------------------------------
for d in "${CONFIG_DIRS[@]}"; do
    mkdir -p "$HOME/.config/$d"
    cp -a "$REPO/config/$d/." "$HOME/.config/$d/"
done
say "Configs copied to ~/.config/"

# --- local/bin ----------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
cp -a "$REPO/local/bin/." "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/awww" "$HOME/.local/bin/screen-record.sh"

# --- fonts ---------------------------------------------------------------------
mkdir -p "$HOME/.local/share/fonts/43pr"
cp -a "$REPO/assets/fonts/." "$HOME/.local/share/fonts/43pr/"
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f >/dev/null
fi
say "Roboto Mono installed in ~/.local/share/fonts/43pr/"

# --- helper permissions ---------------------------------------------------------
find "$HOME/.config/hypr/scripts" "$HOME/.config/waybar/scripts" \
     "$HOME/.config/quickshell/scripts" \
     -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

# --- theme (generates the files excluded from the repo) ---------------------------
if command -v python3 >/dev/null 2>&1; then
    say "Generating theme files (theme.py apply)..."
    if ! python3 "$HOME/.config/43pr/bin/theme.py" apply; then
        warn "theme.py failed; fix the error and run:"
        warn "  python3 ~/.config/43pr/bin/theme.py apply"
    fi
else
    warn "python3 not found. Install it and run:"
    warn "  python3 ~/.config/43pr/bin/theme.py apply"
fi

cat <<EOF

Done.

Next steps:
  1. Monitors: adapt ~/.config/hypr/monitors.lua for your screens
     (or use ~/.config/hypr/scripts/monitor-ctl.sh). The repo ships the
     layout of the original laptop: eDP-1 2880x1800 scale 1.75 + DP-3.
  2. Wallpaper folder: config/quickshell/hyprquickpaper/config.json points to
     \$HOME/Imágenes/Wallpapers — change it if your folder has another name.
  3. Log out and start a Hyprland session (greeter, display manager, or
     'start-hyprland' from a TTY).
  4. Optional pieces:
       Waybar/Lua shim ... docs/waybar-hyprland-lua-shim.md
       hyprlogin greeter . docs/hyprlogin.md
       fingerprint ....... docs/fingerprint.md
       hardware notes .... docs/hardware.md

Rollback: your previous configs (if any) are in:
  $BACKUP
EOF

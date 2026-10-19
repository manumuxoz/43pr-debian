#!/usr/bin/env bash
# update.sh — copy the new/changed files from this checkout into an existing
# 43pr-debian installation.
#
# This port COPIES files into ~/.config (it does not symlink the repository),
# so `git pull` alone does not update the live configuration: pull first, then
# run this script. Only new or changed files are copied and every overwritten
# file is backed up first. Nothing is ever deleted, and package installation is
# report-only (see packages.txt).
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_ROOT="$HOME/.config-backups"
BACKUP="$BACKUP_ROOT/update-$STAMP"
KEEP_BACKUPS=5

# Packages the configuration expects. Extras that only some setups need live
# in OPTIONAL_PACKAGES / packages.txt and are reported separately.
PACKAGES=(
    hyprland hyprland-guiutils hypridle hyprlock hyprpaper hyprpicker
    hyprsunset xdg-desktop-portal-hyprland quickshell
    waybar dunst wofi kitty wlogout mpv ffmpeg
    grim slurp wl-clipboard cliphist
    brightnessctl playerctl network-manager-gnome polkit-kde-agent-1
    swaybg jq imagemagick python3 greetd
    zenity libnotify-bin xdg-desktop-portal-gtk papirus-icon-theme
    xdg-user-dirs xdg-utils
)
OPTIONAL_PACKAGES=(
    thunar thunar-volman thunar-archive-plugin gvfs tumbler ffmpegthumbnailer
    python3-pil pavucontrol blueman
)

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

usage() {
    cat <<'EOF'
Usage: ./update.sh [options]

Copies new/changed files from this checkout into your HOME and regenerates the
theme. Existing files are backed up, one by one, under:

  ~/.config-backups/update-<timestamp>/

The script never deletes files, never installs packages and never runs
`git pull`. Pull the repository yourself first.

  -y, --yes            do not ask for confirmation
  -n, --dry-run        show the plan, change nothing
  -d, --diff           show a unified diff for each changed file
      --skip-theme     do not run theme.py apply
      --skip-packages  do not report missing apt packages
      --restart-shell  restart Quickshell (qs) after updating
  -h, --help           show this help
EOF
}

ASSUME_YES=0
DRY_RUN=0
SHOW_DIFF=0
SKIP_THEME=0
SKIP_PACKAGES=0
RESTART_SHELL=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)         ASSUME_YES=1 ;;
        -n|--dry-run)     DRY_RUN=1 ;;
        -d|--diff)        SHOW_DIFF=1 ;;
        --skip-theme)     SKIP_THEME=1 ;;
        --skip-packages)  SKIP_PACKAGES=1 ;;
        --restart-shell)  RESTART_SHELL=1 ;;
        -h|--help)        usage; exit 0 ;;
        *)                warn "Unknown option: $arg"; usage; exit 2 ;;
    esac
done

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    warn "Do not run this script as root: it installs into your user's HOME."
    exit 1
fi

if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
        warn "This checkout has uncommitted changes; the update copies the working tree."
    fi
fi

# Generated at install time (theme.py recreates them) or per-user state.
is_generated() {
    case "$1" in
        config/hypr/hyprlock-colors.conf|config/waybar/colors.css|config/wlogout/colors.css|config/wofi/style.css|config/kitty/matugen.conf|config/quickshell/state/*)
            return 0 ;;
        *) return 1 ;;
    esac
}

# Scan $1 into $2 and store "status|label|rel|src|dst" entries in CHANGES.
scan_tree() {
    local src_root="$1" dst_root="$2" label="$3"
    local src rel dst status
    [[ -d "$src_root" ]] || return 0
    while IFS= read -r -d '' src; do
        rel="${src#"$src_root"/}"
        is_generated "${src#"$REPO"/}" && continue
        dst="$dst_root/$rel"
        if [[ ! -e "$dst" ]]; then
            status="new"
        elif ! cmp -s "$src" "$dst"; then
            status="upd"
        else
            continue
        fi
        CHANGES+=("$status|$label|$rel|$src|$dst")
    done < <(find "$src_root" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print0)
}

CHANGES=()
scan_tree "$REPO/config" "$HOME/.config" "config"
scan_tree "$REPO/local/bin" "$HOME/.local/bin" "local-bin"
scan_tree "$REPO/assets/fonts" "$HOME/.local/share/fonts/43pr" "fonts"

added=0
updated=0
for entry in ${CHANGES[@]+"${CHANGES[@]}"}; do
    [[ "${entry%%|*}" == "new" ]] && added=$((added + 1)) || updated=$((updated + 1))
done

say "Checkout: $REPO"
say "Changes: $added new, $updated updated"
if [[ ${#CHANGES[@]} -gt 0 ]]; then
    for entry in "${CHANGES[@]}"; do
        IFS='|' read -r status label rel src dst <<<"$entry"
        printf '  %s  %s/%s\n' "$([[ $status == new ]] && echo '+' || echo '~')" "$label" "$rel"
    done
else
    say "Everything is already up to date."
fi

if [[ $SHOW_DIFF -eq 1 && ${#CHANGES[@]} -gt 0 ]]; then
    say "Differences (live -> checkout):"
    for entry in "${CHANGES[@]}"; do
        IFS='|' read -r status label rel src dst <<<"$entry"
        printf '\n--- %s/%s ---\n' "$label" "$rel"
        if [[ -f "$dst" ]]; then
            diff -u --label "live/$label/$rel" --label "checkout/$label/$rel" "$dst" "$src" || true
        else
            diff -u --label /dev/null --label "checkout/$label/$rel" /dev/null "$src" || true
        fi
    done
    echo
fi

if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] nothing was changed."
    exit 0
fi

if [[ $ASSUME_YES -eq 0 ]]; then
    read -r -p "Apply these changes? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if [[ ${#CHANGES[@]} -gt 0 ]]; then
    mkdir -p "$BACKUP"
    {
        printf '43pr-debian update %s\n' "$STAMP"
        printf 'checkout: %s\n\n' "$REPO"
    } >"$BACKUP/CHANGES.txt"
fi

backed_up=0
copied=0
for entry in ${CHANGES[@]+"${CHANGES[@]}"}; do
    IFS='|' read -r status label rel src dst <<<"$entry"
    mkdir -p "$(dirname -- "$dst")"
    if [[ -e "$dst" ]]; then
        bdir="$BACKUP/$label/$(dirname -- "$rel")"
        mkdir -p "$bdir"
        if ! cp -a "$dst" "$BACKUP/$label/$rel"; then
            warn "backup failed for $dst; aborting before it is overwritten."
            exit 1
        fi
        backed_up=$((backed_up + 1))
        printf '%s  %s/%s\n' "$status" "$label" "$rel" >>"$BACKUP/CHANGES.txt"
    else
        printf 'new  %s/%s\n' "$label" "$rel" >>"$BACKUP/CHANGES.txt"
    fi
    if ! cp -a "$src" "$dst"; then
        warn "copy failed: $src -> $dst"
        exit 1
    fi
    case "$rel" in
        *.sh|*.py) chmod +x "$dst" ;;
    esac
    copied=$((copied + 1))
done

if [[ $copied -gt 0 ]]; then
    say "Copied $copied file(s); $backed_up backed up in $BACKUP"
else
    say "No files needed updating."
fi

# --- fonts --------------------------------------------------------------------
if [[ $copied -gt 0 ]] && [[ -d "$HOME/.local/share/fonts/43pr" ]]; then
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
fi

# --- keep only the newest backups ----------------------------------------------
if [[ -d "$BACKUP_ROOT" ]]; then
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'update-*' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | tail -n "+$((KEEP_BACKUPS + 1))" | cut -d' ' -f2- \
        | while IFS= read -r old; do rm -rf -- "$old"; done
fi

# --- packages (report only) -----------------------------------------------------
report_packages() {
    local p missing=() optional_missing=()
    for p in "${PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed' \
            || missing+=("$p")
    done
    for p in "${OPTIONAL_PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed' \
            || optional_missing+=("$p")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing[*]}"
        warn "Install them with: sudo apt install ${missing[*]}"
    else
        say "All required packages are installed."
    fi
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        say "Optional, not installed: ${optional_missing[*]}"
    fi
}
[[ $SKIP_PACKAGES -eq 0 ]] && report_packages

# --- theme (generates the files excluded from the repo) --------------------------
if [[ $SKIP_THEME -eq 0 ]] && command -v python3 >/dev/null 2>&1; then
    say "Regenerating theme files (theme.py apply)..."
    if ! python3 "$HOME/.config/43pr/bin/theme.py" apply; then
        warn "theme.py failed; fix the error and run:"
        warn "  python3 ~/.config/43pr/bin/theme.py apply"
    fi
fi

# --- optional shell restart -----------------------------------------------------
if [[ $RESTART_SHELL -eq 1 ]]; then
    if pgrep -x qs >/dev/null 2>&1; then
        say "Restarting Quickshell..."
        pkill -x qs || true
        sleep 1
        setsid -f env QSG_RENDER_LOOP=basic qs >/dev/null 2>&1 || true
    else
        warn "Quickshell (qs) is not running; nothing to restart."
    fi
fi

cat <<EOF

Done. Files removed from the repo are left untouched in ~/.config; review them
manually if you want to clean up (for example, leftovers from removed features).
EOF

#!/usr/bin/env bash
# upstream-diff.sh — compare this Debian port against the upstream 43PR dotfiles.
#
# Clones (or updates) the upstream repository into a cache directory and shows
# which files differ from the configs in this repo, so changes can be reviewed
# and ported manually. Generated files (colors, etc.) are expected to differ.
set -Eeuo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/43PR/dotfiles.git}"
CACHE="${UPSTREAM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/43pr-debian/upstream}"
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIRS=(43pr dunst hypr kitty matugen quickshell rofi waybar wlogout wofi)

usage() {
    cat <<'EOF'
Usage: tools/upstream-diff.sh [component]

Compares this repo's config/ against the upstream 43PR dotfiles.

  component      diff only one component (43pr, dunst, hypr, kitty, matugen,
                 quickshell, rofi, waybar, wlogout, wofi)

Environment:
  UPSTREAM_URL    upstream git URL
                  (default: https://github.com/43PR/dotfiles.git)
  UPSTREAM_CACHE  clone location
                  (default: ~/.cache/43pr-debian/upstream)
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
FILTER="${1:-}"

if [[ -d "$CACHE/.git" ]]; then
    echo "Updating $CACHE ..."
    if ! git -C "$CACHE" pull --ff-only --quiet; then
        echo "Could not update the cached clone. Remove it and retry:"
        echo "  rm -rf \"$CACHE\""
        exit 1
    fi
else
    echo "Cloning $UPSTREAM_URL ..."
    mkdir -p "$(dirname -- "$CACHE")"
    git clone --depth=1 --quiet "$UPSTREAM_URL" "$CACHE"
fi

echo "Upstream: $(git -C "$CACHE" log -1 --format='%h %cs %s')"
echo

found=0
for d in "${CONFIG_DIRS[@]}"; do
    [[ -z "$FILTER" || "$FILTER" == "$d" ]] || continue
    src="$CACHE/.config/$d"
    dst="$REPO/config/$d"
    [[ -d "$src" ]] || continue
    if [[ ! -d "$dst" ]]; then
        echo "== $d: exists upstream but not in this port"
        found=1
        continue
    fi
    files="$(diff -rq --exclude='__pycache__' "$src" "$dst" 2>/dev/null || true)"
    if [[ -n "$files" ]]; then
        found=1
        echo "== $d"
        printf '%s\n' "$files" | sed "s|$src|upstream/.config/$d|g; s|$dst|port/config/$d|g"
    fi
done

if [[ $found -eq 0 ]]; then
    echo "No differences found (for the selected component)."
fi

cat <<'EOF'

Notes:
  - Generated files (waybar/colors.css, hyprlock-colors.conf, wofi/style.css,
    rofi/colors.rasi, kitty/matugen.conf, wlogout/colors.css) are not committed
    here and will always show as missing; theme.py apply regenerates them.
  - Divergences are expected: this port adds Waybar, adapts monitors/keybinds
    and adds the Debian-specific hooks.
  - Waybar has no upstream counterpart (upstream uses the Quickshell bar).
EOF

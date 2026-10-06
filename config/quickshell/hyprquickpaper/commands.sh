#!/usr/bin/env bash
# Central wallpaper hook, called by hyprquickpaper with the chosen image path.

img="$1"
[[ -f "$img" ]] || { echo "commands.sh: not a file: $img" >&2; exit 1; }

# Adaptacion Debian: awww no está empaquetado en Debian; si no existe se usa
# el shim ~/.local/bin/awww (hyprpaper con respaldo swaybg).
if command -v awww >/dev/null 2>&1; then
    awww img "$img" -t random --transition-duration 1
else
    "$HOME/.local/bin/awww" img "$img"
fi

mkdir -p "$HOME/.cache/43pr"
setsid -f python3 "$HOME/.config/43pr/bin/theme.py" wallpaper "$img" \
    >>"$HOME/.cache/43pr/theme.log" 2>&1

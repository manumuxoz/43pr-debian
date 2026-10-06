#!/usr/bin/env bash
# Restaura al iniciar sesion el ultimo wallpaper elegido con el picker (SUPER+W).
# Lee ~/.local/state/43pr/state.json (lo escribe 43pr/theme.py) y lo pinta con
# swaybg: hyprpaper 0.8.4 de trixie-backports segfaultea al re-aplicar.
set -u

state="$HOME/.local/state/43pr/state.json"
wp=""

if [ -f "$state" ]; then
    wp=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaper",""))' "$state" 2>/dev/null || true)
fi

[ -n "$wp" ] && [ -f "$wp" ] || exit 0

pkill -x swaybg 2>/dev/null || true
sleep 0.2
# Modo stretch: ajusta la imagen a los bordes de la pantalla aunque se deforme.
setsid -f swaybg -i "$wp" -m stretch >/dev/null 2>&1

#!/usr/bin/env bash
# Capturas de pantalla (grim).
# Uso: screenshot.sh [area]
#   sin argumentos -> captura el monitor con el foco (grim -o)
#   area           -> seleccion libre con slurp (grim -g)
# Guarda en "$XDG_PICTURES/Capturas de pantalla/" (resuelto via xdg-user-dir),
# copia al portapapeles y notifica por Quickshell (tolerante a fallos).
set -u

pictures="$(xdg-user-dir PICTURES 2>/dev/null || true)"
[ -n "$pictures" ] || pictures="$HOME/Pictures"
dir="$pictures/Capturas de pantalla"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

if [ "${1:-}" = "area" ]; then
    geom="$(slurp 2>/dev/null)" || { qs ipc call screenshot cancelled || true; exit 0; }
    # Rechaza cancelaciones y geometrias 0x0 (slurp puede devolver "0,0 0x0").
    re='^-?[0-9]+,-?[0-9]+ [1-9][0-9]*x[1-9][0-9]*$'
    if [[ ! $geom =~ $re ]]; then
        qs ipc call screenshot cancelled || true
        exit 0
    fi
    grim -g "$geom" "$file" || exit 1
else
    # Monitor con el foco; si la deteccion falla, grim captura todo (sin -o).
    monitor="$(hyprctl -j monitors 2>/dev/null | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m.get("focused")), ""))' 2>/dev/null)"
    if [ -n "$monitor" ]; then
        grim -o "$monitor" "$file" || exit 1
    else
        grim "$file" || exit 1
    fi
fi

wl-copy --type image/png < "$file"
qs ipc call screenshot notify "$file" || true

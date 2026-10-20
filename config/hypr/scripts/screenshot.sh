#!/usr/bin/env bash
# Capturas de pantalla (grim).
# Uso: screenshot.sh [area|annotate]
#   sin argumentos -> captura el monitor con el foco (grim -o)
#   area           -> seleccion libre con slurp (grim -g)
#   annotate       -> seleccion libre y editor swappy para anotar
# Guarda en "$XDG_PICTURES/Capturas de pantalla/" (resuelto via xdg-user-dir),
# copia al portapapeles y notifica por Quickshell (tolerante a fallos).
set -u

pictures="$(xdg-user-dir PICTURES 2>/dev/null || true)"
[ -n "$pictures" ] || pictures="$HOME/Pictures"
dir="$pictures/Capturas de pantalla"
mkdir -p "$dir" || { notify-send "Captura" "No se pudo crear $dir" 2>/dev/null || true; exit 1; }
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

if [ "${1:-}" = "annotate" ]; then
    if ! command -v swappy >/dev/null 2>&1; then
        notify-send "Captura" "swappy no está instalado" 2>/dev/null || true
        exit 1
    fi
    geom="$(slurp 2>/dev/null)" || { qs ipc call screenshot cancelled || true; exit 0; }
    re='^-?[0-9]+,-?[0-9]+ [1-9][0-9]*x[1-9][0-9]*$'
    if [[ ! $geom =~ $re ]]; then
        qs ipc call screenshot cancelled || true
        exit 0
    fi
    tmp="$(mktemp --suffix=.png)" || { notify-send "Captura" "No se pudo crear el archivo temporal" 2>/dev/null || true; exit 1; }
    trap 'rm -f "$tmp"' EXIT
    grim -g "$geom" "$tmp" || { notify-send "Captura" "Error al capturar el área" 2>/dev/null || true; exit 1; }
    swappy -f "$tmp"
    exit 0
fi

if [ "${1:-}" = "area" ]; then
    geom="$(slurp 2>/dev/null)" || { qs ipc call screenshot cancelled || true; exit 0; }
    # Rechaza cancelaciones y geometrias 0x0 (slurp puede devolver "0,0 0x0").
    re='^-?[0-9]+,-?[0-9]+ [1-9][0-9]*x[1-9][0-9]*$'
    if [[ ! $geom =~ $re ]]; then
        qs ipc call screenshot cancelled || true
        exit 0
    fi
    grim -g "$geom" "$file" || { notify-send "Captura" "Error al capturar el área" 2>/dev/null || true; exit 1; }
else
    # Monitor con el foco; si la deteccion falla, grim captura todo (sin -o).
    monitor="$(hyprctl -j monitors 2>/dev/null | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m.get("focused")), ""))' 2>/dev/null)"
    if [ -n "$monitor" ]; then
        grim -o "$monitor" "$file" || { notify-send "Captura" "Error al capturar $monitor" 2>/dev/null || true; exit 1; }
    else
        grim "$file" || { notify-send "Captura" "Error al capturar la pantalla" 2>/dev/null || true; exit 1; }
    fi
fi

if wl-copy --type image/png < "$file"; then
    qs ipc call screenshot notify "$file" || true
else
    notify-send "Captura" "Guardada en $file (no se pudo copiar al portapapeles)" 2>/dev/null || true
fi

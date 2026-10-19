#!/usr/bin/env bash
# Cambia a un wallpaper aleatorio de la carpeta del selector (SUPER+ALT+W).
#
# DECISIÓN DEL PORT: solo cambia la imagen. NO regenera la paleta del tema ni
# actualiza el fondo de bloqueo/login; para eso usa el selector (SUPER+W) o
# `theme.py auto`. La imagen elegida sí se guarda en state.json para que
# wallpaper-restore.sh la recupere al iniciar sesión.
#
# Uso: random-wallpaper.sh [--dry-run]
set -euo pipefail

cfg="$HOME/.config/quickshell/hyprquickpaper/config.json"
[ -f "$cfg" ] || { notify-send "Fondo" "No existe $cfg" 2>/dev/null || true; exit 1; }

dir="$(jq -r '.wallpaper_path // empty' "$cfg" 2>/dev/null || true)"
dir="${dir//\$HOME/$HOME}"
[ -n "$dir" ] && [ -d "$dir" ] || {
    notify-send "Fondo" "Carpeta de wallpapers no válida: ${dir:-<vacía>}" 2>/dev/null || true
    exit 1
}

mapfile -t images < <(
    find "$dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
        -o -iname '*.png' -o -iname '*.webp' \) | sort
)
[ ${#images[@]} -gt 0 ] || {
    notify-send "Fondo" "No hay imágenes en $dir" 2>/dev/null || true
    exit 1
}

cache="${XDG_CACHE_HOME:-$HOME/.cache}/43pr"
last_file="$cache/last-random-wallpaper"
last=""
[ -f "$last_file" ] && last="$(<"$last_file")"

# Evita repetir el último aleatorio y el fondo actual registrado.
current=""
state="${XDG_STATE_HOME:-$HOME/.local/state}/43pr/state.json"
if [ -f "$state" ]; then
    current="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaper", ""))' "$state" 2>/dev/null || true)"
fi

candidates=()
for img in "${images[@]}"; do
    [ "$img" = "$last" ] && continue
    [ "$img" = "$current" ] && continue
    candidates+=("$img")
done
# Si solo hay una o dos imágenes, permite repetir antes que fallar.
[ ${#candidates[@]} -gt 0 ] || candidates=("${images[@]}")

img="$(printf '%s\n' "${candidates[@]}" | shuf -n1)"

if [ "${1:-}" = "--dry-run" ]; then
    printf '%s\n' "$img"
    exit 0
fi

# Cierra el selector si estuviera abierto.
qs ipc -p "$HOME/.config/quickshell/hyprquickpaper" call hyprquickpaper close \
    >/dev/null 2>&1 || true

# Misma lógica que hyprquickpaper/commands.sh: awww real o shim Debian.
if command -v awww >/dev/null 2>&1; then
    awww img "$img" -t random --transition-duration 1
else
    "$HOME/.local/bin/awww" img "$img"
fi

mkdir -p "$cache"
printf '%s\n' "$img" > "$last_file"

# Guarda la ruta para restaurarla al iniciar sesión, sin tocar la paleta.
python3 - "$img" <<'PY'
import fcntl, json, os, sys
from pathlib import Path

img = sys.argv[1]
home = Path.home()
state_dir = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "43pr"
cache_dir = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache")) / "43pr"
state = state_dir / "state.json"

state_dir.mkdir(parents=True, exist_ok=True)
cache_dir.mkdir(parents=True, exist_ok=True)
with open(cache_dir / "lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        data = json.loads(state.read_text())
    except Exception:
        data = {}
    data["wallpaper"] = img
    tmp = state.with_name("." + state.name + ".43pr-tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, state)
PY

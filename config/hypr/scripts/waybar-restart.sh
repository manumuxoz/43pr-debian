#!/bin/sh
# waybar-restart.sh — reinicia Waybar por completo (kill + arranque).
#
# Se usa desde el motor de temas (~/.config/43pr/targets.toml) para aplicar
# colors.css. No se usa SIGUSR2: en Waybar 0.12 ese "reload" vuelve a registrar
# los callbacks de monitor sin desconectar los anteriores, asi que tras apagar
# o reconectar el monitor externo aparecen varias barras apiladas (upstream
# issues #3344 y #4336). Un reinicio del proceso deja un solo estado limpio.
#
# Si Waybar no esta corriendo no hace nada: el motor de temas se puede ejecutar
# desde una TTY o durante una actualizacion sin sesion grafica.

set -u

pgrep -x waybar >/dev/null 2>&1 || exit 0

pkill -x waybar 2>/dev/null || true
i=0
while pgrep -x waybar >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
done

# Si no respondio a SIGTERM en 5 s, forzamos la salida antes de arrancar otro.
if pgrep -x waybar >/dev/null 2>&1; then
    pkill -KILL -x waybar 2>/dev/null || true
    sleep 0.2
fi

setsid -f sh "$HOME/.config/hypr/scripts/waybar-start.sh" >/dev/null 2>&1 || true

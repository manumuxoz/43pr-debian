#!/usr/bin/env bash
# Copia el wallpaper y los colores ACTUALES de tu tema 43pr a la pantalla de login.
#
# Normalmente NO hace falta ejecutarlo: theme.py sincroniza el login solo cada
# vez que cambias de fondo/tema. Este script queda como respaldo manual.
#
# Los ficheros del greeter son enlaces al directorio compartido /var/lib/hyprlogin:
#   /etc/hyprlogin/colors.conf            -> /var/lib/hyprlogin/colors.conf
#   /usr/share/hyprlogin/wallpaper.jpg    -> /var/lib/hyprlogin/wallpaper.jpg
# (activar-sync-login.sh crea los enlaces una sola vez; así el tema puede
#  actualizarlos sin sudo.)
set -Eeuo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con sudo."; exit 1; }
# Usuario objetivo: con sudo, SUDO_USER; si no, primer argumento.
USUARIO="${SUDO_USER:-${1:-}}"
if [ -z "$USUARIO" ] || ! id "$USUARIO" >/dev/null 2>&1; then
    echo "Uso: sudo sincronizar-login [usuario]  (o define SUDO_USER)." >&2
    exit 1
fi
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"
ESTADO="$HOME_USUARIO/.local/state/43pr/state.json"
COLORES="$HOME_USUARIO/.config/hypr/hyprlock-colors.conf"
DESTINO="/var/lib/hyprlogin"

install -d -o root -g "$USUARIO" -m 775 "$DESTINO"

WP="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaper",""))' "$ESTADO" 2>/dev/null || true)"
if [ -n "$WP" ] && [ -f "$WP" ]; then
    install -m644 "$WP" "$DESTINO/wallpaper.jpg"
    echo "Fondo de login actualizado desde: $WP"
else
    echo "No pude leer el wallpaper actual (¿cambió el estado de 43pr?)."
fi

if [ -f "$COLORES" ]; then
    install -m644 "$COLORES" "$DESTINO/colors.conf"
    echo "Colores de login actualizados."
fi
echo "Se aplicará en el próximo inicio de sesión (no hay que reiniciar)."

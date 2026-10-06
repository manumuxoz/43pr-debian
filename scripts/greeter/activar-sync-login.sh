#!/usr/bin/env bash
# Activa la sincronización automática del fondo/colores del login (hyprlogin).
#
# Qué hace (una sola vez, con sudo):
#   1. crea /var/lib/hyprlogin (root:$USUARIO, 775), escribible por el tema 43pr
#   2. redirige los ficheros del greeter a ese directorio con enlaces:
#        /etc/hyprlogin/colors.conf         -> /var/lib/hyprlogin/colors.conf
#        /usr/share/hyprlogin/wallpaper.jpg -> /var/lib/hyprlogin/wallpaper.jpg
#   3. instala la versión actualizada de sincronizar-login (respaldo manual)
#   4. copia el wallpaper/colores actuales para que el próximo login ya salga bien
#
# Es idempotente: se puede volver a ejecutar sin problema.
set -Eeuo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con:  sudo bash $0"; exit 1; }

AQUI="$(cd "$(dirname "$0")" && pwd)"
# Usuario dueño de la sesión (el paquete vive en su $HOME). Con sudo: SUDO_USER.
USUARIO="${SUDO_USER:-$(stat -c '%U' "$AQUI" 2>/dev/null || true)}"
if [ -z "$USUARIO" ] || ! id "$USUARIO" >/dev/null 2>&1; then
    echo "No pude determinar el usuario. Ejecuta con:  sudo bash $0" >&2
    exit 1
fi
DESTINO=/var/lib/hyprlogin
F_COLORES=/etc/hyprlogin/colors.conf
F_FONDO=/usr/share/hyprlogin/wallpaper.jpg

if [ ! -d /etc/hyprlogin ] || [ ! -d /usr/share/hyprlogin ]; then
    echo "No encuentro el greeter (/etc/hyprlogin, /usr/share/hyprlogin)." >&2
    exit 1
fi

# 1) Directorio compartido ---------------------------------------------------
install -d -o root -g "$USUARIO" -m 775 "$DESTINO"

# 2) Enlaces del greeter (copia de seguridad si eran ficheros normales) ------
for f in "$F_COLORES" "$F_FONDO"; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        cp -a "$f" "$f.bak-$(date +%s)"
    fi
done
ln -sfn "$DESTINO/colors.conf" "$F_COLORES"
ln -sfn "$DESTINO/wallpaper.jpg" "$F_FONDO"

# 3) Script manual actualizado ----------------------------------------------
install -m755 "$AQUI/sincronizar-login.sh" /usr/local/bin/sincronizar-login

# 4) Contenido actual --------------------------------------------------------
/usr/local/bin/sincronizar-login

echo
echo "Sincronización automática activada:"
ls -l "$F_COLORES" "$F_FONDO" "$DESTINO"
echo
echo "A partir de ahora theme.py actualiza el login en cada cambio de fondo/tema."
echo "Se aplica en el próximo inicio de sesión (no hace falta reiniciar)."

#!/usr/bin/env bash
# Vuelve a SDDM como gestor de login (rescate si el greeter diera problemas)
set -Eeuo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con sudo."; exit 1; }
systemctl disable greetd.service >/dev/null 2>&1 || true
systemctl stop greetd.service 2>/dev/null || true
printf '/usr/bin/sddm\n' > /etc/X11/default-display-manager
systemctl enable sddm.service >/dev/null 2>&1 || true
ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
systemctl daemon-reload
echo "Gestor de login: SDDM."
echo "Reinicia, o arranca ya con:  systemctl start sddm"

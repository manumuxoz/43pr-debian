#!/usr/bin/env bash
# Vuelve a greetd + hyprlogin como gestor de login
set -Eeuo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con sudo."; exit 1; }
systemctl disable sddm.service >/dev/null 2>&1 || true
systemctl stop sddm.service 2>/dev/null || true
printf '/usr/sbin/greetd\n' > /etc/X11/default-display-manager
systemctl enable greetd.service >/dev/null 2>&1 || true
ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl daemon-reload
echo "Gestor de login: greetd + hyprlogin."
echo "Reinicia, o arranca ya con:  systemctl start greetd"

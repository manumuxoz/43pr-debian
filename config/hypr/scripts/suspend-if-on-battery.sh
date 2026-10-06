#!/bin/sh
# Lo usa hypridle (listener de 15 min): suspende el equipo solo si
# está funcionando a batería, es decir, con el cargador desenchufado.
# Adaptador de corriente: ADP1 (ver /sys/class/power_supply/).

if [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = "0" ]; then
    systemctl suspend
fi

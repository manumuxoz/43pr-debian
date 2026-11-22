#!/bin/sh
# Lo usa hypridle (listener de 15 min): suspende el equipo solo si
# está funcionando a batería, es decir, sin ningún cargador conectado.
# No basta con ADP1: un cargador USB-C aparece como otra fuente
# (ucsi-source-psy-*) con type=USB y online=1.

on_ac=0
for supply in /sys/class/power_supply/*; do
    case "$(cat "$supply/type" 2>/dev/null)" in
        Mains|USB|USB_PD)
            if [ "$(cat "$supply/online" 2>/dev/null)" = "1" ]; then
                on_ac=1
                break
            fi
            ;;
    esac
done

if [ "$on_ac" -eq 0 ]; then
    systemctl suspend
fi

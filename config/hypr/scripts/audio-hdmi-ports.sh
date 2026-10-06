#!/bin/sh
# audio-hdmi-ports.sh — estado de los jacks HDMI/DP del códec interno.
# Salida: pcm3=on|off|unknown (pcm3/4/5 = salidas HDMI/DisplayPort 1/2/3)
card=sofhdadsp
for p in 3 4 5; do
    numid=$(amixer -c "$card" controls 2>/dev/null | sed -n "s/^numid=\([0-9]*\),iface=CARD,name='HDMI\/DP,pcm=$p Jack'.*/\1/p" | head -n1)
    val=unknown
    if [ -n "$numid" ]; then
        v=$(amixer -c "$card" cget numid="$numid" 2>/dev/null | sed -n 's/^[[:space:]]*:[[:space:]]*values=\(.*\)/\1/p' | head -n1)
        [ -n "$v" ] && val="$v"
    fi
    echo "pcm$p=$val"
done

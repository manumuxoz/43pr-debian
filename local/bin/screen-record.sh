#!/usr/bin/env bash
# Toggle de grabación de pantalla (wf-recorder empaquetado en ~/.local/opt).
# Uso: screen-record.sh  → start / stop según /tmp/osu-rec.pid
set -u

PIDFILE="/tmp/osu-rec.pid"
REC="$HOME/.local/opt/wf-recorder/usr/bin/wf-recorder"
OUTDIR="$HOME/Videos"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -INT "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    notify-send "Grabación" "Detenida. Vídeo guardado en $OUTDIR"
else
    rm -f "$PIDFILE"
    mkdir -p "$OUTDIR"
    file="$OUTDIR/rec-$(date +%F_%H-%M-%S).mp4"
    "$REC" -o eDP-1 -a default -f "$file" >/tmp/wf-recorder.log 2>&1 &
    echo $! > "$PIDFILE"
    sleep 0.5
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        notify-send "Grabación" "Grabando → $file (SUPER+R para parar)"
    else
        rm -f "$PIDFILE"
        notify-send "Grabación" "Error: wf-recorder no pudo arrancar"
        exit 1
    fi
fi

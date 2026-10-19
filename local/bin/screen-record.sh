#!/usr/bin/env bash
# Toggle de grabación de pantalla (wf-recorder empaquetado en ~/.local/opt).
# Uso: screen-record.sh  → start / stop según /tmp/osu-rec.pid
#
# Los vídeos se guardan en el directorio XDG de vídeos
# (~/Vídeos/Grabaciones de la pantalla/, la misma carpeta que usaba GNOME)
# para que aparezcan donde se espera al abrir el gestor de archivos.
set -u

PIDFILE="/tmp/osu-rec.pid"
FILEINFO="/tmp/osu-rec.file"
REC="$HOME/.local/opt/wf-recorder/usr/bin/wf-recorder"

XDG_VIDEOS="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
[ -n "$XDG_VIDEOS" ] || XDG_VIDEOS="$HOME/Vídeos"
OUTDIR="$XDG_VIDEOS/Grabaciones de la pantalla"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    # --- Detener grabación en curso ---
    pid="$(cat "$PIDFILE")"
    file="$(cat "$FILEINFO" 2>/dev/null || true)"
    kill -INT "$pid"
    # Esperar a que wf-recorder cierre el MP4 (escribe el moov) antes de avisar.
    for _ in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    rm -f "$PIDFILE" "$FILEINFO"
    if [ -n "$file" ] && [ -s "$file" ]; then
        notify-send "Grabación" "Detenida. Vídeo guardado en $file"
    else
        notify-send "Grabación" "Detenida, pero no se generó el vídeo (revisa /tmp/wf-recorder.log)"
    fi
else
    # --- Iniciar grabación ---
    rm -f "$PIDFILE" "$FILEINFO"
    mkdir -p "$OUTDIR"
    # Monitor con el foco (fallback: eDP-1 si la detección falla).
    monitor="$(hyprctl -j monitors 2>/dev/null | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m.get("focused")), ""))' 2>/dev/null)"
    [ -n "$monitor" ] || monitor="eDP-1"
    file="$OUTDIR/rec-$(date +%F_%H-%M-%S).mp4"
    "$REC" -o "$monitor" -a default -f "$file" >/tmp/wf-recorder.log 2>&1 &
    pid=$!
    echo "$pid" > "$PIDFILE"
    echo "$file" > "$FILEINFO"
    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
        notify-send "Grabación" "Grabando ($monitor) → $file (SUPER+R para parar)"
    else
        rm -f "$PIDFILE" "$FILEINFO"
        notify-send "Grabación" "Error: wf-recorder no pudo arrancar (ver /tmp/wf-recorder.log)"
        exit 1
    fi
fi

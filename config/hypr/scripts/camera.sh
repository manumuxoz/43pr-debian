#!/usr/bin/env bash
# camera.sh — webcam helper for the 43pr-debian Hyprland setup.
#
# The UVC webcam is driven straight through V4L2 with tools that are already
# installed (mpv for the preview), so it needs no extra packages. A single
# keybind (SUPER+C) opens the floating preview; once it is open, take a photo
# or record a video with keys inside the window (see camera-mpv.lua).
set -u

PREVIEW_PID="/tmp/osu-cam-preview.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$@"
    fi
    return 0
}

usage() {
    cat <<'EOF'
camera.sh — webcam helper (V4L2 through mpv)

Usage:
  camera.sh              Toggle the floating preview window (SUPER+C)
  camera.sh preview      Same as above
  camera.sh info         Show the detected device and its V4L2 formats
  camera.sh help         Show this help

With the preview open, use these keys inside the window:
  s                      Take a photo -> ~/Imágenes/Camera/<fecha-hora>.jpg
  r                      Record/stop  -> ~/Vídeos/Camera/<fecha-hora>.mp4

Environment (all optional):
  CAMERA_DEVICE     force a device node (default: auto-detect, usually /dev/video0)
  CAMERA_SIZE       capture size (default 1280x720)
  CAMERA_PHOTO_DIR  photo folder (default ~/Imágenes/Camera)
  CAMERA_VIDEO_DIR  video folder (default ~/Vídeos/Camera)
EOF
}

# --- device detection --------------------------------------------------------
# Pick a /dev/videoN that ffmpeg can open as a V4L2 capture device. UVC webcams
# expose two nodes (capture + metadata); only the capture one lists formats.
# MJPEG is preferred (smoother); otherwise a raw-capable node is used.
DEVICE=""
DEVICE_FMT=""
resolve_device() {
    local -a devs
    local dev out fallback="" fallback_fmt=""
    if [ -n "${CAMERA_DEVICE:-}" ]; then
        devs=("$CAMERA_DEVICE")
    else
        devs=(/dev/video*)
    fi
    for dev in "${devs[@]}"; do
        [ -e "$dev" ] || continue
        out="$(ffmpeg -hide_banner -f v4l2 -list_formats all -i "$dev" 2>&1)"
        if printf '%s\n' "$out" | grep -qiE 'mjpeg'; then
            DEVICE="$dev"
            DEVICE_FMT="mjpeg"
            return 0
        fi
        if [ -z "$fallback" ] && printf '%s\n' "$out" | grep -qE 'Raw|Compressed'; then
            fallback="$dev"
            if printf '%s\n' "$out" | grep -qiE 'yuyv422'; then
                fallback_fmt="yuyv422"
            else
                fallback_fmt="yuv420p"
            fi
        fi
    done
    if [ -n "$fallback" ]; then
        DEVICE="$fallback"
        DEVICE_FMT="$fallback_fmt"
        return 0
    fi
    return 1
}

# --- preview window ----------------------------------------------------------
# mpv owns the device. Photos (s) and recordings (r) are driven from inside the
# window by camera-mpv.lua, so only one reader ever touches the webcam.
preview_running() {
    [ -f "$PREVIEW_PID" ] && kill -0 "$(cat "$PREVIEW_PID")" 2>/dev/null
}

preview_stop() {
    if preview_running; then
        kill "$(cat "$PREVIEW_PID")" 2>/dev/null
    fi
    rm -f "$PREVIEW_PID"
    return 0
}

# Launch the floating preview window. Returns non-zero if mpv fails to stay up.
preview_start() {
    local photo_dir="${CAMERA_PHOTO_DIR:-$HOME/Imágenes/Camera}"
    rm -f "$PREVIEW_PID"
    mkdir -p "$photo_dir"
    mpv --no-audio --no-osc --profile=low-latency --title="Camara" \
        --demuxer-lavf-o="input_format=$DEVICE_FMT,video_size=$SIZE" \
        --screenshot-format=jpg \
        --screenshot-template="$photo_dir/%tY-%tm-%td_%tH-%tM-%tS" \
        --script="$SCRIPT_DIR/camera-mpv.lua" \
        "av://v4l2:$DEVICE" >/tmp/osu-cam-preview.log 2>&1 &
    echo $! >"$PREVIEW_PID"
    sleep 1
    if kill -0 "$(cat "$PREVIEW_PID")" 2>/dev/null; then
        return 0
    fi
    rm -f "$PREVIEW_PID"
    return 1
}

# --- actions -----------------------------------------------------------------
preview_toggle() {
    if preview_running; then
        preview_stop
        return 0
    fi
    if preview_start; then
        notify "Cámara" "Vista previa de $DEVICE (s = foto, r = grabar/parar)"
    else
        notify "Cámara" "Error: mpv no pudo abrir $DEVICE (ver /tmp/osu-cam-preview.log)"
        exit 1
    fi
}

show_info() {
    printf 'Dispositivo: %s (formato de captura: %s)\n' "$DEVICE" "$DEVICE_FMT"
    ffmpeg -hide_banner -f v4l2 -list_formats all -i "$DEVICE" 2>&1 \
        | grep -iE 'raw|compressed'
}

# --- dispatch ----------------------------------------------------------------
# Parse the action first so `help` and unknown options work without a camera.
ACTION="${1:-preview}"
case "$ACTION" in
    -h | --help | help) usage; exit 0 ;;
    preview | "" | info) ;;
    *)
        printf 'Opción no reconocida: %s\n\n' "$ACTION" >&2
        usage >&2
        exit 2
        ;;
esac

if ! resolve_device; then
    notify "Cámara" "No se ha detectado ninguna cámara V4L2"
    exit 1
fi

SIZE="${CAMERA_SIZE:-1280x720}"

case "$ACTION" in
    preview | "")    preview_toggle ;;
    info)            show_info ;;
esac

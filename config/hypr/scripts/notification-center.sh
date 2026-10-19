#!/usr/bin/env bash
# Historial de notificaciones de dunst en wofi.
# Uso: notification-center.sh [--list]
#   sin argumentos -> menú: elegir una notificación la copia al portapapeles;
#   el pie permite restaurar la última o limpiar todo el historial.
#   --list         -> volcado de prueba (id, app, resumen), sin abrir wofi.
set -u

if ! command -v dunstctl >/dev/null 2>&1; then
    notify-send "Notificaciones" "dunstctl no está disponible" 2>/dev/null || true
    exit 1
fi

history_json="$(dunstctl history 2>/dev/null || true)"

# Cada notificación se procesa como un objeto JSON en base64 para no romper
# con cuerpos que contengan tabuladores, saltos de línea o HTML.
mapfile -t rows < <(
    printf '%s' "$history_json" | jq -r '
        .data[]? | add |
        {id: .id.data, app: (.appname.data // ""), summary: (.summary.data // ""),
         body: (.body.data // "")} | @base64' 2>/dev/null
)

if [ "${1:-}" = "--list" ]; then
    for row in ${rows[@]+"${rows[@]}"}; do
        obj="$(printf '%s' "$row" | base64 -d 2>/dev/null)" || continue
        printf '%s\t%s\t%s\n' \
            "$(printf '%s' "$obj" | jq -r '.id')" \
            "$(printf '%s' "$obj" | jq -r '.app')" \
            "$(printf '%s' "$obj" | jq -r '.summary')"
    done
    exit 0
fi

if [ ${#rows[@]} -eq 0 ]; then
    notify-send "Notificaciones" "El historial está vacío" 2>/dev/null || true
    exit 0
fi

plain_text() {
    python3 -c 'import html,re,sys; print(html.unescape(re.sub(r"<[^>]+>", "", sys.stdin.read())).strip())'
}

declare -A BODY_BY_ID=()
lines=()
# Más recientes primero.
for ((i = ${#rows[@]} - 1; i >= 0; i--)); do
    obj="$(printf '%s' "${rows[i]}" | base64 -d 2>/dev/null)" || continue
    id="$(printf '%s' "$obj" | jq -r '.id')"
    app="$(printf '%s' "$obj" | jq -r '.app')"
    summary="$(printf '%s' "$obj" | jq -r '.summary')"
    body="$(printf '%s' "$obj" | jq -r '.body')"

    text="$(printf '%s' "$body" | plain_text)"
    [ -n "$text" ] || text="$summary"
    BODY_BY_ID["$id"]="$text"

    preview="$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-140)"
    [ -n "$app" ] || app="notificación"
    lines+=("#$id [$app] $summary — $preview")
done

if [ ${#lines[@]} -eq 0 ]; then
    notify-send "Notificaciones" "El historial está vacío" 2>/dev/null || true
    exit 0
fi

lines+=("── Restaurar la última notificación")
lines+=("── Limpiar el historial")

chosen="$(printf '%s\n' "${lines[@]}" | wofi --dmenu --prompt "Notificaciones" --width 820 --height 440)" || exit 0
[ -n "$chosen" ] || exit 0

case "$chosen" in
    "── Restaurar la última notificación")
        dunstctl history-pop
        ;;
    "── Limpiar el historial")
        if zenity --question --title="Notificaciones" \
            --text="¿Borrar todo el historial de notificaciones?" 2>/dev/null; then
            dunstctl history-clear
        fi
        ;;
    *)
        id="${chosen#\#}"
        id="${id%% *}"
        text="${BODY_BY_ID[$id]:-}"
        if [ -n "$text" ]; then
            printf '%s' "$text" | wl-copy
        fi
        ;;
esac

#!/usr/bin/env bash
# nightlight-toggle.sh — controla la luz nocturna de Hyprland con hyprsunset.
# Lo usan el atajo SUPER+SHIFT+P, el arranque de sesion (--restore) y el
# control NIGHTLIGHT de los ajustes de Quickshell.
#
# Uso:
#   nightlight-toggle.sh                 -> alterna encendido/apagado
#   nightlight-toggle.sh on [K]          -> enciende a K kelvin (si ya estaba
#                                            encendida, solo cambia el tono)
#   nightlight-toggle.sh off             -> apaga
#   nightlight-toggle.sh set K           -> guarda K y la aplica si esta on
#   nightlight-toggle.sh status          -> imprime "<on|off> <K>"
#   nightlight-toggle.sh --restore       -> reaplica el estado guardado
#                                            (para el arranque de sesion)
#   NIGHTLIGHT_TEMP=3000 nightlight-toggle.sh on
#
# Estado en ~/.local/state/hypr/nightlight ("on"/"off"); temperatura
# preferida en ~/.local/state/hypr/nightlight-temperature (Kelvin). Si
# hyprsunset no esta en marcha se arranca en segundo plano; al apagar solo se
# aplica "identity" (el proceso sigue vivo para el siguiente encendido). Al
# iniciar sesion (--restore) y el estado es "on", se reaplica la temperatura
# para que la luz nocturna sobreviva a reinicios de sesion.
set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/nightlight"
TEMP_FILE="$STATE_DIR/nightlight-temperature"
DEFAULT_TEMP=4000

mode=toggle
arg_temp=""

case "${1:-}" in
    --restore|restore) mode=restore ;;
    on) mode=on; arg_temp="${2:-}" ;;
    off) mode=off ;;
    set) mode=set; arg_temp="${2:-}" ;;
    status) mode=status ;;
    "") ;;
    *)
        notify-send -u critical "Luz nocturna" "Argumento no reconocido: '$1' (usa on, off, set, status, --restore o ninguno)."
        exit 1
        ;;
esac

# Entero valido en Kelvin, p.ej. 4000.
valid_temp() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

# Prioridad: argumento explicito > NIGHTLIGHT_TEMP > temperatura guardada > 4000.
resolve_temp() {
    local temp=""
    if [ -n "$arg_temp" ]; then
        if ! valid_temp "$arg_temp"; then
            notify-send -u critical "Luz nocturna" "Temperatura invalida: '$arg_temp' (usa un entero en Kelvin, p.ej. 4000)."
            return 1
        fi
        temp="$arg_temp"
    elif [ -n "${NIGHTLIGHT_TEMP:-}" ]; then
        if ! valid_temp "$NIGHTLIGHT_TEMP"; then
            notify-send -u critical "Luz nocturna" "NIGHTLIGHT_TEMP invalida: '$NIGHTLIGHT_TEMP' (usa un entero en Kelvin, p.ej. 4000)."
            return 1
        fi
        temp="$NIGHTLIGHT_TEMP"
    elif [ -r "$TEMP_FILE" ]; then
        temp="$(cat "$TEMP_FILE" 2>/dev/null || true)"
        if ! valid_temp "$temp"; then
            temp="$DEFAULT_TEMP"
        fi
    else
        temp="$DEFAULT_TEMP"
    fi
    printf '%s' "$temp"
}

save_temp() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >"$TEMP_FILE"
}

read_state() {
    if [ -r "$STATE_FILE" ]; then
        cat "$STATE_FILE" 2>/dev/null || printf 'off'
    else
        printf 'off'
    fi
}

# Comprueba dependencias y arranca hyprsunset si no esta en marcha.
ensure_sunset() {
    if ! command -v hyprsunset >/dev/null 2>&1; then
        notify-send -u critical "Luz nocturna" "hyprsunset no esta instalado."
        exit 1
    fi
    if ! command -v hyprctl >/dev/null 2>&1; then
        notify-send -u critical "Luz nocturna" "hyprctl no esta disponible."
        exit 1
    fi
    if ! pgrep -x hyprsunset >/dev/null 2>&1; then
        nohup hyprsunset >/dev/null 2>&1 &
        sleep 0.5
    fi
}

enable() {
    local temp prev_state
    temp="$(resolve_temp)" || exit 1
    prev_state="$(read_state)"
    ensure_sunset
    if hyprctl hyprsunset temperature "$temp" >/dev/null 2>&1; then
        mkdir -p "$STATE_DIR"
        printf 'on\n' >"$STATE_FILE"
        save_temp "$temp"
        # Solo notifica en un cambio real off -> on; asi mover la barra con la
        # luz ya encendida no genera avisos repetidos.
        if [ "$prev_state" != "on" ]; then
            notify-send "Luz nocturna activada (${temp} K)"
        fi
    else
        notify-send -u critical "Luz nocturna" "No pude activarla: hyprctl fallo (revisa que hyprsunset haya arrancado)."
        exit 1
    fi
}

disable() {
    local prev_state
    prev_state="$(read_state)"
    if pgrep -x hyprsunset >/dev/null 2>&1; then
        hyprctl hyprsunset identity >/dev/null 2>&1 || true
    fi
    mkdir -p "$STATE_DIR"
    printf 'off\n' >"$STATE_FILE"
    # Solo notifica si de verdad estaba encendida.
    if [ "$prev_state" = "on" ]; then
        notify-send "Luz nocturna desactivada"
    fi
}

# Guarda la temperatura y, si la luz esta encendida, la aplica.
apply_temp() {
    local temp
    temp="$(resolve_temp)" || exit 1
    save_temp "$temp"
    if [ "$(read_state)" = "on" ] && pgrep -x hyprsunset >/dev/null 2>&1; then
        hyprctl hyprsunset temperature "$temp" >/dev/null 2>&1 || true
    fi
}

case "$mode" in
    on) enable ;;
    off) disable ;;
    set) apply_temp ;;
    status)
        temp="$(resolve_temp)" || exit 1
        printf '%s %s\n' "$(read_state)" "$temp"
        ;;
    restore)
        if [ "$(read_state)" = "on" ]; then
            temp="$(resolve_temp)" || exit 1
            ensure_sunset
            if hyprctl hyprsunset temperature "$temp" >/dev/null 2>&1; then
                notify-send "Luz nocturna restaurada (${temp} K)"
                exit 0
            fi
            notify-send -u critical "Luz nocturna" "No pude restaurarla: hyprctl fallo (revisa que hyprsunset haya arrancado)."
            exit 1
        fi
        if pgrep -x hyprsunset >/dev/null 2>&1; then
            hyprctl hyprsunset identity >/dev/null 2>&1 || true
        fi
        ;;
    toggle)
        if [ "$(read_state)" = "on" ]; then
            disable
        else
            enable
        fi
        ;;
esac

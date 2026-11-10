#!/usr/bin/env bash
# opacity.sh — opacidad en Hyprland 0.55 (config Lua): ventana activa o global.
#
# Uso:
#   opacity.sh                     menú wofi (ámbito: ventana activa o todas)
#   opacity.sh window N            aplica N a la ventana activa (0.1-1.0 o 10-100 %)
#   opacity.sh window-step D       suma D a la ventana activa (0.05 o 5 = 5 puntos)
#   opacity.sh window-cycle        cicla 100 -> 90 -> ... -> 40 -> 100
#   opacity.sh reset               devuelve la ventana activa a 100 %
#   opacity.sh global N            guarda N y recarga Hyprland (todas las ventanas)
#   opacity.sh status              imprime la opacidad efectiva de la ventana activa
#
# La opacidad por ventana se aplica en caliente y no toca la configuración.
# Hyprland 0.55 ya no acepta `hyprctl setprop` como petición directa (responde
# "unknown request"): hay que enviar el dispatcher Lua con `hyprctl dispatch`.
# Se fijan opacity y opacity_inactive para que la ventana conserve la
# transparencia al perder el foco; opacity_fullscreen se deja en 1.0 para que
# una ventana a pantalla completa siga opaca (igual que la regla global).
#
# El ámbito global se guarda en ~/.local/state/hypr/opacity.lua, que rules.lua
# lee al cargar; así el valor sobrevive a install/update y a los reinicios.
#
# Variables de entorno (pruebas/automatización):
#   OPACITY_MENU_SELECT   opción a ejecutar sin abrir wofi
#   OPACITY_SCOPE         ámbito inicial del menú: window (por defecto) o global
#   OPACITY_STATE_FILE    archivo de estado alternativo para el comando `global`
#   OPACITY_DRY_RUN       1 = escribe el estado pero no recarga ni toca ventanas
set -u

readonly PRESETS=(100 90 80 70 60 50 40)
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="${OPACITY_STATE_FILE:-$STATE_HOME/hypr/opacity.lua}"

die() {
    printf 'Opacidad: %s\n' "$*" >&2
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "Opacidad" "$*" 2>/dev/null || true
    fi
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "falta el comando '$1'."
}

is_number() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    return 0
}

# Compara dos opacidades con tolerancia (0.8 == 0.80).
floats_equal() {
    is_number "$1" || return 1
    is_number "$2" || return 1
    LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN {
        d = a - b
        if (d < 0) d = -d
        exit (d < 0.005) ? 0 : 1
    }'
}

# Acepta 0.8, 0,8, .8, 80 o 80 %. Devuelve siempre un decimal con dos cifras
# (0.10-1.00). Los valores fuera de rango se recortan; los ambiguos (entre 1 y
# 10) se rechazan para no convertir 1.5 en 1,5 % por accidente.
normalize() {
    local raw="$1" out
    raw="${raw//[[:space:]]/}"
    raw="${raw//%/}"
    raw="${raw//,/.}"

    [[ "$raw" =~ ^[+]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || return 1

    out=$(LC_ALL=C awk -v v="$raw" 'BEGIN {
        if (v > 1.0 && v < 10.0) exit 1
        if (v >= 10.0) v /= 100.0
        if (v < 0.1) v = 0.1
        if (v > 1.0) v = 1.0
        printf "%.2f", v
    }') || return 1

    printf '%s' "$out"
}

# 1.00 -> 1.0, 0.80 -> 0.8 (para el estado y para los mensajes).
pretty() {
    LC_ALL=C awk -v v="$1" 'BEGIN {
        s = sprintf("%.2f", v)
        sub(/0$/, "", s)
        if (s ~ /\.$/) s = s "0"
        print s
    }'
}

percent() {
    LC_ALL=C awk -v v="$1" 'BEGIN { printf "%.0f %%", v * 100 }'
}

active_address() {
    hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null
}

active_class() {
    hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null
}

window_opacity() {
    hyprctl getprop "address:$1" opacity 2>/dev/null | head -n1
}

usage() {
    # Imprime el bloque de comentarios de cabecera (hasta la primera línea de código).
    awk 'NR > 1 && $0 !~ /^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
}

# Aplica la opacidad a una dirección concreta y comprueba que se ha quedado.
# El dispatcher Lua imprime "ok"; los errores empiezan por "error:" pero
# hyprctl sale con código 0, así que hay que revisar la salida. Además, si la
# ventana ya no existe, Hyprland responde "ok" sin hacer nada: se verifica el
# valor con getprop.
apply_window() {
    local addr="$1" value="$2" prop out current
    for prop in opacity opacity_inactive; do
        out=$(hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"$prop\", value = \"$value\", window = \"address:$addr\" })" 2>&1) || true
        [ "$out" = "ok" ] || return 1
    done

    current=$(window_opacity "$addr")
    floats_equal "$current" "$value" || return 1
    current=$(hyprctl getprop "address:$addr" opacity_inactive 2>/dev/null | head -n1)
    floats_equal "$current" "$value" || return 1
    return 0
}

apply_active() {
    local addr
    addr=$(active_address)
    [ -n "$addr" ] || die "no hay ninguna ventana activa."
    apply_value "$addr" "$1"
}

apply_value() {
    local addr="$1" value
    value=$(normalize "$2") || die "opacidad inválida: '$2' (usa 0.1-1.0 o 10-100 %)."
    apply_window "$addr" "$value" || die "no se pudo aplicar la opacidad a la ventana seleccionada."
}

step_active() {
    local delta="$1" addr current next
    delta="${delta//[[:space:]]/}"
    delta="${delta//%/}"
    delta="${delta//,/.}"
    [[ "$delta" =~ ^[+-]?[0-9]+(\.[0-9]+)?$ ]] || die "incremento inválido: '$1'."
    # Acepta fracciones (0.05) y puntos porcentuales (5 o 5 %).
    delta=$(LC_ALL=C awk -v d="$delta" 'BEGIN {
        if (d >= 1.0 || d <= -1.0) d /= 100.0
        printf "%.4f", d
    }')

    addr=$(active_address)
    [ -n "$addr" ] || die "no hay ninguna ventana activa."
    current=$(window_opacity "$addr")
    is_number "$current" || die "no se pudo leer la opacidad de la ventana activa."

    next=$(LC_ALL=C awk -v c="$current" -v d="$delta" 'BEGIN {
        v = c + d
        if (v < 0.1) v = 0.1
        if (v > 1.0) v = 1.0
        printf "%.2f", v
    }')

    apply_window "$addr" "$next" || die "no se pudo cambiar la opacidad de la ventana activa."
}

# Ciclo pensado para un atajo: 100 -> 90 -> ... -> 40 -> 100. Si el valor
# actual no es un preset (p. ej. 0.83), salta al preset inmediatamente inferior.
cycle_active() {
    local addr current next
    addr=$(active_address)
    [ -n "$addr" ] || die "no hay ninguna ventana activa."
    current=$(window_opacity "$addr")
    is_number "$current" || die "no se pudo leer la opacidad de la ventana activa."

    next=$(LC_ALL=C awk -v c="$current" 'BEGIN {
        split("1.00 0.90 0.80 0.70 0.60 0.50 0.40", p, " ")
        for (i = 1; i <= 7; i++) {
            if (p[i] < c - 0.0005) { print p[i]; exit }
        }
        print "1.00"
    }')

    apply_window "$addr" "$next" || die "no se pudo cambiar la opacidad de la ventana activa."
}

# "Todas las ventanas" también actualiza las que ya tienen una opacidad propia:
# set_prop vive por encima de la regla global y un reload no lo borra.
apply_global_to_clients() {
    local value="$1" addr active inactive
    while IFS= read -r addr; do
        [ -n "$addr" ] || continue
        active=$(window_opacity "$addr")
        inactive=$(hyprctl getprop "address:$addr" opacity_inactive 2>/dev/null | head -n1)
        if floats_equal "$active" "$value" && floats_equal "$inactive" "$value"; then
            continue
        fi
        apply_window "$addr" "$value" || true
    done < <(hyprctl clients -j 2>/dev/null | jq -r '.[].address // empty' 2>/dev/null)
}

apply_global() {
    local value pretty_value state_dir tmp errors
    value=$(normalize "$1") || die "opacidad inválida: '$1' (usa 0.1-1.0 o 10-100 %)."
    pretty_value=$(pretty "$value")

    state_dir=$(dirname "$STATE_FILE")
    mkdir -p "$state_dir" || die "no se pudo crear $state_dir."
    tmp="$STATE_FILE.tmp.$$"
    if ! printf 'return "%s"\n' "$pretty_value" > "$tmp"; then
        rm -f "$tmp"
        die "no se pudo escribir $tmp."
    fi
    if ! mv -f "$tmp" "$STATE_FILE"; then
        rm -f "$tmp"
        die "no se pudo actualizar $STATE_FILE."
    fi

    # Hook de pruebas: deja el estado escrito, sin tocar la sesión viva.
    [ "${OPACITY_DRY_RUN:-0}" = "1" ] && return 0

    if ! hyprctl reload >/dev/null 2>&1; then
        die "$STATE_FILE actualizado, pero 'hyprctl reload' falló."
    fi

    errors=$(hyprctl configerrors 2>&1 || true)
    case "$errors" in
        *[![:space:]]*) die "Hyprland recargó con errores: $errors" ;;
    esac

    apply_global_to_clients "$value"
}

show_status() {
    local addr class value fullscreen
    addr=$(active_address)
    [ -n "$addr" ] || die "no hay ninguna ventana activa."
    class=$(active_class)
    fullscreen=$(hyprctl activewindow -j 2>/dev/null | jq -r '.fullscreen // 0' 2>/dev/null)
    value=$(window_opacity "$addr")
    is_number "$value" || die "la ventana activa no expone una opacidad válida."

    if [ "${fullscreen:-0}" != "0" ]; then
        value=$(hyprctl getprop "address:$addr" opacity_fullscreen 2>/dev/null | head -n1)
        is_number "$value" || die "la ventana activa no expone una opacidad válida."
        printf '%s (%s): %s (%s, pantalla completa)\n' \
            "${class:-ventana}" "$addr" "$(pretty "$value")" "$(percent "$value")"
    else
        printf '%s (%s): %s (%s)\n' \
            "${class:-ventana}" "$addr" "$(pretty "$value")" "$(percent "$value")"
    fi
}

show_menu() {
    local addr scope entries header selection lines prompt="Opacidad"
    addr=$(active_address)

    # El menú muestra primero el ámbito y después los presets: así cabe en el
    # alto habitual de wofi y no hay que repetir cada porcentaje por ámbito.
    scope="${1:-${OPACITY_SCOPE:-window}}"
    if [ -z "$addr" ] || [ "$scope" = "global" ]; then
        scope=global
    else
        scope=window
    fi

    if [ "$scope" = "window" ]; then
        header="Aplicar a: ventana activa  →  todas"
    elif [ -n "$addr" ]; then
        header="Aplicar a: todas las ventanas  →  ventana activa"
    else
        # Sin ventana activa no hay nada que alternar: sin cabecera y con el
        # ámbito en el prompt para no dejar una entrada que no haga nada.
        header=""
        prompt="Opacidad (todas)"
    fi

    entries=""
    [ -n "$header" ] && entries+="$header"$'\n'
    for p in "${PRESETS[@]}"; do
        entries+="$p %"$'\n'
    done

    if [ -n "${OPACITY_MENU_SELECT:-}" ]; then
        selection="$OPACITY_MENU_SELECT"
        # Solo para la primera invocación: evita un bucle si la opción inyectada
        # es la cabecera que cambia de ámbito.
        unset OPACITY_MENU_SELECT
    else
        # --cache-file /dev/null evita que wofi reordene los presets según el
        # uso. --conf /dev/null ignora el height=480 de ~/.config/wofi/config
        # (el menú se dimensiona con --lines); el resto de opciones replica la
        # configuración habitual y el estilo sigue saliendo de wofi/style.css.
        lines=$(printf '%s' "$entries" | awk 'END { print NR }')
        # wofi descuenta el campo de búsqueda del alto de --lines: +2 deja
        # visibles todas las entradas sin scroll.
        selection=$(printf '%s' "$entries" | wofi --dmenu --cache-file /dev/null \
            --conf /dev/null --matching contains --insensitive --gtk-dark \
            --hide-scroll --lines "$((lines + 2))" --width 480 --prompt "$prompt") || exit 0
    fi
    [ -n "$selection" ] || exit 0

    case "$selection" in
        "Aplicar a: ventana activa  →  todas")
            show_menu global
            ;;
        "Aplicar a: todas las ventanas  →  ventana activa")
            show_menu window
            ;;
        *"%")
            if [ "$scope" = "global" ]; then
                apply_global "$selection"
            else
                apply_value "$addr" "$selection"
            fi
            ;;
        *)
            die "opción no reconocida: '$selection'."
            ;;
    esac
}

case "${1:-menu}" in
    ""|menu)          need hyprctl; need jq
                      [ -n "${OPACITY_MENU_SELECT:-}" ] || need wofi
                      show_menu ;;
    window)           need hyprctl; need jq
                      [ $# -eq 2 ] || die "uso: opacity.sh window N"
                      apply_active "$2" ;;
    window-step)      need hyprctl; need jq
                      [ $# -eq 2 ] || die "uso: opacity.sh window-step D"
                      step_active "$2" ;;
    window-cycle|cycle) need hyprctl; need jq; cycle_active ;;
    reset)            need hyprctl; need jq; apply_active 100 ;;
    global)           need hyprctl; need jq
                      [ $# -eq 2 ] || die "uso: opacity.sh global N"
                      apply_global "$2" ;;
    status)           need hyprctl; need jq; show_status ;;
    -h|--help|help)   usage ;;
    *)                die "comando no reconocido: '$1' (prueba --help)." ;;
esac

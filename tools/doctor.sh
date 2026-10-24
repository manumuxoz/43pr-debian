#!/usr/bin/env bash
# doctor.sh — diagnóstico de solo lectura del port 43pr-debian.
# Comprueba sesión, procesos, comandos, IPC de Quickshell, tema, estado,
# wallpapers, fuentes y paquetes. No modifica nada.
#
# Uso: ./tools/doctor.sh
# Salida: 0 si no hay fallos (puede haber avisos), 1 si algo falla.
set -u

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
okc=0 warnc=0 failc=0

if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[1;32m'; Y=$'\033[1;33m'
    R=$'\033[1;31m'; N=$'\033[0m'
else
    B=''; G=''; Y=''; R=''; N=''
fi

section() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
pass()    { printf '  %sOK%s   %s\n' "$G" "$N" "$*"; okc=$((okc + 1)); }
warn()    { printf '  %sWARN%s %s\n' "$Y" "$N" "$*"; warnc=$((warnc + 1)); }
fail()    { printf '  %sFAIL%s %s\n' "$R" "$N" "$*"; failc=$((failc + 1)); }
have()    { command -v "$1" >/dev/null 2>&1; }

section "Sesión y compositor"
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    pass "Sesión Wayland"
else
    warn "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<vacío>} (se esperaba wayland)"
fi

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    pass "Hyprland activo"
else
    fail "HYPRLAND_INSTANCE_SIGNATURE no definido; ¿estás dentro de Hyprland?"
fi

if have hyprctl; then
    version="$(hyprctl version 2>/dev/null | head -n1)"
    pass "hyprctl: ${version:-<sin versión>}"
    errors="$(hyprctl configerrors 2>/dev/null || true)"
    if [ -z "$errors" ] || [ "$errors" = "ok" ]; then
        pass "Configuración de Hyprland sin errores"
    else
        fail "hyprctl configerrors: $errors"
    fi
else
    fail "hyprctl no está instalado o no está en PATH"
fi

section "Monitores"
if have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    if monitors_json="$(hyprctl monitors -j 2>/dev/null)" && jq -e . >/dev/null 2>&1 <<<"$monitors_json"; then
        bad_modes="$(jq -r '
            .[] | select((.disabled // false) | not) | . as $m
            | ([.availableModes[]?
                | capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz$")
                | select((.w|tonumber) == $m.width
                    and (.h|tonumber) == $m.height
                    and (((.r|tonumber) - $m.refreshRate) | fabs) < 0.02)
               ] | length) as $n
            | select($n == 0)
            | "\(.name): \(.width)x\(.height)@\(.refreshRate)"' <<<"$monitors_json")"
        if [ -z "$bad_modes" ]; then
            pass "todos los monitores activos usan un modo anunciado en el EDID"
        else
            fail "modo no soportado (pantalla potencialmente negra): $bad_modes"
            printf '       corrige con: %s/.config/hypr/scripts/monitor-ctl.sh mode <salida> preferred\n' "$HOME"
        fi
    else
        warn "no pude leer hyprctl monitors -j"
    fi
else
    warn "Hyprland no accesible; comprobación de monitores omitida"
fi

section "Procesos"
for proc in qs waybar swaybg hypridle; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        pass "$proc en ejecución"
    else
        fail "$proc no está corriendo"
    fi
done
if pgrep -x hyprsunset >/dev/null 2>&1; then
    pass "hyprsunset activo (luz nocturna)"
else
    printf '  %sINFO%s hyprsunset inactivo (luz nocturna apagada)\n' "$B" "$N"
fi

qs_instances="$(pgrep -xc qs 2>/dev/null || true)"
if [ "${qs_instances:-0}" -gt 1 ]; then
    warn "$qs_instances instancias de Quickshell: comparten org.freedesktop.Notifications; cierra la sesión más antigua si los avisos no aparecen o el sonido/DND no responde"
fi

section "Comandos imprescindibles"
for cmd in hyprctl qs waybar dunst wofi grim slurp wl-copy cliphist jq \
           python3 playerctl brightnessctl swaybg xdg-user-dir notify-send swappy; do
    if have "$cmd"; then
        pass "$cmd"
    else
        fail "$cmd no está instalado"
    fi
done

for cmd in matugen magick convert btop cava; do
    if have "$cmd"; then
        pass "$cmd (opcional)"
    else
        printf '  %sINFO%s %s no instalado (opcional)\n' "$B" "$N" "$cmd"
    fi
done

section "IPC de Quickshell"
if pgrep -x qs >/dev/null 2>&1; then
    for target in screenshot settings notepad todo powermenu mediaosd notifications; do
        # Una función inexistente distingue "target existe" (Function not found)
        # de "target no registrado" (Target not found) sin abrir ninguna UI.
        reply="$(qs ipc call "$target" __doctor__ 2>&1 || true)"
        if [ "$reply" != "Target not found." ]; then
            pass "target '$target'"
        else
            fail "target '$target' no responde"
        fi
    done
else
    fail "Quickshell no está corriendo; IPC omitido"
fi

section "Tema"
theme_py="$HOME/.config/43pr/bin/theme.py"
if [ -f "$theme_py" ]; then
    if out="$(python3 "$theme_py" status 2>&1)"; then
        pass "theme.py status"
    else
        fail "theme.py status falló: $out"
    fi
else
    fail "no existe $theme_py"
fi

for rel in waybar/colors.css wlogout/colors.css wofi/style.css hypr/hyprlock-colors.conf; do
    if [ -s "$HOME/.config/$rel" ]; then
        pass "generado: ~/.config/$rel"
    else
        fail "falta o está vacío: ~/.config/$rel"
    fi
done

preset_count="$(find "$HOME/.config/43pr/themes" -maxdepth 1 -name '*.toml' 2>/dev/null | wc -l)"
if [ "$preset_count" -ge 27 ]; then
    pass "$preset_count presets de tema"
else
    warn "solo $preset_count presets (se esperaban 27 o más)"
fi

if [ -s "${XDG_CACHE_HOME:-$HOME/.cache}/43pr/palette.json" ]; then
    pass "paleta activa en ~/.cache/43pr/palette.json"
else
    warn "no hay paleta generada; ejecuta theme.py apply"
fi

state="${XDG_STATE_HOME:-$HOME/.local/state}/43pr/state.json"
if [ -f "$state" ] && jq -e . "$state" >/dev/null 2>&1; then
    pass "state.json válido"
    wp="$(jq -r '.wallpaper // empty' "$state" 2>/dev/null)"
    if [ -n "$wp" ] && [ -f "$wp" ]; then
        pass "wallpaper actual existe"
    else
        warn "wallpaper registrado ausente: ${wp:-<vacío>}"
    fi
else
    warn "no existe o no es JSON válido: $state"
fi

section "Estado de Quickshell"
qs_state="$HOME/.config/quickshell/state"
if [ -d "$qs_state" ]; then
    pass "directorio $qs_state"
    for f in todo-state.json mediaosd-state.json; do
        if [ -f "$qs_state/$f" ]; then
            if jq -e . "$qs_state/$f" >/dev/null 2>&1; then
                pass "$f válido"
            else
                warn "$f no es JSON válido"
            fi
        fi
    done
else
    warn "no existe $qs_state (lo crean install.sh/update.sh)"
fi

section "Wallpapers y fuentes"
wp_cfg="$HOME/.config/quickshell/hyprquickpaper/config.json"
if [ -f "$wp_cfg" ]; then
    wp_dir="$(jq -r '.wallpaper_path // empty' "$wp_cfg" 2>/dev/null)"
    wp_dir="${wp_dir//\$HOME/$HOME}"
    if [ -d "$wp_dir" ]; then
        count="$(find "$wp_dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | wc -l)"
        if [ "$count" -gt 0 ]; then
            pass "$count wallpapers en $wp_dir"
        else
            warn "sin imágenes en $wp_dir"
        fi
    else
        warn "carpeta de wallpapers no válida: ${wp_dir:-<vacía>}"
    fi
else
    warn "no existe $wp_cfg"
fi

if fc-list 2>/dev/null | grep -qi "Nerd Font"; then
    pass "fuente Nerd Font disponible"
else
    fail "no se encontró ninguna Nerd Font (iconos rotos)"
fi

section "Scripts ejecutables"
for rel in hypr/scripts/screenshot.sh hypr/scripts/monitor-ctl.sh \
           hypr/scripts/random-wallpaper.sh hypr/scripts/wallpaper-restore.sh; do
    if [ -x "$HOME/.config/$rel" ]; then
        pass "$rel"
    else
        fail "no ejecutable o ausente: ~/.config/$rel"
    fi
done

section "Paquetes"
required=(waybar dunst wofi quickshell hyprland hyprlock hypridle grim slurp \
          wl-clipboard cliphist jq python3 playerctl brightnessctl swaybg \
          swappy libnotify-bin zenity)
missing=()
for pkg in "${required[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        missing+=("$pkg")
    fi
done
if [ ${#missing[@]} -eq 0 ]; then
    pass "todos los paquetes imprescindibles instalados"
else
    fail "faltan paquetes: ${missing[*]}"
fi

optional=(imagemagick thunar thunar-volman thunar-archive-plugin gvfs tumbler \
          ffmpegthumbnailer python3-pil pavucontrol blueman)
opt_missing=()
for pkg in "${optional[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        opt_missing+=("$pkg")
    fi
done
if [ ${#opt_missing[@]} -eq 0 ]; then
    pass "todos los paquetes opcionales instalados"
else
    warn "opcionales no instalados: ${opt_missing[*]}"
fi

section "Repositorio"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
        pass "árbol de trabajo limpio"
    else
        warn "hay cambios sin commitear en $REPO"
    fi
    pass "HEAD: $(git -C "$REPO" log -1 --oneline)"
else
    warn "$REPO no parece un repositorio git"
fi

printf '\nResumen: %d OK, %d avisos, %d fallos\n' "$okc" "$warnc" "$failc"
[ "$failc" -eq 0 ]

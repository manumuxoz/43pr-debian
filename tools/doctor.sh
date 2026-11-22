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
have()    { command -v "$1" >/dev/null 2>&1 || [ -x "/usr/sbin/$1" ]; }

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

waybar_pid="$(pgrep -x waybar 2>/dev/null | head -n1 || true)"
if [ -n "$waybar_pid" ]; then
    waybar_sig="$(tr '\0' '\n' <"/proc/$waybar_pid/environ" 2>/dev/null \
        | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -n1)"
    shim_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/waybar-lua-shim"
    shim_pid="$(cat "$shim_dir/shim.pid" 2>/dev/null || true)"
    if [ "$waybar_sig" != "waybar-lua-shim" ]; then
        fail "Waybar habla con Hyprland sin puente: los clics de workspace no cambian de escritorio; reinicia con ~/.config/hypr/scripts/waybar-restart.sh"
    elif [ -z "$shim_pid" ] || ! kill -0 "$shim_pid" 2>/dev/null; then
        fail "Waybar apunta al puente IPC pero el proceso no está vivo; reinicia con ~/.config/hypr/scripts/waybar-restart.sh"
    else
        pass "Waybar usa el puente IPC (clics de workspace operativos)"
    fi
fi

qs_instances="$(pgrep -xc qs 2>/dev/null || true)"
if [ "${qs_instances:-0}" -gt 1 ]; then
    warn "$qs_instances instancias de Quickshell: comparten org.freedesktop.Notifications; cierra la sesión más antigua si los avisos no aparecen o el sonido/DND no responde"
fi

section "Portales"
tracking=""
if have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    tracking="$(hyprctl getoption misc:initial_workspace_tracking 2>/dev/null | awk '/^int:/ {print $2}')"
    if [ "${tracking:-}" = "0" ]; then
        pass "misc:initial_workspace_tracking = 0"
    else
        fail "misc:initial_workspace_tracking = ${tracking:-<desconocido>} (se esperaba 0)"
    fi
fi

if have systemctl; then
    hl_env="$(systemctl --user show-environment 2>/dev/null | grep -E '^HL_(INITIAL_WORKSPACE|EXEC_RULE)_TOKEN=' || true)"
    if [ -z "$hl_env" ]; then
        pass "entorno de systemd sin tokens HL_*"
    elif [ "${tracking:-}" = "0" ]; then
        warn "tokens HL_* residuales en systemd (inertes con tracking desactivado); se limpian al cerrar sesión"
    else
        fail "tokens de Hyprland filtrados al entorno de systemd: ${hl_env%%=*}"
        printf '       corrige con: systemctl --user unset-environment HL_INITIAL_WORKSPACE_TOKEN HL_EXEC_RULE_TOKEN\n'
    fi
else
    warn "systemctl no disponible; comprobación de portales omitida"
fi

portal_leak=""
while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qE '^HL_(INITIAL_WORKSPACE|EXEC_RULE)_TOKEN='; then
        portal_leak="$portal_leak $pid"
    fi
done < <(pgrep -f '/usr/libexec/xdg-desktop-portal' 2>/dev/null || true)
if [ -n "$portal_leak" ]; then
    if [ "${tracking:-}" = "0" ]; then
        warn "portales con token heredado (inertes con tracking desactivado): PID:$portal_leak"
    else
        fail "portales con token de workspace heredado (PID:$portal_leak)"
        printf '       reinícialos: systemctl --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal.service\n'
    fi
else
    pass "portales sin tokens de workspace heredados"
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

for rel in waybar/colors.css wofi/style.css hypr/colors.lua hypr/hyprlock-colors.conf; do
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
           hypr/scripts/random-wallpaper.sh hypr/scripts/wallpaper-restore.sh \
           hypr/scripts/opacity.sh; do
    if [ -x "$HOME/.config/$rel" ]; then
        pass "$rel"
    else
        fail "no ejecutable o ausente: ~/.config/$rel"
    fi
done

section "Energía y rendimiento"
bat=/sys/class/power_supply/BAT0
full="$(cat "$bat/charge_full" 2>/dev/null || true)"
design="$(cat "$bat/charge_full_design" 2>/dev/null || true)"
if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ]; then
    health=$((full * 100 / design))
    if [ "$health" -ge 80 ]; then pass "salud de batería: ${health}%"
    elif [ "$health" -ge 70 ]; then warn "salud de batería: ${health}% (70-79%)"
    else fail "salud de batería: ${health}% (<70%)"; fi
else
    warn "no pude leer la salud de BAT0"
fi
limit="$(cat "$bat/charge_control_end_threshold" 2>/dev/null || true)"
if [ "$limit" = 100 ]; then printf '  %sINFO%s límite de carga 100%%; 60-80%% alarga la vida útil\n' "$B" "$N"
elif [ -n "$limit" ] && [ "$limit" -le 80 ]; then pass "límite de carga: ${limit}%"
elif [ -n "$limit" ]; then warn "límite de carga: ${limit}% (sugerido 60-80%)"; fi
profile="$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || true)"
[ -n "$profile" ] && pass "platform_profile: $profile" || warn "platform_profile no disponible"
turbo="$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true)"
if [ "$turbo" = 0 ]; then pass "turbo habilitado"
elif [ "$turbo" = 1 ]; then printf '  %sINFO%s turbo desactivado (no_turbo=1)\n' "$B" "$N"; fi
swaps="$(awk 'NR>1 && $1 != "" {print $1}' /proc/swaps 2>/dev/null)"
if [ -n "$swaps" ]; then pass "swap activa: $swaps"
elif [ -e /sys/block/zram0 ]; then warn "zram0 presente pero sin swap activa"
else warn "sin swap ni zram; usa: sudo bash $REPO/scripts/install-zram.sh"; fi
if systemctl is-active --quiet systemd-oomd 2>/dev/null || systemctl is-active --quiet earlyoom 2>/dev/null || [ -e /sys/block/zram0 ]; then pass "gestor OOM o zram disponible"; else warn "sin systemd-oomd/earlyoom ni zram"; fi
missing_tools=""
for tool in thermald powertop; do have "$tool" || missing_tools="$missing_tools $tool"; done
if [ -z "$missing_tools" ]; then pass "thermald y powertop instalados"
else printf '  %sINFO%s no instalados (opcionales):%s\n' "$B" "$N" "$missing_tools"; fi
thr="$(cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count 2>/dev/null || true)"
if [ -n "$thr" ] && [ "$thr" -gt 0 ]; then warn "throttle de paquete: $thr eventos desde el arranque"; else pass "sin throttle de paquete registrado"; fi

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

optional=(imagemagick thunar thunar-volman thunar-archive-plugin \
          thunar-media-tags-plugin tumbler tumbler-plugins-extra \
          file-roller catfish plocate gvfs gvfs-fuse \
          ffmpegthumbnailer python3-pil 7zip unzip ranger \
          pavucontrol blueman)
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

#!/usr/bin/env bash
# power-audit.sh — auditoría de energía y rendimiento del port 43pr-debian.
# Solo lectura: no instala, no habilita y no modifica nada.
# Uso: ./tools/power-audit.sh [-h|--help]   (siempre sale con 0)
set -u
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
warnc=0 health="" limit="" swaps="" pkg_thr="" batdev=""
if [[ -t 1 ]]; then
    B=$'\033[1m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; N=$'\033[0m'
else
    B=''; G=''; Y=''; N=''
fi
section() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
pass()    { printf '  %sOK%s   %s\n' "$G" "$N" "$*"; }
warn()    { printf '  %sWARN%s %s\n' "$Y" "$N" "$*"; warnc=$((warnc + 1)); }
info()    { printf '  %sINFO%s %s\n' "$B" "$N" "$*"; }
have()    { command -v "$1" >/dev/null 2>&1 || [ -x "/usr/sbin/$1" ]; }
readf()   { cat "$1" 2>/dev/null || true; }
for arg in "$@"; do
    case "$arg" in
        -h|--help) printf '%s\n' 'Uso: ./tools/power-audit.sh' '' 'Auditoría de solo lectura: batería, CPU, memoria/swap, arranque,' 'temperaturas y energía. No cambia nada y siempre sale con 0'; exit 0 ;;
        *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
    esac
done
section "Batería"
bat=/sys/class/power_supply/BAT0
if [ -d "$bat" ]; then
    cap="$(readf "$bat/capacity")"; status="$(readf "$bat/status")"
    pass "BAT0: ${cap:-?}% (${status:-desconocido})"
    full="$(readf "$bat/charge_full")"; design="$(readf "$bat/charge_full_design")"
    [ -n "$full" ] || full="$(readf "$bat/energy_full")"
    [ -n "$design" ] || design="$(readf "$bat/energy_full_design")"
    if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] 2>/dev/null; then
        health=$((full * 100 / design)); wear=$((100 - health))
        if [ "$health" -ge 80 ]; then pass "Salud: ${health}% (desgaste ${wear}%)"
        else warn "Salud: ${health}% (desgaste ${wear}%; por debajo del 80%)"; fi
    fi
    cycles="$(readf "$bat/cycle_count")"
    [ -n "$cycles" ] && info "Ciclos de carga: $cycles"
    limit="$(readf "$bat/charge_control_end_threshold")"
    if [ -n "$limit" ]; then
        if [ "$limit" -eq 100 ] 2>/dev/null; then info "Límite de carga 100% (sugerencia: 60 u 80% enchufado)"
        elif [ "$limit" -le 80 ] 2>/dev/null; then pass "Límite de carga: ${limit}%"
        else info "Límite de carga: ${limit}% (sugerencia: 60-80%)"; fi
    fi
    for t in "$bat"/temp "$bat"/hwmon*/temp1_input; do
        [ -r "$t" ] || continue; v="$(readf "$t")"; [ -n "$v" ] || continue
        [ "$v" -gt 1000 ] 2>/dev/null && v=$((v / 1000))
        info "Temperatura de batería: ${v} °C"; break
    done
else
    warn "No existe /sys/class/power_supply/BAT0"
fi
ac_online=0
for ac in /sys/class/power_supply/*; do
    case "$(readf "$ac/type")" in
        Mains|USB|USB_PD)
            [ "$(readf "$ac/online")" = 1 ] && ac_online=1
            ;;
    esac
done
[ "$ac_online" -eq 1 ] && pass "Cargador conectado" || info "Cargador desconectado (batería)"

section "CPU"
profile="$(readf /sys/firmware/acpi/platform_profile)"
choices="$(readf /sys/firmware/acpi/platform_profile_choices)"
[ -n "$profile" ] && pass "platform_profile: ${profile} (disponibles: ${choices:-?})" || warn "platform_profile no disponible"
gov="$(readf /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
epp="$(readf /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"
[ -n "$gov" ] && pass "governor: $gov" || warn "governor no disponible"
[ -n "$epp" ] && pass "energy_performance_preference: $epp"
pstate="$(readf /sys/devices/system/cpu/intel_pstate/status)"
[ -n "$pstate" ] && pass "intel_pstate: $pstate"
turbo="$(readf /sys/devices/system/cpu/intel_pstate/no_turbo)"
if [ "$turbo" = 0 ]; then pass "Turbo habilitado (no_turbo=0)"
elif [ "$turbo" = 1 ]; then warn "Turbo deshabilitado (no_turbo=1)"; fi
cores="$(nproc 2>/dev/null || awk '/^processor/ {n++} END {print n+0}' /proc/cpuinfo)"
avg="$(awk -F: '/cpu MHz/ {s += $2; n++} END {if (n) printf "%.0f", s / n}' /proc/cpuinfo)"
pass "${cores} núcleos; media actual: ${avg:-?} MHz"
systemctl is-active --quiet power-profiles-daemon 2>/dev/null \
    && info "power-profiles-daemon activo: gestiona platform_profile (no lo cambies a mano)"
info "Controles de energía en la GUI: ./scripts/install-power-sudoers.sh"

section "Memoria"
total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
avail="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
[ -n "$total" ] && [ -n "$avail" ] && pass "$(awk -v t="$total" -v a="$avail" 'BEGIN {printf "RAM: %.1f GiB total, %.1f GiB disponible", t/1048576, a/1048576}')"
swaps="$(awk 'NR > 1 && $1 != "" {print $1}' /proc/swaps 2>/dev/null)"
if [ -n "$swaps" ]; then
    pass "Swap activa: $swaps"
    awk 'NR == 1 || $1 != "" {print "       " $0}' /proc/swaps
else
    warn "Sin swap ni zram: con la RAM llena el OOM killer puede matar procesos"
    info "Actívalo con: sudo bash $REPO/scripts/install-zram.sh"
fi
if [ -e /sys/block/zram0 ]; then
    zsize="$(readf /sys/block/zram0/disksize)"
    zalg="$(readf /sys/block/zram0/comp_algorithm | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\[/) {gsub(/[\[\]]/, "", $i); print $i}}')"
    [ -n "$zsize" ] && zsize="$(awk -v b="$zsize" 'BEGIN {printf "%.1f GiB", b/1073741824}')"
    info "zram0 presente: ${zsize:-?}, algoritmo ${zalg:-?}"
    [ -n "$swaps" ] || warn "zram0 existe pero no está activo como swap"
else
    info "zram no cargado"
fi
swappiness="$(readf /proc/sys/vm/swappiness)"
if [ -e /sys/block/zram0 ] && [ -n "$swaps" ] && [ "${swappiness:-100}" -lt 100 ] 2>/dev/null; then
    warn "vm.swappiness=${swappiness:-?} (bajo para zram; sugerido 150)"
else
    info "vm.swappiness=${swappiness:-?}"
fi
psi="$(awk '/^some/ {for (i = 1; i <= NF; i++) if ($i ~ /^avg300=/) {sub("avg300=", "", $i); print $i}}' /proc/pressure/memory 2>/dev/null)"
if [ -n "$psi" ]; then
    if awk -v v="$psi" 'BEGIN {exit !(v >= 5)}'; then warn "PSI memoria avg300=${psi}% (presión alta)"
    else pass "PSI memoria avg300=${psi}%"; fi
else
    info "PSI de memoria no disponible"
fi
oom=""
systemctl is-active --quiet systemd-oomd 2>/dev/null && oom="systemd-oomd"
[ -n "$oom" ] || { systemctl is-active --quiet earlyoom 2>/dev/null && oom="earlyoom"; }
if [ -n "$oom" ]; then pass "Gestor OOM activo: $oom"
elif [ -n "$swaps" ]; then info "Sin systemd-oomd/earlyoom (hay swap)"
else warn "Sin systemd-oomd ni earlyoom y sin swap"; fi

section "Almacenamiento"
root_used="$(df -P / 2>/dev/null | awk 'NR == 2 {gsub("%", "", $5); print $5}')"
root_avail="$(df -Ph / 2>/dev/null | awk 'NR == 2 {print $4}')"
if [ -n "$root_used" ]; then
    if [ "$root_used" -ge 90 ] 2>/dev/null; then
        warn "raíz al ${root_used}% (${root_avail} libres): libera espacio; ext4 pierde margen y las actualizaciones pueden fallar"
    else
        pass "raíz al ${root_used}% (${root_avail} libres)"
    fi
fi

section "Arranque y servicios"
if have systemd-analyze; then
    pass "$(systemd-analyze 2>/dev/null | head -n1)"
    info "Los 5 servicios más lentos:"
    systemd-analyze blame 2>/dev/null | head -n5 | sed 's/^/       /'
fi
if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then pass "fstrim.timer habilitado"
else warn "fstrim.timer no habilitado (SSD sin TRIM periódico)"; fi
for tool in thermald powertop irqbalance tlp tuned; do
    have "$tool" && pass "$tool instalado" || info "$tool no instalado (opcional)"
done
for svc in vboxdrv rabbitmq-server docker snapd tor; do
    systemctl is-enabled --quiet "$svc" 2>/dev/null \
        && info "$svc habilitado; si no lo usas: sudo systemctl disable --now ${svc}.service"
done
for ovs in ovs-vswitchd ovsdb-server; do
    systemctl is-active --quiet "$ovs" 2>/dev/null \
        && info "$ovs activo; si no lo usas: sudo systemctl disable --now ${ovs}.service"
done
section "Térmico"
pkg_temp=""
for hw in /sys/class/hwmon/hwmon*; do
    [ "$(readf "$hw/name")" = coretemp ] || continue
    for f in "$hw"/temp*_input; do
        [ -r "$f" ] || continue
        [ "$(readf "${f%_input}_label")" = "Package id 0" ] || continue
        pkg_temp="$(readf "$f")"; break 2
    done
done
if [ -n "$pkg_temp" ] && [ "$pkg_temp" -gt 0 ] 2>/dev/null; then
    c=$((pkg_temp / 1000))
    if [ "$c" -ge 90 ]; then warn "CPU package: ${c} °C (muy alto)"
    elif [ "$c" -ge 80 ]; then warn "CPU package: ${c} °C (alto)"
    else pass "CPU package: ${c} °C"; fi
else
    info "Sensor coretemp no disponible"
fi
fan=""; fan_sensor=0
for hw in /sys/class/hwmon/hwmon*; do
    [ "$(readf "$hw/name")" = acpi_fan ] || continue
    fan_sensor=1; fan="$(readf "$hw/fan1_input")"
done
if [ "$fan_sensor" -eq 1 ]; then
    [ -n "$fan" ] && info "Ventilador: ${fan} RPM" || info "Ventilador: lectura no disponible (acpi_fan)"
fi
pkg_thr="$(readf /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count)"
core_thr="$(for f in /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count; do readf "$f"; done | awk '{s += $1} END {print s+0}')"
if { [ -n "$pkg_thr" ] && [ "$pkg_thr" -gt 0 ] 2>/dev/null; } || [ "${core_thr:-0}" -gt 0 ] 2>/dev/null; then
    warn "Throttle desde el arranque: paquete=${pkg_thr:-?}, núcleos=${core_thr:-0} (térmico o límite de potencia)"
else
    pass "Sin eventos de throttle registrados"
fi
section "Energía"
if have upower; then
    batdev="$(upower -e 2>/dev/null | grep -i bat | head -n1)"
    if [ -n "$batdev" ]; then
        summary="$(upower -i "$batdev" 2>/dev/null | grep -E '^[[:space:]]+(energy-full|energy-full-design|charge-cycles|capacity):' | sed 's/^[[:space:]]*//')"
        [ -n "$summary" ] && { pass "upower: $batdev"; printf '%s\n' "$summary" | sed 's/^/       /'; }
    fi
else
    info "upower no instalado"
fi
if have powerprofilesctl; then
    if pp="$(powerprofilesctl get 2>/dev/null)"; then pass "powerprofilesctl: $pp"
    else info "powerprofilesctl sin daemon activo (PPD ausente o enmascarado)"; fi
else
    info "powerprofilesctl no instalado"
fi
usb_total=0; usb_auto=0
for f in /sys/bus/usb/devices/*/power/control; do
    [ -r "$f" ] || continue
    usb_total=$((usb_total + 1))
    [ "$(readf "$f")" = auto ] && usb_auto=$((usb_auto + 1))
done
[ "$usb_total" -gt 0 ] && info "USB autosuspend: ${usb_auto}/${usb_total} dispositivos en auto"

suggestions=()
[ -z "$swaps" ] && suggestions+=("sudo bash $REPO/scripts/install-zram.sh")
[ -n "$limit" ] && [ "$limit" -eq 100 ] 2>/dev/null \
    && suggestions+=("echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold")
[ -n "$health" ] && [ "$health" -lt 80 ] \
    && suggestions+=("upower -i $batdev   # vigilar la salud de la batería")
systemctl is-enabled --quiet vboxdrv 2>/dev/null \
    && suggestions+=("sudo systemctl disable --now vboxdrv.service")
systemctl is-enabled --quiet rabbitmq-server 2>/dev/null \
    && suggestions+=("sudo systemctl disable --now rabbitmq-server.service")
[ -n "$pkg_thr" ] && [ "$pkg_thr" -gt 0 ] 2>/dev/null \
    && suggestions+=("cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_total_time_ms")
[ ! -x "$REPO/scripts/install-power-sudoers.sh" ] \
    && suggestions+=("$REPO/scripts/install-power-sudoers.sh   # controles de energía en la GUI")
[ "${#suggestions[@]}" -lt 3 ] \
    && suggestions+=("systemd-analyze blame | head -n 10" "cat /proc/pressure/memory" "systemd-analyze critical-chain")

printf '\nResumen: %d avisos\n' "$warnc"
printf 'Sugerencias:\n'
n=0
for s in "${suggestions[@]}"; do
    [ "$n" -ge 6 ] && break
    printf '  - %s\n' "$s"; n=$((n + 1))
done
exit 0

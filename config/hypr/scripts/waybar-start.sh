#!/bin/sh
# waybar-start.sh — lanza waybar a traves del puente IPC waybar-ipc-shim.py.
#
# waybar 0.12 envia los clics de los iconos de workspace con la sintaxis
# antigua ("dispatch workspace N") y Hyprland 0.55 configurado en Lua ya solo
# acepta dispatchers Lua. El puente traduce esos clics (ver el comentario de
# waybar-ipc-shim.py). Se usa en el autostart (hyprland.lua) y en el atajo
# SUPER+SHIFT+W.
#
# Si el puente no puede arrancar, waybar se lanza igual sin el: la barra
# funciona, pero el clic en los iconos no cambiara de escritorio.

set -u

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec_plain() {
    exec waybar "$@"
}

real_sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ -z "$real_sig" ] || ! command -v python3 >/dev/null 2>&1; then
    exec_plain "$@"
fi

fake_sig="waybar-lua-shim"
shim_dir="$runtime/hypr/$fake_sig"
pidfile="$shim_dir/shim.pid"
log="$runtime/waybar-ipc-shim.log"

shim_pid() { cat "$pidfile" 2>/dev/null; }

shim_alive() {
    pid="$(shim_pid)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

shim_matches() {
    pid="$(shim_pid)"
    [ -n "$pid" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "--real-sig $real_sig"
}

# Puente de una sesion anterior de Hyprland: lo paramos y arrancamos otro.
if shim_alive && ! shim_matches; then
    kill "$(shim_pid)" 2>/dev/null
    i=0
    while shim_alive && [ "$i" -lt 20 ]; do
        sleep 0.1
        i=$((i + 1))
    done
fi

# Puente huerfano del que ya no queda pidfile: lo paramos.
if ! shim_alive && pgrep -f "waybar-ipc-shim.py --real-sig" >/dev/null 2>&1; then
    pkill -f "waybar-ipc-shim.py --real-sig" 2>/dev/null
    sleep 0.3
fi

if ! shim_alive; then
    rm -rf "$shim_dir"
    mkdir -p "$shim_dir"
    nohup python3 "$script_dir/waybar-ipc-shim.py" \
        --real-sig "$real_sig" --fake-sig "$fake_sig" >>"$log" 2>&1 &
fi

# Espera (max. 5 s) a que el socket de comandos este listo.
i=0
while [ ! -S "$shim_dir/.socket.sock" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
done

if [ ! -S "$shim_dir/.socket.sock" ]; then
    echo "waybar-start.sh: el puente IPC no arranco; revisa $log" >&2
    exec_plain "$@"
fi

export HYPRLAND_INSTANCE_SIGNATURE="$fake_sig"
exec waybar "$@"

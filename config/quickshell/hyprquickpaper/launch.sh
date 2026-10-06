#!/usr/bin/env bash
# Toggle the wallpaper picker on the currently focused monitor.
# If an instance is already running it is closed; otherwise it is launched.
# HYPRPAPER_MON is read by shell.qml to choose the PanelWindow's screen.
set -euo pipefail

dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Toggle: close the running instance if there is one. `qs ipc` exits 255 when
# there are no running instances, so this doubles as the "is it open?" test.
if qs ipc -p "$dir" call hyprquickpaper close >/dev/null 2>&1; then
    exit 0
fi

mon=""
if command -v jq >/dev/null 2>&1; then
    mon="$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' | head -n1)"
fi

if [ -n "$mon" ]; then
    export HYPRPAPER_MON="$mon"
fi

exec qs -n -p "$dir"

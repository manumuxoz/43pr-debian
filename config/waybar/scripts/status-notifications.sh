#!/usr/bin/env bash
# Waybar: Quickshell notification panel / Do Not Disturb state.
# Prints a JSON line consumed by custom/notifications (return-type: json).

set -u

state="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/state/notifications-state.json"
dnd=false
if [ -f "$state" ]; then
    dnd="$(jq -r 'if .dnd == true then "true" else "false" end' "$state" 2>/dev/null || echo false)"
fi

if [ "$dnd" = "true" ]; then
    jq -cn '{text:"󰂛", class:"paused", tooltip:"No molestar · clic para abrir las notificaciones"}'
else
    jq -cn '{text:"󰂚", class:"active", tooltip:"Notificaciones · clic para abrir, clic derecho para No molestar"}'
fi

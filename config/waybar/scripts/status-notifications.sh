#!/usr/bin/env bash
# Waybar: pending notifications and Do Not Disturb state (dunst).
# Prints a JSON line consumed by custom/notifications (return-type: json).

set -u

if ! command -v dunstctl >/dev/null 2>&1; then
    jq -cn '{text:"", class:"unavailable", tooltip:"dunstctl no disponible"}'
    exit 0
fi

paused="$(dunstctl is-paused 2>/dev/null || echo false)"
waiting="$(dunstctl count waiting 2>/dev/null || echo 0)"
displayed="$(dunstctl count displayed 2>/dev/null || echo 0)"
[[ "$waiting" =~ ^[0-9]+$ ]] || waiting=0
[[ "$displayed" =~ ^[0-9]+$ ]] || displayed=0

if [[ "$paused" == "true" ]]; then
    text="󰂛"
    class="paused"
    tooltip="No molestar activado · $waiting en espera"
    [[ "$waiting" -gt 0 ]] && text+=" $waiting"
else
    text="󰂚"
    class="active"
    tooltip="$waiting notificación(es) en espera"
    [[ "$displayed" -gt 0 ]] && tooltip+=" · $displayed mostrada(s)"
    if [[ "$waiting" -gt 0 ]]; then
        text+=" $waiting"
        class="has"
    fi
fi

jq -cn --arg text "$text" --arg class "$class" --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'

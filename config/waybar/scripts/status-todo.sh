#!/usr/bin/env bash
# Waybar: pending Quickshell Todo items and how many reminders are overdue.
# Prints a JSON line consumed by custom/todo (return-type: json).

set -u

state="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/state/todo-state.json"
now="$(date +%s%3N)"
pending=0
overdue=0

if [[ -r "$state" ]] && command -v jq >/dev/null 2>&1; then
    read -r pending overdue < <(
        jq -r --argjson now "$now" '
            [.items[] | select(.done != true)] as $pending
            | [
                ($pending | length),
                ([$pending[] | select(.remindAt > 0 and .remindAt <= $now)] | length)
              ]
            | @tsv
        ' "$state" 2>/dev/null
    )
fi
[[ "$pending" =~ ^[0-9]+$ ]] || pending=0
[[ "$overdue" =~ ^[0-9]+$ ]] || overdue=0

if [[ "$pending" -eq 0 ]]; then
    jq -cn '{text:"", class:"empty", tooltip:"Sin tareas pendientes"}'
    exit 0
fi

text="󰄬 $pending"
class="pending"
tooltip="$pending tarea(s) pendiente(s)"
if [[ "$overdue" -gt 0 ]]; then
    text+="  ⚠ $overdue"
    class="overdue"
    tooltip+=" · $overdue con recordatorio vencido"
fi

jq -cn --arg text "$text" --arg class "$class" --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'

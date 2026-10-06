#!/bin/bash

choice=$(printf "100%%\n90%%\n80%%\n70%%\n60%%\n50%%\n40%%" | wofi --dmenu --prompt "")

case "$choice" in
    "100%") opacity=1.0 ;;
    "90%")  opacity=0.9 ;;
    "80%")  opacity=0.8 ;;
    "70%")  opacity=0.7 ;;
    "60%")  opacity=0.6 ;;
    "50%")  opacity=0.5 ;;
    "40%")  opacity=0.4 ;;
    *) exit 0 ;;
esac

rules_file="$HOME/.config/hypr/rules.lua"

if ! grep -qE '^[[:space:]]*opacity[[:space:]]*=[[:space:]]*"[^"]+ override"' "$rules_file"; then
    notify-send -u critical "Opacidad" "No encuentro la regla opacity esperada en $rules_file; no se cambio nada."
    exit 1
fi

sed -i "0,/opacity = \".* override\"/s//opacity = \"$opacity override\"/" "$rules_file"

hyprctl reload

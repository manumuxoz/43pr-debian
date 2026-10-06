#!/usr/bin/env bash
# Conmutador de escritorios para Hyprland (SUPER+G).
# Muestra TODOS los workspaces con su nº de ventanas y las apps que contienen;
# al elegir uno, salta a ese escritorio.
# Notas:
#  - Hyprland 0.55 con config Lua recibe los dispatches como expresión Lua
#    (hl.dsp...), no con la sintaxis legacy "hyprctl dispatch workspace N".
#  - Se usa --sort-order alphabetical en wofi porque wofi mantiene
#    ~/.cache/wofi-dmenu (contador de uso) y por defecto coloca arriba los
#    workspaces usados con más frecuencia. El prefijo "01 · ", "02 · "...
#    garantiza orden numérico correcto también con workspaces de 2 cifras.
set -u

ws_file=$(mktemp)
cl_file=$(mktemp)
trap 'rm -f "$ws_file" "$cl_file"' EXIT

hyprctl -j workspaces >"$ws_file" 2>/dev/null || exit 1
hyprctl -j clients >"$cl_file" 2>/dev/null || true

menu=$(jq -rn --slurpfile ws "$ws_file" --slurpfile cl "$cl_file" '
  (($cl[0] // []) | group_by(.workspace.id)
    | map({ key: (.[0].workspace.id | tostring), value: (map(.class) | unique) })
    | from_entries) as $apps
  | ($ws[0] | sort_by([
      (if ((.name // "") | test("^[0-9]+$")) then (.name | tonumber) else 100000 end),
      (.name // ""),
      .id
    ])) as $sorted
  | range(0; $sorted | length) as $i
  | $sorted[$i] as $w
  | (($i + 1) | tostring | if length < 2 then "0" + . else . end) as $n
  | "\($n) · WS [\($w.id)]"
    + (if ($w.name // "") != "" and ($w.name // "") != ($w.id | tostring) then " " + $w.name else "" end)
    + " — \($w.windows) ventana\(if $w.windows == 1 then "" else "s" end)"
    + (if (($apps[($w.id | tostring)] // []) | length) > 0
        then ": " + ($apps[($w.id | tostring)] | join(", "))
        else "" end)
')

[ -n "$menu" ] || exit 0

if [ -n "${WS_SWITCH_SELECT:-}" ]; then
    sel="$WS_SWITCH_SELECT"        # modo test: selección inyectada
else
    sel=$(printf '%s\n' "$menu" | wofi --dmenu --prompt "Escritorio…" --width 640 --sort-order alphabetical) || exit 0
fi
[ -n "$sel" ] || exit 0

id=$(printf '%s' "$sel" | sed -nE 's/.*WS \[(-?[0-9]+)\].*/\1/p')
[ -n "$id" ] || exit 0

name=$(jq -r --argjson id "$id" '.[] | select(.id == $id) | .name // empty' "$ws_file" | head -n1)

if [ "$id" -lt 0 ] && [ -n "$name" ]; then
    # Los especiales se enfocan como "special:<nombre>" (name viene como
    # "special:scratch"; se quita el prefijo si ya lo trae).
    hyprctl dispatch "hl.dsp.focus({workspace=\"special:${name#special:}\"})" >/dev/null
else
    hyprctl dispatch "hl.dsp.focus({workspace=$id})" >/dev/null
fi

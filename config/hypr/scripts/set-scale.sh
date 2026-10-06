#!/usr/bin/env bash
# set-scale.sh <escala> [output]
#
# Wrapper fino de monitor-ctl.sh (mantiene la firma antigua):
#   set-scale.sh 1.75          -> monitor-ctl.sh scale <salida principal> 1.75
#   set-scale.sh 1.75 eDP-1    -> monitor-ctl.sh scale eDP-1 1.75
#
# Toda la logica (aplicar en vivo, validar, persistir el bloque gestionado,
# asegurar debug:disable_scale_checks) vive en scripts/monitor-ctl.sh.

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "uso: set-scale.sh <escala> [output]" >&2
    exit 1
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ctl="$here/monitor-ctl.sh"

if [ ! -x "$ctl" ]; then
    echo "set-scale: no encuentro $ctl" >&2
    exit 1
fi

if [ "$#" -eq 2 ]; then
    output="$2"
else
    output="$("$ctl" primary)"
fi

exec "$ctl" scale "$output" "$1"

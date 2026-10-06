#!/bin/bash
# RAM speed for Quickshell's SystemPage.
#
# The SMBIOS memory tables (/sys/firmware/dmi, /dev/mem) are root-only, so
# the speed is read once through polkit (pkexec) and cached. Later calls
# only print the cached value; delete the cache to refresh:
#
#   rm ~/.cache/quickshell/ram-speed
#
# Prints an em dash when the user cancels or the data is unavailable.

set -u

cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/ram-speed"

if [ -s "$cache" ]; then
    cat "$cache"
    exit 0
fi

dmi=$(pkexec /usr/bin/dmidecode -t memory 2>/dev/null) || true

speed=$(printf '%s\n' "$dmi" | awk '
    /^[[:space:]]*Speed:/ && spd == "" { spd = $2 " " $3 }
    /^[[:space:]]*Configured Memory Speed:/ { cspd = $4 " " $5; exit }
    END { print (cspd != "" ? cspd : spd) }
')

if [ -n "$speed" ]; then
    mkdir -p "$(dirname "$cache")"
    printf '%s\n' "$speed" >"$cache"
fi

printf '%s\n' "${speed:-—}"

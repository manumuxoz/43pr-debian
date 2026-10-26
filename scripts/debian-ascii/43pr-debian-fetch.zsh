# Cabecera Debian ASCII animada para fastfetch/kitty.
#
# Uso: añade esta línea a ~/.zshrc
#
#   source "$HOME/Proyectos/43pr-debian/scripts/debian-ascii/43pr-debian-fetch.zsh"
#
# La cabecera se dibuja al abrir la terminal, se pausa al ejecutar un comando
# y sube con el scroll. No se queda fija.

typeset -g _DEBIAN_FETCH_SCRIPT="${${(%):-%x}:A:h}/debian-fetch-header.py"
typeset -g _DEBIAN_FETCH_TTY_TAG="${TTY#/}"
_DEBIAN_FETCH_TTY_TAG="${_DEBIAN_FETCH_TTY_TAG//\//_}"
typeset -g _DEBIAN_FETCH_PID="${XDG_RUNTIME_DIR:-/tmp}/debian-fetch-header-${_DEBIAN_FETCH_TTY_TAG}-$UID.pid"

# Devuelve el PID solo si el proceso sigue siendo nuestro script. Evita
# mandar señales a un PID reciclado tras un cierre anormal.
_debian_fetch_pid() {
    local pid
    [[ -s "$_DEBIAN_FETCH_PID" ]] || return 1
    pid=$(<"$_DEBIAN_FETCH_PID")
    [[ "$pid" == <-> ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    [[ "$(tr '\0' ' ' < "/proc/$pid/cmdline")" == *debian-fetch-header.py* ]] || return 1
    print -r -- "$pid"
}

_debian_fetch_alive() {
    _debian_fetch_pid >/dev/null
}

_debian_fetch_signal() {
    local pid
    pid=$(_debian_fetch_pid) || return 0
    kill -"$1" "$pid" 2>/dev/null
}

# Arranca la cabecera si no existe; si ya existe, la reanuda.
debian-fetch-start() {
    if [[ -n "$FASTFETCH_TTY" && "$FASTFETCH_TTY" != "$TTY" ]]; then
        return 0
    fi
    if _debian_fetch_alive; then
        _debian_fetch_signal USR2
        return 0
    fi
    if [[ -f "$_DEBIAN_FETCH_SCRIPT" ]]; then
        if ! python3 "$_DEBIAN_FETCH_SCRIPT" --pidfile "$_DEBIAN_FETCH_PID" --fallback "$@"; then
            command fastfetch
        fi
    else
        command fastfetch
    fi
}

# Detiene la animación, limpia la cabecera y restaura la región de scroll.
debian-fetch-stop() {
    local pid i
    _debian_fetch_signal TERM
    pid=$(_debian_fetch_pid) || true
    if [[ -n "$pid" ]]; then
        for i in {1..20}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.01
        done
    fi
    rm -f "$_DEBIAN_FETCH_PID"
    printf '\e[r'
}

debian-fetch-pause() {
    _debian_fetch_signal USR1
}

debian-fetch-resume() {
    _debian_fetch_signal USR2
}

# Compatibilidad con el nombre anterior: sin argumentos, arranca/reanuda.
debian-fetch() {
    debian-fetch-start "$@"
}

debian-fetch-restart() {
    debian-fetch-stop
    debian-fetch-start "$@"
}

# Pausa antes de ejecutar un comando; clear/reset paran la cabecera para no
# repintarla sobre una pantalla limpia.
_debian_fetch_preexec() {
    [[ -n "$FASTFETCH_TTY" && "$FASTFETCH_TTY" == "$TTY" ]] || return 0
    case "$1" in
        clear|reset|c) debian-fetch-stop ;;
        *) debian-fetch-pause ;;
    esac
}

# Solo el shell dueño de la terminal detiene la cabecera al salir; un shell
# anidado no debe matar la animación del shell padre.
_debian_fetch_cleanup() {
    [[ "${DEBIAN_FETCH_OWNER:-}" == "$$" ]] || return 0
    debian-fetch-stop
    unset FASTFETCH_TTY DEBIAN_FETCH_OWNER
}

if [[ -o interactive ]]; then
    _debian_fetch_clear_widget() {
        debian-fetch-stop
        zle clear-screen
    }
    zle -N _debian_fetch_clear_widget
    bindkey '^L' _debian_fetch_clear_widget
fi

autoload -Uz add-zsh-hook
add-zsh-hook preexec _debian_fetch_preexec
add-zsh-hook zshexit _debian_fetch_cleanup

# Solo en shells interactivos y una vez por terminal: los shells anidados
# comparten el mismo TTY y reanudan la animación existente.
if [[ -o interactive && -t 1 && "${FASTFETCH_TTY:-}" != "$TTY" ]]; then
    export FASTFETCH_TTY="$TTY"
    export DEBIAN_FETCH_OWNER=$$
    debian-fetch-start
elif [[ -o interactive && -t 1 && -n "${FASTFETCH_TTY:-}" && "$FASTFETCH_TTY" == "$TTY" ]]; then
    if [[ -n "${DEBIAN_FETCH_OWNER:-}" ]] && ! kill -0 "$DEBIAN_FETCH_OWNER" 2>/dev/null; then
        export DEBIAN_FETCH_OWNER=$$
    fi
    debian-fetch-start
fi

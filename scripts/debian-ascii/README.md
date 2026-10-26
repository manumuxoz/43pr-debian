# Cabecera Debian ASCII animada para fastfetch

Cabecera para kitty que combina el logo Debian en ASCII con la información de
`fastfetch`:

- Logo fijo de **22×13** a la izquierda, en rojo `#A80030`, con una línea de
  barrido animada.
- Información de fastfetch a la derecha, sin volver a ejecutarlo en cada frame.
- El prompt y los comandos van debajo.
- La animación se pausa al ejecutar un comando y **no** se reanuda sola.
- La cabecera no se queda fija: al llenarse la pantalla sube con el scroll como
  cualquier otra línea.

## Requisitos

- Debian 13 / zsh.
- `fastfetch` y `python3`.
- Terminal de al menos **69×26** (22 de logo + 2 de separación + 45 de info +
  10 de shell). En kitty funciona sin configuración extra.
- No hace falta actualizar fastfetch: la animación la gestiona el script, no
  fastfetch. La animación nativa de fastfetch (GIF/APNG en `logo.type: kitty`)
  solo existe desde la 2.69 y no es ASCII.

## Instalación

Copia la carpeta a tu HOME o clona el repositorio y añade esta línea al final
de `~/.zshrc`:

```zsh
source "$HOME/Proyectos/43pr-debian/scripts/debian-ascii/43pr-debian-fetch.zsh"
```

Ajusta la ruta si tienes el repositorio en otro sitio. Abre una terminal nueva.

También puedes probarlo sin tocar el `.zshrc`:

```sh
python3 /ruta/a/scripts/debian-ascii/debian-fetch-header.py \
  --no-fork --seconds 10
```

## Controles

```sh
debian-fetch-start      # arranca o reanuda
debian-fetch-pause      # pausa
debian-fetch-resume     # reanuda y redibuja
debian-fetch-stop       # para la animación; deja la cabecera en el scrollback
debian-fetch-restart    # reinicia
```

`clear`, `reset` y `Ctrl+L` paran la animación y limpian la pantalla. Para
recuperar la cabecera después, `debian-fetch-start`.

## Opciones

```sh
# otro arte (mediano 30×18 o grande 44×26); por defecto siempre 22×13
python3 debian-fetch-header.py --art debian_medium_30x18.txt

# velocidad y color
python3 debian-fetch-header.py --fps 15 --color 206,0,86

# estado
python3 debian-fetch-header.py --status
```

Opciones principales: `--art`, `--fps`, `--color R,G,B`, `--no-glitch`,
`--fallback`, `--pidfile`, `--status`, `--stop`, `--resume`, `--no-fork` y
`--seconds`.

## Cómo funciona

El script ejecuta `fastfetch --logo-type none` una vez, guarda la información y
dibuja el logo animado en las filas superiores. El proceso de animación se
separa en un hijo y se pausa con `SIGUSR1` cuando zsh va a ejecutar un comando.
Al no fijar una región de scroll, la cabecera se desplaza hacia arriba con la
salida normal de la terminal.

El PID se guarda por terminal en
`${XDG_RUNTIME_DIR:-/tmp}/debian-fetch-header-<tty>-<uid>.pid`, así que varias
terminales pueden tener su propia cabecera.

## Créditos y licencias

- Código del script: MIT, igual que el resto del repositorio.
- Logo Debian: marca de Debian. El *Open Use Logo* se distribuye bajo LGPLv3+
  o CC BY-SA 3.0; fuente oficial: <https://www.debian.org/logos/>.
- Los artes ASCII se generaron a partir del SVG oficial
  [`openlogo-nd.svg`](https://www.debian.org/logos/openlogo-nd.svg) con una
  rampa de densidad.
- La idea del barrido está inspirada en el arte animado de
  <https://ascii.rest/debian/> (código MIT).

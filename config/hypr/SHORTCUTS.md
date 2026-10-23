# Atajos de Hyprland (cheatsheet)

- **mainMod**: `SUPER` (tecla Windows/Cmd)
- **Config**: `~/.config/hypr/keybinds.lua`
- **Recargar tras editar**: `hyprctl reload`
- **Layout de teclado**: `es` (afecta a los binds de teclas especiales, ver **Notas**)
- **Total**: 85 binds activos

> Algunas filas agrupan varios binds (los rangos 1–9 / 0 de workspaces).

## Lanzadores / aplicaciones

| Atajo | Acción |
| --- | --- |
| `SUPER + T` | Terminal — kitty |
| `SUPER + D` | Menú de aplicaciones — wofi `--show drun` (si wofi ya está abierto, lo cierra) |
| `SUPER + E` | Gestor de archivos — thunar |
| `SUPER + B` | Navegador — firefox |

## Ventanas

| Atajo | Acción |
| --- | --- |
| `SUPER + Q` | Cerrar la ventana activa |
| `SUPER + F` | Alternar pantalla completa |
| `SUPER + Espacio` | Alternar ventana flotante; si queda flotante, la centra y redimensiona al 70 % del monitor |
| `SUPER + H` | Foco a la izquierda (estilo vim) |
| `SUPER + J` | Foco abajo |
| `SUPER + K` | Foco arriba |
| `SUPER + L` | Foco a la derecha (estilo vim) |
| `SUPER + SHIFT + H` | Mover la ventana activa a la izquierda |
| `SUPER + SHIFT + J` | Mover la ventana activa abajo |
| `SUPER + SHIFT + K` | Mover la ventana activa arriba |
| `SUPER + SHIFT + L` | Mover la ventana activa a la derecha |
| `SUPER + CTRL + H` | Redimensionar: −40 px en horizontal (repetible) |
| `SUPER + CTRL + L` | Redimensionar: +40 px en horizontal (repetible) |
| `SUPER + CTRL + K` | Redimensionar: −40 px en vertical (repetible) |
| `SUPER + CTRL + J` | Redimensionar: +40 px en vertical (repetible) |
| `SUPER + S` | Alternar el scratchpad — workspace especial `scratch` (toggle) |
| `SUPER + SHIFT + S` | Mover la ventana activa al scratchpad (`special:scratch`) |

> **Snap de ventanas** activado (`look.lua`, `general.snap`): al mover una
> ventana se ajusta a las demás y a los bordes del monitor (window_gap 4,
> monitor_gap 8, respeta los gaps).

## Workspaces

| Atajo | Acción |
| --- | --- |
| `SUPER + 1 … 9` | Cambiar al workspace 1–9 |
| `SUPER + 0` | Cambiar al workspace 10 |
| `SUPER + SHIFT + 1 … 9` | Mover la ventana activa al workspace 1–9 |
| `SUPER + SHIFT + 0` | Mover la ventana activa al workspace 10 |

## Ratón

| Atajo | Acción |
| --- | --- |
| `SUPER + arrastrar botón izquierdo` | Mover la ventana |
| `SUPER + arrastrar botón derecho` | Redimensionar la ventana |
| `SUPER + rueda arriba` | Zoom del cursor +0.5 (rango 1.0–1.5, repetible) |
| `SUPER + rueda abajo` | Zoom del cursor −0.5 (rango 1.0–1.5, repetible) |

## Gestos táctiles

| Gesto | Acción |
| --- | --- |
| 3 dedos, deslizar en horizontal | Cambiar de workspace |

> El gesto se define en `hyprland.lua` (`hl.gesture`: 3 dedos, dirección
> horizontal, acción `workspace`). No cuenta como bind.

## Multimedia

Funcionan también con la pantalla bloqueada (`locked`).

| Atajo | Acción |
| --- | --- |
| `Volumen +` | Subir volumen del sink por defecto (+5 %; **tope 100 %**, sin sobre-amplificación) |
| `Volumen −` | Bajar volumen (−5 %; si hubiera quedado por encima del 100 %, lo devuelve al 100 %) |
| `Mute` | Silenciar/desilenciar |
| `Mic mute` (`XF86AudioMicMute`) | Silenciar/desilenciar el micrófono por defecto (`wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`) |
| `Play/Pausa` | playerctl play-pause |
| `Siguiente` | playerctl next |
| `Anterior` | playerctl previous |
| `Brillo −` | Bajar brillo de pantalla un 5 % (Fn+F4 → `XF86MonBrightnessDown`) |
| `Brillo +` | Subir brillo de pantalla un 5 % (Fn+F5 → `XF86MonBrightnessUp`) |
| `Fn+F1 en Logitech` | Mismo que F1 del portátil: Mute (`XF86HomePage`) |
| `Fn+F2 en Logitech` | Mismo que F2 del portátil: Volumen − (`XF86Mail`) |
| `Fn+F3 en Logitech` | Mismo que F3 del portátil: Volumen + (`XF86Search`) |
| `Fn+F4 en Logitech` | Mismo que F4 del portátil: Brillo − (`XF86Calculator`) |
| `Fn+F5 en Logitech` | Mismo que F5 del portátil: Brillo + (`XF86Tools`) |

> En el teclado del portátil, **Fn+F1/F2/F3** emiten Mute/Bajar/Subir
> (`XF86AudioMute`/`LowerVolume`/`RaiseVolume`) y actúan sobre el sink por
> defecto. El volumen está limitado a **100 %** (`wpctl set-volume -l 1.0`,
> sin sobre-amplificación). La salida cambia automáticamente entre **altavoces
> internos y auriculares** al conectar/desconectar el jack, y la salida interna
> es la predeterminada (servicio `audio-jack-switch.service`, ver
> `~/.config/hypr/scripts/audio-jack-switch.py`): lleva antirrebote (~1 s) y,
> si el default quedara en una salida HDMI/DP sin conexión, la restaura.
> En Ajustes > Audio, las salidas HDMI/DisplayPort sin conexión aparecen
> atenuadas con "SIN CONEXIÓN" y no se pueden seleccionar.
>
> **Fn+F4/Fn+F5** no pasan por el teclado interno: llegan como
> `XF86MonBrightnessDown`/`XF86MonBrightnessUp` desde el dispositivo ACPI
> **Video Bus**. Hyprland las gestiona con `brightnessctl` sobre el panel
> `intel_backlight` (5 % por pulsación, repetible al mantener). Cada cambio de
> brillo muestra el mismo OSD superior que el volumen (componente
> `~/.config/quickshell/BrightnessOsd.qml`, que observa sysfs y se dispara con
> cualquier cambio, venga de las teclas o del slider del panel).
>
> **Teclado Logitech K235** (receptor Nano `046d:4023`): su fila Fn venía con
> otro orden (Fn+F1=Internet, F2=Email, F3=Buscar, F4=Calculadora,
> F5=Reproductor, F6/F7/F8=Prev/Play/Next, F9/F10/F11=Mute/Vol−/Vol+,
> F12=ImprPant). Desde `keybinds.lua`, Fn+F1..F5 del Logitech ejecutan lo
> mismo que F1..F5 del portátil (misma posición, misma acción). Fn+F9/F10/F11
> del Logitech ya coincidían con F1/F2/F3 del portátil (Mute/Vol−/Vol+) y
> Fn+F6/F7/F8 ya eran Prev/Play/Next, así que esos no se tocan. Fn+F12
> (ImprPant) se deja como está.

## Capturas y grabación

| Atajo | Acción |
| --- | --- |
| `SUPER + Supr (Delete)` | Captura del **monitor con el foco** (`grim -o`) → `~/Imágenes/Capturas de pantalla/<fecha-hora>.png`; copia al portapapeles (`wl-copy`) y notificación OSD (`qs ipc call screenshot notify`, tolerante a fallos); wrapper `~/.config/hypr/scripts/screenshot.sh` |
| `SUPER + SHIFT + Supr (Delete)` | Captura de **área**: selección con `slurp` + `grim -g` → mismo flujo (archivo, portapapeles, notificación); `Esc` cancela sin guardar; wrapper `~/.config/hypr/scripts/screenshot.sh area` |
| `SUPER + CTRL + Supr (Delete)` | Captura de área + anotación: `slurp` + `grim` a un temporal y editor **swappy** (flechas, texto, difuminado); `Ctrl+S` guarda en `~/Imágenes/Capturas de pantalla/` y `Ctrl+C` copia al portapapeles; wrapper `screenshot.sh annotate` |
| `SUPER + R` | Grabar/parar con wf-recorder (monitor con el foco, audio por defecto) → `~/Vídeos/Grabaciones de la pantalla/rec-<fecha-hora>.mp4` (carpeta XDG de vídeos, la misma que usaba GNOME); wrapper `~/.local/bin/screen-record.sh` con PID en `/tmp/osu-rec.pid`; al parar espera a finalizar el MP4 antes de notificar. Mientras grabas se muestra un indicador REC arriba a la derecha (`RecorderOSD.qml`) |

## Cámara (webcam)

| Atajo | Acción |
| --- | --- |
| `SUPER + C` | Vista previa flotante de la webcam — `mpv` (toggle: repetir el atajo cierra la ventana) |

> Con la ventana abierta se controla todo desde dentro (script `camera-mpv.lua`):
> **`s`** = foto → `~/Imágenes/Camera/<fecha-hora>.jpg`;
> **`r`** = grabar/parar → `~/Vídeos/Camera/<fecha-hora>.mp4` (H.264).
> Wrapper `~/.config/hypr/scripts/camera.sh`: captura V4L2 directa con `mpv`
> (sin paquetes extra). La webcam solo admite un lector a la vez, así que `mpv`
> es el único que accede al dispositivo: graba a un FIFO y un `ffmpeg` de fondo
> reencoda a H.264. Autodetecta `/dev/video0`; se puede forzar con `CAMERA_DEVICE`
> y ajustar `CAMERA_SIZE` (1280x720).

## Utilidades

| Atajo | Acción |
| --- | --- |
| `SUPER + V` | Historial del portapapeles — cliphist + wofi (toggle) |
| `SUPER + X` | Cambiar al siguiente layout de teclado |
| `SUPER + SHIFT + D` | Alternar tema claro/oscuro (`theme.py toggle`) |
| `SUPER + P` | Selector de color — `hyprpicker -a` (copia el color HEX al portapapeles; hyprpicker 0.4.7 instalado) |
| `SUPER + SHIFT + P` | Luz nocturna on/off — `~/.config/hypr/scripts/nightlight-toggle.sh` (hyprsunset 0.4.0; 4000 K por defecto, temperatura compartida con Ajustes → Display y guardada; `NIGHTLIGHT_TEMP` la fuerza al activar) |
| `SUPER + O` | Menú de opacidad de la ventana activa (wofi; guarda override en `rules.lua` y recarga) — toggle: repetir el atajo cierra el menú |
| `SUPER + G` | Conmutador de escritorios — wofi con todos los escritorios, nº de ventanas y apps; eliges y salta (toggle: repetir el atajo cierra el menú) |
| `SUPER + W` | Fondos de pantalla — quickshell hyprquickpaper |
| `SUPER + I` | Panel de ajustes — quickshell settings |
| `SUPER + N` | Bloc de notas — widget de notas (Quickshell), autoguardado; `Ctrl+Shift+S` = «guardar como…» en cualquier ruta (toggle) |
| `SUPER + SHIFT + T` | Tareas y recordatorios — widget Todo (Quickshell): tareas con recordatorio (`30s`, `45m`, `2h`, `1d`, `14:30`, `tomr 9am`…), avisa con `notify-send` (toggle) |
| `SUPER + SHIFT + M` | Panel de medios — MediaOSD de Quickshell (carátula, controles, cava; cualquier reproductor MPRIS) |
| `SUPER + SHIFT + N` | Panel de notificaciones — Quickshell: toasts, historial persistente, No Molestar y sonido; clic en la campana también lo abre |
| `SUPER + ALT + W` | Fondo aleatorio — elige una imagen de `~/Imágenes/Wallpapers`; actualiza la imagen y el fondo de bloqueo/login, pero no recolorea el tema; `random-wallpaper.sh` |
| `SUPER + SHIFT + E` | Menú de energía alternativo — PowerMenu de Quickshell (apagar, reiniciar, suspender, cerrar sesión, hibernar) con estado propio; el icono ⏻ de Waybar y la esquina superior derecha (hot corner) abren este mismo menú; wlogout sigue en `SUPER + ºª` |
| `SUPER + SHIFT + Tab` | Bloquear la pantalla — hyprlock |
| `SUPER + Tab` | Alternar entre el escritorio actual y el anterior utilizado |
| `SUPER + ºª/\ (keycode 49)` | Menú de apagado/sesión — wlogout (bind por keycode; funciona con cualquier layout) |
| `SUPER + SHIFT + W` | Mostrar/ocultar waybar |
| Clic en la campana de Waybar | Abre el panel de notificaciones de Quickshell; clic derecho activa/desactiva No Molestar; clic central limpia el historial |
| Clic en el contador de tareas de Waybar | Abre el widget Todo; el indicador solo aparece si hay tareas pendientes (en rojo si algún recordatorio venció) |
| `SUPER + teclado numérico −` | Zoom del cursor −0.3 (repetible; bind por keycode, funciona en cualquier layout) |
| `SUPER + teclado numérico +` | Zoom del cursor +0.3 (repetible; bind por keycode, funciona en cualquier layout) |

## Notas y avisos

Estado tras la revisión de `keybinds.lua` con Hyprland 0.55.2 (config Lua):

1. **Binds por keycode y `hyprctl`**: los atajos por keycode (`code:49` de wlogout y `code:82/86` del zoom del numpad) funcionan con cualquier layout, pero `hyprctl binds -j` los muestra con el campo `key` vacío; en `hyprctl binds` (salida normal) aparecen como `SUPER + code:49`, etc.
2. **Notificación de capturas (quickshell)**: si el shell está arrancando, `qs ipc call screenshot notify` puede responder `Not ready to accept queries yet.`; el bind lo tolera (`|| true`) y la captura + copiado no se ven afectados.
3. **Grabadora**: `gpu-screen-recorder` no está empaquetado en Debian; se usa `wf-recorder` extraído manualmente en `~/.local/opt/wf-recorder` y el wrapper `~/.local/bin/screen-record.sh` (sin sudo, con las libs ffmpeg/pulse del sistema). Los vídeos van a `$(xdg-user-dir VIDEOS)/Grabaciones de la pantalla` (`~/Vídeos/Grabaciones de la pantalla/`), no a `~/Videos`; si la grabación no arranca o no genera fichero, la notificación lo indica y el log está en `/tmp/wf-recorder.log`.
4. **Teclas de brillo**: Fn+F4/Fn+F5 llegan por el dispositivo ACPI **Video Bus** (no por el teclado interno); antes de añadir los binds no había nada escuchándolas y no hacían nada. El brillo se ajusta con `brightnessctl` (`intel_backlight`, 5 % por pulsación) y también funciona con la pantalla bloqueada (`locked`).
5. **Utilidades instaladas**: `SUPER + P` (`hyprpicker` 0.4.7) y
   `SUPER + SHIFT + P` (`hyprsunset` 0.4.0) ya están instalados y funcionan
   (binarios en `/usr/bin/hyprpicker` y `/usr/bin/hyprsunset`).

# Energía, salud de la batería y rendimiento

Esta página cubre las herramientas de salud de la batería añadidas a
Quickshell, la instalación opcional de zram y la auditoría de rendimiento de
solo lectura. Todo es opcional: el escritorio funciona sin ello.

## Ajustes → Power

La página Power (segunda entrada de la barra lateral de ajustes) muestra:

- **Carga y autonomía** — porcentaje, estado de carga, voltaje, corriente,
  potencia y tiempo restante o hasta llenarse.
- **Salud de la batería** — `charge_full / charge_full_design`, desgaste,
  ciclos y capacidad resultante en Ah/Wh. Notas: `EXCELLENT` ≥ 90 %,
  `GOOD` ≥ 80 %, `FAIR` ≥ 70 %, `POOR` por debajo.
- **Historial de salud** — se guarda una muestra cada seis horas mientras la
  sesión está en marcha en `~/.local/state/43pr/battery-history.jsonl`
  (retención de tres años). La gráfica muestra los últimos 180 días.
- **Límite de carga** — 60 %, 80 % o 100 % en baterías que exponen
  `charge_control_end_threshold` (ASUS Battery Health Charging). 60–80 %
  reduce mucho el desgaste si el portátil suele estar enchufado; 100 % mantiene
  la autonomía máxima.
- **Gráfica de potencia** — los últimos tres minutos de potencia del paquete,
  muestreados cada tres segundos mientras la página está abierta.
- **Rendimiento** — Turbo Boost on/off, gobernador actual, preferencia de
  energía, perfil ACPI, estado de power-profiles-daemon, temperatura del
  paquete, ventilador (si el firmware lo expone), eventos de throttling desde
  el arranque y dispositivos swap/zram.

El perfil de CPU sigue en **Ajustes → System → CPU MODE**, junto a las gráficas
de CPU/GPU/RAM. CPU MODE escribe el `platform_profile` ACPI (límites de potencia
y política de ventilador del firmware); Linux mantiene el gobernador `powersave`
y EPP `balance_performance`, que sigue subiendo al turbo máximo cuando hace
falta. Turbo Boost es el interruptor de hardware independiente de arriba.

El límite de carga y la elección de Turbo se guardan en
`~/.config/quickshell/state/power.json`. `PowerAgent` (un componente pequeño de
Quickshell) los vuelve a aplicar al iniciar el shell y escribe las muestras de
salud cada seis horas aunque nunca se abra la página.

### Configuración privilegiada (una sola vez)

El límite de carga y el interruptor de Turbo escriben archivos de sysfs.
Instala una vez la regla sudoers estrecha:

```bash
sudo bash scripts/install-power-sudoers.sh
```

Permite exactamente tres escrituras mediante `sudo -n /usr/bin/tee`:
`platform_profile`, `intel_pstate/no_turbo` y
`BAT0/charge_control_end_threshold`. El kernel sigue validando los valores.
Vuelve a ejecutarlo si actualizas desde una versión que usaba
`install-cpu-profile-sudoers.sh`; la regla antigua se elimina sola.

El módulo de batería de Waybar abre la página al hacer clic.

## CLI de salud de la batería

Los mismos datos están disponibles en la terminal:

```bash
~/.config/quickshell/scripts/battery-health.py status   # JSON
~/.config/quickshell/scripts/battery-health.py history --days 30
~/.config/quickshell/scripts/battery-health.py record --force
~/.config/quickshell/scripts/battery-health.py report   # resumen en español
~/.config/quickshell/scripts/battery-health.py limit    # umbral actual
~/.config/quickshell/scripts/battery-health.py limit 80 # requiere la regla sudoers
```

`status` es la interfaz estable que usa la GUI; `report` añade una sección del
sistema (gobernador, perfil, Turbo, PPD, swap/zram) y sugerencias.

## Auditoría de rendimiento de solo lectura

```bash
./tools/power-audit.sh
```

Informa del desgaste y el límite de carga, gobernador/EPP/perfil de CPU, Turbo,
presión de memoria, swap/zram, tiempo de arranque y unidades más lentas,
throttling térmico y herramientas opcionales (`thermald`, `powertop`,
`irqbalance`, `tlp`, `tuned`). Imprime comandos concretos pero no cambia nada.
`tools/doctor.sh` incluye una versión compacta de las mismas comprobaciones.

## zram (swap comprimida en RAM)

Una instalación de escritorio de Debian puede no tener swap. Cuando la RAM se
llena, el kernel tiene que soltar cachés o activar el OOM killer, lo que se nota
como un congelamiento general. zram da a esa presión un respaldo rápido y
comprimido en RAM:

```bash
sudo bash scripts/install-zram.sh --dry-run   # ver el plan
sudo bash scripts/install-zram.sh             # instalar y arrancar
sudo bash scripts/install-zram.sh --remove    # deshacer
```

El script instala `systemd-zram-generator` si hace falta y escribe:

- `/etc/systemd/zram-generator.conf` — `min(ram / 2, 8192)` MiB, zstd,
  prioridad de swap 100.
- `/etc/sysctl.d/99-43pr-zram.conf` — `vm.swappiness=150`,
  `vm.page-cluster=0`, `vm.watermark_boost_factor=0`,
  `vm.watermark_scale_factor=125` (el ajuste habitual para zram; inofensivo sin
  zram).

zram no es compatible con la hibernación (no hay un dispositivo de swap
persistente). Si tienes `resume=` configurado, no uses este script. No sustituye
a una partición de swap para suspender a disco.

## Otras mejoras medibles

Son decisiones de sistema; el repositorio no las aplica:

- **`thermald`** (`sudo apt install thermald`) — en un i9 de 13.ª generación
  puede evitar throttling innecesario y mantener relojes sostenidos más
  estables. También puede pelearse con la política `platform_profile` del
  firmware en portátiles ASUS, así que mide antes/después y quédatelo solo si
  ayuda. Compruébalo con `systemctl status thermald`.
- **Espacio libre** — una raíz por encima del 90 % ralentiza la asignación de
  ext4 y puede romper actualizaciones. Compruébalo con `df -h /`; `apt clean`,
  `journalctl --vacuum-size=200M` y borrar kernels antiguos suelen recuperar
  varios GiB.
- **Tiempo de arranque** — `systemd-analyze blame` y
  `systemd-analyze critical-chain`. Desactiva los servicios que no uses, por
  ejemplo `sudo systemctl disable --now NetworkManager-wait-online.service`
  (solo si no necesitas el orden network-online al arrancar) y lo mismo con
  `vboxdrv`, `rabbitmq-server`, `docker`, `snapd`, `tor` u `ovs-vswitchd` si no
  forman parte de tu flujo de trabajo. No desactives servicios que no
  reconozcas.
- **systemd-oomd** (`sudo apt install systemd-oomd`) — mata el cgroup más
  pesado antes de que se congele todo el escritorio bajo presión de memoria.
  Complementa a zram; no sustituye a tener RAM suficiente.
- **TRIM** — `systemctl status fstrim.timer`; actívalo con
  `sudo systemctl enable --now fstrim.timer` si está inactivo.
- **Frecuencia de refresco** — el panel interno va a 90 Hz a 2880×1800, lo que
  es caro para la iGPU. A batería, un modo de 60 Hz ahorra energía:
  `~/.config/hypr/scripts/monitor-ctl.sh mode eDP-1 2880x1800@60` (comprueba
  antes el modo exacto con `hyprctl monitors`). `monitor-ctl.sh` persiste la
  elección en `monitors.lua`; vuelve a `@90` al enchufar, o pon una anulación
  manual en `monitors.local.lua`. El cambio automático AC/batería no está
  implementado.
- **Funciones de panel de i915** — este equipo arranca con
  `i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0` en
  `/etc/default/grub`, desactivando panel self-refresh, estados de energía del
  display y compresión de framebuffer. Valen aproximadamente 1–3 W en reposo,
  pero algunos paneles parpadean o se corrompen con ellas. Reactiva una cada
  vez, reinicia y prueba; mantén una entrada de rescate. Es un experimento, no
  un valor por defecto.
- **Ahorro de energía Wi-Fi** — NetworkManager suele activarlo; compruébalo con
  `iw dev wlo1 get power_save`. Si está desactivado, activarlo ahorra algo de
  energía en reposo (`nmcli connection modify <nombre> wifi.powersave 3`).
- **Efectos de Hyprland** — `look.lua` activa blur (tamaño 5, una pasada) y
  sombras. Bajar `blur.size`, reducir `passes` o desactivar `shadow` es un
  ahorro directo de GPU; es un compromiso estético, así que el repositorio deja
  los valores por defecto.
- **Un solo dueño de la energía** — no ejecutes a la vez
  `power-profiles-daemon`, TLP, `tuned` y escrituras manuales de
  `platform_profile`. En este equipo PPD está inactivo y **Ajustes → System →
  CPU MODE** es el dueño del perfil. Si activas PPD, úsalo como único dueño (o
  enmascáralo y quédate con el selector manual).
- **`powertop`** — para una segunda opinión sobre qué gasta la batería:
  `sudo powertop` (la pestaña `Tunables` lista sugerencias; revísalas una a
  una).

Nada de esto supera los límites físicos del portátil. La palanca más grande
para la batería es el límite de carga; la palanca más grande de respuesta en un
equipo sin swap es zram.

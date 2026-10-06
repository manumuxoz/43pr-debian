> Documento en español. Versión en inglés: [hyprlogin.md](hyprlogin.md).
>
> El binario de hyprlogin no se distribuye en este repo: compílalo con las instrucciones de hyprlogin.md.

# hyprlogin instalado — notas (Debian 13, trixie)

## Qué es
`hyprlogin` es un greeter para `greetd` forkeado de `hyprlock` (mismo aspecto
que la pantalla de bloqueo). Repo: https://github.com/AuthenticSm1les/hyprlogin
Versión compilada: 0.3.0, commit `b11d764` (15-sep-2026).

## Dónde está todo
- Binario:            /usr/bin/hyprlogin   (copia de seguridad local; no incluido en el repo)
- Config del greeter: /etc/hyprlogin/hyprlogin.conf
- Sesión Hyprland:    /etc/hyprlogin/hyprland-greeter.lua
- Colores (43pr):     /etc/hyprlogin/colors.conf         -> /var/lib/hyprlogin/colors.conf
- Fondo:              /usr/share/hyprlogin/wallpaper.jpg -> /var/lib/hyprlogin/wallpaper.jpg
- Datos del login:    /var/lib/hyprlogin  (root:TU_USUARIO 775; lo escribe theme.py)
- Config greetd:      /etc/greetd/config.toml  (VT 7, usuario `_greetd`)
- Fuente:             /usr/local/share/fonts/43pr/RobotoMono-*.ttf
- Utilidades:         /usr/local/bin/login-a-sddm | login-a-greetd | sincronizar-login

## Parche local aplicado (IMPORTANTE al actualizar)
Bug de la 0.3.0: si la autenticación termina antes de recibir el evento
`locked` del protocolo ext-session-lock, la orden de desbloqueo se perdía y
el greeter se quedaba colgado tras meter la contraseña (la sesión no
arrancaba nunca). Cambios:

1. `src/core/hyprlock.hpp`: nuevo miembro
   `bool m_bUnlockQueued = false;`
2. `src/core/hyprlock.cpp` → `CHyprlock::unlock()`:
   si `!m_bLocked`, en vez de solo avisar, hace `m_bUnlockQueued = true;`
3. `src/core/hyprlock.cpp` → `CHyprlock::onLockLocked()`:
   tras `m_bLocked = true;`, si `m_bUnlockQueued` → `m_bUnlockQueued = false; unlock();`

## Recompilar (si actualizas el proyecto)
```bash
sudo apt-get install -y cmake ninja-build libgles-dev libegl-dev libgl-dev libglx-dev \
  libgbm-dev libdrm-dev libpam0g-dev libcairo2-dev libpango1.0-dev libwayland-dev \
  wayland-protocols libxkbcommon-dev/trixie-backports hyprwayland-scanner \
  libhyprgraphics-dev libhyprlang-dev libhyprutils-dev libsdbus-c++-dev \
  libhyprcursor-dev libtomlplusplus-dev libmagic-dev libwebp-dev libjpeg-dev \
  libseat-dev libspdlog-dev
git clone https://github.com/AuthenticSm1les/hyprlogin
cd hyprlogin   # aplicar el parche de arriba
cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -S . -B ./build
cmake --build ./build --config Release --target hyprlogin -j$(nproc)
sudo install -m755 build/hyprlogin /usr/bin/hyprlogin
```

## Sincronización automática con el tema 43pr
`theme.py` copia el fondo y los colores actuales a `/var/lib/hyprlogin` en cada
cambio de tema (el selector de fondos SUPER+W lo lanza solo). El fondo se genera
estirado a la proporción de la pantalla (`swaybg -m stretch` en el escritorio),
para que el encuadre del login sea igual que el del escritorio. Los ficheros del
greeter son enlaces a ese directorio, así que la pantalla de login se actualiza
sola en el siguiente inicio de sesión.

- Activar (una sola vez):  `sudo bash scripts/greeter/activar-sync-login.sh (en este repo)`
- Respaldo manual:         `sudo sincronizar-login`

## Recordatorios de uso
- El login se sincroniza solo (ver arriba); respaldo manual: `sudo sincronizar-login`
- Volver a SDDM (rescate):              `sudo login-a-sddm`  (+ `sudo systemctl start sddm`)
- Volver a hyprlogin:                   `sudo login-a-greetd`

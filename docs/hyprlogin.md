# hyprlogin — greetd greeter for Debian 13

[hyprlogin](https://github.com/AuthenticSm1les/hyprlogin) is a work-in-progress
**greetd greeter forked from hyprlock**: the login screen looks like the lock
screen of the 43PR rice. It has no Debian package, so it is built from source.

- Upstream version built here: **0.3.0**, commit `b11d764` (2026-09-15)
- License: BSD-3-Clause (© 2024 Hypr Development)
- Spanish notes: [`hyprlogin.es.md`](hyprlogin.es.md)
- The binary is **not** distributed in this repository.

## Local patch: unlock race (`patches/hyprlogin-0.3.0-unlock-race.patch`)

**Bug (0.3.0):** if authentication finishes *before* the `locked` event of the
`ext-session-lock` protocol arrives, the unlock request is lost and the greeter
hangs after entering the password (the session never starts).

**Patch:** queue the unlock request until the lock is confirmed:

1. `src/core/hyprlock.hpp` — new member `bool m_bUnlockQueued = false;`
2. `src/core/hyprlock.cpp` → `CHyprlock::unlock()` — if not locked yet, log
   `"Unlock called, but not locked yet. Queuing unlock."`, set the flag and
   return instead of dropping the request.
3. `src/core/hyprlock.cpp` → `CHyprlock::onLockLocked()` — after
   `m_bLocked = true;`, run the queued unlock if the flag is set.

Validated against upstream `b11d764` with `git apply --check` (applies cleanly).

## Build on trixie

```bash
sudo apt-get install -y cmake ninja-build libgles-dev libegl-dev libgl-dev \
  libglx-dev libgbm-dev libdrm-dev libpam0g-dev libcairo2-dev \
  libpango1.0-dev libwayland-dev wayland-protocols \
  libxkbcommon-dev/trixie-backports hyprwayland-scanner \
  libhyprgraphics-dev libhyprlang-dev libhyprutils-dev libsdbus-c++-dev \
  libhyprcursor-dev libtomlplusplus-dev libmagic-dev libwebp-dev \
  libjpeg-dev libseat-dev libspdlog-dev

git clone https://github.com/AuthenticSm1les/hyprlogin
cd hyprlogin
git checkout b11d764
git apply /path/to/43pr-debian/patches/hyprlogin-0.3.0-unlock-race.patch
cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -S . -B ./build
cmake --build ./build --config Release --target hyprlogin -j"$(nproc)"
sudo install -m755 build/hyprlogin /usr/bin/hyprlogin
```

> Upstream is active: if you update it, re-check whether the patch is still
> needed and, if so, re-apply it (or send it upstream as a PR — it is welcome).

## System files (copies in `etc/`)

| Repository file | Installed to | Purpose |
|---|---|---|
| `etc/hyprlogin/hyprlogin.conf` | `/etc/hyprlogin/hyprlogin.conf` | greeter config (font, colors, sessions) |
| `etc/hyprlogin/hyprland-greeter.lua` | `/etc/hyprlogin/hyprland-greeter.lua` | minimal Hyprland session that runs `hyprlogin` |
| `etc/hyprlogin/start-greeter.sh` | `/etc/hyprlogin/start-greeter.sh` | greetd command: `HYPRLAND_CONFIG=… exec /usr/bin/start-hyprland` |
| `etc/greetd/config.toml` | `/etc/greetd/config.toml` | `vt = 7`, user `_greetd`, command `start-greeter.sh` |
| `etc/pam.d/greetd` | `/etc/pam.d/greetd` | password + fingerprint (see [`fingerprint.md`](fingerprint.md)) |
| `assets/fonts/` | `/usr/local/share/fonts/43pr/` or `~/.local/share/fonts/43pr/` | Roboto Mono for the greeter |

The template leaves `sessions:default_user` empty on purpose: the greeter then
asks for the username. If you want it prefilled, set it to your real user (the
output of `id -un`). Never leave a nonexistent placeholder there: the greeter
would try to authenticate that user and reject every password.

**VT note:** Debian's `getty@tty7` uses the same virtual terminal as greetd,
hence the explicit `vt = 7` and the warning in the config.

## Troubleshooting: the greeter rejects the correct password

Symptom: the greeter asks for a password and rejects the correct one, while the
same password works on a TTY (`Ctrl+Alt+F3`) and on the lock screen. greetd
logs show:

```
pam_unix(greetd:auth): check pass; user unknown
greetd[...]: error: authentication error: pam_authenticate: AUTH_ERR
```

Cause: `sessions:default_user` in `/etc/hyprlogin/hyprlogin.conf` points to a
user that does not exist, typically because the `TU_USUARIO` placeholder from
the template was copied literally. Since 0.3.0, hyprlogin starts the greetd
conversation as soon as the username is known, so it tries that user before you
can change it and then keeps retrying the same one. The lock screen and a TTY
are not affected because they authenticate the already logged-in user through
their own PAM services (`hyprlock` / `login`).

Fix: edit `/etc/hyprlogin/hyprlogin.conf` and either set `default_user` to your
real user or leave it empty (the greeter will ask for the username). Then:

```bash
sudo systemctl restart greetd
```

Verify that greetd no longer logs `user unknown`:

```bash
journalctl -b -u greetd --no-pager
```

## Theme synchronization (`/var/lib/hyprlogin`)

`theme.py` writes the current colors and wallpaper to `/var/lib/hyprlogin`
(owned `root:<your-user>`, mode 775). The greeter reads through symlinks:

```
/etc/hyprlogin/colors.conf            -> /var/lib/hyprlogin/colors.conf
/usr/share/hyprlogin/wallpaper.jpg    -> /var/lib/hyprlogin/wallpaper.jpg
```

The wallpaper is generated stretched to the focused monitor's aspect ratio
(`swaybg -m stretch` on the desktop) so the login screen framing matches.

- One-time setup: `sudo bash scripts/greeter/activar-sync-login.sh`
  (auto-detects your user).
- Manual sync: `sudo sincronizar-login [user]`.
- The script is idempotent and re-run-safe.

## Rescue

- Back to SDDM: `sudo login-a-sddm` (then `sudo systemctl start sddm`)
- Back to hyprlogin: `sudo login-a-greetd`

Both scripts live in `scripts/greeter/`.

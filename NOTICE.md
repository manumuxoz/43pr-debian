# Credits and third-party licenses

This repository is a **Debian 13 (trixie) adaptation** of the
[43PR dotfiles](https://github.com/43PR/dotfiles) rice. The MIT license in
[`LICENSE`](LICENSE) covers the adaptation itself (Debian-specific changes,
Waybar setup, IPC shim, documentation and patches).

## Upstream projects

- **[43PR dotfiles](https://github.com/43PR/dotfiles)** — MIT, © 2026 43PR
  (`LICENSES/43PR-MIT.txt`). Most files under `config/` are adapted from this
  project: Hyprland Lua config, Quickshell widgets, the `43pr` theme engine,
  dunst/kitty/rofi/wofi/wlogout setup.
- **[hyprlogin](https://github.com/AuthenticSm1les/hyprlogin)** — BSD-3-Clause,
  © 2024 Hypr Development (`LICENSES/hyprlogin-BSD-3-Clause.txt`).
  `patches/hyprlogin-0.3.0-unlock-race.patch` applies to it; no hyprlogin
  source code is redistributed here.
- **[libfprint-egismoc-sdcp](https://github.com/TenSeventy7/libfprint-egismoc-sdcp)** —
  LGPL-2.1 (`LICENSES/LGPL-2.1.txt`). Only a one-line build patch is included;
  no libfprint source code is redistributed here.
- **[Roboto Mono](https://fonts.google.com/specimen/Roboto+Mono)** — Apache-2.0
  (`LICENSES/Apache-2.0.txt`). Binaries under `assets/fonts/`.
- **[wlogout](https://github.com/ArtsyMacaw/wlogout)** — MIT. Layout and icons.

## Runtime dependencies

Hyprland, Quickshell, Waybar, greetd, kitty, dunst, rofi, wofi, grim, slurp,
cliphist, brightnessctl, playerctl, ImageMagick, matugen and the rest are
licensed by their respective projects and are **not** redistributed here.

## Assets

No personal images, avatars or wallpapers from the original setup are included.
The avatar in `config/quickshell/comitern.svg` is a neutral placeholder; the
wallpaper system expects your own images (see `README.md`).

Hyprland, hyprlogin, waybar and the other names are trademarks or projects of
their respective owners; this repository is not affiliated with or endorsed by
any of them.

# 43PR dotfiles for Debian 13 (trixie)

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Debian 13](https://img.shields.io/badge/Debian-13-A81D33?logo=debian&logoColor=white)](packages.txt)
[![Hyprland 0.55](https://img.shields.io/badge/Hyprland-0.55-58E1FF?logo=hyprland&logoColor=black)](#whats-inside)
[![Release](https://img.shields.io/badge/release-v1.0.0-blue.svg)](https://github.com/manumuxoz/43pr-debian/releases)

A Debian 13 adaptation of the [43PR dotfiles](https://github.com/43PR/dotfiles)
rice — *"Hyprland + Quickshell setup"* — running on **Hyprland 0.55 (Lua config
era)**, **Waybar 0.12** and **Quickshell 0.3**, with a **greetd/hyprlogin** login
screen and **fingerprint** unlock.

> **Upstream project:** [43PR dotfiles](https://github.com/43PR/dotfiles) —
> https://github.com/43PR/dotfiles — *"Hyprland + Quickshell setup"*, MIT, © 43PR.
> This is an independent Debian 13 adaptation: all credit for the original rice,
> theme engine, QML shell and keybind design goes to the 43PR authors; only the
> Debian port and the hardware/greeter adaptations are new.

Tested on: ASUS Zenbook UX3402VA · Debian 13.7 · Hyprland 0.55.2 · Quickshell
0.3.0 · Waybar 0.12.0 · greetd 0.10.3.

> This is a personal setup published as a reference for Debian users. It is not
> affiliated with the 43PR project. Some parts are hardware-specific and are
> documented in [`docs/hardware.md`](docs/hardware.md). Upstream 43PR targets
> Arch-based distributions; everything Debian-related lives in this repository.

## What's inside

| Component | Notes |
|---|---|
| Hyprland config | Lua files (`hyprland.lua`, `keybinds.lua`, `look.lua`, `monitors.lua`, `rules.lua`) |
| Bar | Waybar 0.12 + `waybar-ipc-shim.py` (bridges legacy IPC to Hyprland 0.55 Lua dispatchers) |
| Widgets | Quickshell: volume/brightness screenshot OSDs, settings window, wallpaper picker (`hyprquickpaper`) |
| Theme engine | `~/.config/43pr/bin/theme.py` — palettes, wallpapers, matugen (optional), greeter sync |
| Launchers / UI | wofi, rofi, wlogout, dunst, kitty |
| Login screen | **hyprlogin** (greetd greeter forked from hyprlock) + theme sync + fingerprint PAM |
| Patches | hyprlogin unlock-race fix, libfprint EGIS/`egismoc` build fix |

## Debian-specific pieces (why this repo exists)

- **Hyprland 0.55 + Lua config** from trixie-backports (`start-hyprland`).
- **`graphical-session.target` never activates** under `start-hyprland`, so
  hypridle/hyprsunset/portals are started manually — see
  [`docs/debian-adaptations.md`](docs/debian-adaptations.md).
- **Waybar 0.12 vs Lua dispatchers**: the official fix is not in any Waybar
  release yet, so this repo ships an IPC shim —
  [`docs/waybar-hyprland-lua-shim.md`](docs/waybar-hyprland-lua-shim.md).
- **hyprpaper 0.8.4 crashes on re-apply** → wallpaper handled by `swaybg` plus
  an `awww` shim.
- **hyprlogin** Debian build + unlock-race patch —
  [`docs/hyprlogin.md`](docs/hyprlogin.md) (also available
  [in Spanish](docs/hyprlogin.es.md)).
- **Fingerprint** (EgisTech `1c7a:0584`) with fprintd + PAM —
  [`docs/fingerprint.md`](docs/fingerprint.md).
- GNOME is left untouched: GTK global theming is intentionally disabled.

## Install

```bash
# 1. Add trixie-backports and install packages (see packages.txt for the
#    full list and versions):
sudo apt install -t trixie-backports \
  hyprland hyprland-guiutils hypridle hyprlock hyprpaper hyprpicker \
  hyprsunset xdg-desktop-portal-hyprland quickshell
sudo apt install \
  waybar dunst wofi rofi kitty wlogout grim slurp wl-clipboard cliphist \
  brightnessctl playerctl network-manager-gnome polkit-kde-agent-1 \
  swaybg jq imagemagick python3 greetd

# 2. Clone and install into your HOME (backs up existing configs):
git clone https://github.com/manumuxoz/43pr-debian.git
cd 43pr-debian
./install.sh
```

`install.sh` copies the configs to `~/.config/`, the helper scripts to
`~/.local/bin/`, installs Roboto Mono in `~/.local/share/fonts/43pr/`, and runs
`theme.py apply` to generate the files that are not committed (colors, etc.).
Previous configs are backed up to `~/.config-backups/43pr-debian-<date>/`.
Use `./install.sh --dry-run` to preview the changes, and `./uninstall.sh` to
restore the latest backup.

### After installing

1. Adapt `~/.config/hypr/monitors.lua` to your screens (or use
   `scripts/monitor-ctl.sh`). The repo ships the original layout:
   `eDP-1 2880x1800@90 scale 1.75` + `DP-3 1440x900`.
2. Check `~/.config/quickshell/hyprquickpaper/config.json` — the wallpaper
   folder defaults to `$HOME/Imágenes/Wallpapers` (Spanish locale).
3. Log out and start a Hyprland session (`start-hyprland` from a TTY works;
   greetd/hyprlogin is optional).
4. Optional: `/etc/hyprlogin` greeter (`docs/hyprlogin.md`) and fingerprint
   (`docs/fingerprint.md`).

### Keybinds

See [`config/hypr/SHORTCUTS.md`](config/hypr/SHORTCUTS.md). Highlights:
`SUPER+W` wallpaper picker, `SUPER+I` Quickshell settings, `SUPER+N` notepad,
`SUPER+R` screen recording, `SUPER+SHIFT+D` theme toggle, `SUPER+SHIFT+W`
toggle Waybar. Everything else is upstream 43PR (vim-style focus, scratchpad,
screenshots to `~/Imágenes/Capturas`, media keys…).

## Repository layout

```
config/      files that go to ~/.config/ (hypr, waybar, quickshell, 43pr, …)
local/bin/   helpers that go to ~/.local/bin/ (awww shim, screen-record.sh)
assets/      fonts (Roboto Mono)
etc/         system files for the greeter (greetd, hyprlogin, PAM)
patches/     hyprlogin unlock-race fix, libfprint egismoc build fix
scripts/     greeter utilities (theme sync, rescue, install)
docs/        Debian notes, shim + greeter + fingerprint + hardware docs
tools/       upstream-diff.sh (diff against 43PR), check-links.py (CI)
.github/     CI workflow + hardware-report issue template
packages.txt apt package reference
install.sh   user-level installer (supports --dry-run)
uninstall.sh restores the pre-install configuration
CHANGELOG.md release notes
```

Files generated at install time (`hyprlock-colors.conf`, `waybar/colors.css`,
`wlogout/colors.css`, `wofi/style.css`, `rofi/colors.rasi`,
`kitty/matugen.conf`) are **not** committed; `theme.py apply` recreates them.

## Credits and license

This repository is a **Debian 13 adaptation of the [43PR dotfiles](https://github.com/43PR/dotfiles)**
(https://github.com/43PR/dotfiles), MIT © 43PR — most files under `config/`
originate there and keep the upstream MIT license. See [`NOTICE.md`](NOTICE.md)
for the full attribution and [`LICENSES/`](LICENSES/) for the license texts.

The adaptation itself is MIT (see [`LICENSE`](LICENSE)). hyprlogin is
BSD-3-Clause (© 2024 Hypr Development); the Waybar IPC shim works around two
unmerged upstream Waybar PRs; the libfprint patch refers to an LGPL-2.1 project
(patch only — no upstream source is redistributed). No personal wallpapers or
images from the original setup are included.

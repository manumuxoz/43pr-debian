# Debian 13 (trixie) adaptations

The upstream [43PR dotfiles](https://github.com/43PR/dotfiles) target Arch-based
distributions. This document lists everything that had to change to make the
rice work on Debian 13 with Hyprland 0.55 from `trixie-backports`.

## 1. Packages come from trixie-backports

Hyprland, hyprlock, hypridle, hyprpaper, hyprsunset, hyprpicker,
hyprland-guiutils, xdg-desktop-portal-hyprland and Quickshell are only available
in `trixie-backports`. Install them with `apt install -t trixie-backports …`
(see `packages.txt`).

## 2. Hyprland 0.55 uses Lua configuration

The classic `hyprland.conf` was replaced by a Lua API (`hl.config`, `hl.bind`,
`hl.monitor`, `hl.on`, …). The session is started with the Debian entrypoint
`/usr/bin/start-hyprland`, which loads `~/.config/hypr/hyprland.lua` (and the
files it requires: `monitors.lua`, `keybinds.lua`, `look.lua`, `rules.lua`).

## 3. `graphical-session.target` never activates under `start-hyprland`

Because `start-hyprland` does not integrate with the systemd user session,
units bound to `graphical-session.target` (portals, idle daemons, etc.) are not
started. Workarounds used here:

- `dbus-update-activation-environment --systemd --all` at session start so the
  portals can find the Wayland environment.
- `hypridle`, `hyprsunset` and the rest are launched explicitly from
  `hyprland.lua` (`hl.on("hyprland.start", …)`).
- `hypridle` is not run as a systemd unit for the same reason.

## 4. polkit agent path

Debian installs the KDE polkit agent under a multiarch path, which differs from
what the rice expects:

```lua
hl.exec_cmd("/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1")
```

## 5. hyprpaper 0.8.4 crashes when re-applying a wallpaper

The backports build segfaults when a wallpaper is applied a second time, and the
rice normally uses `awww` (Arch-only). Instead:

- `scripts/wallpaper-restore.sh` sets the wallpaper with **swaybg** (`-m stretch`,
  matching the login screen framing).
- `~/.local/bin/awww` is a small shim kept for compatibility: scripts that call
  `awww` end up in the swaybg-based path.
- `hyprpaper.conf` is kept minimal; `theme.py` triggers the wallpaper update.

## 6. hyprsunset instead of gammastep

Upstream uses `gammastep` for the night light. Debian ships `hyprsunset`:
`scripts/nightlight-toggle.sh` toggles it, stores the state/kelvin between
sessions and restores it at login with `--restore`.

## 7. GTK theming is isolated from GNOME

GNOME is kept untouched on the same machine:

- `GTK_THEME=Adwaita:dark` is exported **only** inside the Hyprland session.
- The `gtk3`/`gtk4` targets in `~/.config/43pr/targets.toml` are disabled, so
  `theme.py` never rewrites the user's global GTK settings.

## 8. Fractional scaling 1.75 and XWayland

The panel runs at 1.75 scale. To avoid rounding and blurry X11 apps:

- `debug.disable_scale_checks` (Hyprland would otherwise force integer-ish
  scales in some cases).
- `xwayland.force_zero_scaling = true`.

## 9. wofi instead of rofi for menus

The rice uses rofi for the launcher; here **wofi** is used for the app launcher
and the workspace switcher (its cache/ordering is handled by
`scripts/workspace-switcher.sh`). Rofi is still installed and themed for other
dialogs.

## 10. Waybar 0.12 cannot talk to Hyprland 0.55 Lua dispatchers

Trixie ships Waybar 0.12, which sends legacy `dispatch` commands over the
Hyprland IPC socket; 0.55 expects Lua. The official Waybar fix is not in any
release yet, so this repo ships an IPC shim — full details in
[`waybar-hyprland-lua-shim.md`](waybar-hyprland-lua-shim.md).

## 11. greetd and VT 7

Debian's `getty@tty7` uses the same VT that greetd wants, so
`/etc/greetd/config.toml` sets `vt = 7` explicitly and the note is kept next to
it. See [`hyprlogin.md`](hyprlogin.md) for the full greeter setup.

## 12. hyprlogin build on trixie

`hyprlogin` (greetd greeter forked from hyprlock) has no Debian package. Build
dependencies and the local unlock-race patch are documented in
[`hyprlogin.md`](hyprlogin.md).

## 13. wf-recorder is not packaged in Debian

`SHORTCUTS.md` documents extracting the `wf-recorder` binary under
`~/.local/opt`; `local/bin/screen-record.sh` wraps it for the `SUPER+R` shortcut.

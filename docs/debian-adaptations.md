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

## 9. wofi as the only launcher (rofi dropped)

The upstream rice uses **rofi** for the launcher; here the launcher and the
workspace switcher are handled by **wofi** (its cache/ordering is managed by
`scripts/workspace-switcher.sh`). **rofi is not used at all** in this port, so
it is not part of the package list nor of the theme engine targets.

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

## 14. Camera: V4L2 + mpv/ffmpeg instead of libcamera

The webcam is a standard UVC device, so the PipeWire/libcamera stack is not
needed: `config/hypr/scripts/camera.sh` captures straight from `/dev/video0`
with `mpv` — already in the base install — for the `SUPER+C` preview. Photos
and recordings are driven from inside the window by `camera-mpv.lua`
(`s` / `r`). Because V4L2 admits a single reader, a recording is remuxed by
`mpv` to a FIFO and a background `ffmpeg` re-encodes it to H.264 MP4.

## 15. Upstream themes with Waybar and wlogout

Upstream dropped the Waybar (`wb_*`) and wlogout (`wl_*`) colour tokens from
its presets when it moved to a Quickshell-only shell. This port still renders
both, so `theme.py merged()` derives those keys from each theme's semantic
colours (panel, accent, danger…) instead of falling back to `default.toml`.
The 26 imported presets keep upstream's `override = false`: a wallpaper change
regenerates the palette. Set `override = true` in a theme TOML to pin it.

Presets are applied with `theme.py preset <id>` or from Settings → Themes.
btop 1.3.2 is compatible with the generated theme
(`color_theme = "43pr"` in `~/.config/btop/btop.conf`); cava's target stays
disabled because Debian 13 ships cava 0.10.4, which lacks `theme =` support.

## 16. Editors: xdg-open instead of xed

`xed` is not packaged in Debian, so the Quickshell config pages open files
with `xdg-open` (honours the user's default application).

## 17. Updating: copy model, not symlinks

Upstream's `install.sh`/`update.sh` use symlinks and `pacman`. This port keeps
copying files into `~/.config`, so a `git pull` does not update the live
configuration by itself: run `./update.sh` afterwards. It copies only
new/changed files, backs them up per file under
`~/.config-backups/update-<date>/` (never `43pr-debian-*`, so `uninstall.sh`
keeps working), regenerates the theme and never deletes files or installs
packages. `--dry-run`, `--diff`, `--skip-theme`, `--skip-packages`,
`--reload-hyprland`, `--reload-waybar` and `--restart-shell` control its
behaviour.

## 18. Pack 3: extra Quickshell widgets and Settings lifecycle

Upstream's full MediaOSD replaces the old volume OSD (playerctl + cava, cover
art, transport controls and its own settings panel; state lives in
`~/.config/quickshell/state/mediaosd-state.json`). Three more upstream widgets
were ported:

- **Todo** — task list with reminder parsing, on `SUPER+SHIFT+T`
  (`qs ipc call todo toggle`).
- **PowerMenu** — an alternative to wlogout (which stays on `SUPER+ºª`), on
  `SUPER+SHIFT+E` (`qs ipc call powermenu toggle`); the Waybar power icon opens
  the same menu; logout dispatches `hl.dsp.exit()`.
- **RecorderOSD** — REC indicator polling `screen-record.sh`'s
  `/tmp/osu-rec.pid` (every 2 s when idle, 1 s while recording).

Waybar gained two custom modules: the bell shows pending notifications (click
toggles Do Not Disturb through `dunstctl`, right-click closes the visible ones)
and the todo badge shows pending tasks (red when a reminder is overdue; click
opens Todo). The full media panel is also available on `SUPER+SHIFT+M`.

Their layer namespaces (`mediaosd`, `mediaosd-settings`, `todo`, `powermenu`,
`powermenu-settings`, `recorder-osd`) are added to `rules.lua` so they keep the
blur that used to come from the generic `quickshell` rule.

Settings keeps its always-mapped design, but the page `Loader` is only active
while the window is open (`mounted` + `keepAliveMs`, 20 s), so page timers
(`gpu-usage.py`, `/proc/net/dev`) stop once Settings is closed. The sidebar has
a search box (type to filter pages, `Ctrl+F` to focus, `Escape` clears/hides,
`Return` jumps to the first match).

Storage cleanup actions are Debian-native: APT CACHE (`apt-get clean`), APT
AUTOREMOVE (`apt-get autoremove --purge`), JOURNAL (`journalctl
--vacuum-time=7d`) and FLATPAK UNUSED, all through `pkexec`.

`install.sh`/`update.sh` create `~/.config/quickshell/state/` (gitignored); the
stateful widgets would silently lose their state otherwise.

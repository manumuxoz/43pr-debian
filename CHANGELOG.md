# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `SUPER+ALT+Tab` focuses the previously active window, mirroring the
  `SUPER+Tab` previous-workspace toggle. It uses Hyprland's
  `focuscurrentorlast` dispatcher, so pressing it again returns to the window
  you came from.
- Hyprland window borders now follow the active 43PR theme. `theme.py` renders
  `~/.config/hypr/colors.lua` from the palette (`accent` for active windows,
  `bg_hover` for inactive ones) and reloads Hyprland; `look.lua` keeps a neutral
  fallback when the generated file is missing.

### Changed

- `config/hypr/monitors.lua` is now user-owned: `update.sh` no longer
  overwrites the per-machine monitor layout. Manual overrides can live in
  `~/.config/hypr/monitors.local.lua`, which is loaded last.
- The `slurp` area-selection guide uses a neutral white fill and border over
  the dark veil instead of a red highlight.

### Fixed

- The external ASUS VW199 no longer stays powered on with a black screen. The
  repo preset forced `1920x1080@120`, a mode the EDID does not advertise;
  Hyprland accepted it and the panel could not display it. The default is now
  `1440x900@74.98`, with a wildcard `preferred` fallback for unknown outputs.
  `monitor-ctl.sh` validates every exact mode against `availableModes`,
  refuses to persist unsupported live modes, repairs them in `scale`/`primary`,
  and has a new `reconcile` command that runs on start and monitor hotplug. The
  Quickshell monitor page warns when the current mode is unsupported and offers
  a one-click "Preferred" reset.

- Notification sound and Do Not Disturb toggles now reach every running
  Quickshell instance. With a leftover session on another VT, the oldest
  instance keeps owning `org.freedesktop.Notifications` and kept its own
  in-memory state, so turning sound off in the active session had no effect.
  The state file is now watched and reloaded on change. `doctor.sh` also warns
  when more than one Quickshell is running.
- Waybar no longer stacks duplicate bars on the external monitor. Applying a
  theme used to send `SIGUSR2`; in Waybar 0.12 that reload re-registers the
  monitor callbacks, so every later DPMS cycle or monitor source change added
  another bar (upstream #3344 and #4336). The theme engine now performs a full
  restart through `hypr/scripts/waybar-restart.sh`.
- Area screenshots (`SUPER+SHIFT+Delete` and `SUPER+CTRL+Delete`) no longer
  include `slurp`'s selection overlay: the wrapper waits 200 ms after the
  selection so Hyprland repaints without it before running `grim`.
- The gap between the Waybar notification bell and the volume indicator now
  matches the spacing of the other right-side modules. The bell glyph leaves
  more side bearing inside its box than the speaker, so it looked tighter.

## [1.2.0] - 2026-10-23

### Added

- Quickshell notification panel replaces dunst as the session daemon: native
  `NotificationServer`, top-right toasts, persistent history
  (`~/.cache/43pr/notifications.json`, last 100 entries), Do Not Disturb, sound
  toggle and battery alerts. `SUPER+SHIFT+N` or the Waybar bell opens the panel;
  right-click toggles DND and middle-click clears the history.
- Quickshell widgets: MediaOSD with cover art, player controls and cava; Todo
  list with natural-language reminders; PowerMenu (also reachable from the
  top-right hot corner and the Waybar power icon); RecorderOSD for `wf-recorder`.
- Lazy page loading for the Settings window (the page is destroyed 20 seconds
  after closing) and sidebar search with `Ctrl+F`.
- Debian-native storage cleanup: APT cache and autoremove, journal, Flatpak,
  trash, clipboard history and thumbnails.
- Theme catalogue with 26 upstream presets plus a btop target. The theme engine
  derives the Waybar/wlogout tokens (`wb_*`/`wl_*`) and updates the appearance
  mode without touching the global GTK configuration.
- Copy-model `update.sh` with `--dry-run`, `--diff`, per-file backups, a package
  report and optional Hyprland, Waybar and Quickshell reloads.
- Read-only `tools/doctor.sh`.
- Screenshot annotation with swappy (`SUPER+CTRL+Delete`), area-selection
  feedback in the Quickshell OSD, and random wallpaper (`SUPER+ALT+W`) that also
  refreshes the lock and login backgrounds.
- Waybar notification/DND and Todo badges; MediaOSD shortcut
  (`SUPER+SHIFT+M`).

### Changed

- Waybar: the battery shows only its icon; right-side modules share consistent
  spacing; hover changes color only (no `font-size` changes); the MPRIS marquee
  updates every second and skips duplicate JSON.
- Lock is now `SUPER+SHIFT+Tab`; `SUPER+Tab` switches between the current and
  previous workspace.
- `SUPER+SHIFT+N` opens the notification panel instead of the old wofi history.
- `xed` was replaced by `xdg-open`.
- `update.sh --reload-waybar` now performs a full Waybar restart.
- MediaOSD now picks up every MPRIS player instead of a hardcoded list of music
  apps, so video players (Stremio, VLC, mpv, …) and any other media app show up
  too. The "Music players only" filter was removed.

### Removed

- Rofi configuration and theme targets, plus the unused autoclicker bind.
- Dunst is no longer started; it stays installed only as a fallback.
- The old wofi notification-history helper.

### Fixed

- The clock calendar tooltip no longer races with hover resizing (Waybar
  #4917).
- The top-right hot corner reliably opens the PowerMenu through the new
  `powermenu open` IPC (`show` collided with the `qs ipc show` subcommand).
- Screenshot selection gives immediate feedback, rejects stacked `slurp`
  overlays and uses a high-contrast overlay.
- Random wallpaper updates the lock/login background without recoloring the
  palette.
- The theme engine no longer warns when `pkill` finds no process, respects
  `XDG_STATE_HOME`, and fullscreen windows stay opaque when the opacity menu is
  used.

## [1.1.0] - 2026-10-15

### Added

- Webcam support (`config/hypr/scripts/camera.sh` + `camera-mpv.lua`):
  `SUPER+C` opens a floating `mpv` preview; with the window open, `s` takes a
  photo and `r` starts/stops a video. It captures straight from the UVC device
  over V4L2 with the already-installed `mpv`, and recordings are re-encoded by
  `ffmpeg` from a FIFO so the single-reader device is respected — no extra
  packages are needed.
- Screenshots in the READMEs (`docs/screenshots/`), including a desktop capture
  usable as the GitHub social preview.

### Fixed

- Lock screen and greeter wallpaper are framed like the desktop again: when
  ImageMagick is not installed, `theme.py` now stretches the lock wallpaper with
  Pillow (`python3-pil`) instead of falling back to the un-stretched original
  (which hyprlock cropped).
- `hyprquickpaper` previews wallpapers again: the thumbnail cache falls back to
  Pillow (new `thumbnail.py`) when `magick`/`convert` are missing, so the SUPER+W
  carousel no longer shows "Caching" forever.

## [1.0.0] - 2026-10-06

First public release: Debian 13 (trixie) adaptation of the
[43PR dotfiles](https://github.com/43PR/dotfiles).

### Added

- Hyprland 0.55 Lua configuration adapted from 43PR (`config/hypr/`).
- Waybar 0.12 setup (`config/waybar/`) plus `waybar-ipc-shim.py`, a bridge
  between the legacy Waybar dispatchers and the Hyprland 0.55 Lua dispatchers
  (`hl.dsp.*`), since the official fix is not in any Waybar release yet.
- Quickshell 0.3 widgets (volume/brightness/screenshot OSDs, settings window,
  `hyprquickpaper` wallpaper picker) and the `theme.py` theme engine with
  greeter theme sync.
- greetd/hyprlogin login stack (`etc/`, `scripts/greeter/`) with fingerprint
  PAM integration and a rescue path back to SDDM.
- Patches: hyprlogin unlock-race fix (`patches/hyprlogin-0.3.0-unlock-race.patch`),
  libfprint EGIS/`egismoc` build fix.
- Debian notes, Waybar shim, greeter, fingerprint and hardware docs (`docs/`).
- `install.sh` user-level installer with backup, `--dry-run` and `--help`.
- `uninstall.sh` to restore the pre-install configuration.
- `tools/upstream-diff.sh` (diff against the upstream 43PR repo) and
  `tools/check-links.py` (CI link checker).
- CI workflow (ShellCheck, Python syntax, personal-data guard, link check) and
  a hardware-report issue template.

### Known issues

- `hyprpaper` 0.8.4 (trixie-backports) crashes when re-applying the wallpaper;
  this setup uses `swaybg` instead (`docs/debian-adaptations.md`).
- The Waybar Lua-dispatch fix (upstream PRs #5013, #5231) is not in any released
  Waybar version yet, hence the IPC shim.

[1.2.0]: https://github.com/manumuxoz/43pr-debian/releases/tag/v1.2.0
[1.1.0]: https://github.com/manumuxoz/43pr-debian/releases/tag/v1.1.0
[1.0.0]: https://github.com/manumuxoz/43pr-debian/releases/tag/v1.0.0

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `SUPER+ALT+1…0` sends every window on the current workspace to workspace
  1–10, and `SUPER+ALT+S` sends them to the scratchpad (`special:scratch`).
  Windows are moved by object through `hl.dsp.window.move`, so background
  windows and windows on other monitors move too, and focus follows to the
  destination workspace (the scratchpad is shown for `S`). If the destination
  has no tiled windows, the source split tree and its ratios are reproduced;
  if it already has windows, every tiled window is redistributed into a
  balanced split tree with equal areas, avoiding one oversized window. The
  layout logic lives in `config/hypr/move-all.lua`. Spotatui moves to
  `SUPER+ALT+SHIFT+S` to free `SUPER+ALT+S`.
- Per-window opacity: the `SUPER+O` menu now offers presets for the **focused
  window** (the default scope) as well as the existing "all windows" setting.
  The first menu entry switches the scope; the presets below apply to it. With
  no active window the menu applies the global scope directly. The per-window
  choice is applied live through `hl.dsp.window.set_prop` (Hyprland 0.55 no
  longer accepts `hyprctl setprop` as a direct request), sets both `opacity` and
  `opacity_inactive` so the window stays translucent when unfocused, and leaves
  the config untouched. The global value is stored in
  `~/.local/state/hypr/opacity.lua`, which `rules.lua` reads at load time, so
  installs and updates no longer reset it; choosing "all windows" also updates
  windows that already had their own opacity. `SUPER+SHIFT+O` cycles the focused
  window through 100 → 90 → … → 40 → 100 %, and the `opacity.sh` commands
  (`window`, `window-step`, `window-cycle`, `reset`, `global`, `status`) work
  from a terminal. Fullscreen windows remain opaque, matching the existing
  global behaviour.
- Animated Debian ASCII header for fastfetch/kitty (`scripts/debian-ascii/`):
  fixed 22×13 logo, live scanline, fixed system info beside it; it pauses when
  a command runs and scrolls away with the output. The 30×18 and 44×26 arts are
  available with `--art`.
- Settings → System now has a **CPU MODE** selector (Power Saver / Balanced /
  Performance) that writes the ACPI `platform_profile` directly, bypassing
  `power-profiles-daemon`. Available modes are read from the kernel, the
  active one is highlighted, and the CPU badge above the graph refreshes after
  each change. Switching modes is passwordless once the narrow rule from
  `scripts/install-power-sudoers.sh` is installed (one-time `sudo`/`pkexec`).
  The chosen mode is saved in `~/.config/quickshell/state/cpu-profile.json` and
  re-applied when the shell starts, so it survives reboots.
- Settings → **Power** page: live charge/runtime, pack power graph, battery
  health (`charge_full / charge_full_design`), wear, cycle count, capacity in
  Ah/Wh, a 180-day health history, charge-limit presets (60/80/100 %) for
  batteries that expose `charge_control_end_threshold`, a Turbo Boost toggle
  (`intel_pstate/no_turbo`), package temperature, fan and package-throttle
  counters, and the active swap/zram devices. The battery CLI
  (`config/quickshell/scripts/battery-health.py`) also supports
  `status`, `history`, `record`, `report` and `limit`. `PowerAgent` records a
  health sample every six hours to
  `~/.local/state/43pr/battery-history.jsonl` (three-year retention) and
  re-applies the charge limit and Turbo choice saved in
  `~/.config/quickshell/state/power.json` at shell start.
- `scripts/install-power-sudoers.sh` replaces
  `install-cpu-profile-sudoers.sh` and extends the narrow NOPASSWD rule to the
  Turbo and charge-limit sysfs files; the old rule is removed on upgrade.
- `scripts/install-zram.sh`: optional compressed RAM swap
  (`systemd-zram-generator`, `min(ram / 2, 8192)` MiB, zstd) plus the usual
  zram sysctls, with `--dry-run` and `--remove`. Useful on machines without a
  swap partition; it is not compatible with hibernation.
- `tools/power-audit.sh`: read-only battery, CPU, memory, boot, thermal and
  tooling report with concrete suggestions. `tools/doctor.sh` gained a compact
  "Energía y rendimiento" section.
- `docs/power.md` and `docs/power.es.md` document the Power page, the battery
  CLI, zram, thermald, systemd-oomd, boot-time cleanup, the 60 Hz battery mode
  and the one-power-owner rule. Waybar's battery module opens the Power page on
  click and uses the accent colour while charging.
- `SUPER+ALT+Tab` focuses the previously active window, mirroring the
  `SUPER+Tab` previous-workspace toggle. It uses Hyprland's
  `focuscurrentorlast` dispatcher, so pressing it again returns to the window
  you came from.
- `theme.py` renders `~/.config/hypr/colors.lua` from the active palette
  (`accent` at 50% for the active window and 25% for inactive ones) and reloads
  Hyprland; `look.lua` keeps a neutral fallback when the generated file is
  missing.
- Thunar is the default file manager (`SUPER+E`). The repo now deploys
  `config/Thunar/uca.xml` with "Abrir terminal aquí" and "Abrir Ranger aquí"
  actions; both call `kitty` directly. `install.sh`/`uninstall.sh` include the
  new `Thunar` config directory and `update.sh` picks it up automatically.
- Ranger is an optional TUI companion (`SUPER+ALT+E`). `config/ranger/`
  contains the reviewed `rc.conf`, `rifle.conf` and `scope.sh`, with kitty
  image/PDF/video previews, a 25 MiB preview limit, `gio trash` integration
  and `gN`/`gF` mappings that open Thunar.
- `file-roller` (plus `7zip` and `unzip`) is now listed explicitly as the
  archive backend for `thunar-archive-plugin`, so a fresh install offers
  "Comprimir...", "Extract Here" and "Extract To..." in Thunar's context menu.
  Ark and the KDE dependency stack are no longer needed.

### Changed

- The Waybar battery tooltip is now in English and shows only the state, the
  health and the power draw. The `{timeTo}` line (which printed `Plugged` when
  connected) and the `Click: salud de la batería` hint are gone, and the
  plugged state uses `Plugged: N%` with a colon instead of the middle dot.
- Settings → System no longer duplicates the battery and battery-health rows
  at the bottom; battery status, health and the charge limit live only in
  Settings → Power. The CPU/GPU/RAM/load/net graphs and the SENSORS row are
  unchanged.
- Area screenshot now uses the laptop's dedicated capture key (`Fn+F11`,
  `KEY_SELECTIVE_SCREENSHOT` → `XF86SelectiveScreenshot`) instead of
  `SUPER+SHIFT+Delete`. The bind ignores held modifiers (`ignore_mods`) so it
  also works if Super/Shift are still pressed. The key's firmware also emits a
  `Super+Shift+S` macro; that synthetic press is ignored so it no longer moves
  the window to the scratchpad, while a real `SUPER+SHIFT+S` still works. The
  annotate variant stays on `SUPER+CTRL+Delete`.
- Hyprland window borders are disabled (`border_size = 0`): windows are
  separated only by gaps, with rounding and shadows still marking their edges.
  The generated border colours stay available for anyone re-enabling borders in
  `look.lua`.
- `config/hypr/monitors.lua` is now user-owned: `update.sh` no longer
  overwrites the per-machine monitor layout. Manual overrides can live in
  `~/.config/hypr/monitors.local.lua`, which is loaded last.
- The `slurp` area-selection guide uses a neutral white fill and border over
  the dark veil instead of a red highlight.

### Fixed

- Clicking a workspace icon in Waybar now keeps working after a manual
  `waybar` restart. A plain `/usr/bin/waybar` launched inside the session
  bypassed `waybar-start.sh`, so Waybar sent the legacy `dispatch workspace N`
  command straight to Hyprland 0.55 and the click did nothing. The new
  `~/.local/bin/waybar` launcher forwards manual invocations to
  `waybar-start.sh` while a Hyprland Lua session is active; use
  `WAYBAR_NO_SHIM=1 waybar` to start the plain binary for debugging.
- The hypridle suspend-on-battery listener now treats USB-C chargers as AC
  power. It checked only `ADP1`, so a charger connected through a USB-C port
  (`ucsi-source-psy-*`, `type=USB`, `online=1`) still let the 15-minute
  timeout suspend the laptop.
- hyprlock's fingerprint `retry_delay` is now 750 ms. The EgisTech sensor is a
  "press" reader, and the previous 250 ms restarted verification before the
  finger was lifted after a `verify-no-match`. The fingerprint block and the
  known hyprlock 0.9.6 teardown issues are documented in
  `docs/fingerprint.md`.
- Portal dialogs (the file chooser used by WhatsApp and other apps) no longer
  open on workspace 1 the first time. `hyprland.lua` was propagating Hyprland's
  per-process `HL_INITIAL_WORKSPACE_TOKEN`/`HL_EXEC_RULE_TOKEN` into the systemd
  user environment with `dbus-update-activation-environment --all`, so
  D-Bus-activated services such as `xdg-desktop-portal-gtk` inherited the
  workspace of the login session. The session now disables
  `misc:initial_workspace_tracking`, unsets the tokens before propagating the
  environment, and `rules.lua` forces `xdg-desktop-portal-*` dialogs to the
  active workspace. The second dialog already worked because the initial
  workspace token is single-use.
- The animated Debian header now only renders when the complete fastfetch
  information fits beside the logo. In smaller terminal windows it shows
  nothing instead of clipping the info or printing a reduced variant. Resizing
  below the required size clears the header and stops the animation.
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

### Removed

- The wlogout power menu and its `SUPER+ºª` bind were removed. The Quickshell
  PowerMenu (`SUPER+SHIFT+E`, the Waybar power icon and the top-right hot
  corner) remains as the single power/lock menu. This also drops the
  `wlogout` package dependency, its GTK stylesheet and icon set, the
  `wlogout/colors.css` theme target and the related Settings → Configs page.

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

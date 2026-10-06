# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Screenshots in the READMEs (`docs/screenshots/`), including a desktop capture
  usable as the GitHub social preview.

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

[1.0.0]: https://github.com/manumuxoz/43pr-debian/releases/tag/v1.0.0

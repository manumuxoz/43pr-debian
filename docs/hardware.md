# Hardware notes — ASUS Zenbook UX3402VA

The setup was developed and tested on this laptop. These are the parts that are
hardware-specific; if your machine differs, this is what to edit.

## Displays

- Internal panel: `eDP-1`, 2880x1800 @ 90 Hz, **scale 1.75**.
- External monitor used: `DP-3`, 1440x900 @ 74.98 Hz, scale 1.0.
- Managed block in `~/.config/hypr/monitors.lua`; edit it directly or use
  `~/.config/hypr/scripts/monitor-ctl.sh` (mode/scale/primary; it persists the
  changes back into `monitors.lua`).
- Fractional scale 1.75 requires `debug.disable_scale_checks` and
  `xwayland.force_zero_scaling` (see `docs/debian-adaptations.md`).

## Touchpad

The touchpad device is matched by name in `hyprland.lua`:

```
asue140d:00-04f3:31b9-touchpad
```

Check your device name with `hyprctl devices` and update the block if needed.
The three-finger workspace swipe gesture is also configured there.

## Audio (ALC294 + SOF UCM)

- Codec: Realtek **ALC294** with the SOF UCM `sof-hda-dsp` profile set.
- Speakers and Headphones are **mutually exclusive UCM profiles** on this
  machine, so plugging headphones does not silence the speakers by itself.
  `~/.config/hypr/scripts/audio-jack-switch.py` polls the ALSA jack state
  (libasound via ctypes) and switches the profile both ways.
- HDMI/DisplayPort output states are collected by
  `~/.config/hypr/scripts/audio-hdmi-ports.sh`, used by the Quickshell
  `SoundPage`.
- If your codec/UCM differs, these two scripts are the ones to adapt or remove.

## Battery / power

- Waybar shows `BAT0` and `ADP1` (fixed in `~/.config/waybar/config.jsonc`).
- `suspend-if-on-battery.sh` (hypridle timeout) only suspends on battery.

## Fingerprint

- EgisTech `1c7a:0584` — see [`fingerprint.md`](fingerprint.md) for the
  libfprint fork, the build patch and PAM.

## Other

- The wallpaper folder defaults to `~/Imágenes/Wallpapers` (Spanish locale) in
  `~/.config/quickshell/hyprquickpaper/config.json`.
- `SUPER+R` screen recording expects `wf-recorder` under `~/.local/opt`
  (not packaged in Debian; see `SHORTCUTS.md`).

# Hardware notes — ASUS Zenbook UX3402VA

The setup was developed and tested on this laptop. These are the parts that are
hardware-specific; if your machine differs, this is what to edit.

## Displays

- Internal panel: `eDP-1`, 2880x1800 @ 90 Hz, **scale 1.75**.
- External monitor used: ASUS VW199, 1440x900. It appears as `HDMI-A-1` when
  connected through the laptop HDMI port or as `DP-3` through USB-C. The repo
  preset uses `HDMI-A-1` at 1440x900 @ 74.98 Hz, scale 1.0.
- Safe modes for this panel: `1440x900@74.98`, `1440x900@59.89` (EDID
  preferred) and `1920x1080@60.00`. **Never force `1920x1080@120`**: the EDID
  does not advertise it, Hyprland may accept it anyway and the panel stays
  powered on with a black screen.
- The managed block lives in `~/.config/hypr/monitors.lua`. Use
  `~/.config/hypr/scripts/monitor-ctl.sh` (`mode`, `scale`, `primary`,
  `reconcile`) instead of editing it by hand: exact modes are validated against
  `availableModes` before they are applied or persisted. `reconcile` also
  adopts new outputs and repairs unsupported modes after a port change or
  hotplug.
- If the external panel is black after an update or a manual experiment, run
  `monitor-ctl.sh mode HDMI-A-1 1440x900@74.98` (or `mode HDMI-A-1 preferred`).
- `monitors.lua` is user-owned: `update.sh` does not overwrite it. For a
  manual override that survives `monitor-ctl.sh` rewrites, create
  `~/.config/hypr/monitors.local.lua`; it is loaded last.
- Any output without an explicit rule uses its EDID preferred mode through the
  wildcard `output = ""` fallback in `monitors.lua`.
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

## Camera (webcam)

- Sonix **USB2.0 FHD UVC WebCam** (`3277:0010`), a standard UVC device: it works
  through V4L2 with no `libcamera` or extra drivers. It exposes `/dev/video0`
  (capture, MJPEG/YUYV up to 1920x1080) and `/dev/video1` (metadata).
- `~/.config/hypr/scripts/camera.sh` opens the floating `mpv` preview
  (`SUPER+C`); with the window open, `s` takes a photo (mpv screenshot) and `r`
  starts/stops a recording (see `camera-mpv.lua`). A recording is remuxed by
  `mpv` to a FIFO and a background `ffmpeg` re-encodes it to H.264 MP4, so the
  single-reader webcam is respected. No extra packages.
- It picks the first `/dev/videoN` that ffmpeg lists capture formats for; force
  another one with `CAMERA_DEVICE=/dev/videoN`.

## Other

- The wallpaper folder defaults to `~/Imágenes/Wallpapers` (Spanish locale) in
  `~/.config/quickshell/hyprquickpaper/config.json`.
- `SUPER+R` screen recording expects `wf-recorder` under `~/.local/opt`
  (not packaged in Debian; see `SHORTCUTS.md`).

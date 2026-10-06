# Screenshots

Captures of this setup, linked from the main READMEs:

- `waybar.jpg` — desktop with the Waybar bar (also usable as the GitHub social preview)
- `wofi.jpg` — wofi launcher
- `quickshell.jpg` — Quickshell settings window (`SUPER+I`)
- `wallpapers.jpg` — `SUPER+W` wallpaper picker (hyprquickpaper)
- `notas.jpg` — notepad window (`SUPER+N`)
- `escritorios.jpg` — workspace switcher
- `fastfetch-kitty.jpg` — fastfetch in kitty

How to capture on Hyprland (grim is enough):

```bash
# whole primary monitor
grim -o eDP-1 desktop.png
# or an interactive region
grim -g "$(slurp)" shot.png
# a video (wf-recorder, see config/hypr/SHORTCUTS.md)
wf-recorder -f demo.mp4
```

Compress and convert with ImageMagick, then add the images to `README.md` and
`README.es.md` in a `## Screenshots` section (and use one as the GitHub social
preview in Settings → General → Social preview):

```bash
magick desktop.png -resize 1920x -strip -quality 82 desktop.jpg
```

Close anything private before capturing.

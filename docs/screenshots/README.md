# Screenshots

The main READMEs link captures of this setup once they are added here.

Suggested captures (each under ~500 KB):

- `desktop.jpg` — clean desktop: wallpaper, Waybar, a couple of windows
- `launcher.jpg` — `SUPER+W` wallpaper picker (hyprquickpaper)
- `settings.jpg` — Quickshell settings (`SUPER+I`)
- `lock.jpg` — hyprlock / hyprlogin lock screen

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

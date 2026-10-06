# Waybar ↔ Hyprland Lua dispatchers (IPC shim)

## The problem

- Debian 13 ships **Waybar 0.12.0**.
- Hyprland 0.55 replaced the hyprlang config with a **Lua API** and expects
  dispatchers such as `hl.dsp.focus{ workspace = "2" }` instead of the legacy
  strings.
- Old Waybar sends legacy commands over the Hyprland IPC socket:
  `dispatch workspace N`, `dispatch focusworkspaceoncurrentmonitor N`,
  `dispatch togglespecialworkspace …`. On Hyprland 0.55 those fail (or only
  partially work), so clicking workspaces in the bar does nothing.

The fix exists upstream (Waybar PRs **#5013** and **#5231**) but it is **not
included in any released version** as of October 2026, including 0.15.0.
So on trixie the bridge is done here.

## The solution: `hyprland/scripts/waybar-ipc-shim.py`

The shim is a small fake Hyprland instance:

1. It creates `$XDG_RUNTIME_DIR/hypr/waybar-lua-shim/` with the two Hyprland
   sockets (`.socket.sock` and `.socket2.sock`).
2. `waybar-start.sh` launches Waybar with
   `HYPRLAND_INSTANCE_SIGNATURE=waybar-lua-shim`, so Waybar believes it is
   talking to Hyprland.
3. Requests are received on the fake socket:
   - Legacy dispatches (`dispatch workspace 2`,
     `dispatch focusworkspaceoncurrentmonitor 2`,
     `dispatch togglespecialworkspace …`) are **translated** to the Lua
     equivalents executed with `hyprctl eval`:
     `hl.dsp.focus{ workspace = "2" }`,
     `hl.dsp.focus{ workspace = "2", on_current_monitor = true }`,
     `hl.dsp.workspace.toggle_special(...)`.
   - Anything else (`j/…` queries, raw messages) is passed through to the real
     Hyprland instance.
4. Events from the real `.socket2.sock` are forwarded to Waybar, so the
   workspace list updates live.

`waybar-start.sh` is the wrapper used by `hyprland.lua`; it starts the shim in
the background and prints a warning (without killing the session) if the shim
fails to start.

## Usage

- Waybar starts automatically with the session (`SUPER+SHIFT+W` toggles it).
- Test the translation manually:

  ```bash
  python3 ~/.config/hypr/scripts/waybar-ipc-shim.py --translate "workspace 2"
  ```

- Log file: `$XDG_RUNTIME_DIR/waybar-ipc-shim.log`
- Debug: run `waybar-start.sh` from a terminal and watch the log.

## When to remove the shim

When a Waybar release with the Lua-dispatch support reaches Debian, remove the
wrapper from `hyprland.lua` and launch `waybar` directly (the config itself
needs no changes). The shim is self-contained, so deleting it is safe.

## Notes

- `hyprctl instances` will list `waybar-lua-shim` as an extra instance; that is
  expected.
- The shim only translates the three dispatch families Waybar needs; it is not a
  general-purpose Hyprland proxy.

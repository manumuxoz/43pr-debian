-- ~/.config/hypr/keybinds.lua
-- Migrated from keybinds.conf
-- Docs: https://wiki.hypr.land/Configuring/Basics/Binds/
--       https://wiki.hypr.land/Configuring/Basics/Dispatchers/

local home = os.getenv("HOME")
local menu = "wofi --show drun"

-- Launchers
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("pgrep -x wofi >/dev/null && pkill -x wofi || " .. menu))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("hyprlock")) -- Lock screen

hl.bind(mainMod .. " + code:49", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/wlogout.sh")) -- Power menu (code:49 = tecla GRAVE/ºª con layout es)

hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("qs ipc call settings toggle")) -- Settings

hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(home .. "/.config/quickshell/hyprquickpaper/launch.sh")) -- Wallpapers (toggle)

hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notepad toggle")) -- Bloc de notas (widget Quickshell)

hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 0 })) -- Fullscreen

hl.bind(mainMod .. " + O", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/opacity.sh")) -- Opacity

hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("pgrep -x wofi >/dev/null && pkill -x wofi || " .. home .. "/.config/hypr/scripts/workspace-switcher.sh")) -- Conmutador de escritorios (wofi; toggle)

hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("python3 " .. home .. "/.config/43pr/bin/theme.py toggle")) -- Light/dark toggle

-- Mouse move/resize window
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Toggle waybar
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("sh -c 'pgrep -x waybar >/dev/null && pkill -x waybar || nohup \"$HOME/.config/hypr/scripts/waybar-start.sh\" >/dev/null 2>&1 &'"))

-- Clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("pgrep -x wofi >/dev/null && pkill -x wofi || cliphist list | wofi --dmenu --prompt '' | cliphist decode | wl-copy"))

-- Screenshot fullscreen (SUPER+Supr; guarda en Imágenes/Capturas de pantalla)
hl.bind(mainMod .. " + Delete", hl.dsp.exec_cmd("sh -c 'dir=\"" .. home .. "/Imágenes/Capturas de pantalla\"; mkdir -p \"$dir\"; file=\"$dir/$(date +%Y-%m-%d_%H-%M-%S).png\"; if grim \"$file\"; then wl-copy < \"$file\"; qs ipc call screenshot notify \"$file\" || true; fi'"))
-- Screenshot area select (SUPER+SHIFT+Supr)
hl.bind(mainMod .. " + SHIFT + Delete", hl.dsp.exec_cmd("sh -c 'dir=\"" .. home .. "/Imágenes/Capturas de pantalla\"; mkdir -p \"$dir\"; file=\"$dir/$(date +%Y-%m-%d_%H-%M-%S).png\"; if grim -g \"$(slurp)\" \"$file\"; then wl-copy < \"$file\"; qs ipc call screenshot notify \"$file\" || true; fi'"))

-- Keyboard layout
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))

-- Toggle float window, center and rezise
hl.bind(mainMod .. " + Space", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))

    local w = hl.get_active_window()
    if w ~= nil and w.floating then
        local mon = hl.get_active_monitor()
        if mon ~= nil then
            -- mon.width/height son px fisicos; las ventanas usan px logicos (layout)
            local mon_w = mon.width / (mon.scale or 1)
            local mon_h = mon.height / (mon.scale or 1)
            local target_w = math.floor(mon_w * 0.7)
            local target_h = math.floor(mon_h * 0.7)

            -- absolute resize (relative = false), not a delta
            hl.dispatch(hl.dsp.window.resize({ x = target_w, y = target_h, relative = false }))

            local mon_x = mon.x or 0
            local mon_y = mon.y or 0
            local target_x = mon_x + math.floor((mon_w - target_w) / 2)
            local target_y = mon_y + math.floor((mon_h - target_h) / 2)

            -- absolute move to the centered position
            hl.dispatch(hl.dsp.window.move({ x = target_x, y = target_y, relative = false }))
        end
    end
end)

-- Screen recorder (wf-recorder en ~/.local/opt; wrapper con pidfile /tmp/osu-rec.pid)
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(home .. "/.local/bin/screen-record.sh"))

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 1.5 then
        hl.config({ cursor = { zoom_factor = 1.5 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind(mainMod .. " + mouse_down", function() zoomfunction(-0.5) end, { repeating = true })
hl.bind(mainMod .. " + mouse_up", function() zoomfunction(0.5) end, { repeating = true })

--# Zoom with keypad
hl.bind(mainMod .. " + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + code:86", function() zoomfunction(0.3) end, { repeating = true })

-- Focus (H/J/K/L = left/down/up/right, vim-style, matching your original)
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))

-- Move active window within layout (old `movewindow` dispatcher).
-- Verified against Hyprland 0.55.2: hl.dsp.window.move({ direction = ... }) is valid.
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

-- Resize active window by pixel delta (old `resizeactive`, repeating while held
-- via `binde`). Verified against Hyprland 0.55.2: window.resize({ x, y, relative })
-- is valid; relative = true is required (default absolute mode rejects |size| < 1).
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + J", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })

-- Workspaces 1-10, and move-to-workspace with SHIFT (confirmed pattern from
-- the official example config)
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad (workspace especial "scratch")
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }))

-- Color picker y luz nocturna
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nightlight-toggle.sh"))

-- Media keys (confirmed pattern from the official example config)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Brillo de pantalla (Fn+F4 / Fn+F5, emitidos por el dispositivo ACPI "Video Bus")
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --class=backlight set 5%-"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl --class=backlight set 5%+"), { locked = true, repeating = true })

-- Teclado Logitech (K235 via receptor Nano, PID 4023): su fila Fn no coincide
-- en posicion con la del portatil (ASUS UX3402VA). Aliases posicionales para
-- que Fn+F1..F5 hagan lo mismo en ambos teclados:
--   Logi Fn+F1 (XF86HomePage)   = portatil F1 = Mute
--   Logi Fn+F2 (XF86Mail)       = portatil F2 = Volumen -
--   Logi Fn+F3 (XF86Search)     = portatil F3 = Volumen +
--   Logi Fn+F4 (XF86Calculator) = portatil F4 = Brillo -
--   Logi Fn+F5 (XF86Tools)      = portatil F5 = Brillo +
-- (Logi Fn+F9/F10/F11 ya emiten XF86AudioMute/LowerVolume/RaiseVolume, los
-- mismos que el portatil en F1/F2/F3, y Fn+F6/F7/F8 ya son Prev/Play/Next:
-- esos funcionan con los binds de arriba sin tocar nada.)
hl.bind("XF86HomePage", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86Mail", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86Search", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86Calculator", hl.dsp.exec_cmd("brightnessctl --class=backlight set 5%-"), { locked = true, repeating = true })
hl.bind("XF86Tools", hl.dsp.exec_cmd("brightnessctl --class=backlight set 5%+"), { locked = true, repeating = true })


-- Docs: https://wiki.hypr.land/Configuring/Basics/Window-Rules/

hl.layer_rule({
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.layer_rule({
    match = { namespace = "waybar" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.layer_rule({
    match = { namespace = "quickshell" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.layer_rule({
    match = { namespace = "wofi" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.layer_rule({
    match = { namespace = "notifications" },
    blur = true,
    ignore_alpha = 0.15,
})

-- Opacity rules: 100% for all windows
hl.window_rule({
    match = { class = ".*" },
    opacity = "1.0 override",
})

hl.window_rule({
    match = { class = "kitty" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "float-pavucontrol",
    match = { class = "^(pavucontrol)$" },
    float = true,
})

hl.window_rule({
    name = "float-nm-connection-editor",
    match = { class = "^(nm-connection-editor)$" },
    float = true,
})

hl.window_rule({
    name = "float-blueman-manager",
    match = { class = "^(blueman-manager)$" },
    float = true,
})

hl.window_rule({
    name = "float-open-file",
    match = { title = "^(Open File)$" },
    float = true,
})

hl.window_rule({
    name = "float-save-file",
    match = { title = "^(Save File)$" },
    float = true,
})

hl.window_rule({
    name = "float-firefox-pip",
    match = { class = "^(firefox)$", title = "^Picture-in-Picture$" },
    float = true,
    pin = true,
    size = "480 270",
    move = "monitor_w-500 20",
})

hl.window_rule({
    name = "float-xdg-desktop-portal-gtk",
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float = true,
})

hl.window_rule({
    name = "float-thunar-dialogs",
    match = { class = "^(Thunar|thunar)$", title = "^(Confirm to replace files|File Operation Progress)$" },
    float = true,
})

hl.window_rule({
    name = "float-virtualbox",
    match = { class = "^(VirtualBox Machine)$" },
    float = true,
})


-- Docs: https://wiki.hypr.land/Configuring/Basics/Window-Rules/

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

-- Componentes de Quickshell con namespace propio (MediaOSD, Todo, PowerMenu,
-- RecorderOSD). Sin estas reglas perderian el blur que reciben hoy por la
-- regla generica de "quickshell".
hl.layer_rule({
    match = { namespace = "^(mediaosd|mediaosd-settings)$" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.layer_rule({
    match = { namespace = "^(todo|powermenu|powermenu-settings|recorder-osd)$" },
    blur = true,
    ignore_alpha = 0.15,
})

-- Opacidad global para todas las ventanas. El valor lo escribe
-- scripts/opacity.sh (SUPER+O → ámbito "todas las ventanas") en el estado del
-- usuario; si el archivo no existe, se usa 100 %. La opacidad de una sola
-- ventana se aplica en caliente con hyprctl y no toca este archivo.
local opacity_state_home = os.getenv("XDG_STATE_HOME")
if opacity_state_home == nil or opacity_state_home == "" then
    opacity_state_home = os.getenv("HOME") .. "/.local/state"
end

local global_opacity = "1.0"
local opacity_ok, saved_opacity = pcall(dofile, opacity_state_home .. "/hypr/opacity.lua")
if opacity_ok and type(saved_opacity) == "string" and saved_opacity:match("^%d+%.?%d*$") then
    global_opacity = saved_opacity
end

hl.window_rule({
    match = { class = ".*" },
    opacity = global_opacity .. " override",
})

-- Fullscreen windows stay fully opaque even if the global rule was lowered
-- with scripts/opacity.sh (SUPER+O) or a per-window override is active.
hl.window_rule({
    match = { class = ".*", fullscreen = true },
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

-- El portal es un proceso aparte, activado por D-Bus, y puede heredar un
-- HL_INITIAL_WORKSPACE_TOKEN antiguo (o recibir el workspace de la app padre
-- aunque el usuario este en otro). "workspace = unset" ignora ese workspace
-- solicitado y deja que el dialogo siga al workspace activo.
hl.window_rule({
    name = "portal-dialogs-active-workspace",
    match = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-gnome|xdg-desktop-portal-kde)$" },
    workspace = "unset",
})

hl.window_rule({
    name = "float-xdg-desktop-portal-gtk",
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float = true,
    center = true,
    size = "900 600",
})

hl.window_rule({
    name = "float-thunar-modal-dialogs",
    match = { class = "^(thunar|Thunar|org\\.xfce\\.Thunar)$", modal = true },
    float = true,
    center = true,
})

hl.window_rule({
    name = "float-thunar-aux-windows",
    match = { class = "^(thunar|Thunar|org\\.xfce\\.Thunar)$", title = "negative:.* - Thunar$" },
    float = true,
    center = true,
})

hl.window_rule({
    name = "float-virtualbox",
    match = { class = "^(VirtualBox Machine)$" },
    float = true,
})

-- Cámara: vista previa flotante y centrada (scripts/camera.sh, SUPER+C)
hl.window_rule({
    name = "float-camera",
    match = { class = "^(mpv)$", title = "^(Camara)$" },
    float = true,
    size = "960 540",
    center = true,
})

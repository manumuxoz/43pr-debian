-- ~/.config/hypr/hyprland.lua
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- Adaptado a Debian 13 (ver notas "Adaptacion Debian" más abajo).

---- MY PROGRAMS ----

mainMod    = "SUPER"
terminal   = "kitty"
menu       = "wofi --show drun"
fileManager = "thunar"
browser    = "firefox"

---- AUTOSTART ----

hl.on("hyprland.start", function()
    -- Adaptacion Debian: actualiza el entorno del gestor systemd de usuario
    -- para que los portales (xdg-desktop-portal-hyprland) funcionen bien.
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    -- Adaptacion waybar 0.12 + Hyprland 0.55 (Lua): el wrapper arranca el
    -- puente IPC que traduce los clics de los iconos de workspace.
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/waybar-start.sh")
    hl.exec_cmd("dunst")
    -- Luz nocturna: arranca hyprsunset y reaplica el estado guardado si estaba
    -- encendida (el script lo arranca si hace falta y conserva el estado "on").
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/nightlight-toggle.sh --restore")
    -- Adaptacion Debian: hypridle no arranca por systemd (graphical-session.target
    -- nunca se activa con start-hyprland), asi que se lanza como el resto.
    hl.exec_cmd("hypridle")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- Adaptacion Debian: ruta real del agente polkit (paquete polkit-kde-agent-1)
    hl.exec_cmd("/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1")

    -- Adaptacion Debian: restaura el ultimo wallpaper elegido con swaybg
    -- (hyprpaper 0.8.4 de trixie-backports segfaultea al re-aplicar; ver shim ~/.local/bin/awww)
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/wallpaper-restore.sh")
    hl.exec_cmd("sleep 2 && qs")
end)

---- ENVIRONMENT VARIABLES ----

hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_SIZE", "20")
hl.env("XCURSOR_THEME", "default")
-- Electron en Wayland: deja que elija el backend (Wayland nativo o X11)
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- Apps Java bajo Xwayland: evita que el gestor de ventanas las reparente
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
-- hl.env("GDK_SCALE", "2.5") -- En Wayland no hace falta; causaba doble escalado
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
-- Tema oscuro solo para apps GTK dentro de Hyprland (GNOME no se toca)
hl.env("GTK_THEME", "Adwaita:dark")
-- Terminal por defecto para apps/scripts que consultan $TERMINAL
hl.env("TERMINAL", "kitty")
-- Steam (X11) no hereda la escala del monitor y su UI se ve diminuta. El
-- arreglo vive en ~/.local/share/applications/steam.desktop: aplica GDK_SCALE=2
-- solo a Steam (STEAM_FORCE_DESKTOPUI_SCALING y -forcedesktopscaling no
-- funcionan en la rama estable).

-- Xwayland a resolucion nativa en eDP-1 (escala 1.75): sin esto, Hyprland
-- amplia la ventana desde 1646x1029 y las apps X (Java/JFLAP/ProjectLibre)
-- se ven borrosas. Las apps Java compensan con -Dsun.java2d.uiScale=2.
-- Nota: requiere reiniciar Xwayland (xwayland:enabled false -> true); las
-- apps X que no escalen por su cuenta se veran pequenas en eDP-1.
hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

---- INPUT ----

hl.config({
    input = {
        kb_layout = "es",
        follow_mouse = 1,
        sensitivity = 0.5,
        touchpad = {
            natural_scroll = false,
            tap_to_click = true,
        },
    },
})

-- Touchpad del Asus UX3402VA: opciones especificas del dispositivo que no
-- estan ya definidas en input.touchpad.
hl.device({
    name = "asue140d:00-04f3:31b9-touchpad",
    disable_while_typing = true,
    scroll_factor = 1.0,
})

-- Gestos del touchpad (sintaxis del ejemplo oficial): 3 dedos deslizando en
-- horizontal cambia de workspace.
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- LAYOUT
hl.config({
    dwindle = { preserve_split = true },
})
hl.config({
    master = { new_status = "master" },
})

-- MISC
hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

-- Permite escalas fraccionales exactas (p.ej. 1.75) sin que Hyprland las
-- recorte a un divisor "limpio" (1.75 -> 1.8). Necesario para los presets
-- de escala del panel (scripts/set-scale.sh).
hl.config({
    debug = {
        disable_scale_checks = 1,
    },
})

---- SPLIT-OUT FILES ----

require("monitors")
require("keybinds")
require("look")
require("rules")

-- HyprMod managed settings
require("hyprland-gui")

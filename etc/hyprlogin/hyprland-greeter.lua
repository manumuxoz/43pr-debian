-- Sesión Hyprland del greeter (la lanza greetd como usuario _greetd)
-- Se instala en /etc/hyprlogin/hyprland-greeter.lua
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprlogin")
end)

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

hl.config({
    input = {
        kb_layout = "es",
    },
    misc = {
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },
})

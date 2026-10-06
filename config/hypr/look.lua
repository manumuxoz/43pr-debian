---- LOOK AND FEEL ----

hl.config({ render = { expand_undersized_textures = false}})
hl.config({
    general = {
        gaps_in = 4,
        gaps_out = {
            top = 3,
            right = 8,
            bottom = 8,
            left = 8,
        },
        border_size = 0,
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 8,
            border_overlap = false,
            respect_gaps = true,
        },
    },
    decoration = {
        rounding = 8,
        blur = {
            enabled = true,
            size = 5,
            passes = 1,
            vibrancy = 0.2,
        },
        shadow = {
            enabled = true,
            range = 8,
            render_power = 3,
        },
    },
    animations = {
        enabled = true,
    },
})

hl.curve("easeOut", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "border",     enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "default", style = "slidefade" })
hl.animation({ leaf = "windowsIn",       enabled = true, speed = 5, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "layers",          enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "layersIn",        enabled = true, speed = 5, bezier = "easeOut", style = "fade" })
hl.animation({ leaf = "layersOut",       enabled = true, speed = 5, bezier = "easeOut", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",    enabled = true, speed = 4, bezier = "easeOut" })
hl.animation({ leaf = "fadeLayersOut",   enabled = true, speed = 4, bezier = "easeOut" })
hl.animation({ leaf = "workspacesIn",    enabled = true, speed = 6, bezier = "easeOut", style = "slidefade" })
hl.animation({ leaf = "workspacesOut",   enabled = true, speed = 6, bezier = "easeOut", style = "slidefade" })
hl.animation({ leaf = "zoomFactor",      enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "fadeDim",         enabled = true, speed = 4, bezier = "easeOut" })
hl.animation({ leaf = "windowsMove",     enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 6, bezier = "easeOut", style = "slidefade" })


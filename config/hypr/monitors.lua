-- Adaptacion Debian: variables usadas por las reglas de mas abajo.
-- Este equipo tiene dos monitores: eDP-1 (portatil, Intel Iris Xe, izquierda)
-- y el externo ASUS VW199 (derecha), que puede aparecer como HDMI-A-1 (HDMI
-- del portatil) o DP-3 (USB-C) segun el puerto usado.
-- Gestiona las reglas con scripts/monitor-ctl.sh (mode/scale/primary):
-- cualquier salida conectada que no este en el bloque se adopta
-- automaticamente con un modo soportado, sin editar nombres a mano.
--
-- Importante: no fuerces un modo que no aparezca en `availableModes`
-- (`hyprctl -j monitors`). Hyprland acepta modos inventados, pero el panel
-- puede quedarse encendido y en negro. El ASUS VW199 soporta, entre otros,
-- 1440x900@74.98, 1440x900@59.89 y 1920x1080@60.00; NO soporta 1080p@120.

-- To check names run: hyprctl monitors

-- ==== INICIO gestionado por monitor-ctl.sh (no editar a mano) ====
PRIMARY_MONITOR = "eDP-1"
SECONDARY_MONITOR = "HDMI-A-1"
hl.monitor({ output = "eDP-1", mode = "2880x1800@90.00", position = "0x0", scale = 1.75 })
hl.monitor({ output = "HDMI-A-1", mode = "1440x900@74.98", position = "auto", scale = 1.0 })
PRIMARY_WORKSPACES = 5
for i = 1, PRIMARY_WORKSPACES do hl.workspace_rule({ workspace = tostring(i), monitor = PRIMARY_MONITOR, default = true, persistent = true }) end
hl.workspace_rule({ workspace = tostring(PRIMARY_WORKSPACES + 1), monitor = SECONDARY_MONITOR, default = true })
-- ==== FIN gestionado por monitor-ctl.sh ====

-- Cualquier salida que no tenga una regla explicita (proyector, otro monitor,
-- el ASUS si aparece con un nombre nuevo) usa el modo preferido de su EDID.
-- La regla con output="" solo se aplica cuando ninguna regla exacta coincide.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.0 })

-- Overrides manuales que monitor-ctl.sh no reescribe. Crea este archivo solo
-- si necesitas un ajuste puntual (p.ej. otro modo para el externo); el bloque
-- gestionado de arriba se sigue actualizando con normalidad.
pcall(function()
    local path = os.getenv("HOME") .. "/.config/hypr/monitors.local.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        dofile(path)
    end
end)

-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Las reglas las genera el bloque de arriba: 1-5 fijos y persistentes en el
-- principal. El 6 pertenece al monitor secundario pero es temporal (no
-- persistente): se crea al enchufar el monitor y desaparece al desenchufarlo.
-- Si subes PRIMARY_WORKSPACES, el escritorio temporal pasa al siguiente numero.
-- Adaptacion Debian: eliminado el workspace "gaming" del rice original (no aplica en este equipo)

-- For other layouts such as scrolling, see example below
-- hl.workspace_rule({ workspace = "1", monitor = PRIMARY_MONITOR, default = true, persistent = true, layout = scroling })

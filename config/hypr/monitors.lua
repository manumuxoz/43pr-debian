-- Adaptacion Debian: variables usadas por las reglas de mas abajo.
-- Este equipo tiene dos monitores: eDP-1 (portatil, Intel Iris Xe, izquierda)
-- y el externo ASUS VW199 (derecha), que puede aparecer como DP-3 (USB-C,
-- actual) o HDMI-A-1 (HDMI del portatil) segun el puerto usado.
-- Gestiona las reglas con scripts/monitor-ctl.sh (mode/scale/primary):
-- cualquier salida conectada que no este en el bloque se adopta
-- automaticamente con su estado en vivo, sin editar nombres a mano.

-- To check names run: hyprctl monitors

-- ==== INICIO gestionado por monitor-ctl.sh (no editar a mano) ====
PRIMARY_MONITOR = "eDP-1"
SECONDARY_MONITOR = "DP-3"
hl.monitor({ output = "eDP-1", mode = "2880x1800@90.00", position = "0x0", scale = 1.75 })
hl.monitor({ output = "DP-3", mode = "1440x900@74.98", position = "auto", scale = 1.0 })
PRIMARY_WORKSPACES = 5
for i = 1, PRIMARY_WORKSPACES do hl.workspace_rule({ workspace = tostring(i), monitor = PRIMARY_MONITOR, default = true, persistent = true }) end
hl.workspace_rule({ workspace = tostring(PRIMARY_WORKSPACES + 1), monitor = SECONDARY_MONITOR, default = true })
-- ==== FIN gestionado por monitor-ctl.sh ====

-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Las reglas las genera el bloque de arriba: 1-5 fijos y persistentes en el
-- principal. El 6 pertenece al monitor secundario pero es temporal (no
-- persistente): se crea al enchufar el monitor y desaparece al desenchufarlo.
-- Si subes PRIMARY_WORKSPACES, el escritorio temporal pasa al siguiente numero.
-- Adaptacion Debian: eliminado el workspace "gaming" del rice original (no aplica en este equipo)

-- For other layouts such as scrolling, see example below
-- hl.workspace_rule({ workspace = "1", monitor = PRIMARY_MONITOR, default = true, persistent = true, layout = scroling })

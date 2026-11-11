-- ~/.config/hypr/move-all.lua
-- Envía todas las ventanas del workspace activo a otro workspace.
--
-- Si el destino no tiene ventanas tiled, reproduce el árbol de splits del
-- origen (incluidas las proporciones) para que la distribución no cambie.
-- Si el destino ya tiene ventanas tiled, las evacúa a un workspace temporal,
-- reparte todas las ventanas en un árbol equilibrado (áreas iguales) y las
-- devuelve al destino.
--
-- El árbol se reconstruye con `preselect` + `splitratio ... exact`, sin mover
-- el cursor: se enfoca la ventana que hace de nodo de apertura y se inserta la
-- siguiente con el lado forzado.

local M = {}

-- ---------- geometría ----------

local function box_of(w)
    return { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end

local function copy_list(list)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = v
    end
    return out
end

local function bbox_of(nodes)
    local x1, y1 = math.huge, math.huge
    local x2, y2 = -math.huge, -math.huge
    for _, n in ipairs(nodes) do
        local b = n.box
        x1 = math.min(x1, b.x)
        y1 = math.min(y1, b.y)
        x2 = math.max(x2, b.x + b.w)
        y2 = math.max(y2, b.y + b.h)
    end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

local function center_axis(b, axis)
    if axis == "lr" then
        return b.x + b.w / 2
    end
    return b.y + b.h / 2
end

-- Ordena por el eje y busca el corte con el hueco más grande entre grupos.
local function best_split(nodes, axis)
    local sorted = copy_list(nodes)
    table.sort(sorted, function(a, b)
        local ca = center_axis(a.box, axis)
        local cb = center_axis(b.box, axis)
        if ca == cb then
            if axis == "lr" then
                return a.box.x < b.box.x
            end
            return a.box.y < b.box.y
        end
        return ca < cb
    end)

    local best_i, best_gap, best_line = 1, -math.huge, nil
    for i = 1, #sorted - 1 do
        local max_left = -math.huge
        local min_right = math.huge
        for j = 1, i do
            local b = sorted[j].box
            local edge = axis == "lr" and (b.x + b.w) or (b.y + b.h)
            if edge > max_left then
                max_left = edge
            end
        end
        for j = i + 1, #sorted do
            local b = sorted[j].box
            local edge = axis == "lr" and b.x or b.y
            if edge < min_right then
                min_right = edge
            end
        end
        local gap = min_right - max_left
        local line = (max_left + min_right) / 2
        if gap > best_gap then
            best_i, best_gap, best_line = i, gap, line
        end
    end

    return sorted, best_i, best_gap, best_line
end

-- Construye un árbol de splits a partir de las cajas actuales. El eje se
-- deduce del hueco real entre grupos, así también funciona con layouts donde
-- preserve_split ha fijado un eje distinto al que sugiere el aspect ratio.
local function make_tree(nodes)
    if #nodes == 1 then
        return { leaf = nodes[1] }
    end

    local bbox = bbox_of(nodes)
    local lr_sorted, lr_i, lr_gap, lr_line = best_split(nodes, "lr")
    local tb_sorted, tb_i, tb_gap, tb_line = best_split(nodes, "tb")
    local axis, sorted, idx, line
    local prefer_lr = bbox.w >= bbox.h

    if lr_gap > 0 and tb_gap > 0 then
        if math.abs(lr_gap - tb_gap) < 0.5 then
            if prefer_lr then
                axis, sorted, idx, line = "lr", lr_sorted, lr_i, lr_line
            else
                axis, sorted, idx, line = "tb", tb_sorted, tb_i, tb_line
            end
        elseif lr_gap > tb_gap then
            axis, sorted, idx, line = "lr", lr_sorted, lr_i, lr_line
        else
            axis, sorted, idx, line = "tb", tb_sorted, tb_i, tb_line
        end
    elseif lr_gap > 0 then
        axis, sorted, idx, line = "lr", lr_sorted, lr_i, lr_line
    elseif tb_gap > 0 then
        axis, sorted, idx, line = "tb", tb_sorted, tb_i, tb_line
    else
        -- Sin huecos (gaps_in = 0 o ventanas solapadas): partir por el centro.
        axis = prefer_lr and "lr" or "tb"
        sorted = axis == "lr" and lr_sorted or tb_sorted
        idx = math.floor(#sorted / 2)
        local c1 = center_axis(sorted[idx].box, axis)
        local c2 = center_axis(sorted[idx + 1].box, axis)
        line = (c1 + c2) / 2
    end

    if idx < 1 or idx >= #sorted then
        idx = math.floor(#sorted / 2)
        line = axis == "lr" and (bbox.x + bbox.w / 2) or (bbox.y + bbox.h / 2)
    end

    local origin = axis == "lr" and bbox.x or bbox.y
    local size = axis == "lr" and bbox.w or bbox.h
    local ratio = size > 0 and (2 * (line - origin) / size) or 1.0
    ratio = math.max(0.1, math.min(1.9, ratio))

    local a, b = {}, {}
    for i = 1, idx do
        a[#a + 1] = sorted[i]
    end
    for i = idx + 1, #sorted do
        b[#b + 1] = sorted[i]
    end

    return {
        axis = axis,
        ratio = ratio,
        a = make_tree(a),
        b = make_tree(b),
    }
end

-- Árbol equilibrado por áreas: cada split reparte el espacio en proporción al
-- número de ventanas de cada lado, así ninguna ventana queda desproporcionada.
local function balanced_tree(windows, area)
    local function rec(list, box)
        if #list == 1 then
            return { leaf = { win = list[1], box = box } }
        end

        local axis = box.w >= box.h and "lr" or "tb"
        local n = #list
        local n_a = math.floor(n / 2)
        if n_a < 1 then
            n_a = 1
        end
        local ratio = 2 * n_a / n
        local line = axis == "lr" and (box.x + box.w * n_a / n)
            or (box.y + box.h * n_a / n)

        local a_box, b_box
        if axis == "lr" then
            a_box = { x = box.x, y = box.y, w = line - box.x, h = box.h }
            b_box = { x = line, y = box.y, w = box.x + box.w - line, h = box.h }
        else
            a_box = { x = box.x, y = box.y, w = box.w, h = line - box.y }
            b_box = { x = box.x, y = line, w = box.w, h = box.y + box.h - line }
        end

        local a_list, b_list = {}, {}
        for i = 1, n_a do
            a_list[#a_list + 1] = list[i]
        end
        for i = n_a + 1, n do
            b_list[#b_list + 1] = list[i]
        end

        return {
            axis = axis,
            ratio = math.max(0.1, math.min(1.9, ratio)),
            a = rec(a_list, a_box),
            b = rec(b_list, b_box),
        }
    end

    return rec(windows, area)
end

-- ---------- reconstrucción ----------

local function first_leaf(node)
    while node.a ~= nil do
        node = node.a
    end
    return node.leaf
end

-- Genera la secuencia de inserciones. El primer leaf se coloca solo (llena el
-- workspace); cada paso parte el leaf de apertura y coloca el nuevo a la
-- derecha o abajo. Después se fija el ratio exacto del nuevo padre.
local function make_plan(tree)
    local plan = {}
    local first = first_leaf(tree)

    local function emit(node, existing)
        if node.a == nil then
            return
        end
        local new = first_leaf(node.b)
        plan[#plan + 1] = {
            win = new.win,
            opening = existing.win,
            direction = node.axis == "lr" and "r" or "d",
            ratio = node.ratio,
        }
        emit(node.a, existing)
        emit(node.b, new)
    end

    emit(tree, first)
    return first.win, plan
end

local function replay(target, first, plan)
    if first == nil then
        return
    end

    hl.dispatch(hl.dsp.window.move({ window = first, workspace = target, follow = false }))

    for _, step in ipairs(plan) do
        hl.dispatch(hl.dsp.focus({ window = step.opening }))
        hl.dispatch(hl.dsp.layout("preselect " .. step.direction))
        hl.dispatch(hl.dsp.window.move({ window = step.win, workspace = target, follow = false }))
        hl.dispatch(hl.dsp.focus({ window = step.win }))
        hl.dispatch(hl.dsp.layout(string.format("splitratio %.4f exact", step.ratio)))
    end
end

-- ---------- workspaces y ventanas ----------

local function split_windows(ws)
    local tiled, floating = {}, {}
    if ws == nil then
        return tiled, floating
    end
    for _, w in ipairs(hl.get_workspace_windows(ws)) do
        if w.floating then
            floating[#floating + 1] = w
        else
            tiled[#tiled + 1] = w
        end
    end
    return tiled, floating
end

local function nodes_from(windows)
    local nodes = {}
    for i, w in ipairs(windows) do
        nodes[i] = { win = w, box = box_of(w) }
    end
    return nodes
end

local function show_special(target)
    if type(target) ~= "string" then
        return
    end
    local name = target:match("^special:(.+)$")
    if name == nil then
        return
    end
    local active = hl.get_active_special_workspace()
    if active == nil or active.name ~= target then
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
end

local function find_temp(exclude)
    for id = 99, 90, -1 do
        if id ~= exclude then
            local ws = hl.get_workspace(id)
            if ws == nil or ws.windows == 0 then
                return id
            end
        end
    end
    return "special:moveall-temp"
end

local function move_floating(windows, target)
    for _, w in ipairs(windows) do
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = target, follow = false }))
    end
end

local function focus_target(target)
    hl.dispatch(hl.dsp.focus({ workspace = target }))
end

-- ---------- API ----------

function M.move_all_windows_to(target)
    local source = hl.get_active_workspace()
    if source == nil then
        return
    end

    local source_tiled, source_floating = split_windows(source)
    local target_ws = hl.get_workspace(target)
    local target_tiled = split_windows(target_ws)

    -- Mismo workspace: no hay nada que mover.
    if target_ws ~= nil and target_ws.id == source.id then
        focus_target(target)
        return
    end

    show_special(target)

    -- Sin ventanas tiled en el origen solo hay que trasladar las flotantes.
    if #source_tiled == 0 then
        move_floating(source_floating, target)
        focus_target(target)
        return
    end

    -- Destino sin ventanas tiled: conservar la distribución del origen.
    if #target_tiled == 0 then
        local tree = make_tree(nodes_from(source_tiled))
        local first, plan = make_plan(tree)
        replay(target, first, plan)
        move_floating(source_floating, target)
        focus_target(target)
        return
    end

    -- Destino ocupado: evacuar sus ventanas tiled y repartir todo desde cero.
    local all = {}
    for _, w in ipairs(target_tiled) do
        all[#all + 1] = w
    end
    for _, w in ipairs(source_tiled) do
        all[#all + 1] = w
    end

    local temp = find_temp(target)
    for _, w in ipairs(target_tiled) do
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = temp, follow = false }))
    end

    local mon = target_ws and target_ws.monitor or source.monitor
    local area = { x = 0, y = 0, w = 1920, h = 1080 }
    if mon ~= nil then
        local scale = mon.scale or 1
        area = { x = 0, y = 0, w = mon.width / scale, h = mon.height / scale }
    end

    local tree = balanced_tree(all, area)
    local first, plan = make_plan(tree)
    replay(target, first, plan)
    move_floating(source_floating, target)
    focus_target(target)

    -- Si algún movimiento falló, no dejar ventanas perdidas en el temporal.
    for _, w in ipairs(hl.get_workspace_windows(temp)) do
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = target, follow = false }))
    end
end

return M

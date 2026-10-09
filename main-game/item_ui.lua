-- item_ui.lua — how an item looks in the menus (shop + equip share this).
--
--   M.drawGlyph(inst, x, y, size)   the item's square token: a letter (W/A/T) in a
--                                   frame tinted by its grade
--   M.modsText(inst, sep)           "+21 ATK" (what it adds when equipped)
--   M.tooltipLines(inst, opts)      lines for common.drawTooltip: name, description,
--                                   bonuses, who can use it, price
--       opts.price    = { label = "costs" | "sells for", amount = n }   (optional)
--       opts.charName = class key; adds a red "X cannot use this" line when true
--   The shared INVENTORY panel (same place and look on EQUIP and SHOP): see the
--   bottom of this file.

local common = require("common")
local items  = require("items")

local M = {}

M.GRADE_COLORS = {
    [1] = {1, 1, 1, 1},              -- low: white
    [2] = {0.95, 0.78, 0.20, 1},     -- mid: gold
    [3] = {1, 0, 0, 1},              -- high: red
}
M.GOLD   = {0.95, 0.78, 0.20, 1}
M.BONUS  = {1, 0, 0, 1}
M.GREY   = {1, 1, 1, 1}
M.BAD    = {1, 0, 0, 1}

local GLYPHS = { weapon = "W", armor = "A", trinket = "T" }

function M.gradeColor(inst)
    return M.GRADE_COLORS[inst and inst.grade] or M.GRADE_COLORS[1]
end

function M.drawGlyph(inst, x, y, size)
    love.graphics.setColor(M.gradeColor(inst))
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 2, y + 2, size - 4, size - 4)
    love.graphics.setColor(1, 1, 1, 1)
    common.printCentered(common.loadFont(16), GLYPHS[inst.itemType] or "?", x, y, size, size)
end

function M.modsText(inst, sep)
    local parts = {}
    for k, v in pairs(inst.mods or {}) do
        parts[#parts + 1] = "+" .. tostring(v) .. " " .. k
    end
    table.sort(parts)
    return table.concat(parts, sep or ", ")
end

function M.tooltipLines(inst, opts)
    opts = opts or {}
    local lines = {
        { text = inst.name or "(unnamed)", size = 16, color = (inst.grade or 1) > 1 and M.gradeColor(inst) or common.COLOR_WHITE },
        { text = common.titleCase(inst.itemType or "item"), color = M.GREY },
    }
    if inst.desc and inst.desc ~= "" then
        lines[#lines + 1] = { text = inst.desc, color = common.COLOR_WHITE }
    end
    local mods = M.modsText(inst)
    if mods ~= "" then lines[#lines + 1] = { text = mods, color = M.BONUS } end
    if inst.usableBy and #inst.usableBy > 0 then
        local names = {}
        for i, c in ipairs(inst.usableBy) do names[i] = common.titleCase(c) end
        lines[#lines + 1] = { text = "For: " .. table.concat(names, ", "), color = M.GREY }
    end
    if opts.charName and not items.canUse(inst, opts.charName) then
        lines[#lines + 1] = { text = common.titleCase(opts.charName) .. " cannot use this", color = M.BAD }
    end
    if opts.price then
        lines[#lines + 1] = { text = opts.price.label .. " " .. tostring(opts.price.amount) .. " gold", color = M.GOLD }
    end
    return lines
end

-- ============================================================================
-- THE INVENTORY PANEL (identical on the EQUIP and SHOP screens)
-- ============================================================================
-- A framed panel on the right of the screen: "INVENTORY", a hint line, and a
-- 7 x 5 grid of the party's carried items (items.INVENTORY_SIZE cells).
--   M.INV                         its geometry
--   M.invCellRect(index)          -> x, y, w, h of cell `index` (1-based)
--   M.invIndexAt(x, y, saveData)  -> index of the ITEM under the point, or nil
--   M.drawInventory(saveData, selectedId, hint, hintColor)

local INV = { x = 306, y = common.TOP_BAR_H + 12, cols = 7, rows = 5, cell = 64, headH = 34, pad = 14 }
INV.w = common.VW - 20 - INV.x
INV.h = common.VH - 20 - INV.y
INV.gridX = INV.x + math.floor((INV.w - INV.cols * INV.cell) / 2)
INV.gridY = INV.y + INV.headH + math.floor((INV.h - INV.headH - INV.rows * INV.cell) / 2)
M.INV = INV

function M.invCellRect(idx)
    local col = (idx - 1) % INV.cols
    local row = math.floor((idx - 1) / INV.cols)
    return INV.gridX + col * INV.cell, INV.gridY + row * INV.cell, INV.cell, INV.cell
end

function M.invIndexAt(px, py, saveData)
    local inv = saveData.inventory or {}
    for idx = 1, math.min(#inv, INV.cols * INV.rows) do
        local x, y, w, h = M.invCellRect(idx)
        if px >= x and px < x + w and py >= y and py < y + h then return idx end
    end
    return nil
end

function M.drawInventory(saveData, selectedId, hint, hintColor)
    local f16, f13 = common.loadFont(16), common.loadFont(13)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", INV.x, INV.y, INV.w, INV.h)

    love.graphics.setFont(f16)
    love.graphics.setColor(common.COLOR_RED)
    local headY = math.floor(INV.y + (INV.headH - f16:getHeight()) / 2) + 2
    love.graphics.print("INVENTORY", INV.x + INV.pad, headY)

    -- What a click will do next, right-aligned in the caption band.
    if hint then
        hint = common.fitText(f13, hint, INV.w - INV.pad * 2 - f16:getWidth("INVENTORY") - 16)
        love.graphics.setFont(f13)
        love.graphics.setColor(hintColor or {1, 1, 1, 1})
        love.graphics.print(hint, INV.x + INV.w - INV.pad - f13:getWidth(hint), headY + 2)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    for idx = 1, INV.cols * INV.rows do
        love.graphics.rectangle("line", M.invCellRect(idx))
    end

    for idx, id in ipairs(saveData.inventory or {}) do
        if idx > INV.cols * INV.rows then break end
        local x, y, w, h = M.invCellRect(idx)
        local inst = saveData.items and saveData.items[id]
        if type(inst) == "table" then M.drawGlyph(inst, x + 6, y + 6, w - 12) end
        if id == selectedId then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2)
        end
    end
end

return M

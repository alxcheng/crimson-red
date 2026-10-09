-- item_ui.lua — how an item looks in the menus (shop + equip share this).
--
--   M.drawGlyph(inst, x, y, size)   the item's square token: a letter (W/A/T) in a
--                                   frame tinted by its grade
--   M.modsText(inst, sep)           "+21 ATK" (what it adds when equipped)
--   M.tooltipLines(inst, opts)      lines for common.drawTooltip: name, description,
--                                   bonuses, who can use it, price
--       opts.price    = { label = "costs" | "sells for", amount = n }   (optional)
--       opts.charName = class key; adds a red "X cannot use this" line when true

local common = require("common")
local items  = require("items")

local M = {}

M.GRADE_COLORS = {
    [1] = {0.55, 0.55, 0.55, 1},   -- low: grey
    [2] = {0.95, 0.55, 0.20, 1},   -- mid: orange
    [3] = {0.95, 0.20, 0.35, 1},   -- high: crimson
}
M.GOLD   = {0.95, 0.78, 0.20, 1}
M.BONUS  = {0.95, 0.55, 0.20, 1}
M.GREY   = {0.75, 0.75, 0.75, 1}
M.BAD    = {0.85, 0.30, 0.35, 1}

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

return M

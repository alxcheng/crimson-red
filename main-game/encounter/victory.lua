-- encounter/victory.lua — the screens shown after a battle is won.
--
-- Battleheart's order (MotherBrain.levelCompleteSequence —
-- bh/systems/battle-end-rewards-xp-loot.md section 3), in three stages:
--   1. "victory"  the word VICTORY
--   2. "spoils"   the gold earned, then the ONE item dropped
--   3. "xp"       every hero's XP gain; the bars fill and heroes level up
-- A click or key press moves to the next stage (or finishes the bar animation);
-- stages 1 and 2 also move on by themselves. Stage 3 waits for the player.
--
-- The rewards are already in the save when this starts: progression.onEncounterWon
-- granted them and returned the `result` table this module displays.
--
--   M.start(battle, result, partyNames, deadSlots)
--   M.update(battle, dt) -> true when the player has dismissed the last stage
--   M.advance(battle)       click / key
--   M.draw(battle)

local common  = require("common")
local item_ui = require("item_ui")

local M = {}

local VW, VH = common.VW, common.VH

local VICTORY_TIME = 2.1     -- BH: the word stays 2.1 s
local GOLD_AT      = 0.4     -- seconds into "spoils" the gold appears (BH 0.4)
local LOOT_AT      = 0.8     -- ... and the item (BH 0.4 later)
local SPOILS_TIME  = 3.8     -- BH: 3.0 s after the item
local BARS_AT      = 1.0     -- seconds into "xp" before the bars start to fill
local BAR_SPEED    = 0.9     -- bar lengths filled per second

local RED     = {1, 0, 0, 1}
local GOLD    = item_ui.GOLD

function M.start(battle, result, partyNames, deadSlots)
    local rows, byName = {}, {}
    for _, x in ipairs(result.xp or {}) do byName[x.name] = x end
    for i, name in ipairs(partyNames or {}) do
        local x = byName[name]
        if x and not (deadSlots and deadSlots[i]) then
            rows[#rows + 1] = {
                name = name, gained = x.gained, levelUps = x.levelUps,
                from = x.before.level + x.before.frac,          -- bar position as level + fraction
                to   = x.after.level + x.after.frac,
                pos  = x.before.level + x.before.frac,
            }
        else
            rows[#rows + 1] = { name = name, fallen = true }
        end
    end
    battle.victory = { stage = "victory", t = 0, result = result, rows = rows, finished = false }
end

local function barsDone(v)
    for _, r in ipairs(v.rows) do
        if not r.fallen and r.pos < r.to then return false end
    end
    return true
end

function M.advance(battle)
    local v = battle.victory
    if not v then return end
    if v.stage == "victory" then
        v.stage, v.t = "spoils", 0
    elseif v.stage == "spoils" then
        v.stage, v.t = "xp", 0
    elseif not barsDone(v) then
        for _, r in ipairs(v.rows) do if not r.fallen then r.pos = r.to end end
    else
        v.finished = true
    end
end

function M.update(battle, dt)
    local v = battle.victory
    if not v then return false end
    v.t = v.t + dt
    if v.stage == "victory" and v.t >= VICTORY_TIME then
        v.stage, v.t = "spoils", 0
    elseif v.stage == "spoils" and v.t >= SPOILS_TIME then
        v.stage, v.t = "xp", 0
    elseif v.stage == "xp" and v.t >= BARS_AT then
        for _, r in ipairs(v.rows) do
            if not r.fallen and r.pos < r.to then
                local before = math.floor(r.pos)
                r.pos = math.min(r.to, r.pos + BAR_SPEED * dt)
                if math.floor(r.pos) > before then r.flash = 1 end   -- crossed a level
            end
            if r.flash then
                r.flash = r.flash - dt / 0.8
                if r.flash <= 0 then r.flash = nil end
            end
        end
    end
    return v.finished
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function panel(w, h, title)
    local x, y = math.floor((VW - w) / 2), math.floor((VH - h) / 2)
    love.graphics.setColor(0, 0, 0, 0.95)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setColor(common.COLOR_RED)
    common.printCentered(common.loadFont(20), title, x, y + 8, w, 28)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(x + 14, y + 42, x + w - 14, y + 42)
    return x, y
end

local function drawSpoils(v)
    local res = v.result
    local w, h = 380, 176
    local x, y = panel(w, h, "SPOILS")
    local f16, f13 = common.loadFont(16), common.loadFont(13)

    if v.t >= GOLD_AT then
        local label = "+" .. tostring(res.gold) .. " gold"
        local lw = f16:getWidth(label)
        local sx = math.floor(x + (w - (20 + lw)) / 2)
        love.graphics.setColor(GOLD)
        love.graphics.circle("fill", sx + 7, y + 66, 7)
        love.graphics.setColor(0.70, 0.52, 0.10, 1)
        love.graphics.circle("line", sx + 7, y + 66, 5)
        love.graphics.setFont(f16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(label, sx + 20, y + 66 - math.floor(f16:getHeight() / 2))
    end

    if v.t >= LOOT_AT then
        local inst = res.loot
        if inst then
            local bx, by, bw, bh = x + 24, y + 96, w - 48, 60
            love.graphics.setColor(item_ui.gradeColor(inst))
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", bx, by, bw, bh)
            item_ui.drawGlyph(inst, bx + 8, by + 8, 44)
            local tx, tw = bx + 62, bw - 70
            love.graphics.setFont(f16)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(common.fitText(f16, inst.name or "(unnamed)", tw), tx, by + 10)
            love.graphics.setFont(f13)
            love.graphics.setColor(item_ui.BONUS)
            love.graphics.print(common.fitText(f13, common.titleCase(inst.itemType or "") .. "   " .. item_ui.modsText(inst), tw),
                tx, by + 32)
        else
            love.graphics.setColor(1, 1, 1, 1)
            common.printCentered(f13, res.lootLost and "Inventory full - the item was lost" or "No item this time",
                x, y + 96, w, 60)
        end
    end
end

local function drawXP(v)
    local rowH = 40
    local w, h = 520, 56 + #v.rows * rowH + 30
    local x, y = panel(w, h, "EXPERIENCE")
    local f16, f13 = common.loadFont(16), common.loadFont(13)
    local barX, barW = x + 190, 200

    for i, r in ipairs(v.rows) do
        local ry = y + 52 + (i - 1) * rowH
        local midY = ry + rowH / 2
        love.graphics.setFont(f16)
        love.graphics.setColor(r.fallen and {1, 1, 1, 1} or {1, 1, 1, 1})
        love.graphics.print(common.fitText(f16, common.titleCase(r.name), 110), x + 20, midY - 9)
        if r.fallen then
            love.graphics.setFont(f13)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("fell in battle - no XP", barX - 54, midY - 7)
        else
            local level = math.floor(r.pos)
            local frac  = r.pos - level
            if r.pos >= r.to and r.to == math.floor(r.to) and r.to > r.from then frac = 0 end
            love.graphics.setFont(f13)
            love.graphics.setColor(RED)
            love.graphics.print("Lv " .. tostring(level), barX - 54, midY - 7)
            -- Bar: dark track, crimson fill; flashes white on a level-up.
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", barX, midY - 5, barW, 10)
            love.graphics.setColor(r.flash and {1, 1, 1, 1} or RED)
            love.graphics.rectangle("fill", barX, midY - 5, barW * frac, 10)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", barX, midY - 5, barW, 10)
            if r.flash then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print("LEVEL UP!", barX + barW + 12, midY - 7)
            else
                love.graphics.setColor(GOLD)
                love.graphics.print("+" .. tostring(r.gained) .. " XP", barX + barW + 12, midY - 7)
            end
        end
    end

    if barsDone(v) then
        love.graphics.setColor(1, 1, 1, 1)
        common.printCentered(f13, "Click to continue", x, y + h - 30, w, 22)
    end
end

function M.draw(battle)
    local v = battle.victory
    if not v then return end
    local dim = (v.stage == "victory") and math.min(1, v.t / 0.4) * 0.5 or 0.5
    love.graphics.setColor(0, 0, 0, dim)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    if v.stage == "victory" then
        -- Pops in slightly oversized, then settles.
        local f = common.loadFont(50)
        local s = 1 + 0.25 * math.max(0, 1 - v.t / 0.25)
        local txt = "VICTORY"
        love.graphics.setFont(f)
        love.graphics.setColor(common.COLOR_RED)
        love.graphics.print(txt, VW / 2, VH / 2 - 10, 0, s, s, f:getWidth(txt) / 2, f:getHeight() / 2)
    elseif v.stage == "spoils" then
        drawSpoils(v)
    else
        drawXP(v)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return M

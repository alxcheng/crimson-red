-- encounter/defeat.lua — what happens when every hero is dead.
--
-- Battleheart's order (MotherBrain.defeatSequence, normal level —
-- bh/systems/battle-end-rewards-xp-loot.md section 6.1):
--   0.0 s  the last hero dies; the player can no longer give orders
--   1.8 s  the word DEFEAT pops in
--   4.9 s  the screen fades to black (1.5 s)
--   6.4 s  back to the map
-- No gold, XP or loot is given and nothing is taken away; the battle is not
-- marked as won, so it can be fought again (screens/encounter.lua puts the
-- encounter back on the map).
--
-- The battle keeps running underneath (death animations, enemies standing
-- around). A click or key press once DEFEAT is showing skips to the fade.
--
--   M.start(battle)
--   M.update(battle, dt) -> true when it is time to leave for the map
--   M.advance(battle)       click / key
--   M.draw(battle)

local common = require("common")

local M = {}

local VW, VH = common.VW, common.VH

local BANNER_AT = 1.8
local FADE_AT   = 4.9
local FADE_TIME = 1.5

function M.start(battle)
    battle.defeat = { t = 0 }
end

function M.update(battle, dt)
    local d = battle.defeat
    if not d then return false end
    d.t = d.t + dt
    return d.t >= FADE_AT + FADE_TIME
end

function M.advance(battle)
    local d = battle.defeat
    if d and d.t >= BANNER_AT and d.t < FADE_AT then d.t = FADE_AT end
end

function M.draw(battle)
    local d = battle.defeat
    if not d or d.t < BANNER_AT then return end
    local bt = d.t - BANNER_AT
    love.graphics.setColor(0, 0, 0, math.min(1, bt / 0.4) * 0.5)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Pops in slightly oversized, then settles (same as VICTORY).
    local f = common.loadFont(50)
    local s = 1 + 0.25 * math.max(0, 1 - bt / 0.25)
    local txt = "DEFEAT"
    love.graphics.setFont(f)
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print(txt, VW / 2, VH / 2 - 10, 0, s, s, f:getWidth(txt) / 2, f:getHeight() / 2)

    if d.t >= FADE_AT then
        love.graphics.setColor(0, 0, 0, math.min(1, (d.t - FADE_AT) / FADE_TIME))
        love.graphics.rectangle("fill", 0, 0, VW, VH)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return M

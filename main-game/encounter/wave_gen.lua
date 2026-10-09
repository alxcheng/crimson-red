-- encounter/wave_gen.lua — makes up the waves of a battle (procedural).
--
--   M.generate(tier) -> { wave, ... }     tier 1 = a floor's first battle
--
-- The output has Battleheart's wave shape (see encounter/encounter_mgr.lua), and
-- the generator is tuned to look like BH's own first-map battles
-- (data/bh_rewards.lua LEVELS[n].waves): about five waves; the first is a single
-- weak enemy; the size of the waves ramps up with a breather in the middle;
-- waves alternate between a TRICKLE (mixed enemies a couple of seconds apart)
-- and a BURST (two or three of the same enemy at once).
--
-- How a wave is filled: each wave has a danger BUDGET; enemies are picked at
-- random from the types allowed at this tier (data/enemies.lua `minTier`,
-- `danger`) until the budget is spent. To change how hard battles are, change
-- the numbers in TUNING — nothing else.

local enemies = require("data/enemies")

local M = {}

M.TUNING = {
    waves        = 5,                           -- waves per battle
    ramp         = { 0.4, 0.8, 1.3, 0.9, 1.7 }, -- wave N's budget = budget(tier) x ramp[N]
    baseBudget   = 4,                           -- budget(tier) = baseBudget + perTier x (tier - 1)
    perTier      = 1.5,
    maxOnField   = 4,                           -- hard cap on enemies alive at once
    firstDelay   = 3.5,                         -- seconds before the first enemy (BH: 3.5)
    waveDelay    = { 2.0, 4.0 },                -- pause before each later wave
    trickleDelay = { 1.5, 3.0 },                -- seconds between spawns in a trickle wave
    burstDelay   = { 0.1, 0.5 },                -- ... in a burst wave
}

local function rand(range) return range[1] + (range[2] - range[1]) * math.random() end

-- Enemy ids allowed at `tier`, cheapest first.
local function pool(tier)
    local ids = {}
    for id, def in pairs(enemies.ENEMIES) do
        if (def.minTier or 1) <= tier then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local da, db = enemies.ENEMIES[a].danger, enemies.ENEMIES[b].danger
        if da ~= db then return da < db end
        return a < b
    end)
    return ids
end

-- Spend `budget` on enemies from `ids`. `sameType` = a burst of one enemy type.
local function fill(ids, budget, sameType)
    local out = {}
    local cheapest = enemies.ENEMIES[ids[1]].danger
    local affordable = {}
    for _, id in ipairs(ids) do
        if enemies.ENEMIES[id].danger <= math.max(budget, cheapest) then affordable[#affordable + 1] = id end
    end
    local burstId = affordable[math.random(#affordable)]
    repeat
        local id = burstId
        if not sameType then
            local options = {}
            for _, cand in ipairs(affordable) do
                if enemies.ENEMIES[cand].danger <= math.max(budget, cheapest) then options[#options + 1] = cand end
            end
            id = options[math.random(#options)]
        end
        out[#out + 1] = id
        budget = budget - enemies.ENEMIES[id].danger
    until budget < cheapest or #out >= 8
    return out
end

function M.generate(tier)
    tier = math.max(1, tier or 1)
    local T, ids = M.TUNING, pool(tier)
    local budget = T.baseBudget + T.perTier * (tier - 1)
    local waves = {}
    for n = 1, T.waves do
        local burst = (n % 2 == 0)
        local list
        if n == 1 then
            list = { ids[1] }                      -- always open with one weak enemy
        else
            list = fill(ids, budget * T.ramp[n], burst)
        end
        waves[n] = {
            initialDelay = (n == 1) and T.firstDelay or rand(T.waveDelay),
            spawnDelay   = burst and rand(T.burstDelay) or rand(T.trickleDelay),
            -- A burst puts its whole group on the field; a trickle keeps a couple at a time.
            maxEnemies   = math.min(T.maxOnField, burst and #list or math.max(1, math.min(#list, 1 + math.floor((tier + 1) / 2)))),
            enemies      = list,
        }
    end
    return waves
end

return M

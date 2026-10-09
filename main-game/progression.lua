-- progression.lua — hero stats, XP / level-ups, battle rewards and hiring.
--
-- A hero's saved record (saveData.unlockedCharacters[name]) holds only
-- CHOICES and PROGRESS: level, pointsToNextLevel, equipped, skillTree,
-- recruited. Stats are never saved — M.heroStats derives them every time:
--
--   stat = class base + class scale x (level - 1) + equipped gear + talent picks
--
-- Rules marked BH follow Battleheart (see bh/README.md); [tuned] are ours.

local classes = require("data/classes")
local talents = require("data/talents")
local rewards = require("data/bh_rewards")
local items   = require("items")

local M = {}

M.MAX_LEVEL = 30   -- BH's last power unlock

-- ============================================================================
-- STATS
-- ============================================================================

-- Flat battle stats for a hero: { maxHP, ATK, DEF, CRIT }, or nil if the
-- class has no battle data (data/classes.lua).
function M.heroStats(saveData, name)
    local def = classes.CLASSES[name]
    local rec = saveData and saveData.unlockedCharacters and saveData.unlockedCharacters[name]
    if not def then return nil end
    local level = rec and rec.level or 1
    local b, s = def.base, def.scale
    local out = {
        maxHP = b.hp      + s.hp      * (level - 1),
        ATK   = b.power   + s.power   * (level - 1),
        DEF   = b.defense + s.defense * (level - 1),
        CRIT  = b.crit or 0,
    }
    local function add(mods)
        for k, v in pairs(mods or {}) do
            if out[k] then out[k] = out[k] + v end
        end
    end
    if rec then
        for _, inst in pairs(items.resolveGear(saveData, name)) do add(inst.mods) end
        add(talents.modsFor(name, rec.skillTree))
    end
    out.maxHP, out.ATK, out.DEF = math.floor(out.maxHP), math.floor(out.ATK), math.floor(out.DEF)
    return out
end

-- Highest level among recruited heroes (drives shop stock and hire level).
function M.highestLevel(saveData)
    local best = 1
    for _, rec in pairs(saveData.unlockedCharacters or {}) do
        if rec.recruited and (rec.level or 1) > best then best = rec.level end
    end
    return best
end

-- ============================================================================
-- XP  (BH: MotherBrain.calculateNextLevelXP — bh/systems/battle-end-rewards-xp-loot.md)
-- ============================================================================

-- XP needed to go from `level` to `level + 1`: 30, 40, 54, 72, 97, 129, ...
function M.xpToNext(level)
    local xp, tbl = rewards.FIRST_LEVEL_XP, rewards.XP_TABLE
    for i = 2, level or 1 do
        xp = math.floor(xp * (tbl[i + 1] or tbl[#tbl]))   -- BH reads XPtable[i], 0-based
    end
    return xp
end

-- Add `amount` XP to one hero record. Returns the number of levels gained.
function M.addXP(rec, amount)
    if type(rec) ~= "table" or not amount or amount <= 0 then return 0 end
    rec.level = (type(rec.level) == "number" and rec.level >= 1) and math.floor(rec.level) or 1
    if rec.level >= M.MAX_LEVEL then
        rec.pointsToNextLevel = 0
        return 0
    end
    local need = rec.pointsToNextLevel
    if type(need) ~= "number" or need <= 0 then need = M.xpToNext(rec.level) end
    need = need - amount
    local gained = 0
    while need <= 0 and rec.level < M.MAX_LEVEL do
        rec.level = rec.level + 1
        gained = gained + 1
        need = need + M.xpToNext(rec.level)
    end
    rec.pointsToNextLevel = (rec.level >= M.MAX_LEVEL) and 0 or need
    return gained
end

-- ============================================================================
-- BATTLE REWARDS
-- ============================================================================

-- BH: each survivor gets the level's XP times this, by how many survived.
local SURVIVOR_XP_MULT = { 4, 2, 1.33, 1 }

local function floorRewards(floor)
    local rows = rewards.LEVELS
    return rows[math.max(1, math.min(floor or 1, #rows))]
end

-- Grant the rewards for a WON battle. `survivors` = hero names still standing,
-- `kills` = enemies defeated. Returns { gold = n, levelUps = { [name] = n } }.
--   gold: BH level gold x random 0.85..1.15, + 1 per kill [tuned]
--   XP:   BH level XP x survivor multiplier, to each survivor
function M.onEncounterWon(saveData, survivors, kills)
    local row = floorRewards(saveData.floor)
    local gold = math.floor(row.gold * (0.85 + 0.30 * math.random()) + 0.5) + (kills or 0)
    items.addGold(saveData, gold)

    local levelUps = {}
    local n = #survivors
    if n > 0 then
        local share = math.floor(row.xp * (SURVIVOR_XP_MULT[n] or 1) + 0.5)
        for _, name in ipairs(survivors) do
            local gained = M.addXP(saveData.unlockedCharacters[name], share)
            if gained > 0 then levelUps[name] = gained end
        end
    end
    -- The shop restocks after every won battle (BH rule).
    if saveData.shopState then saveData.shopState.pendingRestock = true end
    return { gold = gold, levelUps = levelUps }
end

-- ============================================================================
-- HIRING
-- ============================================================================

-- A recruit joins one level below the party's best hero (minimum 1). [tuned]
function M.hireLevel(saveData)
    return math.max(1, M.highestLevel(saveData) - 1)
end

-- BH charges 10 gold per level of the hero hired; BH's cheapest recruit is
-- level 2, hence the +1.                                             [tuned]
function M.hireCost(saveData)
    return 10 * (M.hireLevel(saveData) + 1)
end

-- A random hero who can be hired: not yet recruited, and playable.
function M.rollHire(saveData)
    local candidates = {}
    for name, rec in pairs(saveData.unlockedCharacters or {}) do
        if not rec.recruited and classes.CLASSES[name] then candidates[#candidates + 1] = name end
    end
    table.sort(candidates)   -- pairs() order is not stable; keep rolls reproducible
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

-- Recruit `name`: sets level, gives starter gear. Does NOT charge gold or
-- touch partyOrder (the shop does both).
function M.recruit(saveData, name)
    local rec = saveData.unlockedCharacters[name]
    if not rec then return end
    rec.recruited = true
    rec.level = M.hireLevel(saveData)
    rec.pointsToNextLevel = M.xpToNext(rec.level)
    items.equipStarterGear(saveData, name)
end

return M

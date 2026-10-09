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
-- BH: the best / 2nd / 3rd performers among the survivors get this much extra.
local RANK_BONUS = { 0.25, 0.16, 0.08 }

-- Which battle of the floor is being fought: 1 for the first, 2 for the second...
-- (the map records an encounter as cleared the moment it is entered). It picks the
-- reward row and how hard the waves are (encounter/wave_gen.lua).
function M.battleTier(saveData)
    local mp = saveData and saveData.mapProgression
    local cleared = mp and mp.clearedEncounters and #mp.clearedEncounters or 0
    return math.max(1, cleared) + ((saveData and saveData.floor or 1) - 1) * 4
end

local function tierRewards(tier)
    local rows = rewards.LEVELS
    return rows[math.max(1, math.min(tier or 1, #rows))]
end

-- Where a hero stands on the way to the next level: { level, frac = 0..1 }.
local function xpState(rec)
    local level = rec.level or 1
    if level >= M.MAX_LEVEL then return { level = level, frac = 0 } end
    local need = M.xpToNext(level)
    local left = rec.pointsToNextLevel
    if type(left) ~= "number" or left <= 0 then left = need end
    return { level = level, frac = math.max(0, math.min(1, 1 - left / need)) }
end

-- The one item a won battle drops (BH loot roll): a random entry of the tier's
-- loot table, or of the next table up on a "rare" roll. Returns a catalog id.
local function rollLoot(row)
    local tables = require("data/bh_items").LOOT_TABLES
    local idx = (row.lootTable or 0) + 1
    if (row.rareChance or 0) > 0 and math.random(0, 100) <= row.rareChance then idx = idx + 1 end
    local tbl = tables[math.min(idx, #tables)]
    for _ = 1, 20 do                                  -- skip trinkets the game cannot apply yet
        local bhId = tbl.items[math.random(#tbl.items)]
        if items.isSupported(bhId) then return bhId end
    end
    return nil
end

-- Grant the rewards for a WON battle and return what was granted, for the
-- victory screen (encounter/victory.lua).
--   survivors = hero names still standing, in party order
--   kills     = enemies defeated
--   scores    = { [name] = performance score } (optional; ranks the XP bonus)
-- Returns {
--   gold  = n,                         BH level gold x random 0.85..1.15
--   loot  = item instance | nil,       exactly one item if the inventory has room
--   lootLost = true                    when it was full (BH: the item is lost)
--   kills = n,
--   xp    = { { name, gained, before = {level, frac}, after = {level, frac}, levelUps }, ... }
-- }
-- XP per survivor: level XP x survivor-count multiplier x (1 + rank bonus).
function M.onEncounterWon(saveData, survivors, kills, scores)
    local row = tierRewards(M.battleTier(saveData))
    local result = { kills = kills or 0, xp = {} }

    result.gold = math.floor(row.gold * (0.85 + 0.30 * math.random()) + 0.5)
    items.addGold(saveData, result.gold)

    if items.inventoryFull(saveData) then
        result.lootLost = true
    else
        local bhId = rollLoot(row)
        local id = bhId and items.mint(saveData, bhId)
        if id then
            saveData.inventory[#saveData.inventory + 1] = id
            result.loot = saveData.items[id]
        end
    end

    -- Rank the survivors by score (ties: later party slot first, as in BH).
    local ranked = {}
    for i, name in ipairs(survivors) do ranked[i] = { name = name, slot = i, score = scores and scores[name] or 0 } end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.slot > b.slot
    end)
    local bonus = {}
    for rank, r in ipairs(ranked) do bonus[r.name] = RANK_BONUS[rank] or 0 end

    local mult = SURVIVOR_XP_MULT[#survivors] or 1
    for _, name in ipairs(survivors) do
        local rec = saveData.unlockedCharacters[name]
        if rec then
            local before = xpState(rec)
            local gained = math.floor(row.xp * mult * (1 + bonus[name]) + 0.5)
            local ups = M.addXP(rec, gained)
            result.xp[#result.xp + 1] = { name = name, gained = gained, before = before,
                                          after = xpState(rec), levelUps = ups }
        end
    end

    -- The shop restocks after every won battle (BH rule).
    if saveData.shopState then saveData.shopState.pendingRestock = true end
    return result
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

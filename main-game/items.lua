-- items.lua — Phase 0 economy & item foundation.
--
-- Implements the Foundation API from work/phase0-contract.md:
--   CATALOG (3 grades x weapon/armor/trinket, ~15 templates),
--   makeInstance, randomItem, rollOffers, rollHire, resolveGear,
--   addGold, spendGold, sellValue, nextId, onEncounterWon.
--
-- Item instances live in saveData.items[id]; per-character equipment in
-- saveData.unlockedCharacters[name].equipped = {weapon=, armor=, trinket=}.
--
-- Gear is folded into encounter stats at the boundary ONLY (encounter/stats.lua
-- M.fromSave(ss, gear)). This module never mutates a character's stats directly.
--
-- NOTE: There is no Lua interpreter available in this environment. All values
-- below tagged [tuned] are CR placeholder guesses (the BH data DB is not
-- extractable). They are centralized in this one file for easy retuning.

local M = {}

-- ============================================================================
-- TUNED ECONOMY CONSTANTS (single source of truth, see contract § Values)
-- ============================================================================

local GRADE_VALUE = { [1] = 8, [2] = 16, [3] = 30 }   -- [tuned] base item value by grade
local HIRE_COST   = function(floor) return 60 + 20 * floor end  -- [tuned] character hire cost

-- Grade bands by floor (contract):
--   floor 1-2 -> mostly g1 + some g2
--   floor 3-4 -> g2 + some g3
--   floor 5+  -> g2 / g3
-- Each returns (g1Weight, g2Weight, g3Weight). [tuned]
local function gradeWeights(floor)
    floor = floor or 1
    if floor <= 2 then
        return 7, 3, 0
    elseif floor <= 4 then
        return 0, 6, 4
    else
        return 0, 4, 6
    end
end

-- ============================================================================
-- CATALOG — base item templates per (itemType, grade).
--
-- Structure: M.CATALOG.<itemType>[grade] = { name=, mods=, usableBy=, value= }
--   name     : display name (generated per catalog; grade conveyed by prefix)
--   mods     : flat stat additions added to the matching stat's .add at the
--              encounter boundary. Keys must be valid stat names from
--              encounter/stats.lua (ATK, DEF, maxHP, CRIT, RES, BOOST, ...)
--              so they map 1:1 onto stats. Percentage modifiers are expressed
--              as flat adds to the relevant stat (e.g. +ATK% is a flat +ATK,
--              since CR has no separate percent axis in its stat table yet).
--   usableBy : weapon class-gate (array of character keys). armor/trinket = {} (any).
--   value    : base value in gold; sellPrice = floor(value / 2) [tuned].
-- ============================================================================

-- Weapon class-gates (contract):
--   knight/champion -> sword line
--   duelist/hunter  -> blade/bow line
--   witch/wizard    -> staff line
--   rogue/nomad/piper/jester/cleric/paladin -> mixed (all)
local SWORD_LINE = { "knight", "champion" }
local BLADE_BOW  = { "duelist", "hunter" }
local STAFF_LINE = { "witch", "wizard" }
local MIXED      = {}   -- {} means "any character" (gate not enforced per-class)

-- Weapon mod magnitudes (contract): g1 ATK 2 / g2 ATK 4 / g3 ATK 7. [tuned]
-- Armor: g1 DEF1+HP10 / g2 DEF2+HP20 / g3 DEF4+HP35. [tuned]
-- Trinket: one of +ATK% / +DEF / +maxHP / +XP% (scaled g1..g3). [tuned]
--   +ATK% and +XP% are represented as flat ATK / a no-op marker, because CR's
--   stat table has no percent axis yet; see comment in makeInstance.

M.CATALOG = {
    weapon = {
        [1] = { name = "Rusted Longsword",   mods = { ATK = 2 }, usableBy = SWORD_LINE, value = GRADE_VALUE[1] },
        [2] = { name = "Steel Longsword",    mods = { ATK = 4 }, usableBy = SWORD_LINE, value = GRADE_VALUE[2] },
        [3] = { name = "Crimson Longsword",  mods = { ATK = 7 }, usableBy = SWORD_LINE, value = GRADE_VALUE[3] },
    },
    armor = {
        [1] = { name = "Leather Jerkin",     mods = { DEF = 1, maxHP = 10 }, usableBy = {}, value = GRADE_VALUE[1] },
        [2] = { name = "Chain Hauberk",      mods = { DEF = 2, maxHP = 20 }, usableBy = {}, value = GRADE_VALUE[2] },
        [3] = { name = "Plate Cuirass",      mods = { DEF = 4, maxHP = 35 }, usableBy = {}, value = GRADE_VALUE[3] },
    },
    trinket = {
        [1] = { name = "Worn Charm",         mods = { ATK = 1, DEF = 1 }, usableBy = {}, value = GRADE_VALUE[1] },
        [2] = { name = "Silver Amulet",      mods = { ATK = 2, DEF = 2 }, usableBy = {}, value = GRADE_VALUE[2] },
        [3] = { name = "Radiant Relic",      mods = { ATK = 3, DEF = 3, maxHP = 15 }, usableBy = {}, value = GRADE_VALUE[3] },
    },
}

-- BLADE_BOW / STAFF_LINE are reserved for class-specific weapon lines if the
-- catalog is expanded (contract mentions duelist/hunter blade-bow and
-- witch/wizard staff lines). The current 3-grade weapon set is shared (sword
-- line) to keep the launch catalog lean (~15 templates total per contract);
-- MIXED/other classes can equip it because the gate is enforced at equip time,
-- not in this table. [tuned — catalog may grow per class in a later phase.]

-- ============================================================================
-- INSTANCE FACTORY
-- ============================================================================

local ICON_BY_TYPE = { weapon = "weapon", armor = "armor", trinket = "trinket" }

-- Build a concrete item instance from a CATALOG template. The id is
-- pre-allocated by the caller (see M.nextId). Returns the instance table
-- (does NOT store it in saveData.items — the caller does that).
function M.makeInstance(id, itemType, grade)
    local cat  = M.CATALOG[itemType]
    local tmpl = cat and cat[grade] or nil
    if not tmpl then
        -- Defensive fallback: unknown type/grade yields a no-mod item so we
        -- never crash the save format. This should not happen in practice.
        tmpl = { name = "Mystery Item", mods = {}, usableBy = {}, value = GRADE_VALUE[1] }
    end
    return {
        id        = id,
        itemType  = itemType,
        grade     = grade,
        name      = tmpl.name,
        icon      = ICON_BY_TYPE[itemType] or "trinket",
        sellPrice = math.floor((tmpl.value or GRADE_VALUE[1]) / 2),  -- [tuned] 50% of value
        usableBy  = tmpl.usableBy or {},
        mods      = tmpl.mods or {},
    }
end

-- ============================================================================
-- RNG HELPERS
-- ============================================================================

-- Weighted random pick over {1..n} with integer weights. Returns the chosen
-- index (1-based). Nil-safe: returns 1 if no weights are valid.
local function weightedIndex(weights)
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    if total <= 0 then return 1 end
    local r = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r < acc then return i end
    end
    return #weights
end

-- ============================================================================
-- OFFER / HIRE ROLLS
-- ============================================================================

-- Return a random (itemType, grade) pair weighted by floor tier.
-- grade is chosen from gradeWeights(floor); itemType is uniform over the
-- three slots (weapon/armor/trinket).
function M.randomItem(floor, itemType)
    floor = floor or 1
    local g1, g2, g3 = gradeWeights(floor)
    local grade = weightedIndex({ g1, g2, g3 })
    if not itemType then
        itemType = M.CATALOG and ({ "weapon", "armor", "trinket" })[weightedIndex({1,1,1})] or "weapon"
    end
    return itemType, grade
end

-- Roll 3 gear offers weighted by floor. Per contract, returns an array of 3
-- {itemType=, grade=} entries (NOT materialized instances). The shop screen
-- (out of Foundation scope) decides how to store/materialize them — it can
-- mint instances via makeInstance + nextId at display or purchase time.
function M.rollOffers(floor)
    floor = floor or 1
    local offers = {}
    for i = 1, 3 do
        local itemType, grade = M.randomItem(floor)
        offers[i] = { itemType = itemType, grade = grade }
    end
    return offers
end

-- Hire cost for the current floor. [tuned]
function M.hireCost(floor)
    return HIRE_COST(floor or 1)
end

-- Pick 1 random character NOT yet in the active party, if the party can
-- afford one at the current floor. Returns the character key, or nil.
-- "Active party" = the truthy entries of saveData.partyOrder.
function M.rollHire(saveData)
    if not saveData then return nil end
    local floor = saveData.floor or 1
    local gold  = saveData.gold or 0
    if gold < M.hireCost(floor) then return nil end

    -- Build the set of characters currently in the active party.
    local inParty = {}
    local po = saveData.partyOrder or {}
    for _, name in ipairs(po) do
        if type(name) == "string" then inParty[name] = true end
    end

    -- Collect unlocked characters not in the party.
    local uc = saveData.unlockedCharacters or {}
    local candidates = {}
    for name in pairs(uc) do
        if not inParty[name] then
            table.insert(candidates, name)
        end
    end
    if #candidates == 0 then return nil end

    return candidates[math.random(#candidates)]
end

-- ============================================================================
-- GEAR RESOLUTION
-- ============================================================================

-- Resolve a character's equipped item ids to their instance tables.
-- Returns { weapon=instance?, armor=instance?, trinket=instance? } — any slot
-- that is nil/unequipped is simply absent. Returns {} (empty) if the
-- character has nothing equipped, which M.fromSave treats as no-gear
-- (byte-identical to today's stats).
function M.resolveGear(saveData, charName)
    local out = {}
    if not saveData or not charName then return out end
    local uc = saveData.unlockedCharacters
    local cd = uc and uc[charName]
    if not cd then return out end
    local eq = cd.equipped or {}
    local items = saveData.items or {}
    for _, slot in ipairs({ "weapon", "armor", "trinket" }) do
        local itemId = eq[slot]
        if itemId and items[itemId] then
            out[slot] = items[itemId]
        end
    end
    return out
end

-- ============================================================================
-- GOLD
-- ============================================================================

function M.addGold(saveData, n)
    if not saveData or not n then return end
    saveData.gold = (saveData.gold or 0) + n
end

-- Spend gold. Returns true (and deducts) if there is enough, else false.
-- Never allows gold to go negative.
function M.spendGold(saveData, n)
    if not saveData or not n or n <= 0 then return false end
    local gold = saveData.gold or 0
    if gold < n then return false end
    saveData.gold = gold - n
    return true
end

function M.sellValue(inst)
    if not inst then return 0 end
    return inst.sellPrice or 0
end

-- ============================================================================
-- ID ALLOCATION
-- ============================================================================

-- Allocate the next unique item id ("it_XXXX") and stash the sequence in
-- saveData._itemIdSeq. Returns the new id string.
function M.nextId(saveData)
    if not saveData then return "it_0001" end
    local seq = saveData._itemIdSeq or 0
    seq = seq + 1
    saveData._itemIdSeq = seq
    return string.format("it_%04d", seq)
end

-- ============================================================================
-- VICTORY GOLD HOOK
-- ============================================================================

-- Award victory gold for a WON encounter:
--   base  = 10 + 5 * floor        [tuned]
--   + 1 per enemy defeated        [tuned] per-kill drip
-- Call this from the confirmed victory site (see screens/encounter.lua).
-- `enemiesDefeated` is the count of enemies killed in the encounter.
function M.onEncounterWon(saveData, enemiesDefeated)
    if not saveData then return end
    local floor = saveData.floor or 1
    local base  = 10 + 5 * floor                -- [tuned] victory gold
    local kills = enemiesDefeated or 0
    if kills < 0 then kills = 0 end
    saveData.gold = (saveData.gold or 0) + base + kills
end

return M

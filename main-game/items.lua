-- items.lua — items, gold and the shop's stock rules.
--
-- The item CATALOG is Battleheart's (data/bh_items.lua, generated from the
-- game's own table). An owned item is an INSTANCE stored in the save:
--
--   saveData.items[instanceId] = {
--       id        = "it_0007",          -- unique per save (M.nextId)
--       bhId      = 10,                 -- row in data/bh_items.lua
--       itemType  = "weapon" | "armor" | "trinket",
--       name, desc,
--       grade     = 1..3,               -- colour band for the UI (from loot tier)
--       value     = 60,                 -- shop buy price
--       sellPrice = 30,                 -- what selling it pays (half, BH rule)
--       usableBy  = { "knight", ... },  -- class keys; {} = everyone
--       mods      = { ATK = 21 },       -- flat stats it adds when equipped
--   }
--   saveData.inventory = { instanceId, ... }      -- carried, unequipped items
--   saveData.unlockedCharacters[name].equipped = { weapon=, armor=, trinket= }  -- instance ids
--
-- Weapons add their power to ATK, armor to DEF. Trinkets add to whatever their
-- BH effect says — but only effects in TRINKET_STATS are implemented, and the
-- shop never stocks a trinket whose effect is not.

local bh = require("data/bh_items")

local M = {}

-- Trinket effect -> the stat `power` is added to (and a scale factor).
local TRINKET_STATS = {
    power   = { stat = "ATK",  mult = 1 },
    defense = { stat = "DEF",  mult = 1 },
    crit    = { stat = "CRIT", mult = 0.01 },   -- BH crit is in percent, CR's is 0..1
}

local function modsFor(row)
    if row.type == "weapon" then return { ATK = row.power } end
    if row.type == "armor"  then return { DEF = row.power } end
    local t = TRINKET_STATS[row.effect]
    return t and { [t.stat] = row.power * t.mult } or {}
end

-- True if the game can actually apply this catalog row's effect.
local function supported(row)
    return row and (row.type ~= "trinket" or TRINKET_STATS[row.effect] ~= nil)
end

-- ============================================================================
-- INSTANCES
-- ============================================================================

-- Allocate the next unique instance id ("it_0001", ...).
function M.nextId(saveData)
    local seq = (saveData._itemIdSeq or 0) + 1
    saveData._itemIdSeq = seq
    return string.format("it_%04d", seq)
end

-- Build an instance of catalog item `bhId`. Does not store it anywhere.
function M.makeInstance(id, bhId)
    local row = bh.ITEMS[bhId]
    if not row then return nil end
    local tier = row.tier or 9
    return {
        id        = id,
        bhId      = bhId,
        itemType  = row.type,
        name      = row.name,
        desc      = row.desc,
        grade     = (tier <= 3) and 1 or (tier <= 6) and 2 or 3,
        value     = row.price,
        sellPrice = math.floor(row.price / 2),
        usableBy  = row.usableBy or {},
        mods      = modsFor(row),
    }
end

-- Create an instance of `bhId`, store it in the save and return its id.
function M.mint(saveData, bhId)
    local id = M.nextId(saveData)
    local inst = M.makeInstance(id, bhId)
    if not inst then return nil end
    saveData.items[id] = inst
    return id
end

function M.buyPrice(inst)  return inst and inst.value or 0 end
function M.sellValue(inst) return inst and inst.sellPrice or 0 end

-- May the character class `charName` equip this instance? (BH usableBy rule)
function M.canUse(inst, charName)
    local users = inst and inst.usableBy
    if not users or #users == 0 then return true end
    for _, c in ipairs(users) do
        if c == charName then return true end
    end
    return false
end

-- A character's equipped instances: { weapon = inst?, armor = inst?, trinket = inst? }.
function M.resolveGear(saveData, charName)
    local out = {}
    local rec = saveData and saveData.unlockedCharacters and saveData.unlockedCharacters[charName]
    if not rec then return out end
    for slot, id in pairs(rec.equipped or {}) do
        out[slot] = saveData.items and saveData.items[id]
    end
    return out
end

-- Give a character the starter weapon + armor of its class (data/classes.lua),
-- equipped. Used for a new game's party and for new recruits.
function M.equipStarterGear(saveData, charName)
    local def = require("data/classes").CLASSES[charName]
    local rec = saveData.unlockedCharacters[charName]
    if not (def and def.starterGear and rec) then return end
    rec.equipped = rec.equipped or {}
    for i, slot in ipairs({ "weapon", "armor" }) do
        if not rec.equipped[slot] and def.starterGear[i] then
            rec.equipped[slot] = M.mint(saveData, def.starterGear[i])
        end
    end
end

-- ============================================================================
-- GOLD
-- ============================================================================

function M.addGold(saveData, n)
    saveData.gold = (saveData.gold or 0) + n
end

-- Deducts and returns true if there is enough gold; otherwise returns false.
function M.spendGold(saveData, n)
    if not n or n <= 0 then return false end
    local gold = saveData.gold or 0
    if gold < n then return false end
    saveData.gold = gold - n
    return true
end

-- ============================================================================
-- INVENTORY
-- ============================================================================

-- How many unequipped items the party can carry (the grid on the EQUIP and SHOP
-- screens is 7 x 5). BH's backpack holds 20.                          [tuned]
M.INVENTORY_SIZE = 35

function M.inventoryFull(saveData)
    return #(saveData.inventory or {}) >= M.INVENTORY_SIZE
end

-- True if catalog item `bhId` exists and the game can apply its effect.
function M.isSupported(bhId)
    return supported(bh.ITEMS[bhId]) and true or false
end

-- ============================================================================
-- SHOP STOCK  (BH: Database.populateMerchant — bh/systems/effects-database-pets-misc.md B.6)
-- ============================================================================

M.SHOP_SLOTS = 6   -- BH has 8 slots; the Director asked for about 6

-- Loot tables whose level range contains `level` (the party's best hero).
local function eligibleTables(level)
    local out = {}
    for _, t in ipairs(bh.LOOT_TABLES) do
        if level >= t.minLevel and level <= t.maxLevel then out[#out + 1] = t end
    end
    return out
end

-- Roll the shop's stock: 3..SHOP_SLOTS catalog ids. Each is an independent
-- draw - a random eligible table, then a random item of it - so duplicates can
-- happen, exactly as in BH. Trinkets the game cannot apply yet are re-rolled.
function M.rollOffers(level)
    local tables = eligibleTables(level or 1)
    local offers = {}
    if #tables == 0 then return offers end
    for _ = 1, math.random(3, M.SHOP_SLOTS) do
        for _ = 1, 20 do
            local t = tables[math.random(#tables)]
            local bhId = t.items[math.random(#t.items)]
            if supported(bh.ITEMS[bhId]) then offers[#offers + 1] = bhId; break end
        end
    end
    return offers
end

return M

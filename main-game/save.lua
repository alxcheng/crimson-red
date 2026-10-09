-- save.lua — save slots (JSON files in LÖVE's save directory).
--
-- saveData = {
--   floor       = 1,                       -- current floor (difficulty / reward tier)
--   gold        = 0,
--   partyOrder  = { name|false x4 },       -- the active party, by slot
--   unlockedCharacters = { [name] = {      -- every hero in the game
--       recruited = bool,                  -- owned (shown in PARTY); else hireable
--       level, pointsToNextLevel,          -- progression.lua
--       equipped  = { weapon=, armor=, trinket= },   -- item instance ids
--       skillTree = { optionId, ... },     -- talent picks (data/talents.lua)
--   } },
--   items       = { [instanceId] = instance },   -- every owned item (items.lua)
--   inventory   = { instanceId, ... },           -- carried, unequipped items
--   shopState   = { offers = {instanceId..}, hireOffer = name|nil, seeded, pendingRestock },
--   mapProgression = { playerCol, playerRow, revealedTiles, clearedEncounters },
-- }
-- Stats are NOT saved; progression.heroStats derives them.

local M   = {}
local json = require("json")

local ALL_CHARACTERS = {
    "knight", "champion", "duelist", "hunter", "jester", "nomad", "piper", "witch",
    "cleric", "paladin", "wizard", "rogue",
}
-- A new game starts with BH's opening pair: a tank and a healer.
local STARTING_PARTY = { "knight", "cleric" }

local function filename(slot)
    return "save_" .. slot .. ".json"
end

function M.exists(slot)
    return love.filesystem.getInfo(filename(slot)) ~= nil
end

local function defaultShopState()
    return { offers = {}, hireOffer = nil, seeded = false }
end

-- Bring a save written by an older version up to the current shape.
local function migrate(data)
    data.floor     = data.floor or 1
    data.gold      = data.gold or 0
    data.items     = data.items or {}
    data.inventory = data.inventory or {}
    data.shopState = data.shopState or defaultShopState()
    data.unlockedCharacters = data.unlockedCharacters or {}

    -- Before recruiting existed every character was usable: keep them all.
    local hasFlag = false
    for _, rec in pairs(data.unlockedCharacters) do
        if rec.recruited ~= nil then hasFlag = true end
    end
    for _, rec in pairs(data.unlockedCharacters) do
        if not hasFlag then rec.recruited = true end
        rec.stats = nil                       -- stats are derived now
        rec.equipped = rec.equipped or {}
        if type(rec.skillTree) ~= "table" then rec.skillTree = {} end
    end

    -- Items from before the Battleheart catalog have no bhId and cannot be
    -- interpreted any more: drop them (and any reference to them).
    for id, inst in pairs(data.items) do
        if type(inst) ~= "table" or not inst.bhId then data.items[id] = nil end
    end
    local kept = {}
    for _, id in ipairs(data.inventory) do
        if data.items[id] then kept[#kept + 1] = id end
    end
    data.inventory = kept
    for _, rec in pairs(data.unlockedCharacters) do
        for slot, id in pairs(rec.equipped) do
            if not data.items[id] then rec.equipped[slot] = nil end
        end
    end
    local offers = {}
    for _, id in ipairs(data.shopState.offers or {}) do
        if data.items[id] then offers[#offers + 1] = id end
    end
    data.shopState.offers = offers
    return data
end

function M.load(slot)
    local raw = love.filesystem.read(filename(slot))
    if not raw then return nil end
    local ok, data = pcall(json.decode, raw)
    if not (ok and type(data) == "table") then return nil end
    return migrate(data)
end

function M.write(slot, data)
    local ok, err = love.filesystem.write(filename(slot), json.encode(data))
    if not ok then print("[save] write error:", err) end
end

function M.delete(slot)
    love.filesystem.remove(filename(slot))
end

function M.defaultData()
    local progression = require("progression")
    local items       = require("items")
    local data = {
        floor = 1,
        gold  = 15,   -- BH starting gold
        partyOrder = { false, false, false, false },
        unlockedCharacters = {},
        items = {},
        inventory = {},
        shopState = defaultShopState(),
        mapProgression = {
            playerCol         = 9,
            playerRow         = 5,
            revealedTiles     = {{9, 5}},
            clearedEncounters = {},
        },
    }
    for _, name in ipairs(ALL_CHARACTERS) do
        data.unlockedCharacters[name] = {
            recruited         = false,
            level             = 1,
            pointsToNextLevel = progression.xpToNext(1),
            equipped          = {},
            skillTree         = {},
        }
    end
    for i, name in ipairs(STARTING_PARTY) do
        data.unlockedCharacters[name].recruited = true
        data.partyOrder[i] = name
        items.equipStarterGear(data, name)
    end
    return data
end

return M

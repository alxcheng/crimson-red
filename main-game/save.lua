-- save.lua — save slot I/O using love.filesystem + JSON

local M   = {}
local json = require("json")

local function filename(slot)
    return "save_" .. slot .. ".json"
end

function M.exists(slot)
    return love.filesystem.getInfo(filename(slot)) ~= nil
end

function M.load(slot)
    local raw = love.filesystem.read(filename(slot))
    if not raw then return nil end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then
        -- Floor was added after the initial save format: old saves lack it,
        -- so normalize to 1 so consumers never see a nil floor.
        data.floor = data.floor or 1
    end
    return ok and data or nil
end

function M.write(slot, data)
    local ok, err = love.filesystem.write(filename(slot), json.encode(data))
    if not ok then print("[save] write error:", err) end
end

function M.delete(slot)
    love.filesystem.remove(filename(slot))
end

local DEFAULT_STATS = {
    ATK=10, DEF=5, maxHP=100, SPD=80, ATKSPD=2.0,
    CRIT=0.10, CRITDEF=0.05, RES=1.0, BOOST=1.0,
    WGT=0, STR=0, maxSTAGGER=50, STAGGERdur=10, STAGGERres=1.0,
}

local function defaultChar()
    return {
        level             = 1,
        pointsToNextLevel = 100,
        stats             = DEFAULT_STATS,
        equipped          = {},
        skillTree         = {1, 1, 1, 1, 1},
    }
end

function M.defaultData()
    return {
        floor = 1,
        partyOrder = {"knight", false, false, false},
        unlockedCharacters = {
            knight   = defaultChar(),
            champion = defaultChar(),
            duelist  = defaultChar(),
            hunter   = defaultChar(),
            jester   = defaultChar(),
            nomad    = defaultChar(),
            piper    = defaultChar(),
            witch    = defaultChar(),
        },
        inventory = {},
        mapProgression = {
            playerCol         = 9,
            playerRow         = 5,
            revealedTiles     = {{9, 5}},
            clearedEncounters = {},
        },
    }
end

return M

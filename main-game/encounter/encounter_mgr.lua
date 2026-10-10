-- encounter/encounter_mgr.lua — spawns a battle's enemies, wave by wave.
--
-- This is Battleheart's spawner (MotherBrain.enemySpawn — see
-- bh/systems/battle-director-setup-input-spawning.md section 9). A battle is a
-- list of WAVES; each wave is
--   { initialDelay = s, spawnDelay = s, maxEnemies = n, enemies = { enemyId, ... } }
-- and the rules are:
--   * a wave's first enemy appears `initialDelay` seconds after the wave starts;
--   * its enemies appear one at a time, in list order, `spawnDelay` seconds apart;
--   * never more than `maxEnemies` alive at once — and the timer does NOT run
--     while the field is full, so the rest of the delay still has to pass after
--     a kill frees a place;
--   * the next wave starts once every enemy of this one has been spawned AND killed;
--   * the battle is won when the last wave is finished and a hero is still alive.
-- The waves themselves come from encounter/wave_gen.lua.
--
--   M.new(waves, firstDelay)  -> the manager state kept in battle.encounterMgr
--   M.system(world, battle, dt, VW, VH)   call once per frame
--   M.checkVictory(world, battle)
--   M.checkDefeat(world, battle)

local entities_mod = require("encounter/entities")
local enemies      = require("data/enemies")

local M = {}

-- firstDelay (optional) replaces the first wave's initialDelay (tests use it).
function M.new(waves, firstDelay)
    local first = waves[1]
    return {
        waves         = waves,
        currentWave   = 1,
        wavePosition  = 1,                                   -- next entry of the wave's `enemies`
        spawnDelay    = firstDelay or (first and first.initialDelay) or 0,
        spawnCooldown = first and first.spawnDelay or 0,
        maxEnemies    = first and first.maxEnemies or 0,
        done          = #waves == 0,                         -- every wave spawned and killed
    }
end

local function livingEnemies(world)
    local n = 0
    for id in pairs(world.entities) do
        local sd = world.side[id]
        if sd and sd.s == 1 and not world.deathState[id] then n = n + 1 end
    end
    return n
end

-- Where a new enemy appears (x, y = its centre). BH spawningStyle 1 / 4 / 2-3.
local function spawnPoint(def, VW, VH)
    local y = VH * (0.32 + 0.45 * math.random())
    if def.spawn == "inside" then
        return VW * (0.15 + 0.70 * math.random()), y
    elseif def.spawn == "left" then
        return -60, y
    end
    return VW + 60, y
end

function M.system(world, battle, dt, VW, VH)
    -- Units that appeared inside the arena fade in over ~0.7 s (BH colorSpeed 1.5).
    for id, f in pairs(world.spawnFade) do
        f = f + 1.5 * dt
        world.spawnFade[id] = (f < 1) and f or nil
    end

    local mgr = battle.encounterMgr
    if not mgr or mgr.done then return end
    local wave   = mgr.waves[mgr.currentWave]
    local active = livingEnemies(world)

    if mgr.spawnDelay > 0 then
        if active < mgr.maxEnemies then mgr.spawnDelay = mgr.spawnDelay - dt end
        return
    end

    if mgr.wavePosition > #wave.enemies and active == 0 then
        -- Wave cleared: start the next one.
        mgr.currentWave  = mgr.currentWave + 1
        mgr.wavePosition = 1
        local nextWave = mgr.waves[mgr.currentWave]
        if nextWave then
            mgr.spawnDelay    = nextWave.initialDelay
            mgr.maxEnemies    = nextWave.maxEnemies
            mgr.spawnCooldown = nextWave.spawnDelay
        else
            mgr.done = true
        end
    elseif active < mgr.maxEnemies and mgr.wavePosition <= #wave.enemies then
        -- Spawn one enemy, then wait spawnDelay before the next.
        local enemyId = wave.enemies[mgr.wavePosition]
        local def = enemies.ENEMIES[enemyId]
        if def then
            local x, y = spawnPoint(def, VW, VH)
            entities_mod.createEnemy(world, battle, enemyId, x, y)
        end
        mgr.wavePosition = mgr.wavePosition + 1
        mgr.spawnDelay   = mgr.spawnCooldown
    end
end

local function livingHeroes(world, battle)
    local n = 0
    for _, pid in ipairs(battle.partyIds) do
        -- (a dead hero's entity is destroyed after its death animation)
        if world.entities[pid] and not world.deathState[pid] then n = n + 1 end
    end
    return n
end

function M.checkVictory(world, battle)
    local mgr = battle.encounterMgr
    if not (mgr and mgr.done) or livingEnemies(world) > 0 then return false end
    return livingHeroes(world, battle) > 0
end

-- BH: the defeat sequence starts the moment the last hero dies.
function M.checkDefeat(world, battle)
    return #battle.partyIds > 0 and livingHeroes(world, battle) == 0
end

return M

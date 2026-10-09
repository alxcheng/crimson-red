-- encounter/encounter_mgr.lua — Wave spawning and encounter management

local entities_mod = require("encounter/entities")
local enemies      = require("data/enemies")

local M = {}

-- ============================================================================
-- WAVE SPAWNING
-- ============================================================================

function M.queueWave(battle, isSurprise)
    local mgr = battle.encounterMgr
    if mgr.pendingWave then return end
    if not isSurprise and mgr.dangerDefeated >= mgr.encounterGoal then return end
    local budget = math.random(mgr.waveMinThreat, mgr.waveMaxThreat)
    mgr.pendingWave = { timer = 3.0, budget = budget }
end

-- Spend the pending wave's danger budget on enemies and spawn them off the
-- right edge of the screen.
function M.flushPendingWave(world, battle, VW, VH)
    local mgr = battle.encounterMgr
    local pw  = mgr.pendingWave
    local enemyId = enemies.SPAWN_POOL[1]
    local cost    = enemies.ENEMIES[enemyId].danger
    local count = 0
    while pw.budget >= cost do
        local spawnX = VW + 400 + count * 120 + math.random(0, 80)
        local spawnY = VH * 0.35 + count * 80
        entities_mod.createEnemy(world, battle, enemyId, spawnX, spawnY)
        mgr.currentDanger = mgr.currentDanger + cost
        pw.budget = pw.budget - cost
        count     = count     + 1
    end
    mgr.pendingWave  = nil
    mgr.waveCooldown = 2.0
end

-- ============================================================================
-- ENCOUNTER MANAGER SYSTEM (runs each frame)
-- ============================================================================

function M.system(world, battle, dt, VW, VH)
    local mgr = battle.encounterMgr
    if mgr.spawnTimer > 0 then
        mgr.spawnTimer = mgr.spawnTimer - dt
        return
    end

    if mgr.pendingWave then
        mgr.pendingWave.timer = mgr.pendingWave.timer - dt
        if mgr.pendingWave.timer <= 0 then M.flushPendingWave(world, battle, VW, VH) end
    else
        mgr.waveCooldown = math.max(0, mgr.waveCooldown - dt)
        if mgr.waveCooldown == 0
           and mgr.currentDanger  < mgr.dangerThreshold
           and mgr.dangerDefeated < mgr.encounterGoal then
            M.queueWave(battle)
        end
    end

    mgr.surpriseTimer = mgr.surpriseTimer - dt
    if mgr.surpriseTimer <= 0 then
        mgr.surpriseTimer = mgr.surpriseInterval
        if mgr.dangerDefeated < mgr.encounterGoal and math.random() < mgr.surpriseChance then
            M.queueWave(battle, true)
        end
    end
end

-- ============================================================================
-- VICTORY CHECK
-- ============================================================================

function M.checkVictory(world, battle)
    local mgr = battle.encounterMgr
    if not mgr or mgr.dangerDefeated < mgr.encounterGoal then return false end
    local hasEnemy = false
    for id in pairs(world.entities) do
        local sd = world.side[id]
        if sd and sd.s == 1 and not world.deathState[id] then hasEnemy=true; break end
    end
    if not hasEnemy and #battle.partyIds > 0 then
        for _, pid in ipairs(battle.partyIds) do
            if not world.deathState[pid] then return true end
        end
    end
    return false
end

return M

-- encounter/entities.lua — builds battle units from the data tables.
--
--   M.createHero(world, battle, classId, x, y, saveStats, gear)  -> id | nil
--   M.createEnemy(world, battle, enemyId, x, y)                  -> id | nil
--
-- A unit is an id plus one entry in each `world.<component>` table (see the
-- component list in screens/encounter.lua initWorld). What a class or enemy IS
-- lives in data/classes.lua and data/enemies.lua; this file only assembles it.
-- x, y are the unit's CENTER in virtual pixels (feet = y + size.h / 2).

local stats_mod   = require("encounter/stats")
local anim_mod    = require("encounter/anim")
local effects_mod = require("encounter/effects")
local abilities   = require("encounter/abilities")
local classes     = require("data/classes")
local enemies     = require("data/enemies")

local M = {}

local SIDE_PARTY, SIDE_ENEMY = 0, 1

-- Components every unit has.
local function addBaseComponents(world, id, def, x, y, scale, side, st)
    world.position[id]     = {x = x, y = y}
    world.size[id]         = {w = def.size[1] * scale, h = def.size[2] * scale}
    world.facing[id]       = {right = side == SIDE_PARTY}
    world.physics[id]      = {vx = 0, vy = 0, fx = 0, fy = 0}
    world.moveTarget[id]   = {x = x, y = y, active = false}
    world.side[id]         = {s = side}
    -- Which side this unit's default action is aimed at.
    world.targetSide[id]   = def.targetsAllies and side or (1 - side)
    world.stats[id]        = st
    world.locks[id]        = {actionLock = 0, moveLock = 0}
    world.stagger[id]      = {points = 0, staggered = false, timer = 0}
    world.stun[id]         = {stunned = false, timer = 0}
    local tint = def.tint
    world.tintColor[id]    = {R = tint and tint[1] or 0, G = tint and tint[2] or 0, B = tint and tint[3] or 0}
    world.bar[id]          = {hpColor = side == SIDE_PARTY and {0, 1, 0} or {1, 1, 0}, hpPrevRatio = 1, timer = 0}
    world.effects_comp[id] = {pending = {}, active = {}}
    world.spriteOffset[id] = {x = 0, y = def.spriteOffsetY or 0}
    world.hasEntered[id]   = {h = false, v = false}
    if def.ranged then world.isRanged[id] = true end

    local set = classes.ANIM_SETS[def.anims]
    local list = {}
    for i, a in ipairs(set.list) do
        list[i] = anim_mod.newInst(set.sprite .. a[1], a[2], a[3] or false, a[4] or false)
    end
    world.anim[id] = {list = list}

    -- Slot 0 is the default action; slots 1..4 are the Q/W/E/R abilities.
    local skills = { [0] = abilities.make(def.auto, 0) }
    for slot, abilityId in ipairs(def.actives or {}) do
        skills[slot] = abilities.make(abilityId, slot)
    end
    world.skills[id] = {list = skills, queue = {}, abilityQueue = {}, execGate = 0}
end

-- saveStats: the character's saved stat table (save.lua), or nil to use the
-- class base stats. gear: equipped item instances (items.resolveGear), or nil.
function M.createHero(world, battle, classId, x, y, saveStats, gear)
    local def = classes.CLASSES[classId]
    if not def then return nil end
    local st
    if saveStats then
        st = stats_mod.fromSave(saveStats, gear)
    else
        local b = def.stats
        st = stats_mod.newStats(b.hp, b.atk, b.def, b.crit)
    end
    if def.moveSpeed then st.MOVE_SPEED.base = def.moveSpeed end

    local id = world:new()
    addBaseComponents(world, id, def, x, y, battle.SCALE, SIDE_PARTY, st)
    if def.drawsThreat then world.hasThreateningPresence[id] = true end
    if def.passive then
        table.insert(world.effects_comp[id].pending, effects_mod.PASSIVES[def.passive](id))
    end
    battle.selCircleScales[id] = 0
    return id
end

function M.createEnemy(world, battle, enemyId, x, y)
    local def = enemies.ENEMIES[enemyId]
    if not def then return nil end
    local b = def.stats
    local st = stats_mod.newStats(b.hp, b.atk, b.def, b.crit, b.atkSpeed)
    if def.moveSpeed then st.MOVE_SPEED.base = def.moveSpeed end

    local id = world:new()
    addBaseComponents(world, id, def, x, y, battle.SCALE, SIDE_ENEMY, st)
    world.threatMap[id]   = {map = {}, decayTimer = 0}
    world.dangerLevel[id] = def.danger

    -- Start by going after a random hero.
    if #battle.partyIds > 0 then
        local tgtId = battle.partyIds[math.random(#battle.partyIds)]
        world.entityTarget[id] = {id = tgtId}
        world.threatMap[id].map[tgtId] = 1
        local tp = world.position[tgtId]
        if tp then world.facing[id].right = (tp.x > x) end
    end
    return id
end

return M

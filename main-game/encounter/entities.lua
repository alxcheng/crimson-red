-- encounter/entities.lua — Entity creation functions with shared template

local stats_mod  = require("encounter/stats")
local anim_mod   = require("encounter/anim")
local skills_mod = require("encounter/skills")
local effects_mod = require("encounter/effects")
local abilities_mod = require("encounter/abilities")

local M = {}

-- ============================================================================
-- SHARED ENTITY TEMPLATE
-- ============================================================================

local function applyBaseComponents(world, id, x, y, w, h, side, st, opts)
    opts = opts or {}
    world.position[id]     = {x=x, y=y}
    world.size[id]         = {w=w, h=h}
    world.facing[id]       = {right = opts.faceRight ~= false}
    world.physics[id]      = {vx=0, vy=0, fx=0, fy=0}
    world.moveTarget[id]   = {x=x, y=y, active=false}
    world.side[id]         = {s=side}
    world.targetSide[id]   = opts.targetSide or (side == 0 and 1 or 0)
    world.stats[id]        = st
    world.locks[id]        = {actionLock=0, moveLock=0}
    world.stagger[id]      = {points=0, staggered=false, timer=0}
    world.stun[id]         = {stunned=false, timer=0}
    world.tintColor[id]    = {R=0, G=0, B=0}
    world.bar[id]          = {hpColor = opts.hpColor or {0, 1, 0}, hpPrevRatio=1, timer=0}
    world.effects_comp[id] = {pending={}, active={}}
    if world.spriteOffset  then world.spriteOffset[id]  = {x = opts.spriteOffsetX or 0, y = opts.spriteOffsetY or 0} end
    if world.hasAttacked   then world.hasAttacked[id]   = nil end
    if opts.isRanged then world.isRanged[id] = true end
end

-- ============================================================================
-- KNIGHT
-- ============================================================================

function M.createKnight(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(100, 10, 5, 0.10)
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st)
    world.anim[id] = {list={
        [1] = anim_mod.newInst("KnightIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("KnightMove",     6/60, true,  false),
        [3] = anim_mod.newInst("KnightAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("KnightAttack2", 12/60, false, false),
        [5] = anim_mod.newInst("KnightTakeHit",  6/60, false, false),
        [6] = anim_mod.newInst("KnightDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = {
            [0] = skills_mod.newKnightAutoAttackSkill(SCALE, GRAVITY),
            [1] = skills_mod.newKnightSunderArmorSkill(SCALE, GRAVITY),
            [2] = skills_mod.newKnightDefendSkill(),
            [3] = skills_mod.newKnightChallengingShoutSkill(),
        },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    -- Passives
    world.hasThreateningPresence[id] = true
    local ec = world.effects_comp[id]
    table.insert(ec.pending, effects_mod.newKnightRage(id))

    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- SKELETON
-- ============================================================================

function M.createSkeleton(world, battle, x, y, SCALE, GRAVITY, ENEMY_DANGER)
    local id = world:new()
    local st = stats_mod.newStats(80, 8, 3, 0.05, 2.5)
    st.MOVE_SPEED.base = 1.5
    applyBaseComponents(world, id, x, y, 40*SCALE, 40*SCALE, 1, st, {
        hpColor = {1, 1, 0},
        faceRight = false,
        targetSide = 1,
    })
    world.threatMap[id]   = {map={}, decayTimer=0}
    world.hasEntered[id]  = {h=false, v=false}
    world.dangerLevel[id] = ENEMY_DANGER.skeleton
    world.anim[id] = {list={
        [1] = anim_mod.newInst("SkeletonIdle",    8/60, true,  true),
        [2] = anim_mod.newInst("SkeletonMove",    8/60, true,  false),
        [3] = anim_mod.newInst("SkeletonAttack",  6/60, false, false),
        [4] = anim_mod.newInst("SkeletonDeath",   6/60, false, false),
    }}
    world.skills[id] = {list={[0]=skills_mod.newSkeletonAutoAttackSkill(SCALE, GRAVITY)}, queue={}, gcd=0}
    if #battle.partyIds > 0 then
        local tgtId = battle.partyIds[math.random(#battle.partyIds)]
        world.entityTarget[id] = {id=tgtId}
        world.threatMap[id].map[tgtId] = 1
        local sp, tp = world.position[id], world.position[tgtId]
        if sp and tp then world.facing[id].right = (tp.x > sp.x) end
    end
    return id
end

-- ============================================================================
-- BRIGAND
-- ============================================================================

function M.createBrigand(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(100, 10, 5, 0.10)
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st, {spriteOffsetY=5})
    world.anim[id] = {list={
        [1] = anim_mod.newInst("BrigandIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("BrigandMove",     6/60, true,  false),
        [3] = anim_mod.newInst("BrigandAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("BrigandDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = { [0] = skills_mod.newBrigandAutoAttackSkill(SCALE, GRAVITY) },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- CHAMPION
-- ============================================================================

function M.createChampion(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(100, 10, 5, 0.10)
    applyBaseComponents(world, id, x, y, 32*SCALE, 52*SCALE, 0, st, {spriteOffsetY=-35})
    world.anim[id] = {list={
        [1] = anim_mod.newInst("ChampionIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("ChampionMove",     6/60, true,  false),
        [3] = anim_mod.newInst("ChampionAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("ChampionDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = { [0] = skills_mod.newChampionAutoAttackSkill(SCALE, GRAVITY) },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- DUELIST
-- ============================================================================

function M.createDuelist(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(100, 10, 5, 0.10)
    applyBaseComponents(world, id, x, y, 27.6*SCALE, 41.88*SCALE, 0, st)
    world.anim[id] = {list={
        [1] = anim_mod.newInst("DuelistIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("DuelistMove",     6/60, true,  false),
        [3] = anim_mod.newInst("DuelistAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("DuelistDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = { [0] = skills_mod.newDuelistAutoAttackSkill(SCALE, GRAVITY) },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- NOMAD
-- ============================================================================

function M.createNomad(world, battle, x, y, saveStats, SCALE, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(80, 8, 2, 0.05)
    applyBaseComponents(world, id, x, y, 29.43*SCALE, 38.97*SCALE, 0, st, {isRanged=true, targetSide=0, spriteOffsetY=-18})
    world.anim[id] = {list={
        [1] = anim_mod.newInst("NomadIdle",    8/60, true,  true),
        [2] = anim_mod.newInst("NomadMove",    8/60, true,  false),
        [3] = anim_mod.newInst("NomadAttack1", 6/60, false, false),
        [4] = anim_mod.newInst("NomadAttack2", 6/60, false, false),
        [5] = anim_mod.newInst("NomadDeath",   6/60, false, false),
    }}
    world.skills[id] = {
        list  = {
            [0] = skills_mod.newNomadAutoHealSkill(SCALE),
            [1] = skills_mod.newNomadGrantPowerSkill(),
            [2] = skills_mod.newNomadMendWoundsSkill(),
            [3] = skills_mod.newNomadSparkOfInspirationSkill(),
        },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- PROOF-OF-PORT CLASSES (Cleric / Paladin / Wizard / Rogue)
--
-- Data-driven: stats come from the class-port spec
-- (work/class-port-spec-cleric-paladin-wizard-rogue.md), abilities are wired
-- via abilities_mod.make(dbId) + _slot stamping. All four REUSE THE KNIGHT
-- anim frame set ("recolor" = a persistent world.tintColor, set below — no
-- new frames). Stats fall back to the spec bases unless saveStats is passed
-- (matches createKnight's `saveStats and ... or ...` pattern).
-- ============================================================================

local function buildClassSkills(classSet)
    local list = {}
    if classSet.auto then
        local s = abilities_mod.make(classSet.auto); s._slot = 0; list[0] = s
    end
    for i, aid in ipairs(classSet.actives) do
        local s = abilities_mod.make(aid); s._slot = i; list[i] = s
    end
    return list
end

-- The shared Knight anim frame set, reused verbatim for all four classes.
local function knightAnimSet()
    return {list={
        [1] = anim_mod.newInst("KnightIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("KnightMove",     6/60, true,  false),
        [3] = anim_mod.newInst("KnightAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("KnightAttack2", 12/60, false, false),
        [5] = anim_mod.newInst("KnightTakeHit",  6/60, false, false),
        [6] = anim_mod.newInst("KnightDeath",    6/60, false, false),
    }}
end

-- CLERIC (Lucille) — support, NO melee auto (default action is the auto-heal).
-- Spec §1.2: maxHP 300 [tuned], DEF 9 [wiki], ATK 16 [wiki], CRIT 0, MOVE_SPEED 3.0 [tuned].
function M.createCleric(world, battle, x, y, saveStats, SCALE, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(300, 16,  9, 0.0)
    st.MOVE_SPEED.base = 3.0
    -- Ranged support (mirrors the Nomad): isRanged=true so the Cleric never
    -- has to pass the melee-range gate for its auto-heal — it faces its target
    -- and heals at range. targetSide=0: its auto-heal targets its own side
    -- (allies); the heal recipient is read from entityTarget (the selected ally).
    applyBaseComponents(world, id, x, y, 29.43*SCALE, 38.97*SCALE, 0, st, {isRanged=true, targetSide=0})
    world.tintColor[id] = {R=1, G=0.85, B=0.2}   -- recolor: yellow
    world.anim[id] = knightAnimSet()
    world.skills[id] = {
        list  = buildClassSkills(abilities_mod.CLASS_SETS.cleric),
        queue = {}, abilityQueue = {}, execGate = 0,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- PALADIN (Heleth) — tank/hybrid, HAS melee auto + draws aggro.
-- Spec §2.2: maxHP 520 [tuned], DEF 24 [wiki Lv5], ATK 24 [wiki], CRIT 0, MOVE_SPEED 2.8 [tuned].
function M.createPaladin(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(520, 24, 24, 0.0)
    st.MOVE_SPEED.base = 2.8
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st)
    world.tintColor[id] = {R=0.4, G=1, B=0.4}    -- recolor: green
    world.anim[id] = knightAnimSet()
    world.skills[id] = {
        list  = buildClassSkills(abilities_mod.CLASS_SETS.paladin),
        queue = {}, abilityQueue = {}, execGate = 0,
    }
    world.hasThreateningPresence[id] = true      -- tank: hits draw aggro
    battle.selCircleScales[id] = 0
    return id
end

-- WIZARD (Bromswell) — ranged DPS, isRanged=true, auto-fires fireballs.
-- Spec §3.2: maxHP 260 [tuned], DEF 5 [wiki], ATK 28 [inferred], CRIT 0, MOVE_SPEED 3.2 [tuned].
function M.createWizard(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(260, 28, 5, 0.0)
    st.MOVE_SPEED.base = 3.2
    applyBaseComponents(world, id, x, y, 29.43*SCALE, 38.97*SCALE, 0, st, {isRanged=true, targetSide=1})
    world.tintColor[id] = {R=1, G=0.5, B=0.9}    -- recolor: pink
    world.anim[id] = knightAnimSet()
    world.skills[id] = {
        list  = buildClassSkills(abilities_mod.CLASS_SETS.wizard),
        queue = {}, abilityQueue = {}, execGate = 0,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ROGUE (Gustav) — melee burst DPS, fastest swing. Crit base 0.20 [wiki Critical Strikes].
-- Spec §4.2: maxHP 300 [tuned], DEF 11 [wiki avg 9–13], ATK 31 [wiki Lv1 bare], CRIT 0.20, MOVE_SPEED 3.4 [tuned].
function M.createRogue(world, battle, x, y, saveStats, SCALE, GRAVITY, gear)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats, gear) or stats_mod.newStats(300, 31, 11, 0.20)
    st.MOVE_SPEED.base = 3.4
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st)
    world.tintColor[id] = {R=0.63, G=0.09, B=0.14}  -- recolor: dark-crimson #a01824
    world.anim[id] = knightAnimSet()
    world.skills[id] = {
        list  = buildClassSkills(abilities_mod.CLASS_SETS.rogue),
        queue = {}, abilityQueue = {}, execGate = 0,
    }
    battle.selCircleScales[id] = 0
    return id
end

return M

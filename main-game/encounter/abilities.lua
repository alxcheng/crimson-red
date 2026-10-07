-- encounter/abilities.lua — Data-driven ability definitions + effect resolver
--
-- Battleheart-style data-driven ability layer, adapted to CR's existing
-- animation/timing pipeline (anim-lock + timed-action). This module does NOT
-- touch anim.lua or change how animations play; it defines ABILITY DATA and
-- interprets it through the same effects_mod / combat / status primitives the
-- hand-coded closures used before.
--
-- Adding a new class/skill = add a row to M.DB (data), no new closure needed
-- for the common shapes (damage / status / heal / threat / aoe).
--
-- Public:
--   M.DB[abilityId]          — definition table (see below)
--   M.make(id)               — skill-instance shell for sk.list[slot]
--   M.execute(world,battle,casterId,targetId,def) — fire the defined effect
--   M.resolveEffect(world,battle,def,srcId,tgtId) — interpret inner effect data
--   M.applyAoE(world,battle,cx,cy,radius,def)     — AoE resolver (center-based)
--
-- Definition fields:
--   name        : string  display name
--   role        : string  informational ("tank"/"support"/"dps"/...)
--   targetType  : "single" | "self" | "aoe" | "ally"
--   cdMax       : number  per-ability cooldown (seconds)
--   resourceCost: number  paid IMMEDIATELY at press (queueing model)
--   animLock    : number  moveLock (seconds) applied to side-0 casters
--   animListIdx : number  ac.list[N] slot to trigger for the cast animation
--   iconName    : string  skill icon name (UI)
--   iconScale   : number  icon scale (UI)
--   noTargetRequired : bool  true = self-cast, no entityTarget needed
--   effect      : effect spec — a pure data table interpreted by the resolver
--                 kinds listed below. (There is NO custom/fn closure form.)
--
-- Inner-effect kinds (M.resolveEffect) — ALL declarative data, no closures:
--   { kind="damage", tags?, vfx?, buffMods?, ability? }
--       ability = { aimedShot=bool, falloff=number, canCrit=bool }
--       buffMods = { [0]=fraction } — explicit outgoing multiplier (e.g. Sneak Attack)
--       chain    = { count=N, decay=d, radius=R? } — after hitting the primary,
--                  hit up to N further living enemies nearest to the primary,
--                  each for (decay^i)*primary damage [Paladin Wrath]
--       knockback= { force=F }      — add a world.physics force pushing the
--                  victim away from the caster [Thunderbolt / Vengeful Angel]
--   { kind="status", isBuff=bool, index=status.<NAME>, magnitude?, duration?,
--                    tint?={r,g,b,speed} }
--       index may be a NUMBER (status constant) or a STRING name ("SLOW") —
--       resolved through M._statusIndex so in-flight indices degrade gracefully.
--   { kind="effects", effects={ <inner>, <inner>, ... } }
--       apply a LIST of inner effects to the SAME target, in order [Divine
--       Intervention WARD+REFLECT, Conflagrate DOT+STUN, Poisoned Knife
--       damage+DOT].
--   { kind="heal", value=number }                     — heal one target
--   { kind="healGroup", value=number }                — heal every living ally
--                                                          (side 0) [Cleric Group Heal]
--   { kind="healLowestAlly", value=number }           — heal the most-injured
--                                                          living ally [Holy Word]
--   { kind="threat", flat=number }                    — threat to all enemies
--   { kind="resourceGain", amount=number }            — grant resource to caster
--   { kind="drainHp", fraction=number }               — drain a fraction of the
--                                                          target's current HP
--   { kind="stunAll", seconds=number }                — stun every living enemy
--                                                          [Time Stop]
--   { kind="aoe", radius=number, centerSelf?=bool, inner=<inner spec>,
--                  alsoStatus={<status>}, alsoKnockback={force=} }
--       centerSelf=true centers the AoE on the CASTER instead of the target
--       [Thunderbolt, Vengeful Angel]; alsoStatus applies an extra status to
--       every unit the inner effect touches [Blizzard SLOW]; alsoKnockback
--       adds a push-away force to every hit unit.
--
-- NOTE: there is NO kind="custom" / fn closure anywhere in M.DB. Every ability
-- is a plain data row interpreted by the branches below.

local combat  = require("encounter/combat")
local status  = require("encounter/status")
local effects_mod = require("encounter/effects")
local stats_mod = require("encounter/stats")

local statGet = stats_mod.get

local M = {}

-- ============================================================================
-- SHARED TARGET HELPERS (used by the data-driven resolver kinds)
--
-- NOTE ON IN-FLIGHT STATUS INDICES: status.SHIELD / SLOW / DOT / PARALYZE are
-- resolved BY NAME at call time (M._statusIndex), so an index added later
-- resolves as soon as it exists — no load-order coupling, and a missing index
-- simply no-ops rather than crashing.
-- ============================================================================

local function livingOfSide(world, sideVal)
    local out = {}
    for eid in pairs(world.entities) do
        local sd = world.side[eid]
        if sd and sd.s == sideVal and not world.deathState[eid] then out[#out+1] = eid end
    end
    return out
end

-- Lowest-current-HP living ally of srcId (for Holy Word "seek out the wounded").
local function lowestHpAlly(world, srcId)
    local best, bestRatio = nil, math.huge
    for _, eid in ipairs(livingOfSide(world, 0)) do
        local ss = world.stats[eid]
        if ss then
            local cur, maxHp = statGet(ss.HP), statGet(ss.maxHP)
            local ratio = maxHp > 0 and (cur / maxHp) or 1
            if ratio < bestRatio then best, bestRatio = eid, ratio end
        end
    end
    return best
end

-- Stun every living enemy for `secs` via combat.applyStun (seconds -> frames).
-- This drives world.stun (reliable CC on both sides) rather than the no-behavior
-- STUN status slot.
local function stunAllEnemies(world, secs)
    local frames = secs * 60
    for _, eid in ipairs(livingOfSide(world, 1)) do
        combat.applyStun(world, eid, frames)
    end
end

-- ============================================================================
-- EFFECT RESOLVER
-- ============================================================================

-- Resolve a status index that may be given as a number (a status.<NAME>
-- constant) or as a string name ("SLOW", "SHIELD"). Returns the numeric index,
-- or nil when unknown (the caller then no-ops rather than crashing). Reading
-- by name at call time means an index added later by status-dev resolves as
-- soon as it exists — no load-order coupling.
function M._statusIndex(def)
    local idx = def.index
    if type(idx) == "number" then return idx end
    if type(idx) == "string" then
        local named = status[idx]
        if named ~= nil then return named end
    end
    return nil
end

-- Interpret a single effect spec against one target. `srcId` is the caster,
-- `tgtId` the recipient; `targetSelf` specs ignore tgtId and use srcId. The
-- aoe kind dispatches to M.applyAoE (which re-enters here per hit unit).
function M.resolveEffect(world, battle, def, srcId, tgtId)
    local kind = def.kind

    if kind == "aoe" then
        -- Self-centered vs target-centered blast.
        local centerId = def.centerSelf and srcId or tgtId
        M.applyAoE(world, battle, centerId, def.radius, def, srcId)
        return
    end

    local target = def.targetSelf and srcId or tgtId
    if not world.entities[target] then return end

    if kind == "damage" then
        if world.deathState[target] then return end
        local useVFX = def.vfx ~= false
        combat.registerHit(world, battle, srcId, target, {
            ability  = def.ability or nil,
            buffMods = def.buffMods,   -- explicit outgoing multiplier (Sneak Attack)
        }, useVFX, battle.SCALE, battle.GRAVITY)
        -- Knockback: push the victim away from the caster [Thunderbolt].
        if def.knockback then
            M._applyKnockback(world, battle, srcId, target, def.knockback.force or 80)
        end
        -- Post-hit extra effects (e.g. Sunder Armor's vulnerability seed).
        if def.onHit and def.onHit.effect then
            M.resolveEffect(world, battle, def.onHit.effect, srcId, target)
        end
        -- Chain lightning: after the primary hit, arc to N nearest other foes
        -- with decaying damage [Paladin Wrath].
        if def.chain then
            M._applyChain(world, battle, srcId, target, def.chain)
        end

    elseif kind == "effects" then
        -- A declarative sequence of inner effects on the same target (the most
        -- BH-like shape: one row = a list of shared primitive applications).
        if world.deathState[target] then return end
        for _, inner in ipairs(def.effects or {}) do
            M.resolveEffect(world, battle, inner, srcId, target)
        end

    elseif kind == "status" then
        if world.deathState[target] then return end
        local idx = M._statusIndex(def)
        if idx ~= nil then
            local mag = def.magnitude
            -- DoT/HoT seed: scale an explicit per-second FRACTION off the
            -- caster's power at cast time (BH conflag/poison dot seeding —
            -- magnitude is stored as damage-OR-heal per second).
            if def.dotPerSec then
                local ss = world.stats[srcId]
                local power = ss and stats_mod.getPower(ss) or 0
                mag = power * def.dotPerSec
            end
            status.apply(world, target, def.isBuff and true or false,
                         idx, mag, def.duration, def.chainParams)
        end
        -- Optional visual tint riding on the status (matches old closures).
        if def.tint then
            effects_mod.addEffectTint(world, target,
                def.tint[1], def.tint[2], def.tint[3], def.tint[4] or 4.0)
        end

    elseif kind == "heal" then
        if world.deathState[target] then return end
        combat.registerHeal(world, battle, srcId, target, def.value or 1.0,
                            battle.SCALE)

    elseif kind == "healGroup" then
        -- Heal every living ally (whole arena, side 0) [Cleric Group Heal].
        for _, eid in ipairs(livingOfSide(world, 0)) do
            combat.registerHeal(world, battle, srcId, eid, def.value or 1.0, battle.SCALE)
        end

    elseif kind == "healLowestAlly" then
        -- Heal the most-injured living ally (falls back to self) [Holy Word].
        local tgt = lowestHpAlly(world, srcId) or srcId
        combat.registerHeal(world, battle, srcId, tgt, def.value or 1.0, battle.SCALE)

    elseif kind == "resourceGain" then
        if battle.resource then
            battle.resource = math.min(battle.resourceMax or 50,
                                       battle.resource + (def.amount or 0))
        end

    elseif kind == "drainHp" then
        -- Sacrifice a fraction of the target's CURRENT HP [Spark of Inspiration].
        local ts = world.stats[target]
        if ts then
            local curHp = statGet(ts.HP)
            local sacrifice = curHp * (def.fraction or 0)
            ts.HP.base = math.max(0, ts.HP.base - sacrifice)
        end

    elseif kind == "stunAll" then
        stunAllEnemies(world, def.seconds or 5.0)

    elseif kind == "threat" then
        -- Flat threat to all living enemies (side == 1).
        local flat = def.flat or 0
        for eid in pairs(world.entities) do
            local sd = world.side[eid]
            if sd and sd.s == 1 and not world.deathState[eid] then
                combat.addThreat(world, eid, srcId, flat)
                local ec = world.effects_comp[eid]
                if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(eid)) end
            end
        end
    end
end

-- ============================================================================
-- AoE RESOLVER
-- ============================================================================

-- Push `tgtId` away from `srcId` by adding a one-shot force into the target's
-- physics accumulator (magnitude `force`, short 0.12s pulse — the same shape
-- combat.registerHit already uses for its built-in nudge, just scaled by an
-- ability-chosen magnitude). [tuned force values live in the DB rows.]
function M._applyKnockback(world, battle, srcId, tgtId, force)
    local sp, tp = world.position[srcId], world.position[tgtId]
    local ph = world.physics and world.physics[tgtId]
    if not (sp and tp and ph) then return end
    local dx, dy = tp.x - sp.x, tp.y - sp.y
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.001 then return end
    dx, dy = dx/len, dy/len
    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newForce(tgtId, dx*force, dy*force, 0.12)) end
end

-- Chain lightning: after `primary` has been hit by `srcId`, arc to up to
-- `chain.count` further LIVING ENEMIES (side 1, excluding primary) nearest to
-- the primary, each taking (decay^i) times the FULL base roll (decay<1 →
-- decaying). Implemented as plain registerHit calls with explicit buffMods
-- fractions — fully data-driven, no closure. [Paladin Wrath]
function M._applyChain(world, battle, srcId, primaryId, chain)
    local count = chain.count or 3
    local decay = chain.decay or 0.5
    local pp = world.position[primaryId]
    local sp = world.position[srcId]
    if not pp then return end
    -- Gather candidate chain targets: living enemies other than the primary,
    -- sorted nearest-first (so the bolt arcs to the tightest cluster).
    local cands = {}
    for eid in pairs(world.entities) do
        local sd = world.side[eid]
        if sd and sd.s == 1 and eid ~= primaryId and not world.deathState[eid] then
            local ep = world.position[eid]
            if ep then
                local dx, dy = ep.x - pp.x, ep.y - pp.y
                cands[#cands+1] = {id=eid, d2=dx*dx+dy*dy}
            end
        end
    end
    table.sort(cands, function(a,b) return a.d2 < b.d2 end)
    for i = 1, math.min(count, #cands) do
        local frac = math.pow(decay, i)   -- 1st chain hop = decay^1, etc.
        combat.registerHit(world, battle, srcId, cands[i].id, {
            buffMods = { [0] = frac },
            ability  = { canCrit = false },   -- chain hops don't crit
        }, true, battle.SCALE, battle.GRAVITY)
    end
end

-- Given a center entity, find every living entity within `radius` virtual
-- pixels of its center and resolve `aoeDef` against each. If `aoeDef.inner`
-- is set that inner spec is resolved instead; `aoeDef.alsoStatus` (a status
-- spec) and `aoeDef.alsoKnockback` ({force}) are additionally applied to every
-- unit the AoE touches (Blizzard's dmg+SLOW, Thunderbolt/Vengeful Angel's
-- dmg+knockback). Center-to-center distance (documented simplification).
-- `srcId` is the caster, passed through so damage/heal credit correctly.
function M.applyAoE(world, battle, centerId, radius, aoeDef, srcId)
    local cp = world.position[centerId]
    if not cp then return end
    local r2 = radius * radius
    local inner = aoeDef.inner
    for eid in pairs(world.entities) do
        if not world.deathState[eid] then
            local ep = world.position[eid]
            if ep then
                local dx, dy = ep.x - cp.x, ep.y - cp.y
                if dx*dx + dy*dy <= r2 then
                    if inner then
                        M.resolveEffect(world, battle, inner, srcId, eid)
                    else
                        M.resolveEffect(world, battle, aoeDef, srcId, eid)
                    end
                    -- Extra per-hit status (e.g. Blizzard SLOW on every hit unit).
                    if aoeDef.alsoStatus then
                        M.resolveEffect(world, battle, aoeDef.alsoStatus, srcId, eid)
                    end
                    -- Extra per-hit knockback (e.g. Vengeful Angel / Thunderbolt).
                    if aoeDef.alsoKnockback then
                        M._applyKnockback(world, battle, srcId, eid, aoeDef.alsoKnockback.force or 80)
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- SKILL INSTANCE FACTORY
-- ============================================================================

-- Create a skill-instance shell that the per-entity skill list (sk.list[slot])
-- can hold. The `use` closure is the activation path: it fires the anim-lock
-- and queues the timed-action effect into the caster's effects_comp.pending,
-- matching CR's existing animation pipeline exactly.
--
-- `use` signature: (world, battle, casterId, skill) — same as before.
-- The timedAction delay (seconds) is the same value the old closures used, so
-- animation timing is unchanged.
function M.make(id)
    local def = M.DB[id]
    if not def then
        error("abilities.make: unknown ability id " .. tostring(id))
    end
    local skill = {
        abilityId      = id,
        name           = def.name,
        iconName       = def.iconName,
        iconScale      = def.iconScale or 1.0,
        iconScaleTarget = def.iconScaleTarget or 1.0,
        cd             = 0,
        cdMax          = def.cdMax or 10.0,
        resourceCost   = def.resourceCost or 0,
        noTargetRequired = def.noTargetRequired or false,
        animListIdx    = def.animListIdx or 4,
        animLock       = def.animLock or 0,
        -- Activation: plays the anim + queues the timed effect.
        -- SCALE/GRAVITY live on the `battle` table (the integrator sets
        -- battle.SCALE / battle.GRAVITY in initBattle; see the report).
        -- RETURNS true if the timed-action effect was successfully queued
        -- (i.e. the ability ACTIVATED), false on every early-out (missing /
        -- dead target, missing anim/effects comp). The caller (M.system in
        -- skills.lua) ALWAYS drops the front queue slot once `use` has been
        -- attempted; the boolean only decides whether to set the exec-gate.
        -- A dead/missing target is a stale slot → simply dropped (the resource
        -- paid at press is consumed; there is no refund path).
        use = function(world, battle, casterId, sk)
            local def2 = M.DB[sk.abilityId]
            if not def2 then return false end
            local SCALE   = battle.SCALE
            local GRAVITY = battle.GRAVITY
            local tgtId = nil
            if not def2.noTargetRequired then
                local et = world.entityTarget[casterId]
                if not et or not world.entities[et.id] then
                    return false  -- stale slot (target dead/missing); drop it
                end
                tgtId = et.id
            end
            -- Trigger the cast animation (existing anim-lock pattern).
            local ac = world.anim[casterId]
            if ac and ac.list[def2.animListIdx or 4] then
                ac.list[def2.animListIdx or 4].active = true
                ac.list[def2.animListIdx or 4].timer = 0
            end
            -- Feet-conversion rule (same as old path): moveLock for side-0
            -- (party) casters only.
            local sd = world.side[casterId]
            if sd and sd.s == 0 and def2.animLock then
                local lk = world.locks[casterId]
                if lk then lk.moveLock = math.max(lk.moveLock, def2.animLock) end
            end
            -- Queue the timed-action effect (same pipeline as before).
            local ec = world.effects_comp[casterId]
            if not ec then return false end
            local delay = def2.delay or 24/60
            local opts  = { skillSlot = sk._slot or 0 }
            if def2.isActionEffect == false then
                opts.isActionEffect = false
            end
            table.insert(ec.pending, effects_mod.newTimedAction(
                casterId, tgtId or casterId, delay,
                function(w2, b2, eff)
                    M.resolveEffect(w2, b2, def2.effect, eff.src, eff.tgt)
                end,
                opts
            ))
            return true
        end,
    }
    return skill
end

-- ============================================================================
-- ABILITY DATABASE
--
-- Each row is a data-driven definition. The EXISTING CR abilities are defined
-- first so their behavior is identical to the old closures (same cdMax,
-- resourceCost, status index/magnitude/duration, same anim slot + timing).
--
-- The 4 proof-of-port classes (Cleric, Paladin, Wizard, Rogue) are marked
-- TODO and will be overridden by the Director's class-design doc.
-- ============================================================================

M.DB = {}

-- ----------------------------------------------------------------------------
-- EXISTING CR ABILITIES (1:1 with the old closures)
-- ----------------------------------------------------------------------------

-- Knight: Sunder Armor (slot 1)
-- Old: registerHit(Melee,Slash,useVFX=true) + newSunderArmor(VULNERABILITY 0.25/10s)
M.DB.KnightSunderArmor = {
    name = "SunderArmor", iconName = "skill_icons17",
    role = "tank", targetType = "single",
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "damage", tags = { "Melee", "Slash" }, vfx = true,
        onHit = { effect = {
            kind = "status", isBuff = false,
            index = status.VULNERABILITY, magnitude = 0.25, duration = 10.0,
        } },
    },
}

-- Knight: Defend (slot 2, self-cast)
-- Old: newKnightDefend → DEF_BUFF 0.5/10s + blue tint (+ stagger-point drain,
-- dropped here as a CR-only nicety with no status-table analog — see note on
-- the old newKnightDefend in effects.lua). The DEF buff + tint are now data.
M.DB.KnightDefend = {
    name = "KnightDefend", iconName = "skill_icons22",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = nil,  -- no anim trigger in old path
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,  -- immediate
    effect = {
        kind = "status", isBuff = true, index = status.DEF_BUFF,
        magnitude = 0.5, duration = 10.0, tint = {0, 0, 1, 4.0},
    },
}

-- Knight: Challenging Shout (slot 3, self-cast AoE threat)
-- Old: addThreat(10*ATK) over all enemies + hurt indicator
M.DB.KnightChallengingShout = {
    name = "ChallengingShout", iconName = "skill_icons13",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = nil,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    -- Flat threat to all enemies. The old closure scaled it by caster ATK; in
    -- the data-driven form this is a fixed value [tuned] (Challenging Shout
    -- threat magnitude).
    effect = {
        kind = "threat",
        flat = 240,  -- [tuned] ~10x a mid-level party member's ATK
    },
}

-- Nomad: Grant Power (slot 1)
-- Old: newGrantPower → ATK_BUFF 0.5/10s + red tint
M.DB.NomadGrantPower = {
    name = "GrantPower", iconName = "skill_icons15",
    role = "support", targetType = "ally",
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    -- ATK buff on the target ally (+50% outgoing, 10s) + red tint [data].
    effect = {
        kind = "status", isBuff = true, index = status.ATK_BUFF,
        magnitude = 0.5, duration = 10.0, tint = {1, 0, 0, 4.0},
    },
}

-- Nomad: Mend Wounds (slot 2)
-- Old: newMendWounds → HOT (5*casterATK/10 per sec, 10s) + green tint.
-- Data form: HOT with a fixed heal/sec [tuned] (the old value tracked caster
-- ATK; a flat rate keeps it declarative — see note on newMendWounds).
M.DB.NomadMendWounds = {
    name = "MendWounds", iconName = "skill_icons11",
    role = "support", targetType = "ally",
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "status", isBuff = true, index = status.HOT,
        magnitude = 7.5, duration = 10.0,  -- [tuned] ~5*ATK/10 for a mid party member
        tint = {0, 1, 0, 4.0},
    },
}

-- Nomad: Spark of Inspiration (slot 3)
-- Old: sacrifice 20% of target HP, gain +20 resource.
M.DB.NomadSparkOfInspiration = {
    name = "SparkOfInspiration", iconName = "skill_icons46",
    role = "support", targetType = "ally",
    cdMax = 10.0, resourceCost = 0,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "drainHp", fraction = 0.20 },       -- sacrifice 20% target HP
            { kind = "resourceGain", amount = 20 },      -- +20 resource to caster
        },
    },
}

-- ----------------------------------------------------------------------------
-- AUTO-ATTACK ABILITIES (data rows for the parametric auto-attack factory)
-- ----------------------------------------------------------------------------
-- These keep the same structure the old newAutoAttackSkill produced. The
-- anim-lock + timed-action delay are preserved exactly.

M.DB.KnightAutoAttack = {
    name = "KnightAutoAttack", role = "melee", targetType = "single",
    cdMax = 2.0, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 4*6/60,
    delay = 12/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

M.DB.SkeletonAutoAttack = {
    name = "SkeletonAutoAttack", role = "melee", targetType = "single",
    cdMax = 2.0, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 8*6/60,
    delay = 21/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

M.DB.NomadAutoHeal = {
    name = "NomadAutoHeal", role = "support", targetType = "ally",
    cdMax = 2.5, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 8*6/60,
    delay = 24/60,
    effect = { kind = "heal", value = 1.0 },
}

M.DB.BrigandAutoAttack = {
    name = "BrigandAutoAttack", role = "melee", targetType = "single",
    cdMax = 2.0, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 7*6/60,
    delay = 5*6/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

M.DB.ChampionAutoAttack = {
    name = "ChampionAutoAttack", role = "melee", targetType = "single",
    cdMax = 2.0, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 4*6/60,
    delay = 3*6/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

M.DB.DuelistAutoAttack = {
    name = "DuelistAutoAttack", role = "melee", targetType = "single",
    cdMax = 2.0, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 6*6/60,
    delay = 5*6/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- ----------------------------------------------------------------------------
-- PROOF-OF-PORT CLASSES (data — from work/class-port-spec-cleric-paladin-wizard-rogue.md)
--
-- Numbers are used as-is from the spec ([tuned]/[wiki-only] baselines). All four
-- classes reuse the KNIGHT anim frame set in entities.lua ("recolor" = a
-- persistent world.tintColor set there, not an anim change). In-flight status
-- indices (SHIELD/SLOW/PARALYZE, being added by status-dev2) are referenced by
-- NAME and GUARDED so this file loads cleanly even before they exist.
-- ----------------------------------------------------------------------------

-- ============================ CLERIC (Lucille) ==============================
-- Support. NO melee auto-attack; its default action IS the auto-HEAL below.
-- Stats [spec §1.2]: maxHP 300 [tuned], DEF 9 [wiki], ATK 16 [wiki], CRIT 0,
-- MOVE_SPEED 3.0 [tuned]; heal cadence 1.75s [wiki]. Heals scale off power.

-- slot 0: Auto-Heal (default action, single-ally = selected target)
M.DB.ClericAutoHeal = {
    name = "ClericAutoHeal", role = "support", targetType = "ally",
    cdMax = 1.75, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 8*6/60,
    delay = 24/60,
    effect = { kind = "heal", value = 1.15 },  -- passives[0]==-1 ⇒ ×1.15 (spec IL L88497)
}

-- Group Heal: heal every living ally (whole arena, not radius-limited)
M.DB.ClericGroupHeal = {
    name = "GroupHeal", iconName = "skill_icons11",
    role = "support", targetType = "aoe", noTargetRequired = true,
    cdMax = 20.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "healGroup", value = 1.0 },
}

-- Shield: single-ally, takes -75% damage for 10s (flat SHIELD reduction).
-- Index given by NAME so it resolves as soon as status.SHIELD is present.
M.DB.ClericShield = {
    name = "Shield", iconName = "skill_icons22",
    role = "support", targetType = "ally",
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 12/60,
    effect = { kind = "status", isBuff = true, index = "SHIELD", magnitude = 0.75, duration = 10.0 },
}

-- Power Infusion: single-ally, ATK ×2 (=+100%) for 10s
M.DB.ClericPowerInfusion = {
    name = "PowerInfusion", iconName = "skill_icons15",
    role = "support", targetType = "ally",
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 12/60,
    effect = { kind = "status", isBuff = true, index = status.ATK_BUFF, magnitude = 1.0, duration = 10.0 },
}

-- Vengeful Angel: self → AoE around the CASTER, pulse-damage + knockback all
-- enemies in radius. [wiki CD60/res30; radius ~90px ≈ BH 2.0u; power·1.0
-- [tuned]]. APPROXIMATION: BH runs this as a per-frame aura while buffed; for
-- the port it is a single on-cast AoE pulse (the spec-approved simplification).
M.DB.ClericVengefulAngel = {
    name = "VengefulAngel", iconName = "skill_icons46",
    role = "support", targetType = "self", noTargetRequired = true,
    cdMax = 60.0, resourceCost = 30,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90, centerSelf = true,   -- centered on caster
        alsoKnockback = { force = 120 },                -- [tuned] push-away
        inner = { kind = "damage", tags = { "Melee" }, vfx = true },
    },
}

-- ============================= PALADIN (Heleth) =============================
-- Tank / hybrid healer. HAS a melee auto + draws aggro (hasThreateningPresence).
-- Stats [spec §2.2]: maxHP 520 [tuned], DEF 24 [wiki Lv5], ATK 24 [wiki],
-- CRIT 0, MOVE_SPEED 2.8 [tuned], swing 1.1s [tuned].

-- slot 0: Melee auto (tank swing)
M.DB.PaladinAutoAttack = {
    name = "PaladinAutoAttack", role = "tank", targetType = "single",
    cdMax = 1.1, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 4*6/60,
    delay = 8/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- Holy Word: heal the most-injured living ally (power·1.5 [wiki-only])
M.DB.PaladinHolyWord = {
    name = "HolyWord", iconName = "skill_icons11",
    role = "tank", targetType = "ally", noTargetRequired = true,
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "healLowestAlly", value = 1.5 },
}

-- Divine Intervention: self protection for 10s. APPROXIMATION (the real BH
-- hook is a damage-redirect slot `buffs[0x1e]` we don't have); declared as the
-- WARD .5 (chance to negate) + REFLECT .5 (return half) pair.
M.DB.PaladinDivineIntervention = {
    name = "DivineIntervention", iconName = "skill_icons22",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 30.0, resourceCost = 30,
    animLock = 0, animListIdx = nil,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    effect = {
        kind = "effects", targetSelf = true,
        effects = {
            { kind = "status", isBuff = true, index = status.WARD,    magnitude = 0.5, duration = 10.0 },
            { kind = "status", isBuff = true, index = status.REFLECT, magnitude = 0.5, duration = 10.0 },
        },
    },
}

-- Aura of Light: self, incoming damage converted to healing for 10s.
-- APPROXIMATION: under-faithful vs BH's full conversion — reuses the REFLECT
-- slot at .6 (returns 60% of would-be damage via the existing reflect path).
M.DB.PaladinAuraOfLight = {
    name = "AuraOfLight", iconName = "skill_icons46",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 40.0, resourceCost = 25,
    animLock = 0, animListIdx = nil,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    effect = {
        kind = "status", isBuff = true, index = status.REFLECT,
        magnitude = 0.6, duration = 10.0,
    },
}

-- Wrath: self imbue for 10s; while active the paladin's MELEE HITS chain
-- lightning to up to 3 nearby foes with decaying damage. Data-driven via a
-- dedicated CHAIN_LIGHTNING buff (status.CHAIN): combat.readTagSystem sees the
-- "Melee" tag on each auto-attack and rolls the chain, consuming one charge per
-- hit so it lasts ~10s at the 1.1s swing cadence. [wiki CD30/res20; count 3,
-- decay 0.5, 10 charges all [tuned]]. DEFERRED in-scope note: true per-frame
-- on-hit chaining with a timer-based expire would need a bespoke status handler;
-- the charge-consume model keeps it fully data-driven and time-bounded.
M.DB.PaladinWrath = {
    name = "Wrath", iconName = "skill_icons15",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    effect = {
        kind = "status", isBuff = true, index = "CHAIN",
        -- magnitude field carries the charge count; chain params ride alongside
        magnitude = 10,                       -- [tuned] ~10 melee hits over 10s
        chainParams = { count = 3, decay = 0.5 },  -- [tuned]
        duration = 10.0,
        tint = {1, 0.85, 0.3, 4.0},
    },
}

-- ============================= WIZARD (Bromswell) ===========================
-- Ranged DPS (isRanged=true). Auto-FIREs; heavy CC.
-- Stats [spec §3.2]: maxHP 260 [tuned], DEF 5 [wiki], ATK 28 [inferred],
-- CRIT 0, MOVE_SPEED 3.2 [tuned], cast interval 1.6s [tuned].

-- slot 0: Auto Fireball (aimed-shot distance reward, ranged)
M.DB.WizardAutoFireball = {
    name = "WizardAutoFireball", role = "dps", targetType = "single",
    cdMax = 1.6, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 0,
    delay = 15/60,
    effect = {
        kind = "damage", tags = { "Ranged", "Fire" }, vfx = true,
        ability = { aimedShot = true, falloff = 1.5, canCrit = true },
    },
}

-- Meteor: impact AoE around the target point, large radius (aimedShot), cost 30.
-- Magnitude [wiki-only] ~ power·2.0 → buffMods{2.0}. Radius 90 px ≈ BH 2.0u.
M.DB.WizardMeteor = {
    name = "Meteor", iconName = "skill_icons46",
    role = "dps", targetType = "aoe",
    cdMax = 30.0, resourceCost = 30,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90,
        inner = {
            kind = "damage", tags = { "Ranged", "Fire" }, vfx = true,
            ability = { aimedShot = true, falloff = 1.5, canCrit = true },
            buffMods = { [0] = 2.0 },
        },
    },
}

-- Blizzard: AoE all enemies in radius — damage + SLOW (moveSpeed down) 10s.
-- Declared as an aoe with an inner damage + alsoStatus SLOW (index by NAME so
-- it resolves once status.SLOW exists).
M.DB.WizardBlizzard = {
    name = "Blizzard", iconName = "skill_icons46",
    role = "dps", targetType = "aoe",
    cdMax = 30.0, resourceCost = 25,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90,
        inner = {
            kind = "damage", tags = { "Ranged", "Fire" }, vfx = true,
            ability = { aimedShot = true, falloff = 1.5, canCrit = true },
        },
        alsoStatus = { kind = "status", isBuff = false, index = "SLOW", magnitude = 0.4, duration = 10.0 },
    },
}

-- Time Stop: stun (freeze) all living enemies for 5s. Drives world.stun via
-- combat.applyStun (reliable CC; the STUN status slot has no behavior, so we
-- do NOT rely on it).
M.DB.WizardTimeStop = {
    name = "TimeStop", iconName = "skill_icons46",
    role = "dps", targetType = "aoe", noTargetRequired = true,
    cdMax = 45.0, resourceCost = 30,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "stunAll", seconds = 5.0 },
}

-- Conflagrate: single-enemy DOT burn + brief disable. [wiki CD40/res20; DOT
-- power·0.5/s for 6s, STUN 1.5s — magnitudes [tuned]]. DOT magnitude scales off
-- caster power at cast time.
M.DB.WizardConflagrate = {
    name = "Conflagrate", iconName = "skill_icons46",
    role = "dps", targetType = "single",
    cdMax = 40.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "status", isBuff = false, index = "DOT", dotPerSec = 0.5, duration = 6.0 },  -- [tuned]
            { kind = "status", isBuff = false, index = "STUN", duration = 1.5 },                     -- [tuned]
        },
    },
}

-- Thunderbolt: AoE centered on the CASTER (self blast), damage + knockback.
-- [wiki CD30/res25; radius ~90px ≈ BH medium; knockback force [tuned]].
M.DB.WizardThunderbolt = {
    name = "Thunderbolt", iconName = "skill_icons46",
    role = "dps", targetType = "self", noTargetRequired = true,
    cdMax = 30.0, resourceCost = 25,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90, centerSelf = true,
        alsoKnockback = { force = 100 },   -- [tuned] push-away
        inner = {
            kind = "damage", tags = { "Ranged" }, vfx = true,
            ability = { canCrit = true },
        },
    },
}

-- ============================== ROGUE (Gustav) ==============================
-- Melee burst DPS. Fastest swing of the four (0.85s). Crit base 0.20 [wiki
-- Critical Strikes] → flat-double crits via the existing roll (set in entities).
-- Stats [spec §4.2]: maxHP 300 [tuned], DEF 11 [wiki avg 9–13], ATK 31 [wiki Lv1
-- bare, per spec §5 conflict note], CRIT 0.20, MOVE_SPEED 3.4 [tuned].

-- slot 0: fastest melee swing
M.DB.RogueAutoAttack = {
    name = "RogueAutoAttack", role = "dps", targetType = "single",
    cdMax = 0.85, resourceCost = 0, isAutoAttack = true,
    animListIdx = 3, animLock = 4*6/60,
    delay = 5/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- Sneak Attack: single-enemy 250% normal damage (crits still apply). Declared
-- as a damage row with an explicit outgoing multiplier buffMods{[0]=1.5} (→ ×2.5
-- total) passed through the two-stage roll; the roll's own crit still doubles.
M.DB.RogueSneakAttack = {
    name = "SneakAttack", iconName = "skill_icons17",
    role = "dps", targetType = "single",
    cdMax = 20.0, resourceCost = 20,
    animLock = 4*6/60, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 8/60,
    effect = {
        kind = "damage", tags = { "Melee" }, vfx = true,
        ability = { canCrit = true },
        buffMods = { [0] = 1.5 },   -- [wiki] 250% of normal damage
    },
}

-- Expose Weakness: single-enemy VULNERABILITY +50% for 10s
M.DB.RogueExposeWeakness = {
    name = "ExposeWeakness", iconName = "skill_icons15",
    role = "dps", targetType = "single",
    cdMax = 30.0, resourceCost = 15,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 8/60,
    effect = { kind = "status", isBuff = false, index = status.VULNERABILITY, magnitude = 0.5, duration = 10.0 },
}

-- Shadowstep: single-enemy 350% strike (teleport-behind movement SKIPPED — just
-- the big hit). buffMods{[0]=2.5} (→ ×3.5 total); crits still apply.
M.DB.RogueShadowstep = {
    name = "Shadowstep", iconName = "skill_icons17",
    role = "dps", targetType = "single",
    cdMax = 30.0, resourceCost = 20,
    animLock = 6*6/60, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 10/60,
    effect = {
        kind = "damage", tags = { "Melee" }, vfx = true,
        ability = { canCrit = true },
        buffMods = { [0] = 2.5 },   -- [wiki] 350% of normal damage
    },
}

-- Poisoned Knife: single-enemy ranged-lite — small immediate hit + DOT poison.
-- [wiki CD30/res15; immediate hit power·0.5 [tuned], DOT 6s [tuned]]. The knife
-- "throw" has no projectile renderer here (separate VFX task) — just the damage
-- + DOT seed.
M.DB.RoguePoisonedKnife = {
    name = "PoisonedKnife", iconName = "skill_icons11",
    role = "dps", targetType = "single",
    cdMax = 30.0, resourceCost = 15,
    animLock = 4*6/60, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 8/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "damage", tags = { "Ranged" }, vfx = true,
              ability = { aimedShot = true, falloff = 1.5, canCrit = true },
              buffMods = { [0] = -0.5 } },   -- [tuned] small immediate hit (×0.5)
            { kind = "status", isBuff = false, index = "DOT", dotPerSec = 0.3, duration = 6.0 },  -- [tuned]
        },
    },
}

-- DEFERRED (out of scope — 5-slot UI limit): Rogue Paralytic Knife (PARALYZE 8s)
-- and Paladin Radiance (AoE knockdown + party heal). See class-port-spec §4.3 /
-- §2.3. Not wired into CLASS_SETS.

-- ----------------------------------------------------------------------------
-- CLASS ABILITY SETS (convenience: which abilities each class gets, per slot)
-- The integrator uses these to wire sk.list for new classes.
-- ----------------------------------------------------------------------------

-- Each class: an `auto` (slot 0, the default action) + up to FOUR `actives`
-- (slots 1..4). The UI already maps q/w/e/r → slots 1..4, so a 4th active needs
-- no UI change. Paralytic Knife (rogue) and Radiance (paladin) are DEFERRED by
-- the 5-slot limit — see their notes above; they are intentionally NOT slotted.
M.CLASS_SETS = {
    knight = { auto = "KnightAutoAttack",
               actives = { "KnightSunderArmor", "KnightDefend", "KnightChallengingShout" } },
    nomad  = { auto = "NomadAutoHeal",
               actives = { "NomadGrantPower", "NomadMendWounds", "NomadSparkOfInspiration" } },
    brigand  = { auto = "BrigandAutoAttack",   actives = {} },
    champion = { auto = "ChampionAutoAttack",  actives = {} },
    duelist  = { auto = "DuelistAutoAttack",   actives = {} },
    -- Proof-of-port classes (work/class-port-spec-cleric-paladin-wizard-rogue.md)
    -- Now at full BH-parity kits: auto + 4 actives each.
    cleric  = { auto = "ClericAutoHeal",       -- default action IS the heal
                actives = { "ClericGroupHeal", "ClericShield", "ClericPowerInfusion", "ClericVengefulAngel" } },
    paladin = { auto = "PaladinAutoAttack",
                actives = { "PaladinHolyWord", "PaladinDivineIntervention", "PaladinAuraOfLight", "PaladinWrath" } },
    wizard  = { auto = "WizardAutoFireball",   -- ranged auto-fire
                actives = { "WizardMeteor", "WizardBlizzard", "WizardTimeStop", "WizardConflagrate" } },
    rogue   = { auto = "RogueAutoAttack",      -- fastest melee swing
                actives = { "RogueSneakAttack", "RogueExposeWeakness", "RogueShadowstep", "RoguePoisonedKnife" } },
}
-- NOTE: WizardThunderbolt is defined in M.DB but not slotted into any CLASS_SETS
-- (the wizard's 4 active slots are Meteor/Blizzard/TimeStop/Conflagrate per the
-- Director's final kit). It remains available as data should a future re-slot want it.

return M

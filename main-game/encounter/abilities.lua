-- encounter/abilities.lua — the ability ENGINE: turns rows of
-- data/abilities.lua into things that happen in battle.
--
--   M.DB[id]                — the ability rows (data/abilities.lua)
--   M.make(id, slot)        — a per-unit skill instance for world.skills[u].list[slot]
--   M.resolveEffect(world, battle, effect, srcId, tgtId) — apply one effect spec
--
-- Casting pipeline: skills.lua decides WHEN a unit may act and calls
-- skill.use(...). `use` plays the cast animation, applies the move lock and
-- schedules the row's `effect` to land after `delay` seconds.
--
-- Effect kinds (the `effect` field of a row — pure data, may nest):
--   { kind="damage", tags?, vfx?, ability?, buffMods?, knockback?, chain?, onHit? }
--       tags     = { "Melee", "Ranged", "Fire", ... } what kind of hit it is
--       vfx      = false to suppress the screen shake on hit
--       ability  = { aimedShot=bool, falloff=number, canCrit=bool } roll options
--       buffMods = { [0]=fraction } damage multiplier as an additive fraction
--                  (1.5 = 250% damage, -0.5 = half damage)
--       knockback= { force=F } push the victim away from the caster
--       chain    = { count=N, decay=d } then hit N more nearby foes for decay^i
--       onHit    = { effect=<effect> } a further effect applied to the victim
--   { kind="status", isBuff=bool, index="NAME", magnitude?, duration?, tint?,
--     dotPerSec?, chainParams? }
--       index: a status name from encounter/status.lua ("SLOW", "SHIELD", ...)
--       dotPerSec: magnitude = caster power x this (for DOT / HOT)
--       tint = {r, g, b, speed} pulsing sprite tint while it lasts
--   { kind="effects", effects={ <effect>, ... }, targetSelf? } several effects, in order
--   { kind="heal", value }             heal the target for power x value
--   { kind="healGroup", value }        heal every living hero
--   { kind="healLowestAlly", value }   heal the most injured living hero
--   { kind="threat", flat }            add threat on every living enemy
--   { kind="resourceGain", amount }    refill the shared resource bar
--   { kind="drainHp", fraction }       remove a fraction of the target's current HP
--   { kind="stunAll", seconds }        stun every living enemy
--   { kind="aoe", radius, centerSelf?, inner=<effect>, alsoStatus?, alsoKnockback? }
--       everything within `radius` px of the target (or of the caster when
--       centerSelf) gets `inner`; alsoStatus / alsoKnockback are applied too.
-- Any effect may set targetSelf=true to hit the caster instead of the target.

local combat  = require("encounter/combat")
local status  = require("encounter/status")
local effects_mod = require("encounter/effects")
local stats_mod = require("encounter/stats")

local statGet = stats_mod.get

local M = {}

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

-- A status index given as a number or as a name ("SLOW"). Returns the numeric
-- index, or nil for an unknown name (the effect is then skipped).
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
            tags = def.tags, ability = def.ability, buffMods = def.buffMods,
        }, useVFX)
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
            combat.chainHit(world, battle, srcId, target, def.chain)
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
        -- Optional pulsing tint while the status lasts.
        if def.tint then
            effects_mod.addEffectTint(world, target,
                def.tint[1], def.tint[2], def.tint[3], def.tint[4] or 4.0)
        end

    elseif kind == "heal" then
        if world.deathState[target] then return end
        combat.registerHeal(world, battle, srcId, target, def.value or 1.0)

    elseif kind == "healGroup" then
        -- Heal every living ally (whole arena, side 0) [Cleric Group Heal].
        for _, eid in ipairs(livingOfSide(world, 0)) do
            combat.registerHeal(world, battle, srcId, eid, def.value or 1.0)
        end

    elseif kind == "healLowestAlly" then
        -- Heal the most-injured living ally (falls back to self) [Holy Word].
        local tgt = lowestHpAlly(world, srcId) or srcId
        combat.registerHeal(world, battle, srcId, tgt, def.value or 1.0)

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

-- Create the per-unit instance of ability `id` for skill slot `slot`
-- (0 = default action, 1..4 = Q/W/E/R). The instance holds the live cooldown
-- and a `use(world, battle, casterId, skill)` function.
function M.make(id, slot)
    local def = M.DB[id]
    if not def then
        error("abilities.make: unknown ability id " .. tostring(id))
    end
    local skill = {
        abilityId      = id,
        _slot          = slot or 0,
        name           = def.name,
        iconName       = def.iconName,
        iconScale      = 1.0,   -- animated by encounter/ui.lua
        iconScaleTarget = 1.0,
        cd             = 0,
        cdMax          = def.cdMax or 10.0,
        resourceCost   = def.resourceCost or 0,
        noTargetRequired = def.noTargetRequired or false,
        animListIdx    = def.animListIdx or 4,
        animLock       = def.animLock or 0,
        -- Returns true if the ability actually went off (its effect is now
        -- scheduled), false if it could not (target gone). skills.lua drops
        -- the queued press either way; the resource paid at press is not refunded.
        use = function(world, battle, casterId, sk)
            local def2 = M.DB[sk.abilityId]
            if not def2 then return false end
            local tgtId = nil
            if not def2.noTargetRequired then
                local et = world.entityTarget[casterId]
                if not et or not world.entities[et.id] then
                    return false  -- stale slot (target dead/missing); drop it
                end
                tgtId = et.id
            end
            -- Play the cast animation.
            local ac = world.anim[casterId]
            if ac and ac.list[def2.animListIdx or 4] then
                ac.list[def2.animListIdx or 4].active = true
                ac.list[def2.animListIdx or 4].timer = 0
            end
            -- The move lock applies to heroes (side 0) only.
            local sd = world.side[casterId]
            if sd and sd.s == 0 and def2.animLock then
                local lk = world.locks[casterId]
                if lk then lk.moveLock = math.max(lk.moveLock, def2.animLock) end
            end
            -- Schedule the effect to land after the wind-up.
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

M.DB = require("data/abilities")

return M

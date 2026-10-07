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
--   effect      : effect spec — either an inner-kind table (see resolver) or
--                 an { kind="custom", fn=function(w,b,src,tgt) ... end }
--
-- Inner-effect kinds (M.resolveEffect):
--   { kind="damage", scale?, tags?, vfx?, ability? }
--       ability = { aimedShot=bool, falloff=number, canCrit=bool }
--   { kind="status", isBuff=bool, index=status.<NAME>, magnitude?, duration?,
--                    targetSelf? }
--   { kind="heal", value=number }
--   { kind="threat", flat=number|function(casterStats) }
--   { kind="aoe", radius=number, inner=<one of the above> }
--   { kind="custom", fn=function(world,battle,srcId,tgtId) ... end }

local combat  = require("encounter/combat")
local status  = require("encounter/status")
local effects_mod = require("encounter/effects")
local stats_mod = require("encounter/stats")

local statGet = stats_mod.get

local M = {}

-- ============================================================================
-- EFFECT RESOLVER
-- ============================================================================

-- Interpret a single (non-aoe, non-custom) effect spec against one target.
-- `srcId` is the caster, `tgtId` is the recipient. For targetSelf specs the
-- resolver ignores tgtId and uses srcId.
function M.resolveEffect(world, battle, def, srcId, tgtId)
    local kind = def.kind
    local target = def.targetSelf and srcId or tgtId
    if not world.entities[target] then return end

    if kind == "damage" then
        if world.deathState[target] then return end
        local useVFX = def.vfx ~= false
        combat.registerHit(world, battle, srcId, target, {
            ability = def.ability or nil,
        }, useVFX, battle.SCALE, battle.GRAVITY)
        -- Post-hit extra effects (e.g. Sunder Armor's vulnerability seed).
        if def.onHit and def.onHit.effect then
            M.resolveEffect(world, battle, def.onHit.effect, srcId, target)
        end

    elseif kind == "status" then
        if world.deathState[target] then return end
        status.apply(world, target, def.isBuff and true or false,
                     def.index, def.magnitude, def.duration)
        -- Optional visual tint riding on the status (matches old closures).
        if def.tint then
            effects_mod.addEffectTint(world, target,
                def.tint[1], def.tint[2], def.tint[3], def.tint[4] or 4.0)
        end

    elseif kind == "heal" then
        if world.deathState[target] then return end
        combat.registerHeal(world, battle, srcId, target, def.value or 1.0,
                            battle.SCALE)

    elseif kind == "threat" then
        -- Apply flat threat to all living enemies (side == 1).
        local flat = def.flat
        if type(flat) == "function" then
            local cs = world.stats[srcId]
            flat = cs and flat(cs) or 0
        end
        for eid in pairs(world.entities) do
            local sd = world.side[eid]
            if sd and sd.s == 1 and not world.deathState[eid] then
                combat.addThreat(world, eid, srcId, flat)
                local ec = world.effects_comp[eid]
                if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(eid)) end
            end
        end

    elseif kind == "aoe" then
        -- Resolve AoE: apply inner effect to every living entity within
        -- `radius` of the target point (center-based distance).
        M.applyAoE(world, battle, tgtId, def.radius, def.inner, srcId)

    elseif kind == "custom" then
        if def.fn then def.fn(world, battle, srcId, tgtId) end
    end
end

-- ============================================================================
-- AoE RESOLVER
-- ============================================================================

-- Given a target entity (the "center"), find every living entity within
-- `radius` virtual pixels of its center position and apply the inner effect
-- to each. Uses center-to-center distance (documented simplification).
-- `srcId` is the caster, passed through so damage/heal credit correctly.
function M.applyAoE(world, battle, centerId, radius, inner, srcId)
    local cp = world.position[centerId]
    if not cp then return end
    local r2 = radius * radius
    for eid in pairs(world.entities) do
        if not world.deathState[eid] then
            local ep = world.position[eid]
            if ep then
                local dx, dy = ep.x - cp.x, ep.y - cp.y
                if dx*dx + dy*dy <= r2 then
                    M.resolveEffect(world, battle, inner, srcId, eid)
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

-- ============================================================================
-- SHARED TARGET HELPERS (used by the data-driven active-ability custom fns)
--
-- NOTE ON IN-FLIGHT STATUS INDICES: another agent (status-dev2) is adding
-- status.SHIELD / status.SLOW and enabling DOT/PARALYZE RIGHT NOW. Those
-- indices may not exist when this module loads. Every reference below is
-- GUARDED (`if status.<X> then ... else <fallback>`), and each index is read
-- into a LOCAL at call time (not cached at load) so it resolves as soon as
-- status-dev2 lands its rows. Fallbacks: SHIELD→high WARD, SLOW→skip, PARALYZE→STUN.
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

-- Apply a debuff, falling back to an equivalent existing index if the new one
-- (being added by status-dev2) isn't present yet. Returns nothing; safe to call
-- even if neither index exists (in that case the primary path just no-ops).
local function applyStatusSafe(world, id, isBuff, indexName, fallbackIndex, magnitude, duration)
    local idx = status[indexName]
    if idx ~= nil then
        status.apply(world, id, isBuff, idx, magnitude, duration)
    elseif fallbackIndex ~= nil then
        status.apply(world, id, isBuff, fallbackIndex, magnitude, duration)
    end
    -- If neither index exists yet, skip (no crash); the real index lands later.
end

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
-- Old: newKnightDefend → DEF_BUFF 0.5/10s + blue tint + stagger drain
M.DB.KnightDefend = {
    name = "KnightDefend", iconName = "skill_icons22",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = nil,  -- no anim trigger in old path
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,  -- immediate (old path inserted directly, no timed action)
    effect = { kind = "custom", fn = function(world, battle, srcId)
        local ec = world.effects_comp[srcId]
        if ec then table.insert(ec.pending, effects_mod.newKnightDefend(srcId, statGet)) end
    end },
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
    effect = {
        kind = "threat",
        flat = function(cs) return 10 * statGet(cs.ATK) end,
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
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        local tec = world.effects_comp[tgtId]
        if tec then table.insert(tec.pending, effects_mod.newGrantPower(tgtId)) end
    end },
}

-- Nomad: Mend Wounds (slot 2)
-- Old: newMendWounds → HOT (5*casterATK/10 per sec, 10s) + green tint
M.DB.NomadMendWounds = {
    name = "MendWounds", iconName = "skill_icons11",
    role = "support", targetType = "ally",
    cdMax = 10.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        local tec = world.effects_comp[tgtId]
        if tec then table.insert(tec.pending, effects_mod.newMendWounds(srcId, tgtId, statGet)) end
    end },
}

-- Nomad: Spark of Inspiration (slot 3)
-- Old: sacrifice 20% of target HP, gain +20 resource
M.DB.NomadSparkOfInspiration = {
    name = "SparkOfInspiration", iconName = "skill_icons46",
    role = "support", targetType = "ally",
    cdMax = 10.0, resourceCost = 0,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        local ts = world.stats[tgtId]
        if ts then
            local curHp = statGet(ts.HP)
            local sacrifice = curHp * 0.20
            ts.HP.base = math.max(0, ts.HP.base - sacrifice)
        end
        if battle.resource then
            battle.resource = math.min(battle.resourceMax or 50, battle.resource + 20)
        end
    end },
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
    effect = { kind = "custom", fn = function(world, battle, srcId)
        for _, eid in ipairs(livingOfSide(world, 0)) do
            combat.registerHeal(world, battle, srcId, eid, 1.0, battle.SCALE)
        end
    end },
}

-- Shield: single-ally, takes -75% damage for 10s (DAMAGE_REDUCE/SHIELD slot)
-- GUARDED: falls back to a high WARD until status.SHIELD exists.
M.DB.ClericShield = {
    name = "Shield", iconName = "skill_icons22",
    role = "support", targetType = "ally",
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 12/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        if not world.entities[tgtId] then return end
        applyStatusSafe(world, tgtId, true, "SHIELD", status.WARD, 0.75, 10.0)
    end },
}

-- Power Infusion: single-ally, ATK ×2 (=+100%) for 10s
M.DB.ClericPowerInfusion = {
    name = "PowerInfusion", iconName = "skill_icons15",
    role = "support", targetType = "ally",
    cdMax = 30.0, resourceCost = 20,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 12/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        if not world.entities[tgtId] then return end
        status.apply(world, tgtId, true, status.ATK_BUFF, 1.0, 10.0)
    end },
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
    effect = { kind = "custom", fn = function(world, battle, srcId)
        local tgt = lowestHpAlly(world, srcId) or srcId
        combat.registerHeal(world, battle, srcId, tgt, 1.5, battle.SCALE)
    end },
}

-- Divine Intervention: party-wide protection for 10s. APPROXIMATION (the real
-- BH hook is a damage-redirect slot `buffs[0x1e]` we don't have); approximate
-- as WARD .5 (chance to negate) + REFLECT .5 (return half) on the paladin.
M.DB.PaladinDivineIntervention = {
    name = "DivineIntervention", iconName = "skill_icons22",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 30.0, resourceCost = 30,
    animLock = 0, animListIdx = nil,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    effect = { kind = "custom", fn = function(world, battle, srcId)
        status.apply(world, srcId, true, status.WARD,     0.5, 10.0)
        status.apply(world, srcId, true, status.REFLECT,  0.5, 10.0)
    end },
}

-- Aura of Light: self, incoming damage converted to healing for 10s. APPROXIMATION:
-- under-faithful vs BH's full conversion — reuses the REFLECT slot at .6 (returns
-- 60% of would-be damage as HP via the existing reflect->heal path).
M.DB.PaladinAuraOfLight = {
    name = "AuraOfLight", iconName = "skill_icons46",
    role = "tank", targetType = "self", noTargetRequired = true,
    cdMax = 40.0, resourceCost = 25,
    animLock = 0, animListIdx = nil,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 0,
    effect = { kind = "custom", fn = function(world, battle, srcId)
        status.apply(world, srcId, true, status.REFLECT, 0.6, 10.0)
    end },
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
        kind = "damage", tags = { "Ranged", "Fire" }, vfx = false,
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
-- The resolver cannot stack dmg+status in one inner, so custom fn: loop the
-- radius, registerHit then applyStatusSafe(SLOW) [guarded → skip if absent].
M.DB.WizardBlizzard = {
    name = "Blizzard", iconName = "skill_icons46",
    role = "dps", targetType = "aoe",
    cdMax = 30.0, resourceCost = 25,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        local cp = world.position[tgtId] or world.position[srcId]
        if not cp then return end
        local r2 = 90 * 90
        for eid in pairs(world.entities) do
            local sd = world.side[eid]
            if sd and sd.s == 1 and not world.deathState[eid] then
                local ep = world.position[eid]
                if ep then
                    local dx, dy = ep.x - cp.x, ep.y - cp.y
                    if dx*dx + dy*dy <= r2 then
                        combat.registerHit(world, battle, srcId, eid,
                            {ability={aimedShot=true,falloff=1.5,canCrit=true}}, true, battle.SCALE, battle.GRAVITY)
                        applyStatusSafe(world, eid, false, "SLOW", nil, 0.4, 10.0)
                    end
                end
            end
        end
    end },
}

-- Time Stop: stun (freeze) all living enemies for 5s. Drives world.stun via
-- combat.applyStun (reliable CC on both sides; the STUN status slot has no
-- behavior yet, so we do NOT rely on it).
M.DB.WizardTimeStop = {
    name = "TimeStop", iconName = "skill_icons46",
    role = "dps", targetType = "aoe", noTargetRequired = true,
    cdMax = 45.0, resourceCost = 30,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 24/60,
    effect = { kind = "custom", fn = function(world, battle)
        stunAllEnemies(world, 5.0)
    end },
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

-- Sneak Attack: single-enemy 250% normal damage (crits still apply). Implemented
-- as explicit outgoing buffMods{[0]=1.5} (→ ×2.5 total) passed through the two-stage
-- roll; the roll's own crit still flat-doubles after that.
M.DB.RogueSneakAttack = {
    name = "SneakAttack", iconName = "skill_icons17",
    role = "dps", targetType = "single",
    cdMax = 20.0, resourceCost = 20,
    animLock = 4*6/60, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 8/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        if not world.entities[tgtId] or world.deathState[tgtId] then return end
        combat.registerHit(world, battle, srcId, tgtId,
            {ability={canCrit=true}, buffMods={[0]=1.5}}, true, battle.SCALE, battle.GRAVITY)
    end },
}

-- Expose Weakness: single-enemy VULNERABILITY +50% for 10s
M.DB.RogueExposeWeakness = {
    name = "ExposeWeakness", iconName = "skill_icons15",
    role = "dps", targetType = "single",
    cdMax = 30.0, resourceCost = 15,
    animLock = 0, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 8/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        if not world.entities[tgtId] then return end
        status.apply(world, tgtId, false, status.VULNERABILITY, 0.5, 10.0)
    end },
}

-- Shadowstep: single-enemy 350% strike (teleport-behind movement SKIPPED — just
-- the big hit). Explicit buffMods{[0]=2.5} (→ ×3.5 total); crits still apply.
M.DB.RogueShadowstep = {
    name = "Shadowstep", iconName = "skill_icons17",
    role = "dps", targetType = "single",
    cdMax = 30.0, resourceCost = 20,
    animLock = 6*6/60, animListIdx = 4,
    iconScale = 1.0, iconScaleTarget = 1.0,
    delay = 10/60,
    effect = { kind = "custom", fn = function(world, battle, srcId, tgtId)
        if not world.entities[tgtId] or world.deathState[tgtId] then return end
        combat.registerHit(world, battle, srcId, tgtId,
            {ability={canCrit=true}, buffMods={[0]=2.5}}, true, battle.SCALE, battle.GRAVITY)
    end },
}

-- ----------------------------------------------------------------------------
-- CLASS ABILITY SETS (convenience: which abilities each class gets, per slot)
-- The integrator uses these to wire sk.list for new classes.
-- ----------------------------------------------------------------------------

M.CLASS_SETS = {
    knight = { auto = "KnightAutoAttack",
               actives = { "KnightSunderArmor", "KnightDefend", "KnightChallengingShout" } },
    nomad  = { auto = "NomadAutoHeal",
               actives = { "NomadGrantPower", "NomadMendWounds", "NomadSparkOfInspiration" } },
    brigand  = { auto = "BrigandAutoAttack",   actives = {} },
    champion = { auto = "ChampionAutoAttack",  actives = {} },
    duelist  = { auto = "DuelistAutoAttack",   actives = {} },
    -- Proof-of-port classes (work/class-port-spec-cleric-paladin-wizard-rogue.md)
    cleric  = { auto = "ClericAutoHeal",       -- default action IS the heal
                actives = { "ClericGroupHeal", "ClericShield", "ClericPowerInfusion" } },
    paladin = { auto = "PaladinAutoAttack",
                actives = { "PaladinHolyWord", "PaladinDivineIntervention", "PaladinAuraOfLight" } },
    wizard  = { auto = "WizardAutoFireball",   -- ranged auto-fire
                actives = { "WizardMeteor", "WizardBlizzard", "WizardTimeStop" } },
    rogue   = { auto = "RogueAutoAttack",      -- fastest melee swing
                actives = { "RogueSneakAttack", "RogueExposeWeakness", "RogueShadowstep" } },
}

return M

-- encounter/combat.lua — Damage calculation, hit/heal resolution, stagger, threat
--
-- Damage model: Battleheart's two-stage, asymmetric system.
--   Stage 1 (attacker roll)   M.roll(world, srcId, tgtId, ability)  -> baseAmount
--       attacker power, aimed-shot falloff, flat-doubled crit (player side only).
--   Stage 2 (victim resolve)  M.resolve(world, victimId, baseAmount, srcId, opts) -> finalDamage, flags
--       party victims: flat armor subtract + additive buff fractions + min-3 floor
--                      + ward/reflect negation hooks.
--       enemy victims: NO armor, additive debuff fractions only, no floor.
--
-- The legacy symmetric entry points (calcNormalDmg / resolveHit / registerHit)
-- are kept with compatible signatures and now route through roll -> resolve.

local stats_mod    = require("encounter/stats")
local effects_mod  = require("encounter/effects")
local particles    = require("encounter/particles")
local anim_mod     = require("encounter/anim")
local status_mod   = require("encounter/status")

local statGet = stats_mod.get
local getPower = stats_mod.getPower

-- Party side = 0, enemy side = 1 (world.side convention, see entities.lua).
-- Battleheart asymmetry: only party members roll crits and take armor;
-- enemies have no defense stat.
local function isParty(world, id)
    local sd = world.side[id]
    return sd and sd.s == 0
end

-- Sum additive buff/debuff fractions (BH rule: additive, no compounding).
local function sumFrac(t)
    local s = 0
    for _, f in pairs(t or {}) do s = s + f end
    return s
end

local M = {}

-- ============================================================================
-- COMBAT MATH — STAGE 1: ATTACKER ROLL
-- ============================================================================

-- Roll the raw damage amount from the ATTACKER's side.
--   ability (optional table):
--     aimedShot  = true   — apply the ranged falloff modifier
--     falloff    = number  — cap multiplier for aimed shots (BH projectileDamageMod, default 1.0)
--     canCrit    = bool    — false suppresses crit for this hit (BH apollo-style)
--     buffMods   = { [index]=fraction } — explicit additive offense fractions;
--                 auto-read from the attacker's statuses when omitted
--                 (status_mod.buffMods, see the status system's getMods).
-- Returns baseAmount, isCrit (crit already flat-doubled into baseAmount).
function M.roll(world, srcId, tgtId, ability)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return 0, false end

    local base = getPower(ss) * math.max(0.10, statGet(ss.BOOST))

    -- Additive attacker-offense fractions (BH: fractions of the base roll,
    -- no compounding). Auto-read from the status system when not provided.
    local offenseFrac
    if ability and ability.buffMods ~= nil then
        offenseFrac = sumFrac(ability.buffMods)
    else
        local mods = status_mod.getMods and status_mod.getMods(world, srcId)
        offenseFrac = mods and sumFrac(mods.buffMods) or 0
    end
    base = base * (1 + offenseFrac)

    -- Aimed-shot / ranged falloff: multiplier grows with distance up to the
    -- ability's cap (BH: Clamp(dist*0.6, 1.5, projectileDamageMod)). Default
    -- cap 1.0 keeps plain melee at exactly 1.0x until the ability system
    -- passes a real projectileDamageMod.
    if ability and ability.aimedShot then
        local sp, tp = world.position[srcId], world.position[tgtId]
        local dist = 0
        if sp and tp then
            local dx, dy = tp.x - sp.x, tp.y - sp.y
            dist = math.sqrt(dx*dx + dy*dy)
        end
        local cap = ability.falloff or 1.0
        base = base * math.max(1.5, math.min(cap, dist * 0.6))
    end

    -- Crit: PLAYER-ATTACKS-ENEMY only, flat-double BEFORE resolution.
    local isCrit = false
    if isParty(world, srcId) and (not ability or ability.canCrit ~= false) then
        local critChance = math.max(0, statGet(ss.CRIT) * (1 - statGet(ts.CRIT_DEF)))
        if math.random() < critChance then
            base = base * 2
            isCrit = true
        end
    end

    return base, isCrit
end

-- ============================================================================
-- COMBAT MATH — STAGE 2: VICTIM RESOLVE
-- ============================================================================

-- Resolve the rolled amount against the VICTIM's defensive side.
--   opts (optional table; every field optional):
--     buffMods  = { [index]=fraction } — additive fractions of the base roll
--                 (no compounding). For party victims this is the ATTACKER's
--                 outgoing-damage buffs; for enemies it is the victim's
--                 vulnerability/marked debuffs.
--     debuffMods = { [index]=fraction } — ADDITIONAL victim-side incoming-damage
--                 fractions (e.g. vulnerability) applied on top of buffMods.
--     defFlat   = number — flat DEF bonus added to the party armor subtract.
--     negate    = true   — ward / full-negation already rolled (party side):
--                 final damage 0. Callers (status system) can pre-roll via
--                 status.resolveNegate and pass the result.
--     reflect   = fraction — thorns hook (party side): reflect fraction of
--                 final damage back at the attacker as damage.
-- When `opts.buffMods`/`debuffMods` are nil and the status system is live,
-- the matching table is read automatically from status.getMods(world, ...).
-- Returns finalDamage (>=0), flags {crit=false, negated, reflected}.
-- (crit is always false here; the roll owns the crit and registerHit
-- reports it via `damage` doubling — see M.roll.)
function M.resolve(world, victimId, baseAmount, srcId, opts)
    local vs = world.stats[victimId]
    if not vs then return 0, {crit=false, negated=false, reflected=0} end
    opts = opts or {}

    local party = isParty(world, victimId)
    local statusLive = status_mod.getMods ~= nil
    local victimMods = statusLive and status_mod.getMods(world, victimId) or nil
    local srcMods    = (party and statusLive) and status_mod.getMods(world, srcId) or nil

    -- Gather additive fractions of the base roll (BH: additive, no
    -- compounding). Party victims: attacker's outgoing buffs + victim's
    -- vulnerability debuffs. Enemy victims: victim's vulnerability debuffs.
    local buffFrac, debuffFrac = 0, 0
    if opts.buffMods ~= nil then
        buffFrac = sumFrac(opts.buffMods)
    elseif party and srcMods then
        buffFrac = sumFrac(srcMods.buffMods)
    end
    if opts.debuffMods ~= nil then
        debuffFrac = sumFrac(opts.debuffMods)
    elseif victimMods then
        debuffFrac = sumFrac(victimMods.debuffMods)
    end

    local final = baseAmount * (1 + buffFrac + debuffFrac)

    -- SHIELD: flat fraction of incoming damage removed (0..0.95, additive,
    -- clamped by status.getMods). Applies BEFORE the party-side min-3 floor
    -- per the INTEGRATOR CONTRACT at the top of encounter/status.lua, so a
    -- shield can never push a hit below the floor — the floor still wins.
    -- victimMods was already fetched above (nil only when the status system
    -- is absent, in which case this is a no-op).
    if victimMods and victimMods.shieldReduction > 0 then
        final = final * (1 - victimMods.shieldReduction)
    end

    local negated = false
    if party then
        -- Flat armor subtract (BH: -(defense + sentinelDefense); CR has DEF
        -- plus any status-sourced flat armor, e.g. bard armor / Defend).
        local armor = math.max(0, statGet(vs.DEF) + (opts.defFlat or 0))
        final = final - armor

        -- Minimum-3 floor (party side only).
        final = math.max(3, final)

        -- Ward / full-negation hook.
        if opts.negate then
            final = 0
            negated = true
        end
    else
        final = math.max(0, final)  -- no min-3 floor on the enemy side
    end

    -- Reflect / thorns hook (party side only): a fraction of the dealt damage
    -- is returned as damage to the attacker. status.reflectDamage owns the
    -- fraction lookup + HP application when available; otherwise we apply a
    -- flat fraction here.
    local reflected = 0
    if party and final > 0 then
        local refFrac = opts.reflect
        if refFrac == nil and victimMods then refFrac = victimMods.reflectFraction or 0 end
        if refFrac and refFrac > 0 then
            if status_mod.reflectDamage then
                reflected = status_mod.reflectDamage(world, srcId, victimId, final)
            else
                reflected = final * refFrac
                local ss = world.stats[srcId]
                if ss then ss.HP.base = math.max(0, ss.HP.base - reflected) end
            end
            final = 0
            negated = true
        end
    end

    return final, {crit=false, negated=negated, reflected=reflected}
end

-- ============================================================================
-- LEGACY ENTRY POINTS (backward-compatible, route through roll -> resolve)
-- ============================================================================

-- Backward-compat damage preview for the simple melee case:
-- attacker ATK vs defender DEF, no buffs, no crit.
--   old: max(0, (value*ATK*BOOST - DEF) * RES)
--   new: max(0, (value*ATK*BOOST - DEF) * RES) for party victims (identical
--        for the no-buff case); enemies take the raw roll (no armor).
function M.calcNormalDmg(world, srcId, tgtId, value)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return 0 end
    value = value or 1.0
    local boost = math.max(0.10, statGet(ss.BOOST))
    local res   = math.max(0.10, statGet(ts.RES))
    local base  = value * getPower(ss) * boost
    if isParty(world, tgtId) then
        return math.max(0, (base - statGet(ts.DEF)) * res)
    end
    return base * res
end

-- Backward-compat crit verdict. Only party attackers crit; enemies never do.
function M.resolveHit(world, srcId, tgtId)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return "HIT" end
    if not isParty(world, srcId) then return "HIT" end
    local crit = math.max(0, statGet(ss.CRIT) * (1 - statGet(ts.CRIT_DEF)))
    return math.random() < crit and "CRIT" or "HIT"
end

-- ============================================================================
-- STAGGER
-- ============================================================================

function M.applyStagger(world, tgtId, dmg)
    local sg, ss = world.stagger[tgtId], world.stats[tgtId]
    if not (sg and ss) or sg.staggered then return end
    sg.points = sg.points + dmg * statGet(ss.STAGGER_RES)
    if sg.points >= statGet(ss.MAX_STAGGER) then
        sg.points = 0; sg.staggered = true
        sg.timer = statGet(ss.STAGGER_DUR); sg.reversingAnim = false
        ss.RES.add = ss.RES.add + 1
        anim_mod.activateDeathAnim(world, tgtId, true)
        local lk = world.locks[tgtId]
        if lk then lk.actionLock = 9999 end
    end
end

-- ============================================================================
-- STUN
-- ============================================================================

function M.applyStun(world, tgtId, frames)
    local sn = world.stun[tgtId]; if not sn then return end
    local seconds = frames / 60
    sn.timer = sn.timer + seconds
    if not sn.stunned then
        sn.stunned = true
        local sg = world.stagger[tgtId]
        if not (sg and sg.staggered) then
            anim_mod.activateDeathAnim(world, tgtId, true)
        end
        local lk = world.locks[tgtId]
        if lk then lk.actionLock = 9999 end
    end
end

-- ============================================================================
-- THREAT
-- ============================================================================

function M.addThreat(world, enemyId, allyId, amount)
    local tm = world.threatMap[enemyId]
    if tm then tm.map[allyId] = (tm.map[allyId] or 0) + amount end
end

-- ============================================================================
-- MELEE RANGE CHECK
-- ============================================================================

function M.checkMeleeRange(world, srcId, tgtId)
    local sp, ss = world.position[srcId], world.size[srcId]
    local tp, ts = world.position[tgtId], world.size[tgtId]
    if not (sp and ss and tp and ts) then return false end
    local dx = math.max(0, math.abs(sp.x-tp.x) - (ss.w/2+ts.w/2))
    local dy = math.max(0, math.abs(sp.y-tp.y) - (ss.h/2+ts.h/2))
    return dx <= 6 and dy <= 2
end

-- ============================================================================
-- VFX TRIGGERS
-- ============================================================================

function M.triggerActivationVFX(battle, casterId, world)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+6, 20); vfx.chroma = math.min(vfx.chroma+2, 12)
    vfx.zoomTarget = 1.12
    local p = world.position[casterId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

local function triggerHitVFX(battle, tgtId, world)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+8, 20); vfx.chroma = math.min(vfx.chroma+3, 12)
    vfx.zoomTarget = 1.10
    local p = world.position[tgtId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

-- ============================================================================
-- REGISTER HIT / HEAL
-- ============================================================================

-- keywords (optional table) may carry:
--   ability = {aimedShot=bool, falloff=number}   — stage-1 roll options
--   buffMods = { [idx]=fraction }                — stage-2 additive fractions
--   negate  = bool                                — ward / full-negation hook
--   reflect = fraction                            — thorns hook (party victims)
function M.registerHit(world, battle, srcId, tgtId, keywords, useVFX, SCALE, GRAVITY)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    if world.hasAttacked then world.hasAttacked[srcId] = true end

    local kw = keywords or {}
    local rollOpts = kw.ability
    local resolveOpts = {
        buffMods = kw.buffMods,
        negate   = kw.negate,
        reflect  = kw.reflect,
    }

    -- Two-stage: attacker roll -> victim resolve.
    local baseAmount, isCrit = M.roll(world, srcId, tgtId, rollOpts)
    local dmg, flags = M.resolve(world, tgtId, baseAmount, srcId, resolveOpts)

    local ts = world.stats[tgtId]
    if ts then ts.HP.base = math.max(0, ts.HP.base - dmg) end

    M.applyStagger(world, tgtId, dmg)

    local srcSide = world.side[srcId]
    if srcSide and srcSide.s == 0 then
        local threatAmt = dmg * 0.5
        if world.hasThreateningPresence[srcId] then threatAmt = threatAmt * 2 end
        if world.threatMap[tgtId] then
            M.addThreat(world, tgtId, srcId, threatAmt)
        end
    end

    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(tgtId)) end

    particles.spawnBlood(world, battle, srcId, tgtId, isCrit, SCALE, GRAVITY)
    if useVFX then triggerHitVFX(battle, tgtId, world) end

    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp then
        local dx, dy = tp.x - sp.x, tp.y - sp.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.001 then dx, dy = dx/len, dy/len end
        local kbEc = world.effects_comp[tgtId]
        if kbEc then table.insert(kbEc.pending, effects_mod.newForce(tgtId, dx*60, dy*25, 0.12)) end
    end

    effects_mod.readTagSystem(world, battle, {src=srcId, tgt=tgtId, keywords=kw, amount=dmg})

    local tgtMt = world.moveTarget[tgtId]
    if world.targetSide[tgtId] == 1 and not world.entityTarget[tgtId]
       and not (tgtMt and tgtMt.active)
       and world.entities[srcId] and not world.deathState[srcId] then
        world.entityTarget[tgtId] = {id=srcId}
    end
end

function M.registerHeal(world, battle, srcId, tgtId, value, SCALE)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local ss = world.stats[srcId]; if not ss then return end
    local ts = world.stats[tgtId]; if not ts then return end
    local amount = value * getPower(ss) * math.max(0.10, statGet(ss.BOOST))
    local maxHp  = statGet(ts.maxHP)
    ts.HP.base = math.min(maxHp, ts.HP.base + amount)
    particles.spawnHeal(world, battle, tgtId, SCALE)
    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHealIndicator(tgtId)) end
end

return M

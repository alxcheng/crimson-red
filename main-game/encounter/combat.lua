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
-- M.registerHit is the one entry point abilities use: roll -> resolve -> apply.

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
--     buffMods   = { [index]=fraction } — overrides the attacker's own
--                 outgoing-damage buffs (default: read from its statuses)
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
        offenseFrac = sumFrac(status_mod.getMods(world, srcId).buffMods)
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
--     buffMods   = { [i]=fraction } — the hit's own damage multiplier, as
--                  additive fractions (0.5 = +50%, -0.5 = half damage)
--     debuffMods = { [i]=fraction } — overrides the victim's damage-taken
--                  debuffs (default: read from its statuses)
--     negate     = bool     — force / forbid WARD negation (default: rolled)
--     reflect    = fraction — override the victim's REFLECT fraction
-- Returns finalDamage (>= 0), flags {negated, reflected}.
function M.resolve(world, victimId, baseAmount, srcId, opts)
    local vs = world.stats[victimId]
    if not vs then return 0, {negated=false, reflected=0} end
    opts = opts or {}

    local party = isParty(world, victimId)
    local victimMods = status_mod.getMods(world, victimId)

    -- Additive fractions of the base roll (BH: additive, never compounding):
    -- the hit's own multiplier (opts.buffMods, e.g. Sneak Attack) plus the
    -- victim's damage-taken debuffs (e.g. VULNERABILITY). The attacker's own
    -- buffs were already applied in M.roll.
    local buffFrac   = sumFrac(opts.buffMods)
    local debuffFrac = sumFrac(opts.debuffMods or victimMods.debuffMods)

    local final = baseAmount * (1 + buffFrac + debuffFrac)

    -- SHIELD: fraction of incoming damage removed (0..0.95). Applied BEFORE
    -- the party-side min-3 floor, so the floor still wins.
    if victimMods.shieldReduction > 0 then
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

        -- WARD: chance to negate the hit outright (rolled here unless the
        -- caller already decided via opts.negate).
        local negate = opts.negate
        if negate == nil and victimMods.negationChance > 0 then
            negate = math.random() < victimMods.negationChance
        end
        if negate then
            final = 0
            negated = true
        end
    else
        final = math.max(0, final)  -- no min-3 floor on the enemy side
    end

    -- REFLECT (party side only): the victim takes nothing and a fraction of
    -- the hit is dealt back to the attacker.
    local reflected = 0
    if party and final > 0 then
        local refFrac = opts.reflect or victimMods.reflectFraction
        if refFrac > 0 then
            reflected = final * refFrac
            local ss = world.stats[srcId]
            if ss and not world.deathState[srcId] then
                ss.HP.base = math.max(0, ss.HP.base - reflected)
            end
            final = 0
            negated = true
        end
    end

    return final, {negated=negated, reflected=reflected}
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
    -- BH's melee gate is a FLAT center-to-center distance test (attack fires
    -- iff dist <= 1.8 + aoeRadiusBonus); sprite size never enters the test —
    -- it only enters via the per-target authored slot offsets. We mirror that:
    -- a per-attacker "reach" (base 6 [tuned] + a fraction of the attacker's
    -- own body, so bigger melee units swing a bit farther) is compared against
    -- the horizontal GAP between bodies, instead of one global 6px slack that
    -- skewed badly when source/target sizes differ (a big boss vs a small
    -- melee read "in range" from far away; the reverse read "out of range"
    -- while visually touching). Vertical tolerance is a generous height band
    -- [tuned] since all units are feet-aligned and 39-78px tall; the old 2px
    -- was too tight and produced the "near but out / far but in" artifact.
    local reach = 6 + 0.25 * ss.w   -- [tuned] BH flat-reach analogue
    local gapX  = math.max(0, math.abs(sp.x - tp.x) - (ss.w/2 + ts.w/2))
    local inRangeX = gapX <= reach
    local inRangeY = math.abs(sp.y - tp.y) <= 18  -- [tuned] feet-aligned height band
    return inRangeX and inRangeY
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

-- Deal one hit from srcId to tgtId and apply everything that follows from it
-- (HP, stagger, threat, hurt flash, blood, knockback nudge, on-hit passives).
--   hit (optional table):
--     tags     = { "Melee", "Fire", ... }  — what kind of hit this is; passives
--                and on-hit statuses react to these (e.g. "Melee")
--     ability  = { aimedShot, falloff, canCrit } — roll options (see M.roll)
--     buffMods = { [idx] = fraction }      — extra outgoing-damage fractions
--   useVFX: true = screen shake / zoom punch on the target
-- Performance score per hero unit (BH `browniePoints`): the best scorers get
-- bonus XP on the victory screen. +4 per damaging hit, +20 per kill, +5 per
-- heal, +20 per ability used.
function M.addScore(battle, unitId, points)
    battle.score = battle.score or {}
    battle.score[unitId] = (battle.score[unitId] or 0) + points
end

function M.registerHit(world, battle, srcId, tgtId, hit, useVFX)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    hit = hit or {}
    local tags = hit.tags or {}

    local baseAmount, isCrit = M.roll(world, srcId, tgtId, hit.ability)
    local dmg = M.resolve(world, tgtId, baseAmount, srcId, { buffMods = hit.buffMods })

    local ts = world.stats[tgtId]
    local wasAlive = ts and ts.HP.base > 0
    if ts then ts.HP.base = math.max(0, ts.HP.base - dmg) end

    M.applyStagger(world, tgtId, dmg)

    local srcSide = world.side[srcId]
    if srcSide and srcSide.s == 0 then
        -- Performance score: +4 a hit, +20 a kill (BH browniePoints).
        M.addScore(battle, srcId, (wasAlive and ts.HP.base <= 0) and 24 or 4)
        local threatAmt = dmg * 0.5
        if world.hasThreateningPresence[srcId] then threatAmt = threatAmt * 2 end
        if world.threatMap[tgtId] then
            M.addThreat(world, tgtId, srcId, threatAmt)
        end
    end

    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(tgtId)) end

    particles.spawnBlood(world, battle, srcId, tgtId, isCrit, battle.SCALE, battle.GRAVITY)
    if useVFX then triggerHitVFX(battle, tgtId, world) end

    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp then
        local dx, dy = tp.x - sp.x, tp.y - sp.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.001 then dx, dy = dx/len, dy/len end
        local kbEc = world.effects_comp[tgtId]
        if kbEc then table.insert(kbEc.pending, effects_mod.newForce(tgtId, dx*60, dy*25, 0.12)) end
    end

    effects_mod.readTagSystem(world, battle, {src=srcId, tgt=tgtId, tags=tags, amount=dmg})

    -- CHAIN status (Paladin Wrath): each MELEE hit by the carrier arcs to
    -- nearby foes and uses up one charge (the status magnitude counts charges).
    local isMelee = false
    for _, t in ipairs(tags) do if t == "Melee" then isMelee = true; break end end
    local store = world.status and world.status[srcId]
    local chain = store and store.buffs[status_mod.CHAIN]
    if isMelee and chain and (chain.magnitude or 0) > 0 then
        chain.magnitude = chain.magnitude - 1
        if chain.magnitude <= 0 then status_mod.remove(world, srcId, true, status_mod.CHAIN) end
        M.chainHit(world, battle, srcId, tgtId, chain.chainParams or {})
    end

    local tgtMt = world.moveTarget[tgtId]
    if world.targetSide[tgtId] == 1 and not world.entityTarget[tgtId]
       and not (tgtMt and tgtMt.active)
       and world.entities[srcId] and not world.deathState[srcId] then
        world.entityTarget[tgtId] = {id=srcId}
    end
end

-- After `primaryId` was hit by `srcId`, hit up to chain.count other living
-- enemies nearest to it, each for decay^i of a normal hit. Chain hops carry
-- no tags, so they can never chain again.
function M.chainHit(world, battle, srcId, primaryId, chain)
    local count, decay = chain.count or 3, chain.decay or 0.5
    local pp = world.position[primaryId]
    if not pp then return end
    local cands = {}
    for eid in pairs(world.entities) do
        local sd, ep = world.side[eid], world.position[eid]
        if sd and sd.s == 1 and eid ~= primaryId and ep and not world.deathState[eid] then
            local dx, dy = ep.x - pp.x, ep.y - pp.y
            cands[#cands+1] = {id = eid, d2 = dx*dx + dy*dy}
        end
    end
    table.sort(cands, function(a, b) return a.d2 < b.d2 end)
    for i = 1, math.min(count, #cands) do
        M.registerHit(world, battle, srcId, cands[i].id, {
            buffMods = { [0] = decay ^ i - 1 },   -- total multiplier = decay^i
            ability  = { canCrit = false },
        }, true)
    end
end

-- Heal tgtId for value x the healer's power (capped at max HP).
function M.registerHeal(world, battle, srcId, tgtId, value)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local ss = world.stats[srcId]; if not ss then return end
    local ts = world.stats[tgtId]; if not ts then return end
    local amount = value * getPower(ss) * math.max(0.10, statGet(ss.BOOST))
    local maxHp  = statGet(ts.maxHP)
    ts.HP.base = math.min(maxHp, ts.HP.base + amount)
    M.addScore(battle, srcId, 5)
    particles.spawnHeal(world, battle, tgtId, battle.SCALE)
    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHealIndicator(tgtId)) end
end

return M

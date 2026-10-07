-- encounter/status.lua — Centralized, indexed buff/debuff (status effect) system
--
-- Data-driven status effects, modeled on Battleheart's indexed
-- buff/debuff tables: each entity carries `buffs` and `debuffs` (index ->
-- active-entry maps) and the magnitude/duration of every index is looked up
-- against M.buffMagnitudes / M.debuffMagnitudes (+ ...Durations).
--
-- This module owns the DATA/LOGIC of status effects only. It deliberately does
-- NOT touch CR's animation/timing engine (anim.lua / the timed-action pipeline)
-- and does NOT perform the damage math itself. The damage system (combat.lua,
-- being rewritten to a two-stage roll -> resolve) CONSUMES the aggregate mods
-- produced by M.getMods / M.resolveNegate / M.reflectDamage — see the contract
-- documented at the top of each of those functions.
--
-- Adding a new status = add a row to the magnitude tables (and, only if it has
-- bespoke behavior, a small handler below). No big per-effect closures.
--
-- ============================================================================
-- INTEGRATOR CONTRACT — value-exposure only; status.lua does NOT edit other
-- modules. The following two wiring lines are REQUIRED for the new statuses to
-- take effect. status.lua exposes every value they need.
-- ============================================================================
--
-- (1) SLOW (debuff idx 3) — movement speed.
--     systems.lua, M.moveTarget, around the line
--         local spd = statGet(ss.MOVE_SPEED) * 30
--     change it to multiply by the slow factor:
--         local spd = statGet(ss.MOVE_SPEED) * 30 * status_mod.getSlowFactor(world, id)
--     (status_mod is already required in systems.lua for other stats).
--
-- (2) SHIELD (buff idx 9) — flat % incoming-damage reduction.
--     combat.lua, M.resolve, at the point where final damage to the victim is
--     about to be applied, BEFORE the min-3 floor, subtract the shield
--     reduction fraction of the computed damage (it is a FRACTION REMOVED,
--     additive, already clamped to <= 0.95 by getMods):
--         local modsV = status_mod.getMods(world, victimId)
--         finalDamage = finalDamage * (1 - modsV.shieldReduction)
--     Keep the existing min-3 floor AFTER this line, exactly as it is now.
--
-- Note: WARD and SHIELD are distinct on purpose — WARD is a % chance to FULLY
-- negate a hit (probabilistic), SHIELD ALWAYS reduces by a fixed fraction.
-- PARALYZE (buff idx 8) is a hard immobilize distinct from STUN: it locks the
-- entity via world.locks[id].actionLock = 9999, triggers NO death-anim and NO
-- stagger interaction; its lock is released on expire only when the entity is
-- not also stunned/staggered (mirrors systems.stagger's lock release).

local stats_mod = require("encounter/stats")

local M = {}

local statGet = stats_mod.get

-- ============================================================================
-- EFFECT-TINT BRIDGE — status.lua reuses effects.lua's tint helpers so HoT /
-- buffs / debuffs can show the same undulating tint as before. Loaded lazily
-- to avoid a hard require cycle at load time.
--
-- ORDERING NOTE: these MUST be defined BEFORE M.onApply / M.onExpire below,
-- because those handlers call them at run time (they are plain locals, not
-- M fields — a forward reference would resolve to nil).
-- ============================================================================

local function effects_addTint(world, id, r, g, b, speed)
    local eff = require("encounter/effects")
    return eff.addEffectTint(world, id, r, g, b, speed)
end
local function effects_removeTint(world, id, entry)
    local eff = require("encounter/effects")
    eff.removeEffectTint(world, id, entry)
end

-- ============================================================================
-- STATUS INDICES (readable names we assigned — Battleheart's index->name map is
-- not in the assembly, so we define our own, matching its mechanical roles)
-- ============================================================================

-- Buff indices (entity.buffs[index] active)
M.ATK_BUFF     = 1   -- power/attack buff  -> outgoing damage up (Grant Power)
M.DEF_BUFF     = 2   -- defense/armor buff -> flat DEF up (Knight Defend)
M.WARD         = 3   -- % chance to fully negate an incoming hit
M.REFLECT      = 4   -- thorns: return a fraction of damage taken
M.HOT          = 5   -- heal over time (Mend Wounds / self-Healing)
M.STUN         = 6   -- hard CC slot (coexists with world.stun)
M.FEAR         = 7   -- SLOT ONLY — no behavior yet (later enemy-AI task)
M.PARALYZE     = 8   -- hard immobilize: actionLock = 9999 (no death-anim, no stagger)
M.SHIELD       = 9   -- flat % REDUCTION of incoming damage, always applies (Cleric Shield −75%)

-- Debuff indices (entity.debuffs[index] active)
M.VULNERABILITY = 1  -- "marked": incoming damage taken up (generalizes Sunder Armor)
M.DOT           = 2  -- damage over time, ticks continuously (Poisoned Knife / Conflagrate)
M.SLOW          = 3  -- movement-slow: fraction of MOVE_SPEED removed (Blizzard 10 s)

-- Default durations (seconds). `duration` on apply() overrides these.
M.buffDurations = {
    [M.ATK_BUFF]   = 10,
    [M.DEF_BUFF]   = 10,
    [M.WARD]       = 10,
    [M.REFLECT]    = 10,
    [M.HOT]        = 10,
    [M.STUN]       = 2,
    [M.FEAR]       = 3,
    [M.PARALYZE]   = 3,
    [M.SHIELD]     = 10,
}
M.debuffDurations = {
    [M.VULNERABILITY] = 10,
    [M.DOT]           = 10,
    [M.SLOW]          = 10,
}

-- ============================================================================
-- MAGNITUDE TABLES — what each index does and how strongly
--
-- Convention: a magnitude is expressed as a FRACTION of a base quantity, used
-- additively (no compounding), consistent with Battleheart:
--   VULNERABILITY : +magnitude of incoming damage taken (per hit)
--   ATK_BUFF      : +magnitude of outgoing damage (per hit)
--   DEF_BUFF      : +magnitude flat to the DEF stat
--   WARD          : magnitude = chance (0..1) to fully negate a hit
--   REFLECT       : magnitude = fraction of damage taken returned to attacker
--   HOT           : magnitude = heal per second
--   SHIELD        : magnitude = fraction of INCOMING damage REMOVED (always
--                   applies, NOT a chance). Additive across stacks; total
--                   clamped to [0, 0.95] in getMods so a shield can never
--                   fully negate a hit by itself. Distinct from WARD.
--   SLOW          : magnitude = FRACTION of MOVE_SPEED removed (0.4 = target
--                   moves at 60% speed). Additive across stacks; the exposed
--                   slowFactor is clamped to [0, 1].
--   DOT           : magnitude = damage PER SECOND, seeded at cast time (the
--                   ability passes it); ticks continuously in M.tick like HOT.
--   PARALYZE      : magnitude ignored; the lock is the behavior itself.
-- ============================================================================

M.buffMagnitudes = {
    [M.ATK_BUFF]  = 0.5,  -- +50% outgoing damage (Grant Power: ATK.mult +0.5)
    [M.DEF_BUFF]  = 0.5,  -- flat DEF bonus (Knight Defend magnitude)
    [M.WARD]      = 0.25, -- 25% chance to fully negate
    [M.REFLECT]   = 0.5,  -- return 50% of damage taken (BH thorns ~50-60%)
    [M.HOT]       = 6,    -- 6 HP/sec (matches old self-Healing rate)
    [M.STUN]      = 0,
    [M.FEAR]      = 0,
    [M.PARALYZE]  = 0,
    [M.SHIELD]    = 0.75, -- remove 75% of incoming damage (Cleric Shield)
}
M.debuffMagnitudes = {
    [M.VULNERABILITY] = 0.25, -- +25% incoming damage taken (marked)
    [M.DOT]           = 0,    -- magnitude seeded at cast time, not a table value
    [M.SLOW]          = 0.4,  -- remove 40% of MOVE_SPEED (Blizzard default)
}

-- ============================================================================
-- ENTITY STORE (per entity: buffs + debuffs, index -> entry)
-- ============================================================================

local function getStore(w, id)
    if not w.status then w.status = {} end
    local s = w.status[id]
    if not s then
        s = {buffs = {}, debuffs = {}}
        w.status[id] = s
    end
    return s
end

-- ============================================================================
-- APPLY — start/refresh a status on an entity
-- ============================================================================

-- M.apply(world, id, isBuff, index, magnitude, duration)
--   world       : the battle `w` table (ECS world)
--   id          : entity id
--   isBuff      : true -> buffs map, false -> debuffs map
--   index       : one of M.<NAME>
--   magnitude   : optional explicit magnitude (overrides the table default)
--   duration    : optional seconds (overrides the table default). nil => table.
-- Returns the active entry. Re-applying refreshes the duration and (optionally)
-- the magnitude.
function M.apply(world, id, isBuff, index, magnitude, duration)
    if not world.entities[id] then return nil end
    local store = getStore(world, id)
    local map = isBuff and store.buffs or store.debuffs
    local durs = isBuff and M.buffDurations or M.debuffDurations
    local mags = isBuff and M.buffMagnitudes or M.debuffMagnitudes

    local dur = duration or durs[index] or 0
    local mag = (magnitude ~= nil) and magnitude or (mags[index] or 0)

    local existing = map[index]
    if existing then
        existing.duration = dur
        existing.magnitude = mag
        -- refresh per-tick accumulators
        existing.tickTimer = 0
        return existing
    end

    local entry = {
        index      = index,
        magnitude  = mag,
        duration   = dur,
        maxDuration = dur,
        tickTimer  = 0,
    }
    map[index] = entry

    local h = M.onApply
    if h then h(world, id, isBuff, entry) end
    return entry
end

-- M.remove(world, id, isBuff, index) — drop one status immediately
function M.remove(world, id, isBuff, index)
    local s = world.status and world.status[id]
    if not s then return end
    local map = isBuff and s.buffs or s.debuffs
    local e = map[index]
    if not e then return end
    map[index] = nil
    local h = M.onExpire
    if h then h(world, id, isBuff, e) end
end

-- M.clear(world, id) — drop all statuses (e.g. on death)
function M.clear(world, id)
    local s = world.status and world.status[id]
    if not s then return end
    for _, isBuff in ipairs({true, false}) do
        local map = isBuff and s.buffs or s.debuffs
        for idx in pairs(map) do M.remove(world, id, isBuff, idx) end
    end
    world.status[id] = nil
end

-- ============================================================================
-- TICK / SYSTEM — advance durations, tick HoTs, expire
--
-- M.system(world, battle, dt) is the pipeline hook (same signature as
-- effects_mod.system). It also aliases to M.tick for clarity.
-- ============================================================================

-- M.tickHot(world, id, entry, dt) — heal `magnitude` HP/sec, capped at maxHP.
function M.tickHot(world, id, entry, dt)
    local ss = world.stats and world.stats[id]
    if not ss then return end
    local maxHp = statGet(ss.maxHP)
    if statGet(ss.HP) >= maxHp then return end
    ss.HP.base = math.min(maxHp, ss.HP.base + (entry.magnitude or 0) * dt)
end

-- M.tickDot(world, id, entry, dt) — drain `magnitude` HP/sec (floor 0),
-- continuous, the damage-side mirror of M.tickHot.
function M.tickDot(world, id, entry, dt)
    local ss = world.stats and world.stats[id]
    if not ss then return end
    if entry.magnitude and entry.magnitude > 0 then
        ss.HP.base = math.max(0, ss.HP.base - entry.magnitude * dt)
    end
end

function M.tick(world, dt)
    local w = world
    if not w.status then return end
    for id, s in pairs(w.status) do
        if not w.entities[id] or w.deathState[id] then
            M.clear(w, id)
            goto continue
        end
        for _, isBuff in ipairs({true, false}) do
            local map = isBuff and s.buffs or s.debuffs
            for idx, e in pairs(map) do
                -- tick DoTs / HoTs (continuous, like CR's existing HoT timing)
                if idx == M.HOT then
                    M.tickHot(w, id, e, dt)
                elseif idx == M.DOT then
                    M.tickDot(w, id, e, dt)
                end
                e.duration = e.duration - dt
                if e.duration <= 0 then
                    map[idx] = nil
                    local h = M.onExpire
                    if h then h(w, id, isBuff, e) end
                end
            end
        end
        ::continue::
    end
end

-- Pipeline-facing entry point. battle is accepted for signature symmetry but
-- unused by the core; handlers may use it.
function M.system(world, battle, dt)
    M.tick(world, dt)
end

-- ============================================================================
-- GET MODS — aggregate the entity's statuses into the table the damage system
-- consumes (see combat.resolve contract in the report).
--
-- Returns {
--   buffMods        = { [index] = additiveFraction },  -- OUTGOING dmg up (attacker side)
--   debuffMods      = { [index] = additiveFraction },  -- INCOMING dmg up (victim side, e.g. vuln)
--   defFlat         = number,   -- flat DEF bonus to add before armor subtract
--   negationChance  = number,   -- 0..1 chance to fully negate an incoming hit (Ward)
--   reflectFraction = number,   -- fraction of incoming damage returned to attacker
--   hotPerSec       = number,   -- informational: heal/sec currently ticking
--   shieldReduction = number,   -- NEW: fraction of incoming damage REMOVED (0..0.95)
--   slowFactor      = number,   -- NEW: movement-speed multiplier (1 = normal, lower = slower)
-- }
-- The damage agent consumes `buffMods` (attacker) and `debuffMods` + the
-- negation/reflect fields (victim), all additively.
--
-- NEW FIELDS (added, existing fields unchanged — see header INTEGRATOR CONTRACT):
--   shieldReduction : consumed by combat.resolve (victim) BEFORE the min-3 floor.
--   slowFactor      : consumed by systems.moveTarget (victim) as a speed multiplier.
--   Both are ALSO exposed via dedicated getters (M.getShieldReduction /
--   M.getSlowFactor) for call sites that don't want a full getMods() table.
-- ============================================================================

function M.getMods(world, id)
    local mods = {
        buffMods        = {},
        debuffMods      = {},
        defFlat         = 0,
        negationChance  = 0,
        reflectFraction = 0,
        hotPerSec       = 0,
        shieldReduction = 0,
        slowFactor      = 1,
    }
    local s = world.status and world.status[id]
    if not s then return mods end

    for idx, e in pairs(s.buffs) do
        local mag = e.magnitude or 0
        if idx == M.ATK_BUFF then
            -- additive outgoing-damage fraction (attacker side)
            mods.buffMods[idx] = (mods.buffMods[idx] or 0) + mag
        elseif idx == M.DEF_BUFF then
            mods.defFlat = mods.defFlat + mag
        elseif idx == M.WARD then
            mods.negationChance = math.max(mods.negationChance, mag)
        elseif idx == M.REFLECT then
            mods.reflectFraction = math.max(mods.reflectFraction, mag)
        elseif idx == M.HOT then
            mods.hotPerSec = mods.hotPerSec + mag
        elseif idx == M.SHIELD then
            -- additive fraction REMOVED from incoming damage, clamped 0..0.95
            -- so a shield alone can never fully negate a hit
            mods.shieldReduction = mods.shieldReduction + mag
        end
    end

    for idx, e in pairs(s.debuffs) do
        local mag = e.magnitude or 0
        if idx == M.VULNERABILITY then
            mods.debuffMods[idx] = (mods.debuffMods[idx] or 0) + mag
        end
        -- SLOW is aggregated via M.getSlowFactor below; DOT ticks in M.tickDot
    end

    mods.shieldReduction = math.min(0.95, math.max(0, mods.shieldReduction))
    if s.debuffs[M.SLOW] then
        mods.slowFactor = M.getSlowFactor(world, id)
        -- (stays 1 from table init when no SLOW is active)
    end
    return mods
end

-- M.getSlowFactor(world, id) -> number in [0..1]
-- Movement-speed multiplier: 1 = normal speed, lower = slower.
-- = max(0, 1 - sum of active SLOW magnitudes), clamped to [0, 1].
-- INTEGRATOR: systems.lua M.moveTarget must multiply its `spd` by this
-- (see the INTEGRATOR CONTRACT in the file header).
function M.getSlowFactor(world, id)
    local s = world.status and world.status[id]
    if not s then return 1 end
    local sum = 0
    for idx, e in pairs(s.debuffs) do
        if idx == M.SLOW then
            sum = sum + (e.magnitude or 0)
        end
    end
    if sum <= 0 then return 1 end
    return math.max(0.0, math.min(1.0, 1 - sum))
end

-- M.getShieldReduction(world, id) -> number in [0..0.95]
-- Flat fraction of incoming damage REMOVED (additive stacks, clamped).
-- INTEGRATOR: combat.lua M.resolve must apply finalDamage * (1 - this)
-- BEFORE its min-3 floor (see the INTEGRATOR CONTRACT in the file header).
function M.getShieldReduction(world, id)
    local s = world.status and world.status[id]
    if not s then return 0 end
    local sum = 0
    for idx, e in pairs(s.buffs) do
        if idx == M.SHIELD then
            sum = sum + (e.magnitude or 0)
        end
    end
    return math.max(0, math.min(0.95, sum))
end

-- ============================================================================
-- DAMAGE-RESOLUTION HELPERS (called by combat.resolve / the damage agent)
--
-- M.resolveNegate(world, id) -> boolean
--   Returns true if the entity's WARD fully negates this hit (roll now).
--   Call once per incoming hit BEFORE applying damage.
-- ============================================================================

function M.resolveNegate(world, id)
    local mods = M.getMods(world, id)
    if mods.negationChance > 0 and math.random() < mods.negationChance then
        return true
    end
    return false
end

-- ============================================================================
-- M.reflectDamage(world, attackerId, victimId, amount)
--   After `amount` damage is dealt to `victimId`, the victim's REFLECT returns
--   a fraction of it back to `attackerId`. This does NOT recurse (a reflected
--   hit does not itself reflect). Returns the reflected amount (0 if none).
--   The damage agent calls this inside resolve(); the actual HP subtraction is
--   the damage agent's responsibility (or call M.dealReflectedHP below).
-- ============================================================================

function M.reflectDamage(world, attackerId, victimId, amount)
    local mods = M.getMods(world, victimId)
    if mods.reflectFraction <= 0 then return 0 end
    local reflected = amount * mods.reflectFraction
    M.dealReflectedHP(world, attackerId, reflected)
    return reflected
end

-- M.dealReflectedHP(world, targetId, amount) — subtract reflected damage from
-- an entity's HP (capped at 0). Kept separate so the damage agent can reuse it.
function M.dealReflectedHP(world, targetId, amount)
    if amount <= 0 then return end
    local ts = world.stats and world.stats[targetId]
    if not ts or (world.deathState and world.deathState[targetId]) then return end
    ts.HP.base = math.max(0, ts.HP.base - amount)
end

-- ============================================================================
-- CUSTOM-BEHAVIOR HOOKS (onApply / onExpire) — only for statuses whose effect
-- is a direct stat mutation or a visual that cannot be expressed purely as a
-- damage-mod fraction. Data-driven statuses (vuln, ward, reflect, atk, hot)
-- need no hook.
-- ============================================================================

-- onApply(world, id, isBuff, entry)
-- Direct stat / lock / tint side-effects (NOT damage-mod fractions):
--   DEF_BUFF  -> DEF.add  + magnitude  (Knight Defend)
--   HOT       -> begin green heal-over-time tint
--   SHIELD    -> gold/white tint (damage reduction is read from getMods)
--   SLOW      -> light blue/purple tint (speed factor read from getSlowFactor)
--   DOT       -> red/orange tint (damage ticks in M.tickDot)
--   PARALYZE  -> actionLock = 9999 hard freeze (no death-anim, no stagger)
function M.onApply(world, id, isBuff, entry)
    if isBuff and entry.index == M.DEF_BUFF then
        local ss = world.stats and world.stats[id]
        if ss then ss.DEF.add = ss.DEF.add + entry.magnitude end
        return
    end
    if isBuff and entry.index == M.HOT then
        entry.tint = effects_addTint(world, id, 0, 1, 0, 4.0)
        return
    end
    if isBuff and entry.index == M.SHIELD then
        -- subtle gold/white
        entry.tint = effects_addTint(world, id, 1.0, 0.9, 0.55, 3.0)
        return
    end
    if isBuff and entry.index == M.PARALYZE then
        local lk = world.locks and world.locks[id]
        if lk then
            -- only claim the lock if no other CC source currently owns it
            if (lk.actionLock or 0) < 9999 then
                lk.actionLock = 9999
                entry.setLock = true
            end
        end
        return
    end
    if not isBuff and entry.index == M.SLOW then
        -- subtle light blue/purple
        entry.tint = effects_addTint(world, id, 0.55, 0.65, 1.0, 3.0)
        return
    end
    if not isBuff and entry.index == M.DOT then
        -- red/orange burn/poison tint
        entry.tint = effects_addTint(world, id, 1.0, 0.35, 0.2, 4.0)
        return
    end
    -- FEAR / STUN: slots only; no behavior yet (STUN goes through combat.applyStun).
end

-- onExpire(world, id, isBuff, entry) — inverse of onApply
function M.onExpire(world, id, isBuff, entry)
    if isBuff and entry.index == M.DEF_BUFF then
        local ss = world.stats and world.stats[id]
        if ss then ss.DEF.add = ss.DEF.add - entry.magnitude end
        return
    end
    if isBuff and entry.index == M.HOT then
        if entry.tint then effects_removeTint(world, id, entry.tint) end
        return
    end
    if isBuff and entry.index == M.SHIELD then
        if entry.tint then effects_removeTint(world, id, entry.tint) end
        return
    end
    if isBuff and entry.index == M.PARALYZE then
        if entry.setLock then
            local lk = world.locks and world.locks[id]
            if lk then
                -- release ONLY if no other CC source still owns the lock
                -- (mirror systems.stagger: keep it if stunned; the stagger
                --  path releases 9999 itself, so we skip when staggered too)
                local sn = world.stun and world.stun[id]
                local sg = world.stagger and world.stagger[id]
                if not (sn and sn.stunned) and not (sg and sg.staggered) then
                    lk.actionLock = 0
                end
            end
            entry.setLock = nil
        end
        return
    end
    if not isBuff and (entry.index == M.SLOW or entry.index == M.DOT) then
        if entry.tint then effects_removeTint(world, id, entry.tint) end
        return
    end
end

return M

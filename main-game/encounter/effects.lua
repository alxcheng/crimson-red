-- encounter/effects.lua — Generic effect system + all effect constructors

local status_mod = require("encounter/status")

local M = {}

-- ============================================================================
-- EFFECT SYSTEM (processes pending → active → end lifecycle)
-- ============================================================================

function M.system(world, battle, dt)
    for id in pairs(world.entities) do
        local ec = world.effects_comp[id]; if not ec then goto continue end
        for _, eff in ipairs(ec.pending) do table.insert(ec.active, eff) end
        ec.pending = {}
        local toRemove = {}
        for i, eff in ipairs(ec.active) do
            if eff.startFlag then
                if eff.start then eff.start(world, battle, eff) end
                eff.startFlag = false
            end
            if eff.cancelFlag then
                table.insert(toRemove, i)
            else
                if not eff.endFlag and eff.active then eff.active(world, battle, eff, dt) end
                if eff.endFlag then
                    if eff.end_fn then eff.end_fn(world, battle, eff) end
                    table.insert(toRemove, i)
                end
            end
        end
        for i = #toRemove, 1, -1 do table.remove(ec.active, toRemove[i]) end
        ::continue::
    end
end

-- ============================================================================
-- INDICATOR EFFECTS (opaque colored overlay that fades)
-- ============================================================================

function M.newHurtIndicator(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, alpha=1.0, decayRate=2.5,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.alpha = eff.alpha - eff.decayRate * dt
            if eff.alpha <= 0 then eff.endFlag = true end
        end,
    }
end

function M.newHealIndicator(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, alpha=1.0, decayRate=2.5, isHeal=true,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.alpha = eff.alpha - eff.decayRate * dt
            if eff.alpha <= 0 then eff.endFlag = true end
        end,
    }
end

-- ============================================================================
-- FORCE EFFECT (knockback)
-- ============================================================================

function M.newForce(tgtId, fx, fy, duration)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, force_x=fx, force_y=fy, timer=duration,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true; return end
            local ph = w.physics[eff.target]
            if ph then ph.fx = ph.fx + eff.force_x; ph.fy = ph.fy + eff.force_y end
        end,
    }
end

-- ============================================================================
-- TIMED ACTION EFFECT (generic: countdown then fire end_fn)
-- ============================================================================

function M.newTimedAction(srcId, tgtId, timer, endFn, opts)
    opts = opts or {}
    return {
        startFlag=true, endFlag=false,
        isActionEffect = opts.isActionEffect ~= false,
        isAction       = opts.isAction ~= false,
        skillSlot      = opts.skillSlot or 0,
        src=srcId, tgt=tgtId, timer=timer,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = endFn,
    }
end

-- ============================================================================
-- CHARACTER-SPECIFIC PASSIVE EFFECTS
-- ============================================================================

function M.newKnightRage(srcId)
    return {
        startFlag=true, endFlag=false, src=srcId, resource=0, resourceMax=10,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.resource = math.max(0, eff.resource - 0.5 * dt)
            local s = w.stats[eff.src]
            if s then s.ATK.mult = 1.0 + eff.resource * 0.1 end
        end,
        conditional = function(w, b, eff, tag)
            if tag.src ~= eff.src then return end
            for _, kw in ipairs(tag.keywords or {}) do
                if kw == "Melee" then
                    eff.resource = math.min(eff.resourceMax, eff.resource + 1); break
                end
            end
        end,
    }
end

-- Migrated to the indexed status system: self-Healing is now the HOT status
-- (magnitude 6 HP/sec, 10s), driven by status.lua's tick. (Currently unused by
-- any skill, but kept table-driven for consistency with Mend Wounds.)
function M.newHealing(srcId, statGet)
    return {
        startFlag=true, endFlag=false, src=srcId, rate=6,
        start  = function(w, b, eff)
            eff.startFlag = false
            status_mod.apply(w, eff.src, true, status_mod.HOT, 6, 10.0)
        end,
        active = function(w, b, eff, dt) end,
    }
end

-- Migrated to the indexed status system: the DEF buff now lives in status.lua
-- (DEF_BUFF index, magnitude 0.5, 10s). The stagger-point drain is CR-specific
-- flavor that has no status-table analog, so it is kept as a thin local timer.
function M.newKnightDefend(srcId, statGet)
    return {
        startFlag=true, endFlag=false, isAction=false, isActionEffect=false, skillSlot=2,
        src=srcId, timer=10.0, drainPerSec=0, tintEntry=nil,
        start = function(w, b, eff)
            eff.startFlag = false
            -- DEF buff, now table-driven (DEF.add += 0.5 for 10s)
            status_mod.apply(w, eff.src, true, status_mod.DEF_BUFF, 0.5, 10.0)
            local sg = w.stagger[eff.src]
            eff.drainPerSec = sg and (sg.points / 2 / 10) or 0
            eff.tintEntry = M.addEffectTint(w, eff.src, 0, 0, 1, 4.0)
        end,
        active = function(w, b, eff, dt)
            if w.deathState[eff.src] then return end
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true; return end
            if eff.drainPerSec <= 0 then return end
            local sg = w.stagger[eff.src]
            if sg and not sg.staggered and sg.points > 0 then
                sg.points = math.max(0, sg.points - eff.drainPerSec * dt)
            end
        end,
        end_fn = function(w, b, eff)
            if eff.tintEntry then M.removeEffectTint(w, eff.src, eff.tintEntry) end
        end,
    }
end

-- ============================================================================
-- GRANT POWER (ATK mult +0.5 for 10 seconds, red undulating tint)
-- ============================================================================

-- Migrated to the indexed status system: the ATK buff now lives in status.lua
-- (ATK_BUFF index, magnitude 0.5 = +50% outgoing damage, 10s), consumed by
-- combat.resolve via getMods().buffMods. The red tint stays here (visual).
function M.newGrantPower(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, timer=10.0, tintEntry=nil,
        start = function(w, b, eff)
            eff.startFlag = false
            status_mod.apply(w, eff.target, true, status_mod.ATK_BUFF, 0.5, 10.0)
            eff.tintEntry = M.addEffectTint(w, eff.target, 1, 0, 0, 4.0)
        end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if eff.tintEntry then M.removeEffectTint(w, eff.target, eff.tintEntry) end
        end,
    }
end

-- ============================================================================
-- MEND WOUNDS (heal over time for 10 seconds, green undulating tint, no particles)
-- ============================================================================

-- Migrated to the indexed status system: Mend Wounds is now the HOT status
-- (magnitude = heal/sec = 5 * caster ATK, 10s), driven by status.lua's tick.
-- The green tint stays here (visual).
function M.newMendWounds(srcId, tgtId, statGet)
    local ss = statGet and statGet
    return {
        startFlag=true, endFlag=false,
        src=srcId, target=tgtId, timer=10.0, tintEntry=nil, statGet=ss,
        start = function(w, b, eff)
            eff.startFlag = false
            local srcStats = w.stats[eff.src]
            local healPerSec = srcStats and (5 * eff.statGet(srcStats.ATK)) / 10 or 0
            status_mod.apply(w, eff.target, true, status_mod.HOT, healPerSec, 10.0)
            eff.tintEntry = M.addEffectTint(w, eff.target, 0, 1, 0, 4.0)
        end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if eff.tintEntry then M.removeEffectTint(w, eff.target, eff.tintEntry) end
        end,
    }
end

-- ============================================================================
-- SUNDER ARMOR (reduces DEF by 1 for 10 seconds, stackable)
-- ============================================================================

-- Migrated to the indexed status system: Sunder Armor is now the VULNERABILITY
-- debuff (damage-taken up), the canonical "marked" role in Battleheart.
-- Magnitude 0.25 = +25% incoming damage for 10s (old effect was DEF.add -1).
function M.newSunderArmor(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, timer=10.0,
        start = function(w, b, eff)
            eff.startFlag = false
            status_mod.apply(w, eff.target, false, status_mod.VULNERABILITY, 0.25, 10.0)
        end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
    }
end

-- ============================================================================
-- EFFECT TINT HELPERS
-- ============================================================================

function M.addEffectTint(world, id, r, g, b, speed)
    if not world.effectTints[id] then world.effectTints[id] = {} end
    local entry = {R=r, G=g, B=b, intensity=0, speed=speed or 4.0, timer=0}
    table.insert(world.effectTints[id], entry)
    return entry
end

function M.removeEffectTint(world, id, entry)
    local list = world.effectTints[id]; if not list then return end
    for i, e in ipairs(list) do
        if e == entry then table.remove(list, i); return end
    end
end

-- ============================================================================
-- EFFECT TINT SYSTEM (updates undulating intensities)
-- ============================================================================

function M.effectTintSystem(world, dt)
    for id, list in pairs(world.effectTints) do
        for _, e in ipairs(list) do
            e.timer = e.timer + dt
            e.intensity = 0.5 + 0.5 * math.sin(e.timer * e.speed)
        end
    end
end

-- ============================================================================
-- TAG SYSTEM (broadcasts events to conditional effects)
-- ============================================================================

function M.readTagSystem(world, battle, tag)
    for _, ec in pairs(world.effects_comp) do
        for _, eff in ipairs(ec.active) do
            if eff.conditional then eff.conditional(world, battle, eff, tag) end
        end
    end
end

-- ============================================================================
-- CANCEL ACTION EFFECTS
-- ============================================================================

function M.cancelActions(world, id)
    local ec = world.effects_comp[id]; if not ec then return end
    local sk = world.skills[id]
    for _, eff in ipairs(ec.active) do
        if eff.isActionEffect then
            eff.cancelFlag = true
            if eff.skillSlot ~= nil and sk and sk.list[eff.skillSlot] then
                sk.list[eff.skillSlot].cd = 0
            end
        end
    end
    local sg = world.stagger[id]
    if sg and sg.staggered then return end
    local ac = world.anim[id]; if not ac then return end
    for _, a in pairs(ac.list) do a.active = false end
    if ac.list[1] then ac.list[1].active = true; ac.list[1].timer = 0 end
end

return M

-- encounter/effects.lua — Generic effect system + all effect constructors

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
            for _, kw in ipairs(tag.tags or {}) do
                if kw == "Melee" then
                    eff.resource = math.min(eff.resourceMax, eff.resource + 1); break
                end
            end
        end,
    }
end

-- Passive effect constructors by id (data/classes.lua `passive`). Each takes
-- the owner's entity id and returns an effect for its effects_comp.
M.PASSIVES = {
    KnightRage = M.newKnightRage,
}

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

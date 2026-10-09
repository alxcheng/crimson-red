-- encounter/skills.lua — WHEN units act: default-action and ability queues.
--
-- Each unit has two queues (world.skills[id]):
--   queue        — the default action (slot 0: auto-attack / auto-heal). Queued
--                  automatically whenever the unit has a target in range.
--   abilityQueue — active abilities (slots 1..4) in the order their keys were
--                  pressed. "Pay at press, activate when ready": the cooldown
--                  starts and the resource is spent when the key is pressed;
--                  the ability fires later, once the unit is free and in range.
-- WHAT an ability does is data (data/abilities.lua) run by encounter/abilities.lua.
--
-- Called once per frame from screens/encounter.lua, in this order:
--   M.autoAttackSystem(world)     -- queue slot 0 when in range & free
--   M.system(world, battle, dt)   -- tick cooldowns, fire the front of a queue
--                                    (at most one action per unit per frame)

local combat      = require("encounter/combat")
local abilities   = require("encounter/abilities")
local stats_mod   = require("encounter/stats")

local M = {}

-- ============================================================================
-- TUNING CONSTANTS
-- ============================================================================

-- Per-unit execution gate (seconds). After an ability fires, the unit cannot
-- fire another for EXEC_GATE seconds. This is NOT a global GCD — it is a
-- per-unit "just executed, wait a beat" so two abilities don't resolve in the
-- same frame. BH has no global GCD; pacing is per-ability cooldown.
M.EXEC_GATE = 0.4

-- ============================================================================
-- ENQUEUE — a player pressed an ability key (screens/encounter.lua)
--
-- Rejects (returns false, nothing spent) if the ability is on cooldown or the
-- shared resource is too low. Otherwise starts the cooldown, spends the
-- resource, queues the ability and returns true. Activation happens later in
-- M.system when the unit is free, in range, and this press is first in line.
-- ============================================================================

function M.enqueue(world, battle, unitId, slot)
    local sk = world.skills[unitId]
    if not sk then return false end
    local skill = sk.list[slot]
    if not skill then return false end

    -- Already on cooldown?
    if skill.cd > 0 then return false end

    -- Enough resource?
    local cost = skill.resourceCost or 0
    if (battle.resource or 0) < cost then return false end

    -- PAY AT PRESS: start cd + deduct resource immediately.
    skill.cd = skill.cdMax or 10.0
    if cost > 0 and battle.resource then
        battle.resource = math.max(0, battle.resource - cost)
    end

    -- Camera punch the instant a press is accepted; a second one fires when
    -- the ability actually goes off (M.system).
    combat.triggerActivationVFX(battle, unitId, world)

    -- QUEUE: push onto the per-unit ability queue (FIFO, press order).
    if not sk.abilityQueue then sk.abilityQueue = {} end
    table.insert(sk.abilityQueue, slot)

    return true
end

-- ============================================================================
-- SKILL SYSTEM (per-frame: tick cds, process ability queue, tick exec gate)
-- ============================================================================

-- Unit is able to act this frame? (not action-locked, not staggered/stunned)
local function unitIsFree(world, id)
    local lk = world.locks[id]
    if lk and lk.actionLock > 0 then return false end
    local sg = world.stagger[id]
    if sg and sg.staggered then return false end
    local sn = world.stun[id]
    if sn and sn.stunned then return false end
    return true
end

-- True if the unit can ACTIVATE a targeted ability right now (has a valid
-- living entityTarget in melee range when it's not ranged).
local function targetInRange(world, id)
    local et = world.entityTarget[id]
    if not et or not world.entities[et.id] or world.deathState[et.id] then return false end
    if not world.isRanged[id] and not combat.checkMeleeRange(world, id, et.id) then return false end
    return true
end

function M.system(world, battle, dt)
    for id in pairs(world.entities) do
        local sk = world.skills[id]
        if not sk then goto continue end

        -- Tick cooldowns.
        for _, skill in pairs(sk.list) do
            skill.cd = math.max(0, skill.cd - dt)
        end

        -- Tick the per-unit execution gate.
        if sk.execGate then
            sk.execGate = math.max(0, sk.execGate - dt)
        end

        -- Skip dead units.
        if world.deathState[id] then goto continue end

        -- Unit must be free and past the exec gate to act at all.
        if not unitIsFree(world, id) then goto continue end
        if sk.execGate and sk.execGate > 0 then goto continue end

        -- ---- 1. ACTIVE ABILITY QUEUE (front only — sequential, press order) ----
        local q = sk.abilityQueue
        if q and #q > 0 then
            local frontSlot = q[1]
            local skill = sk.list[frontSlot]
            local mt = world.moveTarget[id]
            if mt and mt.active then
                -- Still walking (a move order, or closing on its target):
                -- queued abilities are held until the unit stands still.
            elseif not skill then
                -- Stale slot (ability removed); drop it.
                table.remove(q, 1)
            elseif skill.noTargetRequired or targetInRange(world, id) then
                -- READY to attempt. `use` returns true only if it actually
                -- queued the timed-action (activated). We ALWAYS drop the
                -- front slot once attempted: on success the unit settles for
                -- EXEC_GATE before the next queued ability; on failure
                -- (dead/missing target) we drop it with NO refund, so a dead
                -- target can never re-fire / double-refund.
                local ok = skill.use(world, battle, id, skill)
                table.remove(q, 1)
                if ok then
                    sk.execGate = M.EXEC_GATE
                    -- Activation camera-punch (shake + chroma + zoom on the
                    -- caster). Only fires when the ability ACTUALLY activated
                    -- (use queued the timed effect) — not when a slot was
                    -- dropped for a dead target.
                    combat.triggerActivationVFX(battle, id, world)
                end
            end
            -- Not in range / no valid target yet → leave it queued; it waits
            -- until the unit gets in range (resource already paid at press).
            goto continue
        end

        -- ---- 2. DEFAULT-ACTION QUEUE (slot 0) ----
        local aq = sk.queue
        if aq and #aq > 0 then
            local slotIdx = table.remove(aq, 1)
            local skill = sk.list[slotIdx]
            if skill and skill.cd <= 0 and skill.use
               and (skill.noTargetRequired or targetInRange(world, id)) then
                if skill.use(world, battle, id, skill) then
                    -- The interval runs from the START of the action (BH:
                    -- actionTimer = 0 when the swing begins). Attack speed
                    -- shortens the interval; the animation is untouched.
                    local st = world.stats[id]
                    local speed = st and st.ATK_SPEED and math.max(0.1, stats_mod.get(st.ATK_SPEED)) or 1
                    skill.cd = skill.cdMax * abilities.AUTO_COOLDOWN_SCALE / speed
                end
                sk.execGate = M.EXEC_GATE
            end
        end

        ::continue::
    end
end

-- ============================================================================
-- AUTO-ATTACK SYSTEM — queue the default action (slot 0) for every unit that
-- has a living target in range and is free to act. Costs no resource.
-- ============================================================================

function M.autoAttackSystem(world)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local et = world.entityTarget[id]
        if not et or not world.entities[et.id] then goto continue end
        if world.deathState[et.id] then goto continue end
        local lk, sk = world.locks[id], world.skills[id]
        if not (lk and sk) then goto continue end

        -- Don't queue auto if an active ability is being queued/executing.
        local aq = sk.abilityQueue
        if aq and #aq > 0 then goto continue end

        if lk.actionLock > 0 then goto continue end
        local auto = sk.list[0]
        if not auto or auto.cd > 0 then goto continue end
        if not world.isRanged[id] and not combat.checkMeleeRange(world, id, et.id) then goto continue end
        local mt = world.moveTarget[id]
        if not world.isRanged[id] and mt and mt.active then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end

        -- Don't double-queue.
        local alreadyQueued = false
        if sk.queue then
            for _, qi in ipairs(sk.queue) do
                if qi == 0 then alreadyQueued = true; break end
            end
        end
        if not alreadyQueued then
            if not sk.queue then sk.queue = {} end
            table.insert(sk.queue, 0)
        end
        ::continue::
    end
end

-- ============================================================================
-- INTERRUPT — the player gave this unit a move order
--
-- Whatever the unit was winding up is stopped at once so it can walk away:
--   * a default action (auto-attack / auto-heal) that has not landed yet is
--     discarded, and its interval is reset so the next one is immediate when
--     the unit next has a target in range (BH: actionTimer = 100);
--   * an ability that has not landed yet goes back to the FRONT of the
--     ability queue — still paid for, cooldown still running — and starts its
--     wind-up again from the beginning once the unit stands still;
--   * an ability that already landed just loses the rest of its animation.
-- The move lock is cleared, so the unit starts walking this frame.
-- ============================================================================

function M.interrupt(world, id)
    local sk, ec = world.skills[id], world.effects_comp[id]
    if ec then
        local requeue = {}
        for _, list in ipairs({ ec.active, ec.pending }) do
            for i = #list, 1, -1 do
                local eff = list[i]
                if eff.isActionEffect then
                    table.remove(list, i)
                    if (eff.skillSlot or 0) > 0 then requeue[#requeue + 1] = eff.skillSlot end
                end
            end
        end
        if sk then
            for _, slot in ipairs(requeue) do table.insert(sk.abilityQueue, 1, slot) end
        end
    end
    if sk then
        if sk.list[0] then sk.list[0].cd = 0 end
        sk.queue = {}
    end
    local lk = world.locks[id]
    if lk then lk.moveLock = 0 end

    -- Back to the idle animation (a knocked-down unit keeps its pose).
    local sg, sn = world.stagger[id], world.stun[id]
    if (sg and sg.staggered) or (sn and sn.stunned) then return end
    local ac = world.anim[id]
    if ac then
        for _, a in pairs(ac.list) do a.active = false end
        if ac.list[1] then ac.list[1].active = true; ac.list[1].timer = 0 end
    end
end

return M

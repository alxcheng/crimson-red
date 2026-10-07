-- encounter/skills.lua — Skill system, auto-attack system, ability queueing
--
-- DATA-DRIVEN ABILITY LAYER: ability definitions live in encounter/abilities.lua
-- (M.DB). This module owns the per-frame SYSTEMS that drive those abilities:
--   - auto-attack queueing + execution (slot 0, unchanged behavior)
--   - active-ability queueing (Director's "pay at press, activate when ready"
--     model — replaces the old single-pendingActive + shared-GCD design)
--
-- ANIMATION/LOCK PRESERVATION: the `use` closures in abilities.lua trigger
-- ac.list[N].active=true / .timer=0 exactly as the old hand-coded closures did,
-- and queue effects through effects_mod.newTimedAction with the same delay
-- values. This module does NOT change anim.lua or animation timing.
--
-- CALL ORDER (same as the old pipeline — encounter.lua unchanged):
--   M.pendingActiveSystem(world, battle)  -- legacy no-op shim
--   M.autoAttackSystem(world)             -- queue slot 0 when in range & free
--   M.system(world, battle, dt)           -- tick cds/gate, execute queue fronts
--     (auto-attacks in sk.queue AND actives in sk.abilityQueue both execute
--      here, one unit-action per frame)

local combat      = require("encounter/combat")
local stats_mod   = require("encounter/stats")
local abilities   = require("encounter/abilities")

local statGet = stats_mod.get

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
-- SKILL FACTORY (data-driven via abilities.DB)
-- ============================================================================

-- Create a skill-instance for sk.list[slot]. Delegates to abilities.make(id)
-- and stamps the slot index for timed-action opts.
local function newSkillFromDB(abilityId, slot)
    local sk = abilities.make(abilityId)
    sk._slot = slot or 0
    return sk
end

-- ============================================================================
-- AUTO-ATTACK SKILL FACTORIES (data-driven wrappers)
--
-- These keep the old signatures so entities.lua works unchanged. Each returns
-- a skill-instance whose `use` closure triggers the correct anim slot +
-- timed-action delay from the DB row.
-- ============================================================================

function M.newKnightAutoAttackSkill(SCALE, GRAVITY)
    return newSkillFromDB("KnightAutoAttack", 0)
end

function M.newSkeletonAutoAttackSkill(SCALE, GRAVITY)
    return newSkillFromDB("SkeletonAutoAttack", 0)
end

function M.newNomadAutoHealSkill(SCALE)
    return newSkillFromDB("NomadAutoHeal", 0)
end

function M.newBrigandAutoAttackSkill(SCALE, GRAVITY)
    return newSkillFromDB("BrigandAutoAttack", 0)
end

function M.newChampionAutoAttackSkill(SCALE, GRAVITY)
    return newSkillFromDB("ChampionAutoAttack", 0)
end

function M.newDuelistAutoAttackSkill(SCALE, GRAVITY)
    return newSkillFromDB("DuelistAutoAttack", 0)
end

-- ============================================================================
-- ACTIVE SKILL FACTORIES (data-driven wrappers — same signatures as before)
-- ============================================================================

function M.newKnightSunderArmorSkill(SCALE, GRAVITY)
    return newSkillFromDB("KnightSunderArmor", 1)
end

function M.newKnightDefendSkill()
    return newSkillFromDB("KnightDefend", 2)
end

function M.newNomadGrantPowerSkill()
    return newSkillFromDB("NomadGrantPower", 1)
end

function M.newNomadMendWoundsSkill()
    return newSkillFromDB("NomadMendWounds", 2)
end

function M.newNomadSparkOfInspirationSkill()
    return newSkillFromDB("NomadSparkOfInspiration", 3)
end

function M.newKnightChallengingShoutSkill()
    return newSkillFromDB("KnightChallengingShout", 3)
end

-- ============================================================================
-- ENQUEUE (called from screens/encounter.lua keypress handler)
--
-- DIRECTOR'S QUEUEING MODEL — "pay at press, activate when ready":
--   1. Look up the ability for this unit+slot.
--   2. If on cooldown or insufficient resource → reject (no cost, no queue).
--   3. START the cooldown NOW (skill.cd = skill.cdMax).
--   4. DEDUCT resourceCost from battle.resource NOW.
--   5. PUSH the slot onto sk.abilityQueue.
--   6. Do NOT activate yet — activation happens in M.system() when the unit
--      is free, in range of a valid target, and this is the front of queue.
--
-- Returns true if enqueued, false if rejected.
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
            if not skill then
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

        -- ---- 2. AUTO-ATTACK QUEUE (slot 0, old behavior, unchanged cadence) ----
        local aq = sk.queue
        if aq and #aq > 0 then
            local slotIdx = table.remove(aq, 1)
            local skill = sk.list[slotIdx]
            if skill and skill.cd <= 0 and skill.use
               and (skill.noTargetRequired or targetInRange(world, id)) then
                skill.use(world, battle, id, skill)
                sk.execGate = M.EXEC_GATE
            end
        end

        ::continue::
    end
end

-- ============================================================================
-- AUTO-ATTACK SYSTEM (queues slot 0 when in range & unlocked)
--
-- Auto-attacks keep their existing path: they queue slot 0 into sk.queue (the
-- OLD queue, separate from abilityQueue) and are processed in M.system via
-- the same exec-gate-free path. Auto-attacks do NOT pay resource and do NOT
-- go through the queueing model — they fire when the unit is in range,
-- unlocked, and not executing an active ability.
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
-- PENDING ACTIVE SYSTEM (LEGACY SHIM — now a true no-op)
--
-- The old encounter.lua called pendingActiveSystem(world, battle) every frame
-- after setting sk.pendingActive = slot. The queueing model replaces that
-- entirely: the keypress handler now calls M.enqueue(world, battle, su, slot)
-- directly, and execution happens in M.system. This function is kept so the
-- existing pipeline call site does not crash before the integrator removes it.
-- ============================================================================

function M.pendingActiveSystem(world, battle)
    -- No-op. Kept for pipeline compatibility (integrator may remove the call).
end

-- ============================================================================
-- CLEANUP (called on entity death / reset)
-- ============================================================================

function M.clearQueues(world, id)
    local sk = world.skills[id]
    if not sk then return end
    sk.abilityQueue = {}
    sk.queue = {}
    sk.execGate = 0
end

return M

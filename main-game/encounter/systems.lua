-- encounter/systems.lua — Physics, movement, targeting, anti-clumping, death, stagger

local stats_mod  = require("encounter/stats")
local anim_mod   = require("encounter/anim")
local combat     = require("encounter/combat")
local status_mod = require("encounter/status")

local statGet = stats_mod.get

local M = {}

-- ============================================================================
-- 6-SLOT RING FORMATION — where melee attackers stand around their target
--
-- Each TARGET owns a symmetric 6-slot ring: 3 rings x 2 sides (left/right).
-- A slot is a GROUND (feet) point relative to the TARGET'S FEET:
--   x: the two bodies side by side — half the target's width + half the
--      attacker's width, times MELEE_SPACING — plus the ring's extra distance;
--   y: the ring's depth (outer rings stand a little lower on the stage).
-- Because x comes from the two body widths, changing a unit's spriteScale
-- moves its attackers in or out with it; nothing here needs retuning.
--
-- MELEE_SPACING is THE knob for how far apart two fighting units stand:
--   1.0 = their body boxes exactly touch, less = they overlap, more = a gap.
--
-- FEET CONVENTION (critical): world.position[id] is the entity's CENTER.
-- FEET = position.y + size.h/2. A slot is a GROUND point, so to store it as a
-- unit's moveTarget center we set position.y = groundY - size.h/2.
--
-- State: world.slots[targetId] = { [slotIndex] = ownerId }
-- slotIndex = (ring-1)*2 + side, ring in {1,2,3}, side in {1=left,2=right}.
-- ============================================================================

local NUM_RINGS = 3
local MELEE_SPACING = 0.8                                               -- [tuned]
-- Per ring: extra sideways distance beyond ring 1, and depth.
local RING = {
    [1] = { extraX = 0,  y = 0  },   -- inner
    [2] = { extraX = 26, y = 14 },   -- middle
    [3] = { extraX = 56, y = 32 },   -- outer
}

local function slotsFor(world, targetId)
    local t = world.slots; if not t then return nil end
    local s = t[targetId]
    if not s then s = {}; t[targetId] = s end
    return s
end

local function sideOf(world, tgtId, id, preferBack)
    local tp, sp = world.position[tgtId], world.position[id]
    if preferBack then
        local fc = world.facing[tgtId]
        -- preferBack: go to the side BEHIND the target (opposite its facing).
        return (fc and fc.right) and 1 or 2
    end
    if not (tp and sp) then return 2 end
    return (sp.x < tp.x) and 1 or 2
end

-- Move the occupant of slot `idx` to the nearest free slot further out on the
-- same side (slot indices on one side step by 2). Returns true if it moved.
local function displaceOutward(world, tgtId, idx)
    local s = world.slots and world.slots[tgtId]
    if not s then return false end
    local owner = s[idx]
    if not owner then return false end
    for outer = idx + 2, NUM_RINGS * 2, 2 do
        if s[outer] == nil then
            s[outer] = owner
            s[idx] = nil
            return true
        end
    end
    return false
end

-- Backfill after a release: pull the innermost occupied outer ring on `side`
-- inward, one ring at a time, until it sits adjacent to the freed hole.
local function backfillSide(world, tgtId, side)
    local s = world.slots and world.slots[tgtId]
    if not s then return end
    for r = 1, NUM_RINGS - 1 do
        local inner, outer = (r-1)*2 + side, r*2 + side
        if s[inner] == nil and s[outer] ~= nil then
            s[inner] = s[outer]
            s[outer] = nil
        end
    end
    if not next(s) then
        world.slots[tgtId] = nil
    end
end

-- Fill inside-out on one side with newcomer-wins bumping. Returns the ring
-- taken, or nil when that side is full on every ring.
local function fillSide(world, tgtId, id, side)
    local s = world.slots and world.slots[tgtId]
    if not s then return nil end
    for r = 1, NUM_RINGS do
        local idx = (r-1)*2 + side
        if s[idx] == nil then
            s[idx] = id
            return r
        end
        -- Inner slot occupied → try to push that occupant one ring out so we
        -- can take the closer slot (newcomer-wins behavior).
        if displaceOutward(world, tgtId, idx) then
            s[idx] = id
            return r
        end
    end
    return nil
end

-- The side (1=left, 2=right) on which any current occupant of the target's
-- ring stands, or nil when no one occupies the ring yet. (All occupants of a
-- freshly-filled ring are on the same side; once straddling kicks in the two
-- sides are both populated and either reading gives the "first" side for
-- straddle purposes, because the 2nd+ path only needs *a* side to flip.)
local function firstOccupantSide(world, tgtId)
    local s = world.slots and world.slots[tgtId]
    if not s then return nil end
    for idx, owner in pairs(s) do
        if owner then return idx % 2 == 0 and 2 or 1 end
    end
    return nil
end

-- Request a slot on the target's ring for `id`. Returns the (ring, side) of
-- the slot, or nil when the ring is full on every side (caller "stays put").
--
-- Side selection mirrors Battleheart (EnemyScript::requestPosition):
--   * 1st attacker on the target: side by horizontal position (or behind
--     the target when preferBack).
--   * 2nd+ attacker: prefer the OPPOSITE side of the first occupant so the
--     two attackers STRADDLE the target (BH's anti-clumping). Behind-facing
--     is a tiebreak only: if the opposite side is unavailable, we fall back
--     to the other side inside-out rather than collapsing onto the same
--     side as the first occupant.
local function requestPosition(world, tgtId, id, preferBack)
    local firstSide = firstOccupantSide(world, tgtId)
    local s = slotsFor(world, tgtId)
    if not s or not next(s) then
        -- First attacker: X-based (or preferBack) side, inside-out.
        local side = sideOf(world, tgtId, id, preferBack)
        local r = fillSide(world, tgtId, id, side)
        if r then return r, side end
        return nil
    end
    -- 2nd+ attacker: straddle the first occupant.
    local prefSide = (firstSide == 1) and 2 or 1
    local otherSide = (prefSide == 1) and 2 or 1
    local r = fillSide(world, tgtId, id, prefSide)
    if r then return r, prefSide end
    r = fillSide(world, tgtId, id, otherSide)
    if r then return r, otherSide end
    return nil -- full on both sides: caller falls back to "stay put"
end

-- Release `id`'s slot on target `tgtId` and backfill outer occupants inward.
local function purgePosition(world, tgtId, id)
    local t = world.slots
    if not t then return end
    local s = t[tgtId]
    if not s then return end
    local side = nil
    for idx, owner in pairs(s) do
        if owner == id then
            s[idx] = nil
            side = idx % 2 == 0 and 2 or 1
            break
        end
    end
    if side then backfillSide(world, tgtId, side) end
    if not next(s) then t[tgtId] = nil end
end

-- Ground/feet point of a slot for an attacker `attackerW` pixels wide.
local function slotGroundPoint(world, tgtId, ring, side, attackerW)
    local tp, ts = world.position[tgtId], world.size[tgtId]
    local r = RING[ring]
    if not (tp and ts and r) then return nil end
    local dx = (ts.w / 2 + (attackerW or ts.w) / 2) * MELEE_SPACING + r.extraX
    return tp.x + ((side == 1) and -dx or dx), tp.y + ts.h / 2 + r.y
end

-- A unit is alive while it exists and is not dying. (A dead unit's entity is
-- destroyed after its death animation, and its deathState goes with it — so
-- "no deathState" alone does NOT mean alive.)
local function isAlive(world, id)
    return world.entities[id] ~= nil and not world.deathState[id]
end

local function hasActiveAction(world, id)
    local ec = world.effects_comp[id]; if not ec then return false end
    for _, eff in ipairs(ec.active) do
        if eff.isAction then return true end
    end
    return false
end

-- ============================================================================
-- MELEE SLOT SELECTION (6-slot ring)
-- ============================================================================

local function getMeleeSlot(world, id, tgtId)
    local tp, ts = world.position[tgtId], world.size[tgtId]
    local sp, ss = world.position[id],    world.size[id]
    if not (tp and ts and sp and ss) then return nil end

    -- If this unit's slot on this target was released (e.g. the ring refilled
    -- around it), request one again. preferBack=false: flank by horizontal
    -- position, which is the Battleheart default for auto-attackers.
    local t = world.slots
    local ring, side
    if t and t[tgtId] and t[tgtId] then
        ring, side = nil, nil
        for idx, owner in pairs(t[tgtId]) do
            if owner == id then ring, side = math.floor((idx-1)/2)+1, idx % 2 == 0 and 2 or 1 break end
        end
    end
    if not ring then
        ring, side = requestPosition(world, tgtId, id, false)
    end

    if not ring then
        -- Ring is full on our side. Don't stack on top of anyone: stay put
        -- (keep current position as the movement target) rather than erroring.
        return sp.x, sp.y + ss.h/2
    end

    -- Convert the slot's GROUND/feet point to this unit's CENTER using the
    -- feet rule: center.y = groundY - size.h/2 (the attacker's own height).
    local gx, gy = slotGroundPoint(world, tgtId, ring, side, ss.w)
    if not gx then return nil end
    return gx, gy - ss.h/2
end

-- ============================================================================
-- TARGET FOLLOW
-- ============================================================================

function M.targetFollow(world)
    -- Release slots for units that no longer target their slot's owner target
    -- (cleared a target, died, lost aggro). Each stale owner is purged, which
    -- backfills the freed side. Survivors keep their slot.
    if world.slots then
        for tgtId, s in pairs(world.slots) do
            local stale = {}
            for _, owner in pairs(s) do
                if not (world.entities[owner] and not world.deathState[owner]
                        and world.entityTarget[owner] and world.entityTarget[owner].id == tgtId) then
                    table.insert(stale, owner)
                end
            end
            for _, owner in ipairs(stale) do
                purgePosition(world, tgtId, owner)
            end
        end
    end

    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local et = world.entityTarget[id]
        if not et then
            -- No target: drop any slot we held on whatever we last targeted.
            if world.slots then
                for tgtId, s in pairs(world.slots) do
                    for _, owner in pairs(s) do
                        if owner == id then purgePosition(world, tgtId, id) break end
                    end
                end
            end
            goto continue
        end
        if not world.entities[et.id] or world.deathState[et.id] then
            world.entityTarget[id] = nil
            goto continue
        end
        local lk = world.locks[id]
        if hasActiveAction(world, id) or (lk and lk.moveLock > 0) then goto continue end
        -- Knocked-down or stunned units cannot follow anything.
        local sg, sn = world.stagger[id], world.stun[id]
        if (sg and sg.staggered) or (sn and sn.stunned) then goto continue end
        local mt = world.moveTarget[id]; if not mt then goto continue end
        if world.isRanged[id] then goto continue end

        -- BH "hold position" rule (bh/systems/party-member-stats-ai-damage.md
        -- §7 F3): a hero whose target is a melee enemy that is attacking THIS
        -- hero, and is already in reach, fights where it stands. Without it the
        -- two keep stepping to each other's slot and neither ever swings.
        do
            local sd, tgtEt = world.side[id], world.entityTarget[et.id]
            if sd and sd.s == 0 and tgtEt and tgtEt.id == id and not world.isRanged[et.id]
               and combat.checkMeleeRange(world, id, et.id) then
                mt.active = false
                goto continue
            end
        end

        local tx, ty = getMeleeSlot(world, id, et.id)
        if not tx then goto continue end

        local sp = world.position[id]
        local ss = world.size[id]
        local tp = world.position[et.id]
        if not (sp and ss and tp) then goto continue end

        -- Unit must reach its exact slot before it can attack. Check X and Y
        -- proximity to the assigned slot CENTER (tx, ty are center coords from
        -- getMeleeSlot) against the unit's CENTER (sp.x, sp.y). Comparing to
        -- the unit's FEET (sp.y + h/2) here would be off by half a height and
        -- the unit would never register as "arrived" → infinite repositioning.
        local atSlotX = math.abs(sp.x - tx) <= 4
        local atSlotY = math.abs(sp.y - ty) <= 4
        if atSlotX and atSlotY then
            -- ARRIVING (was walking): stop and settle exactly on the slot, so
            -- the last sub-pixel of the approach does not re-trigger the walk.
            -- A unit that is already standing is left alone — its slot moves
            -- with its target, and re-snapping every frame would drag the unit
            -- along with a walking target as if glued to it, even while
            -- knocked down. It walks again (at its own speed) only once the
            -- slot has drifted out of tolerance.
            if mt.active then
                mt.active = false
                sp.x = tx; sp.y = ty
            end
        else
            mt.x = tx; mt.y = ty; mt.active = true
        end
        ::continue::
    end
end

-- ============================================================================
-- MOVE TARGET
-- ============================================================================

function M.moveTarget(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local mt = world.moveTarget[id]; if not (mt and mt.active) then goto continue end
        if hasActiveAction(world, id) then mt.active = false; goto continue end
        local lk = world.locks[id]; if lk and lk.moveLock > 0 then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end
        local pos, sz, ss, ph = world.position[id], world.size[id], world.stats[id], world.physics[id]
        if not (pos and sz and ss and ph) then goto continue end
        -- mt.x/mt.y are CENTER coordinates (set by targetFollow from
        -- getMeleeSlot, or by the right-click move which stores the clicked
        -- point as a center). Compute the direction against the unit's CENTER
        -- (pos.x, pos.y), NOT its feet. Using the feet here caused a vertical
        -- drift/oscillation: the unit chased a point that was always half a
        -- height above/below where it actually was, so it never settled.
        local dx = mt.x - pos.x; local dy = mt.y - pos.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 1 then mt.active = false; goto continue end
        dx, dy = dx/dist, dy/dist
        -- SLOW debuff: movement speed multiplier (1 = normal, lower = slower).
        local spd = statGet(ss.MOVE_SPEED) * 30 * status_mod.getSlowFactor(world, id)
        local moveAmt = math.min(spd * dt, dist)
        pos.x = pos.x + dx * moveAmt; pos.y = pos.y + dy * moveAmt
        local fc = world.facing[id]
        if fc then fc.right = (dx > 0) end
        ::continue::
    end
end

-- ============================================================================
-- PHYSICS
-- ============================================================================

-- Feet may not sink below the play area: bottom bound = VH(in) - inset.
-- VH here is ALREADY the resource-bar-adjusted bottom (call site passes
-- VH - RESOURCE_BAR_AREA_H), so the inset is a small visual margin above
-- that line. [tuned]
local FEET_BOTTOM_INSET = 12

function M.physics(world, dt, VW, VH, BATTLE_LINE_Y, FRICTION, MASS)
    local fric = math.pow(FRICTION, 60 * dt)
    local feetBottomMax = VH - FEET_BOTTOM_INSET  -- [tuned]
    for id in pairs(world.entities) do
        local pos, ph, sz = world.position[id], world.physics[id], world.size[id]
        if not (pos and ph) then goto continue end
        ph.vx = ph.vx + (ph.fx / MASS); ph.vy = ph.vy + (ph.fy / MASS)
        ph.fx, ph.fy = 0, 0
        pos.x = pos.x + ph.vx * dt; pos.y = pos.y + ph.vy * dt
        ph.vx = ph.vx * fric; ph.vy = ph.vy * fric
        if sz then
            local sd = world.side[id]
            local mb = pos.y + sz.h/2
            if sd and sd.s == 0 then
                local he = world.hasEntered[id]
                if he then
                    if not he.h and pos.x >= sz.w/2 then he.h = true end
                    if he.h then
                        pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                    end
                    if not he.v and mb >= BATTLE_LINE_Y then he.v = true end
                    if he.v then
                        if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                        if mb > feetBottomMax then pos.y = feetBottomMax - sz.h/2 end
                    end
                else
                    pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                    if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                    if mb > feetBottomMax then pos.y = feetBottomMax - sz.h/2 end
                end
            elseif sd and sd.s == 1 then
                local he = world.hasEntered[id]
                -- (enemies walk in from either edge)
                if he and not he.h and pos.x >= sz.w/2 and pos.x <= VW - sz.w/2 then he.h = true end
                if he and he.h then
                    pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                end
                if he and not he.v and mb >= BATTLE_LINE_Y then he.v = true end
                if he and he.v then
                    if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                    if mb > feetBottomMax then pos.y = feetBottomMax - sz.h/2 end
                end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- STAGGER + LOCK DECAY
-- ============================================================================

function M.stagger(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sg = world.stagger[id]
        if sg and sg.staggered then
            if sg.reversingAnim then
                local di = anim_mod.getDeathAnimIdx(world, id)
                local ac = world.anim[id]
                if ac and di > 0 then
                    local da    = ac.list[di]
                    local entry = anim_mod.db[da and da.name]
                    if entry and da and da.timer >= da.frameLength * entry.frames then
                        sg.staggered = false; sg.reversingAnim = false
                        local ss = world.stats[id]
                        if ss then ss.RES.add = ss.RES.add - 1 end
                        local lk2 = world.locks[id]
                        if lk2 and not (world.stun[id] and world.stun[id].stunned) then lk2.actionLock = 0 end
                        local sn = world.stun[id]
                        if sn and sn.stunned and sn.timer > 0 then
                            da.active = true; da.timer = da.frameLength * entry.frames
                            da.reverse = nil; da.holdAtEnd = true
                        else
                            da.active = false; da.reverse = nil; da.timer = 0
                            if ac.list[1] then ac.list[1].active = true end
                        end
                    end
                end
            else
                sg.timer = sg.timer - dt
                if sg.timer <= 0 then
                    sg.reversingAnim = true
                    local di = anim_mod.getDeathAnimIdx(world, id)
                    local ac = world.anim[id]
                    if ac and di > 0 then
                        local da = ac.list[di]
                        da.active = true; da.timer = 0; da.reverse = true; da.holdAtEnd = false
                    end
                end
            end
        end
        local lk = world.locks[id]
        local sn = world.stun[id]
        if lk then
            if not (sg and sg.staggered) and not (sn and sn.stunned) then
                lk.actionLock = math.max(0, lk.actionLock - dt)
            end
            lk.moveLock = math.max(0, lk.moveLock - dt)
        end
        ::continue::
    end
end

-- ============================================================================
-- STUN
-- ============================================================================

function M.stunSystem(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sn = world.stun[id]; if not (sn and sn.stunned) then goto continue end
        local sg = world.stagger[id]
        if sg and sg.staggered then goto continue end
        sn.timer = sn.timer - dt
        if sn.timer <= 0 then
            sn.stunned = false
            sn.timer = 0
            local lk = world.locks[id]
            if lk then lk.actionLock = 0 end
            local ac = world.anim[id]
            if ac then
                local di = anim_mod.getDeathAnimIdx(world, id)
                if di > 0 then
                    local da = ac.list[di]
                    da.active = true; da.timer = 0; da.reverse = true; da.holdAtEnd = false
                    sn.reversingAnim = true
                end
            end
        end
        ::continue::
    end
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sn = world.stun[id]; if not (sn and sn.reversingAnim) then goto continue end
        local di = anim_mod.getDeathAnimIdx(world, id)
        local ac = world.anim[id]
        if ac and di > 0 then
            local da = ac.list[di]
            local entry = anim_mod.db[da and da.name]
            if entry and da and da.timer >= da.frameLength * entry.frames then
                sn.reversingAnim = false
                da.active = false; da.reverse = nil; da.timer = 0
                if ac.list[1] then ac.list[1].active = true end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- THREAT
-- ============================================================================

function M.threat(world, battle, dt)
    for id in pairs(world.entities) do
        local sd = world.side[id]; if not (sd and sd.s == 1) then goto continue end
        local tm = world.threatMap[id]; if not tm then goto continue end
        if world.chaotic[id] then
            -- BH `chaotic`: ignores threat; a new random hero each time its attack is ready.
            local sk, et = world.skills[id], world.entityTarget[id]
            local ready  = sk and sk.list[0] and sk.list[0].cd <= 0 and not hasActiveAction(world, id)
            local lost   = not et or not world.entities[et.id] or world.deathState[et.id]
            if ready or lost then
                local alive = {}
                for _, pid in ipairs(battle.partyIds) do
                    if isAlive(world, pid) then alive[#alive + 1] = pid end
                end
                if #alive > 0 then world.entityTarget[id] = {id = alive[math.random(#alive)]} end
            end
            goto continue
        end
        tm.decayTimer = tm.decayTimer + dt
        if tm.decayTimer >= 1.0 then
            tm.decayTimer = 0
            for ally, val in pairs(tm.map) do tm.map[ally] = val * 0.9 end
        end
        local bestId, bestVal = nil, -1
        for ally, val in pairs(tm.map) do
            if world.entities[ally] and not world.deathState[ally] and val > bestVal then
                bestId, bestVal = ally, val
            end
        end
        if bestId then
            world.entityTarget[id] = {id=bestId}
        elseif not world.entityTarget[id] then
            for _, pid in ipairs(battle.partyIds) do
                if isAlive(world, pid) then world.entityTarget[id] = {id=pid}; break end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- DEATH
-- ============================================================================

function M.death(world, battle, dt)
    local toDestroy = {}
    for id in pairs(world.entities) do
        local ds = world.deathState[id]
        if not ds then
            local ss = world.stats[id]
            if not (ss and statGet(ss.HP) <= 0) then goto continue end
            world.deathState[id] = {phase="dying", timer=2.5, blinkTimer=0, blinkVisible=true}
            anim_mod.activateDeathAnim(world, id, true)
            world.bar[id] = nil
            local mt = world.moveTarget[id]; if mt then mt.active = false end
            world.entityTarget[id] = nil
            -- Free any ring slot this unit held (it may have been mid-attack).
            if world.slots then
                for tgtId, s in pairs(world.slots) do
                    for _, owner in pairs(s) do
                        if owner == id then purgePosition(world, tgtId, id) break end
                    end
                end
            end
            -- This unit was a TARGET: destroy its whole ring (all occupants
            -- lose their target and re-pick next frame).
            if world.slots then world.slots[id] = nil end
            for eid in pairs(world.entities) do
                local tm = world.threatMap[eid]
                if tm then tm.map[id] = nil end
                local et = world.entityTarget[eid]
                if et and et.id == id then
                    world.entityTarget[eid] = nil
                end
            end
            local side = world.side[id]
            if side and side.s == 0 then
                for i, pid in ipairs(battle.partyIds) do
                    if pid == id then
                        battle.deadSlots[i] = true
                        if battle.selectedUnit == id then
                            battle.selectedUnit = nil
                            for j, pid2 in ipairs(battle.partyIds) do
                                if not battle.deadSlots[j] then battle.selectedUnit = pid2; break end
                            end
                        end
                        break
                    end
                end
            elseif side and side.s == 1 then
                -- Kill counter (shown on the victory screen).
                battle.enemyDefeated = (battle.enemyDefeated or 0) + 1
            end
        elseif ds.phase == "dying" then
            ds.timer = ds.timer - dt
            if ds.timer <= 0 then
                ds.phase="blinking"; ds.blinkTimer=0; ds.blinkVisible=true
            end
        elseif ds.phase == "blinking" then
            ds.blinkTimer = ds.blinkTimer + dt
            local rate   = 2 + ds.blinkTimer * 8
            local period = 1 / rate
            ds.blinkVisible = (math.floor(ds.blinkTimer / period) % 2 == 0)
            if ds.blinkTimer >= 2.0 then table.insert(toDestroy, id) end
        end
        ::continue::
    end
    for _, id in ipairs(toDestroy) do world:destroy(id) end
end

-- ============================================================================
-- VFX DECAY
-- ============================================================================

function M.vfxDecay(battle, dt, common)
    local vfx = battle.vfx
    vfx.shake  = math.max(0, vfx.shake  - 18 * dt)
    vfx.chroma = math.max(0, vfx.chroma -  5 * dt)
    vfx.zoom   = vfx.zoom + (vfx.zoomTarget - vfx.zoom) * math.min(1, dt * 8)
    vfx.zoomTarget = vfx.zoomTarget + (1.0 - vfx.zoomTarget) * math.min(1, dt * 3)
    battle.postfx.chromasep.radius = common.CHROMA_RADIUS + vfx.chroma
end

function M.updateFacing(world)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end
        local et = world.entityTarget[id]; if not et then goto continue end
        if not world.entities[et.id] or world.deathState[et.id] then goto continue end
        local sp = world.position[id]
        local tp = world.position[et.id]
        local fc = world.facing[id]
        if sp and tp and fc then
            fc.right = (tp.x >= sp.x)
        end
        ::continue::
    end
end

return M

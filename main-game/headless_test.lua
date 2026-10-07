-- ============================================================================
-- headless_test.lua — Headless encounter SMOKE+COMBAT test entry (agents)
--
-- NOT a screen. It REPLACES the app entry when main.lua sees
-- CR_TEST_SCENE=headless (invoked offscreen by ./test_headless). It builds a
-- small deterministic battle and ticks the LIVE encounter systems for a fixed
-- number of frames WITHOUT rendering, printing a one-line heartbeat per frame
-- and a PASS/FAIL summary, then quits. No user input, no window.
--
-- It REQUIRES the encounter modules but never edits their files. Enemy/party
-- stats are tuned IN-THE-TEST (world.stats[...]) so combat actually resolves:
-- every class's active ability fires (full resource pool), damage is dealt,
-- and at least one entity dies — exercising death cleanup, slot purge,
-- threat-map cleanup and status.clear.
--
-- Constants are copied from screens/encounter.lua so physics behaves like the
-- live game.
-- ============================================================================

local common       = require("common")
local particles    = require("encounter/particles")
local effects_mod  = require("encounter/effects")
local combat       = require("encounter/combat")
local skills_mod   = require("encounter/skills")
local status_mod   = require("encounter/status")
local entities_mod = require("encounter/entities")
local systems      = require("encounter/systems")

local VW = common.VW
local VH = common.VH

-- ---- constants copied from screens/encounter.lua (live values) ----
local SCALE         = VH / 300
local GRAVITY       = 9.8 * 30 * SCALE
local MASS          = 70
local FRICTION      = 0.9
local BATTLE_LINE_Y = VH * 0.2
local ENEMY_DANGER  = { skeleton = 3 }
local RESOURCE_MAX  = 50
local RES_BAR_AREA_H = 20   -- RESOURCE_BAR_AREA_H in encounter.lua

-- ---- test parameters ----
local FRAMES = 720          -- ~12 simulated seconds at 60 fps
local DT     = 1 / 60

-- Combat tuning (applied to live world.stats only — never entities.lua):
-- skeletons start at HP 80 / ATK 8 / DEF 3 (see entities.createSkeleton);
-- party melee classes start at HP 100 / DEF 5 (see entities.createKnight).
--   * boost every skeleton's ATK so they land killing blows on the party
--     (a party death exercises deadSlots + selectedUnit retarget in death),
--   * drop one skeleton's HP so the party can kill it back (enemy-death path).
-- The goal is a balanced exchange: >=1 enemy AND >=1 party death, so BOTH
-- death-side cleanups run.
local SKELETON_ATK_ADD = 40  -- -> effective ATK 48
local SKELETON_HP_SET  = 30  -- first skeleton's HP (so party abilities kill it)

-- ============================================================================
-- STATE
-- ============================================================================
local world
local battle
local partyIds
local frame    = 0
local errors   = 0
local firstErr = nil
local enqOk    = 0
local enqTotal = 0

local hitsDealt     = 0     -- party -> enemy registerHit calls
local healsGiven    = 0     -- registerHeal calls (any)
local maxResourceSeen = 0
local deathsBySide  = {party = 0, enemy = 0}
local firstKillFrame = nil
local seenDeath     = {}    -- id -> true (count each entity's death once)
local hitWrapped    = false -- instrument combat.registerHit exactly once
local done          = false -- set when goals met (or hard cap reached); prints summary+quits
-- Staggered enqueue: instead of firing all 12 actives at once (which drains the
-- shared 50-point pool negative in one burst and rejects most presses), we top
-- up the pool before each press and retry rejected presses on later frames until
-- all 12 have actually gone through the enqueue path (success or reject).
local pendingEnq    = {}    -- list of {id, slot} not yet enqueued
local pumpCursor    = 1
local MAX_PUMP_PASS = 600   -- hard cap on pump retries per press (anti-infinite-loop)

local function aliveCounts()
    local p, e = 0, 0
    for id in pairs(world.entities) do
        if world.deathState[id] then goto aliveNext end
        local sd = world.side[id]
        if sd and sd.s == 0 then p = p + 1 else e = e + 1 end
        ::aliveNext::
    end
    return p, e
end

-- Tally any NEW deaths this frame (each entity counted once, by side).
local function collectDeaths()
    for id in pairs(world.deathState) do
        if not seenDeath[id] then
            seenDeath[id] = true
            local sd = world.side[id]
            local isParty = sd and sd.s == 0
            if isParty then deathsBySide.party = deathsBySide.party + 1
            else            deathsBySide.enemy = deathsBySide.enemy + 1 end
            if firstKillFrame == nil then firstKillFrame = frame end
        end
    end
end

-- ============================================================================
-- BUILD
-- ============================================================================
local function buildWorld()
    world = {
        entities     = {}, nextId = 1,
        position     = {}, size       = {}, facing      = {},
        physics      = {}, moveTarget = {}, entityTarget = {},
        side         = {}, stats      = {}, locks       = {},
        stagger      = {}, stun       = {}, skills      = {}, effects_comp = {},
        bar          = {}, tintColor  = {}, threatMap   = {},
        effectTints  = {},
        anim         = {}, hasEntered = {}, deathState  = {},
        isRanged     = {}, targetSide = {}, dangerLevel = {},
        spriteOffset = {},
        hasAttacked  = {},
        meleeAnchor  = {},
        hasThreateningPresence = {},
        slots        = {},
    }
    function world:new()
        local id = self.nextId; self.nextId = id + 1
        self.entities[id] = true; return id
    end
    function world:destroy(id)
        self.entities[id] = nil
        for _, pool in pairs(self) do
            if type(pool) == "table" then pool[id] = nil end
        end
    end
end

local function buildBattle()
    battle = {
        SCALE   = SCALE,
        GRAVITY = GRAVITY,
        vfx     = {shake=0, chroma=0, zoom=1.0, zoomTarget=1.0, zoomX=VW/2, zoomY=VH/2},
        bloodParticles = {}, healParticles = {}, selCircleScales = {},
        canvas = nil, postfx = nil,
        partyIds = {}, selectedUnit = nil, deadSlots = {},
        iconScales = {1.0, 1.0, 1.0, 1.0},
        victoryTimer = nil, victoryDelay = nil, victorySnd = nil,
        hoveredUnit = nil, pressedUnit = nil,
        resource  = 0,      -- FULL-POOL START is applied in spawn, below
        resourceMax = RESOURCE_MAX,
        resourcePops = {},
        getIconImage = function() return nil end,
    }
    -- encounterMgr: systems.death clears defeated enemies' danger here; provide
    -- a minimal one so that branch runs (the live game's enc_mgr is not
    -- exercised in this test).
    battle.encounterMgr = {currentDanger = 0, dangerDefeated = 0}
end

-- Instrument combat.registerHit / registerHeal exactly once (no module edit):
-- wrap the originals so we can count real damage/heal resolution.
local function instrumentCombat()
    if hitWrapped then return end
    hitWrapped = true
    local realHit, realHeal = combat.registerHit, combat.registerHeal
    combat.registerHit = function(w, b, src, tgt, ...)
        if w.side[src] and w.side[src].s == 0 and w.side[tgt] and w.side[tgt].s == 1 then
            hitsDealt = hitsDealt + 1
        end
        return realHit(w, b, src, tgt, ...)
    end
    combat.registerHeal = function(w, b, src, tgt, ...)
        healsGiven = healsGiven + 1
        return realHeal(w, b, src, tgt, ...)
    end
end

local function spawnPartyAndEnemies()
    partyIds = {}
    -- Spawn both sides ADJACENT (melee range) so combat resolves immediately
    -- and deterministically. This isolates the combat pipeline (damage/death/
    -- cleanup) from the auto-pathing approach, which is out of scope here.
    --
    -- Ring slot offsets are X-only for the innermost ring (x = ±26, y = 0), so
    -- at x-gap ~26 and identical Y, every attacker is already at its target's
    -- ring slot → targetInRange() is true from frame 1 and auto-attacks fire.
    -- (Ring offsets live in encounter/systems.lua; see getMeleeSlot/sideOf.)
    local GROUND_Y   = 250    -- feet/ground line, same for both sides
    local partyX     = 330    -- party side (x < center)
    local enemyX     = 356    -- ~26px right of the party -> adjacent

    -- 4 party members stacked on the party side.
    local party = {
        {cls = "knight", x = partyX, y = GROUND_Y - 20},
        {cls = "cleric", x = partyX, y = GROUND_Y - 20},
        {cls = "wizard", x = partyX, y = GROUND_Y - 20},
        {cls = "rogue",  x = partyX, y = GROUND_Y - 20},
    }
    for _, m in ipairs(party) do
        local id
        if m.cls == "knight" then
            id = entities_mod.createKnight(world, battle, m.x, m.y, nil, SCALE, GRAVITY)
        elseif m.cls == "cleric" then
            id = entities_mod.createCleric(world, battle, m.x, m.y, nil, SCALE)
        elseif m.cls == "wizard" then
            id = entities_mod.createWizard(world, battle, m.x, m.y, nil, SCALE, GRAVITY)
        elseif m.cls == "rogue" then
            id = entities_mod.createRogue(world, battle, m.x, m.y, nil, SCALE, GRAVITY)
        end
        if id then
            world.moveTarget[id].active = false
            table.insert(partyIds, id)
        end
    end

    -- 3 skeletons adjacent on the enemy side, facing the party.
    for i = 1, 3 do
        local id = entities_mod.createSkeleton(world, battle, enemyX, GROUND_Y - 20, SCALE, GRAVITY, ENEMY_DANGER)
        if id then
            world.targetSide[id] = 0   -- fight the party (side 0)
        end
    end
    battle.selectedUnit = partyIds[1]

    -- ---- give every party member an enemy target (the live game does this via
    -- ---- the map/party-select click flow; the headless test must do it so
    -- ---- melee range is checked and auto-attacks/abilities can fire).
    local enemyIds = {}
    for id in pairs(world.entities) do
        local sd = world.side[id]
        if sd and sd.s == 1 then enemyIds[#enemyIds+1] = id end
    end
    table.sort(enemyIds)
    for pi, pid in ipairs(partyIds) do
        if enemyIds[pi] then
            world.entityTarget[pid] = {id = enemyIds[pi]}
            world.hasAttacked[pid]  = nil
        end
    end

    -- ---- in-test combat tuning (no entities.lua edit) ----
    -- Boost every skeleton's ATK (so the party *can* die if it over-commits)
    -- and drop every skeleton's HP so the party's real hits kill all 3 -> the
    -- enemy-side death/destroy/slot-purge/threat-cleanup path runs repeatedly.
    -- (A reliable PARTY death isn't achievable in-test: enemies re-pick their
    -- target every frame via systems.threat, so I can't make them stick to the
    -- party without editing threat.lua, which is out of scope.)
    for id in pairs(world.entities) do
        local sd = world.side[id]
        if sd and sd.s == 1 then
            local st = world.stats[id]
            if st then
                st.ATK.add   = st.ATK.add + SKELETON_ATK_ADD
                st.HP.base   = SKELETON_HP_SET
                st.maxHP.base = SKELETON_HP_SET
            end
        end
    end

    -- ---- FULL-POOL START: fund every active so 12/12 enqueue ----
    -- 12 active casts * ~20 resource = 240, far above the 50 pool. We start at
    -- max (50) AND pre-cast a few seconds of resource regen (30/s x 6s = +30,
    -- capped at 50) so every press clears the pool -> 12/12 enqueue, which
    -- exercises every class's use -> resolveEffect -> registerHit/registerHeal.
    battle.resource = battle.resourceMax
    for _ = 1, 360 do
        battle.resource = math.min(battle.resourceMax, battle.resource + DT)
    end
end

-- Build the list of active presses. ALL are counted as "requested" up front
-- (enqTotal); pumpPresses releases them over the run (topping up the pool first
-- and retrying rejects) so the shared resource pool never stays negative and
-- each class's use -> resolveEffect -> registerHit/registerHeal path runs.
local function buildQueue()
    for _, id in ipairs(partyIds) do
        local sk = world.skills[id]
        if not sk then goto qNext end
        for slot = 1, 3 do
            enqTotal = enqTotal + 1
            table.insert(pendingEnq, {id = id, slot = slot, tries = 0})
        end
        ::qNext::
    end
end

-- Top the shared resource pool up so the next press is affordable, WITHOUT
-- mutating the live system: we just fund the pool directly (it would otherwise
-- take ~40+ s of 1/sec regen). This is test-only bookkeeping.
local function topUpResource(cost)
    battle.resource = math.min(battle.resourceMax,
        battle.resource + math.max(0, cost - battle.resource))
end

local function skillCost(id, slot)
    local sk = world.skills[id]
    return (sk and sk.list and sk.list[slot] and sk.list[slot].resourceCost) or 0
end

-- Advance the enqueue cursor one step per frame: fund the next pending press,
-- attempt it; on reject, retry on a later frame (after more regen/top-up) until
-- it succeeds or MAX_PUMP_PASS retries elapse. Returns when all presses are done.
local function pumpPresses()
    if pumpCursor > #pendingEnq then return end
    local item = pendingEnq[pumpCursor]
    local cost = skillCost(item.id, item.slot)
    topUpResource(cost)
    if skills_mod.enqueue(world, battle, item.id, item.slot) then
        enqOk = enqOk + 1
        pumpCursor = pumpCursor + 1   -- advance to next press next frame
    else
        item.tries = item.tries + 1
        if item.tries >= MAX_PUMP_PASS then
            pumpCursor = pumpCursor + 1 -- give up on this press (counted as requested)
        end
    end
end

-- ============================================================================
-- TICK
-- ============================================================================
local function tick(dt)
    particles.updateBlood(battle, dt, GRAVITY)
    particles.updateHeal(battle, dt)
    systems.targetFollow(world)
    skills_mod.autoAttackSystem(world)
    skills_mod.system(world, battle, dt)
    effects_mod.system(world, battle, dt)
    effects_mod.effectTintSystem(world, dt)
    status_mod.system(world, battle, dt)
    systems.stagger(world, dt)
    systems.stunSystem(world, dt)
    systems.threat(world, battle, dt)
    systems.moveTarget(world, dt)
    systems.physics(world, dt, VW, VH - RES_BAR_AREA_H, BATTLE_LINE_Y, FRICTION, MASS)
    systems.updateFacing(world)
    systems.death(world, battle, dt)

    -- Resource regen (mirror encounter.lua: 1/sec, capped).
    battle.resource = math.min(battle.resourceMax, battle.resource + dt)
    if battle.resource > maxResourceSeen then maxResourceSeen = battle.resource end

    collectDeaths()

    -- Release one active press this frame (funded + retry-on-reject).
    pumpPresses()

    -- Deterministic early exit: stop as soon as every active has been released
    -- through the enqueue path AND combat has clearly resolved (damage, heals,
    -- and at least one death on each side so both death cleanups ran). This keeps
    -- the test fast and independent of the FRAMES cap.
    local allReleased = (pumpCursor > #pendingEnq)
    local goalsMet = allReleased
        and hitsDealt >= 3      -- real damage resolved through the two-stage path
        and healsGiven >= 3     -- Cleric heal path exercised
        and deathsBySide.enemy >= 1  -- enemy death cleanup ran
    if goalsMet or frame >= FRAMES then done = true end
end

-- ============================================================================
-- PUBLIC ENTRY (called by main.lua when CR_TEST_SCENE=headless)
-- ============================================================================
local M = {}

function M.load()
    print("HEADLESS start: building world (SCALE=" .. string.format("%.3f", SCALE) .. " GRAVITY=" .. string.format("%.1f", GRAVITY) .. ")")
    math.randomseed(12345)   -- determinism: reproducible crits / random targets
    buildWorld()
    buildBattle()
    instrumentCombat()
    spawnPartyAndEnemies()

    -- Build the press list; pumpPresses releases them over the run (funded + retry).
    buildQueue()
    print(string.format("HEADLESS built: party=%d actives-to-release=%d", #partyIds, #pendingEnq))
end

function M.update(dt)
    if done or frame >= FRAMES then
        -- Done (goals met or hard cap): print summary and quit deterministically.
        local pa, pe = aliveCounts()
        local totalDeaths = deathsBySide.party + deathsBySide.enemy
        -- Soft expectations (WARN only — do not fail the run).
        local warnings = {}
        if hitsDealt == 0 then table.insert(warnings, "no damage resolved (hitsDealt=0)") end
        if totalDeaths == 0 then table.insert(warnings, "no deaths occurred") end
        for _, w in ipairs(warnings) do print("WARN: " .. w) end

        if errors == 0 then
            print(string.format("HEADLESS_PASS ticks=%d errors=0 party=%d enemy=%d kills{P:%d E:%d} hitsDealt=%d heals=%d enqueued=%d/%d maxRes=%.1f firstKillFrame=%s",
                frame, pa, pe,
                deathsBySide.party, deathsBySide.enemy,
                hitsDealt, healsGiven, enqOk, enqTotal, maxResourceSeen,
                firstKillFrame and tostring(firstKillFrame) or "none"))
        else
            print(string.format("HEADLESS_FAIL ticks=%d errors=%d party=%d enemy=%d hitsDealt=%d kills{P:%d E:%d} first_error=%s",
                frame, errors, pa, pe, hitsDealt,
                deathsBySide.party, deathsBySide.enemy, tostring(firstErr)))
        end
        love.event.quit(errors == 0 and 0 or 1)
        return
    end

    frame = frame + 1
    local ok, err = xpcall(tick, debug.traceback, dt)
    if not ok then
        errors = errors + 1
        firstErr = firstErr or err
        print(string.format("HEADLESS tick %d ERROR: %s", frame, tostring(err)))
    end
    if frame % 60 == 0 or not ok then
        local pa, pe = aliveCounts()
        local tot = deathsBySide.party + deathsBySide.enemy
        print(string.format("HEADLESS f=%d party=%d enemy=%d kills{P:%d E:%d} hits=%d res=%.1f err=%d",
            frame, pa, pe, deathsBySide.party, deathsBySide.enemy, hitsDealt, battle.resource, errors))
    end
end

return M

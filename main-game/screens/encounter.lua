-- screens/encounter.lua — Encounter/battle screen module (orchestrator)
-- Sub-modules live in encounter/ and handle stats, anim, particles,
-- effects, combat, skills, entities, systems, encounter manager, and UI.

local common       = require("common")
local anim_mod     = require("encounter/anim")
local particles    = require("encounter/particles")
local effects_mod  = require("encounter/effects")
local combat       = require("encounter/combat")
local skills_mod   = require("encounter/skills")
local status_mod   = require("encounter/status")
local entities_mod = require("encounter/entities")
local systems      = require("encounter/systems")
local enc_mgr      = require("encounter/encounter_mgr")
local ui           = require("encounter/ui")

local VW    = common.VW
local VH    = common.VH
local SCALE = VH / 300

local GRAVITY       = 9.8 * 30 * SCALE
local MASS          = 70
local FRICTION      = 0.9
local BATTLE_LINE_Y = VH * 0.2

local ENEMY_DANGER = { skeleton = 3 }

-- Resource bar layout constants
local RES_PER_SEG        = 5
local RES_SEG_COUNT      = 10
local RESOURCE_MAX       = RES_PER_SEG * RES_SEG_COUNT   -- 50
local RESOURCE_BAR_AREA_H = 20   -- pixels reserved at bottom (physics clamp + bar)

-- ============================================================================
-- MODULE STATE — reset each onEnter
-- ============================================================================

local world = {}
local battle = {
    font=nil, smallFont=nil, battlebg=nil,
}

local iconImages = {}
local assetsLoaded = false

-- Pause (Director's screenshot aid): freezes ALL simulation + animations.
-- Toggled by the top-right pause icon or the P key. While paused, M.update
-- skips every system tick; draw still runs so the screen stays visible.
local paused = false

-- Pause icon: top-right corner. 28x28 hit area, 4px from the edges.
local PAUSE_BTN_SIZE = 28
local PAUSE_BTN_PAD  = 6
local function pauseBtnRect()
    return VW - PAUSE_BTN_PAD - PAUSE_BTN_SIZE,
           PAUSE_BTN_PAD,
           PAUSE_BTN_SIZE, PAUSE_BTN_SIZE
end

local switchFn
local saveData_ref, slot_ref

-- ============================================================================
-- WORLD INIT
-- ============================================================================

local function initWorld()
    world = {
        entities     = {},  nextId = 1,
        position     = {},  size        = {},  facing      = {},
        physics      = {},  moveTarget  = {},  entityTarget = {},
        side         = {},  stats       = {},  locks        = {},
        stagger      = {},  stun        = {},  skills      = {},  effects_comp = {},
        bar          = {},  tintColor   = {},  threatMap    = {},
        effectTints  = {},
        anim         = {},  hasEntered  = {},  deathState   = {},
        isRanged     = {},  targetSide  = {},  dangerLevel = {},
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

local function initBattle(c, pfx)
    battle.SCALE          = SCALE
    battle.GRAVITY        = GRAVITY
    battle.vfx            = {shake=0, chroma=0, zoom=1.0, zoomTarget=1.0, zoomX=VW/2, zoomY=VH/2}
    battle.bloodParticles  = {}
    battle.healParticles   = {}
    battle.selCircleScales = {}
    battle.canvas          = c
    battle.postfx          = pfx
    battle.partyIds        = {}
    battle.selectedUnit    = nil
    battle.deadSlots       = {}
    battle.iconScales      = {1.0, 1.0, 1.0, 1.0}
    battle.victoryTimer    = nil
    battle.victoryDelay    = nil
    battle.victorySnd      = nil
    battle.hoveredUnit     = nil
    battle.pressedUnit     = nil
    battle.resource        = 0
    battle.resourceMax     = RESOURCE_MAX
    battle.resourcePops    = {}
end

-- ============================================================================
-- ASSET LOADING (once per session)
-- ============================================================================

local function getIconImage(iconName)
    if not iconName then return nil end
    local n = tonumber(iconName:match("skill_icons(%d+)"))
    return n and iconImages[n]
end

local function loadAssets()
    if assetsLoaded then
        battle.font      = battle.font      or common.loadFont(16)
        battle.smallFont = battle.smallFont or common.loadFont(10)
        return
    end
    assetsLoaded = true

    battle.font      = common.loadFont(16)
    battle.smallFont = common.loadFont(10)

    local ok, bg = pcall(love.graphics.newImage, "assets/images/forestbg2.png")
    battle.battlebg = ok and bg or nil

    local C = "assets/characters/"
    local E = "assets/enemies/"
    anim_mod.load("KnightIdle",    C.."Knight/Idle.png",      10, 135, 135, 1.1)
    anim_mod.load("KnightMove",    C.."Knight/Run.png",         6, 135, 135, 1.1)
    anim_mod.load("KnightAttack1", C.."Knight/Attack1.png",     4, 135, 135, 1.1)
    anim_mod.load("KnightAttack2", C.."Knight/Attack2.png",     4, 135, 135, 1.1)
    anim_mod.load("KnightTakeHit", C.."Knight/Take Hit.png",    3, 135, 135, 1.1)
    anim_mod.load("KnightDeath",   C.."Knight/Death.png",       9, 135, 135, 1.1)

    anim_mod.load("BrigandIdle",    C.."Brigand/Idle.png",      10, 126, 126, 0.9)
    anim_mod.load("BrigandMove",    C.."Brigand/Run.png",        8, 126, 126, 0.9)
    anim_mod.load("BrigandAttack1", C.."Brigand/Attack1.png",    7, 126, 126, 0.9)
    anim_mod.load("BrigandDeath",   C.."Brigand/Death.png",     11, 126, 126, 0.9)

    anim_mod.load("ChampionIdle",    C.."Champion/Idle.png",     8, 160, 111, 1.0)
    anim_mod.load("ChampionMove",    C.."Champion/Run.png",      8, 160, 111, 1.0)
    anim_mod.load("ChampionAttack1", C.."Champion/Attack1.png",  4, 160, 111, 1.0)
    anim_mod.load("ChampionDeath",   C.."Champion/Death.png",    6, 160, 111, 1.0)

    anim_mod.load("DuelistIdle",    C.."Duelist/Idle.png",      8, 200, 200, 0.959)
    anim_mod.load("DuelistMove",    C.."Duelist/Run.png",       8, 200, 200, 0.959)
    anim_mod.load("DuelistAttack1", C.."Duelist/Attack1.png",   6, 200, 200, 0.959)
    anim_mod.load("DuelistDeath",   C.."Duelist/Death.png",     6, 200, 200, 0.959)

    anim_mod.load("SkeletonIdle",   E.."Skeleton/Idle.png",     4, 150, 150, 0.75)
    anim_mod.load("SkeletonMove",   E.."Skeleton/Walk.png",     4, 150, 150, 0.75)
    anim_mod.load("SkeletonAttack", E.."Skeleton/Attack.png",   8, 150, 150, 0.75)
    anim_mod.load("SkeletonDeath",  E.."Skeleton/Death.png",    4, 150, 150, 0.75)

    anim_mod.load("BatIdle",   E.."Bat/Flight.png",  8, 150, 150, 0.75)
    anim_mod.load("BatAttack", E.."Bat/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("BatDeath",  E.."Bat/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("ImpIdle",   E.."Imp/Idle.png",    4, 150, 150, 0.75)
    anim_mod.load("ImpMove",   E.."Imp/Move.png",    8, 150, 150, 0.75)
    anim_mod.load("ImpAttack", E.."Imp/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("ImpDeath",  E.."Imp/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("MushroomIdle",   E.."Mushroom/Idle.png",    4, 150, 150, 0.75)
    anim_mod.load("MushroomMove",   E.."Mushroom/Move.png",    8, 150, 150, 0.75)
    anim_mod.load("MushroomAttack", E.."Mushroom/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("MushroomDeath",  E.."Mushroom/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("NomadIdle",    C.."Nomad/Idle.png",     8, 250, 250, 0.72)
    anim_mod.load("NomadMove",    C.."Nomad/Run.png",       8, 250, 250, 0.72)
    anim_mod.load("NomadAttack1", C.."Nomad/Attack1.png",   8, 250, 250, 0.72)
    anim_mod.load("NomadAttack2", C.."Nomad/Attack2.png",   8, 250, 250, 0.72)
    anim_mod.load("NomadDeath",   C.."Nomad/Death.png",     7, 250, 250, 0.72)

    for i = 1, 54 do
        local ok2, img = pcall(love.graphics.newImage, "assets/icons/skill_icons"..i..".png")
        iconImages[i] = ok2 and img or nil
    end

    local okv, vs = pcall(love.audio.newSource, "assets/sounds/encounter/Victory!.wav", "static")
    if okv then battle.victorySnd = vs end

end

-- ============================================================================
-- DRAW SCENE (composites all render sub-systems)
-- ============================================================================

local function drawScene(dt)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    if battle.battlebg then
        local iw, ih = battle.battlebg:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(battle.battlebg, 0, 0, 0, VW/iw, VH/ih)
    end

    ui.drawShadows(world)
    ui.drawSelectionCircles(world, battle)
    anim_mod.drawEntities(world, battle, SCALE)
    particles.drawBlood(battle)
    particles.drawHeal(battle)
    ui.barSystem(world, battle)
    ui.skillIconSystem(world, battle, dt)
    ui.drawResourceBar(battle)

    -- Victory overlay
    if battle.victoryTimer then
        local alpha = math.min(1, (2.0 - battle.victoryTimer) / 0.5)
        love.graphics.setColor(0, 0, 0, alpha * 0.5)
        love.graphics.rectangle("fill", 0, 0, VW, VH)
        love.graphics.setFont(battle.font)
        local txt = "VICTORY"
        local tw  = battle.font:getWidth(txt)
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.print(txt, (VW-tw)/2, VH/2 - battle.font:getHeight())
    end

    love.graphics.setFont(battle.smallFont)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print("1-2: select  Q/W/E: skills (20 res)  K: spawn  RClick: target/move  P: pause  Esc: retreat", 5, VH - RESOURCE_BAR_AREA_H - 14)
    love.graphics.setColor(1, 1, 1, 1)

    -- Pause button (top-right): two bars when running, a play-triangle when
    -- paused (the universal "click to resume" affordance).
    do
        local px, py, pw, ph = pauseBtnRect()
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", px, py, pw, ph)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)
        if not paused then
            -- Two pause bars.
            local barW, barH = 5, ph * 0.5
            local gap = 5
            local bx = px + (pw - (barW * 2 + gap)) / 2
            love.graphics.rectangle("fill", bx, py + (ph - barH) / 2, barW, barH)
            love.graphics.rectangle("fill", bx + barW + gap, py + (ph - barH) / 2, barW, barH)
        else
            -- Play triangle (resume).
            local cx, cy = px + pw / 2, py + ph / 2
            local r = ph * 0.32
            love.graphics.polygon("fill",
                cx - r * 0.6, cy - r,
                cx - r * 0.6, cy + r,
                cx + r,       cy)
        end
    end

    -- PAUSED overlay (subtle dim + label) so the Director knows the sim is
    -- frozen and the screenshot is stable.
    if paused then
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.rectangle("fill", 0, 0, VW, VH)
        love.graphics.setFont(battle.font)
        local txt = "PAUSED"
        local tw  = battle.font:getWidth(txt)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(txt, (VW - tw) / 2, 14)
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, sd, slot, encounterConfig)
    switchFn     = sw
    saveData_ref = sd
    slot_ref     = slot
    require("music_mgr").play("battle")

    initWorld()
    initBattle(canvas, postfx)
    loadAssets()

    -- Expose icon lookup for UI sub-module
    battle.getIconImage = getIconImage


    -- Initialize encounter manager from config
    local cfg = encounterConfig or {}
    local spawnDelay = cfg.spawnDelay or 4.0
    battle.encounterMgr = {
        dangerThreshold  = cfg.dangerThreshold  or 3,
        waveMinThreat    = cfg.waveMinThreat    or 3,
        waveMaxThreat    = cfg.waveMaxThreat    or 12,
        encounterGoal    = cfg.encounterGoal    or 45,
        spawnTimer       = spawnDelay,
        waveCooldown     = 0,
        currentDanger    = 0,
        dangerDefeated   = 0,
        surpriseTimer    = 30,
        surpriseInterval = 30,
        surpriseChance   = 0.15,
        pendingWave      = nil,
    }

    -- Spawn party walking in — rhombus formation.
    -- Members are 100px apart horizontally; vertical position alternates every
    -- slot by 100px, so slots 1 & 3 share one level and slots 2 & 4 share another.
    -- All spawn off-screen already in formation and walk in together.
    local partyOrder = sd and sd.partyOrder or {"knight"}
    local SLOT_H     = 40 * SCALE

    local x1   = VW * 0.25 - 60   -- leftmost member X (centers formation at VW*0.25)
    local y_hi = VH * 0.54        -- midbottom Y for slots 1 and 3
    local y_lo = y_hi + 40        -- midbottom Y for slots 2 and 4

    local rhombusPos = {
        {x = x1,      y = y_hi},  -- slot 1: left,         high
        {x = x1 + 40, y = y_lo},  -- slot 2: centre-left,  low
        {x = x1 + 80, y = y_hi},  -- slot 3: centre-right, high
        {x = x1 + 120, y = y_lo}, -- slot 4: right,        low
    }

    local WALK_IN = VW * 0.5  -- off-screen walk-in distance, same for all members

    local partyRow = 0
    for i = 1, 4 do
        local charName = partyOrder[i]
        if type(charName) ~= "string" then goto spawnNext end
        partyRow = partyRow + 1
        local charData = sd and sd.unlockedCharacters and sd.unlockedCharacters[charName]
        local ss  = charData and charData.stats or nil
        local pos = rhombusPos[partyRow] or {x = x1, y = y_hi}
        local spawnX = pos.x - WALK_IN
        local spawnY = pos.y - SLOT_H / 2
        local id
        if charName == "knight" then
            id = entities_mod.createKnight(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "brigand" then
            id = entities_mod.createBrigand(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "champion" then
            id = entities_mod.createChampion(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "duelist" then
            id = entities_mod.createDuelist(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "nomad" then
            id = entities_mod.createNomad(world, battle, spawnX, spawnY, ss, SCALE)
        elseif charName == "cleric" then
            id = entities_mod.createCleric(world, battle, spawnX, spawnY, ss, SCALE)
        elseif charName == "paladin" then
            id = entities_mod.createPaladin(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "wizard" then
            id = entities_mod.createWizard(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "rogue" then
            id = entities_mod.createRogue(world, battle, spawnX, spawnY, ss, SCALE, GRAVITY)
        end
        if id then
            world.hasEntered[id]        = {h=false, v=false}
            world.moveTarget[id].x      = pos.x
            world.moveTarget[id].y      = pos.y
            world.moveTarget[id].active = true
            table.insert(battle.partyIds, id)
        end
        ::spawnNext::
    end
    battle.selectedUnit = battle.partyIds[1]
end

function M.onExit()
    if battle.postfx then
        battle.postfx.chromasep.radius = common.CHROMA_RADIUS
    end
end

function M.update(dt)
    -- PAUSED: freeze all simulation + animations. Draw still runs (M.draw is
    -- separate), so the screen stays visible for screenshots. Only the pause
    -- toggle itself is still handled (in mousepressed/keypressed).
    if paused then return end

    -- Victory timeout → return to map
    if battle.victoryTimer then
        battle.victoryTimer = battle.victoryTimer - dt
        if battle.victoryTimer <= 0 then
            switchFn("map", saveData_ref, slot_ref)
            return
        end
        systems.vfxDecay(battle, dt, common)
        return
    end

    particles.updateBlood(battle, dt, GRAVITY)
    particles.updateHeal(battle, dt)
    systems.targetFollow(world)
    skills_mod.pendingActiveSystem(world, battle)
    skills_mod.autoAttackSystem(world)
    skills_mod.system(world, battle, dt)
    effects_mod.system(world, battle, dt)
    effects_mod.effectTintSystem(world, dt)
    status_mod.system(world, battle, dt)
    systems.stagger(world, dt)
    systems.stunSystem(world, dt)
    systems.threat(world, battle, dt)
    systems.moveTarget(world, dt)
    systems.physics(world, dt, VW, VH - RESOURCE_BAR_AREA_H, BATTLE_LINE_Y, FRICTION, MASS)
    systems.updateFacing(world)
    anim_mod.updateTimers(world, dt)
    systems.death(world, battle, dt)
    systems.vfxDecay(battle, dt, common)
    ui.updateIconScaleAnimations(world, battle, dt)
    ui.updateSelCircles(world, battle, dt)
    enc_mgr.system(world, battle, dt, VW, VH, SCALE, GRAVITY, ENEMY_DANGER)

    -- Resource regeneration (1 per second) + pop animations
    do
        local prev = battle.resource
        battle.resource = math.min(battle.resourceMax, battle.resource + dt)
        local prevSegs = math.floor(prev / RES_PER_SEG)
        local currSegs = math.floor(battle.resource / RES_PER_SEG)
        for i = prevSegs + 1, math.min(currSegs, RES_SEG_COUNT) do
            battle.resourcePops[i] = 1.0
        end
        for i = 1, RES_SEG_COUNT do
            local p = battle.resourcePops[i]
            if p then
                battle.resourcePops[i] = p - dt / 0.3
                if battle.resourcePops[i] <= 0 then battle.resourcePops[i] = nil end
            end
        end
    end

    -- Hover detection for plate highlighting
    do
        local vmx, vmy = common.virtualMouse()
        battle.hoveredUnit = nil
        for id in pairs(world.entities) do
            if not world.deathState[id] then
                local pos, sz = world.position[id], world.size[id]
                if pos and sz
                and vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
                and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                    battle.hoveredUnit = id; break
                end
            end
        end
    end

    if battle.victoryDelay then
        battle.victoryDelay = battle.victoryDelay - dt
        if battle.victoryDelay <= 0 then
            battle.victoryDelay = nil
            local dur = (battle.victorySnd and battle.victorySnd:getDuration() or 4.0)
            battle.victoryTimer = math.max(1.0, dur - 2.0)
        end
    elseif enc_mgr.checkVictory(world, battle) then
        require("music_mgr").stop()
        if battle.victorySnd then
            battle.victorySnd:stop()
            battle.victorySnd:play()
        end
        battle.victoryDelay = 2.0
    end
end

function M.keypressed(key)
    -- P toggles pause (works even while paused).
    if key == "p" then
        paused = not paused
        common.playClickSound()
        return
    end

    if key == "escape" then
        -- Esc unpauses if paused; otherwise retreats to the map.
        if paused then
            paused = false
            return
        end
        switchFn("map", saveData_ref, slot_ref)
        return
    end

    if paused then return end   -- while paused, ignore combat/selection keys

    if key == "1" and battle.partyIds[1] and not battle.deadSlots[1] then battle.selectedUnit = battle.partyIds[1] end
    if key == "2" and battle.partyIds[2] and not battle.deadSlots[2] then battle.selectedUnit = battle.partyIds[2] end
    if key == "3" and battle.partyIds[3] and not battle.deadSlots[3] then battle.selectedUnit = battle.partyIds[3] end
    if key == "4" and battle.partyIds[4] and not battle.deadSlots[4] then battle.selectedUnit = battle.partyIds[4] end

    if key == "k" then
        local vmx, vmy = common.virtualMouse()
        entities_mod.createSkeleton(world, battle, vmx, vmy, SCALE, GRAVITY, ENEMY_DANGER)
    end

    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end

    local slotMap = {q=1, w=2, e=3, r=4}
    local slot = slotMap[key]
    if slot then
        -- enqueue re-checks cd + resource and pays at press; activation is
        -- deferred to skills_mod.system when the unit is free & in range.
        skills_mod.enqueue(world, battle, su, slot)
    end
end

function M.mousepressed(x, y, button)
    local vmx, vmy = common.virtualMouse()

    -- Pause button (top-right): toggles the freeze. Checked FIRST so it works
    -- even while paused, and never falls through to unit selection.
    if button == 1 then
        local px, py, pw, ph = pauseBtnRect()
        if vmx >= px and vmx < px + pw and vmy >= py and vmy < py + ph then
            paused = not paused
            common.playClickSound()
            return
        end
    end

    if paused then return end   -- while paused, ignore all other input

    if button == 1 then
        for i, id in ipairs(battle.partyIds) do
            if not battle.deadSlots[i] then
                local pos, sz = world.position[id], world.size[id]
                if pos and sz and vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
                and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                    battle.selectedUnit = id; break
                end
            end
        end
        return
    end

    if button ~= 2 then return end
    local su = battle.selectedUnit; if not su then return end
    if battle.hoveredUnit and not world.deathState[battle.hoveredUnit] then
        battle.pressedUnit = battle.hoveredUnit
    end

    local tSide = world.targetSide[su] or 1
    local clicked = nil
    for id in pairs(world.entities) do
        if world.deathState[id]           then goto scanNext end
        if id == su and tSide ~= 0        then goto scanNext end
        local sd, pos, sz = world.side[id], world.position[id], world.size[id]
        if sd and sd.s == tSide and pos and sz then
            if vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
            and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                clicked = id; break
            end
        end
        ::scanNext::
    end

    if clicked then
        world.entityTarget[su] = {id=clicked}
        world.hasAttacked[su]  = nil
        if tSide == 1 then
            for id in pairs(world.entities) do
                local sd = world.side[id]
                if sd and sd.s == 1 and world.threatMap[id] then
                    world.threatMap[id].map[su] = world.threatMap[id].map[su] or 0
                end
            end
        end
    else
        local sgSu = world.stagger[su]
        if not (sgSu and sgSu.staggered) then
            world.entityTarget[su] = nil
            world.hasAttacked[su]  = nil
        end
        local mt = world.moveTarget[su]
        if mt then mt.x=vmx; mt.y=vmy; mt.active=true end
        local sk = world.skills[su]
        if sk and sk.list[0] then sk.list[0].cd = 0 end
        effects_mod.cancelActions(world, su)
    end
end

function M.mousereleased(x, y, button)
    if button == 2 then battle.pressedUnit = nil end
end

function M.draw()
    local vfx = battle.vfx

    love.graphics.setCanvas(battle.canvas)
    love.graphics.clear()
    drawScene(love.timer.getDelta())
    love.graphics.setCanvas()

    local ox, oy, s = common.letterbox()
    local zx, zy = vfx.zoomX, vfx.zoomY
    local zs = s * vfx.zoom
    local wx, wy = ox + zx*s, oy + zy*s
    local sk = math.floor(vfx.shake)
    local sox = sk > 0 and love.math.random(-sk, sk) or 0
    local soy = sk > 0 and love.math.random(-sk, sk) or 0

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)

    battle.postfx(function()
        love.graphics.draw(battle.canvas, wx+sox, wy+soy, 0, zs, zs, zx, zy)
    end)
end

return M

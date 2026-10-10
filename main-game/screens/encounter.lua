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
local wave_gen     = require("encounter/wave_gen")
local victory      = require("encounter/victory")
local defeat       = require("encounter/defeat")
local ui           = require("encounter/ui")
local progression  = require("progression")

local VW    = common.VW
local VH    = common.VH
local SCALE = VH / 300

local GRAVITY       = 9.8 * 30 * SCALE
local MASS          = 70
local FRICTION      = 0.9
local BATTLE_LINE_Y = VH * 0.2

-- Resource bar layout constants
local RES_PER_SEG        = require("encounter/abilities").RESOURCE_PER_BAR
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

-- Pause: freezes ALL simulation + animations and shows a small menu
-- (RETURN = carry on, RETREAT = leave the battle as if it was never entered).
-- Toggled by ESC, SPACE or the top-right icon. While paused, M.update skips
-- every system tick; draw still runs so the screen stays visible.
local paused = false
local pauseHover, pausePressed = nil, nil     -- index into PAUSE_ITEMS

local PAUSE_ITEMS  = { "RETURN", "RETREAT" }
local PAUSE_MENU_W = 180
local PAUSE_ITEM_H = 34
local PAUSE_MENU_H = 20 + #PAUSE_ITEMS * PAUSE_ITEM_H + 20
local PAUSE_MENU_X = math.floor((VW - PAUSE_MENU_W) / 2)
local PAUSE_MENU_Y = math.floor((VH - PAUSE_MENU_H) / 2)

-- The box around menu item i (what the hover box covers and a click hits).
local function pauseItemRect(i)
    local w, h = 120, 26
    return math.floor(PAUSE_MENU_X + (PAUSE_MENU_W - w) / 2),
           PAUSE_MENU_Y + 20 + (i - 1) * PAUSE_ITEM_H + (PAUSE_ITEM_H - h) / 2, w, h
end

local function pauseItemAt(x, y)
    for i = 1, #PAUSE_ITEMS do
        local ix, iy, iw, ih = pauseItemRect(i)
        if x >= ix and x < ix + iw and y >= iy and y < iy + ih then return i end
    end
    return nil
end

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

-- The battle can be paused until it is decided (no menu over VICTORY / DEFEAT).
local function canPause()
    return not (battle.victory or battle.victoryDelay or battle.defeat)
end

local function setPaused(on)
    paused = on and canPause() or false
    pauseHover, pausePressed = nil, nil
    common.playClickSound()
end

-- Leave a battle that was not won (defeat or RETREAT): no rewards. The map
-- recorded this encounter as cleared when it was entered; put it back, so the
-- party stands in front of it again exactly as before entering.
local function leaveUnfought()
    local mp = saveData_ref and saveData_ref.mapProgression
    if mp and mp.clearedEncounters and #mp.clearedEncounters > 0 then
        table.remove(mp.clearedEncounters)
        if slot_ref then require("save").write(slot_ref, saveData_ref) end
    end
    switchFn("map", saveData_ref, slot_ref)
end

-- ============================================================================
-- WORLD INIT
-- ============================================================================

local function initWorld()
    world = require("encounter/world").new()
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
    battle.partyNames      = {}
    battle.selectedUnit    = nil
    battle.deadSlots       = {}
    battle.iconScales      = {1.0, 1.0, 1.0, 1.0}
    battle.victory         = nil   -- encounter/victory.lua state once the battle is won
    battle.defeat          = nil   -- encounter/defeat.lua state once every hero is dead
    battle.victoryDelay    = nil   -- short pause between the last kill and the victory screens
    battle.victorySnd      = nil
    battle.score           = {}    -- [unitId] = performance score (combat.addScore)
    battle.showBoxes       = false -- debug: draw body boxes (key B)
    battle.hoveredUnit     = nil
    battle.pressedUnit     = nil
    battle.resource        = 0
    battle.resourceMax     = RESOURCE_MAX
    battle.resourcePops    = {}
    battle.enemyDefeated   = 0   -- enemies killed this battle (gold drip)
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

    -- BH's "spider" battlefield (The Silken Wildwood), cropped to 16:9.
    local ok, bg = pcall(love.graphics.newImage, "assets/images/bh_spider_forest.png")
    battle.battlebg = ok and bg or nil

    for _, sheet in ipairs(require("data/sprites")) do
        anim_mod.load(sheet[1], "assets/" .. sheet[2], sheet[3], sheet[4], sheet[5])
    end

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

    -- DEBUG (key B): every unit's body box (white) and feet line (red). The
    -- sprite should stand exactly inside its box; see ./align_sprites.
    if battle.showBoxes then
        love.graphics.setLineWidth(1)
        for id in pairs(world.entities) do
            local pos, sz = world.position[id], world.size[id]
            if pos and sz then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("line", pos.x - sz.w/2, pos.y - sz.h/2, sz.w, sz.h)
                love.graphics.setColor(1, 0, 0, 1)
                love.graphics.line(pos.x - sz.w/2 - 4, pos.y + sz.h/2, pos.x + sz.w/2 + 4, pos.y + sz.h/2)
            end
        end
    end

    victory.draw(battle)
    defeat.draw(battle)

    love.graphics.setColor(1, 1, 1, 1)

    -- Pause button (top-right, no frame): two bars when running, a
    -- play-triangle when paused.
    do
        local px, py, pw, ph = pauseBtnRect()
        love.graphics.setColor(1, 1, 1, 1)
        if not paused then
            local barW, barH = 5, ph * 0.5
            local gap = 5
            local bx = px + (pw - (barW * 2 + gap)) / 2
            love.graphics.rectangle("fill", bx, py + (ph - barH) / 2, barW, barH)
            love.graphics.rectangle("fill", bx + barW + gap, py + (ph - barH) / 2, barW, barH)
        else
            local cx, cy = px + pw / 2, py + ph / 2
            local r = ph * 0.32
            love.graphics.polygon("fill",
                cx - r * 0.6, cy - r,
                cx - r * 0.6, cy + r,
                cx + r,       cy)
        end
    end

    -- Pause menu: dim the battle, small panel in the middle.
    if paused then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, VW, VH)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", PAUSE_MENU_X, PAUSE_MENU_Y, PAUSE_MENU_W, PAUSE_MENU_H)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", PAUSE_MENU_X, PAUSE_MENU_Y, PAUSE_MENU_W, PAUSE_MENU_H)
        local f = common.loadFont(16)
        for i, label in ipairs(PAUSE_ITEMS) do
            local ix, iy, iw, ih = pauseItemRect(i)
            local pressed = pausePressed == i and pauseHover == i
            if pressed then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("fill", ix, iy, iw, ih)
            elseif pauseHover == i then
                love.graphics.setColor(1, 0, 0, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", ix, iy, iw, ih)
            end
            love.graphics.setColor(pressed and common.COLOR_BLACK or common.COLOR_WHITE)
            common.printCentered(f, label, ix, iy, iw, ih)
        end
        love.graphics.setColor(1, 1, 1, 1)
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
    paused       = false
    require("music_mgr").play("battle")

    initWorld()
    initBattle(canvas, postfx)
    loadAssets()

    -- Expose icon lookup for UI sub-module
    battle.getIconImage = getIconImage


    -- The battle's waves: generated for how far into the floor the party is.
    -- encounterConfig (tests only): { waves = {...}, spawnDelay = seconds before the first enemy }.
    local cfg = encounterConfig or {}
    battle.encounterMgr = enc_mgr.new(cfg.waves or wave_gen.generate(progression.battleTier(sd)), cfg.spawnDelay)

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
        local pos = rhombusPos[partyRow] or {x = x1, y = y_hi}
        local spawnX = pos.x - WALK_IN
        local spawnY = pos.y - SLOT_H / 2
        local id = entities_mod.createHero(world, battle, charName, spawnX, spawnY,
                                           sd and progression.heroStats(sd, charName))
        if id then
            -- pos.x/pos.y is the GROUND/feet point for this slot ("midbottom Y").
            -- moveTarget treats mt.y as a CENTER coord, so convert: center.y =
            -- groundY - size.h/2. (size.h equals SLOT_H for all party classes.)
            world.moveTarget[id].x      = pos.x
            world.moveTarget[id].y      = pos.y - SLOT_H / 2
            world.moveTarget[id].active = true
            table.insert(battle.partyIds, id)
            battle.partyNames[#battle.partyIds] = charName   -- parallel to partyIds
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
    if paused then
        local hov = pauseItemAt(common.virtualMouse())
        if hov and hov ~= pauseHover then common.playHoverSound() end
        pauseHover = hov
        return
    end

    -- Victory screens (gold, item, XP); back to the map when dismissed.
    if battle.victory then
        if victory.update(battle, dt) then
            switchFn("map", saveData_ref, slot_ref)
            return
        end
        systems.vfxDecay(battle, dt, common)
        return
    end

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
    systems.physics(world, dt, VW, VH - RESOURCE_BAR_AREA_H, BATTLE_LINE_Y, FRICTION, MASS)
    systems.updateFacing(world)
    anim_mod.updateTimers(world, dt)
    systems.death(world, battle, dt)
    systems.vfxDecay(battle, dt, common)
    ui.updateIconScaleAnimations(world, battle, dt)
    ui.updateSelCircles(world, battle, dt)
    enc_mgr.system(world, battle, dt, VW, VH)

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

    if battle.defeat then
        if defeat.update(battle, dt) then
            -- Lost: no rewards, nothing taken (BH); the encounter can be fought again.
            leaveUnfought()
            return
        end
    elseif battle.victoryDelay then
        battle.victoryDelay = battle.victoryDelay - dt
        if battle.victoryDelay <= 0 then
            battle.victoryDelay = nil
            -- Grant the rewards (once) and show them.
            local survivors, scores = {}, {}
            for i, name in ipairs(battle.partyNames or {}) do
                if not battle.deadSlots[i] then survivors[#survivors + 1] = name end
                scores[name] = battle.score[battle.partyIds[i]] or 0
            end
            local result = saveData_ref
                and progression.onEncounterWon(saveData_ref, survivors, battle.enemyDefeated, scores)
                or { gold = 0, kills = battle.enemyDefeated, xp = {} }
            if saveData_ref and slot_ref then require("save").write(slot_ref, saveData_ref) end
            victory.start(battle, result, battle.partyNames, battle.deadSlots)
        end
    elseif enc_mgr.checkDefeat(world, battle) then
        require("music_mgr").stop()
        battle.selectedUnit = nil
        defeat.start(battle)
    elseif enc_mgr.checkVictory(world, battle) then
        require("music_mgr").stop()
        if battle.victorySnd then
            battle.victorySnd:stop()
            battle.victorySnd:play()
        end
        battle.victoryDelay = 1.7   -- BH: VICTORY appears 1.7 s after the last kill
    end
end

function M.keypressed(key)
    -- ESC or SPACE: open / close the pause menu.
    if key == "escape" or key == "space" or key == " " then   -- LÖVE 11 reports the spacebar as "space"
        if paused or canPause() then setPaused(not paused) end
        return
    end

    if paused then return end   -- while paused, ignore combat/selection keys

    if battle.victory then victory.advance(battle); return end
    if battle.defeat then defeat.advance(battle); return end

    if key == "1" and battle.partyIds[1] and not battle.deadSlots[1] then battle.selectedUnit = battle.partyIds[1] end
    if key == "2" and battle.partyIds[2] and not battle.deadSlots[2] then battle.selectedUnit = battle.partyIds[2] end
    if key == "3" and battle.partyIds[3] and not battle.deadSlots[3] then battle.selectedUnit = battle.partyIds[3] end
    if key == "4" and battle.partyIds[4] and not battle.deadSlots[4] then battle.selectedUnit = battle.partyIds[4] end

    -- DEBUG: B shows / hides the body boxes.
    if key == "b" then battle.showBoxes = not battle.showBoxes end

    -- DEBUG: K / J / L / M spawn a skeleton / goblin / bat / mushroom under the mouse.
    local debugSpawn = ({ k = "skeleton", j = "goblin", l = "bat", m = "mushroom" })[key]
    if debugSpawn then
        local vmx, vmy = common.virtualMouse()
        entities_mod.createEnemy(world, battle, debugSpawn, vmx, vmy)
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
            if paused or canPause() then setPaused(not paused) end
            return
        end
    end

    if paused then   -- while paused, only the menu takes input
        if button == 1 then pausePressed = pauseItemAt(vmx, vmy) end
        return
    end

    if battle.victory then
        if button == 1 then victory.advance(battle) end
        return
    end
    if battle.defeat then
        if button == 1 then defeat.advance(battle) end
        return
    end

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
        -- A hero given a target while it had none attacks as soon as it is in
        -- range (BH: actionTimer = 100 on a fresh target order).
        local hadTarget = world.entityTarget[su] ~= nil
        world.entityTarget[su] = {id=clicked}
        local skSu = world.skills[su]
        if not hadTarget and skSu and skSu.list[0] then skSu.list[0].cd = 0 end
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
        end
        -- Right-click move: vmx/vmy is a GROUND/feet point (where the player
        -- clicked). moveTarget treats mt.x/mt.y as CENTER coords, so convert:
        -- center.y = groundY - size.h/2 (the feet rule). This makes the unit
        -- stop with its FEET at the clicked point.
        local mt = world.moveTarget[su]
        local suSz = world.size[su]
        if mt and suSz then
            mt.x = vmx
            mt.y = vmy - suSz.h / 2
            mt.active = true
        end
        skills_mod.interrupt(world, su)
    end
end

function M.mousereleased(x, y, button)
    if paused then
        local hit = button == 1 and pausePressed and pauseItemAt(common.virtualMouse()) == pausePressed and pausePressed
        pausePressed = nil
        if hit == 1 then
            setPaused(false)                       -- RETURN
        elseif hit == 2 then
            common.playClickSound()                -- RETREAT
            paused = false
            leaveUnfought()
        end
        return
    end
    if button == 2 then battle.pressedUnit = nil end
end

-- Test hook (ui_smoke_test.lua): the live world/battle tables, read-only use.
function M.debugState() return world, battle end

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

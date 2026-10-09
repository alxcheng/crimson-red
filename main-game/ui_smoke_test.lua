-- ============================================================================
-- ui_smoke_test.lua — UI-screen DRIVER smoke test (agents)
--
-- NOT a screen. Replaces the app entry when main.lua sees CR_TEST_SCENE=ui
-- (invoked by ./test_ui). headless_test.lua only LOADS the UI screens; this
-- one DRIVES them: for each town-menu screen it calls onEnter, then pumps
-- update/draw while sweeping a grid of synthetic hovers, left/right clicks,
-- key presses and wheel ticks across the whole 800x450 canvas. Every call is
-- xpcall-wrapped, so call-time errors (nil upvalues, bad scissor, bad save
-- shapes) are caught and listed instead of surfacing in a Director playtest.
--
-- Isolation: save.write is stubbed (the Director's real save slots are never
-- touched), music/sfx are stubbed, the mouse is synthetic (common.virtualMouse
-- is replaced). Screenshots of each screen are written to the LÖVE save dir
-- under ui_smoke/ so an agent can look at the result.
-- ============================================================================

local common    = require("common")
local moonshine = require("moonshine")
local save      = require("save")
local items     = require("items")
local progression = require("progression")
local music_mgr = require("music_mgr")

local VW, VH = common.VW, common.VH

local M = {}

-- ---- synthetic input / stubs ----
local mouseX, mouseY = -100, -100
local saveWrites = 0
local switched   = nil      -- {name, ...} recorded from the screen's switchFn

local function installStubs()
    common.virtualMouse   = function() return mouseX, mouseY end
    common.playClickSound = function() end
    common.playHoverSound = function() end
    music_mgr.play        = function() end
    music_mgr.stop        = function() end
    save.write            = function() saveWrites = saveWrites + 1 end
end

local function switchFn(name, ...)
    switched = { name = name, args = {...} }
end

-- ---- fixtures ----
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepCopy(v) end
    return out
end

-- Brand-new game, exactly what save_select hands to the map on a fresh slot.
local function fixtureFresh()
    return deepCopy(save.defaultData())
end

-- Mid-run save: full party, mixed levels, gold, a stocked inventory.
local function fixtureRich()
    local sd = deepCopy(save.defaultData())
    sd.floor      = 2
    sd.gold       = 500
    sd.partyOrder = { "knight", "cleric", "wizard", "rogue" }
    for name, level in pairs({ knight = 9, cleric = 4, wizard = 1, rogue = 21 }) do
        local rec = sd.unlockedCharacters[name]
        rec.recruited, rec.level = true, level
        items.equipStarterGear(sd, name)
    end
    -- Longsword, Scale Mail, Soft Leather Garb, Silver Armlet, Swordsman's Gauntlet, Energy Ring
    for _, bhId in ipairs({ 10, 4, 5, 24, 12, 15 }) do
        table.insert(sd.inventory, items.mint(sd, bhId))
    end
    return sd
end

-- ---- results ----
local errors     = {}   -- unique messages, in first-seen order
local errorCount = {}   -- message -> occurrences
local checks     = {}   -- { ok=bool, label=string }
local canvas, postfx

local function recordError(where, err)
    local msg = tostring(err)
    local head = where .. ": " .. (msg:match("^[^\n]*") or msg)
    if not errorCount[head] then
        errorCount[head] = 0
        errors[#errors + 1] = { head = head, full = msg }
    end
    errorCount[head] = errorCount[head] + 1
end

local function check(ok, label)
    checks[#checks + 1] = { ok = ok and true or false, label = label }
end

-- Run fn under xpcall; reset graphics state on failure so one bad draw (e.g. a
-- dangling canvas/scissor/push) doesn't cascade into unrelated errors.
local function guard(where, fn, ...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then
        recordError(where, err)
        pcall(love.graphics.setCanvas)
        pcall(love.graphics.setScissor)
        while pcall(love.graphics.pop) do end   -- unwind any leaked push
        pcall(love.graphics.origin)
        pcall(love.graphics.setShader)
    end
    return ok
end

local function screenshot(name)
    if not canvas then return end
    love.filesystem.createDirectory("ui_smoke")
    local ok, err = pcall(function()
        canvas:newImageData():encode("png", "ui_smoke/" .. name .. ".png")
    end)
    if not ok then print("UI_SMOKE screenshot failed: " .. tostring(err)) end
end

-- ---- driver ----
local KEYS = { "up", "down", "left", "right", "w", "a", "s", "d", "tab", "1", "2", "3",
               "q", "e", "space", " ", "return", "kpenter", "escape" }

local function drive(tag, screenName, sd, opts)
    opts = opts or {}
    local scr  = require("screens/" .. screenName)
    local slot = 99
    local enters, exits = 0, {}

    local function enter()
        switched = nil
        enters = enters + 1
        return guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, slot)
    end
    local function frame(draw)
        guard(tag .. " update", scr.update, 1 / 60)
        if draw then guard(tag .. " draw", scr.draw) end
    end
    local function afterInput()
        if switched then
            exits[switched.name] = (exits[switched.name] or 0) + 1
            if scr.onExit then guard(tag .. " onExit", scr.onExit) end
            enter()
        end
    end

    if not enter() then return exits end
    mouseX, mouseY = -100, -100
    for _ = 1, 3 do frame(true) end
    screenshot(tag .. "-1-enter")

    -- Tooltip screenshots: opts.hover = { {x, y}, ... } points to rest the mouse on.
    for i, pt in ipairs(opts.hover or {}) do
        mouseX, mouseY = pt[1], pt[2]
        for _ = 1, 30 do frame(true) end
        screenshot(tag .. "-1h" .. i .. "-hover")
    end

    -- Hover sweep (draw every frame at a coarse grid: hover states are where
    -- tooltip / desc-bar code paths live).
    for y = 4, VH, 12 do
        for x = 4, VW, 12 do
            mouseX, mouseY = x, y
            frame(true)
        end
    end

    -- Click sweeps: left on a fine grid, right on a coarser one.
    local function clickSweep(button, step)
        local n = 0
        for y = 3, VH, step do
            for x = 3, VW, step do
                mouseX, mouseY = x, y
                frame(false)
                if scr.mousepressed then guard(tag .. " mousepressed", scr.mousepressed, x, y, button) end
                frame(false)
                if scr.mousereleased then guard(tag .. " mousereleased", scr.mousereleased, x, y, button) end
                n = n + 1
                frame(n % 15 == 0)
                afterInput()
            end
        end
    end
    clickSweep(1, 7)
    screenshot(tag .. "-2-after-clicks")
    clickSweep(2, 16)

    -- Random fuzz: multi-step interactions (select item -> click slot, switch
    -- tab -> buy, scroll -> pick) that a single ordered sweep cannot compose.
    for n = 1, (opts.fuzz or 6000) do
        local r = math.random()
        mouseX, mouseY = math.random(0, VW - 1), math.random(0, VH - 1)
        frame(false)
        if r < 0.06 and scr.wheel then
            guard(tag .. " wheel", scr.wheel, math.random(-3, 3))
        else
            local button = (r > 0.97) and 2 or 1
            if scr.mousepressed then guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, button) end
            frame(false)
            if scr.mousereleased then guard(tag .. " mousereleased", scr.mousereleased, mouseX, mouseY, button) end
        end
        frame(n % 40 == 0)
        afterInput()
    end
    screenshot(tag .. "-2b-after-fuzz")

    -- Directed scroll sweep: step the wheel down one notch at a time and click
    -- both branch columns over the whole height, so every row that scrolling
    -- can bring into view gets a click on each side.
    if opts.scrollSweep and scr.wheel then
        guard(tag .. " wheel", scr.wheel, -1000)
        for _ = 1, opts.scrollSweep do
            for _, x in ipairs({ 300, 500 }) do
                for y = 100, VH, 8 do
                    mouseX, mouseY = x, y
                    frame(false)
                    guard(tag .. " mousepressed", scr.mousepressed, x, y, 1)
                    frame(false)
                    guard(tag .. " mousereleased", scr.mousereleased, x, y, 1)
                    frame(false)
                end
            end
            guard(tag .. " wheel", scr.wheel, 1)
            frame(true)
        end
        screenshot(tag .. "-2c-scrolled-to-end")
    end

    -- Wheel.
    if scr.wheel then
        for _, dy in ipairs({ 1, 1, 1, 5, -1, -9, 3 }) do
            guard(tag .. " wheel", scr.wheel, dy)
            frame(true)
        end
        screenshot(tag .. "-3-scrolled")
    end

    -- Keys (mouse parked off-canvas so keys act alone).
    mouseX, mouseY = -100, -100
    for pass = 1, 2 do
        for _, key in ipairs(KEYS) do
            if scr.keypressed then guard(tag .. " keypressed(" .. key .. ")", scr.keypressed, key) end
            frame(true)
            afterInput()
        end
    end
    screenshot(tag .. "-4-end")
    return exits
end

-- ---- save invariants (the economy contract, work/phase0-contract.md) ----
local function invariants(tag, sd)
    check(type(sd.gold) == "number" and sd.gold >= 0 and sd.gold == math.floor(sd.gold),
          tag .. ": gold is a non-negative integer (" .. tostring(sd.gold) .. ")")
    local seen, dup, dangling = {}, 0, 0
    for _, id in ipairs(sd.inventory or {}) do
        if seen[id] then dup = dup + 1 end
        seen[id] = true
        if not sd.items[id] then dangling = dangling + 1 end
    end
    check(dup == 0, tag .. ": no duplicate ids in inventory")
    check(dangling == 0, tag .. ": every inventory id resolves in items")
    local eqBad, eqDup = 0, 0
    for name, rec in pairs(sd.unlockedCharacters or {}) do
        for slotName, id in pairs(rec.equipped or {}) do
            if not sd.items[id] or sd.items[id].itemType ~= slotName then eqBad = eqBad + 1 end
            if seen[id] then eqDup = eqDup + 1 end
            seen[id] = true
        end
    end
    check(eqBad == 0, tag .. ": every equipped id resolves to an item of that slot's type")
    check(eqDup == 0, tag .. ": no item is both equipped and in inventory / equipped twice")
    local poBad, poSeen = 0, {}
    for i = 1, 4 do
        local n = sd.partyOrder[i]
        if type(n) == "string" then
            if not sd.unlockedCharacters[n] or poSeen[n] then poBad = poBad + 1 end
            poSeen[n] = true
        end
    end
    check(poBad == 0, tag .. ": partyOrder entries are unique, unlocked characters")
    local ok = pcall(require("json").encode, sd)
    check(ok, tag .. ": save still JSON-encodes")
end

local function countEquipped(sd)
    local n = 0
    for _, rec in pairs(sd.unlockedCharacters) do
        for _ in pairs(rec.equipped or {}) do n = n + 1 end
    end
    return n
end

local function countPicks(rec)
    local n = 0
    for _, v in ipairs(rec.skillTree or {}) do
        if type(v) == "string" and v ~= "" then n = n + 1 end
    end
    return n
end

-- Directed map walk: start tile (9,5) -> right -> up lands on the "S" tile
-- (10,4). The camera keeps the player centred, so the neighbours are always
-- one 80px tile from screen centre. Then click the popup until it engages.
local function mapShopWalk(sd)
    local tag, scr = "map-shop", require("screens/map")
    switched = nil
    if not guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99) then return nil end
    local function frames(n)
        for _ = 1, n do
            guard(tag .. " update", scr.update, 1 / 60)
            guard(tag .. " draw", scr.draw)
        end
    end
    local function click(x, y)
        mouseX, mouseY = x, y
        frames(2)
        guard(tag .. " mousepressed", scr.mousepressed, x, y, 1)
        frames(1)
        guard(tag .. " mousereleased", scr.mousereleased, x, y, 1)
        frames(1)
    end
    local function engagePopup()
        frames(90)
        for y = 60, VH - 4, 6 do
            for x = 600, VW - 4, 8 do
                click(x, y)
                if switched then return switched.name end
            end
        end
        return nil
    end
    frames(30)
    click(480, 245); frames(60)   -- step right
    click(400, 165); frames(60)   -- step up, onto the shop tile
    screenshot(tag .. "-1-on-shop-tile")
    local first = engagePopup()
    -- Coming back from the shop: same save, fresh onEnter.
    switched = nil
    guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99)
    screenshot(tag .. "-2-back-from-shop")
    local second = engagePopup()
    return first, second
end

-- Drive a whole battle on screens/encounter.lua: enter with `party`, mash the
-- ability keys, retarget with right-clicks, toggle pause, and run until the
-- screen asks to leave (victory -> "map") or `maxSeconds` of game time pass.
-- `level` (default 1) is every hero's level; heroes carry their starter gear.
-- tier: which battle of the floor this is (1 = first; later ones are harder and
-- bring in the bat and the mushroom).
local function driveEncounter(tag, party, level, tier)
    local scr = require("screens/encounter")
    local sd = fixtureFresh()
    sd.partyOrder = party
    sd.mapProgression = sd.mapProgression or {}
    sd.mapProgression.clearedEncounters = {}
    for i = 1, tier or 1 do sd.mapProgression.clearedEncounters[i] = { i, 1 } end
    local inv0 = #sd.inventory
    local names = {}
    for _, name in ipairs(party) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        local rec = sd.unlockedCharacters[name]
        rec.recruited, rec.level = true, level or 1
        items.equipStarterGear(sd, name)
    end
    local gold0 = sd.gold
    switched = nil
    local xp0 = {}
    for _, name in ipairs(names) do xp0[name] = sd.unlockedCharacters[name].pointsToNextLevel end
    if not guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99, { spawnDelay = 0.5 }) then return end
    local keys = { "q", "w", "e", "r" }
    local maxFrames, frame = 420 * 60, 0
    local seenTypes, shotStage, result = {}, {}, nil
    while frame < maxFrames and not switched do
        frame = frame + 1
        mouseX, mouseY = math.random(300, VW - 40), math.random(120, VH - 60)
        guard(tag .. " update", scr.update, 1 / 60)
        do
            local world, battle = scr.debugState()
            for id in pairs(world.entities) do
                if world.side[id] and world.side[id].s == 1 and world.chaotic[id] then seenTypes.ranged = true end
            end
            -- Victory screens: let each stage show, screenshot it, then click through.
            local v = battle.victory
            if v then
                result = v.result
                local wait = ({ victory = 1.0, spoils = 2.0, xp = 3.5 })[v.stage]
                if v.t >= wait and not shotStage[v.stage] then
                    shotStage[v.stage] = true
                    guard(tag .. " draw", scr.draw)
                    screenshot(tag .. "-3-" .. v.stage)
                    guard(tag .. " mousepressed", scr.mousepressed, 400, 225, 1)
                elseif v.stage == "xp" and shotStage.xp then
                    guard(tag .. " keypressed", scr.keypressed, "return")
                end
                goto nextFrame
            end
        end
        if frame % 30 == 0 then guard(tag .. " draw", scr.draw) end   -- drawing dominates the run time
        if frame % 20 == 0 then
            guard(tag .. " keypressed", scr.keypressed, keys[math.random(#keys)])
        end
        -- Play like a person: once a second pick the next hero (keys 1-4) and
        -- right-click a living enemy so idle heroes get a target. Every 10th
        -- order is a move to open ground instead.
        if frame % 60 == 0 then
            local world, battle = scr.debugState()
            local order = frame / 60
            local slot = order % #names + 1
            guard(tag .. " keypressed", scr.keypressed, tostring(slot))
            local hero = battle.partyIds[slot]
            local tx, ty
            if order % 10 == 0 then
                -- move order to open ground (mouseX/mouseY are already random)
            elseif world.targetSide[hero] == 0 then
                -- a healer: aim at the most injured living hero
                local worst = math.huge
                for i, id in ipairs(battle.partyIds) do
                    local st, pos = world.stats[id], world.position[id]
                    if st and pos and not battle.deadSlots[i] then
                        local ratio = st.HP.base / st.maxHP.base
                        if ratio < worst then worst, tx, ty = ratio, pos.x, pos.y end
                    end
                end
            else
                for id in pairs(world.entities) do
                    local sd, pos = world.side[id], world.position[id]
                    if sd and sd.s == 1 and pos and not world.deathState[id] and pos.x < VW then
                        tx, ty = pos.x, pos.y; break
                    end
                end
            end
            if tx then mouseX, mouseY = tx, ty end
            guard(tag .. " update", scr.update, 1 / 60)   -- refresh hover on the new mouse spot
            guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 2)
            guard(tag .. " mousereleased", scr.mousereleased, mouseX, mouseY, 2)
        end
        if frame % 173 == 0 then
            guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 1)
        end
        if frame == 300 or frame == 330 then   -- pause, then resume
            guard(tag .. " keypressed(space)", scr.keypressed, "space")
        end
        if frame == 200 then screenshot(tag .. "-1-fighting") end
        ::nextFrame::
    end
    screenshot(tag .. "-2-end")
    do  -- how it ended, for the log
        local world, battle = scr.debugState()
        local alive = 0
        for i in ipairs(battle.partyIds) do if not battle.deadSlots[i] then alive = alive + 1 end end
        print(string.format("UI_SMOKE %s: %.0fs, heroes alive %d/%d, kills %d", tag, frame / 60, alive,
            #battle.partyIds, battle.enemyDefeated))
    end
    if scr.onExit then guard(tag .. " onExit", scr.onExit) end
    check(switched ~= nil and switched.name == "map",
          tag .. ": battle is won and returns to the map (" .. string.format("%.0fs", frame / 60) .. ")")
    check(sd.gold > gold0, tag .. ": victory awards gold (" .. gold0 .. "->" .. sd.gold .. ")")
    check(sd.shopState.pendingRestock == true, tag .. ": victory flags the shop restock")
    local leveled = false
    for _, name in ipairs(names) do
        local rec = sd.unlockedCharacters[name]
        if rec.level > (level or 1) or rec.pointsToNextLevel < xp0[name] then leveled = true end
    end
    check(leveled, tag .. ": victory grants XP to survivors")
    check(shotStage.victory and shotStage.spoils and shotStage.xp, tag .. ": the VICTORY, SPOILS and XP screens were all shown")
    check(result ~= nil and result.loot ~= nil and #sd.inventory == inv0 + 1
          and sd.items[sd.inventory[#sd.inventory]] == result.loot,
          tag .. ": victory drops exactly one item into the inventory (" .. tostring(result and result.loot and result.loot.name) .. ")")
    if (tier or 1) >= 2 then check(seenTypes.ranged, tag .. ": a ranged enemy (bat) appeared at tier " .. tier) end
end

-- Combat rules checked on a controlled duel: one knight, one unkillable goblin.
-- The BH wave spawner (encounter/encounter_mgr.lua) and the wave generator.
local function checkSpawner()
    local tag = "spawner"
    local scr = require("screens/encounter")
    local enemies = require("data/enemies")
    local sd = fixtureFresh()
    switched = nil
    local waves = {
        { initialDelay = 1.0, spawnDelay = 0.5, maxEnemies = 2, enemies = { "skeleton", "goblin", "bat" } },
        { initialDelay = 1.0, spawnDelay = 0.1, maxEnemies = 1, enemies = { "mushroom" } },
    }
    if not guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99, { waves = waves }) then return end
    local world, battle = scr.debugState()
    mouseX, mouseY = -100, -100
    local function step(seconds) for _ = 1, math.floor(seconds * 60 + 0.5) do guard(tag .. " update", scr.update, 1 / 60) end end
    local function living()
        local list = {}
        for id in pairs(world.entities) do
            if world.side[id].s == 1 and not world.deathState[id] then list[#list + 1] = id end
        end
        table.sort(list)
        return list
    end
    -- Heroes must not interfere: make them harmless and unkillable.
    for _, id in ipairs(battle.partyIds) do
        world.stats[id].ATK.base, world.stats[id].HP.base, world.stats[id].maxHP.base = 0, 1e9, 1e9
    end
    step(0.9);  check(#living() == 0, tag .. ": nothing spawns before the wave's initialDelay")
    step(0.2);  check(#living() == 1, tag .. ": the first enemy appears after initialDelay")
    step(0.5);  check(#living() == 2, tag .. ": the next follows spawnDelay later")
    step(3.0);  check(#living() == 2, tag .. ": never more than maxEnemies alive at once")
    local first = living()[1]
    world.stats[first].HP.base = 0
    step(0.2)
    check(#living() == 1, tag .. ": the spawn timer was frozen while the field was full (nothing right after a kill)")
    step(0.5)
    local l = living()
    check(#l == 2, tag .. ": the next enemy appears once the rest of spawnDelay has passed")
    local bat = l[#l]
    local bp = world.position[bat]
    check(world.isRanged[bat] and bp.x > 0 and bp.x < VW, tag .. ": the ranged enemy appears inside the arena (x=" .. math.floor(bp.x) .. ")")
    local bx = bp.x
    step(2.0)
    guard(tag .. " draw", scr.draw); screenshot(tag .. "-1-goblin-and-bat")
    check(math.abs(world.position[bat].x - bx) < 1, tag .. ": the ranged enemy stays where it appeared")
    for _, id in ipairs(living()) do world.stats[id].HP.base = 0 end
    step(0.9);  check(#living() == 0, tag .. ": the next wave waits for its own initialDelay")
    step(0.9);  check(#living() == 1, tag .. ": the next wave starts once the last one is dead")
    step(4.0)
    guard(tag .. " draw", scr.draw); screenshot(tag .. "-2-mushroom")
    check(battle.victory == nil and battle.victoryDelay == nil, tag .. ": no victory while a wave is still alive")
    for _, id in ipairs(living()) do world.stats[id].HP.base = 0 end
    step(2.5);  check(battle.victory ~= nil, tag .. ": the battle is won when the last wave is dead")
    if scr.onExit then guard(tag .. " onExit", scr.onExit) end

    -- The generator: BH-shaped waves, only enemies allowed at that tier.
    local gen = require("encounter/wave_gen")
    local ok = true
    for tier = 1, 12 do
        for _ = 1, 20 do
            local w = gen.generate(tier)
            if #w ~= gen.TUNING.waves or #w[1].enemies ~= 1 then ok = false end
            for _, wave in ipairs(w) do
                if #wave.enemies < 1 or wave.maxEnemies < 1 or wave.maxEnemies > gen.TUNING.maxOnField then ok = false end
                for _, id in ipairs(wave.enemies) do
                    local def = enemies.ENEMIES[id]
                    if not def or (def.minTier or 1) > tier then ok = false end
                end
            end
        end
    end
    check(ok, tag .. ": generated battles have " .. gen.TUNING.waves .. " waves, open with one enemy, and respect minTier")
end

local function checkCombatRules()
    local tag = "combat-rules"
    local abilities = require("encounter/abilities")
    local combat    = require("encounter/combat")
    local entities  = require("encounter/entities")
    local scr       = require("screens/encounter")

    -- Costs: whole bars only; BH abilities cost cd // 10 bars; default 3 bars / 15 s.
    local costsOk, bhOk = true, true
    for id, def in pairs(abilities.DB) do
        local cost = abilities.costOf(def, 1)
        if cost % abilities.RESOURCE_PER_BAR ~= 0 then costsOk = false end
        if def.bh and cost ~= math.floor(def.cdMax / 10) * abilities.RESOURCE_PER_BAR then bhOk = false end
    end
    check(costsOk, tag .. ": every ability costs a whole number of bars")
    check(bhOk, tag .. ": every Battleheart ability costs cd // 10 bars")
    local sunder = abilities.make("KnightSunderArmor", 1)
    check(sunder.cdMax == 15 and sunder.resourceCost == 15, tag .. ": default ability is 15 s and 3 bars")
    check(abilities.make("ClericVengefulAngel", 4).resourceCost == 30 and abilities.make("WizardTimeStop", 3).resourceCost == 20,
          tag .. ": 60 s costs 6 bars, 45 s costs 4 bars")

    local sd = fixtureFresh()
    sd.partyOrder = { "knight", false, false, false }
    switched = nil
    -- A huge spawn delay keeps the wave spawner out of the way.
    if not guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99, { spawnDelay = 100000 }) then return end
    local world, battle = scr.debugState()
    local knight = battle.partyIds[1]
    mouseX, mouseY = 60, 300                      -- open ground, away from every unit
    local function step(n) for _ = 1, n do guard(tag .. " update", scr.update, 1 / 60) end end
    step(240)                                     -- walk in
    local kp = world.position[knight]
    local goblin = entities.createEnemy(world, battle, "skeleton", kp.x + 60, kp.y)
    world.stats[goblin].HP.base, world.stats[goblin].maxHP.base = 1e9, 1e9
    world.stats[goblin].ATK.base = 0              -- harmless
    world.stats[knight].MAX_STAGGER.base = 1e9
    world.stats[goblin].MAX_STAGGER.base = 1e9    -- never knocked down by the knight's hits

    local hits = 0
    local realHit = combat.registerHit
    combat.registerHit = function(w, b, src, ...)
        if src == knight then hits = hits + 1 end
        return realHit(w, b, src, ...)
    end
    local function engage()
        world.entityTarget[knight] = { id = goblin }
        local n = 0
        while hits == 0 and n < 600 do step(1); n = n + 1 end
    end
    local function countHits(seconds)
        local h0 = hits; step(seconds * 60); return hits - h0
    end
    local function actionEffect(slot)
        for _, list in ipairs({ world.effects_comp[knight].active, world.effects_comp[knight].pending }) do
            for _, eff in ipairs(list) do
                if eff.isActionEffect and eff.skillSlot == slot then return eff end
            end
        end
    end

    -- 1. Attack interval and attack speed.
    engage()
    local n = countHits(11)
    check(n >= 9 and n <= 11, tag .. ": knight swings every 1.1 s (BH) - " .. n .. " hits in 11 s")
    world.stats[knight].ATK_SPEED.base = 2
    n = countHits(11)
    check(n >= 18 and n <= 21, tag .. ": doubled attack speed halves the interval - " .. n .. " hits in 11 s")
    local frameLen = world.anim[knight].list[3].frameLength
    check(math.abs(frameLen - 7 / 60) < 1e-6, tag .. ": attack speed leaves the swing animation's frame time alone")
    world.stats[knight].ATK_SPEED.base = 1

    -- 2. A move order during an auto-attack wind-up cancels the swing and the hero walks at once.
    local tries = 0
    while not actionEffect(0) and tries < 300 do step(1); tries = tries + 1 end
    local h0, x0 = hits, world.position[knight].x
    guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 2)
    check(actionEffect(0) == nil and world.locks[knight].moveLock == 0,
          tag .. ": move order discards the pending swing and clears the move lock")
    step(12)
    check(math.abs(world.position[knight].x - x0) > 3, tag .. ": the hero is walking within 12 frames of the order")
    check(hits == h0, tag .. ": the cancelled swing deals no damage")
    check(world.skills[knight].list[0].cd == 0, tag .. ": moving resets the auto-attack interval")

    -- 3. A move order during an ability wind-up puts it back at the front of the queue, still paid for.
    local function standNextToGoblin()
        local gp = world.position[goblin]
        world.position[knight].x, world.position[knight].y = gp.x - 45, gp.y
        world.moveTarget[knight].active = false
        world.entityTarget[knight] = { id = goblin }
    end
    standNextToGoblin()
    step(30)
    battle.resource = 50
    guard(tag .. " keypressed", scr.keypressed, "q")
    tries = 0
    while not actionEffect(1) and tries < 300 do step(1); tries = tries + 1 end
    check(actionEffect(1) ~= nil, tag .. ": Q ability starts its wind-up")
    local res0 = battle.resource
    guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 2)
    local sk = world.skills[knight]
    check(actionEffect(1) == nil and sk.abilityQueue[1] == 1, tag .. ": interrupted ability returns to the front of the queue")
    check(sk.list[1].cd > 0 and battle.resource <= res0 + 0.1, tag .. ": it stays paid for (cooldown running, no refund)")
    step(20)
    check(actionEffect(1) == nil, tag .. ": it is held while the hero walks")
    standNextToGoblin()
    tries = 0
    while not actionEffect(1) and tries < 300 do step(1); tries = tries + 1 end
    check(actionEffect(1) ~= nil and #sk.abilityQueue == 0, tag .. ": it winds up again once the hero stands still in range")

    -- 4. Units are never dragged by their target: a stunned enemy stays put when the hero it
    --    was fighting walks away, and a free one follows at its own speed, not the hero's.
    local function duelThenWalkAway()
        standNextToGoblin()
        world.entityTarget[goblin] = { id = knight }
        step(240)                                  -- both settle into the duel
        local gx, gy, kx = world.position[goblin].x, world.position[goblin].y, world.position[knight].x
        mouseX = (kx > VW / 2) and 60 or (VW - 60)   -- order the hero to the far side of the arena
        return gx, gy, kx
    end
    local gx, gy, kx = duelThenWalkAway()
    combat.applyStun(world, goblin, 20 * 60)
    guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 2)
    step(90)
    local gp = world.position[goblin]
    check(math.abs(world.position[knight].x - kx) > 40, tag .. ": the hero walked away from the duel")
    check(math.abs(gp.x - gx) < 2 and math.abs(gp.y - gy) < 2,
          tag .. ": a stunned enemy is not dragged along (moved " .. string.format("%.1f", math.abs(gp.x - gx)) .. " px)")
    world.stun[goblin].stunned, world.stun[goblin].timer = false, 0
    world.locks[goblin].actionLock = 0
    gx, gy, kx = duelThenWalkAway()
    guard(tag .. " mousepressed", scr.mousepressed, mouseX, mouseY, 2)
    step(60)
    gp = world.position[goblin]
    local moved = math.sqrt((gp.x - gx) ^ 2 + (gp.y - gy) ^ 2)
    local ownSpeed = world.stats[goblin].MOVE_SPEED.base * 30   -- px per second
    check(moved <= ownSpeed + 6, tag .. ": a following enemy moves at its own speed (" ..
          string.format("%.0f px in 1 s, limit %.0f", moved, ownSpeed) .. ")")

    step(180)
    local later = math.sqrt((world.position[goblin].x - gx) ^ 2 + (world.position[goblin].y - gy) ^ 2)
    local mtg, lkg = world.moveTarget[goblin], world.locks[goblin]
    check(later > 30, tag .. ": the enemy does chase the hero it is fighting (" ..
          string.format("%.0f px after 4 s; mt.active=%s actionLock=%.1f stunned=%s", later,
              tostring(mtg.active), lkg.actionLock, tostring(world.stun[goblin].stunned)) .. ")")

    -- 5. Every hero walks at the same speed.
    local same = true
    for _, cls in ipairs({ "knight", "cleric", "wizard", "rogue", "paladin", "champion", "duelist", "nomad", "brigand" }) do
        local id = entities.createHero(world, battle, cls, -500, 200)
        if world.stats[id].MOVE_SPEED.base ~= require("data/classes").HERO_MOVE_SPEED then same = false end
        world:destroy(id)
    end
    check(same, tag .. ": every class has the same move speed")

    combat.registerHit = realHit
    if scr.onExit then guard(tag .. " onExit", scr.onExit) end
end

local function runAll()
    -- EQUIP
    local sd = fixtureRich()
    drive("equip-rich", "equip", sd, { hover = { {350, 130}, {60, 290}, {750, 400}, {130, 90} } })
    invariants("equip-rich", sd)
    check(countEquipped(sd) > 0, "equip-rich: fuzz equipped at least one item (" .. countEquipped(sd) .. " equipped)")
    drive("equip-fresh", "equip", fixtureFresh())

    -- SHOP
    sd = fixtureRich()
    local gold0, inv0 = sd.gold, #sd.inventory
    local exits = drive("shop-rich", "shop", sd, { hover = { {66, 150}, {350, 130}, {150, 80} } })
    invariants("shop-rich", sd)
    check(sd.shopState.seeded == true and sd.shopState.pendingRestock ~= true, "shop-rich: shop stocked on entry")
    check(sd.gold ~= gold0 or #sd.inventory ~= inv0, "shop-rich: fuzz bought or sold something (gold "
          .. gold0 .. "->" .. sd.gold .. ", inventory " .. inv0 .. "->" .. #sd.inventory .. ")")
    check((exits.map or 0) > 0, "shop-rich: back/escape returns to map")
    sd = fixtureFresh()
    drive("shop-fresh", "shop", sd)
    invariants("shop-fresh", sd)
    check(sd.gold >= 0 and sd.gold <= 15 + 100, "shop-fresh: a new game's 15 gold never goes negative")

    -- TALENTS
    sd = fixtureRich()
    local wiz0   = progression.heroStats(sd, "wizard")
    local champ0 = progression.heroStats(sd, "champion")
    exits = drive("talents-rich", "talents", sd, { fuzz = 20000, hover = { {290, 230}, {510, 230}, {400, 160}, {430, 70} } })
    invariants("talents-rich", sd)
    local uc = sd.unlockedCharacters
    check(countPicks(uc.knight) == 3, "talents-rich: Lv9 knight picked exactly 3 branches (got " .. countPicks(uc.knight) .. ")")
    check(countPicks(uc.cleric) == 1, "talents-rich: Lv4 cleric picked exactly 1 branch (got " .. countPicks(uc.cleric) .. ")")
    check(countPicks(uc.wizard) == 0, "talents-rich: Lv1 wizard picked nothing (got " .. countPicks(uc.wizard) .. ")")
    local kn9 = progression.heroStats(sd, "knight")
    local knBare = progression.heroStats(fixtureRich(), "knight")
    check(kn9.ATK + kn9.DEF + kn9.maxHP > knBare.ATK + knBare.DEF + knBare.maxHP,
          "talents-rich: the knight's picks raise its stats")
    check(progression.heroStats(sd, "wizard").ATK == wiz0.ATK and progression.heroStats(sd, "champion").ATK == champ0.ATK,
          "talents-rich: picks do not leak into other heroes' stats")
    check((exits.map or 0) > 0, "talents-rich: back/escape returns to map")
    drive("talents-fresh", "talents", fixtureFresh())
    sd = fixtureRich()
    sd.partyOrder = { "rogue", false, false, false }
    drive("talents-rogue", "talents", sd, { fuzz = 0, scrollSweep = 40 })
    check(countPicks(sd.unlockedCharacters.rogue) == 7,
          "talents-rogue: Lv21 rogue can reach all 7 branches by scrolling (got " .. countPicks(sd.unlockedCharacters.rogue) .. ")")

    -- PROGRESSION (XP grant that feeds the talent ladder)
    sd = fixtureFresh()
    local kn = sd.unlockedCharacters.knight
    local bhCurve = { 30, 40, 54, 72, 97, 129, 167, 213, 266, 327 }
    local curveOk = true
    for lv, want in ipairs(bhCurve) do
        if progression.xpToNext(lv) ~= want then curveOk = false end
    end
    check(curveOk, "progression: XP curve matches Battleheart's for levels 1-10")
    check(progression.addXP(kn, 29) == 0 and kn.level == 1 and kn.pointsToNextLevel == 1,
          "progression: 29 XP leaves a fresh hero 1 short of Lv2")
    check(progression.addXP(kn, 1) == 1 and kn.level == 2 and kn.pointsToNextLevel == 40,
          "progression: the 30th XP levels up and resets the counter")
    check(progression.addXP(kn, 10000000) == progression.MAX_LEVEL - 2 and kn.level == progression.MAX_LEVEL,
          "progression: a huge grant multi-levels and stops at MAX_LEVEL")
    sd = fixtureFresh()
    local r = progression.onEncounterWon(sd, { "knight" }, 3)
    check(sd.unlockedCharacters.knight.level > 1 and sd.unlockedCharacters.cleric.level == 1,
          "progression: only survivors get the win's XP")
    check(r.xp[1].gained == 175, "progression: a lone survivor gets 35 x 4 x 1.25 = 175 XP (got " .. r.xp[1].gained .. ")")
    check(sd.gold == 15 + r.gold and r.gold >= 23 and r.gold <= 31,
          "progression: the first battle pays BH's 27 gold +/-15% (got " .. r.gold .. ")")
    check(r.loot ~= nil and #sd.inventory == 1 and sd.items[sd.inventory[1]] == r.loot,
          "progression: a win drops exactly one item (" .. tostring(r.loot and r.loot.name) .. ")")
    sd = fixtureFresh()
    r = progression.onEncounterWon(sd, { "knight", "cleric" }, 3, { knight = 10, cleric = 50 })
    check(r.xp[1].gained == 81 and r.xp[2].gained == 88,
          "progression: 2 survivors get 35 x 2, the best scorer +25%, the other +16% (knight " ..
          r.xp[1].gained .. ", cleric " .. r.xp[2].gained .. ")")
    sd = fixtureFresh()
    for i = 1, items.INVENTORY_SIZE do sd.inventory[i] = items.mint(sd, 0) end
    r = progression.onEncounterWon(sd, { "knight" }, 3)
    check(r.loot == nil and r.lootLost and #sd.inventory == items.INVENTORY_SIZE,
          "progression: with a full inventory the dropped item is lost (BH rule)")
    for level = 1, 30 do
        local offers = items.rollOffers(level)
        if #offers < 3 or #offers > items.SHOP_SLOTS then
            check(false, "shop stock: 3.." .. items.SHOP_SLOTS .. " items at level " .. level .. " (got " .. #offers .. ")")
        end
    end
    check(true, "shop stock: 3.." .. items.SHOP_SLOTS .. " items at every hero level")
    sd = fixtureFresh()
    local st = progression.heroStats(sd, "knight")
    check(st.maxHP == 1000 and st.ATK == 20 + 15 and st.DEF == 15 + 20,
          "progression: Lv1 knight = BH base + Iron Sword + Scale Mail (HP " .. st.maxHP .. " ATK " .. st.ATK .. " DEF " .. st.DEF .. ")")
    sd.unlockedCharacters.knight.level = 11
    sd.unlockedCharacters.knight.skillTree = { "guard" }
    st = progression.heroStats(sd, "knight")
    check(st.maxHP == 1150 and st.ATK == 45 and st.DEF == 15 + 12 + 20 + 6,
          "progression: levels, gear and talent picks all add up (HP " .. st.maxHP .. " ATK " .. st.ATK .. " DEF " .. st.DEF .. ")")
    sd = fixtureFresh()
    sd.gold = 100
    local hireName = progression.rollHire(sd)
    progression.recruit(sd, hireName)
    check(sd.unlockedCharacters[hireName].recruited and sd.unlockedCharacters[hireName].equipped.weapon ~= nil,
          "progression: a recruit joins with starter gear (" .. tostring(hireName) .. ")")

    checkCombatRules()
    checkSpawner()

    -- ENCOUNTER (full battles through to the victory branch). These take minutes;
    -- `./test_ui quick` (CR_UI_QUICK=1) skips them for UI-only work.
    if os.getenv("CR_UI_QUICK") ~= "1" then
        driveEncounter("battle-new-game", { "knight", "cleric", false, false })       -- the fresh-save party, level 1
        driveEncounter("battle-bh-classes", { "paladin", "cleric", "wizard", "rogue" }, 4, 3)
        driveEncounter("battle-cr-classes", { "knight", "champion", "duelist", "nomad" }, 3, 2)
    end

    -- PARTY
    sd = fixtureRich()
    drive("party-rich", "party_select", sd, { hover = { {360, 115}, {240, 250} } })
    invariants("party-rich", sd)
    drive("party-fresh", "party_select", fixtureFresh())

    -- MAP (top bar + shop popup + movement keys)
    sd = fixtureRich()
    exits = drive("map-rich", "map", sd)
    invariants("map-rich", sd)
    local seenExits = {}
    for name, n in pairs(exits) do seenExits[#seenExits + 1] = name .. "x" .. n end
    table.sort(seenExits)
    print("UI_SMOKE map exits: " .. table.concat(seenExits, " "))
    check((exits.party_select or 0) > 0, "map-rich: top bar reaches PARTY")
    check((exits.talents or 0) > 0, "map-rich: top bar reaches TALENTS")
    check((exits.equip or 0) > 0, "map-rich: top bar reaches EQUIP")
    drive("map-fresh", "map", fixtureFresh())
    local first, second = mapShopWalk(fixtureFresh())
    check(first == "shop", "map-shop: walking onto the S tile and clicking ENTER opens the SHOP (got " .. tostring(first) .. ")")
    check(second == "shop", "map-shop: the SHOP can be re-entered after returning to the map (got " .. tostring(second) .. ")")
end

-- ============================================================================
-- PUBLIC ENTRY (called by main.lua when CR_TEST_SCENE=ui)
-- ============================================================================
local ran = false

function M.load()
    math.randomseed(12345)
    installStubs()
    print(string.format("UI_SMOKE start: window=%s graphics=%s", tostring(love.window.isOpen()),
        tostring(love.graphics.isActive())))
    canvas = common.newSceneCanvas()
    postfx = common.newPostFX(moonshine)
end

function M.update(dt)
    if ran then return end
    ran = true
    local ok, err = xpcall(runAll, debug.traceback)
    if not ok then recordError("driver", err) end

    local failed = 0
    for _, c in ipairs(checks) do
        if not c.ok then failed = failed + 1 end
        print((c.ok and "  ok   " or "  FAIL ") .. c.label)
    end
    for _, e in ipairs(errors) do
        print(string.format("UI_SMOKE ERROR x%d %s", errorCount[e.head], e.head))
        print(e.full)
    end
    print("UI_SMOKE screenshots: " .. love.filesystem.getSaveDirectory() .. "/ui_smoke/")
    if #errors == 0 and failed == 0 then
        print(string.format("UI_SMOKE_PASS errors=0 checks=%d saveWritesStubbed=%d", #checks, saveWrites))
    else
        print(string.format("UI_SMOKE_FAIL errors=%d failedChecks=%d/%d", #errors, failed, #checks))
    end
    love.event.quit((#errors == 0 and failed == 0) and 0 or 1)
end

return M

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
    sd.unlockedCharacters.knight.level = 9
    sd.unlockedCharacters.cleric.level = 4
    sd.unlockedCharacters.wizard.level = 1
    sd.unlockedCharacters.rogue.level  = 21
    for _, spec in ipairs({ {"weapon",1}, {"weapon",3}, {"armor",1}, {"armor",2}, {"trinket",2}, {"trinket",3} }) do
        local id = items.nextId(sd)
        sd.items[id] = items.makeInstance(id, spec[1], spec[2])
        table.insert(sd.inventory, id)
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
-- Party stats are inflated so the fight is winnable and reaches the victory
-- branch (gold / XP / shop-restock latch).
local function driveEncounter(tag, party)
    local scr = require("screens/encounter")
    local sd = fixtureFresh()
    sd.partyOrder = party
    local names = {}
    for _, name in ipairs(party) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        local st = sd.unlockedCharacters[name].stats
        st.maxHP, st.ATK, st.DEF = 4000, 60, 20
    end
    local gold0 = sd.gold
    switched = nil
    local cfg = { encounterGoal = 9, spawnDelay = 0.5 }
    if not guard(tag .. " onEnter", scr.onEnter, canvas, postfx, switchFn, sd, 99, cfg) then return end
    local keys = { "q", "w", "e", "r" }
    local maxFrames, frame = 180 * 60, 0
    while frame < maxFrames and not switched do
        frame = frame + 1
        mouseX, mouseY = math.random(300, VW - 40), math.random(120, VH - 60)
        guard(tag .. " update", scr.update, 1 / 60)
        if frame % 6 == 0 then guard(tag .. " draw", scr.draw) end
        if frame % 20 == 0 then
            guard(tag .. " keypressed", scr.keypressed, keys[math.random(#keys)])
        end
        -- Play like a person: once a second pick the next hero (keys 1-4) and
        -- right-click a living enemy so idle heroes get a target. Every 10th
        -- order is a move to open ground instead.
        if frame % 60 == 0 then
            local world = scr.debugState()
            local order = frame / 60
            guard(tag .. " keypressed", scr.keypressed, tostring(order % 4 + 1))
            local tx, ty
            if order % 10 ~= 0 then
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
    end
    screenshot(tag .. "-2-end")
    if scr.onExit then guard(tag .. " onExit", scr.onExit) end
    check(switched ~= nil and switched.name == "map",
          tag .. ": battle is won and returns to the map (" .. string.format("%.0fs", frame / 60) .. ")")
    check(sd.gold > gold0, tag .. ": victory awards gold (" .. gold0 .. "->" .. sd.gold .. ")")
    check(sd.shopState.pendingRestock == true, tag .. ": victory flags the shop restock")
    local leveled = false
    for _, name in ipairs(names) do
        local rec = sd.unlockedCharacters[name]
        if rec.level > 1 or rec.pointsToNextLevel < 50 then leveled = true end
    end
    check(leveled, tag .. ": victory grants XP to survivors")
end

local function runAll()
    -- EQUIP
    local sd = fixtureRich()
    drive("equip-rich", "equip", sd)
    invariants("equip-rich", sd)
    check(countEquipped(sd) > 0, "equip-rich: fuzz equipped at least one item (" .. countEquipped(sd) .. " equipped)")
    drive("equip-fresh", "equip", fixtureFresh())

    -- SHOP
    sd = fixtureRich()
    local gold0, inv0 = sd.gold, #sd.inventory
    local exits = drive("shop-rich", "shop", sd)
    invariants("shop-rich", sd)
    check(sd.shopState.seeded == true and sd.shopState.pendingRestock ~= true, "shop-rich: shop stocked on entry")
    check(sd.gold ~= gold0 or #sd.inventory ~= inv0, "shop-rich: fuzz bought or sold something (gold "
          .. gold0 .. "->" .. sd.gold .. ", inventory " .. inv0 .. "->" .. #sd.inventory .. ")")
    check((exits.map or 0) > 0, "shop-rich: back/escape returns to map")
    sd = fixtureFresh()
    drive("shop-fresh", "shop", sd)
    invariants("shop-fresh", sd)
    check(sd.gold == 0, "shop-fresh: nothing can be bought with 0 gold")

    -- TALENTS
    sd = fixtureRich()
    local atk0 = sd.unlockedCharacters.knight.stats.ATK
    local wizAtk0 = sd.unlockedCharacters.wizard.stats.ATK
    exits = drive("talents-rich", "talents", sd, { fuzz = 20000 })
    invariants("talents-rich", sd)
    local uc = sd.unlockedCharacters
    check(countPicks(uc.knight) == 3, "talents-rich: Lv9 knight picked exactly 3 branches (got " .. countPicks(uc.knight) .. ")")
    check(countPicks(uc.cleric) == 1, "talents-rich: Lv4 cleric picked exactly 1 branch (got " .. countPicks(uc.cleric) .. ")")
    check(countPicks(uc.wizard) == 0, "talents-rich: Lv1 wizard picked nothing (got " .. countPicks(uc.wizard) .. ")")
    check(uc.wizard.stats.ATK == wizAtk0, "talents-rich: another character's picks did not leak into wizard stats")
    check(uc.champion.stats.ATK == atk0, "talents-rich: picks did not leak into a benched character's stats")
    check((exits.map or 0) > 0, "talents-rich: back/escape returns to map")
    drive("talents-fresh", "talents", fixtureFresh())
    sd = fixtureRich()
    sd.partyOrder = { "rogue", false, false, false }
    drive("talents-rogue", "talents", sd, { fuzz = 0, scrollSweep = 40 })
    check(countPicks(sd.unlockedCharacters.rogue) == 7,
          "talents-rogue: Lv21 rogue can reach all 7 branches by scrolling (got " .. countPicks(sd.unlockedCharacters.rogue) .. ")")

    -- PROGRESSION (XP grant that feeds the talent ladder)
    local progression = require("progression")
    sd = fixtureFresh()
    local kn = sd.unlockedCharacters.knight
    check(progression.addXP(kn, 49) == 0 and kn.level == 1 and kn.pointsToNextLevel == 1,
          "progression: 49 XP leaves a fresh character 1 short of Lv2")
    check(progression.addXP(kn, 1) == 1 and kn.level == 2 and kn.pointsToNextLevel == progression.xpToNext(2),
          "progression: the 50th XP levels up and resets the counter")
    check(progression.addXP(kn, 100000) == progression.MAX_LEVEL - 2 and kn.level == progression.MAX_LEVEL,
          "progression: a huge grant multi-levels and stops at MAX_LEVEL")
    sd = fixtureFresh()
    sd.partyOrder = { "knight", "cleric", false, false }
    progression.onEncounterWon(sd, { "knight" })
    check(sd.unlockedCharacters.knight.level == 2 and sd.unlockedCharacters.cleric.level == 1,
          "progression: only survivors get the win's XP")

    -- ENCOUNTER (full battles through to the victory branch)
    driveEncounter("battle-knight-solo", { "knight", false, false, false })
    driveEncounter("battle-bh-classes", { "paladin", "cleric", "wizard", "rogue" })
    driveEncounter("battle-cr-classes", { "knight", "champion", "duelist", "nomad" })

    -- PARTY
    sd = fixtureRich()
    drive("party-rich", "party_select", sd)
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

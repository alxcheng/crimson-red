-- ============================================================================
-- Crimson Red — Main Game Entry Point
-- Screen manager: delegates love callbacks to the active screen module.
-- ============================================================================

local common    = require("common")
local moonshine = require("moonshine")
local music_mgr = require("music_mgr")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- ENV FLAG CONVENTION (set by the agent background test harness)
--   CR_HEADLESS  = "1"  -> run offscreen (no window); used by ./test_headless
--   CR_TEST_MODE = "1"  -> additionally skip music + guard the fade render
--   CR_TEST_SCENE = "headless" -> run the headless encounter smoke test
-- When none of these are set, every visible default below is byte-identical
-- to the original game: normal window, newSceneCanvas + newPostFX, doSwitch
-- ("title"), normal draw, normal music.
-- ============================================================================
local function headless_on()  return os.getenv("CR_HEADLESS") == "1" end
local function test_mode_on() return os.getenv("CR_TEST_MODE") == "1" or headless_on() end

local skipMusic = test_mode_on()   -- fixed at load; gates music_mgr.update (B3)

-- Screen modules (loaded once; state reset per onEnter call)
local screens = {
    title        = require("screens/title"),
    save_select  = require("screens/save_select"),
    map          = require("screens/map"),
    encounter    = require("screens/encounter"),
    party_select = require("screens/party_select"),
    equip        = require("screens/equip"),
    talents      = require("screens/talents"),
    shop         = require("screens/shop"),
    sprite_dev   = require("screens/sprite_dev"),
}

local canvas, postfx
local current = "title"

-- Fade transition state
local trans = {
    phase   = nil,   -- nil | "fade_out" | "fade_in"
    timer   = 0,
    HALF    = 0.25,  -- seconds per half-transition
    pending = nil,   -- { name=, args= } for the deferred switch
}

local switchTo  -- forward-declared so screens can capture it in their closure

local function doSwitch(name, ...)
    if screens[current].onExit then screens[current].onExit() end
    current = name
    screens[name].onEnter(canvas, postfx, switchTo, ...)
end

switchTo = function(name, ...)
    if trans.phase then return end  -- ignore calls mid-transition
    trans.phase   = "fade_out"
    trans.timer   = 0
    trans.pending = { name = name, args = {...} }
end

-- ============================================================================
-- LOVE CALLBACKS
-- ============================================================================

function love.load()
    love.window.setTitle("Crimson Red")

    -- CR_TEST_SCENE=headless: run the standalone encounter smoke test instead
    -- of the normal app (see main-game/headless_test.lua). No window is drawn.
    if os.getenv("CR_TEST_SCENE") == "headless" then
        require("headless_test").load()
        return
    end
    -- CR_TEST_SCENE=ui: drive the UI screens with synthetic input instead of
    -- the normal app (see main-game/ui_smoke_test.lua, invoked by ./test_ui).
    if os.getenv("CR_TEST_SCENE") == "ui" then
        require("ui_smoke_test").load()
        return
    end

    if headless_on() then
        -- Offscreen: no default framebuffer exists, so common.newPostFX
        -- (moonshine chain sized to the framebuffer) cannot be built. Set the
        -- canvas, leave postfx = nil, and never draw (see love.draw). The
        -- screen update pipeline still runs — that's the point.
        love.window.setMode(VW, VH, {offscreen=true})
        math.randomseed(os.time())
        canvas = common.newSceneCanvas()
        postfx = nil
        doSwitch("title")
    else
        -- VISIBLE DEFAULT — unchanged from before this feature.
        love.window.setMode(VW, VH, {resizable=true, minwidth=400, minheight=225})
        math.randomseed(os.time())

        canvas = common.newSceneCanvas()
        postfx = common.newPostFX(moonshine)

        doSwitch("title")
    end
end

function love.update(dt)
    -- CR_TEST_SCENE=headless owns the whole frame; skip normal app logic.
    if os.getenv("CR_TEST_SCENE") == "headless" then
        require("headless_test").update(dt)
        return
    end
    if os.getenv("CR_TEST_SCENE") == "ui" then
        require("ui_smoke_test").update(dt)
        return
    end

    if skipMusic then
        -- Test mode: skip music (offscreen has a dummy/silent audio device
        -- anyway; this keeps the test deterministic and quiet).
    else
        music_mgr.update(dt)
    end
    screens[current].update(dt)

    if trans.phase then
        trans.timer = trans.timer + dt
        if trans.timer >= trans.HALF then
            trans.timer = trans.timer - trans.HALF
            if trans.phase == "fade_out" then
                doSwitch(trans.pending.name, unpack(trans.pending.args))
                trans.phase = "fade_in"
            else
                trans.phase   = nil
                trans.timer   = 0
                trans.pending = nil
            end
        end
    end
end

function love.draw()
    -- Headless: never render. The screen UPDATE pipeline still runs (that's
    -- the whole point); only the draw is skipped. This also keeps the fade
    -- block (which calls love.graphics.getDimensions(), 0x0 offscreen)
    -- unreachable offscreen.
    if headless_on() and test_mode_on() then return end
    if os.getenv("CR_TEST_SCENE") == "ui" then return end

    screens[current].draw()

    if trans.phase then
        local alpha
        if trans.phase == "fade_out" then
            alpha = trans.timer / trans.HALF
        else
            alpha = 1 - trans.timer / trans.HALF
        end
        local ww, wh = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, ww, wh)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function love.keypressed(key)
    if trans.phase then return end
    local s = screens[current]
    if s.keypressed then s.keypressed(key) end
end

function love.mousepressed(x, y, button)
    if trans.phase then return end
    if button == 1 and love.keyboard.isDown('lctrl', 'rctrl') then button = 2 end
    local s = screens[current]
    if s.mousepressed then s.mousepressed(x, y, button) end
end

function love.mousereleased(x, y, button)
    if trans.phase then return end
    if button == 1 and love.keyboard.isDown('lctrl', 'rctrl') then button = 2 end
    local s = screens[current]
    if s.mousereleased then s.mousereleased(x, y, button) end
end

function love.wheelmoved(x, y)
    if trans.phase then return end
    local s = screens[current]
    -- Screens take "positive = scroll down"; LÖVE reports wheel-up as positive.
    if s.wheel then s.wheel(-y) end
end

function love.resize(w, h)
    -- Headless runs without postfx (and with a dummy/no window); the fade and
    -- render are skipped, so nothing needs a resize here. Visible default is
    -- unchanged (postfx is non-nil and resizes exactly as before).
    if postfx then postfx.resize(w, h) end
end

-- ============================================================================
-- Crimson Red — Main Game Entry Point
-- Screen manager: delegates love callbacks to the active screen module.
-- ============================================================================

local common    = require("common")
local moonshine = require("moonshine")
local music_mgr = require("music_mgr")

local VW = common.VW
local VH = common.VH

-- Screen modules (loaded once; state reset per onEnter call)
local screens = {
    title        = require("screens/title"),
    save_select  = require("screens/save_select"),
    map          = require("screens/map"),
    encounter    = require("screens/encounter"),
    party_select = require("screens/party_select"),
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
    love.window.setMode(VW, VH, {resizable=true, minwidth=400, minheight=225})
    math.randomseed(os.time())

    canvas = common.newSceneCanvas()
    postfx = common.newPostFX(moonshine)

    doSwitch("title")
end

function love.update(dt)
    music_mgr.update(dt)
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

function love.resize(w, h)
    postfx.resize(w, h)
end

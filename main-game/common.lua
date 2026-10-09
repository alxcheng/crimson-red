-- common.lua — shared helpers for every screen: virtual resolution, the
-- post-processing chain, letterboxing, the animated selection box, fonts,
-- hit-testing, the back arrow and UI sounds.
--
-- All drawing happens on an 800x450 canvas (M.VW x M.VH) that is scaled to the
-- window with letterboxing; M.virtualMouse() converts the mouse to that space.

local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

M.VW = 800
M.VH = 450

M.COLOR_RED   = {1, 0, 0, 1}
M.COLOR_WHITE = {1, 1, 1, 1}
M.COLOR_BLACK = {0, 0, 0, 1}

-- ============================================================================
-- MOONSHINE SETUP
-- ============================================================================
-- Both chromatic aberration and bloom are handled by Moonshine.
-- main.lua builds one chain with M.newPostFX(moonshine) and passes it to screens.
--
-- Pipeline:
--   1. Draw scene into canvas (nearest, VW×VH)
--   2. In love.draw: setCanvas(nil), then postfx(function()
--          love.graphics.draw(canvas, ox, oy, 0, scale, scale)
--      end)  ← draw scaled into moonshine's window-sized buffers
--   3. Call postfx.resize(w, h) in love.resize so moonshine buffers stay window-sized.
--      vw/vh stay at VW/VH so blur steps are in virtual-pixel units at any window size.

M.CHROMA_RADIUS  = 1.0   -- chromatic aberration pixel offset
M.BLOOM_MIN_LUMA = 0.25  -- pixels brighter than this glow (pure red luma ≈ 0.21)
M.BLOOM_STRENGTH = 2     -- glow spread (sigma); glow.lua only has strength + min_luma

function M.newPostFX(moonshine)
    -- Use .chain() not :chain() — colon passes self as the effect arg.
    -- vw/vh = VW/VH so blur/shift offsets are virtual-pixel-based at any window size.
    -- Moonshine buffers start at window size and resize with love.resize → postfx.resize.
    local fx = moonshine(moonshine.effects.chromasep).chain(moonshine.effects.glow)
    fx.chromasep.angle  = 0
    fx.chromasep.radius = M.CHROMA_RADIUS
    fx.chromasep.vw     = M.VW
    fx.chromasep.vh     = M.VH
    fx.glow.min_luma    = M.BLOOM_MIN_LUMA
    fx.glow.strength    = M.BLOOM_STRENGTH
    fx.glow.vw          = M.VW
    fx.glow.vh          = M.VH
    return fx
end

-- ============================================================================
-- CANVAS HELPERS
-- ============================================================================

-- Scene canvas: nearest filter keeps pixels crisp at native res.
function M.newSceneCanvas()
    local c = love.graphics.newCanvas(M.VW, M.VH)
    c:setFilter("nearest", "nearest")
    return c
end

-- ============================================================================
-- WINDOW / MOUSE HELPERS
-- ============================================================================

-- Maps real window mouse position to virtual 800x450 canvas coordinates
function M.virtualMouse()
    local mx, my = love.mouse.getPosition()
    local sw, sh = love.graphics.getDimensions()
    local s  = math.min(sw / M.VW, sh / M.VH)
    local ox = (sw - M.VW * s) / 2
    local oy = (sh - M.VH * s) / 2
    return (mx - ox) / s, (my - oy) / s
end

-- Returns ox, oy, scale for letterboxing the virtual canvas to the window
function M.letterbox()
    local sw, sh = love.graphics.getDimensions()
    local s  = math.min(sw / M.VW, sh / M.VH)
    return (sw - M.VW * s) / 2, (sh - M.VH * s) / 2, s
end

-- ============================================================================
-- BOX ANIMATION SYSTEM
-- ============================================================================
-- A persistent animated red outline box that glides between interactive items.
-- Once shown it never hides; when the mouse leaves it freezes at last position.

M.BOX_SPEED = 14  -- exponential lerp speed (higher = snappier)

local function lerp(a, b, t) return a + (b - a) * t end

-- Create a new box state table
function M.newBox()
    return {
        x = 0, y = 0, w = 0, h = 0,   -- current animated position
        tx = 0, ty = 0, tw = 0, th = 0, -- target position
        shown = false,
    }
end

-- Snap box to a position immediately and mark as shown
-- Call this on startup to set the initial position without animation
function M.initBox(box, x, y, w, h)
    box.x,  box.y,  box.w,  box.h  = x, y, w, h
    box.tx, box.ty, box.tw, box.th = x, y, w, h
    box.shown = true
end

-- Update the box target (called when a new item is hovered)
-- The box will animate toward the new target on the next updateBox call
function M.setBoxTarget(box, x, y, w, h, silent)
    if box.shown and box.tx == x and box.ty == y and box.tw == w and box.th == h then
        return
    end
    box.tx, box.ty, box.tw, box.th = x, y, w, h
    if not box.shown then
        -- Snap on first ever hover so it doesn't fly in from (0,0)
        box.x, box.y, box.w, box.h = x, y, w, h
        box.shown = true
    elseif not silent then
        M.playHoverSound()
    end
end

-- Advance the box animation. Call every frame regardless of hover state
-- so the box keeps gliding even after the mouse leaves an item.
function M.updateBox(box, dt)
    if not box.shown then return end
    local t = 1 - math.exp(-M.BOX_SPEED * dt)
    box.x = lerp(box.x, box.tx, t)
    box.y = lerp(box.y, box.ty, t)
    box.w = lerp(box.w, box.tw, t)
    box.h = lerp(box.h, box.th, t)
end

-- Draw the box: red outline normally, white fill when an item is pressed
function M.drawBox(box, pressed)
    if not box.shown then return end
    if pressed then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", box.x, box.y, box.w, box.h)
    else
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", box.x, box.y, box.w, box.h)
    end
end

-- ============================================================================
-- FONT HELPER
-- ============================================================================

-- Load the Dedicool font at the given size.
function M.loadFont(size)
    local ok, f = pcall(love.graphics.newFont, "assets/dedicool/Dedicool.ttf", size)
    if not ok then print("[common] Font load error:", f) end
    return ok and f or love.graphics.newFont(size)
end

-- ============================================================================
-- RENDER FRAME
-- ============================================================================
-- Full love.draw() pipeline: render drawSceneFn into canvas at virtual
-- resolution, then blit to screen with letterbox + post-processing.

function M.renderFrame(canvas, postfx, drawSceneFn)
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    drawSceneFn()
    love.graphics.setCanvas()

    local ox, oy, scale = M.letterbox()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    postfx(function()
        love.graphics.draw(canvas, ox, oy, 0, scale, scale)
    end)
end

-- ============================================================================
-- HIT TEST
-- ============================================================================
-- Generic hover detection: iterates 1..count, calls getRectFn(i) for each
-- item, tests virtual-mouse against the rect. Returns hovered index or nil.

function M.hitTest(count, getRectFn)
    local vmx, vmy = M.virtualMouse()
    for i = 1, count do
        local bx, by, bw, bh = getRectFn(i)
        if vmx >= bx and vmx <= bx + bw and vmy >= by and vmy <= by + bh then
            return i
        end
    end
    return nil
end

-- ============================================================================
-- ITEM COLOR HELPER
-- ============================================================================
-- Sets love.graphics color for interactive item text/icons:
-- pressed → black (text inverts over white fill), otherwise → white.

function M.setItemColor(isPressed)
    if isPressed then
        love.graphics.setColor(0, 0, 0, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- ============================================================================
-- BACK ARROW
-- ============================================================================
-- Shared back-arrow geometry used by save_select, party_select, map top-bar.
-- Draws a left-pointing arrow at a fixed top-left position.

M.ARROW_X       = 18
M.ARROW_Y       = 14
M.ARROW_H       = 20
M.ARROW_HEAD_W  = 12
M.ARROW_SHAFT_H = 8
M.ARROW_SHAFT_W = 16
M.ARROW_W       = M.ARROW_HEAD_W + M.ARROW_SHAFT_W

-- ============================================================================
-- HOVER SOUND
-- ============================================================================

local _hoverSnd = nil
local _clickSnd = nil

function M.playHoverSound()
    if not _hoverSnd then
        local ok, s = pcall(love.audio.newSource, "assets/sounds/UI/Menu Selection Click.wav", "static")
        if ok then _hoverSnd = s; _hoverSnd:setVolume(1.0) end
    end
    if _hoverSnd then _hoverSnd:stop(); _hoverSnd:play() end
end

function M.playClickSound()
    if not _clickSnd then
        local ok, s = pcall(love.audio.newSource, "assets/sounds/UI/ps5-selection-button.mp3", "static")
        if ok then _clickSnd = s; _clickSnd:setVolume(1.0) end
    end
    if _clickSnd then _clickSnd:stop(); _clickSnd:play() end
end

function M.drawBackArrow(isPressed)
    local ax, ay, ah = M.ARROW_X, M.ARROW_Y, M.ARROW_H
    local hw = M.ARROW_HEAD_W
    local sh, sw = M.ARROW_SHAFT_H, M.ARROW_SHAFT_W
    love.graphics.setColor(isPressed and M.COLOR_BLACK or M.COLOR_RED)
    love.graphics.polygon("fill", ax, ay + ah/2, ax + hw, ay, ax + hw, ay + ah)
    love.graphics.rectangle("fill", ax + hw - 2, ay + (ah - sh)/2, sw + 2, sh)
end

return M

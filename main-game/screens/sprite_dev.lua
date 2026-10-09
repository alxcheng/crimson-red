-- screens/sprite_dev.lua — Dev tool for tuning sprite scale, hitbox, and offsetY

local common   = require("common")
local anim_mod = require("encounter/anim")

local VW    = common.VW
local VH    = common.VH
local SCALE = VH / 300   -- matches encounter SCALE

local M = {}

-- ============================================================================
-- CHARACTER DATA
-- ============================================================================

local CHARS = {
    { name="knight",   path="assets/characters/Knight/Idle.png",   frames=10, fw=135, fh=135, fl=10/60 },
    { name="champion", path="assets/characters/Champion/Idle.png", frames=8,  fw=160, fh=111, fl=10/60 },
    { name="nomad",    path="assets/characters/Nomad/Idle.png",    frames=8,  fw=250, fh=250, fl=8/60  },
    { name="brigand",  path="assets/characters/Brigand/Idle.png",  frames=10, fw=126, fh=126, fl=10/60 },
    { name="duelist",  path="assets/characters/Duelist/Idle.png",  frames=8,  fw=200, fh=200, fl=8/60  },
    { name="skeleton", path="assets/enemies/Skeleton/Idle.png",    frames=4,  fw=150, fh=150, fl=8/60  },
    { name="bat",      path="assets/enemies/Bat/Flight.png",       frames=8,  fw=150, fh=150, fl=8/60  },
    { name="imp",      path="assets/enemies/Imp/Idle.png",         frames=4,  fw=150, fh=150, fl=8/60  },
    { name="mushroom", path="assets/enemies/Mushroom/Idle.png",    frames=4,  fw=150, fh=150, fl=8/60  },
}

-- Starting values: displayW/H are virtual pixels (= raw * SCALE)
local DEFAULTS = {
    knight   = { displayW=45,   displayH=60,   scale=1.10, offsetY=0,   offsetX=0 },
    champion = { displayW=48,   displayH=78,   scale=1.00, offsetY=-35, offsetX=0 },
    nomad    = { displayW=44,   displayH=58,   scale=0.72, offsetY=-18, offsetX=0 },
    brigand  = { displayW=45,   displayH=60,   scale=0.90, offsetY=5,   offsetX=0 },
    duelist  = { displayW=41,   displayH=63,   scale=0.959, offsetY=0,  offsetX=0 },
    skeleton = { displayW=60,   displayH=60,   scale=0.75, offsetY=0,   offsetX=0 },
    bat      = { displayW=60,   displayH=60,   scale=0.75, offsetY=0,   offsetX=0 },
    imp      = { displayW=60,   displayH=60,   scale=0.75, offsetY=0,   offsetX=0 },
    mushroom = { displayW=60,   displayH=60,   scale=0.75, offsetY=0,   offsetX=0 },
}

-- ============================================================================
-- SLIDER DEFINITIONS
-- ============================================================================

local SLIDER_LX = 15    -- label left x
local SLIDER_X  = 110   -- bar left x
local SLIDER_W  = 210   -- bar width

local SLIDERS = {
    { label="Game W",  key="displayW", min=10,   max=200,  y=105, step=1    },
    { label="Game H",  key="displayH", min=10,   max=200,  y=140, step=1    },
    { label="Scale",   key="scale",    min=0.05, max=3.0,  y=175, step=0.01 },
    { label="Offset Y",key="offsetY",  min=-150, max=150,  y=210, step=1    },
    { label="Offset X",key="offsetX",  min=-150, max=150,  y=245, step=1    },
}

local PREV_CX = 590
local PREV_CY = 210

-- ============================================================================
-- STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local font14, font10, font12

local charIdx     = 1
local values      = {}   -- [charName] = { displayW, displayH, scale, offsetY }
local timer       = 0
local activeSlider = nil

-- ============================================================================
-- HELPERS
-- ============================================================================

local function currentChar()  return CHARS[charIdx] end

local function currentValues()
    local ch = currentChar()
    if not values[ch.name] then
        local d = DEFAULTS[ch.name] or { displayW=45, displayH=60, scale=1.0, offsetY=0, offsetX=0 }
        values[ch.name] = { displayW=d.displayW, displayH=d.displayH, scale=d.scale, offsetY=d.offsetY, offsetX=d.offsetX or 0 }
    end
    return values[ch.name]
end

local function sliderKnobX(sl, val)
    local t = (val - sl.min) / (sl.max - sl.min)
    return SLIDER_X + t * SLIDER_W
end

local function xToValue(sl, x)
    local t   = math.max(0, math.min(1, (x - SLIDER_X) / SLIDER_W))
    local raw = sl.min + t * (sl.max - sl.min)
    local steps = math.floor((raw - sl.min) / sl.step + 0.5)
    local v = sl.min + steps * sl.step
    return math.max(sl.min, math.min(sl.max, v))
end

local function saveToFile()
    local lines = { "-- sprite_values.txt  (copy values into entities.lua / anim_mod.load calls)\n" }
    for _, ch in ipairs(CHARS) do
        local v = values[ch.name]
        if v then
            local rawW = v.displayW / SCALE
            local rawH = v.displayH / SCALE
            lines[#lines+1] = string.format(
                "-- %s\n  entities gameW=%.1f  gameH=%.1f  (%.0fpx x %.0fpx at SCALE %.2f)\n"..
                "  anim scale=%.4f   offsetY=%.0f   offsetX=%.0f\n",
                ch.name, rawW, rawH, v.displayW, v.displayH, SCALE, v.scale, v.offsetY, v.offsetX or 0)
        end
    end
    local content = table.concat(lines, "\n")
    local dir = love.filesystem.getSourceBaseDirectory()
    local f = io.open(dir .. "/sprite_values.txt", "w")
    if f then
        f:write(content)
        f:close()
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

function M.onEnter(canvas, postfx, sw)
    canvas_ref = canvas
    postfx_ref = postfx
    switchFn   = sw
    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    if not font14 then
        font14 = common.loadFont(14)
        font12 = common.loadFont(12)
        font10 = common.loadFont(10)
    end

    for _, ch in ipairs(CHARS) do
        local key = "dev_" .. ch.name
        ch.devKey = key
        if not anim_mod.db[key] then
            pcall(anim_mod.load, key, ch.path, ch.frames, ch.fw, ch.fh)
        end
    end

    timer = 0
end

function M.update(dt)
    timer = timer + dt
    local vmx = common.virtualMouse()
    if activeSlider and love.mouse.isDown(1) then
        local sl = SLIDERS[activeSlider]
        local v  = currentValues()
        v[sl.key] = xToValue(sl, vmx)
    else
        activeSlider = nil
    end
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    -- BACK
    if common.overBack(vmx, vmy) then
        switchFn("title"); return
    end

    -- Char navigation  < >
    if vmy >= 55 and vmy < 75 then
        if vmx >= 15 and vmx < 32 then
            charIdx = ((charIdx - 2) % #CHARS) + 1; return
        end
        if vmx >= 200 and vmx < 217 then
            charIdx = (charIdx % #CHARS) + 1; return
        end
    end

    -- Sliders
    for i, sl in ipairs(SLIDERS) do
        if vmx >= SLIDER_X - 10 and vmx <= SLIDER_X + SLIDER_W + 10
        and vmy >= sl.y - 10 and vmy <= sl.y + 10 then
            activeSlider = i
            local v = currentValues()
            v[sl.key] = xToValue(sl, vmx)
            return
        end
    end

    -- Save button
    if vmx >= 15 and vmx < 130 and vmy >= VH - 30 and vmy < VH - 12 then
        saveToFile()
    end
end

function M.mousereleased(x, y, button)
    if button == 1 then activeSlider = nil end
end

function M.keypressed(key)
    if key == "escape" then switchFn("title") end
    if key == "left"   then charIdx = ((charIdx - 2) % #CHARS) + 1 end
    if key == "right"  then charIdx = (charIdx % #CHARS) + 1 end
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    common.drawBackButton(false)

    -- Title
    love.graphics.setFont(font14)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.print("SPRITE DEV", 50, 10)

    -- Character selector
    local ch = currentChar()
    love.graphics.setFont(font12)
    love.graphics.setColor(0.6, 0, 0, 1)
    love.graphics.print("<", 15, 57)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.upper(ch.name), 35, 57)
    love.graphics.setColor(0.6, 0, 0, 1)
    love.graphics.print(">", 200, 57)

    love.graphics.setFont(font10)
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.print(string.format("fw=%d  fh=%d  frames=%d", ch.fw, ch.fh, ch.frames), 35, 75)

    -- Sliders
    local v = currentValues()
    for i, sl in ipairs(SLIDERS) do
        local val  = v[sl.key]
        local knob = sliderKnobX(sl, val)
        local active = (activeSlider == i)

        love.graphics.setFont(font10)
        love.graphics.setColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7, 1)
        love.graphics.print(sl.label, SLIDER_LX, sl.y - 7)

        -- Track
        love.graphics.setColor(0.25, 0.25, 0.25, 1)
        love.graphics.rectangle("fill", SLIDER_X, sl.y - 3, SLIDER_W, 6, 3, 3)

        -- Fill
        love.graphics.setColor(active and 1 or 0.6, 0, 0, 1)
        love.graphics.rectangle("fill", SLIDER_X, sl.y - 3, knob - SLIDER_X, 6, 3, 3)

        -- Knob
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", knob, sl.y, active and 7 or 5)

        -- Value label
        local fmt = (sl.step < 1) and "%.3f" or "%.0f"
        love.graphics.print(string.format(fmt, val), SLIDER_X + SLIDER_W + 8, sl.y - 7)
    end

    -- Divider
    love.graphics.setColor(0.15, 0.15, 0.15, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(370, 0, 370, VH)

    -- ---- PREVIEW ----
    local dw      = v.displayW
    local dh      = v.displayH
    local offsetY = v.offsetY
    local offsetX = v.offsetX or 0
    local sprScale = v.scale * SCALE   -- match in-game draw scale

    -- Floor reference line
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(375, PREV_CY + dh/2, VW - 5, PREV_CY + dh/2)

    -- Hitbox
    love.graphics.setColor(1, 0, 0, 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", PREV_CX - dw/2, PREV_CY - dh/2, dw, dh)

    -- Entity center dot
    love.graphics.setColor(0, 1, 0, 1)
    love.graphics.circle("fill", PREV_CX, PREV_CY, 2)

    -- Foot dot
    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.circle("fill", PREV_CX, PREV_CY + dh/2, 2)

    -- Sprite
    local entry = anim_mod.db[ch.devKey]
    if entry and entry.img then
        local frame = math.floor(timer / ch.fl) % ch.frames
        local q = entry.quads and entry.quads[frame]
        if q then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(entry.img, q,
                PREV_CX + offsetX, PREV_CY + offsetY,
                0, sprScale, sprScale,
                ch.fw / 2, ch.fh / 2)
        end
    else
        love.graphics.setFont(font10)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("no sprite", PREV_CX - 25, PREV_CY - 7)
    end

    -- Legend
    love.graphics.setFont(font10)
    love.graphics.setColor(1, 0, 0, 0.8)
    love.graphics.print("red   = hitbox", 375, VH - 58)
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.print("green = entity center", 375, VH - 46)
    love.graphics.setColor(0, 1, 1, 0.8)
    love.graphics.print("cyan  = foot", 375, VH - 34)
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.print("gray line = floor", 375, VH - 22)

    -- Output values
    local rawW = v.displayW / SCALE
    local rawH = v.displayH / SCALE
    love.graphics.setFont(font10)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.print("── output ──────────────────────────", SLIDER_LX, 275)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.print(string.format("entities:  gameW=%.1f  gameH=%.1f", rawW, rawH), SLIDER_LX, 290)
    love.graphics.print(string.format("anim load: scale=%.4f", v.scale), SLIDER_LX, 304)
    love.graphics.print(string.format("offsetY: %.0f   offsetX: %.0f", v.offsetY, v.offsetX or 0), SLIDER_LX, 318)
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.print(string.format("display px: %.0f x %.0f  (SCALE %.2f)", v.displayW, v.displayH, SCALE), SLIDER_LX, 332)

    -- Save button
    love.graphics.setColor(0.4, 0, 0, 1)
    love.graphics.rectangle("fill", SLIDER_LX, VH - 32, 115, 20)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font10)
    love.graphics.print("SAVE ALL TO FILE", SLIDER_LX + 6, VH - 28)
    love.graphics.setColor(0.35, 0.35, 0.35, 1)
    love.graphics.setFont(font10)
    love.graphics.print(">> sprite_values.txt", SLIDER_LX + 120, VH - 28)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

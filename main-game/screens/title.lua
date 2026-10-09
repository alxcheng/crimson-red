-- screens/title.lua — Title screen module

local common = require("common")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local MENU_ITEMS = {"PLAY", "OPTIONS", "DEV TOOLS", "EXIT"}
local BOX_PAD_X  = 8
local BOX_PAD_Y  = 5

local triangles = {}

local function buildTriangles()
    triangles = {}
    local cx   = VW / 2
    local size = VH * 0.11
    local h    = size * math.sqrt(3) / 2
    local startY = VH * 0.08

    local function upTri(cx2, y)
        return { cx2, y, cx2 - size/2, y + h, cx2 + size/2, y + h }
    end

    local r1y = startY
    table.insert(triangles, upTri(cx, r1y))
    local r2y = r1y + h
    table.insert(triangles, upTri(cx - size/2, r2y))
    table.insert(triangles, upTri(cx + size/2, r2y))
    local r3y = r2y + h
    table.insert(triangles, upTri(cx - size,   r3y))
    table.insert(triangles, upTri(cx,          r3y))
    table.insert(triangles, upTri(cx + size,   r3y))
end

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn

local font, titleFont
local bell
local hoveredItem = nil
local pressedItem    = nil
local box         = common.newBox()

local function getButtonRect(i)
    local tw = font:getWidth(MENU_ITEMS[i])
    local th = font:getHeight()
    return (VW - tw) / 2, VH * 0.65 + (i-1) * (VH * 0.075), tw, th
end

-- ============================================================================
-- TITLE LETTER ANIMATION
-- ============================================================================

local ANIM_DURATION = 0.37   -- seconds each letter takes to slide in
local ANIM_STAGGER  = 0.053  -- seconds between consecutive letters

local titleLetters  = {}     -- { char, finalX, finalY, fromLeft, delay }
local titleAnimTime = 0

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function initTitleAnim()
    titleLetters  = {}
    titleAnimTime = 0

    local str   = "crimson red"
    local tw    = titleFont:getWidth(str)
    local baseX = (VW - tw) / 2
    local baseY = math.floor(VH * 0.49)

    -- Compute per-character final x positions (sum of advances, no kerning correction)
    local charData = {}
    local cx = baseX
    for i = 1, #str do
        local ch = str:sub(i, i)
        charData[i] = { char = ch, x = cx, y = baseY }
        cx = cx + titleFont:getWidth(ch)
    end
    -- Indices: 1=c 2=r 3=i 4=m 5=s 6=o 7=n  8=space  9=r 10=e 11=d

    -- "crimson": slide from left, n arrives first
    local crimsonOrder = { 7, 6, 5, 4, 3, 2, 1 }
    for rank, idx in ipairs(crimsonOrder) do
        table.insert(titleLetters, {
            char     = charData[idx].char,
            finalX   = charData[idx].x,
            finalY   = charData[idx].y,
            fromLeft = true,
            delay    = (rank - 1) * ANIM_STAGGER,
        })
    end

    -- "red": slide from right, r arrives first
    local redOrder = { 9, 10, 11 }
    for rank, idx in ipairs(redOrder) do
        table.insert(titleLetters, {
            char     = charData[idx].char,
            finalX   = charData[idx].x,
            finalY   = charData[idx].y,
            fromLeft = false,
            delay    = (rank - 1) * ANIM_STAGGER,
        })
    end
end

local function updateTitleAnim(dt)
    titleAnimTime = titleAnimTime + dt
end

local function drawTitleAnim()
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0, 0, 1)
    for _, entry in ipairs(titleLetters) do
        local elapsed = titleAnimTime - entry.delay
        if elapsed > 0 then
            local t    = math.min(1, elapsed / ANIM_DURATION)
            local ease = easeOutCubic(t)
            local startX = entry.fromLeft and -40 or (VW + 40)
            local x    = startX + (entry.finalX - startX) * ease
            love.graphics.print(entry.char, x, entry.finalY)
        end
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw)
    canvas_ref = canvas
    postfx_ref = postfx
    switchFn   = sw

    -- Reset postfx to baseline (encounter may have elevated chroma)
    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    -- Load fonts once (re-use across onEnter calls)
    if not font then
        font      = common.loadFont(math.floor(VH * 0.0444))
        titleFont = common.loadFont(math.floor(VH * 0.08))
    end

    if not bell then
        local okb, b = pcall(love.audio.newSource, "assets/sounds/churchbell.ogg", "static")
        if okb then bell = b; bell:setVolume(0.7) end
    end
    require("music_mgr").playGroup({ "title1", "title2" })

    hoveredItem = nil
    pressedItem = nil

    buildTriangles()
    initTitleAnim()

    local bx, by, bw, bh = getButtonRect(1)
    common.initBox(box, bx - BOX_PAD_X, by - BOX_PAD_Y, bw + BOX_PAD_X*2, bh + BOX_PAD_Y*2)
end

function M.update(dt)
    updateTitleAnim(dt)

    hoveredItem = common.hitTest(#MENU_ITEMS, getButtonRect)

    if hoveredItem then
        local bx, by, bw, bh = getButtonRect(hoveredItem)
        common.setBoxTarget(box, bx-BOX_PAD_X, by-BOX_PAD_Y, bw+BOX_PAD_X*2, bh+BOX_PAD_Y*2)
    end

    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    if hoveredItem then pressedItem = hoveredItem end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    if pressedItem then
        local item = MENU_ITEMS[pressedItem]
        pressedItem = nil
        if item == "PLAY" then
            if bell then bell:stop(); bell:play() end
            switchFn("save_select")
        elseif item == "OPTIONS" then
            common.playClickSound()          -- there is no options screen yet
        elseif item == "DEV TOOLS" then
            common.playClickSound()
            switchFn("sprite_dev")
        elseif item == "EXIT" then
            common.playClickSound()
            love.event.quit()
        end
    end
end

function M.keypressed(key)
    if key == "escape" then love.event.quit() end
end

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Logo (Sierpinski triangles)
    love.graphics.setColor(1, 0, 0, 1)
    for _, tri in ipairs(triangles) do
        love.graphics.polygon("fill", tri[1], tri[2], tri[3], tri[4], tri[5], tri[6])
    end

    -- Title (animated per-letter)
    drawTitleAnim()

    -- Red box
    common.drawBox(box, pressedItem ~= nil)

    -- Menu items
    love.graphics.setFont(font)
    for i, label in ipairs(MENU_ITEMS) do
        local bx, by = getButtonRect(i)
        common.setItemColor(pressedItem == i)
        love.graphics.print(label, bx, by)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

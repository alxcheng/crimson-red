-- screens/map.lua — Map screen module

local common = require("common")
local save   = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local TOP_BAR_H    = 40
local TILE_SIZE    = 80
local MAP_Y        = TOP_BAR_H
local MAP_H        = VH - TOP_BAR_H
local POPUP_W      = 210
local POPUP_X      = VW - POPUP_W
local POPUP_CX     = POPUP_X + POPUP_W / 2
local POPUP_CY     = MAP_Y + MAP_H / 2

local PLAYER_SCR_X = VW / 2
local PLAYER_SCR_Y = MAP_Y + MAP_H / 2

local BOX_PAD = 5

-- ============================================================================
-- TILE TYPES
-- ============================================================================

local T_EMPTY     = "empty"
local T_TREE      = "tree"
local T_WATER     = "water"
local T_ENCOUNTER = "encounter"
local T_SHOP      = "shop"

-- ============================================================================
-- MAP DATA
-- ============================================================================

local GRID_COLS        = 21
local GRID_ROWS        = 13
local PLAYER_START_COL = 9
local PLAYER_START_ROW = 5

local RAW_MAP = {
    {".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".","."}, -- row 0
    {".",".",".",".",".",".",".",".","T","T","T","T","T",".",".",".",".",".",".",".","."}, -- row 1
    {".",".",".",".",".",".","T",".","X",".",".",".","X",".","T",".",".",".",".",".","."},
    {".",".",".",".",".","T",".","X",".",".",".",".",".",  "X",".","T",".",".",".",".","."},
    {".",".",".",".","T",".",".",".",".",".",  "S",".",".",".",".",".",  "T",".",".",".","."}, -- row 4
    {".",".",".",  "T",".",".","X",".",".",".",".",".",".","X",".",".",".",  "T",".",".","."},
    {".",".",".",  "T",".",".",".",".",".",".",  "X",".",".",".",".",".",".","T",".",".","."},
    {".",".",".",  "T","W","W","W","W","W","W","W","W","W","W","W","W","W","T",".",".","."}, -- row 7
    {".",".",".",".","W","W","W","W","W","W","W","W","W","W","W","W","W",".",".",".","."},
    {".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".","."}, -- row 9
    {".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".","."}, -- row 10
    {".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".","."}, -- row 11
    {".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",".","."}, -- row 12
}

local DIRS = {{0,-1},{0,1},{-1,0},{1,0}}

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local grid = {}
local player = { col=PLAYER_START_COL, row=PLAYER_START_ROW, px=0, py=0,
                 fromCol=PLAYER_START_COL, fromRow=PLAYER_START_ROW }
-- Visual-only encounter lock: while the player SPRITE sits on an encounter tile
-- (popup showing), the move data already points at that tile but the encounter
-- is NOT yet engaged/cleared. The lock keeps the player from straying off
-- mid-popup and is the ONLY thing that survives a save/quit; it is never
-- written to the save. Cleared by the ENTER press (engage) or by walking off.
local standingOnEncounter = false

local canvas_map, vignette_shader
local font16, font14
local icons = {}

local hoveredItem = nil
local hoveredKey  = nil
local pressedItem = nil
local box = common.newBox()
local topbarItems = {}

local POPUP_TEXT  = "There are a group of enemies here."
local POPUP_SPEED = 0.25
local TYPE_SPEED  = 40

local popup = { visible=false, scale=0, direction=0, typeProgress=0, typing=false }

local ENTER_LABEL = "ENTER"
local enterLabelW = 0
local enterLabelH = 0
local enterX, enterY = 0, 0

local MOVE_SPEED = 14

-- ============================================================================
-- GRID HELPERS
-- ============================================================================

local function getCell(c, r)
    if c < 0 or c >= GRID_COLS or r < 0 or r >= GRID_ROWS then return nil end
    return grid[r+1] and grid[r+1][c+1]
end

local function isBarrier(c, r)
    local cell = getCell(c, r)
    if not cell then return true end
    return cell.type == T_TREE or cell.type == T_WATER
end

local function clearTile(c, r)
    for _, d in ipairs(DIRS) do
        local nc = getCell(c + d[1], r + d[2])
        if nc and (nc.type == T_TREE or nc.type == T_WATER) then
            nc.revealed = true
        end
    end
end

local function initGrid(sd)
    grid = {}
    for r = 1, GRID_ROWS do
        grid[r] = {}
        for c = 1, GRID_COLS do
            local raw = RAW_MAP[r][c]
            local ttype
            if     raw == "T" then ttype = T_TREE
            elseif raw == "W" then ttype = T_WATER
            elseif raw == "X" then ttype = T_ENCOUNTER
            elseif raw == "S" then ttype = T_SHOP
            else                   ttype = T_EMPTY
            end
            grid[r][c] = {type=ttype, revealed=false}
        end
    end

    -- Apply cleared encounters from save data
    if sd and sd.mapProgression then
        local mp = sd.mapProgression
        for _, pos in ipairs(mp.clearedEncounters or {}) do
            local cell = getCell(pos[1], pos[2])
            if cell then cell.type = T_EMPTY end
        end
        for _, pos in ipairs(mp.revealedTiles or {}) do
            local cell = getCell(pos[1], pos[2])
            if cell then cell.revealed = true end
        end
    end
end

local function getRevealedTiles()
    local result = {}
    for r = 0, GRID_ROWS-1 do
        for c = 0, GRID_COLS-1 do
            local cell = getCell(c, r)
            if cell and cell.revealed then
                result[#result+1] = {c, r}
            end
        end
    end
    return result
end

local function updateSaveData()
    local sd = saveData_ref
    if not sd then return end
    local mp = sd.mapProgression
    mp.playerCol         = player.col
    mp.playerRow         = player.row
    mp.revealedTiles     = getRevealedTiles()
    -- clearedEncounters is updated in onEnterPress
end

-- ============================================================================
-- LAYOUT HELPERS
-- ============================================================================

local function lerp(a, b, t) return a + (b-a) * t end

local function tileToScreen(c, r)
    local offX = (c - player.col) * TILE_SIZE - player.px
    local offY = (r - player.row) * TILE_SIZE - player.py
    return PLAYER_SCR_X - TILE_SIZE/2 + offX,
           PLAYER_SCR_Y - TILE_SIZE/2 + offY
end

local function buildTopBar()
    topbarItems = {}
    local aW, aH = 24, 18
    local aX = 12
    local aY = math.floor((TOP_BAR_H - aH) / 2)
    topbarItems[1] = {isArrow=true, x=aX, y=aY, w=aW, h=aH}

    local labels  = {"PARTY", "TALENTS", "ITEMS"}
    local centers = {100, 205, 300}
    for i, lbl in ipairs(labels) do
        local lw = font16:getWidth(lbl)
        local lh = font16:getHeight()
        topbarItems[i+1] = {
            label = lbl,
            x = math.floor(centers[i] - lw/2),
            y = math.floor((TOP_BAR_H - lh)/2),
            w = lw, h = lh,
        }
    end
end

-- ============================================================================
-- HOVER DETECTION
-- ============================================================================

local function detectHover(vmx, vmy)
    hoveredItem = nil

    -- Adjacent non-barrier tiles
    for _, d in ipairs(DIRS) do
        local tc, tr = player.col + d[1], player.row + d[2]
        if not isBarrier(tc, tr) then
            local sx, sy = tileToScreen(tc, tr)
            if vmx >= sx and vmx < sx+TILE_SIZE and vmy >= sy and vmy < sy+TILE_SIZE then
                hoveredItem = {zone="map", col=tc, row=tr, rect={sx, sy, TILE_SIZE, TILE_SIZE}}
                return
            end
        end
    end

    -- Popup ENTER button
    if popup.visible and popup.scale >= 1 then
        local ex1 = enterX - BOX_PAD
        local ey1 = enterY - BOX_PAD
        local ex2 = ex1 + enterLabelW + BOX_PAD*2
        local ey2 = ey1 + enterLabelH + BOX_PAD*2
        if vmx >= ex1 and vmx < ex2 and vmy >= ey1 and vmy < ey2 then
            hoveredItem = {zone="popup", rect={ex1, ey1, enterLabelW+BOX_PAD*2, enterLabelH+BOX_PAD*2}}
            return
        end
    end

    -- Top bar
    for i, it in ipairs(topbarItems) do
        if vmx >= it.x and vmx < it.x+it.w and vmy >= it.y and vmy < it.y+it.h then
            hoveredItem = {zone="topbar", index=i, rect={it.x-BOX_PAD, it.y-BOX_PAD, it.w+BOX_PAD*2, it.h+BOX_PAD*2}}
            return
        end
    end
end

-- ============================================================================
-- MOVEMENT / ACTIONS
-- ============================================================================

local function tryMove(tc, tr)
    if math.abs(tc-player.col) + math.abs(tr-player.row) ~= 1 then return end
    if isBarrier(tc, tr) then return end

    -- While the player sits on an encounter tile (popup open), they may only
    -- walk back to where they came from. (The old check read the live grid
    -- cell, which cleared the moment ENTER pressed — this flag is stable.)
    if standingOnEncounter then
        if not (tc == player.fromCol and tr == player.fromRow) then return end
    end

    player.px      = (player.col - tc) * TILE_SIZE
    player.py      = (player.row - tr) * TILE_SIZE
    player.fromCol = player.col
    player.fromRow = player.row
    player.col     = tc
    player.row     = tr

    local dest = getCell(player.col, player.row)
    dest.revealed = true

    if dest.type == T_ENCOUNTER then
        -- Player now sits ON the encounter tile: the popup opens and the move
        -- data records this tile, but the encounter is NOT engaged yet.
        standingOnEncounter = true
        popup.visible      = true
        popup.direction    = 1
        popup.typeProgress = 0
        popup.typing       = true
    else
        standingOnEncounter = false
        if popup.visible then
            popup.direction = -1
            popup.typing    = false
        end
        if dest.type == T_EMPTY then
            clearTile(player.col, player.row)
        end
    end

    -- Autosave on every move EXCEPT when the player is sitting on an
    -- encounter tile (waiting to enter). Persisting that position would make
    -- a later quit look like "player is on an encounter" and — combined with
    -- onEnter re-arming the popup from the saved position — mark the
    -- encounter cleared without it ever being fought. On-encounter positions
    -- are visual-only; the last OFF-tile position is what gets saved.
    if not standingOnEncounter then
        updateSaveData()
        save.write(slot_ref, saveData_ref)
    end
end

local function onEnterPress()
    local here = getCell(player.col, player.row)
    local onEncounter = here and here.type == T_ENCOUNTER

    -- Dismiss the popup (visual state)
    standingOnEncounter = false
    popup.direction = -1
    popup.typing    = false

    if not onEncounter then
        -- ENTER was pressed while standing on a non-encounter tile (the popup
        -- had already closed): nothing to engage. Reset the autosave to the
        -- last safe position and stay on the map.
        updateSaveData()
        save.write(slot_ref, saveData_ref)
        return
    end

    -- ENGAGE the encounter: this is the single moment it is recorded as
    -- cleared, right before we leave the map. (Never mark it cleared earlier,
    -- and never on quit — a quit means we never actually fought it.)
    local mp = saveData_ref.mapProgression
    local ce = mp.clearedEncounters or {}
    ce[#ce+1] = {player.col, player.row}
    mp.clearedEncounters = ce

    here.type     = T_EMPTY
    here.revealed = true
    clearTile(player.col, player.row)

    updateSaveData()
    save.write(slot_ref, saveData_ref)

    switchFn("encounter", saveData_ref, slot_ref)
end

local function onTopBar(index)
    if index == 1 then
        switchFn("save_select")
    elseif index == 2 then
        switchFn("party_select", saveData_ref, slot_ref)
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, sd, slot)
    canvas_ref  = canvas
    postfx_ref  = postfx
    switchFn    = sw
    saveData_ref = sd
    slot_ref    = slot
    require("music_mgr").play("forest")

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    -- One-time asset loading
    if not font16 then
        font16 = common.loadFont(16)
        font14 = common.loadFont(14)

        canvas_map = love.graphics.newCanvas(VW, MAP_H)
        canvas_map:setFilter("nearest", "nearest")

        vignette_shader = love.graphics.newShader([[
            vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _sc) {
                vec4 c = Texel(tex, tc);
                vec2 uv = (tc - 0.5) * 2.0;
                float d = length(uv);
                float v = 1.0 - smoothstep(0.25, 1.05, d);
                v = v * v;
                return vec4(c.rgb * v, c.a);
            }
        ]])

        icons.unknown   = love.graphics.newImage("assets/icons/mapicon-unknown.png")
        icons.tree      = love.graphics.newImage("assets/icons/mapicon-tree.png")
        icons.water     = love.graphics.newImage("assets/icons/mapicon-ocean.png")
        icons.shop      = love.graphics.newImage("assets/icons/mapicon-shop.png")
        icons.player    = love.graphics.newImage("assets/icons/mapicon-player.png")
        icons.encounter = love.graphics.newImage("assets/icons/encounter.png")
        for _, img in pairs(icons) do img:setFilter("nearest", "nearest") end
    end

    -- Restore player position from save
    local mp = sd and sd.mapProgression
    player.col     = (mp and mp.playerCol) or PLAYER_START_COL
    player.row     = (mp and mp.playerRow) or PLAYER_START_ROW
    player.px      = 0
    player.py      = 0
    player.fromCol = player.col
    player.fromRow = player.row

    initGrid(sd)

    -- Reveal starting area barriers if tile was already known
    clearTile(player.col, player.row)

    hoveredItem = nil
    hoveredKey  = nil
    pressedItem = nil
    popup = {visible=false, scale=0, direction=0, typeProgress=0, typing=false}

    -- If the save records the player standing on an encounter tile (possible
    -- only from a pre-fix save), re-engage the popup instead of leaving a
    -- ghost encounter that would never be fought or dismissed. (Post-fix,
    -- on-encounter positions are never saved, so this is a no-op normally.)
    local here0 = getCell(player.col, player.row)
    if here0 and here0.type == T_ENCOUNTER then
        standingOnEncounter = true
        popup.visible      = true
        popup.scale        = 1
        popup.typeProgress = #POPUP_TEXT
    else
        standingOnEncounter = false
    end

    buildTopBar()

    enterLabelW = font16:getWidth(ENTER_LABEL)
    enterLabelH = font16:getHeight()
    enterX = math.floor(POPUP_X + (POPUP_W - enterLabelW) / 2)
    enterY = MAP_Y + MAP_H - 38

    local sx, sy = tileToScreen(player.col, player.row - 1)
    common.initBox(box, sx, sy, TILE_SIZE, TILE_SIZE)
end

function M.update(dt)
    -- Player pixel offset animation
    if math.abs(player.px) > 0.3 or math.abs(player.py) > 0.3 then
        local t = 1 - math.exp(-MOVE_SPEED * dt)
        player.px = lerp(player.px, 0, t)
        player.py = lerp(player.py, 0, t)
    else
        player.px = 0; player.py = 0
    end

    -- Popup scale
    if popup.direction == 1 then
        popup.scale = math.min(1, popup.scale + dt / POPUP_SPEED)
        if popup.scale >= 1 then popup.direction = 0 end
    elseif popup.direction == -1 then
        popup.scale = math.max(0, popup.scale - dt / POPUP_SPEED)
        if popup.scale <= 0 then popup.direction=0; popup.visible=false end
    end

    if popup.visible and popup.typing then
        popup.typeProgress = math.min(#POPUP_TEXT, popup.typeProgress + dt * TYPE_SPEED)
    end

    local vmx, vmy = common.virtualMouse()
    detectHover(vmx, vmy)

    if hoveredItem then
        local newKey = hoveredItem.zone .. (hoveredItem.col or "") ..
                       (hoveredItem.row or "") .. (hoveredItem.index or "")
        local silent = (newKey == hoveredKey)
        hoveredKey   = newKey
        local r = hoveredItem.rect
        common.setBoxTarget(box, r[1], r[2], r[3], r[4], silent)
    else
        hoveredKey = nil
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
        local p = pressedItem
        pressedItem = nil
        if     p.zone == "map"    then tryMove(p.col, p.row)
        elseif p.zone == "popup"  then common.playClickSound(); onEnterPress()
        elseif p.zone == "topbar" then common.playClickSound(); onTopBar(p.index)
        end
    end
end

function M.keypressed(key)
    if key == "escape" then switchFn("save_select") end
end

-- ============================================================================
-- DRAW HELPERS
-- ============================================================================

local function drawIcon(img, sx, sy)
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, sx, sy, 0, TILE_SIZE/iw, TILE_SIZE/ih)
end

local function drawTile(c, r)
    local cell = getCell(c, r)
    if not cell then return end
    local sx, sy = tileToScreen(c, r)
    if sx+TILE_SIZE < 0 or sx > VW or sy+TILE_SIZE < MAP_Y or sy > VH then return end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", sx, sy, TILE_SIZE, TILE_SIZE)

    if not cell.revealed then
        drawIcon(icons.unknown, sx, sy)
    else
        local t = cell.type
        if t == T_TREE then
            drawIcon(icons.tree, sx, sy)
        elseif t == T_WATER then
            drawIcon(icons.water, sx, sy)
        elseif t == T_ENCOUNTER then
            drawIcon(icons.encounter, sx, sy)
        elseif t == T_SHOP then
            drawIcon(icons.shop, sx, sy)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", sx+0.5, sy+0.5, TILE_SIZE-1, TILE_SIZE-1)
end

local function drawArrowTopBar(x, y, w, h, inBlack)
    love.graphics.setColor(inBlack and common.COLOR_BLACK or common.COLOR_RED)
    local headW  = math.floor(w * 0.45)
    local shaftH = math.floor(h * 0.42)
    love.graphics.polygon("fill", x, y+h/2, x+headW, y, x+headW, y+h)
    love.graphics.rectangle("fill", x+headW-1, y+(h-shaftH)/2, w-headW+1, shaftH)
end

local function isItemPressed(zone, index)
    return pressedItem and pressedItem.zone == zone and
           (index == nil or pressedItem.index == index)
end

local LOCATION_NAME = "DARK FOREST"

local function drawTopBar()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, TOP_BAR_H, VW, TOP_BAR_H)

    local it = topbarItems[1]
    drawArrowTopBar(it.x, it.y, it.w, it.h, isItemPressed("topbar", 1))

    love.graphics.setFont(font16)
    for i = 2, #topbarItems do
        local t = topbarItems[i]
        love.graphics.setColor(isItemPressed("topbar", i) and common.COLOR_BLACK or common.COLOR_WHITE)
        love.graphics.print(t.label, t.x, t.y)
    end

    local lw = font16:getWidth(LOCATION_NAME)
    local lh = font16:getHeight()
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print(LOCATION_NAME, VW - lw - 12, math.floor((TOP_BAR_H - lh) / 2))
end

local function drawPopupContent()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", POPUP_X+2, MAP_Y+2, POPUP_W-4, MAP_H-4)

    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", POPUP_X+1, MAP_Y+1, POPUP_W-2, MAP_H-2)

    love.graphics.setFont(font16)
    local title = "ENCOUNTER"
    local tw    = font16:getWidth(title)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(title, math.floor(POPUP_X + (POPUP_W-tw)/2), MAP_Y+18)

    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(POPUP_X+8, MAP_Y+44, POPUP_X+POPUP_W-8, MAP_Y+44)

    local visible = string.sub(POPUP_TEXT, 1, math.floor(popup.typeProgress))
    love.graphics.setFont(font14)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.printf(visible, POPUP_X+10, MAP_Y+56, POPUP_W-20, "left")

    local enterPressed = isItemPressed("popup")
    if hoveredItem and hoveredItem.zone == "popup" then
        if enterPressed then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", enterX-BOX_PAD, enterY-BOX_PAD,
                                    enterLabelW+BOX_PAD*2, enterLabelH+BOX_PAD*2)
        else
            love.graphics.setColor(1, 0, 0, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", enterX-BOX_PAD, enterY-BOX_PAD,
                                    enterLabelW+BOX_PAD*2, enterLabelH+BOX_PAD*2)
        end
    end
    love.graphics.setFont(font16)
    love.graphics.setColor(enterPressed and common.COLOR_BLACK or common.COLOR_WHITE)
    love.graphics.print(ENTER_LABEL, enterX, enterY)
end

local function drawPopup()
    if not popup.visible and popup.scale <= 0 then return end
    love.graphics.push()
    love.graphics.translate(POPUP_CX, POPUP_CY)
    love.graphics.scale(popup.scale, popup.scale)
    love.graphics.translate(-POPUP_CX, -POPUP_CY)
    drawPopupContent()
    love.graphics.pop()
end

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Pass 1: map tiles to mapCanvas
    love.graphics.setCanvas(canvas_map)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.push()
    love.graphics.translate(0, -MAP_Y)
    for r = 0, GRID_ROWS-1 do
        for c = 0, GRID_COLS-1 do
            drawTile(c, r)
        end
    end
    local psx, psy = tileToScreen(player.col, player.row)
    love.graphics.setColor(1, 1, 1, 1)
    drawIcon(icons.player, psx, psy)
    love.graphics.pop()

    -- Pass 2: composite with vignette onto main canvas
    love.graphics.setCanvas(canvas_ref)
    love.graphics.setShader(vignette_shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas_map, 0, MAP_Y)
    love.graphics.setShader()

    common.drawBox(box, pressedItem ~= nil and pressedItem.zone ~= "popup")
    drawTopBar()
    drawPopup()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

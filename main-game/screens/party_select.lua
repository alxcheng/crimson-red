-- screens/party_select.lua — Party select screen module (click-to-move)
--
-- Interaction is instant clicks (no drag):
--   * Click a PARTY member (filled slot)  -> remove it, append to roster bottom.
--   * Click an INVENTORY (roster) member  -> fill the lowest-index empty party
--     slot, or (party full) move it to the roster bottom (net no visual change).

local common   = require("common")
local save     = require("save")
local anim_mod = require("encounter/anim")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local ICON_SIZE     = 55
local PARTY_SLOTS   = 4
local PARTY_GAP     = 16
local PARTY_Y       = 50

-- Roster cells are uniform ICON_SIZE × ICON_SIZE squares
local ROSTER_COLS   = 6
local ROSTER_ROWS   = 2
local ROSTER_CELL_W = ICON_SIZE
local ROSTER_CELL_H = ICON_SIZE
local ROSTER_INNER_W = ROSTER_COLS * ROSTER_CELL_W
local ROSTER_INNER_H = ROSTER_ROWS * ROSTER_CELL_H
local ROSTER_PAD    = 8
local ROSTER_OUTER_W = ROSTER_INNER_W + ROSTER_PAD * 2
local ROSTER_OUTER_H = ROSTER_INNER_H + ROSTER_PAD * 2
local ROSTER_X      = 50
local ROSTER_Y      = 175
local ROSTER_INNER_X = ROSTER_X + ROSTER_PAD
local ROSTER_INNER_Y = ROSTER_Y + ROSTER_PAD

-- Center party slots above the roster grid
local PARTY_TOTAL_W = PARTY_SLOTS * ICON_SIZE + (PARTY_SLOTS - 1) * PARTY_GAP
local PARTY_X       = ROSTER_X + math.floor((ROSTER_OUTER_W - PARTY_TOTAL_W) / 2)

-- Preview panel (right side)
local PREVIEW_X      = 450
local PREVIEW_Y      = 50
local PREVIEW_W      = 280
local PREVIEW_H      = 350
local PREVIEW_NAME_Y = PREVIEW_Y + PREVIEW_H + 12

-- Idle animation data for the preview panel (scale/offsetY from sprite_values.txt)
local IDLE_DATA = {
    knight   = { key = "KnightIdle",   path = "assets/characters/Knight/Idle.png",   frames = 10, fw = 135, fh = 135, scale = 1.1000, offsetY =   0, fl = 10/60 },
    brigand  = { key = "BrigandIdle",  path = "assets/characters/Brigand/Idle.png",  frames = 10, fw = 126, fh = 126, scale = 0.9000, offsetY =   5, fl = 10/60 },
    nomad    = { key = "NomadIdle",    path = "assets/characters/Nomad/Idle.png",    frames =  8, fw = 250, fh = 250, scale = 0.7200, offsetY = -18, fl =  8/60 },
    champion = { key = "ChampionIdle", path = "assets/characters/Champion/Idle.png", frames =  8, fw = 160, fh = 111, scale = 1.0000, offsetY = -35, fl = 10/60 },
    duelist  = { key = "DuelistIdle",  path = "assets/characters/Duelist/Idle.png",  frames =  8, fw = 200, fh = 200, scale = 0.9590, offsetY =   0, fl =  8/60 },
}

local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local A_H     = common.ARROW_H
local A_W     = common.ARROW_W
local BOX_PAD = 5

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local party    = {}   -- [1..4] charName or nil
local roster   = {}   -- ordered list of charNames not in active party
local icons    = {}   -- { [charName] = Image }

local assetsLoaded  = false
local font           -- size 14, slot number labels
local previewFont    -- size 24, preview character name
local hoveredBack   = false
local pressedItem   = nil   -- "back" or nil
local hoveredChar   = nil
local previewTimer  = 0
local box          = common.newBox()

-- ============================================================================
-- HELPERS
-- ============================================================================

local function getPartySlotRect(i)
    return PARTY_X + (i - 1) * (ICON_SIZE + PARTY_GAP), PARTY_Y, ICON_SIZE, ICON_SIZE
end

-- Returns top-left + full cell dimensions (including name zone for hit testing)
local function getRosterCellRect(idx)
    local col = (idx - 1) % ROSTER_COLS
    local row = math.floor((idx - 1) / ROSTER_COLS)
    return ROSTER_INNER_X + col * ROSTER_CELL_W,
           ROSTER_INNER_Y + row * ROSTER_CELL_H,
           ROSTER_CELL_W, ROSTER_CELL_H
end

local function drawIcon(name, x, y, size)
    size = size or ICON_SIZE
    local img = icons[name]
    -- A class without a charicon (cleric/paladin/wizard/rogue have none yet)
    -- falls back to a shared existing icon so the cell still renders.
    if not img and name ~= "knight" then img = icons["knight"] end
    if not img then return end
    local iw, ih = img:getDimensions()
    local sc = math.min(size / iw, size / ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
end


local function drawArrow()
    common.drawBackArrow(pressedItem == "back")
end

-- Lowest-index empty party slot, or nil when the party is full.
local function firstFreeSlot()
    for s = 1, PARTY_SLOTS do
        if not party[s] then return s end
    end
    return nil
end

-- ============================================================================
-- EXIT — saves partyOrder and returns to map
-- ============================================================================

local function exit()
    local order = {}
    for i = 1, PARTY_SLOTS do
        order[i] = party[i] or false
    end
    saveData_ref.partyOrder = order
    save.write(slot_ref, saveData_ref)
    switchFn("map", saveData_ref, slot_ref)
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, saveData, slot)
    canvas_ref   = canvas
    postfx_ref   = postfx
    switchFn     = sw
    saveData_ref = saveData
    slot_ref     = slot
    require("music_mgr").play("forest")

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    party = {}
    local inParty = {}
    local po = saveData.partyOrder or {}
    for i = 1, PARTY_SLOTS do
        local name = po[i]
        if type(name) == "string" then
            party[i] = name
            inParty[name] = true
        end
    end

    roster = {}
    local uc = saveData.unlockedCharacters or {}
    for name in pairs(uc) do
        if not inParty[name] then
            roster[#roster + 1] = name
        end
    end
    table.sort(roster)

    if not assetsLoaded then
        assetsLoaded = true
        font        = common.loadFont(14)
        previewFont = common.loadFont(24)
        for _, d in pairs(IDLE_DATA) do
            if not anim_mod.db[d.key] then
                anim_mod.load(d.key, d.path, d.frames, d.fw, d.fh, d.scale)
            end
        end
    end
    -- Load any icons not yet cached (handles new characters across save slots)
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    hoveredBack  = false
    pressedItem  = nil
    hoveredChar  = nil
    previewTimer = 0

    local ix, iy = getPartySlotRect(1)
    common.initBox(box, ix - BOX_PAD, iy - BOX_PAD, ICON_SIZE + BOX_PAD * 2, ICON_SIZE + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    -- Hover detection
    hoveredBack = false
    if vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H then
        hoveredBack = true
        common.setBoxTarget(box, AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD * 2, A_H + BOX_PAD * 2)
    end

    -- Red box tracks the hovered icon cell (party slots first, then roster).
    local boxHit = false
    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, sw + BOX_PAD * 2, sh + BOX_PAD * 2)
            boxHit = true; break
        end
    end
    if not boxHit then
        for idx = 1, #roster do
            local rx, ry = getRosterCellRect(idx)
            if vmx >= rx and vmx < rx + ROSTER_CELL_W and vmy >= ry and vmy < ry + ICON_SIZE then
                common.setBoxTarget(box, rx - BOX_PAD, ry - BOX_PAD, ROSTER_CELL_W + BOX_PAD * 2, ICON_SIZE + BOX_PAD * 2)
                break
            end
        end
    end

    common.updateBox(box, dt)

    -- Track hovered character for preview panel (hover only).
    hoveredChar = nil
    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            hoveredChar = party[i]
            break
        end
    end
    if not hoveredChar then
        for idx = 1, #roster do
            local rx, ry = getRosterCellRect(idx)
            if vmx >= rx and vmx < rx + ICON_SIZE and vmy >= ry and vmy < ry + ICON_SIZE then
                hoveredChar = roster[idx]
                break
            end
        end
    end

    previewTimer = previewTimer + dt
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    -- Back arrow (handled on release, as before).
    if vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H then
        pressedItem = "back"
        return
    end

    -- Click a filled PARTY slot: remove it, append to the roster bottom.
    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if party[i] and vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            local name = table.remove(party, i)
            roster[#roster + 1] = name
            common.playClickSound()
            return
        end
    end

    -- Click an INVENTORY (roster) cell: move to the lowest free party slot,
    -- or (party full) append to the roster bottom (net no visual change).
    for idx, name in ipairs(roster) do
        local rx, ry, rw = getRosterCellRect(idx)
        if vmx >= rx and vmx < rx + rw and vmy >= ry and vmy < ry + ICON_SIZE then
            local target = firstFreeSlot()
            local removed = table.remove(roster, idx)
            if target then
                party[target] = removed
            else
                roster[#roster + 1] = removed
            end
            common.playClickSound()
            return
        end
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end

    if pressedItem == "back" and hoveredBack then
        pressedItem = nil
        common.playClickSound()
        exit()
        return
    end
    pressedItem = nil
end

function M.keypressed(key)
    if key == "escape" or key == "return" or key == "kpenter" then
        exit()
    end
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Icons first (lines drawn on top afterwards)

    -- Roster icons (no name labels)
    for idx, name in ipairs(roster) do
        local rx, ry = getRosterCellRect(idx)
        drawIcon(name, rx, ry)
    end

    -- Party icons (no name labels)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        if party[i] then
            drawIcon(party[i], sx, sy)
        end
    end

    -- 3. Lines and outlines (drawn on top of icons)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)

    -- Roster cells as individual squares
    for col = 0, ROSTER_COLS - 1 do
        for row = 0, ROSTER_ROWS - 1 do
            love.graphics.rectangle("line",
                ROSTER_INNER_X + col * ROSTER_CELL_W,
                ROSTER_INNER_Y + row * ROSTER_CELL_H,
                ROSTER_CELL_W, ROSTER_CELL_H)
        end
    end

    -- Party slot outlines (white)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        love.graphics.rectangle("line", sx, sy, ICON_SIZE, ICON_SIZE)
    end

    -- 4. Party slot number labels at top (white)
    love.graphics.setFont(font)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        local lbl = tostring(i)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(lbl, sx + (ICON_SIZE - font:getWidth(lbl)) / 2, sy - font:getHeight() - 2)
    end

    -- 5. Animated following red box
    common.drawBox(box, pressedItem == "back")

    -- 6. Back arrow (above box so it stays visible when pressed/filled white)
    drawArrow()

    -- 7. Preview panel (right side)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", PREVIEW_X, PREVIEW_Y, PREVIEW_W, PREVIEW_H)

    if hoveredChar then
        local data = IDLE_DATA[hoveredChar]
        if data then
            local entry = anim_mod.db[data.key]
            if entry and entry.img then
                local frame = math.floor(previewTimer / data.fl) % entry.frames
                local q = entry.quads[frame]
                if q then
                    local basefit  = math.min(PREVIEW_W / entry.fw, PREVIEW_H / entry.fh)
                    local fitScale = basefit * 1.9 * data.scale
                    local offsetPx = data.offsetY * basefit * 1.9
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(entry.img, q,
                        PREVIEW_X + PREVIEW_W / 2,
                        PREVIEW_Y + PREVIEW_H / 2 + offsetPx,
                        0, fitScale, fitScale,
                        entry.fw / 2, entry.fh / 2)
                end
            end
        end

        love.graphics.setFont(previewFont)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(string.upper(hoveredChar),
            PREVIEW_X, PREVIEW_NAME_Y, PREVIEW_W, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

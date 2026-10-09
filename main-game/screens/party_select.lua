-- screens/party_select.lua — Party select screen module (click-to-move)
--
-- Interaction is instant clicks (no drag):
--   * Click a PARTY member (filled slot)  -> remove it, append to roster bottom.
--   * Click an INVENTORY (roster) member  -> fill the lowest-index empty party
--     slot, or (party full) move it to the roster bottom (net no visual change).
--
-- Presentation: Battleheart "Party Reserves" — the 4 active slots are a
-- prominent framed strip on top, the reserve grid (6x2) sits below, and a
-- hover tooltip (name / level / stats) follows the hovered slot.

local common   = require("common")
local save     = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- PALETTE (project: crimson red / off-red / white on black)
-- ============================================================================

local CRIMSON = {0.84, 0.07, 0.16, 1}   -- crimson red  (primary accent)
local OFFRED  = {1.00, 0.42, 0.42, 1}   -- off-red      (hover accent)
local WHITE   = {1.00, 1.00, 1.00, 1}   -- white        (pressed/active)

-- ============================================================================
-- LAYOUT
-- ============================================================================

local ICON_SIZE   = 56
local PARTY_SLOTS = 4
local PARTY_GAP   = 18
local FRAME_PAD   = 14
local LABEL_H     = 20                       -- "ACTIVE" / "RESERVES" caption above each frame
local NUMBER_H    = 20                       -- slot-number band under the portraits

-- Active party frame: 4 portraits with their slot numbers underneath.
local PARTY_TOTAL_W = PARTY_SLOTS * ICON_SIZE + (PARTY_SLOTS - 1) * PARTY_GAP
local PARTY_FRAME_W = PARTY_TOTAL_W + FRAME_PAD * 2
local PARTY_FRAME_H = FRAME_PAD + ICON_SIZE + NUMBER_H + FRAME_PAD - 6
local PARTY_FRAME_X = math.floor((VW - PARTY_FRAME_W) / 2)
local PARTY_FRAME_Y = common.TOP_BAR_H + 14 + LABEL_H
local PARTY_X       = PARTY_FRAME_X + FRAME_PAD
local PARTY_Y       = PARTY_FRAME_Y + FRAME_PAD

-- Reserve grid (BH: 6x2 = 12 slots), same cell size as the party portraits.
local ROSTER_COLS   = 6
local ROSTER_ROWS   = 2
local ROSTER_CELL_W = ICON_SIZE
local ROSTER_CELL_H = ICON_SIZE
local ROSTER_GAP    = 8
local ROSTER_INNER_W = ROSTER_COLS * ROSTER_CELL_W + (ROSTER_COLS - 1) * ROSTER_GAP
local ROSTER_INNER_H = ROSTER_ROWS * ROSTER_CELL_H + (ROSTER_ROWS - 1) * ROSTER_GAP
local ROSTER_OUTER_W = ROSTER_INNER_W + FRAME_PAD * 2
local ROSTER_OUTER_H = ROSTER_INNER_H + FRAME_PAD * 2
local ROSTER_X      = math.floor((VW - ROSTER_OUTER_W) / 2)
local ROSTER_Y      = PARTY_FRAME_Y + PARTY_FRAME_H + 14 + LABEL_H
local ROSTER_INNER_X = ROSTER_X + FRAME_PAD
local ROSTER_INNER_Y = ROSTER_Y + FRAME_PAD

local BOX_PAD = common.BOX_PAD

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local party    = {}   -- [1..4] charName or nil
local roster   = {}   -- ordered list of charNames not in active party
local icons    = {}   -- { [charName] = Image }

local assetsLoaded    = false
local font            -- size 14, slot numbers and captions
local hoveredBack     = false
local pressedItem     = nil   -- "back" or nil
local hoveredChar     = nil
local hoveredInParty  = false
local hoveredRect     = nil   -- {x, y, w, h} of the hovered cell (tooltip anchor)
local box             = common.newBox()

-- ============================================================================
-- HELPERS
-- ============================================================================

local function getPartySlotRect(i)
    return PARTY_X + (i - 1) * (ICON_SIZE + PARTY_GAP), PARTY_Y, ICON_SIZE, ICON_SIZE
end

-- Returns top-left + full cell dimensions
local function getRosterCellRect(idx)
    local col = (idx - 1) % ROSTER_COLS
    local row = math.floor((idx - 1) / ROSTER_COLS)
    return ROSTER_INNER_X + col * (ROSTER_CELL_W + ROSTER_GAP),
           ROSTER_INNER_Y + row * (ROSTER_CELL_H + ROSTER_GAP),
           ROSTER_CELL_W, ROSTER_CELL_H
end

local displayName = common.titleCase

local function drawIcon(name, x, y, size, alpha)
    size = size or ICON_SIZE
    local img = icons[name]
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    -- No charicon: the class name, shrunk to fit the cell.
    love.graphics.setColor(1, 1, 1, alpha or 1)
    common.printCentered(font, displayName(name), x, y, size, size)
end

-- Lowest-index empty party slot, or nil when the party is full.
local function firstFreeSlot()
    for s = 1, PARTY_SLOTS do
        if not party[s] then return s end
    end
    return nil
end

-- Save lookup for a character's level / base stats (nil-safe).
local function charRecord(name)
    local uc = saveData_ref and saveData_ref.unlockedCharacters
    if not uc then return nil end
    return uc[name]
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
    for name, rec in pairs(uc) do
        if rec.recruited and not inParty[name] then   -- unrecruited heroes are hired in the SHOP
            roster[#roster + 1] = name
        end
    end
    table.sort(roster)

    if not assetsLoaded then
        assetsLoaded = true
        font = common.loadFont(14)
    end
    -- Load any icons not yet cached (handles new characters across save slots)
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    hoveredBack    = false
    pressedItem    = nil
    hoveredChar    = nil
    hoveredInParty = false
    hoveredRect    = nil

    local ix, iy = getPartySlotRect(1)
    common.initBox(box, ix - BOX_PAD, iy - BOX_PAD, ICON_SIZE + BOX_PAD * 2, ICON_SIZE + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    -- Hover detection
    hoveredBack = false
    if common.overBack(vmx, vmy) then
        hoveredBack = true
        common.setBoxTarget(box, common.backBoxRect())
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
            if vmx >= rx and vmx < rx + ROSTER_CELL_W and vmy >= ry and vmy < ry + ROSTER_CELL_H then
                common.setBoxTarget(box, rx - BOX_PAD, ry - BOX_PAD, ROSTER_CELL_W + BOX_PAD * 2, ROSTER_CELL_H + BOX_PAD * 2)
                break
            end
        end
    end

    common.updateBox(box, dt)

    -- Track hovered character for the tooltip (hover only).
    hoveredChar = nil
    hoveredInParty = false
    hoveredRect = nil
    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            hoveredChar = party[i]
            hoveredInParty = party[i] ~= nil
            if hoveredChar then hoveredRect = {x = sx, y = sy, w = sw, h = sh} end
            break
        end
    end
    if not hoveredChar then
        for idx = 1, #roster do
            local rx, ry, rw, rh = getRosterCellRect(idx)
            if vmx >= rx and vmx < rx + rw and vmy >= ry and vmy < ry + rh then
                hoveredChar = roster[idx]
                hoveredRect = {x = rx, y = ry, w = rw, h = rh}
                break
            end
        end
    end
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    -- BACK (acts on release).
    if common.overBack(vmx, vmy) then
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
        local rx, ry, rw, rh = getRosterCellRect(idx)
        if vmx >= rx and vmx < rx + rw and vmy >= ry and vmy < ry + rh then
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

-- Hover tooltip for the hovered hero: name / level and stats / where they are.
local function drawTooltip()
    if not hoveredChar or not hoveredRect then return end
    local rec   = charRecord(hoveredChar)
    local stats = require("progression").heroStats(saveData_ref, hoveredChar)
    common.drawTooltip({
        { text = displayName(hoveredChar), size = 16, color = OFFRED },
        { text = ("Lv %d    ATK %s    DEF %s    HP %s"):format((rec and rec.level) or 1,
              stats and tostring(stats.ATK) or "?", stats and tostring(stats.DEF) or "?",
              stats and tostring(stats.maxHP) or "?"), color = WHITE },
        { text = hoveredInParty and "IN PARTY - click to remove"
                                 or "RESERVE - click to add", color = CRIMSON },
    }, hoveredRect)
end

-- A white frame with a crimson inner line, and a caption above its top-left corner.
local function drawFrame(caption, x, y, w, h)
    love.graphics.setFont(font)
    love.graphics.setColor(CRIMSON)
    love.graphics.print(caption, x, y - LABEL_H)
    love.graphics.setColor(WHITE)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setColor(CRIMSON)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 3, y + 3, w - 6, h - 6)
end

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Top bar
    common.drawTopBar("PARTY", pressedItem == "back")

    -- 3. Active party: portraits, slot numbers underneath.
    drawFrame("ACTIVE", PARTY_FRAME_X, PARTY_FRAME_Y, PARTY_FRAME_W, PARTY_FRAME_H)

    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)

        -- Portrait background: dim black, crimson edge.
        love.graphics.setColor(0.05, 0.02, 0.02, 1)
        love.graphics.rectangle("fill", sx, sy, ICON_SIZE, ICON_SIZE)
        love.graphics.setColor(CRIMSON)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", sx, sy, ICON_SIZE, ICON_SIZE)

        if party[i] then
            drawIcon(party[i], sx, sy)
        end

        -- Slot number in the band below the portrait
        local lbl = tostring(i)
        love.graphics.setFont(font)
        love.graphics.setColor(CRIMSON)
        love.graphics.print(lbl, sx + (ICON_SIZE - font:getWidth(lbl)) / 2,
            sy + ICON_SIZE + 5)
    end

    -- 4. Reserve grid (BH 6x2).
    drawFrame("RESERVES", ROSTER_X, ROSTER_Y, ROSTER_OUTER_W, ROSTER_OUTER_H)

    -- Unlocked, not-active characters fill the grid; the remaining cells are
    -- locked/dim (BH shows the full 12-slot grid).
    for idx = 1, ROSTER_COLS * ROSTER_ROWS do
        local rx, ry = getRosterCellRect(idx)
        local name = roster[idx]
        love.graphics.setColor(0.04, 0.02, 0.02, 1)
        love.graphics.rectangle("fill", rx, ry, ROSTER_CELL_W, ROSTER_CELL_H)
        love.graphics.setColor(name and CRIMSON or {0.20, 0.05, 0.06, 1})
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", rx, ry, ROSTER_CELL_W, ROSTER_CELL_H)
        if name then
            drawIcon(name, rx, ry)
        end
    end

    -- 5. Animated following red box (drawn white when BACK is pressed)
    common.drawBox(box, pressedItem == "back")
    common.drawBackButton(pressedItem == "back")

    -- 7. Hover tooltip (name / Lv / ATK / DEF), anchored to the hovered cell
    drawTooltip()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

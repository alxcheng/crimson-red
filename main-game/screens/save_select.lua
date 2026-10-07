-- screens/save_select.lua — Save Select screen module
--
-- Layout (Battleheart-style): full-width stacked rows, one per save slot.
-- No permanent box per row — the animated red hover box is the only
-- per-row indicator. Row left = SLOT N + description, row right = DELETE
-- (non-empty slots only). Clicking a row selects/starts the slot.

local common = require("common")
local save   = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local SLOT_COUNT  = 5

-- Rows are full-width bands, evenly spaced, vertically centered as a group.
local ROW_MARGIN_X = 40
local ROW_W        = VW - ROW_MARGIN_X * 2
local ROW_H        = 60
local ROW_GAP      = 10
local ROW_TOTAL_H  = SLOT_COUNT * ROW_H + (SLOT_COUNT - 1) * ROW_GAP
local ROW_START_Y  = math.floor((VH - ROW_TOTAL_H) / 2)

-- DELETE button: separate small bordered button, right-aligned in its row.
local DEL_BTN_W = 76
local DEL_BTN_H = 22
local DEL_BTN_PAD = 6   -- gap between the button's right edge and the row's right edge

local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local A_H     = common.ARROW_H
local A_W     = common.ARROW_W
local BOX_PAD = 5

-- Item index map (shared by hover, hit-rect, box-target and release):
--   1        = back arrow
--   2 .. 6   = rows 1..5          (index 2+si-1)
--   7 .. 11  = delete 1..5        (index 7+si-1)
local ITEM_COUNT = 11

local function rowRect(si)
    return ROW_MARGIN_X, ROW_START_Y + (si - 1) * (ROW_H + ROW_GAP), ROW_W, ROW_H
end

local function delBtnRect(si)
    local _, ry = rowRect(si)
    return VW - ROW_MARGIN_X - DEL_BTN_PAD - DEL_BTN_W, ry + (ROW_H - DEL_BTN_H) / 2,
           DEL_BTN_W, DEL_BTN_H
end

local function getBoxTarget(i)
    if i == 1 then
        return AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD*2, A_H + BOX_PAD*2
    elseif i <= 6 then
        local sx, sy, sw, sh = rowRect(i - 1)
        return sx, sy, sw, sh
    else
        local bx, by, bw, bh = delBtnRect(i - 6)
        return bx - BOX_PAD, by - BOX_PAD, bw + BOX_PAD*2, bh + BOX_PAD*2
    end
end

local function getHitRect(i)
    if i == 1 then
        return AX, AY, A_W, A_H
    elseif i <= 6 then
        return rowRect(i - 1)
    else
        return delBtnRect(i - 6)
    end
end

-- ============================================================================
-- FLOOR NAMES
-- ============================================================================

local FLOOR_NAMES = {
    [1] = "DARK FOREST",
}

local function floorLabel(floor)
    local n = math.floor(tonumber(floor) or 1)
    local name = FLOOR_NAMES[n]
    return name and ("FLOOR " .. n .. " \195\150 " .. name) or ("FLOOR " .. n)
end

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn

local labelFont, descFont, smallFont
local hoveredItem = nil
local pressedItem = nil
local box         = common.newBox()

local saveSlots = {}  -- rebuilt in onEnter from disk

local function partySummary(data)
    local party = data.partyOrder or {}
    local names = {}
    for _, name in ipairs(party) do
        if type(name) == "string" then
            local uc = data.unlockedCharacters and data.unlockedCharacters[name]
            local lv = uc and uc.level or 1
            names[#names+1] = string.upper(name) .. " " .. lv
        end
    end
    -- Keep the summary concise: at most the first 3 party members.
    if #names > 3 then
        return table.concat({names[1], names[2], names[3]}, " · ") .. " +"
    end
    return table.concat(names, " · ")
end

local function loadSlotInfo()
    saveSlots = {}
    for i = 1, SLOT_COUNT do
        if save.exists(i) then
            local data = save.load(i)
            if data then
                saveSlots[i] = {
                    empty   = false,
                    floor   = math.floor(tonumber(data.floor) or 1),
                    summary = partySummary(data),
                }
            else
                saveSlots[i] = {empty = true}
            end
        else
            saveSlots[i] = {empty = true}
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
    require("music_mgr").stop()

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    if not labelFont then
        labelFont = common.loadFont(16)
        descFont  = common.loadFont(13)
        smallFont = common.loadFont(11)
    end

    loadSlotInfo()
    hoveredItem = nil
    pressedItem = nil

    local bx, by, bw, bh = getBoxTarget(2)
    common.initBox(box, bx, by, bw, bh)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    hoveredItem = nil
    for i = 1, ITEM_COUNT do
        -- DELETE buttons only exist on non-empty rows.
        if i > 6 and (saveSlots[i-6] or {}).empty then goto nextItem end
        local hx, hy, hw, hh = getHitRect(i)
        if vmx >= hx and vmx <= hx+hw and vmy >= hy and vmy <= hy+hh then
            hoveredItem = i; break
        end
        ::nextItem::
    end

    if hoveredItem then
        local tx, ty, tw, th = getBoxTarget(hoveredItem)
        common.setBoxTarget(box, tx, ty, tw, th)
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
        local item = pressedItem
        pressedItem = nil
        if item == 1 then
            common.playClickSound()
            switchFn("title")
        elseif item <= 6 then
            common.playClickSound()
            local si = item - 1
            local data = save.exists(si) and save.load(si) or nil
            if not data then
                data = save.defaultData()
                save.write(si, data)
            end
            switchFn("map", data, si)
        else
            local si = item - 6
            save.delete(si)
            loadSlotInfo()
        end
    end
end

function M.keypressed(key)
    if key == "escape" then switchFn("title") end
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Red hover/press box (the only row indicator)
    common.drawBox(box, pressedItem ~= nil)

    -- Back arrow
    common.drawBackArrow(pressedItem == 1)

    -- Rows
    for si = 1, SLOT_COUNT do
        local slot = saveSlots[si] or {empty = true}
        local item = si + 1
        local rx, ry = rowRect(si)

        -- SLOT N
        love.graphics.setFont(labelFont)
        common.setItemColor(pressedItem == item)
        love.graphics.print("SLOT " .. si, rx + 10, ry + (ROW_H - labelFont:getHeight()) / 2)

        if slot.empty then
            -- EMPTY prompt, accent red (white when the row is pressed)
            love.graphics.setFont(descFont)
            love.graphics.setColor(pressedItem == item and 1 or 0.85, 0, 0, 1)
            love.graphics.print("EMPTY", rx + 90, ry + (ROW_H - descFont:getHeight()) / 2)
        else
            -- Floor, then party summary
            love.graphics.setFont(descFont)
            common.setItemColor(pressedItem == item)
            love.graphics.print(floorLabel(slot.floor), rx + 90, ry + 9)

            love.graphics.setFont(smallFont)
            local summary = slot.summary or ""
            if pressedItem == item then
                love.graphics.setColor(0, 0, 0, 1)
            else
                love.graphics.setColor(0.75, 0.75, 0.75, 1)
            end
            love.graphics.print(summary, rx + 90, ry + 32)
        end
    end

    -- DELETE buttons (non-empty rows only)
    for si = 1, SLOT_COUNT do
        local slot = saveSlots[si] or {empty = true}
        if not slot.empty then
            local item = si + 6
            local bx, by = delBtnRect(si)
            local isPressed = pressedItem == item
            love.graphics.setLineWidth(1)
            love.graphics.setColor(isPressed and 0.85 or 0.5, 0, 0, 1)
            love.graphics.rectangle("line", bx, by, DEL_BTN_W, DEL_BTN_H)
            local lbl = "DELETE"
            love.graphics.setFont(smallFont)
            common.setItemColor(isPressed)
            local tw = smallFont:getWidth(lbl)
            local th = smallFont:getHeight()
            love.graphics.print(lbl, bx + (DEL_BTN_W - tw) / 2, by + (DEL_BTN_H - th) / 2)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

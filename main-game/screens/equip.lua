-- screens/equip.lua — EQUIP screen (BH's "Armory").
--
-- Pick a hero from the party strip, then move items between the shared
-- inventory (saveData.inventory) and the hero's three gear slots
-- (weapon / armor / trinket — saveData.unlockedCharacters[name].equipped).
--
-- Clicks:
--   * a party hero            -> select them (shows their gear and stats)
--   * an inventory item       -> select it (description bar shows it)
--   * a gear slot, with an item selected -> equip it there, if it is that
--     slot's type and the hero's class may use it (items.canUse). Whatever
--     was in the slot goes back to the inventory.
--   * an occupied gear slot, nothing selected -> unequip to the inventory
-- The save is written on exit.

local common = require("common")
local save   = require("save")
local progression = require("progression")

local items  = require("items")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT (800x450 virtual px)
-- ============================================================================

local TOP_BAR_H    = 40
local DESC_BAR_H   = 60
local CONTENT_TOP  = TOP_BAR_H
local CONTENT_BOT  = VH - DESC_BAR_H

-- Active party strip (top bar): 4 character chips
local PARTY_CHIPS    = 4
local CHIP_SIZE      = 28
local CHIP_GAP       = 10
local CHIP_TOTAL_W   = PARTY_CHIPS * CHIP_SIZE + (PARTY_CHIPS - 1) * CHIP_GAP
local CHIP_X         = 70
local CHIP_Y         = math.floor((TOP_BAR_H - CHIP_SIZE) / 2)

-- Left/center: selected character panel
local CHAR_PANEL_X   = 20
local CHAR_PANEL_Y   = 55
local CHAR_PANEL_W   = 270
local CHAR_PANEL_H   = CONTENT_BOT - CHAR_PANEL_Y - 10

local PORTRAIT_SIZE  = 110
local PORTRAIT_X     = CHAR_PANEL_X + 14
local PORTRAIT_Y     = CHAR_PANEL_Y + 22

-- Equipment rail (3 slots stacked vertically below the portrait)
local SLOT_SIZE      = 54
local SLOT_GAP       = 10
local SLOT_X         = CHAR_PANEL_X + 14
local SLOT_Y0        = PORTRAIT_Y + PORTRAIT_SIZE + 8
local SLOT_LABEL_W   = CHAR_PANEL_W - SLOT_X + CHAR_PANEL_X - 14 - SLOT_SIZE - 14

-- Stats readout (right of the portrait, under the name / level)
local STATS_X        = PORTRAIT_X + PORTRAIT_SIZE + 12
local STATS_Y        = PORTRAIT_Y + 46

-- Right: inventory grid
local INV_X          = 310
local INV_Y          = 55
local INV_W          = 470
local INV_H          = CONTENT_BOT - INV_Y - 10
local INV_COLS       = 6
local INV_ROWS       = 4
local INV_CELL       = 64
local INV_PAD        = 10
local INV_GRID_W     = INV_COLS * INV_CELL
local INV_GRID_H     = INV_ROWS * INV_CELL
local INV_GRID_X     = INV_X + math.floor((INV_W - INV_GRID_W) / 2)
local INV_GRID_Y     = INV_Y + math.floor((INV_H - INV_GRID_H) / 2)

-- Bottom description bar
local DESC_Y         = VH - DESC_BAR_H

local BOX_PAD = 5

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local party        = {}     -- [1..4] charName or nil (from partyOrder)
local selectedChar = nil    -- charName currently being edited
local icons        = {}     -- { [charName] = Image }

local selectedItemId = nil  -- inventory item id currently "held" (if any)
local hoveredItemId  = nil  -- inventory item id under cursor
local hoveredChar    = nil  -- party char under cursor (top strip)
local hoveredSlot    = nil  -- "weapon"|"armor"|"trinket" under cursor
local hoveredBack    = false

local pressedItem = nil     -- {zone=..., ...} while mouse is down
local box          = common.newBox()

local assetsLoaded = false
local font16, font14, fontTitle

-- ============================================================================
-- DATA HELPERS
-- ============================================================================

-- Build the ordered active-party list from saveData.partyOrder.
local function loadParty()
    party = {}
    local po = saveData_ref.partyOrder or {}
    for i = 1, PARTY_CHIPS do
        local name = po[i]
        if type(name) == "string" then
            party[i] = name
        end
    end
end

local function getCharData(name)
    local uc = saveData_ref.unlockedCharacters or {}
    return uc[name]
end

-- Ensure .equipped has the 3 contract keys (defensive against old saves
-- whose equipped is {} — see save.lua defaultChar).
local function getEquipped(name)
    local cd = getCharData(name)
    if not cd then return nil end
    cd.equipped = cd.equipped or {}
    cd.equipped.weapon  = cd.equipped.weapon  -- may be nil
    cd.equipped.armor   = cd.equipped.armor
    cd.equipped.trinket = cd.equipped.trinket
    return cd.equipped
end

local function getInventory()
    saveData_ref.inventory = saveData_ref.inventory or {}
    return saveData_ref.inventory
end

local function getItems()
    saveData_ref.items = saveData_ref.items or {}
    return saveData_ref.items
end

-- Remove an item id from the inventory array (first match). Returns true if removed.
local function removeFromInventory(id)
    if not id then return false end
    local inv = getInventory()
    for i, v in ipairs(inv) do
        if v == id then
            table.remove(inv, i)
            return true
        end
    end
    return false
end

-- Append an item id to the inventory array.
local function addToInventory(id)
    if not id then return end
    getInventory()[#getInventory() + 1] = id
end

-- Displayed stats for a hero, gear and talents included.
local function computeCharStats(name)
    local st = progression.heroStats(saveData_ref, name)
    if not st then return { atk = 0, def = 0, hp = 0 } end
    return { atk = st.ATK, def = st.DEF, hp = st.maxHP }
end

-- ============================================================================
-- EQUIP / UNEQUIP
-- ============================================================================

local SLOTS = {
    { key = "weapon",  label = "WEAPON" },
    { key = "armor",   label = "ARMOR"  },
    { key = "trinket", label = "TRINKET" },
}

-- Equip an inventory item (by id) into a slot on the selected character.
-- Returns true if any change was made.
local function equipItem(itemId, slotKey)
    local id = itemId
    if not id then return false end
    local inst = getItems()[id]
    if type(inst) ~= "table" then return false end

    -- Wrong slot for this item, or a class that cannot use it (BH usableBy).
    if inst.itemType ~= slotKey then return false end
    if not items.canUse(inst, selectedChar) then return false end

    local eq = getEquipped(selectedChar)
    local prevId = eq[slotKey]
    eq[slotKey] = id
    removeFromInventory(id)
    if prevId and prevId ~= id then
        addToInventory(prevId)
    end
    if selectedItemId == id then selectedItemId = nil end
    return true
end

-- Unequip a slot on the selected character: the item returns to inventory.
local function unequipItem(slotKey)
    local eq = getEquipped(selectedChar)
    local id = eq[slotKey]
    if not id then return false end
    eq[slotKey] = nil
    addToInventory(id)
    return true
end

-- ============================================================================
-- LAYOUT HELPERS
-- ============================================================================

local function chipRect(i)
    return CHIP_X + (i - 1) * (CHIP_SIZE + CHIP_GAP), CHIP_Y, CHIP_SIZE, CHIP_SIZE
end

local function slotRect(i)
    local x = SLOT_X
    local y = SLOT_Y0 + (i - 1) * (SLOT_SIZE + SLOT_GAP)
    return x, y, SLOT_SIZE, SLOT_SIZE
end

local function invCellRect(idx)
    local col = (idx - 1) % INV_COLS
    local row = math.floor((idx - 1) / INV_COLS)
    return INV_GRID_X + col * INV_CELL,
           INV_GRID_Y + row * INV_CELL,
           INV_CELL, INV_CELL
end

-- ============================================================================
-- HIT TESTING
-- ============================================================================

local function detectHover(vmx, vmy)
    hoveredChar   = nil
    hoveredSlot   = nil
    hoveredItemId = nil
    hoveredBack   = false

    local AX = common.ARROW_X
    local AY = common.ARROW_Y
    local AW = common.ARROW_W
    local AH = common.ARROW_H
    if vmx >= AX and vmx < AX + AW and vmy >= AY and vmy < AY + AH then
        hoveredBack = true
        return "back"
    end

    for i = 1, PARTY_CHIPS do
        local cx, cy, cw, ch = chipRect(i)
        if party[i] and vmx >= cx and vmx < cx + cw and vmy >= cy and vmy < cy + ch then
            hoveredChar = party[i]
            return "chip"
        end
    end

    if selectedChar then
        for i, s in ipairs(SLOTS) do
            local sx, sy, sw, sh = slotRect(i)
            if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
                hoveredSlot = s.key
                return "slot"
            end
        end
    end

    for idx, id in ipairs(getInventory()) do
        local ix, iy, iw, ih = invCellRect(idx)
        if vmx >= ix and vmx < ix + iw and vmy >= iy and vmy < iy + ih then
            hoveredItemId = id
            return "inv"
        end
    end

    return nil
end

-- ============================================================================
-- EXIT
-- ============================================================================

local function exit()
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

    if not assetsLoaded then
        assetsLoaded = true
        font16    = common.loadFont(16)
        font14    = common.loadFont(14)
        fontTitle = common.loadFont(20)
    end

    -- Load any character icons not yet cached.
    local uc = saveData.unlockedCharacters or {}
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    loadParty()

    -- Default selection: first party member, or the first unlocked char.
    selectedChar = nil
    for i = 1, PARTY_CHIPS do
        if party[i] then selectedChar = party[i]; break end
    end
    if not selectedChar then
        local uc = saveData.unlockedCharacters or {}
        for name in pairs(uc) do selectedChar = name; break end
    end

    selectedItemId = nil
    hoveredItemId  = nil
    hoveredChar    = nil
    hoveredSlot    = nil
    hoveredBack    = false
    pressedItem    = nil

    -- Snap box to the first party chip (or the back arrow if no party).
    if party[1] then
        local cx, cy, cw, ch = chipRect(1)
        common.initBox(box, cx - BOX_PAD, cy - BOX_PAD, cw + BOX_PAD * 2, ch + BOX_PAD * 2)
    else
        local AX = common.ARROW_X
        local AY = common.ARROW_Y
        common.initBox(box, AX - BOX_PAD, AY - BOX_PAD,
                       common.ARROW_W + BOX_PAD * 2, common.ARROW_H + BOX_PAD * 2)
    end
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()
    local zone = detectHover(vmx, vmy)

    local newKey = nil
    if zone == "back" then
        newKey = "back"
        local AX = common.ARROW_X
        local AY = common.ARROW_Y
        common.setBoxTarget(box, AX - BOX_PAD, AY - BOX_PAD,
                            common.ARROW_W + BOX_PAD * 2, common.ARROW_H + BOX_PAD * 2)
    elseif zone == "chip" then
        newKey = "chip:" .. (hoveredChar or "")
        for i = 1, PARTY_CHIPS do
            if party[i] == hoveredChar then
                local cx, cy, cw, ch = chipRect(i)
                common.setBoxTarget(box, cx - BOX_PAD, cy - BOX_PAD, cw + BOX_PAD * 2, ch + BOX_PAD * 2)
                break
            end
        end
    elseif zone == "slot" then
        newKey = "slot:" .. (hoveredSlot or "")
        for i, s in ipairs(SLOTS) do
            if s.key == hoveredSlot then
                local sx, sy, sw, sh = slotRect(i)
                common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, sw + BOX_PAD * 2, sh + BOX_PAD * 2)
                break
            end
        end
    elseif zone == "inv" then
        newKey = "inv:" .. (hoveredItemId or "")
        for idx, id in ipairs(getInventory()) do
            if id == hoveredItemId then
                local ix, iy, iw, ih = invCellRect(idx)
                common.setBoxTarget(box, ix - BOX_PAD, iy - BOX_PAD, iw + BOX_PAD * 2, ih + BOX_PAD * 2)
                break
            end
        end
    end

    -- setBoxTarget already short-circuits when the target rect is unchanged,
    -- so the hover sound is naturally throttled across repeated frames.
    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local zone = detectHover(common.virtualMouse())
    if zone then
        pressedItem = {
            zone = zone,
            char = hoveredChar,
            slot = hoveredSlot,
            item = hoveredItemId,
            back = hoveredBack,
        }
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    if not pressedItem then return end
    local p = pressedItem
    pressedItem = nil

    if p.back then
        if hoveredBack then
            common.playClickSound()
            exit()
        end
        return
    end

    if p.zone == "chip" and p.char then
        selectedChar = p.char
        selectedItemId = nil
        common.playClickSound()
        return
    end

    if p.zone == "slot" and p.slot and selectedChar then
        local changed
        if selectedItemId then
            changed = equipItem(selectedItemId, p.slot)
        else
            changed = unequipItem(p.slot)
        end
        if changed then common.playClickSound() end
        return
    end

    if p.zone == "inv" and p.item then
        selectedItemId = (selectedItemId == p.item) and nil or p.item
        common.playClickSound()
        return
    end
end

function M.keypressed(key)
    if key == "escape" then
        exit()
    elseif key == "return" or key == "kpenter" then
        -- No-op: Enter is not used on this screen.
    end
end

-- onExit: changes are already persisted in saveData; save.write happens in
-- exit() before the switch. main.lua also calls onExit before onEnter of the
-- next screen, so this is a no-op guard for that path.
function M.onExit()
    if saveData_ref and slot_ref then
        save.write(slot_ref, saveData_ref)
    end
end

-- ============================================================================
-- DRAW HELPERS
-- ============================================================================

local GRADE_COLORS = {
    [1] = {0.55, 0.55, 0.55, 1},   -- low: grey
    [2] = {0.95, 0.55, 0.20, 1},   -- mid: orange
    [3] = {0.95, 0.20, 0.35, 1},   -- high: crimson
}

local SLOT_COLORS = {
    weapon  = {0.85, 0.85, 0.90, 1},
    armor   = {0.55, 0.75, 0.95, 1},
    trinket = {0.70, 0.90, 0.55, 1},
}

local function displayName(name)
    if not name then return "" end
    local parts = {}
    for part in name:gmatch("%S+") do
        parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2)
    end
    return table.concat(parts, " ")
end

local function drawCharIcon(name, x, y, size)
    local img = icons[name]
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    local label = displayName(name)
    local fw, fh = font16:getWidth(label), font16:getHeight()
    local scale = 1
    if fw > size - 4 then scale = (size - 4) / fw end
    love.graphics.setFont(font16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(label, x + (size - fw * scale) / 2, y + (size - fh * scale) / 2, 0, scale, scale)
end

-- Draw an item instance into a cell (icon glyph + grade tint border).
local function drawItemInCell(id, x, y, size)
    local inst = getItems()[id]
    if type(inst) ~= "table" then return end

    -- Grade tint border.
    local gc = GRADE_COLORS[inst.grade] or {0.55, 0.55, 0.55, 1}
    love.graphics.setColor(gc)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 2, y + 2, size - 4, size - 4)

    -- Item type glyph (letter) in the center, tinted by slot color.
    local GLYPHS = { weapon = "W", armor = "A", trinket = "T" }
    local glyph = GLYPHS[inst.itemType] or "?"
    love.graphics.setFont(font16)
    local gw, gh = font16:getWidth(glyph), font16:getHeight()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(glyph, x + (size - gw) / 2, y + (size - gh) / 2)
end

-- Dashed empty slot.
local function drawDashedSlot(x, y, size, label)
    love.graphics.setColor(0.55, 0.20, 0.25, 1)
    love.graphics.setLineWidth(1)
    local dash = 4
    local step = dash * 2
    -- Top
    local cx = x
    while cx < x + size do
        local endx = math.min(cx + dash, x + size)
        love.graphics.line(cx, y, endx, y)
        cx = cx + step
    end
    -- Bottom
    cx = x
    while cx < x + size do
        local endx = math.min(cx + dash, x + size)
        love.graphics.line(cx, y + size, endx, y + size)
        cx = cx + step
    end
    -- Left
    local cy = y
    while cy < y + size do
        local endy = math.min(cy + dash, y + size)
        love.graphics.line(x, cy, x, endy)
        cy = cy + step
    end
    -- Right
    cy = y
    while cy < y + size do
        local endy = math.min(cy + dash, y + size)
        love.graphics.line(x + size, cy, x + size, endy)
        cy = cy + step
    end

    love.graphics.setFont(font14)
    love.graphics.setColor(0.55, 0.20, 0.25, 1)
    local lw = font14:getWidth(label)
    love.graphics.print(label, x + (size - lw) / 2, y + (size - font14:getHeight()) / 2)
end

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Top bar
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, TOP_BAR_H, VW, TOP_BAR_H)

    common.drawBackArrow(pressedItem and pressedItem.back and hoveredBack)

    -- Title centered in the top bar (CR name for BH's Armory).
    love.graphics.setFont(fontTitle)
    local title = "EQUIP"
    local tw = fontTitle:getWidth(title)
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print(title, (VW - tw) / 2, math.floor((TOP_BAR_H - fontTitle:getHeight()) / 2))

    -- Active party strip (4 chips).
    for i = 1, PARTY_CHIPS do
        local cx, cy, cw, ch = chipRect(i)
        local name = party[i]
        if name then
            local isSel   = (name == selectedChar)
            local isHover = (name == hoveredChar)
            -- Chip background: white ring when selected, off-red hover, dim otherwise.
            if isSel then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", cx - 1, cy - 1, cw + 2, ch + 2)
            elseif isHover then
                love.graphics.setColor(0.85, 0.30, 0.35, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", cx - 1, cy - 1, cw + 2, ch + 2)
            else
                love.graphics.setColor(0.45, 0.15, 0.20, 1)
                love.graphics.setLineWidth(1)
                love.graphics.rectangle("line", cx, cy, cw, ch)
            end
            drawCharIcon(name, cx, cy, cw)
        else
            -- Empty party slot: dashed.
            drawDashedSlot(cx, cy, ch, "?")
        end
    end

    -- 3. Selected character panel (left/center)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", CHAR_PANEL_X, CHAR_PANEL_Y, CHAR_PANEL_W, CHAR_PANEL_H)

    if selectedChar then
        local cd = getCharData(selectedChar)
        -- Portrait
        love.graphics.setColor(0.10, 0.10, 0.10, 1)
        love.graphics.rectangle("fill", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
        drawCharIcon(selectedChar, PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE)

        -- Class name + level
        love.graphics.setFont(font16)
        local cname = displayName(selectedChar)
        local lvl   = cd and cd.level or 1
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(cname, PORTRAIT_X + PORTRAIT_SIZE + 12, PORTRAIT_Y + 2)
        love.graphics.setColor(common.COLOR_RED)
        love.graphics.print("Lv " .. tostring(lvl), PORTRAIT_X + PORTRAIT_SIZE + 12, PORTRAIT_Y + 20)

        -- Equipment rail (3 slots)
        local eq = getEquipped(selectedChar)
        for i, s in ipairs(SLOTS) do
            local sx, sy, sw, sh = slotRect(i)
            local id = eq and eq[s.key]
            if id then
                drawItemInCell(id, sx, sy, sw)
            else
                drawDashedSlot(sx, sy, sh, s.label:sub(1, 1))
            end
            -- Slot label to the right of the slot
            love.graphics.setFont(font14)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(s.label, sx + sw + 8, sy + (sh - font14:getHeight()) / 2)
        end

        -- Stats readout (right of the portrait)
        local st = computeCharStats(selectedChar)
        local statLines = {
            { label = "ATK",  value = st.atk,  color = {0.95, 0.55, 0.20, 1} },
            { label = "DEF",  value = st.def,  color = {0.55, 0.75, 0.95, 1} },
            { label = "HP",   value = st.hp,   color = {0.85, 0.30, 0.35, 1} },
        }
        love.graphics.setFont(font16)
        for i, line in ipairs(statLines) do
            local ly = STATS_Y + (i - 1) * 22
            love.graphics.setColor(line.color)
            love.graphics.print(line.label, STATS_X, ly)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(tostring(line.value), STATS_X + 44, ly)
        end
    else
        -- No selected character (empty party / no unlocked chars)
        love.graphics.setFont(font16)
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        love.graphics.print("No character", CHAR_PANEL_X + 14, CHAR_PANEL_Y + 14)
    end

    -- 4. Inventory grid (right)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", INV_X, INV_Y, INV_W, INV_H)

    love.graphics.setFont(font16)
    local invTitle = "INVENTORY"
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print(invTitle, INV_X + 12, INV_Y + 8)

    -- Grid cell outlines
    love.graphics.setColor(0.35, 0.35, 0.35, 1)
    love.graphics.setLineWidth(1)
    for idx = 1, INV_COLS * INV_ROWS do
        local ix, iy, iw, ih = invCellRect(idx)
        love.graphics.rectangle("line", ix, iy, iw, ih)
    end

    -- Items in inventory
    local inv = getInventory()
    for idx, id in ipairs(inv) do
        if idx > INV_COLS * INV_ROWS then break end
        local ix, iy, iw, ih = invCellRect(idx)
        drawItemInCell(id, ix, iy, math.min(iw, ih))
        -- Highlight: selected item gets a white ring.
        if id == selectedItemId then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", ix - 1, iy - 1, iw + 2, ih + 2)
        end
    end

    if #inv == 0 then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("Empty", INV_X + (INV_W - font14:getWidth("Empty")) / 2,
                            INV_Y + (INV_H - font14:getHeight()) / 2)
    end

    -- 5. Bottom description bar (parchment-style: dark with red border)
    love.graphics.setColor(0.05, 0.03, 0.03, 1)
    love.graphics.rectangle("fill", 0, DESC_Y, VW, DESC_BAR_H)
    love.graphics.setColor(0.6, 0.15, 0.20, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(0, DESC_Y, VW, DESC_Y)

    local descId = selectedItemId or hoveredItemId
    local descInst = descId and getItems()[descId]
    if type(descInst) == "table" then
        love.graphics.setFont(font16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(descInst.name or "(unnamed)", 12, DESC_Y + 6)

        love.graphics.setFont(font14)
        love.graphics.setColor(0.75, 0.75, 0.75, 1)
        love.graphics.print(descInst.desc or tostring(descInst.itemType or "?"), 12, DESC_Y + 26)

        -- What it adds, and whether the selected hero can use it.
        local modParts = {}
        for k, v in pairs(descInst.mods or {}) do
            modParts[#modParts + 1] = "+" .. tostring(v) .. " " .. k
        end
        table.sort(modParts)
        local line = table.concat(modParts, ", ")
        local usable = selectedChar == nil or items.canUse(descInst, selectedChar)
        if not usable then line = line .. "   (" .. displayName(selectedChar) .. " cannot use this)" end
        love.graphics.setColor(usable and {0.95, 0.55, 0.20, 1} or {0.85, 0.30, 0.35, 1})
        love.graphics.print(line, 12, DESC_Y + 42)

        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        local sellStr = "sells for " .. tostring(items.sellValue(descInst))
        love.graphics.print(sellStr, VW - font14:getWidth(sellStr) - 12, DESC_Y + 8)
    else
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("Select an item to see details.", 12, DESC_Y + (DESC_BAR_H - font14:getHeight()) / 2)
    end

    -- 6. Red hover box (drawn on top)
    local boxPressed = (pressedItem ~= nil and pressedItem.back and hoveredBack)
    common.drawBox(box, boxPressed)

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

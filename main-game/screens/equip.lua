-- screens/equip.lua — EQUIP screen (BH's "Armory").
--
-- Pick a hero from the party strip, then move items between the shared
-- inventory (saveData.inventory) and the hero's three gear slots
-- (weapon / armor / trinket — saveData.unlockedCharacters[name].equipped).
--
-- Clicks:
--   * a party hero            -> select them (shows their gear and stats)
--   * an inventory item       -> select it (white ring)
--   * a gear slot, with an item selected -> equip it there, if it is that
--     slot's type and the hero's class may use it (items.canUse). Whatever
--     was in the slot goes back to the inventory.
--   * an occupied gear slot, nothing selected -> unequip to the inventory
-- Hovering an item (in the inventory or in a gear slot) shows its details in a
-- tooltip. The save is written on exit.

local common = require("common")
local save   = require("save")
local progression = require("progression")

local items  = require("items")
local item_ui = require("item_ui")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT (800x450 virtual px)
-- ============================================================================

local TOP_BAR_H = common.TOP_BAR_H
local MARGIN    = 20
local BOX_PAD   = common.BOX_PAD
local PANEL_Y   = TOP_BAR_H + 12
local PANEL_H   = VH - MARGIN - PANEL_Y
local PAD       = 14                          -- padding inside a panel

-- Left panel: party chips, the selected hero, their three gear slots
local CHAR_PANEL_X = MARGIN
local CHAR_PANEL_Y = PANEL_Y
local CHAR_PANEL_W = 270
local CHAR_PANEL_H = PANEL_H

local PARTY_CHIPS  = 4
local CHIP_SIZE    = 48
local CHIP_GAP     = math.floor((CHAR_PANEL_W - PAD * 2 - PARTY_CHIPS * CHIP_SIZE) / (PARTY_CHIPS - 1))
local CHIP_X       = CHAR_PANEL_X + PAD
local CHIP_Y       = CHAR_PANEL_Y + PAD
local DIVIDER_Y    = CHIP_Y + CHIP_SIZE + 12

local PORTRAIT_SIZE = 96
local PORTRAIT_X    = CHAR_PANEL_X + PAD
local PORTRAIT_Y    = DIVIDER_Y + 12
local STATS_X       = PORTRAIT_X + PORTRAIT_SIZE + 14
local STATS_Y       = PORTRAIT_Y + 40

local SLOT_SIZE    = 48
local SLOT_GAP     = 12
local SLOT_X       = CHAR_PANEL_X + PAD
local SLOT_Y0      = PORTRAIT_Y + PORTRAIT_SIZE + 12
local SLOT_TEXT_X  = SLOT_X + SLOT_SIZE + 12
local SLOT_TEXT_W  = CHAR_PANEL_X + CHAR_PANEL_W - PAD - SLOT_TEXT_X

-- Right panel: the shared inventory panel (item_ui.lua).
local invCellRect = item_ui.invCellRect

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
local font16, font14, font13

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

-- ============================================================================
-- HIT TESTING
-- ============================================================================

local function detectHover(vmx, vmy)
    hoveredChar   = nil
    hoveredSlot   = nil
    hoveredItemId = nil
    hoveredBack   = false

    if common.overBack(vmx, vmy) then
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

    local invIdx = item_ui.invIndexAt(vmx, vmy, saveData_ref)
    if invIdx then
        hoveredItemId = getInventory()[invIdx]
        return "inv"
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
        font13    = common.loadFont(13)
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

    -- Snap box to the first party chip (or BACK if no party).
    if party[1] then
        local cx, cy, cw, ch = chipRect(1)
        common.initBox(box, cx - BOX_PAD, cy - BOX_PAD, cw + BOX_PAD * 2, ch + BOX_PAD * 2)
    else
        common.initBox(box, common.backBoxRect())
    end
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()
    local zone = detectHover(vmx, vmy)

    local newKey = nil
    if zone == "back" then
        newKey = "back"
        common.setBoxTarget(box, common.backBoxRect())
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

local RED     = {1, 0, 0, 1}

local displayName = common.titleCase

local function drawCharIcon(name, x, y, size)
    local img = icons[name]
    love.graphics.setColor(1, 1, 1, 1)
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    common.printCentered(font14, displayName(name), x, y, size, size)
end

-- Dashed empty slot.
local function drawDashedSlot(x, y, size, label)
    love.graphics.setColor(1, 0, 0, 1)
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

    love.graphics.setColor(RED)
    common.printCentered(font14, label, x, y, size, size)
end

-- Tooltip for the item under the mouse (inventory cell or gear slot) or the hovered hero chip.
local function drawHoverTooltip()
    if hoveredItemId then
        local inst = getItems()[hoveredItemId]
        for idx, id in ipairs(getInventory()) do
            if id == hoveredItemId and type(inst) == "table" then
                local x, y, w, h = invCellRect(idx)
                common.drawTooltip(item_ui.tooltipLines(inst, {
                    charName = selectedChar, price = { label = "Sells for", amount = items.sellValue(inst) } }),
                    { x = x, y = y, w = w, h = h })
                return
            end
        end
    elseif hoveredSlot and selectedChar then
        local eq = getEquipped(selectedChar)
        local inst = eq and eq[hoveredSlot] and getItems()[eq[hoveredSlot]]
        if type(inst) == "table" then
            for i, s in ipairs(SLOTS) do
                if s.key == hoveredSlot then
                    local x, y, w, h = slotRect(i)
                    local lines = item_ui.tooltipLines(inst)
                    lines[#lines + 1] = { text = "Click to unequip", color = item_ui.GREY }
                    common.drawTooltip(lines, { x = x, y = y, w = w, h = h })
                end
            end
        end
    elseif hoveredChar then
        for i = 1, PARTY_CHIPS do
            if party[i] == hoveredChar then
                local cd = getCharData(hoveredChar)
                local x, y, w, h = chipRect(i)
                common.drawTooltip({
                    { text = displayName(hoveredChar), size = 16, color = RED },
                    { text = "Lv " .. tostring(cd and cd.level or 1), color = common.COLOR_WHITE },
                }, { x = x, y = y, w = w, h = h })
            end
        end
    end
end

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Top bar
    local backPressed = pressedItem ~= nil and pressedItem.back and hoveredBack
    common.drawTopBar("EQUIP", backPressed)

    -- 3. Left panel
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", CHAR_PANEL_X, CHAR_PANEL_Y, CHAR_PANEL_W, CHAR_PANEL_H)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(CHAR_PANEL_X + PAD, DIVIDER_Y, CHAR_PANEL_X + CHAR_PANEL_W - PAD, DIVIDER_Y)

    -- Party chips: white ring = the hero being edited.
    for i = 1, PARTY_CHIPS do
        local cx, cy, cw, ch = chipRect(i)
        local name = party[i]
        if name then
            local isSel = (name == selectedChar)
            love.graphics.setColor(isSel and common.COLOR_WHITE or {1, 0, 0, 1})
            love.graphics.setLineWidth(isSel and 2 or 1)
            love.graphics.rectangle("line", cx, cy, cw, ch)
            drawCharIcon(name, cx, cy, cw)
        else
            drawDashedSlot(cx, cy, ch, "")
        end
    end

    if selectedChar then
        local cd = getCharData(selectedChar)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
        drawCharIcon(selectedChar, PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE)

        -- Name, level, stats to the right of the portrait.
        local textW = CHAR_PANEL_X + CHAR_PANEL_W - PAD - STATS_X
        love.graphics.setFont(font16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(common.fitText(font16, displayName(selectedChar), textW), STATS_X, PORTRAIT_Y)
        love.graphics.setColor(common.COLOR_RED)
        love.graphics.print("Lv " .. tostring(cd and cd.level or 1), STATS_X, PORTRAIT_Y + 18)

        local st = computeCharStats(selectedChar)
        local statLines = {
            { label = "ATK", value = st.atk, color = {1, 0, 0, 1} },
            { label = "DEF", value = st.def, color = {1, 1, 1, 1} },
            { label = "HP",  value = st.hp,  color = {1, 0, 0, 1} },
        }
        for i, line in ipairs(statLines) do
            local ly = STATS_Y + (i - 1) * 19
            love.graphics.setColor(line.color)
            love.graphics.print(line.label, STATS_X, ly)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(tostring(line.value), STATS_X + 44, ly)
        end

        -- Gear slots: the token, then the slot name and what is in it.
        local eq = getEquipped(selectedChar)
        for i, s in ipairs(SLOTS) do
            local sx, sy, sw, sh = slotRect(i)
            local inst = eq and eq[s.key] and getItems()[eq[s.key]]
            if type(inst) == "table" then
                item_ui.drawGlyph(inst, sx, sy, sw)
            else
                drawDashedSlot(sx, sy, sh, s.label:sub(1, 1))
            end
            love.graphics.setFont(font13)
            love.graphics.setColor(RED)
            love.graphics.print(s.label, SLOT_TEXT_X, sy + 7)
            love.graphics.setFont(font14)
            if type(inst) == "table" then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print(common.fitText(font14, inst.name or "(unnamed)", SLOT_TEXT_W), SLOT_TEXT_X, sy + 24)
            else
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print("empty", SLOT_TEXT_X, sy + 24)
            end
        end
    else
        love.graphics.setColor(1, 1, 1, 1)
        common.printCentered(font16, "No character", CHAR_PANEL_X, DIVIDER_Y, CHAR_PANEL_W, CHAR_PANEL_Y + CHAR_PANEL_H - DIVIDER_Y)
    end

    -- 4. Inventory panel, with what a click will do next as its hint.
    local selInst = selectedItemId and getItems()[selectedItemId]
    if type(selInst) == "table" then
        item_ui.drawInventory(saveData_ref, selectedItemId,
            "Now click the " .. tostring(selInst.itemType) .. " slot to equip it", RED)
    else
        item_ui.drawInventory(saveData_ref, nil, "Click an item, then its slot")
    end

    -- 5. Red hover box (white when BACK is pressed), BACK on top, tooltip last
    common.drawBox(box, backPressed)
    common.drawBackButton(backPressed)
    drawHoverTooltip()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

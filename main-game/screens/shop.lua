-- screens/shop.lua — SHOP screen (BH's "Merchant" + "Tavern").
--
-- Left panel, two tabs:
--   GEAR: up to items.SHOP_SLOTS items for sale (shopState.offers), as small
--         slots. Click one to select it, then BUY (at the bottom of the panel).
--   HIRE: one hero for hire (shopState.hireOffer). Hiring pays
--         progression.hireCost, recruits the hero with starter gear, and puts
--         them in the first free party slot (or leaves them in reserve).
-- Right panel: the party's inventory, the same panel as on the EQUIP screen
-- (item_ui.drawInventory). Click an item to select it, then SELL.
--
-- Rules (BH): buy at the item's value, sell for half; a bought slot stays empty
-- until the shop restocks; no buying with a full inventory; equipped items
-- cannot be sold here. Hovering any item shows its details in a tooltip.
--
-- Restock: on entry, if the shop was never stocked or a battle was won since
-- (shopState.pendingRestock), the stock and the hire are re-rolled
-- (items.rollOffers). Re-entering without a new win does not reshuffle.
--
-- On exit the save is written and the game returns to the map.

local common = require("common")
local save   = require("save")

local items       = require("items")
local item_ui     = require("item_ui")
local progression = require("progression")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT (800x450 virtual px) — the left panel mirrors the EQUIP screen's
-- ============================================================================

local TOP_BAR_H = common.TOP_BAR_H
local MARGIN    = 20
local BOX_PAD   = common.BOX_PAD
local PAD       = 14                         -- padding inside the panel

local PANEL_X   = MARGIN
local PANEL_Y   = TOP_BAR_H + 12
local PANEL_W   = 270
local PANEL_H   = VH - MARGIN - PANEL_Y
local INNER_W   = PANEL_W - PAD * 2

-- Tabs across the top of the panel
local TAB_GAP   = 10
local TAB_W     = math.floor((INNER_W - TAB_GAP) / 2)
local TAB_H     = 28
local TAB_Y     = PANEL_Y + PAD
local DIVIDER_Y = TAB_Y + TAB_H + 12

-- GEAR tab: 3 x 2 slots, each with its price underneath
local SLOT_COLS  = 3
local SLOT_SIZE  = 64                         -- same cell size as the inventory grid
local SLOT_GAP_X = math.floor((INNER_W - SLOT_COLS * SLOT_SIZE) / (SLOT_COLS - 1))
local SLOT_ROW_H = SLOT_SIZE + 24             -- cell + price line
local SLOT_Y0    = DIVIDER_Y + 14

-- Action button (BUY / SELL / HIRE) at the bottom of the panel; the selected
-- item's name sits just above it.
local BTN_H     = 36
local BTN_X     = PANEL_X + PAD
local BTN_W     = INNER_W
local BTN_Y     = PANEL_Y + PANEL_H - PAD - BTN_H
local DETAIL_Y  = BTN_Y - 46

-- HIRE tab: recruit portrait
local PORTRAIT_SIZE = 96
local PORTRAIT_X    = PANEL_X + PAD
local PORTRAIT_Y    = DIVIDER_Y + 14

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local tab          = "gear"   -- "gear" | "hire"
local selected     = nil      -- { kind = "offer", idx = n } | { kind = "inv", id = instanceId }
local hover        = {}       -- what the mouse is over this frame (see detectHover)
local pressedItem  = nil      -- copy of `hover` taken at mouse-down
local box          = common.newBox()
local recruitIcon  = { name = nil, img = nil }   -- cached portrait of the hero for hire

local font16, font14, font13

-- ============================================================================
-- DATA HELPERS
-- ============================================================================

local function getShopState()
    local sd = saveData_ref
    sd.shopState = sd.shopState or { offers = {}, hireOffer = nil, seeded = false }
    sd.shopState.offers = sd.shopState.offers or {}
    return sd.shopState
end

local function getInventory()
    saveData_ref.inventory = saveData_ref.inventory or {}
    return saveData_ref.inventory
end

local function itemOf(id)
    local inst = id and saveData_ref.items and saveData_ref.items[id]
    return type(inst) == "table" and inst or nil
end

local function goldValue() return saveData_ref.gold or 0 end

-- Lowest-index empty party slot (1..4), or nil if full.
local function firstFreePartySlot()
    local po = saveData_ref.partyOrder or {}
    for s = 1, 4 do
        if type(po[s]) ~= "string" then return s end
    end
    return nil
end

-- The selected thing as an item instance (nil if the selection went stale).
local function selectedItem()
    if not selected then return nil end
    if selected.kind == "offer" then return itemOf(getShopState().offers[selected.idx]) end
    for _, id in ipairs(getInventory()) do
        if id == selected.id then return itemOf(id) end
    end
    return nil
end

-- ============================================================================
-- RESTOCK
-- ============================================================================

-- shopState.offers is a FIXED-POSITION list: offers[i] is the instance id in
-- slot i, or false once it has been bought.
local function restockIfNeeded()
    local sd = saveData_ref
    local ss = getShopState()
    if ss.seeded and not ss.pendingRestock then return end

    -- Unsold offers from the previous stock are discarded with it.
    for _, oldId in ipairs(ss.offers) do
        if oldId then sd.items[oldId] = nil end
    end
    ss.offers = {}
    for _, bhId in ipairs(items.rollOffers(progression.highestLevel(sd))) do
        ss.offers[#ss.offers + 1] = items.mint(sd, bhId)
    end
    ss.hireOffer      = progression.rollHire(sd)
    ss.seeded         = true
    ss.pendingRestock = false
end

-- ============================================================================
-- TRANSACTIONS (all gold goes through the items API)
-- ============================================================================

local flash = { text = nil, t = 0 }   -- transient message ("NOT ENOUGH GOLD")

local function setFlash(text)
    flash.text, flash.t = text, 1.4
end

-- BUY the selected offer: pay its value, move it to the inventory, leave the slot empty.
local function buySelected()
    local ss, idx = getShopState(), selected.idx
    local id = ss.offers[idx]
    local inst = itemOf(id)
    if not inst then return end
    if items.inventoryFull(saveData_ref) then setFlash("INVENTORY FULL"); return end
    if not items.spendGold(saveData_ref, items.buyPrice(inst)) then setFlash("NOT ENOUGH GOLD"); return end
    ss.offers[idx] = false
    getInventory()[#getInventory() + 1] = id
    selected = nil
    common.playClickSound()
end

-- SELL the selected inventory item for half its value; it leaves the save.
local function sellSelected()
    local inst = selectedItem()
    if not inst then return end
    local inv = getInventory()
    for i, id in ipairs(inv) do
        if id == selected.id then
            table.remove(inv, i)
            items.addGold(saveData_ref, math.max(0, items.sellValue(inst)))
            saveData_ref.items[id] = nil
            break
        end
    end
    selected = nil
    common.playClickSound()
end

-- HIRE the offered hero: pay, recruit (level + starter gear), first free party
-- slot — or the reserves when the party is full.
local function hire()
    local ss = getShopState()
    local name = ss.hireOffer
    if not name then return end
    if not items.spendGold(saveData_ref, progression.hireCost(saveData_ref)) then
        setFlash("NOT ENOUGH GOLD")
        return
    end
    progression.recruit(saveData_ref, name)
    local slot = firstFreePartySlot()
    if slot then saveData_ref.partyOrder[slot] = name end
    ss.hireOffer = nil
    common.playClickSound()
end

-- What the action button does right now: nil (hidden) or
-- { verb = "BUY"|"SELL"|"HIRE", price = n, enabled = bool, run = fn }.
local function currentAction()
    if tab == "hire" then
        if not getShopState().hireOffer then return nil end
        local cost = progression.hireCost(saveData_ref)
        return { verb = "HIRE", price = cost, enabled = goldValue() >= cost, run = hire }
    end
    local inst = selectedItem()
    if not inst then return nil end
    if selected.kind == "offer" then
        local price = items.buyPrice(inst)
        return { verb = "BUY", price = price, run = buySelected,
                 enabled = goldValue() >= price and not items.inventoryFull(saveData_ref) }
    end
    return { verb = "SELL", price = items.sellValue(inst), enabled = true, run = sellSelected }
end

-- ============================================================================
-- LAYOUT HELPERS
-- ============================================================================

local function tabRect(which)
    local x = PANEL_X + PAD + ((which == "hire") and (TAB_W + TAB_GAP) or 0)
    return x, TAB_Y, TAB_W, TAB_H
end

local function offerSlotRect(idx)
    local col = (idx - 1) % SLOT_COLS
    local row = math.floor((idx - 1) / SLOT_COLS)
    return PANEL_X + PAD + col * (SLOT_SIZE + SLOT_GAP_X), SLOT_Y0 + row * SLOT_ROW_H, SLOT_SIZE, SLOT_SIZE
end

local function inside(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- ============================================================================
-- HIT TESTING
-- ============================================================================

-- Fills `hover` = { zone = "back"|"tab"|"offer"|"inv"|"button"|"recruit", ... } and
-- returns the rectangle the red box should surround (or nil).
local function detectHover(vmx, vmy)
    hover = {}
    if common.overBack(vmx, vmy) then
        hover.zone = "back"
        return common.backBoxRect()
    end
    for _, which in ipairs({ "gear", "hire" }) do
        local x, y, w, h = tabRect(which)
        if inside(vmx, vmy, x, y, w, h) then
            hover.zone, hover.tab = "tab", which
            return x - BOX_PAD, y - BOX_PAD, w + BOX_PAD * 2, h + BOX_PAD * 2
        end
    end
    if currentAction() and inside(vmx, vmy, BTN_X, BTN_Y, BTN_W, BTN_H) then
        hover.zone = "button"
        return BTN_X - BOX_PAD, BTN_Y - BOX_PAD, BTN_W + BOX_PAD * 2, BTN_H + BOX_PAD * 2
    end
    if tab == "gear" then
        for i = 1, items.SHOP_SLOTS do
            local x, y, w, h = offerSlotRect(i)
            if getShopState().offers[i] and inside(vmx, vmy, x, y, w, h) then
                hover.zone, hover.idx = "offer", i
                return x, y, w, h
            end
        end
        local invIdx = item_ui.invIndexAt(vmx, vmy, saveData_ref)
        if invIdx then
            hover.zone, hover.idx, hover.id = "inv", invIdx, getInventory()[invIdx]
            return item_ui.invCellRect(invIdx)
        end
    elseif getShopState().hireOffer
       and inside(vmx, vmy, PORTRAIT_X, PORTRAIT_Y, INNER_W, PORTRAIT_SIZE) then
        hover.zone = "recruit"
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

    font16 = common.loadFont(16)
    font14 = common.loadFont(14)
    font13 = common.loadFont(13)

    restockIfNeeded()

    tab         = "gear"
    selected    = nil
    hover       = {}
    pressedItem = nil
    flash.text, flash.t = nil, 0

    local tx, ty, tw, th = tabRect("gear")
    common.initBox(box, tx - BOX_PAD, ty - BOX_PAD, tw + BOX_PAD * 2, th + BOX_PAD * 2)
end

function M.update(dt)
    local x, y, w, h = detectHover(common.virtualMouse())
    if x then common.setBoxTarget(box, x, y, w, h) end
    common.updateBox(box, dt)
    if flash.t > 0 then flash.t = math.max(0, flash.t - dt) end
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    detectHover(common.virtualMouse())
    pressedItem = hover.zone and hover or nil
end

function M.mousereleased(x, y, button)
    if button ~= 1 or not pressedItem then return end
    local p = pressedItem
    pressedItem = nil
    detectHover(common.virtualMouse())
    if hover.zone ~= p.zone then return end          -- dragged off: no click

    if p.zone == "back" then
        common.playClickSound()
        exit()
    elseif p.zone == "tab" and hover.tab == p.tab then
        tab, selected = p.tab, nil
        common.playClickSound()
    elseif p.zone == "offer" and hover.idx == p.idx then
        local same = selected and selected.kind == "offer" and selected.idx == p.idx
        selected = (not same) and { kind = "offer", idx = p.idx } or nil
        common.playClickSound()
    elseif p.zone == "inv" and hover.id == p.id then
        local same = selected and selected.kind == "inv" and selected.id == p.id
        selected = (not same) and { kind = "inv", id = p.id } or nil
        common.playClickSound()
    elseif p.zone == "button" then
        local action = currentAction()
        if action then action.run() end
    end
end

function M.keypressed(key)
    if key == "escape" then
        exit()
    end
end

-- main.lua calls onExit before the next screen's onEnter; keep the save current.
function M.onExit()
    if saveData_ref and slot_ref then
        save.write(slot_ref, saveData_ref)
    end
end

-- ============================================================================
-- DRAW HELPERS
-- ============================================================================

local CRIMSON = {0.84, 0.07, 0.16, 1}
local OFFRED  = {1.00, 0.42, 0.42, 1}
local GOLD    = item_ui.GOLD
local GREY    = {0.5, 0.5, 0.5, 1}

local displayName = common.titleCase

-- Small drawn coin (the font has no coin glyph).
local function drawCoin(cx, cy, r)
    love.graphics.setColor(GOLD)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.70, 0.52, 0.10, 1)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", cx, cy, r - 2)
end

-- A coin and a number, centred on cx.
local function drawPrice(font, amount, cx, y, color)
    local str = tostring(amount)
    local w = 14 + font:getWidth(str)
    local x = math.floor(cx - w / 2)
    drawCoin(x + 5, y + font:getHeight() / 2, 5)
    love.graphics.setFont(font)
    love.graphics.setColor(color or GOLD)
    love.graphics.print(str, x + 14, y)
end

local function drawGoldDisplay()
    local str = tostring(math.floor(goldValue()))
    local w = font16:getWidth(str)
    local x = VW - MARGIN - w
    drawCoin(x - 10, math.floor(TOP_BAR_H / 2), 7)
    love.graphics.setFont(font16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(str, x, math.floor((TOP_BAR_H - font16:getHeight()) / 2))
end

local function drawTabs()
    for _, which in ipairs({ "gear", "hire" }) do
        local x, y, w, h = tabRect(which)
        if tab == which then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", x, y, w, h)
            love.graphics.setColor(CRIMSON)
        else
            love.graphics.setColor(0.45, 0.15, 0.20, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x, y, w, h)
        end
        common.printCentered(font16, which:upper(), x, y, w, h)
    end
end

-- The action button: a coin and "<VERB> <price>" centred; dimmed when it cannot be used.
local function drawActionButton()
    local action = currentAction()
    if not action then return end
    love.graphics.setColor(action.enabled and CRIMSON or {0.30, 0.10, 0.12, 1})
    love.graphics.rectangle("fill", BTN_X, BTN_Y, BTN_W, BTN_H)
    local label = action.verb .. " " .. tostring(action.price)
    local startX = math.floor(BTN_X + (BTN_W - (16 + font16:getWidth(label))) / 2)
    drawCoin(startX + 6, BTN_Y + BTN_H / 2, 6)
    love.graphics.setFont(font16)
    love.graphics.setColor(action.enabled and {1, 1, 1, 1} or {0.5, 0.4, 0.4, 1})
    love.graphics.print(label, startX + 16, math.floor(BTN_Y + (BTN_H - font16:getHeight()) / 2))
end

local function drawGearTab()
    local offers = getShopState().offers
    for i = 1, items.SHOP_SLOTS do
        local x, y, w, h = offerSlotRect(i)
        local inst = itemOf(offers[i])
        love.graphics.setColor(0.35, 0.35, 0.35, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h)
        if inst then
            item_ui.drawGlyph(inst, x + 6, y + 6, w - 12)
            local affordable = goldValue() >= items.buyPrice(inst)
            drawPrice(font13, items.buyPrice(inst), x + w / 2, y + h + 4, affordable and GOLD or GREY)
            if selected and selected.kind == "offer" and selected.idx == i then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2)
            end
        elseif offers[i] == false then
            love.graphics.setColor(0.4, 0.3, 0.3, 1)
            common.printCentered(font13, "SOLD", x, y, w, h)
        end
    end

    -- The selected item, named above the button.
    local inst = selectedItem()
    if inst then
        love.graphics.setFont(font14)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(common.fitText(font14, inst.name or "(unnamed)", INNER_W), PANEL_X + PAD, DETAIL_Y, INNER_W, "center")
        love.graphics.setFont(font13)
        love.graphics.setColor(item_ui.BONUS)
        love.graphics.printf(common.fitText(font13, item_ui.modsText(inst), INNER_W), PANEL_X + PAD, DETAIL_Y + 18, INNER_W, "center")
    else
        love.graphics.setColor(GREY)
        common.printCentered(font13, "Click an item to buy or sell it", PANEL_X + PAD, BTN_Y, INNER_W, BTN_H)
    end
end

local function drawHireTab()
    local name = getShopState().hireOffer
    if not name then
        love.graphics.setColor(GREY)
        common.printCentered(font14, "No one is looking for work", PANEL_X, DIVIDER_Y, PANEL_W, PANEL_Y + PANEL_H - DIVIDER_Y)
        return
    end

    love.graphics.setColor(0.10, 0.10, 0.10, 1)
    love.graphics.rectangle("fill", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
    if recruitIcon.name ~= name then
        local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
        recruitIcon.name, recruitIcon.img = name, ok and img or nil
    end
    love.graphics.setColor(1, 1, 1, 1)
    if recruitIcon.img then
        local iw, ih = recruitIcon.img:getDimensions()
        local sc = math.min(PORTRAIT_SIZE / iw, PORTRAIT_SIZE / ih)
        love.graphics.draw(recruitIcon.img, PORTRAIT_X + (PORTRAIT_SIZE - iw * sc) / 2,
            PORTRAIT_Y + (PORTRAIT_SIZE - ih * sc) / 2, 0, sc, sc)
    else
        common.printCentered(font14, displayName(name), PORTRAIT_X, PORTRAIT_Y, PORTRAIT_SIZE, PORTRAIT_SIZE)
    end

    -- Name, level, stats to the right of the portrait (as on the EQUIP screen).
    local tx = PORTRAIT_X + PORTRAIT_SIZE + 14
    love.graphics.setFont(font16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(common.fitText(font16, displayName(name), PANEL_X + PANEL_W - PAD - tx), tx, PORTRAIT_Y)
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print("Lv " .. tostring(progression.hireLevel(saveData_ref)), tx, PORTRAIT_Y + 18)
    local st = progression.heroStats(saveData_ref, name) or {}
    local statLines = {
        { "ATK", st.ATK or 0,   {0.95, 0.55, 0.20, 1} },
        { "DEF", st.DEF or 0,   {0.55, 0.75, 0.95, 1} },
        { "HP",  st.maxHP or 0, {0.85, 0.30, 0.35, 1} },
    }
    for i, line in ipairs(statLines) do
        local ly = PORTRAIT_Y + 40 + (i - 1) * 19
        love.graphics.setColor(line[3])
        love.graphics.print(line[1], tx, ly)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(tostring(line[2]), tx + 44, ly)
    end

    love.graphics.setFont(font13)
    love.graphics.setColor(GREY)
    love.graphics.printf("Joins with starter gear. " ..
        (firstFreePartySlot() and "Goes straight into the party." or "The party is full: goes to the reserves."),
        PANEL_X + PAD, PORTRAIT_Y + PORTRAIT_SIZE + 16, INNER_W, "left")
end

-- Tooltip for the item under the mouse (for sale, or in the inventory).
local function drawHoverTooltip()
    if hover.zone == "offer" then
        local inst = itemOf(getShopState().offers[hover.idx])
        if inst then
            local x, y, w, h = offerSlotRect(hover.idx)
            common.drawTooltip(item_ui.tooltipLines(inst, { price = { label = "Costs", amount = items.buyPrice(inst) } }),
                { x = x, y = y, w = w, h = h + 20 })
        end
    elseif hover.zone == "inv" then
        local inst = itemOf(hover.id)
        if inst then
            local x, y, w, h = item_ui.invCellRect(hover.idx)
            common.drawTooltip(item_ui.tooltipLines(inst, { price = { label = "Sells for", amount = items.sellValue(inst) } }),
                { x = x, y = y, w = w, h = h })
        end
    end
end

local function drawFlash()
    if flash.t <= 0 or not flash.text then return end
    love.graphics.setColor(0.95, 0.2, 0.3, math.min(1, flash.t / 0.4))
    common.printCentered(font14, flash.text, PANEL_X + PAD, BTN_Y - 24, INNER_W, 20)
end

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    local backPressed = pressedItem ~= nil and pressedItem.zone == "back" and hover.zone == "back"
    common.drawTopBar("SHOP", backPressed)
    drawGoldDisplay()

    -- Left panel
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", PANEL_X, PANEL_Y, PANEL_W, PANEL_H)
    love.graphics.setColor(0.35, 0.35, 0.35, 1)
    love.graphics.setLineWidth(1)
    love.graphics.line(PANEL_X + PAD, DIVIDER_Y, PANEL_X + PANEL_W - PAD, DIVIDER_Y)
    drawTabs()
    if tab == "gear" then drawGearTab() else drawHireTab() end
    drawActionButton()
    drawFlash()

    -- Right panel: the inventory, exactly as on the EQUIP screen
    local sel = selected and selected.kind == "inv" and selected.id or nil
    item_ui.drawInventory(saveData_ref, sel, (tab == "gear") and "Click an item to sell it" or nil)

    -- Red hover box (white when BACK is pressed), BACK on top, tooltip last
    common.drawBox(box, backPressed)
    common.drawBackButton(backPressed)
    drawHoverTooltip()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

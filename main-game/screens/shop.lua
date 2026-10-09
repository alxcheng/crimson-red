-- screens/shop.lua — SHOP screen (BH's "Merchant" + "Tavern").
--
-- Two tabs:
--   GEAR: 3 items for sale (shopState.offers) with BUY buttons, plus a SELL
--         list of the party's carried (unequipped) items. Buy at the item's
--         value, sell for half (BH rule). Stock comes from items.rollOffers.
--         Hovering a card or a sell row shows the item's details in a tooltip.
--   HIRE: one hero for hire (shopState.hireOffer). Hiring pays
--         progression.hireCost, recruits the hero with starter gear, and puts
--         them in the first free party slot (or leaves them in reserve).
--
-- Restock: on entry, if the shop was never stocked or a battle was won since
-- (shopState.pendingRestock), the 3 offers and the hire are re-rolled.
-- Re-entering without a new win does not reshuffle.
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
-- LAYOUT (800x450 virtual px)
-- ============================================================================

local TOP_BAR_H = common.TOP_BAR_H
local MARGIN    = 20                         -- gap between the content and the screen edges
local BOX_PAD   = common.BOX_PAD

-- Tab switcher (below the top bar)
local TAB_Y   = TOP_BAR_H + 12
local TAB_H   = 26
local TAB_W   = 110
local TAB1_X  = MARGIN                       -- GEAR
local TAB2_X  = TAB1_X + TAB_W + 12          -- HIRE

local CONTENT_Y = TAB_Y + TAB_H + 14         -- everything under the tabs
local CONTENT_H = VH - MARGIN - CONTENT_Y

-- GEAR tab: 3 offer cards on the left
local OFFER_X     = MARGIN
local OFFER_Y     = CONTENT_Y
local OFFER_W     = 150
local OFFER_H     = CONTENT_H
local OFFER_GAP   = 12
local OFFER_BTN_H = 34
local OFFER_BTN_Y = OFFER_Y + OFFER_H - OFFER_BTN_H - 8

-- GEAR tab: SELL list filling the rest of the row
local SELL_X      = OFFER_X + 3 * OFFER_W + 2 * OFFER_GAP + 16
local SELL_Y      = OFFER_Y
local SELL_W      = VW - MARGIN - SELL_X
local SELL_H      = OFFER_H
local SELL_HEAD_H = 30                       -- "SELL" caption band
local SELL_ROW_H  = 30
local SELL_ROWS   = math.floor((SELL_H - SELL_HEAD_H - 24) / SELL_ROW_H)   -- rows shown; 24 px left for "+N more"

-- HIRE tab: one recruit card centred in the content area
local HIRE_W      = 360
local HIRE_H      = 200
local HIRE_X      = math.floor((VW - HIRE_W) / 2)
local HIRE_Y      = CONTENT_Y + math.floor((CONTENT_H - HIRE_H) / 2)
local HIRE_BTN_H  = 40
local HIRE_BTN_Y  = HIRE_Y + HIRE_H - HIRE_BTN_H - 14

local PARTS_SIZE = 56   -- recruit portrait

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local tab            = "gear"   -- "gear" | "hire"
local hoveredTab     = nil      -- "gear" | "hire"
local hoveredBack    = false
local hoveredBuy     = nil      -- 1..3 offer index whose BUY button is hovered (GEAR)
local hoveredCard    = nil      -- 1..3 offer index whose card is hovered (tooltip)
local hoveredHireCard = false   -- recruit card hovered (tooltip)
local hoveredSell    = nil      -- 1..N owned-item index (GEAR)
local hoveredHire    = false    -- HIRE button (HIRE tab)
local pressedItem    = nil      -- {zone=...} while mouse is down
local box            = common.newBox()

local assetsLoaded = false
local font16, font14

-- ============================================================================
-- DATA HELPERS
-- ============================================================================

local function getShopState()
    local sd = saveData_ref
    sd.shopState = sd.shopState or {
        offers    = {},
        hireOffer = nil,
        seeded    = false,
    }
    local ss = sd.shopState
    ss.offers = ss.offers or {}
    return ss
end

local function getItemsTable()
    saveData_ref.items = saveData_ref.items or {}
    return saveData_ref.items
end

local function getInventory()
    saveData_ref.inventory = saveData_ref.inventory or {}
    return saveData_ref.inventory
end

local function goldValue()
    return saveData_ref.gold or 0
end

-- Remove an item id from the offers array. Returns true if removed.
local function removeFromOffers(id)
    local offers = getShopState().offers
    for i, v in ipairs(offers) do
        if v == id then
            table.remove(offers, i)
            return true
        end
    end
    return false
end

-- Remove an item id from the inventory array. Returns true if removed.
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

-- Lowest-index empty party slot (1..4), or nil if full.
local function firstFreePartySlot()
    local po = saveData_ref.partyOrder or {}
    for s = 1, 4 do
        if type(po[s]) ~= "string" then return s end
    end
    return nil
end

-- ============================================================================
-- RESTOCK
-- ============================================================================

local OFFER_COUNT = 3

local function restockIfNeeded()
    local sd = saveData_ref
    local ss = getShopState()
    if ss.seeded and not ss.pendingRestock then return end

    -- Unsold offers from the previous stock are discarded with it.
    for _, oldId in ipairs(ss.offers or {}) do
        sd.items[oldId] = nil
    end
    ss.offers = {}
    for _, bhId in ipairs(items.rollOffers(progression.highestLevel(sd), OFFER_COUNT)) do
        ss.offers[#ss.offers + 1] = items.mint(sd, bhId)
    end
    ss.hireOffer      = progression.rollHire(sd)
    ss.seeded         = true
    ss.pendingRestock = false
end

-- ============================================================================
-- TRANSACTIONS (all gold via the items API)
-- ============================================================================

local flash = { text = nil, t = 0 }   -- transient "not enough gold" state

local function setFlash(text)
    flash.text, flash.t = text, 1.2
end

-- BUY an offer (GEAR tab): cost = the item's VALUE.
-- Value = 2 * sellPrice (sellPrice is 50% of value per contract).
-- On success: spend gold, move the id out of offers into inventory.
-- On failure: flash "not enough gold" (no purchase).
local function buyOffer(idx)
    local ss = getShopState()
    local id = ss.offers[idx]
    if not id then return end
    local inst = getItemsTable()[id]
    if type(inst) ~= "table" then return end

    if items.spendGold(saveData_ref, items.buyPrice(inst)) then
        removeFromOffers(id)
        getInventory()[#getInventory() + 1] = id
        -- Item instance stays in saveData.items (now owned by the party).
        common.playClickSound()
    else
        setFlash("NOT ENOUGH GOLD")
    end
end

-- SELL an owned item (GEAR tab): pays sellValue(inst) = 50% of value.
-- On success: add gold, remove the id from inventory AND from items.
local function sellOwned(idx)
    local id = getInventory()[idx]
    if not id then return end
    local inst = getItemsTable()[id]
    if type(inst) ~= "table" then
        -- Stale id: drop it from the list, no gold.
        removeFromInventory(id)
        return
    end

    local pay = items.sellValue(inst)
    if pay < 0 then pay = 0 end
    items.addGold(saveData_ref, pay)
    removeFromInventory(id)
    getItemsTable()[id] = nil   -- item no longer owned
    common.playClickSound()
end

-- HIRE the offered hero: pay the cost, recruit them (level + starter gear),
-- and put them in the first free party slot. With a full party they go to
-- the reserves and can be swapped in on the PARTY screen.
local function hire()
    local ss = getShopState()
    local name = ss.hireOffer
    if not name then return end
    if items.spendGold(saveData_ref, progression.hireCost(saveData_ref)) then
        progression.recruit(saveData_ref, name)
        local slot = firstFreePartySlot()
        if slot then saveData_ref.partyOrder[slot] = name end
        ss.hireOffer = nil
        common.playClickSound()
    else
        setFlash("NOT ENOUGH GOLD")
    end
end

-- ============================================================================
-- LAYOUT HELPERS
-- ============================================================================

local function tabRect(which)
    if which == "hire" then return TAB2_X, TAB_Y, TAB_W, TAB_H end
    return TAB1_X, TAB_Y, TAB_W, TAB_H
end

local function offerCardRect(idx)
    return OFFER_X + (idx - 1) * (OFFER_W + OFFER_GAP), OFFER_Y, OFFER_W, OFFER_H
end

local function offerBuyRect(idx)
    local cx = OFFER_X + (idx - 1) * (OFFER_W + OFFER_GAP)
    return cx + 8, OFFER_BTN_Y, OFFER_W - 16, OFFER_BTN_H
end

local function sellRowRect(idx)
    return SELL_X, SELL_Y + SELL_HEAD_H + (idx - 1) * SELL_ROW_H, SELL_W, SELL_ROW_H
end

local function hireBtnRect()
    return HIRE_X + 24, HIRE_BTN_Y, HIRE_W - 48, HIRE_BTN_H
end

-- ============================================================================
-- HIT TESTING
-- ============================================================================

local function detectHover(vmx, vmy)
    hoveredBack    = false
    hoveredTab     = nil
    hoveredBuy     = nil
    hoveredSell    = nil
    hoveredHire    = false
    hoveredCard    = nil
    hoveredHireCard = false

    if common.overBack(vmx, vmy) then
        hoveredBack = true
        return "back"
    end

    local t1x, t1y, t1w, t1h = tabRect("gear")
    if vmx >= t1x and vmx < t1x + t1w and vmy >= t1y and vmy < t1y + t1h then
        hoveredTab = "gear"
        return "tab"
    end
    local t2x, t2y, t2w, t2h = tabRect("hire")
    if vmx >= t2x and vmx < t2x + t2w and vmy >= t2y and vmy < t2y + t2h then
        hoveredTab = "hire"
        return "tab"
    end

    if tab == "gear" then
        for i = 1, 3 do
            local cx, cy, cw, ch = offerCardRect(i)
            if getShopState().offers[i] and vmx >= cx and vmx < cx + cw and vmy >= cy and vmy < cy + ch then
                hoveredCard = i
            end
            local bx, by, bw, bh = offerBuyRect(i)
            if getShopState().offers[i] and vmx >= bx and vmx < bx + bw and vmy >= by and vmy < by + bh then
                hoveredBuy = i
                return "buy"
            end
        end
        for i = 1, #getInventory() do
            if i > SELL_ROWS then break end
            local sx, sy, sw, sh = sellRowRect(i)
            if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
                hoveredSell = i
                return "sell"
            end
        end
        return nil
    end

    -- HIRE tab
    hoveredHireCard = getShopState().hireOffer ~= nil
        and vmx >= HIRE_X and vmx < HIRE_X + HIRE_W and vmy >= HIRE_Y and vmy < HIRE_Y + HIRE_H
    local hx, hy, hw, hh = hireBtnRect()
    if getShopState().hireOffer and vmx >= hx and vmx < hx + hw and vmy >= hy and vmy < hy + hh then
        hoveredHire = true
        return "hire"
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
    end

    -- Restock if a battle was won since the last visit.
    restockIfNeeded()

    tab           = "gear"
    hoveredTab    = nil
    hoveredBack   = false
    hoveredBuy    = nil
    hoveredSell   = nil
    hoveredHire   = false
    pressedItem   = nil
    flash.text    = nil
    flash.t       = 0

    -- Snap the red box to the first tab.
    local tx, ty, tw, th = tabRect("gear")
    common.initBox(box, tx - BOX_PAD, ty - BOX_PAD, tw + BOX_PAD * 2, th + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()
    local zone = detectHover(vmx, vmy)

    if zone == "back" then
        common.setBoxTarget(box, common.backBoxRect())
    elseif zone == "tab" then
        local tx, ty, tw, th = tabRect(hoveredTab)
        common.setBoxTarget(box, tx - BOX_PAD, ty - BOX_PAD, tw + BOX_PAD * 2, th + BOX_PAD * 2)
    elseif zone == "buy" then
        local bx, by, bw, bh = offerBuyRect(hoveredBuy)
        common.setBoxTarget(box, bx - BOX_PAD, by - BOX_PAD, bw + BOX_PAD * 2, bh + BOX_PAD * 2)
    elseif zone == "sell" then
        local sx, sy, sw2, sh = sellRowRect(hoveredSell)
        common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, sw2 + BOX_PAD * 2, sh + BOX_PAD * 2)
    elseif zone == "hire" then
        local hx, hy, hw, hh = hireBtnRect()
        common.setBoxTarget(box, hx - BOX_PAD, hy - BOX_PAD, hw + BOX_PAD * 2, hh + BOX_PAD * 2)
    end

    common.updateBox(box, dt)

    -- Decay the transient "not enough gold" flash.
    if flash.t > 0 then
        flash.t = flash.t - dt
        if flash.t < 0 then flash.t = 0 end
    end
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local zone = detectHover(common.virtualMouse())
    if zone then
        pressedItem = {
            zone = zone,
            tab  = hoveredTab,
            buy  = hoveredBuy,
            sell = hoveredSell,
            hire = hoveredHire,
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

    if p.zone == "tab" then
        if hoveredTab then
            tab = hoveredTab
            local tx, ty, tw, th = tabRect(hoveredTab)
            common.initBox(box, tx - BOX_PAD, ty - BOX_PAD, tw + BOX_PAD * 2, th + BOX_PAD * 2)
            common.playClickSound()
        end
        return
    end

    if tab == "gear" then
        if p.zone == "buy" and p.buy then
            if hoveredBuy == p.buy then buyOffer(p.buy) end
            return
        end
        if p.zone == "sell" and p.sell then
            if hoveredSell == p.sell then sellOwned(p.sell) end
            return
        end
        return
    end

    if tab == "hire" and p.zone == "hire" then
        if hoveredHire then hire() end
        return
    end
end

function M.keypressed(key)
    if key == "escape" then
        exit()
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

local CRIMSON = {0.84, 0.07, 0.16, 1}
local OFFRED  = {1.00, 0.42, 0.42, 1}
local GOLD    = item_ui.GOLD

local displayName = common.titleCase

-- Small drawn coin glyph (Dedicool has no emoji). A gold circle + inner ring.
local function drawCoin(cx, cy, r)
    love.graphics.setColor(0.95, 0.78, 0.20, 1)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.70, 0.52, 0.10, 1)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", cx, cy, r - 2)
end

-- A filled button with a coin and "<verb> <price>" centred in it; dimmed when unaffordable.
local function drawPriceButton(verb, price, bx, by, bw, bh)
    local canAfford = goldValue() >= price
    love.graphics.setColor(canAfford and CRIMSON or {0.30, 0.10, 0.12, 1})
    love.graphics.rectangle("fill", bx, by, bw, bh)
    local label = verb .. " " .. tostring(price)
    local lw = font16:getWidth(label)
    local startX = math.floor(bx + (bw - (16 + lw)) / 2)       -- coin (12) + gap (4) + label
    drawCoin(startX + 6, by + bh / 2, 6)
    love.graphics.setFont(font16)
    love.graphics.setColor(canAfford and {1, 1, 1, 1} or {0.5, 0.4, 0.4, 1})
    love.graphics.print(label, startX + 16, math.floor(by + (bh - font16:getHeight()) / 2))
end

-- Recruit portrait: charicon image, or a name-fallback if absent.
local function drawRecruitPortrait(name, x, y, size)
    local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
    if ok and img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    love.graphics.setColor(1, 1, 1, 1)
    common.printCentered(font16, displayName(name), x, y, size, size)
end

local function drawGoldDisplay()
    local g = goldValue()
    love.graphics.setFont(font16)
    local str = tostring(math.floor(g))
    local w = font16:getWidth(str)
    local cx = VW - MARGIN - w
    drawCoin(cx - 8, math.floor(TOP_BAR_H / 2), 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(str, cx, math.floor((TOP_BAR_H - font16:getHeight()) / 2))
end

local function drawTabs()
    for _, which in ipairs({ "gear", "hire" }) do
        local tx, ty, tw, th = tabRect(which)
        local selected = (tab == which)
        love.graphics.setLineWidth(2)
        if selected then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", tx, ty, tw, th)
            love.graphics.setColor(CRIMSON)
            love.graphics.setFont(font16)
            local lbl = which:upper()
            love.graphics.print(lbl, tx + (tw - font16:getWidth(lbl)) / 2, ty + (th - font16:getHeight()) / 2)
        else
            love.graphics.setColor(0.45, 0.15, 0.20, 1)
            love.graphics.rectangle("line", tx, ty, tw, th)
            love.graphics.setFont(font16)
            local lbl = which:upper()
            love.graphics.print(lbl, tx + (tw - font16:getWidth(lbl)) / 2, ty + (th - font16:getHeight()) / 2)
        end
    end
end

-- One offer card: grade-tinted frame, glyph, name, type, bonuses, BUY button.
-- Everything is centred in the card; the full description is in the hover tooltip.
local function drawOfferCard(idx)
    local id = getShopState().offers[idx]
    local cx, cy, cw, ch = offerCardRect(idx)

    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", cx, cy, cw, ch)

    local inst = id and getItemsTable()[id]
    if type(inst) == "table" then
        love.graphics.setColor(item_ui.gradeColor(inst))
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", cx, cy, cw, ch)

        item_ui.drawGlyph(inst, cx + (cw - 48) / 2, cy + 20, 48)

        -- Name: up to two centred lines.
        love.graphics.setFont(font14)
        love.graphics.setColor(1, 1, 1, 1)
        local _, nameLines = font14:getWrap(inst.name or "(unnamed)", cw - 16)
        for i = 1, math.min(2, #nameLines) do
            local ln = (i == 2 and #nameLines > 2) and common.fitText(font14, nameLines[2] .. " " .. nameLines[3], cw - 16) or nameLines[i]
            love.graphics.printf(ln, cx + 8, cy + 82 + (i - 1) * 18, cw - 16, "center")
        end

        love.graphics.setColor(item_ui.GREY)
        love.graphics.printf(displayName(inst.itemType or "?"), cx + 8, cy + 128, cw - 16, "center")
        love.graphics.setColor(item_ui.BONUS)
        love.graphics.printf(item_ui.modsText(inst, "\n"), cx + 8, cy + 150, cw - 16, "center")

        local bx, by, bw, bh = offerBuyRect(idx)
        drawPriceButton("BUY", items.buyPrice(inst), bx, by, bw, bh)
    else
        -- Empty slot.
        love.graphics.setColor(0.20, 0.05, 0.06, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", cx, cy, cw, ch)
        love.graphics.setColor(0.4, 0.3, 0.3, 1)
        common.printCentered(font14, "SOLD OUT", cx, cy, cw, ch)
    end
end

local function drawSellSection()
    -- Frame + title.
    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", SELL_X, SELL_Y, SELL_W, SELL_H)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", SELL_X, SELL_Y, SELL_W, SELL_H)

    love.graphics.setFont(font16)
    love.graphics.setColor(CRIMSON)
    love.graphics.print("SELL", SELL_X + 12, math.floor(SELL_Y + (SELL_HEAD_H - font16:getHeight()) / 2) + 1)

    local inv = getInventory()
    local count = math.min(#inv, SELL_ROWS)
    if count == 0 then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local lbl = "No items to sell"
        love.graphics.print(lbl, SELL_X + 12, SELL_Y + SELL_HEAD_H + 8)
        return
    end

    for i = 1, count do
        local id = inv[i]
        local inst = getItemsTable()[id]
        local sx, sy, sw, sh = sellRowRect(i)

        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.30, 0.30, 0.30, 1)
        love.graphics.rectangle("line", sx, sy, sw, sh)

        if type(inst) == "table" then
            love.graphics.setColor(item_ui.gradeColor(inst))
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", sx + 5, sy + 5, sh - 10, sh - 10)

            -- Sell price right-aligned; the name gets whatever width is left.
            local textY = math.floor(sy + (sh - font14:getHeight()) / 2)
            local pstr  = tostring(items.sellValue(inst))
            local priceX = sx + sw - 10 - font14:getWidth(pstr)
            love.graphics.setFont(font14)
            love.graphics.setColor(GOLD)
            love.graphics.print(pstr, priceX, textY)
            love.graphics.setColor(1, 1, 1, 1)
            local nameX = sx + sh + 4
            love.graphics.print(common.fitText(font14, inst.name or "(unnamed)", priceX - 10 - nameX), nameX, textY)
        end
    end

    if #inv > SELL_ROWS then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("+" .. tostring(#inv - SELL_ROWS) .. " more", SELL_X + 12,
            SELL_Y + SELL_HEAD_H + SELL_ROWS * SELL_ROW_H + 5)
    end
end

local function drawHireCard()
    local ss = getShopState()
    local name = ss.hireOffer

    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", HIRE_X, HIRE_Y, HIRE_W, HIRE_H)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", HIRE_X, HIRE_Y, HIRE_W, HIRE_H)

    love.graphics.setFont(font16)
    love.graphics.setColor(CRIMSON)
    love.graphics.print("RECRUIT", HIRE_X + 14, HIRE_Y + 10)

    if not name then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        common.printCentered(font16, "No recruits available", HIRE_X, HIRE_Y, HIRE_W, HIRE_H)
        return
    end

    local stats = progression.heroStats(saveData_ref, name)
    local px, py = HIRE_X + 20, HIRE_Y + 42
    local tx = px + PARTS_SIZE + 14
    love.graphics.setColor(0.45, 0.15, 0.20, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, PARTS_SIZE, PARTS_SIZE)
    drawRecruitPortrait(name, px, py, PARTS_SIZE)

    love.graphics.setFont(font16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(displayName(name), tx, py)
    love.graphics.setFont(font14)
    love.graphics.setColor(OFFRED)
    love.graphics.print("Lv " .. tostring(progression.hireLevel(saveData_ref)), tx, py + 20)
    if stats then
        love.graphics.setColor(item_ui.BONUS)
        love.graphics.print(common.fitText(font14, ("ATK %d  DEF %d  HP %d"):format(stats.ATK or 0, stats.DEF or 0, stats.maxHP or 0),
            HIRE_X + HIRE_W - 14 - tx), tx, py + 40)
    end

    local hx, hy, hw, hh = hireBtnRect()
    drawPriceButton("HIRE", progression.hireCost(saveData_ref), hx, hy, hw, hh)
end

-- Tooltip for whatever is under the mouse: an item for sale, an item to sell, the recruit.
local function drawHoverTooltip()
    if tab == "gear" then
        if hoveredSell then
            local inst = getItemsTable()[getInventory()[hoveredSell]]
            if type(inst) == "table" then
                local x, y, w, h = sellRowRect(hoveredSell)
                common.drawTooltip(item_ui.tooltipLines(inst, { price = { label = "Sells for", amount = items.sellValue(inst) } }),
                    { x = x, y = y, w = w, h = h })
            end
        elseif hoveredCard then
            local inst = getItemsTable()[getShopState().offers[hoveredCard]]
            if type(inst) == "table" then
                -- The card is large, so this one hangs under the mouse instead of under the card.
                local vmx, vmy = common.virtualMouse()
                common.drawTooltip(item_ui.tooltipLines(inst, { price = { label = "Costs", amount = items.buyPrice(inst) } }),
                    { x = vmx, y = vmy, w = 12, h = 14 })
            end
        end
    elseif hoveredHireCard then
        local name = getShopState().hireOffer
        local lines = {
            { text = displayName(name), size = 16, color = OFFRED },
            { text = "Joins at Lv " .. tostring(progression.hireLevel(saveData_ref)) .. " with starter gear.", color = {1, 1, 1, 1} },
            { text = firstFreePartySlot() and "Goes straight into the party." or "Party is full: goes to the reserves.", color = item_ui.GREY },
            { text = "Costs " .. tostring(progression.hireCost(saveData_ref)) .. " gold", color = GOLD },
        }
        common.drawTooltip(lines, { x = HIRE_X, y = HIRE_Y, w = HIRE_W, h = HIRE_H })
    end
end

local function drawFlash()
    if flash.t <= 0 or not flash.text then return end
    local a = math.min(1, flash.t / 0.4)
    love.graphics.setColor(0.95, 0.2, 0.3, a)
    love.graphics.setFont(font16)
    local w = font16:getWidth(flash.text)
    love.graphics.print(flash.text, (VW - w) / 2, TAB_Y + math.floor((TAB_H - font16:getHeight()) / 2))
end

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Top bar
    local backPressed = pressedItem ~= nil and pressedItem.back and hoveredBack
    common.drawTopBar("SHOP", backPressed)
    drawGoldDisplay()

    -- 3. Tabs
    drawTabs()

    -- 4. Content
    if tab == "gear" then
        for i = 1, 3 do
            drawOfferCard(i)
        end
        drawSellSection()
    else
        drawHireCard()
    end

    -- 5. Red hover box (white when BACK is pressed), then BACK again on top of it
    common.drawBox(box, backPressed)
    common.drawBackButton(backPressed)

    -- 6. Transient flash, hover tooltip
    drawFlash()
    drawHoverTooltip()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

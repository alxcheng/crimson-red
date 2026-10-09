-- screens/shop.lua — Merchant / shop screen module (Battleheart merchant look)
--
-- A stall with TWO tabs:
--   GEAR tab (default): 3 gear offers (shopState.offers) with BUY buttons,
--     plus a SELL list of the party's owned (un-equipped) items at 50% value.
--   HIRE tab: one recruit card (shopState.hireOffer) with a HIRE button.
--
-- Data contract (work/phase0-contract.md):
--   saveData.gold             = unspent gold
--   saveData.items[id]        = item instance { id, itemType, grade, name,
--                                     icon, sellPrice, usableBy, mods }
--   saveData.inventory        = flat array of item INSTANCE ids (un-equipped)
--   saveData.shopState        = { offers = {3 instance ids}, hireOffer = charKey|nil,
--                                 lastFloor, seeded, pendingRestock }
--   All gold economy goes through the items API (addGold / spendGold /
--   sellValue / hireCost / rollOffers / rollHire / makeInstance / nextId).
--
-- RESTOCK (contract, Director-confirmed): on entry, if
--   shopState.pendingRestock == true  OR
--   shopState.seeded == false         OR
--   shopState.lastFloor ~= saveData.floor
-- then mint 3 fresh instances from rollOffers(floor), roll a new hire offer,
-- and mark lastFloor=floor / seeded=true / pendingRestock=false.
-- Re-entering the shop with no new win does NOT reshuffle.
--
-- On exit: save.write(slot, saveData) then switchFn("map", saveData, slot)
-- (same routine equip.lua / party_select.lua use).

local common = require("common")
local save   = require("save")

-- The `items` module (main-game/items.lua) exists (Foundation phase). pcall
-- guard is defensive only so the screen still loads if it is ever absent.
local items
do
    local ok, mod = pcall(require, "items")
    items = (ok and type(mod) == "table") and mod or nil
end

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT (800x450 virtual px)
-- ============================================================================

local TOP_BAR_H    = 40
local DESC_BAR_H   = 60
local CONTENT_TOP  = TOP_BAR_H
local CONTENT_BOT  = VH - DESC_BAR_H

local BOX_PAD = 5

-- Tab switcher (below the top bar)
local TAB_Y        = 50
local TAB_H        = 26
local TAB_W        = 110
local TAB1_X       = 20                     -- GEAR
local TAB2_X       = TAB1_X + TAB_W + 14    -- HIRE

-- GEAR tab — 3 offer cards in a row (left/center)
local OFFER_X      = 20
local OFFER_Y      = 90
local OFFER_W      = 160
local OFFER_H      = 232
local OFFER_GAP    = 12
local OFFER_BTN_H  = 34
local OFFER_BTN_Y  = OFFER_Y + OFFER_H - OFFER_BTN_H - 8

-- GEAR tab — SELL section (right column)
local SELL_X       = OFFER_X + 3 * OFFER_W + 2 * OFFER_GAP + 16
local SELL_Y       = OFFER_Y
local SELL_W       = VW - SELL_X - 20
local SELL_H       = OFFER_H
local SELL_ROWS    = 6                      -- owned-item rows shown
local SELL_ROW_H   = 30

-- HIRE tab — one centered recruit card
local HIRE_X       = math.floor((VW - 300) / 2)
local HIRE_Y       = 120
local HIRE_W       = 300
local HIRE_H       = 240
local HIRE_BTN_H   = 40
local HIRE_BTN_Y   = HIRE_Y + HIRE_H - HIRE_BTN_H - 12

-- Bottom description bar
local DESC_Y       = VH - DESC_BAR_H

local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local AW      = common.ARROW_W
local AH      = common.ARROW_H

local PARTS_SIZE = 56   -- recruit portrait

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local tab            = "gear"   -- "gear" | "hire"
local hoveredTab     = nil      -- "gear" | "hire"
local hoveredBack    = false
local hoveredBuy     = nil      -- 1..3 offer index (GEAR)
local hoveredSell    = nil      -- 1..N owned-item index (GEAR)
local hoveredHire    = false    -- HIRE button (HIRE tab)
local pressedItem    = nil      -- {zone=...} while mouse is down
local box            = common.newBox()

local assetsLoaded = false
local font16, font14, fontTitle

-- ============================================================================
-- DATA HELPERS
-- ============================================================================

local function getShopState()
    local sd = saveData_ref
    sd.shopState = sd.shopState or {
        offers    = {},
        hireOffer = nil,
        lastFloor = 1,
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

local function inParty(name)
    local po = saveData_ref.partyOrder or {}
    for _, n in ipairs(po) do
        if n == name then return true end
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
-- RESTOCK (contract § Shop restock rule)
-- ============================================================================

-- If pendingRestock / not-seeded / floor-changed: mint 3 fresh instances from
-- rollOffers(floor) into saveData.items + shopState.offers, roll a new hire
-- offer, and mark stocked. Re-entering without a new win does NOT reshuffle.
local function restockIfNeeded()
    if not items then return end
    local sd = saveData_ref
    local ss = getShopState()
    local floor = sd.floor or 1

    local need = (ss.pendingRestock == true)
        or (ss.seeded == false)
        or (ss.lastFloor ~= floor)
    if not need then return end

    -- Unsold offers from the previous stock are discarded with it.
    for _, oldId in ipairs(ss.offers or {}) do
        sd.items[oldId] = nil
    end

    -- Mint 3 fresh instances.
    local newOffers = {}
    local offers = items.rollOffers(floor)
    for _, t in ipairs(offers or {}) do
        if t and t.itemType and t.grade then
            local id = items.nextId(sd)
            local inst = items.makeInstance(id, t.itemType, t.grade)
            sd.items[id] = inst
            newOffers[#newOffers + 1] = id
        end
    end
    ss.offers = newOffers

    -- Roll a new hire offer.
    if items.rollHire then
        local ok, name = pcall(items.rollHire, sd)
        ss.hireOffer = (ok and type(name) == "string") and name or nil
    else
        ss.hireOffer = nil
    end

    ss.lastFloor      = floor
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
    if not items or not items.spendGold then return end

    local price = (inst.sellPrice or 0) * 2
    if price <= 0 then price = 8 end   -- defensive floor (g1 value)

    if items.spendGold(saveData_ref, price) then
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
    if not items or not items.addGold or not items.sellValue then return end

    local pay = items.sellValue(inst)
    if pay < 0 then pay = 0 end
    items.addGold(saveData_ref, pay)
    removeFromInventory(id)
    getItemsTable()[id] = nil   -- item no longer owned
    common.playClickSound()
end

-- HIRE a recruit (HIRE tab): cost = items.hireCost(floor).
-- All 12 chars already exist in unlockedCharacters, so "hiring" = pay gold
-- and place the char into the active party (next free slot, 4 max).
-- If the party is full the char remains in the roster (no change) and the
-- button reads "IN ROSTER".
local function hire()
    local ss = getShopState()
    local name = ss.hireOffer
    if not name then return end
    if not items or not items.spendGold or not items.hireCost then return end

    -- Already in the active party: nothing to do (no gold consumed).
    if inParty(name) then
        setFlash("ALREADY IN PARTY")
        return
    end

    local slot = firstFreePartySlot()
    if not slot then
        -- Party full: the char is already in the roster; hiring is a no-op.
        setFlash("PARTY FULL")
        return
    end

    local cost = items.hireCost(saveData_ref.floor or 1)
    if items.spendGold(saveData_ref, cost) then
        saveData_ref.partyOrder[slot] = name
        ss.hireOffer = nil   -- recruit is now in the party
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
    return SELL_X, SELL_Y + 26 + (idx - 1) * SELL_ROW_H, SELL_W, SELL_ROW_H
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

    if vmx >= AX and vmx < AX + AW and vmy >= AY and vmy < AY + AH then
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
        fontTitle = common.loadFont(20)
    end

    -- Restock per the contract rule (no-op if already stocked this floor).
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
        common.setBoxTarget(box, AX - BOX_PAD, AY - BOX_PAD, AW + BOX_PAD * 2, AH + BOX_PAD * 2)
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

local GRADE_COLORS = {
    [1] = {0.55, 0.55, 0.55, 1},   -- low: grey
    [2] = {0.95, 0.55, 0.20, 1},   -- mid: orange
    [3] = {0.95, 0.20, 0.35, 1},   -- high: crimson
}

local CRIMSON = {0.84, 0.07, 0.16, 1}
local OFFRED  = {1.00, 0.42, 0.42, 1}

local function displayName(name)
    if not name then return "" end
    local parts = {}
    for part in name:gmatch("%S+") do
        parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2)
    end
    return table.concat(parts, " ")
end

-- Small drawn coin glyph (Dedicool has no emoji). A gold circle + inner ring.
local function drawCoin(cx, cy, r)
    love.graphics.setColor(0.95, 0.78, 0.20, 1)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.70, 0.52, 0.10, 1)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", cx, cy, r - 2)
end

-- Draw an item instance's type glyph (letter) — matches equip's W/A/T tokens.
local function drawItemGlyph(inst, x, y, size)
    local GLYPHS = { weapon = "W", armor = "A", trinket = "T" }
    local glyph = GLYPHS[inst.itemType] or "?"
    local gc = GRADE_COLORS[inst.grade] or {0.55, 0.55, 0.55, 1}
    love.graphics.setColor(gc)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 2, y + 2, size - 4, size - 4)
    love.graphics.setFont(font16)
    local gw, gh = font16:getWidth(glyph), font16:getHeight(glyph)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(glyph, x + (size - gw) / 2, y + (size - gh) / 2)
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
    local label = displayName(name)
    love.graphics.setFont(font16)
    local fw, fh = font16:getWidth(label), font16:getHeight()
    local scale = 1
    if fw > size - 4 then scale = (size - 4) / fw end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(label, x + (size - fw * scale) / 2, y + (size - fh * scale) / 2, 0, scale, scale)
end

local function drawGoldDisplay()
    local g = goldValue()
    love.graphics.setFont(font16)
    local str = tostring(math.floor(g))
    local w = font16:getWidth(str)
    local cx = VW - 18 - w
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

-- One offer card: grade-tinted frame, name, type/grade, mods, BUY button.
local function drawOfferCard(idx)
    local id = getShopState().offers[idx]
    local cx, cy, cw, ch = offerCardRect(idx)

    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", cx, cy, cw, ch)

    local inst = id and getItemsTable()[id]
    if type(inst) == "table" then
        local gc = GRADE_COLORS[inst.grade] or {0.55, 0.55, 0.55, 1}
        love.graphics.setColor(gc)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", cx, cy, cw, ch)

        drawItemGlyph(inst, cx + 12, cy + 12, 40)

        -- Name wraps to two lines beside the glyph so it never leaves the card.
        love.graphics.setFont(font14)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(inst.name or "(unnamed)", cx + 60, cy + 16, cw - 66, "left")

        love.graphics.setColor(0.75, 0.75, 0.75, 1)
        love.graphics.print(tostring(inst.itemType or "?") .. "  grade " .. tostring(inst.grade or "?"),
            cx + 12, cy + 62)

        -- Mods (wrap up to 2 lines).
        local mods = inst.mods or {}
        local modParts = {}
        for k, v in pairs(mods) do
            modParts[#modParts + 1] = "+" .. tostring(v) .. " " .. k
        end
        if #modParts > 0 then
            table.sort(modParts)
            love.graphics.setColor(0.95, 0.55, 0.20, 1)
            love.graphics.printf(table.concat(modParts, "\n"), cx + 12, cy + 86, cw - 24, "left")
        end

        -- BUY button with price = value (2 * sellPrice).
        local price = (inst.sellPrice or 0) * 2
        if price <= 0 then price = 8 end
        local bx, by, bw, bh = offerBuyRect(idx)
        local canAfford = goldValue() >= price
        love.graphics.setColor(canAfford and CRIMSON or {0.30, 0.10, 0.12, 1})
        love.graphics.rectangle("fill", bx, by, bw, bh)
        love.graphics.setColor(canAfford and {1, 1, 1, 1} or {0.5, 0.4, 0.4, 1})
        love.graphics.setFont(font16)
        drawCoin(bx + 14, by + bh / 2, 6)
        love.graphics.print("BUY", bx + 26, by + (bh - font16:getHeight()) / 2)
        love.graphics.print(tostring(price), bx + 64, by + (bh - font16:getHeight()) / 2)
    else
        -- Empty slot.
        love.graphics.setColor(0.20, 0.05, 0.06, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", cx, cy, cw, ch)
        love.graphics.setFont(font14)
        love.graphics.setColor(0.4, 0.3, 0.3, 1)
        local lbl = "SOLD OUT"
        love.graphics.print(lbl, cx + (cw - font14:getWidth(lbl)) / 2, cy + ch / 2 - 8)
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
    love.graphics.print("SELL (50%)", SELL_X + 12, SELL_Y + 6)

    local inv = getInventory()
    local count = math.min(#inv, SELL_ROWS)
    if count == 0 then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local lbl = "No items to sell"
        love.graphics.print(lbl, SELL_X + 12, SELL_Y + 40)
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
            local gc = GRADE_COLORS[inst.grade] or {0.55, 0.55, 0.55, 1}
            love.graphics.setColor(gc)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", sx + 4, sy + 4, sh - 8, sh - 8)

            love.graphics.setFont(font14)
            love.graphics.setColor(1, 1, 1, 1)
            local nm = inst.name or "(unnamed)"
            love.graphics.print(nm, sx + (sh + 8) + 6, sy + (sh - font14:getHeight()) / 2)

            -- Sell price on the right.
            local pay = (items and items.sellValue) and items.sellValue(inst) or (inst.sellPrice or 0)
            love.graphics.setColor(0.95, 0.78, 0.20, 1)
            local pstr = tostring(pay)
            love.graphics.print(pstr, sx + sw - 10 - font14:getWidth(pstr), sy + (sh - font14:getHeight()) / 2)
        end
    end

    if #inv > SELL_ROWS then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("+" .. tostring(#inv - SELL_ROWS) .. " more", SELL_X + 12,
            SELL_Y + 26 + SELL_ROWS * SELL_ROW_H + 4)
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
    local ttl = "RECRUIT"
    love.graphics.print(ttl, HIRE_X + 12, HIRE_Y + 8)

    if not name then
        love.graphics.setFont(font16)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local lbl = "No recruits available"
        love.graphics.print(lbl, HIRE_X + (HIRE_W - font16:getWidth(lbl)) / 2, HIRE_Y + HIRE_H / 2 - 8)
        return
    end

    local cd = (saveData_ref.unlockedCharacters or {})[name]
    local lvl = (cd and cd.level) or 1
    local stats = cd and cd.stats or nil

    drawRecruitPortrait(name, HIRE_X + 20, HIRE_Y + 40, PARTS_SIZE)

    love.graphics.setFont(font16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(displayName(name), HIRE_X + 20 + PARTS_SIZE + 14, HIRE_Y + 44)
    love.graphics.setFont(font14)
    love.graphics.setColor(OFFRED)
    love.graphics.print("Lv " .. tostring(lvl), HIRE_X + 20 + PARTS_SIZE + 14, HIRE_Y + 66)

    if stats then
        love.graphics.setFont(font14)
        love.graphics.setColor(0.95, 0.55, 0.20, 1)
        love.graphics.print("ATK " .. tostring(stats.ATK or 0)
            .. "   DEF " .. tostring(stats.DEF or 0)
            .. "   HP " .. tostring(stats.maxHP or 0),
            HIRE_X + 20 + PARTS_SIZE + 14, HIRE_Y + 86)
    end

    -- HIRE button: cost = hireCost(floor); "IN PARTY"/"PARTY FULL" variants.
    local hx, hy, hw, hh = hireBtnRect()
    local already = inParty(name)
    local full    = firstFreePartySlot() == nil
    local label, dim
    if already then
        label, dim = "IN PARTY", true
    elseif full then
        label, dim = "PARTY FULL", true
    else
        local cost = (items and items.hireCost) and items.hireCost(saveData_ref.floor or 1) or 0
        local canAfford = goldValue() >= cost
        label = "HIRE  " .. tostring(cost)
        dim = not canAfford
    end
    love.graphics.setColor(dim and {0.30, 0.10, 0.12, 1} or CRIMSON)
    love.graphics.rectangle("fill", hx, hy, hw, hh)
    love.graphics.setFont(font16)
    love.graphics.setColor(dim and {0.5, 0.4, 0.4, 1} or {1, 1, 1, 1})
    if not dim and not already and not full then
        drawCoin(hx + 22, hy + hh / 2, 6)
        love.graphics.print("HIRE", hx + 34, hy + (hh - font16:getHeight()) / 2)
        local costStr = label:match("(%d+)$") or ""
        love.graphics.print(costStr, hx + 84, hy + (hh - font16:getHeight()) / 2)
    else
        love.graphics.print(label, hx + (hw - font16:getWidth(label)) / 2, hy + (hh - font16:getHeight()) / 2)
    end
end

local function drawDescBar()
    love.graphics.setColor(0.05, 0.03, 0.03, 1)
    love.graphics.rectangle("fill", 0, DESC_Y, VW, DESC_BAR_H)
    love.graphics.setColor(0.6, 0.15, 0.20, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(0, DESC_Y, VW, DESC_Y)

    -- Determine the focused item / recruit.
    local inst, hireName = nil, nil
    if tab == "gear" then
        if hoveredSell then
            local id = getInventory()[hoveredSell]
            inst = id and getItemsTable()[id]
        elseif hoveredBuy then
            local id = getShopState().offers[hoveredBuy]
            inst = id and getItemsTable()[id]
        end
    elseif tab == "hire" then
        hireName = getShopState().hireOffer
    end

    if type(inst) == "table" then
        love.graphics.setFont(font16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(inst.name or "(unnamed)", 12, DESC_Y + 6)
        love.graphics.setFont(font14)
        love.graphics.setColor(0.75, 0.75, 0.75, 1)
        love.graphics.print(tostring(inst.itemType or "?") .. " · grade " .. tostring(inst.grade or "?"),
            12, DESC_Y + 28)
        local mods = inst.mods or {}
        local modParts = {}
        for k, v in pairs(mods) do
            modParts[#modParts + 1] = "+" .. tostring(v) .. " " .. k
        end
        if #modParts > 0 then
            love.graphics.setColor(0.95, 0.55, 0.20, 1)
            love.graphics.print(table.concat(modParts, ", "), 240, DESC_Y + 28)
        end
        love.graphics.setColor(0.95, 0.78, 0.20, 1)
        local pay = (items and items.sellValue) and items.sellValue(inst) or (inst.sellPrice or 0)
        love.graphics.print("sells for " .. tostring(pay), VW - 160, DESC_Y + 28)
    elseif hireName then
        local cd = (saveData_ref.unlockedCharacters or {})[hireName]
        love.graphics.setFont(font16)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(displayName(hireName), 12, DESC_Y + 6)
        love.graphics.setFont(font14)
        love.graphics.setColor(0.75, 0.75, 0.75, 1)
        love.graphics.print("Lv " .. tostring((cd and cd.level) or 1), 12, DESC_Y + 28)
        local cost = (items and items.hireCost) and items.hireCost(saveData_ref.floor or 1) or 0
        love.graphics.setColor(0.95, 0.78, 0.20, 1)
        love.graphics.print("hire cost " .. tostring(cost), VW - 160, DESC_Y + 28)
    else
        love.graphics.setFont(font14)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("Hover an item or recruit for details.",
            12, DESC_Y + (DESC_BAR_H - font14:getHeight()) / 2)
    end
end

local function drawFlash()
    if flash.t <= 0 or not flash.text then return end
    local a = math.min(1, flash.t / 0.4)
    love.graphics.setColor(0.95, 0.2, 0.3, a)
    love.graphics.setFont(font16)
    local w = font16:getWidth(flash.text)
    love.graphics.print(flash.text, (VW - w) / 2, 78)
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

    local title = "SHOP"
    love.graphics.setFont(fontTitle)
    love.graphics.setColor(common.COLOR_RED)
    love.graphics.print(title, (VW - fontTitle:getWidth(title)) / 2,
        math.floor((TOP_BAR_H - fontTitle:getHeight()) / 2))

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

    -- 5. Bottom description bar
    drawDescBar()

    -- 6. Red hover box (on top)
    local boxPressed = (pressedItem ~= nil and pressedItem.back and hoveredBack)
    common.drawBox(box, boxPressed)

    -- 7. Transient flash
    drawFlash()

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

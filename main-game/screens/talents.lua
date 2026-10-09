-- screens/talents.lua — TALENTS screen (BH's "Academy").
--
-- Shows one hero's talent ladder (data/talents.lua): a vertical list of level
-- rows where every few levels is a fork of two passive bonuses. Clicking a
-- branch at a reached, unchosen fork records the pick in
-- saveData.unlockedCharacters[name].skillTree; the other branch locks for good.
-- Bonuses take effect through progression.heroStats — this screen only records
-- picks. Levels come from XP earned in battle (progression.lua).
-- Hovering a row shows what it does (and whether it can be picked) in a tooltip.

local common   = require("common")
local save     = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- PALETTE (project: crimson red / off-red / white on black)
-- ============================================================================

local CRIMSON = {0.84, 0.07, 0.16, 1}   -- crimson red  (primary accent)
local OFFRED  = {1.00, 0.42, 0.42, 1}   -- off-red      (hover accent)
local WHITE   = {1.00, 1.00, 1.00, 1}   -- white        (pressed/active/chosen)
local DIM     = {0.32, 0.12, 0.14, 1}   -- locked/future nodes
local FAINT   = {0.16, 0.06, 0.07, 1}   -- very dim (empty cells, connectors)

local talents_data = require("data/talents")
local CHOICE_EVERY = talents_data.CHOICE_EVERY
local ladderFor    = talents_data.ladderFor

-- ============================================================================
-- LAYOUT
-- ============================================================================

local BOX_PAD = common.BOX_PAD

-- Party chips (pick whose ladder is shown), centred under the top bar.
local PARTY_SLOTS  = 4
local ICON_SIZE    = 44
local PARTY_GAP    = 12
local PARTY_TOTAL_W = PARTY_SLOTS * ICON_SIZE + (PARTY_SLOTS - 1) * PARTY_GAP
local PARTY_X      = math.floor((VW - PARTY_TOTAL_W) / 2)
local PARTY_Y      = common.TOP_BAR_H + 12

local NAME_Y       = PARTY_Y + ICON_SIZE + 10   -- "Lv 3  Knight"
local XP_Y         = NAME_Y + 18                -- "XP to next: 40"

local LADDER_TOP    = XP_Y + 26          -- first ladder row
local LADDER_BOTTOM = VH - 16            -- ladder viewport lower bound
local NODE_H        = 24
local NODE_GAP      = 6
local MAX_NODES_SHOWN = 21    -- highest level laid out (= the last choice level)

local CENTERLINE_X  = math.floor(VW / 2)
local BRANCH_BOX_W  = 200
local FORK_HEIGHT   = 40                 -- vertical space a choice fork occupies
local PLAIN_HEIGHT  = NODE_H             -- vertical space a plain level node occupies

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local partyNames   = {}   -- [1..4] charName or nil (active party)
local selectedChar = nil  -- charName whose ladder is displayed
local icons        = {}   -- { [charName] = Image }
local assetsLoaded = false

local font       -- size 13 node labels / misc
local nameFont   -- size 14 branch names
local smallFont  -- size 12 branch descriptions / tiny text

local scrollOff  = 0      -- vertical scroll offset of the ladder (px down)
local hoveredNode = nil   -- the nodeRow ({kind=...}) currently under the mouse
local hoveredOpt  = nil   -- the specific sub-box (left/right/plain) under the mouse
local pressedNode = nil   -- {kind="back"} | {kind="fork",idx,opt} | {kind="plain",level}
local hoveredPartySlot = nil
local box        = common.newBox()

-- Computed layout cache, rebuilt when selectedChar / scroll changes:
-- nodeRects[lvl] = {x,y,w,h, kind, ...} keyed by level number.
local nodeRects  = {}
local scrollInfo = { content = 0, view = 0 }   -- ladder height vs. viewport height (for the scrollbar)

-- ============================================================================
-- SAVE-RECORD HELPERS
-- ============================================================================

local function charRecord(name)
    local uc = saveData_ref and saveData_ref.unlockedCharacters
    if not uc then return nil end
    return uc[name]
end

-- The character's current level (>=1). Degrades cleanly to 1 if absent.
local function charLevel(rec)
    local lv = rec and rec.level
    if type(lv) == "number" and lv >= 1 then return math.floor(lv) end
    return 1
end

-- Forward declarations: these locals are referenced by functions defined
-- BEFORE the local function that assigns them. Without a prior `local name`
-- in scope, the earlier closures would capture a GLOBAL (nil at call time)
-- instead of the upvalue -> runtime "attempt to call a nil value" once the
-- talents screen is actually driven (headless only loads, never drives it).
local resolveOption, displayName
local drawLadder, drawPlainRow, drawForkRow, drawBranchBox, drawHoverTooltip

-- Read the chosen-branch map from skillTree, tolerant of the OLD shape
-- ({1,1,1,1,1}) and partial arrays. Returns a fresh table keyed by the
-- choice INDEX (1-based position in ladder.choices): chosen[idx] = optionId.
-- Old numeric entries are ignored (see resolveOption).
local function readChoices(rec, ladder)
    local out = {}
    local st = rec and rec.skillTree
    if type(st) == "table" then
        for i, v in ipairs(st) do
            local choice = ladder.choices[i]
            if choice then
                local resolved = resolveOption(choice, v)
                if resolved then out[i] = resolved end
            end
        end
    end
    return out
end

-- Given a choice table and a stored value (option id string OR 1/2 index),
-- return the canonical option id, or nil if it doesn't match either.
resolveOption = function(choice, v)
    if type(v) == "string" then
        for _, o in ipairs(choice.options) do
            if o.id == v then return v end
        end
        return nil
    end
    -- Numbers are the pre-talents placeholder ({1,1,1,1,1}): no passive was ever
    -- applied for them, so they read as "not chosen yet".
    return nil
end

-- Write a choice back into skillTree, preserving the NEW string-id shape while
-- keeping the field a plain ipairs-safe array. Earlier unfilled slots get "" so
-- positional indexing (readChoices iterates by array index) stays stable.
local function writeChoice(rec, ladder, choiceIdx, optId)
    if not rec then return end
    local st = rec.skillTree
    if type(st) ~= "table" then st = {}; rec.skillTree = st end
    for i = 1, choiceIdx - 1 do
        if st[i] == nil then st[i] = "" end
    end
    st[choiceIdx] = optId
end

-- ============================================================================
-- EXIT — persists any talent picks and returns to map
-- ============================================================================

local function exit()
    -- Persist the whole save record (talent picks were folded in live; this
    -- flushes them to disk). Same routine party_select uses.
    if saveData_ref then
        save.write(slot_ref, saveData_ref)
    end
    switchFn("map", saveData_ref, slot_ref)
end

-- ============================================================================
-- LAYOUT BUILD  (defined BEFORE the interface: onEnter / mousepressed /
-- mousereleased / wheel all call rebuildLayout, so it must be in scope by then.)
-- ============================================================================

local function getPartyRect(i)
    return PARTY_X + (i - 1) * (ICON_SIZE + PARTY_GAP), PARTY_Y, ICON_SIZE, ICON_SIZE
end

local function pointInRect(px, py, r)
    -- Rows scrolled outside the ladder viewport are clipped, so not hittable.
    if py < LADDER_TOP - 8 or py >= LADDER_BOTTOM + 4 then return false end
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

local function addPlainRow(rects, lvl, y, level)
    local w = 90
    local x = CENTERLINE_X - w / 2
    local state = (level >= lvl) and "reached" or "locked"
    rects[lvl] = {
        kind = "plain", level = lvl,
        x = x, y = y, w = w, h = PLAIN_HEIGHT,
        state = state,
        hoverRect = { x - BOX_PAD, y - BOX_PAD, w + BOX_PAD*2, PLAIN_HEIGHT + BOX_PAD*2 },
    }
end

local function rebuildLayout()
    nodeRects = {}
    if not selectedChar then return end
    local rec = charRecord(selectedChar)
    local ladder = ladderFor(selectedChar)
    local level = rec and charLevel(rec) or 1

    -- Determine how many levels to show: up to MAX_NODES_SHOWN starting at 1.
    -- Always include the NEXT choice level so the upcoming fork is previewed.
    local totalRows = math.min(MAX_NODES_SHOWN,
                               (math.floor(level / CHOICE_EVERY) + 1) * CHOICE_EVERY)

    -- Pre-compute cumulative Y.
    local y = LADDER_TOP - scrollOff
    local choiceIdx = 0
    local lvl = 1
    while lvl <= totalRows do
        local isChoice = (lvl % CHOICE_EVERY == 0)
        if isChoice then
            choiceIdx = choiceIdx + 1
            local ch = ladder.choices[choiceIdx]
            if ch and ch.level == lvl then
                local chosenMap = readChoices(rec, ladder)
                local leftX  = CENTERLINE_X - 12 - BRANCH_BOX_W
                local rightX = CENTERLINE_X + 12
                local reached = level >= lvl
                local chosenId = chosenMap[choiceIdx]
                nodeRects[lvl] = {
                    kind = "fork", idx = choiceIdx, level = lvl,
                    x = leftX, y = y, w = BRANCH_BOX_W * 2 + 24, h = FORK_HEIGHT,
                    left  = { x = leftX,  y = y, w = BRANCH_BOX_W, h = FORK_HEIGHT, opt = 1,
                              state = (not reached) and "locked"
                                      or (chosenId == ch.options[1].id) and "chosen"
                                      or (chosenId ~= nil) and "lockedOther"
                                      or "selectable" },
                    right = { x = rightX, y = y, w = BRANCH_BOX_W, h = FORK_HEIGHT, opt = 2,
                              state = (not reached) and "locked"
                                      or (chosenId == ch.options[2].id) and "chosen"
                                      or (chosenId ~= nil) and "lockedOther"
                                      or "selectable" },
                }
                nodeRects[lvl]._whole = { x = leftX, y = y, w = BRANCH_BOX_W*2+24, h = FORK_HEIGHT }
                y = y + FORK_HEIGHT + NODE_GAP
            else
                addPlainRow(nodeRects, lvl, y, level)
                y = y + PLAIN_HEIGHT + NODE_GAP
            end
        else
            addPlainRow(nodeRects, lvl, y, level)
            y = y + PLAIN_HEIGHT + NODE_GAP
        end
        lvl = lvl + 1
    end

    local contentH = (y + scrollOff) - LADDER_TOP
    local viewportH = LADDER_BOTTOM - LADDER_TOP
    local maxScroll = math.max(0, contentH - viewportH)
    scrollInfo.content, scrollInfo.view = contentH, viewportH
    scrollOff = math.max(0, math.min(scrollOff, maxScroll))
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

    partyNames = {}
    local po = saveData.partyOrder or {}
    for i = 1, PARTY_SLOTS do
        local name = po[i]
        if type(name) == "string" then
            partyNames[i] = name
        end
    end

    -- Default selection: first active party member.
    selectedChar = partyNames[1]

    if not assetsLoaded then
        assetsLoaded = true
        font       = common.loadFont(13)
        nameFont   = common.loadFont(14)
        smallFont  = common.loadFont(12)
    end
    local uc = (saveData and saveData.unlockedCharacters) or {}
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    hoveredNode    = nil
    hoveredOpt     = nil
    pressedNode    = nil
    hoveredPartySlot = nil
    scrollOff      = 0

    local ix, iy = getPartyRect(1)
    common.initBox(box, ix - BOX_PAD, iy - BOX_PAD, ICON_SIZE + BOX_PAD * 2, ICON_SIZE + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    -- Hover: BACK.
    if common.overBack(vmx, vmy) then
        common.setBoxTarget(box, common.backBoxRect())
    end

    -- Hover: party strip (switch whose ladder is shown).
    hoveredPartySlot = nil
    local boxHit = false
    for i = 1, PARTY_SLOTS do
        local sx, sy, swd, sh = getPartyRect(i)
        if vmx >= sx and vmx < sx + swd and vmy >= sy and vmy < sy + sh then
            hoveredPartySlot = i
            common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, swd + BOX_PAD * 2, sh + BOX_PAD * 2)
            boxHit = true
            break
        end
    end

    -- Hover: ladder nodes (test the per-branch boxes on a fork so hovering one
    -- branch highlights only that branch).
    hoveredNode = nil
    hoveredOpt  = nil
    if not boxHit then
        for lvl, nr in pairs(nodeRects) do
            local hitSub = nil
            if nr.kind == "fork" then
                -- Locked branches can be hovered too (the tooltip previews them).
                if pointInRect(vmx, vmy, nr.left) then hitSub = nr.left
                elseif pointInRect(vmx, vmy, nr.right) then hitSub = nr.right end
            else
                if pointInRect(vmx, vmy, nr) then hitSub = nr end
            end
            if hitSub then
                hoveredNode = nr
                hoveredOpt  = hitSub
                local hx, hy, hw, hh
                if nr.kind == "fork" then
                    hx, hy, hw, hh = hitSub.x - BOX_PAD, hitSub.y - BOX_PAD, hitSub.w + BOX_PAD*2, hitSub.h + BOX_PAD*2
                else
                    hx, hy, hw, hh = nr.hoverRect[1], nr.hoverRect[2], nr.hoverRect[3], nr.hoverRect[4]
                end
                -- Keep the box inside the ladder viewport for half-scrolled rows.
                local top = math.max(hy, LADDER_TOP - 8)
                local bot = math.min(hy + hh, LADDER_BOTTOM + 4)
                common.setBoxTarget(box, hx, top, hw, bot - top)
                boxHit = true
                break
            end
        end
    end
    -- (hoveredNode / hoveredOpt locals are the source of truth for mousereleased)

    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    -- BACK.
    if common.overBack(vmx, vmy) then
        pressedNode = {kind="back"}
        return
    end

    -- Party strip: switch character.
    for i = 1, PARTY_SLOTS do
        local sx, sy, swd, sh = getPartyRect(i)
        if partyNames[i] and vmx >= sx and vmx < sx + swd and vmy >= sy and vmy < sy + sh then
            selectedChar = partyNames[i]
            rebuildLayout()
            common.playClickSound()
            return
        end
    end

    -- Ladder node press: capture WHICH sub-box was pressed so release can act.
    for lvl, nr in pairs(nodeRects) do
        local hitSub
        if nr.kind == "fork" then
            if nr.left and nr.left.state ~= "locked" and pointInRect(vmx, vmy, nr.left)  then hitSub = nr.left  end
            if not hitSub and nr.right and nr.right.state ~= "locked" and pointInRect(vmx, vmy, nr.right) then hitSub = nr.right end
        else
            if pointInRect(vmx, vmy, nr) then hitSub = nr end
        end
        if hitSub then
            if nr.kind == "fork" then
                pressedNode = {kind="fork", idx=nr.idx, opt=hitSub.opt}
            else
                pressedNode = {kind="plain", level=nr.level}
            end
            return
        end
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    local p = pressedNode
    pressedNode = nil
    if not p then return end

    if p.kind == "back" then
        if common.overBack(common.virtualMouse()) then
            common.playClickSound()
            exit()
        end
        return
    end

    -- Branch pick: the pressed sub-box must still be the hovered one (no drag-off)
    -- and it must be a SELECTABLE state (reached + unchosen).
    if p.kind == "fork" and p.opt then
        local ho = hoveredOpt
        local hr = hoveredNode
        -- The pressed branch must STILL be the one under the mouse at release.
        local sameBranch = ho ~= nil and hr ~= nil
            and ( (p.opt == 1 and ho == hr.left) or (p.opt == 2 and ho == hr.right) )
        if sameBranch and ho.state == "selectable" then
            local rec = charRecord(selectedChar)
            if rec then
                local ladder = ladderFor(selectedChar)
                local choice = ladder.choices[p.idx]
                if choice then
                    local level = charLevel(rec)
                    if level >= choice.level then
                        local opt = choice.options[p.opt]
                        if opt then
                            writeChoice(rec, ladder, p.idx, opt.id)
                            common.playClickSound()
                            rebuildLayout()
                            return
                        end
                    end
                end
            end
        end
    end
end

function M.keypressed(key)
    if key == "escape" or key == "return" or key == "kpenter" then
        exit()
    end
end

-- (onExit is intentionally a no-op hook kept for interface symmetry.)
function M.onExit() end

-- Wheel scrolling of the ladder viewport (positive dy = scroll down).
function M.wheel(dy)
    if not selectedChar then return end
    scrollOff = scrollOff + dy * 24
    rebuildLayout()
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawIconSmall(name, x, y, size, alpha)
    local img = icons[name]
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    love.graphics.setColor(1, 1, 1, alpha or 1)
    common.printCentered(font, displayName(name), x, y, size, size)
end

displayName = common.titleCase

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    local backPressed = pressedNode ~= nil and pressedNode.kind == "back"
    common.drawTopBar("TALENTS", backPressed)

    -- Party chips: white = the hero whose ladder is shown.
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartyRect(i)
        local name = partyNames[i]
        love.graphics.setColor(0.05, 0.02, 0.02, 1)
        love.graphics.rectangle("fill", sx, sy, ICON_SIZE, ICON_SIZE)
        local isSel = name ~= nil and name == selectedChar
        love.graphics.setColor(isSel and WHITE or (name and CRIMSON or FAINT))
        love.graphics.setLineWidth(isSel and 2 or 1)
        love.graphics.rectangle("line", sx, sy, ICON_SIZE, ICON_SIZE)
        if name then drawIconSmall(name, sx, sy, ICON_SIZE, isSel and 1 or 0.8) end
    end

    -- Character name + level under the strip.
    if selectedChar then
        local rec = charRecord(selectedChar)
        local lvl = rec and charLevel(rec) or 1
        local pts = rec and rec.pointsToNextLevel
        love.graphics.setFont(nameFont)
        love.graphics.setColor(OFFRED)
        love.graphics.printf(("Lv %d  %s"):format(lvl, displayName(selectedChar)), 0, NAME_Y, VW, "center")
        love.graphics.setFont(smallFont)
        love.graphics.setColor({0.5,0.5,0.5,1})
        local xpTxt = (pts and pts > 0) and ("XP to next level: " .. tostring(pts)) or "Max level"
        love.graphics.printf(xpTxt, 0, XP_Y, VW, "center")
    end

    -- Ladder (scrolled).
    drawLadder()

    -- Animated red box (white when BACK is pressed), BACK on top, tooltip last.
    common.drawBox(box, backPressed)
    common.drawBackButton(backPressed)
    drawHoverTooltip()

    love.graphics.setColor(1, 1, 1, 1)
end

drawLadder = function()
    if not selectedChar then return end
    local rec = charRecord(selectedChar)
    local ladder = ladderFor(selectedChar)
    local level = rec and charLevel(rec) or 1

    love.graphics.push()
    -- Scissor so the scrolling ladder never paints over the desc bar or header.
    love.graphics.setScissor(CENTERLINE_X - BRANCH_BOX_W - 24, LADDER_TOP - 8,
                             (BRANCH_BOX_W + 24) * 2, LADDER_BOTTOM - LADDER_TOP + 12)

    -- Vertical centerline behind the nodes.
    love.graphics.setColor(FAINT)
    love.graphics.setLineWidth(2)
    love.graphics.line(CENTERLINE_X, LADDER_TOP - 4, CENTERLINE_X, LADDER_BOTTOM)

    for lvl, nr in pairs(nodeRects) do
        if nr.kind == "fork" then
            drawForkRow(nr, ladder, level, rec)
        else
            drawPlainRow(nr)
        end
    end

    love.graphics.setScissor()
    love.graphics.pop()

    -- Scrollbar to the right of the ladder when it does not fit (mouse wheel scrolls).
    if scrollInfo.content > scrollInfo.view then
        local sx = CENTERLINE_X + BRANCH_BOX_W + 30
        local trackY, trackH = LADDER_TOP, LADDER_BOTTOM - LADDER_TOP
        local thumbH = math.max(20, trackH * scrollInfo.view / scrollInfo.content)
        local thumbY = trackY + (trackH - thumbH) * scrollOff / (scrollInfo.content - scrollInfo.view)
        love.graphics.setColor(FAINT)
        love.graphics.rectangle("fill", sx, trackY, 4, trackH)
        love.graphics.setColor(CRIMSON)
        love.graphics.rectangle("fill", sx, thumbY, 4, thumbH)
    end
end

drawPlainRow = function(nr)
    local reached = (nr.state == "reached")
    local col = reached and CRIMSON or DIM
    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", nr.x, nr.y, nr.w, nr.h)
    love.graphics.setColor(col)
    love.graphics.setLineWidth(reached and 2 or 1)
    love.graphics.rectangle("line", nr.x, nr.y, nr.w, nr.h)
    love.graphics.setFont(font)
    love.graphics.setColor(reached and WHITE or {0.4,0.2,0.22,1})
    local lbl = "Lv " .. tostring(nr.level)
    love.graphics.print(lbl, nr.x + (nr.w - font:getWidth(lbl))/2,
                        nr.y + (nr.h - font:getHeight())/2)
end

drawForkRow = function(nr, ladder, level, rec)
    local ch = ladder.choices[nr.idx]
    if not ch then return end
    local lbox, rbox = nr.left, nr.right

    -- Connector stubs from the centerline to each branch box.
    love.graphics.setColor(DIM)
    love.graphics.setLineWidth(2)
    local cy = nr.y + FORK_HEIGHT/2
    love.graphics.line(CENTERLINE_X, cy, lbox.x + lbox.w, cy)
    love.graphics.line(CENTERLINE_X, cy, rbox.x, cy)

    -- Center diamond marker (the fork).
    love.graphics.setColor(OFFRED)
    love.graphics.polygon("fill",
        CENTERLINE_X, cy - 6, CENTERLINE_X + 6, cy,
        CENTERLINE_X, cy + 6, CENTERLINE_X - 6, cy)

    drawBranchBox(lbox, ch.options[1], "A")
    drawBranchBox(rbox, ch.options[2], "B")
end

drawBranchBox = function(b, opt, tag)
    -- State colors:
    --   selectable  -> crimson border, dark fill, white name (clickable)
    --   chosen      -> white border, crimson fill, white name (locked-in)
    --   lockedOther -> dim border, darker fill, dim name (forever locked)
    --   locked      -> faint border, near-black fill, faint name (future level)
    local borderCol, fillCol, nameCol, descCol
    if b.state == "selectable" then
        borderCol, fillCol = CRIMSON, {0.10, 0.03, 0.03, 1}
        nameCol, descCol = WHITE, OFFRED
    elseif b.state == "chosen" then
        borderCol, fillCol = WHITE, {0.55, 0.08, 0.14, 1}
        nameCol, descCol = WHITE, {1,0.85,0.85,1}
    elseif b.state == "lockedOther" then
        borderCol, fillCol = {0.28,0.10,0.12,1}, {0.05,0.02,0.02,1}
        nameCol, descCol = {0.45,0.2,0.22,1}, {0.35,0.15,0.17,1}
    else -- locked
        borderCol, fillCol = FAINT, {0.03,0.015,0.015,1}
        nameCol, descCol = {0.30,0.12,0.14,1}, {0.25,0.10,0.12,1}
    end

    love.graphics.setColor(fillCol)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
    love.graphics.setColor(borderCol)
    love.graphics.setLineWidth(b.state == "chosen" and 3 or 2)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h)

    -- Name on the first line, bonus on the second; both cut to the box width
    -- (the hover tooltip has the full text).
    love.graphics.setFont(smallFont)
    love.graphics.setColor(nameCol)
    love.graphics.printf(common.fitText(smallFont, opt.name, b.w - 12), b.x, b.y + 5, b.w, "center")
    love.graphics.setColor(descCol)
    love.graphics.printf(common.fitText(smallFont, opt.desc, b.w - 12), b.x, b.y + b.h - 17, b.w, "center")
end

-- Tooltip for the hovered ladder row or party chip.
drawHoverTooltip = function()
    if hoveredPartySlot and partyNames[hoveredPartySlot] then
        local name = partyNames[hoveredPartySlot]
        local x, y, w, h = getPartyRect(hoveredPartySlot)
        common.drawTooltip({
            { text = displayName(name), size = 16, color = OFFRED },
            { text = "Lv " .. tostring(charLevel(charRecord(name))), color = WHITE },
        }, { x = x, y = y, w = w, h = h })
        return
    end

    local nr, b = hoveredNode, hoveredOpt
    if not (nr and b) then return end
    local lines
    if nr.kind == "plain" then
        lines = { { text = (nr.state == "reached") and ("Level %d reached"):format(nr.level)
                                                     or ("Reach level %d to unlock"):format(nr.level),
                    color = (nr.state == "reached") and WHITE or OFFRED } }
    else
        local ch  = ladderFor(selectedChar).choices[nr.idx]
        local opt = ch and ch.options[b.opt]
        if not opt then return end
        local status, col
        if b.state == "selectable" then
            status, col = "Click to choose. The other option locks for good.", OFFRED
        elseif b.state == "chosen" then
            status, col = "Chosen", WHITE
        elseif b.state == "lockedOther" then
            status, col = "Unavailable: the other option was chosen", {0.6, 0.6, 0.6, 1}
        else
            status, col = ("Reach level %d to choose"):format(nr.level), {0.6, 0.6, 0.6, 1}
        end
        lines = {
            { text = opt.name, size = 16, color = OFFRED },
            { text = opt.desc, color = WHITE },
            { text = status, color = col },
        }
    end
    common.drawTooltip(lines, { x = b.x, y = b.y, w = b.w, h = b.h })
end

function M.draw()
    -- Rebuild layout lazily only when needed (cheap enough to do per-frame here
    -- since the ladder is small; keeps selection/scroll always consistent).
    rebuildLayout()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

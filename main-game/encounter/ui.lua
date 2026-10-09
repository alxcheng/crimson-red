-- encounter/ui.lua — Bar rendering, skill icon rendering, selection circles

local stats_mod = require("encounter/stats")
local common    = require("common")
local statGet   = stats_mod.get

local VW = common.VW
local VH = common.VH

local M = {}

-- ============================================================================
-- SELECTION CIRCLES
-- ============================================================================

function M.updateSelCircles(world, battle, dt)
    for _, id in ipairs(battle.partyIds) do
        local dead   = world.deathState[id] ~= nil
        local target = (not dead and id == battle.selectedUnit) and 1.0 or 0.0
        local curr   = battle.selCircleScales[id] or 0.0
        battle.selCircleScales[id] = curr + (target - curr) * math.min(1, dt * 14)
    end
end

function M.drawShadows(world)
    love.graphics.setColor(0, 0, 0, 0.35)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local pos, sz = world.position[id], world.size[id]
        if not (pos and sz) then goto continue end
        local rx = sz.w * 0.4
        local ry = sz.w * 0.05
        love.graphics.ellipse("fill", pos.x, pos.y + sz.h/2, rx, ry)
        ::continue::
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function M.drawSelectionCircles(world, battle)
    for _, id in ipairs(battle.partyIds) do
        local sc = battle.selCircleScales[id] or 0
        if sc < 0.01 then goto continue end
        local pos, sz = world.position[id], world.size[id]
        if not (pos and sz) then goto continue end
        local rx = (sz.w / 2) * sc
        local ry = (sz.w * 0.18) * sc
        love.graphics.setLineWidth(3)
        love.graphics.setColor(0, 0.85, 0.1, 0.9 * sc)
        love.graphics.ellipse("line", pos.x, pos.y + sz.h/2, rx, ry)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 0.65 * sc)
        love.graphics.ellipse("line", pos.x, pos.y + sz.h/2, rx, ry)
        ::continue::
    end
end

-- ============================================================================
-- HP / STAGGER BARS
-- ============================================================================

function M.barSystem(world, battle)
    local BAR_W = 40; local BAR_H = 4; local BAR_GAP = 2; local ABOVE = 20
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local pos, sz, bar, ss, sg = world.position[id], world.size[id],
                                     world.bar[id], world.stats[id], world.stagger[id]
        if not (pos and sz and bar and ss) then goto continue end

        local topY = pos.y - sz.h/2
        local barX = pos.x - BAR_W/2
        local hpY  = topY - ABOVE - BAR_H
        local stgY = hpY + BAR_H + BAR_GAP

        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", barX-2, hpY-1, BAR_W+4, BAR_H+2)

        local hp    = statGet(ss.HP)
        local maxHp = statGet(ss.maxHP)
        local ratio = (maxHp > 0) and math.max(0, hp/maxHp) or 0
        local r, g, b = unpack(bar.hpColor)
        love.graphics.setColor(r, g, b, 1)
        love.graphics.rectangle("fill", barX, hpY, BAR_W*ratio, BAR_H)

        if bar.hpPrevRatio > ratio then
            love.graphics.setColor(0.9, 0.1, 0.1, 0.6)
            love.graphics.rectangle("fill", barX+BAR_W*ratio, hpY,
                                    BAR_W*(bar.hpPrevRatio-ratio), BAR_H)
        end
        bar.hpPrevRatio = bar.hpPrevRatio + (ratio - bar.hpPrevRatio) * 0.05

        if sg then
            local maxSt   = statGet(ss.MAX_STAGGER)
            love.graphics.setColor(0.18, 0.18, 0.18, 1)
            love.graphics.rectangle("fill", barX, stgY, BAR_W, BAR_H)
            if sg.staggered then
                local staggerDur   = statGet(ss.STAGGER_DUR)
                local staggerRatio = (staggerDur > 0) and math.max(0, sg.timer/staggerDur) or 0
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("fill", barX, stgY, BAR_W*staggerRatio, BAR_H)
            else
                local stRatio = (maxSt > 0) and math.min(1, sg.points/maxSt) or 0
                if stRatio > 0 then
                    love.graphics.setColor(1, 0.85, 0, 1)
                    love.graphics.rectangle("fill", barX, stgY, BAR_W*stRatio, BAR_H)
                end
                love.graphics.setColor(0.75, 0.75, 0.75, 1)
                love.graphics.rectangle("fill", barX+BAR_W-2, stgY, 2, BAR_H)
            end
        end

        if id == battle.hoveredUnit then
            local isEnemy = world.side[id] and world.side[id].s == 1
            local bright  = (id == battle.pressedUnit) and 1.0 or 0.65
            local cr = isEnemy and bright or 0
            local cg = isEnemy and 0      or bright
            love.graphics.setColor(cr, cg, 0, 1)
            love.graphics.setLineWidth(1)
            local plateH = BAR_H + BAR_GAP + BAR_H + 2
            love.graphics.rectangle("line", barX-3, hpY-2, BAR_W+6, plateH)
        end
        ::continue::
    end

    love.graphics.setFont(battle.smallFont)
    for i, id in ipairs(battle.partyIds) do
        local pos, sz = world.position[id], world.size[id]
        if not (pos and sz) then goto continue2 end
        local hpY = pos.y - sz.h/2 - ABOVE - BAR_H
        love.graphics.setColor(id == battle.selectedUnit and {0,1,0,1} or {1,1,1,1})
        love.graphics.print(tostring(i), pos.x - BAR_W/2 - 10, hpY)
        ::continue2::
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- SKILL ICONS
-- ============================================================================

local ICON_SIZE = 50; local ICON_GAP = 5; local ICON_X = 5; local ICON_Y = 5
local SKILL_KEYS = {"q", "w", "e", "r"}

function M.skillIconSystem(world, battle, dt)
    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end
    for slotIdx = 1, 4 do
        local skill = sk.list[slotIdx]
        local ix = ICON_X + (slotIdx-1) * (ICON_SIZE+ICON_GAP)
        local iy = ICON_Y
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        love.graphics.rectangle("fill", ix, iy, ICON_SIZE, ICON_SIZE)
        if skill then
            local iconImg = battle.getIconImage and battle.getIconImage(skill.iconName) or nil
            local sc = skill.iconScale or 1.0
            local cx, cy = ix+ICON_SIZE/2, iy+ICON_SIZE/2
            if iconImg then
                local iw, ih = iconImg:getDimensions()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(iconImg, cx, cy, 0, ICON_SIZE*sc/iw, ICON_SIZE*sc/ih, iw/2, ih/2)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                love.graphics.rectangle("fill", cx-ICON_SIZE*sc/2, cy-ICON_SIZE*sc/2, ICON_SIZE*sc, ICON_SIZE*sc)
            end
            -- Resource sweep: fills from top, shrinks as resource approaches cost
            local cost   = skill.resourceCost or 0
            local curRes = battle.resource or 0
            if cost > 0 and curRes < cost then
                local resRatio = (cost - curRes) / cost
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.rectangle("fill", ix, iy, ICON_SIZE, ICON_SIZE * resRatio)
            end
            -- Fixed cooldown: slight tint + centered second count
            if skill.cd > 0 then
                love.graphics.setColor(0, 0, 0, 0.45)
                love.graphics.rectangle("fill", ix, iy, ICON_SIZE, ICON_SIZE)
                love.graphics.setFont(battle.smallFont)
                love.graphics.setColor(1, 1, 1, 1)
                local cdStr = tostring(math.ceil(skill.cd))
                local tw    = battle.smallFont:getWidth(cdStr)
                local th    = battle.smallFont:getHeight()
                love.graphics.print(cdStr, ix + (ICON_SIZE - tw) / 2, iy + (ICON_SIZE - th) / 2)
            end
            local scTarget = skill.iconScaleTarget or 1.0
            skill.iconScale = (skill.iconScale or 1.0) + (scTarget-(skill.iconScale or 1.0)) * math.min(1, dt*12)
        end
        love.graphics.setFont(battle.smallFont)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print(string.upper(SKILL_KEYS[slotIdx]), ix+2, iy+ICON_SIZE-12)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("line", ix, iy, ICON_SIZE, ICON_SIZE)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- RESOURCE BAR (Clash Royale style, shared party pool)
-- ============================================================================

local RES_PER_SEG   = require("encounter/abilities").RESOURCE_PER_BAR
local RES_SEG_COUNT = 10
local RES_BAR_H     = 8
local RES_MARGIN_X  = 15
local RES_SEG_GAP   = 2
local RES_POP_EXTRA = 10  -- extra height added instantly when a segment fills
local RES_BAR_Y     = VH - RES_BAR_H - 4

function M.drawResourceBar(battle)
    local resource = battle.resource or 0
    local pops     = battle.resourcePops or {}
    local totalW   = VW - 2 * RES_MARGIN_X
    local segW     = (totalW - (RES_SEG_COUNT - 1) * RES_SEG_GAP) / RES_SEG_COUNT

    for i = 1, RES_SEG_COUNT do
        local segX      = RES_MARGIN_X + (i - 1) * (segW + RES_SEG_GAP)
        local fillStart = (i - 1) * RES_PER_SEG
        local fillEnd   = i * RES_PER_SEG
        local pop       = pops[i] or 0
        local extra     = pop * RES_POP_EXTRA
        local cx        = segX + segW / 2
        local cy        = RES_BAR_Y + RES_BAR_H / 2
        local drawW     = segW + extra
        local drawH     = RES_BAR_H + extra
        local drawX     = cx - drawW / 2
        local drawY     = cy - drawH / 2

        love.graphics.setColor(0.15, 0.15, 0.15, 1)
        love.graphics.rectangle("fill", drawX, drawY, drawW, drawH)

        local filled
        if resource >= fillEnd then
            filled = 1.0
        elseif resource > fillStart then
            filled = (resource - fillStart) / RES_PER_SEG
        else
            filled = 0
        end

        if filled > 0 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", drawX, drawY, drawW * filled, drawH)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- ICON SCALE ANIMATION (key hold bounce)
-- ============================================================================

function M.updateIconScaleAnimations(world, battle, dt)
    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end
    for slotIdx = 1, 4 do
        local skill = sk.list[slotIdx]
        if skill then
            local held = love.keyboard.isDown(SKILL_KEYS[slotIdx])
            if held then
                skill.iconScaleTarget = 0.8
            else
                if (skill.iconScale or 1.0) < 0.95 and (skill.iconScaleTarget or 1.0) == 0.8 then
                    skill.iconScaleTarget = 1.1
                else
                    skill.iconScaleTarget = 1.0 + ((skill.iconScaleTarget or 1.0)-1.0) * math.max(0, 1-dt*6)
                end
            end
        end
    end
end

return M

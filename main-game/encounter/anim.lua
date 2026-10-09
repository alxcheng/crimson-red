-- encounter/anim.lua — Sprite animation loading, instancing, timer updates, rendering

local M = {}

-- Shared animation database (populated by loadAnim, persists across onEnter calls)
M.db = {}

function M.load(name, path, frames, fw, fh, defaultScale)
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok then
        print("[anim] missing: " .. path)
        M.db[name] = {img=nil, frames=frames, fw=fw, fh=fh,
                      defaultScale=defaultScale or 1.0, quads={}}
        return
    end
    local quads = {}
    for i = 0, frames-1 do
        quads[i] = love.graphics.newQuad(i*fw, 0, fw, fh, img:getWidth(), img:getHeight())
    end
    M.db[name] = {img=img, frames=frames, fw=fw, fh=fh,
                  defaultScale=defaultScale or 1.0, quads=quads}
end

function M.newInst(name, frameLen, repeating, startActive)
    return {name=name, timer=0, frameLength=frameLen,
            repeat_=repeating, active=startActive or false}
end

function M.updateTimers(world, dt)
    for id in pairs(world.entities) do
        local ac = world.anim[id]; if not ac then goto continue end
        local mt = world.moveTarget[id]
        if ac.list[2] then
            local ph = world.physics[id]
            local sg = world.stagger[id]
            local sn = world.stun[id]
            local moving = not (sg and sg.staggered) and not (sn and sn.stunned) and
                           ((mt and mt.active) or (ph and (math.abs(ph.vx)>5 or math.abs(ph.vy)>5)))
            ac.list[2].active = moving or false
        end
        for _, animInst in pairs(ac.list) do
            if animInst.active then
                animInst.timer = animInst.timer + dt
                local entry = M.db[animInst.name]
                if entry then
                    local totalTime = animInst.frameLength * entry.frames
                    if not animInst.repeat_ and animInst.timer >= totalTime then
                        if animInst.holdAtEnd or animInst.reverse then
                            animInst.timer = totalTime
                        else
                            animInst.active = false; animInst.timer = totalTime
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

-- Sort entities by foot Y for correct draw order
local function getEntitiesSortedByY(world)
    local result = {}
    for id in pairs(world.entities) do
        if world.anim[id] and world.position[id] then
            local sz = world.size[id]
            local py = world.position[id].y + (sz and sz.h/2 or 0)
            table.insert(result, {id=id, sortY=py})
        end
    end
    table.sort(result, function(a, b) return a.sortY < b.sortY end)
    return result
end

function M.drawEntities(world, battle, SCALE)
    local sorted = getEntitiesSortedByY(world)
    for _, entry in ipairs(sorted) do
        local id = entry.id
        local ac, pos = world.anim[id], world.position[id]
        if not (ac and pos) then goto continue end

        local chosen, chosenIdx = nil, 0
        for idx, animInst in pairs(ac.list) do
            if animInst.active and idx > chosenIdx then chosen, chosenIdx = animInst, idx end
        end
        if not chosen then chosen = ac.list[1] end
        if not chosen then goto continue end

        local ds = world.deathState[id]
        if ds and ds.phase == "blinking" and not ds.blinkVisible then goto continue end

        local dbEntry = M.db[chosen.name]
        if not (dbEntry and dbEntry.img) then goto continue end

        local fw, fh = dbEntry.fw, dbEntry.fh
        local drawScale = dbEntry.defaultScale * SCALE
        local rawFrame = math.floor(chosen.timer / chosen.frameLength)
        local frame
        if chosen.reverse then
            frame = (dbEntry.frames-1) - math.min(rawFrame, dbEntry.frames-1)
        elseif chosen.repeat_ then
            frame = rawFrame % dbEntry.frames
        else
            frame = math.min(rawFrame, dbEntry.frames-1)
        end

        local q = dbEntry.quads[frame]; if not q then goto continue end

        local faceRight = world.facing[id] and world.facing[id].right
        local flipSign  = faceRight and 1 or -1
        local sx, sy    = flipSign * drawScale, drawScale

        local so = world.spriteOffset and world.spriteOffset[id]
        local ox = so and so.x or 0
        local oy = so and so.y or 0
        local dx = pos.x + ox * flipSign
        local dy = pos.y + oy

        -- Persistent class recolor (world.tintColor). Zero/absent = no tint,
        -- so untinted units render plain white.
        local tc = world.tintColor and world.tintColor[id]
        local baseR, baseG, baseB = 1, 1, 1
        if tc and (tc.R ~= 0 or tc.G ~= 0 or tc.B ~= 0) then
            baseR, baseG, baseB = tc.R, tc.G, tc.B
        end

        -- Draw sprite with effect tints (undulating RGB modifications)
        local etList = world.effectTints[id]
        if etList and #etList > 0 then
            love.graphics.setColor(baseR, baseG, baseB, 1)
            love.graphics.draw(dbEntry.img, q, dx, dy, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("add")
            for _, et in ipairs(etList) do
                love.graphics.setColor(et.R * et.intensity, et.G * et.intensity, et.B * et.intensity, 1)
                love.graphics.draw(dbEntry.img, q, dx, dy, 0, sx, sy, fw/2, fh/2)
            end
            love.graphics.setBlendMode("alpha")
        else
            love.graphics.setColor(baseR, baseG, baseB, 1)
            love.graphics.draw(dbEntry.img, q, dx, dy, 0, sx, sy, fw/2, fh/2)
        end

        -- Hurt/heal indicator: additive sprite overlay that fades
        local ec = world.effects_comp[id]
        if ec then
            for _, eff in ipairs(ec.active) do
                if eff.alpha and eff.alpha > 0 and eff.target == id then
                    love.graphics.setBlendMode("add")
                    if eff.isHeal then
                        love.graphics.setColor(0, eff.alpha * 0.8, 0, 1)
                    else
                        love.graphics.setColor(eff.alpha * 0.8, 0, 0, 1)
                    end
                    love.graphics.draw(dbEntry.img, q, dx, dy, 0, sx, sy, fw/2, fh/2)
                    love.graphics.setBlendMode("alpha")
                end
            end
        end

        -- Selection highlight: additive white overlay on selected/pressed party unit
        local selAlpha = 0
        if id == battle.pressedUnit  then selAlpha = 0.55
        elseif id == battle.selectedUnit then selAlpha = 0.12
        end
        if selAlpha > 0 then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(selAlpha, selAlpha, selAlpha, 1)
            love.graphics.draw(dbEntry.img, q, dx, dy, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("alpha")
        end

        ::continue::
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Death animation index (highest index in the anim list)
function M.getDeathAnimIdx(world, id)
    local ac = world.anim[id]; if not ac then return 0 end
    local maxIdx = 0
    for idx in pairs(ac.list) do if idx > maxIdx then maxIdx = idx end end
    return maxIdx
end

function M.activateDeathAnim(world, id, holdAtEnd)
    local ac = world.anim[id]; if not ac then return end
    local di = M.getDeathAnimIdx(world, id); if di == 0 then return end
    for _, a in pairs(ac.list) do a.active = false end
    local da = ac.list[di]
    da.active = true; da.timer = 0; da.reverse = nil; da.holdAtEnd = holdAtEnd or false
end

return M

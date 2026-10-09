-- encounter/world.lua — the battle "world": every unit in a fight.
--
-- A unit is just a numeric id. Its data lives in component tables keyed by
-- that id: world.position[id], world.stats[id], ... A unit "has" a component
-- when its entry is non-nil. Systems (encounter/systems.lua, skills.lua, ...)
-- loop over world.entities and read/write the components they care about.
--
--   local world = require("encounter/world").new()
--   local id = world:new()        -- allocate a unit id
--   world:destroy(id)             -- remove the unit from every component table

local M = {}

function M.new()
    local world = {
        entities     = {},   -- [id] = true for every live unit
        nextId       = 1,

        -- Placement & motion (positions are unit CENTERS in virtual pixels;
        -- feet = position.y + size.h / 2)
        position     = {},   -- {x, y}
        size         = {},   -- {w, h} body box
        facing       = {},   -- {right = bool}
        physics      = {},   -- {vx, vy, fx, fy} knockback velocity / pending force
        moveTarget   = {},   -- {x, y, active} where the unit is walking to (center coords)
        hasEntered   = {},   -- {h, v} has walked inside the arena bounds yet
        spriteOffset = {},   -- {x, y} sprite nudge relative to the body box

        -- Allegiance & targeting
        side         = {},   -- {s = 0 party | 1 enemy}
        targetSide   = {},   -- side its default action aims at
        entityTarget = {},   -- {id} current target unit
        threatMap    = {},   -- enemies only: {map = {[heroId] = threat}, decayTimer}
        hasThreateningPresence = {},  -- true = generates double threat
        isRanged     = {},   -- true = acts from range, never walks into melee
        slots        = {},   -- [targetId] = {[slotIndex] = attackerId} melee standing spots
        chaotic      = {},   -- enemies only: true = re-picks a random hero before each attack
        spawnFade    = {},   -- 0..1 fade-in of a unit that appeared inside the arena (nil = done)

        -- Combat state
        stats        = {},   -- stat table (encounter/stats.lua)
        skills       = {},   -- {list = {[slot] = skill}, queue, abilityQueue, execGate}
        effects_comp = {},   -- {pending = {}, active = {}} running effects (effects.lua)
        status       = {},   -- {buffs = {}, debuffs = {}} (status.lua)
        locks        = {},   -- {actionLock, moveLock} seconds the unit cannot act / move
        stagger      = {},   -- {points, staggered, timer}
        stun         = {},   -- {stunned, timer}
        deathState   = {},   -- {phase, timer, ...} set once HP hits 0

        -- Presentation
        anim         = {},   -- {list = {[i] = animation instance}}
        tintColor    = {},   -- {R, G, B} permanent sprite recolor (0,0,0 = none)
        effectTints  = {},   -- list of pulsing tints from active statuses
        bar          = {},   -- health-bar animation state
    }
    function world:new()
        local id = self.nextId; self.nextId = id + 1
        self.entities[id] = true; return id
    end
    function world:destroy(id)
        self.entities[id] = nil
        for _, pool in pairs(self) do
            if type(pool) == "table" then pool[id] = nil end
        end
    end
    return world
end

return M

-- encounter/stats.lua — Stat creation and evaluation helpers

local M = {}

function M.newStat(base)  return {base=base, add=0, mult=1} end
function M.get(s)         return (s.base * s.mult) + s.add end

-- Derived "power" getter: the attacker-side damage base.
-- Battleheart uses a dedicated `power` stat; CR keeps `ATK` as the
-- underlying field (other code reads it), so power is derived, not renamed.
function M.getPower(s) return M.get(s.ATK) end

-- Build a battle stat table from flat numbers:
--   flat = { maxHP, ATK, DEF, CRIT }   (CRIT is a 0..1 chance)
-- Heroes get theirs from progression.heroStats; enemies from data/enemies.lua.
-- Stagger: a unit is knocked down once it has taken half its max HP in
-- damage since the last knock-down.                                 [tuned]
function M.fromFlat(flat)
    local hp = flat.maxHP or 100
    return {
        HP          = M.newStat(hp),
        maxHP       = M.newStat(hp),
        RES         = M.newStat(1.0),
        BOOST       = M.newStat(1.0),
        DEF         = M.newStat(flat.DEF  or 0),
        ATK         = M.newStat(flat.ATK  or 0),
        CRIT        = M.newStat(flat.CRIT or 0),
        CRIT_DEF    = M.newStat(0.05),
        MOVE_SPEED  = M.newStat(2.0),
        -- Attack speed: 1.0 = normal. It divides the default-action interval
        -- (skills.lua) and nothing else — animations never speed up (BH rule:
        -- haste shortens primaryActionCooldown / speeds its timer).
        ATK_SPEED   = M.newStat(1.0),
        STAGGER_RES = M.newStat(1.0),
        MAX_STAGGER = M.newStat(hp * 0.5),
        STAGGER_DUR = M.newStat(10),
    }
end

return M

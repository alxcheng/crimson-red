-- encounter/stats.lua — Stat creation and evaluation helpers

local M = {}

function M.newStat(base)  return {base=base, add=0, mult=1} end
function M.get(s)         return (s.base * s.mult) + s.add end

-- Derived "power" getter: the attacker-side damage base.
-- Battleheart uses a dedicated `power` stat; CR keeps `ATK` as the
-- underlying field (other code reads it), so power is derived, not renamed.
function M.getPower(s) return M.get(s.ATK) end

function M.newStats(hp, atk, def, crit, atkspd)
    return {
        HP          = M.newStat(hp     or 100),
        maxHP       = M.newStat(hp     or 100),
        RES         = M.newStat(1.0),
        BOOST       = M.newStat(1.0),
        DEF         = M.newStat(def    or 5),
        ATK         = M.newStat(atk    or 10),
        CRIT        = M.newStat(crit   or 0.10),
        CRIT_DEF    = M.newStat(0.05),
        MOVE_SPEED  = M.newStat(2.0),
        ATK_SPEED   = M.newStat(atkspd or 2.0),
        STAGGER_RES = M.newStat(1.0),
        MAX_STAGGER = M.newStat(50),
        STAGGER_DUR = M.newStat(10),
    }
end

-- Build battle stats from a character's saved stat table (save.lua).
-- gear (optional): equipped item instances keyed by slot, e.g.
-- { weapon = inst, armor = inst, trinket = inst }; each instance's flat `mods`
-- are added to the matching stat. Gear only ever enters stats here.
function M.fromSave(ss, gear)
    local s = {
        HP          = M.newStat(ss.maxHP or 100),
        maxHP       = M.newStat(ss.maxHP or 100),
        RES         = M.newStat(ss.RES   or 1.0),
        BOOST       = M.newStat(ss.BOOST or 1.0),
        DEF         = M.newStat(ss.DEF   or 5),
        ATK         = M.newStat(ss.ATK   or 10),
        CRIT        = M.newStat(ss.CRIT  or 0.10),
        CRIT_DEF    = M.newStat(ss.CRITDEF  or 0.05),
        MOVE_SPEED  = M.newStat(2.0),
        ATK_SPEED   = M.newStat(ss.ATKSPD  or 1.0),
        STAGGER_RES = M.newStat(ss.STAGGERres or 1.0),
        MAX_STAGGER = M.newStat(ss.maxSTAGGER or 50),
        STAGGER_DUR = M.newStat(ss.STAGGERdur or 10),
    }
    if gear then
        for _, inst in pairs(gear) do
            if type(inst) == "table" then
                for k, v in pairs(inst.mods or {}) do
                    if s[k] then s[k].add = s[k].add + v end
                end
            end
        end
    end
    return s
end

return M

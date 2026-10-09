-- progression.lua — character XP & level-ups (feeds the TALENTS ladder).
--
-- Implements the plan in work/non-encounter-systems-research.md §5: XP is
-- granted on a WON encounter and split evenly among the SURVIVING party
-- members (BH's totalLivingPartyMembers split); several level-ups in one win
-- are allowed. All numbers are [tuned] placeholders (the BH XP table is not
-- extractable) — retune here.
--
-- Save fields used (per saveData.unlockedCharacters[name]):
--   level              current level (>= 1)
--   pointsToNextLevel  XP still needed to reach level + 1

local M = {}

M.XP_FIRST  = 50     -- [tuned] XP to go from level 1 to 2
M.XP_SCALE  = 1.22   -- [tuned] geometric growth per level
M.MAX_LEVEL = 21     -- [tuned] last choice level on the talent ladders

-- XP needed to go from `level` to `level + 1`.
function M.xpToNext(level)
    return math.floor(M.XP_FIRST * M.XP_SCALE ^ ((level or 1) - 1) + 0.5)
end

-- Total XP a won encounter is worth on this floor, before the split.
function M.victoryXP(floor)
    return 40 + 15 * (floor or 1)   -- [tuned]
end

-- Add `amount` XP to one character record. Returns the number of levels gained.
function M.addXP(rec, amount)
    if type(rec) ~= "table" or not amount or amount <= 0 then return 0 end
    rec.level = (type(rec.level) == "number" and rec.level >= 1) and math.floor(rec.level) or 1
    if rec.level >= M.MAX_LEVEL then
        rec.pointsToNextLevel = 0
        return 0
    end
    local need = rec.pointsToNextLevel
    if type(need) ~= "number" or need <= 0 then need = M.xpToNext(rec.level) end
    need = need - amount
    local gained = 0
    while need <= 0 and rec.level < M.MAX_LEVEL do
        rec.level = rec.level + 1
        gained = gained + 1
        need = need + M.xpToNext(rec.level)
    end
    rec.pointsToNextLevel = (rec.level >= M.MAX_LEVEL) and 0 or math.floor(need)
    return gained
end

-- Award a won encounter's XP to the surviving party members (array of
-- character keys). Returns { [name] = levelsGained } for those who levelled.
function M.onEncounterWon(saveData, survivors)
    local levelUps = {}
    if not saveData or type(survivors) ~= "table" or #survivors == 0 then return levelUps end
    local share = math.floor(M.victoryXP(saveData.floor) / #survivors)
    local uc = saveData.unlockedCharacters or {}
    for _, name in ipairs(survivors) do
        local gained = M.addXP(uc[name], share)
        if gained > 0 then levelUps[name] = gained end
    end
    return levelUps
end

return M

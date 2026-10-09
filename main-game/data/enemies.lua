-- data/enemies.lua — every enemy type, as data.
--
-- To add an enemy: add a row here (and its sprite sheets in data/sprites.lua,
-- its attack in data/abilities.lua). encounter/entities.lua builds the unit;
-- encounter/encounter_mgr.lua spawns it by spending the wave's danger budget.
--
-- Row fields:
--   name       display name
--   size       {w, h} body box in art pixels (multiplied by the battle SCALE)
--   stats      {hp, power}. Enemies have no defense and never crit (BH rule).
--   moveSpeed  MOVE_SPEED
--   anims      entry in data/classes.lua ANIM_SETS
--   danger     how much of a wave's danger budget one of these costs, and how
--              much it adds to the encounter's progress when killed
--   auto       ability id of its attack
-- BH's real enemy stats are in bh/data/prefabs/EnemyScript.json.

local M = {}

M.ENEMIES = {
    skeleton = {
        name = "Skeleton", size = {40, 40}, anims = "skeleton",
        -- BH's basic goblin ("basic1"): 500 health, 70 power, attacks every 1.3 s.
        stats = {hp = 500, power = 70},
        moveSpeed = 1.5, danger = 3,
        auto = "SkeletonAutoAttack",
    },
}

-- Enemy ids the wave spawner may pick from, cheapest first.
M.SPAWN_POOL = { "skeleton" }

return M

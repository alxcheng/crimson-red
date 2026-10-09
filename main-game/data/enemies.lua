-- data/enemies.lua — every enemy type, as data.
--
-- To add an enemy: add a row here (and its sprite sheets in data/sprites.lua,
-- its attack in data/abilities.lua, its animation set in data/classes.lua
-- ANIM_SETS). encounter/entities.lua builds the unit; encounter/wave_gen.lua
-- decides which ones a battle contains; encounter/encounter_mgr.lua spawns them.
--
-- Row fields:
--   name       display name
--   spriteScale how big it is drawn. THE one size knob: its body box, feet and
--              sprite position all follow from it (see data/sprite_bounds.lua)
--   stats      {hp, power}. Enemies have no defense and never crit (BH rule).
--   moveSpeed  MOVE_SPEED = BH moveSpeed x SPEED_SCALE (x30 = pixels/second)
--   anims      entry in data/classes.lua ANIM_SETS
--   auto       ability id of its attack
--   ranged     true = stands where it spawned and shoots (BH AIType 2)
--   chaotic    true = picks a new random hero before every attack (BH `chaotic`)
--   spawn      where it appears (BH spawningStyle):
--                "right"  walks in from the right edge (style 1)
--                "left"   walks in from the left edge  (style 4)
--                "inside" appears at a random spot inside the arena (styles 2/3)
--   danger     its weight when encounter/wave_gen.lua fills a wave's budget
--   minTier    first battle tier (1 = a floor's first battle) it can appear in
--
-- CONFUSING NAMES (the Director's mapping, 2026-10-09): the STATS come from one
-- BH monster and the SPRITE from another.
--   CR skeleton = BH goblin (basic1)          CR goblin   = BH bat (basic2)
--   CR bat      = BH skeleton archer (basic4) CR mushroom = BH ogre (basic3)
-- BH's numbers are in bh/data/prefabs/EnemyScript.json.

local M = {}

M.SPEED_SCALE = 1.667   -- BH moveSpeed -> CR MOVE_SPEED (BH goblin 0.9 -> 1.5)   [tuned]

M.ENEMIES = {
    skeleton = {
        name = "Skeleton", spriteScale = 0.75, anims = "skeleton",
        stats = {hp = 500, power = 70},          -- BH basic1: attacks every 1.3 s
        moveSpeed = 1.5, spawn = "right",
        danger = 2, minTier = 1,
        auto = "SkeletonAutoAttack",
    },
    goblin = {
        name = "Goblin", spriteScale = 0.75, anims = "goblin",
        stats = {hp = 375, power = 80},          -- BH basic2 (bat): fast and frail, every 1.16 s
        moveSpeed = 1.83, spawn = "right",       -- BH 1.1
        danger = 2, minTier = 1,
        auto = "GoblinAutoAttack",
    },
    bat = {
        name = "Bat", spriteScale = 0.75, anims = "bat",
        stats = {hp = 600, power = 95},          -- BH basic4 (skeleton archer): shoots every 1.8 s
        moveSpeed = 1.0, spawn = "inside",       -- never moves: appears in the arena and shoots
        ranged = true, chaotic = true,
        danger = 4, minTier = 2,
        auto = "BatAutoShot",
    },
    mushroom = {
        name = "Mushroom", spriteScale = 1.25, anims = "mushroom",
        stats = {hp = 2200, power = 165},        -- BH basic3 (ogre): slow and heavy, every 1.5 s
        moveSpeed = 0.83, spawn = "right",       -- BH 0.5
        danger = 8, minTier = 3,                 -- costly: one per wave until late battles
        auto = "MushroomAutoAttack",
    },
}

return M

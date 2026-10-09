-- data/classes.lua — every playable class, as data.
--
-- To add a class: add a row here (and its sprite sheets in data/sprites.lua,
-- its abilities in data/abilities.lua). No code changes are needed —
-- encounter/entities.lua builds the battle unit from this row.
--
-- Row fields:
--   name        display name
--   size        {w, h} body box in art pixels (multiplied by the battle SCALE)
--   stats       {hp, atk, def, crit} class base stats, used when a save record
--               carries no stats of its own            [tuned] unless tagged
--   moveSpeed   optional MOVE_SPEED override (default 2.0)
--   anims       name of an entry in M.ANIM_SETS (frame timing per action)
--   tint        optional {r, g, b} persistent recolor of the sprite
--   spriteOffsetY optional vertical sprite nudge in pixels
--   ranged      true = never walks into melee; acts from where it stands
--   targetsAllies true = its default action targets its own side (healers)
--   drawsThreat true = its hits generate double threat (tanks)
--   passive     optional passive effect id (see encounter/effects.lua PASSIVES)
--   auto        ability id of the default action (slot 0)
--   actives     ability ids for slots 1..4 (keys Q/W/E/R)

local M = {}

-- Animation sets: list index = draw priority (highest active index wins; the
-- LAST entry is the death animation). Each entry: {sheet suffix, seconds per
-- frame, loops, starts active}. The sheet name is <sprite><suffix>, looked up
-- in data/sprites.lua.
M.ANIM_SETS = {
    knight = { sprite = "Knight", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 6/60},
        {"Attack2", 12/60}, {"TakeHit", 6/60}, {"Death", 6/60} } },
    brigand = { sprite = "Brigand", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 6/60}, {"Death", 6/60} } },
    champion = { sprite = "Champion", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 6/60}, {"Death", 6/60} } },
    duelist = { sprite = "Duelist", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 6/60}, {"Death", 6/60} } },
    nomad = { sprite = "Nomad", list = {
        {"Idle", 8/60, true, true}, {"Move", 8/60, true}, {"Attack1", 6/60},
        {"Attack2", 6/60}, {"Death", 6/60} } },
    skeleton = { sprite = "Skeleton", list = {
        {"Idle", 8/60, true, true}, {"Move", 8/60, true}, {"Attack", 6/60}, {"Death", 6/60} } },
}

M.CLASSES = {
    -- ---- Crimson Red originals -------------------------------------------
    knight = {
        name = "Knight", size = {30, 40}, anims = "knight",
        stats = {hp = 100, atk = 10, def = 5, crit = 0.10},
        drawsThreat = true, passive = "KnightRage",
        auto = "KnightAutoAttack",
        actives = { "KnightSunderArmor", "KnightDefend", "KnightChallengingShout" },
    },
    brigand = {
        name = "Brigand", size = {30, 40}, anims = "brigand", spriteOffsetY = 5,
        stats = {hp = 100, atk = 10, def = 5, crit = 0.10},
        auto = "BrigandAutoAttack", actives = {},
    },
    champion = {
        name = "Champion", size = {32, 52}, anims = "champion", spriteOffsetY = -35,
        stats = {hp = 100, atk = 10, def = 5, crit = 0.10},
        auto = "ChampionAutoAttack", actives = {},
    },
    duelist = {
        name = "Duelist", size = {27.6, 41.88}, anims = "duelist",
        stats = {hp = 100, atk = 10, def = 5, crit = 0.10},
        auto = "DuelistAutoAttack", actives = {},
    },
    nomad = {
        name = "Nomad", size = {29.43, 38.97}, anims = "nomad", spriteOffsetY = -18,
        stats = {hp = 80, atk = 8, def = 2, crit = 0.05},
        ranged = true, targetsAllies = true,
        auto = "NomadAutoHeal",
        actives = { "NomadGrantPower", "NomadMendWounds", "NomadSparkOfInspiration" },
    },

    -- ---- Ported from Battleheart (see bh/README.md) ------------------------
    -- These four reuse the Knight sprite with a tint until they get their own art.
    cleric = {   -- BH Cleric (Lucille): healer, no attack; default action is a heal
        name = "Cleric", size = {29.43, 38.97}, anims = "knight", tint = {1, 0.85, 0.2},
        stats = {hp = 300, atk = 16, def = 9, crit = 0}, moveSpeed = 3.0,
        ranged = true, targetsAllies = true,
        auto = "ClericAutoHeal",
        actives = { "ClericGroupHeal", "ClericShield", "ClericPowerInfusion", "ClericVengefulAngel" },
    },
    paladin = {  -- BH Paladin (Heleth): tank / off-healer
        name = "Paladin", size = {30, 40}, anims = "knight", tint = {0.4, 1, 0.4},
        stats = {hp = 520, atk = 24, def = 24, crit = 0}, moveSpeed = 2.8,
        drawsThreat = true,
        auto = "PaladinAutoAttack",
        actives = { "PaladinHolyWord", "PaladinDivineIntervention", "PaladinAuraOfLight", "PaladinWrath" },
    },
    wizard = {   -- BH Wizard (Bromswell): ranged damage + crowd control
        name = "Wizard", size = {29.43, 38.97}, anims = "knight", tint = {1, 0.5, 0.9},
        stats = {hp = 260, atk = 28, def = 5, crit = 0}, moveSpeed = 3.2,
        ranged = true,
        auto = "WizardAutoFireball",
        actives = { "WizardMeteor", "WizardBlizzard", "WizardTimeStop", "WizardConflagrate" },
    },
    rogue = {    -- BH Rogue (Gustav): fast melee burst
        name = "Rogue", size = {30, 40}, anims = "knight", tint = {0.63, 0.09, 0.14},
        stats = {hp = 300, atk = 31, def = 11, crit = 0.20}, moveSpeed = 3.4,
        auto = "RogueAutoAttack",
        actives = { "RogueSneakAttack", "RogueExposeWeakness", "RogueShadowstep", "RoguePoisonedKnife" },
    },
}

-- Classes that exist in save files / the party screen but have no battle unit
-- yet (no row above): hunter, jester, piper, witch. Selecting one fields no
-- unit. Add a row here to make it playable.

return M

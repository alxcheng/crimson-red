-- data/classes.lua — every playable class, as data.
--
-- To add a class: add a row here (and its sprite sheets in data/sprites.lua,
-- its abilities in data/abilities.lua). No code changes are needed —
-- encounter/entities.lua builds the battle unit from this row.
--
-- Row fields:
--   name        display name
--   spriteScale how big the hero is drawn. THE one size knob: the body box, the
--               feet and the sprite position all follow from it (data/sprite_bounds.lua)
--   base        level-1 stats before gear: {hp, power, defense, crit}. hp/power/
--               defense are Battleheart's values (bh/data/party.json); crit is a
--               0..1 chance [tuned]
--   scale       added per level above 1: {power, defense, hp} (bh/data/classes.json)
--               stat = base + scale * (level - 1) + gear + talents
--               (see progression.heroStats)
--   starterGear {weapon, armor} BH item ids a new recruit comes with
--               (data/bh_items.lua)
--   anims       name of an entry in M.ANIM_SETS (frame timing per action)
--   tint        optional {r, g, b} persistent recolor of the sprite
--   ranged      true = never walks into melee; acts from where it stands
--   targetsAllies true = its default action targets its own side (healers)
--   drawsThreat true = its hits generate double threat (tanks)
--   passive     optional passive effect id (see encounter/effects.lua PASSIVES)
--   auto        ability id of the default action (slot 0)
--   actives     ability ids for slots 1..4 (keys Q/W/E/R)

local M = {}

-- Animation sets: list index = draw priority (highest active index wins; the
-- LAST entry is the death animation). Each entry: {sheet suffix, seconds per
-- frame, loops, starts active}. Attack frames last 7/60 s (one tick longer
-- than the other animations' 6/60) so swings read clearly; the hit `delay`
-- values in data/abilities.lua are timed to these frames. The sheet name is <sprite><suffix>, looked up
-- in data/sprites.lua.
M.ANIM_SETS = {
    knight = { sprite = "Knight", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 7/60},
        {"Attack2", 13/60}, {"TakeHit", 6/60}, {"Death", 6/60} } },
    -- cleric / paladin / wizard / rogue: the knight's set on their own sheets (added below).
    brigand = { sprite = "Brigand", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 7/60}, {"Death", 6/60} } },
    champion = { sprite = "Champion", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 7/60}, {"Death", 6/60} } },
    duelist = { sprite = "Duelist", list = {
        {"Idle", 10/60, true, true}, {"Move", 6/60, true}, {"Attack1", 7/60}, {"Death", 6/60} } },
    nomad = { sprite = "Nomad", list = {
        {"Idle", 8/60, true, true}, {"Move", 8/60, true}, {"Attack1", 7/60},
        {"Attack2", 7/60}, {"Death", 6/60} } },
    skeleton = { sprite = "Skeleton", list = {
        {"Idle", 8/60, true, true}, {"Move", 8/60, true}, {"Attack", 7/60}, {"Death", 6/60} } },
    goblin = { sprite = "Goblin", list = {
        {"Idle", 8/60, true, true}, {"Move", 6/60, true}, {"Attack", 7/60}, {"Death", 6/60} } },
    bat = { sprite = "Bat", list = {
        {"Idle", 6/60, true, true}, {"Move", 6/60, true}, {"Attack", 7/60}, {"Death", 6/60} } },
    mushroom = { sprite = "Mushroom", list = {
        {"Idle", 8/60, true, true}, {"Move", 8/60, true}, {"Attack", 7/60}, {"Death", 6/60} } },
}

for key, sprite in pairs({ cleric = "Cleric", paladin = "Paladin", wizard = "Wizard", rogue = "Rogue" }) do
    M.ANIM_SETS[key] = { sprite = sprite, list = M.ANIM_SETS.knight.list }
end

-- Every hero walks at the same speed (MOVE_SPEED units; x30 = pixels/second).
-- 2.4 = 80% of 3.0, which is BH's standard hero speed (1.5 world units/s) at
-- the 2x conversion the ported classes used.                          [tuned]
M.HERO_MOVE_SPEED = 2.4

M.CLASSES = {
    -- ---- Crimson Red originals -------------------------------------------
    knight = {
        name = "Knight", spriteScale = 1.1, anims = "knight",
        base  = {hp = 1000, power = 20, defense = 15, crit = 0.10},   -- BH Knight (Shepherd)
        scale = {power = 1.0, defense = 1.2, hp = 15},
        starterGear = {0, 4},
        drawsThreat = true, passive = "KnightRage",
        auto = "KnightAutoAttack",
        actives = { "KnightSunderArmor", "KnightDefend", "KnightChallengingShout" },
    },
    brigand = {
        name = "Brigand", spriteScale = 0.9, anims = "brigand",
        base  = {hp = 1000, power = 26, defense = 8, crit = 0.10},   -- borrowed from BH Rogue [tuned]
        scale = {power = 1.0, defense = 1.0, hp = 15},
        starterGear = {1, 5},
        auto = "BrigandAutoAttack", actives = {},
    },
    champion = {
        name = "Champion", spriteScale = 1, anims = "champion",
        base  = {hp = 1000, power = 28, defense = 7, crit = 0.10},   -- borrowed from BH Barbarian (Baelrosh) [tuned]
        scale = {power = 1.0, defense = 1.0, hp = 15},
        starterGear = {11, 5},
        auto = "ChampionAutoAttack", actives = {},
    },
    duelist = {
        name = "Duelist", spriteScale = 0.959, anims = "duelist",
        base  = {hp = 1000, power = 20, defense = 15, crit = 0.10},   -- borrowed from BH Monk (Feung) [tuned]
        scale = {power = 1.0, defense = 1.2, hp = 15},
        starterGear = {43, 44},
        auto = "DuelistAutoAttack", actives = {},
    },
    nomad = {
        name = "Nomad", spriteScale = 0.72, anims = "nomad",
        base  = {hp = 1000, power = 12, defense = 6, crit = 0.05},   -- borrowed from BH Bard (Edwardo) [tuned]
        scale = {power = 1.0, defense = 1.0, hp = 15},
        starterGear = {45, 5},
        ranged = true, targetsAllies = true,
        auto = "NomadAutoHeal",
        actives = { "NomadGrantPower", "NomadMendWounds", "NomadSparkOfInspiration" },
    },

    -- ---- Ported from Battleheart (see bh/README.md) ------------------------
    -- These four use recoloured copies of the Knight sheets (made with ./recolor: only
    -- the blue clothes are shifted to another colour; see RECOLOURS in data/sprites.lua).
    cleric = {   -- BH Cleric (Lucille): healer, no attack; default action is a heal
        name = "Cleric", spriteScale = 1.1, anims = "cleric",
        base  = {hp = 1000, power = 65, defense = 4, crit = 0},   -- BH Cleric (Lucille)
        scale = {power = 3.0, defense = 1.0, hp = 15},
        starterGear = {2, 6},
        ranged = true, targetsAllies = true,
        auto = "ClericAutoHeal",
        actives = { "ClericGroupHeal", "ClericShield", "ClericPowerInfusion", "ClericVengefulAngel" },
    },
    paladin = {  -- BH Paladin (Heleth): tank / off-healer
        name = "Paladin", spriteScale = 1.1, anims = "paladin",
        base  = {hp = 1000, power = 19, defense = 18, crit = 0},   -- BH Paladin (Heleth)
        scale = {power = 1.0, defense = 1.2, hp = 15},
        starterGear = {0, 4},
        drawsThreat = true,
        auto = "PaladinAutoAttack",
        actives = { "PaladinHolyWord", "PaladinDivineIntervention", "PaladinAuraOfLight", "PaladinWrath" },
    },
    wizard = {   -- BH Wizard (Bromswell): ranged damage + crowd control
        name = "Wizard", spriteScale = 1.1, anims = "wizard",
        base  = {hp = 1000, power = 33, defense = 0, crit = 0},   -- BH Wizard (Bromswell)
        scale = {power = 1.0, defense = 1.0, hp = 15},
        starterGear = {3, 6},
        ranged = true,
        auto = "WizardAutoFireball",
        actives = { "WizardMeteor", "WizardBlizzard", "WizardTimeStop", "WizardConflagrate" },
    },
    rogue = {    -- BH Rogue (Gustav): fast melee burst
        name = "Rogue", spriteScale = 1.1, anims = "rogue",
        base  = {hp = 1000, power = 26, defense = 8, crit = 0.20},   -- BH Rogue (Gustav)
        scale = {power = 1.0, defense = 1.0, hp = 15},
        starterGear = {1, 5},
        auto = "RogueAutoAttack",
        actives = { "RogueSneakAttack", "RogueExposeWeakness", "RogueShadowstep", "RoguePoisonedKnife" },
    },
}

-- Classes that exist in save files / the party screen but have no battle unit
-- yet (no row above): hunter, jester, piper, witch. Selecting one fields no
-- unit. Add a row here to make it playable.

return M

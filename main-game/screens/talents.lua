-- screens/talents.lua — Academy / Talent screen module (per-class LINEAR ladder)
--
-- Battleheart's "Academy" is NOT a point-spend tree: it is a LINEAR per-class
-- level LADDER with a BINARY CHOICE every few levels (work/non-encounter-systems-
-- research.md §5). This file ports that shape: a vertical list of level nodes,
-- where every CHOICE_EVERY levels is a fork of two small passive bonuses — pick
-- one, the other locks. Between forks are plain level nodes (auto stat bump).
--
-- The player views ONE character at a time (picked from the active-party strip
-- on top). When the character has REACHED a choice level but not yet chosen, a
-- click on a branch records the pick into saveData.unlockedCharacters[name].
-- skillTree and folds the passive's stat mods into .stats. Reaching more levels
-- unlocks more choice nodes; future (unreached) nodes are dim/locked.
--
-- PERSISTENCE: same field as before — unlockedCharacters[name].skillTree — now
-- meaning "chosen branch id per choice-level". Backward compatible: the old
-- numeric placeholder array ({1,1,1,1,1}) reads as "nothing chosen yet" and is
-- overwritten slot-by-slot with option ids as picks are made.
--
-- XP GRANTING IS OUT OF SCOPE here (economy-dev / encounter-win path owns it).
-- This screen only READS rec.level and rec.pointsToNextLevel for display. Until
-- XP is granted the ladder simply shows a level-1 character — fully functional,
-- nothing crashes, no choices selectable (all unreached). That is by design.

local common   = require("common")
local save     = require("save")
local anim_mod = require("encounter/anim")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- PALETTE (project: crimson red / off-red / white on black)
-- ============================================================================

local CRIMSON = {0.84, 0.07, 0.16, 1}   -- crimson red  (primary accent)
local OFFRED  = {1.00, 0.42, 0.42, 1}   -- off-red      (hover accent)
local WHITE   = {1.00, 1.00, 1.00, 1}   -- white        (pressed/active/chosen)
local DIM     = {0.32, 0.12, 0.14, 1}   -- locked/future nodes
local FAINT   = {0.16, 0.06, 0.07, 1}   -- very dim (empty cells, connectors)

-- ============================================================================
-- LADDER DATA  [tuned] — per-class linear ladder with binary choices
--
-- Shape:
--   LADDER[class] = {
--       title     = string,                 -- flavour header
--       autoBump  = { <statKey> = perLevel },  -- auto stat gain each non-choice level
--       choices   = {                       -- binary choice nodes, ascending level
--           { level = 3, options = {
--               {id="atk",  name="...", desc="...", mods={ATK=3}},
--               {id="hp",   name="...", desc="...", mods={maxHP=25}},
--           } },
--           { level = 6, ... },
--       },
--   }
-- Choice cadence: every CHOICE_EVERY levels (3), matching the Director's final
-- call (faster than BH's ~5, see research §5(c)). Passives are SIMPLE STAT MODS
-- (self-contained here); magnitudes are [tuned] placeholders — retune freely.
-- Only ATK / DEF / maxHP / CRIT are used because those keys exist in the save's
-- DEFAULT_STATS table (save.lua) and fold straight into rec.stats.
-- ============================================================================

local CHOICE_EVERY = 3

-- Generic fallback ladder for any class without its own flavor row.
local GENERIC_LADDER = {
    title  = "War Training",
    autoBump = { ATK = 1, DEF = 1, maxHP = 5 },
    choices = {
        { level = 3,  options = {
            { id = "atk", name = "Keen Edge",   desc = "+4 ATK",                  mods = { ATK = 4 } },
            { id = "def", name = "Steady Guard",desc = "+3 DEF, +15 HP",          mods = { DEF = 3, maxHP = 15 } },
        }},
        { level = 6,  options = {
            { id = "hp",  name = "Hardened",    desc = "+40 max HP",              mods = { maxHP = 40 } },
            { id = "crit",name = "Precise",     desc = "+8% CRIT chance",         mods = { CRIT = 0.08 } },
        }},
        { level = 9,  options = {
            { id = "atk2",name = "Might",       desc = "+7 ATK",                  mods = { ATK = 7 } },
            { id = "def2",name = "Bulwark",     desc = "+6 DEF",                  mods = { DEF = 6 } },
        }},
        { level = 12, options = {
            { id = "all1",name = "Veteran",     desc = "+5 ATK, +5 DEF, +30 HP",  mods = { ATK = 5, DEF = 5, maxHP = 30 } },
            { id = "crit2",name = "Deadly",     desc = "+15% CRIT chance",        mods = { CRIT = 0.15 } },
        }},
        { level = 15, options = {
            { id = "atk3",name = "Overwhelming",desc = "+12 ATK",                 mods = { ATK = 12 } },
            { id = "hp2", name = "Titanic",     desc = "+80 max HP",              mods = { maxHP = 80 } },
        }},
        { level = 18, options = {
            { id = "def3",name = "Impregnable", desc = "+12 DEF",                 mods = { DEF = 12 } },
            { id = "crit3",name = "Executioner",desc = "+20% CRIT chance",        mods = { CRIT = 0.20 } },
        }},
        { level = 21, options = {
            { id = "all2",name = "Legendary",   desc = "+10 ATK, +10 DEF, +60 HP",mods = { ATK = 10, DEF = 10, maxHP = 60 } },
            { id = "crit4",name = "Mythic",     desc = "+25% CRIT chance",        mods = { CRIT = 0.25 } },
        }},
    },
}

local LADDER = {
    -- Tank line: durability + threat.
    knight  = {
        title  = "Shield Mastery",
        autoBump = { DEF = 1, maxHP = 8 },
        choices = {
            { level = 3,  options = {
                { id = "guard", name = "Iron Guard",  desc = "+6 DEF",                        mods = { DEF = 6 } },
                { id = "thick", name = "Thick Skin",  desc = "+50 max HP",                    mods = { maxHP = 50 } },
            }},
            { level = 6,  options = {
                { id = "taunt", name = "Provoker",    desc = "+8 DEF, +20 HP",                mods = { DEF = 8, maxHP = 20 } },
                { id = "bash",  name = "Heavy Blow",  desc = "+6 ATK",                        mods = { ATK = 6 } },
            }},
            { level = 9,  options = {
                { id = "wall",  name = "Living Wall", desc = "+90 max HP",                    mods = { maxHP = 90 } },
                { id = "armor", name = "Tower Plate", desc = "+10 DEF",                       mods = { DEF = 10 } },
            }},
            { level = 12, options = {
                { id = "bulw",  name = "Bulwark",     desc = "+8 ATK, +8 DEF",                mods = { ATK = 8, DEF = 8 } },
                { id = "vital", name = "Vitality",    desc = "+120 max HP",                   mods = { maxHP = 120 } },
            }},
            { level = 15, options = {
                { id = "bastn", name = "Bastion",     desc = "+14 DEF, +60 HP",               mods = { DEF = 14, maxHP = 60 } },
                { id = "warhd", name = "Warhead",     desc = "+14 ATK",                       mods = { ATK = 14 } },
            }},
            { level = 18, options = {
                { id = "giant", name = "Colossus",    desc = "+200 max HP",                   mods = { maxHP = 200 } },
                { id = "siege", name = "Siege Breaker",desc = "+18 ATK, +10 DEF",             mods = { ATK = 18, DEF = 10 } },
            }},
            { level = 21, options = {
                { id = "fortr", name = "Fortress",    desc = "+20 DEF, +100 HP",              mods = { DEF = 20, maxHP = 100 } },
                { id = "onsla", name = "Onslaught",   desc = "+24 ATK",                       mods = { ATK = 24 } },
            }},
        },
    },
    champion = GENERIC_LADDER,
    duelist  = {
        title  = "Blade Precision",
        autoBump = { ATK = 1, CRIT = 0.01 },
        choices = {
            { level = 3,  options = {
                { id = "fast",  name = "Quick Draw",  desc = "+8% CRIT",                      mods = { CRIT = 0.08 } },
                { id = "edge",  name = "Razor Edge",  desc = "+6 ATK",                        mods = { ATK = 6 } },
            }},
            { level = 6,  options = {
                { id = "duel",  name = "Duelist's Nerve", desc = "+12% CRIT",                 mods = { CRIT = 0.12 } },
                { id = "slash", name = "Deep Slash",  desc = "+9 ATK",                        mods = { ATK = 9 } },
            }},
            { level = 9,  options = {
                { id = "focus", name = "Cold Focus",  desc = "+18% CRIT",                     mods = { CRIT = 0.18 } },
                { id = "power", name = "Power Stroke",desc = "+14 ATK",                       mods = { ATK = 14 } },
            }},
            { level = 12, options = {
                { id = "lunge", name = "Lethal Lunge",desc = "+12 ATK, +10% CRIT",            mods = { ATK = 12, CRIT = 0.10 } },
                { id = "evasive",name = "Evasive",    desc = "+30 HP, +8% CRIT",              mods = { maxHP = 30, CRIT = 0.08 } },
            }},
            { level = 15, options = {
                { id = "deadly",name = "Deadly Grace",desc = "+25% CRIT",                     mods = { CRIT = 0.25 } },
                { id = "sharp", name = "Keener Steel",desc = "+20 ATK",                       mods = { ATK = 20 } },
            }},
            { level = 18, options = {
                { id = "master",name = "Master Blademaster", desc = "+18 ATK, +15% CRIT",     mods = { ATK = 18, CRIT = 0.15 } },
                { id = "swift", name = "Swift as Wind",desc = "+35% CRIT",                    mods = { CRIT = 0.35 } },
            }},
            { level = 21, options = {
                { id = "legend",name = "Legendary Duelist",desc = "+24 ATK, +20% CRIT",       mods = { ATK = 24, CRIT = 0.20 } },
                { id = "assass",name = "Assassin",    desc = "+40% CRIT",                     mods = { CRIT = 0.40 } },
            }},
        },
    },
    hunter   = {
        title  = "Hunter's Instinct",
        autoBump = { ATK = 1, CRIT = 0.01 },
        choices = {
            { level = 3,  options = {
                { id = "track", name = "Tracker",     desc = "+7% CRIT",                      mods = { CRIT = 0.07 } },
                { id = "aim",   name = "Sure Aim",    desc = "+5 ATK",                        mods = { ATK = 5 } },
            }},
            { level = 6,  options = {
                { id = "scope", name = "Scoped Shot", desc = "+11% CRIT",                     mods = { CRIT = 0.11 } },
                { id = "pierce",name = "Piercing",    desc = "+8 ATK",                        mods = { ATK = 8 } },
            }},
            { level = 9,  options = {
                { id = "snel",  name = "Silent Steps",desc = "+40 HP, +6% CRIT",              mods = { maxHP = 40, CRIT = 0.06 } },
                { id = "hail",  name = "Arrowsmith",  desc = "+12 ATK",                       mods = { ATK = 12 } },
            }},
            { level = 12, options = {
                { id = "hunt",  name = "Beast Hunter",desc = "+10 ATK, +12% CRIT",            mods = { ATK = 10, CRIT = 0.12 } },
                { id = "surviv",name = "Survivor",    desc = "+70 HP, +8% CRIT",              mods = { maxHP = 70, CRIT = 0.08 } },
            }},
            { level = 15, options = {
                { id = "marksm",name = "Marksman",    desc = "+22% CRIT",                     mods = { CRIT = 0.22 } },
                { id = "quiver",name = "Storm Quiver",desc = "+18 ATK",                       mods = { ATK = 18 } },
            }},
            { level = 18, options = {
                { id = "trk2",  name = "Relentless Tracker", desc = "+14 ATK, +16% CRIT",     mods = { ATK = 14, CRIT = 0.16 } },
                { id = "ghst",  name = "Ghost Arrow", desc = "+30% CRIT",                     mods = { CRIT = 0.30 } },
            }},
            { level = 21, options = {
                { id = "mstr",  name = "Master Huntsman",desc = "+20 ATK, +20% CRIT",         mods = { ATK = 20, CRIT = 0.20 } },
                { id = "phntm", name = "Phantom Sights",desc = "+35% CRIT",                   mods = { CRIT = 0.35 } },
            }},
        },
    },
    jester   = GENERIC_LADDER,
    nomad    = {
        title  = "Pathfinder's Resolve",
        autoBump = { ATK = 1, DEF = 1, maxHP = 4 },
        choices = {
            { level = 3,  options = {
                { id = "mend",  name = "Field Medicine",desc = "+45 max HP",                  mods = { maxHP = 45 } },
                { id = "ember", name = "Ember Blade",   desc = "+5 ATK",                      mods = { ATK = 5 } },
            }},
            { level = 6,  options = {
                { id = "path",  name = "Pathfinder",    desc = "+6 DEF, +25 HP",              mods = { DEF = 6, maxHP = 25 } },
                { id = "heal",  name = "Mending Hands", desc = "+70 max HP",                  mods = { maxHP = 70 } },
            }},
            { level = 9,  options = {
                { id = "ward",  name = "Battle Ward",   desc = "+8 DEF",                      mods = { DEF = 8 } },
                { id = "tenac", name = "Tenacity",      desc = "+100 max HP",                 mods = { maxHP = 100 } },
            }},
            { level = 12, options = {
                { id = "shaman",name = "Shamanic Rites",desc = "+120 max HP, +5 ATK",         mods = { maxHP = 120, ATK = 5 } },
                { id = "clash", name = "Clash Proof",   desc = "+10 DEF, +40 HP",             mods = { DEF = 10, maxHP = 40 } },
            }},
            { level = 15, options = {
                { id = "druid", name = "Druidic Bloom", desc = "+160 max HP",                 mods = { maxHP = 160 } },
                { id = "warlock",name = "Warlock Pact", desc = "+14 ATK, +8 DEF",             mods = { ATK = 14, DEF = 8 } },
            }},
            { level = 18, options = {
                { id = "oracle",name = "Oracle",        desc = "+120 max HP, +10% CRIT",      mods = { maxHP = 120, CRIT = 0.10 } },
                { id = "veteran",name = "Seasoned Vet", desc = "+18 ATK, +12 DEF",            mods = { ATK = 18, DEF = 12 } },
            }},
            { level = 21, options = {
                { id = "sage",  name = "Battle Sage",   desc = "+200 max HP, +15% CRIT",      mods = { maxHP = 200, CRIT = 0.15 } },
                { id = "conq",  name = "Conqueror",     desc = "+22 ATK, +16 DEF",            mods = { ATK = 22, DEF = 16 } },
            }},
        },
    },
    piper    = GENERIC_LADDER,
    witch    = {
        title  = "Hexweaving",
        autoBump = { ATK = 1, CRIT = 0.01 },
        choices = {
            { level = 3,  options = {
                { id = "hex",   name = "Cunning Hex",   desc = "+9% CRIT",                    mods = { CRIT = 0.09 } },
                { id = "spoke", name = "Spell Power",   desc = "+6 ATK",                      mods = { ATK = 6 } },
            }},
            { level = 6,  options = {
                { id = "curse", name = "Curseweave",    desc = "+13% CRIT",                   mods = { CRIT = 0.13 } },
                { id = "bind",  name = "Binding Sigil", desc = "+9 ATK",                      mods = { ATK = 9 } },
            }},
            { level = 9,  options = {
                { id = "grimo", name = "Grimoire",      desc = "+18% CRIT",                   mods = { CRIT = 0.18 } },
                { id = "blood", name = "Blood Pact",    desc = "+40 HP, +10 ATK",             mods = { maxHP = 40, ATK = 10 } },
            }},
            { level = 12, options = {
                { id = "ritual",name = "Dark Ritual",   desc = "+14 ATK, +12% CRIT",          mods = { ATK = 14, CRIT = 0.12 } },
                { id = "veil",  name = "Veil Witch",    desc = "+60 HP, +10% CRIT",           mods = { maxHP = 60, CRIT = 0.10 } },
            }},
            { level = 15, options = {
                { id = "sorcer",name = "Sorcery",       desc = "+24% CRIT",                   mods = { CRIT = 0.24 } },
                { id = "necro", name = "Necromancy",    desc = "+18 ATK",                     mods = { ATK = 18 } },
            }},
            { level = 18, options = {
                { id = "archhex",name = "Arch-Hexer",   desc = "+16 ATK, +16% CRIT",          mods = { ATK = 16, CRIT = 0.16 } },
                { id = "chaos", name = "Chaos Magic",   desc = "+32% CRIT",                   mods = { CRIT = 0.32 } },
            }},
            { level = 21, options = {
                { id = "grand", name = "Grand Enchantress",desc = "+20 ATK, +22% CRIT",       mods = { ATK = 20, CRIT = 0.22 } },
                { id = "void",  name = "Void Caller",   desc = "+40% CRIT",                   mods = { CRIT = 0.40 } },
            }},
        },
    },
    -- ---- proof-of-port BH classes ----------------------------------------
    cleric   = {
        title  = "Divine Intercession",
        autoBump = { ATK = 1, maxHP = 6 },
        choices = {
            { level = 3,  options = {
                { id = "bless", name = "Blessed Aegis", desc = "+40 max HP",                  mods = { maxHP = 40 } },
                { id = "hymn",  name = "Hymn of Faith", desc = "+5 ATK (holy power)",         mods = { ATK = 5 } },
            }},
            { level = 6,  options = {
                { id = "shield",name = "Sanctified Shield", desc = "+6 DEF, +30 HP",          mods = { DEF = 6, maxHP = 30 } },
                { id = "light", name = "Radiant Light", desc = "+70 max HP",                  mods = { maxHP = 70 } },
            }},
            { level = 9,  options = {
                { id = "prayer",name = "Prayer of Mending", desc = "+110 max HP",             mods = { maxHP = 110 } },
                { id = "zeal",  name = "Zealotry",      desc = "+9 ATK",                      mods = { ATK = 9 } },
            }},
            { level = 12, options = {
                { id = "halo",  name = "Halo of Protection", desc = "+8 DEF, +80 HP",         mods = { DEF = 8, maxHP = 80 } },
                { id = "miracle",name = "Miracle Worker",desc = "+130 max HP",                mods = { maxHP = 130 } },
            }},
            { level = 15, options = {
                { id = "angel", name = "Angelic Favor", desc = "+100 max HP, +6% CRIT",       mods = { maxHP = 100, CRIT = 0.06 } },
                { id = "avenger",name = "Avenging Host",desc = "+14 ATK",                     mods = { ATK = 14 } },
            }},
            { level = 18, options = {
                { id = "prophet",name = "Prophet",       desc = "+140 max HP, +10% CRIT",     mods = { maxHP = 140, CRIT = 0.10 } },
                { id = "judge", name = "Divine Judge",  desc = "+18 ATK, +10 DEF",            mods = { ATK = 18, DEF = 10 } },
            }},
            { level = 21, options = {
                { id = "saint", name = "Saint",         desc = "+200 max HP, +12% CRIT",      mods = { maxHP = 200, CRIT = 0.12 } },
                { id = "archang",name = "Archangel",    desc = "+22 ATK, +16 DEF",            mods = { ATK = 22, DEF = 16 } },
            }},
        },
    },
    paladin  = {
        title  = "Oathkeeper",
        autoBump = { DEF = 1, maxHP = 7 },
        choices = {
            { level = 3,  options = {
                { id = "oath",  name = "Oath of Steel", desc = "+7 DEF",                      mods = { DEF = 7 } },
                { id = "creed", name = "Creed of Life", desc = "+50 max HP",                  mods = { maxHP = 50 } },
            }},
            { level = 6,  options = {
                { id = "holy",  name = "Holy Bulwark",  desc = "+9 DEF, +25 HP",              mods = { DEF = 9, maxHP = 25 } },
                { id = "wrath", name = "Righteous Wrath", desc = "+6 ATK",                    mods = { ATK = 6 } },
            }},
            { level = 9,  options = {
                { id = "guard", name = "Guardian Oath", desc = "+100 max HP",                 mods = { maxHP = 100 } },
                { id = "hammer",name = "Hammer of Justice", desc = "+11 ATK",                 mods = { ATK = 11 } },
            }},
            { level = 12, options = {
                { id = "sentinel",name = "Sentinel",    desc = "+9 ATK, +9 DEF",              mods = { ATK = 9, DEF = 9 } },
                { id = "bulwark2",name = "Bulwark",     desc = "+130 max HP",                 mods = { maxHP = 130 } },
            }},
            { level = 15, options = {
                { id = "champion2",name = "Holy Champion",desc = "+15 DEF, +70 HP",           mods = { DEF = 15, maxHP = 70 } },
                { id = "cruiser",name = "Crusader",    desc = "+15 ATK",                      mods = { ATK = 15 } },
            }},
            { level = 18, options = {
                { id = "justicar",name = "Justicar",    desc = "+210 max HP",                 mods = { maxHP = 210 } },
                { id = "palbld",name = "Paladin Blade", desc = "+18 ATK, +11 DEF",            mods = { ATK = 18, DEF = 11 } },
            }},
            { level = 21, options = {
                { id = "templar",name = "Templar",      desc = "+22 DEF, +110 HP",            mods = { DEF = 22, maxHP = 110 } },
                { id = "liberat",name = "Liberator",    desc = "+24 ATK",                     mods = { ATK = 24 } },
            }},
        },
    },
    wizard   = {
        title  = "Arcane Studies",
        autoBump = { ATK = 1, CRIT = 0.01 },
        choices = {
            { level = 3,  options = {
                { id = "focus2",name = "Arcane Focus",  desc = "+8 ATK (spell power)",        mods = { ATK = 8 } },
                { id = "intel", name = "Intellect",     desc = "+8% CRIT (critical cast)",    mods = { CRIT = 0.08 } },
            }},
            { level = 6,  options = {
                { id = "arcana",name = "High Arcana",   desc = "+12% CRIT",                   mods = { CRIT = 0.12 } },
                { id = "spell2",name = "Greater Spells",desc = "+10 ATK",                     mods = { ATK = 10 } },
            }},
            { level = 9,  options = {
                { id = "element",name = "Elementalist",desc = "+18% CRIT",                    mods = { CRIT = 0.18 } },
                { id = "conjure",name = "Conjurer",    desc = "+14 ATK",                      mods = { ATK = 14 } },
            }},
            { level = 12, options = {
                { id = "abjuration",name = "Abjurer",   desc = "+50 HP, +10% CRIT",           mods = { maxHP = 50, CRIT = 0.10 } },
                { id = "evocation",name = "Evoker",     desc = "+16 ATK, +8% CRIT",           mods = { ATK = 16, CRIT = 0.08 } },
            }},
            { level = 15, options = {
                { id = "mage2", name = "Archmage",      desc = "+26% CRIT",                   mods = { CRIT = 0.26 } },
                { id = "pyrom", name = "Pyromancer",    desc = "+20 ATK",                     mods = { ATK = 20 } },
            }},
            { level = 18, options = {
                { id = "astral",name = "Astral Projection", desc = "+60 HP, +16% CRIT",       mods = { maxHP = 60, CRIT = 0.16 } },
                { id = "wild",  name = "Wild Magic",    desc = "+22 ATK, +12% CRIT",          mods = { ATK = 22, CRIT = 0.12 } },
            }},
            { level = 21, options = {
                { id = "archwit",name = "Arch-Witch",   desc = "+24 ATK, +22% CRIT",          mods = { ATK = 24, CRIT = 0.22 } },
                { id = "spell20",name = "Spellstorm",   desc = "+34% CRIT",                   mods = { CRIT = 0.34 } },
            }},
        },
    },
    rogue    = {
        title  = "Shadow Craft",
        autoBump = { ATK = 1, CRIT = 0.01 },
        choices = {
            { level = 3,  options = {
                { id = "poison",name = "Poisoned Fang", desc = "+7% CRIT",                    mods = { CRIT = 0.07 } },
                { id = "stab",  name = "Quick Stab",    desc = "+6 ATK",                      mods = { ATK = 6 } },
            }},
            { level = 6,  options = {
                { id = "vanish",name = "Vanish",        desc = "+11% CRIT",                   mods = { CRIT = 0.11 } },
                { id = "backstab",name = "Backstab",    desc = "+9 ATK",                      mods = { ATK = 9 } },
            }},
            { level = 9,  options = {
                { id = "venom", name = "Venomous Blades", desc = "+35 HP, +10% CRIT",         mods = { maxHP = 35, CRIT = 0.10 } },
                { id = "shadow",name = "Shadow Dance",  desc = "+13 ATK",                     mods = { ATK = 13 } },
            }},
            { level = 12, options = {
                { id = "assas", name = "Assassin",      desc = "+11 ATK, +12% CRIT",          mods = { ATK = 11, CRIT = 0.12 } },
                { id = "skulk", name = "Skulker",       desc = "+60 HP, +9% CRIT",            mods = { maxHP = 60, CRIT = 0.09 } },
            }},
            { level = 15, options = {
                { id = "night", name = "Nightblade",    desc = "+24% CRIT",                   mods = { CRIT = 0.24 } },
                { id = "daggers",name = "Twin Daggers", desc = "+19 ATK",                     mods = { ATK = 19 } },
            }},
            { level = 18, options = {
                { id = "ninj",  name = "Shadow Ninja",  desc = "+15 ATK, +16% CRIT",          mods = { ATK = 15, CRIT = 0.16 } },
                { id = "phantom",name = "Phantom",      desc = "+32% CRIT",                   mods = { CRIT = 0.32 } },
            }},
            { level = 21, options = {
                { id = "masterassas",name = "Master Assassin", desc = "+22 ATK, +20% CRIT",   mods = { ATK = 22, CRIT = 0.20 } },
                { id = "death", name = "Death itself",  desc = "+38% CRIT",                   mods = { CRIT = 0.38 } },
            }},
        },
    },
}

local function ladderFor(class)
    return LADDER[class] or GENERIC_LADDER
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local A_H     = common.ARROW_H
local A_W     = common.ARROW_W
local BOX_PAD = 5

local TITLE_Y      = 12
local PARTY_SLOTS  = 4
local ICON_SIZE    = 40
local PARTY_GAP    = 14
local PARTY_TOTAL_W = PARTY_SLOTS * ICON_SIZE + (PARTY_SLOTS - 1) * PARTY_GAP
local PARTY_FRAME_PAD = 10
local PARTY_FRAME_W = PARTY_TOTAL_W + PARTY_FRAME_PAD * 2
local PARTY_FRAME_H = ICON_SIZE + 18 + PARTY_FRAME_PAD
local PARTY_FRAME_X = math.floor((VW - PARTY_FRAME_W) / 2)
local PARTY_FRAME_Y = TITLE_Y + 30
local PARTY_X       = PARTY_FRAME_X + PARTY_FRAME_PAD
local PARTY_Y       = PARTY_FRAME_Y + PARTY_FRAME_PAD + 14

local DESC_Y   = PARTY_FRAME_Y + PARTY_FRAME_H + 10
local DESC_H   = 20
local DESC_X   = 40
local DESC_W   = VW - 80

local DESC_BAR_Y    = VH - DESC_H - 10   -- parchment description strip, pinned to the bottom
local LADDER_TOP    = DESC_Y + 40        -- first ladder row (below the name / XP readout)
local LADDER_BOTTOM = DESC_BAR_Y - 8     -- ladder viewport lower bound
local NODE_H        = 24
local NODE_GAP      = 6
local ROW_STRIDE    = NODE_H + NODE_GAP   -- uniform row pitch for scroll clamping
local MAX_NODES_SHOWN = 21    -- highest level laid out (= the last choice level)

local CENTERLINE_X  = math.floor(VW / 2)
local BRANCH_BOX_W  = 180
local FORK_HEIGHT   = 40                 -- vertical space a choice fork occupies
local PLAIN_HEIGHT  = NODE_H             -- vertical space a plain level node occupies

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local partyNames   = {}   -- [1..4] charName or nil (active party)
local selectedChar = nil  -- charName whose ladder is displayed
local icons        = {}   -- { [charName] = Image }
local assetsLoaded = false

local font       -- size 13 node labels / misc
local titleFont  -- size 18 banner
local nameFont   -- size 14 branch names
local smallFont  -- size 12 branch descriptions / tiny text

local scrollOff  = 0      -- vertical scroll offset of the ladder (px down)
local hoveredNode = nil   -- the nodeRow ({kind=...}) currently under the mouse
local hoveredOpt  = nil   -- the specific sub-box (left/right/plain) under the mouse
local pressedNode = nil   -- {kind="back"} | {kind="fork",idx,opt} | {kind="plain",level}
local hoveredPartySlot = nil
local box        = common.newBox()

-- Computed layout cache, rebuilt when selectedChar / scroll changes:
-- nodeRects[lvl] = {x,y,w,h, kind, ...} keyed by level number.
local nodeRects  = {}

-- ============================================================================
-- SAVE-RECORD HELPERS
-- ============================================================================

local function charRecord(name)
    local uc = saveData_ref and saveData_ref.unlockedCharacters
    if not uc then return nil end
    return uc[name]
end

-- The character's current level (>=1). Degrades cleanly to 1 if absent.
local function charLevel(rec)
    local lv = rec and rec.level
    if type(lv) == "number" and lv >= 1 then return math.floor(lv) end
    return 1
end

-- Forward declarations: these locals are referenced by functions defined
-- BEFORE the local function that assigns them. Without a prior `local name`
-- in scope, the earlier closures would capture a GLOBAL (nil at call time)
-- instead of the upvalue -> runtime "attempt to call a nil value" once the
-- talents screen is actually driven (headless only loads, never drives it).
local resolveOption, displayName
local drawLadder, drawPlainRow, drawForkRow, drawBranchBox, drawDescBar

-- Read the chosen-branch map from skillTree, tolerant of the OLD shape
-- ({1,1,1,1,1}) and partial arrays. Returns a fresh table keyed by the
-- choice INDEX (1-based position in ladder.choices): chosen[idx] = optionId.
-- Old numeric entries are ignored (see resolveOption).
local function readChoices(rec, ladder)
    local out = {}
    local st = rec and rec.skillTree
    if type(st) == "table" then
        for i, v in ipairs(st) do
            local choice = ladder.choices[i]
            if choice then
                local resolved = resolveOption(choice, v)
                if resolved then out[i] = resolved end
            end
        end
    end
    return out
end

-- Given a choice table and a stored value (option id string OR 1/2 index),
-- return the canonical option id, or nil if it doesn't match either.
resolveOption = function(choice, v)
    if type(v) == "string" then
        for _, o in ipairs(choice.options) do
            if o.id == v then return v end
        end
        return nil
    end
    -- Numbers are the pre-talents placeholder ({1,1,1,1,1}): no passive was ever
    -- applied for them, so they read as "not chosen yet".
    return nil
end

-- Write a choice back into skillTree, preserving the NEW string-id shape while
-- keeping the field a plain ipairs-safe array. Earlier unfilled slots get "" so
-- positional indexing (readChoices iterates by array index) stays stable.
local function writeChoice(rec, ladder, choiceIdx, optId)
    if not rec then return end
    local st = rec.skillTree
    if type(st) ~= "table" then st = {}; rec.skillTree = st end
    for i = 1, choiceIdx - 1 do
        if st[i] == nil then st[i] = "" end
    end
    st[choiceIdx] = optId
end

-- Apply a passive's stat mods to rec.stats (additive). Used once at pick-time.
-- Keys that don't exist in stats are skipped (keeps load-clean).
local function applyPassiveMods(rec, mods)
    local s = rec and rec.stats
    if type(s) ~= "table" then return end
    for k, v in pairs(mods or {}) do
        if s[k] ~= nil and type(v) == "number" then
            s[k] = s[k] + v
        end
    end
end

-- ============================================================================
-- EXIT — persists any talent picks and returns to map
-- ============================================================================

local function exit()
    -- Persist the whole save record (talent picks were folded in live; this
    -- flushes them to disk). Same routine party_select uses.
    if saveData_ref then
        save.write(slot_ref, saveData_ref)
    end
    switchFn("map", saveData_ref, slot_ref)
end

-- ============================================================================
-- LAYOUT BUILD  (defined BEFORE the interface: onEnter / mousepressed /
-- mousereleased / wheel all call rebuildLayout, so it must be in scope by then.)
-- ============================================================================

local function getPartyRect(i)
    return PARTY_X + (i - 1) * (ICON_SIZE + PARTY_GAP), PARTY_Y, ICON_SIZE, ICON_SIZE
end

local function pointInRect(px, py, r)
    -- Rows scrolled outside the ladder viewport are clipped, so not hittable.
    if py < LADDER_TOP - 8 or py >= LADDER_BOTTOM + 4 then return false end
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

local function addPlainRow(rects, lvl, y, level)
    local w = 90
    local x = CENTERLINE_X - w / 2
    local state = (level >= lvl) and "reached" or "locked"
    rects[lvl] = {
        kind = "plain", level = lvl,
        x = x, y = y, w = w, h = PLAIN_HEIGHT,
        state = state,
        hoverRect = { x - BOX_PAD, y - BOX_PAD, w + BOX_PAD*2, PLAIN_HEIGHT + BOX_PAD*2 },
    }
end

local function rebuildLayout()
    nodeRects = {}
    if not selectedChar then return end
    local rec = charRecord(selectedChar)
    local ladder = ladderFor(selectedChar)
    local level = rec and charLevel(rec) or 1

    -- Determine how many levels to show: up to MAX_NODES_SHOWN starting at 1.
    -- Always include the NEXT choice level so the upcoming fork is previewed.
    local totalRows = math.min(MAX_NODES_SHOWN,
                               (math.floor(level / CHOICE_EVERY) + 1) * CHOICE_EVERY)

    -- Pre-compute cumulative Y.
    local y = LADDER_TOP - scrollOff
    local choiceIdx = 0
    local lvl = 1
    while lvl <= totalRows do
        local isChoice = (lvl % CHOICE_EVERY == 0)
        if isChoice then
            choiceIdx = choiceIdx + 1
            local ch = ladder.choices[choiceIdx]
            if ch and ch.level == lvl then
                local chosenMap = readChoices(rec, ladder)
                local leftX  = CENTERLINE_X - 12 - BRANCH_BOX_W
                local rightX = CENTERLINE_X + 12
                local reached = level >= lvl
                local chosenId = chosenMap[choiceIdx]
                nodeRects[lvl] = {
                    kind = "fork", idx = choiceIdx, level = lvl,
                    x = leftX, y = y, w = BRANCH_BOX_W * 2 + 24, h = FORK_HEIGHT,
                    left  = { x = leftX,  y = y, w = BRANCH_BOX_W, h = FORK_HEIGHT, opt = 1,
                              state = (not reached) and "locked"
                                      or (chosenId == ch.options[1].id) and "chosen"
                                      or (chosenId ~= nil) and "lockedOther"
                                      or "selectable" },
                    right = { x = rightX, y = y, w = BRANCH_BOX_W, h = FORK_HEIGHT, opt = 2,
                              state = (not reached) and "locked"
                                      or (chosenId == ch.options[2].id) and "chosen"
                                      or (chosenId ~= nil) and "lockedOther"
                                      or "selectable" },
                }
                nodeRects[lvl]._whole = { x = leftX, y = y, w = BRANCH_BOX_W*2+24, h = FORK_HEIGHT }
                y = y + FORK_HEIGHT + NODE_GAP
            else
                addPlainRow(nodeRects, lvl, y, level)
                y = y + PLAIN_HEIGHT + NODE_GAP
            end
        else
            addPlainRow(nodeRects, lvl, y, level)
            y = y + PLAIN_HEIGHT + NODE_GAP
        end
        lvl = lvl + 1
    end

    local contentH = (y + scrollOff) - LADDER_TOP
    local viewportH = LADDER_BOTTOM - LADDER_TOP
    local maxScroll = math.max(0, contentH - viewportH)
    scrollOff = math.max(0, math.min(scrollOff, maxScroll))
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, saveData, slot)
    canvas_ref   = canvas
    postfx_ref   = postfx
    switchFn     = sw
    saveData_ref = saveData
    slot_ref     = slot
    require("music_mgr").play("forest")

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    partyNames = {}
    local po = saveData.partyOrder or {}
    for i = 1, PARTY_SLOTS do
        local name = po[i]
        if type(name) == "string" then
            partyNames[i] = name
        end
    end

    -- Default selection: first active party member.
    selectedChar = partyNames[1]

    if not assetsLoaded then
        assetsLoaded = true
        font       = common.loadFont(13)
        titleFont  = common.loadFont(18)
        nameFont   = common.loadFont(14)
        smallFont  = common.loadFont(12)
    end
    local uc = (saveData and saveData.unlockedCharacters) or {}
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    hoveredNode    = nil
    hoveredOpt     = nil
    pressedNode    = nil
    hoveredPartySlot = nil
    scrollOff      = 0

    local ix, iy = getPartyRect(1)
    common.initBox(box, ix - BOX_PAD, iy - BOX_PAD, ICON_SIZE + BOX_PAD * 2, ICON_SIZE + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    -- Hover: back arrow.
    local backHover = (vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H)
    if backHover then
        common.setBoxTarget(box, AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD * 2, A_H + BOX_PAD * 2)
    end

    -- Hover: party strip (switch whose ladder is shown).
    hoveredPartySlot = nil
    local boxHit = false
    for i = 1, PARTY_SLOTS do
        local sx, sy, swd, sh = getPartyRect(i)
        if vmx >= sx and vmx < sx + swd and vmy >= sy and vmy < sy + sh then
            hoveredPartySlot = i
            common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, swd + BOX_PAD * 2, sh + BOX_PAD * 2)
            boxHit = true
            break
        end
    end

    -- Hover: ladder nodes (test the per-branch boxes on a fork so hovering one
    -- branch highlights only that branch).
    hoveredNode = nil
    hoveredOpt  = nil
    if not boxHit then
        for lvl, nr in pairs(nodeRects) do
            local hitSub = nil
            if nr.kind == "fork" then
                if nr.left and nr.left.state ~= "locked" and pointInRect(vmx, vmy, nr.left)  then hitSub = nr.left  end
                if not hitSub and nr.right and nr.right.state ~= "locked" and pointInRect(vmx, vmy, nr.right) then hitSub = nr.right end
            else
                if pointInRect(vmx, vmy, nr) then hitSub = nr end
            end
            if hitSub then
                hoveredNode = nr
                hoveredOpt  = hitSub
                local hx, hy, hw, hh
                if nr.kind == "fork" then
                    hx, hy, hw, hh = hitSub.x - BOX_PAD, hitSub.y - BOX_PAD, hitSub.w + BOX_PAD*2, hitSub.h + BOX_PAD*2
                else
                    hx, hy, hw, hh = nr.hoverRect[1], nr.hoverRect[2], nr.hoverRect[3], nr.hoverRect[4]
                end
                common.setBoxTarget(box, hx, hy, hw, hh)
                boxHit = true
                break
            end
        end
    end
    -- (hoveredNode / hoveredOpt locals are the source of truth for mousereleased)

    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    -- Back arrow.
    if vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H then
        pressedNode = {kind="back"}
        return
    end

    -- Party strip: switch character.
    for i = 1, PARTY_SLOTS do
        local sx, sy, swd, sh = getPartyRect(i)
        if partyNames[i] and vmx >= sx and vmx < sx + swd and vmy >= sy and vmy < sy + sh then
            selectedChar = partyNames[i]
            rebuildLayout()
            common.playClickSound()
            return
        end
    end

    -- Ladder node press: capture WHICH sub-box was pressed so release can act.
    for lvl, nr in pairs(nodeRects) do
        local hitSub
        if nr.kind == "fork" then
            if nr.left and nr.left.state ~= "locked" and pointInRect(vmx, vmy, nr.left)  then hitSub = nr.left  end
            if not hitSub and nr.right and nr.right.state ~= "locked" and pointInRect(vmx, vmy, nr.right) then hitSub = nr.right end
        else
            if pointInRect(vmx, vmy, nr) then hitSub = nr end
        end
        if hitSub then
            if nr.kind == "fork" then
                pressedNode = {kind="fork", idx=nr.idx, opt=hitSub.opt}
            else
                pressedNode = {kind="plain", level=nr.level}
            end
            return
        end
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    local p = pressedNode
    pressedNode = nil
    if not p then return end

    if p.kind == "back" then
        common.playClickSound()
        exit()
        return
    end

    -- Branch pick: the pressed sub-box must still be the hovered one (no drag-off)
    -- and it must be a SELECTABLE state (reached + unchosen).
    if p.kind == "fork" and p.opt then
        local ho = hoveredOpt
        local hr = hoveredNode
        -- The pressed branch must STILL be the one under the mouse at release.
        local sameBranch = ho ~= nil and hr ~= nil
            and ( (p.opt == 1 and ho == hr.left) or (p.opt == 2 and ho == hr.right) )
        if sameBranch and ho.state == "selectable" then
            local rec = charRecord(selectedChar)
            if rec then
                local ladder = ladderFor(selectedChar)
                local choice = ladder.choices[p.idx]
                if choice then
                    local level = charLevel(rec)
                    if level >= choice.level then
                        local opt = choice.options[p.opt]
                        if opt then
                            writeChoice(rec, ladder, p.idx, opt.id)
                            applyPassiveMods(rec, opt.mods)
                            common.playClickSound()
                            rebuildLayout()
                            return
                        end
                    end
                end
            end
        end
    end
end

function M.keypressed(key)
    if key == "escape" or key == "return" or key == "kpenter" then
        exit()
    end
end

-- (onExit is intentionally a no-op hook kept for interface symmetry.)
function M.onExit() end

-- Wheel scrolling of the ladder viewport (positive dy = scroll down).
function M.wheel(dy)
    if not selectedChar then return end
    scrollOff = scrollOff + dy * 24
    rebuildLayout()
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawIconSmall(name, x, y, size, alpha)
    local img = icons[name]
    if img then
        local iw, ih = img:getDimensions()
        local sc = math.min(size / iw, size / ih)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
        return
    end
    local label = displayName(name)
    local fw, fh = font:getWidth(label), font:getHeight()
    local scale = 1
    if fw > size - 4 then scale = (size - 4) / fw end
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.print(label, x + (size - fw * scale) / 2, y + (size - fh * scale) / 2, 0, scale, scale)
end

displayName = function(name)
    if not name then return "" end
    local parts = {}
    for part in name:gmatch("%S+") do
        parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2)
    end
    return table.concat(parts, " ")
end

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Title banner.
    love.graphics.setFont(titleFont)
    love.graphics.setColor(CRIMSON)
    love.graphics.printf("TALENTS", 0, TITLE_Y, VW, "center")
    love.graphics.setLineWidth(2)
    local tw = titleFont:getWidth("TALENTS")
    local ruleY = TITLE_Y + titleFont:getHeight() / 2
    love.graphics.line(40, ruleY, VW/2 - tw/2 - 20, ruleY)
    love.graphics.line(VW/2 + tw/2 + 20, ruleY, VW - 40, ruleY)

    -- Active-party strip (pick whose ladder to view).
    love.graphics.setColor(WHITE)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", PARTY_FRAME_X, PARTY_FRAME_Y, PARTY_FRAME_W, PARTY_FRAME_H)
    love.graphics.setColor(CRIMSON)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", PARTY_FRAME_X+3, PARTY_FRAME_Y+3, PARTY_FRAME_W-6, PARTY_FRAME_H-6)

    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartyRect(i)
        local name = partyNames[i]
        love.graphics.setColor(0.05, 0.02, 0.02, 1)
        love.graphics.rectangle("fill", sx, sy, ICON_SIZE, ICON_SIZE)
        local isSel = (name == selectedChar)
        love.graphics.setColor(isSel and WHITE or CRIMSON)
        love.graphics.setLineWidth(isSel and 3 or 2)
        love.graphics.rectangle("line", sx, sy, ICON_SIZE, ICON_SIZE)
        if name then
            drawIconSmall(name, sx, sy, ICON_SIZE, isSel and 1 or 0.8)
        else
            love.graphics.setFont(font)
            love.graphics.setColor(0.35, 0.10, 0.12, 1)
            love.graphics.print("—", sx + (ICON_SIZE - font:getWidth("—"))/2,
                                sy + (ICON_SIZE - font:getHeight())/2)
        end
    end

    -- Character name + level under the strip.
    if selectedChar then
        local rec = charRecord(selectedChar)
        local lvl = rec and charLevel(rec) or 1
        local pts = rec and rec.pointsToNextLevel
        love.graphics.setFont(nameFont)
        love.graphics.setColor(OFFRED)
        love.graphics.printf(("Lv %d  ·  %s"):format(lvl, displayName(selectedChar)),
                             0, DESC_Y, VW, "center")
        love.graphics.setFont(smallFont)
        love.graphics.setColor({0.5,0.5,0.5,1})
        local xpTxt = pts and ("XP to next: " .. tostring(pts)) or "XP: —"
        love.graphics.printf(xpTxt, 0, DESC_Y + 14, VW, "center")
    end

    -- Description bar (parchment-style strip) at the bottom of the screen: the
    -- ladder viewport scrolls ABOVE it, so the readout never moves.
    love.graphics.setColor(0.06, 0.04, 0.04, 1)
    love.graphics.rectangle("fill", DESC_X, DESC_BAR_Y, DESC_W, DESC_H)
    love.graphics.setColor(CRIMSON)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", DESC_X, DESC_BAR_Y, DESC_W, DESC_H)

    -- Ladder (scrolled).
    drawLadder()

    -- Description text in the bar.
    drawDescBar()

    -- Animated red box + back arrow.
    common.drawBox(box, pressedNode ~= nil and pressedNode.kind == "back")
    common.drawBackArrow(pressedNode ~= nil and pressedNode.kind == "back")

    love.graphics.setColor(1, 1, 1, 1)
end

drawLadder = function()
    if not selectedChar then return end
    local rec = charRecord(selectedChar)
    local ladder = ladderFor(selectedChar)
    local level = rec and charLevel(rec) or 1

    love.graphics.push()
    -- Scissor so the scrolling ladder never paints over the desc bar or header.
    love.graphics.setScissor(CENTERLINE_X - BRANCH_BOX_W - 24, LADDER_TOP - 8,
                             (BRANCH_BOX_W + 24) * 2, LADDER_BOTTOM - LADDER_TOP + 12)

    -- Vertical centerline behind the nodes.
    love.graphics.setColor(FAINT)
    love.graphics.setLineWidth(2)
    love.graphics.line(CENTERLINE_X, LADDER_TOP - 4, CENTERLINE_X, LADDER_BOTTOM)

    for lvl, nr in pairs(nodeRects) do
        if nr.kind == "fork" then
            drawForkRow(nr, ladder, level, rec)
        else
            drawPlainRow(nr)
        end
    end

    love.graphics.setScissor()
    love.graphics.pop()
end

drawPlainRow = function(nr)
    local reached = (nr.state == "reached")
    local col = reached and CRIMSON or DIM
    love.graphics.setColor(0.04, 0.02, 0.02, 1)
    love.graphics.rectangle("fill", nr.x, nr.y, nr.w, nr.h)
    love.graphics.setColor(col)
    love.graphics.setLineWidth(reached and 2 or 1)
    love.graphics.rectangle("line", nr.x, nr.y, nr.w, nr.h)
    love.graphics.setFont(font)
    love.graphics.setColor(reached and WHITE or {0.4,0.2,0.22,1})
    local lbl = "Lv " .. tostring(nr.level)
    love.graphics.print(lbl, nr.x + (nr.w - font:getWidth(lbl))/2,
                        nr.y + (nr.h - font:getHeight())/2)
end

drawForkRow = function(nr, ladder, level, rec)
    local ch = ladder.choices[nr.idx]
    if not ch then return end
    local lbox, rbox = nr.left, nr.right

    -- Connector stubs from the centerline to each branch box.
    love.graphics.setColor(DIM)
    love.graphics.setLineWidth(2)
    local cy = nr.y + FORK_HEIGHT/2
    love.graphics.line(CENTERLINE_X, cy, lbox.x + lbox.w, cy)
    love.graphics.line(CENTERLINE_X, cy, rbox.x, cy)

    -- Center diamond marker (the fork).
    love.graphics.setColor(OFFRED)
    love.graphics.polygon("fill",
        CENTERLINE_X, cy - 6, CENTERLINE_X + 6, cy,
        CENTERLINE_X, cy + 6, CENTERLINE_X - 6, cy)

    drawBranchBox(lbox, ch.options[1], "A")
    drawBranchBox(rbox, ch.options[2], "B")
end

drawBranchBox = function(b, opt, tag)
    -- State colors:
    --   selectable  -> crimson border, dark fill, white name (clickable)
    --   chosen      -> white border, crimson fill, white name (locked-in)
    --   lockedOther -> dim border, darker fill, dim name (forever locked)
    --   locked      -> faint border, near-black fill, faint name (future level)
    local borderCol, fillCol, nameCol, descCol
    if b.state == "selectable" then
        borderCol, fillCol = CRIMSON, {0.10, 0.03, 0.03, 1}
        nameCol, descCol = WHITE, OFFRED
    elseif b.state == "chosen" then
        borderCol, fillCol = WHITE, {0.55, 0.08, 0.14, 1}
        nameCol, descCol = WHITE, {1,0.85,0.85,1}
    elseif b.state == "lockedOther" then
        borderCol, fillCol = {0.28,0.10,0.12,1}, {0.05,0.02,0.02,1}
        nameCol, descCol = {0.45,0.2,0.22,1}, {0.35,0.15,0.17,1}
    else -- locked
        borderCol, fillCol = FAINT, {0.03,0.015,0.015,1}
        nameCol, descCol = {0.30,0.12,0.14,1}, {0.25,0.10,0.12,1}
    end

    love.graphics.setColor(fillCol)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
    love.graphics.setColor(borderCol)
    love.graphics.setLineWidth(b.state == "chosen" and 3 or 2)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h)

    -- Tag letter + name.
    love.graphics.setFont(smallFont)
    love.graphics.setColor(nameCol)
    local tagStr = "[" .. tag .. "] "
    local nameStr = opt.name
    local full = tagStr .. nameStr
    local fw = smallFont:getWidth(full)
    local fxx = b.x + (b.w - fw)/2
    love.graphics.print(full, fxx, b.y + 6)

    -- Description (wrap-ish: just truncate if too wide).
    love.graphics.setFont(smallFont)
    love.graphics.setColor(descCol)
    local d = opt.desc
    if smallFont:getWidth(d) > b.w - 10 then
        -- ASCII ellipsis: byte-wise trimming must never split a UTF-8 sequence.
        while #d > 1 and smallFont:getWidth(d .. "...") > b.w - 10 do
            d = d:sub(1, -2)
        end
        d = d .. "..."
    end
    love.graphics.print(d, b.x + (b.w - smallFont:getWidth(d))/2, b.y + b.h - 16)
end

drawDescBar = function()
    local bx, by = DESC_X, DESC_BAR_Y
    love.graphics.setFont(smallFont)
    local txt, col

    if hoveredNode then
        local nr = hoveredNode
        if nr.kind == "plain" then
            if nr.state == "reached" then
                txt, col = ("Level %d reached."):format(nr.level), {0.6,0.6,0.6,1}
            else
                txt, col = ("Reach Level %d to unlock."):format(nr.level), DIM
            end
        else
            -- Fork: describe the hovered option (whichever half the mouse is in).
            local ladder = ladderFor(selectedChar)
            local ch = ladder.choices[nr.idx]
            if ch then
                local vmx, vmy = common.virtualMouse()
                local optIdx = (vmx < CENTERLINE_X) and 1 or 2
                local opt = ch.options[optIdx]
                local b = (optIdx == 1) and nr.left or nr.right
                if opt then
                    if b.state == "selectable" then
                        txt, col = ("> %s (%s) — CLICK TO CHOOSE. Locks the other option."):format(opt.name, opt.desc), OFFRED
                    elseif b.state == "chosen" then
                        txt, col = ("%s — CHOSEN. Locked in."):format(opt.name), WHITE
                    elseif b.state == "lockedOther" then
                        txt, col = ("%s — unavailable (other branch chosen)."):format(opt.name), DIM
                    else
                        txt, col = ("Reach Level %d to choose: %s (%s)."):format(nr.level, opt.name, opt.desc), DIM
                    end
                end
            end
        end
    else
        txt, col = "Hover a node to preview. Pick a branch at a reached choice level.", {0.45,0.45,0.45,1}
    end
    love.graphics.setColor(col or WHITE)
    love.graphics.print(txt, bx + 10, by + (DESC_H - smallFont:getHeight())/2)
end

function M.draw()
    -- Rebuild layout lazily only when needed (cheap enough to do per-frame here
    -- since the ladder is small; keeps selection/scroll always consistent).
    rebuildLayout()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M

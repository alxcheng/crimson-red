-- data/talents.lua — the TALENTS ladders, as data.                    [tuned]
--
-- Each class has a linear ladder: every CHOICE_EVERY levels the player picks
-- ONE of two passive bonuses (the other locks). A pick is stored in the save as
-- unlockedCharacters[name].skillTree[choiceIndex] = option id. Bonuses are never
-- written into the save: M.modsFor() re-derives them from the picks whenever
-- stats are built (progression.heroStats).
--
--   LADDER[class] = {
--       title    = string,
--       autoBump = { STAT = n },   -- shown only; not applied (leveling already
--                                  -- grows stats through the class scales)
--       choices  = { { level = 3, options = {
--                        { id=, name=, desc=, mods = { ATK=, DEF=, maxHP=, CRIT= } },
--                        { ... } } }, ... },
--   }
-- Mod keys: ATK, DEF, maxHP (flat), CRIT (fraction: 0.08 = +8%).

local M = {}

M.CHOICE_EVERY = 3

-- Generic fallback ladder for any class without its own flavor row.
local GENERIC_LADDER = {
    title  = "War Training",
    autoBump = { ATK = 1, DEF = 1, maxHP = 50 },
    choices = {
        { level = 3,  options = {
            { id = "atk", name = "Keen Edge",   desc = "+4 ATK",                  mods = { ATK = 4 } },
            { id = "def", name = "Steady Guard",desc = "+3 DEF, +150 HP",          mods = { DEF = 3, maxHP = 150 } },
        }},
        { level = 6,  options = {
            { id = "hp",  name = "Hardened",    desc = "+400 max HP",              mods = { maxHP = 400 } },
            { id = "crit",name = "Precise",     desc = "+8% CRIT chance",         mods = { CRIT = 0.08 } },
        }},
        { level = 9,  options = {
            { id = "atk2",name = "Might",       desc = "+7 ATK",                  mods = { ATK = 7 } },
            { id = "def2",name = "Bulwark",     desc = "+6 DEF",                  mods = { DEF = 6 } },
        }},
        { level = 12, options = {
            { id = "all1",name = "Veteran",     desc = "+5 ATK, +5 DEF, +300 HP",  mods = { ATK = 5, DEF = 5, maxHP = 300 } },
            { id = "crit2",name = "Deadly",     desc = "+15% CRIT chance",        mods = { CRIT = 0.15 } },
        }},
        { level = 15, options = {
            { id = "atk3",name = "Overwhelming",desc = "+12 ATK",                 mods = { ATK = 12 } },
            { id = "hp2", name = "Titanic",     desc = "+800 max HP",              mods = { maxHP = 800 } },
        }},
        { level = 18, options = {
            { id = "def3",name = "Impregnable", desc = "+12 DEF",                 mods = { DEF = 12 } },
            { id = "crit3",name = "Executioner",desc = "+20% CRIT chance",        mods = { CRIT = 0.20 } },
        }},
        { level = 21, options = {
            { id = "all2",name = "Legendary",   desc = "+10 ATK, +10 DEF, +600 HP",mods = { ATK = 10, DEF = 10, maxHP = 600 } },
            { id = "crit4",name = "Mythic",     desc = "+25% CRIT chance",        mods = { CRIT = 0.25 } },
        }},
    },
}

M.LADDER = {
    -- Tank line: durability + threat.
    knight  = {
        title  = "Shield Mastery",
        autoBump = { DEF = 1, maxHP = 80 },
        choices = {
            { level = 3,  options = {
                { id = "guard", name = "Iron Guard",  desc = "+6 DEF",                        mods = { DEF = 6 } },
                { id = "thick", name = "Thick Skin",  desc = "+500 max HP",                    mods = { maxHP = 500 } },
            }},
            { level = 6,  options = {
                { id = "taunt", name = "Provoker",    desc = "+8 DEF, +200 HP",                mods = { DEF = 8, maxHP = 200 } },
                { id = "bash",  name = "Heavy Blow",  desc = "+6 ATK",                        mods = { ATK = 6 } },
            }},
            { level = 9,  options = {
                { id = "wall",  name = "Living Wall", desc = "+900 max HP",                    mods = { maxHP = 900 } },
                { id = "armor", name = "Tower Plate", desc = "+10 DEF",                       mods = { DEF = 10 } },
            }},
            { level = 12, options = {
                { id = "bulw",  name = "Bulwark",     desc = "+8 ATK, +8 DEF",                mods = { ATK = 8, DEF = 8 } },
                { id = "vital", name = "Vitality",    desc = "+1200 max HP",                   mods = { maxHP = 1200 } },
            }},
            { level = 15, options = {
                { id = "bastn", name = "Bastion",     desc = "+14 DEF, +600 HP",               mods = { DEF = 14, maxHP = 600 } },
                { id = "warhd", name = "Warhead",     desc = "+14 ATK",                       mods = { ATK = 14 } },
            }},
            { level = 18, options = {
                { id = "giant", name = "Colossus",    desc = "+2000 max HP",                   mods = { maxHP = 2000 } },
                { id = "siege", name = "Siege Breaker",desc = "+18 ATK, +10 DEF",             mods = { ATK = 18, DEF = 10 } },
            }},
            { level = 21, options = {
                { id = "fortr", name = "Fortress",    desc = "+20 DEF, +1000 HP",              mods = { DEF = 20, maxHP = 1000 } },
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
                { id = "evasive",name = "Evasive",    desc = "+300 HP, +8% CRIT",              mods = { maxHP = 300, CRIT = 0.08 } },
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
                { id = "snel",  name = "Silent Steps",desc = "+400 HP, +6% CRIT",              mods = { maxHP = 400, CRIT = 0.06 } },
                { id = "hail",  name = "Arrowsmith",  desc = "+12 ATK",                       mods = { ATK = 12 } },
            }},
            { level = 12, options = {
                { id = "hunt",  name = "Beast Hunter",desc = "+10 ATK, +12% CRIT",            mods = { ATK = 10, CRIT = 0.12 } },
                { id = "surviv",name = "Survivor",    desc = "+700 HP, +8% CRIT",              mods = { maxHP = 700, CRIT = 0.08 } },
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
        autoBump = { ATK = 1, DEF = 1, maxHP = 40 },
        choices = {
            { level = 3,  options = {
                { id = "mend",  name = "Field Medicine",desc = "+450 max HP",                  mods = { maxHP = 450 } },
                { id = "ember", name = "Ember Blade",   desc = "+5 ATK",                      mods = { ATK = 5 } },
            }},
            { level = 6,  options = {
                { id = "path",  name = "Pathfinder",    desc = "+6 DEF, +250 HP",              mods = { DEF = 6, maxHP = 250 } },
                { id = "heal",  name = "Mending Hands", desc = "+700 max HP",                  mods = { maxHP = 700 } },
            }},
            { level = 9,  options = {
                { id = "ward",  name = "Battle Ward",   desc = "+8 DEF",                      mods = { DEF = 8 } },
                { id = "tenac", name = "Tenacity",      desc = "+1000 max HP",                 mods = { maxHP = 1000 } },
            }},
            { level = 12, options = {
                { id = "shaman",name = "Shamanic Rites",desc = "+1200 max HP, +5 ATK",         mods = { maxHP = 1200, ATK = 5 } },
                { id = "clash", name = "Clash Proof",   desc = "+10 DEF, +400 HP",             mods = { DEF = 10, maxHP = 400 } },
            }},
            { level = 15, options = {
                { id = "druid", name = "Druidic Bloom", desc = "+1600 max HP",                 mods = { maxHP = 1600 } },
                { id = "warlock",name = "Warlock Pact", desc = "+14 ATK, +8 DEF",             mods = { ATK = 14, DEF = 8 } },
            }},
            { level = 18, options = {
                { id = "oracle",name = "Oracle",        desc = "+1200 max HP, +10% CRIT",      mods = { maxHP = 1200, CRIT = 0.10 } },
                { id = "veteran",name = "Seasoned Vet", desc = "+18 ATK, +12 DEF",            mods = { ATK = 18, DEF = 12 } },
            }},
            { level = 21, options = {
                { id = "sage",  name = "Battle Sage",   desc = "+2000 max HP, +15% CRIT",      mods = { maxHP = 2000, CRIT = 0.15 } },
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
                { id = "blood", name = "Blood Pact",    desc = "+400 HP, +10 ATK",             mods = { maxHP = 400, ATK = 10 } },
            }},
            { level = 12, options = {
                { id = "ritual",name = "Dark Ritual",   desc = "+14 ATK, +12% CRIT",          mods = { ATK = 14, CRIT = 0.12 } },
                { id = "veil",  name = "Veil Witch",    desc = "+600 HP, +10% CRIT",           mods = { maxHP = 600, CRIT = 0.10 } },
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
        autoBump = { ATK = 1, maxHP = 60 },
        choices = {
            { level = 3,  options = {
                { id = "bless", name = "Blessed Aegis", desc = "+400 max HP",                  mods = { maxHP = 400 } },
                { id = "hymn",  name = "Hymn of Faith", desc = "+5 ATK (holy power)",         mods = { ATK = 5 } },
            }},
            { level = 6,  options = {
                { id = "shield",name = "Sanctified Shield", desc = "+6 DEF, +300 HP",          mods = { DEF = 6, maxHP = 300 } },
                { id = "light", name = "Radiant Light", desc = "+700 max HP",                  mods = { maxHP = 700 } },
            }},
            { level = 9,  options = {
                { id = "prayer",name = "Prayer of Mending", desc = "+1100 max HP",             mods = { maxHP = 1100 } },
                { id = "zeal",  name = "Zealotry",      desc = "+9 ATK",                      mods = { ATK = 9 } },
            }},
            { level = 12, options = {
                { id = "halo",  name = "Halo of Protection", desc = "+8 DEF, +800 HP",         mods = { DEF = 8, maxHP = 800 } },
                { id = "miracle",name = "Miracle Worker",desc = "+1300 max HP",                mods = { maxHP = 1300 } },
            }},
            { level = 15, options = {
                { id = "angel", name = "Angelic Favor", desc = "+1000 max HP, +6% CRIT",       mods = { maxHP = 1000, CRIT = 0.06 } },
                { id = "avenger",name = "Avenging Host",desc = "+14 ATK",                     mods = { ATK = 14 } },
            }},
            { level = 18, options = {
                { id = "prophet",name = "Prophet",       desc = "+1400 max HP, +10% CRIT",     mods = { maxHP = 1400, CRIT = 0.10 } },
                { id = "judge", name = "Divine Judge",  desc = "+18 ATK, +10 DEF",            mods = { ATK = 18, DEF = 10 } },
            }},
            { level = 21, options = {
                { id = "saint", name = "Saint",         desc = "+2000 max HP, +12% CRIT",      mods = { maxHP = 2000, CRIT = 0.12 } },
                { id = "archang",name = "Archangel",    desc = "+22 ATK, +16 DEF",            mods = { ATK = 22, DEF = 16 } },
            }},
        },
    },
    paladin  = {
        title  = "Oathkeeper",
        autoBump = { DEF = 1, maxHP = 70 },
        choices = {
            { level = 3,  options = {
                { id = "oath",  name = "Oath of Steel", desc = "+7 DEF",                      mods = { DEF = 7 } },
                { id = "creed", name = "Creed of Life", desc = "+500 max HP",                  mods = { maxHP = 500 } },
            }},
            { level = 6,  options = {
                { id = "holy",  name = "Holy Bulwark",  desc = "+9 DEF, +250 HP",              mods = { DEF = 9, maxHP = 250 } },
                { id = "wrath", name = "Righteous Wrath", desc = "+6 ATK",                    mods = { ATK = 6 } },
            }},
            { level = 9,  options = {
                { id = "guard", name = "Guardian Oath", desc = "+1000 max HP",                 mods = { maxHP = 1000 } },
                { id = "hammer",name = "Hammer of Justice", desc = "+11 ATK",                 mods = { ATK = 11 } },
            }},
            { level = 12, options = {
                { id = "sentinel",name = "Sentinel",    desc = "+9 ATK, +9 DEF",              mods = { ATK = 9, DEF = 9 } },
                { id = "bulwark2",name = "Bulwark",     desc = "+1300 max HP",                 mods = { maxHP = 1300 } },
            }},
            { level = 15, options = {
                { id = "champion2",name = "Holy Champion",desc = "+15 DEF, +700 HP",           mods = { DEF = 15, maxHP = 700 } },
                { id = "cruiser",name = "Crusader",    desc = "+15 ATK",                      mods = { ATK = 15 } },
            }},
            { level = 18, options = {
                { id = "justicar",name = "Justicar",    desc = "+2100 max HP",                 mods = { maxHP = 2100 } },
                { id = "palbld",name = "Paladin Blade", desc = "+18 ATK, +11 DEF",            mods = { ATK = 18, DEF = 11 } },
            }},
            { level = 21, options = {
                { id = "templar",name = "Templar",      desc = "+22 DEF, +1100 HP",            mods = { DEF = 22, maxHP = 1100 } },
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
                { id = "abjuration",name = "Abjurer",   desc = "+500 HP, +10% CRIT",           mods = { maxHP = 500, CRIT = 0.10 } },
                { id = "evocation",name = "Evoker",     desc = "+16 ATK, +8% CRIT",           mods = { ATK = 16, CRIT = 0.08 } },
            }},
            { level = 15, options = {
                { id = "mage2", name = "Archmage",      desc = "+26% CRIT",                   mods = { CRIT = 0.26 } },
                { id = "pyrom", name = "Pyromancer",    desc = "+20 ATK",                     mods = { ATK = 20 } },
            }},
            { level = 18, options = {
                { id = "astral",name = "Astral Projection", desc = "+600 HP, +16% CRIT",       mods = { maxHP = 600, CRIT = 0.16 } },
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
                { id = "venom", name = "Venomous Blades", desc = "+350 HP, +10% CRIT",         mods = { maxHP = 350, CRIT = 0.10 } },
                { id = "shadow",name = "Shadow Dance",  desc = "+13 ATK",                     mods = { ATK = 13 } },
            }},
            { level = 12, options = {
                { id = "assas", name = "Assassin",      desc = "+11 ATK, +12% CRIT",          mods = { ATK = 11, CRIT = 0.12 } },
                { id = "skulk", name = "Skulker",       desc = "+600 HP, +9% CRIT",            mods = { maxHP = 600, CRIT = 0.09 } },
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

function M.ladderFor(class)
    return M.LADDER[class] or GENERIC_LADDER
end

-- Sum of the stat mods of every option picked in `skillTree` (see header).
function M.modsFor(class, skillTree)
    local out = {}
    if type(skillTree) ~= "table" then return out end
    for i, choice in ipairs(M.ladderFor(class).choices) do
        local picked = skillTree[i]
        for _, opt in ipairs(choice.options) do
            if opt.id == picked then
                for k, v in pairs(opt.mods) do out[k] = (out[k] or 0) + v end
            end
        end
    end
    return out
end

return M

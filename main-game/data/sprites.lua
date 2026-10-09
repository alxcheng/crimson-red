-- data/sprites.lua — sprite sheets loaded for battle.
-- Each row: {sheet name, file under assets/, frame count, frame w, frame h}.
-- How big a unit is drawn is NOT here: it is the one `scale` number on the unit's
-- row in data/classes.lua / data/enemies.lua. After adding or changing an Idle
-- sheet run ./align_sprites (it measures where the sprite is inside its frame).
-- A sheet is one horizontal strip of equally sized frames. The sheet name is
-- what data/classes.lua ANIM_SETS refers to (<sprite><suffix>).

local C, E = "characters/", "enemies/"

local SHEETS = {
    {"KnightIdle",    C.."Knight/Idle.png",     10, 135, 135},
    {"KnightMove",    C.."Knight/Run.png",       6, 135, 135},
    {"KnightAttack1", C.."Knight/Attack1.png",   4, 135, 135},
    {"KnightAttack2", C.."Knight/Attack2.png",   4, 135, 135},
    {"KnightTakeHit", C.."Knight/Take Hit.png",  3, 135, 135},
    {"KnightDeath",   C.."Knight/Death.png",     9, 135, 135},

    {"BrigandIdle",    C.."Brigand/Idle.png",    10, 126, 126},
    {"BrigandMove",    C.."Brigand/Run.png",      8, 126, 126},
    {"BrigandAttack1", C.."Brigand/Attack1.png",  7, 126, 126},
    {"BrigandDeath",   C.."Brigand/Death.png",   11, 126, 126},

    {"ChampionIdle",    C.."Champion/Idle.png",    8, 160, 111},
    {"ChampionMove",    C.."Champion/Run.png",     8, 160, 111},
    {"ChampionAttack1", C.."Champion/Attack1.png", 4, 160, 111},
    {"ChampionDeath",   C.."Champion/Death.png",   6, 160, 111},

    {"DuelistIdle",    C.."Duelist/Idle.png",    8, 200, 200},
    {"DuelistMove",    C.."Duelist/Run.png",     8, 200, 200},
    {"DuelistAttack1", C.."Duelist/Attack1.png", 6, 200, 200},
    {"DuelistDeath",   C.."Duelist/Death.png",   6, 200, 200},

    {"NomadIdle",    C.."Nomad/Idle.png",    8, 250, 250},
    {"NomadMove",    C.."Nomad/Run.png",     8, 250, 250},
    {"NomadAttack1", C.."Nomad/Attack1.png", 8, 250, 250},
    {"NomadAttack2", C.."Nomad/Attack2.png", 8, 250, 250},
    {"NomadDeath",   C.."Nomad/Death.png",   7, 250, 250},

    {"SkeletonIdle",   E.."Skeleton/Idle.png",   4, 150, 150},
    {"SkeletonMove",   E.."Skeleton/Walk.png",   4, 150, 150},
    {"SkeletonAttack", E.."Skeleton/Attack.png", 8, 150, 150},
    {"SkeletonDeath",  E.."Skeleton/Death.png",  4, 150, 150},

    {"GoblinIdle",   E.."Goblin/Idle.png",   4, 150, 150},
    {"GoblinMove",   E.."Goblin/Move.png",   8, 150, 150},
    {"GoblinAttack", E.."Goblin/Attack.png", 8, 150, 150},
    {"GoblinDeath",  E.."Goblin/Death.png",  4, 150, 150},

    -- The bat only has a flight loop: it is both its idle and its move sheet.
    {"BatIdle",   E.."Bat/Flight.png", 8, 150, 150},
    {"BatMove",   E.."Bat/Flight.png", 8, 150, 150},
    {"BatAttack", E.."Bat/Attack.png", 8, 150, 150},
    {"BatDeath",  E.."Bat/Death.png",  4, 150, 150},

    {"MushroomIdle",   E.."Mushroom/Idle.png",   4, 150, 150},
    {"MushroomMove",   E.."Mushroom/Move.png",   8, 150, 150},
    {"MushroomAttack", E.."Mushroom/Attack.png", 8, 150, 150},
    {"MushroomDeath",  E.."Mushroom/Death.png",  4, 150, 150},
}

-- Recoloured copies of the Knight: same frames, clothes shifted to another
-- colour. The files were generated with
--   ./recolor shift main-game/assets/characters/Knight main-game/assets/characters/<Name> 225 <hue> 30 <sat> <val>
-- (225 = the Knight's blue). To add another: run that, add a row here, add an
-- ANIM_SETS entry in data/classes.lua.
local RECOLOURS = {
    -- name      hue  sat  val   (the arguments used)
    "Cleric",  -- 48  0.9  1.9   yellow
    "Paladin", -- 130 1.0  1.35  green
    "Wizard",  -- 290 1.0  1.4   purple
    "Rogue",   -- 355 1.1  1.15  dark red
}
for _, name in ipairs(RECOLOURS) do
    for _, row in ipairs(SHEETS) do
        if row[1]:sub(1, 6) == "Knight" then
            SHEETS[#SHEETS + 1] = { name .. row[1]:sub(7), (row[2]:gsub("Knight/", name .. "/")), row[3], row[4], row[5] }
        end
    end
end

return SHEETS

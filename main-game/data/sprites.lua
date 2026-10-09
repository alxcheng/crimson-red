-- data/sprites.lua — sprite sheets loaded for battle.
-- Each row: {sheet name, file under assets/, frame count, frame w, frame h, draw scale}.
-- A sheet is one horizontal strip of equally sized frames. The sheet name is
-- what data/classes.lua ANIM_SETS refers to (<sprite><suffix>).

local C, E = "characters/", "enemies/"

return {
    {"KnightIdle",    C.."Knight/Idle.png",     10, 135, 135, 1.1},
    {"KnightMove",    C.."Knight/Run.png",       6, 135, 135, 1.1},
    {"KnightAttack1", C.."Knight/Attack1.png",   4, 135, 135, 1.1},
    {"KnightAttack2", C.."Knight/Attack2.png",   4, 135, 135, 1.1},
    {"KnightTakeHit", C.."Knight/Take Hit.png",  3, 135, 135, 1.1},
    {"KnightDeath",   C.."Knight/Death.png",     9, 135, 135, 1.1},

    {"BrigandIdle",    C.."Brigand/Idle.png",    10, 126, 126, 0.9},
    {"BrigandMove",    C.."Brigand/Run.png",      8, 126, 126, 0.9},
    {"BrigandAttack1", C.."Brigand/Attack1.png",  7, 126, 126, 0.9},
    {"BrigandDeath",   C.."Brigand/Death.png",   11, 126, 126, 0.9},

    {"ChampionIdle",    C.."Champion/Idle.png",    8, 160, 111, 1.0},
    {"ChampionMove",    C.."Champion/Run.png",     8, 160, 111, 1.0},
    {"ChampionAttack1", C.."Champion/Attack1.png", 4, 160, 111, 1.0},
    {"ChampionDeath",   C.."Champion/Death.png",   6, 160, 111, 1.0},

    {"DuelistIdle",    C.."Duelist/Idle.png",    8, 200, 200, 0.959},
    {"DuelistMove",    C.."Duelist/Run.png",     8, 200, 200, 0.959},
    {"DuelistAttack1", C.."Duelist/Attack1.png", 6, 200, 200, 0.959},
    {"DuelistDeath",   C.."Duelist/Death.png",   6, 200, 200, 0.959},

    {"NomadIdle",    C.."Nomad/Idle.png",    8, 250, 250, 0.72},
    {"NomadMove",    C.."Nomad/Run.png",     8, 250, 250, 0.72},
    {"NomadAttack1", C.."Nomad/Attack1.png", 8, 250, 250, 0.72},
    {"NomadAttack2", C.."Nomad/Attack2.png", 8, 250, 250, 0.72},
    {"NomadDeath",   C.."Nomad/Death.png",   7, 250, 250, 0.72},

    {"SkeletonIdle",   E.."Skeleton/Idle.png",   4, 150, 150, 0.75},
    {"SkeletonMove",   E.."Skeleton/Walk.png",   4, 150, 150, 0.75},
    {"SkeletonAttack", E.."Skeleton/Attack.png", 8, 150, 150, 0.75},
    {"SkeletonDeath",  E.."Skeleton/Death.png",  4, 150, 150, 0.75},
    -- Bat, Imp and Mushroom sheets exist under assets/enemies/ but no enemy
    -- row uses them yet; add them here when their rows are added.
}

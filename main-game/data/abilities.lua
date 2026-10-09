-- data/abilities.lua — every ability in the game, as data.
--
-- One row per ability, keyed by ability id. Rows are pure data: the engine in
-- encounter/abilities.lua interprets them. To add an ability, add a row and
-- reference its id from a class in data/classes.lua (or an enemy in
-- data/enemies.lua). Value tags: [IL]/[wiki] = from Battleheart, [tuned] = ours.
--
-- Row fields:
--   name          display name
--   iconName      "skill_iconsN" (assets/icons/); omit for default actions
--   cdMax         cooldown in seconds (default 15). For a default action
--                 (slot 0) this is the attack interval; "attack speed" shortens
--                 it and never changes the animation.
--   bars          cost in BARS of the shared resource (one bar = 5 resource),
--                 paid when the key is pressed. ALWAYS A WHOLE NUMBER OF BARS —
--                 never half a bar. Default 3. Default actions are free.
--   bh            true = a Battleheart ability: cdMax is BH's cooldown
--                 (bh/data/classes.json) and, unless `bars` is given, the cost
--                 is  cd // 10  bars (20 s -> 2, 30 s -> 3, 45 s -> 4, 60 s -> 6)
--   noTargetRequired  true = can fire without a selected target (self / group)
--   animListIdx   which of the caster's animations to play (index into its
--                 anim set in data/classes.lua; default 4)
--   animLock      seconds the caster cannot move after casting (heroes only)
--   delay         seconds from cast to the effect landing (the wind-up)
--   isActionEffect false = a move order does not cancel it
--   effect        what happens — see "Effect kinds" in encounter/abilities.lua
--
-- Statuses are referred to by NAME (see encounter/status.lua).

local DB = {}


-- ----------------------------------------------------------------------------
-- CRIMSON RED ORIGINALS — Knight and Nomad
-- ----------------------------------------------------------------------------

-- Knight: Sunder Armor (slot 1)
DB.KnightSunderArmor = {
    name = "SunderArmor", iconName = "skill_icons17",
    -- default cooldown (15 s) and cost (3 bars; full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "damage", tags = { "Melee", "Slash" }, vfx = true,
        onHit = { effect = {
            kind = "status", isBuff = false,
            index = "VULNERABILITY", magnitude = 0.25, duration = 10.0,
        } },
    },
}

-- Knight: Defend (slot 2, self-cast)
DB.KnightDefend = {
    name = "KnightDefend", iconName = "skill_icons22",
    noTargetRequired = true,
    -- default cooldown (15 s) and cost (3 bars; full bars only)
    animLock = 0, animListIdx = nil,
    delay = 0,  -- immediate
    effect = {
        kind = "status", isBuff = true, index = "DEF_BUFF",
        magnitude = 0.5, duration = 10.0, tint = {0, 0, 1, 4.0},
    },
}

-- Knight: Challenging Shout (slot 3, self-cast AoE threat)
DB.KnightChallengingShout = {
    name = "ChallengingShout", iconName = "skill_icons13",
    noTargetRequired = true,
    -- default cooldown (15 s) and cost (3 bars; full bars only)
    animLock = 0, animListIdx = nil,
    delay = 0,
    -- Flat threat on every living enemy.
    effect = {
        kind = "threat",
        flat = 350,  -- [tuned] ~10 knight hits' worth of threat
    },
}

-- Nomad: Grant Power (slot 1)
DB.NomadGrantPower = {
    name = "GrantPower", iconName = "skill_icons15",
    -- default cooldown (15 s) and cost (3 bars; full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    -- ATK buff on the target ally (+50% outgoing, 10s) + red tint [data].
    effect = {
        kind = "status", isBuff = true, index = "ATK_BUFF",
        magnitude = 0.5, duration = 10.0, tint = {1, 0, 0, 4.0},
    },
}

-- Nomad: Mend Wounds (slot 2)
DB.NomadMendWounds = {
    name = "MendWounds", iconName = "skill_icons11",
    -- default cooldown (15 s) and cost (3 bars; full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "status", isBuff = true, index = "HOT",
        dotPerSec = 0.5, duration = 10.0,  -- heals 0.5 x caster power per second [tuned]
        tint = {0, 1, 0, 4.0},
    },
}

-- Nomad: Spark of Inspiration (slot 3)
DB.NomadSparkOfInspiration = {
    name = "SparkOfInspiration", iconName = "skill_icons46",
    bars = 0,   -- free: it trades HP for resource (default 15 s cooldown)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "drainHp", fraction = 0.20 },       -- sacrifice 20% target HP
            { kind = "resourceGain", amount = 20 },      -- +20 resource to caster
        },
    },
}

-- ----------------------------------------------------------------------------
-- AUTO-ATTACK ABILITIES (data rows for the parametric auto-attack factory)
-- ----------------------------------------------------------------------------
-- `delay` is timed to the frame of the attack animation where the blow lands.

DB.KnightAutoAttack = {
    name = "KnightAutoAttack",
    cdMax = 1.1,
    animListIdx = 3, animLock = 4*7/60,
    delay = 14/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

DB.SkeletonAutoAttack = {
    name = "SkeletonAutoAttack",
    cdMax = 1.3,   -- BH basic1 primaryActionCooldown
    animListIdx = 3, animLock = 8*7/60,
    delay = 24.5/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

DB.NomadAutoHeal = {
    name = "NomadAutoHeal",
    cdMax = 2.8,
    animListIdx = 3, animLock = 8*7/60,
    delay = 28/60,
    effect = { kind = "heal", value = 1.0 },
}

DB.BrigandAutoAttack = {
    name = "BrigandAutoAttack",
    cdMax = 0.9,
    animListIdx = 3, animLock = 7*7/60,
    delay = 5*7/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

DB.ChampionAutoAttack = {
    name = "ChampionAutoAttack",
    cdMax = 1.15,
    animListIdx = 3, animLock = 4*7/60,
    delay = 3*7/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

DB.DuelistAutoAttack = {
    name = "DuelistAutoAttack",
    cdMax = 0.9,
    animListIdx = 3, animLock = 6*7/60,
    delay = 5*7/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- ----------------------------------------------------------------------------
-- PORTED FROM BATTLEHEART — Cleric, Paladin, Wizard, Rogue
--
-- Current numbers are the earlier wiki/tuned estimates. BH's real cooldowns
-- are in bh/data/classes.json, its buff magnitudes and durations in
-- bh/data/prefabs/MotherBrain.json, and each ability's exact behaviour in
-- bh/systems/hero-abilities-part1.md / part2.md.
-- ----------------------------------------------------------------------------

-- ============================ CLERIC (Lucille) ==============================
-- Support. NO melee auto-attack; its default action IS the auto-HEAL below.
-- Stats [spec §1.2]: maxHP 300 [tuned], DEF 9 [wiki], ATK 16 [wiki], CRIT 0,
-- MOVE_SPEED 3.0 [tuned]; heal cadence 1.75s [wiki]. Heals scale off power.

-- slot 0: Auto-Heal (default action, single-ally = selected target)
DB.ClericAutoHeal = {
    name = "ClericAutoHeal",
    cdMax = 1.75,
    animListIdx = 3, animLock = 8*7/60,
    delay = 28/60,
    effect = { kind = "heal", value = 1.15 },  -- passives[0]==-1 ⇒ ×1.15 (spec IL L88497)
}

-- Group Heal: heal every living ally (whole arena, not radius-limited)
DB.ClericGroupHeal = {
    name = "GroupHeal", iconName = "skill_icons11",
    noTargetRequired = true,
    cdMax = 20.0, bh = true,   -- BH cooldown; cost = cd // 10 = 2 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = { kind = "healGroup", value = 1.0 },
}

-- Shield: single-ally, takes -75% damage for 10s (flat SHIELD reduction).
-- Index given by NAME so it resolves as soon as "SHIELD" is present.
DB.ClericShield = {
    name = "Shield", iconName = "skill_icons22",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 12/60,
    effect = { kind = "status", isBuff = true, index = "SHIELD", magnitude = 0.75, duration = 10.0 },
}

-- Power Infusion: single-ally, ATK ×2 (=+100%) for 10s
DB.ClericPowerInfusion = {
    name = "PowerInfusion", iconName = "skill_icons15",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 12/60,
    effect = { kind = "status", isBuff = true, index = "ATK_BUFF", magnitude = 1.0, duration = 10.0 },
}

-- Vengeful Angel: self → AoE around the CASTER, pulse-damage + knockback all
-- enemies in radius. [wiki CD60/res30; radius ~90px ≈ BH 2.0u; power·1.0
-- [tuned]]. APPROXIMATION: BH runs this as a per-frame aura while buffed; for
-- the port it is a single on-cast AoE pulse (the spec-approved simplification).
DB.ClericVengefulAngel = {
    name = "VengefulAngel", iconName = "skill_icons46",
    noTargetRequired = true,
    cdMax = 60.0, bh = true,   -- BH cooldown; cost = cd // 10 = 6 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90, centerSelf = true,   -- centered on caster
        alsoKnockback = { force = 120 },                -- [tuned] push-away
        inner = { kind = "damage", tags = { "Melee" }, vfx = true },
    },
}

-- ============================= PALADIN (Heleth) =============================
-- Tank / hybrid healer. HAS a melee auto + draws aggro (hasThreateningPresence).
-- Stats [spec §2.2]: maxHP 520 [tuned], DEF 24 [wiki Lv5], ATK 24 [wiki],
-- CRIT 0, MOVE_SPEED 2.8 [tuned], swing 1.1s [tuned].

-- slot 0: Melee auto (tank swing)
DB.PaladinAutoAttack = {
    name = "PaladinAutoAttack",
    cdMax = 1.1,
    animListIdx = 3, animLock = 4*7/60,
    delay = 9.3/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- Holy Word: heal the most-injured living ally (power·1.5 [wiki-only])
DB.PaladinHolyWord = {
    name = "HolyWord", iconName = "skill_icons11",
    noTargetRequired = true,
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = { kind = "healLowestAlly", value = 1.5 },
}

-- Divine Intervention: self protection for 10s. APPROXIMATION (the real BH
-- hook is a damage-redirect slot `buffs[0x1e]` we don't have); declared as the
-- WARD .5 (chance to negate) + REFLECT .5 (return half) pair.
DB.PaladinDivineIntervention = {
    name = "DivineIntervention", iconName = "skill_icons22",
    noTargetRequired = true,
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = nil,
    delay = 0,
    effect = {
        kind = "effects", targetSelf = true,
        effects = {
            { kind = "status", isBuff = true, index = "WARD",    magnitude = 0.5, duration = 10.0 },
            { kind = "status", isBuff = true, index = "REFLECT", magnitude = 0.5, duration = 10.0 },
        },
    },
}

-- Aura of Light: self, incoming damage converted to healing for 10s.
-- APPROXIMATION: under-faithful vs BH's full conversion — reuses the REFLECT
-- slot at .6 (returns 60% of would-be damage via the existing reflect path).
DB.PaladinAuraOfLight = {
    name = "AuraOfLight", iconName = "skill_icons46",
    noTargetRequired = true,
    cdMax = 40.0, bh = true,   -- BH cooldown; cost = cd // 10 = 4 bars (full bars only)
    animLock = 0, animListIdx = nil,
    delay = 0,
    effect = {
        kind = "status", isBuff = true, index = "REFLECT",
        magnitude = 0.6, duration = 10.0,
    },
}

-- Wrath: self imbue for 10s; while active the paladin's MELEE HITS chain
-- lightning to up to 3 nearby foes with decaying damage. Data-driven via a
-- dedicated CHAIN_LIGHTNING buff ("CHAIN"): combat.readTagSystem sees the
-- "Melee" tag on each auto-attack and rolls the chain, consuming one charge per
-- hit so it lasts ~10s at the 1.1s swing cadence. [wiki CD30/res20; count 3,
-- decay 0.5, 10 charges all [tuned]]. DEFERRED in-scope note: true per-frame
-- on-hit chaining with a timer-based expire would need a bespoke status handler;
-- the charge-consume model keeps it fully data-driven and time-bounded.
DB.PaladinWrath = {
    name = "Wrath", iconName = "skill_icons15",
    noTargetRequired = true,
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 0,
    effect = {
        kind = "status", isBuff = true, index = "CHAIN",
        -- magnitude field carries the charge count; chain params ride alongside
        magnitude = 10,                       -- [tuned] ~10 melee hits over 10s
        chainParams = { count = 3, decay = 0.5 },  -- [tuned]
        duration = 10.0,
        tint = {1, 0.85, 0.3, 4.0},
    },
}

-- ============================= WIZARD (Bromswell) ===========================
-- Ranged DPS (isRanged=true). Auto-FIREs; heavy CC.
-- Stats [spec §3.2]: maxHP 260 [tuned], DEF 5 [wiki], ATK 28 [inferred],
-- CRIT 0, MOVE_SPEED 3.2 [tuned], cast interval 1.6s [tuned].

-- slot 0: Auto Fireball (aimed-shot distance reward, ranged)
DB.WizardAutoFireball = {
    name = "WizardAutoFireball",
    cdMax = 1.5,
    animListIdx = 3, animLock = 0,
    delay = 17.5/60,
    effect = {
        -- vfx=false: the auto-fireball must NOT screen-shake on every hit —
        -- it fires on a 1.6s loop, so per-hit shake would be constant
        -- nauseating rattle. Camera shake now comes from VALID ABILITY
        -- PRESSES instead (see skills.enqueue → combat.triggerActivationVFX).
        kind = "damage", tags = { "Ranged", "Fire" }, vfx = false,
        ability = { aimedShot = true, falloff = 1.5, canCrit = true },
    },
}

-- Meteor: impact AoE around the target point, large radius (aimedShot), cost 30.
-- Magnitude [wiki-only] ~ power·2.0 → buffMods{2.0}. Radius 90 px ≈ BH 2.0u.
DB.WizardMeteor = {
    name = "Meteor", iconName = "skill_icons46",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90,
        inner = {
            kind = "damage", tags = { "Ranged", "Fire" }, vfx = true,
            ability = { aimedShot = true, falloff = 1.5, canCrit = true },
            buffMods = { [0] = 2.0 },
        },
    },
}

-- Blizzard: AoE all enemies in radius — damage + SLOW (moveSpeed down) 10s.
-- Declared as an aoe with an inner damage + alsoStatus SLOW (index by NAME so
-- it resolves once "SLOW" exists).
DB.WizardBlizzard = {
    name = "Blizzard", iconName = "skill_icons46",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90,
        inner = {
            kind = "damage", tags = { "Ranged", "Fire" }, vfx = true,
            ability = { aimedShot = true, falloff = 1.5, canCrit = true },
        },
        alsoStatus = { kind = "status", isBuff = false, index = "SLOW", magnitude = 0.4, duration = 10.0 },
    },
}

-- Time Stop: stun (freeze) all living enemies for 5s. Drives world.stun via
-- combat.applyStun (reliable CC; the STUN status slot has no behavior, so we
-- do NOT rely on it).
DB.WizardTimeStop = {
    name = "TimeStop", iconName = "skill_icons46",
    noTargetRequired = true,
    cdMax = 45.0, bh = true,   -- BH cooldown; cost = cd // 10 = 4 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = { kind = "stunAll", seconds = 5.0 },
}

-- Conflagrate: single-enemy DOT burn + brief disable. [wiki CD40/res20; DOT
-- power·0.5/s for 6s, STUN 1.5s — magnitudes [tuned]]. DOT magnitude scales off
-- caster power at cast time.
DB.WizardConflagrate = {
    name = "Conflagrate", iconName = "skill_icons46",
    cdMax = 40.0, bh = true,   -- BH cooldown; cost = cd // 10 = 4 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "status", isBuff = false, index = "DOT", dotPerSec = 0.5, duration = 6.0 },  -- [tuned]
            { kind = "status", isBuff = false, index = "STUN", duration = 1.5 },                     -- [tuned]
        },
    },
}

-- Thunderbolt: AoE centered on the CASTER (self blast), damage + knockback.
-- [wiki CD30/res25; radius ~90px ≈ BH medium; knockback force [tuned]].
DB.WizardThunderbolt = {
    name = "Thunderbolt", iconName = "skill_icons46",
    noTargetRequired = true,
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 24/60,
    effect = {
        kind = "aoe", radius = 90, centerSelf = true,
        alsoKnockback = { force = 100 },   -- [tuned] push-away
        inner = {
            kind = "damage", tags = { "Ranged" }, vfx = true,
            ability = { canCrit = true },
        },
    },
}

-- ============================== ROGUE (Gustav) ==============================
-- Melee burst DPS. Fastest swing of the four (0.85s). Crit base 0.20 [wiki
-- Critical Strikes] → flat-double crits via the existing roll (set in entities).
-- Stats [spec §4.2]: maxHP 300 [tuned], DEF 11 [wiki avg 9–13], ATK 31 [wiki Lv1
-- bare, per spec §5 conflict note], CRIT 0.20, MOVE_SPEED 3.4 [tuned].

-- slot 0: fastest melee swing
DB.RogueAutoAttack = {
    name = "RogueAutoAttack",
    cdMax = 0.9,
    animListIdx = 3, animLock = 4*7/60,
    delay = 5.8/60,
    effect = { kind = "damage", tags = { "Melee" }, vfx = false },
}

-- Sneak Attack: single-enemy 250% normal damage (crits still apply). Declared
-- as a damage row with an explicit outgoing multiplier buffMods{[0]=1.5} (→ ×2.5
-- total) passed through the two-stage roll; the roll's own crit still doubles.
DB.RogueSneakAttack = {
    name = "SneakAttack", iconName = "skill_icons17",
    cdMax = 20.0, bh = true,   -- BH cooldown; cost = cd // 10 = 2 bars (full bars only)
    animLock = 4*6/60, animListIdx = 4,
    delay = 8/60,
    effect = {
        kind = "damage", tags = { "Melee" }, vfx = true,
        ability = { canCrit = true },
        buffMods = { [0] = 1.5 },   -- [wiki] 250% of normal damage
    },
}

-- Expose Weakness: single-enemy VULNERABILITY +50% for 10s
DB.RogueExposeWeakness = {
    name = "ExposeWeakness", iconName = "skill_icons15",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 0, animListIdx = 4,
    delay = 8/60,
    effect = { kind = "status", isBuff = false, index = "VULNERABILITY", magnitude = 0.5, duration = 10.0 },
}

-- Shadowstep: single-enemy 350% strike (teleport-behind movement SKIPPED — just
-- the big hit). buffMods{[0]=2.5} (→ ×3.5 total); crits still apply.
DB.RogueShadowstep = {
    name = "Shadowstep", iconName = "skill_icons17",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 6*6/60, animListIdx = 4,
    delay = 10/60,
    effect = {
        kind = "damage", tags = { "Melee" }, vfx = true,
        ability = { canCrit = true },
        buffMods = { [0] = 2.5 },   -- [wiki] 350% of normal damage
    },
}

-- Poisoned Knife: single-enemy ranged-lite — small immediate hit + DOT poison.
-- [wiki CD30/res15; immediate hit power·0.5 [tuned], DOT 6s [tuned]]. The knife
-- "throw" has no projectile renderer here (separate VFX task) — just the damage
-- + DOT seed.
DB.RoguePoisonedKnife = {
    name = "PoisonedKnife", iconName = "skill_icons11",
    cdMax = 30.0, bh = true,   -- BH cooldown; cost = cd // 10 = 3 bars (full bars only)
    animLock = 4*6/60, animListIdx = 4,
    delay = 8/60,
    effect = {
        kind = "effects",
        effects = {
            { kind = "damage", tags = { "Ranged" }, vfx = true,
              ability = { aimedShot = true, falloff = 1.5, canCrit = true },
              buffMods = { [0] = -0.5 } },   -- [tuned] small immediate hit (×0.5)
            { kind = "status", isBuff = false, index = "DOT", dotPerSec = 0.3, duration = 6.0 },  -- [tuned]
        },
    },
}

-- DEFERRED (out of scope — 5-slot UI limit): Rogue Paralytic Knife (PARALYZE 8s)
-- and Paladin Radiance (AoE knockdown + party heal). See class-port-spec §4.3 /
-- §2.3. Not wired into CLASS_SETS.

return DB

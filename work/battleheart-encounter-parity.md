# Battleheart Encounter Parity — Gap Analysis & Feature Roadmap

**Prepared by:** battleheart-research (research agent) · **For:** Director / Manager
**Scope:** encounter/combat system + immediate context only. Map/stage/progression/UI/meta are covered *only* insofar as they feed encounters.
**Sources, cross-compared (datamine wins on conflict):**
1. **Battleheart datamine** (authoritative): `docs/01-positioning-system.md`, `docs/02-damage-system.md`, and the IL dump `il/Assembly-UnityScript.il` (108,667 lines; classes `MotherBrain`, `PartyMember`, `EnemyScript`, `EffectScript`, plus data classes `Player`/`Power`/`LootTable`/`Wave`/`Level`/`LootThreshold`/`Item`/`Database`). Binary Unity assets under `decompiled/resources/assets/bin/Data` exist but are not parsed into readable tables without AssetStudio — noted where relevant.
2. **Public web** (untrusted; cited as markdown links): [Fandom Class Types](https://battleheart.fandom.com/wiki/Class_Types), [Fandom Knight](https://battleheart.fandom.com/wiki/Knight), [Fandom Cleric](https://battleheart.fandom.com/wiki/Cleric), [StrategyWiki Knight](https://strategywiki.org/wiki/Battleheart/Knight), [StrategyWiki Cleric](https://strategywiki.org/wiki/Battleheart/Cleric), [StrategyWiki Gameplay](https://strategywiki.org/wiki/Battleheart/Gameplay), [GiantBomb](https://giantbomb.com/wiki/Games/Battleheart), [Gamezebo walkthrough](https://www.gamezebo.com/walkthroughs/battleheart-walkthrough/), [PocketGamer Ranger tree](https://www.pocketgamer.com/battleheart-legacy/battleheart-legacy-expert-hints-and-tips-ranger-sk/), [GameFAQs party strategy](https://gamefaqs.gamespot.com/boards/620694-battleheart/58023935?page=1).
3. **Crimson Red code**: `main-game/encounter/*.lua` (~2,100 LOC) + `main-game/screens/encounter.lua`.

> Sourcing convention: `[IL Lxxxx]` = line range in `il/Assembly-UnityScript.il`; `[doc1 §n]` / `[doc2 §n]` = section of the porting docs; `[wiki]` = public source above; `inferred` = my interpretation, not directly read from a source.

---

## 1. TL;DR — biggest gaps

1. **Damage model is fundamentally different.** CR uses a symmetric `(value·ATK·BOOST − DEF)·RES` formula with crit chance/dodge (`combat.lua:16-29`). Battleheart has **two-stage asymmetric** math: an attacker-side roll (`power × ability multiplier`, crits, aimed-shot distance falloff) then a **victim-side** resolution (flat armor subtract, buff/debuff magnitude tables, min-3 floor, three independent full-negation slots, reflect) — and **enemies have no defense stat at all**. This must be reworked to match before anything else feels like Battleheart. `[doc2 §2-3]`
2. **No real 6-slot ring formation.** CR's "melee slot" is a *1D vertical column of up to N units on one side* (anchor-based) in `systems.lua:23-119`. Battleheart has a **symmetric 6-slot ring (3 rings × 2 sides)** around each target with request/backfill displacement logic — both player→enemy *and* enemy→player. The surround/space-out feel is missing. `[doc1 §3-5]`
3. **Ability system lacks data-driven structure, targeting modes, AoE, projectiles & CC.** CR abilities are hand-coded Lua closures with single-target or self scope, one shared 1.0 s GCD, and no AoE/projectile/fear/web/poison mechanics. Battleheart abilities come from `abilities[]`/`passives[]` index arrays + a `SpecialMove {moveName, cooldownMin, cooldownMax}` pool, run as coroutines, and include real AOE (`meteorStorm`, `earthquake`, `enrage`), projectiles (`chaosBolt`, `webShot`, `throwBomb`), summons (`summonGoblinAdds`), crowd control (`stunBolt`), and class spells (`castFireball`, `castBardBuff`, `castHeal`, `blink`, `pounceAttack`). `[IL PartyMember fields 76916+; EnemyScript 5304+; SpecialMove 5282]`
4. **Enemy AI is a single archetypes-less behavior (threat-map chaser).** Every CR enemy is a skeleton that follows a decaying threat map and auto-attacks. Battleheart enemies have rich per-type behaviors and targeting policies: highest-armor fixation + taunt rules, random-target (archers/necromancers), healer enemies, fear/flee, charge, enrage, boss phase scripts. `[IL acquireRandomTarget 22107; targetHighestArmorPlayer 23178; acquireHealTarget 17390; wiki monsters]`
5. **Status effects are ad-hoc, not an indexed table system.** CR has stagger, stun, Sunder Armor, Grant Power, Mend Wounds, Defend, Knight Rage as bespoke effect objects. Battleheart drives buffs/debuffs through `float[] buffs` / `float[] debuffs` index arrays resolved against `MotherBrain.buffMagnitudes[]` / `debuffMagnitudes[]` tables, with named effects (ward, thorns/reflect, bard song, stance aura, poison DoTs, fear/paralyze loops). A data-driven buff/debuff table is needed. `[doc2 §2.2, §5; IL MotherBrain fields 59090+]`

Secondary: loot/gold/XP/rewards are **absent** (CR victory just fades back to map); ranged attack exists but has no aimed-shot falloff/projectile travel; party is 4 vs BH's flexible 1-4 with per-class roles; difficulty scaling (`levelUpEnemies` ×1.1 tier) is absent.

---

## 2. Battleheart encounter system spec

### 2.1 Battle tick / real-time structure
- **Fully real-time, frame-steered.** No turn order. Each character runs a per-frame `AI()` / `remoteUpdate()` / `Main()` loop; movement is continuous steering toward `movementTarget`. `[IL EnemyScript methods Main/AI/remoteUpdate 5704+; PartyMember 78103+]`
- **Actions are Unity coroutines** (`IEnumerator`) — e.g. `meleeAttack()`, `rangedAttack()`, `die()`, every boss ability — i.e. timed sequences with waits, not instant resolution. Casts take time; animations lock the unit while active. `[IL EnemyScript/PetScript method lists]`
- **Per-entity action pacing:** `primaryActionCooldown`, `actionTimer`, `autoAttackTimer`, per-ability `cooldowns[]` / `remainingCooldowns[]` arrays (party) and a per-enemy `specialMoves[]` (`SpecialMove{timer, cooldownMin, cooldownMax}`). There is **no global GCD in the original** — pacing is per-ability cooldown. `[IL PartyMember.cooldowns/remainingCooldowns 76916+; SpecialMove 5282-5304]`
- **Arena = fixed camera bounded rectangle**: depth axis (z between `floor`..`ceiling`) and width axis (x between ±`edge`); a 0.3-unit inset keeps sprites off the walls. `[doc1 §1,§5,§7]`
- **Waves/spawning:** `MotherBrain` owns `waves[]` (`Wave{initialDelay, spawnDelay, maxEnemies, enemies[]}`), `spawnDelay`, `spawnCooldown`, `activeEnemies`, `maxEnemies`, and `populateEnemyPools()` + `enemySpawn()`. Enemies enter from screen edges or drop in (bats/necromancers/archers random-entry). `[IL MotherBrain fields 59090+; wiki Gameplay]`

### 2.2 Party formation & positioning
- **Manual drag-to-move** is the primary input: touch-down raycasts ground/party/enemy masks, a visible "leash" line follows, and on release the unit either free-moves to the dot (clearing its attack slot via `purgePosition`) or attacks the dropped enemy (`requestPosition`). Multi-touch commands multiple units. `[doc1 §6; IL MotherBrain.playerControl 61854-63786]`
- **Attack-slot AI (the signature mechanic):** every unit carries `meleeSlot`, `meleePositions[6]` (fixed local offsets, set per-prefab — values not recovered, see Open Q), `meleeOccupants[6]`, `attackers`. On targeting, `requestPosition(preferBack, whosAsking)` fills the ring **inside-out**; a newer attacker can **displace** an occupant one ring further out; `purgePosition` releases and backfills outer rings inward. Side chosen by horizontal position, or by target facing when `preferBack`. 5th+ concurrent attacker falls through (no slot) — recommend explicit "no slot" handling. `[doc1 §2-5,§7]`
- **Movement target computation:** `movementTarget = myTarget.position + meleePositions[meleeSlot]`, clamped to arena rect. `[doc1 §5; IL PartyMember.findMovementTarget 81248-81333]`
- **Steering** (speed/easing/facing snap) is separate and not fully traced (`animateSliding`/friction/`slideVector` present). `[doc1 §8; IL slideVector/frictionConstant fields]`
- **`preferBack`** field exists so flankers go behind relative to target facing. `[IL PartyMember.preferBack 76916+]`
- **Selection & leader:** tap to select; `leader`/`leaderScript` marks the controlled unit; selection circle UI. `[IL MotherBrain.leader/selectionCircle 59090+]`

### 2.3 Targeting & auto-attack logic
- **Auto-attack:** each combatant auto-attacks its `myTarget` once in melee range; ranged classes (`isRanged`/bow) auto-fire from afar. Party members continuously attack a selected target; clerics continuously heal their target. `[wiki Knight/Cleric; IL meleeAttack/rangedAttack/castHeal]`
- **Tank aggro rule:** a tank hit forces most enemies to fixate; `tauntable` flag gates whether an enemy will switch targets; War Cry pulls all enemies (including normally un-tauntable ones). `[wiki Gameplay/ClassTypes; IL EnemyScript.tauntable 5304+]`
- **Enemy target-selection variants:** `acquireRandomTarget()` (random pick), `targetHighestArmorPlayer()` (fixate on highest-defense living member, skip if that member already has ≥4 attackers / is busy, respect `tauntable`), `acquireHealTarget()` (healer enemies pick lowest-health ally). Bats go for healers/mages. `[IL 22107 / 23178 / 17390; wiki Monsters]`
- **Melee-range gate:** attackers only strike when within the target's melee envelope; otherwise they walk to a slot first. (CR analog: `checkMeleeRange`.)

### 2.4 Ability / skill system
- **Data-driven identity:** a party member is described by `characterClass` (int), `abilities[]` (ints), `passives[]` (ints, values `+1/-1/0` = variant), `cooldowns[]`, `remainingCooldowns[]`, `myEffectNames[]`, `myEffectPrereqs[]`, and prefabs `myEffects[]`/`mySounds[]`. Powers themselves live in `Database.powerDB` (`powerCollection{whichClass, powerScale, defenseScale, healthScale, Power[]{powerName, description, icon, cooldown}}`). `[IL Player 633-665; Power 665-687; powerCollection 822-854; Database 854+; PartyMember 76916+]`
- **Player special activation:** UI `actionBar` with `actionButton1/2/3`, icons (`currentIcons`, `classIcons`, `shades`, `flashers`), cooldown shading; `performSpecial(specialSlot)` coroutine executes it; some specials need a target (`specialAwaitingTarget`). `[IL MotherBrain.actionBar* 59090+; PartyMember.performSpecial/specialAwaitingTarget]`
- **Ability vocabulary (real names from IL nested coroutine classes):**
  - *Enemy/boss:* `stunBolt`, `discharge`, `meteorStorm`, `chaosBolt`, `dropMeteor1/2`, `dropBoulder1/2`, `earthquake`, `enrage`, `spitAttack`(+`puddleDamage`), `teleport`, `webShot`, `summonSkeletonAdds`/`summonGoblinAdds`/`summonSpiderAdds`, `enterChargeMode`, `throwBomb`, boss deaths `oozeBossSplit`, `goblinBossDeath`, `lichBossDeath`, `spiderBossDeath`. `[IL $...$nested class list 5304+]`
  - *Party spells:* `castHeal`, `castBardBuff`, `castFireball`, `shootArrow`, `counterAttack`, `meleeAttack`, `clericAuraAttack`, `flameArrowPulse`, `pounceAttack`, `blink`, `adrenalineRush`. `[IL PartyMember methods]`
  - *Class examples (wiki):* Knight Shield Wall/Cleave/Intimidate/War Cry/Shield Rush (+passives Chivalry, Might, Crippling Blows, Sunder Armor, Blitz, Fortress, Revenge); Cleric Group Heal/Shield/Power Infusion (+Passion, Discipline, Guardian Angel, Vengeful Angel, Holy Embrace…); Ranger Aimed Shot/Barrage/Incendiary Arrow/Bear Trap/Vile Bolt/Apollo Strike (+Mortal Wounds, Summon Pet, Death-by-1000-Cuts…). `[wiki Knight/Cleric/Ranger]`
- **Targeting modes observed:** single target, AoE-all-around (`cleave`/`meteorStorm`/`earthquake`/`enrage`), directional/cone (`barrage`), projectile-at-point (`fireball`/`arrow`/`chaosBolt`/`throwBomb`/`meteors`), zone/puddle (`spitAttack` puddle, `bear trap`), self (`shield wall`, `bard buff` on self), ally-target (heals), and "highest defense / random" for enemy casts. `validTargets`/`projectileTarget`/`lowestHealthAlly` helpers exist. `[IL helper nested classes]`
- **Effect object (`EffectScript`)** is the spawned thing when a swing/spell connects: fields `projectileDamageMod`, `canCrit`, `applyDebuff` (+`debuffColor`), `impactForce`, `aimedShot`, `healProjectile`/`healAmount`, `followupEffect(2)`, `dramaticImpact`, `apollo`, `flameArrow`, `canMortalStrike`, `canMisdirect`. It resolves via `damageEnemy()`/`damagePlayer()`/`healPlayer()`. `[IL EffectScript 2676-4876]`

### 2.5 Enemy AI & behavior types
- **Per-enemy fields:** `AIType` (enum), `AIState` (enum incl. 1=free/manual, 100=stunned-ish per branch at `IL_008e`), `isMelee`, `chaotic`, `canBackpeddle`, `runSpeedScale`, `moveSpeed`, `tauntable`, `likeABoss`, `immuneToDeath`, `specialDeath`, `fearLocation`/`fearTimer`, `stampedeCounter`, `ignoreDebuffColor`, plus animation states `paralyzeLoop`, `fearLoop`. `[IL EnemyScript fields 5304+]`
- **Behavior inventory (from methods + wiki):** basic melee chasers (skeletons, goblins, ogres); **fixate-but-tauntable** (red bats, slimes); **random-target/un-tauntable** (archers, necromancers); **enemy healers** (necromancer heals lowest-HP ally, may self-heal); **fear** (Knight Intimidate makes adjacent enemies flee — `fearLoop`/`fearLocation`); **charge** (`enterChargeMode`, goblin leader war-cry + charge); **enrage** (golem/berserk red-slow phase); **summons** (add-spawn); **boss phase scripts** (Ooze splits into ~7 slimes; Golem boulder drops; Lich shadow-ball → death shockwave → summon minions → meteorfall → blackout-stun). `[IL methods; wiki Monsters/GameFAQs]`
- **CC on enemies:** debuffs array drives fear/paralyze/stun visuals & gating (e.g. `debuffs[0x0b]` and `debuffs[0x0d]` checked at top of `AI()`). `[IL AI() 5704-6103]`

### 2.6 Status effects / buffs / debuffs
- **Indexed table system:** `PartyMember.buffs[float][]` & `EnemyScript.debuffs[float][]`, magnitudes in `MotherBrain.buffMagnitudes[]` / `debuffMagnitudes[]` (paired with `buffDurations[]`/`debuffDurations[]`). Index→name mapping is NOT in the assembly (lives in serialized DB asset). Known-in-context indices: `0x0e`=Bard power/armor song, `0x0f`=stance/aura (outgoing AND incoming damage trade, branched by `passives[0]==±1`), `4` & `0x0d` reused across direct-hit (additive) and DoT-seed (multiplicative) paths, plus `0,2,5,6,0x12,0x14,0x15,0x17,0x1a,0x1b,0x1c,0x1e`. `[doc2 §2.2,§3.2,§5]`
- **Mechanics confirmed in damage paths:** flat bard armor; ward % full-negate (`wardChance`); two more full-negate slots (`buffs[0x1a]`, `buffs[0x17]`); reflect/thorns (`buffs[0x1c]`, heals 50-60%); guardian taunt-redirect (`buffs[0x1e]`+`myProtector`); lifesteal (`lifeDraining`, assassin variant ×0.75); vulnerability/"marked" victim debuffs increase damage taken; DoT seeds (`poisonMagnitude`, `rangerDotMagnitude`, `meteorDotMagnitude`, `conflagDotMagnitude`, `baelDotMagnitude`, `plagueDotMagnitude`) baked at cast via `calculateDamageMultiplier()`. HoTs: `directHealHotMagnitude`, `bardHotMagnitude`. `[doc2 §2-4; IL fields]`
- **Visuals:** `activateColors`/shader tints + `mostRecentBuff`/`debuffColor` color pulses. `[IL methods]`

### 2.7 Damage system (cite doc2)
- **Two-stage, asymmetric** (see TL;DR #1).
  - **Player→Enemy roll** `EffectScript.damageEnemy`: `base=attacker.power`; aimed-shot multiplies by `Clamp(dist*0.6, 1.5, projectileDamageMod)` (rewards range up to a cap); ranger aimed-shot passive ×1.4; non-`apollo` attacks crit at `critChance`% for **flat double**. → `EnemyScript.takeDamage`. `[doc2 §2.1; IL 3761-4574]`
  - **Enemy→Player roll** `EffectScript.damagePlayer`: `int(enemy.power * projectileDamageMod)` — no crit, no falloff. `[doc2 §3.1; IL 4511-4719]`
  - **Enemy resolution** `EnemyScript.takeDamage`: **no armor stat**; adds attacker-offense fractions of the base roll from bard/stance/other attacker buffs and victim vulnerability debuffs; lifesteal; floating text; subtract HP. All additive, no compounding. `[doc2 §2.2; IL 18394-19181]`
  - **Party resolution** `PartyMember.takeDamage`: guardian redirect → invincible check → `-(defense+sentinelDefense)` flat armor → bard armor subtract → buff multipliers (incl. dual-purpose `0x0f`) → enemy-debuff "damage taken" multipliers → **min-3 floor** → ward negation / `0x1a` / reflect(`0x1c`) / `0x17` negations in sequence → subtract HP. `[doc2 §3.2; IL 81498-82407]`
  - **DoT seed** `calculateDamageMultiplier`: multiplicative over `buffs[4]`, `debuffs[2]/[6]`, `buffs[0x0d]`; seeded as `0.5×power×mult`. `[doc2 §4; IL 86535-86610]`
- **Difficulty scaling:** `MotherBrain.levelUpEnemies()` multiplies every live enemy's `maxHealth` and `power` by **1.1×** and bumps `enemyTier` (stacks 1.1ⁿ); trigger unknown. `[doc2 §7; IL 70188-70259]`
- **Stats origin:** `PartyMember.power/defense` copied from persistent `Player` (from save data); level-up growth curve not in this assembly. `[doc2 §6; IL 60077-60768]`

### 2.8 Loot / drops / XP / rewards
- **Level reward block** `Level{goldReward, XPReward, lootTable, rareChance, highScore, arenaTable[LootThreshold{requiredKills, whichTable}]}`. `[IL Level 740-781]`
- **Loot** `LootTable{tableName, minLevel, maxLevel, tableContents[]}`, items `Item{itemName, description, icon, itemType, power, upgrade, sellPrice, usableBy[], ingameModel}`; `Database.itemDB`. Victory shows `lootFrame`/`lootIcon`/`goldText`/`spoilsText` UI. `[IL Item 606-633; LootTable 687-709; Database; MotherBrain loot fields]`
- **XP:** `Database.firstLevelXP`, `XPscale`, `XPtable[]`; `MotherBrain.calculateNextLevelXP(whichLevel)`; per-party-member XP bars (`XPBars[]`, `XPBarAnimation`, `$XPReward`, `$nextLevelXP`, `$totalLivingPartyMembers` — XP split among survivors). `Player.XP`. `[IL Database; MotherBrain; Player]`
- **In-combat gold:** `$goldReward`/`$randomDrop` coroutines exist (drops during fight). Arena mode tracked separately (`arenaMode`, `enemyTier`).

### 2.9 Class archetypes & roles
- **Four roles** ([wiki Class Types]): **Tank** (Shepherd/Knight, Black Knight, Feung/Monk, Heleth/Paladin — high armor, draws aggro), **Melee DPS** (Baelrosh/Garrick Barbarian, Gustav/Robin Rogue — burst vs sustain), **Support** (Lucille Cleric, Edwardo Bard — **no auto-attack**, sustain/augment), **Ranged DPS** (Bromswell/Thistle Wizard, Wynter Witch, Oakley Ranger — high damage + CC, aim falloff).
- **10 trainable classes** exist in DB: Barbarian, Bard, Cleric, Knight, Monk, Paladin, Ranger, Rogue, Witch, Wizard. `Player{characterClass, gear[], abilities[], passives[], power, defense, maxHealth, recruited, available}`.
- **Roles drive encounter design:** tanks hold aggro so ranged/support can operate; supports have no attack and must be protected; ranged use animation-cancel to spike. `[wiki ClassTypes/Gameplay; IL Player/Database]`

---

## 3. Crimson Red current state (per subsystem, with file refs)

- **Battle tick / orchestrator** — `screens/encounter.lua:update(dt)` runs a fixed-order per-frame pipeline: `targetFollow → pendingActiveSystem → autoAttackSystem → skills.system → effects.system → effectTintSystem → stagger → stun → threat → moveTarget → physics → updateFacing → anim → death → vfxDecay → ui updates → encounter_mgr`. Real-time, frame-steered (matches BH at a high level). Resource regenerates 1/sec. `[screens/encounter.lua:323-405]`
- **Entity structure** — ECS-lite: parallel tables keyed by id in `world` (`position,size,facing,physics,moveTarget,entityTarget,side,stats,locks,stagger,stun,skills,effects_comp,bar,anim,…`). Built in `initWorld`/`initBattle`. `[screens/encounter.lua:52-99]`
- **Stats** — `stats.lua`: `{HP,maxHP,RES,BOOST,DEF,ATK,CRIT,CRIT_DEF,MOVE_SPEED,ATK_SPEED,STAGGER_RES,MAX_STAGGER,STAGGER_DUR}`, each `{base,add,mult}`; `get = base*mult + add`. `fromSave` maps save fields. Flat stats, no buff/index tables, no per-class power/defense archetype numbers. `[encounter/stats.lua]`
- **Damage** — `combat.calcNormalDmg = max(0,(value·ATK·BOOST − DEF)·RES)`; `resolveHit` crit chance = `CRIT·(1−CRIT_DEF)`; `registerHit` applies dmg, stagger, threat, hurt indicator, knockback force, tag broadcast. **Symmetric** (both sides use same formula) — differs from BH two-stage/asymmetric. No aimed-shot falloff, no min-floor on enemy side, no negation/reflect/ward. `[encounter/combat.lua:16-175]`
- **Positioning** — `systems.getMeleeSlot` computes a 1D vertical column (anchor-based, opposite side of anchor, even spacing SPACING=20). `targetFollow` sets `moveTarget`; `moveTarget` steers at `MOVE_SPEED·30`; `physics` integrates velocity+friction and clamps to screen/battle-line. **Not a 6-slot ring.** Manual move: right-click empty space sets `moveTarget` + clears target. `[encounter/systems.lua:23-238; screens/encounter.lua:454-498]`
- **Skills** — `skills.lua`: parametric `newAutoAttackSkill` (slot 0) + hand-coded active closures (Sunder Armor, Defend, Challenging Shout, Nomad Grant Power/Mend Wounds/Spark of Inspiration). One shared `GCD_DURATION=1.0` for actives; per-skill `cdMax`; `resourceCost`; queue + `pendingActive` flow; `autoAttackSystem` queues auto-attack when in range & unlocked. **No AoE, no projectiles, no CC, no data-driven definitions, no per-ability cooldown pools.** `[encounter/skills.lua]`
- **Effects** — `effects.lua`: generic effect lifecycle (pending→active→end) + constructors: hurt/heal indicators, force (knockback), timed action, Knight Rage (proc-on-melee ATK stack), Healing (HoT), KnightDefend (RES buff + tint), GrantPower (ATK mult), MendWounds (HoT), SunderArmor (DEF debuff), effect tints, tag system, cancel actions. Ad-hoc, not an indexed table. `[encounter/effects.lua]`
- **Status/CC** — Stagger (points→staggered→death-anim-reverse), Stun (timer→lock) in `combat.lua`/`systems.lua`. These are the only hard CC. No fear/flee, no paralyze, no vuln, no ward/reflect.
- **Enemy AI** — Skeletons only: `createSkeleton` gives random initial target + threat entry; `systems.threat` maintains a per-enemy `threatMap` (decay ×0.9/sec) and picks highest-threat living ally; auto-attacks it. **Single archetype, no taunt/fear/heal/random-target/charge/enrage/boss phases.** Bat/Imp/Mushroom sprites are loaded (`screens/encounter.lua:154-166`) but have **no entity creators / AI** yet. `[encounter/entities.lua:73-100; systems.lua:346-372]`
- **Encounter manager** — `encounter_mgr.lua`: danger-budget wave spawning (only skeletons), `currentDanger`/`dangerDefeated` vs `encounterGoal`, surprise waves, `checkVictory`. No loot/XP/gold on win. `[encounter/encounter_mgr.lua; screens/encounter.lua:246-261]`
- **Classes present** — Knight (tank-ish: Sunder/Defend/ChallengingShout/ThreateningPresence/Rage), Champion, Duelist, Brigand (melee DPS, auto-attack only), Nomad (support: auto-heal + Grant Power/Mend Wounds/Spark; `isRanged=true` flag but heals allies). 4-party rhombus formation, keyboard select (1-4) + Q/W/E/R skills + K spawn. **No Bard/Wizard/Witch/Rogue/Monk/Paladin/Barbarian archetypes; no per-class data-driven stats/abilities.** `[encounter/entities.lua; screens/encounter.lua:284-315]`
- **UI** — HP + stagger bars, skill icons w/ cooldown + resource sweep, shared bottom resource bar, selection circles, hover highlight, VICTORY overlay. No XP bars, no loot/gold display, no per-character ability unlock UI. `[encounter/ui.lua]`

---

## 4. Feature gap list (core deliverable)

Priority: **P0** = needed for encounters to *function like* Battleheart baseline · **P1** = important to *feel* right · **P2** = nice-to-have. Effort S/M/L.

### 4.1 Positioning & movement
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| 6-slot ring formation (3 rings × 2 sides) around each target | `requestPosition` fills inside-out, displacement/backfill | **Missing** (1D column) | Replace `getMeleeSlot` column logic with a 6-slot ring; symmetric for both sides; handle full-ring case | P0 | M | [doc1 §3-5] |
| Slot request/release w/ occupant bumping | `requestPosition`/`purgePosition`, new arrival displaces outward | Missing | Implement request/release + backfill on same side | P1 | M | [doc1 §3-4] |
| Exact `meleePositions` numeric offsets | Per-prefab (AssetStudio) | Unknown | Recover or measure empirically; choose defaults meanwhile | P1 | S/M | [doc1 §2] (Open Q) |
| Manual drag-to-move w/ leash visual | Touch raycast + drawn line, release to move/attack | Partial (RMB click teleports target) | Add drag-line visual + press-drag-release semantics; clamp to arena | P1 | M | [doc1 §6] |
| `preferBack` flank routing | Go behind relative to target facing | Missing | Add `preferBack` to slot-side choice | P2 | S | [IL PartyMember] |
| Per-frame steering speed/easing/facing | Separate locomotion step | Present (`moveTarget` steer) | Mostly OK; tune MOVE_SPEED, add facing snap | P2 | S | [doc1 §8] |

### 4.2 Targeting & auto-attack
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Continuous auto-attack of selected target | Melee/ranged auto-fire in range | Present | Works; keep | P0 | – | [wiki] |
| Tank aggro/fixate rule | Hit by armored unit fixes enemies; `tauntable` gate | Partial (`hasThreateningPresence`, threat map) | Make threat respect armor/tauntable + un-tauntable enemy types | P1 | M | [wiki; IL tauntable] |
| War-Cry pull-all (incl. un-tauntable) | Knight War Cry | Partial (ChallengingShout adds threat) | Extend shout to override un-tauntable targeting | P1 | S/M | [wiki Knight] |
| Ranged auto-fire + aimed-shot distance falloff | `Clamp(dist*0.6,1.5,mod)`, projectile travel | Partial (Nomad `isRanged`, no falloff/travel) | Add projectile entity + distance-multiplier damage | P1 | M | [doc2 §2.1] |
| Enemy target-selection variants | highest-armor / random / heal / bat→caster | Missing (all chase threat) | Add per-enemy targeting policy field | P0 | M | [IL acquire*/wiki Monsters] |

### 4.3 Abilities / skills
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Data-driven ability definition (`abilities[]`/`passives[]` + DB) | Integer-indexed arrays + `powerDB` | Missing (hardcoded closures) | Build ability table + loader so new classes are data, not code | P0 | L | [IL Player/Power/Database] |
| Per-ability cooldowns (no shared GCD) | `cooldowns[]`/`remainingCooldowns[]` per ability | Partial (shared 1.0 GCD + per-skill cd) | Move to per-ability cooldowns; drop/soften global GCD | P1 | M | [IL PartyMember] |
| AoE abilities (cleave, meteor, earthquake, enrage) | Hit all in radius / all on screen | Missing | Add area-of-effect resolver | P0 | M | [IL nested classes/wiki] |
| Projectile spells (fireball, arrow, chaos bolt, bombs) | Traveling `EffectScript.projectile` | Missing | Add projectile travel + impact resolve | P1 | M | [IL EffectScript] |
| Crowd-control spells (stun, fear, web, knockdown) | `stunBolt`,`webShot`, Intimidate-fear, Apollo knockdown | Partial (stun only) | Add fear/flee, immobilize, knockdown effects + enemy reactions | P1 | M/L | [IL; wiki Knight/Ranger] |
| Summons & pets | `summonGoblinAdds`, Ranger pet (PetScript) | Missing | Add add-spawning + optional pet framework | P2 | L | [IL; wiki Ranger] |
| Support-only class (no auto-attack) | Cleric/Bard don't auto-attack | Partial (Nomad auto-heals) | Model support auto-action = heal, not attack | P1 | S | [wiki ClassTypes] |
| Special-needs-target UI (pick target for spell) | `specialAwaitingTarget`, action bar | Missing (skills fire at entityTarget) | Add targeting reticle for targeted specials | P2 | M | [IL performSpecial] |

### 4.4 Enemy AI
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Multiple enemy archetypes (melee, ranged, caster, healer) | Per-type behaviors | Missing (skeleton only) | Add ranged/bat/caster/healer enemy creators + AI | P0 | M/L | [wiki Monsters; IL methods] |
| Fixate highest-armor + taunt switching | `targetHighestArmorPlayer` | Missing | Implement armor-based fixation + taunt rules | P1 | M | [IL 23178] |
| Random-target / un-tauntable enemies | Archers/necromancers | Missing | Add chaotic/random targeting flag | P1 | S/M | [IL acquireRandomTarget] |
| Enemy healers (heal lowest-HP ally, self) | Necromancer | Missing | Add `acquireHealTarget` + heal action | P1 | M | [IL 17390; wiki] |
| Fear / flee reaction | `fearLoop`/`fearLocation`, Intimidate | Missing | Add fear state + flee steering | P1 | M | [IL; wiki Knight] |
| Charge / enrage / berserk phases | `enterChargeMode`, `enrage`, golem red phase | Missing | Add charge + enrage (stat boost + slow) | P1 | M | [IL; wiki Golem/Goblin] |
| Boss phase scripts (split, shockwave, summon, meteorfall, stun) | Ooze/Golem/Lich/Spider | Missing | Build scriptable boss phase state machine | P2 | L | [IL die/*BossDeath; wiki Monsters] |
| Spawn variety & entry (edges vs drop-in) | Waves, bats drop from ceiling | Partial (skeletons from right) | Drive spawns from `Wave` data; vary entry | P1 | M | [IL Wave; wiki] |

### 4.5 Status effects / buffs / debuffs
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Indexed buff/debuff tables + magnitude lookup | `buffs[]`/`debuffs[]` × `buffMagnitudes[]`/`debuffMagnitudes[]` | Missing (ad-hoc effects) | Centralize status into indexed arrays resolved by magnitude tables | P0 | L | [doc2 §5; IL MotherBrain] |
| Vulnerability / "marked" (damage-taken up) | Victim debuffs idx 2/6/0x0d | Partial (SunderArmor = DEF down) | Add multiplicative damage-taken debuffs | P1 | S/M | [doc2 §2.2] |
| Ward / full-negate slots | `wardChance`, `buffs[0x1a]`,`[0x17]` | Missing | Add %chance-to-negate + absolute-negate statuses | P1 | S | [doc2 §3.2] |
| Reflect / thorns | `buffs[0x1c]` heals 50-60% | Missing | Add reflect-on-hit | P1 | S/M | [doc2 §3.2] |
| Taunt-redirect (guardian) | `buffs[0x1e]`+`myProtector` | Missing | Redirect incoming hits to protector | P2 | S/M | [doc2 §3.2] |
| Lifesteal | `lifeDraining` (assassin ×0.75) | Missing | Add drain-on-hit healing | P2 | S | [doc2 §2.2] |
| DoTs (poison, meteor, plague, conflag, bael, ranger) | Magnitude fields + ticks | Missing | Add DoT tick system seeded at cast | P1 | M | [IL EnemyScript Dot fields] |
| HoTs (direct heal, bard) | `directHealHotMagnitude` etc. | Present (MendWounds/Healing) | Keep; generalize into HoT table | P2 | S | [IL PartyMember] |
| Stance/aura dual-purpose buff (0x0f) | Trades in/out damage by passive | Missing | Add stance buffs affecting both outgoing+incoming | P2 | M | [doc2 §2.2/§3.2] |

### 4.6 Damage
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Two-stage roll→resolve architecture | Attacker roll then victim resolve | Missing (single symmetric calc) | Split damage into `roll(src)` + `resolve(victim, amt)` | P0 | M | [doc2 §1] |
| Enemy has NO armor; party has armor | Asymmetric mitigation | Wrong (both use DEF) | Remove enemy defense path; keep party armor | P0 | S | [doc2 §2.2/§3.2] |
| Flat double crit (player only) | `crit = int(base*2)` | Different (doubled final after RES) | Match: crit doubles base before resolve; no enemy crit | P1 | S | [doc2 §2.1/§3.1] |
| Aimed-shot distance falloff | `Clamp(dist*0.6,1.5,mod)` | Missing | Add range-scaled multiplier for ranged abilities | P1 | S | [doc2 §2.1] |
| Min-3 damage floor (party side) | `if dmg<3 → 3` | Missing | Add floor on party incoming | P2 | S | [doc2 §3.2] |
| Additive buff sums (no compounding) | Fractions of base roll | N/A | Ensure mitigation/offense stack additively | P1 | S | [doc2 §2.2] |
| Difficulty tier scaling (×1.1^n) | `levelUpEnemies` | Missing | Add enemy tier multiplier hook | P2 | S | [doc2 §7] |

### 4.7 Loot / XP / rewards
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| Post-victory gold reward | `Level.goldReward`, gold UI | Missing | Award + display gold on win | P1 | S | [IL Level/MotherBrain] |
| XP grant + per-member level-ups | `XPReward`, `XPtable`, split among survivors, XP bars | Missing | Compute XP, split, animate bars, level-up | P1 | M | [IL calculateNextLevelXP/$XPReward] |
| Loot drop (table roll, rare chance) | `LootTable`, `lootIcon` | Missing | Roll loot table, show item | P2 | M | [IL LootTable/Item] |
| In-combat drops | `$goldReward`/`$randomDrop` coroutines | Missing | Optional mid-fight pickups | P2 | M | [IL coroutines] |

### 4.8 Classes / party composition
| Feature | Battleheart behavior | CR state | Gap | Pri | Effort | Source |
|---|---|---|---|---|---|---|
| 10 class archetypes w/ role data | Barbarian..Wizard, DB-defined | Partial (5 CR classes) | Define full archetype set as data (role, stats, abilities, passives) | P0 | L | [wiki; IL Database/Player] |
| Role-driven behavior (tank/aggro, support/no-auto, ranged/CC) | Roles shape play | Partial (Knight tank, Nomad support) | Encode role traits driving targeting/auto-action | P1 | M | [wiki ClassTypes] |
| Per-class attack/heal speed | e.g. Knight 1.1s, Cleric 1.75s heal | Hardcoded cd per class | Parameterize action cadence per class | P2 | S | [wiki Knight/Cleric] |
| Flexible party size 1-4 | Up to 4 selectable | Fixed 4 rhombus | Allow variable party size from save | P2 | S | [wiki Gameplay] |
| Passives (variant ±1) affecting formulas | `passives[]` shifts damage/crit | Missing | Add passive array influencing rolls (e.g. ranger aimed ×1.4) | P1 | M | [doc2 §2.1; IL] |

---

## 5. Recommended implementation order

Sequence so each step lands a playable increment and dependencies resolve:

1. **Damage core rewrite (P0).** Split into `roll(src,target,ability)` + `resolve(victim,amt)`; remove enemy armor; flat-double crit; additive stacking; party min-3 floor. *(Everything downstream reads damage, so fix the math first.)*
2. **Centralized status/buff-debuff tables (P0).** Introduce `buffs[]`/`debuffs[]` + `buffMagnitudes[]`/`debuffMagnitudes[]` on entities; migrate existing Sunder/Grant/Defend onto it; add vuln + ward + reflect. *(Makes abilities & damage composable.)*
3. **6-slot ring formation (P0).** Replace the 1D column with the ring request/backfill; verify surround works for both flanks; clamp to arena. *(Signature BH spatial feel.)*
4. **Data-driven ability system (P0).** Build the ability/passive table + loader (even starting with the 5 existing CR classes); per-ability cooldowns; AoE resolver. *(Unblocks adding every future class/ability as data.)*
5. **Enemy archetypes + targeting policies (P0/P1).** Ranged/caster/healer/basic + highest-armor-fixate & random-target & taunt rules; drive spawning from wave data. *(Encounters stop being "wall of identical skeletons.")*
6. **Crowd control & ranged fidelity (P1).** Fear/flee, immobilize, knockdown, projectiles + aimed-shot falloff, DoTs/HoTs generalized.
7. **Enemy advanced behaviors (P1/P2).** Charge, enrage, boss phase state machine, summons.
8. **Rewards (P1/P2).** Gold + XP split + XP bars; then loot-table drops.
9. **Full class roster & role tuning (P0-deferred/P1).** Add remaining archetypes now that abilities are data-driven; tune speeds/roles.
10. **Feel polish (P2).** Drag-leash visuals, `preferBack`, facing snap, difficulty tier scaling, flexible party size.

Rationale: 1→2 make the *numbers* correct and composable; 3 makes the *space* feel like Battleheart; 4 makes *content* cheap to add; 5 makes *enemies* varied; 6-7 deepen AI; 8 closes the reward loop; 9/10 scale content & feel.

---

## 6. Open questions for the Director

1. **`meleePositions` exact values** (the 6 ring offsets) are serialized per-prefab in the APK, not in the assembly — I could not parse the binary Unity `Data/` assets into readable numbers without running AssetStudio. **Decision needed:** (a) author our own 6-slot offsets tuned to CR's 800×450 stage and sprite sizes, or (b) have someone extract them from the prefabs. I defaulted the spec to "author our own" since BH was 3D world-space, not virtual pixels.
2. **How faithful must the damage numbers be?** BH uses persisted `power`/`defense` integers (save-data driven) with no visible in-level growth curve in the assembly (level-up math lives in a screen we didn't trace). CR currently scales stats from save. **Decision:** do we adopt BH's two-stage *structure* exactly (recommended) but keep CR's own stat magnitudes, or attempt to recover BH's actual curves?
3. **Buff/debuff index→name mapping** is not in the IL (it's in the serialized DB asset). The spec documents *mechanical* behavior per known index, not canonical names. **Decision:** fine to treat these as mechanical slots and assign our own names, or required to recover the original names?
4. **Resource/mana model.** CR added a **shared Clash-Royale-style resource bar** (10 segs, regen 1/sec, costs 20) gating actives — this does **not** appear in Battleheart (BH gates on cooldowns only; enemies have a `mana` field but party actives are cooldown-driven). **Decision:** keep CR's resource bar as a deliberate deviation, or drop it for pure cooldowns to match BH?
5. **Stagger system.** CR has a prominent stagger/knockdown meter (points → staggered → reverse-death-anim). BH's closest analogs are per-ability knockdowns (Apollo Strike, Shield Rush) and CC, not a universal stagger gauge. **Decision:** keep stagger as a CR feature (P1 flavor) or fold knockdowns into ability-specific effects only?
6. **Party size & roster.** CR currently ships Knight/Champion/Duelist/Brigand/Nomad (4-party rhombus). BH ships 10 roles. **Decision:** how many archetypes for the parity milestone (recommend: get the 4 roles — tank/melee-DPS/ranged/support — functional first, expand later)?
7. **Scope of boss content.** Full boss phase scripts (Ooze split, Golem boulders, Lich 5-phase) are large. **Decision:** are bosses in-scope for encounter-parity, or deferred to a later content pass?
8. **`levelUpEnemies` trigger** (what causes the ×1.1 tier bump — NG+, per-wipe, arena kill-count) was not traced. Low risk; **decision** can wait until a difficulty-scaling feature is actually requested.

---
*All IL line references point to `il/Assembly-UnityScript.il`; doc sections to `docs/01-positioning-system.md` (doc1) and `docs/02-damage-system.md` (doc2); CR file refs are relative to `main-game/`. Web claims are labeled as public-source and are lower-confidence than the datamine; where they disagree, the datamine governs.*

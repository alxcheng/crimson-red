# Battleheart Class Port Spec — Cleric / Paladin / Wizard / Rogue

**Prepared by:** class-research · **For:** encounter-foundation (data-driven classes)
**Scope:** express BH's *own* four non-Knight party classes as DATA in our new systems
(stats table, indexed buff/debuffs, 6-slot ring, data-driven abilities). These are port
targets for feel-testing — not CR custom designs.

## 0. Method & confidence key

Sourcing convention used throughout:

- `[IL Lxxxx]` — line range in `il/Assembly-UnityScript.il` (datamine, authoritative).
- `[doc2 §n]` / `[doc1 §n]` — sections of the porting docs `docs/02-damage-system.md` / `01-positioning-system.md`.
- `[wiki <url>]` — public wiki (Fandom / StrategyWiki). Lower confidence; the datamine wins on conflict.
- `[wiki-only]` — value exists only in a wiki, not found in IL/docs.
- `[inferred]` — my interpretation bridging sources.
- `[tuned]` — no BH source found anywhere; a baseline I chose so the four roles differ meaningfully. Flag for Director.

**What the datamine confirmed vs. wiki fallback:**

| Class | Datamine-confirmed mechanics | Wiki-only fallback |
|---|---|---|
| Cleric | Full auto-heal recipe + passive branches [IL $castHeal$1802]; Group Heal + Vengeful Angel + Shield special bodies inside `performSpecial`; aura/pulse engine `clericAuraAttack` | Special names ("Group Heal"/"Shield"), cooldowns (20/30/30/60 s), heal-cast 1.75 s cadence, per-skill % magnitudes |
| Paladin | Generic damage/heal math, tank redirect slot `buffs[0x1e]`, reflect `buffs[0x1c]`, lifesteal variant [doc2 §3.2, IL takeDamage 18394–19181] | Entire special list (Holy Word/Wrath/Aura of Light/Radiance…), all numbers `[wiki-only]` |
| Wizard | Auto-fire `shootArrow`/`castFireball` recipes incl. cast anim, pitch randomize, projectile origin [IL $shootArrow$1822, $castFireball$1817]; Meteor special branch [IL performSpecial $1850]; aimed-shot falloff ×1.4 passive rule [doc2 §2.1] | Special names/cooldowns (Meteor 30 s etc.), fireball multiplier, slow/stun durations |
| Rogue | Generic roll + crit (`calculateCrit`) [IL 87113]; debuff-index writes pattern (`debuffs[3]=3.0/[4]=0.15` seen on pounce) [IL $pounceAttack$1845] | Entire special list (Sneak Attack 250%, Expose Weakness +50%, Poisoned Knife, Paralytic/Shadowstep), all numbers `[wiki-only]` |

No base HP/power/defense/moveSpeed values exist in the IL — they are persisted
save-data integers read from `PlayerPrefs` at battle setup ([IL L1916–1960],
[doc2 §6]); only a few starting values are printed in the Fandom *Characters* page
([wiki https://battlehead.fandom.com/wiki/Characters]). All stat tables below are therefore
`[wiki]` where a number was printed, else `[tuned]`.

Stat-name mapping (BH → ours): BH `power` ≈ our ATK/offense roll base; BH flat `defense` =
party armor subtraction (enemies have none, [doc2 §2.2/§3.2]); BH `critChance` (%) maps to a
flat-double crit hook; BH `passiveRegen` is passive HP/s; BH `wardChance` (%) = Ward; BH
`lifeDraining` (× fraction of dmg dealt) = lifesteal. `moveSpeed`/`meleeOffset`/`positionThreshold`
are per-prefab floats not present in the assembly [doc1 Open Q] → `[tuned]`.

Targeting modes available in our system: self / single-ally / single-enemy / AoE-radius /
projectile-to-point / cone. Resource costs are suggestions — BH gates specials purely on
cooldowns (`cooldowns[]`/`remainingCooldowns[]`, [IL PartyMember fields L76916+]) — we keep
per-ability cooldowns and mark resources as optional.

---

## 1. Cleric (Lucille)

### 1.1 Overview
- **Role:** Support — **no auto-attack**; its default action when a target is selected is to
  continuously heal ([wiki Class_Types]; dispatch `characterClass==1 → castHeal(myTarget)`
  gated by `primaryActionCooldown` [IL AI() L80024–80038]).
- **Playstyle:** pick your most wounded ally, let her heal them relentlessly; drop big
  cooldown heals/buffs; optional self-AoE damage phase (Vengeful Angel).
- **In-story:** Lucille, rod-wielding healer, starting character with Shepherd.
- **Cadence:** heal-cast interval **1.75 s** `[wiki Fandom Cleric]` → set
  `primaryActionCooldown = 1.75` and map the "basic" ability to the heal coroutine.
- Buff tick: HoTs run through `handleBuffs` per frame [IL 86040+].

### 1.2 Base stats (as data)
BH starting values are Lv-1 save integers; use as bases, scale per our level curve.

| Our field | BH source | Value | Note |
|---|---|---|---|
| maxHP | `maxHealth` | **[tuned]** 300 | Fandom prints Lucille P16/A9 only; HP not printed |
| HP | — | = maxHP at spawn | |
| RES | n/a in BH | 0 | mitigation is victim-side buff fractions, not a flat RES |
| BOOST | n/a | 0 | |
| DEF | BH `defense` (flat armor) | 9 `[wiki Fandom Characters]` | subtracted in `PartyMember.takeDamage` [doc2 §3.2] |
| ATK | BH `power` | 16 `[wiki Fandom Characters]` | drives heals AND aura dmg (heals scale off power [IL castHeal]) |
| CRIT | BH `critChance` (%) | 0 `[tuned]` | clerics don't crit heals in IL |
| CRIT_DEF | n/a | 0 | |
| MOVE_SPEED | BH `moveSpeed` (per-prefab) | 3.0 `[tuned]` | slower than DPS `[inferred]` |
| ATK_SPEED / swing | `primaryActionCooldown` | 1.75 s heal cast `[wiki]` | support "attack" is the heal |
| STAGGER_RES / MAX_STAGGER / STAGGER_DUR | n/a | default | CR-only mechanic |

Note: heal amounts in BH are computed from **power**, not HP ([IL $castHeal$1802] multiplies
`self.power` by 1.0/1.15/0.3 etc.) — keep that quirk: our heal formulas should read
ATK, not maxHP.

### 1.3 Active abilities
Ability ids = `abilities[specialSlot]` ints read in `performSpecial` (Cleric block
`characterClass==1`, ability checks ==1/2/3 [IL L93591+, L93813+, region ~L93992+]).

| Name (wiki) | Target | CD (s) | Resource (suggest) | Range | Effect (numeric) | Anim | Notes |
|---|---|---|---|---|---|---|---|
| **Auto-Heal** (default action) | single-ally (selected) | 1.75 (gate) | — | melee-range-ish | heal `int(power·mult)`; mult 1.15 if passives[0]==−1 else 1.0 [IL L88497–88527] | `cast` (body+weapon) [IL L88442–88460] | resets `actionTimer=0` after cast; if target dies mid-cast → abort+idle [IL L88804+] |
| **Group Heal** | all party | 20 `[wiki]` | 20 | whole arena | each living ally healed `int(power·buffMagnitudes[3])`; passives[3]==−1 ⇒ ×1.25 first [IL L93678–93729] | `specialCast` + weapon `cast` | white flash on all healed [IL L93776–93790]; tutorial sets state 41 [IL L93802–93811] |
| **Shield** | single-ally | 30 `[wiki]` | 20 | melee | target takes −75% dmg 10 s `[wiki]` → encode buffs[idx_shield]=dur(10 s) via `buffDurations[...]` write pattern seen for ab 2 [IL L93992+] | `specialCast` | magnitude 0.75 `[wiki-only]`; needs a DAMAGE_REDUCE status slot (see §2) |
| **Power Infusion** | single-ally | 30 `[wiki]` | 20 | melee | target ATK ×2 for 10 s `[wiki]` → ATK_BUFF index, mag 1.0 (=×2), dur 10 | `specialCast` | `[wiki-only]` magnitude |
| **Guardian Angel** | self | 60 `[wiki]` | 30 | — | own healing output ×2 for 15 s `[wiki]`; IL branch sets `disableSpecials=true` during cast [IL L93994+] | `shieldWall`-style | pairs w/ Favored Soul (immunity while active) `[wiki]` |
| **Vengeful Angel** | self→AoE around caster | 60 `[wiki]` | 30 | radius ~2.0+aoeRadiusBonus | pulse every 1 s: hit all enemies in box x≤2.0 z≤1.5 for `int(power·buffMagnitudes[7])` + knockback `impactForce·2` [IL clericAuraAttack 84372–84586] | aura glow (sound idx 4) | runs **every remoteUpdate frame** while `buffs[7]>0` — encode as per-frame aura effect; sound fades over 0.7×volume [IL 84887–84975] |
| (alt) **Binding Heal / Passion / Holy Embrace** — see passives | | | | | | | |

### 1.4 Passives (from `passives[]` int variants ±1)
| Passive (wiki name) | Formula shift (verified in IL where possible) | Encoding in our model |
|---|---|---|
| passives[0]==−1: bigger direct heal | auto-heal ×1.15 instead of ×1.0 [IL L88497] | per-class const in ability data (`healMultByPassive`) |
| passives[0]==+1: **Group Heal splash** ("Passion") | each auto-heal also heals allies within 2.5 u of target for `int(power·0.3)` [IL L88712–88800] | ability flag `splashPct=0.3, splashRange=2.5` |
| passives[1]==−1: attach HoT ("Holy Embrace") | sets target `buffs[0x0c]=buffDurations[0x0c]` and seeds `directHealHotMagnitude = power·mags[0x0c]·(1+mags[4]|1+mags[6])` [IL L88529–88625] | HOT status index; magnitude seeded at cast time (multiplicative, like DoT seed [doc2 §4]) |
| passives[1]==+1: alt HoT flavor | sets `buffs[0x0d]=buffDurations[0x0d]` (different HoT channel) [IL L88627–88646] | second HOT index |
| passives[3]==−1: stronger Group Heal | group heal ×1.25 then ×mag[3] [IL L93684–93706] | passive multiplier hook on the ability |
| "Discipline/Empowering Words/Binding Heal/Favored Soul/Desperate Prayer" `[wiki]` | +15% heal, +15% target power after auto-heal, self-heal 50% of heals given, immunity during Angels, group heal +25% | hotfixes: boost-heal-mult, post-heal ATK_BUFF, self-heal-on-heal proc, invincible-while-buffed flag, group-heal mult |

### 1.5 Sprite & recolor plan
Reuse **Knight** frame set, tinted **yellow**:
- Reuse states: `Idle`, `Run`, `Attack1`, `Attack2`, `Take Hit`, `Death` (map `Attack1/2`→the
  `cast` anim used for heals [IL plays `"cast"`]; keep `Attack3` unused or remap to the
  `specialCast` pose).
- Add/remap later (ideal, not for proof-of-port): dedicated **cast pose** (currently Knight
  sword frames) and an **aura ring** VFX for Vengeful Angel (BH uses a looping sound + color
  flash instead [IL 84887+]).

---

## 2. Paladin (Heleth)

### 2.1 Overview
- **Role:** Tank / hybrid healer — high armor, draws aggro (tank rule: hitting an enemy
  fixates it, except archers/bats `[wiki Class_Types]`), plus group shield/redirect kit.
- **Playstyle:** stand in front, eat hits, convert damage into shields/heals, punish with
  chain-lightning imbues and full-field knockdown bursts.
- **In-story:** Heleth, holy warrior; short temper, sharp blade-and-tongue.
- **Cadence:** melee swings on shared melee cadence `[tuned]` ~1.0–1.1 s (same structure as
  Knight `meleeAttack`); healing spells on their own cooldowns. No separate heal interval.

### 2.2 Base stats (as data)
| Our field | Value | Note |
|---|---|---|
| maxHP | **[tuned]** 520 | highest of the four `[inferred]` tank role |
| DEF | 24 `[wiki Fandom Characters (Lv5)]` | flat armor subtract [doc2 §3.2] |
| ATK | 24 `[wiki (Lv5)]` | lower than DPS classes |
| CRIT | 0 `[tuned]` | |
| MOVE_SPEED | 2.8 `[tuned]` | |
| ATK_SPEED / swing | 1.1 s `[tuned]` | |
| others | defaults | |

### 2.3 Active abilities
No Paladin-specific coroutine exists in the IL (only `castHeal/castBardBuff/castFireball/…`
coroutines were found; paladin effects ride the generic buff/debuff indexes). All rows below
are `[wiki StrategyWiki Paladin]`; mechanism columns use verified IL hooks.

| Name | Target | CD (s) | Resource | Range | Effect | Anim | Notes |
|---|---|---|---|---|---|---|---|
| **Holy Word** | lowest-HP ally | 30 | 20 | whole arena | heal most-injured ally (magnitude `[wiki-only]`, suggest `power·1.5`) | `specialCast` | "seeks out and heals" = target-lowest-health helper exists in IL vocabulary (`lowestHealthAlly` field) |
| **Wrath** | self (imbue) | 30 | 20 | melee | 10 s: melee hits deal extra lightning chaining to nearby foes | `specialCast` | encode as ATK_BUFF window + on-hit chain projectile (NEW: CHAIN_LIGHTNING sub-effect) |
| **Aura of Light** | self | 40 | 25 | self | 10 s: incoming damage converted to healing | `specialCast` | reuse existing `buffs[0x1c]` reflect/heal-on-hit path (heal 50–60% of would-be dmg, [doc2 §3.2 IL 81498+]); ×1.0 conversion = full convert `[wiki-only]` |
| **Divine Intervention** | party | 30 | 30 | whole arena | 10 s: all incoming damage redirected to paladin | `specialCast` | **exact IL hook exists**: guardian redirect `if buffs[0x1e]>0 && myProtector!=null → protector.takeDamage(...)` [doc2 §3.2]; set party members' redirect target to this unit |
| **Radiance** | AoE all enemies | 30 | 25 | whole arena | knock all enemies down + heal party | `specialCast` + screen flash | knockdown = CR stagger/knockdown effect; party heal magnitude `[wiki-only]` |
| **Melee attack (auto)** | single-enemy | 1.1 (swing) | — | melee | `int(power)` roll, flat-double crit via calculateCrit, standard resolve | `Attack1/2` | tank aggro: hit fixes tauntable enemies `[wiki]` |

### 2.4 Passives
| Name `[wiki]` | Effect | Encoding |
|---|---|---|
| Stalwart | +15% armor | DEF `add += 0.15·baseDEF` (or mult 1.15) at level-up hook |
| Swift Justice | +10% move & attack speed | `moveSpeed·1.10`, swing interval `/1.10` |
| Bastion | +20% max health | maxHP mult hook |
| Power of The Word | +20% heal power | global heal multiplier on this unit (all heal formulas read it) |
| Sentinel | grants 25% of own armor to all allies | per-frame aura adding flat DEF to party (new: AURA_ARMOR) |
| Word of Asylum / Retribution `[wiki]` | lingering 5 s negate-shield after Holy Word / +50% target power 10 s after Holy Word | post-heal WARD window / ATK_BUFF hook |

### 2.5 Sprite & recolor plan
Reuse **Knight** frames, tinted **green**. Reuse Idle/Run/Attack1/Attack2/Take Hit/Death
paladin IS a swordsman — knight frames fit natively; no new poses needed for proof-of-port.
Ideal later: `shieldWall`-style raise for Divine Intervention, golden flash VFX for Radiance.

---

## 3. Wizard (Bromswell / Thistle)

### 3.1 Overview
- **Role:** Ranged DPS — **auto-fires projectiles from afar** with distance reward; heavy CC.
- **Playstyle:** kite; alternate Meteor/Blizzard/Time Stop for constant slow/freeze uptime.
- **In-story:** Bromswell, retired wizened master of arcane arts (staff, robes).
- **Cadence:** ranged auto-fire loop on `primaryActionCooldown` `[tuned]` 1.6 s; casts lock
  the unit via `cast` anim.

### 3.2 Base stats (as data)
| Our field | Value | Note |
|---|---|---|
| maxHP | **[tuned]** 260 | squishiest role `[inferred]` |
| DEF | 5 `[wiki Fandom Characters]` | near-zero armor — wizard survivability comes from Mage Armor/Teleport |
| ATK | 28 `[wiki Fandom Characters (partial: "P…8")]` → treat as ~28 `[inferred]` | verify against save data |
| CRIT | 0 `[tuned]` | |
| MOVE_SPEED | 3.2 `[tuned]` (10 u teleport once Teleport passive) | |
| ATK_SPEED / swing | 1.6 s cast interval `[tuned]` | |

### 3.3 Active abilities
Auto-fire + Meteor are **IL-verified**; the rest `[wiki StrategyWiki Wizard]`.

| Name | Target | CD (s) | Resource | Range | Effect | Anim | Source |
|---|---|---|---|---|---|---|---|
| **Auto Fireball** (basic) | projectile-to-point | gate 1.6 `[tuned]` | — | long (aimed) | spawns `EffectScript` projectile from `pos + facing·0.4scale`; damage `int(power·projectileDamageMod)` via two-stage roll; aimed-shot dist factor `Clamp(dist·0.6, 1.5, mod)` applies to ranged shots; **passives[1]==+1 ⇒ ×1.4** [doc2 §2.1] | `attack` (arrow) then `returnToNormalFromShot` | IL `$shootArrow$1822` L89482–89637; `$castFireball$1817` L89307–89480 (plays `cast`, pitch rand 0.9–1.1, wait 0.15 s) |
| **Meteor** | projectile-to-point (falls on point) | 30 `[wiki]` | 30 | whole-screen | impact zone dmg large radius; sets `meteorImpactPosition`, disables specials during flight, dim background [IL performSpecial class-4 branch L93994+, `$meteorImpactPosition$1853`] | `specialCast` + meteor drop | IL verified (class 4, ability 1); magnitude `[wiki-only]` suggest `power·2.0` AoE r≈2.0 |
| **Blizzard** | AoE all enemies | 30 `[wiki]` | 25 | whole arena | damage + slow all enemies 10 s `[wiki]` | `specialCast` | slow = NEW SLOW debuff (reduce moveSpeed fraction 10 s) |
| **Time Stop** | AoE all enemies | 45 `[wiki]` | 30 | whole arena | stun (frozen) 5 s `[wiki]` | `specialCast` | STUN status, dur 5 |
| **Conflagrate** | single-enemy | 40 `[wiki]` | 20 | long | DOT burn + disable 6 s `[wiki]` | `specialCast` | DOT (conflagDotMagnitude exists in IL [doc2 §4]) + short STUN |
| **Thunderbolt** | AoE around caster | 30 `[wiki]` | 25 | medium | self-centered blast, dmg + knock away foes `[wiki]` | `specialCast` | AoE-radius centered on self + knockback force |

### 3.4 Passives
| Name `[wiki]` | Effect | Encoding |
|---|---|---|
| Enveloping Flames | basic fireball splashes 75% dmg to nearby targets | ability flag `splashPct=0.75` on auto-fire |
| Impact | basic fireball +20% dmg | `projectileDamageMod` +20% hook |
| Fire Shield | 20% chance to fire counter-fireball on being hit | proc-on-hit: WARD-like negation + return projectile (reuse reflect path [doc2 §3.2]) |
| Mage Armor | 20% chance an attack does no damage | **Ward** (`wardChance=20`) — exact IL slot [doc2 §3.2] |
| Teleport | movement becomes teleport (10 u jumps) | move-mode flag: on command, jump up to 10 u (BH units are 3D; our analog = fixed-step blink) |
| Flaming Meteor / Concussive Shockwave `[wiki]` | meteor ignites +50% dmg over 8 s / knocks down 3 s | DoT seed on meteor (like rangerDot [doc2 §4]) / KNOCKDOWN 3 s on meteor |

### 3.5 Sprite & recolor plan
Reuse **Knight** frames, tinted **pink**. Map `Attack1/2`→bow/arm frames used for arrow
auto-fire (BH plays `attack` even for shootArrow [IL 89573–89579]) and `cast`→`Attack3`.
Add later (ideal): staff cast pose + floating/idle hover for the teleport passive; for
proof-of-port plain recolor is fine — note pink-over-knight-armour looks odd, acceptable as
placeholder.

---

## 4. Rogue (Gustav / Robin)

### 4.1 Overview
- **Role:** Melee DPS (burst) — fast dagger swings, CC + vuln procs, mobility.
- **Playstyle:** burst windows: Expose Weakness → Sneak Attack/Shadowstep; poison + paralyze
  for control. Rogues favor burst/mobility/survival over barbarian sustain `[wiki Class_Types]`.
- **In-story:** Gustav, mercenary with a criminal record seeking pardon (iron dagger).
- **Cadence:** fastest melee swing of the four `[tuned]` 0.85 s (Flurry +15% faster at L10
  supports a quick base).

### 4.2 Base stats (as data)
| Our field | Value | Note |
|---|---|---|
| maxHP | **[tuned]** 300 | |
| DEF | 9–13 `[wiki: StrategyWiki Gustav init def 9; Fandom Lv5 armor 13]` | leather |
| ATK | 31 (Lv1) / 46 (StrategyWiki initial) `[wiki]` | highest raw offense of the four |
| CRIT | 0 base; Critical Strikes gives 20% `[wiki]` | maps to `critChance=20` |
| MOVE_SPEED | 3.4 `[tuned]` (+15% w/ Pursuit) | |
| ATK_SPEED / swing | 0.85 s `[tuned]` | |

### 4.3 Active abilities
All `[wiki StrategyWiki Rogue]` except the debuff-write *pattern*, which is IL-verified.

| Name | Target | CD (s) | Resource | Range | Effect | Anim | Notes |
|---|---|---|---|---|---|---|---|
| **Sneak Attack** | single-enemy | 20 | 20 | melee | 250% normal damage | `Attack1/2` | roll `int(power·2.5)` then two-stage resolve; crits still apply (flat double) |
| **Expose Weakness** | single-enemy | 30 | 15 | melee | target takes +50% damage, 10 s | `Attack1` | **VULNERABILITY** index; magnitude write follows the verified pattern `debuffs[idx]=duration, debuffIdx_magnitude=0.5` — cf. pounce sets `debuffs[3]=3.0, debuffs[4]=0.15` [IL $pounceAttack$1845 L93052–93066] (index semantics DB-side) |
| **Poisoned Knife** | projectile single-enemy | 30 | 15 | long-lite | throw knife: small immediate hit + DOT | `throw`-style (Anim state `"throw"` exists in IL [IL L93892]) | DOT seed like poisonMagnitude [doc2 §4]; duration `[wiki-only]` ~6 s |
| **Paralytic Knife** | projectile single-enemy | 45 | 25 | long-lite | PARALYZE (helpless) 8 s `[wiki]` | `throw` | hard immobilize: lock move+actions, no stagger interaction |
| **Shadowstep** | single-enemy (behind) | 30 | 20 | leap | warp behind target + strike 350% dmg `[wiki]` | dash+`Attack1` | movement sub-effect (teleport-behind) then hit; "warp" mirrors pounce-style reposition [IL $pounceAttack$1845] minus the AoE |
| **Counter / retaliation flavor** `[inferred]` | — | — | — | — | (optional) on-hit riposte | `Attack2` | skip unless Director wants it |

### 4.4 Passives
| Name `[wiki]` | Effect | Encoding |
|---|---|---|
| Flurry | +15% attack speed | swing interval ÷1.15 |
| Critical Strikes | 20% melee crit (double) | `critChance=20` (calculateCrit roll [IL 87113]) |
| Combat Tactics / Pursuit | +15% armor / +15% move speed | DEF add / MOVE_SPEED mult |
| Envenomed Blades | random paralyze chance on hit | proc-on-hit → PARALYZE (chance `[wiki-only]` ~10%) |
| Lethality / Aggression `[wiki]` | +40% dmg on SA/Shadowstep / +10% power | ability mult hook / ATK mult |

### 4.5 Sprite & recolor plan
Reuse **Knight** frames, tinted **red** (a red-recolor copy distinct from Crimson Red UI red —
use a darker crimson, e.g. `#a01824`). Reuse Idle/Run/Attack1/Attack2/Take Hit/Death.
Add later: backstab pose (flip facing before Shadowstep hit) and knife-throw armature; for
proof-of-port reuse dagger-anim-less knight slash frames.

---

## 5. Cross-class consistency check

**Sanity deltas (bases):**
- DEF ladder: Paladin 24 > Rogue 9–13 > Cleric 9 > Wizard 5 — tanks clearly sturdiest; good.
- ATK ladder: Rogue 31/46 > Pal 24 ≥ Wizard 28 > Cleric 16 — DPS leads; cleric lowest is right
  (its output is healing measured off the same power).
- maxHP (tuned): Pal 520 > Rogue/Cleric 300 > Wiz 260 — reasonable.
- Support check: Cleric has **no auto-attack** — correct per both IL (class-1 branch goes
  straight to `castHeal`) and wiki. Paladin is NOT pure support (it melee-attacks + heals).
- Does the tank out-heal DPS? No — Paladin heal numbers are modest (Holy Word `[wiki-only]`);
  healing dominance stays with Cleric. Good separation.

**Wiki ↔ datamine conflicts / ambiguities:**
1. **Cleric heal-cadence:** wiki says 1.75 s heal cast; IL confirms the cast animation timing
   (0.3 s wait [IL L88468]) but the loop gate is `primaryActionCooldown` (a per-prefab float
   not in the assembly) — 1.75 s is the only concrete number, accepted.
2. **Rogue base power:** Fandom (Lv1) = 31 vs StrategyWiki "Initial Power 46". Both are
   "[wiki]" tier; 46 likely includes starting weapon (Iron Dagger +19 tier-1 power per Fandom
   Weapons table `[wiki]`). Recommend using **bare 31 + gear** to stay consistent with other
   classes whose printed values appear bare.
3. **Cleric passion splash %:** Fandom says 25%, StrategyWiki 30%; IL shows the actual code
   uses a **fixed 0.3** multiplier (`ldc.r4 0.3` [IL L88778]) → **30% wins** (datamine beats wiki).
4. **Wizard "Impact +20%"** sits oddly next to the aimed-shot ×1.4 passive rule (both modify
   projectile multipliers additively per [doc2 §2.1]); treat both as additive modifiers of
   `projectileDamageMod`.
5. **Paladin "Aura of Light converts ALL damage to healing"** exceeds the IL reflect slot
   (which heals only 50–60%). Either accept under-conversion (safer) or add a dedicated
   full-convert flag (faithful but bespoke).

**Top 3 values to confirm with the Director before locking:**
1. **Base stat magnitudes** (whole table) — none are in the datamine; approve the tuned set or
   provide BH save exports.
2. **Paladin Aura of Light fidelity** — full conversion (bespoke hook) vs. reuse 50–60% reflect
   slot.
3. **Caster cast-interval (wizard 1.6 s) and rogue swing (0.85 s)** — tuned cadences that
   define the feel; playtest-tune after first build.

---

## 6. Open questions

| # | Question | Status | Recommended default |
|---|---|---|---|
| 1 | Exact `cooldowns[]` seconds for each class special — stored in serialized DB asset (`powerDB`), not in IL (`Power.cooldown` field exists [IL 665–687] but values are binary) | unresolvable here | Use wiki cooldowns (they're clean 20/30/40/45/60 s steps); replace on AssetStudio parse |
| 2 | Buff/debuff index→name map (which index = ward/shield/vuln/paralyze/slow) | in DB asset [doc2 §5] | Assign our own canonical slots (WARD, REFLECT, ATK_BUFF, DEF_BUFF, HOT, DOT, STUN, FEAR, PARALYZE, VULNERABILITY) and hard-code the mechanical behavior per known index from doc2 §3.2 |
| 3 | Per-prefab `moveSpeed`, `meleeOffset`, `positionThreshold`, `primaryActionCooldown` floats | per-prefab Unity assets, not in assembly [doc1 Open Q] | Tuned values above |
| 4 | Which `characterClass` int is Paladin / Barbarian etc. (IL proves 1=Cleric, 3=?, 4=Meteor-class, 5=?; assassin-type = 7 per [IL L18754]) | partial | Keep enum open; label 1=Cleric confirmed, others tentative |
| 5 | Paladin/Rogue entire special trees live in the DB (no coroutines in IL) | unresolvable without AssetStudio | Port from wiki text with IL-verified mechanic hooks; flag every row `[wiki-only]` |
| 6 | New statuses needed beyond current list: **SLOW** (Blizzard), **DAMAGE_REDUCE/SHIELD** (Cleric Shield/Paladin wards), **PARALYZE** (distinct from STUN: no duration pop, just frozen) | design decision | Add SLOW + DAMAGE_REDUCE + PARALYZE to the indexed table alongside ATK_BUFF/DEF_BUFF/WARD/REFLECT/HOT/STUN/FEAR/VULNERABILITY/DOT |
| 7 | Chain-lightning (Paladin Wrath) sub-effect | no BH-side analog traced | Optional NEW: CHAIN (hit N nearest, dmg decay) |

*(End of spec — ~330 lines)*

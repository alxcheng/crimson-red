# PartyMember — hero battle stats, AI, damage taken, healing, buffs, death

**Scope:** class `PartyMember` (a player-controlled hero in battle), IL lines **76916–88335** of
`Assembly-UnityScript.il`: class header + all 107 fields, `.ctor`, `initialize`, `remoteUpdate`, `AI`,
`findMovementTarget`, `handleCooldowns` (+ coroutine `handleCooldowns2`), `takeDamage`, `die` (coroutine),
`heal`, `healthAnimation`, `updateHealthBar`, `blink`, `select`/`deselect`, `shaderAnimation`,
`activateColors`, `pulse`, `flash`, `clericAuraAttack`, `flameArrowPulse`, `requestPosition`,
`purgePosition`, `animateSliding`, `handleBuffs`, `returnToNormal*`, `calculateDamageMultiplier`,
`createMyEffects`, `drainLife`, `adrenalineRush`, `returnDamageValue`, `muteSoundEffects`,
`congratsScreenInitialize`, `calculateCrit`.
Not covered here (other docs): the attack/cast coroutines `castHeal`, `castBardBuff`, `castFireball`,
`shootArrow`, `counterAttack`, `meleeAttack`, `pounceAttack`, `performSpecial` (IL 88337–105808). Only their
one-line stubs are in this range.

Because the hero's base stats are **not** computed inside `PartyMember` (they are written into the hero by
`MotherBrain.Awake` before `initialize` runs), section 4 documents that external block
(IL 59634–61475) so the full stat formula is in one place.

Citations are `[IL Lnnnnn]` = line number in the .il file.

---

## 1. Summary

- A `PartyMember` is one hero on the battlefield. `MotherBrain` (the battle manager) spawns up to 4 from
  prefabs `Allies/<playerName>`, copies stats from the saved `Player` record, class table and equipped
  items into the hero's fields, then calls `initialize()`, which applies the hero's chosen passives.
- `MotherBrain` calls `remoteUpdate()` once per frame. It ticks buff timers, runs the `AI` state machine
  (idle / walk to point / engage target / pounce / busy with a special), cooldowns, health-bar and tint
  animations and knock-back sliding.
- Heroes have three behaviour archetypes (`AIType`): **1 = support** (Cleric heals, Bard buffs — target is
  an ally), **2 = ranged attacker** (fireball / arrow), **3 = melee attacker** (walks to a melee slot
  beside the enemy, then swings). Idle melee/ranged heroes auto-acquire a nearby enemy every 0.5 s and
  retaliate when hit.
- Damage taken = raw hit − flat armor (defense + Paladin Sentinel aura + Bard armor song), then multiplied
  by active buff/debuff magnitudes, minimum 3, then possibly nullified (ward chance, shields, evasion,
  Aura of Light converts it to healing, Divine Intervention redirects it to the Paladin).
- Healing received is boosted by the healer's buffs and by the target's `bonusHealing` multiplier and is
  clamped to `maxHealth`.
- At 0 HP the hero plays "death", waits 2 s, flickers and is moved off-screen. If no hero is alive the
  defeat sequence starts.

**Important numbering fact:** `characterClass` is **1-based**; `bh/data/classes.json` ids are 0-based.
`classes.json id = characterClass − 1` (the code indexes `powerDB[characterClass − 1]`) [IL L59858-59866].

| `characterClass` | Class (classes.json id) |
|---|---|
| 1 | Cleric (0) |
| 2 | Knight (1) |
| 3 | Rogue (2) |
| 4 | Wizard (3) |
| 5 | Witch (4) |
| 6 | Bard (5) |
| 7 | Barbarian (6) |
| 8 | Monk (7) |
| 9 | Ranger (8) |
| 10 | Paladin (9) |

---

## 2. Fields (all 107, in declaration order) [IL L76919-77025]

Defaults are from `.ctor` [IL L77028-77118] unless stated. "prefab" = no code in the assembly assigns it;
the value is serialized on the `Allies/<name>` prefab (not in the IL).

| Field | Type | Meaning | Default / who sets it |
|---|---|---|---|
| `petScript` | PetScript | Ranger's dog (Canine Ally) | set in `initialize` [IL L78016-78035] |
| `flamePatch` | Vector3 | world position of Ranger fire patch #1 (ticked while `buffs[7]>0`) | written outside this range |
| `flamePatch2` | Vector3 | fire patch #2 (ticked while `buffs[6]>0`) | written outside this range |
| `browniePoints` | int | score counter; +5 to the healer for every `heal()` call [IL L82583-82588] | 0 |
| `flee` | bool | when true the hero runs off the left edge and is invincible [IL L78424-78546] | written by MotherBrain |
| `myTextureName` | string | texture file under `DynamicTextures/` | `"textureName"` [IL L77037] (prefab overrides) |
| `buffs` | float[] | remaining seconds of each buff, indexed by buff id (see §3) | prefab-sized; ticked in `handleBuffs` |
| `characterClass` | int | 1..10, see table above | 1 [IL L77040] (prefab overrides) |
| `passives` | int[4] | chosen passive per tier; values −1 / 0 / 1 (see §5) | copied from `Player.passives` in MotherBrain.Awake |
| `abilities` | int[3] | active power per action-bar slot (see §4.3) | copied from `Player.abilities` |
| `cooldowns` | float[3] | full cooldown (s) of each slot | MotherBrain.Awake (§4.3) |
| `remainingCooldowns` | float[3] | remaining cooldown (s) | ticked in `handleCooldowns` |
| `myEffectNames` | string[] | Resources paths of this hero's effect prefabs | prefab |
| `myEffectPrereqs` | int[] | per effect: 0 = always create, 2..5 = only if that ability is equipped (§18) | prefab |
| `myEffects` | EffectScript[] | instantiated effects, same index as names | `createMyEffects` |
| `mySounds` | AudioSource[] | sound slots (index meanings are per prefab) | prefab |
| `totalMeleeSounds` | int | | 5 [IL L77043] |
| `blinkCooldown` | float (private) | eye-blink timer | 10; `initialize` sets Random 1..5 [IL L77133-77136] |
| `commandPending` | bool | a player command is queued; suppresses auto-targeting | cleared by `returnToNormal*` |
| `colorSpeed` | float | speed of tint fade back to neutral | 2.0 |
| `actionTimer` | float | time since last basic action; action fires when ≥ `primaryActionCooldown` | 0 |
| `primaryActionCooldown` | float | seconds between basic attacks/heals | **1.3** [IL L77052] (prefab may override; modified by passives/trinkets) |
| `dragType` | int | input drag behaviour (used by MotherBrain) | 2 |
| `AIType` | int | 1 support, 2 ranged, 3 melee (§7) | 1 (prefab overrides) |
| `power` | float | attack / heal power | 15 (overwritten, §4) |
| `defense` | float | flat armor subtracted from each hit | 20 (overwritten, §4) |
| `sentinelDefense` | int | extra flat armor granted by a Paladin with Sentinel | 0; set by the Paladin's `initialize` (§5) |
| `impactForce` | float | knock-back strength of this hero's hits | 2.0 |
| `moveSpeed` | float | walk speed, world units/s | 1.5 |
| `runAnimMod` | float | run animation speed = `moveSpeed*runAnimMod` | 0.6666667 |
| `positionThreshold` | float | (not read in this range) | 0.1 |
| `meleeSlot` | int | which melee slot of the target enemy this hero holds | from `EnemyScript.requestPosition` |
| `preferBack` | int | passed to `EnemyScript.requestPosition` (1 = wants to stand behind) | prefab |
| `health` | float | current HP | 1000 → set to maxHealth (§4) |
| `maxHealth` | float | max HP | 1000 → §4 |
| `passiveRegen` | float | HP per second regenerated always (trinkets) | 0 |
| `wardChance` | int | % chance to negate a hit | 0 |
| `critChance` | int | % chance for `calculateCrit` to return 2 | 0 |
| `noCooldownChance` | int | % chance an activated power costs no cooldown (read in performSpecial) | 0 |
| `bonusXP` | float | XP multiplier. Stored as percent (default 100) then /100 in `initialize` | 100 → 1.0 |
| `lifeDraining` | float | life-steal fraction. Percent, then /100 in `initialize` | 0 |
| `bonusHealing` | float | healing-received multiplier. Percent bonus, converted to `(100+x)/100` in `initialize`; 0 means "no bonus" | 0 |
| `invincible` | bool | `takeDamage` does nothing while true | false |
| `greenHealthA/B`, `redHealthA/B` | Transform (private) | health-bar quads `life/bar_greenLeft`, `life/bar_redLeft`, `life/bar_greenRight`, `life/bar_redRight` | `initialize` [IL L77216-77242] |
| `mainHandBone` | Transform | `arm_l/weapon` | `initialize` |
| `offHandBone` | Transform | `shield` (class 2, 10) or `arm_r/weapon2` (class 7) | `initialize` |
| `myTransform`, `myAnimation` | Transform, Animation | cached components | `initialize` |
| `myWeapon`, `myOffhand` | Transform | weapon / off-hand model instances | MotherBrain.Awake [IL L61141-61330] |
| `myWeaponAnimation` | Animation | Animation on the weapon model | `initialize` |
| `myRenderer` | Renderer | child `geometry` | `initialize` |
| `myRenderer2` | Renderer | child `geometry2` (class 9 Ranger only) | `initialize` |
| `myTarget` | Transform | current target (enemy, or ally for support) | MotherBrain / AI / takeDamage |
| `myTargetEnemyScript` | EnemyScript | current enemy target's script (null for support heroes) | same |
| `motherBrain` | MotherBrain | `GameObject.Find("**MOTHERBRAIN")` component `"MotherBrain"` | `initialize` [IL L77146-77151] |
| `blinkingBone` | Transform | `head/blink`; localScale.y 1 = eyelids shown, 0 = hidden | `initialize` |
| `movementTarget` | Vector3 | where the hero is walking to | MotherBrain / `findMovementTarget` |
| `healthVisible` | bool | health bar currently shown | |
| `selected` | bool | hero is selected by the player | `select`/`deselect` |
| `healthTimer` | float | seconds the bar stays visible | set to 2.6 on damage/heal |
| `AIState` | int | 0 idle, 1 moving to point, 2 engaging target, 3 pouncing, 5 performing special (§7) | 0 |
| `tempInstance` | Transform (private) | scratch | |
| `run`, `powerUp` | AnimationState | cached states `"run"`, `"powerUp"` | `initialize` |
| `basicAction` | AnimationState (private) | `"cast"` if the clip exists, else `"attack"` | `initialize` [IL L77243-77269] |
| `specialAction` | AnimationState (private) | first existing of `"sneakAttack"`, `"shieldRush"`, `"reckless"`, `"specialShot"`, else = `basicAction` | `initialize` [IL L77270-77333] |
| `teleport` | AnimationState (private) | `"teleport"` (class 4 Wizard only) | `initialize` [IL L77334-77344] |
| `slideVector` | Vector3 | current knock-back velocity | set by `takeDamage` |
| `midAction` | bool | an attack coroutine is running | false at `initialize` |
| `internalIntCounter` | int (private) | cycles 7..9 = effect index for charge dust | 7 |
| `internalTimeCounter` | float (private) | charge dust timer | 0 |
| `whichVolley` | int (private) | (used by attack coroutines) | 18 |
| `bardCoefficient` | float | damage coefficient temp; set 0.12 around flame-patch ticks, then back to 1 | 1.0 |
| `moveVector` | Vector3 (private) | normalized movement direction | |
| `autoAttackTimer` | float (private) | idle auto-acquire timer | 0.5 |
| `prestissimo` | bool | (not read in this range; Bard passive flag) | |
| `noHitReact` | bool | suppress the `"hitReact"` flinch | |
| `myProtector` | PartyMember | hero who receives my damage while `buffs[30]>0` (Divine Intervention) | written in performSpecial |
| `redAnim/greenAnim/blueAnim/alphaAnim` | bool | per-channel tint fade in progress | |
| `tempAllyScript` | PartyMember (private) | scratch | |
| `directHealHotMagnitude` | float | HP/s of the Cleric heal-over-time on me (`buffs[12]`) | written in castHeal |
| `bardHotMagnitude` | float | HP/s of Bard Song of Vigor on me (`buffs[19]`) | written in performSpecial |
| `bardBuffPower` | int | flat power bonus from the Bard's lute buff (`buffs[14]`) | written in castBardBuff |
| `bardBuffArmor` | int | flat armor bonus from the Bard's lute buff (`buffs[14]`) | written in castBardBuff |
| `meleeOffset` | float | | 0.21 |
| `auraTimer` | float | tick timer for Cleric aura / Ranger fire patch | 0 |
| `meleePositions` | Vector3[] | offsets (relative to this hero) of the 6 melee slots enemies stand in | prefab |
| `meleeOccupants` | EnemyScript[6] | which enemy holds each of my melee slots | `requestPosition`/`purgePosition` |
| `attackers` | int | number of melee enemies currently assigned to me | |
| `frictionConstant` | float | knock-back decay rate | 10 |
| `myWeight` | float | knock-back multiplier | 1.0 |
| `colorPulseTimer` | float (private) | buff tint pulse timer | 0 |
| `buffColor` | Color (private) | tint pulsed while a buff is active; neutral = (0.25,0.25,0.25) | (0.25,0.25,0.25) [IL L77109-77113] |
| `mostRecentBuff` | int (private) | buff index whose expiry resets `buffColor` | 0 |
| `specialAwaitingTarget` | int (private) | action-bar slot of a special waiting for a target, −1 = none | −1 [IL L77115-77116] |
| `pounceDestination` | Vector3 (private) | Savage Pounce landing point | |
| `pounceTimer`, `pounceSpeed` | float (private) | pounce flight time left / speed | |
| `tempGO` | GameObject (private) | scratch | |
| `returnedDamage` | float | last value passed to `returnDamageValue` | |

---

## 3. Buff index table (`buffs[i]` = seconds remaining)

`buffs[i] > 0` means buff *i* is active. Timers are decremented in `handleBuffs` (§17). The multiplier of
buff *i* is `MotherBrain.buffMagnitudes[i]`, its standard duration `MotherBrain.buffDurations[i]`.
**Those two arrays are public fields with no initializer in the IL** (fields at [IL L59140-59141]; no
`newarr`/`stelem` writer exists) — the numbers are serialized in the Unity scene and are *not determined*.

Column "read in this range" is fully verified. Column "who sets it" comes from a mechanical scan of writer
sites outside this range (line cited); the class/ability attribution there relies on
`characterClass == N` and `abilities[slot] == k` comparisons immediately preceding the write, and the
power name on the mapping in §4.3. Treat the names as **UNVERIFIED** labels; the performSpecial doc is
authoritative.

| i | Read in this range (verified) | Who sets it (outside range) |
|---|---|---|
| 0 | incoming damage × `buffMagnitudes[0]` [IL L81802-81822]; Knight Revenge reflect requires it [IL L81560-81577] | Knight ability 1 (Shield Wall) [IL L94443]; then +5 s [IL L94462] / −5 s [IL L94484] variants |
| 1 | — | Rogue ability 1 (Sneak Attack) [IL L96094]; Barbarian ability 4 = 500 [IL L102220]; Monk ability 4 [IL L103775]; zeroed in meleeAttack [IL L90536, 91347, 91529] |
| 2 | incoming damage × `buffMagnitudes[2]` [IL L81781-81801] | Cleric ability 2 (Shield) [IL L93870, 93917] |
| 4 | outgoing damage × `buffMagnitudes[4]` (`calculateDamageMultiplier`) [IL L86542-86559]; healer's heals × `buffMagnitudes[4]` [IL L82488-82508] | Cleric ability 3 (Power Infusion) [IL L94048, 94095] |
| 5 | incoming damage × `buffMagnitudes[5]`; also disables the "minimum 3 damage" rule [IL L81739-81759, 81886-81902] | Cleric abilities 4 and 5 (Guardian/Vengeful Angel) [IL L94213, 94322] |
| 6 | healer's heals × `buffMagnitudes[6]` [IL L82509-82529]; Ranger: fire patch #2 active [IL L84752-84886] | Cleric ability 4 (Guardian Angel) [IL L94224]; Ranger: `EffectScript.damageEnemy` sets 10 [IL L4260] |
| 7 | Cleric damage aura active [IL L84386]; Ranger: fire patch #1 active [IL L84617] | Cleric ability 5 (Vengeful Angel) [IL L94333]; Ranger: `EffectScript.damageEnemy` sets 10 [IL L4195] |
| 8 | — | Rogue ability 2 [IL L96119]; zeroed in meleeAttack [IL L91860] |
| 9 | — | Rogue ability 5 [IL L96324]; zeroed in meleeAttack [IL L91711] |
| 11 | melee approach becomes a charge at speed 9 with `"charge"` anim [IL L80620-80703] | Knight ability 5 (Shield Rush) [IL L96059]; zeroed in meleeAttack [IL L91039] |
| 12 | heal-over-time: `directHealHotMagnitude` HP/s [IL L86107-86181] | castHeal [IL L88538] |
| 13 | outgoing damage × `buffMagnitudes[13]` [IL L86592-86607] | castHeal [IL L88638] |
| 14 | incoming damage − `bardBuffArmor` [IL L81666-81680]; healer's heals + `bardBuffPower` [IL L82472-82487] | castBardBuff [IL L89023] |
| 15 | incoming damage × `(1 + buffMagnitudes[15])` with passive variants (§9 step 8) [IL L81681-81738] | Barbarian ability 1 (Enrage) [IL L101083] |
| 16 | move speed × `buffMagnitudes[16]`; melee action timer × 1.15 [IL L79336-79494, 80337-80354, 80704-80836] | `adrenalineRush()` [IL L86824-86832] |
| 17 | melee action timer × `buffMagnitudes[17]`; also triggers the `buffMagnitudes[16]` move-speed branch [IL L80316-80336, 79353, 80721] | Barbarian ability 2 (Frenzy) [IL L101168] |
| 18 | cooldowns tick × `buffMagnitudes[18]` [IL L81359-81383] | castBardBuff [IL L89114] |
| 19 | heal-over-time: `bardHotMagnitude` HP/s [IL L86182-86255] | Bard ability 2 [IL L100308] |
| 20 | incoming damage × `buffMagnitudes[20]` [IL L81760-81780] | Bard ability 3 [IL L100520, 100544] |
| 21 | — | Bard ability 4 [IL L100725, 100749] |
| 22 | move speed × `buffMagnitudes[22]` and action timer × `buffMagnitudes[22]` (all AI types) [IL L79495-79637, 79879-79899, 80078-80098, 80355-80376, 80837-80953] | castBardBuff [IL L89134] |
| 23 | incoming damage = 0, alpha flicker [IL L82019-82070] | Monk ability 2 (Evasion) [IL L103296] |
| 24 | regen 5 % of maxHealth per second [IL L86256-86331]; also triggers the `buffMagnitudes[16]` move-speed branch [IL L79345, 80713] | Monk ability 5 (Spirit Trance) [IL L103843] |
| 25 | stunned: plays `"stun"`, AI and knock-back sliding skipped [IL L78547-78566, 78076-78089] | `EnemyScript.stunBolt` sets 5 [IL L23818] |
| 26 | incoming damage = 0 [IL L81936-81964] | Paladin ability 1 (Holy Word) [IL L104819] |
| 27 | — | Paladin ability 1 [IL L104876] |
| 28 | incoming damage converted to healing (50 % / 60 %) [IL L81965-82018] | Paladin ability 3 (Aura of Light) [IL L105079] |
| 29 | — | Paladin ability 2 (Wrath) [IL L104998] |
| 30 | all damage redirected to `myProtector` [IL L81518-81542] | Paladin ability 4 (Divine Intervention) [IL L105214] |
| 3, 10 | never read or written in this range | not found by the scan |

Enemy debuffs read by this class (`EnemyScript.debuffs[i]`, magnitudes `MotherBrain.debuffMagnitudes[i]`,
also scene-serialized): 7, 18, 14 multiply damage **taken from** that enemy [IL L81823-81885]; 2 and 6
multiply damage **dealt to** that enemy [IL L86560-86591]; 5 (fear, 4 s) is applied by Witch Terrifying
Presence [IL L82089-82138].

---

## 4. Base stat construction — `MotherBrain.Awake` (outside range, IL 59634–61475)

For each party slot `s` (0..3) with `DB.party[s] != −1` [IL L59640-59648]; let `P = DB.partyDB[DB.party[s]]`
(see `bh/data/party.json`), `C = DB.powerDB[P.characterClass − 1]` (see `bh/data/classes.json`),
`item(id) = DB.itemDB[id]` (see `bh/data/items.json`).

### 4.1 Spawn
- Instantiate `Resources.Load("Allies/" + P.playerName)`; `playerScripts[s]` = its `"PartyMember"`
  component [IL L59649-59682].
- Start positions (x, 0, z): slot 0 (−3.086418, 0.5977823); slot 1 (−3.859224, −0.3016483);
  slot 2 (−4.402369, 1.110445); slot 3 (−5.213078, 0.1269366) [IL L59686-59730].

### 4.2 Stats (exact order)
```
abilities[0..2] = P.abilities[0..2]                               [IL L59731-59788]
passives[0] = P.passives[0];  passives[1] = P.passives[1]          [IL L59789-59829]
maxHealth = P.maxHealth + C.healthScale * (P.level - 1)            [IL L59831-59883]
health    = maxHealth                                              [IL L59885-59893]
passives[2] = (P.level >= 25) ? 1 : 0     // NOT read from the save [IL L59894-59924]
passives[3] = P.passives[3]                                        [IL L59925-59943]
power   = P.power   + C.powerScale   * (P.level - 1)               [IL L60062-60135]
defense = P.defense + C.defenseScale * (P.level - 1)               [IL L60079-60177]
power  += item(P.gear[0]).power          // weapon, always          [IL L60180-60206]
if P.gear[1] != -1: defense += item(P.gear[1]).power   // armor    [IL L60207-60250]
for g in 2..3:  apply trinket P.gear[g] (table below)              [IL L60251-61140]
```
`healthScale` is an int, `powerScale`/`defenseScale` floats. With data: every class has healthScale 15;
powerScale 3.0 for Cleric and 1.0 for all others; defenseScale 1.2 for Knight, Monk, Paladin, 1.0 otherwise
(`bh/data/classes.json`).

Trinket loop: the code compares the **item id** in `gear[2]` and `gear[3]` against id ranges. `v` =
`item.power` of that trinket. An empty slot (−1) matches no range.

| Item id range | Items (items.json) | Effect | IL |
|---|---|---|---|
| 12–17 | Swordsman's Gauntlet 3, Power Fist 6, Titan's Glove 10, Energy Ring 3, Firestorm Band 6, Kaimani's Bloodstone 10 | `power += v` | L60257-60317 |
| 7, 32 | Tome of Mastery 3, Codex of Jabe 6 | `cooldowns[0..2] -= v` each | L60318-60448 |
| 8, 19 | Ring of Regeneration 10, Trollskin Amulet 20 | `passiveRegen += v` (HP per second) | L60449-60509 |
| 18, 27 | Sprint Shoes 10, Hermes Charm 20 | `moveSpeed *= (100 + v) / 100` | L60510-60574 |
| 20–21 | Warding Amulet 10, Phasing Lodestone 20 | `wardChance += v` | L60575-60634 |
| 22–23, 28 | Ancient Dragon Tooth 15, Truestrike Monocle 10, Rabbit's Foot 5 | `critChance += v` | L60635-60709 |
| 24–26 | Silver Armlet 3, Glyph of Stoneskin 6, Sharkul's Skull 10 | `defense += v` | L60710-60770 |
| 29–31 | Ring of Haste 5, Tempest Stone 10, Ninja Glove 15 | `primaryActionCooldown *= (100 − v) / 100` | L60771-60835 |
| 33–35 | Broken Pocketwatch 5, Monkey's Paw 10, Azamoth's Cursed Eyeball 15 | `noCooldownChance += v` | L60836-60895 |
| 36–37 | Glove of the Thief 10, Bandit's Satchel 20 | `MotherBrain.bonusGold += v` (party-wide; divided by 100 after the loop [IL L61343-61346]) | L60896-60950 |
| 38–39 | Mystic Journal 10, Mystery Egg 20 | `bonusXP += v` (on top of default 100) | L60951-61011 |
| 40–42 | Blood-soaked Sash 10, Vampire Tooth Pendant 20, Choker of the Red Feast 30 | `lifeDraining += v` | L61012-61072 |
| 46–48 | Ring of Swift Recovery 5, Medic's Charm 10, Zara's Signet 15 | `bonusHealing += v` | L61073-61131 |

Notes: the cooldown trinkets are applied to all three slots even if a slot has no ability; two of the same
kind stack additively (or multiplicatively for the two `*=` kinds).

### 4.3 Abilities and cooldowns
`abilities[slot]` holds a number, not a power index. From the cooldown lookup:
```
cooldowns[0] = C.whichPower[0].cooldown                                  [IL L59944-59972]
if abilities[1] != 0: cooldowns[1] = C.whichPower[abilities[1] - 1].cooldown   [IL L59973-60016]
if abilities[2] != 0: cooldowns[2] = C.whichPower[abilities[2] + 1].cooldown   [IL L60017-60061]
```
and from `createMyEffects` (§18) `abilities[1]` is compared with 2 and 3, `abilities[2]` with 4 and 5.
So: ability number 1 → `whichPower[0]`; 2 → `[1]`; 3 → `[2]`; 4 → `[5]`; 5 → `[6]`; 0 = slot empty.
(Slot 0 always uses `whichPower[0]` for its cooldown regardless of `abilities[0]`.)

### 4.4 Models, then initialize
- Weapon model: if `item(gear[0]).ingameModel != "none"`, instantiate it → `myWeapon`; for class 7
  (Barbarian) a second instance → `myOffhand` [IL L61141-61234].
- Shield: playerName `"Shepherd"` → `Weapons/shield1`; else class 2 → `Weapons/shield2`; else class 10 →
  `Weapons/pallyShield` → `myOffhand` [IL L61235-61330].
- After all heroes are built: `playerScripts[i].initialize()` for every non-null hero, in slot order
  [IL L61451-61475].
- Tutorial only: `playerScripts[0].takeDamage(360, zero, enemyScripts[0])`, its `healthTimer = 2.2`,
  `"showHealth"` stopped, `healthVisible = false`; `playerScripts[1].dragType = 3` [IL L61600-61644].

---

## 5. `initialize()` [IL L77121-78037]

1. `midAction = false`; `blinkCooldown = Random.Range(1.0, 5.0)`; cache transform/animation; find
   MotherBrain; `myRenderer` = child `"geometry"`; class 9: `myRenderer2` = `"geometry2"`
   [IL L77130-77176].
2. Bones: `mainHandBone = "arm_l/weapon"`; class 2 or 10: `offHandBone = "shield"`; class 7:
   `offHandBone = "arm_r/weapon2"`; `blinkingBone = "head/blink"`; four health-bar transforms
   [IL L77177-77242].
3. Animation states: `basicAction`, `specialAction`, `teleport` (class 4) as in §2. If clip `"powerUp"`
   exists: cache and set speed 10. If `"charge"` exists: speed 2.5. `"select"`: layer 1, blendMode 1
   (additive). `"hitReact"`: layer 2, blendMode 1. `"showHealth"` and `"hideHealth"`: layer 5.
   `run = "run"` [IL L77243-77418].
4. Parent `myWeapon` to `mainHandBone` and `myOffhand` to `offHandBone` at local position/rotation zero;
   `myWeaponAnimation` = weapon's Animation [IL L77419-77485].
5. `createMyEffects()` (§18) [IL L77486-77487].
6. Texture: if `Screen.width > 500` load `"DynamicTextures/" + myTextureName`, else the same + `"Lo"`;
   applied to `myRenderer` and (if present) `myRenderer2` [IL L77488-77549].
7. **Passives** (table below) [IL L77550-77962].
8. Unit conversions [IL L77963-77996]:
   - `if bonusHealing != 0: bonusHealing = (100 + bonusHealing) / 100` (so 0 stays 0 = "×1")
   - `if lifeDraining != 0: lifeDraining = lifeDraining / 100`
   - `bonusXP = bonusXP / 100` (always)
9. Play `"idle"`; `muteSoundEffects()` [IL L77996-78004].
10. Class 9 with `passives[2] != 0`: instantiate `"Allies/Dog"`, `petScript` = its `PetScript`,
    `petScript.myOwner = this`, `petScript.Initialize()` [IL L78005-78035].

### Passive encoding
`passives[t]` for tier `t`: `1` = first power of the pair, `−1` = second, `0` = none. Matching every
effect below against `classes.json` descriptions gives: tier 0 → `whichPower[3]` (1) / `[4]` (−1);
tier 1 → `[7]` (1) / `[8]` (−1); tier 2 → `[9]` (non-zero; auto-granted at level ≥ 25, §4.2);
tier 3 → `[10]` (1) / `[11]` (−1). (The power *names* in the table are that inference; the class id,
array index, compared value and effect are read directly from the IL.)

### Passives applied in `initialize` (exact order)

| class | condition | effect | power name | IL |
|---|---|---|---|---|
| 2 Knight | `passives[0] == −1` | `power *= 1.15` | Might | L77550-77569 |
| 2 Knight | else `passives[0] == 1` | `defense *= 1.15` | Chivalry | L77570-77587 |
| 3 Rogue | `passives[3] == −1` | `power *= 1.10` | Aggression | L77588-77605 |
| 8 Monk | `passives[1] == −1` | `power *= 1.15` | Dragon Style | L77606-77623 |
| 3 Rogue | `passives[1] == −1` | `moveSpeed *= 1.15` | Pursuit | L77624-77643 |
| 3 Rogue | else `passives[1] == 1` | `defense *= 1.15` | Combat Tactics | L77644-77661 |
| 3 Rogue | `passives[0] == 1` | `primaryActionCooldown *= 0.85` | Flurry | L77662-77679 |
| 4 Wizard | `passives[0] == −1` | `myEffects[0].projectileDamageMod = 1.2` | Impact | L77680-77697 |
| 5 Witch | `passives[0] == 1` | `myEffects[0].projectileDamageMod = 1.15` | Piercing Shadow | L77698-77715 |
| 4 Wizard | `passives[1] == −1` | `wardChance += 20` | Mage Armor | L77716-77733 |
| 3 Rogue | `passives[0] == −1` | `critChance += 20` | Critical Strikes | L77734-77751 |
| 7 Barbarian | `passives[1] == 1` | `critChance += 20` | Precision Strikes | L77752-77769 |
| 10 Paladin | `passives[0] == 1` | `defense *= 1.15` | Stalwart | L77770-77789 |
| 10 Paladin | else `passives[0] == −1` | `primaryActionCooldown *= 0.9`; `moveSpeed *= 1.1` | Swift Justice | L77790-77813 |
| 9 Ranger | `passives[0] == 1` | `critChance += 15` | Sniper's Sense | L77814-77831 |
| 8 Monk | `passives[0] == −1` | `critChance += 15` | Tiger Claw | L77832-77849 |
| 10 Paladin | `passives[1] == 1` | `health *= 1.2`; `maxHealth *= 1.2` | Bastion | L77850-77873 |
| 5 Witch | `passives[0] == −1` | `lifeDraining += 30` (percent, before the /100) | Life Leech | L77874-77892 |
| 8 Monk | `passives[1] == 1` | `bonusHealing += 10` (percent, before conversion) | Clarity | L77893-77911 |
| 10 Paladin | `passives[2] != 0` | for i in 0..3: if `playerScripts[i]` exists and is not this hero: `playerScripts[i].sentinelDefense = (int)(this.defense * 0.25)` | Sentinel | L77912-77962 |

Notes:
- All of these run **after** the gear/trinket additions of §4, so the percentage passives multiply the
  full level+gear value (e.g. Knight Might: `(P.power + scale*(lvl−1) + weapon + trinkets) * 1.15`).
- Sentinel uses the Paladin's `defense` at the moment its own `initialize` runs (Stalwart ×1.15 is already
  applied because it is earlier in the same method). It is never recomputed, and the Paladin does not give
  it to itself.
- Passives not in this table (e.g. Cleric tier passives, Knight tier 1/3, Wizard Fire Shield, Witch
  tier 1, Monk Counter, Barbarian Enrage variants) are checked at use time; the ones inside this range are
  in §9. The rest live in the attack/special coroutines (other doc).

---

## 6. `remoteUpdate()` — per-frame driver [IL L78040-78099]

```
handleBuffs()
if health > 0:
    AI(); blink(); handleCooldowns()
    if characterClass == 1: clericAuraAttack()
    else if characterClass == 9: flameArrowPulse()
healthAnimation(); shaderAnimation()
if buffs[25] <= 0: animateSliding()          // stunned heroes do not slide
if petScript: petScript.RemoteUpdate()
```

---

## 7. `AI()` — hero behaviour state machine [IL L78102-81244]

### Enums

| `AIType` | Meaning (from which coroutine it starts) |
|---|---|
| 1 | support: target is an ally. Class 1 → `castHeal(myTarget)`, class 6 → `castBardBuff(myTarget)` [IL L80014-80051] |
| 2 | ranged attacker: class 9 → `shootArrow(myTarget)`, any other class → `castFireball(myTarget)` [IL L80213-80261] |
| 3 | melee attacker: walks to a melee slot, then `meleeAttack()` [IL L80303-81111] |

`AIType` is a prefab value (the only code write is the `.ctor` default 1). UNVERIFIED which classes use
2 vs 3 beyond the class checks above (Cleric/Bard = 1; Ranger = 2).

| `AIState` | Meaning |
|---|---|
| 0 | idle (stands, may auto-acquire a target) |
| 1 | moving to `movementTarget` (player move order) |
| 2 | engaging `myTarget` |
| 3 | pouncing (flying to `pounceDestination`) |
| 5 | performing a special (AI does nothing) |

(4 is never used in this range.)

"Face" below means: set `myTransform.localScale.x` to −1 (facing left) or +1 (facing right) if it is not
already, then call `updateHealthBar(1)` so the bar is mirrored back. This boilerplate repeats ~14 times.

### Step-by-step (evaluated top to bottom every frame)

**A. Trinket regeneration** [IL L78240-78295]
`if passiveRegen > 0 and health > 0: health += passiveRegen * dt * (bonusHealing if bonusHealing != 0 else 1)`;
clamp to `maxHealth`; `updateHealthBar(0)`.

**B. Special waiting for a target** [IL L78296-78423]
`if specialAwaitingTarget > −1 and myTarget != null`: `AIState = 5`; face the target (left if
`target.x < my.x`, else right); `StartCoroutine(performSpecial(specialAwaitingTarget))`. (Execution then
continues to C.)

**C. Exclusive branch chain** — first match wins, then jump to step H:

1. **Flee** [IL L78424-78546]: `if flee and AIState is 0, 1 or 2`: `invincible = true`; face left; Play
   `"run"`; `run.speed = moveSpeed * runAnimMod * 2`; `position.x -= dt * moveSpeed * 1.5`.
2. **Stunned** [IL L78547-78566]: `if buffs[25] > 0 and AIState != 3`: Play `"stun"`.
3. **Busy/dead** [IL L78567-78579]: `if AIState == 5 or health <= 0`: nothing.
4. **Idle (`AIState == 0`)** → section D.
5. **Level complete walk** [IL L78961-79129]: `if motherBrain.levelComplete and AIState == 1 and
   Distance(position, movementTarget) > 0.04`: `moveVector = normalize(movementTarget − position)`;
   `position += moveVector * moveSpeed * dt` (no speed buffs); CrossFade `"run"` 0.15;
   `run.speed = moveSpeed * runAnimMod`; face by sign of `moveVector.x`; if now within 0.04 snap to
   `movementTarget`.
6. **Move order (`AIState == 1` and distance > 0.07)** → section E.
7. **Arrived (`AIState == 1`)** [IL L79761-79817]: CrossFade `"idle"` 0.15; Play `"select"`. If
   (`AIType == 1` or `AIType == 2`) and `myTarget != null`: `AIState = levelComplete ? 0 : 2`; otherwise
   `AIState = 0`. (A melee hero that finishes a plain move always goes idle.)
8. **Engage** → section F, entered when
   (`AIType == 3` and `AIState == 2` and `myTarget` and `myTargetEnemyScript`) or
   (`AIType == 2` and the same three) or (`AIType == 1` and `AIState == 2` and `myTarget`)
   [IL L79818-79872].
9. **Lost target** [IL L81140-81177]: `if AIState == 2 and (myTarget == null or myTargetEnemyScript == null)`:
   clear both, `AIState = 0`, Play `"idle"`.
10. **Pounce (`AIState == 3`)** [IL L81178-81232]: `moveVector = normalize(pounceDestination − position)`;
    `if pounceTimer > 0`: `position += moveVector * pounceSpeed * dt`; `pounceTimer -= dt`; when it reaches
    ≤ 0 → `StartCoroutine(pounceAttack())`.

**H. End of frame** [IL L81233-81243]: `if AIState != 1: movementTarget = position`.

### D. Idle [IL L78580-78960]

1. Animation: `if basicAction.normalizedTime >= 0.8 and basicAction.weight == 1` → CrossFade `"idle"` 0.2;
   else if `basicAction.weight != 1` → CrossFade `"idle"` 0.2 [IL L78585-78615].
2. **Melee auto-acquire** [IL L78616-78777] — requires `AIType == 3`, `!DB.tutorial`, `myTarget == null`,
   `myTargetEnemyScript == null`:
   ```
   autoAttackTimer -= dt
   if autoAttackTimer <= 0 and basicAction.weight != 1 and !commandPending:
       autoAttackTimer = 0.5
       for each e in motherBrain.enemyScripts (in array order; a null entry ends the loop):
           if Distance(e.position, position) < 1.5 and e.attackers < 4 and e.health > 0
              and e.myRenderer.enabled and !e.invincible:
               myTargetEnemyScript = e; myTarget = e.myTransform
               meleeSlot = e.requestPosition(preferBack, this)
               AIState = 2; actionTimer = 100      // 100 ⇒ first swing is immediate on arrival
               break
   ```
3. **Ranged auto-acquire** [IL L78778-78914] — only evaluated if the melee condition block of step 2 was
   not entered; requires `AIType == 2`, both target fields null; same timer logic (0.5 s, not mid-attack,
   no command pending). Per enemy: `Distance < 1.8`, `health > 0`, renderer enabled, not invincible (no
   `attackers` test, no slot request). Sets target, `AIState = 2`, `actionTimer = 100`.
   Note: there is **no** tutorial check for ranged heroes.
4. Support heroes (`AIType == 1`) never auto-acquire.
5. `if motherBrain.partyFormUp and not facing right` → face right [IL L78915-78958].

Auto-acquire picks the **first** qualifying enemy in array order, not the nearest.

### E. Moving to a point [IL L79130-79760]

`moveVector = normalize(movementTarget − position)`, then one of:

| Condition | Movement | IL |
|---|---|---|
| class 4 (Wizard) and `passives[2] != 0` (Teleport) | No walking. If `teleport.weight != 1`: `mySounds[2].Play()`, Play `"teleport"`, `myEffects[13].activate(position, null)`, `myEffects[14].activate(position, null)`. Face by `moveVector.x`. When `teleport.normalizedTime >= 1`: `activateColors()`, material color = (1,1,1), `colorSpeed = 2`, `position = movementTarget`, `myEffects[15].activate(position, null)` | L79156-79335 |
| `buffs[16] > 0` or `buffs[24] > 0` or `buffs[17] > 0` | `position += moveVector * moveSpeed * dt * buffMagnitudes[16]`; CrossFade `"run"` 0.15; `run.speed = moveSpeed * runAnimMod * buffMagnitudes[16]`; face | L79336-79494 |
| else `buffs[22] > 0` | same with `buffMagnitudes[22]` | L79495-79637 |
| else | `position += moveVector * moveSpeed * dt`; CrossFade `"run"` 0.15; `run.speed = moveSpeed * runAnimMod`; face | L79638-79760 |

Arrival threshold is 0.07 world units [IL L79136-79145].

### F. Engaging a target

**F1. Support (`AIType == 1`)** [IL L79873-80064]
```
actionTimer += dt * (buffMagnitudes[22] if buffs[22] > 0 else 1)
face target (left if target.x < my.x, right if target.x > my.x)
if actionTimer >= primaryActionCooldown and characterClass == 1: StartCoroutine(castHeal(myTarget))
else if actionTimer >= primaryActionCooldown and characterClass == 6: StartCoroutine(castBardBuff(myTarget))
if basicAction.normalizedTime >= 0.9: CrossFade "idle" 0.15
```
There is **no range check and no movement**: support heroes act on their target from anywhere. There is
also no "who needs healing" logic — the target is whoever the player assigned. (Resetting `actionTimer`
is done inside the coroutines.)

**F2. Ranged (`AIType == 2`), target alive** [IL L80065-80274]
```
actionTimer += dt * (buffMagnitudes[22] if buffs[22] > 0 else 1)
face target
if actionTimer >= primaryActionCooldown:
    if characterClass == 9:
        StartCoroutine(shootArrow(myTarget))
        if petScript and petScript.myTarget == null:
            petScript.myTarget = myTarget; petScript.myTargetEnemyScript = myTargetEnemyScript
    else: StartCoroutine(castFireball(myTarget))
if basicAction.normalizedTime >= 0.9: CrossFade "idle" 0.15
```
No range check and no movement either.
Target dead (`myTargetEnemyScript.health <= 0`): clear target fields, `AIState = 0`, CrossFade `"idle"`
0.2 [IL L80275-80302].

**F3. Melee (`AIType == 3`), target alive** [IL L80303-81111]

1. Attack-speed timer (first matching line only) [IL L80316-80382]:
   ```
   if   buffs[17] > 0: actionTimer += dt * buffMagnitudes[17]
   elif buffs[16] > 0: actionTimer += dt * 1.15
   elif buffs[22] > 0: actionTimer += dt * buffMagnitudes[22]
   else:               actionTimer += dt
   ```
2. Face: left if `my.x > target.x`, else right [IL L80383-80490].
3. "Hold position" flag `hold = false` [IL L80491-80579]. Let `E = myTargetEnemyScript`. If
   `E.myTargetScript != null`:
   - `slotPos = E.myTarget.position + E.myTargetScript.meleePositions[E.meleeSlot]`
   - `d = Distance(myTarget.position, position)`
   - if `E.isMelee and E.myTargetScript == this and Distance(E.position, slotPos) <= 0.25` → `hold = true`
   - else if `E.isMelee and E.myTargetScript == this and d < Distance(position, position + meleePositions[E.meleeSlot])`
     (i.e. `d <` length of that slot offset) → `hold = true`

   Meaning: if the melee enemy I am attacking is itself attacking me and is already standing in (or inside)
   its slot next to me, I do not walk — we fight where we stand.
4. `findMovementTarget()` (§8) [IL L80580].
5. If `Distance(position, movementTarget) > 0.07` and `basicAction.weight != 1` and `!hold` and
   `specialAction.weight != 1` → **approach** [IL L80581-81038]; `moveVector = normalize(movementTarget − position)`:

   | Condition | Movement |
   |---|---|
   | `buffs[11] > 0` (charge) | `position += moveVector * 9 * dt`; CrossFade `"charge"` 0.05. Dust trail: when `internalTimeCounter > 0.06`: clamp `internalIntCounter` into 7..9, reset the timer to 0, `myEffects[internalIntCounter].activate(position, null)`, increment (wrap 9 → 7); otherwise `internalTimeCounter += dt` [IL L80620-80703] |
   | `buffs[16] > 0` or `buffs[24] > 0` or `buffs[17] > 0` | speed `moveSpeed * buffMagnitudes[16]`; CrossFade `"run"` 0.1 [IL L80704-80836] |
   | else `buffs[22] > 0` | speed `moveSpeed * buffMagnitudes[22]`; CrossFade `"run"` 0.1 [IL L80837-80953] |
   | else | speed `moveSpeed`; CrossFade `"run"` 0.1 [IL L80954-81037] |

   In the three run rows `run.speed = ±moveSpeed * runAnimMod * (buff magnitude or 1)`; the sign is negative
   (animation plays backwards = back-pedalling) when the hero faces right but moves left, or faces left
   but moves right. The hero does not turn to its walking direction here; it keeps facing the target.
6. Otherwise (in position, or holding, or mid-swing) [IL L81039-81092]:
   ```
   if actionTimer >= primaryActionCooldown and basicAction.weight > 0
      and Distance(position, movementTarget) > 0.75:      CrossFade "idle" 0.3
   elif actionTimer >= primaryActionCooldown:             StartCoroutine(meleeAttack())
   elif run.weight > 0:                                   CrossFade "idle" 0.3
   ```
7. `if basicAction.normalizedTime >= 0.85 or specialAction.normalizedTime >= 0.85` → CrossFade `"idle"`
   0.15 [IL L81093-81109].

Target dead (`E.health <= 0`): clear target fields, `AIState = 0`, `movementTarget = position`
[IL L81112-81137].

---

## 8. `findMovementTarget()` [IL L81247-81333]

```
movementTarget = myTarget.position + myTargetEnemyScript.meleePositions[meleeSlot]
if movementTarget.z > motherBrain.cieling:          movementTarget.z = cieling
if movementTarget.x > motherBrain.edge - 0.3:       movementTarget.x = edge - 0.3
if movementTarget.x < -motherBrain.edge + 0.3:      movementTarget.x = -edge + 0.3
if movementTarget.z < motherBrain.floor:            movementTarget.z = floor
```
The melee slot offsets belong to the **enemy** (`EnemyScript.meleePositions`), indexed by the slot the
hero got from `EnemyScript.requestPosition`. `cieling` (sic), `edge`, `floor` are MotherBrain arena bounds.

---

## 9. `takeDamage(int damageAmount, Vector3 impactForce, EnemyScript whoHitMe)` [IL L81497-82407]

Exact order (`dmg` is the int argument, re-truncated with `(int)` after every float step):

1. **Divine Intervention redirect** [IL L81518-81542]: `if buffs[30] > 0`: `activateColors()`, tint
   (0.56, 0.56, 0.9), `myProtector.takeDamage(damageAmount, impactForce, whoHitMe)` with the *unmodified*
   arguments, **return**.
2. `if invincible: return` [IL L81543-81547].
3. **Knight Revenge reflect** [IL L81548-81577]: `if characterClass == 2 and passives[3] == −1 and buffs[0] > 0`:
   `whoHitMe.takeDamage(damageAmount, Vector3(0,0,0), this)` — the full raw amount, before any mitigation.
4. `if !noHitReact`: Stop then Play `"hitReact"` [IL L81578-81590].
5. Hit flash: `colorSpeed = 2`; `activateColors()`; material color **red channel = 0.6**;
   `blinkingBone.localScale.y = 1`; `blinkCooldown = 0.3` [IL L81591-81652].
6. **Flat armor**: `dmg = (int)(dmg − (defense + sentinelDefense))` [IL L81653-81665].
7. **Bard armor**: `if buffs[14] > 0: dmg = dmg − bardBuffArmor` [IL L81666-81680].
8. **Enrage penalty** [IL L81681-81738]: `if buffs[15] > 0`:
   - `passives[0] == 1` (Barbarian Death Wish): `dmg = (int)(dmg * (1 + buffMagnitudes[15] + 0.15))`
   - `passives[0] == −1` (Iron Skin): unchanged
   - else: `dmg = (int)(dmg * (1 + buffMagnitudes[15]))`

   (No class check — it relies on only the Barbarian having `buffs[15]`.)
9. **Multiplicative buffs on me**, each `dmg = (int)(dmg * buffMagnitudes[i])`, in this order:
   `buffs[5]` [IL L81739-81759], `buffs[20]` [IL L81760-81780], `buffs[2]` [IL L81781-81801],
   `buffs[0]` [IL L81802-81822].
10. **Debuffs on the attacker**, each `dmg = (int)(dmg * debuffMagnitudes[i])`, in this order:
    `whoHitMe.debuffs[7]` [IL L81823-81843], `[18]` [IL L81844-81864], `[14]` [IL L81865-81885].
11. **Minimum damage**: `if dmg < 3 and buffs[5] <= 0: dmg = 3` [IL L81886-81902].
12. **Ward (deflect)** [IL L81903-81935]: `if wardChance > 0 and Random.Range(0, 100) <= wardChance`:
    `dmg = 0`, tint (0.56, 0.56, 0.9), Stop `"hitReact"`. (Integer `Range(0,100)` gives 0..99 and the test is
    `<=`, so the real chance is `wardChance + 1` percent.)
13. **Shield `buffs[26]`** [IL L81936-81964]: `if buffs[26] > 0`: `dmg = 0`, same tint, Stop `"hitReact"`.
14. **Aura of Light `buffs[28]`** [IL L81965-82018]: `if buffs[28] > 0`:
    `heal((int)(dmg * 0.6), this)` if `passives[1] == −1` (Paladin Power of the Word) else
    `heal((int)(dmg * 0.5), this)`; `myEffects[3].activate(position, myTransform)`; `dmg = 0`; Stop
    `"hitReact"`. The heal uses the *mitigated* damage (after steps 6–11).
15. **Evasion `buffs[23]`** [IL L82019-82070]: `if buffs[23] > 0`: `dmg = 0`; `alphaAnim = true`;
    `colorSpeed = 2`; material alpha = 0.5; Stop `"hitReact"`.
16. **Witch on-hit passives** (`characterClass == 5`) [IL L82071-82164]:
    - `passives[1] == 1` (Terrifying Presence) and `Random.Range(1, 101) <= 10` (10 %):
      `whoHitMe.debuffs[5] = 4` (seconds); `whoHitMe.debuffColor = (0.34, 0.16, 0.57)`;
      `whoHitMe.mostRecentDebuff = 5`;
      `whoHitMe.fearLocation = (Random.Range(−edge + 0.7, edge − 0.7), 0, Random.Range(floor + 0.9, cieling − 0.8))`;
      `whoHitMe.fearTimer = Random.Range(0.6, 1.0)`.
    - else `passives[1] == −1` (Sudden Doom) and `Random.Range(1, 101) <= 5` (5 %) and
      `remainingCooldowns[0] > 0`: `remainingCooldowns[0] = 0.05`.

    Both roll even when the hit was nullified in steps 12–15.
17. `health -= dmg` [IL L82165-82170].
18. **Wizard Fire Shield** [IL L82171-82231]: `if characterClass == 4 and passives[1] == 1 and
    Random.Range(0, 100) <= 20 and !myEffects[5].enabled`: tint (0.9, 0.4, 0.4);
    `myEffects[5].activate(position, whoHitMe.myTransform)` (launches the retaliation fireball effect at the
    attacker). Real chance 21 % (same off-by-one as ward).
19. Health bar: `healthTimer = 2.6`; if not visible, `healthVisible = true` and Play `"showHealth"`;
    `updateHealthBar(0)` [IL L82232-82249].
20. **If `health > 0`** [IL L82250-82400]:
    - `slideVector = impactForce` (knock-back; applied in `animateSliding`).
    - **Melee retaliation**: `if AIType == 3 and myTargetEnemyScript == null and whoHitMe.attackers < 4
      and run.weight == 0 and !commandPending and AIState == 0 and !whoHitMe.invincible`: target `whoHitMe`
      (`myTargetEnemyScript`, `myTarget = whoHitMe.myTransform`),
      `meleeSlot = whoHitMe.requestPosition(preferBack, this)`, `AIState = 2`.
    - else **ranged retaliation**: `if AIType == 2 and myTargetEnemyScript == null and run.weight == 0
      and !commandPending and AIState == 0 and !whoHitMe.invincible`: target it, `AIState = 2`.
    - **Monk Counter**: `if characterClass == 8 and !whoHitMe.invincible and AIState == 2 and health > 0
      and passives[2] != 0 and whoHitMe.isMelee and !midAction and Random.Range(1, 101) <= 30` (30 %):
      `StartCoroutine(counterAttack(whoHitMe))`.
21. **Else** (`health <= 0`): `StartCoroutine(die())` [IL L82401-82405].

Compact formula for an unshielded hit:
```
dmg = raw − defense − sentinelDefense − (bardBuffArmor if buffs[14])
dmg *= (1 + buffMagnitudes[15] [+0.15])            if enraged (see step 8)
dmg *= buffMagnitudes[i]   for each active i in 5, 20, 2, 0
dmg *= debuffMagnitudes[j] for each active attacker debuff j in 7, 18, 14
dmg = max(dmg, 3)          unless buffs[5] active
```
Armor is a flat subtraction, never a percentage. There is no hero "dodge" stat other than `wardChance`.
Enemy crits/misses, if any, are decided by the caller before `takeDamage`.

---

## 10. `heal(int healAmount, PartyMember whoHealedMe)` [IL L82423-82590]

Only if `health > 0` (dead heroes cannot be healed):
```
colorSpeed = 0.7; activateColors(); material color green channel = 0.5          [IL L82441-82471]
if whoHealedMe.buffs[14] > 0: healAmount += whoHealedMe.bardBuffPower           [IL L82472-82487]
if whoHealedMe.buffs[4]  > 0: healAmount = (int)(healAmount * buffMagnitudes[4]) [IL L82488-82508]
if whoHealedMe.buffs[6]  > 0: healAmount = (int)(healAmount * buffMagnitudes[6]) [IL L82509-82529]
health += healAmount * (bonusHealing if bonusHealing != 0 else 1)               [IL L82530-82554]
health = min(health, maxHealth)                                                 [IL L82555-82564]
healthTimer = 2.6; show health bar if hidden ("showHealth"); updateHealthBar(0) [IL L82565-82582]
whoHealedMe.browniePoints += 5                                                  [IL L82583-82588]
```
The healer-side modifiers are read from the **healer's** buffs; `bonusHealing` is the **recipient's**
(healing trinkets 46–48, Monk Clarity). Other ways HP is restored, none of which go through `heal`:

| Source | Formula | bonusHealing applied? | IL |
|---|---|---|---|
| `passiveRegen` (trinkets 8, 19) | `+passiveRegen * dt` | yes | L78240-78295 |
| `buffs[12]` heal-over-time | `+directHealHotMagnitude * dt` | yes | L86107-86181 |
| `buffs[19]` Bard HoT | `+bardHotMagnitude * dt` | yes | L86182-86255 |
| `buffs[24]` Spirit Trance | `+maxHealth * 0.05 * dt` | yes | L86256-86331 |
| `drainLife(howMuch)` | `+howMuch` (only if alive), clamp, `updateHealthBar(0)` | **no** | L86755-86787 |
| `adrenalineRush()` | `+maxHealth * 0.2` (only if alive), clamp | **no** | L86790-86847 |

---

## 11. `handleCooldowns()` and `handleCooldowns2(i)` [IL L81336-81494, 87154-87266]

For slot `i` in 0..2, if `remainingCooldowns[i] > 0`:
```
remainingCooldowns[i] -= dt * (buffMagnitudes[18] if buffs[18] > 0 else 1)   [IL L81350-81393]
if remainingCooldowns[i] <= 0:
    remainingCooldowns[i] = 0
    if !motherBrain.disableSpecials and motherBrain.leaderScript == this and !motherBrain.freezeUI:
        motherBrain.actionBarAnimation.Play("tap1" | "tap2" | "tap3")   // for i = 0 | 1 | 2
        motherBrain.flashIcon[i] = true
        StartCoroutine(handleCooldowns2(i))                              [IL L81394-81470]
```
`handleCooldowns2(i)`: wait **0.25 s**; then `if !motherBrain.disableSpecials: flashIcon[i] = false`
[IL L87229-87260]. `leaderScript` is the currently selected hero (whose powers the action bar shows).
Starting a cooldown (`remainingCooldowns[i] = cooldowns[i]`, `noCooldownChance`) happens in
`performSpecial` (other doc).

---

## 12. Health bar: `healthAnimation`, `updateHealthBar`, `select`, `deselect`

**`updateHealthBar(int flip)`** [IL L82781-83186] — the bar has a green part and a red "recent damage" part.
Full bar width = 0.72 local units (±0.36).
- Hero facing right (`localScale.x > 0`): `greenHealthA.x = 0.36`; if `flip == 1`:
  `redHealthB.x = −redHealthA.x`; `redHealthA.x = 0.36`;
  `greenHealthB.x = greenHealthA.x − (health / maxHealth) * 0.72`;
  if `redHealthB.x > greenHealthB.x`: `redHealthB.x = greenHealthB.x` (heals pull the red part in instantly).
- Facing left: mirror — `greenHealthB.x = −0.36`; if `flip == 1`: `redHealthA.x = −redHealthB.x`;
  `redHealthB.x = −0.36`; `greenHealthA.x = greenHealthB.x + (health / maxHealth) * 0.72`;
  if `redHealthA.x < greenHealthA.x`: `redHealthA.x = greenHealthA.x`.
- `flip = 1` is passed whenever the hero's facing was just mirrored; `0` otherwise.

**`healthAnimation()`** [IL L82593-82778] (every frame):
- `if healthTimer > 0: healthTimer -= dt`; else if `healthVisible and !selected`: `healthVisible = false`,
  Play `"hideHealth"`.
- While `0 < healthTimer < 2.2` the red part slides toward the green part at 1 unit/s: facing right:
  `if redHealthB.x < greenHealthB.x: redHealthB.x += dt`; facing left:
  `if redHealthA.x > greenHealthA.x: redHealthA.x −= dt`. (Since damage sets the timer to 2.6, the red
  chunk lingers 0.4 s before shrinking.)

**`select()`** [IL L83385-83412]: `selected = true`; if bar hidden Play `"showHealth"`;
`healthVisible = true`; Play `"select"`.
**`deselect()`** [IL L83358-83382]: `selected = false`; if `healthTimer <= 0`: Play `"hideHealth"`,
`healthVisible = false`.

---

## 13. `blink()` [IL L83189-83355]

`blinkCooldown -= dt`. When it reaches ≤ 0:
- if `blinkingBone.localScale.y < 0.5` (eyelid hidden): set y = 1 (eyes closed) and
  `blinkCooldown = Random.Range(1.16, 1.19) − 1` (≈ 0.16–0.19 s);
- else: set y = 0 (eyes open) and `blinkCooldown = Random.Range(1.0, 5.0)`.

Additionally, if `specialAction` exists with `weight == 1` and y == 1 → y = 0 (eyes forced open during
the special animation). `takeDamage` forces y = 1 for 0.3 s (eyes shut on hit).

---

## 14. Tint system: `shaderAnimation`, `activateColors`, `pulse`, `flash`

The hero material's neutral color is **(0.25, 0.25, 0.25, 1)**. Effects set the material color to
something else and call `activateColors()`; `shaderAnimation()` then fades each channel back.

**`activateColors()`** [IL L84223-84239]: `redAnim = blueAnim = greenAnim = true`.

**`shaderAnimation()`** [IL L83415-84220], every frame, for each of r, g, b whose flag is set:
```
step = Time.deltaTime * colorSpeed * (1 / Time.timeScale)     // fade is independent of slow-motion
if c > 0.25: c -= step; if c < 0.25: c = 0.25, flag = false
elif c < 0.25: c += step; if c > 0.25: c = 0.25, flag = false
else: flag = false
```
(red [IL L83500-83695], green [IL L83696-83892], blue [IL L83893-84089]).
Alpha, if `alphaAnim`: `if a < 1: a += step; if a >= 1: a = 1, alphaAnim = false` else `alphaAnim = false`
[IL L84090-84194]. Finally, if `myRenderer2` exists and its color differs, copy `myRenderer`'s color to
it [IL L84195-84218].

**`pulse()`** [IL L84242-84262]: `colorSpeed = 2`; `activateColors()`; color = (0.7, 0.7, 0.7).
**`flash()`** [IL L84265-84285]: `colorSpeed = 1.1`; `activateColors()`; color = (0.55, 0.55, 0.55).

All tint constants in this range:

| Event | Color set | colorSpeed | IL |
|---|---|---|---|
| Hit taken | r = 0.6 (g, b unchanged) | 2 | L81591-81621 |
| Ward / `buffs[26]` / Divine Intervention redirect | (0.56, 0.56, 0.9) | unchanged | L81526-81534, 81915-81931, 81944-81960 |
| Evasion | a = 0.5 | 2 | L82027-82066 |
| Fire Shield proc | (0.9, 0.4, 0.4) | unchanged | L82198-82206 |
| Healed | g = 0.5 | 0.7 | L82441-82471 |
| Teleport arrival | (1, 1, 1) | 2 | L79305-79322 |
| Active-buff pulse | `buffColor`, every 0.35 s | 0.6 | L86048-86077 |
| Adrenaline Rush | (0.75, 0.32, 0.32) | 0.6 | L86833-86845 |

---

## 15. Class-specific per-frame attacks

### `clericAuraAttack()` — class 1 only [IL L84371-84586]
```
if buffs[7] > 0 and auraTimer <= 0:
    auraTimer = 1.0
    mySounds[4].Play(); myEffects[8].activate(position, null)
    for each e in enemyScripts (a null entry ends the loop):
        if |e.x - x| < 2.0 + e.aoeRadiusBonus and |e.z - z| < 1.5 + e.aoeRadiusBonus
           and e.health > 0 and e.myRenderer.enabled:
            dir = normalize(e.position - position)
            e.takeDamage((int)(power * buffMagnitudes[7]), dir * impactForce * 2, this)
elif buffs[7] > 0 and auraTimer > 0:
    auraTimer -= dt
```
One pulse per second in a 4.0 × 3.0 box (plus each enemy's `aoeRadiusBonus`), knocking enemies away.

### `flameArrowPulse()` — class 9 only [IL L84589-84975]
```
if auraTimer > 0: auraTimer -= dt
else:
    if buffs[7] > 0:
        auraTimer = 0.25
        for each e in enemyScripts (null ends loop):
            if |e.x - flamePatch.x| < 1.8 + e.aoeRadiusBonus and |e.z - flamePatch.z| < 1.3 + e.aoeRadiusBonus
               and e.health > 0 and e.myRenderer.enabled:
                bardCoefficient = 0.12
                e.takeDamage((int)(power * 0.12), Vector3(0,0,0), this)
                bardCoefficient = 1.0
    if buffs[6] > 0:  same, around flamePatch2, auraTimer = 0.25
```
So each fire patch ticks every 0.25 s for 12 % of power, no knock-back. Sound: if
`DB.soundEnabled` and both `buffs[6] <= 1` and `buffs[7] <= 1` and `mySounds[13]` is playing: fade its
volume by `dt * 0.7` per frame while volume > 0, then `Stop()` once volume ≤ 0 [IL L84887-84973].

---

## 16. Melee slot bookkeeping for enemies attacking this hero

Enemies that melee a hero ask the hero for one of 6 slots (`meleePositions[0..5]`, prefab offsets).
From the logic: slot 0 = left side, slot 1 = right side; slots 2+3 replace slot 0 when two enemies share
the left; slots 4+5 replace slot 1 when two share the right.

### `requestPosition(int preferBack, EnemyScript whosAsking) → int slot` [IL L84991-85546]
`attackers += 1`, then by the new `attackers` value ("left" = `asker.x < my.x`; `occ` = `meleeOccupants`;
"split left" = `occ[2] = occ[0]; occ[0] = null; occ[2].meleeSlot = 2; occ[3] = asker; return 3`;
"split right" = `occ[4] = occ[1]; occ[1] = null; occ[4].meleeSlot = 4; occ[5] = asker; return 5`):

| attackers | Rules, first match wins | IL |
|---|---|---|
| 1 | left → `occ[0] = asker`, return 0; else `occ[1] = asker`, return 1 | L85016-85056 |
| 2 | `preferBack == 1` and `occ[0]` taken → slot 1. `preferBack == 1` and `occ[1]` taken → slot 0. Left and `occ[0]` free → slot 0. Not left and `occ[1]` free → slot 1. Left and `occ[0]` taken → split left. Not left and `occ[1]` taken → split right. Else return 0 | L85057-85255 |
| 3 | `occ[2]` and `occ[3]` taken → slot 1. `occ[4]` and `occ[5]` taken → slot 0. Hero faces right and `preferBack == 1` → split right. Hero faces left and `preferBack == 1` → split left. Left → split left. Not left → split right | L85256-85470 |
| 4 | `occ[0]` taken → split left; else `occ[1]` taken → split right | L85471-85543 |
| ≥ 5 or no rule matched | return 0 (no occupant recorded) | L85544-85545 |

### `purgePosition(int whichSlot)` [IL L85549-85703]
`attackers -= 1`; `occ[whichSlot] = null`; then re-merge split sides:
- `occ[2]` taken and `occ[3]` empty → move 2 → 0 (`occ[0].meleeSlot = 0`); else `occ[3]` taken and
  `occ[2]` empty → move 3 → 0.
- `occ[4]` taken and `occ[5]` empty → move 4 → 1 (`meleeSlot = 1`); else `occ[5]` taken and `occ[4]`
  empty → move 5 → 1.

(The mirror image — heroes taking slots around an enemy — is `EnemyScript.requestPosition/purgePosition`,
called from §7 D, §9 step 20 and `die`.)

---

## 17. `handleBuffs()` — buff timers [IL L86039-86362]

1. Buff tint pulse: `if colorPulseTimer <= 0 and buffColor != (0.25, 0.25, 0.25)`: `colorPulseTimer = 0.35`,
   `colorSpeed = 0.6`, `activateColors()`, material color = `buffColor`; else `colorPulseTimer -= dt`
   [IL L86048-86083].
2. For every index `i` with `buffs[i] > 0` [IL L86090-86360]:
   - `buffs[i] -= dt` (real `Time.deltaTime`; all buffs tick at the same rate).
   - `i == 12`, `i == 19`, `i == 24` and `health > 0`: heal-over-time per the table in §10; clamp;
     `updateHealthBar(0)`; `if healthTimer < 2.2: healthTimer = 2.2`; show the bar if hidden.
   - if the buff just expired (`buffs[i] <= 0`) and `i == mostRecentBuff`: `buffColor = (0.25, 0.25, 0.25)`
     (stops the pulse).

Buffs are not cleared on death; they simply keep counting down. A buff is "refreshed" by overwriting its
timer (writers are in the coroutines / other classes, see §3).

---

## 18. Small helpers

**`animateSliding()`** — knock-back [IL L85706-86022]
```
if position.x >= edge - 1.2 and slideVector.x > 0:  slideVector.x = 0; position.x = edge - 1.2
elif position.x <= -(edge - 1.2) and slideVector.x < 0: slideVector.x = 0; position.x = -(edge - 1.2)
if position.z >= cieling and slideVector.z > 0:     slideVector.z = 0; position.z = cieling
elif position.z <= floor + 0.5 and slideVector.z < 0: slideVector.z = 0; position.z = floor + 0.5
if |slideVector.x| > 0 or |slideVector.z| > 0:
    position += slideVector * dt * myWeight
    slideVector = Lerp(slideVector, (0,0,0), dt * frictionConstant)     // frictionConstant = 10
if |slideVector.x| <= 0.005: slideVector.x = 0
if |slideVector.z| <= 0.005: slideVector.z = 0
```

**`returnToNormal()`** [IL L86365-86421] (called by attack/special coroutines when they finish):
`commandPending = false`; `if !levelComplete and AIState != 3`: if `myTarget != null` → `AIState = 2`,
`actionTimer = 100`; else if `Distance(position, movementTarget) > 0.07` → `AIState = 1`; else
`AIState = 0`, CrossFade `"idle"` 0.15.
**`returnToNormalFromShot()`** [IL L86424-86477]: identical but does **not** set `actionTimer = 100`.
**`returnToNormalFromPounce()`** [IL L86480-86531]: identical to `returnToNormal` but without the
`AIState != 3` test.

**`calculateDamageMultiplier(EnemyScript victim) → float`** [IL L86534-86610] (outgoing damage):
```
m = 1
if buffs[4]  > 0:         m *= buffMagnitudes[4]
if victim.debuffs[2] > 0: m *= debuffMagnitudes[2]
if victim.debuffs[6] > 0: m *= debuffMagnitudes[6]
if buffs[13] > 0:         m *= buffMagnitudes[13]
return m
```

**`calculateCrit() → int`** [IL L87112-87142]: `if critChance > 0 and Random.Range(0, 100) <= critChance`
→ 2, else 1. (Crit = double damage; real chance `critChance + 1` %.)

**`createMyEffects()`** [IL L86613-86752]: for each `i` in `myEffectNames`: create when
`myEffectPrereqs[i] == 0`, or `== 2 and abilities[1] == 2`, or `== 3 and abilities[1] == 3`, or
`== 4 and abilities[2] == 4`, or `== 5 and abilities[2] == 5`. Create =
`Instantiate(Resources.Load(myEffectNames[i]))`, `myEffects[i]` = its `"EffectScript"` component,
`myEffects[i].myBoss = this`. Uncreated entries stay null.

Effect / sound indices used in this range (their prefab names are scene data, not in the IL):
`myEffects[0]` basic projectile (its `projectileDamageMod` is set by Wizard Impact / Witch Piercing Shadow),
`[3]` Paladin Aura-of-Light heal effect, `[5]` Wizard Fire Shield retaliation, `[7..9]` charge dust,
`[8]` Cleric aura pulse, `[13]`, `[14]` teleport departure, `[15]` teleport arrival; `mySounds[2]` teleport,
`[4]` Cleric aura, `[13]` Ranger fire loop.

**`drainLife(float)`**, **`adrenalineRush()`**: see §10. `adrenalineRush` also sets
`buffs[16] = motherBrain.buffDurations[16]` [IL L86821-86832].

**`returnDamageValue(float v)`** [IL L86850-86860]: `returnedDamage = v`.

**`muteSoundEffects()`** [IL L86863-86901]: if `!DB.soundEnabled`, set volume 0 on every `mySounds` entry.

**`congratsScreenInitialize()`** [IL L86904-87109]: reduced `initialize` for the victory screen — caches
transform/animation/renderers (class 9 `geometry2`), bones (class 2 `shield`, class 7 `arm_r/weapon2`; note
class 10 is **not** handled here), attaches weapon/off-hand, loads the texture (`Lo` variant if
`Screen.width <= 500`), Plays `"run"`. No stats, no passives.

**Coroutine stubs** (bodies outside range): `castHeal(Transform)` [IL L84288], `castBardBuff(Transform)`
[IL L84302], `castFireball(Transform)` [IL L84316], `shootArrow(Transform)` [IL L84330],
`counterAttack(EnemyScript)` [IL L84344], `meleeAttack()` [IL L84358], `pounceAttack()` [IL L84978],
`performSpecial(int specialSlot)` [IL L86025]. `Main()` is empty [IL L87145-87152].

---

## 19. `die()` coroutine [IL L82410-82420, body 87268-88335]

1. `TPK = true`; for every non-null `motherBrain.playerScripts[i]` with `health > 0` → `TPK = false`
   [IL L87451-87502].
2. If `TPK`: `motherBrain.disableInput = true`; if `!motherBrain.levelComplete` →
   `StartCoroutine(motherBrain.defeatSequence())`; then `motherBrain.levelComplete = true`
   [IL L87503-87529].
3. If `motherBrain.leaderScript == this` → `StartCoroutine(motherBrain.disableActionBar())`
   [IL L87530-87546].
4. `meleeOccupants[0..5] = null`; `attackers = 0`; `gameObject.layer = 11`; `myAnimation.Stop()`; Play
   `"hideHealth"`; Play `"death"`; `blinkingBone.localScale.y = 1` (eyes closed) [IL L87547-87645].
5. If `myTargetEnemyScript != null and AIType == 3` → `myTargetEnemyScript.purgePosition(meleeSlot)`
   (frees the hero's slot on the enemy) [IL L87646-87664].
6. `yield WaitForSeconds(2.0)` [IL L87665-87671].
7. Flicker: 7 × ( `position.y = 100`; wait 0.06 s; `position.y = 0`; wait 0.06 s ) — 14 waits, 0.84 s
   total [IL L87672-88287].
8. `position.x = 10` (parked off-field); coroutine ends [IL L88288-88328].

The body is not destroyed and `health` stays ≤ 0, which is what gates `AI`, `heal`, regen and HoTs.
`myTarget`/`AIState`/buffs are not reset here. There is no revive logic in this range.

---

## 20. Uncertain / not determined

- **`MotherBrain.buffMagnitudes[]`, `buffDurations[]`, `debuffMagnitudes[]`** values are not in the IL
  (scene-serialized). Every formula above that uses them is exact in structure but the numbers are unknown.
  UNVERIFIED hints from power descriptions in `classes.json` only (e.g. Shield "reducing damage taken by
  75%" would imply `buffMagnitudes[2] = 0.25`; Shield Wall "50%" → `[0] = 0.5`; Enrage "35%" → `[15] = 0.35`)
  — do not treat these as read values.
- **Prefab-serialized hero fields** not in the IL: `AIType`, `preferBack`, `characterClass` per prefab,
  `meleePositions`, `myEffectNames`, `myEffectPrereqs`, `mySounds`, `myTextureName`, size of `buffs`,
  and any prefab override of `.ctor` defaults (`moveSpeed` 1.5, `primaryActionCooldown` 1.3,
  `impactForce` 2, `myWeight` 1, `frictionConstant` 10). The `.ctor` defaults are what the code sets; a
  prefab may override them.
- **Buff "who sets it" column in §3** and all power *names* attached to passives/abilities are inferences
  (see notes there); class ids, array indices and compared values are read from the IL.
- `buffs[1]`, `[8]`, `[9]`, `[21]`, `[27]`, `[29]` are only read in the attack/special coroutines;
  `buffs[3]`, `[10]` have no reader or writer found.
- Who sets `flee`, `myProtector`, `specialAwaitingTarget`, `commandPending`, `pounce*`, `flamePatch*`,
  `directHealHotMagnitude`, `bardHot*`/`bardBuff*`: outside this range (MotherBrain input code and the
  coroutines); not traced here.
- `positionThreshold`, `meleeOffset`, `totalMeleeSounds`, `whichVolley`, `prestissimo`, `dragType`,
  `noCooldownChance`, `lifeDraining`, `bonusXP`, `critChance` (via `calculateCrit`) are consumed outside
  this range.
- UNVERIFIED: a melee hero receives `AIState = 2` for a player attack order from MotherBrain's input code
  (the AI itself only sets 2 via auto-acquire, retaliation, `returnToNormal*`, or arrival for AIType 1/2).

### Contradictions with older notes
- `work/battleheart-encounter-parity.md` L65 calls buff `0x0f` a "stance/aura (outgoing AND incoming
  damage trade)" and `0x0e` "Bard power/armor song": consistent with this range for incoming damage, but
  note the incoming multiplier is `1 + buffMagnitudes[15]` (additive form), with `+0.15` for
  `passives[0] == 1` and **no penalty at all** for `passives[0] == −1`.
- The same note says the index→name mapping "is NOT in the assembly": partly true (no names), but writer
  sites do identify most indices (§3).
- `bh/data/party.json` `characterClass` values are 1-based while `bh/data/classes.json` `id` is 0-based;
  anything that joins them directly is off by one (code uses `powerDB[characterClass − 1]`).
- `party.json` `passives[2]` is ignored in battle: the hero's tier-2 passive is recomputed as
  `level >= 25` [IL L59894-59924].

---

## 21. Cross-references

Called by (outside this range):
- `MotherBrain.Awake` [IL L59305-61650]: builds stats, calls `initialize()`, tutorial `takeDamage`.
- `MotherBrain` per-frame loop → `remoteUpdate()`; `MotherBrain.playerControl` [IL ~62204-63656] /
  `pauseInput` / `tutorialDriver` / `specialMove` write `AIState`, targets, `commandPending`, `flee`.
- `EnemyScript` attack code → `takeDamage`, `requestPosition`, `purgePosition`; `EnemyScript.stunBolt`
  sets `buffs[25] = 5` [IL L23818].
- `EffectScript.damageEnemy` [IL L3760-4507] sets Ranger `buffs[7]`/`buffs[6]` = 10 [IL L4195, L4260];
  `EffectScript.myBoss` back-reference set in `createMyEffects`.
- Attack/special coroutines in `PartyMember` [IL L88337-105808] → `heal`, `calculateDamageMultiplier`,
  `calculateCrit`, `returnToNormal*`, `drainLife`, `adrenalineRush`, `pulse`, `flash`.
- `Congrats.Awake` → `congratsScreenInitialize()`.

Calls out:
- `EnemyScript.takeDamage(int, Vector3, PartyMember)` (Revenge reflect, Cleric aura, fire patch).
- `EnemyScript.requestPosition(int preferBack, PartyMember)` / `purgePosition(int)`.
- `EffectScript.activate(Vector3, Transform)`.
- `MotherBrain.defeatSequence()` [IL L75663-76802], `MotherBrain.disableActionBar()`; reads
  `motherBrain.enemyScripts`, `playerScripts`, `leaderScript`, `levelComplete`, `partyFormUp`,
  `disableSpecials`, `freezeUI`, `flashIcon`, `actionBarAnimation`, `edge`, `floor`, `cieling`,
  `buffMagnitudes`, `buffDurations`, `debuffMagnitudes`, `DB.tutorial`, `DB.soundEnabled`.
- `PetScript.Initialize()` / `RemoteUpdate()` [IL L105848, L105884].

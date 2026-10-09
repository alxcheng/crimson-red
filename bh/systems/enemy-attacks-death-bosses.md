# EnemyScript — attacks, special moves, death and boss sequences

**Scope:** class `EnemyScript`, IL lines 22091–32635 of `Assembly-UnityScript.il`: the non-coroutine helpers
`acquireRandomTarget`, `heal`, `handleDebuffs`, `clearAllAttackers`, `clearAllMeleeAttackers`, `muteSoundEffects`,
`targetHighestArmorPlayer`, `Main`, the coroutine stubs `completeLichSpawn`, `meleeAttack`, `omegaPunch`,
`enragedMeleeAttack`, `rangedAttack`, `castHeal`, and **all 28 nested coroutine classes** (`$stunBolt$1281` …
`$castHeal$1425`, L23399–32633). Field declarations/constructor (L5304–5472) were read for context.
The big `AI` method (L5703–16684), `takeDamage`, `spawn`, `requestPosition` etc. are **out of scope** (documented
elsewhere); where a coroutine depends on them this is said explicitly.

All citations are `[IL Lnnnnn]` = line numbers in the `.il` file.

## 1. Summary

This part of `EnemyScript` is everything an enemy *does* once the AI has decided to act, plus how it dies.

- **Basic actions** (§8): a melee swing (damage = `power`, reach 1.8), a ranged shot (launches projectile `fx[0]`), a
  healer's heal (restores `power` HP to another enemy, costs 1 mana), an enraged swing (3 × `power`) and a boss
  "omega punch" (2 × `power`, huge knockback). Each plays the `"attack"` clip, waits `meleeOffset` seconds (wind-up) and
  only lands if the enemy was not interrupted meanwhile.
- **Special moves** (§6): stun bolt, point-blank discharge (4.5 × `power` within 2.3), meteor storm / random meteors,
  earthquake / random boulders, chaos bolt, spit, teleport, web shot, summoning adds from the enemy pool, charge mode
  (invincible stampede) and bomb throw. Each is a short timed script that ends by resetting a `specialMoves[n]`
  cooldown and (in most cases) returning `AIState` to 0.
- **Death** (§7): the generic `die` clears debuffs and attackers, plays `"death"`, leaves the corpse 2 s, blinks it 7
  times (0.84 s) and parks the pooled object at x = 10. No loot is dropped here.
- **Boss deaths** (§9): goblin and spider bosses explode over 2.4 s, the lich over 4.7 s (flashes, screen shakes,
  full-screen flashes every 0.2 s); the ooze boss instead bursts after 1.3 s into up to six small oozes thrown to
  random spots.
- **Helpers** (§5): random targeting, taunt-to-highest-armor targeting, receiving heals, per-frame debuff/DoT ticking
  (DoTs cannot kill — they floor health at 0.1), detaching all party attackers.

## 2. Conventions used in this document

- `self` = the `EnemyScript` instance running the coroutine. `MB` = `self.motherBrain` (class `MotherBrain`).
  `players[i]` = `MB.playerScripts[i]` (array of `PartyMember`, 4 slots, slot may be null) — every loop over players
  in this file is `for i = 0; i < 4` and skips a slot unless `players[i]` is non-null **and** `players[i].health > 0`.
- `sm[n]` = `self.specialMoves[n]` (class `SpecialMove`, fields used here: `timer`, `cooldownMin`, `cooldownMax`).
  "reset sm[n]" means `sm[n].timer = Random.Range(sm[n].cooldownMin, sm[n].cooldownMax)` (float overload).
  The numeric cooldown values are Inspector data on each enemy prefab — **not in the IL**.
- `fx[n]` = `self.myEffects[n]` (`EffectScript`, instantiated in `initialize` from `myEffectsPrefabs[n]`
  [IL L5614-5651]). `fx[n].activate(pos, target)` = `EffectScript.activate(Vector3, Transform)`. Which visual / projectile
  each index is depends on the enemy prefab (Inspector data, not in the IL). What a projectile does on arrival (damage,
  debuff) is in `EffectScript`, **not** in this file.
- `snd[n]` = `self.mySounds[n].Play()`.
- "shake" = `MB.cameraShaker.Play("shake")` (an `Animation` on the camera rig).
- `player.takeDamage(dmg, knock, self)` = `PartyMember.takeDamage(int damage, Vector3 force, EnemyScript attacker)`.
  Armor/mitigation is applied inside `PartyMember.takeDamage` (out of scope). `dmg` values below are the **raw** values
  passed in. `(int)` = IL `conv.i4` (truncation toward zero).
- **Facing rule** ("face X"): if `self.x < X.x` and `localScale.x != -1` → `localScale.x = -1`; else if
  `self.x >= X.x` and `localScale.x != 1` → `localScale.x = 1`; after either flip call `updateHealthBar(1)`.
  So `localScale.x = -1` means "facing +x (right)" and `+1` means "facing left". Offsets written as
  `localScale.x * -k` therefore mean "k units in front of the enemy".
- World axes: `x` = left/right, `z` = up/down on the battlefield (depth), `y` = height (used to hide sprites:
  `y = 100` = invisible). Arena bounds are `MB.edge` (x from `-edge` to `+edge`), `MB.floor` and `MB.cieling` (sic) for z.
- `AIState` values seen in this file: `0` = normal/idle-seek (set at the end of most moves), `1` = set by
  `acquireRandomTarget` when no target was found (with `movementTarget = own position`), `3` = enraged (set by `enrage`),
  `4` = charge mode (set by `enterChargeMode`), `-100` = "busy / scripted, AI suspended" (set at the start of
  `discharge`, `earthquake`, `spitAttack` and tested by `targetHighestArmorPlayer`); `2` = set on the ooze boss by
  `oozeBossSplit` after it bursts.
  The full meaning of each state lives in `AI` (out of scope).
- The object is "parked" by setting `position.x = 10`; `remoteUpdate` does nothing while `x == 10` [IL L5667-5675].
- Layer `11` = the layer dead/untargetable enemies are moved to (`gameObject.layer = 11`). UNVERIFIED: layer 11 is
  ignored by the touch/target raycast — the raycast is not in this file.

## 3. Fields read or written by this code

Declared at [IL L5307-5391]; defaults from `.ctor` [IL L5394-5472].

| Field | Type | Default (.ctor) | Meaning in this code |
|---|---|---|---|
| `specialMoves` | `SpecialMove[]` | Inspector | per-enemy special-move slots; coroutines reset `timer` from `cooldownMin/Max` |
| `oozeBoss` | bool | false | true on ooze boss pieces; `remoteUpdate` then also runs `residualEffects` [IL L5693-5698] |
| `debuffs` | `float32[]` | Inspector size | remaining seconds per debuff id (see §5.3) |
| `myEffects` | `EffectScript[]` | built in `initialize` | effect/projectile pool per enemy |
| `mySounds` | `AudioSource[]` | Inspector | sound slots |
| `totalMeleeSounds` | int | 5 [IL L5403-5404] | (not used in scope) |
| `motherBrain` | `MotherBrain` | found in `initialize` [IL L5481-5487] | battle manager |
| `attackers` | int | 0 | number of party members attacking this enemy; zeroed on death / clear |
| `meleeSlot` | int | 0 | slot index this enemy holds around its target (`PartyMember.requestPosition`) |
| `colorSpeed` | float | 2.0 [IL L5406-5407] | speed of tint fade back to normal (used by `shaderAnimation`, out of scope) |
| `myRenderer` | Renderer | `geometry` child [IL L5499-5505] | `material.color` is tinted for flashes |
| `myTransform` | Transform | own | position / `localScale.x` facing |
| `myAnimation` | Animation | own | clip names quoted in each section |
| `power` | int | 30 [IL L5409-5410] | base damage stat; Inspector overrides per prefab |
| `impactForce` | float | 1.2 [IL L5412-5413] | knockback magnitude of normal melee hits |
| `health` | float | 1000 [IL L5415-5416] | current HP |
| `maxHealth` | int | 1000 [IL L5418-5419] | max HP |
| `healthTimer` | float | 0 | seconds the health bar stays visible |
| `healthVisible` | bool | false | health bar shown flag |
| `movementTarget` | Vector3 | – | AI walk target |
| `frictionConstant` | float | 10 | (not used in scope) |
| `myWeight` | float | 1 | (not used in scope) |
| `aoeRadiusBonus` | float | 0 (not set in `.ctor`; Inspector) | added to the 1.8 melee reach in `meleeAttack` [IL L31657-31663] |
| `spawningStyle` | int | 1 | (not used in scope; see `spawn`) |
| `myTargetScript` / `myTarget` | `PartyMember` / Transform | null | current target |
| `AIType` | int | 1 | (enemy archetype; used by `AI`) |
| `isMelee` | bool | true | melee enemies hold a slot around their target |
| `AIState` | int | 0 | see §2 |
| `actionTimer` | float | 0 | time since last basic action; zeroed by some moves |
| `moveSpeed` | float | 1.1 | (AI) |
| `runSpeedScale` | float | 1.2 | (AI) |
| `primaryActionCooldown` | float | 1.3 | (AI) seconds between basic attacks |
| `standingAnimLength` | float | 0.5 | (AI) |
| `tauntable` | bool | true | may be forced onto the highest-armor player |
| `run`, `basicAction`, `idle`, … | AnimationState | from clips `"run"`, `"attack"`, `"idle"`, `"spawn"`, `"paralyzed"`, `"fear"` [IL L5559-5608] | cached clip states |
| `invincible` | bool | false | damage immunity flag (checked in `takeDamage`, out of scope) |
| `specialDeath` | int | 0 | which death routine `takeDamage` starts (out of scope) |
| `i` | int | – | shared loop counter (hoisted to a field; coroutines share it!) |
| `randomValue` | int | – | scratch random |
| `bombVector` | Vector3 | – | scratch direction (discharge) / bomb landing point (throwBomb) |
| `bombLaunchPoint` | Vector3 | – | bomb start position |
| `bombFlightSpeed` | float | – | bomb speed, units/second |
| `webTarget` | `PartyMember` | null | victim chosen (by `AI`) for `webShot` |
| `ignoreDebuffColor` | bool | false | when true `handleDebuffs` does not apply `debuffColor` |
| `myHealTarget` | `EnemyScript` | null | chosen by `acquireHealTarget` (L17389, out of scope) for `castHeal` |
| `meleeOccupants` | `PartyMember[]` (6) | Inspector | party members standing in this enemy's 6 melee slots |
| `meleeOffset` | float | 0.21 [IL L5457-5458] | **seconds** from attack-animation start to the hit frame |
| `mana` | int | 50 | (not used in scope) |
| `debuffColor` | Color | (0.25,0.25,0.25) [IL L5462-5467] | current tint; (0.25,0.25,0.25) = "no debuff" |
| `mostRecentDebuff` | int | -1 | debuff id that owns `debuffColor` |
| `poisonMagnitude`, `meteorDotMagnitude`, `conflagDotMagnitude`, `baelDotMagnitude`, `plagueDotMagnitude`, `rangerDotMagnitude` | float | 0 | damage **per second** of each DoT (set by the party-side ability that applied it) |

## 4. Coroutine stubs in scope

Each of these only constructs the nested generator and returns its enumerator; the body is the `MoveNext` documented
in §6–§9.

| Stub | Lines | Body class |
|---|---|---|
| `completeLichSpawn()` | [IL L22093-22103] | `$completeLichSpawn$1405` |
| `meleeAttack()` | [IL L22261-22271] | `$meleeAttack$1408` |
| `omegaPunch()` | [IL L22274-22284] | `$omegaPunch$1413` |
| `enragedMeleeAttack()` | [IL L22287-22297] | `$enragedMeleeAttack$1417` |
| `rangedAttack()` | [IL L22300-22310] | `$rangedAttack$1422` |
| `castHeal()` | [IL L22313-22323] | `$castHeal$1425` |

The stubs of the other coroutines (`stunBolt(int)`, `discharge`, `meteorStorm`, `chaosBolt`, `dropMeteor1/2`,
`dropBoulder1/2`, `earthquake`, `enrage`, `spitAttack(int)`, `teleport`, `webShot`, `summonGoblinAdds`,
`summonSpiderAdds`, `enterChargeMode`, `throwBomb`, `die`, `oozeBossSplit`, `goblinBossDeath`, `lichBossDeath`,
`spiderBossDeath`) sit at L16687–19527 (see `bh/index/methods.md`); they are identical one-liners.

## 5. Non-coroutine helpers

### 5.1 `acquireRandomTarget()` [IL L22106-22258]

Picks **one** random party slot and targets it if valid — it does not retry.

1. If `myTargetScript` exists and `isMelee`: `myTargetScript.purgePosition(meleeSlot)` (release the old melee slot)
   [IL L22114-22127].
2. `myTarget = null; myTargetScript = null` [IL L22128-22133].
3. `r = Random.Range(0, 4)` (int overload → 0,1,2,3) [IL L22134-22137].
4. If `isMelee` and `players[r]` exists [IL L22138-22148]:
   - if `players[r].attackers < 4` and `players[r].health > 0` [IL L22150-22167]: `myTargetScript = players[r]`,
     `myTarget = its myTransform`, `meleeSlot = myTargetScript.requestPosition(0, self)`, `AIState = 0`; and if
     `basicAction.weight == 1` (attack clip fully playing) then `myAnimation.Play("idle")` [IL L22169-22201].
   - otherwise nothing (no target).
5. Else (not melee, or slot empty) — if `players[r]` exists and `health > 0`: target it, `AIState = 0`,
   `Play("idle")` [IL L22205-22241]. (No `attackers` cap for ranged enemies.)
6. If `myTarget == null` afterwards: `AIState = 1`, `movementTarget = own position` [IL L22243-22256].

### 5.2 `heal(int healAmount, EnemyScript whoHealedMe)` [IL L22326-22455]

Called on the enemy **receiving** a heal (see `castHeal`, §8.5).

1. `colorSpeed = 0.7`; `activateColors()`; set `myRenderer.material.color.g = 0.5` (green flash) [IL L22337-22366].
2. If `whoHealedMe.debuffs[14] > 0`: `healAmount = (int)(healAmount * MB.debuffMagnitudes[14])` [IL L22369-22386].
3. If `self.debuffs[17] > 0`: `healAmount = (int)(healAmount * MB.debuffMagnitudes[17])` [IL L22390-22407].
4. If `health > 0`: `health += healAmount` (a dead enemy is not revived) [IL L22411-22423].
5. Clamp `health` to `maxHealth` [IL L22424-22435].
6. `healthTimer = 2.6`; if not `healthVisible`: set it and `Play("showHealth")`; `updateHealthBar(0)` [IL L22436-22453].

`MB.debuffMagnitudes[]` values are MotherBrain data (out of scope). Debuff 14 on the healer and 17 on the recipient
are therefore "healing-reduction" debuffs.

### 5.3 `handleDebuffs()` [IL L22458-22834]

Called every frame from `remoteUpdate` while `health > 0` [IL L5684-5692].

1. If `debuffColor != (0.25, 0.25, 0.25)` and not `ignoreDebuffColor`: `activateColors()` and
   `material.color = debuffColor` (permanent tint while debuffed) [IL L22464-22484].
2. For every `i` in `0 .. debuffs.length-1` with `debuffs[i] > 0` [IL L22485-22497, L22820-22831]:
   1. `debuffs[i] -= Time.deltaTime` [IL L22499-22510].
   2. If `i` is a damage-over-time id, apply the tick [IL L22511-22795]:

      | `i` | magnitude field | lines |
      |---|---|---|
      | 0 | `poisonMagnitude` | [IL L22513-22556] |
      | 8 | `meteorDotMagnitude` | [IL L22558-22604] |
      | 9 | `conflagDotMagnitude` | [IL L22606-22652] |
      | 12 | `baelDotMagnitude` | [IL L22654-22700] |
      | 15 | `plagueDotMagnitude` | [IL L22702-22748] |
      | 16 | `rangerDotMagnitude` | [IL L22750-22795] |

      Tick (identical for all six): `health -= Time.deltaTime * magnitude`; **if `health <= 0` then `health = 0.1`**
      (a DoT can never kill an enemy; it leaves it at 0.1 HP); `updateHealthBar(0)`; if `healthTimer < 2.2` then
      `healthTimer = 2.2`; if not `healthVisible` → set true and `Play("showHealth")`.
   3. If the debuff has just expired (`debuffs[i] <= 0`) and `i == mostRecentDebuff`:
      `debuffColor = (0.25, 0.25, 0.25)`, `colorSpeed = 0.3` [IL L22795-22819].

### 5.4 `clearAllAttackers()` [IL L22837-22978]

1. If `myAnimation["hitReact"].speed != 1` set it to 1 [IL L22843-22858].
2. `meleeOccupants[0..5] = null`; `attackers = 0` [IL L22859-22883].
3. For each party slot 0..3 (no health check): if that member's `myTarget == self.myTransform` →
   `myTarget = null`, `myTargetEnemyScript = null` [IL L22889-22925]; if the member has a `petScript` whose
   `myTarget == self.myTransform` → `petScript.clearTarget()` [IL L22926-22965].

Used by `enterChargeMode` and the boss death/split sequences so that the party stops attacking.

### 5.5 `clearAllMeleeAttackers()` [IL L22981-23132]

Same as 5.4, except party members are only detached if `PartyMember.AIType == 3` [IL L23042-23050]
(UNVERIFIED: AIType 3 = melee party classes; the enum is in `PartyMember`). Pets are detached regardless.

### 5.6 `muteSoundEffects()` [IL L23135-23174]

If `MB.DB.soundEnabled` is false, set `volume = 0` on every `mySounds[i]`. Called at the end of `initialize` [IL L5653-5654].

### 5.7 `targetHighestArmorPlayer()` [IL L23177-23387]

1. `best` = index of the first living party member (0→3); then for every later living member with
   `defense > players[best].defense` (strictly greater), `best` = that index [IL L23186-23268].
2. If the enemy already has a target and `isMelee` [IL L23270-23277]: when `tauntable` **and** current target ≠
   `players[best]` **and** `players[best].attackers < 4` **and** `AIState != -100`: `purgePosition(meleeSlot)` on the old
   target, target `players[best]`, `meleeSlot = requestPosition(0, self)`, `AIState = 0` [IL L23279-23333].
3. Else if it has **no** target and `isMelee` and `tauntable` and `players[best].attackers < 4` and `AIState != -100`:
   same acquisition without the purge [IL L23336-23385].
4. Non-melee enemies are never retargeted by this function.

### 5.8 `Main()` [IL L23390-23397] — empty.

## 6. Special-move coroutines (boss / elite abilities)

Which enemy prefab owns which move is decided by the `AI` method's `AIType` branches and by Inspector data
(out of scope). The "used by" notes below are restricted to what this code proves (clip names, names of methods,
indices) — anything else is marked UNVERIFIED.

### 6.1 `stunBolt(int stunTarget)` — body [IL L23471-23849]

Instant single-target damage + stun. `stunTarget` = party slot index.

| t (s) | Step |
|---|---|
| 0 | reset sm[5] [IL L23499-23517]; `flash()` [IL L23518]; face `players[stunTarget]` [IL L23521-23664]; `actionTimer = 0`; `Stop("attack")`, `Play("attack")` [IL L23669-23684] |
| wait 0.2 | [IL L23684-23689] |
| 0.2 | `activateColors()`; `colorSpeed = 1`; `material.color = (0.1, 0.1, 0.1)` (dark flash); `snd[0]` [IL L23692-23714] |
| wait 0.35 | [IL L23714-23718] |
| 0.55 | `snd[2]`; `fx[2]` and `fx[3]` `localScale = (1,1,1)` then both `.activate(players[stunTarget].position, null)` [IL L23721-23785] |
| 0.55 | `players[stunTarget].takeDamage((int)(power * 0.75), (0,0,0), self)` [IL L23787-23808] |
| 0.55 | `players[stunTarget].buffs[25] = 5.0` → 5-second effect in party buff slot 25 (UNVERIFIED: slot 25 is the "stunned" status; the name `stunBolt` implies it, `PartyMember` defines it) [IL L23811-23821] |
| 0.55 | if `sm[2].timer < 6` then `sm[2].timer = 6` (delays special move 2 by at least 6 s) [IL L23821-23838] |
| 0.55 | `AIState = 0` [IL L23839-23842] |

No health/alive check on the target is done inside the coroutine.

### 6.2 `discharge()` — body [IL L23913-24152]

Point-blank area burst around the enemy with heavy knockback. Shares `fx[2]`/`fx[3]` and `snd[2]` with `stunBolt`
(same prefab).

| t (s) | Step |
|---|---|
| 0 | if `fx[2].localScale.x != 1.4`: set `fx[2]` and `fx[3]` `localScale = (1.4,1.4,1.4)` [IL L23928-23962] |
| 0 | `ignoreDebuffColor = false`; `AIState = -100`; `Play("discharge")`; `invincible = false`; `snd[2]` [IL L23963-23987] |
| 0 | `fx[2].activate(self.pos + (0,0,-0.1), null)`; `fx[3].activate(self.pos + (0,0,-0.1), null)` [IL L23987-24021] |
| 0 | for each living player with `Vector3.Distance(self.pos, player.pos) <= 2.3`: `bombVector = (player.pos - self.pos).normalized`; `player.takeDamage((int)(power * 4.5), bombVector * 10, self)` [IL L24023-24126] |
| wait 0.7 | [IL L24130-24134] |
| 0.7 | `CrossFade("idle")`; `AIState = 0` [IL L24137-24146] |

Radius **2.3**, damage **4.5 × power**, knockback magnitude **10**. Because step 1 clears `invincible` and
`ignoreDebuffColor`, the caller (in `AI`) evidently sets them during a charge-up phase before calling `discharge`
(UNVERIFIED — that code is in `AI`).

### 6.3 `meteorStorm()` — body [IL L24216-24338]

Only the "cast" animation; the meteors themselves are `dropMeteor1/2` (called from elsewhere, see 6.5).

| t (s) | Step |
|---|---|
| 0 | `snd[6]`; `Play("laugh")`; `flash()`; `fx[4].activate(self.pos + (0,0,-0.05), null)`; shake [IL L24229-24268] |
| wait 0.6 | [IL L24268-24273] |
| 0.6 | `sm[3].timer = 0`; `sm[3].cooldownMin = sm[3].cooldownMax` (after the first cast the storm's cooldown is always its max); reset sm[0] [IL L24276-24314] |
| wait 1.5 | [IL L24315-24319] |
| 2.1 | `AIState = 0`; `CrossFade("idle", 0.2)` [IL L24322-24328] |

### 6.4 `chaosBolt()` — body [IL L24406-24885]

Fires a homing/aimed projectile (`fx[0]`) at the highest-defense player in range.

1. `myTarget = null; myTargetScript = null` [IL L24435-24441].
2. Target selection loop over living players [IL L24443-24595]:
   - if a candidate is already chosen and `chosen.defense < players[i].defense`: switch to `players[i]` only if
     `Distance(players[i].pos, self.pos) < 2.5` [IL L24473-24535];
   - else if nothing is chosen yet and `Distance < 2.5`: choose `players[i]` [IL L24537-24582].
   Net effect: the **highest-`defense` living player within 2.5 units** (first one wins ties).
3. If nobody is within 2.5: `randomValue = Random.Range(0,4)`; if that slot is a living player, target it
   (one try only; may leave no target) [IL L24599-24656].
4. If there is no target the coroutine ends immediately (nothing else happens) [IL L24659-24663, L24879].
5. Otherwise:

| t (s) | Step |
|---|---|
| 0 | face `myTarget` [IL L24665-24801]; `actionTimer = 0`; `Play("attack")` [IL L24803-24810] |
| wait 0.2 | [IL L24813-24818] |
| 0.2 | `activateColors()`; `colorSpeed = 1`; `material.color = (0.1,0.1,0.1)`; `snd[0]` [IL L24821-24839] |
| wait 0.35 | [IL L24843-24847] |
| 0.55 | `fx[0].activate(self.pos + (localScale.x * -1, 0, 0), myTarget)` — projectile spawned 1 unit in front, homing on `myTarget` [IL L24850-24877] |

`chaosBolt` does not change `AIState` and does not reset any special-move timer; damage and flight speed are in
`EffectScript`. Note it overwrites `myTarget/myTargetScript` **without** purging the old melee slot.

### 6.5 `dropMeteor1()` / `dropMeteor2()` — bodies [IL L24950-25168] / [IL L25233-25451]

One meteor falling on a **uniformly random point of the arena** (not aimed at a player). The two methods are
byte-for-byte identical except for the sound and effect indices, so two meteors can be in flight at once.

| | `dropMeteor1` | `dropMeteor2` |
|---|---|---|
| start sound | `snd[3]` [IL L24965] | `snd[5]` |
| falling meteor effect | `fx[5]` [IL L24978] | `fx[8]` |
| impact effects | `fx[6]`, `fx[7]` [IL L25026-25053] | `fx[9]`, `fx[10]` |

| t (s) | Step (indices for `dropMeteor1`) |
|---|---|
| 0 | `snd[3]` [IL L24965] |
| wait 0.35 | [IL L24971-24975] |
| 0.35 | `fx[5].activate( (Random.Range(-MB.edge, MB.edge), 0, Random.Range(MB.floor, MB.cieling)), null )` [IL L24978-25005] |
| wait 0.27 | [IL L25007-25011] |
| 0.62 | `cameraShaker.Stop("shake")` then `Play("shake")`; `fx[6].activate(fx[5].position, null)`; `fx[7].activate(fx[5].position, null)` [IL L25014-25053] |
| 0.62 | for each living player with `Distance(fx[6].position, player.pos) <= 1.9`: `tempVector = (player.pos - fx[6].position).normalized`; `player.takeDamage(power, tempVector * 10, self)` [IL L25055-25158] |

Radius **1.9**, damage **1.0 × power**, knockback magnitude **10**. UNVERIFIED: these are fired repeatedly by `AI`
while the meteor storm is active (the caller is outside this range).

### 6.6 `dropBoulder1()` / `dropBoulder2()` — bodies [IL L25516-25712] / [IL L25777-25973]

Falling rock on a random arena point (the earthquake boss's version of the meteor). Identical pair; only effect
indices differ.

| | `dropBoulder1` | `dropBoulder2` |
|---|---|---|
| falling boulder effect | `fx[7]` [IL L25530] | `fx[8]` |
| impact effect / damage centre | `fx[5]` [IL L25585] | `fx[6]` |

| t (s) | Step (indices for `dropBoulder1`) |
|---|---|
| 0 | `fx[7].activate( (Random.Range(-MB.edge, MB.edge), 0, Random.Range(MB.floor, MB.cieling)), null )` [IL L25530-25557] |
| wait 0.8 | [IL L25559-25563] |
| 0.8 | `cameraShaker.Stop("shake")`, `Play("shake")`; `snd[6]`; `fx[5].activate(fx[7].position, null)` [IL L25566-25597] |
| 0.8 | for each living player with `Distance(fx[5].position, player.pos) <= 1.9`: `player.takeDamage(power, (player.pos - fx[5].position).normalized * 10, self)` [IL L25599-25700] |

Radius **1.9**, damage **1.0 × power**, knockback **10**, warning time **0.8 s**.

### 6.7 `earthquake()` — body [IL L26037-26161]

Stomp animation that starts the boulder phase (boulders are separate calls).

| t (s) | Step |
|---|---|
| 0 | `invincible = true`; `AIState = -100`; `Play("stomp")` [IL L26050-26063] |
| wait 0.67 | [IL L26063-26068] |
| 0.67 | `invincible = false`; shake; `snd[6]`; `fx[5].activate(self.pos, null)` [IL L26071-26097] |
| wait 0.63 | [IL L26099-26103] |
| 1.30 | `sm[3].timer = 0`; `sm[3].cooldownMin = sm[3].cooldownMax`; reset sm[0]; `AIState = 0`; `CrossFade("idle", 0.2)` [IL L26106-26149] |

The stomp itself deals **no damage** in this coroutine.

### 6.8 `enrage()` — body [IL L26225-26313]

| t (s) | Step |
|---|---|
| 0 | `Play("enrage")` [IL L26238] |
| wait 0.26 | [IL L26243-26248] |
| 0.26 | shake; `sm[2].timer = 10.0`; `snd[9]`; `fx[3].activate(self.pos + (0,0,-0.05), null)`; `debuffColor = (0.9, 0.25, 0.25)` (red tint, applied every frame by `handleDebuffs`) [IL L26251-26295] |
| wait 0.7 | [IL L26296-26300] |
| 0.96 | `AIState = 3` (enraged state — the AI then uses `enragedMeleeAttack`, §8.3; UNVERIFIED: the dispatch is in `AI`) [IL L26303-26306] |

`sm[2].timer = 10` — UNVERIFIED: this is the enrage duration counted by `AI`.

### 6.9 `spitAttack(int whichPlayerScript)` — body [IL L26391-26707]

Ranged spit at a specific party slot (ooze-type enemy: it uses the `"spit"` clip).

| t (s) | Step |
|---|---|
| 0 | `AIState = -100`; face `players[whichPlayerScript]` (here the second test is strictly `self.x > target.x`) [IL L26422-26569]; `Play("spit")` [IL L26574] |
| wait `meleeOffset` s | [IL L26579-26586] (default 0.21, Inspector may override) |
| +0 | if `fx[3].myTransform.position.z == 50` (i.e. projectile #3 is parked/idle) → use `fx[1]`, else use `fx[4]`: `.activate(self.pos + (localScale.x * -0.3, 0, 0), players[whichPlayerScript].myTransform)` [IL L26589-26662] |
| wait 0.7 | [IL L26671-26675] |
| +0.7 | `AIState = 0`; reset sm[0] [IL L26678-26700] |

UNVERIFIED: the test reads `fx[3]` but fires `fx[1]`; this may be an original bug (intended "if fx[1] is free use fx[1] else
fx[4]"). Port the literal behaviour or simply use a 2-projectile pool. Damage / puddle creation is in `EffectScript`
and `puddleDamage` (L17155, out of scope).

### 6.10 `teleport()` — body [IL L26771-26910]

| t (s) | Step |
|---|---|
| 0 | `Stop("attack")`, `Play("attack")` [IL L26783-26788] |
| wait `meleeOffset` s | [IL L26793-26800] |
| +0 | `snd[1]`; `fx[1].activate(self.pos, null)`; `fx[2].activate(self.pos, null)` (puff at the **old** position) [IL L26803-26829] |
| +0 | `position = ( Random.Range(-MB.edge + 0.7, MB.edge - 0.7), 0, Random.Range(MB.floor + 0.9, MB.cieling - 0.8) )` [IL L26831-26864] |
| +0 | `colorSpeed = 2`; `activateColors()`; `material.color = (1,1,1)` (white flash); reset sm[0] [IL L26865-26903] |

No `AIState` change, no target/slot bookkeeping.

### 6.11 `webShot()` — body [IL L26974-27050]

| t (s) | Step |
|---|---|
| 0 | reset sm[2] [IL L26987-27005] |
| wait 0.4 | [IL L27006-27010] |
| 0.4 | if `webTarget` is non-null: `fx[6].activate(self.pos, webTarget.myTransform)` (web projectile homing on the victim) [IL L27013-27028] |
| wait 0.76 | [IL L27033-27037] |
| 1.16 | `AIState = 0` [IL L27040-27043] |

`webTarget`, the animation and the `AIState` lock are set by the caller in `AI`. The web's effect on the victim is in
`EffectScript`.

### 6.12 `summonGoblinAdds()` — body [IL L27115-27292]

| t (s) | Step |
|---|---|
| wait 0.1 | [IL L27129-27133] |
| 0.1 | `snd[6]`; shake; `fx[3].activate(self.pos + (0, 0.5, 0), null)` [IL L27136-27165] |
| wait 0.1 | [IL L27167-27171] |
| 0.2 | `fx[4].activate(self.pos + (0, 0.5, 0), null)` [IL L27174-27190] |
| wait 1.13 | [IL L27192-27196] |
| 1.33 | **only if `self.health > 0`**: `MB.enemyScripts[6].spawn()` — if it returns true `MB.activeEnemies += 1`; same for `MB.enemyScripts[12]`; then `AIState = 0`; `Play("idle")`; reset sm[0] [IL L27199-27285] |

Summons **2** adds: pool slots **6 and 12** of `MotherBrain.enemyScripts`. `spawn()` (L21096, out of scope) returns
false if that pooled enemy is already in play, so an add that is still alive is not re-summoned. If the boss died
during the cast, nothing is spawned and `AIState` is left alone.

### 6.13 `summonSpiderAdds()` — body [IL L27357-27582]

| t (s) | Step |
|---|---|
| 0 | reset sm[1] [IL L27371-27389] |
| wait 0.1 | [IL L27390-27394] |
| 0.1 | `snd[9]`; shake; `fx[3].activate(self.pos + (0, 0.5, 0), null)` [IL L27397-27426] |
| wait 0.1 | [IL L27428-27432] |
| 0.2 | `fx[4].activate(self.pos + (0, 0.5, 0), null)` [IL L27435-27451] |
| wait 0.95 | [IL L27453-27457] |
| 1.15 | **only if `self.health > 0`**: `spawn()` pool slots **6, 7, 12, 13** (each success → `MB.activeEnemies += 1`); `AIState = 0`; `Play("idle")` [IL L27460-27570] |

Summons up to **4** adds.

(`summonSkeletonAdds`, L17541–17628, is a plain method outside this range.)

### 6.14 `enterChargeMode()` — body [IL L27646-27733]

| t (s) | Step |
|---|---|
| 0 | `snd[7]` [IL L27658] |
| wait 0.95 | [IL L27664-27668] |
| 0.95 | `sm[2].timer = 0`; `run.speed = 2.8` (run clip playback speed); `Play("run")`; `AIState = 4`; `invincible = true`; `gameObject.layer = 11` [IL L27671-27701] |
| 0.95 | if `myTargetScript`: `myTargetScript.purgePosition(meleeSlot)`; `myTargetScript = null`; `myTarget = null`; `clearAllAttackers()` [IL L27703-27724] |

The charging enemy is invincible and untargetable; the actual stampede movement/damage is `AIState 4` in `AI`
(uses the private `stampedeCounter` field; out of scope). The wind-up animation is started by the caller.

### 6.15 `throwBomb()` — body [IL L27797-27914]

| t (s) | Step |
|---|---|
| 0 | `snd[8]` [IL L27812] |
| wait 0.3 | [IL L27818-27822] |
| 0.3 | `fx[5].activate(self.pos + (localScale.x * -0.6, 0, 0), null)` (bomb appears 0.6 in front) [IL L27825-27849] |
| 0.3 | `sm[1].timer = 102.6` [IL L27851-27857] |
| 0.3 | `bombFlightSpeed = Distance(fx[5].position, bombVector) / 0.9` → the bomb reaches `bombVector` in **0.9 s** regardless of distance; `bombLaunchPoint = fx[5].position` [IL L27858-27883] |
| wait 0.65 | [IL L27884-27888] |
| 0.95 | if `health > 0`: `AIState = 0`; `Play("idle")` [IL L27891-27902] |

`bombVector` (the landing point) is chosen by the caller in `AI` before `throwBomb` starts, and the per-frame flight
and explosion are also in `AI` (it watches `sm[1].timer`, which is why it is set to the sentinel 102.6;
UNVERIFIED — inferred from the sentinel, the consumer is out of scope).

## 7. Death

### 7.1 `die()` — body [IL L28008-28912]

Generic death for every non-boss enemy (boss variants in §9 replace it). **There is no loot, gold or XP code in
`die`** — nothing is instantiated or awarded here. Rewards are handled by `MotherBrain` (out of scope).

| t (s) | Step |
|---|---|
| 0 | if `MB.arenaMode`: `MB.totalKills += 1`; `MB.updateScore()` [IL L28095-28111] |
| 0 | all `debuffs[i] = 0` [IL L28115-28145] |
| 0 | `meleeOccupants[0..5] = null`; `attackers = 0` [IL L28147-28186] |
| 0 | `gameObject.layer = 11` [IL L28187-28191] |
| 0 | `myAnimation.Stop()`; `Play("hideHealth")`; `Play("death")` [IL L28193-28202] |
| 0 | `MB.activeEnemies -= 1` [IL L28208-28218] |
| 0 | if `myTargetScript != null` and `isMelee`: `myTargetScript.purgePosition(meleeSlot)`; then `myTargetScript = null`, `myTarget = null` [IL L28219-28245] |
| wait 2.0 | corpse stays visible for 2 s [IL L28246-28250] |
| 2.0 → 2.84 | blink out: 7 × ( `position.y = 100` , wait 0.06 , `position.y = 0` , wait 0.06 ) — 14 waits of 0.06 s [IL L28253-28866] |
| 2.84 | `position.x = 10` (parked; `remoteUpdate` stops processing it) [IL L28869-28903] |

Notes: `die` does not touch `health`, does not clear the party members' `myTarget` pointers (they notice
`health <= 0` themselves, out of scope), and does not reset `AIState`. The pooled object is re-used later by `spawn()`.

## 8. Basic attack coroutines

All four start the same way: `Stop("attack")`, `Play("attack")`, `actionTimer = 0`, then **wait `meleeOffset` seconds**
(the wind-up; default 0.21 s [IL L5457-5458], per-prefab Inspector value) and only then re-validate and apply the hit.
The "still valid" guard uses `basicAction` (= the `"attack"` AnimationState [IL L5572-5577]): `basicAction.weight == 1`
and `basicAction.speed != 0` — i.e. the attack clip is still the fully-weighted playing clip (it was not interrupted by
a hit-react/knockdown/crossfade) and it is not frozen (UNVERIFIED: speed 0 = frozen by stun/paralyze, set elsewhere).
If the guard fails the attack silently does nothing. The cadence between attacks (`primaryActionCooldown`) is in `AI`.

### 8.1 `meleeAttack()` — body [IL L31569-31747]

| t (s) | Step |
|---|---|
| 0 | `Stop("attack")`; `Play("attack")`; `actionTimer = 0` [IL L31583-31598] |
| wait `meleeOffset` | [IL L31599-31605] |
| hit frame | Guard — ALL must hold, else end: `myTarget` non-null; `myTargetScript` non-null; `AIState == 0`; `health > 0`; `basicAction.weight == 1`; `basicAction.speed != 0`; `Distance(self.pos, myTarget.pos) <= 1.8 + aoeRadiusBonus` [IL L31608-31663] |
| hit frame | `randomMeleeSound = Random.Range(0, totalMeleeSounds)` (int; default 0..4); `mySounds[r].pitch = Random.Range(0.9, 1.1)`; `mySounds[r].Play()` [IL L31664-31687] |
| hit frame | `tempVector = (myTarget.pos - self.pos).normalized`; `myTargetScript.takeDamage(power, tempVector * impactForce, self)` [IL L31688-31716] |
| hit frame | if `myTarget` still non-null: `fx[0].activate(myTarget.pos + (0,0,-0.05), null)` (hit spark) [IL L31717-31739] |

**Damage = `power` (×1.0), knockback = unit vector away from the enemy × `impactForce` (default 1.2). Melee reach = 1.8
(+ `aoeRadiusBonus`).** Used by every `isMelee` enemy. For melee enemies, `mySounds[0 .. totalMeleeSounds-1]` are the
swing/impact sound variants.

### 8.2 `omegaPunch()` — body [IL L31812-32037]

Boss knock-away punch (heavy single-target hit that throws the victim across the arena and makes them drop the boss).

| t (s) | Step |
|---|---|
| 0 | `flash()`; `snd[9]`; `Stop("attack")`; `Play("attack")`; `actionTimer = 0` [IL L31827-31851] |
| wait `meleeOffset` | [IL L31852-31858] |
| hit frame | Guard (ALL): `myTarget`; `myTargetScript`; `AIState == 0`; `health > 0`; `basicAction.weight == 1`; `basicAction.speed != 0`. **No distance check.** If it fails skip to the 0.5 s wait [IL L31861-31897] |
| hit frame | `snd[10]`; shake [IL L31901-31912] |
| hit frame | `tempVector = (myTarget.pos - self.pos).normalized`; `myTargetScript.takeDamage(power * 2, tempVector * impactForce * 33, self)` (int multiply) [IL L31913-31945] |
| hit frame | if `myTargetScript.myTarget == self.myTransform` (victim was attacking this boss): `self.purgePosition(myTargetScript.meleeSlot)` (`EnemyScript.purgePosition`, L20939); `myTargetScript.myTarget = null`; `myTargetScript.myTargetEnemyScript = null`; `myTargetScript.AIState = 0` (victim goes idle) [IL L31948-31979] |
| hit frame | `fx[4].activate(myTarget.pos + (0,0,-0.05), null)`; reset sm[1] [IL L31980-32016] |
| wait 0.5 | (always, even if the guard failed) [IL L32017-32021] |
| +0.5 | `acquireRandomTarget()` (§5.1); `AIState = 4` [IL L32024-32030] |

**Damage = 2 × `power`; knockback magnitude = 33 × `impactForce`.** It always ends by picking a random new target and
entering `AIState 4` — the same state `enterChargeMode` sets — so it belongs to the charging boss
(UNVERIFIED which prefab; the `AI` branch for state 4 decides what happens next). Note `acquireRandomTarget` itself
writes `AIState` 0 or 1 and this is then overwritten with 4.

### 8.3 `enragedMeleeAttack()` — body [IL L32103-32256]

Same as `meleeAttack` with three differences: the guard requires **`AIState == 3`** (enraged, see §6.8) instead of 0,
it does not test `myTargetScript` for null nor the distance, and damage is tripled.

| t (s) | Step |
|---|---|
| 0 | `Stop("attack")`; `Play("attack")`; `actionTimer = 0` [IL L32117-32132] |
| wait `meleeOffset` | [IL L32133-32139] |
| hit frame | Guard (ALL): `myTarget`; `AIState == 3`; `health > 0`; `basicAction.weight == 1`; `basicAction.speed != 0` [IL L32142-32173] |
| hit frame | random melee sound exactly as §8.1 (pitch 0.9–1.1) [IL L32177-32200] |
| hit frame | `myTargetScript.takeDamage(power * 3, (myTarget.pos - self.pos).normalized * impactForce, self)` [IL L32201-32229] |
| hit frame | `fx[0].activate(myTarget.pos + (0,0,-0.05), null)` [IL L32232-32248] |

**Damage = 3 × `power`**, normal knockback, **no range check** (hits from any distance if the clip completes).

### 8.4 `rangedAttack()` — body [IL L32320-32428]

| t (s) | Step |
|---|---|
| 0 | `Stop("attack")`; `Play("attack")`; `actionTimer = 0` [IL L32334-32349] |
| wait `meleeOffset` | [IL L32350-32356] |
| release | Guard (ALL): `myTarget`; `AIState == 0`; `health > 0`; `basicAction.weight == 1`; `basicAction.speed != 0` [IL L32359-32389] |
| release | `fx[0].activate(self.pos + (-localScale.x * 0.5, 0, 0), myTarget)` — projectile `fx[0]` launched 0.5 units in front of the enemy, with `myTarget` as its target transform [IL L32393-32418] |

No damage is applied here: the projectile's speed, homing and on-hit `takeDamage` are in `EffectScript` (out of
scope) — **projectile speed is therefore not determinable from this file**. One projectile object per enemy (`fx[0]`) is
re-used for every shot. No sound is played here.

### 8.5 `castHeal()` — body [IL L32492-32629]

Enemy healer's action (heals another enemy, `myHealTarget`, chosen by `acquireHealTarget` L17389).

| t (s) | Step |
|---|---|
| 0 | `mana -= 1` [IL L32504-32511]; `Stop("attack")`; `Play("attack")`; `actionTimer = 0` [IL L32512-32527] |
| 0 | `colorSpeed = 1.5`; `activateColors()`; `material.color = (0.8, 0.8, 0.8)` (bright flash) [IL L32528-32543] |
| wait `meleeOffset` | [IL L32544-32550] |
| cast | Guard (ALL): `myHealTarget` non-null; `AIState == 0`; `myHealTarget.health > 0`; `basicAction.weight == 1`; `self.health > 0`; `basicAction.speed != 0` [IL L32553-32591] |
| cast | `myHealTarget.heal(power, self)` (§5.2) → **heal amount = healer's `power`**, reduced by debuff 14 on the healer / 17 on the recipient [IL L32595-32603] |
| cast | `fx[0].activate(myTarget.position, myTarget)`; `snd[0]` [IL L32604-32622] |

Mana is spent (1 per cast, default pool 50 [IL L5459-5461]) at the start even if the heal later fails the guard. The
effect is positioned on `myTarget` (a Transform), not on `myHealTarget` — UNVERIFIED: `acquireHealTarget` sets
`myTarget` to the heal target's transform (it is outside this range). No `mana > 0` check exists in this coroutine.

## 9. Boss death / phase sequences

`takeDamage` (L18393, out of scope) chooses the routine from `specialDeath` when health reaches 0:

| `specialDeath` | Routine started | Dispatch lines |
|---|---|---|
| 1 | `goblinBossDeath()` | [IL L18949-18955] |
| 2 | `spiderBossDeath()` | [IL L18961-18967] |
| 3 | `oozeBossSplit()` | [IL L18973-18979] |
| 4 | `lichBossDeath()` | [IL L18985-18991] |
| 5 | `MB.enemyScripts[0].maxHealth -= 1500`; `MB.enemyScripts[1].health -= 1500`; then `die()` | [IL L18997-19032] |
| other (0) | `die()` | [IL L19039] |

Boss levels in `bh/data/maps.json` (by `enemySet`): `boar` = "The Squealing Bog" (map 0), `spider` = "The Silken
Wildwood" (map 0), `oozeBoss` = "The Oozing Dark" (map 1), `golem` = "The Earthen Gate" (map 1), `lich` = "Throne of
Ruin" (map 3). UNVERIFIED: mapping of `specialDeath` values to those prefabs is by method name only (goblin→boar set,
spider, ooze, lich); `specialDeath` is Inspector data.

**Common opening block** (identical in the four boss routines; referred to as "boss cleanup" below):
all `debuffs[i] = 0`; `meleeOccupants[0..5] = null`; `attackers = 0`; `gameObject.layer = 11`; `myAnimation.Stop()`;
`Play("hideHealth")`; `Play("death")`; if `myTargetScript != null` → `myTargetScript.purgePosition(meleeSlot)`
(no `isMelee` test, and the target pointers are **not** nulled, unlike `die`).
`FSF` = `MB.fullScreenFlash.activate((0, 4.2, -7), null)` (white full-screen flash effect at a fixed camera-space
position). `shake!` = `cameraShaker.Stop("shake")` then `Play("shake")` (restart). `flash()` = `EnemyScript.flash`
(L17683, sprite white-flash).

None of the boss routines increments `MB.totalKills`, awards loot/gold/XP, or ends the level — they only decrement
`MB.activeEnemies`; `MotherBrain` reacts to that (out of scope).

### 9.1 `oozeBossSplit()` — body [IL L28976-29423]

The big ooze "dies" and bursts into up to 6 small oozes that are flung to random spots.

| t (s) | Step |
|---|---|
| 0 | `invincible = true`; `snd[6]`; FSF; shake!; `flash()` [IL L28988-29025] |
| 0 | all `debuffs = 0`; `debuffColor = (0.25,0.25,0.25)`; `colorSpeed = 0.3` [IL L29026-29068] |
| 0 | rest of boss cleanup (occupants, `attackers = 0`, layer 11, `Stop()`, `"hideHealth"`, `"death"`, purge slot) [IL L29069-29144] |
| wait 1.3 | [IL L29145-29149] |
| 1.3 | `clearAllAttackers()`; `fx[2].activate(self.pos, null)`; `snd[5]`; `self.AIState = 2`; `MB.activeEnemies -= 1` [IL L29152-29185] |
| 1.3 | for `i = 6 .. 11` (pool slots `MB.enemyScripts[6..11]`), **only if `e.health > 0`** [IL L29186-29204, L29398-29410]: |
| | • `e.position = self.position`; `e.AIState = 1`; `e.myAnimation.Play("knockdown")` [IL L29205-29240] |
| | • landing z: `Random.Range(0,2) == 0` → `e.bombVector.z = Random.Range(1.5, MB.cieling)`, else `Random.Range(MB.floor, -0.5)` [IL L29240-29279] |
| | • landing x: `Random.Range(0,2) == 0` → `e.bombVector.x = Random.Range(1.2, MB.edge)`, else `Random.Range(-MB.edge, -1.2)` [IL L29280-29319] |
| | • `e.bombFlightSpeed = Distance(e.position, e.bombVector) / 0.4` (reaches the landing point in **0.4 s**) [IL L29320-29350] |
| | • `e.specialMoves[0].timer = 0`; `e.invincible = false`; `e.myRenderer.enabled = true`; `e.gameObject.layer = 10` (targetable layer) [IL L29351-29397] |
| 1.3 | `self.myRenderer.enabled = false` (boss sprite hidden; object is **not** parked at x = 10) [IL L29412-29416] |

Notes: the small oozes are pre-existing pooled enemies in slots 6–11 (wave data for "The Oozing Dark" lists six type-2
enemies after the boss: `[1,2,2,2,2,2,2]`, `bh/data/maps.json`); this routine does not call `spawn()` and does not
increment `activeEnemies` for them — they must already be counted/alive (`health > 0`) but hidden and invincible
(UNVERIFIED: set up by `spawn`/`AI`). `e.bombVector.y` is not written here. The flight to `bombVector` at
`bombFlightSpeed` is performed by the small ooze's `AI` in `AIState 1` (out of scope). The boss ends in
`AIState = 2` with `invincible = true`; `oozeBoss`-flagged objects keep running `residualEffects` (L16818) from
`remoteUpdate` [IL L5693-5698].

### 9.2 `goblinBossDeath()` — body [IL L29489-29991]

2.4-second explosion sequence, a step every 0.2 s.

| t (s) | Step | Lines |
|---|---|---|
| 0.0 | `snd[9]`; `snd[11]` (looping rumble, stopped at 2.2); FSF; shake!; `flash()`; boss cleanup | [IL L29517-29664] |
| 0.2 | `flash()` | [IL L29672] |
| 0.4 | `flash()`; shake! | [IL L29682-29696] |
| 0.6 | `flash()` | [IL L29705] |
| 0.8 | `flash()`; shake!; FSF; `snd[10]` | [IL L29715-29748] |
| 1.0 | `flash()` | [IL L29756] |
| 1.2 | `flash()` | [IL L29766] |
| 1.4 | `flash()`; shake! | [IL L29776-29790] |
| 1.6 | `flash()`; shake!; FSF; `snd[10]` | [IL L29799-29832] |
| 1.8 | `flash()` | [IL L29840] |
| 2.0 | `flash()` | [IL L29850] |
| 2.2 | shake!; FSF; `mySounds[11].Stop()`; `snd[10]`; `fx[1].activate(self.pos, null)`; `fx[2].activate(self.pos, null)`; `snd[5]`; `snd[7]`; `position.x = 10` (boss removed) | [IL L29860-29965] |
| 2.4 | `MB.activeEnemies -= 1` | [IL L29975-29984] |

Every wait is `WaitForSeconds(0.2)` [IL L29665, 29675, 29697, 29708, 29749, 29759, 29769, 29791, 29833, 29843, 29853, 29966].

### 9.3 `lichBossDeath()` — body [IL L30057-30820]

Final boss; same pattern, twice as long (4.7 s).

| t (s) | Step | Lines |
|---|---|---|
| 0.0 | `mySounds[8].pitch = 1`; `snd[7]`; `snd[9]` (loop, stopped at 4.4); FSF; shake!; `flash()`; boss cleanup | [IL L30096-30251] |
| 0.2 | `flash()` | [IL L30259] |
| 0.4 | `flash()`; shake! | [IL L30269-30283] |
| 0.6 | `flash()` | [IL L30292] |
| 0.8 | `flash()`; shake!; FSF; `snd[8]` | [IL L30302-30335] |
| 1.0 | `flash()` | [IL L30343] |
| 1.2 | `flash()` | [IL L30353] |
| 1.4 | `flash()`; shake! | [IL L30363-30377] |
| 1.6 | `flash()`; shake!; FSF; `snd[8]` | [IL L30386-30419] |
| 1.8 | `flash()` | [IL L30427] |
| 2.0 | `flash()` | [IL L30437] |
| 2.2 | shake!; FSF; `snd[8]` (no `flash()`) | [IL L30447-30477] |
| 2.4 | `flash()` | [IL L30485] |
| 2.6 | `flash()`; shake! | [IL L30495-30509] |
| 2.8 | `flash()` | [IL L30518] |
| 3.0 | `flash()`; shake!; FSF; `snd[8]` | [IL L30528-30561] |
| 3.2 | `flash()` | [IL L30569] |
| 3.4 | `flash()` | [IL L30579] |
| 3.6 | `flash()`; shake! | [IL L30589-30603] |
| 3.8 | `flash()`; shake!; FSF; `snd[8]` | [IL L30612-30645] |
| 4.0 | `flash()` | [IL L30653] |
| 4.2 | `flash()` | [IL L30663] |
| 4.4 | shake!; FSF; `mySounds[9].Stop()`; `fx[11]`, `fx[12]`, `fx[6]`, `fx[7]` each `.activate(self.pos, null)`; `snd[10]`; `snd[6]`; `position.x = 10` | [IL L30673-30794] |
| wait 0.3 | (the only non-0.2 wait) | [IL L30795-30801] |
| 4.7 | `MB.activeEnemies -= 1` | [IL L30804-30813] |

(`fx[6]`/`fx[7]` are the lich's `dropMeteor1` impact effects re-used as the final explosion.)

### 9.4 `spiderBossDeath()` — body [IL L30886-31376]

Identical schedule to `goblinBossDeath` (2.4 s, 0.2 s steps); only sound indices and the final step differ.

| t (s) | Step | Lines |
|---|---|---|
| 0.0 | `snd[5]`; `snd[8]` (loop, stopped at 2.2); FSF; shake!; `flash()`; boss cleanup | [IL L30914-31061] |
| 0.2 | `flash()` | [IL L31069] |
| 0.4 | `flash()`; shake! | [IL L31079-31093] |
| 0.6 | `flash()` | [IL L31102] |
| 0.8 | `flash()`; shake!; FSF; `snd[7]` | [IL L31112-31145] |
| 1.0 | `flash()` | [IL L31153] |
| 1.2 | `flash()` | [IL L31163] |
| 1.4 | `flash()`; shake! | [IL L31173-31187] |
| 1.6 | `flash()`; shake!; FSF; `snd[7]` | [IL L31196-31229] |
| 1.8 | `flash()` | [IL L31237] |
| 2.0 | `flash()` | [IL L31247] |
| 2.2 | shake!; FSF; `mySounds[8].Stop()`; `fx[1].activate(self.pos, null)`; `fx[2].activate(self.pos, null)`; `snd[6]`; `position.x = 10` | [IL L31257-31350] |
| 2.4 | `MB.activeEnemies -= 1` | [IL L31360-31369] |

### 9.5 `completeLichSpawn()` — body [IL L31440-31503]

End of the lich's entrance (started from `spawn`, L21096, out of scope).

| t (s) | Step |
|---|---|
| wait 0.3 | [IL L31452-31456] |
| 0.3 | `position = (1.2, 0, 0.3)` (fixed arena spot); `activateColors()`; `material.color = (0, 0, 0)` (appears black and fades to normal); `colorSpeed = 1.5`; `Play("idle")`; `AIState = 0` (AI starts) [IL L31459-31496] |

## 10. Lookup tables

### 10.1 Damage / radius summary (raw values passed to `PartyMember.takeDamage`)

| Move | Damage | Area / reach | Knockback vector | Extra | Lines |
|---|---|---|---|---|---|
| `meleeAttack` | `power` | target within `1.8 + aoeRadiusBonus` | dir × `impactForce` | – | [IL L31657-31716] |
| `enragedMeleeAttack` | `power * 3` | no range check | dir × `impactForce` | needs `AIState == 3` | [IL L32148-32229] |
| `omegaPunch` | `power * 2` | no range check | dir × `impactForce` × 33 | victim drops the boss; boss retargets randomly, `AIState = 4` | [IL L31928-32030] |
| `stunBolt` | `(int)(power * 0.75)` | single chosen slot | (0,0,0) | `buffs[25] = 5.0` on victim | [IL L23787-23821] |
| `discharge` | `(int)(power * 4.5)` | all players within 2.3 of boss | dir × 10 | – | [IL L24067-24115] |
| `dropMeteor1/2` | `power` | all players within 1.9 of impact | dir × 10 | random arena point, 0.27 s after the meteor appears | [IL L25102-25147] |
| `dropBoulder1/2` | `power` | all players within 1.9 of impact | dir × 10 | random arena point, 0.8 s warning | [IL L25646-25689] |
| `castHeal` | heals `power` to `myHealTarget` | – | – | costs 1 mana | [IL L32595-32603] |
| `rangedAttack`, `chaosBolt`, `spitAttack`, `webShot`, `throwBomb` | not in this file (applied by `EffectScript` / `AI`) | | | | |

### 10.2 `specialMoves[]` indices touched, per coroutine

| Coroutine | Writes |
|---|---|
| `stunBolt` | reset sm[5]; `sm[2].timer = max(sm[2].timer, 6)` |
| `meteorStorm` | `sm[3].timer = 0`, `sm[3].cooldownMin = cooldownMax`; reset sm[0] |
| `earthquake` | `sm[3].timer = 0`, `sm[3].cooldownMin = cooldownMax`; reset sm[0] |
| `enrage` | `sm[2].timer = 10` |
| `spitAttack` | reset sm[0] |
| `teleport` | reset sm[0] |
| `webShot` | reset sm[2] |
| `summonGoblinAdds` | reset sm[0] |
| `summonSpiderAdds` | reset sm[1] |
| `enterChargeMode` | `sm[2].timer = 0` |
| `throwBomb` | `sm[1].timer = 102.6` |
| `omegaPunch` | reset sm[1] |
| `oozeBossSplit` | `sm[0].timer = 0` on each small ooze |

Slot numbers are per-prefab: e.g. the prefab with `enterChargeMode`/`omegaPunch`/`summonGoblinAdds` uses sm[0] =
summon, sm[1] = punch, sm[2] = charge; the prefab with `webShot`/`summonSpiderAdds` uses sm[1] = summon, sm[2] = web
(grouping UNVERIFIED — inferred from consistent, non-clashing index use and method names; the authoritative
dispatch is the `AI` method).

### 10.3 Animation clip names used

`"attack"`, `"idle"`, `"run"`, `"death"`, `"hideHealth"`, `"showHealth"`, `"hitReact"`, `"knockdown"`, `"discharge"`,
`"laugh"`, `"stomp"`, `"enrage"`, `"spit"`; camera: `"shake"`.

### 10.4 Debuff ids referenced in this range

| id | Use | Lines |
|---|---|---|
| 0 | poison DoT (`poisonMagnitude`/s) | [IL L22513-22523] |
| 8 | meteor DoT | [IL L22558-22571] |
| 9 | conflagrate DoT | [IL L22606-22619] |
| 12 | "bael" DoT | [IL L22654-22667] |
| 14 | on the **healer**: its heals are multiplied by `MB.debuffMagnitudes[14]` | [IL L22369-22386] |
| 15 | plague DoT | [IL L22702-22715] |
| 16 | ranger DoT | [IL L22750-22763] |
| 17 | on the **recipient**: heals received multiplied by `MB.debuffMagnitudes[17]` | [IL L22390-22407] |

Party-side: `PartyMember.buffs[25] = 5.0` is written by `stunBolt` [IL L23811-23821].

## 11. Uncertain / not determined

- **Which enemy prefab uses which coroutine** is not stated in this range. It is decided in `AI` (L5703–16684) by
  `AIType` and by Inspector data (`specialMoves`, `specialDeath`, `myEffectsPrefabs`). All "used by" statements above
  that go beyond method/clip names are UNVERIFIED.
- **Projectile speeds and projectile damage** (`rangedAttack`, `chaosBolt`, `spitAttack`, `webShot`) are in
  `EffectScript`, not here. The only speeds computed in this range are `bombFlightSpeed = distance / 0.9` (`throwBomb`)
  and `distance / 0.4` (ooze split).
- **Loot / gold / XP drops:** no code in this range instantiates loot or awards anything. `die` and the boss routines
  only change `MB.activeEnemies` (and `MB.totalKills` + `updateScore()` in arena mode, `die` only). Any older note
  describing a "loot-drop sequence inside `die`" is **not supported by the IL**.
- `SpecialMove.cooldownMin/Max`, `power`, `maxHealth`, `meleeOffset`, `impactForce`, `aoeRadiusBonus` per enemy are
  Inspector values (not in the IL, not in `bh/data`). Only the `.ctor` defaults are known.
- `MB.debuffMagnitudes[14]`, `[17]`, `MB.edge`, `MB.floor`, `MB.cieling` values: defined in `MotherBrain`.
- Meaning of `PartyMember.buffs[25]` (assumed stun) and `PartyMember.AIType == 3` (assumed melee) — defined in `PartyMember`.
- Meaning of layers 10 and 11 (assumed targetable / untargetable).
- `spitAttack` tests `fx[3]` but fires `fx[1]`/`fx[4]` — possibly an original bug; reproduced literally above.
- `castHeal` places its effect on `myTarget`, not `myHealTarget`.
- `targetHighestArmorPlayer`: if no party member is alive `best` stays −1 and the second loop indexes
  `playerScripts[-1]` (would throw) [IL L23186-23250]; presumably never called in that situation.
- Shared loop counter: every coroutine uses the instance field `EnemyScript.i` as its loop variable (the same field
  `handleDebuffs` uses each frame). Loops here contain no `yield`, so they do not interleave.
- Contradictions with older notes: `work/*.md` and datamine `docs/*.md` were not consulted line-by-line; the only
  claim checked is the task brief's "death/loot-drop sequence" — there is no loot drop in `EnemyScript` L22091–32635.

## 12. Cross-references

| Called from this range | Where |
|---|---|
| `EnemyScript.flash()` | L17683–17703 |
| `EnemyScript.activateColors()` | L18374–18390 |
| `EnemyScript.updateHealthBar(int)` | L19530–19937 |
| `EnemyScript.spawn()` (returns bool) | L21096–22090 |
| `EnemyScript.purgePosition(int)` | L20939–21093 |
| `EnemyScript.acquireHealTarget()` (sets `myHealTarget`) | L17389–17525 |
| `EnemyScript.takeDamage` (starts `die` / boss deaths via `specialDeath`) | L18393–19181, dispatch L18949–19039 |
| `EnemyScript.AI` (starts every attack/special coroutine; owns `AIState` semantics, bomb flight, charge, meteor/boulder cadence) | L5703–16684 |
| `EnemyScript.remoteUpdate` (calls `handleDebuffs`, skips parked enemies) | L5659–5700 |
| `EnemyScript.residualEffects`, `puddleDamage`, `summonSkeletonAdds` (related, out of range) | L16818, L17155, L17541 |
| `PartyMember.takeDamage(int, Vector3, EnemyScript)`, `requestPosition(int, EnemyScript)`, `purgePosition(int)`; fields `health`, `defense`, `attackers`, `buffs[]`, `myTarget`, `myTargetEnemyScript`, `meleeSlot`, `AIState`, `AIType`, `petScript`, `myTransform` | class `PartyMember` (see `bh/index/methods.md`) |
| `PetScript.clearTarget()`, `PetScript.myTarget` | class `PetScript` |
| `MotherBrain`: `playerScripts[]`, `enemyScripts[]`, `activeEnemies`, `totalKills`, `arenaMode`, `updateScore()`, `cameraShaker`, `fullScreenFlash`, `edge`, `floor`, `cieling`, `debuffMagnitudes[]`, `DB.soundEnabled` | class `MotherBrain` |
| `EffectScript.activate(Vector3, Transform)`, `EffectScript.myTransform`, `EffectScript.myEnemyBoss` (set in `initialize` [IL L5633-5639]) | class `EffectScript` |
| `SpecialMove.timer / cooldownMin / cooldownMax` | class `SpecialMove` |

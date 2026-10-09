# Hero active abilities, part 1 — `PartyMember.performSpecial` (Cleric, Knight, Rogue, Wizard, Witch 1–4)

**Scope:** class `PartyMember`, coroutine body `$performSpecial$1850` → nested `$::MoveNext`, IL lines
**93226–99788** of `/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`.
The assigned range was 93226–99500; the Witch ability *Horror* straddles line 99500, so it was read to
its end. **This document stops at IL L99788** (the `br` that ends Horror). The next instruction,
**L99790**, is the start of Witch ability 5 (*Hex*) and belongs to part 2 (99790–105808).

All numbers are float32 literals rounded to their intended decimal (e.g. IL `0.69999998807907104` is
written `0.7`). Positions/distances are Unity world units. `[IL Lxxxxx]` = line in the .il file.

---

## 1. Summary

When the player taps one of a hero's (up to three) ability buttons, `MotherBrain.specialMove(slot)`
plays a short "power-up" freeze, starts the cooldown, then starts the coroutine
`PartyMember.performSpecial(slot)` on the selected hero. `performSpecial` is one giant
`if characterClass == N … if abilities[slot] == K …` ladder: 10 classes × 5 active abilities.
Each branch plays an animation and a sound, waits a few tenths of a second, and then does one of:

* heal / buff party members (Cleric),
* set a timed entry in the hero's own `buffs[]` array that *other* code (melee attack, takeDamage, AI)
  reacts to (Knight Shield Wall / Shield Rush, Rogue Sneak Attack / Expose Weakness / Shadowstep,
  Cleric angels),
* loop over `MotherBrain.enemyScripts[]` and damage / debuff every enemy inside an axis-aligned box
  (Cleave, Intimidate, Meteor, Thunderbolt, Plague, Horror) or every enemy on screen (Blizzard,
  Time Stop, War Cry),
* hit the hero's current target (Conflagrate, Drain Life, Debilitate) or launch a projectile
  `EffectScript` at it (Rogue knives).

Abilities that need an enemy target and have none set `specialAwaitingTarget = slot`; the hero's `AI`
re-runs `performSpecial(slot)` as soon as a target exists. This part covers class ids 1–4 completely
and class 5 (Witch) abilities 1–4.

---

## 2. Dispatch

### 2.1 How the code selects an ability

1. `performSpecial(int specialSlot)` only builds the coroutine object [IL L86025-86036].
2. `MoveNext` starts with a `switch` on the coroutine `_state` with 91 resume labels [IL L93497-93590];
   state 0 (first entry) goes to `IL_0177` [IL L93591].
3. First entry: `tempVector = Vector3.zero`, `i = 0` [IL L93591-93596].
4. Class ladder: `if (self.characterClass == C)` for C = 1,2,3,… in order
   [IL L93597-93601, L94392-94396, L96077-96081, L96772-96776, L98323-98327].
5. Inside a class: `if (self.abilities[specialSlot] == K)` for K = 1..5 in order
   (e.g. [IL L93603-93610], [IL L93813-93820]).
6. Every branch ends by jumping to the common exit `IL_9acc` (`YieldDefault(1)`; coroutine finished)
   [IL L94390, L96075, L96770, L98321, L105798-105803].

### 2.2 Id encodings (needed to read the table)

| Thing | Encoding | Source |
|---|---|---|
| `characterClass` | **1-based**: `classes.json` id + 1. 1 Cleric, 2 Knight, 3 Rogue, 4 Wizard, 5 Witch, 6 Bard, 7 Barbarian, 8 Monk, 9 Ranger, 10 Paladin | `powerDB[characterClass - 1]` [IL L59855-59866] |
| `abilities[slot]` value K | 0 = slot empty; 1,2,3 → `whichPower[0,1,2]`; 4,5 → `whichPower[5,6]` | cooldown lookup uses `whichPower[0]` for slot 0, `whichPower[abilities[1]-1]` for slot 1, `whichPower[abilities[2]+1]` for slot 2 [IL L59939-60061]; empty check [IL L59979, L60024, L72040-72047] |
| slot ↔ K | slot 0 holds K=1; slot 1 holds K=2 or 3; slot 2 holds K=4 or 5. UNVERIFIED as a hard rule (it is what the cooldown lookup above and the `specialAwaitingTarget` values written below assume: K=1→0, K=2/3→1, K=4/5→2) | [IL L59939-60061], e.g. [IL L96204-96207, L96284-96287, L97251-97254] |
| `passives[n]` | n=0: talent pair `whichPower[3]`(+1) / `whichPower[4]`(−1); n=1: `whichPower[7]`(+1) / `whichPower[8]`(−1); n=2: `whichPower[9]` — set to 1 when hero level ≥ 25, else 0; n=3: `whichPower[10]`(+1) / `whichPower[11]`(−1). 0 = not chosen | sign mapping read from `initialize`: Knight `passives[0]==-1` → power×1.15 (Might, idx 4), `==1` → defense×1.15 (Chivalry, idx 3) [IL L77550-77587]; Rogue `passives[1]==-1` → moveSpeed×1.15 (Pursuit, idx 8), `==1` → defense×1.15 (Combat Tactics, idx 7) [IL L77624-77661]; Rogue `passives[3]==-1` → power×1.10 (Aggression, idx 11) [IL L77588-77605]; level-25 rule [IL L59894-59925] |

### 2.3 Dispatch table

Cooldowns are `classes.json → whichPower[].cooldown` (seconds).

| characterClass | abilities[slot] | Ability (`classes.json` power idx) | Cooldown s | IL lines |
|---|---|---|---|---|
| 1 Cleric | 1 | Group Heal (0) | 20 | 93603–93811 |
| 1 Cleric | 2 | Shield (1) | 30 | 93813–93989 |
| 1 Cleric | 3 | Power Infusion (2) | 30 | 93991–94167 |
| 1 Cleric | 4 | Guardian Angel (5) | 60 | 94169–94276 |
| 1 Cleric | 5 | Vengeful Angel (6) | 60 | 94278–94389 |
| 2 Knight | 1 | Shield Wall (0) | 30 | 94398–94529 |
| 2 Knight | 2 | Cleave (1) | 30 | 94531–95304 |
| 2 Knight | 3 | Intimidate (2) | 30 | 95306–95653 |
| 2 Knight | 4 | War Cry (5) | 30 | 95655–96046 |
| 2 Knight | 5 | Shield Rush (6) | 30 | 96048–96075 |
| 3 Rogue | 1 | Sneak Attack (0) | 20 | 96083–96106 |
| 3 Rogue | 2 | Expose Weakness (1) | 30 | 96108–96131 |
| 3 Rogue | 3 | Poisoned Knife (2) | 30 | 96133–96211 |
| 3 Rogue | 4 | Paralytic Knife (5) | 45 | 96213–96291 |
| 3 Rogue | 5 | Shadowstep (6) | 30 | 96293–96769 |
| 4 Wizard | 1 | Meteor (0) | 30 | 96778–97258 |
| 4 Wizard | 2 | Blizzard (1) | 30 | 97260–97488 |
| 4 Wizard | 3 | Time Stop (2) | 45 | 97490–97666 |
| 4 Wizard | 4 | Conflagrate (5) | 40 | 97668–97940 |
| 4 Wizard | 5 | Thunderbolt (6) | 30 | 97942–98320 |
| 5 Witch | 1 | Drain Life (0) | 20 | 98329–98772 |
| 5 Witch | 2 | Plague (1) | 30 | 98774–99100 |
| 5 Witch | 3 | Debilitate (2) | 30 | 99102–99241 |
| 5 Witch | 4 | Horror (5) | 40 | 99243–99788 |
| 5 Witch | 5 | Hex (6) | 40 | starts 99790 — **part 2** |
| 6–10 | 1–5 | Bard, Barbarian, Monk, Ranger, Paladin | — | **part 2** |

Class-block boundaries: Cleric 93597–94390, Knight 94392–96075, Rogue 96077–96770, Wizard 96772–98321,
Witch from 98323.

---

## 3. Fields

### 3.1 `PartyMember` fields read/written in this range (declared [IL L76919-77025]; defaults from `.ctor` [IL L77028-77118])

| Field | Type | Meaning in this code | Default |
|---|---|---|---|
| `characterClass` | int | 1-based class id (§2.2) | 1 |
| `abilities` | int[] | per-slot ability id K (§2.2) | filled by MotherBrain [IL L59731-59788] |
| `passives` | int[] | talent choices (§2.2) | filled by MotherBrain [IL L59789-59943] |
| `cooldowns` / `remainingCooldowns` | float[] | per-slot full cooldown / time left. War Cry + Blitz zeroes `remainingCooldowns[0]` and `[1]` | — |
| `buffs` | float[] | remaining seconds of each timed buff on this hero, indexed by buff id (§3.3) | — |
| `power` | float | hero attack/heal power; base of every formula here | 15 |
| `impactForce` | float | knockback magnitude multiplier | 2 |
| `critChance` | int | used by `calculateCrit()` | — |
| `health`, `maxHealth` | float | used for "alive" tests and Drain Life's most-injured search | 1000 / 1000 |
| `noHitReact` | bool | set true for the duration of most casts, false at the end (name implies hit-reaction animation is suppressed; consumer is outside this range) | false |
| `commandPending` | bool | set true during some casts; `returnToNormal()` always clears it [IL L86371-86373] | false |
| `invincible` | bool | true for 0.5 s during Shadowstep's vanish | false |
| `specialAwaitingTarget` | int (private) | −1 = nothing queued; 0/1/2 = slot whose ability is waiting for the hero to get a target | −1 |
| `myTarget` | Transform | current target (enemy, or an ally for Cleric buffs) | — |
| `myTargetEnemyScript` | EnemyScript | script of the current enemy target | — |
| `tempAllyScript` | PartyMember (private) | scratch: buff recipient / most-injured ally | — |
| `myTransform` | Transform | hero transform (position, `localScale.x` = facing: +1 / −1) | — |
| `myAnimation` | Animation | hero body animation | — |
| `myWeaponAnimation` | Animation | weapon animation (staff "cast") | — |
| `myRenderer` | Renderer | hero material; `material.color` is set for a flash | — |
| `mySounds` | AudioSource[] | per-class sound list; indices only (clips are assigned on the prefab, not in code) | — |
| `myEffects` | EffectScript[] | per-class pooled visual/projectile effects; indices only. Built from `myEffectNames` (prefab-serialized resource paths) in `createMyEffects` [IL L86613-86752] | — |
| `colorSpeed` | float | speed of the colour flash fade started by `activateColors()` | 2 |
| `colorPulseTimer`, `buffColor`, `mostRecentBuff` | float, Color, int (private) | buff-glow presentation: timer reset to 0, glow colour, id of the newest buff | 0, (0.25,0.25,0.25), — |
| `auraTimer` | float | reset to 0 by Vengeful Angel (consumed by `clericAuraAttack`) | — |
| `bardCoefficient` | float | temporarily set to 0.7 around each Cleave hit, then back to 1 | 1 |
| `internalTimeCounter` | float (private) | set to 1 by Shield Rush | — |
| `attackers` | int | number of melee enemies currently on this hero (War Cry cap: < 4) | — |
| `meleeSlot`, `preferBack` | int | melee position slot bookkeeping (Shadowstep) | — |
| `movementTarget` | Vector3 | Shadowstep teleports the hero to it after `findMovementTarget()` | — |
| `actionTimer` | float | set to 100 after Shadowstep and in `returnToNormal()` when a target exists (attack is ready immediately) | — |
| `returnedDamage` | float | damage actually dealt by the last `takeDamage` call, written by `returnDamageValue` [IL L86850-86860]; Drain Life heals for it | — |
| `motherBrain` | MotherBrain | battle controller | — |

### 3.2 Coroutine locals (hoisted fields of `$performSpecial$1850/$`) [IL L93272-93309]

| Field | Type | Used by |
|---|---|---|
| `$tempVector` | Vector3 | knockback direction |
| `$i` | int | loop counter |
| `$meteorImpactPosition` | Vector3 | Meteor |
| `$modifier` | float | Drain Life (Prey on the Weak) |
| `$hypotheticalDamage` | int | Drain Life (Crushing Despair) |
| `$plagueDetonationZone` | Vector3 | Plague |
| `$specialSlot` | int | the argument |
| `$validTargets`, `$numberOfStrikes`, `$initialPosition`, `$tookAShot`, `$lowestHealthAlly`, `$originalTauntability` | — | not used in 93226–99788 (part 2) |

### 3.3 Other objects touched

**MotherBrain:** `playerScripts[]` (party), `enemyScripts[]` (enemies), `buffDurations[]`,
`buffMagnitudes[]`, `debuffDurations[]`, `debuffMagnitudes[]` (float tables indexed by buff/debuff id),
`disableSpecials` (bool; true = ability buttons locked), `dimBackground` (bool; darkens the scene),
`cameraShaker` (Animation; clip `"shake"`), `edge`, `floor`, `cieling` (arena bounds, spelling as in
the code), `DB.tutorial`, `tutorialState`.

**EnemyScript:** `myTransform`, `health`, `myRenderer.enabled` (hidden enemies are skipped),
`aoeRadiusBonus` (added to both half-extents of most AoE boxes — big enemies are easier to hit),
`likeABoss` (boss flag: immune to fear effects here), `immuneToDeath`, `isMelee`, `myTarget`,
`myTargetScript`, `meleeSlot`, `debuffs[]` (remaining seconds per debuff id), `debuffColor`,
`mostRecentDebuff`, `fearLocation`, `fearTimer`, `meteorDotMagnitude`, `conflagDotMagnitude`,
`plagueDotMagnitude`, `colorSpeed`, methods `takeDamage(int amount, Vector3 knockback, PartyMember attacker)`,
`hypotheticalDamage(int, PartyMember)`, `purgePosition(int)`, `requestPosition(int, PartyMember)`,
`activateColors()`.

**EffectScript:** `activate(Vector3 position, Transform target)` (target may be null), `myTransform`,
`healAmount`.

### 3.4 Buff ids written in this range (`PartyMember.buffs[id] = MotherBrain.buffDurations[id]`)

The duration/magnitude tables are **not initialised in code** (no `stfld`/`stelem` for them exists in the
assembly; they are serialized on the scene object), so their numeric values are *not determinable from
the IL*. The "tooltip" column quotes `classes.json` descriptions as a hint only.

| Buff id | Set by | Tooltip hint (not from code) | Read by (outside this range) |
|---|---|---|---|
| 0 | Knight Shield Wall (self) | "reducing damage taken by 50% for 15 sec" | `PartyMember.takeDamage` [IL L81560] |
| 1 | Rogue Sneak Attack (self) | "deals 250% normal damage" | `$meleeAttack` [IL L90215] |
| 2 | Cleric Shield (target ally or self) | "damage taken −75% for 10 sec" | `PartyMember.takeDamage` [IL L81782] |
| 4 | Cleric Power Infusion (target ally or self) | "doubling their power for 10 sec" | `calculateDamageMultiplier` (×`buffMagnitudes[4]`) [IL L86542-86559]; `EnemyScript.takeDamage` [IL L18566]; `PartyMember.heal` [IL L82489] |
| 5 | Cleric Guardian/Vengeful Angel **only if `passives[2] != 0`** (Favored Soul) | "immune to damage" | `PartyMember.takeDamage` [IL L81740] |
| 6 | Cleric Guardian Angel | "doubling healing power for 15 sec" | `PartyMember.heal` [IL L82510]; `$castHeal` [IL L88581] |
| 7 | Cleric Vengeful Angel | "dealing damage around them for 15 sec" | `clericAuraAttack` [IL L84386] |
| 8 | Rogue Expose Weakness (self) | "increasing damage taken by 50% for 10 sec" | `$meleeAttack` [IL L90273] |
| 9 | Rogue Shadowstep (self) | "350% normal damage" | `$meleeAttack` [IL L90282] |
| 11 | Knight Shield Rush (self) | — | `PartyMember.AI` [IL L80622]; `$meleeAttack` [IL L90224] |

`buffMagnitudes[]` entries used directly as formula constants in this range: `[3]` (Group Heal power
multiplier) and `[10]` (Cleave per-hit power multiplier).

### 3.5 Debuff ids written in this range (`EnemyScript.debuffs[id]`)

Meanings marked UNVERIFIED are inferred from the ability that sets them, not read from EnemyScript.

| Debuff id | Value written | Set by | Meaning |
|---|---|---|---|
| 1 | 0.9 (min) / 8 / 6 | Drain Life / Horror tier 1 / Horror tier 2 | UNVERIFIED: paralysis/stun timer (read by `EnemyScript.AI` [IL L6348]) |
| 3 | 3 (min) / 1.7 (min) | Meteor + Concussive Shockwave / Thunderbolt | UNVERIFIED: knocked-down timer (read by `EnemyScript.AI` [IL L6375]) |
| 4 | 0.2 | Thunderbolt | UNVERIFIED: companion timer of the knock-down (read by `EnemyScript.animateSliding` [IL L20239]) |
| 5 | `debuffDurations[5]` / `debuffDurations[9]` / 4 | Intimidate / Conflagrate / Horror tier 3 | fear: enemy runs to `fearLocation` (fields `fearLocation`, `fearTimer` are written alongside; read by `EnemyScript.AI` [IL L6420]) |
| 8 | `debuffDurations[8]` | Meteor + Flaming Meteor | meteor burn DoT (`meteorDotMagnitude`) |
| 9 | `debuffDurations[9]` | Conflagrate | conflagrate DoT (`conflagDotMagnitude`) |
| 10 | `debuffDurations[10]` | Blizzard | UNVERIFIED: slow (read by `EnemyScript.AI` [IL L6893]) |
| 11 | `debuffDurations[11]` | Time Stop | UNVERIFIED: frozen in time (read by `EnemyScript.AI` [IL L6049]) |
| 13 | (read only here) | — | tested by Drain Life's Prey on the Weak; written at [IL L99887] (part 2, Hex) |
| 14 | `debuffDurations[14]` | Debilitate | UNVERIFIED: attack-power reduction (read by `PartyMember.takeDamage` [IL L81866]) |
| 15 | `debuffDurations[15]` | Plague | plague DoT (`plagueDotMagnitude`) |

---

## 4. Shared mechanics (apply to every ability below)

### 4.1 What happens *before* `performSpecial` — `MotherBrain.$specialMove$1664` [IL L72034-72391]

1. Preconditions: a leader (selected hero) exists, `leader.abilities[slot] != 0`,
   `leader.remainingCooldowns[slot] <= 0`, `leader.health > 0` [IL L72034-72066].
2. Play `audioPool[3]`; `leader.commandPending = true`; `leader.invincible = true`;
   `leader.browniePoints += 20`; flash the pressed icon; `disableSpecials = true`; wait **0.08 s**
   [IL L72068-72132].
3. `dimBackground = true`; camera `"powerUpShake"`; `audioPool[5]`; power-up effect at the leader;
   `leader.AIState = 5` [IL L72148-72186].
4. **Cooldown start:** if `leader.noCooldownChance > 0` and `Random.Range(0,100) <= noCooldownChance`
   (int range, upper bound exclusive) → `remainingCooldowns[slot] = 0.2`; otherwise
   `remainingCooldowns[slot] = cooldowns[slot]` [IL L72187-72226]. So the cooldown starts at button
   press, before the ability's own cast time.
5. Stop `"hitReact"`, play `"powerUp"`; `Time.timeScale = 0.1`; white-ish flash (colour 1.3,1.3,1.3,
   `colorSpeed = 4`); wait **0.052 s** (a `WaitForSeconds`, which runs on scaled time — UNVERIFIED engine
   behaviour: ≈0.52 s real time at timeScale 0.1) [IL L72227-72267].
6. `disableSpecials = false`; `Time.timeScale = 1`; `dimBackground = false`;
   `leader.commandPending = false`; `leader.invincible = false`;
   `StartCoroutine(leader.performSpecial(slot))` [IL L72310-72341].

### 4.2 Deferred casting when there is no target

Abilities marked "needs target" check `myTarget` first. If it is null they set
`specialAwaitingTarget = <slot>` and call `returnToNormal()`. Every frame `PartyMember.AI` checks
`specialAwaitingTarget > -1 && myTarget`: it sets `AIState = 5`, turns the hero to face the target
(`localScale.x = -1` if target is to the left, `+1` if to the right, then `updateHealthBar(1)`), and
starts `performSpecial(specialAwaitingTarget)` again [IL L78296-78423]. The ability then resets
`specialAwaitingTarget = -1`. The cooldown was already started at the button press (§4.1 step 4).

### 4.3 Helpers

* **`calculateCrit()`** → int multiplier: if `critChance > 0` and `Random.Range(0,100) <= critChance`
  → 2, else 1 [IL L87112-87142]. Shown below as `crit`.
* **`calculateDamageMultiplier(enemy)`** → float, starts at 1; × `buffMagnitudes[4]` if own
  `buffs[4] > 0`; × `debuffMagnitudes[2]` if `enemy.debuffs[2] > 0`; × `debuffMagnitudes[6]` if
  `enemy.debuffs[6] > 0`; × `buffMagnitudes[13]` if own `buffs[13] > 0` [IL L86534-86610]. Used here
  only to pre-bake DoT magnitudes (Meteor burn, Conflagrate).
* **`returnToNormal()`**: `commandPending = false`; unless `motherBrain.levelComplete` or
  `AIState == 3`: if `myTarget != null` → `AIState = 2`, `actionTimer = 100`; else if distance to
  `movementTarget` > 0.07 → `AIState = 1`; else `AIState = 0` and cross-fade `"idle"` over 0.15 s
  [IL L86365-86421].
* **`activateColors()` + `myRenderer.material.color = X`**: starts a colour flash from X that fades at
  `colorSpeed` (body of `activateColors` is outside this range [IL L84223-84239]).
* **Enemy loop conventions.** Loops run `i = 0 .. enemyScripts.length-1`. In most loops, a **null entry
  ends the whole loop** (`i = length`), i.e. the array is assumed to be packed. Exceptions are noted
  (War Cry skips nulls; party loops skip nulls).
* **AoE boxes** are axis-aligned rectangles, not circles: `|enemy.x − centre.x| < halfX` **and**
  `|enemy.z − centre.z| < halfZ` (x = screen horizontal, z = depth). Unless noted, `enemy.aoeRadiusBonus`
  is added to both half-extents.
* **Damage calls** are `enemy.takeDamage(int amount, Vector3 knockback, self)`; the `conv.i4` truncates
  the float amount toward zero. Mitigation, buff multipliers etc. happen inside
  `EnemyScript.takeDamage` (not in this range).
* **Common cast preamble "STAFF-CAST"** used by Cleric, Wizard and Witch: `myAnimation.Play("specialCast")`;
  `myWeaponAnimation.Stop()`; `myWeaponAnimation.Play("cast")`.

---

## 5. Cleric (characterClass 1) [IL L93597-94390]

Sound and effect names are prefab data; only indices are in code.

### 5.1 Group Heal — abilities id 1, cooldown 20 s [IL L93603-93811]

* **Targeting:** all living party members (no range check, no target needed).
* **Timeline**
  1. t=0: `noHitReact = true`; STAFF-CAST; `mySounds[2].Play()`; `myEffects[4].activate(self.position, null)`
     [IL L93612-93648].
  2. t=0, for each `p = motherBrain.playerScripts[i]` that is non-null and has `health > 0`
     (null entries are skipped, not a loop break) [IL L93654-93674, L93754-93767]:
     * heal amount: `int(power × buffMagnitudes[3])`; if `passives[3] == -1` (Desperate Prayer) →
       `int(1.25 × power × buffMagnitudes[3])` [IL L93676-93729];
     * `p.heal(amount, self)` [IL L93706, L93729];
     * `myEffects[i].activate(p.position, p.myTransform)` — effect index = party index, so effects 0–3
       are the per-ally heal visuals [IL L93730-93753].
  3. t=0: caster flash: `colorSpeed = 1.1`; `activateColors()`; material colour (1,1,1) [IL L93769-93784].
  4. wait **1.0 s** [IL L93785-93790].
  5. `noHitReact = false`; `returnToNormal()`; if `motherBrain.DB.tutorial` → `motherBrain.tutorialState = 41`
     [IL L93792-93810].
* **Passives:** Desperate Prayer (`passives[3] == -1`) ×1.25. Further healing modifiers are applied
  inside `PartyMember.heal` (outside this range).
* No crit roll.

### 5.2 Shield — abilities id 2, cooldown 30 s [IL L93813-93989]

* **Targeting:** `myTarget` if set (it is fetched with `GetComponent("PartyMember")`, i.e. an ally),
  otherwise the Cleric herself.
* **Timeline**
  1. t=0: `commandPending = true`; `noHitReact = true`; `mySounds[0].Play()`; STAFF-CAST [IL L93822-93850].
  2. t=0: recipient R = `myTarget.GetComponent("PartyMember")` (stored in `tempAllyScript`) or self
     [IL L93851-93866, L93915]:
     * `R.buffs[2] = buffDurations[2]` [IL L93867-93879, L93915-93927];
     * `R.colorPulseTimer = 0`; `R.buffColor = (0.34, 0.34, 0.75)`; `R.mostRecentBuff = 2`
       [IL L93880-93897, L93928-93941];
     * `myEffects[5].activate(R.position, R.myTransform)` [IL L93898-93912, L93942-93954].
  3. `commandPending = false`; `colorSpeed = 1.1`; `activateColors()`; colour (1,1,1) [IL L93955-93974].
  4. wait **0.5 s**; `noHitReact = false`; `returnToNormal()` [IL L93975-93988].
* **Effect:** buff id 2 for `buffDurations[2]` seconds (value not in IL; tooltip: −75% damage taken,
  10 s). The damage reduction itself is in `PartyMember.takeDamage` [IL L81782].
* Re-casting overwrites the timer (assignment, not addition).

### 5.3 Power Infusion — abilities id 3, cooldown 30 s [IL L93991-94167]

Identical structure to Shield with these substitutions:

| Item | Value | IL |
|---|---|---|
| sound | `mySounds[3]` (played after the animations) | L94023-94029 |
| buff | `R.buffs[4] = buffDurations[4]` | L94045-94057, L94093-94105 |
| glow colour | (0.62, 0.41, 0.25) | L94063-94070, L94109-94115 |
| `mostRecentBuff` | 4 | L94071-94075, L94116-94119 |
| effect | `myEffects[6].activate(R.position, R.myTransform)` | L94076-94090, L94120-94132 |
| tail | `commandPending=false`, flash (1,1,1) `colorSpeed 1.1`, wait **0.5 s**, `noHitReact=false`, `returnToNormal()` | L94133-94166 |

* **Effect:** buff id 4 (tooltip: power doubled for 10 s). Its multiplier is `buffMagnitudes[4]`
  (see `calculateDamageMultiplier`, §4.3).

### 5.4 Guardian Angel — abilities id 4, cooldown 60 s [IL L94169-94276]

* **Targeting:** self.
* **Timeline**
  1. t=0: `noHitReact = true`; `Play("specialCast")`; weapon `Stop()`; `mySounds[5].Play()`; weapon
     `Play("cast")` [IL L94178-94202].
  2. If `passives[2] != 0` (Favored Soul, the level-25 passive): `buffs[5] = buffDurations[5]`
     [IL L94203-94221].
  3. `buffs[6] = buffDurations[6]` [IL L94222-94234].
  4. `myEffects[7].activate(self.position, self.myTransform)`; `colorPulseTimer = 0`;
     `buffColor = (0.62, 0.41, 0.25)`; `mostRecentBuff = 6` [IL L94234-94261].
  5. wait **1.0 s**; `noHitReact = false`; `returnToNormal()` [IL L94262-94275].
* **Effect:** buff id 6 (tooltip: healing power doubled, 15 s), consumed in `heal`/`castHeal`.

### 5.5 Vengeful Angel — abilities id 5, cooldown 60 s [IL L94278-94389]

Same as Guardian Angel except:

| Item | Value | IL |
|---|---|---|
| main buff | `buffs[7] = buffDurations[7]` | L94331-94343 |
| Favored Soul | same: `buffs[5] = buffDurations[5]` if `passives[2] != 0` | L94312-94330 |
| effect | `myEffects[7]` (same index as Guardian Angel) at self, following self | L94343-94354 |
| extra | `auraTimer = 0` | L94355-94359 |
| `mostRecentBuff` | 7; `buffColor` (0.62, 0.41, 0.25) | L94360-94375 |
| tail | wait **1.0 s**; `noHitReact=false`; `returnToNormal()` | L94376-94389 |

* **Effect:** buff id 7; the periodic damage pulse is `PartyMember.clericAuraAttack` [IL L84371-84586]
  (not in this range).

---

## 6. Knight (characterClass 2) [IL L94392-96075]

### 6.1 Shield Wall — abilities id 1, cooldown 30 s [IL L94398-94529]

* **Targeting:** self.
* **Timeline**
  1. t=0: `motherBrain.disableSpecials = true`; `noHitReact = true`; `mySounds[7].Play()`;
     `myAnimation.Play("shieldWall")`; `myEffects[1].activate(self.position, self.myTransform)`
     [IL L94407-94440].
  2. `buffs[0] = buffDurations[0]` [IL L94441-94453]; then
     * `passives[3] == 1` (Fortress): `buffs[0] += 5` [IL L94453-94472];
     * `passives[3] == -1` (Revenge): `buffs[0] -= 5` [IL L94474-94493].
  3. `colorPulseTimer = 0`; `buffColor = (0.34, 0.34, 0.75)`; `mostRecentBuff = 0` [IL L94494-94509].
  4. wait **0.7 s**; `noHitReact = false`; `disableSpecials = false`; `returnToNormal()` [IL L94510-94528].
* **Effect:** buff id 0 for `buffDurations[0]` (+5 / −5) seconds. Tooltips: 50% less damage for 15 s;
  Fortress 20 s; Revenge 10 s + 100% reflect — consistent with ±5 s around a 15 s base, but the base
  value itself is not in the IL. Damage reduction / reflection logic: `PartyMember.takeDamage`
  [IL L81560].

### 6.2 Cleave — abilities id 2, cooldown 30 s [IL L94531-95304]

* **Targeting:** area around the Knight; three sweeps.
* **Box (each sweep):** `|dx| < 1.5 + aoeRadiusBonus` and `|dz| < 1.0 + aoeRadiusBonus` around the
  Knight's current position; enemy must have `health > 0` and `myRenderer.enabled`
  [IL L94621-94708].
* **Damage per hit:** `int(power × buffMagnitudes[10] × crit)` — `crit` rolled separately per enemy per
  sweep [IL L94733-94753]. `buffMagnitudes[10]` is not in the IL.
  Around each `takeDamage` call `self.bardCoefficient` is set to **0.7** and restored to **1.0**
  afterwards [IL L94729-94732, L94767-94770] (its consumer is in the damage path, outside this range).
* **Knockback:** direction = normalized (enemy.position − knight.position); magnitude
  `impactForce × 0.5` for sweeps 1 and 2, `impactForce × 1.5` for sweep 3
  [IL L94710-94728, L94757-94766, L95247-95252].
* **Timeline**
  1. t=0: `commandPending = true`; `disableSpecials = true`; `noHitReact = true`;
     `myAnimation.Play("cleave")`; `mySounds[5].Play()`;
     `myEffects[4].activate(position + (0, 0.05, −0.15), null)`;
     `myEffects[5].activate(position + (0, 0.2, −0.45), null)` [IL L94540-94598].
  2. wait **0.04 s** [IL L94599-94604].
  3. **Sweep 1** (knockback ×0.5) [IL L94606-94793].
  4. wait **0.168 s** [IL L94795-94800].
  5. Flip facing: `localScale.x = −localScale.x`; `updateHealthBar(1)` [IL L94802-94848].
     **Sweep 2** (knockback ×0.5) [IL L94849-95036].
  6. wait **0.19 s** [IL L95038-95043].
  7. Flip facing back (`localScale.x = −localScale.x`; `updateHealthBar(1)`) [IL L95045-95091].
     **Sweep 3** (knockback ×1.5) [IL L95092-95279].
  8. `commandPending = false`; wait **0.34 s**; `noHitReact = false`; `returnToNormal()`;
     `disableSpecials = false` [IL L95281-95303].
* Total cast ≈ 0.74 s; an enemy that stays in the box takes 3 hits.
* Loop breaks at the first null `enemyScripts` entry [IL L94618-94619, L94773-94779].

### 6.3 Intimidate — abilities id 3, cooldown 30 s [IL L95306-95653]

* **Targeting:** non-boss enemies in a box around the Knight; no damage.
* **Timeline**
  1. t=0: `mySounds[8].Play()`; `disableSpecials = true`; `noHitReact = true`;
     `myAnimation.Play("intimidate")`; `myEffects[10].activate(self.position, null)`;
     `cameraShaker.Play("shake")`; `activateColors()`; material colour (1,1,1) [IL L95315-95368].
  2. t=0, loop over enemies [IL L95369-95601]. **The loop ends at the first entry that is null _or_ has
     `likeABoss == true`** (both branch to `i = length`) [IL L95374-95392, L95581-95587] — enemies
     stored after a boss in the array are never affected. For each enemy before that, if
     `|dx| < 1.5 + aoeRadiusBonus`, `|dz| < 1.0 + aoeRadiusBonus`, `health > 0`, `!likeABoss`,
     `myRenderer.enabled` [IL L95394-95491]:
     * `debuffs[5] = debuffDurations[5]` [IL L95493-95508];
     * `debuffColor = (0.34, 0.16, 0.57)`; `mostRecentDebuff = 5` [IL L95508-95529];
     * `fearLocation = Vector3(Random.Range(−edge + 0.7, edge − 0.7), 0, Random.Range(floor + 0.9, cieling − 0.8))`
       (`edge`, `floor`, `cieling` are MotherBrain arena bounds) [IL L95530-95567];
     * `fearTimer = Random.Range(0.6, 1.0)` [IL L95568-95578].
  3. wait **0.12 s** [IL L95603-95608].
  4. `cameraShaker.Stop("shake")`; `cameraShaker.Play("shake")`;
     `myEffects[11].activate(self.position, null)` [IL L95610-95633].
  5. wait **0.58 s**; `noHitReact = false`; `disableSpecials = false`; `returnToNormal()`
     [IL L95634-95652].
* **Effect:** fear (debuff 5) for `debuffDurations[5]` seconds (value not in IL). Bosses immune.

### 6.4 War Cry — abilities id 4, cooldown 30 s [IL L95655-96046]

* **Targeting:** every living enemy anywhere (no range check, no boss check, no visibility check).
* **Timeline**
  1. t=0: `mySounds[8].Play()`; `disableSpecials = true`; `noHitReact = true`;
     `myAnimation.Play("intimidate")` (same clip as Intimidate);
     `myEffects[2].activate(self.position, null)`; `cameraShaker.Play("shake")`; `activateColors()`;
     colour (1,1,1) [IL L95664-95717].
  2. **Blitz** (`passives[2] != 0`): `remainingCooldowns[0] = 0`; `remainingCooldowns[1] = 0`
     [IL L95718-95738]. (Slot 2, War Cry's own slot, is not reset.)
  3. t=0, for each enemy e (null entries are **skipped**, loop continues) with `e.health > 0` and
     `e.myTarget != self.myTransform` [IL L95744-95778]:
     * **melee enemy** (`e.isMelee`) **and `self.attackers < 4`** [IL L95780-95794]:
       - if `e.myTargetScript` exists: `e.myTargetScript.purgePosition(e.meleeSlot)` (frees its slot on
         the old victim) [IL L95796-95823];
       - `e.meleeSlot = self.requestPosition(0, e)` [IL L95824-95842];
       - `e.myTarget = self.myTransform`; `e.myTargetScript = self` [IL L95843-95863];
       - `e.myAnimation.Play("idle")`; `e.activateColors()`; `e.myRenderer.material.color = (0.7, 0.25, 0.25)`;
         `e.colorSpeed = 0.8` (red flash) [IL L95864-95905].
     * **ranged enemy** (`!e.isMelee`): same retarget (`myTarget`, `myTargetScript`, `"idle"`, red
       flash, `colorSpeed 0.8`) without any melee-slot bookkeeping [IL L95908-95980].
     * melee enemy while `self.attackers >= 4`: nothing happens (the Knight can hold at most 4 melee
       attackers; `attackers` is not incremented in this code, so the cap is evaluated against the value
       maintained by `requestPosition`).
  4. wait **0.12 s**; `cameraShaker.Stop("shake")` + `Play("shake")`;
     `myEffects[3].activate(self.position, null)` [IL L95996-96026].
  5. wait **0.58 s**; `noHitReact = false`; `disableSpecials = false`; `returnToNormal()`
     [IL L96027-96045].
* The taunt is a one-time retarget; no debuff timer is written, so nothing in this code stops enemies
  from changing target again later.

### 6.5 Shield Rush — abilities id 5, cooldown 30 s [IL L96048-96075]

The whole branch is three statements:

1. `buffs[11] = buffDurations[11]` [IL L96057-96069];
2. `returnToNormal()` [IL L96070];
3. `internalTimeCounter = 1.0` [IL L96071-96074].

No animation, sound, wait, target check or damage here. The actual rush/knock-down is driven by code
that reads `buffs[11]`: `PartyMember.AI` [IL L80622] and `$meleeAttack` [IL L90224, write at L91039].
Blitz is **not** applied in this branch (the tooltip says Shield Rush also triggers it — if so it is
done by the consumer code; not determined here).

---

## 7. Rogue (characterClass 3) [IL L96077-96770]

### 7.1 Sneak Attack — abilities id 1, cooldown 20 s [IL L96083-96106]

`buffs[1] = buffDurations[1]`; `returnToNormal()`. Nothing else. The buff "arms" the next melee
attack; the damage bonus (tooltip 250%, Lethality +40%) is implemented in `$meleeAttack`
(reads `buffs[1]` at [IL L90215], clears/writes at [IL L90536]) — not in this range.

### 7.2 Expose Weakness — abilities id 2, cooldown 30 s [IL L96108-96131]

`buffs[8] = buffDurations[8]`; `returnToNormal()`. Arms the next melee attack; `$meleeAttack` reads
`buffs[8]` at [IL L90273]. UNVERIFIED (not traced here): the resulting enemy debuff is `debuffs[2]`,
which `$meleeAttack` writes at [IL L91816] and whose multiplier `debuffMagnitudes[2]` is applied in
`calculateDamageMultiplier` (§4.3).

### 7.3 Poisoned Knife — abilities id 3, cooldown 30 s [IL L96133-96211]

* **Targeting:** current target (needs target).
* If `myTarget` is null: `specialAwaitingTarget = 1`; `returnToNormal()` [IL L96204-96210].
* Otherwise:
  1. `specialAwaitingTarget = -1`; `mySounds[7].Play()`; `myAnimation.Play("throw")` [IL L96148-96162];
  2. `myEffects[2].activate(self.position + (localScale.x × 0.35, 0, 0), myTarget)` — the projectile
     spawns 0.35 units in front of the Rogue (facing sign) and homes on `myTarget` [IL L96163-96191];
  3. wait **0.5 s**; `returnToNormal()` [IL L96192-96201].
* Damage and the poison DoT are applied by the projectile's `EffectScript` when it lands
  (`EffectScript.damageEnemy`, [IL L4003-4260] region) — not in this range.
* `noHitReact` / `commandPending` are not touched.

### 7.4 Paralytic Knife — abilities id 4, cooldown 45 s [IL L96213-96291]

Identical to Poisoned Knife except: projectile is **`myEffects[5]`** [IL L96243-96271] and the
no-target fallback sets **`specialAwaitingTarget = 2`** [IL L96284-96287]. Same sound `mySounds[7]`,
same `"throw"` animation, same 0.35 offset, same **0.5 s** wait [IL L96228-96281].

### 7.5 Shadowstep — abilities id 5, cooldown 30 s [IL L96293-96769]

* **Targeting:** current enemy target (needs target). No target → `specialAwaitingTarget = 2`;
  `returnToNormal()` [IL L96763-96769].
* **Timeline**
  1. t=0: `commandPending = true`; `specialAwaitingTarget = -1`; `mySounds[9].Play()`;
     `buffs[9] = buffDurations[9]`; `myEffects[7].activate(self.position, null)`;
     `myEffects[8].activate(self.position, null)`; `myAnimation.Play("hide")`; `invincible = true`
     [IL L96308-96364].
  2. wait **0.5 s**; `invincible = false` [IL L96365-96375].
  3. If `myTargetEnemyScript` and `myTarget` still exist and `myTargetEnemyScript.health > 0`
     [IL L96376-96394]:
     a. Only when the target is currently attacking the Rogue (`target.myTarget == self.myTransform`):
        if `self.x < target.x` → `self.position.x = target.x + 1`; else (`self.x >= target.x`) →
        `self.position.x = target.x − 1` (jump to the opposite side = behind it) [IL L96396-96538].
     b. `myTargetEnemyScript.purgePosition(self.meleeSlot)`;
        `self.meleeSlot = myTargetEnemyScript.requestPosition(self.preferBack, self)`;
        `findMovementTarget()`; `myTransform.position = movementTarget` (instant teleport into the
        melee slot) [IL L96540-96568].
     c. Face the target: if `target.x < self.x` and `localScale.x != -1` → `localScale.x = -1`,
        `updateHealthBar(1)`; else if `target.x > self.x` and `localScale.x != 1` → `localScale.x = 1`,
        `updateHealthBar(1)` [IL L96569-96706].
     d. `activateColors()`; material colour (0,0,0) (reappear from black); `colorSpeed = 1.3`;
        `actionTimer = 100` (attack immediately) [IL L96707-96730].
  4. Else (target died/vanished during the wait): `myAnimation.Play("idle")`; `activateColors()`;
     colour (0,0,0); `colorSpeed = 1.3` [IL L96733-96757]. The buff `buffs[9]` stays set.
  5. `returnToNormal()` [IL L96758-96760].
* **Damage:** none here. `buffs[9]` arms the next melee attack (tooltip 350%; read in `$meleeAttack`
  at [IL L90282], cleared/written at [IL L91711]).

---

## 8. Wizard (characterClass 4) [IL L96772-98321]

### 8.1 Meteor — abilities id 1, cooldown 30 s [IL L96778-97258]

* **Targeting:** area centred on the current target's position **at cast start** (needs target).
  No target → `specialAwaitingTarget = 0`; `returnToNormal()` [IL L97251-97257].
* **Timeline**
  1. t=0: `meteorImpactPosition = myTarget.position`; `disableSpecials = true`; `dimBackground = true`;
     `specialAwaitingTarget = -1`; `noHitReact = true`; STAFF-CAST; `mySounds[4].Play()`
     [IL L96793-96838].
  2. wait **0.35 s**; `myEffects[2].activate(meteorImpactPosition, null)` (falling meteor)
     [IL L96839-96854].
  3. wait **0.27 s**; `cameraShaker.Stop()`; `cameraShaker.Play("shake")`;
     `myEffects[3].activate(myEffects[2].myTransform.position, null)`;
     `myEffects[4].activate(myEffects[2].myTransform.position, null)` (impact visuals)
     [IL L96855-96901].
  4. Impact loop (breaks at first null enemy) [IL L96902-97198]. Centre C =
     `myEffects[2].myTransform.position`. Enemy is hit if `|dx| < 1.5 + aoeRadiusBonus`,
     `|dz| < 1.0 + aoeRadiusBonus`, `health > 0`, `myRenderer.enabled` [IL L96917-97010]:
     * **damage** `int(power × 2 × crit)`; knockback = normalized(enemy − C) × `impactForce` × 2
       [IL L97012-97064];
     * **Concussive Shockwave** (`passives[3] == -1`): if `enemy.debuffs[3] <= 3` → `debuffs[3] = 3`
       (3 s; never shortens a longer one) [IL L97065-97097];
     * **Flaming Meteor** (`passives[3] == 1`): `debuffs[8] = debuffDurations[8]`;
       `enemy.meteorDotMagnitude = debuffMagnitudes[8] × power × 2 × calculateDamageMultiplier(enemy)`;
       `debuffColor = (0.6, 0.22, 0.22)`; `mostRecentDebuff = 8` [IL L97099-97175].
       (Tooltip: +50% damage over 8 s; table values not in IL. Note the DoT base uses `power × 2`
       without the crit multiplier.)
  5. wait **0.14 s**; `Time.timeScale = 0.1`; `disableSpecials = false` [IL L97200-97213].
  6. wait **0.06 s** (scaled time during the slow-motion hit-stop); `Time.timeScale = 1`
     [IL L97214-97222].
  7. wait **0.1 s**; `dimBackground = false` [IL L97223-97234].
  8. wait **0.4 s**; `noHitReact = false`; `returnToNormal()` [IL L97235-97248].

### 8.2 Blizzard — abilities id 2, cooldown 30 s [IL L97260-97488]

* **Targeting:** all enemies on the field; no target needed.
* **Timeline**
  1. t=0: `noHitReact = true`; `mySounds[5].Play()`; STAFF-CAST [IL L97269-97293].
  2. wait **0.2 s** [IL L97294-97300].
  3. `myEffects[10].activate(Vector3(0, 4.2, −7), null)`; `myEffects[11].activate(Vector3(0, 4, −6), null)`
     (fixed world positions — full-screen effects) [IL L97302-97328].
  4. Loop (breaks at first null enemy) [IL L97329-97472]: each enemy with `health > 0`,
     `myRenderer.enabled`, and `position.x < 10` [IL L97344-97381]:
     * **damage** `int(power × crit)`; knockback `Vector3(1, 0, 0) × impactForce` (always toward +x)
       [IL L97383-97412];
     * `debuffs[10] = debuffDurations[10]`; `debuffColor = (0.2, 0.2, 0.8)`; `mostRecentDebuff = 10`
       [IL L97413-97449].
  5. wait **0.6 s**; `noHitReact = false`; `returnToNormal()` [IL L97474-97487].
* **Effect:** one hit of `power` damage plus debuff 10 for `debuffDurations[10]` s (tooltip: slow and
  damage for 10 s; any per-tick damage would be in EnemyScript's handling of debuff 10 — not in this
  range).
* Does not set `disableSpecials` or `dimBackground`.

### 8.3 Time Stop — abilities id 3, cooldown 45 s [IL L97490-97666]

* **Targeting:** all enemies on the field; no damage.
* **Timeline**
  1. t=0: `noHitReact = true`; STAFF-CAST [IL L97499-97517].
  2. wait **0.2 s**; `mySounds[7].Play()` [IL L97518-97531].
  3. `myEffects[10].activate(Vector3(0, 4.2, −7), null)`; `myEffects[12].activate(Vector3(0, 4.4, −6), null)`
     [IL L97532-97557].
  4. Loop (breaks at first null enemy): each enemy with `health > 0`, `myRenderer.enabled`,
     `position.x < 10` → `debuffs[11] = debuffDurations[11]` [IL L97558-97650]. No `debuffColor` /
     `mostRecentDebuff` change, no boss exclusion.
  5. wait **0.6 s**; `noHitReact = false`; `returnToNormal()` [IL L97652-97665].
* **Effect:** debuff 11 for `debuffDurations[11]` s (tooltip: frozen 5 s).

### 8.4 Conflagrate — abilities id 4, cooldown 40 s [IL L97668-97940]

* **Targeting:** current enemy target (needs target). No target → `specialAwaitingTarget = 2`;
  `returnToNormal()` [IL L97933-97939].
* **Timeline**
  1. t=0: `disableSpecials = true`; `specialAwaitingTarget = -1`; `dimBackground = true`;
     `noHitReact = true`; STAFF-CAST [IL L97683-97715].
  2. wait **0.2 s** [IL L97716-97722].
  3. If `myTarget` and `myTargetEnemyScript` still exist [IL L97724-97734] (otherwise skip to step 4):
     * `mySounds[6].Play()`; `myEffects[8].activate(target.position, null)`;
       `myEffects[9].activate(target.position, null)`; `cameraShaker.Stop()` + `Play("shake")`;
       `myEffects[7].activate(target.position, myTarget)` (attached flame) [IL L97736-97788];
     * **damage** `int(power × crit)`; knockback normalized(target − self) × `impactForce`
       [IL L97789-97823];
     * `debuffs[5] = debuffDurations[9]` (fear channel, with Conflagrate's duration) and
       `debuffs[9] = debuffDurations[9]` [IL L97824-97850];
     * `debuffColor = (0.6, 0.15, 0.15)` [IL L97850-97855];
     * `target.conflagDotMagnitude = power × debuffMagnitudes[9] × calculateDamageMultiplier(target)`
       [IL L97856-97876];
     * `mostRecentDebuff = 5` [IL L97877-97881].
     * Note: unlike Intimidate, `fearLocation` / `fearTimer` are **not** written here, and there is no
       `likeABoss` check.
  4. wait **0.09 s**; `Time.timeScale = 0.2` [IL L97882-97890].
  5. wait **0.06 s** (scaled); `Time.timeScale = 1`; `disableSpecials = false` [IL L97891-97904].
  6. wait **0.3 s**; `dimBackground = false` [IL L97905-97916].
  7. wait **0.2 s**; `noHitReact = false`; `returnToNormal()` [IL L97917-97930].
* **Effect:** instant `power` hit + disable (debuff 5) + DoT (debuff 9) for `debuffDurations[9]` s
  (tooltip: 6 s). DoT tick logic is in EnemyScript.

### 8.5 Thunderbolt — abilities id 5, cooldown 30 s [IL L97942-98320]

* **Targeting:** area around the Wizard; no target needed.
* **Timeline**
  1. t=0: `noHitReact = true`; `disableSpecials = true`; `dimBackground = true`; STAFF-CAST
     [IL L97951-97979].
  2. wait **0.12 s**; `activateColors()`; material colour (0,0,0); `colorSpeed = 0` (stay black);
     `mySounds[3].Play()`; `myEffects[16].activate(self.position, null)` [IL L97980-98024].
  3. wait **0.26 s**; `colorSpeed = 2`; `cameraShaker.Stop()` + `Play("shake")`;
     `myEffects[17].activate(self.position, null)` [IL L98025-98058].
  4. Loop (breaks at first null enemy) [IL L98059-98270]: enemy hit if `|dx| < 2.0 + aoeRadiusBonus`,
     `|dz| < 1.5 + aoeRadiusBonus`, `health > 0`, `myRenderer.enabled` [IL L98074-98161]:
     * **damage** `int(power × 3 × crit)`; knockback normalized(enemy − self) × `impactForce` × 2
       [IL L98163-98212];
     * if `enemy.debuffs[3] <= 1.7` → `debuffs[3] = 1.7` **and** `debuffs[4] = 0.2`
       [IL L98213-98247].
  5. wait **0.15 s**; `Time.timeScale = 0.1` [IL L98272-98280].
  6. wait **0.02 s** (scaled); `Time.timeScale = 1`; `disableSpecials = false` [IL L98281-98294].
  7. wait **0.3 s**; `dimBackground = false` [IL L98295-98306].
  8. wait **0.2 s**; `noHitReact = false`; `returnToNormal()` [IL L98307-98320].
* **Effect:** `3 × power` AoE hit, strong knockback, and a 1.7 s debuff-3 (never shortens a longer one;
  `debuffs[4] = 0.2` is only written when debuff 3 was actually (re)set).

---

## 9. Witch (characterClass 5), abilities 1–4 [IL L98323-99788]

### 9.1 Drain Life — abilities id 1, cooldown 20 s [IL L98329-98772]

* **Targeting:** current enemy target (needs both `myTarget` and `myTargetEnemyScript`); heal goes to
  the most injured living party member. No target → `specialAwaitingTarget = 0`; `returnToNormal()`
  [IL L98338-98348, L98765-98771].
* **Timeline**
  1. t=0: `specialAwaitingTarget = -1`; `noHitReact = true`; STAFF-CAST [IL L98350-98372].
  2. wait **0.2 s**; `mySounds[4].Play()` [IL L98373-98386].
  3. If target still valid (`myTarget && myTargetEnemyScript`; otherwise jump to step 9):
     `myEffects[4].activate(target.position, myTarget)` (drain visual on the enemy) [IL L98387-98411].
  4. wait **0.6 s**; re-check target validity (otherwise jump to step 9) [IL L98412-98429].
  5. **Modifier:** `modifier = 1.0`. If `passives[2] != 0` (Prey on the Weak) and the target has
     `debuffs[1] > 0` **or** `debuffs[5] > 0` **or** `debuffs[13] > 0` → `modifier = 1.4`
     [IL L98431-98473].
  6. **Damage** (no crit roll; knockback = normalized(target − self) × `impactForce`) [IL L98474-98561]:
     * `passives[3] == 1` (Crushing Despair): `takeDamage(int(modifier × power × 1.4 × 2), …)`, then
       `hypotheticalDamage = target.hypotheticalDamage(int(modifier × power × 2), self)` — i.e. what the
       hit *would* have dealt without the 1.4 bonus [IL L98488-98537];
     * otherwise: `takeDamage(int(modifier × power × 2), …)` [IL L98540-98561].
  7. `dimBackground = false`; `cameraShaker.Stop()` + `Play("shake")`; if `target.debuffs[1] <= 0.9` →
     `debuffs[1] = 0.9` (brief 0.9 s debuff-1, never shortens a longer one; no boss check)
     [IL L98562-98594].
  8. **Heal:**
     * choose recipient: `best = self`; for each non-null `p` in `playerScripts`: if
       `best.health / best.maxHealth > p.health / p.maxHealth` and `p.health > 0` → `best = p`
       (lowest health fraction among the living; ties keep the earlier one) [IL L98595-98678];
     * `myEffects[5].activate(target.position + (0, 0.05, −0.1), best.myTransform)` — a projectile that
       flies from the enemy to the ally [IL L98680-98699];
     * `myEffects[5].healAmount` = [IL L98700-98748]
       - `passives[3] == -1` (Dark Harvest): `returnedDamage × 1.4`;
       - `passives[3] == 1` (Crushing Despair): `hypotheticalDamage` (un-boosted amount);
       - otherwise: `returnedDamage`
       where `returnedDamage` is the damage the enemy actually took from step 6 (written back by
       `PartyMember.returnDamageValue` [IL L86850-86860]). The heal is applied by the EffectScript on
       arrival (not in this range).
     * wait **0.1 s** [IL L98749-98754].
  9. `noHitReact = false`; `returnToNormal()` [IL L98756-98762].
* **Passive summary:** Prey on the Weak ×1.4 damage (and therefore heal) vs. targets with debuff 1, 5
  or 13; Crushing Despair ×1.4 damage, heal unchanged; Dark Harvest heal ×1.4, damage unchanged.
  Life Leech / Sudden Doom are not handled in this branch.

### 9.2 Plague — abilities id 2, cooldown 30 s [IL L98774-99100]

* **Targeting:** area centred on the current target's position at cast start (needs target). No target
  → `specialAwaitingTarget = 1`; `returnToNormal()` [IL L99093-99099].
* **Timeline**
  1. t=0: `plagueDetonationZone = myTarget.position`; `specialAwaitingTarget = -1`;
     `disableSpecials = true`; `dimBackground = true`; `noHitReact = true`; STAFF-CAST
     [IL L98789-98827].
  2. wait **0.2 s**; `mySounds[6].Play()`; `myEffects[9].activate(zone, null)`;
     `myEffects[10].activate(zone, null)`; `cameraShaker.Play("shake")` [IL L98828-98865].
  3. Loop (breaks at first null enemy) [IL L98866-99058]: enemy affected if
     `|enemy.x − zone.x| < 1.5 + aoeRadiusBonus`, `|enemy.z − zone.z| < 1.0 + aoeRadiusBonus`,
     `health > 0`, `myRenderer.enabled` [IL L98882-98961]:
     * `debuffs[15] = debuffDurations[15]`; `debuffColor = (0.25, 0.55, 0.3)` [IL L98963-98990];
     * `enemy.plagueDotMagnitude = power × debuffMagnitudes[15]` (no `calculateDamageMultiplier`)
       [IL L98991-99008];
     * `mostRecentDebuff = 15` [IL L99009-99017];
     * `enemy.takeDamage(1, Vector3(0,0,0), self)` — a 1-point hit with no knockback
       [IL L99018-99035].
  4. wait **0.3 s**; `dimBackground = false`; `disableSpecials = false` [IL L99060-99076].
  5. wait **0.35 s**; `noHitReact = false`; `returnToNormal()` [IL L99077-99090].
* **Effect:** DoT (debuff 15) for `debuffDurations[15]` s; per-tick damage is derived from
  `plagueDotMagnitude` in EnemyScript (reader at [IL L22712]).

### 9.3 Debilitate — abilities id 3, cooldown 30 s [IL L99102-99241]

* **Targeting:** current enemy target (needs target). No target → `specialAwaitingTarget = 1`;
  `returnToNormal()` [IL L99234-99240].
* **Timeline**
  1. t=0: `specialAwaitingTarget = -1`; `noHitReact = true`; STAFF-CAST [IL L99117-99139].
  2. wait **0.2 s** [IL L99140-99146].
  3. If `myTarget` and `myTargetEnemyScript` still exist [IL L99148-99158]:
     * `mySounds[7].Play()`; `myEffects[11].activate(target.position, myTarget)` [IL L99160-99178];
     * `debuffs[14] = debuffDurations[14]`; `debuffColor = (0.55, 0.21, 0.55)`;
       `mostRecentDebuff = 14` [IL L99179-99203];
     * `takeDamage(1, Vector3(0,0,0), self)` [IL L99204-99217];
     * wait **0.7 s** [IL L99218-99223].
     If the target vanished during step 2, this whole step (including the 0.7 s wait) is skipped.
  4. `noHitReact = false`; `returnToNormal()` [IL L99225-99231].
* **Effect:** debuff 14 for `debuffDurations[14]` s (tooltip: greatly reduced attack power for 10 s).
  No boss check.

### 9.4 Horror — abilities id 4, cooldown 40 s [IL L99243-99788] (straddles L99500; read to its end)

* **Targeting:** every non-boss enemy on the field, in three distance tiers measured from the Witch;
  no target needed. **`aoeRadiusBonus` is NOT added** to these boxes.
* **Timeline**
  1. t=0: `disableSpecials = true`; `dimBackground = true`; `noHitReact = true`;
     `myAnimation.Play("specialCast")` (no weapon animation call); `mySounds[5].Play()`;
     `cameraShaker.Play("shake")`; `activateColors()`; `colorSpeed = 0.8`; material colour (0,0,0)
     [IL L99252-99303].
  2. wait **0.25 s**; `myEffects[7].activate(self.position, null)`;
     `myEffects[8].activate(self.position, null)` [IL L99304-99332].
  3. wait **0.17 s**; `cameraShaker.Stop("shake")` + `Play("shake")` [IL L99333-99351].
  4. Loop (breaks at first null enemy) [IL L99352-99762]; for each enemy the first matching tier
     applies:

     | Tier | Condition | Effect | IL |
     |---|---|---|---|
     | 1 (closest) | `|dx| < 1.4` and `|dz| < 1.0` and `health > 0` and `!likeABoss` and `myRenderer.enabled` | Roll `Random.Range(1, 101)` (int 1..100). If roll `<= 25` **and** `!immuneToDeath` → `takeDamage(10000000, Vector3(0,0,0), self)` (instant kill, 25%). Otherwise `debuffs[1] = 8`; `debuffColor = (0.34, 0.16, 0.57)`; `mostRecentDebuff = 1` | L99368-99518 |
     | 2 (middle) | else `|dx| < 2.1` and `|dz| < 1.6` and `health > 0` and `!likeABoss` and `myRenderer.enabled` | `debuffs[1] = 6`; `debuffColor = (0.34, 0.16, 0.57)`; `mostRecentDebuff = 1` | L99520-99634 |
     | 3 (everything else) | else `health > 0` and `!likeABoss` (no visibility test) | `debuffs[5] = 4`; `debuffColor = (0.34, 0.16, 0.57)`; `mostRecentDebuff = 5`; `fearLocation = Vector3(Random.Range(−edge + 0.7, edge − 0.7), 0, Random.Range(floor + 0.9, cieling − 0.8))`; `fearTimer = Random.Range(0.6, 1.0)` | L99636-99739 |

     Because tier tests are chained with "else", an enemy inside the tier-1 box that is hidden
     (`myRenderer.enabled == false`) falls through to tier 2's test (fails the same way) and then gets
     the tier-3 fear.
  5. wait **0.55 s**; `dimBackground = false`; `disableSpecials = false`; `noHitReact = false`;
     `returnToNormal()` [IL L99764-99787].
* **Effect summary:** close enemies: 25% instant death (unless `immuneToDeath`), else 8 s of debuff 1;
  mid-range: 6 s of debuff 1; far: 4 s of fear (debuff 5). Durations are literal constants here, not
  table lookups. Bosses (`likeABoss`) are completely unaffected. No damage besides the kill.

**End of part 1 — stopped at IL L99788.** Witch *Hex* (abilities id 5) begins at IL L99790.

---

## 10. Quick reference tables

### 10.1 Cast timeline (seconds between steps, in order; total = sum, excluding the pre-cast freeze of §4.1)

| Ability | Waits | Effect lands at | Total |
|---|---|---|---|
| Group Heal | 1.0 | 0 | 1.0 |
| Shield / Power Infusion | 0.5 | 0 | 0.5 |
| Guardian / Vengeful Angel | 1.0 | 0 | 1.0 |
| Shield Wall | 0.7 | 0 | 0.7 |
| Cleave | 0.04, 0.168, 0.19, 0.34 | 0.04 / 0.208 / 0.398 | 0.738 |
| Intimidate | 0.12, 0.58 | 0 | 0.70 |
| War Cry | 0.12, 0.58 | 0 | 0.70 |
| Shield Rush / Sneak Attack / Expose Weakness | none | 0 (buff only) | 0 |
| Poisoned / Paralytic Knife | 0.5 | projectile launched at 0 | 0.5 |
| Shadowstep | 0.5 | teleport at 0.5 | 0.5 |
| Meteor | 0.35, 0.27, 0.14, 0.06*, 0.1, 0.4 | 0.62 | 1.32 |
| Blizzard | 0.2, 0.6 | 0.2 | 0.8 |
| Time Stop | 0.2, 0.6 | 0.2 | 0.8 |
| Conflagrate | 0.2, 0.09, 0.06*, 0.3, 0.2 | 0.2 | 0.85 |
| Thunderbolt | 0.12, 0.26, 0.15, 0.02*, 0.3, 0.2 | 0.38 | 1.05 |
| Drain Life | 0.2, 0.6, 0.1 | 0.8 | 0.9 |
| Plague | 0.2, 0.3, 0.35 | 0.2 | 0.85 |
| Debilitate | 0.2, 0.7 | 0.2 | 0.9 |
| Horror | 0.25, 0.17, 0.55 | 0.42 | 0.97 |

\* wait issued while `Time.timeScale` is 0.1 (Meteor, Thunderbolt) or 0.2 (Conflagrate). Totals add the
literal values; UNVERIFIED engine behaviour: `WaitForSeconds` counts scaled time, so in real time those
waits last 10× / 5× longer.

### 10.2 Damage / heal formulas

| Ability | Amount | Crit? | Knockback |
|---|---|---|---|
| Group Heal | heal `int(power × buffMagnitudes[3])` (×1.25 Desperate Prayer) | no | — |
| Cleave | `int(power × buffMagnitudes[10] × crit)` × 3 sweeps | yes, per hit | dir × impactForce × 0.5 / 0.5 / 1.5 |
| Meteor | `int(power × 2 × crit)` | yes | dir(from impact) × impactForce × 2 |
| Meteor burn (Flaming Meteor) | `meteorDotMagnitude = debuffMagnitudes[8] × power × 2 × calculateDamageMultiplier` | no | — |
| Blizzard | `int(power × crit)` | yes | (1,0,0) × impactForce |
| Conflagrate | `int(power × crit)`; DoT `conflagDotMagnitude = power × debuffMagnitudes[9] × calculateDamageMultiplier` | hit only | dir × impactForce |
| Thunderbolt | `int(power × 3 × crit)` | yes | dir × impactForce × 2 |
| Drain Life | `int(modifier × power × 2)` (× 1.4 Crushing Despair); modifier 1.4 with Prey on the Weak vs debuff 1/5/13 | no | dir × impactForce |
| Plague | 1; DoT `plagueDotMagnitude = power × debuffMagnitudes[15]` | no | none |
| Debilitate | 1 | no | none |
| Horror | 10,000,000 on a 25% roll (tier 1 only) | no | none |

### 10.3 AoE boxes (half-extents)

| Ability | Centre | half X | half Z | + aoeRadiusBonus | Boss excluded | Needs renderer enabled |
|---|---|---|---|---|---|---|
| Cleave | Knight | 1.5 | 1.0 | yes | no | yes |
| Intimidate | Knight | 1.5 | 1.0 | yes | yes (and ends loop) | yes |
| War Cry | — (all) | — | — | — | no | no |
| Meteor | `myEffects[2]` position (= target position at cast) | 1.5 | 1.0 | yes | no | yes |
| Blizzard / Time Stop | — (all with x < 10) | — | — | — | no | yes |
| Thunderbolt | Wizard | 2.0 | 1.5 | yes | no | yes |
| Plague | target position at cast | 1.5 | 1.0 | yes | no | yes |
| Horror tier 1 | Witch | 1.4 | 1.0 | no | yes | yes |
| Horror tier 2 | Witch | 2.1 | 1.6 | no | yes | yes |
| Horror tier 3 | — (all others) | — | — | — | yes | no |

### 10.4 Animation, sound and effect identifiers

Animation clip names are literal strings. `mySounds[n]` / `myEffects[n]` are indices into prefab-
serialized arrays (names not in the IL).

| Ability | Body anim | Weapon anim | Sound idx | Effect idx (where) | Camera / scene |
|---|---|---|---|---|---|
| Group Heal | `specialCast` | `cast` | 2 | 4 (caster), 0..3 (ally i) | — |
| Shield | `specialCast` | `cast` | 0 | 5 (recipient) | — |
| Power Infusion | `specialCast` | `cast` | 3 | 6 (recipient) | — |
| Guardian Angel | `specialCast` | `cast` | 5 | 7 (self) | — |
| Vengeful Angel | `specialCast` | `cast` | 5 | 7 (self) | — |
| Shield Wall | `shieldWall` | — | 7 | 1 (self) | disableSpecials |
| Cleave | `cleave` | — | 5 | 4, 5 (offset from self) | disableSpecials |
| Intimidate | `intimidate` | — | 8 | 10, then 11 (self pos) | `shake` ×2, disableSpecials |
| War Cry | `intimidate` | — | 8 | 2, then 3 (self pos) | `shake` ×2, disableSpecials |
| Shield Rush | — | — | — | — | — |
| Sneak Attack / Expose Weakness | — | — | — | — | — |
| Poisoned Knife | `throw` | — | 7 | 2 (projectile → target) | — |
| Paralytic Knife | `throw` | — | 7 | 5 (projectile → target) | — |
| Shadowstep | `hide` (`idle` if target lost) | — | 9 | 7, 8 (self pos) | — |
| Meteor | `specialCast` | `cast` | 4 | 2 (meteor), 3, 4 (impact) | `shake`, dimBackground, disableSpecials, timeScale 0.1 |
| Blizzard | `specialCast` | `cast` | 5 | 10 at (0,4.2,−7), 11 at (0,4,−6) | — |
| Time Stop | `specialCast` | `cast` | 7 | 10 at (0,4.2,−7), 12 at (0,4.4,−6) | — |
| Conflagrate | `specialCast` | `cast` | 6 | 8, 9 (target pos), 7 (attached to target) | `shake`, dimBackground, disableSpecials, timeScale 0.2 |
| Thunderbolt | `specialCast` | `cast` | 3 | 16, then 17 (self pos) | `shake`, dimBackground, disableSpecials, timeScale 0.1 |
| Drain Life | `specialCast` | `cast` | 4 | 4 (on target), 5 (heal projectile target → ally) | `shake` |
| Plague | `specialCast` | `cast` | 6 | 9, 10 (zone) | `shake`, dimBackground, disableSpecials |
| Debilitate | `specialCast` | `cast` | 7 | 11 (attached to target) | — |
| Horror | `specialCast` | — | 5 | 7, 8 (self pos) | `shake` ×2, dimBackground, disableSpecials |

(IL citations for every cell are in the per-ability sections 5–9.)

---

## 11. Uncertain / not determined

* **Table values.** `MotherBrain.buffDurations[]`, `buffMagnitudes[]`, `debuffDurations[]`,
  `debuffMagnitudes[]` are never assigned in the assembly (only read, e.g. [IL L4580, L18506]); they are
  serialized on the scene/prefab and are not in `bh/data`. Therefore the following are **unknown from
  code**: durations of Shield (2), Power Infusion (4), Favored Soul (5), Guardian Angel (6), Vengeful
  Angel (7), Shield Wall (0), Sneak Attack (1), Expose Weakness (8), Shadowstep (9), Shield Rush (11);
  enemy debuff durations 5, 8, 9, 10, 11, 14, 15; magnitudes `buffMagnitudes[3]` (Group Heal),
  `buffMagnitudes[10]` (Cleave), `debuffMagnitudes[8]`, `[9]`, `[15]` (DoT factors). Tooltip numbers in
  `classes.json` are hints only.
* **Effect and sound names.** `myEffectNames[]` (resource paths) and `mySounds[]` clips are prefab data;
  only indices are known.
* UNVERIFIED: meanings of debuff ids 1, 3, 4, 10, 11, 14 (see §3.5) — inferred from the abilities that
  set them; confirm in the EnemyScript docs.
* UNVERIFIED: that slot 0 always holds ability id 1, slot 1 holds 2/3, slot 2 holds 4/5 (§2.2).
* UNVERIFIED: real-time length of waits issued while `Time.timeScale < 1` (Unity `WaitForSeconds`
  semantics, not visible in the IL).
* Not determined here (code outside this range): how `buffs[1]`, `[8]`, `[9]`, `[11]` are consumed by
  `$meleeAttack`/`AI`; what the knife projectiles (`myEffects[2]`, `[5]` of the Rogue) do on impact; how
  `EffectScript.healAmount` is delivered for Drain Life; what `bardCoefficient = 0.7` changes during
  Cleave; whether Blitz is triggered for Shield Rush (it is **not** in this branch); the per-tick
  behaviour of Blizzard (debuff 10) and of the DoT magnitudes.
* `dimBackground = false` is written in Drain Life although that branch never sets it true
  [IL L98562-98566]; harmless (it was already cleared by `specialMove`).

### Contradictions with older notes (`work/class-port-spec-cleric-paladin-wizard-rogue.md`)

* Line 91 says Guardian Angel "sets `disableSpecials=true` during cast [IL L93994+]" with a
  "`shieldWall`-style" animation. Wrong: L93991–94167 is Power Infusion; Guardian Angel is
  L94169–94276, plays `specialCast` + weapon `cast`, and never touches `disableSpecials`.
* Line 89 cites the Shield buff write at "[IL L93992+]". Shield is L93813–93989 and writes `buffs[2]`;
  L93991+ is Power Infusion (`buffs[4]`).
* Line 246 cites the `"throw"` animation at [IL L93892]. That line is a `Color` constructor inside
  Cleric Shield; `"throw"` is at [IL L96158] (Poisoned Knife) and [IL L96238] (Paralytic Knife).
* That note's Group Heal entry (heal = `int(power·buffMagnitudes[3])`, ×1.25 with `passives[3]==-1`,
  tutorial state 41) agrees with the IL.

---

## 12. Cross-references

| Symbol | Lines | Relation |
|---|---|---|
| `PartyMember.performSpecial` (stub) | 86025–86036 | creates this coroutine |
| `MotherBrain.$specialMove$1664` | 71940–72397 | button handler: pre-cast freeze, cooldown start, starts `performSpecial` (call at L72339) |
| `PartyMember.AI` | 78102–81244 | re-fires `performSpecial(specialAwaitingTarget)` when a target appears (L78296–78423); reads `buffs[11]` (L80622) |
| MotherBrain party setup | 59731–60061 | copies `abilities`, `passives`, `cooldowns` from the database |
| `PartyMember.initialize` | 77121–78037 | applies flat passive bonuses (source of the passive sign mapping) |
| `PartyMember.returnToNormal` | 86365–86421 | called at the end of every branch |
| `PartyMember.calculateCrit` | 87112–87142 | ×2 crit roll |
| `PartyMember.calculateDamageMultiplier` | 86534–86610 | used for Meteor burn / Conflagrate DoT magnitudes |
| `PartyMember.heal(int, PartyMember)` | 82423–82590 | Group Heal target call; reads `buffs[4]`, `[6]` |
| `PartyMember.takeDamage` | 81497–82407 | consumes hero buffs 0, 2, 5 |
| `PartyMember.clericAuraAttack` | 84371–84586 | Vengeful Angel pulse (reads `buffs[7]`, `auraTimer`) |
| `PartyMember.$meleeAttack$1838` | 90106–92750 | consumes Rogue buffs 1, 8, 9 and Knight buff 11 |
| `PartyMember.requestPosition` / `purgePosition` / `findMovementTarget` | 84991–85546 / 85549–85703 / 81247–81333 | melee-slot bookkeeping used by War Cry and Shadowstep |
| `PartyMember.returnDamageValue` | 86850–86860 | writes `returnedDamage` (Drain Life heal) |
| `PartyMember.createMyEffects` | 86613–86752 | instantiates `myEffects[]` from `myEffectNames[]`; entries with `myEffectPrereqs` 2/3 are only created if `abilities[1]` is 2/3, prereqs 4/5 only if `abilities[2]` is 4/5 |
| `EnemyScript.takeDamage` / `hypotheticalDamage` | ≈18463–19064 / ≈19194–19436 | damage resolution for every hit here |
| `EnemyScript.AI` | reads at 6049, 6348, 6375, 6420, 6893 | behaviour under debuffs 11, 1, 3, 5, 10 |
| EnemyScript DoT readers | 22568, 22616, 22712 | `meteorDotMagnitude`, `conflagDotMagnitude`, `plagueDotMagnitude` |
| `EffectScript.activate(Vector3, Transform)` / `damageEnemy` | ≈4003–4400 | visuals and projectile impact (knives, Drain Life heal orb) |
| Part 2 of this coroutine | 99790–105808 | Witch Hex, Bard, Barbarian, Monk, Ranger, Paladin |

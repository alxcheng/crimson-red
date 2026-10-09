# Hero active abilities, part 2 — Witch (Horror, Hex), Bard, Barbarian, Monk, Ranger, Paladin

**Scope:** class `PartyMember`, coroutine body `$performSpecial$1850` → nested class `$` → `MoveNext`,
second half: IL lines **99245–105808** of `Assembly-UnityScript.il`.
The assigned range starts at 99500, which falls in the middle of the Witch ability *Horror*; this
document therefore **starts at line 99245**, where Horror begins. Part 1 (lines 93226–99244:
Cleric, Knight, Rogue, Wizard, Witch abilities 1–3) is another document.

Three abilities in this range only *arm* something in `performSpecial` and are resolved in other
coroutines. Because a porter needs the whole ability, those resolutions are documented here too
(sections 6.4, 6.5, 7.4), read from `$meleeAttack$1838` (L90106–92750), `PartyMember.AI`
(L81179–81231) and `$pounceAttack$1845` (L92752–93224).

All citations are `[IL Lnnnnn]` = line numbers in the `.il` file.

---

## 1. Summary

When the player taps one of a hero's three ability buttons, the game starts
`PartyMember.performSpecial(specialSlot)` on that hero. The coroutine looks at the hero's class
(`characterClass`, 1–10) and at which ability is equipped in that slot (`abilities[specialSlot]`,
1–5) and runs one hard-coded script per (class, ability) pair. A script typically: plays a cast
animation and a sound, spawns pooled visual effects, waits a fraction of a second, then applies
damage / healing / timed buffs / timed debuffs, waits again, and hands control back to the normal AI
(`returnToNormal`).

This part covers 27 scripts: Witch *Horror* and *Hex*; all five Bard songs; all five Barbarian
abilities; all five Monk abilities; all five Ranger shots; all five Paladin abilities.
Flashy abilities dim the background, lock every other ability button (`disableSpecials`), make the
caster invincible and/or slow global time to 10 % for a "freeze-frame" feel.

Buff **durations and magnitudes are not in the code**: scripts copy
`motherBrain.buffDurations[n]` / `debuffDurations[n]` into the target's timer array. Those arrays
are public Inspector-serialized fields on `MotherBrain` with no initialiser in the IL
[IL L59140-59143]. Only literal durations (e.g. Horror's 8 / 6 / 4 s) are known from this code.

---

## 2. Dispatch

### 2.1 How dispatch works

```
performSpecial(int specialSlot)                         [IL L86025-86036] (stub; builds the coroutine)
MoveNext:
  switch(_state) { 91 resume points }                   [IL L93497-93590]
  tempVector = (0,0,0); i = 0                           [IL L93591-93596]
  if (characterClass == 1) { if (abilities[specialSlot] == 1) {...} else if (== 2) ... }   [IL L93599-93610]
  else if (characterClass == 2) ...                     (part 1)
  ...
  else if (characterClass == 5) { ... abilities 4, 5 documented here }   [IL L98325-98327, L99245-99250, L99792-99797]
  else if (characterClass == 6) ...                     [IL L99923-99925]
  else if (characterClass == 7) ...                     [IL L101035-101037]
  else if (characterClass == 8) ...                     [IL L102318-102320]
  else if (characterClass == 9) ...                     [IL L103916-103918]
  else if (characterClass == 10) ...                    [IL L104609-104611]
  yield default; end                                    [IL L105799-105803]
```

* `characterClass` in code = `id + 1` of `bh/data/classes.json` (1 Cleric, 2 Knight, 3 Rogue,
  4 Wizard, 5 Witch, 6 Bard, 7 Barbarian, 8 Monk, 9 Ranger, 10 Paladin). Confirmed for this range by
  matching behaviour to descriptions (e.g. class 6 heals/buffs the party = Bard; class 9 fires
  "specialShot" = Ranger) and by `bh/data/party.json` (`characterClass` 1 = the Cleric Lucille).
* `abilities[]` has three entries, one per button; `specialSlot` is the button index 0–2.
  The stored value 1–5 maps to the `whichPower` index in `classes.json` as
  **1→index 0, 2→index 1, 3→index 2, 4→index 5, 5→index 6**. UNVERIFIED as a rule (the code that
  writes `abilities[]` is outside this range) but every one of the 27 scripts here matches the
  description of the power at that index.
* When a targeted ability is used with no target, the script stores the button index in
  `specialAwaitingTarget` and exits; the values stored are 0 for ability 1, 1 for abilities 2/3 and
  2 for abilities 4/5 (e.g. [IL L99914-99915], [IL L103992-103993], [IL L104071-104072],
  [IL L104150-104151], [IL L104600-104601]). This shows ability 1 lives in slot 0, abilities 2 or 3
  in slot 1, abilities 4 or 5 in slot 2. `PartyMember.AI` later re-invokes
  `performSpecial(specialAwaitingTarget)` once `specialAwaitingTarget > -1` and `myTarget` exists
  [IL L78297-78304, L78420-78422].

### 2.2 Dispatch table (this document)

Cooldowns are from `bh/data/classes.json` (`whichPower[index].cooldown`, seconds).

| characterClass (json id) | Class | abilities[] value | json power index | Ability | Cooldown | IL lines |
|---|---|---|---|---|---|---|
| 5 (4) | Witch | 4 | 5 | Horror | 40 | 99245–99788 |
| 5 (4) | Witch | 5 | 6 | Hex | 40 | 99792–99919 |
| 6 (5) | Bard | 1 | 0 | Song of Renewal | 20 | 99929–100236 |
| 6 (5) | Bard | 2 | 1 | Song of Vigor | 30 | 100240–100448 |
| 6 (5) | Bard | 3 | 2 | Song of Sanctuary | 30 | 100452–100653 |
| 6 (5) | Bard | 4 | 5 | Song of War | 30 | 100657–100858 |
| 6 (5) | Bard | 5 | 6 | Song of Inspiration | 60 | 100862–101031 |
| 7 (6) | Barbarian | 1 | 0 | Enrage | 30 | 101041–101122 |
| 7 (6) | Barbarian | 2 | 1 | Frenzy | 30 | 101126–101207 |
| 7 (6) | Barbarian | 3 | 2 | Whirlwind | 30 | 101211–102207 |
| 7 (6) | Barbarian | 4 | 5 | Reckless Blow | 30 | 102211–102228 (+ melee L91086–91370) |
| 7 (6) | Barbarian | 5 | 6 | Savage Pounce | 30 | 102232–102314 (+ AI L81179–81231, pounce L92752–93224) |
| 8 (7) | Monk | 1 | 0 | Wind Walk | 40 | 102324–103240 |
| 8 (7) | Monk | 2 | 1 | Evasion | 30 | 103244–103365 |
| 8 (7) | Monk | 3 | 2 | Ki Blast | 30 | 103369–103762 |
| 8 (7) | Monk | 4 | 5 | 1000 Palms | 30 | 103766–103787 (+ melee L90263–90867) |
| 8 (7) | Monk | 5 | 6 | Spirit Trance | 40 | 103791–103912 |
| 9 (8) | Ranger | 1 | 0 | Aimed Shot | 20 | 103922–103997 |
| 9 (8) | Ranger | 2 | 1 | Incendiary Arrow | 30 | 104001–104076 |
| 9 (8) | Ranger | 3 | 2 | Vile Bolt | 30 | 104080–104155 |
| 9 (8) | Ranger | 4 | 5 | Barrage | 30 | 104159–104526 |
| 9 (8) | Ranger | 5 | 6 | Apollo Strike | 30 | 104530–104605 |
| 10 (9) | Paladin | 1 | 0 | Holy Word | 30 | 104615–104975 |
| 10 (9) | Paladin | 2 | 1 | Wrath | 30 | 104979–105056 |
| 10 (9) | Paladin | 3 | 2 | Aura of Light | 40 | 105060–105137 |
| 10 (9) | Paladin | 4 | 5 | Divine Intervention | 30 | 105141–105364 |
| 10 (9) | Paladin | 5 | 6 | Radiance | 30 | 105368–105797 |

**The cooldown is not started inside `performSpecial`.** No script in this range writes the
caster's own `remainingCooldowns[]` (the only write is Song of Inspiration zeroing *other* heroes'
cooldowns, section 5.5). The caller (`MotherBrain.$specialMove$1664`, call at [IL L72339]) is
outside this scope — see section 11.

---

## 3. Conventions, fields and shared helpers

### 3.1 Passive talents (`passives[]`)

`passives` is an `int32[]` [IL L76927] indexed by talent tier 0–3; each entry is `0` (not taken),
`+1` or `-1` (which of the two talents of that tier). `party.json` shows four entries per hero.
Mapping to `classes.json` power indices — **UNVERIFIED as a general rule** (the talent menu is out
of scope) but consistent with every use in this range:

| passives[] index | value +1 | value −1 |
|---|---|---|
| 0 | power index 3 | power index 4 |
| 1 | power index 7 | power index 8 |
| 2 | power index 9 (single talent; code tests "non-zero") | — |
| 3 | power index 10 | power index 11 |

Passive names given below are derived with this table and are each consistent with the json
description (e.g. Bard `passives[1]==1` multiplies heals by 1.25 = "Healing Chords … 25% more
effective", index 7).

### 3.2 Fields read or written in this range

`PartyMember` fields (declarations [IL L76919-77025]; defaults from `.ctor` [IL L77028-77118]):

| Field | Type | Meaning in these scripts | Default |
|---|---|---|---|
| `characterClass` | int | class id + 1, first dispatch key | 1 [IL L77040-77041] |
| `abilities` | int[] | equipped ability per button, second dispatch key | — |
| `passives` | int[] | talent choices, see 3.1 | — |
| `power` | float | attack/heal stat used in every formula | 15 [IL L77061-77062] |
| `impactForce` | float | knock-back vector length passed to `takeDamage` | 2 [IL L77067-77068] |
| `health`, `maxHealth` | float | HP | 1000 / 1000 [IL L77079-77083] |
| `critChance` | int | percent, used by `calculateCrit()` | — |
| `buffs` | float[] | remaining seconds per buff index (hero side) | — |
| `remainingCooldowns` | float[] | seconds left per button (3 entries) | — |
| `myEffects` | EffectScript[] | pooled visual/projectile effects, per-class index | — |
| `mySounds` | AudioSource[] | per-class sound index | — |
| `myAnimation` | Animation | body animation | — |
| `myWeaponAnimation` | Animation | weapon animation (Witch) | — |
| `basicAction` | AnimationState | state of the "attack" clip (speed is changed) | — |
| `specialAction` | AnimationState | state of the special clip (Ranger: speed changed) | — |
| `myTarget` | Transform | current target (enemy, or ally for Bard) | — |
| `myTargetEnemyScript` | EnemyScript | target's script if it is an enemy | — |
| `myTransform`, `myRenderer` | Transform/Renderer | own transform / renderer (tint colour) | — |
| `motherBrain` | MotherBrain | battle manager | — |
| `noHitReact` | bool | true while casting: hero does not play hit reactions | — |
| `invincible` | bool | true during Wind Walk, Barrage, Savage Pounce flight | — |
| `commandPending` | bool | set during Whirlwind and Savage Pounce | — |
| `specialAwaitingTarget` | int | −1 = none; else button index waiting for a target | −1 [IL L77115-77116] |
| `AIState` | int | 0 idle, 1 moving, 2 attacking target, 3 "special in flight" (pounce / 1000 Palms), 5 set by AI before a deferred special [IL L86372-86419, L78307-78308] | — |
| `colorSpeed` | float | speed of tint fade started by `activateColors()` | 2 [IL L77049-77050] |
| `colorPulseTimer` | float | timer for the buff-colour pulse | — |
| `buffColor` | Color | colour of the buff pulse | (0.25,0.25,0.25) [IL L77109-77113] |
| `mostRecentBuff` | int | index of last buff applied (drives pulse colour logic) | — |
| `alphaAnim` | bool | enables alpha fade-in (Wind Walk teleports) | — |
| `bardCoefficient` | float | temporary multiplier set around multi-hit damage calls (0.75 Whirlwind, 0.3 1000 Palms), restored to 1 right after. Its consumer is outside this scope. | 1 [IL L77094-77095] |
| `bardHotMagnitude` | float | per-tick heal amount of Song of Vigor, written on each ally | — |
| `tempAllyScript` | PartyMember | scratch: ally targeted by Song of Renewal | — |
| `myProtector` | PartyMember | set on allies by Divine Intervention = the Paladin | — |
| `whichVolley` | int | rotating effect index 18→19→20→18 for Barrage arrows | 18 [IL L77091-77092] |
| `pounceDestination`, `pounceSpeed`, `pounceTimer` | Vector3/float/float | Savage Pounce flight | — |
| `movementTarget` | Vector3 | where the AI walks to; reset after Wind Walk | — |

`MotherBrain` fields used: `playerScripts` (PartyMember[] — heroes), `enemyScripts`
(EnemyScript[]), `buffDurations`, `debuffDurations` (float[]), `disableSpecials` (bool — all ability
buttons locked), `dimBackground` (bool), `cameraShaker` (Animation with clips `"shake"`,
`"powerUpShake"`), `fullScreenFlash` (EffectScript), `edge`, `floor`, `cieling` (sic; arena bounds),
`activeEnemies` (int).

`EnemyScript` fields used: `myTransform`, `myRenderer`, `health`, `likeABoss`, `immuneToDeath`,
`tauntable`, `aoeRadiusBonus`, `debuffs` (float[] seconds), `debuffColor`, `mostRecentDebuff`,
`fearLocation`, `fearTimer`, `meleePositions` (Vector3[]), `myAnimation`.

Coroutine locals (hoisted to fields [IL L93272-93309]): `$tempVector` (knock-back direction),
`$i` (loop index — survives yields), `$validTargets`, `$numberOfStrikes`, `$initialPosition`
(Wind Walk), `$tookAShot` (Barrage), `$lowestHealthAlly` (Holy Word), `$originalTauntability`
(Radiance).

### 3.3 Buff / debuff indices seen in this range

Hero `buffs[]` (value = seconds remaining). Effects of each buff are implemented elsewhere
(`handleBuffs`, `takeDamage`, `meleeAttack` …); the "meaning" column is the json description of the
ability that sets it, i.e. UNVERIFIED from this code.

| Index | Set by | Value written | Pulse colour (r,g,b) |
|---|---|---|---|
| 1 | Barbarian Reckless Blow | literal `500` [IL L102220-102224] | — |
| 1 | Monk 1000 Palms | `buffDurations[1]` [IL L103775-103783] | — |
| 15 (0x0f) | Barbarian Enrage | `buffDurations[15]` | (0.76, 0.34, 0.34) |
| 17 (0x11) | Barbarian Frenzy | `buffDurations[17]` | (0.76, 0.34, 0.34) |
| 19 (0x13) | Bard Song of Vigor (all allies) | `buffDurations[19]` | (0.25, 0.45, 0.25) |
| 20 (0x14) | Bard Song of Sanctuary (all allies) | `buffDurations[20]` (+5 with Enduring Hope) | (0.30, 0.30, 0.45) |
| 21 (0x15) | Bard Song of War (all allies) | `buffDurations[21]` (+5 with Enduring Hope) | (0.45, 0.30, 0.30) |
| 23 (0x17) | Monk Evasion | `buffDurations[23]` | (0.34, 0.34, 0.75) |
| 24 (0x18) | Monk Spirit Trance | `buffDurations[24]` | (0.54, 0.54, 0.54) |
| 26 (0x1a) | Paladin Holy Word + Word of Asylum (on healed ally) | `buffDurations[26]` | (0.34, 0.34, 0.75) |
| 27 (0x1b) | Paladin Holy Word + Word of Retribution (on healed ally) | `buffDurations[27]` | (0.75, 0.34, 0.34) |
| 28 (0x1c) | Paladin Aura of Light (self) | `buffDurations[28]` | (0.5, 0.5, 0.25) |
| 29 (0x1d) | Paladin Wrath (self) | `buffDurations[29]` | (0.5, 0.5, 0.25) |
| 30 (0x1e) | Paladin Divine Intervention (each other ally) | `buffDurations[30]` | (0.5, 0.5, 0.3) |

Enemy `debuffs[]` (value = seconds remaining). Meanings are UNVERIFIED inferences from the ability
descriptions; the code that reads them is in `EnemyScript`.

| Index | Written by | Value | Inferred meaning |
|---|---|---|---|
| 1 | Horror (near / mid ring) | 8 / 6 | paralysed ("helpless") |
| 3 | Whirlwind 4th hit, Ki Blast, Radiance, Savage Pounce + Blunt Trauma, Reckless Blow + Blunt Trauma, 1000 Palms finisher | 1.7 / 3 / 3.5 / 3.5 / 3.5 / 1.7 | knocked down |
| 4 | always written together with index 3 | 0.2 (0.15 for the two Blunt Trauma cases) | short companion timer of the knock-down |
| 5 | Horror (far ring) | 4 | fear (runs to `fearLocation`) |
| 10 (0x0a) | Wind Walk + Sweep the Leg | 6 | movement slow |
| 13 (0x0d) | Hex | `debuffDurations[13]` | hexed (toad) |

### 3.4 Shared helpers called by these scripts

| Call | Lines | What it does (as read) |
|---|---|---|
| `returnToNormal()` | 86365–86421 | `commandPending=false`. Unless `motherBrain.levelComplete` or `AIState==3`: if `myTarget != null` → `AIState=2`, `actionTimer=100`; else if distance(position, movementTarget) > 0.07 → `AIState=1`; else `AIState=0` and `myAnimation.CrossFade("idle", 0.15)` [IL L86372-86419] |
| `returnToNormalFromShot()` | 86424–86477 | identical except it does **not** set `actionTimer=100` [IL L86431-86475] |
| `returnToNormalFromPounce()` | 86480–86531 | like `returnToNormal` but without the `AIState==3` early-out [IL L86487-86529] |
| `calculateCrit()` → int | 87112–87142 | if `critChance > 0` and `Random.Range(0,100) <= critChance` return 2, else 1 [IL L87119-87139]. Used as a damage multiplier. |
| `activateColors()` | 84223–84239 | starts the tint fade from the colour just written into `myRenderer.material.color` back to normal at `colorSpeed` (body not re-read here) |
| `updateHealthBar(1)` | 82781–83186 | called after flipping `localScale.x` so the health bar is not mirrored (body not re-read here) |
| `heal(int amount, PartyMember healer)` | 82423–82590 | heals the receiver (bonuses/caps inside, not in this scope) |
| `EnemyScript.takeDamage(int dmg, Vector3 force, PartyMember attacker)` | — | damage + knock-back on an enemy (armor, lifesteal etc. inside) |
| `EffectScript.activate(Vector3 pos, Transform parentOrTarget)` | — | plays pooled effect `myEffects[n]` at `pos`; second argument `null` = free-standing, otherwise the effect follows / flies to that transform |

**Effect and sound names are not in the code.** `myEffects[n]` are instantiated from the
Inspector-serialized string array `myEffectNames` via `Resources.Load` [IL L86691-86695]; `mySounds`
is likewise serialized. Only the indices are known; they are recorded per ability below.

**Slow motion.** Several scripts set `Time.timeScale = 0.1` (or 0.05) and then `yield
WaitForSeconds(x)`. UNVERIFIED (Unity engine behaviour, not visible in IL): `WaitForSeconds` counts
scaled time, so the real-time wait is `x / timeScale`. Both numbers are given.

**Enemy loops.** Every loop over `motherBrain.enemyScripts` in this range treats the first `null`
slot as end-of-list: it sets `i = enemyScripts.length` (or 10000) and stops (e.g.
[IL L99745-99748], [IL L101441-101444]). Loops over `playerScripts` simply skip null slots.

---

## 4. Witch (characterClass 5) — abilities 4 and 5

### 4.1 Horror — `abilities == 4` [IL L99245-99788]

*json: "Fear consumes all enemies - the severity of the effect increases with proximity to you."
Cooldown 40.*

Targeting: no target needed; affects **all living non-boss enemies**, effect chosen by distance
from the Witch (axis-aligned box test on x and z, not a circle).

Timeline:

1. t=0: `motherBrain.disableSpecials = true`, `dimBackground = true`, `noHitReact = true`
   [IL L99254-99265]; `myAnimation.Play("specialCast")` [IL L99268-99270]; `mySounds[5].Play()`
   [IL L99274-99277]; `cameraShaker.Play("shake")` [IL L99280-99283]; `activateColors()`,
   `colorSpeed = 0.8`, renderer colour = (0,0,0) (flash to black) [IL L99286-99303].
2. wait **0.25 s** [IL L99305-99307].
3. `myEffects[7].activate(self.position, null)` and `myEffects[8].activate(self.position, null)`
   [IL L99313-99332].
4. wait **0.17 s** [IL L99334-99336].
5. `cameraShaker.Stop("shake")`, `Play("shake")` [IL L99342-99351]; then for each enemy `e`
   (stop at first null [IL L99360-99366, L99745-99748]), with
   `dx = |e.x − self.x|`, `dz = |e.z − self.z|`:

   ```
   if dx < 1.4 and dz < 1.0 and e.health > 0 and !e.likeABoss and e.myRenderer.enabled:   [IL L99370-99447]
       if Random.Range(1,101) <= 25 and !e.immuneToDeath:                                 [IL L99449-99463]
           e.takeDamage(10000000, Vector3(0,0,0), self)        # 25 % instant kill        [IL L99467-99482]
       else:
           e.debuffs[1] = 8                                                               [IL L99487-99496]
           e.debuffColor = Color(0.34, 0.16, 0.57); e.mostRecentDebuff = 1                [IL L99499-99517]
   elif dx < 2.1 and dz < 1.6 and e.health > 0 and !e.likeABoss and e.myRenderer.enabled: [IL L99522-99599]
       e.debuffs[1] = 6                                                                   [IL L99603-99612]
       e.debuffColor = Color(0.34, 0.16, 0.57); e.mostRecentDebuff = 1                    [IL L99615-99633]
   elif e.health > 0 and !e.likeABoss:                       # note: no renderer check    [IL L99638-99656]
       e.debuffs[5] = 4                                                                   [IL L99660-99669]
       e.debuffColor = Color(0.34, 0.16, 0.57); e.mostRecentDebuff = 5                    [IL L99672-99690]
       e.fearLocation = Vector3( Random.Range(-edge + 0.7, edge - 0.7), 0,
                                 Random.Range(floor + 0.9, cieling - 0.8) )               [IL L99693-99728]
       e.fearTimer = Random.Range(0.6, 1.0)                                               [IL L99731-99739]
   ```
   (`edge`, `floor`, `cieling` are `MotherBrain` floats.) Debuff values are written unconditionally
   (they overwrite a longer existing timer).
6. wait **0.55 s** [IL L99765-99767].
7. `dimBackground = false`, `disableSpecials = false`, `noHitReact = false`, `returnToNormal()`
   [IL L99773-99787].

Total script time 0.97 s. Bosses (`likeABoss`) are completely immune. No passive modifies Horror in
this code.

### 4.2 Hex — `abilities == 5` [IL L99792-99919]

*json: "Your target is turned into a toad for 6 sec., rendering them weak and harmless."
Cooldown 40.*

Targeting: single enemy (`myTarget`).

1. If `myTarget` is null: `specialAwaitingTarget = 2`, `returnToNormal()`, end
   [IL L99801-99803, L99914-99918]. (The ability then fires automatically when a target is chosen,
   section 2.1.)
2. `specialAwaitingTarget = -1`, `noHitReact = true` [IL L99807-99812];
   `myAnimation.Play("specialCast")`; `myWeaponAnimation.Stop()`; `myWeaponAnimation.Play("cast")`
   [IL L99815-99827].
3. wait **0.2 s** [IL L99830-99832].
4. If `myTarget` and `myTargetEnemyScript` both still exist [IL L99838-99846]:
   * `mySounds[2].Play()` [IL L99850-99853];
   * `myEffects[2].activate(myTarget.position, null)` [IL L99856-99864];
   * if the target is **not** `likeABoss` [IL L99867-99869]:
     `myEffects[3].activate(myTarget.position, myTarget)` (attached to target) and
     `target.debuffs[13] = motherBrain.debuffDurations[13]` [IL L99873-99895];
   * wait **0.6 s** [IL L99897-99899].
   If the target vanished during the 0.2 s, skip straight to step 5 (no effect, no extra wait).
5. `noHitReact = false`, `returnToNormal()` [IL L99905-99909].

Duration is `debuffDurations[13]` (not in IL; json text says 6 s). Bosses get the puff effect but
no debuff. No damage is dealt. No passive modifies Hex here.

---

## 5. Bard (characterClass 6) [class check IL L99923-99925]

All five songs share the same shape: `noHitReact = true`, `myAnimation.Play("cast")`, a sound, an
effect, an instant effect on allies, wait **0.7 s**, `noHitReact = false`, `returnToNormal()`.
None needs an enemy target.

Bard passives used: `passives[1] == +1` = **Healing Chords** (json index 7, ×1.25 healing);
`passives[1] == -1` = **Enduring Hope** (index 8, +5 s on song buffs); `passives[3] == -1` =
**Echo of Renewal** (index 11, Renewal hits whole party).

### 5.1 Song of Renewal — `abilities == 1` [IL L99929-100236]

*json: "An invigorating song that instantly heals your target." Cooldown 20.*

```
noHitReact = true; myAnimation.Play("cast"); mySounds[5].Play()                    [IL L99938-99951]
base = 300 + power * 2                                                             [IL L100002-100010]

if passives[3] == -1:                       # Echo of Renewal: whole party         [IL L99954-99958]
    for i, ally in playerScripts where ally != null and ally.health > 0:           [IL L99961-99985, L100067-100078]
        amount = int(base * 1.25) if passives[1] == 1 else int(base)               [IL L99989-100038]
        ally.heal(amount, self)
        myEffects[i + 1].activate(ally.position, ally.myTransform)                 [IL L100041-100064]
elif myTarget != null:                      # single target                        [IL L100084-100086]
    tempAllyScript = myTarget.GetComponent("PartyMember")                          [IL L100089-100096]
    if tempAllyScript != null and tempAllyScript.health > 0:                       [IL L100099-100109]
        amount = int(base * 1.25) if passives[1] == 1 else int(base)               [IL L100113-100154]
        tempAllyScript.heal(amount, self)
    myEffects[1].activate(tempAllyScript.myTransform.position, myTarget)           [IL L100157-100168]
else:                                       # no target: heal self                 [IL L100173-100176]
    if self.health > 0:
        self.heal(int(base), self)          # NOTE: no ×1.25 here even with Healing Chords   [IL L100180-100192]
        myEffects[1].activate(self.position, self.myTransform)                     [IL L100195-100205]

colorSpeed = 1.1; activateColors(); myRenderer.material.color = (1,1,1)            [IL L100208-100221]
wait 0.7 s                                                                         [IL L100223-100225]
noHitReact = false; returnToNormal()                                               [IL L100231-100235]
```

Notes: effect indices 1–4 are used for party members 0–3 in the Echo branch (`i + 1`). In the
single-target branch the effect call is outside the "alive" check, so it plays even on a dead ally
target. If `myTarget` is an enemy, `GetComponent("PartyMember")` returns null and the following
`tempAllyScript.myTransform` access would fault — the code does not guard this [IL L100157-100164].

### 5.2 Song of Vigor — `abilities == 2` [IL L100240-100448]

*json: "The Bard's soothing melodies replenish the party's health over time." Cooldown 30.*

```
noHitReact = true; myAnimation.Play("cast"); mySounds[1].Play()                    [IL L100249-100262]
myEffects[8].activate(self.position, null)                                         [IL L100265-100273]
for each ally in playerScripts where ally != null and ally.health > 0:             [IL L100275-100299, L100421-100432]
    ally.buffs[19] = motherBrain.buffDurations[19]                                 [IL L100303-100316]
    ally.colorPulseTimer = 0.5                                                     [IL L100319-100325]
    ally.buffColor = Color(0.25, 0.45, 0.25)                                       [IL L100328-100337]
    ally.mostRecentBuff = 19                                                       [IL L100340-100346]
    ally.colorSpeed = 2; ally.myRenderer.material.color = (1,1,1); ally.activateColors()   [IL L100349-100380]
    ally.bardHotMagnitude = power * 0.8 * 1.25  if passives[1] == 1                [IL L100383-100403]
                          = power * 0.8          otherwise                         [IL L100408-100418]
wait 0.7 s                                                                         [IL L100435-100437]
noHitReact = false; returnToNormal()                                               [IL L100443-100447]
```

The heal-over-time itself (tick rate, use of `bardHotMagnitude` while `buffs[19] > 0`) is outside
this scope. Unlike Sanctuary and War, **this script does not add Enduring Hope's +5 s** to
`buffs[19]` — see section 11.

### 5.3 Song of Sanctuary — `abilities == 3` [IL L100452-100653]

*json: "The entire party takes 25% less damage for 15 sec. after hearing this tune." Cooldown 30.*

```
noHitReact = true; myAnimation.Play("cast"); mySounds[2].Play()                    [IL L100461-100474]
myEffects[5].activate(self.position, null)                                         [IL L100477-100485]
for each ally in playerScripts where ally != null and ally.health > 0:             [IL L100487-100511, L100626-100637]
    ally.buffs[20] = motherBrain.buffDurations[20]                                 [IL L100515-100528]
    if passives[1] == -1: ally.buffs[20] += 5          # Enduring Hope             [IL L100531-100559]
    ally.colorPulseTimer = 0.5; ally.buffColor = Color(0.30, 0.30, 0.45)           [IL L100562-100580]
    ally.mostRecentBuff = 20                                                       [IL L100583-100589]
    ally.colorSpeed = 2; ally.myRenderer.material.color = (1,1,1); ally.activateColors()   [IL L100592-100623]
wait 0.7 s                                                                         [IL L100640-100642]
noHitReact = false; returnToNormal()                                               [IL L100648-100652]
```

The 25 % reduction is applied where `buffs[20]` is read (outside this scope).

### 5.4 Song of War — `abilities == 4` [IL L100657-100858]

*json: "The Bard's music empowers the party, increasing their damage by 25% for 15 sec."
Cooldown 30.*

Identical to Sanctuary with these substitutions: `mySounds[3]` [IL L100676-100679];
`myEffects[6]` [IL L100682-100690]; buff index **21** = `buffDurations[21]` [IL L100720-100733],
`+5` if `passives[1] == -1` [IL L100736-100764]; `buffColor = Color(0.45, 0.30, 0.30)`
[IL L100776-100785]; `mostRecentBuff = 21` [IL L100788-100794]; same colour flash
[IL L100797-100828]; wait 0.7 s [IL L100845-100847]; end [IL L100853-100857].

### 5.5 Song of Inspiration — `abilities == 5` [IL L100862-101031]

*json: "The party is inspired in their darkest hour, resetting all of their cooldowns."
Cooldown 60.*

```
noHitReact = true; myAnimation.Play("cast"); mySounds[4].Play()                    [IL L100871-100884]
myEffects[7].activate(self.position, null)                                         [IL L100887-100895]
for each ally in playerScripts where ally != null and ally.health > 0 and ally != self:   [IL L100897-100933]
    ally.remainingCooldowns[0] = 0; [1] = 0; [2] = 0                               [IL L100937-100970]
    ally.myRenderer.material.color = (1,1,1); ally.activateColors(); ally.colorSpeed = 1.5   [IL L100973-101001]
wait 0.7 s                                                                         [IL L101018-101020]
noHitReact = false; returnToNormal()                                               [IL L101026-101030]
```

The Bard's own cooldowns are **not** reset (`ally != self` test [IL L100925-100933]).

---

## 6. Barbarian (characterClass 7) [class check IL L101035-101037]

Barbarian passives used for actives: `passives[3] == +1` = **Blunt Trauma** (json index 10, knock
down); `passives[3] == -1` = **Dismemberment** (index 11, +20 % damage). Both apply to Reckless Blow
and Savage Pounce only.

### 6.1 Enrage — `abilities == 1` [IL L101041-101122]

*json: "Fly into a rage, increasing damage dealt AND taken by 35% for 8 sec." Cooldown 30.*
Self buff.

```
noHitReact = true; mySounds[5].Play(); myAnimation.Play("enrage")                  [IL L101050-101062]
myEffects[2].activate(self.position + Vector3(0, 0.15, -0.3), null)                [IL L101066-101080]
buffs[15] = motherBrain.buffDurations[15]                                          [IL L101083-101091]
colorPulseTimer = 0; buffColor = Color(0.76, 0.34, 0.34); mostRecentBuff = 15      [IL L101094-101107]
wait 0.83 s                                                                        [IL L101109-101111]
noHitReact = false; returnToNormal()                                               [IL L101117-101121]
```

The ±35 % (and the Death Wish / Iron Skin / Bloodthirsty passives) are applied where `buffs[15]` is
read, outside this scope.

### 6.2 Frenzy — `abilities == 2` [IL L101126-101207]

*json: "You become a human blur, attacking at a high rate of speed for 10 sec." Cooldown 30.*
Self buff. Same script as Enrage with: `myEffects[4]` at the same offset (0, 0.15, −0.3)
[IL L101151-101165]; `buffs[17] = buffDurations[17]` [IL L101168-101176]; same colour
(0.76, 0.34, 0.34), `mostRecentBuff = 17` [IL L101179-101192]; same sound `mySounds[5]` and
animation `"enrage"` [IL L101139-101147]; wait 0.83 s [IL L101194-101196]; end
[IL L101202-101206].

How Frenzy speeds up attacks (seen in `$meleeAttack$1838`, outside scope but verified): while
`buffs[17] > 0` the "attack" clip speed is set to `motherBrain.buffMagnitudes[17]` and the wind-up
wait becomes `meleeOffset / buffMagnitudes[17]` [IL L90362-90415].

### 6.3 Whirlwind — `abilities == 3` [IL L101211-102207]

*json: "You become a whirlwind of steel, striking out at all adjacent targets." Cooldown 30.*

Targeting: area around the Barbarian, no target needed. Four hits.

Hit test used by every hit (enemy `e`, stop at first null):
`|e.x − self.x| < 1.5 + e.aoeRadiusBonus` **and** `|e.z − self.z| < 1.0 + e.aoeRadiusBonus` **and**
`e.health > 0` **and** `e.myRenderer.enabled` [IL L101295-101380].

Damage of every hit:
```
tempVector = normalize(e.position − self.position)                                 [IL L101385-101400]
bardCoefficient = 0.75                                                             [IL L101403-101404]
e.takeDamage( int(power * 0.75 * calculateCrit()), tempVector * impactForce, self )   [IL L101407-101431]
bardCoefficient = 1                                                                [IL L101434-101435]
```

Timeline:

1. t=0: `commandPending = true`, `disableSpecials = true`, `noHitReact = true`
   [IL L101220-101230]; `basicAction.speed = 1.8` [IL L101233-101235];
   `myAnimation.Play("attack")` [IL L101238-101240]; `mySounds[8].Play()` [IL L101244-101247];
   `cameraShaker.Stop()`, `Play("shake")` [IL L101250-101258];
   `myEffects[7].activate(self.position, null)` [IL L101262-101270].
2. wait **0.04 s** [IL L101272-101274].
3. **Hit 1** on all enemies in the box [IL L101279-101458]. wait **0.15 s** [IL L101461-101463].
4. Flip facing: `localScale.x = -localScale.x`, `updateHealthBar(1)` [IL L101470-101513];
   camera shake restart [IL L101516-101524]; **Hit 2** [IL L101527-101706]. wait **0.15 s**
   [IL L101709-101711].
5. `myAnimation.Stop("attack")`, `Play("attack")` [IL L101717-101724]; **Hit 3**
   [IL L101727-101906]. wait **0.15 s** [IL L101909-101911].
6. Flip facing again + `updateHealthBar(1)` [IL L101918-101961]; **Hit 4** [IL L101963-102119],
   and each enemy hit by hit 4 additionally gets:
   `if e.debuffs[3] <= 1.7: e.debuffs[3] = 1.7; e.debuffs[4] = 0.2` [IL L102122-102154].
   Then `commandPending = false` [IL L102181-102182]. wait **0.34 s** [IL L102184-102186].
7. `basicAction.speed = 1`, `noHitReact = false`, `returnToNormal()`, `disableSpecials = false`
   [IL L102192-102206].

Total 4 × 0.75 × power = 3.0 × power per enemy before crits (each hit rolls crit separately).
No passive is checked in this script.

### 6.4 Reckless Blow — `abilities == 4` [IL L102211-102228] + melee resolution

*json: "A massive attack that deals damage to the barbarian as well as his target." Cooldown 30.*

`performSpecial` part (complete):
```
buffs[1] = 500            # literal; "next melee attack is a Reckless Blow" flag   [IL L102220-102224]
returnToNormal()                                                                   [IL L102226-102227]
```
No animation, sound, wait or target check here.

Resolution inside `$meleeAttack$1838` (outside the assigned range; read for completeness):

1. At the start of the next melee attack, `buffs[1] > 0` sets `noHitReact = true`
   [IL L90214-90234]; because `buffs[1] > 0` and `characterClass == 7` the attack plays
   `myAnimation.Play("reckless")`, waits **0.366 s** and marks the attack as not basic
   (`isBasicAttack = false`) [IL L90263-90310].
2. If `myTarget` and `myTargetEnemyScript` exist, `AIState == 2`, `buffs[1] > 0`, not basic,
   `characterClass == 7`, `health > 0` [IL L91086-91127]:
   ```
   Time.timeScale = 0.1; motherBrain.dimBackground = true                          [IL L91129-91135]
   # self damage — same in all three variants:
   self.takeDamage( int(health * 0.25), tempVector * impactForce * -2, myTargetEnemyScript )
                                                         [IL L91145-91164, L91217-91236, L91269-91288]
   if passives[3] == 1:      # Blunt Trauma                                        [IL L91137-91142]
       target.takeDamage( int(4 * power * calculateCrit()), tempVector * impactForce * 3, self )   [IL L91166-91191]
       target.debuffs[3] = 3.5; target.debuffs[4] = 0.15                           [IL L91193-91205]
   elif passives[3] == -1:   # Dismemberment                                       [IL L91209-91214]
       target.takeDamage( int(5 * power * 1.2 * calculateCrit()), tempVector * impactForce * 3, self )   [IL L91238-91265]
   else:
       target.takeDamage( int(5 * power * calculateCrit()), tempVector * impactForce * 3, self )   [IL L91290-91315]
   mySounds[6].Play()                                                              [IL L91317-91321]
   myEffects[3].activate(self.position, null)                                      [IL L91323-91332]
   cameraShaker.Stop(); cameraShaker.Play("powerUpShake")                          [IL L91334-91343]
   buffs[1] = 0                                                                    [IL L91346-91351]
   wait 0.04 s scaled (0.4 s real at timeScale 0.1)                                [IL L91353-91355]
   motherBrain.dimBackground = false; Time.timeScale = 1; noHitReact = false       [IL L91360-91369]
   ```
   `tempVector` = normalize(target.position − self.position) [IL L90471-90489].

Self-damage is 25 % of **current** health and goes through the hero's normal `takeDamage` (so armor
and buffs there apply). With Blunt Trauma the multiplier is **4**, not 5 — the knock-down costs
damage. Since the flag is 500 s and is only cleared on a successful hit, the armed blow effectively
waits until the Barbarian next lands a melee attack (UNVERIFIED: whether `handleBuffs` counts
`buffs[1]` down).

### 6.5 Savage Pounce — `abilities == 5` [IL L102232-102314] + AI flight + landing

*json: "Pounce on your target, dealing massive damage in an area around them." Cooldown 30.*

Targeting: needs `myTarget`; damage is an area around the landing point.

`performSpecial` part:
```
if myTarget == null:                                                               [IL L102241-102243]
    specialAwaitingTarget = 2; returnToNormal(); end                               [IL L102309-102313]
motherBrain.disableSpecials = true; motherBrain.dimBackground = true               [IL L102247-102254]
noHitReact = true; specialAwaitingTarget = -1; AIState = 3                         [IL L102257-102266]
myAnimation.Play("leap")                                                           [IL L102269-102271]
pounceDestination = myTarget.position           # snapshot; does not track target  [IL L102274-102279]
pounceSpeed = Distance(self.position, pounceDestination) / 0.46666                 [IL L102281-102292]
pounceTimer = 0.5                                                                  [IL L102295-102296]
invincible = true; commandPending = true                                           [IL L102299-102304]
```
(no yield; the coroutine ends immediately.)

Flight, in `PartyMember.AI` every frame while `AIState == 3` [IL L81179-81231]:
```
moveVector = normalize(pounceDestination − position)                               [IL L81185-81195]
if pounceTimer > 0:                                                                [IL L81197-81200]
    position += moveVector * pounceSpeed * Time.deltaTime                          [IL L81203-81215]
    pounceTimer -= Time.deltaTime                                                  [IL L81218-81221]
    if pounceTimer <= 0: StartCoroutine(pounceAttack())                            [IL L81223-81231]
```
Flight lasts 0.5 s at a speed sized for 0.46666 s, so the Barbarian overshoots the snapshot point by
about 7 % of the distance.

Landing, `$pounceAttack$1845` [IL L92834-93216]:
```
invincible = false; commandPending = false                                         [IL L92834-92840]
myEffects[5].activate(self.position, null); myEffects[6].activate(self.position, null)   [IL L92842-92862]
mySounds[7].Play(); cameraShaker.Stop(); cameraShaker.Play("shake")                [IL L92864-92879]
for each enemy e (stop at first null):                                             [IL L92885-92897, L93145-93163]
    if |e.x − self.x| < 1.6 + e.aoeRadiusBonus and |e.z − self.z| < 1.2 + e.aoeRadiusBonus
       and e.health > 0 and e.myRenderer.enabled:                                  [IL L92900-92986]
        tempVector = normalize(e.position − self.position)                         [IL L92990-93006]
        force = tempVector * impactForce * 2
        if passives[3] == 1:       # Blunt Trauma                                  [IL L93008-93013]
            e.takeDamage( int(2.5 * power * calculateCrit()), force, self )        [IL L93016-93044]
            e.debuffs[3] = 3.5; e.debuffs[4] = 0.15                                [IL L93046-93066]
        elif passives[3] == -1:    # Dismemberment                                 [IL L93070-93075]
            e.takeDamage( int(2.5 * power * 1.2 * calculateCrit()), force, self )  [IL L93078-93108]
        else:
            e.takeDamage( int(2.5 * power * calculateCrit()), force, self )        [IL L93112-93140]
wait 0.14 s                                                                        [IL L93166-93168]
Time.timeScale = 0.1; wait 0.06 s scaled (0.6 s real)                              [IL L93172-93177]
Time.timeScale = 1; motherBrain.disableSpecials = false                            [IL L93181-93187]
wait 0.1 s                                                                         [IL L93189-93191]
motherBrain.dimBackground = false                                                  [IL L93196-93199]
wait 0.52 s                                                                        [IL L93201-93203]
noHitReact = false; returnToNormalFromPounce()                                     [IL L93208-93213]
```

---

## 7. Monk (characterClass 8) [class check IL L102318-102320]

Monk passives used for actives: `passives[3] == +1` = **Sweep the Leg** (json index 10);
`passives[3] == -1` = **Solar Strikes** (index 11). Both affect Wind Walk only.

### 7.1 Wind Walk — `abilities == 1` [IL L102324-103240]

*json: "With blinding speed, the Monk attacks everything on the battlefield at once." Cooldown 40.*

Targeting: every valid enemy on the field; no target needed. The Monk teleports next to each enemy
in array order, strikes, and returns to the start position. Runs in slow motion (timeScale 0.1).

"Valid enemy" test (used three times): `e != null`, `e.health > 0`, `e.position.x < 10`,
`e.myRenderer.enabled` [IL L102341-102386].

```
validTargets = any valid enemy exists (scan stops at first valid or first null)    [IL L102332-102423]
if !validTargets: returnToNormal(); end        # nothing else happens              [IL L102426-102427, L103238-103239]

invincible = true; motherBrain.dimBackground = true; motherBrain.disableSpecials = true   [IL L102431-102442]
basicAction.speed = 20                                                             [IL L102445-102448]
Time.timeScale = 0.1                                                               [IL L102449-102450]
numberOfStrikes = 0; initialPosition = self.position                               [IL L102452-102459]

do:
    for each enemy e (stop at first null):                                         [IL L102463-102475, L103026-103043]
        if e.health > 0 and e.myRenderer.enabled and e.position.x < 10:            [IL L102479-102514]
            # vanish puff — alternates between two effects
            if numberOfStrikes in (0, 2, 4): myEffects[1].activate(self.position, null)   [IL L102517-102540]
            else:                            myEffects[2].activate(self.position, null)   [IL L102545-102553]
            mySounds[5].Play()                                                     [IL L102556-102559]
            # teleport beside the enemy
            if (Random.Range(0,2) == 0 and e.x > -2) or e.x > 2:                   [IL L102560-102595]
                self.position = e.position + e.meleePositions[0]                   [IL L102599-102621]
            else:
                self.position = e.position + e.meleePositions[1]                   [IL L102626-102648]
            # face the enemy
            if e.x < self.x and localScale.x != -1: localScale.x = -1; updateHealthBar(1)   [IL L102651-102721]
            elif e.x >= self.x and localScale.x != 1: localScale.x = 1; updateHealthBar(1)  [IL L102726-102796]
            # fade in from transparent
            myRenderer.material.color = Color(1,1,1,0); colorSpeed = 4; activateColors(); alphaAnim = true   [IL L102799-102821]
            myAnimation.Stop("attack"); myAnimation.Play("attack"); myAnimation.Play("select")   [IL L102824-102837]
            wait 0.0115 s scaled (0.115 s real)                                    [IL L102840-102842]
            tempVector = normalize(e.position − self.position)
            if passives[3] == -1:   # Solar Strikes                                [IL L102848-102852]
                dmg = int(power * 1.5 * 1.5 * calculateCrit())                     [IL L102882-102892]
            else:
                dmg = int(power * 1.5 * calculateCrit())                           [IL L102932-102940]
            e.takeDamage(dmg, tempVector * impactForce, self)                      [IL L102894-102901, L102942-102949]
            if passives[3] == 1: e.debuffs[10] = 6          # Sweep the Leg        [IL L102952-102968]
            myEffects[3].activate(e.position + Vector3(0, 0, -0.05), null)         [IL L102971-102991]
            mySounds[6].Play()                                                     [IL L102994-102997]
            numberOfStrikes += 1                                                   [IL L103000-103003]
            wait 0.024 s scaled (0.24 s real)                                      [IL L103005-103007]
        if motherBrain.activeEnemies <= 0: numberOfStrikes = 3                     [IL L103013-103020]
    validTargets = any valid enemy exists (same scan)                              [IL L103046-103137]
while numberOfStrikes < 3 and validTargets                                         [IL L103140-103146]

myEffects[1].activate(self.position, null); mySounds[5].Play()                     [IL L103150-103164]
self.position = initialPosition; movementTarget = self.position                    [IL L103167-103177]
myRenderer.material.color = Color(1,1,1,0); colorSpeed = 4; activateColors(); alphaAnim = true   [IL L103180-103202]
myAnimation.Play("powerUp")                                                        [IL L103205-103207]
wait 0.03 s scaled (0.3 s real)                                                    [IL L103210-103212]
Time.timeScale = 1                                                                 [IL L103216-103217]
motherBrain.dimBackground = false; motherBrain.disableSpecials = false; invincible = false   [IL L103220-103231]
returnToNormal()                                                                   [IL L103233-103234]
```

Strike-count behaviour that follows from the loop: `numberOfStrikes` counts individual hits but is
only tested after a full pass over all enemies. So with ≥ 3 valid enemies every enemy is hit exactly
once; with 2 enemies each is hit twice (4 hits); with 1 enemy it is hit 3 times. The pass also ends
early when `activeEnemies` drops to 0.

Per-hit damage: 1.5 × power (2.25 × power with Solar Strikes), crit rolled per hit. Sweep the Leg
writes `debuffs[10] = 6` s. `basicAction.speed` is left at 20 by this script (not reset in this
branch); the next melee attack resets it to 1 [IL L90433-90443].

### 7.2 Evasion — `abilities == 2` [IL L103244-103365]

*json: "You become momentarily untouchable, evading all attacks for 8 sec." Cooldown 30.* Self buff.

```
motherBrain.disableSpecials = true; motherBrain.dimBackground = true; noHitReact = true   [IL L103253-103264]
mySounds[7].Play()                                                                 [IL L103267-103270]
myRenderer.material.color = Color(0,0,0)                                           [IL L103273-103282]
myEffects[4].activate(self.position, null)                                         [IL L103285-103293]
buffs[23] = motherBrain.buffDurations[23]                                          [IL L103296-103304]
Time.timeScale = 0.1                                                               [IL L103305-103306]
cameraShaker.Stop("powerUpShake"); cameraShaker.Play("powerUpShake")               [IL L103309-103318]
wait 0.07 s scaled (0.7 s real)                                                    [IL L103321-103323]
Time.timeScale = 1; activateColors()                                               [IL L103327-103331]
motherBrain.disableSpecials = false; motherBrain.dimBackground = false             [IL L103334-103341]
colorPulseTimer = 0; buffColor = Color(0.34, 0.34, 0.75); mostRecentBuff = 23      [IL L103344-103357]
noHitReact = false; returnToNormal()                                               [IL L103360-103364]
```
No body animation is played by this script. The evasion itself is applied where `buffs[23]` is read.

### 7.3 Ki Blast — `abilities == 3` [IL L103369-103762]

*json: "A shockwave of pure Ki erupts from the Monk, knocking foes to the ground." Cooldown 30.*

Targeting: area around the Monk; no target needed.

1. t=0: `noHitReact = true`, `disableSpecials = true`, `dimBackground = true`
   [IL L103378-103389]; `basicAction.speed = 1`; `myAnimation.Stop("attack")`, `Play("attack")`
   [IL L103392-103404]; `activateColors()`, renderer colour = (1,1,1), `colorSpeed = 2`
   [IL L103407-103424].
2. wait **0.2 s** [IL L103426-103428]; `mySounds[8].Play()` [IL L103434-103437].
3. wait **0.08 s** [IL L103439-103441]; `myEffects[5]`, `myEffects[6]`, `myEffects[7]` each
   `.activate(self.position, null)` [IL L103447-103477].
4. wait **0.12 s** [IL L103479-103481]; `colorSpeed = 2`; `cameraShaker.Stop()`, `Play("shake")`
   [IL L103487-103499].
5. For each enemy `e` (stop at first null) with
   `|e.x − self.x| < 2.0 + e.aoeRadiusBonus`, `|e.z − self.z| < 1.5 + e.aoeRadiusBonus`,
   `e.health > 0`, `e.myRenderer.enabled` [IL L103508-103603]:
   ```
   tempVector = normalize(e.position − self.position)                              [IL L103608-103623]
   e.takeDamage( int(power * 1.5 * calculateCrit()), tempVector * impactForce * 3, self )   [IL L103626-103653]
   if e.debuffs[3] <= 3: e.debuffs[3] = 3; e.debuffs[4] = 0.2                      [IL L103656-103688]
   ```
6. wait **0.05 s** [IL L103714-103716]; `Time.timeScale = 0.05` [IL L103720-103721]; wait
   **0.008 s scaled (0.16 s real)** [IL L103723-103725]; `Time.timeScale = 1` [IL L103729-103730].
7. wait **0.3 s** [IL L103732-103734]; `dimBackground = false` [IL L103740-103742].
8. wait **0.2 s** [IL L103744-103746]; `disableSpecials = false`, `noHitReact = false`,
   `returnToNormal()` [IL L103752-103761].

Damage 1.5 × power, triple knock-back, 3 s knock-down. Bosses are not excluded by this script.

### 7.4 1000 Palms — `abilities == 4` [IL L103766-103787] + melee resolution

*json: "Unleash a flurry of blows, dealing heavy damage to a single target." Cooldown 30.*

`performSpecial` part (complete):
```
buffs[1] = motherBrain.buffDurations[1]      # arms the next melee attack          [IL L103775-103783]
returnToNormal()                                                                   [IL L103785-103786]
```

Resolution inside `$meleeAttack$1838` (outside the assigned range; read for completeness):

1. Next melee attack: `buffs[1] > 0` → `noHitReact = true` [IL L90214-90234]; for
   `characterClass == 8`: `myAnimation.Play("attack")`, wait `meleeOffset` seconds (field default
   0.21 [IL L77100-77101]), `isBasicAttack = false`, `AIState = 3` [IL L90314-90340].
2. If `buffs[1] > 0`, not basic, `myTarget` and `myTargetEnemyScript` exist, `AIState == 3`,
   `characterClass == 8`, `health > 0` [IL L90491-90532]:
   ```
   buffs[1] = 0                                                                    [IL L90535-90540]
   Time.timeScale = 0.05                                                           [IL L90541-90542]
   mySounds[10].Play()                                                             [IL L90544-90548]
   basicAction.speed = 40; basicAction.wrapMode = 2 (Loop)                         [IL L90550-90559]
   motherBrain.dimBackground = true                                                [IL L90561-90564]
   myEffects[9].activate(myTarget.position + Vector3(0, 0.1, -0.2), null)          [IL L90566-90581]
   cameraShaker.Stop(); cameraShaker.Play("powerUpShake")                          [IL L90583-90592]
   for i in 0..6:                                   # 7 rapid hits                 [IL L90598-90600, L90697-90704]
       if myTargetEnemyScript != null:                                             [IL L90603-90606]
           bardCoefficient = 0.3                                                   [IL L90609-90611]
           target.takeDamage( int(power * 0.3 * calculateCrit()), tempVector * 0.1, self )   [IL L90613-90632]
           bardCoefficient = 1                                                     [IL L90634-90636]
           target.myAnimation["hitReact"].speed = 20                               [IL L90638-90645]
           mySounds[Random.Range(0,5)].Play()                                      [IL L90647-90653]
           if i in (2, 4, 6): cameraShaker.Stop(); cameraShaker.Play("powerUpShake")   [IL L90655-90679]
           basicAction.normalizedTime = 0.1                                        [IL L90682-90685]
           wait 0.008 s scaled (0.16 s real at timeScale 0.05)                     [IL L90687-90689]
   myAnimation.Stop("attack"); myAnimation.Play("attack")                          [IL L90707-90715]
   basicAction.speed = 7; basicAction.wrapMode = 8 (ClampForever)                  [IL L90718-90726]
   wait 0.03 s scaled (0.6 s real)                                                 [IL L90728-90730]
   if target: myEffects[10].activate(myTarget.position + Vector3(0, 0.1, -0.2), null)   [IL L90735-90756]
   cameraShaker.Stop(); cameraShaker.Play("shake")                                 [IL L90758-90767]
   basicAction.speed = 1                                                           [IL L90770-90773]
   if target: target.takeDamage( int(power * 1.4 * calculateCrit()),
                                 tempVector * impactForce * 3, self )   # finisher [IL L90775-90805]
   mySounds[6].Play(); Time.timeScale = 1                                          [IL L90807-90813]
   if target: target.myAnimation["hitReact"].speed = 1                             [IL L90815-90828]
   motherBrain.dimBackground = false                                               [IL L90830-90833]
   if target and target.debuffs[3] <= 1.7: target.debuffs[3] = 1.7; target.debuffs[4] = 0.2   [IL L90835-90862]
   AIState = 2                                                                     [IL L90864-90866]
   ```
   If the Monk is armed and in `AIState == 3` but the conditions above fail (e.g. target died),
   the fallback only sets `AIState = 2` [IL L90870-90905].

Total 7 × 0.3 + 1.4 = **3.5 × power** before crits (each of the 8 hits rolls crit separately);
the 7 flurry hits have almost no knock-back (force length 0.1), the finisher has triple knock-back
and a 1.7 s knock-down.

### 7.5 Spirit Trance — `abilities == 5` [IL L103791-103912]

*json: "Enter a trance state, granting you increased speed and health regen for 15 sec."
Cooldown 40.* Self buff. Same script as Evasion (7.2) with: `mySounds[9]` [IL L103814-103817];
renderer colour (0,0,0) [IL L103820-103829]; `myEffects[8]` at self position
[IL L103832-103840]; `buffs[24] = buffDurations[24]` [IL L103843-103851]; `Time.timeScale = 0.1`
[IL L103852-103853]; `powerUpShake` [IL L103856-103865]; wait 0.07 s scaled (0.7 s real)
[IL L103868-103870]; `Time.timeScale = 1`, `activateColors()` [IL L103874-103878]; unlock/undim
[IL L103881-103888]; `colorPulseTimer = 0`, `buffColor = Color(0.54, 0.54, 0.54)`,
`mostRecentBuff = 24` [IL L103891-103904]; `noHitReact = false`, `returnToNormal()`
[IL L103907-103911].

---

## 8. Ranger (characterClass 9) [class check IL L103916-103918]

The four single-target shots are the same script with a different projectile effect. All damage,
damage-over-time, slow, knock-down, ground fire, the *Critical Aim* and *Misdirection* passives and
the "more damage with distance" rule are implemented by the projectile (`EffectScript`) and are
**not** in `performSpecial`. No passive is read by any Ranger script here.

### 8.1 Shared single-target shot script

```
if myTarget == null:
    specialAwaitingTarget = <slot>; returnToNormalFromShot(); end
specialAwaitingTarget = -1
myAnimation.Play("specialShot")
mySounds[11].Play()
myEffects[<E>].activate( self.position + Vector3(localScale.x * 0.4, 0, -0.1), myTarget )
wait 0.4 s
returnToNormalFromShot()
```
The projectile spawns 0.4 units in front of the Ranger (`localScale.x` is ±1 = facing) and 0.1
toward the camera, and is given the target transform. Note `noHitReact` is not set by these shots.

| abilities value | Ability (json) | Cooldown | Effect index `<E>` | `<slot>` if no target | IL lines |
|---|---|---|---|---|---|
| 1 | Aimed Shot — "deals more damage the further away the target is" | 20 | `myEffects[5]` | 0 | 103931–103996 (target check L103931-103933; anim L103941-103943; sound L103947-103950; effect L103953-103977; wait L103979-103981; end L103986-103987; no-target L103992-103996) |
| 2 | Incendiary Arrow — "Ignites the ground, dealing continuous damage to enemies who remain in the blaze" | 30 | `myEffects[8]` | 1 | 104010–104075 (effect L104032-104056; wait L104058-104060; no-target L104071-104075) |
| 3 | Vile Bolt — "poisoned arrow which deals continuous damage and leaves the victim slowed" | 30 | `myEffects[3]` | 1 | 104089–104154 (effect L104111-104135; wait L104137-104139; no-target L104150-104154) |
| 5 | Apollo Strike — "throws its victim to the ground for 8 seconds" | 30 | `myEffects[7]` | 2 | 104539–104604 (effect L104561-104585; wait L104587-104589; no-target L104600-104604) |

### 8.2 Barrage — `abilities == 4` [IL L104159-104526]

*json: "Unleash a salvo of arrows that deals damage to all enemies." Cooldown 30.*

Targeting: every living, visible enemy; no target needed. Slow motion (timeScale 0.1).

```
invincible = true; motherBrain.dimBackground = true; motherBrain.disableSpecials = true   [IL L104168-104179]
specialAction.speed = 30                                                           [IL L104182-104185]
Time.timeScale = 0.1                                                               [IL L104186-104187]
tookAShot = false                                                                  [IL L104189-104190]
for each enemy e (stop at first null):                                             [IL L104192-104204, L104471-104488]
    if e.health > 0 and e.myRenderer.enabled:                                      [IL L104208-104237]
        tookAShot = true                                                           [IL L104240-104241]
        myAnimation.Stop("specialShot"); myAnimation.Play("specialShot")           [IL L104244-104251]
        mySounds[11].Play()                                                        [IL L104255-104258]
        if self.x < e.x and localScale.x != 1:  localScale.x = 1;  updateHealthBar(1)    [IL L104261-104331]
        elif self.x > e.x and localScale.x != -1: localScale.x = -1; updateHealthBar(1)  [IL L104336-104406]
        myEffects[whichVolley].activate(
            self.position + Vector3(localScale.x * 0.4, 0, -0.1), e.myTransform )  [IL L104409-104440]
        whichVolley += 1; if whichVolley == 21: whichVolley = 18                   [IL L104442-104458]
        wait 0.01 s scaled (0.1 s real)                                            [IL L104460-104462]
if tookAShot: wait 0.06 s scaled (0.6 s real)                                      [IL L104491-104497]
specialAction.speed = 1; Time.timeScale = 1                                        [IL L104503-104508]
invincible = false; motherBrain.dimBackground = false; motherBrain.disableSpecials = false   [IL L104511-104522]
returnToNormalFromShot()                                                           [IL L104524-104525]
```

One arrow per enemy, fired in array order, cycling through three pooled arrow effects
`myEffects[18]`, `[19]`, `[20]` (`whichVolley` starts at 18 [IL L77091-77092] and persists between
casts). There is no `position.x < 10` test here (unlike Wind Walk / Radiance). Arrow damage is in
the effect, outside this scope.

---

## 9. Paladin (characterClass 10) [class check IL L104609-104611]

Paladin passives used for actives: `passives[1] == -1` = **Power of the Word** (json index 8, ×1.2
healing); `passives[3] == +1` = **Word of Asylum** (index 10); `passives[3] == -1` = **Word of
Retribution** (index 11).

Heal amount used by Holy Word and Radiance:
`int(250 + power * 4)`, or `int((250 + power * 4) * 1.2)` with Power of the Word
[IL L104754-104803], [IL L105483-105532].

### 9.1 Holy Word — `abilities == 1` [IL L104615-104975]

*json: "A wave of soothing light seeks out and heals your most injured ally." Cooldown 30.*

Targeting: automatic — the living party member with the lowest `health / maxHealth` (can be the
Paladin). No target needed.

```
noHitReact = true; myAnimation.Play("specialCast")                                 [IL L104624-104630]
lowest = 0                                                                         [IL L104633-104634]
for i in 0..3:                              # hard-coded 4 party slots             [IL L104636-104638, L104743-104750]
    if playerScripts[lowest] == null or playerScripts[lowest].health <= 0:         [IL L104642-104661]
        lowest = i                                                                 [IL L104665-104666]
    elif playerScripts[i] != null and playerScripts[lowest] != null
         and playerScripts[i].health / playerScripts[i].maxHealth
             < playerScripts[lowest].health / playerScripts[lowest].maxHealth
         and playerScripts[i].health > 0:                                          [IL L104671-104735]
        lowest = i                                                                 [IL L104739-104740]
ally = playerScripts[lowest]
ally.heal( int((250 + power*4) * 1.2) if passives[1] == -1 else int(250 + power*4), self )   [IL L104754-104803]

if passives[3] == 1:           # Word of Asylum                                    [IL L104806-104810]
    ally.buffs[26] = motherBrain.buffDurations[26]                                 [IL L104814-104827]
    ally.colorPulseTimer = 0; ally.buffColor = Color(0.34, 0.34, 0.75); ally.mostRecentBuff = 26   [IL L104830-104858]
elif passives[3] == -1:        # Word of Retribution                               [IL L104863-104867]
    ally.buffs[27] = motherBrain.buffDurations[27]                                 [IL L104871-104884]
    ally.colorPulseTimer = 0; ally.buffColor = Color(0.75, 0.34, 0.34); ally.mostRecentBuff = 27   [IL L104887-104915]

mySounds[5].Play()                                                                 [IL L104918-104921]
myEffects[1].activate(ally.position, ally.myTransform)                             [IL L104924-104944]
colorSpeed = 1.1; activateColors(); myRenderer.material.color = (1,1,1)            [IL L104947-104960]
wait 0.6 s                                                                         [IL L104962-104964]
noHitReact = false; returnToNormal()                                               [IL L104970-104974]
```

Buff 26 = "lingering shield, nullifying damage for 5 sec." and buff 27 = "boosting their power by
50% for 10 seconds" per json; the durations come from `buffDurations[26]` / `[27]` and the effects
are applied where those buffs are read (outside this scope).

### 9.2 Wrath — `abilities == 2` [IL L104979-105056]

*json: "Imbues your sword with holy lightning for 10 sec., which chains to nearby foes."
Cooldown 30.* Self buff.

```
noHitReact = true; myAnimation.Play("specialCast")                                 [IL L104988-104994]
buffs[29] = motherBrain.buffDurations[29]                                          [IL L104998-105006]
colorPulseTimer = 0; buffColor = Color(0.5, 0.5, 0.25); mostRecentBuff = 29        [IL L105009-105022]
mySounds[10].Play()                                                                [IL L105025-105028]
myEffects[14].activate(self.position, self.myTransform)      # attached to self    [IL L105031-105041]
wait 0.6 s                                                                         [IL L105043-105045]
noHitReact = false; returnToNormal()                                               [IL L105051-105055]
```
UNVERIFIED: the chain lightning is presumably in the melee attack code's `characterClass == 10`
branch (a class-10 test exists at [IL L92488-92490]; its body is outside this scope and was not read).

### 9.3 Aura of Light — `abilities == 3` [IL L105060-105137]

*json: "Converts all damage taken into healing instead for 10 seconds." Cooldown 40.* Self buff.

```
noHitReact = true; myAnimation.Play("specialCast")                                 [IL L105069-105075]
buffs[28] = motherBrain.buffDurations[28]                                          [IL L105079-105087]
colorPulseTimer = 0; buffColor = Color(0.5, 0.5, 0.25); mostRecentBuff = 28        [IL L105090-105103]
myEffects[7].activate(self.position, self.myTransform)       # attached to self    [IL L105106-105116]
mySounds[7].Play()                                                                 [IL L105119-105122]
wait 0.6 s                                                                         [IL L105124-105126]
noHitReact = false; returnToNormal()                                               [IL L105132-105136]
```

### 9.4 Divine Intervention — `abilities == 4` [IL L105141-105364]

*json: "Redirects all damage from the group to the paladin for 10 seconds." Cooldown 30.*

Targeting: every other living party member.

```
noHitReact = true; myAnimation.Play("specialCast")                                 [IL L105150-105156]
for i, ally in playerScripts where ally != null and ally.health > 0 and ally != self:   [IL L105159-105195, L105315-105326]
    ally.myProtector = self                                                        [IL L105199-105206]
    ally.buffs[30] = motherBrain.buffDurations[30]                                 [IL L105209-105222]
    ally.colorPulseTimer = 0.5; ally.buffColor = Color(0.5, 0.5, 0.3)              [IL L105225-105243]
    ally.mostRecentBuff = 30                                                       [IL L105246-105252]
    ally.colorSpeed = 2; ally.myRenderer.material.color = (1,1,1); ally.activateColors()   [IL L105255-105286]
    myEffects[i + 8].activate(ally.position, ally.myTransform)                     [IL L105289-105312]
mySounds[8].Play()                                                                 [IL L105330-105333]
colorSpeed = 1.1; activateColors(); myRenderer.material.color = (1,1,1)            [IL L105336-105349]
wait 0.6 s                                                                         [IL L105351-105353]
noHitReact = false; returnToNormal()                                               [IL L105359-105363]
```

Effect indices 8–11 correspond to party slots 0–3. The Paladin gets no buff; the redirect is done
where an ally with `buffs[30] > 0` takes damage, using `myProtector` (outside this scope).

### 9.5 Radiance — `abilities == 5` [IL L105368-105797]

*json: "A blast of divine fury knocks all enemies to the ground while healing the party."
Cooldown 30.*

Targeting: all living allies (heal) and all valid enemies (knock-down). No target needed.

1. t=0: `cameraShaker.Stop()`, `Play("shake")` [IL L105377-105385]; `noHitReact = true`;
   `myAnimation.Play("specialCast")`; `disableSpecials = true`; `dimBackground = true`
   [IL L105389-105406].
2. wait **0.12 s** [IL L105408-105410].
3. `myEffects[2].activate(self.position, null)`; `mySounds[6].Play()`; `Time.timeScale = 0.1`
   [IL L105416-105432].
4. wait **0.01 s scaled (0.1 s real)** [IL L105434-105436]; `Time.timeScale = 1`
   [IL L105440-105441].
5. `motherBrain.fullScreenFlash.activate(Vector3(0, 4.2, -7), null)` [IL L105444-105453].
6. Heal: for `i, ally` in `playerScripts` where `ally != null` and `ally.health > 0` (includes the
   Paladin) [IL L105455-105479, L105561-105572]:
   `ally.heal( int((250 + power*4) * 1.2) if passives[1] == -1 else int(250 + power*4), self )`
   [IL L105483-105532]; `myEffects[i + 3].activate(ally.position, ally.myTransform)`
   [IL L105535-105558] (effect indices 3–6 for slots 0–3).
7. `cameraShaker.Stop()`, `Play("shake")` [IL L105576-105584].
8. Knock-down: for each enemy `e` (stop at first null) with `e.health > 0`,
   `e.myRenderer.enabled`, `e.position.x < 10` [IL L105587-105638, L105748-105765]:
   ```
   originalTauntability = e.tauntable                                              [IL L105643-105649]
   tempVector = normalize(e.position − self.position)                              [IL L105653-105668]
   e.tauntable = false                                                             [IL L105671-105677]
   e.takeDamage( 1, tempVector * impactForce * 3, self )        # 1 point of damage   [IL L105680-105697]
   if e.debuffs[3] <= 3.5: e.debuffs[3] = 3.5; e.debuffs[4] = 0.2                  [IL L105700-105732]
   e.tauntable = originalTauntability                                              [IL L105735-105742]
   ```
   (Temporarily clearing `tauntable` means this hit does not pull the enemy's aggro onto the
   Paladin — UNVERIFIED interpretation; the flag's reader is in `EnemyScript.takeDamage`.)
9. wait **0.3 s** [IL L105768-105770]; `disableSpecials = false`, `dimBackground = false`
   [IL L105776-105783].
10. wait **0.3 s** [IL L105785-105787]; `noHitReact = false`, `returnToNormal()`
    [IL L105793-105797].

Radiance is field-wide (no distance test), deals exactly 1 damage with triple knock-back and a 3.5 s
knock-down. Bosses are not excluded by this script.

### 9.6 End of coroutine

After any branch (or if no class/ability matched) control reaches the common exit:
`YieldDefault(1)` then `return false` [IL L105799-105803].

---

## 10. Quick reference — numbers per ability

| Ability | Target | Total script time (s, real) | Damage / heal | Status applied |
|---|---|---|---|---|
| Horror | all non-boss enemies | 0.97 | 25 % instant kill (10,000,000 dmg) in near box unless `immuneToDeath` | near (dx<1.4, dz<1.0): debuffs[1]=8; mid (dx<2.1, dz<1.6): debuffs[1]=6; else debuffs[5]=4 + flee |
| Hex | enemy | 0.8 | none | debuffs[13]=debuffDurations[13] (non-boss) |
| Song of Renewal | ally / party / self | 0.7 | heal 300 + 2·power (×1.25 Healing Chords, not on self-fallback) | — |
| Song of Vigor | party | 0.7 | HoT magnitude 0.8·power (×1.25 Healing Chords) | buffs[19] |
| Song of Sanctuary | party | 0.7 | — | buffs[20] (+5 s Enduring Hope) |
| Song of War | party | 0.7 | — | buffs[21] (+5 s Enduring Hope) |
| Song of Inspiration | other allies | 0.7 | — | remainingCooldowns[0..2]=0 |
| Enrage | self | 0.83 | — | buffs[15] |
| Frenzy | self | 0.83 | — | buffs[17] |
| Whirlwind | box 1.5×1.0 (+aoeRadiusBonus) | 0.83 | 4 hits × 0.75·power·crit | 4th hit: debuffs[3]=1.7, [4]=0.2 |
| Reckless Blow | melee target | arm instantly; 0.366 wind-up + 0.4 freeze | 5·power·crit (4· with Blunt Trauma, 6· with Dismemberment); self 25 % current HP | Blunt Trauma: debuffs[3]=3.5, [4]=0.15 |
| Savage Pounce | box 1.6×1.2 at landing | 0.5 flight + 1.36 | 2.5·power·crit (×1.2 Dismemberment) | Blunt Trauma: debuffs[3]=3.5, [4]=0.15 |
| Wind Walk | all enemies with x<10 | per hit 0.355; +0.3 | 1.5·power·crit per hit (×1.5 Solar Strikes) | Sweep the Leg: debuffs[10]=6 |
| Evasion | self | 0.7 | — | buffs[23] |
| Ki Blast | box 2.0×1.5 (+aoeRadiusBonus) | 1.11 | 1.5·power·crit, force ×3 | debuffs[3]=3, [4]=0.2 |
| 1000 Palms | melee target | arm instantly; 0.21 + 7×0.16 + 0.6 | 7 × 0.3·power·crit + 1.4·power·crit | debuffs[3]=1.7, [4]=0.2 |
| Spirit Trance | self | 0.7 | — | buffs[24] |
| Aimed Shot / Incendiary Arrow / Vile Bolt / Apollo Strike | enemy | 0.4 | in projectile effect 5 / 8 / 3 / 7 | in projectile |
| Barrage | all enemies | 0.1 per enemy + 0.6 | in projectile effects 18–20 | in projectile |
| Holy Word | lowest-HP% ally | 0.6 | heal 250 + 4·power (×1.2 Power of the Word) | Asylum: buffs[26]; Retribution: buffs[27] |
| Wrath | self | 0.6 | — | buffs[29] |
| Aura of Light | self | 0.6 | — | buffs[28] |
| Divine Intervention | other allies | 0.6 | — | buffs[30], myProtector=paladin |
| Radiance | party + all enemies with x<10 | 0.82 | heal 250 + 4·power (×1.2); 1 damage, force ×3 | debuffs[3]=3.5, [4]=0.2 |

("crit" = `calculateCrit()` = 1 or 2. Script times are sums of the waits cited in each section.)

---

## 11. Uncertain / not determined

* **Cooldown start.** No script in L99245–105808 writes the caster's `remainingCooldowns[]`; where
  the cooldown from `cooldowns[]` is started (and whether a cast that aborts for lack of a target,
  or Wind Walk with no valid enemy, still costs the cooldown) was not determined. Likely in
  `MotherBrain.$specialMove$1664` (L71940–72397), which calls `performSpecial` at [IL L72339].
  `handleCooldowns` (L81336–81480) only counts the three timers down (faster by
  `buffMagnitudes[18]` while `buffs[18] > 0` [IL L81359-81381]).
* **Buff/debuff durations and magnitudes.** `buffDurations[1,15,17,19,20,21,23,24,26,27,28,29,30]`,
  `debuffDurations[13]` and all `buffMagnitudes` are Inspector data, not in the IL. The json
  descriptions give player-facing numbers (e.g. Enrage 8 s, Frenzy 10 s, Evasion 8 s, Spirit Trance
  15 s, Sanctuary/War 15 s, Hex 6 s, Wrath/Aura/Divine Intervention 10 s) — UNVERIFIED against data.
* **What each buff/debuff index does** is implemented in `handleBuffs`, `takeDamage`,
  `meleeAttack`, `EnemyScript` — not in this range. Meanings in section 3.3 are inferences.
  In particular debuffs[1] vs debuffs[5] (paralyse vs fear) and debuffs[3]/[4] (knock-down + its
  0.2 / 0.15 companion value) are UNVERIFIED.
* **Effect and sound names.** Only indices are in the code; names come from the serialized
  `myEffectNames` / `mySounds` arrays on each hero prefab.
* **Ranger shot damage**, Aimed Shot distance scaling, Incendiary ground fire, Vile Bolt DoT/slow,
  Apollo Strike knock-down (8 s), Barrage damage, Critical Aim and Misdirection are in
  `EffectScript`, not here.
* **Song of Vigor + Enduring Hope.** The +5 s is added for buffs 20 and 21 but not for buff 19 in
  this script; whether Vigor is extended somewhere else was not determined.
* **Song of Renewal on a non-ally target.** `tempAllyScript` is dereferenced without a null check
  [IL L100157-100164]; whether an enemy can ever be `myTarget` for the Bard at that point was not
  determined.
* **Reckless Blow flag lifetime.** `buffs[1] = 500` — whether `handleBuffs` decrements index 1 was
  not checked.
* **`bardCoefficient`** (0.75 in Whirlwind, 0.3 in 1000 Palms): its reader is outside this scope
  (UNVERIFIED: a scaling factor for on-hit procs such as life drain inside enemy `takeDamage`).
* **ability value → json power index** (1,2,3,4,5 → 0,1,2,5,6) and **passive ±1 → json index**
  mappings are inferred from behaviour matching descriptions; the code that writes `abilities[]`
  and `passives[]` (talent menu) was not read.
* **WaitForSeconds under `Time.timeScale`**: real-time values assume Unity's scaled-time behaviour.

Contradictions with older notes: none found for this range. `work/battleheart-encounter-parity.md`
describes `passives[]` as "+1/−1/0 = variant", which agrees with the code read here.

---

## 12. Cross-references

| Symbol | Lines | Relation |
|---|---|---|
| `PartyMember.performSpecial(int)` | 86025–86036 | stub that creates this coroutine |
| `MotherBrain.$specialMove$1664` | 71940–72397 | caller (button press); call at L72339, after resetting `disableSpecials`, `timeScale`, `dimBackground`, leader `commandPending`/`invincible` [IL L72313-72331] |
| `PartyMember.AI` | 78102–81244 | deferred cast when `specialAwaitingTarget > -1` [IL L78297-78422]; Savage Pounce flight [IL L81179-81231] |
| `PartyMember.$meleeAttack$1838` | 90106–92750 | resolves Reckless Blow [IL L91086-91370] and 1000 Palms [IL L90491-90867]; Frenzy attack speed [IL L90362-90415] |
| `PartyMember.$pounceAttack$1845` | 92752–93224 | Savage Pounce landing |
| `PartyMember.returnToNormal` / `returnToNormalFromShot` / `returnToNormalFromPounce` | 86365–86531 | end-of-ability state reset |
| `PartyMember.calculateCrit` | 87112–87142 | crit multiplier |
| `PartyMember.heal` | 82423–82590 | all heals |
| `PartyMember.takeDamage` | 81497–82407 | Reckless Blow self-damage; reads buffs 20/23/26/28/30 (UNVERIFIED) |
| `PartyMember.handleBuffs` | 86039–86362 | buff timers / pulse colours |
| `PartyMember.handleCooldowns` | 81336–81480 | cooldown countdown |
| `PartyMember.activateColors`, `updateHealthBar` | 84223–84239, 82781–83186 | tint fade, health-bar refresh |
| `PartyMember.createMyEffects` | 86613–86752 | builds `myEffects[]` from `myEffectNames` |
| `EnemyScript.takeDamage`, `EnemyScript.debuffs`, `fearLocation`, `fearTimer`, `tauntable` | (EnemyScript class) | all enemy-side effects |
| `EffectScript.activate` | (EffectScript class) | visual effects and Ranger projectiles |
| Part 1 of this coroutine | 93226–99244 | Cleric, Knight, Rogue, Wizard, Witch abilities 1–3 |

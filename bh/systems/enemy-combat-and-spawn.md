# Enemy combat, attack slots and spawning (`EnemyScript`, non-coroutine methods after `AI`)

**Scope:** class `EnemyScript`, every non-coroutine method in IL lines **16685–22090** of
`Assembly-UnityScript.il`: `residualEffects`, `puddleDamage`, `acquireHealTarget`,
`summonSkeletonAdds`, `flash`, `shaderAnimation`, `activateColors`, `takeDamage`,
`hypotheticalDamage`, `updateHealthBar`, `healthAnimation`, `animateSliding`, `requestPosition`,
`purgePosition`, `spawn`. The coroutine *stubs* that sit in the same range are listed in §5 (their
bodies live in nested classes at 23399–32633 and are **not** documented here). Field declarations
and constructor defaults were read from 5304–5700.

All `[IL Lnnnn]` tags are line numbers in the `.il` file.

---

## 1. Summary

- An enemy is a pooled object. While "parked" it sits at world `x == 10` with `health <= 0`;
  `spawn()` un-parks it, puts it on the battlefield according to its `spawningStyle` (walk in from
  right/left edge, rise out of the ground inside the arena, boss-specific placements), refills
  health to `maxHealth` and returns `true`. `spawn()` does **no stat scaling** — it only copies
  `maxHealth` into `health`. Scaling is done elsewhere (`MotherBrain.levelUpEnemies`, ×1.1 to
  `maxHealth` and `power`, see §6.2).
- `takeDamage(damage, impactForce, whoHitMe)` is how a party member hurts an enemy. The enemy has
  **no defense stat, no dodge, no crit roll and applies no status effect here**: the number it
  receives is only *increased* by the attacker's active buffs and the enemy's own "vulnerable"
  debuffs, then subtracted from health. It also plays the hit flash, shows the health bar,
  applies knockback (`slideVector`), may switch target to a tank-type attacker ("taunt"), and
  starts the appropriate death coroutine at 0 health.
- `hypotheticalDamage` is a side-effect-light preview of the same bonus maths (returns the number).
- `animateSliding` moves the enemy by its knockback vector each frame with friction and arena-edge
  clamping; one debuff (index 4) makes non-boss enemies slide without friction.
- `requestPosition` / `purgePosition` are the **attack-slot system**: up to 6 slots around the
  enemy (0,2,3 on its left; 1,4,5 on its right) handed out to party members that melee it.
- `shaderAnimation` fades the tint colour of the sprite back to grey 0.25 after a flash.
- `updateHealthBar` / `healthAnimation` drive the two-part overhead health bar (green = current,
  red = delayed "damage trail").
- `residualEffects` / `puddleDamage` are ooze-boss-only per-frame logic (acid puddles, re-forming).
- `acquireHealTarget` (healer enemies) and `summonSkeletonAdds` (lich) are small helpers.

---

## 2. Fields

Declared at [IL L5307-5391]; defaults from `.ctor` [IL L5394-5472]. "inspector" = no default in
code, value comes from the Unity prefab (not in the IL).

| Field | Type | Default | Meaning (as used by the code in scope) |
|---|---|---|---|
| `specialMoves` | `SpecialMove[]` | inspector | Per-enemy special-move timers. `residualEffects` uses `[1]` and `[2]` (`.timer`, `.cooldownMax`) [IL L16829-16902] |
| `oozeBoss` | bool | inspector | If true, `remoteUpdate` calls `residualEffects()` every frame [IL L5694-5698] |
| `likeABoss` | bool | inspector | Boss flag; excludes the enemy from the frictionless-slide debuff [IL L20247-20248] |
| `immuneToDeath` | bool | inspector | Not read or written in scope |
| `debuffs` | `float32[]` | inspector length | Remaining time of each debuff by index; `> 0` means active. All zeroed in `spawn` [IL L21173-21195] |
| `myEffects` | `EffectScript[]` | built in `initialize` [IL L5614-5651] | Effect instances; indices 2,3,5 used in scope |
| `mySounds` | `AudioSource[]` | inspector | Sound slots; indices 2 and 5 used in scope |
| `motherBrain` | `MotherBrain` | found in `initialize` [IL L5482-5487] | Battle controller (`enemyScripts`, `playerScripts`, `activeEnemies`, `edge`, `floor`, `cieling`, `buffMagnitudes`, `debuffMagnitudes`) |
| `attackers` | int | 0 | Number of party members currently holding/claiming an attack slot on this enemy [IL L20365-20368, L20947-20950] |
| `meleeSlot` | int | 0 | The slot index this enemy holds **on its own target** (a `PartyMember`) [IL L19118-19133] |
| `colorSpeed` | float | 2.0 [IL L5406] | Speed of tint fade in `shaderAnimation` |
| `myRenderer` | Renderer | child `"geometry"` [IL L5499-5505] | Sprite renderer; `material.color` is the tint |
| `myTransform`, `myAnimation` | | set in `initialize` | Cached components |
| `power` | int | 30 [IL L5409-5410] | Attack power; used for ooze damage in scope |
| `impactForce` | float | 1.2 [IL L5412-5413] | Knockback this enemy deals (not used in scope; note `takeDamage` has a *parameter* of the same name) |
| `health` | float | 1000 [IL L5415-5416] | Current health |
| `maxHealth` | int | 1000 [IL L5418-5419] | Max health (prefab normally overrides) |
| `healthTimer` | float | 0 | Seconds the health bar stays visible; set to 2.6 on hit [IL L18791-18792] |
| `healthVisible` | bool | false | Health bar currently shown |
| `greenHealthA/B`, `redHealthA/B` | Transform (private) | children `life/bar_greenLeft`, `life/bar_redLeft`, `life/bar_greenRight`, `life/bar_redRight` [IL L5509-5529] | Health bar end-pieces |
| `slideVector` | Vector3 | 0 | Current knockback velocity |
| `frictionConstant` | float | 10 [IL L5421-5422] | Knockback decay rate |
| `myWeight` | float | 1 [IL L5424-5425] | Multiplier on knockback displacement (lower = moves less) |
| `conflagScaleFactor` | float | 1 | Not used in scope |
| `aoeRadiusBonus` | float | 0 | Not used in scope |
| `spawningStyle` | int | 1 [IL L5430-5431] | Selects the branch in `spawn` (§4.15) |
| `myTargetScript` / `myTarget` | `PartyMember` / Transform | null | Current attack target |
| `AIType` | int | 1 | Not used in scope |
| `isMelee` | bool | true [IL L5436-5437] | Melee enemy; only melee enemies can be pulled by the taunt rule in `takeDamage` |
| `chaotic` | bool | inspector | Not used in scope |
| `AIState` | int | 0 | AI state. Values seen in scope: `0` (set after (re)targeting), `-1` (set by "spawn animation" styles), `100` (ooze fragment state checked in `residualEffects`), `-100` (state in which the enemy refuses to retarget) |
| `actionTimer` | float | 0 | Set to 0, 100 or 3 by `spawn` depending on style |
| `moveSpeed` 1.1, `canBackpeddle` true, `runSpeedScale` 1.2, `primaryActionCooldown` 1.3, `standingAnimLength` 0.5 | | [IL L5439-5452] | Not used in scope |
| `tauntable` | bool | true [IL L5454-5455] | Enemy may switch target when hit (§4.8 step 12) |
| `invincible` | bool | false | `takeDamage` does nothing while true [IL L18415-18416] |
| `specialDeath` | int | 0 | Which death routine to run (§4.8 table) |
| `i` | int (private) | | Shared loop counter |
| `myHealTarget` | `EnemyScript` (private) | null | Set by `acquireHealTarget` |
| `redAnim`, `greenAnim`, `blueAnim` | bool | false | Per-channel "tint is animating" flags |
| `tempDamage` | int (private) | | Snapshot of the incoming damage before bonuses |
| `meleePositions` | Vector3[] | inspector | Slot offsets (values not in IL; read by `PartyMember` code outside scope, e.g. [IL L81259]) |
| `meleeOccupants` | `PartyMember[]` | inspector length (indices 0–5 are used) | Who holds each attack slot |
| `meleeOffset` | float | 0.21 [IL L5457-5458] | Not used in scope |
| `mana` | int | 50 [IL L5460-5461] | Set to 25 on spawn [IL L21170-21171] |
| `debuffColor` | Color | (0.25,0.25,0.25) [IL L5463-5467] | Reset to (0.25,0.25,0.25) on spawn [IL L21198-21202] |
| `mostRecentDebuff` | int | -1 | Not used in scope |
| `poisonMagnitude`, `meteorDotMagnitude`, `conflagDotMagnitude`, `baelDotMagnitude`, `plagueDotMagnitude`, `rangerDotMagnitude` | float | 0 | Not used in scope (DoT rates, used by `handleDebuffs` 22458–22834) |

Other objects' fields touched in scope: `PartyMember.buffs[]`, `.passives[]`, `.bardBuffPower`,
`.bardCoefficient`, `.lifeDraining`, `.characterClass`, `.browniePoints`, `.defense`, `.AIType`,
`.attackers`, `.meleeSlot`, `.health`, `.myTransform`; `MotherBrain.buffMagnitudes[]`,
`.debuffMagnitudes[]`, `.activeEnemies`, `.enemyScripts[]`, `.playerScripts[]`, `.edge`,
`.floor`, `.cieling` (sic); `SpecialMove.timer`, `.cooldownMax`; `EffectScript.myTransform`.

### Per-frame call order (context, `remoteUpdate` [IL L5659-5700])

If `myTransform.position.x == 10` (parked) nothing runs [IL L5667-5675]. Otherwise:
`shaderAnimation()`, `healthAnimation()`, `animateSliding()`; then if `health > 0`: `AI()`,
`handleDebuffs()`; then if `oozeBoss`: `residualEffects()` [IL L5677-5698].

---

## 3. Unity layers and sentinel values used

| Value | Where | Meaning from the code |
|---|---|---|
| position `x == 10` | [IL L5672-5675], [IL L21160-21167] | Enemy is parked/unspawned. `spawn()` only works on a parked enemy |
| GameObject layer `10` | set by every `spawn` style, e.g. [IL L21263-21265] | Live/targetable enemy. UNVERIFIED: the layer's name is not in the IL |
| GameObject layer `11` | [IL L17038-17041], checked [IL L18815-18819] | "Dead/hidden" layer: `takeDamage` will not start a death routine if the enemy is already on layer 11 |
| `AIState == -100` (`0xffffff9c`) | [IL L19111-19113], [IL L19159-19161] | Enemy will not switch target when hit |
| `AIState == 100` (`0x64`) | [IL L16916-16918] | Ooze fragment counted as "gone" by `residualEffects` |
| `AIState = -1` | [IL L21392-21393] etc. | Set by spawn styles that play the `"spawn"` animation |

---

## 4. Methods

### 4.1 `residualEffects()` [IL L16818-17138] — ooze boss only

Called every frame from `remoteUpdate` only when `oozeBoss` is true [IL L5694-5698].

Part A — acid puddle tick:
1. `specialMoves[1].timer -= Time.deltaTime` [IL L16829-16839].
2. If `specialMoves[1].timer <= 0` **and** `motherBrain.activeEnemies > 0`: call `puddleDamage()`
   and reset `specialMoves[1].timer = specialMoves[1].cooldownMax` [IL L16841-16866].
   (`cooldownMax` is an inspector value, not in the IL.)

Part B — re-forming after the split:
3. `specialMoves[2].timer -= Time.deltaTime` [IL L16868-16878].
4. Continue only if `specialMoves[2].timer <= 0` **and** `myRenderer.enabled == false` (boss is
   currently hidden) [IL L16880-16891]. Then `specialMoves[2].timer = specialMoves[2].cooldownMax`
   [IL L16894-16902].
5. `allGone = true`. For `i = 6 .. 11`: if `motherBrain.enemyScripts[i].AIState != 100` **and**
   `motherBrain.enemyScripts[i].health > 0` then `allGone = false` [IL L16903-16942].
6. If `allGone` and `motherBrain.activeEnemies > 0` [IL L16944-16951]:
   - `motherBrain.activeEnemies += 1` [IL L16954-16960]
   - `health = maxHealth` [IL L16963-16965]
   - `myTransform.position = (0, 0, 0.5)` [IL L16967-16974]
   - `myRenderer.enabled = true` [IL L16976-16978]; `gameObject.layer = 10` [IL L16980-16983]
   - `AIState = 0` [IL L16985-16986]; `acquireRandomTarget()` [IL L16988]
   - `myEffects[2].activate(myTransform.position, null)` [IL L16990-16997]; `mySounds[5].Play()` [IL L16999-17002]
   - For `i = 6 .. 11` (the fragments): `enemyScripts[i].clearAllAttackers()`,
     `enemyScripts[i].invincible = true`, `enemyScripts[i].myRenderer.enabled = false`,
     `enemyScripts[i].gameObject.layer = 11` [IL L17004-17051]
   - For each party slot `i = 0 .. 3` whose `playerScripts[i]` exists and has `health > 0`: if
     `Vector3.Distance(myPos, playerPos) <= 2.4`, call
     `playerScripts[i].takeDamage(power, normalize(playerPos - myPos) * 10, this)` (full `power`,
     knockback magnitude 10, directed away from the boss) [IL L17055-17132]
   - `this.invincible = false` [IL L17135-17136]

### 4.2 `puddleDamage()` [IL L17155-17373] — ooze acid puddles

For each party slot `i = 0 .. 3` [IL L17171-17173, L17362-17370], for each of the two puddle effects
`myEffects[3]` and `myEffects[5]` independently:

```
if playerScripts[i] exists and playerScripts[i].health > 0
   and abs(player.x - puddle.x) < 1.63
   and abs(player.z - (puddle.z - 0.82)) < 0.85:
       playerScripts[i].takeDamage( int(power * 0.3), Vector3(0,0,0), this )
```

- Puddle `myEffects[3]`: [IL L17176-17267]. Puddle `myEffects[5]`: [IL L17269-17360].
- Constants: half-width 1.63 [IL L17217, L17310]; z centre offset 0.82 [IL L17240, L17333];
  half-depth 0.85 [IL L17244, L17337]; damage factor 0.3 of `power`, truncated to int
  [IL L17254-17258, L17347-17351]; no knockback [IL L17259-17265].
- A player standing in both puddles is damaged twice per tick. Tick interval =
  `specialMoves[1].cooldownMax` (inspector).

### 4.3 `acquireHealTarget()` [IL L17389-17525] — healer enemies

Picks the living enemy with the lowest `health / maxHealth` and targets it.

```
best = -1
for i = 0 .. enemyScripts.length-1:
    if enemyScripts[i] is null:  i = enemyScripts.length (stop loop)      [L17404-17411, L17485-17490]
    elif enemyScripts[i].health > 0 and best == -1:  best = i             [L17414-17431]
    elif best != -1 and enemyScripts[i].health > 0
         and enemyScripts[i].health/maxHealth < enemyScripts[best].health/maxHealth:
             best = i                                                     [L17433-17482]
if best != -1:
    myHealTarget = enemyScripts[best]                                     [L17509-17515]
    myTarget     = myHealTarget.myTransform                               [L17518-17520]
    AIState      = 0                                                      [L17522-17523]
```

Notes read from the code: the scan stops at the first null entry of the array; the caster itself is
not excluded; strict `<` means ties keep the lower index.

### 4.4 `summonSkeletonAdds()` [IL L17541-17628]

Calls `spawn()` on `motherBrain.enemyScripts[6]`, `[7]`, `[12]`, `[13]` in that order. For each call
that returns `true`, `motherBrain.activeEnemies += 1` [IL L17552-17569 (6), L17571-17588 (7),
L17590-17607 (12), L17609-17626 (13)]. An add that is still alive / not parked is skipped
(`spawn` returns false, §4.15).

### 4.5 `flash()` [IL L17683-17703]

`colorSpeed = 1.1`; `activateColors()`; `myRenderer.material.color = (0.55, 0.55, 0.55)`
[IL L17690-17701]. A white-ish flash that `shaderAnimation` then fades back to 0.25. Used by the
death/boss coroutines (callers in §6).

### 4.6 `shaderAnimation()` [IL L17706-18371] — tint fade

Runs every frame. Handles the three colour channels identically and independently, each guarded by
its flag (`redAnim` [IL L17780-17975], `greenAnim` [IL L17977-18172], `blueAnim` [IL L18174-18369]).
For channel `c` of `myRenderer.material.color`:

```
step = Time.deltaTime * colorSpeed * (1 / Time.timeScale)      [L17800-17808]
if c > 0.25:
    c -= step                                                   [L17799-17833]
    if c < 0.25: c = 0.25; flag = false                         [L17842-17875]
elif c < 0.25:
    c += step                                                   [L17894-17928]
    if c > 0.25: c = 0.25; flag = false                         [L17937-17970]
else:                       # exactly 0.25
    flag = false                                                [L17974-17975]
```

- The rest value is the literal **0.25** for every channel (the method does not read `debuffColor`).
- Dividing by `Time.timeScale` makes the fade run in real time even when the game is slowed.
- `colorSpeed` values set in scope: 2.0 on hit [IL L18428-18429], 1.1 in `flash` [IL L17690-17691],
  1.5 for fade-in spawns [IL L21415-21416, L21674-21675, L21807-21808]; `.ctor` default 2.0.

### 4.7 `activateColors()` [IL L18374-18390]

Sets `redAnim = blueAnim = greenAnim = true` [IL L18381-18388]. Must be called after changing the
material colour so `shaderAnimation` fades it back.

### 4.8 `takeDamage(int damageAmount, Vector3 impactForce, PartyMember whoHitMe)` [IL L18393-19181]

`whoHitMe` is dereferenced unconditionally (must not be null). Entire method is skipped when
`invincible` is true [IL L18415-18416].

**Step 1 — hit feedback** [IL L18419-18456]
- `myAnimation.Stop("hitReact")` then `myAnimation.Play("hitReact")` [IL L18419-18425].
- `colorSpeed = 2.0`; `activateColors()` [IL L18428-18431].
- Set only the **red** channel of `material.color` to `0.6` [IL L18432-18456] (red hit flash that
  fades back to 0.25).

**Step 2 — damage bonuses** [IL L18460-18738]

`tempDamage = damageAmount` (the base, before bonuses) [IL L18460-18461]. Then, in this exact
order, each bonus is added and the running total is truncated to int after every step
(`conv.i4`). `B[n]` = `motherBrain.buffMagnitudes[n]`, `D[n]` = `motherBrain.debuffMagnitudes[n]`.

| # | Condition | Effect on `damageAmount` | IL |
|---|---|---|---|
| a | `whoHitMe.buffs[14] > 0` | `+= whoHitMe.bardBuffPower * whoHitMe.bardCoefficient` (flat bonus) | [IL L18462-18480] |
| b | `whoHitMe.buffs[15] > 0` and `whoHitMe.passives[0] == 1` | `+= tempDamage * (B[15] + 0.15)` | [IL L18484-18514] |
| b | `whoHitMe.buffs[15] > 0` and `whoHitMe.passives[0] == -1` | `+= tempDamage * (B[15] - 0.20)` | [IL L18520-18542] |
| b | `whoHitMe.buffs[15] > 0`, other `passives[0]` | `+= tempDamage * B[15]` | [IL L18548-18561] |
| c | `whoHitMe.buffs[4] > 0` | `+= tempDamage * B[4]` | [IL L18565-18586] |
| d | `whoHitMe.buffs[21] > 0` | `+= tempDamage * B[21]` | [IL L18590-18611] |
| e | `whoHitMe.buffs[27] > 0` | `+= tempDamage * B[27]` | [IL L18615-18636] |
| f | `this.debuffs[13] > 0` | `+= tempDamage * D[13]` | [IL L18641-18661] |
| g | `this.debuffs[2] > 0` | `+= tempDamage * D[2]` | [IL L18666-18686] |
| h | `this.debuffs[6] > 0` | `+= tempDamage * D[6]` | [IL L18691-18711] |
| i | `whoHitMe.buffs[13] > 0` | `+= tempDamage * B[13]` | [IL L18715-18736] |

All percentage bonuses are computed from the *base* `tempDamage`, so they stack additively, not
multiplicatively. There is no subtraction anywhere: **enemies have no armour/defense, no minimum
or maximum damage clamp, and no crit or miss roll in this method** (any crit is decided by the
attacker before calling).

**Step 3 — lifesteal and reporting** [IL L18740-18782]
- If `whoHitMe.lifeDraining != 0`: `whoHitMe.drainLife(damageAmount * whoHitMe.lifeDraining)`
  [IL L18740-18752].
- If `whoHitMe.characterClass == 7` and `whoHitMe.passives[1] == -1` and `whoHitMe.buffs[15] > 0`:
  `whoHitMe.drainLife(damageAmount * 0.75)` [IL L18753-18778]. (`bh/data/classes.json` id 7 =
  "Monk". UNVERIFIED: that `characterClass` uses the same numbering as that file's `id`.)
- `whoHitMe.returnDamageValue(damageAmount)` — always [IL L18779-18782].

**Step 4 — apply** [IL L18785-18807]
- `health -= damageAmount` [IL L18785-18789].
- `healthTimer = 2.6` [IL L18791-18792].
- If `!healthVisible`: `healthVisible = true`, `myAnimation.Play("showHealth")` [IL L18794-18803].
- `updateHealthBar(0)` [IL L18806-18807].

**Step 5 — death branch**: taken when `health <= 0` **and** `gameObject.layer != 11`
[IL L18809-18819]. (If health ≤ 0 but layer is 11, falls to Step 6.)

5a. Only when `specialDeath == 0` [IL L18822-18823]:
   - Face away from the blow: if `impactForce.x <= 0` and `localScale.x != -1` → `localScale.x = -1`,
     `updateHealthBar(1)` [IL L18825-18872]; else if `impactForce.x > 0` and `localScale.x != 1` →
     `localScale.x = 1`, `updateHealthBar(1)` [IL L18875-18922].
   - **Death knockback:** `slideVector = impactForce * 3` [IL L18924-18928].

5b. If `whoHitMe.characterClass == 7` and `whoHitMe.passives[2] != 0`: `whoHitMe.adrenalineRush()`
   [IL L18929-18941].

5c. `whoHitMe.browniePoints += 20` (kill credit) [IL L18942-18947].

5d. Start a death coroutine chosen by `specialDeath`:

| `specialDeath` | Action | IL |
|---|---|---|
| 0 (and any value not listed) | `StartCoroutine(die())` | [IL L19039-19040] |
| 1 | `StartCoroutine(goblinBossDeath())` | [IL L18949-18956] |
| 2 | `StartCoroutine(spiderBossDeath())` | [IL L18961-18968] |
| 3 | `StartCoroutine(oozeBossSplit())` | [IL L18973-18980] |
| 4 | `StartCoroutine(lichBossDeath())` | [IL L18985-18992] |
| 5 | `motherBrain.enemyScripts[0].maxHealth -= 1500`; `motherBrain.enemyScripts[1].health -= 1500`; then `StartCoroutine(die())` | [IL L18997-19033] |

   Note for case 5: the code really does subtract from index **0**'s `maxHealth` and index **1**'s
   `health` (different indices) [IL L19002-19029]. UNVERIFIED: which enemy uses `specialDeath == 5`
   (prefab value).

   After the death branch the method returns [IL L19042]; none of Step 6 runs.

**Step 6 — survived the hit** [IL L19044-19179]

6a. Threat/score: `whoHitMe.browniePoints += 2` if `whoHitMe.characterClass == 7`, else `+= 4`
   [IL L19044-19062].

6b. **Knockback:** if `debuffs[3] <= 0` then `slideVector = impactForce` (replaces, does not add)
   [IL L19064-19073]. While `debuffs[3] > 0` the enemy cannot be knocked back by hits.

6c. **Retarget ("taunt by tank")** — two cases:

   Case A, enemy already has a target (`myTargetScript != null`) and `isMelee` [IL L19075-19081].
   Switch to the attacker only if **all** hold [IL L19084-19113]:
   - `tauntable`
   - `myTargetScript.defense < whoHitMe.defense` (attacker is tougher than the current target)
   - `whoHitMe.AIType == 3`
   - `myTargetScript != whoHitMe`
   - `whoHitMe.attackers < 4`
   - `AIState != -100`

   Then [IL L19116-19136]:
   ```
   myTargetScript.purgePosition(meleeSlot)         # release my slot on the old target (PartyMember method)
   myTargetScript = whoHitMe
   myTarget       = whoHitMe.myTransform
   meleeSlot      = myTargetScript.requestPosition(0, this)   # PartyMember.requestPosition
   AIState        = 0
   ```

   Case B, enemy has **no** target (`myTargetScript == null`), `isMelee`, `tauntable`,
   `whoHitMe.attackers < 4`, `AIState != -100` [IL L19140-19161]: same assignment without the
   purge — target the attacker, `meleeSlot = requestPosition(0, this)`, `AIState = 0`
   [IL L19164-19179]. No defense/`AIType` test in this case.

   Ranged enemies (`isMelee == false`) never retarget here [IL L19080-19081, L19146-19147].

### 4.9 `hypotheticalDamage(int damageAmount, PartyMember whoHitMe) : int` [IL L19184-19462]

Returns what `takeDamage` *would* add up to, without touching health. It writes `tempDamage`
[IL L19191-19192] but nothing else. It is **not identical** to `takeDamage` Step 2:

| # | Condition | Effect | IL |
|---|---|---|---|
| a | `whoHitMe.buffs[14] > 0` and `characterClass == 7` | `+= bardBuffPower * 0.5` (truncated) | [IL L19193-19215] |
| a | `whoHitMe.buffs[14] > 0`, other classes | `+= bardBuffPower` | [IL L19221-19225] |
| b | `buffs[15] > 0`, `passives[0] == 1 / -1 / other` | `+= tempDamage * (B[15]+0.15)` / `(B[15]-0.20)` / `B[15]` | [IL L19229-19306] |
| c | `buffs[4] > 0` | `+= tempDamage * B[4]` | [IL L19310-19331] |
| d | `buffs[21] > 0` | `+= tempDamage * B[21]` | [IL L19335-19356] |
| f | `debuffs[13] > 0` | `+= tempDamage * D[13]` | [IL L19361-19381] |
| g | `debuffs[2] > 0` | `+= tempDamage * D[2]` | [IL L19386-19406] |
| h | `debuffs[6] > 0` | `+= tempDamage * D[6]` | [IL L19411-19431] |
| i | `buffs[13] > 0` | `+= tempDamage * B[13]` | [IL L19435-19456] |

Differences from `takeDamage`: (1) row a uses a hard-coded 0.5 (class 7) or 1.0 instead of
`bardCoefficient`; (2) there is **no** `buffs[27]` term; (3) no lifesteal, no `invincible` check.
Returns `damageAmount` [IL L19460-19461].

### 4.10 `updateHealthBar(int flip)` [IL L19530-19937]

The bar is 0.72 units wide, centred on the enemy (ends at ±0.36). `frac = health / maxHealth`
(float division) [IL L19690-19694, L19860-19864]. Which pair of end-pieces is "anchored" depends on
facing (`myTransform.localScale.x`), because the whole object is mirrored when facing left.

Facing right (`localScale.x > 0`) [IL L19589-19766]:
1. `greenHealthA.localPosition.x = 0.36` [IL L19598-19620]
2. if `flip == 1`: `redHealthB.localPosition.x = -redHealthA.localPosition.x` (carry the red trail
   across the mirror) [IL L19623-19655]
3. `redHealthA.localPosition.x = 0.36` [IL L19658-19680]
4. `greenHealthB.localPosition.x = greenHealthA.localPosition.x - frac * 0.72` [IL L19684-19719]
5. if `redHealthB.x > greenHealthB.x`: `redHealthB.x = greenHealthB.x` [IL L19723-19763]

Facing left (`localScale.x <= 0`) [IL L19768-19936] — mirror image:
1. `greenHealthB.localPosition.x = -0.36` [IL L19768-19790]
2. if `flip == 1`: `redHealthA.localPosition.x = -redHealthB.localPosition.x` [IL L19793-19825]
3. `redHealthB.localPosition.x = -0.36` [IL L19828-19850]
4. `greenHealthA.localPosition.x = greenHealthB.localPosition.x + frac * 0.72` [IL L19854-19889]
5. if `redHealthA.x < greenHealthA.x`: `redHealthA.x = greenHealthA.x` [IL L19893-19933]

`flip` is `1` when the caller has just changed `localScale.x` (facing), otherwise `0`. There is no
clamp on `frac` (health below 0 or above max moves the piece past the end).

### 4.11 `healthAnimation()` [IL L19940-20121]

Per frame:
1. If `healthTimer > 0`: `healthTimer -= Time.deltaTime` [IL L19964-19974]. Else if
   `healthVisible`: `healthVisible = false`, `myAnimation.Play("hideHealth")` [IL L19978-19993].
2. Red "damage trail" catch-up, only while `0 < healthTimer < 2.2` [IL L19996-20004] (so it starts
   0.4 s after a hit, since hits set the timer to 2.6):
   - facing right (`localScale.x > 0`) and `redHealthB.x < greenHealthB.x`:
     `redHealthB.localPosition.x += Time.deltaTime` [IL L20007-20059]
   - facing left (`localScale.x < 0`) and `redHealthA.x > greenHealthA.x`:
     `redHealthA.localPosition.x -= Time.deltaTime` [IL L20065-20117]

   i.e. the trail closes at 1 local unit per second (full bar = 0.72 units).

Net effect: bar is visible for 2.6 s after each direct hit.

### 4.12 `animateSliding()` [IL L20124-20336] — knockback motion

Per frame, in this order:

1. **Side walls.** If `pos.x >= motherBrain.edge - 1.2` and `slideVector.x > 0` → `slideVector.x = 0`
   [IL L20136-20159]; else if `pos.x <= -(motherBrain.edge - 1.2)` and `slideVector.x < 0` →
   `slideVector.x = 0` [IL L20163-20187].
2. **Top/bottom.** If `pos.z >= motherBrain.cieling` and `slideVector.z > 0` → `slideVector.z = 0`
   [IL L20189-20210]; else if `pos.z <= motherBrain.floor + 0.5` and `slideVector.z < 0` →
   `slideVector.z = 0` [IL L20214-20237].
3. **Move.**
   - If `debuffs[4] > 0` and `!likeABoss`:
     `position += slideVector * Time.deltaTime * 1.0` — no weight, **no friction** (the vector is
     not decayed while this debuff lasts) [IL L20239-20262].
   - Else if `abs(slideVector.x) > 0` or `abs(slideVector.z) > 0`:
     `position += slideVector * Time.deltaTime * myWeight`, then
     `slideVector = Vector3.Lerp(slideVector, (0,0,0), Time.deltaTime * frictionConstant)`
     [IL L20266-20310].
4. **Snap to rest.** If `abs(slideVector.x) <= 0.005` → `slideVector.x = 0`; same for `z`
   [IL L20312-20334].

Constants: wall margin 1.2 [IL L20144, L20171]; floor margin 0.5 [IL L20222]; rest threshold 0.005
[IL L20315, L20327]; defaults `frictionConstant = 10`, `myWeight = 1` (§2). `slideVector` is in
world units per second; it is set by `takeDamage` (§4.8 steps 5a and 6b).

### 4.13 `requestPosition(int preferBack, PartyMember whosAsking) : int` [IL L20339-20936] — attack slots

A party member calls this on the enemy it wants to melee; the return value is the slot index it
must stand in (index into `meleePositions`). `meleeOccupants[s]` records the holder.

Slot layout as implied by the code (left = attacker's `x` < enemy's `x`):

| Slot | Side | Role |
|---|---|---|
| 0 | left | primary left slot |
| 1 | right | primary right slot |
| 2, 3 | left | used when two attackers share the left side (previous holder of 0 moves to 2, newcomer takes 3) |
| 4, 5 | right | used when two attackers share the right side (previous holder of 1 moves to 4, newcomer takes 5) |

The world offsets of the slots (`meleePositions[]`) are prefab data and not in the IL.

Helper notation: `LEFT = whosAsking.x < this.x` (strict; equal counts as right).
`BUMP_LEFT`: `occ[2] = occ[0]; occ[0] = null; occ[2].meleeSlot = 2; occ[3] = asker; return 3`.
`BUMP_RIGHT`: `occ[4] = occ[1]; occ[1] = null; occ[4].meleeSlot = 4; occ[5] = asker; return 5`.

```
attackers += 1                                                        [L20365-20368]

if attackers == 1:                                                    [L20370-20372]
    if myTargetScript == whosAsking or preferBack == 0:               [L20375-20381]
        if LEFT: occ[0] = asker; return 0                             [L20383-20403]
        else:    occ[1] = asker; return 1                             [L20406-20411]
    elif preferBack == 1:                                             [L20415-20417]
        # go behind the enemy: side chosen by enemy facing, not by position
        if localScale.x == 1: occ[1] = asker; return 1                [L20420-20435]
        else:                 occ[0] = asker; return 0                [L20438-20443]
    # (preferBack other than 0/1: falls to "return 0" with no reservation)

elif attackers == 2:                                                  [L20448-20450]
    if preferBack == 1 and occ[0] != null: occ[1] = asker; return 1   [L20452-20469]
    if preferBack == 1 and occ[1] != null: occ[0] = asker; return 0   [L20471-20488]
    if LEFT     and occ[0] == null: occ[0] = asker; return 0          [L20490-20517]
    if not LEFT and occ[1] == null: occ[1] = asker; return 1          [L20519-20546]
    if LEFT     and occ[0] != null: BUMP_LEFT                         [L20548-20594]
    if not LEFT and occ[1] != null: BUMP_RIGHT                        [L20596-20642]

elif attackers == 3:                                                  [L20647-20649]
    if occ[2] != null and occ[3] != null: occ[1] = asker; return 1    [L20652-20671]
    if occ[4] != null and occ[5] != null: occ[0] = asker; return 0    [L20674-20693]
    if localScale.x > 0 and preferBack == 1: BUMP_RIGHT               [L20696-20734]
    if localScale.x < 0 and preferBack == 1: BUMP_LEFT                [L20737-20775]
    if LEFT:     BUMP_LEFT                                            [L20777-20816]
    if not LEFT: BUMP_RIGHT                                           [L20818-20857]

elif attackers == 4:                                                  [L20862-20864]
    if occ[0] != null:   BUMP_LEFT                                    [L20867-20898]
    elif occ[1] != null: BUMP_RIGHT                                   [L20901-20932]

return 0        # attackers >= 5, or no branch matched: nothing reserved [L20934-20935]
```

Behaviour notes taken directly from the code:
- The method dispatches on the **count** after incrementing, not on which slots are free; it
  trusts the count to describe the occupancy pattern.
- `preferBack == 1` means "stand behind the enemy" (side picked from `localScale.x`), except when
  the asker is the enemy's own current target (`myTargetScript == whosAsking`), which is always
  placed by position [IL L20375-20378].
- When an occupant is bumped, its `PartyMember.meleeSlot` field is rewritten directly
  [IL L20583-20587, L20631-20635] — the bumped character is not otherwise notified.
- In the `attackers == 3` fall-through branches the code does not check that `occ[0]`/`occ[1]` is
  non-null before writing `occ[2].meleeSlot` / `occ[4].meleeSlot` [IL L20792-20809, L20833-20850].
- The 5th and later simultaneous askers get slot `0` returned with no reservation, but `attackers`
  is still incremented [IL L20365-20368, L20934-20935]. Callers gate on `attackers < 4` elsewhere
  (e.g. §4.8 step 6c uses the same test on the `PartyMember` side).

### 4.14 `purgePosition(int whichSlot)` [IL L20939-21093]

Called when an attacker leaves (callers §6).

```
attackers -= 1                                                        [L20947-20950]
meleeOccupants[whichSlot] = null                                      [L20952-20955]

# collapse the left pair back to the primary slot
if occ[2] != null and occ[3] == null:                                 [L20957-20968]
    occ[0] = occ[2]; occ[0].meleeSlot = 0; occ[2] = null              [L20971-20988]
elif occ[3] != null and occ[2] == null:                               [L20992-21003]
    occ[0] = occ[3]; occ[0].meleeSlot = 0; occ[3] = null              [L21006-21023]

# collapse the right pair
if occ[4] != null and occ[5] == null:                                 [L21025-21036]
    occ[1] = occ[4]; occ[1].meleeSlot = 1; occ[4] = null              [L21039-21056]
elif occ[5] != null and occ[4] == null:                               [L21060-21071]
    occ[1] = occ[5]; occ[1].meleeSlot = 1; occ[5] = null              [L21074-21091]
```

No lower bound on `attackers` and no check that `occ[0]`/`occ[1]` is empty before the collapse
overwrites it.

### 4.15 `spawn() : bool` [IL L21096-22090]

**Precondition:** `health <= 0` **and** `myTransform.position.x == 10` (parked). Otherwise returns
`false` and does nothing [IL L21154-21167, L22086-22087].

**Common setup (all styles)** [IL L21170-21212]:
- `mana = 25` [IL L21170-21171]
- every element of `debuffs[]` set to 0 — all status effects cleared [IL L21173-21195]
- `debuffColor = (0.25, 0.25, 0.25)` [IL L21198-21202]
- `activateColors()`; `material.color = (0.25, 0.25, 0.25)` [IL L21204-21212]

**Style-specific part** — switch on `spawningStyle`. `E = motherBrain.edge`, `F = motherBrain.floor`,
`C = motherBrain.cieling`. Position is `(x, 0, z)`. "face by side" = `localScale.x = 1` if the
chosen `x > 0`, else `-1`.

| Style | Position | Facing (`localScale.x`) | Visual | `actionTimer` | `AIState` | Target | Other | IL |
|---|---|---|---|---|---|---|---|---|
| 1 (default) | `x = E + 1`, `z = Random.Range(F, C)` — just off the **right** edge | `1` | none | `0` | unchanged | `acquireRandomTarget()` | — | [IL L21214-21277] |
| 2 | `x = Random.Range(-E + 0.7, E - 0.7)`, `z = Random.Range(F, C)` — inside the arena | by side | `Play("spawn")` | `0` | `-1` | none | — | [IL L21280-21394] |
| 3 | `x = Random.Range(-E + 0.7, E - 0.7)`, `z = Random.Range(F + 0.9, C - 0.8)` | by side | `activateColors()`, `material.color = (0,0,0)`, `colorSpeed = 1.5` (fades in from black), `Play("spawn")` | `100` | `-1` | none | — | [IL L21397-21530] |
| 4 | `x = -E - 1`, `z = Random.Range(F, C)` — just off the **left** edge | `1` | none | `0` | unchanged | `acquireRandomTarget()` | — | [IL L21533-21597] |
| 5 | `r = Random.Range(0, 2)` (int → 0 or 1). `r == 0`: as style 1 position (`E + 1`). `r == 1`: as style 4 position (`-E - 1`). | **not set** | none | `0` | unchanged | `acquireRandomTarget()` | A third branch (in-arena, black fade-in, `Play("spawn")`, face by side, `AIState = -1`) exists in the code [IL L21661-21772] but is unreachable because `Random.Range(0,2)` never yields 2 | [IL L21600-21786] |
| 6 | same as style 3 | by side | same as style 3 | `100` | `-1` | none | additionally `myEffects[3].activate(position, null)` and `mySounds[2].Play()` | [IL L21789-21936] |
| 7 | `x = E + 1.5`, `z = 0` | `1` | none | `0` | unchanged | `acquireRandomTarget()` | — | [IL L21939-21997] |
| 8 | `(12, 0, 0)` | unchanged | none | unchanged | `-1` | none | `invincible = true` | [IL L22000-22029] |
| 9 | **position not changed** | unchanged | `mySounds[2].Play()`; `myEffects[2].activate((1.2, 0, 0.3), null)`; `myEffects[3].activate((1.2, 0, 0.3), null)`; `StartCoroutine(completeLichSpawn())` | `3` | unchanged | none | — | [IL L22032-22079] |
| other | nothing style-specific | | | | | | only the common setup/tail runs | [IL L22032-22034] |

Every style 1–9 also does `gameObject.layer = 10` and `health = maxHealth`
(e.g. [IL L21263-21270], [IL L21379-21386], [IL L21516-21523], [IL L21583-21590], [IL L21774-21781],
[IL L21908-21915], [IL L21983-21990], [IL L22015-22022], [IL L22069-22076]).

**Common tail:** `updateHealthBar(0)`; `return true` [IL L22081-22084].

Notes:
- Style-1 and style-4 enemies both get `localScale.x = 1` regardless of which edge they enter from
  [IL L21236-21259, L21556-21579]; the AI is expected to correct facing afterwards.
- For styles 2, 3, 6 nothing in `spawn` gives the enemy a target; `AIState = -1` hands control to
  the `AI` method's spawn-state handling (outside scope). The `actionTimer = 100` of styles 3 and 6
  is likewise consumed there.
- Style 9 is the lich; `completeLichSpawn` coroutine body is at 31382–31507 (outside scope).
- `spawn` does not touch `power`, `maxHealth`, `moveSpeed`, `attackers`, `meleeOccupants`,
  `slideVector`, `myTargetScript` or `invincible` (except style 8 setting it true). Whatever reset
  those need happens in the death coroutines / `clearAllAttackers` (outside scope).

**How enemy stats are initialised and scaled (everything the code shows):**
- Base stats are per-prefab inspector values; the `.ctor` fallbacks are `maxHealth = 1000`,
  `health = 1000`, `power = 30`, `moveSpeed = 1.1`, `primaryActionCooldown = 1.3`,
  `impactForce = 1.2`, `myWeight = 1`, `frictionConstant = 10`, `mana = 50` [IL L5403-5461].
- On spawn: `health = maxHealth`, `mana = 25`, debuffs cleared (above). No level/tier multiplier is
  applied inside `spawn`.
- The only writers of `EnemyScript.maxHealth` / `power` in the whole assembly, besides the `.ctor`
  and `takeDamage` case 5, are `MotherBrain.levelUpEnemies` [IL L70187-70259] and
  `MotherBrain.tutorialDriver` [IL L68824]; see §6.2.

---

## 5. Coroutine stubs inside the line range (bodies NOT covered here)

Each of these methods only constructs its nested iterator class and returns the enumerator; no
gameplay constants live in the stub.

| Stub | Stub lines | Body (nested class) |
|---|---|---|
| `stunBolt(int stunTarget)` | [IL L16687-16698] | `$stunBolt$1281` 23399–23853 |
| `discharge()` | [IL L16701-16711] | `$discharge$1290` 23855–24156 |
| `meteorStorm()` | [IL L16714-16724] | `$meteorStorm$1293` 24158–24342 |
| `chaosBolt()` | [IL L16727-16737] | `$chaosBolt$1296` 24344–24889 |
| `dropMeteor1()` / `dropMeteor2()` | [IL L16740-16763] | 24891–25172 / 25174–25455 |
| `dropBoulder1()` / `dropBoulder2()` | [IL L16766-16789] | 25457–25716 / 25718–25977 |
| `earthquake()` | [IL L16792-16802] | 25979–26165 |
| `enrage()` | [IL L16805-16815] | 26167–26317 |
| `spitAttack(int whichPlayerScript)` | [IL L17141-17152] | 26319–26711 |
| `teleport()` | [IL L17376-17386] | 26713–26914 |
| `webShot()` | [IL L17528-17538] | 26916–27054 |
| `summonGoblinAdds()` | [IL L17631-17641] | 27056–27296 |
| `summonSpiderAdds()` | [IL L17644-17654] | 27298–27586 |
| `enterChargeMode()` | [IL L17657-17667] | 27588–27737 |
| `throwBomb()` | [IL L17670-17680] | 27739–27918 |
| `die()` | [IL L19465-19475] | `$die$1354` 27920–28916 |
| `oozeBossSplit()` | [IL L19478-19488] | 28918–29427 |
| `goblinBossDeath()` | [IL L19491-19501] | 29429–29995 |
| `lichBossDeath()` | [IL L19504-19514] | 29997–30824 |
| `spiderBossDeath()` | [IL L19517-19527] | 30826–31380 |

---

## 6. Cross-references

### 6.1 Calls made by the code in scope

| Call | From | IL |
|---|---|---|
| `EnemyScript.acquireRandomTarget()` (22106–22258) | `residualEffects`, `spawn` styles 1, 4, 5, 7 | [IL L16988], [IL L21272], [IL L21592], [IL L21630], [IL L21657], [IL L21992] |
| `EnemyScript.clearAllAttackers()` (22837–22978) | `residualEffects` (on fragments 6–11) | [IL L17014] |
| `EnemyScript.completeLichSpawn()` (stub 22093–22103) | `spawn` style 9 | [IL L22065-22066] |
| `EnemyScript.die / goblinBossDeath / spiderBossDeath / oozeBossSplit / lichBossDeath` | `takeDamage` | [IL L18955-19040] |
| `PartyMember.takeDamage(int, Vector3, EnemyScript)` (81497–82407) | `residualEffects`, `puddleDamage` | [IL L17122], [IL L17267], [IL L17360] |
| `PartyMember.drainLife(float)`, `.returnDamageValue(float)`, `.adrenalineRush()` | `takeDamage` | [IL L18752], [IL L18778], [IL L18782], [IL L18941] |
| `PartyMember.purgePosition(int)`, `PartyMember.requestPosition(int, EnemyScript)` | `takeDamage` retarget | [IL L19119], [IL L19132], [IL L19175] |
| `EffectScript.activate(Vector3, Transform)` | `residualEffects`, `spawn` styles 6, 9 | [IL L16997], [IL L21930], [IL L22051], [IL L22062] |

### 6.2 Callers of the code in scope (line numbers are call sites, found by text search)

| Method | Called from |
|---|---|
| `spawn()` | `summonSkeletonAdds` [IL L17556-17613]; `$summonGoblinAdds$1340` [IL L27216, L27240]; `$summonSpiderAdds$1344` [IL L27477, L27501, L27525, L27549]; `MotherBrain.enemySpawn` [IL L65344]; `MotherBrain.tutorialDriver` [IL L68817] |
| `takeDamage` | 59 call sites across `EffectScript`, `PartyMember` and its coroutines (count from text search; not enumerated) |
| `hypotheticalDamage` | no `callvirt` to it found by text search of the assembly (only its own definition [IL L19184-19462]). UNVERIFIED whether it is invoked dynamically by name |
| `requestPosition` | `MotherBrain.playerControl` [IL L63600]; `PartyMember.AI` [IL L78745]; `PartyMember.takeDamage` [IL L82306]; `PartyMember.$performSpecial$1850` [IL L96557, L98536] |
| `purgePosition` | `$omegaPunch$1413` [IL L31964]; `MotherBrain.playerControl` [IL L63484]; `PartyMember.$die$1765` [IL L87664]; `PartyMember.$performSpecial$1850` [IL L96546] |
| `flash()` | `$stunBolt$` [IL L23520]; `$meteorStorm$` [IL L24243]; `$oozeBossSplit$` [IL L29025]; `$goblinBossDeath$`, `$lichBossDeath$`, `$spiderBossDeath$` (many, 29556–31249); `$omegaPunch$` [IL L31829]; `MotherBrain.playerControl` [IL L62867] |
| `acquireHealTarget()` | `EnemyScript.AI` [IL L12004, L12050, L12064, L12258] |
| `summonSkeletonAdds()` | `EnemyScript.AI` [IL L16369] |
| `puddleDamage()` | `residualEffects` [IL L16856] |
| `shaderAnimation`, `healthAnimation`, `animateSliding`, `residualEffects` | `remoteUpdate` [IL L5678-5698] |
| `updateHealthBar(int)` | throughout `AI` (6214–14981), `takeDamage`, `spawn`, `heal` [IL L22453], `handleDebuffs` [IL L22535-22775], several coroutines |

**Stat scaling outside scope (for completeness, read directly):**
`MotherBrain.levelUpEnemies()` [IL L70187-70259] does `enemyTier += 1` [IL L70195-70200] and then,
for every non-null entry of `enemyScripts` (stopping at the first null):
`maxHealth = int(maxHealth * 1.1)` [IL L70217-70227] and `power = int(power * 1.1)`
[IL L70229-70241]. Its only call site is inside `MotherBrain.enemySpawn` [IL L65175]; the condition
that triggers it was not read (outside scope). Because it truncates to int on every call, the
scaling compounds as repeated `floor(x * 1.1)`. `MotherBrain.tutorialDriver` sets
`enemyScripts[7].power = 115` right after spawning it [IL L68817-68824].

---

## 7. Uncertain / not determined

- **Buff and debuff index identities.** The code in scope only shows indices and effects:
  attacker `buffs[4, 13, 14, 15, 21, 27]` add damage; enemy `debuffs[2, 6, 13]` add damage taken;
  `debuffs[3]` blocks hit knockback [IL L19064-19073]; `debuffs[4]` makes non-boss enemies slide
  without friction/weight [IL L20239-20262]. No names are present in this range. UNVERIFIED
  inference: `buffs[14]` is the Bard's damage song (it is the only one that reads
  `bardBuffPower`/`bardCoefficient`).
- **Status application and durations.** No method in 16685–22090 *sets* a debuff timer; `spawn`
  only zeroes them all. Debuffs are applied by code elsewhere writing `EnemyScript.debuffs[n]`
  (party powers, `EffectScript`) and ticked in `handleDebuffs` (22458–22834). Durations therefore
  could not be documented from this range.
- **Stun / slow handling** is not in this range either (it lives in `AI` and `handleDebuffs`).
  The only movement-impairing logic here is knockback (§4.12) and the two debuff gates above.
- **Magnitude values** `motherBrain.buffMagnitudes[]` / `debuffMagnitudes[]` — not set in scope;
  values not determined here.
- **Prefab (inspector) data not in the IL:** per-enemy `maxHealth`, `power`, `spawningStyle`,
  `specialDeath`, `isMelee`, `tauntable`, `likeABoss`, `myWeight`, `frictionConstant`,
  `meleePositions[]` offsets, `specialMoves[n].cooldownMax`, which effect/sound each
  `myEffects[n]` / `mySounds[n]` index is, and `motherBrain.edge/floor/cieling`.
- **Which enemy types use which `spawningStyle` / `specialDeath`** — prefab data; only style 9 =
  lich (calls `completeLichSpawn`) and the ooze/goblin/spider/lich death names are evident.
- **Layer names** for layers 10 and 11 are not in the IL.
- **`AIState` meanings** beyond what is listed in §3 belong to `AI` (5703–16684).
- `characterClass == 7` → "Monk" relies on `bh/data/classes.json` ids matching `characterClass`.
- `takeDamage` call-site list (59 sites) was counted, not individually read.

### Contradictions with older notes

- `docs/02-damage-system.md` (datamine) writes the bard bonus as
  `damageAmount += bardBuffPower + tempDamage * bardCoefficient`. The IL is
  `damageAmount = int(damageAmount + bardBuffPower * bardCoefficient)` — a flat bonus with no
  `tempDamage` term [IL L18470-18480].
- The same note calls class 7 an "assassin-type class"; `bh/data/classes.json` id 7 is "Monk".
- The same note's "victim" section implies the enemy formula is shared with `hypotheticalDamage`;
  in fact `hypotheticalDamage` omits `buffs[27]` and uses fixed 0.5/1.0 instead of
  `bardCoefficient` (§4.9).
- `docs/01-positioning-system.md` describes the slots as concentric rings ("ring 2 = slots 2/3,
  ring 3 = slots 4/5", "fill from the inside out"). The IL groups them by **side**: 0/2/3 are the
  left group and 1/4/5 the right group — `BUMP_LEFT` moves 0→2 and adds 3, `BUMP_RIGHT` moves 1→4
  and adds 5, and `purgePosition` collapses 2 or 3 back to 0 and 4 or 5 back to 1
  [IL L20563-20594, L20611-20642, L20957-21091].
- That note's `attackers == 3` summary ("if slots 2 AND 3 are both occupied, bump whichever of
  slot0/slot1…") is inaccurate: when 2 and 3 are both occupied the asker simply takes slot 1 with
  no bump; when 4 and 5 are both occupied it takes slot 0 [IL L20652-20693].
- The task brief expected `takeDamage` to contain defense, crits and status application, and
  `spawn` to contain stat scaling. None of those exist in these methods (see §4.8, §4.15, §6.2).

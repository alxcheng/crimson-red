# Enemy AI state machine, part 2 — `EnemyScript.AI` (AIType 4 – 9)

**Scope:** class `EnemyScript`, method `AI`, second half: IL lines **11200–16684** of
`Assembly-UnityScript.il` (the method spans 5703–16684; part 1 covers 5703–11200).
Line 11200 falls in the middle of the `AIType == 4` branch, inside its `AIState == 0` chase block.
**I backed up to line 10092**, where the `AIType == 4` branch begins, and document that branch in
full (so 10092–11200 overlaps with part 1). Everything from there to the method's single `ret`
(L16683) is covered: AIType 4, 5, 6, 7, 8 and 9.

Supporting code read for context only (cited where used): field declarations and `.ctor`
(L5304–5472), the crowd-control prelude of `AI` (L6084–6632), `acquireRandomTarget`
(L22106–22258), `acquireHealTarget` (L17389–17525), `residualEffects` (L16818–17138),
`takeDamage` tail (L19095–19180), and the state/timer writes inside the coroutines this code starts.

---

## 1. Summary

`AI()` runs once per frame for every living enemy (`remoteUpdate` calls it only while
`health > 0` [IL L5683-5690]). After a shared prelude that handles crowd control (part 1), the
method is one long `if AIType == N … else if …` chain. Each `AIType` is a different enemy brain
and each has its own meaning for the integer `AIState`. This document covers six brains:

| AIType | What the player sees |
|---|---|
| 4 | A big melee boss that chases a hero and bites, and on timers: **pounces** onto a hero (leaps, lands with an area hit and knock-back), **yells and summons spider adds**, and **shoots a web** at a second hero. |
| 5 | A stationary **healer** that never attacks: it keeps picking the most-hurt enemy, casts heals on it while it has mana, and **teleports** on a timer. |
| 6 | A melee chaser that also **spits** at a random *other* hero on a timer. |
| 7 | A **fragment** thrown out when the ooze boss splits: it flies to a landing point, stands up, crawls back to the middle of the arena and waits there to re-merge. |
| 8 | A melee boss with **earthquake** (followed by falling **boulders**), a heavy **"omega punch"** followed by a 4x-speed **charge** to a new hero, and a 10-second **enrage** during which it walks at 20 % speed and uses a stronger attack. |
| 9 | A stationary caster boss: fires **chaos bolts** on its basic cooldown, and on timers casts **meteor storm** (followed by falling meteors), a pulsing **charge-up into a discharge**, **vanishes and summons skeleton adds** (returns when the timer expires or it is the only enemy left), and a **stun bolt** on a random other hero. |

Enemy *names* for these types are not in the IL (AIType is a serialized prefab value); the names
used in headings below are inferred from the coroutine names called and are marked UNVERIFIED.

---

## 2. Fields read or written by this code

Defaults are from `EnemyScript..ctor` [IL L5394-5472]; "prefab" = no default in code, value comes
from the Unity prefab and is **not determinable from the IL**.

| Field | Type | Meaning in this code | Default |
|---|---|---|---|
| `AIType` | int | Selects the brain (4–9 here) [IL L10092-10094, 11955, 12262, 13442, 14241, 15950] | 1 [IL L5433-5434] |
| `AIState` | int | Per-brain state, see section 10 | 0 (CLR default) |
| `specialMoves` | `SpecialMove[]` | Per-enemy timer slots. `SpecialMove` has `moveName:string, timer:float, cooldownMin:float, cooldownMax:float` [IL L5297-5302]. Slot meaning per AIType in section 11 | prefab |
| `actionTimer` | float | Counts **up** by `Time.deltaTime`; a basic action fires when `>= primaryActionCooldown` | 0 |
| `primaryActionCooldown` | float | Seconds between basic actions | 1.3 [IL L5448-5449] |
| `moveSpeed` | float | Units/second walking speed | 1.1 [IL L5439-5440] |
| `runSpeedScale` | float | Run-animation playback speed = `moveSpeed * runSpeedScale` | 1.2 [IL L5445-5446] |
| `canBackpeddle` | bool | If true, run animation plays reversed when moving away from facing | true [IL L5442-5443] |
| `isMelee` | bool | Used by `acquireRandomTarget`/`takeDamage` (slot release, taunt) | true [IL L5436-5437] |
| `tauntable` | bool | Cleared during the AIType 4 pounce | true [IL L5454-5455] |
| `invincible` | bool | Set during pounce / lich phases | false |
| `power` | int | Damage base | 30 [IL L5409-5410] |
| `impactForce` | float | Knock-back scale (used by coroutines) | 1.2 [IL L5412-5413] |
| `mana` | int | Heals left for AIType 5 (`castHeal` subtracts 1 [IL L32505]) | 50 [IL L5460-5461] |
| `meleeOffset` | float | Wind-up delay used by attack coroutines | 0.21 [IL L5457-5458] |
| `meleeSlot` | int | Index of the slot this enemy holds around its target hero | 0 |
| `meleePositions` | `Vector3[]` | This enemy's own ring of slots for heroes attacking it | prefab |
| `myTarget` / `myTargetScript` | Transform / `PartyMember` | Current hero target | null |
| `myHealTarget` | `EnemyScript` | AIType 5's heal target | null |
| `webTarget` | `PartyMember` | AIType 4's web victim | null |
| `movementTarget`, `tempMovementTarget`, `moveVector` | Vector3 | Destination, scratch, normalized direction | — |
| `ignoreMovement` | bool | "Stand still this frame" flag in chase block | false |
| `bombLaunchPoint` | Vector3 | AIType 4: pounce landing point | — |
| `bombVector` | Vector3 | AIType 4: pounce direction (unit). AIType 7: landing **position** | — |
| `bombFlightSpeed` | float | AIType 4/7: flight speed in units/s | 0 |
| `randomValue` | int | Scratch for `Random.Range(0,4)` hero index | 0 |
| `i` | int | Shared loop counter (see pounce bug, 5.5) | 0 |
| `debuffs` | float[] | Remaining debuff durations; indices 10 and 16 are slows here | prefab-sized |
| `debuffColor` | Color | Tint; reset to (0.25,0.25,0.25) when enrage ends | (0.25,0.25,0.25) [IL L5463-5467] |
| `ignoreDebuffColor` | bool | Set true by lich charge-up | false |
| `colorSpeed` | float | Flash speed, set to 2 by lich charge-up | 2.0 [IL L5406-5407] |
| `run`, `basicAction`, `idle`, `spawnAnim`, `paralyzeLoop`, `fearLoop` | AnimationState | Clips `"run"`, `"attack"`, `"idle"`, `"spawn"`, `"paralyzed"`, `"fear"` [IL L5560-5608] | set in `initialize` |
| `myEffects[]`, `mySounds[]` | EffectScript[] / AudioSource[] | Per-prefab effects and sounds, indexed (section 12) | prefab |
| `myRenderer`, `myTransform`, `myAnimation`, `motherBrain` | refs | Set in `initialize` [IL L5481-5505] | — |

`MotherBrain` fields used: `edge` (half-width of arena, x), `floor` / `cieling` (min / max z; the
field is spelled `cieling`), `playerScripts[0..3]`, `enemyScripts[]`, `debuffMagnitudes[]`,
`activeEnemies`, `cameraShaker` (Animation, clip `"shake"`), `fullScreenFlash` (EffectScript).
`PartyMember` fields used: `health`, `myTransform`, `myTarget`, `myTargetEnemyScript`, `meleeSlot`,
`meleePositions[]`, `AIType`, `AIState`, `commandPending`, `invincible`, `run`, `attackers`.

---

## 3. Where this code sits in `AI`

1. Prelude (part 1 territory, summarised only): for enemies with `likeABoss == false`, any of
   `debuffs[13] > 0`, `debuffs[11] > 0`, `debuffs[1] > 0`, `debuffs[3] > 0`, `debuffs[5] > 0`
   handles the crowd-control effect and jumps straight to the end of the method, so **none of the
   brains below run while crowd-controlled**. Each of those branches also resets `AIState` from
   100 to 0 [IL L6084-6632]. Enemies with `likeABoss == true` skip all of them.
2. Dispatch chain: `AIType == 1` [IL L6635], 2 [IL L7830], 3 [IL L8088] (part 1), then
   4 [IL L10092-10094], 5 [IL L11955], 6 [IL L12262], 7 [IL L13442], 8 [IL L14241], 9 [IL L15950].
   Any other value does nothing [IL L15950-15952 → L16683].
3. Every branch ends by jumping to the single `ret` at IL_7633 [IL L16683].

`AIState == -100` (written as `0xffffff9c`) is used by all brains as "busy inside a coroutine":
none of the state tests below match it, so only the unconditional per-type code (golem boulder
drops, lich meteor drops) runs. `takeDamage` also refuses to retarget an enemy in state -100
[IL L19111, L19159].

---

## 4. Shared building blocks (repeated inline many times)

The compiler inlined the same source snippets in every branch. They are described once here and
referred to by name later. Each use site is cited in the per-type sections.

### 4.1 FACE(x) — turn to face a world x coordinate

```
if myTransform.position.x <  x and localScale.x != -1: localScale.x = -1; updateHealthBar(1)
elif myTransform.position.x >= x and localScale.x != 1: localScale.x = 1;  updateHealthBar(1)
```
So `localScale.x == -1` means "facing +x", `+1` means "facing -x" [IL L10379-10479 (first use in
this range), same shape at every use site].

### 4.2 STEP(speedMul) — move one frame toward `movementTarget`

```
moveVector = normalize(movementTarget - position)
if debuffs[10] > 0:   m = motherBrain.debuffMagnitudes[10]
elif debuffs[16] > 0: m = motherBrain.debuffMagnitudes[16]
else:                 m = 1
position += moveVector * moveSpeed * Time.deltaTime * m
myAnimation.CrossFade("run", 0.1)
run.speed = moveSpeed * runSpeedScale * m
```
[IL L10482-10617]. Debuff 10 takes priority over 16; they do not stack. The magnitudes live in
`MotherBrain.debuffMagnitudes` and are not set in this method.

### 4.3 BACKPEDAL — sign of the run animation (chase blocks only)

After STEP's position update, chase blocks pick the animation speed like this:
```
if   localScale.x ==  1 and moveVector.x > 0 and canBackpeddle: run.speed = -moveSpeed*runSpeedScale*m
elif localScale.x == -1 and moveVector.x < 0 and canBackpeddle: run.speed = -moveSpeed*runSpeedScale*m
else:                                                             run.speed =  moveSpeed*runSpeedScale*m
```
i.e. the run clip plays backwards when the enemy moves opposite to its facing
[IL L10984-11073 for the debuff-10 copy; L11109-11198 debuff-16 copy; L11220-11291 no-debuff copy].
The WANDER block (4.4) does **not** have this logic.

### 4.4 WANDER — behaviour while `AIState == 1` (no target available)

`acquireRandomTarget` sets `AIState = 1` and `movementTarget = own position` when it cannot find a
hero [IL L22244-22256]. While in state 1:

1. If `position.x > motherBrain.edge` **or** `position.x < -motherBrain.edge` (outside the arena):
   `movementTarget = Vector3(Random.Range(-edge, edge), 0, Random.Range(floor, cieling))`.
   A new point is picked **only** while out of bounds.
2. If `Distance(position, movementTarget) > 0.07`: FACE(movementTarget.x), then STEP (no backpedal).
   Otherwise `CrossFade("idle", 0.1)`.
3. Call `acquireRandomTarget()` (every frame) and end.

Use sites: AIType 4 [IL L10322-10627], AIType 6 [IL L12346-12669], AIType 8 [IL L14463-14784].

### 4.5 CHASE — melee chase and basic attack (`AIState == 0`, target alive)

Entry condition: `AIState == 0 and myTargetScript != null and myTargetScript.health > 0`.

1. `actionTimer += Time.deltaTime`.
2. FACE(myTarget.position.x).
3. `movementTarget = myTarget.position + myTargetScript.meleePositions[meleeSlot]` (the hero's own
   ring of slots, slot index assigned by `PartyMember.requestPosition`), then clamp:
   `z <= cieling`, `x <= edge`, `x >= -edge`, `z >= floor`.
4. `ignoreMovement = false`, then:
   - If the hero has an enemy target (`myTargetScript.myTargetEnemyScript != null`):
     `tempMovementTarget = myTargetScript.myTarget.position +
      myTargetScript.myTargetEnemyScript.meleePositions[myTargetScript.meleeSlot]`;
     if `myTargetScript.AIType == 3` **and** that hero's target enemy is this enemy **and**
     `Distance(hero position, tempMovementTarget) <= 0.25` → `ignoreMovement = true`
     (the hero attacking me is already standing in its slot on me, so I hold still).
   - Else (hero has no enemy target): if
     `Distance(myTarget.position, position) < Distance(myTarget.position, myTarget.position + this.meleePositions[this.meleeSlot])`
     **and** `myTargetScript.run.weight == 1` (hero is running) → `ignoreMovement = true`.
     Note this second test indexes the **enemy's own** `meleePositions` with the enemy's `meleeSlot`.
5. If `Distance(position, movementTarget) > 0.07` and `basicAction.weight != 1` (not mid-attack)
   and `!ignoreMovement`: STEP + BACKPEDAL.
6. Else:
   - if `actionTimer >= primaryActionCooldown` and `!myTargetScript.invincible`:
     `StartCoroutine(meleeAttack())`;
   - else if `run.weight > 0`: `CrossFade("idle", 0.3)`.
7. Always afterwards: if `basicAction.normalizedTime >= 0.85`: `CrossFade("idle", 0.15)`.

Target-lost rule that follows every CHASE block: if (`AIState == 0` and target exists and
`health <= 0`) or (`myTargetScript == null` and `AIState == 0`) → `acquireRandomTarget()`.

Use sites and line ranges:

| Step | AIType 4 | AIType 6 | AIType 8 (variant, see 9) |
|---|---|---|---|
| entry | L10630-10643 | L12672-12681 | L14787-14830 |
| 1 timer | L10645-10650 | L12689-12691 | L14850-14852 |
| 2 face | L10651-10758 | L12694-12821 | L14855-14981 |
| 3 target + clamps | L10759-10829 | L12823-12887 | L14984-15048 |
| 4 ignoreMovement | L10830-10917 | L12893-12978 | L15076-15161 |
| 5 move | L10918-11292 | L12981-13366 | L15164-15773 |
| 6 attack / idle | L11294-11320 | L13369-13394 | L15776-15885 |
| 7 attack end | L11324-11331 | L13399-13405 | L15890-15896 |
| target lost | L11338-11365 | L13412-13438 | L15903-15946 |

### 4.6 `acquireRandomTarget()` (called from here; body at L22106-22258)

Releases the current slot if melee (`myTargetScript.purgePosition(meleeSlot)`), clears the target,
rolls **one** `Random.Range(0,4)` hero index. If that hero exists, has `attackers < 4` and
`health > 0`: becomes the target, `meleeSlot = hero.requestPosition(0, this)`, `AIState = 0`
(and `Play("idle")` if `basicAction.weight == 1`). If the slot in `playerScripts` is empty the
second branch is a no-op in practice. If no target results: `AIState = 1`,
`movementTarget = position` [IL L22115-22257]. Because only one hero is rolled per call, a failed
roll puts the enemy in WANDER for at least a frame; WANDER re-rolls every frame.

---

## 5. AIType 4 — pouncing / web-shooting / add-summoning melee boss

UNVERIFIED: this is the spider boss (it calls `summonSpiderAdds` and `webShot`).
Branch: [IL L10092-11952].

### 5.1 Special-move triggers (only while `AIState == 0`) [IL L10097-10320]

Every frame in state 0: `specialMoves[0].timer`, `[1].timer`, `[2].timer` each `-= Time.deltaTime`
[IL L10101-10135]. Then, first match wins (all also require `basicAction.weight != 1`, i.e. not in
the middle of the attack animation, and `AIState == 0`):

| Order | Condition | Action | IL |
|---|---|---|---|
| 1 | `specialMoves[0].timer <= 0` | **Pounce start.** `acquireRandomTarget()`. If a target resulted: `bombLaunchPoint = target position` (snapshot), `invincible = true`, `tauntable = false`, `AIState = 5`, `Play("pounce")`, `specialMoves[0].timer = 0.166`. If no target resulted nothing else happens this frame (state is now 1). | L10137-10189 |
| 2 | `specialMoves[1].timer <= 0` | `AIState = 2` (summon adds, see 5.3) | L10192-10214 |
| 3 | `specialMoves[2].timer <= 0` | **Web.** `randomValue = Random.Range(0, 4)` (integer 0–3). The hero `playerScripts[randomValue]` must: exist, `health > 0`, not be `myTargetScript`, `commandPending == false`, `invincible == false`, `AIState != 3`, `AIState != 5`. If all pass: `webTarget = that hero`, `AIState = 6`. If any fails nothing happens and the roll repeats next frame (timer stays <= 0). | L10217-10320 |

### 5.2 State table

| AIState | Meaning | Logic | IL |
|---|---|---|---|
| 1 | no target | WANDER (4.4) | L10322-10627 |
| 0 | chase + bite | CHASE (4.5); basic attack is `meleeAttack()` | L10630-11365 |
| 2 | summon adds | `Play("yell")`; `AIState = -100`; `StartCoroutine(summonSpiderAdds())` | L11368-11385 |
| 5 | pounce wind-up | see 5.4 | L11756-11816 |
| 3 | pounce in flight | see 5.5 | L11388-11699 |
| 4 | pounce recovery | see 5.6 | L11702-11753 |
| 6 | web shot | FACE(webTarget x); `Play("yell")`; `mySounds[9].Play()`; `AIState = -100`; `StartCoroutine(webShot())` | L11820-11950 |
| -100 | inside `summonSpiderAdds` / `webShot` | nothing in `AI`. Both coroutines end with `AIState = 0` [IL L27567, L27041] and re-roll their own timer as `Random.Range(cooldownMin, cooldownMax)` (`specialMoves[1]` [IL L27372-27389]; `specialMoves[2]` [IL L26988-27005]) | — |

### 5.3 Summon (state 2)
One frame only; see table. The summon cooldown slot is `specialMoves[1]` [IL L10192-10198].

### 5.4 Pounce wind-up (state 5) [IL L11756-11816]
```
specialMoves[0].timer -= dt
if specialMoves[0].timer <= 0:
    AIState = 3
    specialMoves[0].timer = 0.633                       # flight time in seconds
    bombFlightSpeed = Distance(position, bombLaunchPoint) / specialMoves[0].timer
    bombVector = normalize(bombLaunchPoint - position)
    clearAllMeleeAttackers()
```
Wind-up length is the 0.166 s set at pounce start [IL L10184-10188].

### 5.5 Pounce flight and landing (state 3) [IL L11388-11699]
```
specialMoves[0].timer -= dt
if specialMoves[0].timer > 0:
    FACE(myTarget.position.x)                                  [L11414-11520]
    position += bombVector * bombFlightSpeed * dt              [L11522-11534]
else:                                                         # landing
    for i in 0..3:                                             [L11538-11660]
        if playerScripts[i].health > 0 and Distance(playerScripts[i].position, position) < 1.2:
            for i in 0..3:                                     # SAME counter field `i`
                if playerScripts[i] exists and health > 0 and Distance(position, playerScripts[i].position) <= 1.3:
                    dir = normalize(playerScripts[i].position - position)
                    playerScripts[i].takeDamage( int(power * 1.5), dir * 8, this )
    motherBrain.cameraShaker.Play("shake")
    myEffects[5].activate(position, null)
    mySounds[6].Play()
    AIState = 4; invincible = false; tauntable = true
    specialMoves[0].timer = 0.1667
```
Notes read directly from the IL:
- The outer and inner loops both use the instance field `i` [IL L11538, L11569]. The inner loop
  leaves `i == 4`, so the outer loop ends after its first hit. Net effect: **if any living hero is
  within 1.2 of the landing spot, every living hero within 1.3 takes `int(power*1.5)` damage with a
  knock-back vector of length 8 pointing away from the boss; this happens at most once.**
- The outer loop does not null-check `playerScripts[i]` before reading `.health` [IL L11543-11552];
  the inner loop does [IL L11574-11580].
- Flight goes to the hero position sampled at pounce start, not the hero's current position.

### 5.6 Pounce recovery (state 4) [IL L11702-11753]
```
specialMoves[0].timer -= dt
if specialMoves[0].timer <= 0:
    specialMoves[0].timer = Random.Range(specialMoves[0].cooldownMin, specialMoves[0].cooldownMax)
    acquireRandomTarget()
    if myTarget != null: AIState = 0
```
(`acquireRandomTarget` itself sets state 0 on success or 1 on failure, so a failed roll goes to WANDER.)

Pounce timeline: 0.166 s wind-up → 0.633 s flight (invincible, untauntable) → land → 0.1667 s
recovery → new random target.

---

## 6. AIType 5 — stationary healer that teleports

UNVERIFIED: enemy name (older notes call enemy healers "necromancers"; not confirmed in IL).
Branch: [IL L11955-12259]. This brain **never moves by walking and never attacks heroes**.

### 6.1 Timers (only while `AIState == 0`) [IL L11960-12024]
```
specialMoves[0].timer -= dt ; specialMoves[1].timer -= dt
if specialMoves[1].timer <= 0 and basicAction.weight != 1: acquireHealTarget()
if specialMoves[0].timer <= 0 and basicAction.weight != 1: StartCoroutine(teleport())
```
These are two independent `if`s (not else-if) [IL L11988-12005, L12006-12024].
`teleport()` re-rolls `specialMoves[0].timer = Random.Range(cooldownMin, cooldownMax)` when it
finishes [IL L26886-26903] and moves the enemy to
`x = Random.Range(-edge+0.7, edge-0.7)`, `z = Random.Range(floor+0.9, cieling-0.8)` [IL L26832-26848].
No write to `specialMoves[1].timer` exists in this branch, in `acquireHealTarget` or in `castHeal`
(searched L17389-17525 and L32434-32633: zero references to `SpecialMove`), so once that timer
reaches 0 the heal target is re-evaluated every frame the enemy is not mid-cast.

### 6.2 States

| AIState | Logic | IL |
|---|---|---|
| -1 (spawning) | if `spawnAnim != null` and `spawnAnim.normalizedTime >= 1`: `Play("idle")`, `acquireHealTarget()` | L12027-12051 |
| 1 | `CrossFade("idle", 0.1)`; `acquireHealTarget()` | L12054-12065 |
| 0, heal target alive (`myHealTarget != null and myHealTarget.health > 0`) | `actionTimer += dt`. If `myTarget != null`: FACE(myTarget x); then if `actionTimer >= primaryActionCooldown` and `mana > 0`: `StartCoroutine(castHeal())`. Afterwards, if `basicAction.normalizedTime >= 0.95`: `CrossFade("idle", 0.1)` | L12068-12229 |
| 0, heal target dead or null | `acquireHealTarget()` | L12232-12258 |

`acquireHealTarget()` scans `motherBrain.enemyScripts`, picks the living enemy with the lowest
`health / maxHealth`, sets `myHealTarget`, sets `myTarget = myHealTarget.myTransform`, and sets
`AIState = 0` [IL L17397-17522]. `castHeal()` spends 1 mana [IL L32505], zeroes `actionTimer`
[IL L32524], waits `meleeOffset` seconds [IL L32545] and calls `myHealTarget.heal(power, this)`
[IL L32596].

---

## 7. AIType 6 — melee chaser with a spit attack

UNVERIFIED: this is the ooze boss body (`spitAttack` + `puddleDamage` belong together, and
`residualEffects`, which only runs for `oozeBoss == true`, uses the other `specialMoves` slots).
Branch: [IL L12262-13439].

### 7.1 Spit trigger [IL L12267-12343]
While `AIState == 0`: `specialMoves[0].timer -= dt`. If `specialMoves[0].timer <= 0` and
`basicAction.weight != 1` and `AIState == 0`:
`randomValue = Random.Range(0, 4)`; if `playerScripts[randomValue]` exists, has `health > 0` and is
**not** the current `myTargetScript` → `StartCoroutine(spitAttack(randomValue))`.
A failed roll simply retries next frame. `spitAttack` sets `AIState = -100` on entry
[IL L26423], plays `"spit"` [IL L26575], and on exit sets `AIState = 0` and
`specialMoves[0].timer = Random.Range(cooldownMin, cooldownMax)` [IL L26679-26700].

### 7.2 States

| AIState | Logic | IL |
|---|---|---|
| 1 | WANDER (4.4) | L12346-12669 |
| 0 | CHASE (4.5), basic attack `meleeAttack()` | L12672-13438 |
| -100 | inside `spitAttack` | — |

---

## 8. AIType 7 — ooze-boss fragment

Fragments are the enemies in `motherBrain.enemyScripts[6..11]`. When the ooze boss dies,
`oozeBossSplit` teleports each living fragment onto the boss, sets its `AIState = 1`, plays
`"knockdown"`, picks its landing point `bombVector`
(`x` = `Random.Range(1.2, edge)` or `Random.Range(-edge, -1.2)`, 50/50;
`z` = `Random.Range(1.5, cieling)` or `Random.Range(floor, -0.5)`, 50/50),
sets `bombFlightSpeed = Distance(position, bombVector) / 0.4`, `specialMoves[0].timer = 0`,
`invincible = false`, shows it and puts it on layer 10 [IL L29193-29396].
Branch in `AI`: [IL L13442-14238].

### 8.1 State 1 — thrown outward [IL L13447-13647]
```
specialMoves[0].timer += dt                      # counts UP in this brain
if Distance(position, bombVector) > 0.1:
    moveVector = normalize(bombVector - position)
    position += moveVector * bombFlightSpeed * dt          # no debuff scaling
# face the arena centre:
if position.x < 0 and localScale.x != -1: localScale.x = -1; updateHealthBar(1)
elif position.x >= 0 and localScale.x != 1: localScale.x = 1; updateHealthBar(1)
if specialMoves[0].timer >= specialMoves[0].cooldownMin: myAnimation.Play("stand")
if specialMoves[0].timer >= specialMoves[0].cooldownMax: AIState = 0
```
Flight takes about 0.4 s (speed = distance / 0.4). `cooldownMin` = time lying down before the
stand-up animation, `cooldownMax` = time before it starts crawling back (prefab values).

### 8.2 State 0 — crawl back to the centre [IL L13650-14236]
```
movementTarget = Vector3(0, 0, 0.5)
face arena centre (same x < 0 test as above)                       [L13675-13789]
if Distance(position, movementTarget) > 0.6:
    STEP (debuff 10 / 16 slows apply)                              [L13801-14125]
    if paralyzeLoop.weight > 0 or fearLoop.weight > 0: myAnimation.Play("run")
    else: myAnimation.CrossFade("run", 0.1)
    BACKPEDAL
else:
    myAnimation.CrossFade("idle", 0.3)
    AIState = 100
```

### 8.3 State 100 — waiting to re-merge
No code in this branch handles 100; the fragment idles. `residualEffects` (runs on the boss object,
`oozeBoss == true`) checks, when `specialMoves[2].timer <= 0` and the boss renderer is hidden, that
every fragment in slots 6–11 with `health > 0` has `AIState == 100`; if so (and
`activeEnemies > 0`) the boss re-forms at `(0,0,0.5)` with `health = maxHealth`, `AIState = 0`,
hides the fragments (invincible, layer 11) and damages heroes within 2.4
[IL L16880-17135]. Fragments never attack: this branch contains no attack call.
A fragment that is crowd-controlled while in state 100 is reset to state 0 by the prelude
[IL L6096-6101 and siblings] and will walk the last < 0.6 units / re-enter 100 next frame.

---

## 9. AIType 8 — earthquake / omega-punch / enrage melee boss

UNVERIFIED: this is the golem boss (`dropBoulder1/2`, `earthquake`, `omegaPunch`, `enrage`).
Branch: [IL L14241-15947].

### 9.1 Boulder dropper — runs every frame in every state [IL L14246-14319]
```
if specialMoves[3].cooldownMin > 0:              # cooldownMin is used as "boulders left"
    specialMoves[3].timer -= dt
    if specialMoves[3].timer <= 0:
        specialMoves[3].timer = 0.6
        specialMoves[3].cooldownMin -= 1
        if myEffects[7].myTransform.position.z == 50: StartCoroutine(dropBoulder1())
        else:                                          StartCoroutine(dropBoulder2())
```
`earthquake()` arms it: `specialMoves[3].timer = 0`, `specialMoves[3].cooldownMin =
specialMoves[3].cooldownMax` [IL L26107-26125]. So an earthquake is followed by `cooldownMax`
boulders, one every 0.6 s, the first immediately. `z == 50` is the "effect 7 is parked / free" test
that alternates between the two boulder coroutines.

### 9.2 Special-move triggers (only while `AIState == 0`) [IL L14322-14394]
```
specialMoves[2].timer -= dt ; specialMoves[0].timer -= dt
if specialMoves[2].timer <= 0 and basicAction.weight != 1:
    StartCoroutine(enrage()); AIState = 2
elif specialMoves[0].timer <= 0 and basicAction.weight != 1:
    StartCoroutine(earthquake())
```
- `enrage()`: plays `"enrage"`, waits 0.26 s, camera shake, `specialMoves[2].timer = 10`,
  `debuffColor = (0.9, 0.25, 0.25)`, waits 0.7 s, then `AIState = 3` [IL L26239-26305].
- `earthquake()`: `invincible = true`, `AIState = -100`, plays `"stomp"`, waits 0.67 s,
  `invincible = false`, shake + sound + effect, waits 0.63 s, arms boulders (9.1),
  `specialMoves[0].timer = Random.Range(cooldownMin, cooldownMax)`, `AIState = 0` [IL L26051-26150].

### 9.3 State table

| AIState | Meaning | IL |
|---|---|---|
| 0 | normal: chase, melee, omega punch | L14787-15900 |
| 1 | no target → WANDER (4.4) | L14448-14784 |
| 2 | waiting for `enrage()` to finish its 0.96 s intro; no branch handles it (only 9.1 runs) | L14371 |
| 3 | enraged (10 s) | L14397-14446 + chase block |
| 4 | charging at a new target at 4x speed (set by `omegaPunch` [IL L32028]); if `myTarget == null` it WANDERs instead [IL L14453-14461] | chase block |
| -100 | inside `earthquake()` | — |

State 3 timer [IL L14397-14446]:
```
specialMoves[2].timer -= dt
if specialMoves[2].timer <= 0:
    specialMoves[2].timer = Random.Range(specialMoves[2].cooldownMin, specialMoves[2].cooldownMax)
    AIState = 0
    debuffColor = Color(0.25, 0.25, 0.25)
```

### 9.4 Chase block variant [IL L14787-15900]
Entry: (`AIState == 0` or `3` or `4`) and `myTargetScript != null` and its `health > 0`
[IL L14787-14830]. Then CHASE (4.5) with these differences:

- Before step 1: `specialMoves[1].timer -= dt` (omega-punch cooldown) [IL L14837-14846].
- After the clamps, in state 3 there is a statement that compares `debuffColor` with
  `Color(0.9, 0.25, 0.25)` and discards the result (`op_Equality` followed by `pop`); it has
  **no effect** [IL L15054-15073]. (It looks like `==` typed where `=` was meant.)
- Movement (step 5) [IL L15197-15773]:

| Case (first match) | Position step per frame | `run.speed` magnitude | IL |
|---|---|---|---|
| `AIState == 4` | `moveVector * moveSpeed * 4 * dt` (slow debuffs ignored) | `moveSpeed * runSpeedScale * 4` | L15197-15308 |
| `debuffs[10] > 0` | `moveVector * moveSpeed * dt * debuffMagnitudes[10]` | `moveSpeed * runSpeedScale * debuffMagnitudes[10]` | L15311-15437 |
| `debuffs[16] > 0` | same with index 16 | same with index 16 | L15440-15566 |
| `AIState == 3` | `moveVector * moveSpeed * 0.2 * dt` | `moveSpeed * runSpeedScale * 0.3` | L15569-15676 |
| otherwise | `moveVector * moveSpeed * dt` | `moveSpeed * runSpeedScale` | L15679-15773 |

  All cases `CrossFade("run", 0.1)` and apply BACKPEDAL sign. Note the consequence of the ordering:
  an enraged golem that is slowed moves at the *slow debuff* rate instead of the 0.2x enrage rate.

- Action selection (step 6), first match wins; every attack case requires
  `actionTimer >= primaryActionCooldown` and `!myTargetScript.invincible` [IL L15776-15885]:

| Condition | Action | IL |
|---|---|---|
| `AIState == 4` | `AIState = 0`; `StartCoroutine(meleeAttack())` (charge ends with a normal hit) | L15776-15799 |
| `AIState == 0` and `specialMoves[1].timer <= 0` | `StartCoroutine(omegaPunch())` | L15802-15830 |
| `AIState == 0` | `StartCoroutine(meleeAttack())` | L15833-15852 |
| `AIState == 3` | `StartCoroutine(enragedMeleeAttack())` | L15855-15875 |
| none of the above and `run.weight > 0` | `CrossFade("idle", 0.3)` | L15878-15885 |

- Step 7 identical (`normalizedTime >= 0.85` → `CrossFade("idle", 0.15)`) [IL L15890-15896].

`omegaPunch()` (for reference): plays `"attack"`, zeroes `actionTimer`, waits `meleeOffset`; if
still valid (`AIState == 0`, alive, attack clip still playing) deals `power * 2` damage with
knock-back `normalize(target - self) * impactForce * 33`, forces the hero to drop this enemy as its
target, re-rolls `specialMoves[1].timer = Random.Range(cooldownMin, cooldownMax)`; then waits
0.5 s, calls `acquireRandomTarget()` and sets `AIState = 4` [IL L31842-32028].

### 9.5 Target-lost rule [IL L15903-15946]
`acquireRandomTarget()` if (`AIState == 0` and target exists and `health <= 0`) or
(`AIState == 3` and target exists and `health <= 0`) or (`myTargetScript == null` and `AIState == 0`).
Read from the code: state 3 with a **null** target and state 4 with a **dead-but-existing** target
are not handled by any branch (the golem does nothing until the state changes).

---

## 10. AIType 9 — stationary caster boss

UNVERIFIED: this is the lich boss (`completeLichSpawn`, `summonSkeletonAdds`, `meteorStorm`).
Branch: [IL L15950-16683]. This brain contains **no movement code** and never checks a target
before its basic attack.

### 10.1 Meteor dropper — runs every frame in every state [IL L15955-16066]
```
if specialMoves[3].cooldownMin > 0:              # "meteors left"
    specialMoves[3].timer -= dt
    if specialMoves[3].timer <= 0:
        specialMoves[3].timer = 0.7
        if specialMoves[3].cooldownMin in (1, 3, 5, 7, 9, 11): StartCoroutine(dropMeteor1())
        else:                                                   StartCoroutine(dropMeteor2())
        specialMoves[3].cooldownMin -= 1
```
`meteorStorm()` arms it (`timer = 0`, `cooldownMin = cooldownMax`) [IL L24277-24295]. One meteor
every 0.7 s, alternating between the two coroutines by odd/even remaining count (odd values above
11 would use `dropMeteor2`).

### 10.2 State 0 — special-move triggers [IL L16070-16470]
Every frame: `specialMoves[0]`, `[1]`, `[2]`, `[5]` timers each `-= dt` [IL L16074-16119].
First match wins; all require `basicAction.weight != 1`:

| Order | Condition | Action | IL |
|---|---|---|---|
| 1 | `specialMoves[0].timer <= 0` and `!invincible` | `AIState = -100`; `StartCoroutine(meteorStorm())` | L16122-16149 |
| 2 | `specialMoves[2].timer <= 0` | **Charge-up.** `ignoreDebuffColor = true`; `mySounds[8].pitch = 0.85`; `mySounds[8].Play()`; `Play("charge")`; `invincible = true`; `myEffects[3].activate(position + (0,0,-0.05), null)`; camera `"shake"`; `AIState = 1`; `myRenderer.material.color = Color(1,1,1)`; `activateColors()`; `colorSpeed = 2`; `specialMoves[2].timer = Random.Range(cooldownMin, cooldownMax)`; `specialMoves[4].timer = 0.35`; `specialMoves[4].cooldownMin = specialMoves[4].cooldownMax` | L16152-16263 |
| 3 | `specialMoves[1].timer <= 0` | **Vanish + summon.** `myEffects[11].activate(position, null)`; `myEffects[12].activate(position, null)`; `mySounds[6].Play()`; `mySounds[10].Play()`; `motherBrain.fullScreenFlash.activate(Vector3(0, 4.2, -7), null)`; `position.x = 15` (off-screen); `invincible = true`; `clearAllAttackers()`; `AIState = 2`; `specialMoves[1].timer = specialMoves[1].cooldownMin`; `summonSkeletonAdds()` | L16266-16370 |
| 4 | `specialMoves[5].timer <= 0` | **Stun bolt.** `randomValue = Random.Range(0, 4)`; hero must exist, `health > 0`, not be `myTargetScript`, `!commandPending`, `!invincible`, `AIState != 3` (this test appears twice; unlike AIType 4 there is no `!= 5` test). If ok: `AIState = -100`; `StartCoroutine(stunBolt(randomValue))`. A failed roll retries next frame. | L16373-16470 |

`meteorStorm()` plays `"laugh"`, waits 0.6 s, arms meteors, re-rolls `specialMoves[0].timer`,
waits 1.5 s, sets `AIState = 0` [IL L24236-24327]. `stunBolt()` re-rolls `specialMoves[5].timer`
[IL L23500-23517], deals `int(power * 0.75)` [IL L23788-23809], and before returning to state 0
raises `specialMoves[2].timer` to at least 6 (`if timer < 6: timer = 6`) [IL L23823-23842].

### 10.3 State 0 — basic attack [IL L16473-16504]
Evaluated after 10.2 if `AIState` is still 0:
```
actionTimer += dt
if actionTimer >= primaryActionCooldown: StartCoroutine(chaosBolt())
if basicAction.normalizedTime >= 0.85: myAnimation.CrossFade("idle", 0.2)
```
`chaosBolt()` zeroes `actionTimer` and plays `"attack"` [IL L24804-24809].

### 10.4 State 1 — charging the discharge [IL L16507-16601]
```
specialMoves[4].timer -= dt
if specialMoves[4].cooldownMin > 0:              # "pulses left"
    if specialMoves[4].timer <= 0:
        mySounds[8].pitch += 0.05
        specialMoves[4].timer = 0.35
        mySounds[8].Play()
        specialMoves[4].cooldownMin -= 1
        myRenderer.material.color = Color(1,1,1); activateColors(); colorSpeed = 2
else:
    StartCoroutine(discharge())
```
The boss is invincible for the whole charge (set in 10.2 row 2). Charge length =
`specialMoves[4].cooldownMax` pulses of 0.35 s each (first pulse 0.35 s after charge start), the
sound rising 0.05 in pitch per pulse from 0.85. `discharge()` sets `AIState = -100`, plays
`"discharge"`, sets `invincible = false`, hits heroes within 2.3 for `int(power * 4.5)` with
knock-back `bombVector * 10`, waits 0.7 s, sets `AIState = 0` [IL L23968-24143].

### 10.5 State 2 — hidden while adds fight [IL L16604-16681]
```
specialMoves[1].timer -= dt
if specialMoves[1].timer <= 0 or motherBrain.activeEnemies == 1:
    invincible = false
    specialMoves[1].timer = specialMoves[1].cooldownMax
    AIState = 0
    mySounds[2].Play()
    myEffects[2].activate(Vector3(1.2, 0, 0.3), null)
    myEffects[3].activate(Vector3(1.2, 0, 0.3), null)
    StartCoroutine(completeLichSpawn())
```
So for `specialMoves[1]`: `cooldownMin` = maximum time hidden, `cooldownMax` = delay until the next
vanish after returning. `completeLichSpawn()` waits 0.3 s, plays `"idle"`, sets `AIState = 0`
[IL L31453-31495]. The return effects are placed at the fixed point (1.2, 0, 0.3).

---

## 11. Lookup tables

### 11.1 AIState meanings per AIType (this document's range)

| AIState | AIType 4 | AIType 5 | AIType 6 | AIType 7 | AIType 8 | AIType 9 |
|---|---|---|---|---|---|---|
| -100 | in `summonSpiderAdds`/`webShot` | — | in `spitAttack` | — | in `earthquake` | in `meteorStorm`/`stunBolt`/`discharge` |
| -1 | (set by `spawn` [IL L21392 etc.]; not handled here) | spawn anim → acquire heal target | not handled | not handled | not handled | not handled |
| 0 | chase/bite + triggers | heal loop + triggers | chase + spit | crawl to centre | chase + triggers | cast loop + triggers |
| 1 | wander | idle, re-acquire | wander | thrown outward | wander | charging discharge |
| 2 | start add summon | — | — | — | enrage intro | hidden during adds |
| 3 | pounce flight | — | — | — | enraged | — |
| 4 | pounce recovery | — | — | — | charge (4x speed) | — |
| 5 | pounce wind-up | — | — | — | — | — |
| 6 | start web shot | — | — | — | — | — |
| 100 | — | — | — | at centre, ready to merge | — | — |

For AIType 4, 6, 8, 9 no branch in this range handles `AIState == -1`; how those enemies leave the
spawn state is outside this range (see Uncertain).

### 11.2 `specialMoves[]` slot usage

| AIType | Slot | `timer` | `cooldownMin` / `cooldownMax` | IL |
|---|---|---|---|---|
| 4 | 0 | pounce cooldown, then phase timer (0.166 / 0.633 / 0.1667) | re-roll range after pounce | L10137-10188, L11728-11742, L11785 |
| 4 | 1 | add-summon cooldown | re-roll range (in `summonSpiderAdds`) | L10192, L27372 |
| 4 | 2 | web cooldown | re-roll range (in `webShot`) | L10217, L26988 |
| 5 | 0 | teleport cooldown | re-roll range (in `teleport`) | L12006, L26886 |
| 5 | 1 | "re-pick heal target" timer; never reset in code read | unused in code read | L11976-12004 |
| 6 | 0 | spit cooldown | re-roll range (in `spitAttack`) | L12271-12283, L26683 |
| 6 (ooze boss object) | 1, 2 | puddle damage tick / re-merge check (in `residualEffects`), reset to `cooldownMax` | — | L16829-16901 |
| 7 | 0 | counts **up** from 0 after split | `cooldownMin` = stand-up time, `cooldownMax` = start-crawl time | L13452-13645 |
| 8 | 0 | earthquake cooldown | re-roll range | L14338-14394, L26127 |
| 8 | 1 | omega-punch cooldown | re-roll range | L14837, L15806, L31999 |
| 8 | 2 | enrage cooldown; set to 10 = enrage duration | re-roll range after enrage | L14326-14371, L14402-14437, L26259 |
| 8 | 3 | boulder interval (0.6) | `cooldownMin` = boulders left, `cooldownMax` = boulders per earthquake | L14246-14319, L26107 |
| 9 | 0 | meteor-storm cooldown | re-roll range | L16122, L24297 |
| 9 | 1 | vanish cooldown / hidden timer | `cooldownMin` = max hidden time, `cooldownMax` = next-vanish delay | L16266, L16359, L16639 |
| 9 | 2 | discharge cooldown (min 6 after a stun bolt) | re-roll range | L16152, L16232, L23823 |
| 9 | 3 | meteor interval (0.7) | `cooldownMin` = meteors left, `cooldownMax` = meteors per storm | L15955-16066, L24277 |
| 9 | 4 | charge pulse interval (0.35) | `cooldownMin` = pulses left, `cooldownMax` = pulses per charge | L16248-16262, L16512-16575 |
| 9 | 5 | stun-bolt cooldown | re-roll range (in `stunBolt`) | L16373, L23500 |

All `cooldownMin`/`cooldownMax` numbers are prefab data and **not in the IL**.

### 11.3 Constants

| Constant | Value | Where |
|---|---|---|
| Arrival tolerance (wander, chase) | 0.07 | L10375, L10924, L12401, L12986, L14516, L15169 |
| Hero-in-slot tolerance for `ignoreMovement` | 0.25 | L10876, L12938, L15121 |
| Run crossfade | 0.1 s | every STEP |
| Idle crossfade after stopping (chase) | 0.3 s | L11320, L13394, L15885 |
| Idle crossfade at end of attack | 0.15 s at `normalizedTime >= 0.85` | L11327-11331, L13401-13405, L15892-15896 |
| Healer: idle crossfade at end of cast | 0.1 s at `normalizedTime >= 0.95` | L12221-12225 |
| Lich: idle crossfade at end of cast | 0.2 s at `normalizedTime >= 0.85` | L16496-16500 |
| Pounce wind-up / flight / recovery | 0.166 / 0.633 / 0.1667 s | L10187, L11785, L11694 |
| Pounce trigger radius / damage radius | < 1.2 / <= 1.3 | L11565, L11605 |
| Pounce damage / knock-back | `int(power*1.5)` / unit vector × 8 | L11623-11641 |
| Fragment landing tolerance / flight time | 0.1 / 0.4 s | L13469, L29348 |
| Fragment home point / arrival radius | (0, 0, 0.5) / 0.6 | L13654, L13796 |
| Golem boulder interval | 0.6 s | L14276 |
| Golem charge speed multiplier | 4 (move and anim) | L15211, L15247 |
| Golem enraged move / anim multiplier | 0.2 / 0.3 | L15583, L15618 |
| Golem enrage duration | 10 s | L26259 |
| Golem enrage tint | (0.9, 0.25, 0.25); reset (0.25, 0.25, 0.25) | L26290, L14442 |
| Lich meteor interval | 0.7 s | L15985 |
| Lich charge pulse / start pitch / pitch step | 0.35 s / 0.85 / +0.05 | L16248, L16171, L16550 |
| Lich hide x position | 15 | L16320-16337 |
| Lich return effect point | (1.2, 0, 0.3) | L16657-16676 |
| Lich full-screen flash position | (0, 4.2, -7) | L16310 |
| Random hero pick | `Random.Range(0, 4)` → 0..3 | L10237-10240, L12303-12306, L16389-16392 |

### 11.4 Animation clip names used in this range
`"pounce"` [L10180], `"run"`, `"idle"`, `"yell"` [L11373, L11935], `"stand"` [L13628],
`"charge"` [L16182]. Started by coroutines called from here: `"attack"`, `"spit"`, `"stomp"`,
`"enrage"`, `"laugh"`, `"discharge"`, `"knockdown"` (citations in the sections above).

## 12. Effect and sound indices touched directly in this range

| AIType | Index | Use | IL |
|---|---|---|---|
| 4 | `myEffects[5]` | pounce landing effect at own position | L11671-11677 |
| 4 | `mySounds[6]` | pounce landing sound | L11680 |
| 4 | `mySounds[9]` | web-shot yell | L11940 |
| 8 | `myEffects[7]` | boulder effect; `position.z == 50` means free | L14295-14300 |
| 9 | `mySounds[8]` | charge pulse sound (pitch ramps) | L16171-16177, L16542-16560 |
| 9 | `myEffects[3]` | charge start effect; also return effect | L16190-16203, L16668 |
| 9 | `myEffects[11]`, `[12]` | vanish effects | L16282-16297 |
| 9 | `mySounds[6]`, `[10]` | vanish sounds | L16300-16305 |
| 9 | `mySounds[2]`, `myEffects[2]` | return sound / effect | L16652-16665 |

---

## 13. Uncertain / not determined

- **Which enemy prefab uses which AIType.** `AIType` is only ever written in the constructor
  (`= 1`) [IL L5433-5434]; real values are prefab data. The names spider boss (4), healer (5),
  ooze boss (6), ooze fragment (7), golem (8), lich (9) are UNVERIFIED inferences from the
  coroutine names each branch calls. AIType 7 = fragment is the best supported: only
  `oozeBossSplit` puts `enemyScripts[6..11]` into the state-1 setup that branch 7 consumes
  [IL L29193-29396].
- All `specialMoves[*].cooldownMin/cooldownMax` values, `motherBrain.edge/floor/cieling`,
  `debuffMagnitudes[10]`/`[16]`, per-prefab `moveSpeed`, `power`, `primaryActionCooldown`, `mana`:
  not in this code (prefab / other classes). Only the constructor defaults in section 2 are known.
- What debuffs 10 and 16 are called. In this code both are movement slows; names are not given here.
- How AIType 4, 6, 8, 9 leave `AIState == -1` (spawning): no branch in L10092–16684 handles -1 for
  them. `spawn` sets -1 [IL L21392, L21528, L21771, L21920, L22024]; the exit is outside my range.
- AIType 5 `specialMoves[1].timer` is never reset in the code I read (AI branch, `acquireHealTarget`,
  `castHeal`); if nothing else resets it, the heal target is re-picked every frame after it first
  expires. UNVERIFIED that no other method resets it.
- Whether `StartCoroutine(discharge())` can fire more than once: it is called every frame while
  the lich is in state 1 with no pulses left [IL L16596-16599]; `discharge` writes
  `AIState = -100` before its first `yield` [IL L23968 vs first wait L24131], so it should run once.
  UNVERIFIED (depends on coroutine start semantics, not on this code).
- The coroutine bodies (`meleeAttack`, `webShot`, `summonSpiderAdds`, `spitAttack`, `teleport`,
  `castHeal`, `earthquake`, `dropBoulder*`, `enrage`, `omegaPunch`, `enragedMeleeAttack`,
  `meteorStorm`, `dropMeteor*`, `stunBolt`, `chaosBolt`, `discharge`, `completeLichSpawn`,
  `summonSkeletonAdds`) were only skimmed for their `AIState` / `specialMoves` / wait constants.
  They need their own documents.

### Contradictions with older notes
- `work/battleheart-encounter-parity.md` line 60 describes `AIState` 100 as "stunned-ish per branch
  at IL_008e". In the code, 100 is written only by the AIType 7 fragment when it reaches the arena
  centre [IL L14236] and is read by `residualEffects` as "ready to merge" [IL L16911-16918]; the
  crowd-control branches merely reset 100 back to 0 [IL L6096-6101].
- The same note and `docs/01-positioning-system.md` line 71 call `AIState == 1` "free/manual
  movement (no combat target)". That holds for AIType 4, 6, 8 (WANDER) but **not** for AIType 5
  (idle + re-acquire heal target), AIType 7 (being thrown) or AIType 9 (charging discharge):
  `AIState` meanings are per-AIType (table 11.1).
- The older note lists golem "enrage (stat boost + slow)". The slow is confirmed (0.2x move) but
  this method contains no stat boost; the enraged difference here is the use of
  `enragedMeleeAttack()` instead of `meleeAttack()` [IL L15855-15873].

---

## 14. Cross-references

| Called from this range | Defined at | Notes |
|---|---|---|
| `acquireRandomTarget()` | L22106-22258 | section 4.6 |
| `acquireHealTarget()` | L17389-17525 | lowest health ratio among enemies |
| `updateHealthBar(1)` | L19530-19937 | after every facing flip |
| `clearAllMeleeAttackers()` | L22981-23132 | at pounce take-off [L11816] |
| `clearAllAttackers()` | L22837-22978 | at lich vanish [L16354] |
| `activateColors()` | L18374-18390 | lich charge flashes |
| `summonSkeletonAdds()` (plain method) | L17541-17628 | lich vanish [L16369] |
| `meleeAttack()` | stub L22261, body `$meleeAttack$1408` L31509-31751 | AIType 4, 6, 8 |
| `summonSpiderAdds()` | body L27298-27586 | AIType 4 state 2 |
| `webShot()` | body L26916-27054 | AIType 4 state 6 |
| `teleport()` | body L26713-26914 | AIType 5 |
| `castHeal()` | body L32434-32633 | AIType 5 |
| `spitAttack(int)` | body L26319-26711 | AIType 6 |
| `dropBoulder1()/2()` | bodies L25457-25716 / L25718-25977 | AIType 8 |
| `enrage()` | body L26167-26317 | AIType 8 |
| `earthquake()` | body L25979-26165 | AIType 8 |
| `omegaPunch()` | body L31753-32041 | AIType 8; sets state 4 |
| `enragedMeleeAttack()` | body L32043-32260 | AIType 8 state 3 |
| `dropMeteor1()/2()` | bodies L24891-25172 / L25174-25455 | AIType 9 |
| `meteorStorm()` | body L24158-24342 | AIType 9 |
| `stunBolt(int)` | body L23399-23853 | AIType 9 |
| `chaosBolt()` | body L24344-24889 | AIType 9 basic attack |
| `discharge()` | body L23855-24156 | AIType 9 state 1 end |
| `completeLichSpawn()` | body L31382-31507 | AIType 9 return |
| `PartyMember.takeDamage(int, Vector3, EnemyScript)` | class PartyMember | pounce landing [L11641] |
| `EffectScript.activate(Vector3, Transform)` | class EffectScript | effects |

Callers / writers that drive this code: `remoteUpdate` calls `AI()` each frame while alive
[IL L5683-5690]; `oozeBossSplit` sets fragments to state 1 [IL L29220-29228]; `residualEffects`
re-merges the ooze boss [IL L16880-17135]; `takeDamage` can retarget and set `AIState = 0` unless
the state is -100 [IL L19095-19178]; `enterChargeMode` (state 4, started from the AIType 3 branch
at L9551, part 1) is **not** used by AIType 8 — the golem's state 4 comes from `omegaPunch`.

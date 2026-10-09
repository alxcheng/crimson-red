# Enemy AI, part 1 — `EnemyScript` fields, `.ctor`, `initialize`, `remoteUpdate`, and `AI` (crowd-control preamble + AIType 1, 2, 3, 4)

**Scope.** Class `EnemyScript` in `Assembly-UnityScript.il`: class header and all 85 field declarations
(L5304–5391), `.ctor` (L5394–5472), `initialize` (L5475–5656), `remoteUpdate` (L5659–5700), and the first
part of `AI` (method spans L5703–16684). This document covers `AI` from L5703 up to and including
**L11952** (the end of the whole `AIType == 4` block). Line 11200 falls in the middle of the AIType 4
chase code, so the AIType 4 block was read to its end.
**The next document should pick up at L11954** (`IL_4259: if AIType == 5 …`).

Helper class `SpecialMove` (L5282–5302) is documented here too because `AI` uses it constantly.

All citations are `[IL Lnnnn]` = line numbers in
`/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`.

---

## 1. Summary

Every enemy on the battlefield has one `EnemyScript`. Once per frame `remoteUpdate` runs the enemy's
shader/health-bar/knock-back animation and, while the enemy is alive, calls `AI()` and then
`handleDebuffs()`.

`AI()` is one big if/else chain:

1. **Crowd-control preamble.** If a non-boss enemy has certain debuff timers running (wander-while-vanished,
   frozen, paralysed, knocked down, feared) the matching behaviour is executed and `AI()` returns — the
   enemy does nothing else that frame. Bosses (`likeABoss == true`) ignore all of these.
2. Otherwise the code branches on `AIType`, then on `AIState`:
   - **AIType 1 — basic melee enemy**: picks a random living hero, walks to a reserved "melee slot" next to
     that hero, and swings every `primaryActionCooldown` seconds.
   - **AIType 2 — stationary ranged enemy**: never moves; turns to face its target and fires every
     `primaryActionCooldown` seconds. If `chaotic`, it re-rolls a random target before every shot.
   - **AIType 3 — boss that summons goblin adds, throws a bomb, and "stampedes" across the screen**
     (plus normal melee in between).
   - **AIType 4 — boss that pounces on a hero, summons spider adds, and shoots a web at a hero** (plus
     normal melee in between).
   - AIType 5 and above: not covered here (start at L11954).

Positions are 3-D vectors used as 2-D: `x` = left/right, `z` = up/down the battlefield, `y` is always 0.

---

## 2. Fields

### 2.1 `SpecialMove` (helper class, L5282–5302)

A plain serializable object; each enemy has an array `specialMoves[]` of these (filled in the Unity prefab,
not in code).

| Field | Type | Meaning | Cite |
|---|---|---|---|
| `moveName` | string | Label only; never read in L5304–11952. | [IL L5285] |
| `timer` | float | Countdown (seconds) until the move is ready; also re-used as a phase timer while the move runs (see AIType 3/4). | [IL L5286] |
| `cooldownMin` | float | Lower bound for the re-armed cooldown. | [IL L5287] |
| `cooldownMax` | float | Upper bound for the re-armed cooldown. Re-arm formula everywhere: `timer = Random.Range(cooldownMin, cooldownMax)`. | [IL L5288], e.g. [IL L8290-8305] |

The `SpecialMove` constructor sets nothing [IL L5291-5300]; all values come from prefab data that is **not in
the IL**.

### 2.2 `EnemyScript` fields (all 85, in declaration order)

"Default" = value assigned in `.ctor` (L5394–5472). Prefabs can override any public field in the Unity
inspector, so a ctor default is only the fallback. "Not used here" means the field is not read or written
anywhere in L5394–11952; its meaning must come from the document that covers the method that uses it.

| # | Field | Type | Default | Meaning (as far as L5304–11952 shows) | Cite |
|---|---|---|---|---|---|
| 1 | `specialMoves` | `SpecialMove[]` | – | Per-enemy special-move timers. AIType 3 uses indices 0,1,2; AIType 4 uses 0,1,2 (see §7, §8). | [IL L5307] |
| 2 | `oozeBoss` | bool | – | If true, `remoteUpdate` also calls `residualEffects()` every frame (even when dead). | [IL L5308], [IL L5693-5698] |
| 3 | `likeABoss` | bool | – | Boss flag. When true the enemy ignores every crowd-control branch of the AI preamble (§6). | [IL L5309], [IL L6056], [IL L6091], [IL L6303], [IL L6355], [IL L6382], [IL L6427] |
| 4 | `immuneToDeath` | bool | – | Not used here. | [IL L5310] |
| 5 | `debuffs` | `float[]` | – | Array of debuff timers indexed by debuff id; "active" means `debuffs[id] > 0`. Ids read in this range: 1, 3, 5, 10, 11, 13, 16 (see §5). | [IL L5311] |
| 6 | `myEffectsPrefabs` | `Transform[]` | – | Prefabs of visual effects; `initialize` instantiates one of each. | [IL L5312], [IL L5614-5622] |
| 7 | `myEffects` | `EffectScript[]` | – | The instantiated effects (same index as `myEffectsPrefabs`). `activate(position, parentTransform)` shows one. Indices used here: AIType 3 → 1, 2 (bomb explosion), 5 (the bomb projectile); AIType 4 → 5 (pounce landing). | [IL L5313], [IL L5623-5639], [IL L8133], [IL L8186-8201], [IL L11670] |
| 8 | `mySounds` | `AudioSource[]` | – | Sound sources. Indices `0 … totalMeleeSounds-1` are melee-hit sounds picked at random [IL L10060-10077]; AIType 3 uses 5 (bomb explosion) [IL L8202]; AIType 4 uses 6 (pounce landing) [IL L11679] and 9 (web yell) [IL L11939]. (Coroutines use 7 = charge start [IL L27658], 8 = bomb throw [IL L27812].) | [IL L5314] |
| 9 | `totalMeleeSounds` | int | 5 | Number of melee-hit sounds at the start of `mySounds`. | [IL L5315], [IL L5403-5404] |
| 10 | `motherBrain` | `MotherBrain` | – | Reference to the battle manager; found in `initialize` via `GameObject.Find("**MOTHERBRAIN").GetComponent("MotherBrain")`. Used for `playerScripts[0..3]`, arena bounds `edge/floor/cieling`, `debuffMagnitudes[]`, `DB.tutorial`, `cameraShaker`. | [IL L5316], [IL L5481-5487] |
| 11 | `attackers` | int | – | Not used here. | [IL L5317] |
| 12 | `meleeSlot` | int | – | Index of the melee position this enemy reserved around its target hero (returned by `PartyMember.requestPosition(0, this)`); indexes `myTargetScript.meleePositions[]`. | [IL L5318], [IL L6697-6703], [IL L7158-7170] |
| 13 | `colorSpeed` | float | 2.0 | Not used here. | [IL L5319], [IL L5406-5407] |
| 14 | `myRenderer` | `Renderer` | – | Renderer of child `"geometry"`, cached in `initialize`. | [IL L5320], [IL L5496-5505] |
| 15 | `myTransform` | `Transform` | – | Cached own transform. | [IL L5321], [IL L5488-5491] |
| 16 | `myAnimation` | `Animation` | – | Cached own Animation component. | [IL L5322], [IL L5492-5495] |
| 17 | `power` | int | 30 | Attack power. Used as the base of special-attack damage (bomb ×1.5, stampede ×0.2, pounce ×1.5). | [IL L5323], [IL L5409-5410], [IL L8261-8278], [IL L10042-10059], [IL L11624-11641] |
| 18 | `impactForce` | float | 1.2 | Not used here. | [IL L5324], [IL L5412-5413] |
| 19 | `health` | float | 1000.0 | Current hit points. `remoteUpdate` only runs `AI`/`handleDebuffs` when `health > 0`. | [IL L5325], [IL L5415-5416], [IL L5683-5692] |
| 20 | `maxHealth` | int | 1000 | Not used here. | [IL L5326], [IL L5418-5419] |
| 21 | `healthTimer` | float | – | Not used here. | [IL L5327] |
| 22 | `healthVisible` | bool | – | Not used here. | [IL L5328] |
| 23 | `greenHealthA` | `Transform` (private) | – | Child `"life/bar_greenLeft"`. | [IL L5329], [IL L5506-5511] |
| 24 | `redHealthA` | `Transform` (private) | – | Child `"life/bar_redLeft"`. | [IL L5330], [IL L5512-5517] |
| 25 | `greenHealthB` | `Transform` (private) | – | Child `"life/bar_greenRight"`. | [IL L5331], [IL L5518-5523] |
| 26 | `redHealthB` | `Transform` (private) | – | Child `"life/bar_redRight"`. | [IL L5332], [IL L5524-5529] |
| 27 | `movementTarget` | `Vector3` | – | The point the enemy is currently walking to. | [IL L5333], [IL L6748-6767], [IL L7158-7170] |
| 28 | `slideVector` | `Vector3` | – | Not used here. | [IL L5334] |
| 29 | `frictionConstant` | float | 10.0 | Not used here. | [IL L5335], [IL L5421-5422] |
| 30 | `myWeight` | float | 1.0 | Not used here. | [IL L5336], [IL L5424-5425] |
| 31 | `conflagScaleFactor` | float | 1.0 | Not used here. | [IL L5337], [IL L5427-5428] |
| 32 | `aoeRadiusBonus` | float | – | Not used here. | [IL L5338] |
| 33 | `spawningStyle` | int | 1 | Spawn style id. Only test in this range: AIType 2 waits for its spawn animation only when `spawningStyle == 3`. | [IL L5339], [IL L5430-5431], [IL L7839] |
| 34 | `myTargetScript` | `PartyMember` | – | The hero this enemy is targeting (null = none). | [IL L5340] |
| 35 | `myTarget` | `Transform` | – | Transform of that hero. | [IL L5341] |
| 36 | `AIType` | int | 1 | Selects the behaviour block of `AI()`: 1 melee, 2 ranged, 3 and 4 bosses (§7–§10). | [IL L5342], [IL L5433-5434], [IL L6634], [IL L7829], [IL L8087], [IL L10091] |
| 37 | `isMelee` | bool | true | Not read inside `AI` L5703–11952. (Used by `acquireRandomTarget`, see §11.) | [IL L5343], [IL L5436-5437] |
| 38 | `chaotic` | bool | – | AIType 2 only: if true, re-roll a random target each time the attack cooldown is ready. | [IL L5344], [IL L7908-7918] |
| 39 | `AIState` | int | – (0) | State inside the current AIType. See §4. | [IL L5345] |
| 40 | `actionTimer` | float | – | Seconds since the last basic attack; counts **up**; attack allowed when `actionTimer >= primaryActionCooldown`. Forced to 100 by several crowd-control branches so the enemy attacks immediately when it recovers. | [IL L5346], [IL L7044-7049], [IL L7756], [IL L6103] |
| 41 | `moveSpeed` | float | 1.1 | Walk speed, world units per second. | [IL L5347], [IL L5439-5440], [IL L6990-7003] |
| 42 | `canBackpeddle` | bool | true | If true, when the enemy moves away from the direction it is facing, the run animation is played backwards (negative speed). | [IL L5348], [IL L5442-5443], [IL L7404-7439] |
| 43 | `runSpeedScale` | float | 1.2 | Run-animation playback speed = `moveSpeed * runSpeedScale` (× slow factor). | [IL L5349], [IL L5445-5446], [IL L7009-7016] |
| 44 | `primaryActionCooldown` | float | 1.3 | Seconds between basic attacks. | [IL L5350], [IL L5448-5449], [IL L7756] |
| 45 | `standingAnimLength` | float | 0.5 | Length of the "stand" (get-up) animation; knock-down branch switches from "knockdown" to "stand" when `debuffs[3] <= standingAnimLength`. | [IL L5351], [IL L5451-5452], [IL L6394-6416] |
| 46 | `tauntable` | bool | true | Set to false while the AIType 4 boss is pouncing and back to true on landing. Not read in this range. | [IL L5352], [IL L5454-5455], [IL L10172], [IL L11690] |
| 47 | `run` | `AnimationState` (private) | – | `myAnimation["run"]`. | [IL L5353], [IL L5559-5564] |
| 48 | `basicAction` | `AnimationState` (private) | – | `myAnimation["attack"]`, only assigned if that clip exists. `basicAction.weight == 1` is the test for "attack animation is currently playing". | [IL L5354], [IL L5565-5577], [IL L7326] |
| 49 | `spawnAnim` | `AnimationState` (private) | – | `myAnimation["spawn"]`, only assigned if that clip exists (otherwise null). | [IL L5355], [IL L5578-5590] |
| 50 | `paralyzeLoop` | `AnimationState` (private) | – | `myAnimation["paralyzed"]`. | [IL L5356], [IL L5597-5602] |
| 51 | `fearLoop` | `AnimationState` (private) | – | `myAnimation["fear"]`. | [IL L5357], [IL L5603-5608] |
| 52 | `idle` | `AnimationState` (private) | – | `myAnimation["idle"]`. | [IL L5358], [IL L5591-5596] |
| 53 | `invincible` | bool | – | Set true during AIType 3 stampede (by `enterChargeMode`, [IL L27694]) and AIType 4 pounce; cleared when they end. Not read in this range. | [IL L5359], [IL L9948], [IL L10169], [IL L11687] |
| 54 | `specialDeath` | int | – | Not used here. | [IL L5360] |
| 55 | `tempInstance` | `Transform` (private) | – | Scratch variable for `Instantiate` in `initialize`. | [IL L5361], [IL L5614-5622] |
| 56 | `i` | int (private) | – | Shared loop counter (a field, not a local — nested loops that both use it interfere, see §8.5). | [IL L5362] |
| 57 | `fearLocation` | `Vector3` | – | Random point the enemy runs to while feared / vanished. | [IL L5363], [IL L6132-6159] |
| 58 | `fearTimer` | float | – | Countdown until a new `fearLocation` is picked. | [IL L5364], [IL L6111-6164] |
| 59 | `ignoreMovement` | bool (private) | – | Per-frame flag: "do not walk this frame, the target is coming to me" (§7.4 step 5). | [IL L5365], [IL L7229-7316] |
| 60 | `tempMovementTarget` | `Vector3` (private) | – | Scratch vector (target hero's own destination; bomb flight direction for AIType 3). | [IL L5366], [IL L7239-7254], [IL L8121-8132] |
| 61 | `stampedeCounter` | float (private) | – | AIType 3 stampede: accumulates time; damage tick every 0.16 s. | [IL L5367], [IL L9971-9985] |
| 62 | `randomValue` | int (private) | – | Scratch: random hero index 0–3. | [IL L5368], [IL L8398-8402] |
| 63 | `bombVector` | `Vector3` (private) | – | AIType 3: bomb target point, later the explosion point. AIType 4: normalized pounce direction. | [IL L5369], [IL L8434-8443], [IL L8178-8185], [IL L11804-11814] |
| 64 | `bombLaunchPoint` | `Vector3` (private) | – | AIType 3: where the bomb started (set in `throwBomb`, [IL L27874-27883]). AIType 4: pounce landing point (target hero's position when the pounce began). | [IL L5370], [IL L10163-10168] |
| 65 | `bombFlightSpeed` | float (private) | – | AIType 3: bomb speed = distance / 0.9 (set in `throwBomb`, [IL L27858-27873]). AIType 4: pounce speed = distance / 0.633. | [IL L5371], [IL L11790-11803] |
| 66 | `webTarget` | `PartyMember` (private) | – | AIType 4: hero chosen for the web shot. | [IL L5372], [IL L10310-10317] |
| 67 | `moveVector` | `Vector3` (private) | – | Normalized direction of travel this frame. | [IL L5373], [IL L6267-6279] |
| 68 | `ignoreDebuffColor` | bool (private) | – | Not used here. | [IL L5374] |
| 69 | `myHealTarget` | `EnemyScript` (private) | – | Not used here. | [IL L5375] |
| 70 | `redAnim` | bool | – | Not used here. | [IL L5376] |
| 71 | `greenAnim` | bool | – | Not used here. | [IL L5377] |
| 72 | `blueAnim` | bool | – | Not used here. | [IL L5378] |
| 73 | `tempDamage` | int (private) | – | Not used here. | [IL L5379] |
| 74 | `meleePositions` | `Vector3[]` | – | Offsets (relative to this enemy) of the slots where heroes stand to melee **this enemy**. Read on the hero's target enemy to work out where the hero is heading. | [IL L5380], [IL L7239-7254], [IL L7283-7304] |
| 75 | `meleeOccupants` | `PartyMember[]` | – | Not used here. | [IL L5381] |
| 76 | `meleeOffset` | float | 0.21 | Not used here. | [IL L5382], [IL L5457-5458] |
| 77 | `mana` | int | 50 | Not used here. | [IL L5383], [IL L5460-5461] |
| 78 | `debuffColor` | `Color` | (0.25, 0.25, 0.25) | Not used here. | [IL L5384], [IL L5463-5467] |
| 79 | `mostRecentDebuff` | int | -1 | Not used here. | [IL L5385], [IL L5469-5470] |
| 80 | `poisonMagnitude` | float | – | Not used here. | [IL L5386] |
| 81 | `meteorDotMagnitude` | float | – | Not used here. | [IL L5387] |
| 82 | `conflagDotMagnitude` | float | – | Not used here. | [IL L5388] |
| 83 | `baelDotMagnitude` | float | – | Not used here. | [IL L5389] |
| 84 | `plagueDotMagnitude` | float | – | Not used here. | [IL L5390] |
| 85 | `rangerDotMagnitude` | float | – | Not used here. | [IL L5391] |

### 2.3 Fields of other classes read by this code

| Member | Meaning / value | Cite |
|---|---|---|
| `MotherBrain.playerScripts[0..3]` | The four hero slots (`PartyMember`, entries may be null). All "for each hero" loops run `i = 0..3`. | [IL L8212-8289] |
| `MotherBrain.edge` | Half-width of the walkable arena: x is kept in `[-edge, +edge]`. MotherBrain ctor default 3.42 (re-assigned later in MotherBrain at L108468 — outside this scope). | [IL L7185-7214], [IL L59275-59276] |
| `MotherBrain.floor` | Minimum z of the arena. Ctor default -2.8. | [IL L7215-7228], [IL L59278-59279] |
| `MotherBrain.cieling` (sic) | Maximum z of the arena. Ctor default 4.3. | [IL L7171-7184], [IL L59272-59273] |
| `MotherBrain.debuffMagnitudes[id]` | Strength of debuff `id`. For ids 10 and 16 it is used as a movement-speed multiplier. | [IL L6900-6919], [IL L6949-6968] |
| `MotherBrain.DB.tutorial` | True during the tutorial battle. | [IL L6675-6680] |
| `MotherBrain.cameraShaker` | `Animation`; `Play("shake")` shakes the camera. | [IL L8172-8177], [IL L11664-11669] |
| `PartyMember.health`, `.myTransform`, `.invincible`, `.attackers`, `.commandPending`, `.AIState`, `.AIType`, `.run`, `.myTarget`, `.myTargetEnemyScript`, `.meleeSlot`, `.meleePositions[]` | Hero state read for targeting / positioning. | see sections below |
| `PartyMember.requestPosition(int, EnemyScript) : int` | Reserves a melee slot around the hero and returns its index. | [IL L6697-6703] |
| `PartyMember.takeDamage(int damage, Vector3 knockback, EnemyScript source)` | Applies damage + knock-back to a hero. | [IL L8261-8278] |
| `EffectScript.activate(Vector3 pos, Transform parent)`, `EffectScript.myTransform`, `EffectScript.myEnemyBoss` | Effect object API. | [IL L8186-8193], [IL L5633-5639] |

---

## 3. Small methods

### 3.1 `.ctor` [IL L5394-5472]

Sets the defaults listed in the "Default" column of §2.2 and nothing else. Fields with "–" are left at
0 / false / null.

### 3.2 `initialize()` [IL L5475-5656]

Called by other code to set the enemy up (caller not in this scope).

1. `motherBrain = GameObject.Find("**MOTHERBRAIN").GetComponent("MotherBrain")` [IL L5481-5487].
2. Cache `myTransform`, `myAnimation` [IL L5488-5495].
3. `myRenderer = myTransform.Find("geometry").GetComponent(Renderer)` [IL L5496-5505].
4. Health-bar children: `greenHealthA = "life/bar_greenLeft"`, `redHealthA = "life/bar_redLeft"`,
   `greenHealthB = "life/bar_greenRight"`, `redHealthB = "life/bar_redRight"` [IL L5506-5529].
5. Animation layers: `"hitReact"` → layer 2 and blendMode 1 (`AnimationBlendMode` value 1 = Additive in
   Unity) [IL L5530-5541]; `"showHealth"` → layer 5 [IL L5542-5547]; `"hideHealth"` → layer 5
   [IL L5548-5553].
6. `myAnimation.Play("idle")` [IL L5554-5558].
7. Cache animation states: `run = ["run"]` [IL L5559-5564]; `basicAction = ["attack"]` only if that state
   exists [IL L5565-5577]; `spawnAnim = ["spawn"]` only if it exists [IL L5578-5590]; `idle = ["idle"]`
   [IL L5591-5596]; `paralyzeLoop = ["paralyzed"]` [IL L5597-5602]; `fearLoop = ["fear"]`
   [IL L5603-5608].
8. For `i = 0 .. myEffectsPrefabs.length-1`: `tempInstance = Instantiate(myEffectsPrefabs[i])`;
   `myEffects[i] = tempInstance.GetComponent("EffectScript")`; `myEffects[i].myEnemyBoss = this`
   [IL L5609-5651]. (`myEffects` must already be an array of the right size — it is not allocated here.)
9. `muteSoundEffects()` [IL L5653-5654].

Animation clip names an enemy prefab is expected to have (from this method and from `AI`): `idle`, `run`,
`attack`, `spawn`, `paralyzed`, `fear`, `hitReact`, `showHealth`, `hideHealth`, `vanish`, `knockdown`,
`stand`; bosses additionally `summon`, `charge`, `throw` (AIType 3) and `pounce`, `yell` (AIType 4).

### 3.3 `remoteUpdate()` [IL L5659-5700]

Per-frame tick (called from outside; the name suggests the battle manager calls it rather than Unity's
`Update` — UNVERIFIED: the caller is not in this scope).

```
if myTransform.position.x == 10: return            // [IL L5667-5675]  enemy parked at x == 10 is inactive
shaderAnimation()                                   // [IL L5677-5678]
healthAnimation()                                   // [IL L5679-5680]
animateSliding()                                    // [IL L5681-5682]
if health > 0:                                      // [IL L5683-5687]
    AI()                                            // [IL L5689-5690]
    handleDebuffs()                                 // [IL L5691-5692]
if oozeBoss: residualEffects()                      // [IL L5693-5698]
```

UNVERIFIED: "x == 10" is presumably the off-screen pool position for unused/dead enemies; the code only
shows the comparison.

---

## 4. `AIState` values (as used in L5703–11952)

`AIState` meaning depends on `AIType`. Values −2, −1, 0, 1 are shared; 2–6 are boss-specific.

| Value | Hex in IL | Meaning | Where set (in or near this scope) |
|---|---|---|---|
| **-100** | `0xffffff9c` | "Busy — a coroutine is running a special move". No branch of AIType 3/4 handles it, so the AI idles until the coroutine sets a new state. | Set at [IL L9526], [IL L9546], [IL L9566], [IL L11377], [IL L11944] |
| **-2** | `0xfffffffe` | AIType 1 only: scripted hold. Each frame: if `basicAction.normalizedTime >= 0.8`, cross-fade to `idle` over 0.1 s; nothing else. | Handled at [IL L6639-6655]. Set from `MotherBrain.tutorialDriver` [IL L66527] (outside scope). |
| **-1** | `ldc.i4.m1` | Spawning — waiting for the spawn animation. | Handled at [IL L6657-6718] (AIType 1), [IL L7834-7870] (AIType 2). Set by `spawn` (L21392 etc., outside scope). |
| **0** | | Normal: has (or wants) a target; chase / attack. | Set by `acquireRandomTarget` on success [IL L22188], [IL L22235] |
| **1** | | No target available (no living, attackable hero found). Enemy idles / walks back inside the arena and retries `acquireRandomTarget()` every frame. | Set by `acquireRandomTarget` on failure [IL L22244-22250] |
| **2** | | AIType 3: start "summon goblin adds". AIType 4: start "summon spider adds". | [IL L8375], [IL L10211] |
| **3** | | AIType 3: start "charge" (wind-up for stampede). AIType 4: pounce in flight. | [IL L8467], [IL L11781] |
| **4** | | AIType 3: stampeding across the screen. AIType 4: pounce landing recovery. | [IL L27690] (`enterChargeMode`), [IL L11684] |
| **5** | | AIType 3: start bomb throw. AIType 4: pounce wind-up. | [IL L8444], [IL L10175] |
| **6** | | AIType 4: start web shot. | [IL L10318] |
| **100** | `0x64` | In this range only *compared*: each crowd-control branch does `if AIState == 100: AIState = 0`. It is a different state from −100; its only write is at [IL L14236-14237] in the second half of `AI` (part 2). See §12. | [IL L6095-6102], [IL L6307-6314], [IL L6359-6366], [IL L6386-6393], [IL L6431-6438] |

---

## 5. Debuff ids referenced

The names of debuff ids are not in the IL. What each id *does* inside `AI`:

| `debuffs[id]` | Effect in `AI` when `> 0` | Bosses (`likeABoss`) | Cite |
|---|---|---|---|
| 13 (`0x0d`) | Plays `"vanish"`; enemy wanders to random points at fixed speed 1.2; no attacks. Highest priority. | ignored | [IL L6083-6293] |
| 11 (`0x0b`) | Total freeze: all animation speeds set to 0; no movement, no attacks. | ignored | [IL L6295-6345] |
| 1 | Plays `"paralyzed"`; nothing else. | ignored | [IL L6347-6372] |
| 3 | Knock-down: `"knockdown"` then `"stand"`. | ignored | [IL L6374-6417] |
| 5 | Fear: plays `"fear"`, runs to random points at `moveSpeed × 2.5`. | ignored | [IL L6419-6632] |
| 10 (`0x0a`) | Slow: walking speed and run-animation speed multiplied by `motherBrain.debuffMagnitudes[10]`. | **applies to bosses too** (no `likeABoss` test) | [IL L6892-6939], [IL L7350-7494], [IL L8642-8689], [IL L9100-9223], [IL L10493-10540], [IL L10951-11074] |
| 16 (`0x10`) | Slow (second kind): same but `debuffMagnitudes[16]`. Checked only if `debuffs[10] <= 0` — the two never stack. | applies to bosses too | [IL L6941-6988], [IL L7496-7640], [IL L8691-8738], [IL L9225-9348], [IL L10542-10589], [IL L11076-11199] |

The magnitudes themselves (`debuffMagnitudes[10]`, `[16]`) are not set in this scope.

---

## 6. `AI()` — crowd-control preamble [IL L6048-6632]

`AI()` has 338 locals [IL L5709-6047]; all are compiler temporaries (no named gameplay locals). Every
branch of the method ends by jumping to `IL_7633`, which is the single `ret` at [IL L16683]; "return"
below means that jump.

Evaluated top to bottom every frame; first matching branch wins.

### 6.0 Un-freeze [IL L6048-6082]
```
if debuffs[11] <= 0 and not likeABoss and basicAction.speed == 0:
    basicAction.speed = fearLoop.speed = paralyzeLoop.speed = idle.speed = 1
```
(`run.speed` is not restored here; it is rewritten whenever the enemy walks.) Falls through to 6.1.

### 6.1 Debuff 13 — "vanish" wander [IL L6083-6293]
Condition: `debuffs[13] > 0 and not likeABoss` [IL L6083-6093].
1. `if AIState == 100: AIState = 0` [IL L6095-6102].
2. `actionTimer = 100` [IL L6103-6105].
3. `myAnimation.Play("vanish")` [IL L6106-6110].
4. `fearTimer -= deltaTime` [IL L6111-6116].
5. If `fearTimer <= 0` **or** `Distance(position, fearLocation) < 0.1` [IL L6117-6130]:
   - `fearLocation = ( Random.Range(-edge + 0.7, edge - 0.7), 0, Random.Range(floor + 0.9, cieling - 0.8) )` [IL L6132-6159]
   - `fearTimer = Random.Range(0.4, 1.0)` [IL L6160-6164]
6. Face `fearLocation` (facing rule §6.6) [IL L6165-6266].
7. `moveVector = normalize(fearLocation - position)`; `position += moveVector * 1.2 * deltaTime` — fixed
   speed 1.2, **not** `moveSpeed` [IL L6267-6292].
8. return [IL L6293].

### 6.2 Debuff 11 — freeze [IL L6295-6345]
Condition: `debuffs[11] > 0 and not likeABoss`.
1. `if AIState == 100: AIState = 0` [IL L6307-6314].
2. `if run exists: run.speed = 0` [IL L6315-6324]; `basicAction.speed = fearLoop.speed = paralyzeLoop.speed = idle.speed = 0` [IL L6325-6344].
3. return [IL L6345].

### 6.3 Debuff 1 — paralysed [IL L6347-6372]
Condition: `debuffs[1] > 0 and not likeABoss`. `if AIState == 100: AIState = 0`; `Play("paralyzed")`; return.
(`actionTimer` is **not** touched.)

### 6.4 Debuff 3 — knocked down [IL L6374-6417]
Condition: `debuffs[3] > 0 and not likeABoss`. `if AIState == 100: AIState = 0` [IL L6386-6393], then:
- `if debuffs[3] > standingAnimLength: Play("knockdown")` [IL L6394-6406]
- `else: actionTimer = 100; Play("stand")` [IL L6409-6416]
- return [IL L6417].

### 6.5 Debuff 5 — fear [IL L6419-6632]
Condition: `debuffs[5] > 0 and not likeABoss`. Same as 6.1 except:
- animation is `Play("fear")` [IL L6442-6446];
- movement is `position += moveVector * moveSpeed * deltaTime * 2.5` [IL L6616-6631].

Everything else is identical: `AIState 100→0` [IL L6431-6438]; `actionTimer = 100` [IL L6439-6441];
`fearTimer -= deltaTime` [IL L6447-6452]; re-pick when `fearTimer <= 0` or within 0.1 of `fearLocation`
[IL L6453-6466] using the same ranges (x: `-edge+0.7 … edge-0.7`, z: `floor+0.9 … cieling-0.8`)
[IL L6468-6495] and `fearTimer = Random.Range(0.4, 1.0)` [IL L6496-6500]; facing [IL L6501-6602];
return [IL L6632].

### 6.6 Facing rule (used everywhere in `AI`)
Facing is stored in `myTransform.localScale.x`: **−1 = facing right (+x), +1 = facing left (−x)**.
To face a point `P`:
```
if position.x <  P.x and localScale.x != -1: localScale.x = -1; updateHealthBar(1)
elif position.x >= P.x and localScale.x != 1: localScale.x =  1; updateHealthBar(1)
```
First occurrence [IL L6165-6266]. `updateHealthBar(1)` is called only on an actual flip (so the bar is not
mirrored with the sprite — UNVERIFIED purpose; the call is certain).

### 6.7 Otherwise
Branch on `AIType`: 1 → §7 [IL L6634]; 2 → §9 [IL L7829]; 3 → §8 [IL L8087]; 4 → §10 [IL L10091];
else continue at [IL L11954] (next document).

---

## 7. AIType 1 — basic melee enemy [IL L6634-7827]

### 7.1 AIState −2 (scripted hold) [IL L6639-6655]
`if basicAction.normalizedTime >= 0.8: myAnimation.CrossFade("idle", 0.1)`. Return.

### 7.2 AIState −1 (spawning) [IL L6657-6718]
```
if spawnAnim != null:                                           // [IL L6662-6667]
    if spawnAnim.normalizedTime >= 1:                           // [IL L6668-6674]
        if not motherBrain.DB.tutorial:
            acquireRandomTarget()                               // [IL L6675-6683]
        else:                                                   // tutorial: always attack hero slot 1
            myTargetScript = motherBrain.playerScripts[1]       // [IL L6685-6691]
            myTarget       = myTargetScript.myTransform         // [IL L6692-6696]
            meleeSlot      = myTargetScript.requestPosition(0, this)   // [IL L6697-6703]
            AIState        = 0                                  // [IL L6704-6706]
    elif spawnAnim.weight == 0:                                 // spawn anim not playing at all
        acquireRandomTarget()                                   // [IL L6709-6717]
return
```
If `spawnAnim` is null nothing happens in this state (some other code must leave state −1).

### 7.3 AIState 1 (no target) [IL L6720-7026]
1. If `position.x > edge` or `position.x < -edge` (enemy is outside the arena sideways):
   `movementTarget = ( Random.Range(-edge, edge), 0, Random.Range(floor, cieling) )` [IL L6725-6767].
2. If `Distance(position, movementTarget) > 0.07` [IL L6768-6775]:
   - face `movementTarget` [IL L6777-6878];
   - `moveVector = normalize(movementTarget - position)` [IL L6879-6891];
   - move and animate with the slow rule (§7.5, simple variant: always `CrossFade("run", 0.1)`, never
     backpedal) [IL L6892-7016].
3. Else: `CrossFade("idle", 0.1)` [IL L7019-7023].
4. **Every frame**: `acquireRandomTarget()` [IL L7024-7025]. Return.

Note: when `acquireRandomTarget` fails it sets `movementTarget = position` [IL L22252-22256], so the enemy
only actually walks in this state when step 1 fires (it is outside ±edge).

### 7.4 AIState 0 with a living target [IL L7028-7797]
Condition: `AIState == 0 and myTargetScript != null and myTargetScript.health > 0` [IL L7028-7043].

1. `actionTimer += deltaTime` [IL L7044-7049].
2. Face `myTarget.position` (§6.6) [IL L7050-7157].
3. `movementTarget = myTarget.position + myTargetScript.meleePositions[meleeSlot]` [IL L7158-7170].
4. Clamp into the arena, in this order: `if z > cieling: z = cieling`; `if x > edge: x = edge`;
   `if x < -edge: x = -edge`; `if z < floor: z = floor` [IL L7171-7228].
5. `ignoreMovement = false` [IL L7229-7231], then decide whether to stand still because the hero is coming
   to us:
   - **If the hero has an enemy target** (`myTargetScript.myTargetEnemyScript != null`) [IL L7232-7238]:
     `tempMovementTarget = myTargetScript.myTarget.position + myTargetScript.myTargetEnemyScript.meleePositions[myTargetScript.meleeSlot]`
     (the spot the hero wants to stand on) [IL L7239-7254].
     `if myTargetScript.AIType == 3 and myTargetScript.myTargetEnemyScript == this and Distance(myTargetScript.myTransform.position, tempMovementTarget) <= 0.25: ignoreMovement = true`
     [IL L7255-7280]. (Hero `AIType == 3` is a `PartyMember` value; its meaning is not in this scope.)
   - **Else** (hero has no enemy target) [IL L7283-7316]:
     `if Distance(myTarget.position, position) < Distance(myTarget.position, myTarget.position + this.meleePositions[this.meleeSlot]) and myTargetScript.run.weight == 1: ignoreMovement = true`.
     In words: the hero is closer to me than the length of my own `meleePositions[meleeSlot]` offset
     **and** the hero's run animation is at full weight (hero is running). Note it indexes **this enemy's**
     `meleePositions` with **this enemy's** `meleeSlot` (which is a slot index on the hero) [IL L7296-7301].
6. **Walk** if `Distance(position, movementTarget) > 0.07 and basicAction.weight != 1 and not ignoreMovement`
   [IL L7317-7335]:
   - `moveVector = normalize(movementTarget - position)` [IL L7337-7349];
   - move + animate with the full slow/backpedal rule (§7.5) [IL L7350-7754].
7. **Else (in position, or attacking, or ignoring movement)** [IL L7756-7785]:
   - `if actionTimer >= primaryActionCooldown and not myTargetScript.invincible: StartCoroutine(meleeAttack())`
     [IL L7756-7771];
   - `elif run.weight > 0: CrossFade("idle", 0.3)` [IL L7774-7785].
   Nothing here resets `actionTimer`; `meleeAttack` (L22261 / coroutine L31509) must do it (outside scope).
   Note there is **no range check** before attacking: the attack starts whenever the walk condition of
   step 6 is false.
8. Always: `if basicAction.normalizedTime >= 0.85: CrossFade("idle", 0.15)` [IL L7786-7796]. Return.

### 7.5 Movement + run animation rule (shared)
```
slow = 1
if debuffs[10] > 0:   slow = motherBrain.debuffMagnitudes[10]
elif debuffs[16] > 0: slow = motherBrain.debuffMagnitudes[16]

position += moveVector * moveSpeed * deltaTime * slow

// animation start (AIType 1 chase only):
if paralyzeLoop.weight > 0 or fearLoop.weight > 0: myAnimation.Play("run")      // hard cut out of CC anims
else:                                               myAnimation.CrossFade("run", 0.1)

// playback speed:
backpedal = canBackpeddle and ( (localScale.x ==  1 and moveVector.x > 0)     // facing left, moving right
                             or (localScale.x == -1 and moveVector.x < 0) )   // facing right, moving left
run.speed = (backpedal ? -1 : +1) * moveSpeed * runSpeedScale * slow
```
Cites (AIType 1 chase): debuff-10 variant [IL L7350-7494], debuff-16 variant [IL L7496-7640], no-slow
variant [IL L7642-7754]. In the no-slow variant the `slow` factor is simply absent.

Variants of this rule elsewhere:
- "No target" walk (AIState 1 of every AIType): always `CrossFade("run", 0.1)`, no backpedal test, positive
  speed [IL L6892-7016].
- AIType 3 and AIType 4 chase: backpedal test present, but always `CrossFade("run", 0.1)` (no
  paralyze/fear weight test) [IL L9100-9441], [IL L10951-11292].

### 7.6 Fallback re-target [IL L7799-7827]
Reached when 7.1–7.4 did not match:
```
if AIState == 0 and ( (myTargetScript != null and myTargetScript.health <= 0) or myTargetScript == null ):
    acquireRandomTarget()
return
```

---

## 8. AIType 3 — boss: summon goblin adds / bomb / stampede [IL L8087-10089]

UNVERIFIED identity: the prefab that uses AIType 3 is not named in the IL. The coroutine it starts is called
`summonGoblinAdds` and there is a `goblinBossDeath` method, so this is presumably the goblin boss.

`specialMoves` layout for this AIType:

| Index | Move | Trigger state | Cite |
|---|---|---|---|
| 0 | Summon goblin adds | `AIState = 2` | [IL L8355-8377] |
| 1 | Bomb throw (timer doubles as bomb-flight clock, see 8.1) | `AIState = 5` | [IL L8378-8446] |
| 2 | Charge / stampede (timer doubles as pass counter, see 8.8) | `AIState = 3` | [IL L8447-8469] |

### 8.1 Bomb-in-flight clock — runs every frame regardless of AIState [IL L8092-8305]
The `throwBomb` coroutine sets `specialMoves[1].timer = 102.6` when the bomb leaves the hand
[IL L27851-27857]. Values above 90 mean "a bomb is live":

```
t = specialMoves[1].timer
if t > 90: t -= deltaTime                                         // [IL L8092-8112]

if t > 101.7:                                                     // flying: 102.6 → 101.7 = 0.9 s  [IL L8113-8120]
    tempMovementTarget = normalize(bombVector - bombLaunchPoint)  // [IL L8121-8132]
    myEffects[5].myTransform.position += tempMovementTarget * bombFlightSpeed * deltaTime   // [IL L8133-8152]
elif t <= 99.3 and t > 90:                                        // fuse over → explode  [IL L8155-8171]
    motherBrain.cameraShaker.Play("shake")                        // [IL L8172-8177]
    bombVector = myEffects[5].myTransform.position                // [IL L8178-8185]
    myEffects[1].activate(bombVector, null)                       // [IL L8186-8193]
    myEffects[2].activate(bombVector, null)                       // [IL L8194-8201]
    mySounds[5].Play()                                            // [IL L8202-8206]
    for i in 0..3:                                                // [IL L8207-8289]
        p = motherBrain.playerScripts[i]
        if p != null and p.health > 0 and Distance(bombVector, p.myTransform.position) <= 1.25:
            dir = normalize(p.myTransform.position - bombVector)
            p.takeDamage( (int)(power * 1.5), dir * 4, this )     // [IL L8246-8278]
    specialMoves[1].timer = Random.Range(specialMoves[1].cooldownMin, specialMoves[1].cooldownMax)   // [IL L8290-8305]
// 99.3 < t <= 101.7: bomb lies on the ground (fuse) for 2.4 s, nothing happens
```

Bomb timeline (from `throwBomb`, [IL L27812-27912], outside scope but needed to read the numbers):
sound 8 → wait 0.3 s → `myEffects[5]` activated at `position + (localScale.x * -0.6, 0, 0)` → timer = 102.6,
`bombFlightSpeed = Distance(effect position, bombVector) / 0.9`, `bombLaunchPoint = effect position` →
wait 0.65 s → if `health > 0`: `AIState = 0`, `Play("idle")`.
So: 0.9 s flight, 2.4 s fuse, blast radius 1.25, damage `floor(power × 1.5)`, knock-back magnitude 4.

### 8.2 Special-move scheduling — only while `AIState == 0` [IL L8306-8469]
```
specialMoves[0].timer -= deltaTime                                 // [IL L8310-8321]
if specialMoves[1].timer < 90: specialMoves[1].timer -= deltaTime  // bomb cooldown; not while a bomb is live  [IL L8322-8342]
specialMoves[2].timer -= deltaTime                                 // [IL L8343-8354]

if specialMoves[0].timer <= 0 and basicAction.weight != 1 and AIState == 0:
    AIState = 2                                                    // summon  [IL L8355-8377]

if specialMoves[1].timer <= 0 and basicAction.weight != 1 and AIState == 0:     // [IL L8378-8397]
    randomValue = Random.Range(0, 4)                               // integer 0..3  [IL L8398-8402]
    p = motherBrain.playerScripts[randomValue]
    if p != null and p.health > 0 and p != myTargetScript:         // never bombs its current melee target  [IL L8403-8433]
        bombVector = p.myTransform.position                        // [IL L8434-8443]
        AIState = 5                                                // [IL L8444-8446]
    // if the random pick is invalid nothing happens; it is retried next frame

if specialMoves[2].timer <= 0 and basicAction.weight != 1 and AIState == 0:
    AIState = 3                                                    // charge  [IL L8447-8469]
```
The three `if`s are sequential, not `else if`; because each re-tests `AIState == 0`, the priority is
summon > bomb > charge. Special moves never start while the attack animation is at full weight.

### 8.3 AIState 1 (no target) [IL L8470-8776]
Identical to §7.3: pick a random in-arena `movementTarget` if `|x| > edge` [IL L8475-8517]; walk if farther
than 0.07 (simple variant of §7.5) [IL L8518-8766]; else `CrossFade("idle", 0.1)` [IL L8769-8773];
`acquireRandomTarget()` every frame [IL L8774-8775]. Return.

### 8.4 AIState 0 with a living target [IL L8778-9484]
Identical to §7.4 steps 1–8 (same constants 0.07, 0.25, 0.3, 0.85, 0.15) except the run animation is always
started with `CrossFade("run", 0.1)`:
`actionTimer += dt` [IL L8794-8799]; face target [IL L8800-8907]; `movementTarget` + clamp
[IL L8908-8978]; `ignoreMovement` logic [IL L8979-9066]; walk test [IL L9067-9085]; movement
[IL L9087-9441]; attack test `actionTimer >= primaryActionCooldown and not myTargetScript.invincible →
StartCoroutine(meleeAttack())` [IL L9443-9458]; else `run.weight > 0 → CrossFade("idle", 0.3)`
[IL L9461-9472]; `basicAction.normalizedTime >= 0.85 → CrossFade("idle", 0.15)` [IL L9473-9483]. Return.

### 8.5 Fallback re-target [IL L9486-9514]
```
if AIState == 0 and ( (myTargetScript != null and myTargetScript.health <= 0) or myTargetScript == null ):
    acquireRandomTarget(); return
```
Otherwise fall through to the state handlers below.

### 8.6 AIState 2 — summon [IL L9516-9534]
`Play("summon")`; `AIState = -100`; `StartCoroutine(summonGoblinAdds())`. Return.
(Coroutine body at L27056–27296, outside scope.)

### 8.7 AIState 3 — charge wind-up [IL L9536-9554]
`Play("charge")`; `AIState = -100`; `StartCoroutine(enterChargeMode())`. Return.

`enterChargeMode` ([IL L27658-27731], outside scope, summarised for context): `mySounds[7].Play()`; wait
**0.95 s**; `specialMoves[2].timer = 0`; `run.speed = 2.8`; `Play("run")`; `AIState = 4`;
`invincible = true`; `gameObject.layer = 11`; if it had a target: `myTargetScript.purgePosition(meleeSlot)`,
`myTargetScript = null`, `myTarget = null`; `clearAllAttackers()`.

### 8.8 AIState 5 — bomb throw [IL L9556-9676]
`Play("throw")` [IL L9561-9565]; `AIState = -100` [IL L9566-9568]; face `bombVector` (§6.6)
[IL L9569-9670]; `StartCoroutine(throwBomb())` [IL L9671-9675]. Return.

### 8.9 AIState 4 — stampede [IL L9678-10089]
Each frame:
1. Run horizontally in the facing direction at **5 units/s**:
   `if localScale.x == 1: position.x -= deltaTime * 5` [IL L9683-9727];
   `elif localScale.x == -1: position.x += deltaTime * 5` [IL L9730-9774].
2. Turn around when well off-screen:
   `if (position.x < -edge - 1.3 and localScale.x == 1) or (position.x > edge + 1.3 and localScale.x == -1)`
   [IL L9775-9821]:
   - `specialMoves[2].timer += 1` (pass counter) [IL L9822-9834];
   - `localScale.x *= -1`; `updateHealthBar(1)` [IL L9835-9870];
   - `position.z = Random.Range(floor, cieling)` (new random lane) [IL L9871-9901].
3. End of stampede: `if position.x > -edge + 0.5 and position.x < edge - 0.5 and specialMoves[2].timer >= 4`
   [IL L9902-9937]:
   - `acquireRandomTarget()` [IL L9938-9939]; `AIState = 0` (overrides whatever `acquireRandomTarget` set)
     [IL L9940-9942]; `Play("idle")` [IL L9943-9947]; `invincible = false` [IL L9948-9950];
     `gameObject.layer = 10` [IL L9951-9954];
   - `specialMoves[2].timer = Random.Range(specialMoves[2].cooldownMin, specialMoves[2].cooldownMax)`
     [IL L9955-9970].
   So the boss leaves the screen and turns around 4 times, then stops as soon as it is 0.5 inside the edge
   on the pass after the 4th turn-around.
4. Trample damage tick (still executed on the frame the stampede ends): `stampedeCounter += deltaTime`;
   `if stampedeCounter >= 0.16` [IL L9971-9981]: `stampedeCounter = 0` [IL L9982-9985]; for `i` in 0..3
   [IL L9986-10088]:
   - `p = playerScripts[i]`; require `p != null`, `p.health > 0`,
     `Distance(position, p.myTransform.position) <= 1.2` [IL L9991-10025];
   - `dir = normalize(p.myTransform.position - position)` [IL L10026-10041];
   - `p.takeDamage( (int)(power * 0.2), dir * 5, this )` [IL L10042-10059];
   - `n = Random.Range(0, totalMeleeSounds)`; `mySounds[n].pitch = Random.Range(0.9, 1.1)`;
     `mySounds[n].Play()` [IL L10060-10077].

Layer numbers 10 (normal) and 11 (while stampeding) are Unity physics layers; their names are not in the IL.

AIType 3 has no handler for AIState −1 or −100 in this block: in those states only §8.1 runs.

---

## 9. AIType 2 — stationary ranged enemy [IL L7829-8085]

### 9.1 AIState −1 (spawning) [IL L7834-7870]
```
if spawningStyle == 3 and spawnAnim != null:
    if spawnAnim.normalizedTime >= 1: acquireRandomTarget()
    elif spawnAnim.weight == 0:        acquireRandomTarget()
return
```
For any other `spawningStyle` nothing happens here.

### 9.2 AIState 1 (no target) [IL L7872-7884]
`CrossFade("idle", 0.1)`; `acquireRandomTarget()`. Return. (No walking.)

### 9.3 AIState 0 with a living target [IL L7886-8055]
Condition: `AIState == 0 and myTargetScript != null and myTargetScript.health > 0`.
1. `actionTimer += deltaTime` [IL L7902-7907].
2. `if chaotic and actionTimer >= primaryActionCooldown: acquireRandomTarget()` [IL L7908-7919] — picks a
   new random target just before firing.
3. `if myTarget != null` [IL L7920-7924]:
   - face `myTarget.position` (§6.6) [IL L7925-8032];
   - `if actionTimer >= primaryActionCooldown: StartCoroutine(rangedAttack())` [IL L8033-8043].
4. `if basicAction.normalizedTime >= 0.95: CrossFade("idle", 0.1)` [IL L8044-8054]. Return.

No distance test and no movement code exist for AIType 2: it shoots from wherever it stands, at any range.

### 9.4 Fallback re-target [IL L8057-8085]
Same as §7.6.

---

## 10. AIType 4 — boss: pounce / summon spider adds / web shot [IL L10091-11952]

UNVERIFIED identity: presumably the spider boss (coroutines `summonSpiderAdds`, `webShot`; method
`spiderBossDeath` exists).

`specialMoves` layout for this AIType:

| Index | Move | Trigger state | Cite |
|---|---|---|---|
| 0 | Pounce (timer doubles as phase timer for wind-up / flight / recovery) | `AIState = 5` | [IL L10136-10189] |
| 1 | Summon spider adds | `AIState = 2` | [IL L10191-10214] |
| 2 | Web shot | `AIState = 6` | [IL L10216-10320] |

### 10.1 Special-move scheduling — only while `AIState == 0` [IL L10096-10320]
```
specialMoves[0].timer -= deltaTime; specialMoves[1].timer -= deltaTime; specialMoves[2].timer -= deltaTime   // [IL L10100-10135]

if specialMoves[0].timer <= 0 and basicAction.weight != 1 and AIState == 0:         // POUNCE  [IL L10136-10155]
    acquireRandomTarget()                                                           // [IL L10156-10157]
    if myTargetScript != null:                                                      // [IL L10158-10162]
        bombLaunchPoint = myTargetScript.myTransform.position   // landing spot = where the hero is now  [IL L10163-10168]
        invincible = true                                                           // [IL L10169-10171]
        tauntable  = false                                                          // [IL L10172-10174]
        AIState    = 5                                                              // [IL L10175-10177]
        myAnimation.Play("pounce")                                                  // [IL L10178-10182]
        specialMoves[0].timer = 0.166                                               // wind-up  [IL L10183-10188]
elif specialMoves[1].timer <= 0 and basicAction.weight != 1 and AIState == 0:       // SUMMON  [IL L10191-10213]
    AIState = 2
elif specialMoves[2].timer <= 0 and basicAction.weight != 1 and AIState == 0:       // WEB  [IL L10216-10235]
    randomValue = Random.Range(0, 4)                                                // integer 0..3  [IL L10236-10240]
    p = motherBrain.playerScripts[randomValue]
    if  p != null and p.health > 0 and p != myTargetScript                          // [IL L10241-10271]
    and not p.commandPending and not p.invincible                                   // [IL L10272-10289]
    and p.AIState != 3 and p.AIState != 5:                                          // hero states; meaning outside scope  [IL L10290-10309]
        webTarget = p                                                               // [IL L10310-10317]
        AIState   = 6                                                               // [IL L10318-10320]
```
Unlike AIType 3 these are a true `if / elif / elif` chain (explicit jumps at [IL L10189], [IL L10214]).
Priority: pounce > summon > web. The pounce re-rolls the boss's target with `acquireRandomTarget()` first;
if that finds nobody, `AIState` becomes 1.

### 10.2 AIState 1 (no target) [IL L10321-10627]
Identical to §7.3: random in-arena point if `|x| > edge` [IL L10326-10368]; walk if farther than 0.07
[IL L10369-10618]; else `CrossFade("idle", 0.1)` [IL L10620-10624]; `acquireRandomTarget()` every frame
[IL L10625-10626]. Return.

### 10.3 AIState 0 with a living target [IL L10629-11335]
Identical to §8.4 (i.e. §7.4 with `CrossFade("run", 0.1)` always):
`actionTimer += dt` [IL L10645-10650]; face target [IL L10651-10758]; `movementTarget = myTarget.position +
myTargetScript.meleePositions[meleeSlot]` + clamp [IL L10759-10829]; `ignoreMovement` logic (0.25 test and
hero-running test) [IL L10830-10917]; walk if `Distance > 0.07 and basicAction.weight != 1 and not
ignoreMovement` [IL L10918-10936]; movement with debuff-10 / debuff-16 / plain variants and backpedal
[IL L10938-11292]; else `actionTimer >= primaryActionCooldown and not myTargetScript.invincible →
StartCoroutine(meleeAttack())` [IL L11294-11309], or `run.weight > 0 → CrossFade("idle", 0.3)`
[IL L11312-11323]; then `basicAction.normalizedTime >= 0.85 → CrossFade("idle", 0.15)`
[IL L11324-11334]. Return.

### 10.4 Fallback re-target [IL L11337-11365]
Same as §8.5.

### 10.5 AIState 2 — summon [IL L11367-11385]
`Play("yell")`; `AIState = -100`; `StartCoroutine(summonSpiderAdds())`. Return. (Coroutine L27298–27586,
outside scope.)

### 10.6 AIState 5 — pounce wind-up [IL L11755-11817]
```
specialMoves[0].timer -= deltaTime                                        // [IL L11760-11771]
if specialMoves[0].timer <= 0:                                            // after the 0.166 s wind-up
    AIState = 3                                                           // [IL L11781-11783]
    specialMoves[0].timer = 0.633                                         // flight time  [IL L11784-11789]
    bombFlightSpeed = Distance(position, bombLaunchPoint) / specialMoves[0].timer   // = distance / 0.633  [IL L11790-11803]
    bombVector = normalize(bombLaunchPoint - position)                    // [IL L11804-11814]
    clearAllMeleeAttackers()                                              // [IL L11815-11816]
```

### 10.7 AIState 3 — pounce in flight [IL L11387-11699]
```
specialMoves[0].timer -= deltaTime                                        // [IL L11392-11403]
if specialMoves[0].timer > 0:                                             // [IL L11404-11412]
    face myTarget.position (§6.6)                                         // [IL L11413-11520]
    position += bombVector * bombFlightSpeed * deltaTime                  // [IL L11521-11534]
else:                                                                     // LANDING
    // "if any living hero is closer than 1.2, hit every living hero within 1.3"
    for i in 0..3:                                                        // outer loop  [IL L11537-11663]
        if playerScripts[i].health > 0 and Distance(playerScripts[i].myTransform.position, position) < 1.2:   // [IL L11542-11567]
            for i in 0..3:                                                // inner loop re-uses the SAME field i  [IL L11568-11652]
                p = playerScripts[i]
                if p != null and p.health > 0 and Distance(position, p.myTransform.position) <= 1.3:           // [IL L11573-11607]
                    dir = normalize(p.myTransform.position - position)    // [IL L11608-11623]
                    p.takeDamage( (int)(power * 1.5), dir * 8, this )     // [IL L11624-11641]
            // inner loop leaves i == 4, so the outer loop ends too → the damage pass happens at most once
    motherBrain.cameraShaker.Play("shake")                                // [IL L11664-11669]
    myEffects[5].activate(position, null)                                 // [IL L11670-11678]
    mySounds[6].Play()                                                    // [IL L11679-11683]
    AIState = 4; invincible = false; tauntable = true                     // [IL L11684-11692]
    specialMoves[0].timer = 0.1667                                        // recovery  [IL L11693-11698]
```
Notes read directly from the code: the outer loop does **not** null-check `playerScripts[i]` before reading
`.health` [IL L11542-11552] (the inner one does [IL L11573-11581]); the outer test is strict `< 1.2`
(`bge` skips) while the inner is `<= 1.3` (`bgt` skips).

### 10.8 AIState 4 — pounce recovery [IL L11701-11753]
```
specialMoves[0].timer -= deltaTime                                        // [IL L11706-11717]
if specialMoves[0].timer <= 0:                                            // after 0.1667 s
    specialMoves[0].timer = Random.Range(specialMoves[0].cooldownMin, specialMoves[0].cooldownMax)   // [IL L11727-11742]
    acquireRandomTarget()                                                 // [IL L11743-11744]
    if myTarget != null: AIState = 0                                      // [IL L11745-11752]
```
Pounce timeline: 0.166 s wind-up (invincible, untauntable) → 0.633 s flight straight to where the target
stood when the pounce was chosen → landing AoE (`floor(power × 1.5)` damage, knock-back magnitude 8) →
0.1667 s recovery → new random target.

### 10.9 AIState 6 — web shot [IL L11819-11952]
Face `webTarget.myTransform.position` (§6.6) [IL L11824-11933]; `Play("yell")` [IL L11934-11938];
`mySounds[9].Play()` [IL L11939-11943]; `AIState = -100` [IL L11944-11946];
`StartCoroutine(webShot())` [IL L11947-11951]. Return [IL L11952]. (Coroutine L26916–27054, outside scope.)

AIType 4 has no handler for AIState −1 or −100: the AI does nothing in those states.

---

## 11. `acquireRandomTarget()` (L22106–22258) — summary for context only

Outside this document's scope, but `AI` calls it constantly and it is what sets `AIState` 0/1. Read it in the
document that covers L22106; the outline is:

1. If there is a current target and `isMelee`: `myTargetScript.purgePosition(meleeSlot)` [IL L22114-22127].
   Clear `myTarget`, `myTargetScript` [IL L22128-22133].
2. `r = Random.Range(0, 4)` — **one** random hero slot per call, no retry loop [IL L22134-22137].
3. Melee (`isMelee`): accept if `playerScripts[r] != null`, `attackers < 4`, `health > 0`; then set target,
   `meleeSlot = requestPosition(0, this)`, `AIState = 0`, and `Play("idle")` if the attack animation is at
   full weight [IL L22138-22202].
4. Not melee: accept if non-null and `health > 0`; set target, `AIState = 0`, `Play("idle")`
   [IL L22205-22243].
5. If `myTarget == null` afterwards: `AIState = 1`, `movementTarget = position` [IL L22244-22256].

Because only one random slot is tried per call, enemies in state 1 call it every frame until the dice land
on a valid hero.

---

## 12. Uncertain / not determined

- **Which enemies use which `AIType`, and all per-enemy numbers** (`moveSpeed`, `primaryActionCooldown`,
  `power`, `specialMoves[*].cooldownMin/Max` and initial `timer`, `likeABoss`, `chaotic`, `spawningStyle`,
  `canBackpeddle`, …) live in Unity prefab data, not in the IL. Only the ctor fallbacks in §2.2 are known.
  `bh/data/*.json` has no `AIType` field. The "goblin boss" / "spider boss" labels for AIType 3 / 4 are
  UNVERIFIED inferences from coroutine names.
- **Debuff id names** (1, 3, 5, 10, 11, 13, 16) are not in the IL; §5 gives observed behaviour only.
  UNVERIFIED guesses from animation names: 1 = paralyse/stun, 3 = knock-down, 5 = fear, 11 = freeze/time-stop,
  13 = "vanish". `debuffMagnitudes[10]` / `[16]` values not determined here.
- **`AIState == 100` vs `-100`.** The crowd-control branches test for **+100** (`ldc.i4.s 0x64`,
  [IL L6095], [IL L6307], [IL L6359], [IL L6386], [IL L6431]) and reset it to 0, but every write of the
  "busy" state in this range (AIType 3 / 4) stores **−100** (`0xffffff9c`). A whole-file search for
  writes to `EnemyScript::AIState` finds exactly **one** write of +100, at [IL L14236-14237], inside the
  later part of `AI` (part 2 document), and ten writes of −100. So +100 and −100 are two different states:
  the crowd-control reset `100 → 0` applies only to whatever enemy type sets +100 at L14236, and does
  **not** cancel the −100 busy state. (AIType 3 / 4 are bosses in practice — UNVERIFIED — and would skip
  the crowd-control branches anyway if `likeABoss` is set.) See part 2 for the meaning of state 100.
- `MotherBrain.edge/floor/cieling`: ctor defaults (3.42 / −2.8 / 4.3) are cited, but MotherBrain re-assigns
  them at L108408–108553 (outside scope); effective per-level values not determined here.
- Meaning of hero-side values `PartyMember.AIType == 3` (§7.4) and `PartyMember.AIState == 3 / 5`,
  `commandPending` (§10.1): not in this scope.
- Unity layer numbers 10 and 11 (§8.9): names not in the IL.
- `remoteUpdate`'s `position.x == 10` early-out: purpose inferred only.
- Who resets `actionTimer` after an attack: inside `meleeAttack` / `rangedAttack` coroutines (outside scope).
- How AIType 3 / 4 leave AIState −1 after spawning: not in their `AI` blocks (see `spawn`, L21096, and
  `completeLichSpawn`).

### Contradictions with older notes
- `work/battleheart-encounter-parity.md` line 62 describes `debuffs[0x0b]` and `debuffs[0x0d]` loosely as
  "fear/paralyze/stun visuals & gating". Per the IL: index 11 is a full animation freeze, index 13 is the
  "vanish" wander; **fear is index 5, paralysed is index 1, knock-down is index 3** (§5). Not a hard
  contradiction, but the older note is imprecise.
- No other older note covering this range was found to conflict.

---

## 13. Cross-references

| Called from this code | Location | Purpose |
|---|---|---|
| `EnemyScript.muteSoundEffects()` | L23135 | called at end of `initialize` [IL L5654] |
| `EnemyScript.shaderAnimation()` | L17706 | `remoteUpdate` [IL L5678] |
| `EnemyScript.healthAnimation()` | L19940 | `remoteUpdate` [IL L5680] |
| `EnemyScript.animateSliding()` | L20124 | `remoteUpdate` [IL L5682] |
| `EnemyScript.handleDebuffs()` | L22458 | `remoteUpdate`, after `AI` [IL L5692] |
| `EnemyScript.residualEffects()` | L16818 | `remoteUpdate` if `oozeBoss` [IL L5698] |
| `EnemyScript.updateHealthBar(int)` | L19530 | called with 1 on every facing flip [IL L6212] |
| `EnemyScript.acquireRandomTarget()` | L22106 | §11 |
| `EnemyScript.meleeAttack()` → `$meleeAttack$1408` | L22261 / L31509 | basic melee swing [IL L7767] |
| `EnemyScript.rangedAttack()` → `$rangedAttack$1422` | L22300 / L32262 | basic ranged shot [IL L8039] |
| `EnemyScript.summonGoblinAdds()` → `$summonGoblinAdds$1340` | L17631 / L27056 | AIType 3 state 2 [IL L9529] |
| `EnemyScript.enterChargeMode()` → `$enterChargeMode$1348` | L17657 / L27588 | AIType 3 state 3 [IL L9549] |
| `EnemyScript.throwBomb()` → `$throwBomb$1351` | L17670 / L27739 | AIType 3 state 5 [IL L9671] |
| `EnemyScript.summonSpiderAdds()` → `$summonSpiderAdds$1344` | L17644 / L27298 | AIType 4 state 2 [IL L11380] |
| `EnemyScript.webShot()` → `$webShot$1337` | L17528 / L26916 | AIType 4 state 6 [IL L11947] |
| `EnemyScript.clearAllMeleeAttackers()` | L22981 | AIType 4 pounce take-off [IL L11815] |
| `EnemyScript.clearAllAttackers()` | L22837 | called by `enterChargeMode` [IL L27724] |
| `PartyMember.requestPosition(int, EnemyScript)` | (PartyMember) | reserve melee slot [IL L6697-6703] |
| `PartyMember.takeDamage(int, Vector3, EnemyScript)` | (PartyMember) | bomb / stampede / pounce damage |
| `EffectScript.activate(Vector3, Transform)` | (EffectScript) | show an effect |

| Calls into this code | Location |
|---|---|
| `EnemyScript.remoteUpdate` → `AI()` | [IL L5690] |
| `MotherBrain.tutorialDriver` sets `AIState = -2` | [IL L66527] |
| `EnemyScript.spawn` sets `AIState = -1` | L21392, L21528, L21771, L21920, L22024 |

**Continuation:** `AI` continues at **L11954** (`IL_4259`, test `AIType == 5`) through L16684 — see the
part 2 document.

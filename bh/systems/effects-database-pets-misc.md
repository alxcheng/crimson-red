# Effects (EffectScript), Database (save / load / merchant), Pets, and small utility classes

**Scope.** Three parts, all from `il/Assembly-UnityScript.il`:

| Part | Class | IL lines |
|---|---|---|
| A | `EffectScript` (+ coroutines `$onDramaticImpact$1269`, `$onApolloImpact$1272`) | 2676–5280 |
| B | `Database` methods `.ctor`, `Awake`, `save`, `load`, `OnApplicationPause`, `OnApplicationQuit`, `populateMerchant` | 854–2554 |
| C | `PetScript` 105812–107128, `HandScript` 32637–32871, `SpecialMove` 5282–5302, `Blinker` 33–198, `Congrats` 200–604, `DynamicTexture` 2556–2674, `SceneTransfer` 107130–107178, `SplashScreen` 107180–107418, `TextPrint` 107420–107584, `TitleAnimation` 107586–107841, `TitleMusic` 107843–108005, `dynamicbackgroundhandler` 108007–108601, `titleinit` 108603–108666 | see left |

Conventions used in this document:

- `[IL Lnnnn]` = line number in the `.il` file. Every fact carries one.
- `characterClass` is **1-based** against `bh/data/classes.json` (`characterClass 1` = classes.json id 0 = Cleric … `4` = Wizard, `9` = Ranger). This is read from `bh/data/party.json` (Lucille `characterClass 1` carries item 2 "Cleric's Rod"; Bromswell `characterClass 4` carries item 3 "Oakwood Staff") — it is not stated in the IL of this scope.
- `passives[n]` is an `int32[]` on `PartyMember`; the code in this scope compares its entries to `1` and `-1` only. `UNVERIFIED:` which talent each value stands for is inferred here by matching the code's effect to the talent descriptions in `bh/data/classes.json` (the talent-picking code is in MenuBrain, out of scope). The matches found in this scope are all consistent with: `passives[0]`: `1` → power index 3, `-1` → power index 4; `passives[1]`: `1` → index 7, `-1` → index 8; `passives[2]`: non-zero → index 9; `passives[3]`: `1` → index 10, `-1` → index 11. Each use below is marked UNVERIFIED individually.

---

# PART A — `EffectScript` (IL 2676–5280)

## A.1 Summary

`EffectScript` is the single component that sits on every pooled visual-effect object in a battle:
hit sparks, spell bursts, auras, **and every projectile** (arrows, fireballs, thrown knives, heal
bolts, enemy missiles). Each party member and each enemy owns an array `myEffects[]` of these
objects, instantiated once from prefabs and re-used. An effect is *started* by calling
`activate(position, parentTransform)` and *stops itself* (disables its own `Update` and moves to
`z = 50`; UNVERIFIED: this is assumed to be out of the camera's view) when it expires or when a
projectile lands.

Two behaviours exist, chosen by the bool `projectile`:

- **Non-projectile (attached effect):** every frame it snaps to its parent's position (if it has a
  parent), optionally mirrors the parent's facing, and after `hideTime` seconds hides itself and
  optionally starts a follow-up effect.
- **Projectile:** after an optional launch delay `moveTime` it flies in a straight line toward its
  (moving) target at `moveSpeed` units/second — it is homing and cannot miss. When it gets within
  `0.04 × moveSpeed × Time.timeScale` units of the target it lands and calls exactly one of
  `healPlayer()`, `damageEnemy()` or `damagePlayer()`.

All per-effect tuning (speed, damage multiplier, debuff id, lifetime, sounds, follow-up effect ids,
and the flags `aimedShot`, `apollo`, `flameArrow`, `canCrit`, …) is **public serialized data set on
the prefab in the Unity editor**; it is not assigned anywhere in the IL (see A.9). The code only
tells us what each field *does*. `damageEnemy` is the important method: it applies the owner's
`power × projectileDamageMod`, crits, debuffs, the Ranger's Mortal Shots / Misdirection, the
Wizard's fireball splash, the Ranger's Incendiary Arrow ground fire and the Apollo Strike slow-motion
knockdown.

## A.2 Fields

All fields are declared at [IL L2679-2727]. Defaults come from `.ctor` [IL L2730-2781]; a field
not listed in the ctor has the CLR default (0 / false / null) unless the prefab overrides it.
**Every public field can be overridden per prefab by Unity serialization — the ctor value is only
the default.**

| Field | Type | Default (ctor) | Meaning (as used by the code) |
|---|---|---|---|
| `myTransform` | Transform | — | Cached own transform, set in `Awake` [IL L2790-2793]. |
| `myAnimation` | Animation | — | Cached own legacy `Animation` component, set in `Awake` [IL L2794-2797]. Clips used: `"effect"` and `"loop"` [IL L2842, L2853]. |
| `myRenderer` | Renderer | — | Renderer of child `"geometry"`; only fetched if a child named `"opacity"` exists [IL L2798-2819]. |
| `myParent` | Transform | null | What the effect follows (non-projectile) or flies at (projectile). Set by `activate` arg 2, null if the arg is null [IL L3430-3441]. |
| `myParentScript` | EnemyScript | — | `EnemyScript` of `myParent`, fetched in `activate` only when `dieWithParent` and a parent exist [IL L3442-3457]. |
| `animSpeed` | float | `1.0` [IL L2739-2740] | Playback speed applied to clips `"effect"` and (if `hasLoop`) `"loop"` in `Awake` [IL L2836-2857]. |
| `timer` | float | 0 | Seconds since `activate`; `+= Time.deltaTime` every `Update` [IL L2902-2907]; reset to 0 by `activate` [IL L3407-3410]. |
| `hideTime` | float | `1.0` [IL L2742-2743] | Lifetime in seconds. When `timer >= hideTime` the effect hides and disables itself [IL L3212-3267]. |
| `matchOwnerFacing` | bool | false | Mirror the effect's `localScale.x` to the owner's facing (see `activate` step 5 and `Update` step 8). |
| `matchParentFacing` | bool | false | Non-projectile only: every frame copy `myParent.localScale.x` into own `localScale.x` [IL L2932-2979]. |
| `dieWithParent` | bool | false | Force-expire the effect as soon as the parent enemy is dead or hidden [IL L3187-3211]. |
| `hasAnimation` | bool | `true` [IL L2745-2746] | The object has an `Animation` with clip `"effect"`; `activate` restarts it [IL L3414-3425]. |
| `hasLoop` | bool | false | The object also has a `"loop"` clip that is started once `timer >= loopTimer` [IL L3062-3086]. |
| `useScaleMod` | bool | false | On `activate`, scale the effect by the parent enemy's `EnemyScript.conflagScaleFactor` (uniform x,y,z) — only when a parent exists and the effect is player-owned (`myBoss` set) [IL L3590-3623]. |
| `projectile` | bool | false | Selects projectile behaviour in `Update` [IL L2913-2915, L2987-2989]. |
| `impactForce` | float | `3.0` [IL L2748-2749] | Magnitude of the knock-back vector passed to `takeDamage` [IL L3883-3889, L4560-4566]. |
| `projectileDamageMod` | float | `1.0` [IL L2751-2752] | Damage multiplier on the owner's power (and on `healAmount` for heal bolts). See A.6–A.8. Overwritten in code for two talents, see A.9. |
| `canCrit` | bool | false | Allows the 2× crit roll in `damageEnemy` / `onApolloImpact` [IL L3871-3873, L5171-5174]. |
| `applyDebuff` | int | `-1` [IL L2754-2755] | Index into the victim's `debuffs[]` (enemy victim) or `buffs[]` (player victim) to start on hit; `-1` = none [IL L3904-3907, L4567-4570]. |
| `debuffColor` | Color | `(0.25, 0.25, 0.25)` [IL L2757-2761] | Copied to `EnemyScript.debuffColor` when a debuff is applied [IL L3934-3938]. |
| `impactSound` | int | `-1` [IL L2763-2764] | Index into the owner's `mySounds[]` played on impact; `< 0` = silent [IL L4341-4344, L4585-4588, L4759-4761]. |
| `impactLowPitch` | float | `0.9` [IL L2766-2767] | Lower bound of random pitch for the impact sound [IL L4365-4370]. |
| `impactHighPitch` | float | `1.1` [IL L2769-2770] | Upper bound of random pitch for the impact sound [IL L4365-4370]. |
| `followupEffect` | int | `-1` [IL L2772-2773] | Index into the owner's `myEffects[]` of an effect to start on expiry / on impact. |
| `followupEffect2` | int | `-1` [IL L2775-2776] | Second follow-up effect index (impact only); `-1` = none. |
| `moveSpeed` | float | 0 | Projectile speed, world units per second [IL L3016-3022]. |
| `moveTime` | float | 0 | Projectile launch delay: the projectile does not move (and cannot land) while `timer < moveTime` [IL L2991-2995]. |
| `loopTimer` | float | 0 | Time at which the `"loop"` clip is started; negative disables it [IL L3062-3086]. |
| `lookAt` | Transform | null | If assigned (a child to rotate), the effect is rotated on screen to point from itself to `myParent` using the scene object `"AimingHelper"` [IL L2820-2835, L3087-3186]. |
| `cameraCamera` | Camera | — | `Camera.main`, only cached when `lookAt` is assigned [IL L2825-2827]. |
| `aimAssist` | Transform | — | Transform of `GameObject.Find("AimingHelper")`, only cached when `lookAt` is assigned [IL L2828-2835]. |
| `myBoss` | PartyMember | null | Owning party member (player-side effect). Set by `PartyMember.createMyEffects` [IL L86712, L86740]. |
| `myEnemyBoss` | EnemyScript | null | Owning enemy (enemy-side effect). Set by `EnemyScript.initialize` [IL L5639]. |
| `opacityControl` | Transform | — | Child named `"opacity"`; its animated `localScale.x` drives the material alpha [IL L2798-2803, L3268-3305]. |
| `healProjectile` | bool | false | Projectile lands with `healPlayer()` instead of a damage call [IL L3038-3044]. |
| `healAmount` | float | 0 | Base heal of a heal projectile [IL L4749-4757]. Written by `PartyMember.performSpecial` [IL L98718, L98737, L98748] (see A.9). |
| `belongsToPet` | bool | false | With `matchOwnerFacing`: copy facing from the owner's pet instead of the owner [IL L3458-3508]. |
| `usesMeleeSoundCount` | bool | false | Impact sound is picked at random from `impactSound … impactSound + myBoss.totalMeleeSounds − 1` [IL L4346-4376]. |
| `dramaticImpact` | bool | false | On impact run the slow-motion coroutine `onDramaticImpact` [IL L4497-4505]. |
| `aimedShot` | bool | false | Distance-scaled damage (Ranger "Aimed Shot", classes.json id 8 power 0) [IL L3807-3830]. |
| `canMisdirect` | bool | false | Allows the Misdirection talent to trigger [IL L4012-4026]. |
| `canMortalStrike` | bool | false | Allows the Mortal Shots talent to trigger [IL L3989-4011]. |
| `apollo` | bool | false | Apollo Strike projectile: damage is deferred to the `onApolloImpact` coroutine [IL L3853-3855, L4481-4495]. |
| `flameArrow` | bool | false | Incendiary Arrow projectile: creates a ground-fire patch on impact [IL L4173-4340]. |
| `flamePatch` | bool (private) | `true` [IL L2777-2779] | Toggle choosing which of the owner's two flame-patch slots the next Incendiary Arrow fills [IL L4189-4191, L4206-4208, L4271-4273]. |
| `tempVector` | Vector3 (private) | — | Scratch: flight direction / knock-back direction. |
| `tempEnemyScript` | EnemyScript (private) | — | Scratch: victim enemy. |
| `tempPlayerScript` | PartyMember (private) | — | Scratch: victim / heal target player. |
| `i` | int (private) | — | Loop counter for the splash loop. |

## A.3 `Awake()` [IL L2784-2859]

1. Cache `myTransform = transform`, `myAnimation = animation` [IL L2790-2797].
2. `opacityControl = myTransform.Find("opacity")`. If it is not null, `myRenderer = myTransform.Find("geometry").GetComponent(Renderer)` [IL L2798-2819].
3. If `lookAt` is assigned: `cameraCamera = Camera.main`; `aimAssist = GameObject.Find("AimingHelper").GetComponent(Transform)` [IL L2820-2835].
4. If `hasAnimation`: `myAnimation["effect"].speed = animSpeed`; and if `hasLoop`: `myAnimation["loop"].speed = animSpeed` [IL L2836-2857].

## A.4 `activate(Vector3 where, Transform newParent)` [IL L3372-3757]

Starts (or restarts) the effect. Called from 170 sites outside the class (text search of the IL: PartyMember, EnemyScript, PetScript) and from EffectScript itself for follow-up effects.

1. `timer = 0`; `this.enabled = true` (re-enables `Update`) [IL L3407-3413].
2. If `hasAnimation`: `myAnimation.Stop(); myAnimation.Play("effect")` [IL L3414-3425].
3. `myTransform.position = where` [IL L3426-3429].
4. `myParent = newParent` if non-null, else `myParent = null` [IL L3430-3441].
5. If `dieWithParent` and `myParent` exists: `myParentScript = myParent.GetComponent("EnemyScript")` [IL L3442-3457].
6. Facing (`matchOwnerFacing`):
   - if `matchOwnerFacing && belongsToPet`: if `myBoss` and `myBoss.petScript` both exist, `localScale.x = myBoss.petScript.myTransform.localScale.x` [IL L3458-3509]. (No fallback if the pet is missing.)
   - else if `matchOwnerFacing`: if `myBoss` exists `localScale.x = myBoss.myTransform.localScale.x` [IL L3511-3551]; else if `myEnemyBoss` exists `localScale.x = −myEnemyBoss.myTransform.localScale.x` (note the negation for enemies) [IL L3553-3589].
7. If `useScaleMod && myParent && myBoss`: `tempEnemyScript = myParent.GetComponent("EnemyScript")`; `localScale = (f, f, f)` where `f = tempEnemyScript.conflagScaleFactor` [IL L3590-3623].
8. If `myRenderer` exists: set `myRenderer.material.color.a = 1.0` [IL L3624-3655].
9. If `lookAt` assigned: aim once (same maths as `Update` step 5) [IL L3656-3755].

## A.5 `Update()` [IL L2862-3369]

Runs every frame while the component is enabled.

1. `timer += Time.deltaTime` [IL L2902-2907].
2. **Attached effect** — if `myParent` exists and `!projectile` [IL L2908-2915]:
   - if own position ≠ parent position: `position = myParent.position` [IL L2917-2931];
   - if `matchParentFacing` and own `localScale.x` ≠ parent `localScale.x`: copy the parent's `localScale.x` [IL L2932-2979].
3. **Projectile** — else if `myParent` exists and `projectile` and `timer >= moveTime` [IL L2982-2995]:
   - `tempVector = (myParent.position − myTransform.position).normalized` [IL L2997-3008];
   - `position += tempVector × moveSpeed × Time.deltaTime` [IL L3009-3022];
   - **hit test:** if `Vector3.Distance(position, myParent.position) < 0.04 × moveSpeed × Time.timeScale` [IL L3023-3036] then exactly one of:
     - `healProjectile` → `healPlayer()` [IL L3038-3044];
     - else `myBoss` set → `damageEnemy()` [IL L3046-3053];
     - else `myEnemyBoss` set → `damagePlayer()` [IL L3055-3061].
   - The target is re-read every frame, so the projectile homes; there is no miss, no collision with anything else, and no maximum range. The projectile keeps flying at a target that has died (the damage methods check `health > 0` themselves).
4. **Loop clip:** if `timer >= loopTimer && hasLoop && hasAnimation && loopTimer >= 0`: `myAnimation.Play("loop")` (called every frame once the condition holds) [IL L3062-3086].
5. **Aim (`lookAt` assigned)** [IL L3087-3186]: `tempVector = cameraCamera.WorldToScreenPoint(myParent.position) − cameraCamera.WorldToScreenPoint(myTransform.position)`; rewritten as `(tempVector.x, 0, tempVector.y)`; `aimAssist.position = myTransform.position`; `aimAssist.rotation = Quaternion.FromToRotation(Vector3.right, tempVector)`; `aimAssist.localEulerAngles.z = 0`; then `lookAt.localEulerAngles.z = aimAssist.localEulerAngles.y`. Net effect: the `lookAt` child is rolled about its local z axis so that the sprite points at the target on screen.
6. **Die with parent** (`dieWithParent`) [IL L3187-3211]: if `myParentScript.health <= 0` → `timer = hideTime`; if `myParentScript.myRenderer.enabled == false` → `timer = hideTime`. (Both force step 7 this frame.)
7. **Expiry:** if `timer >= hideTime` [IL L3212-3267]:
   - if `followupEffect != -1` and `myBoss` exists: `myBoss.myEffects[followupEffect].activate(myTransform.position, null)` [IL L3218-3238] (expiry follow-ups exist only for player-owned effects);
   - `position.z = 50` (parks the object out of view) [IL L3239-3264];
   - `this.enabled = false` [IL L3265-3267].
8. **Opacity:** if `opacityControl` exists: `myRenderer.material.color.a = opacityControl.localScale.x` (the `"effect"` animation clip animates that dummy child's scale to fade the effect) [IL L3268-3305].
9. **Owner facing:** if `matchOwnerFacing && myBoss != null && myBoss.myTransform == myParent` and own `localScale.x` ≠ parent's: copy the parent's `localScale.x` [IL L3306-3367].

Timing notes: `timer` uses scaled `Time.deltaTime`, so effects freeze while the game is paused and slow down during the slow-motion impacts of A.10/A.11. `hideTime` applies to projectiles too: a projectile whose `timer` reaches `hideTime` before it lands simply disappears without dealing damage [IL L3212-3267].

## A.6 `damageEnemy()` [IL L3760-4507] — player projectile lands on an enemy

Called only from `Update` step 3 [IL L3052]. Owner = `myBoss` (a `PartyMember`), victim = `myParent`.

**Step 0.** `tempEnemyScript = myParent.GetComponent("EnemyScript")` [IL L3776-3782].

**Steps 1–5 run only if `tempEnemyScript.health > 0`** [IL L3783-3788]; otherwise jump to step 6.

1. **Knock-back direction:** `tempVector = (myParent.position − myBoss.myTransform.position).normalized` — from the *shooter* to the victim, not along the projectile path [IL L3790-3802].
2. **Base damage** `dmg` (float local `V_0`) [IL L3803-3836]:
   - `dmg = myBoss.power` [IL L3803-3806];
   - if `aimedShot`: `dist = Vector3.Distance(myTransform.position, myBoss.myTransform.position)` (projectile-to-shooter distance at the moment of impact); `dmg = dmg × Mathf.Clamp(dist × 0.6, 1.5, projectileDamageMod)` [IL L3807-3830]. So the multiplier is at least `1.5`, grows by `0.6` per world unit of range, and is capped at the prefab's `projectileDamageMod` (cap value not in the IL);
   - else `dmg = dmg × projectileDamageMod` [IL L3832-3836].
3. **Critical Aim talent:** if `myBoss.passives[1] == 1 && aimedShot`: `dmg ×= 1.4` [IL L3837-3852]. (UNVERIFIED mapping: Ranger talent "Critical Aim", classes.json id 8 power 7. Note the in-game description says "+50%", the code multiplies by 1.4. The check does not test `characterClass`.)
4. **Deal damage (skipped entirely when `apollo` is true** [IL L3853-3855] — Apollo damage is dealt later by A.11):
   - crit condition = `myBoss.critChance > 0` AND `Random.Range(0, 100) <= myBoss.critChance` AND `canCrit` [IL L3857-3873]. (`Random.Range(int,int)` returns 0…99; the test is "roll not greater than critChance", so the real chance is `critChance + 1` percent.)
   - crit: `tempEnemyScript.takeDamage((int)(dmg × 2), tempVector × impactForce, myBoss)` [IL L3875-3889];
   - no crit: `tempEnemyScript.takeDamage((int)dmg, tempVector × impactForce, myBoss)` [IL L3892-3903].
   - `(int)` is a truncating cast (`conv.i4`) [IL L3881, L3895]. Armour / damage multipliers are applied inside `EnemyScript.takeDamage` (IL 18393–19181, out of scope).
5. **Debuff on hit** — if `applyDebuff != -1` [IL L3904-3907]:
   - if `applyDebuff == 1` and the victim is `likeABoss`: nothing is applied [IL L3909-3919];
   - otherwise [IL L3921-3943]:
     - `victim.debuffs[applyDebuff] = myBoss.motherBrain.debuffDurations[applyDebuff]`;
     - `victim.debuffColor = this.debuffColor`;
     - `victim.mostRecentDebuff = applyDebuff`;
   - if `applyDebuff == 0`: `victim.poisonMagnitude = motherBrain.debuffMagnitudes[0] × myBoss.power × myBoss.calculateDamageMultiplier(victim)` [IL L3944-3968];
   - else if `applyDebuff == 16`: `victim.rangerDotMagnitude = 0.5 × myBoss.power × myBoss.calculateDamageMultiplier(victim)` [IL L3970-3988].
   - **Mortal Shots:** if `canMortalStrike && myBoss.passives[0] == -1`: `victim.debuffs[17] = motherBrain.debuffDurations[17]` [IL L3989-4011]. (UNVERIFIED mapping: Ranger talent "Mortal Shots", classes.json id 8 power 4. No class check in the code.)
   - **Misdirection:** if `canMisdirect && myBoss.passives[1] == -1`: `victim.targetHighestArmorPlayer()` (EnemyScript IL 23177) [IL L4012-4026]. (UNVERIFIED mapping: Ranger talent "Misdirection", classes.json id 8 power 8.)

**Steps 6–12 run whether or not the victim was alive.**

6. **Wizard fireball splash ("Enveloping Flames")** — if `myBoss.characterClass == 4 && myBoss.passives[0] == 1` [IL L4027-4039] (class 4 = Wizard; UNVERIFIED mapping of the passive to classes.json id 3 power 3 "Enveloping Flames", whose description "75% of its damage to nearby targets" matches the constant below). Note this condition is on the *owner*, not on the effect: every projectile of such a wizard that goes through `damageEnemy` splashes.
   ```
   for i = 0 .. motherBrain.enemyScripts.length-1:          [IL L4041-4044, L4158-4171]
       e = motherBrain.enemyScripts[i]
       if e is null: i = enemyScripts.length  (stop the loop at the first empty slot)   [IL L4046-4054, L4151-4157]
       else if Distance(e.myTransform.position, myParent.position) < 1.7                [IL L4056-4070]
            and e.health > 0                                                             [IL L4072-4082]
            and e.myTransform != myParent      (not the primary victim)                  [IL L4084-4095]
            and e.myRenderer.enabled                                                     [IL L4097-4106]
       then:
            tempVector = (e.position - myParent.position).normalized                    [IL L4108-4125]
            e.takeDamage( (int)(myBoss.power * 0.75), tempVector * impactForce * 0.5, myBoss )   [IL L4126-4148]
   ```
   Splash radius `1.7` world units around the primary victim; splash damage is `0.75 × power` (it does **not** include `projectileDamageMod`, does not crit, applies no debuff); knock-back is half strength, directed away from the primary victim.
7. **Incendiary Arrow** — if `flameArrow` [IL L4173-4175]: see A.7.
8. **Impact sound** — if `impactSound >= 0` [IL L4341-4344]:
   - if `usesMeleeSoundCount`: `n = Random.Range(impactSound, impactSound + myBoss.totalMeleeSounds)` (int overload, upper bound exclusive); `myBoss.mySounds[n].pitch = Random.Range(impactLowPitch, impactHighPitch)`; `myBoss.mySounds[n].Play()` [IL L4346-4376];
   - else the same with `n = impactSound` [IL L4379-4397].
9. **Follow-up 1 (always, no `-1` guard):** `myBoss.myEffects[followupEffect].activate(myParent.position, null)` [IL L4398-4408]. Every player projectile prefab therefore must have a valid `followupEffect` (the impact burst); with the default `-1` this line would throw.
10. **Follow-up 2** — if `followupEffect2 != -1`:
    - not `apollo`: `myBoss.myEffects[followupEffect2].activate(myParent.position, myParent)` — attached to the victim, follows it [IL L4409-4429];
    - `apollo`: `myBoss.myEffects[followupEffect2].activate(myParent.position, null)` — left at the impact point [IL L4432-4451].
11. **Retire the projectile:** `position.z = 50`; `this.enabled = false` [IL L4452-4480].
12. **Slow-motion:** if `apollo`: `StartCoroutine(onApolloImpact(tempEnemyScript, dmg, tempVector))` [IL L4481-4495]; else if `dramaticImpact`: `StartCoroutine(onDramaticImpact())` [IL L4497-4505]. (If the victim was already dead at step 0, `dmg` is 0 and `tempVector` is stale; the Apollo coroutine re-checks `health > 0` before damaging.)

### Debuff / buff indices seen in this scope

Only the indices the EffectScript code itself names are listed; the full tables live in `MotherBrain.debuffDurations / debuffMagnitudes / buffDurations` (declared [IL L59140-59143]) which are **inspector-serialized arrays with no values in the IL**.

| Array | Index | What EffectScript does with it | Citation |
|---|---|---|---|
| `EnemyScript.debuffs[]` | 0 | Poison-type DoT: also sets `poisonMagnitude = debuffMagnitudes[0] × power × calculateDamageMultiplier(victim)` | [IL L3944-3968] |
| `EnemyScript.debuffs[]` | 1 | Never applied to `likeABoss` enemies | [IL L3909-3919] |
| `EnemyScript.debuffs[]` | 3 | Apollo Strike: set to `8` (seconds) if currently `< 8` | [IL L5211-5226] |
| `EnemyScript.debuffs[]` | 4 | Apollo Strike: set to `0.3` together with index 3 | [IL L5227-5232] |
| `EnemyScript.debuffs[]` | 16 | Ranger DoT: also sets `rangerDotMagnitude = 0.5 × power × calculateDamageMultiplier(victim)` (UNVERIFIED: this is "Vile Bolt", classes.json id 8 power 2) | [IL L3970-3988] |
| `EnemyScript.debuffs[]` | 17 | Mortal Shots debuff, duration `debuffDurations[17]` | [IL L3989-4011] |
| `PartyMember.buffs[]` | 6 | Incendiary Arrow fire patch #2 timer, set to `10` | [IL L4258-4263] |
| `PartyMember.buffs[]` | 7 | Incendiary Arrow fire patch #1 timer, set to `10` | [IL L4193-4198] |
| `PartyMember.buffs[applyDebuff]` | any | Enemy projectile debuff on a player, duration `buffDurations[applyDebuff]` | [IL L4567-4584] |

How the debuff timers tick and what each debuff does is in `EnemyScript.handleDebuffs` (IL 22458) and `PartyMember.handleBuffs` (IL 86039) — out of scope.

## A.7 Incendiary Arrow impact (`flameArrow` branch of `damageEnemy`) [IL L4173-4340]

Ranger "Incendiary Arrow" (classes.json id 8 power 1; UNVERIFIED that this is the only user of the flag). Runs even if the victim was already dead.

1. Camera shake: `motherBrain.cameraShaker.Stop(); .Play("shake")` [IL L4177-4188].
2. The private toggle `flamePatch` alternates between two patch slots so that two fires can burn at once:

| `flamePatch` before | Owner buff timer set | Owner position field set | Effects activated (index in `myBoss.myEffects`, position, parent null) | Toggle after | Citation |
|---|---|---|---|---|---|
| `true` (first shot, default) | `myBoss.buffs[7] = 10` | `myBoss.flamePatch = victim.myTransform.position` | `[11]` at victim pos + `(0, 0, −0.4)`; `[12]` at victim pos + `(0, 0, +0.4)`; `[13]` at victim pos | `false` | [IL L4189-4256] |
| `false` | `myBoss.buffs[6] = 10` | `myBoss.flamePatch2 = victim.myTransform.position` | `[15]` at victim pos + `(0, 0, −0.4)`; `[16]` at victim pos + `(0, 0, +0.4)`; `[17]` at victim pos | `true` | [IL L4258-4320] |

3. Sound: `myBoss.mySounds[13].Play()`; then if `motherBrain.DB.soundEnabled`: `myBoss.mySounds[13].volume = 1.0` [IL L4321-4340].

The patch lasts 10 seconds (the buff timer). The patch's damage tick is **not** in EffectScript: it is done by `PartyMember.flameArrowPulse` (IL 84589–84975) using `PartyMember.flamePatch` / `flamePatch2` and `buffs[7]` / `buffs[6]` — out of scope. The three activated effects per patch are visuals only.

## A.8 `damagePlayer()` [IL L4510-4719] — enemy projectile lands on a party member

Called only from `Update` step 3 [IL L3061]. Owner = `myEnemyBoss`, victim = `myParent`.

1. `tempPlayerScript = myParent.GetComponent("PartyMember")` [IL L4523-4529].
2. If `tempPlayerScript.health > 0` [IL L4530-4535]:
   - `tempVector = (myParent.position − myTransform.position).normalized` — here the knock-back is along the projectile's flight (projectile → victim) [IL L4537-4548];
   - `tempPlayerScript.takeDamage((int)(myEnemyBoss.power × projectileDamageMod), tempVector × impactForce, myEnemyBoss)` [IL L4549-4566]. `EnemyScript.power` is an int. No crit, no distance scaling;
   - if `applyDebuff != -1`: `tempPlayerScript.buffs[applyDebuff] = myEnemyBoss.motherBrain.buffDurations[applyDebuff]` [IL L4567-4584]. (Player-side negative statuses live in the same `buffs[]` array as positive buffs.)
3. Impact sound, if `impactSound >= 0`:
   - owner **not** `likeABoss`: `n = Random.Range(impactSound, impactSound + myEnemyBoss.totalMeleeSounds)`; set random pitch in `[impactLowPitch, impactHighPitch]`; `myEnemyBoss.mySounds[n].Play()` [IL L4585-4622];
   - owner `likeABoss`: same with `n = impactSound` exactly [IL L4624-4647].
4. Follow-up 1 (always, no guard): `myEnemyBoss.myEffects[followupEffect].activate(myParent.position + (0, 0, −0.05), null)` [IL L4648-4665].
5. Follow-up 2, if `followupEffect2 != -1`: `myEnemyBoss.myEffects[followupEffect2].activate(myParent.position + (0, −0.4, 1), null)` [IL L4666-4688].
6. Retire: `position.z = 50`; `enabled = false` [IL L4689-4717].

## A.9 `healPlayer()` [IL L4722-4835] — heal projectile lands on a party member

Called only from `Update` step 3 when `healProjectile` [IL L3043]. Owner = `myBoss`, target = `myParent`.

1. `tempPlayerScript = myParent.GetComponent("PartyMember")` [IL L4733-4739].
2. If target `health > 0`: `tempPlayerScript.heal((int)(healAmount × projectileDamageMod), myBoss)` [IL L4740-4757]. A dead target is not healed (no revive).
3. If `impactSound >= 0`: `myBoss.mySounds[impactSound].Play()` (no pitch randomisation) [IL L4758-4769].
4. Follow-up 1 (always): `myBoss.myEffects[followupEffect].activate(myParent.position + (0, 0, −0.05), null)` [IL L4770-4787].
5. Follow-up 2 if `!= -1`: `myBoss.myEffects[followupEffect2].activate(myParent.position, myParent)` (attached to the healed target) [IL L4788-4804].
6. Retire: `position.z = 50`; `enabled = false` [IL L4805-4833].

### Where code (not the prefab) writes EffectScript tuning fields

A search of the whole IL for writes to `EffectScript::` fields outside the class finds only these:

| Field | Written by | Value | Citation |
|---|---|---|---|
| `myBoss` | `PartyMember.createMyEffects` — each effect is `Instantiate(Resources.Load(myEffectNames[i]))`, its `EffectScript` stored in `myEffects[i]` | the party member | [IL L86690-86740] |
| `myEnemyBoss` | `EnemyScript.initialize` — same pattern for the enemy's `myEffects[i]` | the enemy | [IL L5620-5639] |
| `projectileDamageMod` of `myEffects[0]` | `PartyMember.initialize`, when `characterClass == 4` (Wizard) and `passives[0] == -1` | `1.2` (matches talent "Impact: fireball +20%", classes.json id 3 power 4) | [IL L77680-77697] |
| `projectileDamageMod` of `myEffects[0]` | `PartyMember.initialize`, when `characterClass == 5` (Witch) and `passives[0] == 1` | `1.15` (matches talent "Piercing Shadow: shadowbolt +15%", classes.json id 4 power 3) | [IL L77699-77715] |
| `healAmount` of `myEffects[5]` | `PartyMember.performSpecial` coroutine (Witch Drain Life heal bolt; UNVERIFIED which power — only the write sites were inspected): `returnedDamage × 1.4` if `passives[3] == -1`; `hypotheticalDamage` if `passives[3] == 1`; else `returnedDamage` | see left | [IL L98700-98748] |

So `myEffects[0]` is the basic-attack projectile of the Wizard (fireball) and Witch (shadowbolt). All other per-effect values (`moveSpeed`, `moveTime`, `hideTime`, `impactForce`, `applyDebuff`, flags, sound ids, follow-up ids, and the default `projectileDamageMod` of every other projectile) are prefab data that is **not present in the IL or in `bh/data`**.

## A.10 `onDramaticImpact()` coroutine [stub IL L4838-4848, body IL L4934-5001]

Short "hit-stop" used by projectiles flagged `dramaticImpact`.

1. `motherBrain.disableSpecials = true` [IL L4946-4951].
2. `Time.timeScale = 0.1` [IL L4952-4953].
3. `motherBrain.dimBackground = true` [IL L4954-4959].
4. `motherBrain.cameraShaker.Stop(); .Play("powerUpShake")` [IL L4960-4973].
5. `yield WaitForSeconds(0.07)` [IL L4974-4978] — scaled time; at timeScale 0.1 this is 0.7 s of real time.
6. `motherBrain.disableSpecials = false`; `motherBrain.dimBackground = false`; `Time.timeScale = 1.0` [IL L4981-4994].

(`motherBrain` is `myBoss.motherBrain`.) The damage itself was already dealt by `damageEnemy` step 4 before the coroutine starts.

## A.11 `onApolloImpact(EnemyScript victimScript, float victimDamage, Vector3 victimVector)` coroutine [stub IL L4851-4864, body IL L5101-5274]

Ranger "Apollo Strike" (classes.json id 8 power 6: "throws its victim to the ground for 8 seconds"). The projectile has already retired itself; the damage is delayed until after a slow-motion beat.

1. `motherBrain.disableSpecials = true`; `Time.timeScale = 0.0333`; `motherBrain.dimBackground = true`; `cameraShaker.Stop(); .Play("powerUpShake")` [IL L5113-5140].
2. `yield WaitForSeconds(0.0233)` [IL L5141-5145] — scaled time; at timeScale 0.0333 this is ≈ 0.7 s real time.
3. If `victimScript.health > 0` [IL L5148-5153]:
   - crit roll identical to `damageEnemy`: `myBoss.critChance > 0 && Random.Range(0,100) <= myBoss.critChance && canCrit` → `victimScript.takeDamage((int)(victimDamage × 2), victimVector × impactForce, myBoss)` [IL L5155-5193]; otherwise `takeDamage((int)victimDamage, victimVector × impactForce, myBoss)` [IL L5196-5210]. `victimDamage` is the `dmg` computed in `damageEnemy` step 2–3 (`power × projectileDamageMod`, plus the aimed-shot rules if the prefab also had `aimedShot`).
   - knock-down: if `victimScript.debuffs[3] < 8`: `debuffs[3] = 8` and `debuffs[4] = 0.3` [IL L5211-5232]. (There is no `likeABoss` exemption here.)
4. Always: `myBoss.mySounds[9].Play()`; `cameraShaker.Stop(); .Play("shake")`; `disableSpecials = false`; `dimBackground = false`; `Time.timeScale = 1.0` [IL L5233-5267].

## A.12 `Main()` [IL L4867-4874] — empty.

## A.13 How to reproduce the effect types (porting cheat-sheet)

Everything below is a restatement of A.3–A.11.

| Effect kind | Flags | Movement | On land / expiry |
|---|---|---|---|
| One-shot burst at a point | `projectile=false`, parent null | none | hides at `hideTime`; optional `followupEffect` (player-owned only) [IL L3212-3267] |
| Aura / status visual on a unit | `projectile=false`, parent set, often `dieWithParent`, `hasLoop` | snaps to parent every frame [IL L2917-2931] | hides at `hideTime`, or immediately when the parent enemy dies / is hidden [IL L3187-3211] |
| Player damage projectile | `projectile=true`, `myBoss` set | homing, `moveSpeed` u/s after `moveTime` s [IL L2991-3022] | `damageEnemy()` A.6 |
| Enemy damage projectile | `projectile=true`, `myEnemyBoss` set | same | `damagePlayer()` A.8 |
| Heal projectile | `projectile=true`, `healProjectile=true` | same | `healPlayer()` A.9 |

Landing threshold: `distance < 0.04 × moveSpeed × Time.timeScale` [IL L3023-3036].

---

# PART B — `Database` (IL 854–2554)

## B.1 Summary

`Database` is a single persistent object (it calls `DontDestroyOnLoad` on itself) that holds every
static data table (items, heroes, class powers, maps/levels/waves, loot tables — all decoded in
`bh/data/*.json`) **and** the live state of the current playthrough (gold, inventory, party line-up,
hero progress, level completion flags, merchant stock). Other scripts reach it with
`GetComponent("Database")` and keep it in a field called `DB`.

Persistence is done with Unity `PlayerPrefs` (flat key → int/float/string store). There are three
player save slots (`1`, `2`, `3`) plus a hidden slot `4` that holds a pristine copy of the default
database (see B.9). Every key of a slot is prefixed with the slot number written as decimal text
with **no separator** (e.g. `1gold`, `2partyDB3level`). `save()` writes everything for the current
slot; `load()` reads it back. The merchant's stock is **not** saved; it is re-rolled by
`populateMerchant()` when a game is started or loaded and after battles.

## B.2 Fields

Declared [IL L857-885]. Table contents are in `bh/data` (extracted from the serialized scene, not from the IL). "ctor default" is what `.ctor` [IL L888-945] sets; `bh/data/globals.json` shows the scene-serialized values that override those at runtime.

| Field | Type | ctor default | Meaning | Persisted by `save()`? |
|---|---|---|---|---|
| `itemDB` | `Item[]` | — | Item table → `bh/data/items.json` | no |
| `partyDB` | `Player[]` | — | Hero table → `bh/data/party.json` | per-hero subset, see B.4 |
| `powerDB` | `powerCollection[]` | — | Classes and powers → `bh/data/classes.json` | no |
| `inventory` | `int[]` | — | Item ids in the shared bag, `-1` = empty (20 slots in globals.json) | yes, all entries |
| `party` | `int[]` | — | `partyDB` indices of the 4 active heroes, `-1` = empty | yes, indices 0–3 |
| `reserves` | `int[]` | — | `partyDB` indices of benched heroes (12 slots in globals.json) | yes |
| `gold` | int | `100` [IL L897-898] (globals.json: 15) | Gold | yes |
| `timePlayed` | float | 0 | Play time | yes (float) |
| `merchant` | `int[]` | — | Item ids currently for sale, `-1` = empty (8 slots in globals.json) | **no** |
| `levelDB` | `Map[]` | — | Maps/levels/waves → `bh/data/maps.json` | `complete` (+ `highScore` for arenas) per level |
| `whichSaveSlot` | int | `1` [IL L900-901] (globals.json: 0) | Current slot; used as the key prefix. `0` = no game loaded (autosave is suppressed, B.7) | (is the prefix) |
| `currentMap` | int | `-1` [IL L903-904] (globals.json: 0) | Selected map | no |
| `whichLevel` | int | `-1` [IL L906-907] (globals.json: 0) | Selected level | no |
| `tutorial` | bool | false | Tutorial flag | no |
| `firstLevelXP` | int | `50` [IL L909-910] (globals.json: 30) | XP curve base | no |
| `XPscale` | float | `1.1` [IL L912-913] (globals.json: 1.35) | XP curve factor | no |
| `XPtable` | `float[]` | — | Per-level XP growth factors (globals.json) | no |
| `transferLevel` | int | 0 | (not used inside this class) | no |
| `lootTables` | `LootTable[]` | — | → `bh/data/loot_tables.json` | no |
| `academyFirstVisit` | int | `1` [IL L915-916] | First-visit tutorial flag | yes |
| `merchantFirstVisit` | int | `1` [IL L918-919] | First-visit tutorial flag | yes |
| `armoryFirstVisit` | int | `1` [IL L921-922] | First-visit tutorial flag | yes |
| `keepFirstVisit` | int | `1` [IL L924-925] | First-visit tutorial flag | yes |
| `level5reminder` | int | `1` [IL L927-928] | One-shot reminder flag | yes |
| `arenaExplanation` | int | `1` [IL L930-931] | One-shot explanation flag | yes |
| `finalBossKill` | int | `1` [IL L933-934] | One-shot flag | yes |
| `musicEnabled` | bool | `true` [IL L936-937] | Music option | yes, global key (no slot prefix) |
| `soundEnabled` | bool | `true` [IL L939-940] | Sound-effects option | yes, global key (no slot prefix) |
| `freshBoot` | bool | `true` [IL L942-943] | True while no game has been started/loaded since boot or since quitting to the title; blocks autosave (B.7) | no |

The meaning of the `*FirstVisit`, `level5reminder`, `arenaExplanation`, `finalBossKill` values (which number means "already shown") is decided by MenuBrain/MotherBrain, not by this class; `Database` only stores the ints.

## B.3 `Awake()` [IL L948-998]

1. `DontDestroyOnLoad(gameObject)` [IL L954-956].
2. Option flags use a **three-valued int** in PlayerPrefs, key `"musicEnabled"` (no slot prefix): `0` = never written, `1` = disabled, `2` = enabled.
   - if `PlayerPrefs.GetInt("musicEnabled") == 0`: `PlayerPrefs.SetInt("musicEnabled", 2)`; `musicEnabled = true` [IL L957-967];
   - else if it `== 1`: `musicEnabled = false` [IL L969-976]; (value 2 leaves the field as it was, i.e. the default `true`).
3. Exactly the same for key `"soundEnabled"` → field `soundEnabled` [IL L977-996].

## B.4 `save()` [IL L1001-1682]

Writes, in this order (`S` = `whichSaveSlot` as decimal text; `+` is plain string concatenation with no separators [IL L1045-1054, L1420-1433, L1514-1529]):

| # | PlayerPrefs key | Type | Value | Citation |
|---|---|---|---|---|
| 1 | `Warning` | string | `"Seriously, don't mess with these values.  You'll probably just break your game."` | [IL L1014-1016] |
| 2 | `musicEnabled` | int | `2` if `musicEnabled` else `1` | [IL L1017-1028] |
| 3 | `soundEnabled` | int | `2` if `soundEnabled` else `1` | [IL L1029-1040] |
| 4 | for each `i` in `0 … partyDB.length−1` (loop [IL L1041-1043, L1407-1415]): | | | |
| 4a | `S+"partyDB"+i+"playerName"` | string | `partyDB[i].playerName` | [IL L1045-1060] |
| 4b | `S+"partyDB"+i+"level"` | int | `partyDB[i].level` | [IL L1061-1076] |
| 4c | `S+"partyDB"+i+"recruited"` | int | `1` if `recruited` else `0` | [IL L1077-1110] |
| 4d | `S+"partyDB"+i+"available"` | int | `1` if `available` else `0` | [IL L1111-1144] |
| 4e | `S+"partyDB"+i+"gear0"` … `"gear3"` | int ×4 | `partyDB[i].gear[0..3]` (item ids, `-1` = empty) | [IL L1145-1216] |
| 4f | `S+"partyDB"+i+"XP"` | int | `partyDB[i].XP` | [IL L1217-1232] |
| 4g | `S+"partyDB"+i+"power"` | int | `partyDB[i].power` | [IL L1233-1248] |
| 4h | `S+"partyDB"+i+"defense"` | int | `partyDB[i].defense` | [IL L1249-1264] |
| 4i | `S+"partyDB"+i+"maxHealth"` | int | `partyDB[i].maxHealth` | [IL L1265-1280] |
| 4j | `S+"partyDB"+i+"abilities0"` … `"abilities2"` | int ×3 | `partyDB[i].abilities[0..2]` | [IL L1281-1334] |
| 4k | `S+"partyDB"+i+"passives0"` … `"passives3"` | int ×4 | `partyDB[i].passives[0..3]` | [IL L1335-1406] |
| 5 | `S+"inv"+i` for `i` in `0 … inventory.length−1` | int | `inventory[i]` | [IL L1417-1442] |
| 6 | `S+"party"+i` for `i` in `0 … 3` (hard-coded 4) | int | `party[i]` | [IL L1444-1467] |
| 7 | `S+"reserves"+i` for `i` in `0 … reserves.length−1` | int | `reserves[i]` | [IL L1469-1494] |
| 8 | for each map `m` in `0 … levelDB.length−1`, each level `l` in `0 … levelDB[m].whichLevel.length−1` (loops [IL L1496-1502, L1579-1600]): | | | |
| 8a | `S+"levelDB"+l+m+"complete"` — **level index first, then map index** | int | `1` if `levelDB[m].whichLevel[l].complete` else `0` | [IL L1504-1546] |
| 8b | `S+"levelDB"+l+m+"highScore"` — only if that level's `arena` is true | int | `levelDB[m].whichLevel[l].highScore` | [IL L1548-1578] |
| 9 | `S+"academyFirstVisit"` | int | field | [IL L1602-1609] |
| 10 | `S+"merchantFirstVisit"` | int | field | [IL L1610-1617] |
| 11 | `S+"armoryFirstVisit"` | int | field | [IL L1618-1625] |
| 12 | `S+"keepFirstVisit"` | int | field | [IL L1626-1633] |
| 13 | `S+"level5reminder"` | int | field | [IL L1634-1641] |
| 14 | `S+"arenaExplanation"` | int | field | [IL L1642-1649] |
| 15 | `S+"finalBossKill"` | int | field | [IL L1650-1657] |
| 16 | `S+"gold"` | int | `gold` | [IL L1658-1665] |
| 17 | `S+"timePlayed"` | **float** (`SetFloat`) | `timePlayed` | [IL L1666-1673] |
| 18 | `S+"saveExists"` | int | `1` | [IL L1674-1680] |

Example keys for slot 2: `2partyDB0level`, `2inv13`, `2party0`, `2reserves11`, `2levelDB30complete` (level 3 of map 0), `2gold`, `2saveExists`.

`save()` does not call `PlayerPrefs.Save()`; flushing to disk is left to Unity [IL L1001-1682 contains no such call].

**Not persisted** (never written by `save()`): `merchant[]`, `currentMap`, `whichLevel`, `tutorial`, `transferLevel`, `freshBoot`, the XP constants, and per-hero `characterClass`, `description`, `icon` (hero identity comes from the fixed `partyDB` order; only the name is saved as text). Current HP is not a `Player` field and is not saved.

## B.5 `load()` [IL L1685-2337]

Reads the same keys for the current `whichSaveSlot` (`S`). Differences from `save()` are highlighted.

1. For each `i` in `0 … partyDB.length−1` [IL L1699-1701, L2075-2083]:
   - **Gate:** the hero record is loaded only if `PlayerPrefs.GetInt(S+"partyDB"+i+"recruited") != 0` **or** `whichSaveSlot == 4` [IL L1703-1719]. Otherwise the hero keeps whatever is currently in memory (so un-recruited heroes are never overwritten from a player slot — including their `available` flag and name).
   - When loaded: `playerName` (GetString) [IL L1721-1736]; `level` [IL L1737-1752]; `recruited = (GetInt(...) == 1)` [IL L1753-1782]; `available = (GetInt(...) == 1)` [IL L1783-1812]; `gear[0..3]` [IL L1813-1884]; `XP` [IL L1885-1900]; `power` [IL L1901-1916]; `defense` [IL L1917-1932]; `maxHealth` [IL L1933-1948]; `abilities[0..2]` [IL L1949-2002]; `passives[0..3]` [IL L2003-2074].
2. `inventory[i] = GetInt(S+"inv"+i)` for `i` in `0 … inventory.length−1` [IL L2085-2110].
3. `party[i] = GetInt(S+"party"+i)` for `i` in `0 … 3` [IL L2112-2135].
4. `reserves[i] = GetInt(S+"reserves"+i)` for `i` in `0 … 11` — **hard-coded 12** here (save uses `reserves.length`) [IL L2137-2160].
5. For each map `m`, level `l` (same nesting as save) [IL L2162-2168, L2241-2262]: `levelDB[m].whichLevel[l].complete = (GetInt(S+"levelDB"+l+m+"complete") == 1)` [IL L2170-2208]; if that level's `arena` is true: `highScore = GetInt(S+"levelDB"+l+m+"highScore")` [IL L2209-2240].
6. Flags, in this order: `armoryFirstVisit` [IL L2265-2271], `merchantFirstVisit` [IL L2273-2279], `academyFirstVisit` [IL L2281-2287], `keepFirstVisit` [IL L2289-2295], `level5reminder` [IL L2297-2303], `arenaExplanation` [IL L2305-2311], `finalBossKill` [IL L2313-2319].
7. `gold = GetInt(S+"gold")` [IL L2321-2327]; `timePlayed = GetFloat(S+"timePlayed")` [IL L2329-2335].

`load()` does not read `saveExists`, `musicEnabled`, `soundEnabled` or `Warning`, and does not touch `merchant[]`. `PlayerPrefs.GetInt` of a missing key returns 0 (Unity behaviour, not visible in the IL), which is why a hero with no saved `recruited` key is skipped by the gate.

## B.6 `populateMerchant()` [IL L2385-2542] — rolling the shop stock

Exact algorithm:

```
1. for i in 0 .. merchant.length-1:  merchant[i] = -1                      [IL L2398-2417]

2. highest = 0                                                             [IL L2419-2420]
   for i in 0 .. partyDB.length-1:                                         [IL L2421-2423, L2446-2454]
       if partyDB[i].level > highest and partyDB[i].recruited:             [IL L2425-2438]
           highest = partyDB[i].level                                      [IL L2440-2445]
   # highest = level of the highest-level RECRUITED hero (benched heroes count, un-recruited do not)

3. eligible = []   (UnityScript Array)                                     [IL L2456-2457]
   for t in 0 .. lootTables.length-1:                                      [IL L2458-2460, L2483-2491]
       if highest >= lootTables[t].minLevel and highest <= lootTables[t].maxLevel:   [IL L2462-2476]
           eligible.push(t)                                                [IL L2478-2482]

4. count = Random.Range(3, 9)        # int overload, upper bound exclusive -> 3..8 items   [IL L2493-2496]

5. for i in 0 .. count-1:                                                  [IL L2501-2503, L2533-2539]
       t    = eligible[ Random.Range(0, eligible.length) ]                 [IL L2505-2512]
       item = lootTables[t].tableContents[ Random.Range(0, tableContents.length) ]   [IL L2513-2527]
       merchant[i] = item                                                  [IL L2528-2532]
```

Rules that follow directly from the code:

- The stock is **3 to 8 items** (uniform), filling `merchant[0 … count−1]`; the remaining slots stay `-1`.
- Each item is an independent draw: first a uniformly random eligible loot table, then a uniformly random entry of that table. **Duplicates are possible** (no de-duplication), there is no filter by class/usability, by item type, or by what the player already owns, and no price logic here.
- Eligibility uses inclusive bounds `minLevel <= highest <= maxLevel`.
- With the values in `bh/data/loot_tables.json`:

| Highest recruited hero level | Eligible loot tables (id: name) |
|---|---|
| 1 | 0: Tier 1 Gear |
| 2–4 | 0: Tier 1 Gear; 1: Tier 2 Gear + 1.0 trinkets |
| 5–7 | 1 |
| 8–11 | 1; 2: Tier 3 Gear + 1.0 & 1.5 trinkets |
| 12–13 | 2 |
| 14–16 | 2; 3: Tier 4 Gear + 1.5 and 2.0 trinks |
| 17 | 3 |
| 18–21 | 3; 4: Tier 5 Gear + 2.0 & 2.5 trinkets |
| 22–23 | 4 |
| 24–27 | 4; 5: Tier 6 Gear + 2.5 & 3.0 trinkets |
| 28–34 | 5; 6: Tier 7 Gear + 3.0 & 3.5 trinkets |
| 35+ | 6 |

  (This table is derived by applying the rule above to loot_tables.json ranges 0–4, 2–11, 8–16, 14–21, 18–27, 24–34, 28–999.) Tables 7 ("Tier 8 Gear + 3.5 trinkets") and 8 ("Tier 9 Gear") have `minLevel = maxLevel = 0` in loot_tables.json, so they are eligible only when `highest == 0`, which cannot happen once any recruited hero has level ≥ 1 — **the merchant never sells Tier 8/9 items**. Because two tables are equally likely when two are eligible, an item that appears in both tables is proportionally more likely.
- If `eligible` were empty the code would index an empty array (no guard) [IL L2505-2512]; with the shipped tables this does not occur for levels ≥ 1.

Callers (cross-reference): `MenuBrain.startNewGame` coroutine [IL L58786] (followed by `save()` [IL L58798]); `MenuBrain.loadExistingGame` coroutine after `load()` [IL L58947, L58960]; `MotherBrain.XPBarAnimation` coroutine [IL L75475]; `MotherBrain.defeatSequence` coroutine [IL L75819, L75904]. So the stock is re-rolled on new game, on loading a save, and after a battle (victory XP screen or defeat). It is never saved, so reloading a slot re-rolls it.

## B.7 `OnApplicationPause(bool paused)` [IL L2340-2362] and `OnApplicationQuit()` [IL L2365-2382] — autosave

- `OnApplicationPause(true)`: if `!freshBoot && whichSaveSlot != 0` → `save()` [IL L2346-2358]. Nothing happens on resume (`false`).
- `OnApplicationQuit()`: if `!freshBoot && whichSaveSlot != 0` → `save()` [IL L2371-2380].

## B.8 `.ctor` [IL L888-945], `Main` [IL L2545-2552]

`.ctor` sets the defaults listed in B.2. `Main` is empty.

## B.9 Cross-references: save slots and the hidden slot 4 (outside this class, verified in the IL)

- Explicit `save()` calls outside the class: `MenuBrain.Awake` [IL L33149, L33312]; `MenuBrain.mainInput` coroutine [IL L49205, L49378]; `MenuBrain.mapInput` coroutine [IL L56157]; `MenuBrain.startNewGame` coroutine [IL L58798]. `load()` calls: [IL L49214, L49387, L58947].
- **Slot 4 = pristine template.** In `MenuBrain.Awake`, when `DB.freshBoot == true`: `activeMenu = 6`, `updateLoadScreen()`, and if `PlayerPrefs.GetInt("cleansave") != 2` then `PlayerPrefs.SetInt("cleansave", 2)`, `DB.whichSaveSlot = 4`, `DB.save()` — i.e. on the very first launch the untouched default database is written under prefix `4` [IL L33120-33149].
- **Quit to title.** In `MenuBrain.mainInput`: `DB.save()` (current slot), then `DB.whichSaveSlot = 4; DB.load()` (restore the pristine database — this is why `load()` bypasses the `recruited` gate for slot 4), then `DB.whichSaveSlot = 0; DB.freshBoot = true` [IL L49200-49224] (same sequence again at [IL L49378-49397]).
- Save-slot presence is tested with the keys `"1saveExists"`, `"2saveExists"`, `"3saveExists"` in `MenuBrain.updateLoadScreen` [IL L34854, L35083, L35312], `MenuBrain.loadInput` [IL L57783-58206] and `titleinit.Update` [IL L108644-108650].
- `EffectScript` reads `DB.soundEnabled` [IL L4329-4332].

---

# PART C — Pet and small classes

## C.1 `PetScript` (IL 105812–107128) — the Ranger's dog

### C.1.1 Summary

The only pet in the game is the Ranger's hunting dog (prefab `Resources "Allies/Dog"`). It exists
only if the party member is a Ranger (`characterClass == 9`) whose `passives[2]` is non-zero
(UNVERIFIED mapping: talent "Canine Ally", classes.json id 8 power 9). The dog is not a party
member: it has no health, cannot be targeted or damaged (nothing in `PetScript` stores HP and no
enemy code references it except to clear its target), and it is driven once per frame by its
owner's `remoteUpdate`. It runs at 3.5 units/s to a melee slot next to its target, plays an
`"attack"` animation, and 0.26 s later deals `0.4 × owner power` (value frozen when the battle
starts) to the target, credited to the owner. It attacks whatever the Ranger attacks; when it has
no target it follows the Ranger's move orders and, every 0.5 s, auto-acquires any enemy within
1.5 units of itself. Two talents modify the bite: one applies debuff 18 to the victim, the other
turns the bite into an area attack around the dog. When the Ranger dies the dog runs off-screen to
x = −20.

### C.1.2 Fields [IL L105815-105827]

| Field | Type | Default | Meaning |
|---|---|---|---|
| `myOwner` | PartyMember | set by `PartyMember.initialize` [IL L78030-78032] | The Ranger that owns the dog. |
| `myTarget` | Transform | null | Enemy transform being attacked; null = no target. |
| `myTargetEnemyScript` | EnemyScript | null | `EnemyScript` of `myTarget`. |
| `myTransform` | Transform | set in `Initialize` [IL L105854-105857] | Own transform. `localScale.x` is the facing: `-1` when the destination is to the left (smaller x), `+1` when to the right [IL L106039-106133]. |
| `myAnimation` | Animation | set in `Initialize` [IL L105858-105861] | Clips used: `"attack"`, `"run"`, `"idle"` [IL L105870, L106162, L106169]. |
| `motherBrain` | MotherBrain | `myOwner.motherBrain` [IL L105862-105866] | Battle controller (enemy list, right screen edge, debuff durations). |
| `meleeSlot` | int | 0 | Index into the target's `EnemyScript.meleePositions[]` the dog stands at; chosen by `chooseSlot` (0, 1, 2 or 4). |
| `moveSpeed` | float | `3.5` [IL L105839-105840] | Run speed, world units / second. |
| `power` | float | `myOwner.power × 0.4` [IL L105873-105879] | Damage per bite; computed once in `Initialize`, never refreshed (owner buffs applied later do not change it — any further scaling happens inside `EnemyScript.takeDamage`, out of scope). |
| `movementTarget` | Vector3 | (0,0,0) | Where the dog is running to. |
| `movementVector` | Vector3 | — | Scratch: normalised direction of travel. |
| `attackState` | AnimationState (private) | `myAnimation["attack"]` [IL L105867-105872] | Used as the "busy" flag: while its `weight != 0` the AI is skipped. |
| `autoTargetTimer` | float (private) | `0.5` [IL L105842-105843] | Countdown to the next auto-target scan. |

### C.1.3 Creation and ownership (in `PartyMember`, cross-reference)

- End of `PartyMember.initialize`: if `characterClass == 9 && passives[2] != 0`: `tempGO = Instantiate(Resources.Load("Allies/Dog"))`; `petScript = tempGO.GetComponent(PetScript)`; `petScript.myOwner = this`; `petScript.Initialize()` [IL L78005-78035].
- `PartyMember.remoteUpdate` ends with: if `petScript` exists → `petScript.RemoteUpdate()` [IL L78091-78097]. The pet has no `Update` of its own.

### C.1.4 `Initialize()` [IL L105848-105881]

Caches `myTransform`, `myAnimation`, `motherBrain = myOwner.motherBrain`, `attackState = myAnimation["attack"]`, and sets `power = myOwner.power × 0.4`.

### C.1.5 `RemoteUpdate()` [IL L105884-106451] — per-frame AI

```
1. if movementTarget.x > motherBrain.edge + 0.5:  movementTarget.x = motherBrain.edge     [IL L105925-105940]
      (edge = right-hand limit of the play field, set by dynamicbackgroundhandler, C.12)
2. if position.y != 0:  position.y = 0                                                    [IL L105941-105976]
3. if myTargetEnemyScript exists and its health <= 0:                                     [IL L105977-105995]
       clearTarget();  movementTarget = position      (stop where it stands)
4. if myOwner.health <= 0:                                                                [IL L105996-106017]
       movementTarget = (-20, 0, 0);  myTarget = null;  myTargetEnemyScript = null
5. if attackState.weight != 0:  return          (attack animation still playing)          [IL L106018-106023]

6. if myTarget is null:                                                                   [IL L106025-106028]
   a. if Distance(position, movementTarget) > 0.4:                                        [IL L106030-106037]
          face(movementTarget)                                                            [IL L106039-106133]
          movementVector = (movementTarget - position).normalized                         [IL L106137-106145]
          position += movementVector * Time.deltaTime * moveSpeed                         [IL L106147-106159]
          myAnimation.Play("run")                                                         [IL L106161-106163]
      else:
          myAnimation.CrossFade("idle", 0.1)                                              [IL L106168-106171]
   b. autoTargetTimer -= Time.deltaTime                                                   [IL L106174-106177]
      if autoTargetTimer <= 0:                                                            [IL L106179-106182]
          autoTargetTimer = 0.5                                                           [IL L106185-106186]
          for i in 0 .. motherBrain.enemyScripts.length-1:                                [IL L106187-106189, L106275-106284]
              e = motherBrain.enemyScripts[i]
              if e is null: stop the loop                                                 [IL L106192-106197, L106271-106274]
              if Distance(e.myTransform.position, position) < 1.5                         [IL L106200-106211]
                 and e.attackers < 4                                                      [IL L106214-106220]
                 and e.health > 0                                                         [IL L106223-106230]
                 and e.myRenderer.enabled                                                 [IL L106233-106239]
                 and not e.invincible:                                                    [IL L106242-106247]
                     myTargetEnemyScript = e;  myTarget = e.myTransform                   [IL L106251-106260]
                     chooseSlot()                                                         [IL L106262]
                     stop the loop                                                        [IL L106264-106267]

7. else (myTarget set):                                                                   [IL L106289-106291]
       movementTarget = myTarget.position + myTargetEnemyScript.meleePositions[meleeSlot] [IL L106295-106305]
       face(movementTarget)                                                               [IL L106307-106400]
       if Distance(position, movementTarget) > 0.2:                                       [IL L106403-106409]
           movementVector = (movementTarget - position).normalized
           position += movementVector * Time.deltaTime * moveSpeed;  Play("run")          [IL L106413-106439]
       else:
           StartCoroutine(attack())                                                       [IL L106445-106446]

face(p):  if p.x < position.x and localScale.x != -1: localScale.x = -1
          else if p.x > position.x and localScale.x != 1: localScale.x = 1
```

Notes: the arrival radius is `0.4` when idle-following but `0.2` when closing on a target. The auto-target scan only runs while the dog has no target. The dog does not increment the enemy's `attackers` count and does not write itself into `meleeOccupants` anywhere in `PetScript` (it only reads them).

### C.1.6 `chooseSlot()` [IL L106454-106574]

Picks which of the target's melee positions to stand at. `occ = myTargetEnemyScript.meleeOccupants` (a `PartyMember[]`).

| Order | Condition | `meleeSlot` | Citation |
|---|---|---|---|
| 1 | `myTarget.position.x > position.x` and `occ[0] == null` | 0 | [IL L106468-106493] |
| 2 | `myTarget.position.x > position.x` and `occ[1] == null` | 1 | [IL L106496-106521] |
| 3 | `myTarget.position.x > position.x` | 2 | [IL L106524-106540] |
| 4 | (target is not to the right) `occ[1] == null` | 1 | [IL L106543-106554] |
| 5 | `occ[0] == null` | 0 | [IL L106557-106568] |
| 6 | otherwise | 4 | [IL L106571-106572] |

What positions 0/1/2/4 of `meleePositions` are geometrically is defined in `EnemyScript` (out of scope).

### C.1.7 `attack()` coroutine [stub IL L106577-106587, body IL L106684-107122]

1. Face the target (`myTarget.position.x` vs own x, same ±1 rule) [IL L106716-106843].
2. `myAnimation.Play("attack")` [IL L106846-106849]; `chooseSlot()` again [IL L106852-106853].
3. `yield WaitForSeconds(0.26)` [IL L106855-106858].
4. If `myTarget` and `myTargetEnemyScript` both still exist [IL L106862-106871] (otherwise nothing happens):
   - hit spark: `myOwner.myEffects[2].activate(myTarget.position + (0, 0, −0.1), null)` [IL L106874-106891];
   - sound: `n = Random.Range(4, 7)` (4, 5 or 6); `myOwner.mySounds[n].pitch = Random.Range(0.9, 1.1)`; `.Play()` [IL L106893-106915];
   - **Crippling Bite:** if `myOwner.passives[3] == 1`: `myTargetEnemyScript.debuffs[18] = motherBrain.debuffDurations[18]` [IL L106917-106936] (UNVERIFIED mapping: classes.json id 8 power 10 "reducing their damage by 15%"; the debuff's effect and duration are not in this scope);
   - **Normal bite** — if `myOwner.passives[3] != -1`: `myTargetEnemyScript.takeDamage((int)power, Vector3(0,0,0), myOwner)` — no knock-back, no crit roll here [IL L106938-106964];
   - **Thrash** — if `myOwner.passives[3] == -1` (UNVERIFIED mapping: classes.json id 8 power 11), instead of the single hit, loop over `motherBrain.enemyScripts` (stopping at the first null entry [IL L106972-106979, L107096-107100]) and hit every enemy `e` with:
     - `|e.x − pet.x| < 1.8 + e.aoeRadiusBonus` [IL L106982-107012], and
     - `|e.z − pet.z| < 1.25 + e.aoeRadiusBonus` [IL L107015-107045], and
     - `e.health > 0` [IL L107048-107057], and `e.myRenderer.enabled` [IL L107060-107068]:
     - `e.takeDamage((int)power, Vector3(0,0,0), myOwner)` [IL L107071-107091].
     The area is a box centred on the **dog** (not the target), half-width 1.8 in x and 1.25 in z; the primary target is hit only if it is inside the box.
5. The coroutine ends; `RemoteUpdate` resumes when the `"attack"` clip's weight returns to 0, and starts another `attack()` if still within 0.2 of its slot. The attack rate is therefore the length of the `"attack"` animation clip (**not in the IL**), not a timer.

Because damage is passed with `myOwner` as the attacker, everything `EnemyScript.takeDamage` does for that attacker (damage multipliers, threat, kill credit) applies to the Ranger.

### C.1.8 `clearTarget()` [IL L106590-106608]

`myTarget = null; myTargetEnemyScript = null; myAnimation.CrossFade("idle", 0.1)`.

### C.1.9 Who commands the dog (cross-reference, all verified in the IL)

| Where | What | Citation |
|---|---|---|
| `PartyMember.AI` (Ranger branch, `characterClass == 9`), when the Ranger fires its basic shot (`shootArrow`) | if the dog has no target: `petScript.myTarget = owner.myTarget; petScript.myTargetEnemyScript = owner.myTargetEnemyScript` | [IL L80220-80252] |
| `MotherBrain.playerControl`, player's drawn command ends on a target (`targetCandidate != null`; the ally's `myTarget`/`myTargetEnemyScript` are set from it [IL L63557-63577]) | `petScript.myTarget / myTargetEnemyScript` = the Ranger's new target (unconditional, replaces the dog's current target) | [IL L63632-63650] |
| `MotherBrain.playerControl`, player's drawn command ends on empty ground (`targetCandidate == null`; the ally's `movementTarget` = the drawn dot, `AIState = 1` [IL L63494-63517]) | if the dog has no target: `StartCoroutine(delayedPetCommand(ranger))` | [IL L63534-63552] |
| `MotherBrain.delayedPetCommand` coroutine | `yield WaitForSeconds(0.5)`; then if the dog still has no target: `petScript.movementTarget = ranger.movementTarget + (0.5, 0, 0.4)` | [IL L76875-76901] |
| `EnemyScript.clearAllAttackers` / `clearAllMeleeAttackers` | for every party member whose pet targets this enemy: `petScript.clearTarget()` | [IL L22936-22965, L23095-23119] |
| `MotherBrain.levelCompleteSequence` | `petScript.movementTarget = owner.movementTarget + (0.3, 0, 0.5)` | [IL L72770-72799] |
| `MotherBrain.XPBarAnimation` | `petScript.movementTarget += (10, 0, 0)` (runs off to the right) | [IL L75553-75585] |
| `EffectScript.activate` | effects flagged `belongsToPet` copy the dog's facing | [IL L3458-3508] |

## C.2 `HandScript` (IL 32637–32871) — tutorial pointing hand

A hand sprite that demonstrates a tap or a tap-drag-release gesture. It is held by `MotherBrain.tutorialHandScript` [IL L59199, L59567-59568] and driven entirely through its public fields, which `MotherBrain.tutorialDriver` sets (e.g. [IL L66372, L66697]; that method is out of scope).

Fields [IL L32640-32648]: `myAnimation`, `myTransform` (cached in `Awake` [IL L32669-32676]); `myClip = myAnimation["tap"]`, `myClip2 = myAnimation["release"]` [IL L32679-32688]; `startPosition`, `endPosition` (Vector3); `tempVector` (private); `handState` (int); `snapTarget` (Transform).

`Update()` [IL L32693-32859]:

1. If `position.y == -20` the hand is parked: do nothing [IL L32703-32710].
2. `handState` machine:

| `handState` | Behaviour | Citation |
|---|---|---|
| `0` (start) | set `handState = 1`; `myAnimation.Stop(); Play("tap")` | [IL L32713-32727] |
| `1` (pressing / dragging) | once `myClip.normalizedTime >= 1` (tap animation finished): move toward `endPosition` at `3.5` units/s (`position += (endPosition − position).normalized × deltaTime × 3.5`) | [IL L32730-32764] |
| `1` → `2` | when `Distance(position, endPosition) < 0.15`: `Play("release")`, `handState = 2` | [IL L32766-32786] |
| `2` (releasing) | once `myClip2.normalizedTime >= 1`: `handState = 1`; `startPosition = snapTarget.position`; `position = startPosition`; `Stop("tap"); Play("tap")` (loop the demo from the snap target) | [IL L32788-32819] |
| `-1` (tap in place) | `Play("tap")`; when `myClip.normalizedTime >= 1`: `Stop("tap"); Play("tap")` (repeat); if `snapTarget` exists: `position = snapTarget.position` every frame | [IL L32822-32857] |

## C.3 `SpecialMove` (IL 5282–5302)

Plain serializable data class (extends `System.Object`), no logic. Fields [IL L5285-5288]: `moveName` (string), `timer` (float), `cooldownMin` (float), `cooldownMax` (float). The constructor only calls the base constructor [IL L5291-5300]. It is the element type of `EnemyScript.specialMoves` (`SpecialMove[]`, declared [IL L5307], read in `EnemyScript.AI` e.g. [IL L8093-8106]); how the timer/cooldown range is used is in `EnemyScript.AI` (out of scope) and the per-enemy values are inspector data, not in the IL.

## C.4 `Blinker` (IL 33–198) — eye blink on character models

Fields [IL L36-37]: `blinkingBone` (Transform), `blinkCooldown` (float).

- `Awake` [IL L52-70]: `blinkCooldown = Random.Range(1.0, 5.0)`; `blinkingBone = transform.Find("head/blink")`.
- `Update` [IL L73-186]: `blinkCooldown -= Time.deltaTime` [IL L91-94]. When `blinkCooldown <= 0`:
  - if `blinkingBone.localScale.y < 0.5`: set `localScale.y = 1.0`; `blinkCooldown = Random.Range(1.16, 1.19) − 1.0` (i.e. 0.16–0.19 s) [IL L96-146];
  - else: set `localScale.y = 0`; `blinkCooldown = Random.Range(1.0, 5.0)` [IL L149-184].
- So the `head/blink` bone alternates between scale-y 0 for 1–5 s and scale-y 1 for 0.16–0.19 s. UNVERIFIED: scale-y 1 is the "eyes closed" pose (the short phase).

## C.5 `Congrats` (IL 200–604) — party line-up scene

UNVERIFIED: from the class name and `congratsScreenInitialize`, this is the congratulations screen shown after finishing the game; nothing in this class says when the scene is loaded.

Fields [IL L203-207]: `DB` (Database), `playerScripts` (PartyMember[]), `tempGO`, `tempTransform`, `i`.

`Awake` [IL L222-592]:

1. `DB = GameObject.Find("**DATABASE").GetComponent("Database")` [IL L229-234].
2. For each party slot `i` in `0 … DB.party.length−1` with `DB.party[i] != -1` [IL L236-247, L547-557]:
   - instantiate `Resources.Load("Allies/" + DB.partyDB[DB.party[i]].playerName)`; store its `PartyMember` in `playerScripts[i]` [IL L250-284];
   - position by slot: `i == 0` → `(2, 0, 0)`; `i == 1` → `(0.67, 0, 0)`; `i == 2` → `(−0.67, 0, 0)`; otherwise → `(−2, 0, 0)` [IL L286-342];
   - weapon model: let `w = DB.itemDB[ partyDB[party[i]].gear[0] ].ingameModel`; if `w != "none"`: instantiate `Resources.Load(w)` and assign its transform to `playerScripts[i].myWeapon`; additionally, if `playerScripts[i].characterClass == 7` (Barbarian), instantiate the same model again as `myOffhand` (dual wield) [IL L344-443];
   - shield: if `playerName == "Shepherd"` → `myOffhand` = instance of `"Weapons/shield1"` [IL L445-477]; else if `partyDB[...].characterClass == 2` (Knight) → `"Weapons/shield2"` [IL L480-511]; else if `characterClass == 10` (Paladin) → `"Weapons/pallyShield"` [IL L514-544].
3. For every non-null `playerScripts[i]`: `congratsScreenInitialize()` (PartyMember IL 86904) [IL L560-589].

## C.6 `DynamicTexture` (IL 2556–2674) — hi/lo-res texture picker

Fields [IL L2559-2560]: `textureName` (string, ctor default `"textureName"` [IL L2572-2573]), `shared` (bool).

`Awake` [IL L2578-2662]: get this object's `Renderer`. If `Screen.width > 500` **or** `Application.platform == 11` [IL L2594-2600] (11 is `RuntimePlatform.Android` in Unity's enum — engine knowledge, not stated in the IL): load `Resources "DynamicTextures/" + textureName` [IL L2602-2625]; otherwise load `"DynamicTextures/" + textureName + "Lo"` [IL L2628-2655]. The texture is assigned to `renderer.sharedMaterial.mainTexture` if `shared`, else to `renderer.material.mainTexture`. Then `renderer.enabled = true` and the component destroys itself (`Destroy(this)`) [IL L2656-2660].

## C.7 `SceneTransfer` (IL 107130–107178)

`Awake` [IL L107148-107166]: `DB = GameObject.Find("**DATABASE").GetComponent("Database")`; `Application.LoadLevel(DB.transferLevel)` (int scene index). A one-frame "loading" scene that immediately jumps to the scene whose index another script stored in `Database.transferLevel`.

## C.8 `SplashScreen` (IL 107180–107418)

Fields [IL L107183-107185]: `timer` (float), `fader` (Renderer of a full-screen cover quad), `theCam` (Camera).

- `Awake` [IL L107200-107230]: if the screen is exactly 1024×768 or 2048×1536 (width×height): `theCam.orthographicSize = 8`. Always `Application.targetFrameRate = 60`.
- `Update` [IL L107233-107406]:
  1. `timer += Time.deltaTime` [IL L107254-107257].
  2. Skip: if `1 <= timer < 4` and `Input.touchCount > 0`: `timer = 4` [IL L107259-107276].
  3. While `timer < 4`: if `fader` alpha `> 0`: alpha `−= deltaTime × 1.0`; when it reaches `<= 0`, `fader.enabled = false` (fade-in over 1 s) [IL L107278-107344].
  4. When `timer >= 4`: re-enable `fader` if disabled; alpha `+= deltaTime × 0.5` (fade-out over 2 s); when `timer >= 6.1`: `Application.LoadLevel("title")` [IL L107348-107404].

## C.9 `TextPrint` (IL 107420–107584) — typewriter text

Fields [IL L107423-107426]: `targetString` (string), `myTextMesh` (TextMesh, private, fetched in `Awake` [IL L107452-107457]), `internalTimer` (float, private), `characterDelay` (float, private, `0.02` s [IL L107438-107439]).

- `Printout(string whatToPrint)` [IL L107555-107572]: `targetString = whatToPrint`; `myTextMesh.text = ""`; `enabled = true`.
- `Update` [IL L107462-107552]: if `targetString != myTextMesh.text`: `internalTimer += deltaTime`; if `internalTimer >= characterDelay`: subtract `characterDelay` and append the next character `targetString[myTextMesh.text.length]` [IL L107478-107509]; then, if `internalTimer` is still `>= characterDelay` and the text is still incomplete, append one more character the same way (so at most 2 characters per frame) [IL L107511-107545]. When the text equals the target: `enabled = false` [IL L107549-107550]. Rate: one character per 0.02 s (50 chars/s), capped at 2 per frame.

## C.10 `TitleAnimation` (IL 107586–107841) — delayed fade in/out of a title-screen sprite

Fields [IL L107589-107595]: `idleTime` (float, delay before starting), `fadeType` (bool: true = fade in, false = fade out), `startingAlpha` (float, default `1.0` [IL L107607-107608]), `fadeSpeed` (float, alpha per second, default `1.0` [IL L107610-107611]), `loadSandbox` (bool), `destroyMe` (bool), `myRenderer` (Renderer).

`Update` [IL L107616-107829]:

1. If `idleTime > 0`: `idleTime -= deltaTime`; on the frame it reaches `<= 0`: material alpha `= startingAlpha`, `myRenderer.enabled = true`. Return [IL L107640-107689].
2. Else if `fadeType` and alpha `< 1`: alpha `+= deltaTime × fadeSpeed` [IL L107692-107743].
3. Else if `!fadeType` and alpha `> 0`: alpha `−= deltaTime × fadeSpeed` [IL L107746-107798].
4. Else (fade finished): if `loadSandbox`: `Application.LoadLevel(2)` (scene index 2) [IL L107801-107806]; otherwise `enabled = false`, then if `destroyMe`: `Destroy(gameObject)`, else if `!fadeType`: `myRenderer.enabled = false` [IL L107809-107827].

## C.11 `TitleMusic` (IL 107843–108005)

Fields [IL L107846-107847]: `music` (AudioSource), `DB` (Database).

- `Awake` [IL L107862-107881]: `StartCoroutine(startMusic())`; `DB = GameObject.Find("**DATABASE").GetComponent("Database")`.
- `startMusic` coroutine [IL L107964-107999]: `yield WaitForSeconds(0.7)`; then if `DB.musicEnabled`: `music.Play()`.

## C.12 `dynamicbackgroundhandler` (IL 108007–108601) — fits the battle scene to the screen aspect ratio

Fields [IL L108010-108020]: `myTransform` (the background root), `motherBrain`, `actionBar`, `pauseButton`, `leftSideMarker`, `cielingMarker`, `cielingFinder`, `cielingHelper`, `floorMarker`, `edgeMarker` (all Transforms placed in the scene), `theCamera` (Camera). All are inspector references.

`Start()` [IL L108035-108589] runs once, then destroys the component. Each "while" below is a loop that nudges an object until a marker reaches a viewport position (`vp(p)` = `theCamera.WorldToViewportPoint(p)`; viewport x/y run 0…1 across the screen):

1. `motherBrain.draggingThreshold = Screen.width / 24.0` (pixels) [IL L108097-108103].
2. `actionBar.localPosition.x = −1`; `pauseButton.localPosition.x = −1` [IL L108104-108152].
3. iPad resolutions — if the screen is 1024×768 or 2048×1536: `actionBar.localScale = (0.8, 0.8, 0.8)`, `actionBar.localPosition.y = 0.06`, `pauseButton.localScale = (0.8, 0.8, 0.8)` [IL L108154-108208].
4. `while vp(leftSideMarker.position).x > 0`: `myTransform.localScale += (0.05, 0.05, 0.05)` — grow the background until its left marker reaches the left screen edge [IL L108212-108233].
5. `while vp(actionBar.position − (0.4832 × actionBar.localScale.x, 0, 0)).x > 0.02`: `actionBar.localPosition.x += 0.05` [IL L108238-108293].
6. `while vp(pauseButton.position + (0.08456 × pauseButton.localScale.x, 0, 0)).x < 0.98`: `pauseButton.localPosition.x −= 0.05` [IL L108298-108353].
7. `while vp(floorMarker.position).y > 0`: `floorMarker.position.z −= 0.1`; then `motherBrain.floor = floorMarker.position.z` — the nearest-to-camera walkable z (bottom of the screen) [IL L108358-108410].
8. `while vp(edgeMarker.position).x < 1`: `edgeMarker.position.x += 0.1`; then `motherBrain.edge = edgeMarker.position.x + 0.3` — the right-hand x limit of the field (just beyond the right screen edge) [IL L108414-108468].
9. `while vp(cielingMarker.position).y > 1.1`: `myTransform.Translate(0, 0, 0.05)` [IL L108472-108489].
10. `while vp(cielingFinder.position).y < vp(cielingHelper.position).y`: `cielingFinder.position.z += 0.1`; then `motherBrain.cieling = cielingFinder.position.z` — the far (top) walkable z limit [IL L108494-108553].
11. If `motherBrain.DB.tutorial`: `pauseButton.localPosition.x = 100` (hide the pause button in the tutorial) [IL L108555-108584].
12. `Destroy(this)` [IL L108587].

So `MotherBrain.floor`, `MotherBrain.cieling` and `MotherBrain.edge` (the playfield bounds used by movement code, e.g. the pet in C.1.5 step 1) are **computed at run time from the camera and screen aspect**, not constants. (Spelling `cieling` is the game's.)

## C.13 `titleinit` (IL 108603–108666)

No fields. `Start` [IL L108620-108629]: `Application.targetFrameRate = 60`. `Update` [IL L108632-108654]: debug key — if `Input.GetKeyDown("a")`: `print("saves cleared")` and `PlayerPrefs.SetInt("1saveExists", 0)`, `("2saveExists", 0)`, `("3saveExists", 0)` (marks all three slots empty; the slot data itself is not erased).

---

# 7. Uncertain / not determined

- **All per-effect prefab values are missing.** `moveSpeed`, `moveTime`, `hideTime`, `loopTimer`, `impactForce`, `projectileDamageMod` (other than the two code overrides in A.9), `applyDebuff`, `debuffColor`, the sound and follow-up indices and the flags (`projectile`, `canCrit`, `aimedShot`, `apollo`, `flameArrow`, `canMortalStrike`, `canMisdirect`, `dramaticImpact`, `healProjectile`, `dieWithParent`, …) of each concrete effect are serialized on prefabs. They are not in the IL and not in `bh/data`. Which effect prefab sits at which `myEffects[]` index (`PartyMember.myEffectNames`) is also inspector data. Consequently actual projectile speeds, lifetimes and the Aimed Shot damage cap are **not determined**.
- **`MotherBrain.debuffDurations[]`, `debuffMagnitudes[]`, `buffDurations[]`** have no initial values in the IL (inspector arrays) — the durations of debuffs 0, 16, 17, 18 and the poison magnitude factor `debuffMagnitudes[0]` are not determined.
- The meaning of each debuff/buff index beyond what A.6's table states (e.g. what `debuffs[3]`/`debuffs[4]` do to an enemy, what `debuffs[1]` is) lives in `EnemyScript.handleDebuffs` / `PartyMember.handleBuffs`, not read here.
- UNVERIFIED: every "talent name ↔ `passives[n]` value" pairing in this document (see Conventions). They are consistent across six independent checks against classes.json descriptions but the code that writes `passives[]` was not read.
- UNVERIFIED: that `flameArrow` belongs only to Incendiary Arrow, `apollo` only to Apollo Strike, `aimedShot` only to Aimed Shot, and `applyDebuff == 16` to Vile Bolt (the flags are prefab data; the names strongly suggest it).
- Length of the dog's `"attack"` animation clip (its real attack interval) is asset data, not determined. Geometry of `EnemyScript.meleePositions[]` slots 0/1/2/4 not read.
- The numeric convention of the `*FirstVisit` / reminder flags (which value means "already shown") is decided in MenuBrain/MotherBrain, not read here.
- `RuntimePlatform` value 11 = Android is Unity engine knowledge, not from the IL.
- Code/description mismatches found (the code is authoritative): "Critical Aim" says +50% Aimed Shot damage, the code multiplies by `1.4` [IL L3850]; the crit test `Random.Range(0,100) <= critChance` gives `critChance + 1` percent [IL L3863-3869].

## Contradictions with older notes

- `work/non-encounter-systems-research.md` (lines 140, 225) and `work/bh-town-menu-research.md` (line 119) say the merchant holds `Random.Range(3, 10)` / "3–9 items". The IL is `Random.Range(3, 9)` (`ldc.i4.3`, `ldc.i4.s 0x09`) → **3–8 items** [IL L2493-2495].
- Datamine `docs/02-damage-system.md` (line 59) describes `apollo` as "a specific non-critable attack type". Wrong: an `apollo` projectile only *defers* its damage; `onApolloImpact` performs the same crit roll (`canCrit`, ×2) after the slow-motion beat [IL L5155-5193].
- The same docs present the splash/aimed-shot rules as part of the generic "player→enemy roll". Note the precise scoping from the IL: the 75% splash is keyed on the **owner** being a Wizard with `passives[0] == 1` [IL L4027-4039], it ignores `projectileDamageMod`, and it also fires when the primary target was already dead.

# 8. Cross-references

| This scope → | Target (IL line) |
|---|---|
| `EffectScript.damageEnemy` → | `EnemyScript.takeDamage` (18393), `EnemyScript.targetHighestArmorPlayer` (23177), `PartyMember.calculateDamageMultiplier` (86534) |
| `EffectScript.damagePlayer` → | `PartyMember.takeDamage` (81497) |
| `EffectScript.healPlayer` → | `PartyMember.heal` (82423) |
| Incendiary patch damage | `PartyMember.flameArrowPulse` (84589), timers ticked by `PartyMember.handleBuffs` (86039) |
| Enemy debuff ticking | `EnemyScript.handleDebuffs` (22458) |
| Effect pools created by | `PartyMember.createMyEffects` (86613), `EnemyScript.initialize` (5475) |
| Effects/projectiles started by | 170 call sites of `EffectScript.activate` (3372) outside the class, in `PartyMember`, `EnemyScript`, `PetScript` (counted by text search of the IL; the individual launch sites — e.g. the `PartyMember` coroutines `castFireball` 89307, `shootArrow` 89482, `performSpecial` 93226 and `EnemyScript.rangedAttack` 32262 — were not read for this document) |
| `Database.save/load` called by | `MenuBrain.Awake` (33082), `mainInput` (48057), `mapInput` (54841), `startNewGame` (58701), `loadExistingGame` (58856) |
| `Database.populateMerchant` called by | `MenuBrain.startNewGame` (58701), `loadExistingGame` (58856), `MotherBrain.XPBarAnimation` (74751), `defeatSequence` (75663) |
| Pet created/updated by | `PartyMember.initialize` (77121), `PartyMember.remoteUpdate` (78040) |
| Pet commanded by | `PartyMember.AI` (78102), `MotherBrain.playerControl` (61853), `MotherBrain.delayedPetCommand` (76804), `EnemyScript.clearAllAttackers` (22837), `clearAllMeleeAttackers` (22981) |
| `dynamicbackgroundhandler.Start` writes | `MotherBrain.draggingThreshold`, `floor`, `edge`, `cieling` |
| `Congrats.Awake` → | `PartyMember.congratsScreenInitialize` (86904) |

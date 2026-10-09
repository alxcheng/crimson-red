# PartyMember — basic attacks, auto-heals, auto-buffs, counter and pounce landing

**Scope:** class `PartyMember`, the coroutine bodies between `die` and `performSpecial`:
`$castHeal$1802` (IL 88337–88858), `$castBardBuff$1808` (88860–89305), `$castFireball$1817`
(89307–89480), `$shootArrow$1822` (89482–89637), `$counterAttack$1827` (89639–90104),
`$meleeAttack$1838` (90106–92750), `$pounceAttack$1845` (92752–93224). Their public stubs are at
IL 84288–84368 and 84978–84988. Helper `calculateCrit` (87112–87142) and the call sites in `AI`
/ `takeDamage` / `initialize` are summarised where needed to make the numbers usable.

Source: `/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`.
All `[IL Lnnnn]` tags are line numbers in that file.

---

## 1. Summary

Every hero has one automatic "primary action" that fires whenever its `actionTimer` reaches
`primaryActionCooldown` while it has a target:

* **Cleric** auto-heals the ally it is targeting (0.30 s cast, then heal = `power`).
* **Bard** auto-buffs the ally it is targeting (0.23 s cast, then a power/armor song buff).
* **Wizard / Witch** throw a projectile (0.15 s cast, then projectile effect 0 is launched).
* **Ranger** shoots an arrow (`meleeOffset` s draw, then projectile effect 0 is launched).
* **Knight, Rogue, Barbarian, Monk, Paladin** swing in melee (`meleeOffset` s wind-up, then a
  hit for `int(power)`, doubled on a crit). The Barbarian swings twice per attack for half
  damage each. Several passives add on-hit debuffs; the Paladin's Wrath buff adds an AoE.

The same melee coroutine also *delivers* "armed" single-hit specials (Shield Rush, Sneak Attack
type strikes, Reckless Blow, 1000 Palms): `performSpecial` sets a buff slot, and the next
`meleeAttack` run sees the slot, plays a different animation and applies the special's damage
instead of a basic hit. The Monk's 30 % counterattack and the Barbarian's Savage Pounce landing
blast are separate small coroutines in this range.

Damage numbers passed to `EnemyScript.takeDamage` here are *pre-modifier* values; all buff /
debuff multipliers are applied inside `EnemyScript.takeDamage` (outside this scope).

---

## 2. Conventions needed to read the tables

### 2.1 `characterClass` ids = `bh/data/classes.json` id + 1

The code's `characterClass` is 1-based; `classes.json` ids are 0-based.

| `characterClass` | Class (classes.json id) | Evidence in IL |
|---|---|---|
| 1 | Cleric (0) | AI dispatches `castHeal` for class 1 [IL L80021-80029]; ctor default is 1 [IL L77040-77041] |
| 2 | Knight (1) | basic hit applies `debuffs[6]`/`debuffs[7]` from `passives[1]` (Crippling Blows / Sunder Armor pair) [IL L92215-92260] |
| 3 | Rogue (2) | `passives[0]==1` → cooldown ×0.85 (Flurry), `==-1` → crit +20 (Critical Strikes) [IL L77663-77679, L77735-77751] |
| 4 | Wizard (3) | `passives[0]==-1` → `myEffects[0].projectileDamageMod = 1.2` (Impact, +20 %) [IL L77681-77697] |
| 5 | Witch (4) | `passives[0]==1` → `myEffects[0].projectileDamageMod = 1.15` (Piercing Shadow, +15 %) [IL L77699-77715] |
| 6 | Bard (5) | AI dispatches `castBardBuff` for class 6 [IL L80041-80049] |
| 7 | Barbarian (6) | "reckless" animation + self-damage strike [IL L90291-90303, L91124-91163]; `passives[1]==1` → crit +20 (Precision Strikes) [IL L77753-77769] |
| 8 | Monk (7) | 30 % counterattack in `takeDamage` [IL L82354-82396]; `passives[0]==-1` → crit +15 (Tiger Claw) [IL L77833-77849] |
| 9 | Ranger (8) | AI dispatches `shootArrow` for class 9 and hands the target to `petScript` [IL L80220-80252]; `passives[0]==1` → crit +15 (Sniper's Sense) [IL L77815-77831] |
| 10 | Paladin (9) | `passives[0]==-1` → cooldown ×0.9 and moveSpeed ×1.1 (Swift Justice) [IL L77791-77813] |

### 2.2 `passives[]` encoding

`passives` is an `int32[]` [IL L76927]. Each slot holds `-1`, `0` or `1`. From the checks above
(Rogue slot 0: `1` = Flurry = power index 3, `-1` = Critical Strikes = power index 4
[IL L77668-77679, L77740-77751]) the encoding is:

| `passives[k]` | Meaning |
|---|---|
| `0` | nothing chosen in tier k |
| `1` | the **first** passive of the tier's pair was chosen |
| `-1` | the **second** passive of the tier's pair was chosen |

Tier → `classes.json` `whichPower` indices: `passives[0]` ↔ powers 3 / 4; `passives[1]` ↔ powers
7 / 8; `passives[3]` ↔ powers 10 / 11. `passives[2]` is only ever tested `!= 0` in this scope
[IL L89106-89109, L91046-91049, L92096-92099, L82374-82377] and corresponds to power 9 (the
single passive, e.g. Knight "Blitz", Monk "Counter", Rogue "Envenomed Blades", Bard
"Prestissimo"). UNVERIFIED: the tier↔index mapping for slots 1–3 is inferred from matching the
coded effects to the power descriptions in `bh/data/classes.json`; where the code that fills
`passives[]` lives was not read.

### 2.3 Crit roll

`calculateCrit()` [IL L87112-87142]:

```
if critChance > 0 and Random.Range(0, 100) <= critChance:   # int Range → 0..99
    return 2
return 1
```

* Crit multiplier is a flat ×2. With `critChance = c > 0` the real probability is
  `(c + 1) %` because the comparison is `<=` against an integer 0..99 [IL L87123-87129].
* The basic melee hit, the counterattack and the Barbarian swings inline the same roll instead
  of calling `calculateCrit` [IL L92021-92087, L89934-89997, L91945-92012].
* `critChance` sources seen: Rogue Critical Strikes +20 [IL L77748-77751]; Barbarian Precision
  Strikes +20 [IL L77766-77769]; Ranger Sniper's Sense +15 [IL L77828-77831]; Monk Tiger Claw
  +15 [IL L77846-77849]; trinket item id 28 "Rabbit's Foot" adds `Item.power` (5)
  [IL L60677-60707; `bh/data/items.json` id 28]. No base value is set in the ctor (defaults 0)
  [IL L77028-77118].

### 2.4 Damage "roll"

There is **no random variance** in this scope: a basic hit passes `(int)power` (or `(int)(power *
k * crit)`) straight to `EnemyScript.takeDamage(int damage, Vector3 knockback, PartyMember
attacker)`. Float→int is `conv.i4` (truncate toward zero) [e.g. IL L92059-92069].

### 2.5 Attack cadence (who starts these coroutines)

All inside `PartyMember.AI` (IL 78102–81244, outside this scope; only the gate is recorded):

| `AIType` | Who | Timer accumulation per frame while `AIState == 2` and `myTarget` set | Fire condition |
|---|---|---|---|
| 1 | Cleric / Bard | `actionTimer += dt * buffMagnitudes[22]` if `buffs[22] > 0`, else `+= dt` [IL L79874-79905] | `actionTimer >= primaryActionCooldown` and class 1 → `StartCoroutine(castHeal(myTarget))`; else class 6 → `castBardBuff(myTarget)` [IL L80015-80051] |
| 2 | Wizard / Witch / Ranger | same as above (`buffs[22]`) and requires `myTargetEnemyScript.health > 0` [IL L80066-80104] | `actionTimer >= primaryActionCooldown`: class 9 → `shootArrow(myTarget)` (and, if `petScript` exists and has no target, copies `myTarget`/`myTargetEnemyScript` to it); any other class → `castFireball(myTarget)` [IL L80214-80260] |
| 3 | melee classes | requires `myTargetEnemyScript.health > 0`; `+= dt * buffMagnitudes[17]` if `buffs[17] > 0`; else `+= dt * 1.15` if `buffs[16] > 0`; else `+= dt * buffMagnitudes[22]` if `buffs[22] > 0`; else `+= dt` [IL L80304-80382] | `actionTimer >= primaryActionCooldown` → `StartCoroutine(meleeAttack())` [IL L81069-81077] (a preceding check cross-fades to `"idle"` over 0.3 s instead when `basicAction.weight > 0` and distance to `movementTarget` > 0.75 [IL L81040-81065]) |

After any of these, AI cross-fades to `"idle"` (0.15 s) once `basicAction.normalizedTime >= 0.9`
[IL L80053-80062, L80263-80272].

`primaryActionCooldown` (seconds between primary actions):

| Source | Value |
|---|---|
| ctor default | 1.3 [IL L77052-77053] |
| Rogue (class 3) `passives[0]==1` (Flurry) | × 0.85 [IL L77663-77679] |
| Paladin (class 10) `passives[0]==-1` (Swift Justice) | × 0.9 [IL L77791-77807] |
| Trinket gear ids 29–31 (Ring of Haste 5, Tempest Stone 10, Ninja Glove 15) | × `(100 − Item.power) / 100` [IL L60783-60833; `bh/data/items.json` ids 29-31] |

No other write to `primaryActionCooldown` exists in the assembly (grep of `stfld float32
PartyMember::primaryActionCooldown` gives only IL L77053, L77679, L77807, L60833), so any
per-class base value other than 1.3 would have to come from the Unity prefab — see §12.

---

## 3. Fields read or written by this code

| Field | Type | Meaning in this code | Default (ctor) |
|---|---|---|---|
| `characterClass` | int32 | class id, see §2.1 | 1 [IL L77040-77041] |
| `passives` | int32[] | passive choices, see §2.2 | — |
| `buffs` | float32[] | remaining seconds per buff slot; `> 0` = active. Slots used here: 1, 4, 6, 8, 9, 11, 12, 13, 14, 17, 18, 22, 29 (see §10) | — |
| `power` | float32 | attack / heal power; every formula here scales from it | 15 [IL L77061-77062] |
| `critChance` | int32 | crit chance in percent (see §2.3) | 0 (unset) |
| `impactForce` | float32 | knockback magnitude multiplier applied to the unit direction vector | 2 [IL L77067-77068] |
| `meleeOffset` | float32 | wind-up delay in seconds between starting the `"attack"` animation and the hit / arrow release | 0.21 [IL L77100-77101] |
| `primaryActionCooldown` | float32 | seconds of `actionTimer` needed before the next primary action | 1.3 [IL L77052-77053] |
| `actionTimer` | float32 | time since last primary action; reset to 0 when an action starts | — |
| `midAction` | bool | true while a melee swing / counter is committed (blocks counterattack trigger [IL L82384-82385]) | false |
| `noHitReact` | bool | set true while an armed special strike is executing | false |
| `AIState` | int32 | 0 = idle/no target (set on abort), 2 = engaged with `myTarget`, 3 = 1000-Palms flurry in progress / pounce flight, 100 = counterattack lock [IL L88821, L90339-90340, L89748-89749, L81180] | — |
| `bardCoefficient` | float32 | scales the Bard power-song flat bonus added per hit in `EnemyScript.takeDamage` (`damage += bardBuffPower * bardCoefficient` when attacker `buffs[14] > 0`) [IL L18462-18480] | 1 [IL L77094-77095] |
| `bardBuffPower`, `bardBuffArmor` | int32 | flat bonuses written **onto the buffed ally** by the Bard's auto-buff | — |
| `directHealHotMagnitude` | float32 | per-tick magnitude of the Cleric "Holy Embrace" HoT, written onto the healed ally | — |
| `tempAllyScript` | PartyMember | scratch: the ally being healed / buffed | — |
| `myTarget` / `myTargetEnemyScript` | Transform / EnemyScript | current target | — |
| `myTransform`, `myAnimation`, `myWeaponAnimation`, `basicAction` | Unity refs | own transform; body animation; weapon animation; the `AnimationState` of the `"attack"` clip (speed / wrapMode / normalizedTime are manipulated) | — |
| `myEffects` | EffectScript[] | per-class effect / projectile pool, indexed by constants below | — |
| `mySounds` | AudioSource[] | per-class sound list | — |
| `totalMeleeSounds` | int32 | melee swing sounds are `mySounds[0 .. totalMeleeSounds-1]` | 5 [IL L77043-77044] |
| `remainingCooldowns` | float32[] | special cooldown timers (indices 0 and 1 zeroed by Knight Blitz) | — |
| `health` | float32 | own HP (strikes abort when `<= 0`; Reckless Blow costs 25 % of it) | 1000 [IL L77079-77080] |
| `invincible`, `commandPending` | bool | cleared at pounce landing [IL L92835-92840] | — |
| `colorSpeed` | float32 | tint animation speed (set to 0.7 on a bard-buffed ally) | 2 [IL L77049-77050] |
| `motherBrain` | MotherBrain | global battle manager: `buffDurations[]`, `buffMagnitudes[]`, `debuffDurations[]`, `playerScripts[]`, `enemyScripts[]`, `cameraShaker`, `dimBackground`, `disableSpecials` | — |
| EnemyScript fields touched | — | `debuffs[]` (slots 1, 2, 3, 4, 6, 7), `debuffColor`, `mostRecentDebuff`, `likeABoss`, `aoeRadiusBonus`, `health`, `myRenderer.enabled`, `myTransform`, `myAnimation["hitReact"]` | — |

---

## 4. `castHeal(Transform healTarget)` — Cleric auto-heal

Stub [IL L84288-84299]; body `$castHeal$1802.MoveNext` [IL L88406-88854].

```
# state 0                                                   [IL L88418-88471]
tempAllyScript = healTarget.GetComponent("PartyMember")
if tempAllyScript is null:                                   [IL L88430, L88834-88847]
    myTarget = null; AIState = 0; myAnimation.Play("idle"); end
if tempAllyScript.health > 0:                                [IL L88432-88465]
    myAnimation.Stop("cast"); myAnimation.Play("cast")
    myWeaponAnimation.Stop(); myWeaponAnimation.Play("cast")
    actionTimer = 0
yield WaitForSeconds(0.3)                                    [IL L88466-88470]

# state 2                                                   [IL L88473-88832]
tempAllyScript = healTarget.GetComponent("PartyMember")      (re-fetched)
if AIState == 2 and tempAllyScript.health > 0:
    # (a) main heal                                         [IL L88495-88526]
    if passives[0] == -1:  tempAllyScript.heal((int)(power * 1.15), self)   # Discipline
    else:                  tempAllyScript.heal((int)power, self)

    # (b) tier-1 passive                                    [IL L88527-88646]
    if passives[1] == -1:                                    # Holy Embrace (HoT)
        tempAllyScript.buffs[12] = motherBrain.buffDurations[12]
        if   buffs[4] > 0: tempAllyScript.directHealHotMagnitude = power * buffMagnitudes[12] * buffMagnitudes[4]
        elif buffs[6] > 0: tempAllyScript.directHealHotMagnitude = power * buffMagnitudes[12] * buffMagnitudes[6]
        else:              tempAllyScript.directHealHotMagnitude = power * buffMagnitudes[12]
    elif passives[1] == 1:                                   # Empowering Words
        tempAllyScript.buffs[13] = motherBrain.buffDurations[13]

    # (c) feedback                                          [IL L88647-88663]
    myEffects[0].activate(healTarget.position, healTarget)
    mySounds[1].Play()

    # (d) Binding Heal                                      [IL L88664-88703]
    if passives[3] == 1 and healTarget != myTransform:
        self.heal((int)(power * 0.5), self)
        myEffects[1].activate(myTransform.position, myTransform)

    # (e) Passion splash                                    [IL L88704-88800]
    if passives[0] == 1:
        for i in 0 .. motherBrain.playerScripts.length-1:
            p = motherBrain.playerScripts[i]
            if p and p.health > 0
               and Vector3.Distance(p.myTransform.position, healTarget.position) <= 2.5
               and p.myTransform != healTarget:
                p.heal((int)(0.3 * power), self)
elif AIState == 2 and tempAllyScript.health <= 0:            [IL L88804-88831]
    AIState = 0; myAnimation.CrossFade("idle", 0.25); myTarget = null
end
```

Constants: cast delay **0.3 s**; base heal **`int(power)`**; Discipline **×1.15**; Binding Heal
**`int(power × 0.5)`** to self (computed from `power`, not from the actual heal); Passion splash
**`int(0.3 × power)`** within **2.5** world units of the target, excluding the target itself
(the Cleric itself *can* receive the splash); idle cross-fade 0.25 s.

Notes:
* `heal(int amount, PartyMember healer)` is `PartyMember.heal` [IL L82423-82590] (not in this
  scope); any healing-power buff multipliers are applied there, not here.
* The self-heal and splash heals do **not** apply the ×1.15 Discipline factor (they can't
  co-exist with Passion anyway since both live in `passives[0]`; Binding Heal uses plain 0.5)
  [IL L88684-88690, L88778-88786].
* No crit roll is made for heals (`calculateCrit` is not called in this coroutine)
  [IL L88406-88854].
* The Holy Embrace HoT magnitude is multiplied by `buffMagnitudes[4]` or `[6]` when the Cleric
  has buff 4 or buff 6 active. UNVERIFIED: buffs 4 and 6 are the Cleric's Guardian Angel /
  Vengeful Angel self-buffs (they are set in `performSpecial` at IL L94048 / L94224, not read
  here).

---

## 5. `castBardBuff(Transform buffTarget)` — Bard auto-buff

Stub [IL L84302-84313]; body `$castBardBuff$1808.MoveNext` [IL L88932-89301].

```
# state 0                                                   [IL L88956-88996]
tempAllyScript = buffTarget.GetComponent("PartyMember")
if tempAllyScript is null:                                   [IL L88965, L89283-89294]
    AIState = 0; myTarget = null; myAnimation.Play("idle"); end
if tempAllyScript.health > 0:
    myAnimation.Stop("cast"); myAnimation.Play("cast")       # no weapon animation here
    actionTimer = 0
yield WaitForSeconds(0.23)                                   [IL L88992-88995]

# state 2                                                   [IL L89001-89279]
tempAllyScript = buffTarget.GetComponent("PartyMember")
if AIState == 2 and tempAllyScript.health > 0:
    tempAllyScript.buffs[14] = motherBrain.buffDurations[14]             [IL L89022-89031]
    if passives[0] == 1:        # Gusto                                  [IL L89034-89057]
        tempAllyScript.bardBuffPower = (int)(power * 1.5)
        tempAllyScript.bardBuffArmor = (int)power
    elif passives[0] == -1:     # Stoicism                               [IL L89062-89085]
        tempAllyScript.bardBuffPower = (int)power
        tempAllyScript.bardBuffArmor = (int)(power * 1.5)
    else:                                                                [IL L89090-89103]
        tempAllyScript.bardBuffPower = (int)power
        tempAllyScript.bardBuffArmor = (int)power
    if passives[2] != 0:        # Prestissimo                            [IL L89106-89122]
        tempAllyScript.buffs[18] = motherBrain.buffDurations[18]
    if passives[3] == 1:        # Vivace                                 [IL L89125-89142]
        tempAllyScript.buffs[22] = motherBrain.buffDurations[22]
    myEffects[0].activate(buffTarget.position, buffTarget)               [IL L89145-89153]
    mySounds[0].Play()                                                   [IL L89156-89159]
    tempAllyScript.colorSpeed = 0.7                                      [IL L89162-89164]
    tempAllyScript.activateColors()                                      [IL L89167-89168]
    tempAllyScript.myRenderer.material.color.r = 0.4                     [IL L89170-89206]
    tempAllyScript.myRenderer.material.color.b = 0.5                     [IL L89210-89246]
elif AIState == 2 and tempAllyScript.health <= 0:                        [IL L89253-89278]
    AIState = 0; myAnimation.CrossFade("idle", 0.25); myTarget = null
end
```

Constants: cast delay **0.23 s**; buff slot **14** for `buffDurations[14]` seconds; flat bonus
`bardBuffPower = int(bard.power)` (×1.5 with Gusto), `bardBuffArmor = int(bard.power)` (×1.5
with Stoicism). The Bard's own `power` is used, not the target's.

How the buff affects the ally's attacks: in `EnemyScript.takeDamage`, if the attacker has
`buffs[14] > 0`, `damage = (int)(damage + attacker.bardBuffPower * attacker.bardCoefficient)`
[IL L18462-18480]. `bardCoefficient` is 1 normally and is temporarily lowered around multi-hit
attacks so the flat bonus is not over-counted: 0.5 for each of the Barbarian's two swings
[IL L91941-91942, L92015-92016, L92377-92378, L92451-92452] and 0.3 for each of the Monk's 7
flurry hits [IL L90610-90611, L90635-90636].

Vivace's `buffs[22]` on the ally speeds its `actionTimer` by `buffMagnitudes[22]` (see §2.5).

---

## 6. `castFireball(Transform projectileTarget)` — Wizard / Witch basic attack

Stub [IL L84316-84327]; body `$castFireball$1817.MoveNext` [IL L89375-89476]. Used for every
`AIType == 2` hero that is not class 9 [IL L80220-80260].

```
# state 0                                                   [IL L89391-89435]
mySounds[0].pitch = Random.Range(0.8, 1.1)                   # float range
mySounds[0].Play()
myAnimation.Stop("cast"); myAnimation.Play("cast")
myWeaponAnimation.Stop(); myWeaponAnimation.Play("cast")
actionTimer = 0
yield WaitForSeconds(0.15)

# state 2                                                   [IL L89439-89469]
if AIState == 2:
    myEffects[0].activate(myTransform.position + Vector3(myTransform.localScale.x * 0.8, 0, 0),
                          projectileTarget)
end
```

* Cast delay **0.15 s**; spawn point is 0.8 units in front of the caster (`localScale.x` is
  ±1 = facing) [IL L89450-89466].
* No damage is computed here. `myEffects[0]` is the projectile (`EffectScript`); it flies to
  `projectileTarget` and applies damage, crit and any splash itself (class `EffectScript`,
  IL 2676–5280, reads `PartyMember.critChance` at IL L3859-3868 and L5158-5168 — not in this
  scope). The only basic-attack modifiers set from PartyMember are
  `myEffects[0].projectileDamageMod = 1.2` (Wizard Impact) [IL L77681-77697] and `= 1.15` (Witch
  Piercing Shadow) [IL L77699-77715].
* If the hero stopped being in `AIState == 2` during the 0.15 s, nothing is launched, but
  `actionTimer` was already reset (the attack is lost) [IL L89427-89441].

---

## 7. `shootArrow(Transform projectileTarget)` — Ranger basic attack

Stub [IL L84330-84341]; body `$shootArrow$1822.MoveNext` [IL L89550-89633].

```
# state 0                                                   [IL L89566-89593]
mySounds[0].Play()                                           # no pitch randomisation
myAnimation.Stop("attack"); myAnimation.Play("attack")
actionTimer = 0
yield WaitForSeconds(meleeOffset)

# state 2                                                   [IL L89597-89626]
if AIState == 2:
    myEffects[0].activate(myTransform.position + Vector3(myTransform.localScale.x * 0.4, 0, -0.1),
                          projectileTarget)
end
```

* Draw delay = **`meleeOffset`** seconds (prefab value; ctor default 0.21) [IL L89590-89591].
* Spawn offset `(0.4 × facing, 0, −0.1)` [IL L89612-89623].
* Damage / crit / Mortal Shots etc. are handled by the projectile `EffectScript` (not in scope).
* The dog companion gets the Ranger's target at the moment the shot is *started*, in `AI`
  [IL L80232-80252].

---

## 8. `meleeAttack()` — melee basic attack and armed-special strikes

Stub [IL L84358-84368]; body `$meleeAttack$1838.MoveNext` [IL L90168-92746]. Hoisted locals:
`isBasicAttack` (bool), `tempVector` (Vector3 knockback direction), `i`, `randomMeleeSound`
[IL L90146-90149]. Resume-state table [IL L90183-90200].

### 8.1 Phase 1 — choose animation and wait the wind-up

```
midAction = true; actionTimer = 0; isBasicAttack = true                  [IL L90203-90212]
if buffs[1] > 0 or buffs[11] > 0: noHitReact = true                      [IL L90215-90234]

if buffs[11] > 0:                                                         [IL L90237-90260]
    myAnimation.Play("shieldRush");  yield 0.066;  isBasicAttack = false
elif buffs[1] > 0 or buffs[8] > 0 or buffs[9] > 0:                        [IL L90264-90287]
    if characterClass == 7:                                               [IL L90291-90311]
        myAnimation.Play("reckless"); yield 0.366; isBasicAttack = false
    elif characterClass == 8:                                             [IL L90315-90341]
        myAnimation.Play("attack");   yield meleeOffset; isBasicAttack = false; AIState = 3
    else:                                                                 [IL L90345-90358]
        myAnimation.Play("sneakAttack"); yield 0.366; isBasicAttack = false
elif buffs[17] > 0:                              # hasted basic attack    [IL L90363-90417]
    myAnimation.Stop("attack"); myAnimation.Play("attack")
    if basicAction.speed != buffMagnitudes[17]: basicAction.speed = buffMagnitudes[17]
    yield WaitForSeconds(meleeOffset / buffMagnitudes[17])
else:                                            # normal basic attack    [IL L90423-90451]
    myAnimation.Stop("attack"); myAnimation.Play("attack")
    if basicAction.speed != 1: basicAction.speed = 1
    yield WaitForSeconds(meleeOffset)
```

| Case | Animation | Wind-up (s) | Citation |
|---|---|---|---|
| `buffs[11] > 0` (Shield Rush strike) | `"shieldRush"` | 0.066 | [IL L90246-90253] |
| armed strike, class 7 Barbarian | `"reckless"` | 0.366 | [IL L90297-90304] |
| armed strike, class 8 Monk | `"attack"` | `meleeOffset` | [IL L90321-90330] |
| armed strike, any other class | `"sneakAttack"` | 0.366 | [IL L90345-90352] |
| basic attack with `buffs[17] > 0` | `"attack"` at speed `buffMagnitudes[17]` | `meleeOffset / buffMagnitudes[17]` | [IL L90372-90415] |
| basic attack | `"attack"` at speed 1 | `meleeOffset` | [IL L90423-90449] |

### 8.2 Phase 2 — common prologue after the wind-up

```
if characterClass != 7 and isBasicAttack: midAction = false               [IL L90455-90466]
tempVector = Vector3.zero                                                 [IL L90468-90469]
if myTarget: tempVector = (myTarget.position - myTransform.position).normalized   [IL L90472-90489]
```

(The Barbarian keeps `midAction` true until after his second swing, §8.4.)

Then exactly one of the following branches runs, tested in this order. Every branch except H
requires `isBasicAttack == false`; branch H requires `isBasicAttack == true`.

### 8.3 Armed-special branches (A–G)

Shared notation: `E` = `myTargetEnemyScript`; `crit` = `calculateCrit()` (1 or 2); `dir` =
`tempVector`; `E.takeDamage(dmg, knockback, self)`.

| Branch | Condition (all must hold) | What it does | Citation |
|---|---|---|---|
| **A — Monk 1000-hit flurry** | `buffs[1] > 0`, `myTarget`, `E`, `AIState == 3`, class 8, `health > 0` | see §8.3.1 | [IL L90492-90867] |
| **B — Monk flurry, target lost** | `buffs[1] > 0`, `AIState == 3`, class 8, `health > 0` (A failed because target/E is gone) | `AIState = 2`; end. (`buffs[1]` is *not* cleared, time scale untouched.) | [IL L90871-90905] |
| **C — Shield Rush hit** | `myTarget`, `E`, `AIState == 2`, `buffs[11] > 0`, `health > 0` | see §8.3.2 | [IL L90909-91083] |
| **D — Barbarian Reckless Blow** | `myTarget`, `E`, `AIState == 2`, `buffs[1] > 0`, class 7, `health > 0` | see §8.3.3 | [IL L91087-91370] |
| **E — generic armed strike, slot 1** | `myTarget`, `E`, `AIState == 2`, `buffs[1] > 0`, `health > 0` (class is neither 7 nor 8 in practice) | see §8.3.4 with `k = 1` | [IL L91374-91552] |
| **F — generic armed strike, slot 9** | same with `buffs[9] > 0` | see §8.3.4 with `k = 9` | [IL L91556-91734] |
| **G — debuffing strike, slot 8** | same with `buffs[8] > 0` | see §8.3.5 | [IL L91738-91878] |

If the hero is not basic-attacking and none of A–G matches (e.g. target died during the
wind-up), nothing happens and the coroutine ends; the armed buff slot stays set so the strike is
retried on the next `meleeAttack` [IL L91882-91924 fall through to L92741].

#### 8.3.1 Branch A — Monk flurry ("1000 Palms", `buffs[1]`, class 8)

```
buffs[1] = 0                                                              [IL L90536-90540]
Time.timeScale = 0.05                                                     [IL L90541-90542]
mySounds[10].Play()                                                       [IL L90545-90548]
basicAction.speed = 40; basicAction.wrapMode = 2   # WrapMode.Loop        [IL L90551-90559]
motherBrain.dimBackground = true                                          [IL L90562-90564]
myEffects[9].activate(myTarget.position + Vector3(0, 0.1, -0.2), null)    [IL L90567-90581]
motherBrain.cameraShaker.Stop(); .Play("powerUpShake")                    [IL L90584-90593]
for i in 0..6:                                     # 7 hits               [IL L90595-90704]
    if E:
        bardCoefficient = 0.3
        E.takeDamage((int)(power * 0.3 * crit), dir * 0.1, self)          [IL L90614-90632]
        bardCoefficient = 1
        E.myAnimation["hitReact"].speed = 20
        mySounds[Random.Range(0, 5)].Play()        # int range → index 0..4
        if i == 2 or i == 4 or i == 6: cameraShaker.Stop(); .Play("powerUpShake")
        basicAction.normalizedTime = 0.1
        yield WaitForSeconds(0.008)                # scaled time; timeScale is 0.05
myAnimation.Stop("attack"); myAnimation.Play("attack")                    [IL L90708-90716]
basicAction.speed = 7; basicAction.wrapMode = 8    # WrapMode.ClampForever [IL L90719-90726]
yield WaitForSeconds(0.03)                                                [IL L90728-90731]
if myTarget: myEffects[10].activate(myTarget.position + Vector3(0, 0.1, -0.2), null)  [IL L90736-90756]
cameraShaker.Stop(); cameraShaker.Play("shake")                           [IL L90759-90768]
basicAction.speed = 1                                                     [IL L90771-90773]
if E: E.takeDamage((int)(power * 1.4 * crit), dir * impactForce * 3, self)   # finisher  [IL L90776-90805]
mySounds[6].Play(); Time.timeScale = 1                                    [IL L90808-90813]
if E: E.myAnimation["hitReact"].speed = 1                                 [IL L90816-90828]
motherBrain.dimBackground = false                                         [IL L90831-90833]
if E and E.debuffs[3] <= 1.7:                                             [IL L90836-90862]
    E.debuffs[3] = 1.7; E.debuffs[4] = 0.2         # knock-down pair, see §11
AIState = 2                                                               [IL L90865-90866]
```

Totals: 7 × `int(power × 0.3 × crit)` + 1 × `int(power × 1.4 × crit)`; each hit rolls crit
separately. Knockback per flurry hit `dir × 0.1`; finisher `dir × impactForce × 3`.

#### 8.3.2 Branch C — Shield Rush hit (`buffs[11]`)

```
Time.timeScale = 0.1; motherBrain.dimBackground = true; mySounds[6].Play()   [IL L90945-90957]
E.takeDamage((int)(power * buffMagnitudes[11] * crit), dir * impactForce * 1.6, self)  [IL L90960-90987]
E.debuffs[3] = motherBrain.debuffDurations[3]; E.debuffs[4] = 0.3            [IL L90990-91006]
cameraShaker.Stop(); .Play("powerUpShake")                                   [IL L91009-91018]
myEffects[6].activate(myTarget.position + Vector3(0, 0, -0.05), null)        [IL L91021-91036]
buffs[11] = 0                                                                [IL L91039-91043]
if passives[2] != 0: remainingCooldowns[0] = 0; remainingCooldowns[1] = 0    # Blitz  [IL L91046-91064]
yield WaitForSeconds(0.07)                         # at timeScale 0.1        [IL L91066-91069]
motherBrain.dimBackground = false; Time.timeScale = 1; noHitReact = false    [IL L91074-91082]
```

There is no class check on this branch; UNVERIFIED: only the Knight ever gets `buffs[11]` (set
in `performSpecial` at IL L96059).

#### 8.3.3 Branch D — Barbarian Reckless Blow (`buffs[1]`, class 7)

```
Time.timeScale = 0.1; motherBrain.dimBackground = true                       [IL L91129-91135]
self.takeDamage((int)(health * 0.25), dir * impactForce * -2, E)             # always  [IL L91148-91164 / L91220-91236 / L91272-91288]
if passives[3] == 1:      # Blunt Trauma                                     [IL L91138-91205]
    E.takeDamage((int)(4 * power * crit), dir * impactForce * 3, self)
    E.debuffs[3] = 3.5; E.debuffs[4] = 0.15
elif passives[3] == -1:   # Dismemberment                                    [IL L91210-91265]
    E.takeDamage((int)(5 * power * 1.2 * crit), dir * impactForce * 3, self)
else:                                                                        [IL L91272-91315]
    E.takeDamage((int)(5 * power * crit), dir * impactForce * 3, self)
mySounds[6].Play()                                                           [IL L91318-91321]
myEffects[3].activate(myTransform.position, null)                            [IL L91324-91332]
cameraShaker.Stop(); .Play("powerUpShake")                                   [IL L91335-91344]
buffs[1] = 0                                                                 [IL L91347-91351]
yield WaitForSeconds(0.04)                                                   [IL L91353-91356]
motherBrain.dimBackground = false; Time.timeScale = 1; noHitReact = false    [IL L91361-91369]
```

Note the Blunt Trauma variant uses a **4×** multiplier while the other two use **5×**
[IL L91168-91173 vs L91240-91245, L91292-91297]. Self-damage is 25 % of *current* health and
goes through the Barbarian's own `takeDamage` (with the enemy as attacker and a knockback of
`−2 × impactForce` along `dir`, i.e. pushed back away from the target).

#### 8.3.4 Branches E / F — generic armed strike (`buffs[k]`, k = 1 or 9)

```
mySounds[8].Play(); Time.timeScale = 0.1; motherBrain.dimBackground = true   [IL L91412-91422 / L91594-91604]
if passives[3] == 1:   dmg = (int)(power * buffMagnitudes[k] * 1.4 * crit)   [IL L91425-91451 / L91607-91633]
else:                  dmg = (int)(power * buffMagnitudes[k] * crit)         [IL L91468-91484 / L91650-91666]
E.takeDamage(dmg, dir * impactForce * 2, self)                               [IL L91453-91463, L91486-91496 / L91635-91645, L91668-91678]
cameraShaker.Stop(); .Play("powerUpShake")                                   [IL L91499-91508 / L91681-91690]
myEffects[1].activate(myTarget.position + Vector3(0, 0, -0.05), null)        [IL L91511-91526 / L91693-91708]
buffs[k] = 0                                                                 [IL L91529-91533 / L91711-91715]
yield WaitForSeconds(0.07)                                                   [IL L91535-91538 / L91717-91720]
motherBrain.dimBackground = false; Time.timeScale = 1; noHitReact = false    [IL L91543-91551 / L91725-91733]
```

UNVERIFIED: these are the Rogue's Sneak Attack (`buffs[1]`, "250 %") and Shadowstep
(`buffs[9]`, "350 %"), with `passives[3] == 1` = Lethality (+40 %, matches the ×1.4). The
multipliers themselves are `buffMagnitudes[1]` / `buffMagnitudes[9]`, whose values are not in
the IL (§11, §12). The slots are armed in `performSpecial` at IL L96094 and L96324.

#### 8.3.5 Branch G — debuffing strike (`buffs[8]`)

```
mySounds[1].pitch = Random.Range(0.85, 1.15); mySounds[1].Play()             [IL L91776-91788]
E.takeDamage((int)(power * crit), dir * impactForce * 2, self)               [IL L91791-91812]
E.debuffs[2] = motherBrain.debuffDurations[2]                                [IL L91815-91824]
E.debuffColor = Color(0.4, 0.26, 0.07); E.mostRecentDebuff = 2               [IL L91827-91837]
myEffects[9].activate(myTarget.position + Vector3(0, 0, -0.02), myTarget)    [IL L91840-91857]
buffs[8] = 0                                                                 [IL L91860-91864]
yield WaitForSeconds(0.2)                                                    [IL L91866-91869]
mySounds[5].Play()                                                           [IL L91874-91877]
```

No time-scale change, no dim, and `noHitReact` is not touched here. UNVERIFIED: this is the
Rogue's Expose Weakness (armed at IL L96119; enemy debuff slot 2 = "damage taken +50 %").

### 8.4 Branch H — the basic melee hit

Conditions (all) [IL L91882-91931]: `myTarget` and `myTargetEnemyScript` exist; `AIState == 2`;
`basicAction.weight == 1` (the attack clip is fully blended in — the swing was not interrupted
by a move/other animation); `basicAction.normalizedTime >= 0.8 * meleeOffset /
basicAction.length`; `isBasicAttack`; `health > 0`. If any fails the swing whiffs silently (no
damage, no sound) and the coroutine ends; `actionTimer` was already reset in phase 1.

```
# --- damage ---------------------------------------------------------------
if characterClass == 7:                         # Barbarian, first swing   [IL L91935-92016]
    bardCoefficient = 0.5
    if critChance > 0 and Random.Range(0,100) <= critChance:
           E.takeDamage((int)power,         dir * impactForce, self)       # crit
    else:  E.takeDamage((int)(power * 0.5), dir * impactForce, self)
    bardCoefficient = 1
else:                                                                      [IL L92021-92087]
    if critChance > 0 and Random.Range(0,100) <= critChance:
           E.takeDamage((int)(power * 2), dir * impactForce, self)         # crit
    else:  E.takeDamage((int)power,       dir * impactForce, self)

# --- on-hit passives ------------------------------------------------------
if characterClass == 3 and passives[2] != 0                # Rogue, Envenomed Blades   [IL L92090-92162]
   and Random.Range(1, 101) <= 5 and not E.likeABoss:
    if E.debuffs[1] <= 3:
        E.debuffs[1] = 3
        E.debuffColor = Color(0.26, 0.18, 0.34); E.mostRecentDebuff = 1
    myEffects[6].activate(myTarget.position + Vector3(0, 0, -0.05), myTarget)   # even if not refreshed

if characterClass == 8 and passives[0] == 1                # Monk, Iron Hand           [IL L92165-92212]
   and Random.Range(1, 101) <= 5 and not E.likeABoss and E.debuffs[3] <= 3:
    E.debuffs[3] = 3; E.debuffs[4] = 0.15

if characterClass == 2:                                    # Knight                    [IL L92215-92260]
    if   passives[1] == -1: E.debuffs[6] = motherBrain.debuffDurations[6]
    elif passives[1] ==  1: E.debuffs[7] = motherBrain.debuffDurations[7]

# --- feedback -------------------------------------------------------------
myEffects[0].activate(myTarget.position + Vector3(0, 0, -0.05), null)      [IL L92263-92278]
randomMeleeSound = Random.Range(0, totalMeleeSounds)                       [IL L92280-92285]
mySounds[randomMeleeSound].pitch = Random.Range(0.95, 1.05)                [IL L92288-92295]
mySounds[randomMeleeSound].Play()                                          [IL L92298-92302]

# --- Barbarian second swing ----------------------------------------------
if characterClass == 7:                                                    [IL L92305-92485]
    if buffs[17] > 0: yield WaitForSeconds(meleeOffset / buffMagnitudes[17])   [IL L92311-92331]
    else:             yield WaitForSeconds(meleeOffset)                        [IL L92337-92342]
    midAction = false                                                          [IL L92347-92348]
    if myTarget and E and AIState == 2 and basicAction.weight == 1:            [IL L92351-92373]
        bardCoefficient = 0.5
        (same crit rule as first swing: crit → (int)power, else (int)(power*0.5),
         knockback dir * impactForce)                                          [IL L92377-92448]
        bardCoefficient = 1
        myEffects[1].activate(myTarget.position + Vector3(0, 0, -0.05), null)  [IL L92455-92470]
        mySounds[0].pitch = Random.Range(0.85, 1.15); mySounds[0].Play()       [IL L92473-92485]

# --- Paladin Wrath chain --------------------------------------------------
if characterClass == 10 and buffs[29] > 0 and myTarget:                    [IL L92488-92738]
    actionTimer -= 0.3                                                     [IL L92511-92514]
    myEffects[12].activate(myTarget.position, null)                        [IL L92517-92525]
    myEffects[13].activate(myTarget.position, null)                        [IL L92528-92536]
    mySounds[9].pitch = Random.Range(0.95, 1.05); mySounds[9].Play()       [IL L92539-92551]
    for i in 0 .. motherBrain.enemyScripts.length-1:
        e = motherBrain.enemyScripts[i]
        if e (non-null; null entries are skipped)
           and |e.x - myTarget.x| < 2.0 + e.aoeRadiusBonus                 [IL L92569-92598]
           and |e.z - myTarget.z| < 1.5 + e.aoeRadiusBonus                 [IL L92602-92631]
           and e.health > 0 and e.myRenderer.enabled:                      [IL L92635-92654]
            if e.myTransform != myTarget: tempVector = Vector3(0,0,0)      [IL L92658-92679]
            else: tempVector = (e.position - myTarget.position).normalized # zero-length → zero  [IL L92684-92699]
            e.takeDamage((int)(power * 1.25), tempVector * impactForce * 3, self)   [IL L92702-92724]
```

Notes on branch H:

* **Barbarian** (class 7): two swings per attack, each `int(power × 0.5)` (crit: `int(power)`),
  `meleeOffset` apart (shortened by `buffMagnitudes[17]` under haste). Each swing rolls crit
  independently. The second swing does not re-check `normalizedTime`, `health` or
  `isBasicAttack`, and does not re-compute `dir`. On-hit passives and the first-hit effect/sound
  happen once, between the swings.
* **Rogue Envenomed Blades**: 5 % per basic hit (`Random.Range(1,101) <= 5`), never on bosses;
  sets enemy `debuffs[1]` to 3 (seconds) only if it is currently ≤ 3.
* **Monk Iron Hand**: 5 % per basic hit, never on bosses, only if `debuffs[3] <= 3`; sets
  `debuffs[3] = 3`, `debuffs[4] = 0.15`.
* **Knight**: every basic hit re-applies the full-duration debuff — slot 7 for `passives[1] == 1`
  (first of the pair = Crippling Blows), slot 6 for `passives[1] == -1` (second = Sunder Armor).
  No chance roll. UNVERIFIED: the slot↔name assignment follows the §2.2 pair-order rule; the
  magnitudes live in `EnemyScript` / `MotherBrain`.
* **Paladin Wrath** (`buffs[29]`): every *landed* basic hit also hits every living, visible
  enemy within a 2.0 (x) × 1.5 (z) box (each widened by that enemy's `aoeRadiusBonus`) centred on
  the **target** — including the primary target again — for `int(power × 1.25)`, with no crit
  roll. Because of the inverted test at IL L92663-92679 the knockback vector is zero for every
  enemy (non-targets get an explicit zero vector; the target gets `normalized(0)` = zero). It
  also subtracts 0.3 from `actionTimer` [IL L92511-92514]. Since `actionTimer` counts *up*
  toward `primaryActionCooldown` (§2.5) and was reset to 0 at the start of this swing, the
  subtraction makes the next swing come 0.3 s (of timer time) **later** while Wrath is active.
* The crit roll for basic hits is inlined: `critChance > 0` and `Random.Range(0,100) <=
  critChance` [IL L92021-92031].
* No life-steal, power buffs or enemy armor are handled here — see `EnemyScript.takeDamage`.

### 8.5 Per-class basic-attack table

`mo` = `meleeOffset` (prefab value, ctor default 0.21 s); `cd` = `primaryActionCooldown` (ctor
default 1.3 s, see §2.5); `h17` = `buffMagnitudes[17]` when `buffs[17] > 0`, else 1.

| characterClass | Class | Coroutine | Animation | Delay before effect | Effect at the delay | Crit | Per-class extras |
|---|---|---|---|---|---|---|---|
| 1 | Cleric | `castHeal` | `"cast"` (body + weapon) | 0.30 s | heal ally `int(power)` | none | Discipline ×1.15; Passion 30 % splash r 2.5; Holy Embrace HoT (`buffs[12]`); Empowering Words (`buffs[13]`); Binding Heal 50 % self (§4) |
| 2 | Knight | `meleeAttack` | `"attack"` | `mo / h17` | `int(power)` to target, knockback `dir × impactForce` | ×2 | every hit: `debuffs[7]` or `debuffs[6]` = `debuffDurations[...]` by `passives[1]` |
| 3 | Rogue | `meleeAttack` | `"attack"` | `mo / h17` | `int(power)` | ×2 (Critical Strikes +20) | Flurry `cd × 0.85`; Envenomed Blades 5 % → `debuffs[1] = 3` (not bosses) |
| 4 | Wizard | `castFireball` | `"cast"` (body + weapon) | 0.15 s | launch `myEffects[0]` from `(+0.8·facing, 0, 0)` | in projectile | Impact: `projectileDamageMod = 1.2` |
| 5 | Witch | `castFireball` | `"cast"` (body + weapon) | 0.15 s | launch `myEffects[0]` from `(+0.8·facing, 0, 0)` | in projectile | Piercing Shadow: `projectileDamageMod = 1.15` |
| 6 | Bard | `castBardBuff` | `"cast"` (body only) | 0.23 s | ally `buffs[14]`, `bardBuffPower/Armor = int(power)` | none | Gusto power ×1.5; Stoicism armor ×1.5; Prestissimo `buffs[18]`; Vivace `buffs[22]` (§5) |
| 7 | Barbarian | `meleeAttack` | `"attack"` | `mo / h17`, then second swing after another `mo / h17` | 2 × `int(power × 0.5)` | each swing: crit → `int(power)` (Precision Strikes +20) | `bardCoefficient = 0.5` per swing; `midAction` held through both swings |
| 8 | Monk | `meleeAttack` | `"attack"` | `mo / h17` | `int(power)` | ×2 (Tiger Claw +15) | Iron Hand 5 % → `debuffs[3] = 3`, `debuffs[4] = 0.15` (not bosses); 30 % counterattack (§9) |
| 9 | Ranger | `shootArrow` | `"attack"` | `mo` | launch `myEffects[0]` from `(+0.4·facing, 0, −0.1)` | in projectile (Sniper's Sense +15) | dog gets the target |
| 10 | Paladin | `meleeAttack` | `"attack"` | `mo / h17` | `int(power)` | ×2 | Swift Justice `cd × 0.9`; Wrath (`buffs[29]`): AoE `int(power × 1.25)` box 2.0 × 1.5 around target, `actionTimer −= 0.3` |

Citations for the table rows: §4–§8.4 above and §2.5.

---

## 9. `counterAttack(EnemyScript whoHitMe)` — Monk counter

Trigger (in `PartyMember.takeDamage`, [IL L82354-82398]): `characterClass == 8`, attacker not
`invincible`, `AIState == 2`, `health > 0`, `passives[2] != 0`, attacker `isMelee`, not
`midAction`, and `Random.Range(1, 101) <= 30` (30 %).

Stub [IL L84344-84355]; body `$counterAttack$1827.MoveNext` [IL L89713-90100].

```
# state 0
midAction = true; AIState = 100                                             [IL L89742-89749]
# face the attacker                                                         [IL L89750-89887]
if myTransform.position.x > whoHitMe.myTransform.position.x and localScale.x != -1:
    localScale.x = -1; updateHealthBar(1)
elif myTransform.position.x <= whoHitMe.position.x and localScale.x != 1:
    localScale.x = 1;  updateHealthBar(1)
basicAction.speed = 1.75                                                    [IL L89888-89892]
myAnimation.Stop("attack"); myAnimation.Play("attack")                      [IL L89893-89902]
yield WaitForSeconds(meleeOffset / 1.75)                                    [IL L89906-89912]

# state 2
tempVector = (whoHitMe.myTransform.position - myTransform.position).normalized   [IL L89915-89931]
if critChance > 0 and Random.Range(0,100) <= critChance:                    [IL L89932-89963]
       whoHitMe.takeDamage((int)(power * 2), tempVector * impactForce, self)
else:  whoHitMe.takeDamage((int)power,       tempVector * impactForce, self)    [IL L89966-89997]
if passives[0] == 1 and Random.Range(1,101) <= 5 and whoHitMe.debuffs[3] <= 3:  # Iron Hand  [IL L89998-90031]
    whoHitMe.debuffs[3] = 3; whoHitMe.debuffs[4] = 0.15
myEffects[0].activate(whoHitMe.myTransform.position + Vector3(0, 0, -0.05), null)   [IL L90032-90048]
randomMeleeSound = Random.Range(0, totalMeleeSounds)                        [IL L90050-90056]
mySounds[randomMeleeSound].pitch = Random.Range(0.95, 1.05); .Play()        [IL L90057-90073]
yield WaitForSeconds(0.35)                                                  [IL L90074-90078]

# state 3
midAction = false; AIState = 2; basicAction.speed = 1                       [IL L90081-90093]
```

* Counter = one normal basic hit (`int(power)`, ×2 on crit) at 1.75× animation speed, wind-up
  `meleeOffset / 1.75`, then a 0.35 s lock in `AIState = 100`.
* It does **not** reset or consume `actionTimer`, so it is a free extra attack.
* Unlike the basic hit, the Iron Hand roll here has **no `likeABoss` check** [IL L89998-90031 vs
  L92185-92188].
* It hits `whoHitMe` regardless of the Monk's current `myTarget`, and has no range, target-alive
  or `health > 0` re-check after the wait.

---

## 10. `pounceAttack()` — Barbarian Savage Pounce landing

Started from `AI` when `AIState == 3`: the hero is moved toward `pounceDestination` at
`pounceSpeed` while `pounceTimer > 0`; when the timer reaches ≤ 0, `StartCoroutine(pounceAttack())`
[IL L81180-81232]. Stub [IL L84978-84988]; body `$pounceAttack$1845.MoveNext` [IL L92812-93220].

```
invincible = false; commandPending = false                                  [IL L92835-92840]
myEffects[5].activate(myTransform.position, null)                           [IL L92843-92851]
myEffects[6].activate(myTransform.position, null)                           [IL L92854-92862]
mySounds[7].Play()                                                          [IL L92865-92868]
motherBrain.cameraShaker.Stop(); .Play("shake")                             [IL L92871-92880]
for i in 0 .. motherBrain.enemyScripts.length-1:                            [IL L92882-93163]
    e = motherBrain.enemyScripts[i]
    if e is null: break            # i is set to length → loop ends at first empty slot  [IL L92891-92897, L93146-93149]
    if |e.x - my.x| < 1.6 + e.aoeRadiusBonus                                [IL L92901-92930]
       and |e.z - my.z| < 1.2 + e.aoeRadiusBonus                            [IL L92934-92963]
       and e.health > 0 and e.myRenderer.enabled:                           [IL L92967-92986]
        tempVector = (e.position - myTransform.position).normalized         [IL L92991-93006]
        if passives[3] == 1:       # Blunt Trauma                           [IL L93009-93066]
            e.takeDamage((int)(2.5 * power * crit), tempVector * impactForce * 2, self)
            e.debuffs[3] = 3.5; e.debuffs[4] = 0.15
        elif passives[3] == -1:    # Dismemberment                          [IL L93071-93108]
            e.takeDamage((int)(2.5 * power * 1.2 * crit), tempVector * impactForce * 2, self)
        else:                                                               [IL L93113-93140]
            e.takeDamage((int)(2.5 * power * crit), tempVector * impactForce * 2, self)
yield WaitForSeconds(0.14)                                                  [IL L93166-93169]
Time.timeScale = 0.1                                                        [IL L93172-93173]
yield WaitForSeconds(0.06)                                                  [IL L93175-93178]
Time.timeScale = 1; motherBrain.disableSpecials = false                     [IL L93181-93187]
yield WaitForSeconds(0.1)                                                   [IL L93189-93192]
motherBrain.dimBackground = false                                           [IL L93197-93199]
yield WaitForSeconds(0.52)                                                  [IL L93201-93204]
noHitReact = false                                                          [IL L93209-93210]
returnToNormalFromPounce()                                                  [IL L93213]
```

* AoE box centred on the **Barbarian**: |Δx| < 1.6, |Δz| < 1.2 (each + enemy `aoeRadiusBonus`).
* Damage `int(2.5 × power × crit)`; Dismemberment ×1.2; Blunt Trauma adds knock-down
  `debuffs[3] = 3.5`, `debuffs[4] = 0.15` (and, unlike Reckless Blow, keeps the full 2.5×).
  Each enemy rolls its own crit.
* Loop quirk: a null entry in `enemyScripts` terminates the scan (the melee Wrath loop in §8.4
  merely skips nulls).

---

## 11. Buff / debuff slots referenced here

Slot numbers are exact; names marked UNVERIFIED are inferred from the matching power
descriptions in `bh/data/classes.json` and from where `performSpecial` sets the slot.

| Slot | Array | Use in this scope | Citation |
|---|---|---|---|
| `buffs[1]` | PartyMember | "next melee strike is special": Monk flurry (class 8), Barbarian Reckless Blow (class 7), generic ×`buffMagnitudes[1]` strike otherwise (UNVERIFIED: Rogue Sneak Attack) | [IL L90492-90540, L91105-91351, L91392-91533] |
| `buffs[4]`, `buffs[6]` | PartyMember (Cleric) | multiply Holy Embrace HoT by `buffMagnitudes[4]` / `[6]` (UNVERIFIED: Guardian / Vengeful Angel) | [IL L88547-88609] |
| `buffs[8]` | PartyMember | next strike applies enemy `debuffs[2]` (UNVERIFIED: Rogue Expose Weakness) | [IL L91756-91864] |
| `buffs[9]` | PartyMember | next strike deals ×`buffMagnitudes[9]` (UNVERIFIED: Rogue Shadowstep) | [IL L91574-91715] |
| `buffs[11]` | PartyMember | next strike is the Shield Rush hit, ×`buffMagnitudes[11]` | [IL L90237-90253, L90927-91043] |
| `buffs[12]` | ally | Cleric Holy Embrace HoT timer (= `buffDurations[12]`), magnitude base `buffMagnitudes[12]` | [IL L88536-88624] |
| `buffs[13]` | ally | Cleric Empowering Words timer (= `buffDurations[13]`) | [IL L88637-88646] |
| `buffs[14]` | ally | Bard song timer (= `buffDurations[14]`); enables `bardBuffPower × bardCoefficient` flat damage | [IL L89022-89031, L18462-18480] |
| `buffs[16]` | PartyMember | melee `actionTimer` runs ×1.15 (not set in this scope; meaning not determined) | [IL L80338-80352] |
| `buffs[17]` | PartyMember | melee haste: `actionTimer` rate, attack animation speed and wind-up all scaled by `buffMagnitudes[17]` (set at IL L101168 next to the `"enrage"` string; UNVERIFIED: Barbarian Frenzy) | [IL L80316-80334, L90363-90415, L92311-92331] |
| `buffs[18]` | ally | Bard Prestissimo timer (= `buffDurations[18]`) | [IL L89106-89122] |
| `buffs[22]` | ally | Bard Vivace timer (= `buffDurations[22]`); `actionTimer` rate × `buffMagnitudes[22]` for all AI types | [IL L89125-89142, L79879-79897, L80078-80096, L80356-80374] |
| `buffs[29]` | PartyMember (Paladin) | Wrath: basic hits chain (set at IL L104998) | [IL L92494-92499] |
| `debuffs[1]` | EnemyScript | Rogue Envenomed Blades: set to 3 s; color (0.26, 0.18, 0.34); `mostRecentDebuff = 1` (UNVERIFIED: stun / paralysis) | [IL L92116-92142] |
| `debuffs[2]` | EnemyScript | set to `debuffDurations[2]` by the `buffs[8]` strike; color (0.4, 0.26, 0.07); `mostRecentDebuff = 2` | [IL L91815-91837] |
| `debuffs[3]` + `debuffs[4]` | EnemyScript | always written as a pair: `[3]` = seconds (1.7 / 3 / 3.5 / `debuffDurations[3]`), `[4]` = 0.2 / 0.15 / 0.15 / 0.3. Used by every "knock to the ground" effect here (Monk finisher, Iron Hand, Blunt Trauma, Shield Rush). UNVERIFIED: `[3]` is the knock-down timer and `[4]` a companion parameter (e.g. get-up/launch value); its semantics are in `EnemyScript` | [IL L90842-90862, L92192-92212, L91194-91205, L93052-93066, L90990-91006, L90014-90031] |
| `debuffs[6]`, `debuffs[7]` | EnemyScript | Knight basic-hit debuffs (`passives[1] == -1` → 6, `== 1` → 7), duration `debuffDurations[6/7]` | [IL L92221-92260] |

`MotherBrain.buffDurations`, `buffMagnitudes`, `debuffDurations` are never assigned in the IL
(no `stfld float32[] MotherBrain::buffDurations|buffMagnitudes|debuffDurations` exists), so
their numeric contents are Unity-serialized scene data and are **not available** from this
source or from `bh/data/*.json`.

---

## 12. Uncertain / not determined

* **`meleeOffset` per class** — only the ctor default 0.21 is in the IL [IL L77100-77101]; the
  field is public and never written elsewhere, so real per-class values (which set the melee
  wind-up and the Ranger's draw time) are prefab data. Not determined.
* **`primaryActionCooldown` per class** — only the default 1.3 and the three multipliers in
  §2.5 are in the IL. Per-prefab overrides not determined.
* **`impactForce`, `totalMeleeSounds`, `AIType` per class** — ctor defaults 2 / 5 / 1
  [IL L77067-77068, L77043-77044, L77058-77059]; prefab overrides not determined. That
  Cleric/Bard are `AIType 1`, Wizard/Witch/Ranger `AIType 2` and the rest `AIType 3` is
  UNVERIFIED (inferred from which coroutine each AI branch can start, §2.5).
* **`buffMagnitudes[1] / [9] / [11] / [12] / [17] / [22]`, `buffDurations[12/13/14/18/22]`,
  `debuffDurations[2/3/6/7]`** — values not in the IL (§11). Power descriptions suggest 2.5
  (Sneak Attack) and 3.5 (Shadowstep) for `buffMagnitudes[1]` / `[9]`, but that is
  UNVERIFIED.
* **Projectile damage** for Wizard / Witch / Ranger basic attacks (base damage, crit, Enveloping
  Flames splash, Mortal Shots, Life Leech) is in `EffectScript` (IL 2676–5280), not read here.
* **What `EnemyScript.takeDamage` does with the number** (buff/debuff multipliers, lifesteal,
  floating text) — outside scope; only the Bard-song line [IL L18462-18480] was read.
* **Meaning of `debuffs[4]`** and of `buffs[16]` — not determined.
* **WrapMode constants**: `2` and `8` are passed to `AnimationState.wrapMode` [IL L90557-90559,
  L90724-90726]; the names Loop / ClampForever are from the Unity enum, not from the IL.
* `WaitForSeconds` uses scaled time, so waits issued while `Time.timeScale` is 0.05 / 0.1 last
  20× / 10× longer in real time (UNVERIFIED: standard Unity behaviour, not stated in the IL).
* The exact enclosing conditions of the `meleeAttack` start in `AI` (range / positioning checks
  before IL L81040) were not read.

### Contradictions with older notes

| Older note | Says | IL says |
|---|---|---|
| datamine `docs/02-damage-system.md` line 92 | Bard buff: `damageAmount += attacker.bardBuffPower + tempDamage * attacker.bardCoefficient` | `damage = (int)(damage + bardBuffPower * bardCoefficient)` — the coefficient multiplies the flat bonus, there is no `tempDamage × coefficient` term [IL L18470-18480] |
| datamine `docs/02-damage-system.md` line 113; `work/class-port-spec-cleric-paladin-wizard-rogue.md` line 314 | `characterClass == 7` is an "assassin-type class" | class 7 is the Barbarian (`"reckless"` strike with 25 % self-damage, double half-damage swings, Precision Strikes) [IL L90291-90303, L91124-91163, L91935-92016, L77753-77769] |
| `work/class-port-spec-…md` line 254 | Flurry: swing interval ÷ 1.15 | `primaryActionCooldown *= 0.85` [IL L77676-77679] |
| `work/class-port-spec-…md` line 156 | Swift Justice: swing interval / 1.10 | `primaryActionCooldown *= 0.9` (and `moveSpeed *= 1.1`) [IL L77804-77813] |
| `work/class-port-spec-…md` line 26 | pounce writes `debuffs[3] = 3.0 / [4] = 0.15` | pounce writes `debuffs[3] = 3.5`, `[4] = 0.15` [IL L93052-93066]; 3.0 is the Monk Iron Hand / Rogue value [IL L92201-92212] |
| `work/class-port-spec-…md` lines 23, 87, 150 | Cleric heal cadence 1.75 s; melee swing 1.1 s | not in the IL: only the shared default `primaryActionCooldown = 1.3` exists [IL L77052-77053] |

---

## 13. Cross-references

| Symbol | Lines | Relation |
|---|---|---|
| `PartyMember.AI` | 78102–81244 | starts `castHeal` [L80029], `castBardBuff` [L80049], `shootArrow` [L80228], `castFireball` [L80259], `meleeAttack` [L81076], `pounceAttack` [L81230]; accumulates `actionTimer` |
| `PartyMember.takeDamage` | 81497–82407 | starts `counterAttack` [L82396]; called on self by Reckless Blow [L91164, L91236, L91288] |
| `PartyMember.initialize` | 77121–78037 | passive stat changes: cooldown, crit, `projectileDamageMod` [L77663-77849] |
| `PartyMember.heal(int, PartyMember)` | 82423–82590 | called by `castHeal` [L88514, L88526, L88690, L88786] |
| `PartyMember.calculateCrit` | 87112–87142 | called by armed strikes and pounce |
| `PartyMember.activateColors` | 84223–84239 | called on the bard-buffed ally [L89168] |
| `PartyMember.updateHealthBar(int)` | 82781–83186 | called after flipping facing in `counterAttack` [L89817, L89887] |
| `PartyMember.returnToNormalFromPounce` | 86480–86531 | called at the end of `pounceAttack` [L93213] |
| `PartyMember.performSpecial` (`$performSpecial$1850`) | 93226–105808 | arms `buffs[1]` [L96094, L102220, L103775], `buffs[8]` [L96119], `buffs[9]` [L96324], `buffs[11]` [L96059], `buffs[17]` [L101168], `buffs[29]` [L104998] |
| `EnemyScript.takeDamage(int, Vector3, PartyMember)` | within 5304–32635 (Bard-song part at L18462-18480) | receives every hit from this code |
| `EffectScript.activate(Vector3, Transform)` | within 2676–5280 | launches projectiles / plays hit effects |
| `MotherBrain` | 59090–76914 | `buffDurations`, `buffMagnitudes`, `debuffDurations`, `playerScripts`, `enemyScripts`, `cameraShaker` (clips `"shake"`, `"powerUpShake"`), `dimBackground`, `disableSpecials`; gear application to `critChance` / `primaryActionCooldown` [L60677-60833] |
| `PetScript` | 105812–107128 | Ranger's dog receives the target when an arrow is started [L80232-80252] |

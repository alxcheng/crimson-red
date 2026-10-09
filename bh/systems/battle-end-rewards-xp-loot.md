# Battle end: victory / defeat sequences, gold, XP, level-up curve, loot rolls, action bar

**Scope:** class `MotherBrain` (the in-battle director) — coroutine bodies and trailing methods.
IL file: `/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`

| Method | Stub lines | Body lines |
|---|---|---|
| `hideLine(int whichLine)` | 64638–64649 | `$hideLine$1627` 70611–70769 |
| `updateActionBar(float timeDelay)` | 64696–64707 | `$updateActionBar$1634` 70771–71589 |
| `disableActionBar()` | 64710–64720 | `$disableActionBar$1653` 71591–71938 |
| `specialMove(int whichSpecial)` | 65510–65521 | `$specialMove$1664` 71940–72397 |
| `levelCompleteSequence()` | 70148–70158 | `$levelCompleteSequence$1673` 72399–74749 |
| `XPBarAnimation()` | 70161–70171 | `$XPBarAnimation$1712` 74751–75661 |
| `defeatSequence()` | 70174–70184 | `$defeatSequence$1730` 75663–76802 |
| `levelUpEnemies()` | 70187–70259 | (plain method) |
| `updateScore()` | 70262–70336 | (plain method) |
| `calculateNextLevelXP(int whichLevel)` | 70339–70404 | (plain method) |
| `muteSoundEffects()` | 70407–70444 | (plain method) |
| `delayedPetCommand(PartyMember whichAlly)` | 70447–70457 | `$delayedPetCommand$1757` 76804–76912 |
| `handleBackButton()` | 70460–70599 | (plain method) |
| `Main()` | 70602–70609 | empty, just `ret` [IL L70608] |

All coordinates below are Unity world/local units of the BH scene, not pixels. All waits are
`WaitForSeconds` (they run on scaled game time — this is Unity engine behaviour, not something
visible in the IL).

---

## 1. Summary

- **Victory** (`levelCompleteSequence`): when the last wave of a normal level is cleared the game
  locks input, marks the level complete, lines the survivors up, plays the victory jingle and a
  "victory" banner, then shows the spoils: a **gold** amount (level gold ±15 %, times the
  gold-trinket bonus), **exactly one loot item** if the 20-slot inventory has a free slot (from the
  level's loot table, or from the *next* table up on a "rare" roll), and then an **XP** number per
  surviving hero. Dead heroes get nothing. Fewer survivors get more XP each (×4 / ×2 / ×1.33 / ×1),
  and the three best performers (by `browniePoints`) get +25 % / +16 % / +8 %.
- **XP bars** (`XPBarAnimation`): each survivor's bar drains toward the new XP value; every time a
  bar fills, the hero levels up (level +1, XP cost subtracted, "level up" text pops) and the bar
  restarts — several levels per battle are possible. When all bars are still, the merchant stock is
  re-rolled, heroes walk off-screen right and the scene changes ~3 s later.
- **Level-up cost** (`calculateNextLevelXP`): 30 XP for level 1→2, then multiplied (with integer
  truncation at every step) by a per-level factor table (1.35 falling to 1.05).
- **Defeat** (`defeatSequence`): in a normal level — "defeat" banner, fade, back to the menu scene
  with no rewards. In an **arena** level (endless survival, always ends in defeat) — shows kill
  count, new-record banner if the high score was beaten, and one loot item whose table is chosen by
  kill-count thresholds. No gold or XP in the arena.
- **Arena difficulty** (`levelUpEnemies`): ×1.1 `maxHealth` and `power` on live enemies each tier.
- **Action bar** (`updateActionBar` / `disableActionBar` / `specialMove`): shows up to three
  ability buttons for the selected hero and runs the "power-up" freeze-frame that precedes every
  special ability, including cooldown assignment.

---

## 2. Fields

### 2.1 `MotherBrain` fields used here (declarations IL L59093–59242; ctor defaults IL L59245–59302)

| Field | Type | Meaning | Default |
|---|---|---|---|
| `victoryMusic` | AudioSource | victory jingle; also played at arena end [IL L72829-72830, L75928-75929] | inspector |
| `BGMusic` | AudioSource | battle music; faded by `Update` after level complete [IL L61767-61775] | inspector |
| `victoryText` / `victoryTextAnim` | Transform / Animation | "victory" banner | inspector |
| `spoilsText` / `spoilsTextAnim` | Transform / Animation | "spoils" heading | inspector |
| `goldText` / `goldTextAnim` / `goldTextText[2]` / `coinIcon` | Transform / Animation / TextMesh[] / Renderer | gold amount display; two TextMeshes get the same string | inspector |
| `lootFrame` / `lootFrameAnim` / `lootIcon` | Transform / Animation / Renderer | loot item frame and icon | inspector |
| `lootText` / `lootTextAnim` / `lootTextText[2]` | Transform / Animation / TextMesh[] | loot item name | inspector |
| `XPBars[4]`, `XPBarAnim[4]` | Transform[] / Animation[] | per-party-slot XP bar root | inspector |
| `darkBar[4]`, `lightBar[4]` | Transform[] | two sliding bar fills per slot; `localPosition.x` encodes fill: **+0.82 = 0 XP, −0.82 = full** | inspector |
| `XPTextText[8]`, `XPTextAnim[4]` | TextMesh[] / Animation[] | "N XP" label; index `i` and `i+4` receive the same text [IL L74221-74246] | inspector |
| `levelUpText[4]`, `levelUpTextAnim[4]`, `levelUpTextTimer[4]` | Transform[] / Animation[] / float[] | "level up" popup and its remaining display time | inspector |
| `defeatText` / `defeatTextAnim` | Transform / Animation | "defeat" banner | inspector |
| `arenaText` / `arenaTextAnim` | Transform / Animation | arena-over banner | inspector |
| `killsText` / `killsTextAnim`, `killCountText` / `killCountAnim` / `killCountTextText[2]` | … | arena kill heading and number | inspector |
| `recordText` / `recordTextAnim` | Transform / Animation | arena "new record" banner | inspector |
| `score` / `scoreText` / `pauseTransform` | Transform / TextMesh / Transform | live arena score label | inspector |
| `bonusGold` | float | gold multiplier. ctor sets 100 [IL L59254-59255]; `Awake` adds `Item.power` of every equipped gear id 36..37 [IL L60905-60948], then divides by 100 [IL L61343-61346]. Result `1 + Σpower/100` | 100 → 1.0 |
| `finalBrowniePoints[4]` | int[] | ranking of survivors: `[3]` = party slot of best, `[2]` second, `[1]` third, `[0]` fourth; `-1` = unassigned | inspector (never assigned in code; logic requires `-1` entries — see §12) |
| `levelComplete` | bool | set when victory or defeat starts; gates sequences | false |
| `animateXPBars` | bool | while true `Update` starts `XPBarAnimation` every frame [IL L61777-61783] | false |
| `partyFormUp` | bool | set true at victory [IL L72715-72716]; read by `PartyMember` [IL L78917] | false |
| `finalBossFirstKill` | bool | selects the ending transfer [IL L61728-61736] | false |
| `disableInput` | bool | ctor sets true [IL L59299-59300] | true |
| `disableSpecials` | bool | blocks ability buttons | false |
| `freezeUI` | bool | set during `updateActionBar` delay | false |
| `flee` | float | exit timer; `-1` = idle, `>= 0` = counting [IL L59286-59288, L61678-61693] | −1 |
| `fadeStatus` | int | ctor 1 [IL L59296-59297]; set to 2 to fade out [IL L75878-75879] | 1 |
| `fader` | Renderer | full-screen fade quad | inspector |
| `arenaMode` | bool | endless-arena battle | false |
| `totalKills` | int | arena kill counter, +1 per enemy death in arena mode [IL L28098-28110] | 0 |
| `enemyTier` | int | arena difficulty tier | 1 [IL L59281-59282] |
| `enemyScripts` | EnemyScript[] | enemy pool | inspector/Awake |
| `playerScripts[4]` | PartyMember[] | party in battle, index = party slot | Awake |
| `leader` / `leaderScript` | Transform / PartyMember | currently selected hero | null |
| `actionBar` / `actionBarAnimation` | Transform / Animation | ability bar root | inspector |
| `actionButton1..3` | Transform | the three button anchors | inspector |
| `currentIcons[3]` | Transform[] | icon currently parented to each button | inspector |
| `classIcons[]` | Transform[] | all ability icons, 5 per class, index `(characterClass-1)*5 + n` | inspector |
| `flashIcon[3]` | bool[] | per-button "flash" flag | false |
| `selectionCircle` | Transform | ring under selected hero | inspector |
| `drawnLine[5]`, `drawnDot[5]`, `drawnTip[5]` | Transform[] | drag-line visuals per touch | inspector |
| `touchState[5]` | int[] | per-touch state | 0 |
| `powerUpEffect` / `powerUpAnimation` | Transform / Animation | special-move burst effect | inspector |
| `cameraShaker` | Animation | camera shake clips | inspector |
| `dimBackground` | bool | darkens background during power-up | false |
| `audioPool[]` | AudioSource[] | SFX: index 3 [IL L72070-72073, L74506-74509], 4 [IL L75068-75071, L76174-76177], 5 [IL L72160-72163] used here | inspector |
| `paused`, `cachedTimeScale`, `pauseScreen` | bool / float / Transform | pause state | false |
| `DB` | Database | global save/data object | Awake |

### 2.2 Other classes' fields touched

| Field | Declared | Use here |
|---|---|---|
| `Database.gold` (int) | IL L863 | `+= goldReward` [IL L73035-73043] |
| `Database.inventory` (int[], 20 slots, `-1` = empty; `bh/data/globals.json` `inventory`) | IL L860 | first free slot receives the loot item id |
| `Database.firstLevelXP` (int) | IL L871 | 30 in `bh/data/globals.json`. (The `Database` ctor default is 50 [IL L909-910]; the serialized value 30 is what the game uses.) |
| `Database.XPtable` (float[27]) | IL L873 | per-level multipliers, `bh/data/globals.json` `XPtable` |
| `Database.XPscale` | — | **not read** by any code in this range (ctor default 1.1 [IL L912-913]; data value 1.35) |
| `Database.lootTables` (LootTable[]) | IL L875 | `bh/data/loot_tables.json`, array index = `id` |
| `LootTable.tableContents` (int[] of item ids) | IL L693 | rolled uniformly |
| `Database.levelDB[currentMap].whichLevel[whichLevel]` → `Level` | — | the level being played |
| `Level.complete` (bool) | IL L745 | set true at victory [IL L72680-72694] |
| `Level.goldReward`, `Level.XPReward`, `Level.lootTable`, `Level.rareChance`, `Level.highScore` (int) | IL L758-762 | reward data, `bh/data/maps.json` |
| `Level.arenaTable` (LootThreshold[]) ; `LootThreshold.requiredKills`, `.whichTable` | IL L747, L784-785 | arena loot tiers |
| `Database.partyDB[Database.party[i]]` → `Player.level`, `Player.XP` | IL L638, L643 | persistent hero level/XP |
| `Database.finalBossKill` (int) | IL L882 | ctor default 1 [IL L933-934]; cleared on first final-boss kill |
| `Database.transferLevel` (int) | IL L874 | tells the menu scene where to open |
| `Database.musicEnabled`, `Database.soundEnabled` (bool) | — | audio toggles |
| `PartyMember.health` (float) | — | `> 0` = alive |
| `PartyMember.browniePoints` (int) | — | performance score (sources in §11) |
| `PartyMember.bonusXP` (float) | — | XP multiplier: ctor 100 [IL L77086]; `MotherBrain.Awake` adds `Item.power` for gear ids 38..39 [IL L60963-61009]; `PartyMember.initialize` divides by 100 [IL L77993-77996] |
| `PartyMember.AIState` (int) | — | set to 1 (walk to `movementTarget`) and 5 (power-up) here |
| `PartyMember.movementTarget` (Vector3), `PartyMember.petScript`, `PetScript.movementTarget`, `PetScript.myTarget` | — | formation / walk-off targets |
| `PartyMember.abilities[3]` (int), `.cooldowns[3]`, `.remainingCooldowns[3]` (float), `.noCooldownChance` (int), `.characterClass` (int), `.commandPending`, `.invincible`, `.flee` (bool), `.colorSpeed` (float), `.myAnimation`, `.myRenderer`, `.myTransform` | — | action bar / special move |
| `EnemyScript.maxHealth`, `EnemyScript.power` (int) | — | scaled by `levelUpEnemies` |

---

## 3. `levelCompleteSequence()` — victory [IL L72492-74745]

**Started by** `MotherBrain.enemySpawn` when `currentWave >= Level.waves.length` and
`levelComplete` is false [IL L65090-65114]. `enemySpawn` runs from `Update` only when
`DB.tutorial` is false [IL L61752-61757]. In arena mode `currentWave` is re-rolled randomly
after each wave [IL L65145-65165], so arenas do not reach this sequence that way.

### 3.1 Timeline

| t (s, cumulative) | Step | IL |
|---|---|---|
| 0 | `levelComplete = true`, `disableInput = true`, `disableSpecials = true` | L72576-72585 |
| 0 | for `i = 0..4`: `touchState[i] = 0`; `drawnLine[i]`, `drawnDot[i]`, `drawnTip[i]` moved to `(0,0,20)` (hidden) | L72587-72652 |
| 0 | if a hero is selected: `leaderScript.deselect()`, `leaderScript = null`, `leader = null`, `actionBarAnimation.Play("hide")` | L72656-72676 |
| 0 | `DB.levelDB[DB.currentMap].whichLevel[DB.whichLevel].complete = true` | L72680-72694 |
| 0 | `selectionCircle.position = (0,0,20)` | L72697-72705 |
| wait 0.5 | | L72707-72710 |
| 0.5 | `partyFormUp = true` | L72715-72716 |
| 0.5 | every slot `i` with a script and `health > 0`: `AIState = 1`; `movementTarget = (-2.0 + i*1.333, 0, 0)`; if it has a pet: `petScript.movementTarget = movementTarget + (0.3, 0, 0.5)` | L72718-72812 |
| wait 0.1 | | L72815-72818 |
| 0.6 | if `DB.musicEnabled`: `victoryMusic.Play()` | L72823-72830 |
| wait 1.1 | | L72832-72835 |
| 1.7 | `victoryText.position.y = 6`; `victoryTextAnim.Play("pop")` | L72839-72879 |
| wait 2.1 | | L72882-72885 |
| 3.8 | `victoryTextAnim.Play("hide")` | L72890-72892 |
| wait 0.4 | | L72895-72898 |
| 4.2 | `victoryText.position.y = 15` (off-screen); `spoilsText.position.y = 6.8`; `spoilsTextAnim.Play("pop")` | L72902-72978 |
| wait 0.4 | | L72981-72984 |
| 4.6 | **Gold** computed, shown, added (§3.2) | L72990-73254 |
| wait 0.4 | | L73257-73260 |
| 5.0 | **Loot** rolled and shown (§3.3) | L73264-73562 |
| wait 3.0 | | L73564-73568 |
| 8.0 | `spoilsTextAnim.Play("hide")`; `coinIcon.enabled = false`; `goldTextAnim`, `lootFrameAnim`, `lootTextAnim` `.Play("hide")` | L73573-73598 |
| wait 0.5 | | L73601-73604 |
| 8.5 | **XP**: ranking, multiplier, then per survivor award + 0.1 s wait each (§3.4) | L73608-74494 |
| wait 2.0 | | L74497-74501 |
| 10.5 + 0.1·survivors | `audioPool[3].Play()`; per survivor: `flash()`, `XPTextAnim[i].Play("hide")`, `lightBar[i]` set to the new XP fill (§3.5) | L74506-74726 |
| wait 0.4 | | L74729-74732 |
| end | `animateXPBars = true` → hands over to `XPBarAnimation` (§4) | L74737-74738 |

### 3.2 Gold

```
goldReward = Mathf.RoundToInt( Level.goldReward * Random.Range(0.85, 1.15) * bonusGold )
DB.gold += goldReward
```
[IL L72990-73014, L73035-73043]

- `Random.Range(0.85f, 1.15f)` is the float overload [IL L73005-73007] (uniform, continuous).
- `bonusGold = (100 + Σ Item.power of equipped items with id 36 or 37, over all party members and
  gear slots) / 100` [IL L59254-59255, L60905-60948, L61343-61346]. Per `bh/data/items.json`:
  id 36 "Glove of the Thief" power 10 (+10 %), id 37 "Bandit's Satchel" power 20 (+20 %). They stack
  additively (each equipped copy adds its power).
- Display: both `goldTextText[0]` and `[1]` get `goldReward.ToString()` [IL L73017-73032];
  `coinIcon.enabled = true` [IL L73046-73048]; `goldText.position.y = 6.22` [IL L73050-73083];
  `goldText.position.x` depends on digit count:

| goldReward | goldText.position.x | IL |
|---|---|---|
| < 10 | 0.02 | L73086-73124 |
| < 100 | 0.09 | L73129-73167 |
| < 1000 | 0.207 | L73172-73210 |
| ≥ 1000 | 0.307 | L73215-73248 |

  then `goldTextAnim.Play("pop")` [IL L73252-73254].

**Worked example** (The Gobwood, map 0 level 0, `goldReward` 27 in `bh/data/maps.json`): no
trinkets → between `RoundToInt(27×0.85)=23` and `RoundToInt(27×1.15)=31` gold. With one Glove of
the Thief and one Bandit's Satchel equipped (`bonusGold = 1.30`) and a roll of 1.00 →
`RoundToInt(27×1.0×1.3) = 35`.

### 3.3 Loot roll (campaign victory)

```
availableSlot = -1
for i in 0 .. DB.inventory.length-1:            # first empty slot
    if DB.inventory[i] == -1: availableSlot = i; break     # (IL sets i = 999 to break)
if availableSlot == -1:  -> no loot, nothing shown, skip to the 3.0 s wait
else:
    lootFrame.position = (0, 5.35, -7.4);  lootFrameAnim.Play("pop")
    lootText.position  = (0, 5.72, -7);    lootTextAnim.Play("pop")
    L = current Level
    if L.rareChance > 0 and Random.Range(0, 101) <= L.rareChance:      # int overload: 0..100
        table = DB.lootTables[L.lootTable + 1]                          # "rare" = next table up
    else:
        table = DB.lootTables[L.lootTable]
    randomDrop = table.tableContents[ Random.Range(0, table.tableContents.length) ]
    DB.inventory[availableSlot] = randomDrop
    lootTextText[0].text = lootTextText[1].text = DB.itemDB[randomDrop].itemName
    lootIcon.material.mainTexture = Resources.Load(DB.itemDB[randomDrop].icon)
```
[slot search IL L73264-73301; skip IL L73304-73306; frame/text IL L73310-73337; rare test
IL L73344-73380; rare table roll IL L73383-73439; normal table roll IL L73443-73495; inventory
write IL L73498-73504; name IL L73507-73542; icon IL L73545-73562]

Facts:
- **Exactly one item per victory, 100 % of the time, provided a free inventory slot exists.**
  With a full inventory the item is silently lost (no "Inventory Full!" text in this path —
  that string only exists in the arena path, §5.2).
- Rare test: the comparison is `Random.Range(0,101) > rareChance → normal` [IL L73361-73380], so
  rare happens when the integer roll (0..100 inclusive, 101 outcomes — Unity's int `Random.Range`
  excludes the upper bound) is `<= rareChance`. **P(rare) = (rareChance + 1) / 101** when
  `rareChance > 0`; exactly 0 when `rareChance == 0` (or negative) [IL L73357-73359].
- Rare does **not** grant a second item; it only swaps the table to index `lootTable + 1`.
- Every entry in `tableContents` is equally likely; an item id listed twice would be twice as likely.
- `LootTable.minLevel` / `maxLevel` / `tableName` are **not read** anywhere in this range; no
  party-level filtering happens in the victory or arena roll.
- No duplicate check, no class filter.

`Level.lootTable` / `rareChance` per level are in `bh/data/maps.json`; tables are in
`bh/data/loot_tables.json`:

| lootTables index | tableName | entries |
|---|---|---|
| 0 | Tier 1 Gear | 12 |
| 1 | Tier 2 Gear + 1.0 trinkets | 17 |
| 2 | Tier 3 Gear + 1.0 & 1.5 trinkets | 22 |
| 3 | Tier 4 Gear + 1.5 and 2.0 trinks | 25 |
| 4 | Tier 5 Gear + 2.0 & 2.5 trinkets | 26 |
| 5 | Tier 6 Gear + 2.5 & 3.0 trinkets | 23 |
| 6 | Tier 7 Gear + 3.0 & 3.5 trinkets | 24 |
| 7 | Tier 8 Gear + 3.5 trinkets | 19 |
| 8 | Tier 9 Gear | 12 |

**Worked loot roll** (The Gobwood: `lootTable` 0, `rareChance` 20):
1. Free slot? Suppose `inventory[0] == -1` → `availableSlot = 0`.
2. `Random.Range(0,101)` → e.g. 57. `57 <= 20` is false → normal table `lootTables[0]`
   (Tier 1 Gear, 12 entries: ids 0,1,2,3,4,5,6,11,43,44,45,123).
3. `Random.Range(0,12)` → e.g. 7 → `tableContents[7] = 11` → item 11 "Dual Hatchets".
   `inventory[0] = 11`.
4. Had the first roll been e.g. 13 (`<= 20`), the table would be `lootTables[1]` (Tier 2, 17
   entries) and `Random.Range(0,17)` → e.g. 14 → item id 36 "Glove of the Thief".

Probabilities for that level: rare `21/101 = 20.79 %`, normal `79.21 %`; each Tier 1 item
`0.7921/12 = 6.60 %`; each Tier 2 item `0.2079/17 = 1.22 %`.
Other examples: `rareChance` 50 → `51/101 = 50.5 %`; 10 → `11/101 = 10.9 %`; 5 → `6/101 = 5.9 %`.
Boss levels with `rareChance` 0 (e.g. map 0 level 4 "The Squealing Bog", `lootTable` 1) always
roll their own table. The final boss (map 3 level 11, `lootTable` 6, `rareChance` 50) rolls table 7
(Tier 8) 50.5 % of the time.

### 3.4 XP reward and how it is split

**Step A — rank the survivors by `browniePoints`** (`finalBrowniePoints`, slots 0..3; a "survivor"
is a slot whose `playerScripts[i]` exists and has `health > 0`):

```
pass 1: for i in 0..3, survivor:                       -> fBP[3] = best      [IL L73614-73681]
          if fBP[3] == -1 or bp(i) >= bp(fBP[3]): fBP[3] = i
pass 2: same, skipping i == fBP[3]                     -> fBP[2] = 2nd best  [IL L73684-73760]
pass 3: same, skipping fBP[3], fBP[2]                  -> fBP[1] = 3rd best  [IL L73763-73848]
pass 4: same, skipping fBP[3], fBP[2], fBP[1]          -> fBP[0] = 4th       [IL L73851-73945]
```
The replace test is "skip if `bp(i) < bp(current)`" (`blt`) so **ties go to the higher slot
index** [IL L73663, L73742, L73830]. Pass 4 compares against `playerScripts[fBP[1]]` instead of
`fBP[0]` (index literal 1 at IL L73923) — harmless because at most one candidate remains.
`fBP[0]` is never used afterwards. With fewer than 4 survivors the lower ranks stay `-1`.

**Step B — survivor-count multiplier** [IL L73948-74022]:

| Living party members | `XPmultiplier` | IL |
|---|---|---|
| 1 | 4.0 | L73996-74002 |
| 2 | 2.0 | L74006-74012 |
| 3 | 1.33 | L74016-74022 |
| 4 (or any other count) | 1.0 | L73993-73994 |

(So the level's XP is effectively a pool of `4 × Level.XPReward` divided among survivors; note
the literal 1.33, not 4/3. The count is over slots 0..3 regardless of party size, so a 2-hero
party that both survive gets ×2.)

**Step C — per survivor, in slot order `i = 0..3`** [IL L74024-74494]:

```
XPBars[i].position.y = 0;  XPBarAnim[i].Play("pop");  XPTextAnim[i].Play("pop")   [L74049-74107]
if   fBP[3] == i: member.bonusXP += 0.25        # best performer                    [L74111-74133]
elif fBP[2] == i: member.bonusXP += 0.16        # second                            [L74138-74160]
elif fBP[1] == i: member.bonusXP += 0.08        # third                             [L74165-74187]
XPReward = Mathf.RoundToInt( Level.XPReward * XPmultiplier * member.bonusXP )       [L74191-74218]
XPTextText[i].text = XPTextText[i+4].text = XPReward + " XP"                        [L74221-74246]
P = DB.partyDB[DB.party[i]]
nextLevelXP = (P.level == 1) ? DB.firstLevelXP : calculateNextLevelXP(P.level)      [L74249-74288]
darkBar[i].localPosition.x  = 0.82 - 1.64 * P.XP / nextLevelXP    # OLD xp          [L74290-74349]
if darkBar[i].localPosition.x < -0.82: darkBar[i].localPosition.x = -0.82           [L74354-74404]
lightBar[i].localPosition.x = 0.82                                                  [L74408-74446]
P.XP += XPReward                                                                    [L74451-74477]
wait 0.1 s                                                                          [L74479-74482]
```

- `member.bonusXP` before the rank bonus is `(100 + Σ Item.power of that hero's own equipped
  items with id 38 or 39) / 100` — id 38 "Mystic Journal" power 10, id 39 "Mystery Egg" power 20
  (`bh/data/items.json`) [IL L77086, L60963-61009, L77993-77996]. Unlike gold trinkets, XP
  trinkets only affect the wearer (the add targets `playerScripts[partyIndex].bonusXP`
  [IL L60981-61009]).
- The rank bonus is **added** to that multiplier (1.00 → 1.25 / 1.16 / 1.08; with a Mystic
  Journal 1.10 → 1.35).
- The 4th-ranked survivor and dead heroes get no rank bonus; dead heroes get no XP at all
  (the whole block is skipped when `health <= 0`) [IL L74030-74046].
- `Mathf.RoundToInt` rounds halves to the nearest even integer (Unity engine behaviour).

**Worked example** — The Gobwood (`XPReward` 35), no XP trinkets:

| Situation | Best (+0.25) | 2nd (+0.16) | 3rd (+0.08) | 4th |
|---|---|---|---|---|
| 4 survivors (×1.0) | round(35×1.25)=**44** | round(35×1.16)=**41** | round(35×1.08)=**38** | **35** |
| 3 survivors (×1.33) | round(35×1.33×1.25)=**58** | round(35×1.33×1.16)=**54** | round(35×1.33×1.08)=**50** | — |
| 2 survivors (×2.0) | round(35×2×1.25)=**88** (87.5 → even) | round(35×2×1.16)=**81** | — | — |
| 1 survivor (×4.0) | round(35×4×1.25)=**175** | — | — | — |

Final boss (map 3 level 11, `XPReward` 500), 4 survivors: 625 / 580 / 540 / 500.

### 3.5 After the 2 s pause [IL L74506-74726]

`audioPool[3].Play()`; then for each survivor: `playerScripts[i].flash()`;
`XPTextAnim[i].Play("hide")`; recompute `nextLevelXP` exactly as above; then

```
if P.XP < nextLevelXP: lightBar[i].localPosition.x = 0.82 - 1.64 * P.XP / nextLevelXP   # NEW xp
else:                  lightBar[i].localPosition.x = -0.82                              # full
```
[IL L74595-74715]. Wait 0.4 s, then `animateXPBars = true` [IL L74729-74738].

Bar geometry: fill fraction `f = XP / nextLevelXP`; `x = 0.82 − 1.64·f`; the bar is 1.64 units
long. `darkBar` holds the old fraction, `lightBar` the target fraction.

---

## 4. `XPBarAnimation()` — bar animation and level-up [IL L74823-75657]

**Called** by `MotherBrain.Update` once per frame (a new coroutine each frame) while
`levelComplete && animateXPBars` [IL L61763-61783]. Each call does one frame step; only the call
that finds everything at rest continues past its `yield`.

```
noAnimation = true                                                              [L74872-74873]
for i in 0..3:
  if playerScripts[i] exists and health > 0:                                    [L74884-74900]
    if darkBar[i].x > lightBar[i].x:                                            [L74904-74922]
        noAnimation = false                                                     [L74925-74926]
        darkBar[i].x -= Time.deltaTime            # 1 unit/s; full bar = 1.64 s  [L74930-74977]
        if darkBar[i].x < lightBar[i].x: darkBar[i].x = lightBar[i].x  (clamp)  [L74982-75050]
    if darkBar[i].x == -0.82:                     # bar full -> LEVEL UP         [L75055-75064]
        audioPool[4].Play()                                                     [L75068-75071]
        playerScripts[i].flash()                                                [L75074-75078]
        playerScripts[i].myAnimation.Play("select")                             [L75081-75087]
        darkBar[i].x = 0.82                       # bar restarts empty           [L75090-75128]
        levelUpText[i].position.y = 6.6;  levelUpTextAnim[i].Play("pop")        [L75132-75180]
        levelUpTextTimer[i] = 1.2                                               [L75184-75188]
        P = DB.partyDB[DB.party[i]]
        P.XP    -= calculateNextLevelXP(P.level)   # cost of the level just gained [L75194-75235]
        P.level += 1                                                            [L75238-75263]
        next = calculateNextLevelXP(P.level)       # cost of the new level       [L75269-75281]
        if P.XP < next: lightBar[i].x = 0.82 - 1.64 * P.XP / next               [L75284-75360]
        else:           lightBar[i].x = -0.82      # will level again            [L75365-75403]
  # for every slot i (alive or not):
  if levelUpTextTimer[i] > 0:                                                   [L75408-75414]
      levelUpTextTimer[i] -= Time.deltaTime                                     [L75418-75429]
      if levelUpTextTimer[i] <= 0: levelUpTextTimer[i] = 0; levelUpTextAnim[i].Play("hide") [L75432-75455]

if noAnimation:                                                                 [L75469-75470]
    DB.populateMerchant()                         # re-roll merchant stock       [L75474-75475]
    animateXPBars = false                                                       [L75478-75479]
    wait 0.7 s                                                                  [L75481-75484]
    for i in 0..3, survivors only:                                              [L75488-75614]
        XPBarAnim[i].Play("hide")                                               [L75514-75519]
        playerScripts[i].movementTarget = myTransform.position + (8, 0, 0)      [L75523-75543]
        playerScripts[i].AIState = 1                                            [L75546-75551]
        if pet: petScript.movementTarget += (10, 0, 0)                          [L75554-75585]
        if levelUpTextTimer[i] > 0: levelUpTextAnim[i].Play("hide")             [L75588-75603]
    flee = 0                                      # starts the exit timer        [L75618-75620]
    if DB.finalBossKill == 1 and DB.currentMap == 3 and DB.whichLevel == 11:    [L75623-75640]
        finalBossFirstKill = true;  DB.finalBossKill = 0                        [L75644-75650]
```

### What a character gains on level-up (in this code)
Only two persistent changes: `Player.level += 1` and `Player.XP -= cost` (excess XP carries
over) [IL L75209-75263]. **No stat, health, ability or skill-point change is made here.** Derived
stats are computed elsewhere from `Player.level` (not in this range — see §12).

- Multiple level-ups per battle are possible: after a level-up the bar restarts at 0.82 and
  drains again toward the new target; if XP still covers the next level the target is −0.82 and
  another level-up fires.
- There is **no level cap** in this code.
- Map 3 / level 11 is "Throne of Ruin" (final boss) in `bh/data/maps.json`.

### Exit after victory (in `MotherBrain.Update`, outside this range, for context)
While `disableInput` is true and `flee >= 0` (and `tutorialState != 47`): `flee += deltaTime`,
`BGMusic.volume -= deltaTime*0.8` [IL L61670-61703]; at `flee >= 1.5` and fader not yet enabled →
`fadeStatus = 2`, `fader.enabled = true` [IL L61705-61721]; at `flee >= 3` →
`DB.transferLevel = 5` if `finalBossFirstKill` else `2`, then `Application.LoadLevel(4)`
[IL L61723-61744].

---

## 5. `calculateNextLevelXP(int whichLevel)` — XP needed to go from `whichLevel` to `whichLevel+1` [IL L70339-70404]

```
xp = DB.firstLevelXP                                   # int, 30                 [L70348-70351]
for i = 2 .. whichLevel (inclusive):                                            [L70354-70356, L70396-70398]
    if i < DB.XPtable.length:   xp = (int)( (float)xp * DB.XPtable[i] )         [L70358-70374]
    else:                       xp = (int)( (float)xp * DB.XPtable[length-1] )  [L70377-70391]
return Mathf.RoundToInt((float)xp)                                              [L70400-70403]
```

- `(int)` is `conv.i4` = **truncation toward zero after every multiplication** [IL L70373, L70390].
- The table is indexed by `i` directly, so `XPtable[0]` and `XPtable[1]` are never used.
- For `whichLevel <= 1` the loop does not run and the result is `firstLevelXP` (30). The callers
  also special-case `level == 1 → firstLevelXP` [IL L74259-74268, L74563-74572].
- `XP` is per-level progress, not a lifetime total: on level-up the cost is subtracted (§4).

`bh/data/globals.json`: `firstLevelXP = 30`; `XPtable` (index: value) =
0: 1.35, 1: 1.35, 2: 1.35, 3: 1.35, 4: 1.35, 5: 1.35, 6: 1.33, 7: 1.30, 8: 1.28, 9: 1.25, 10: 1.23,
11: 1.20, 12: 1.18, 13: 1.15, 14: 1.13, 15: 1.10, 16: 1.09, 17: 1.09, 18: 1.08, 19: 1.08, 20: 1.07,
21: 1.07, 22: 1.07, 23: 1.06, 24: 1.06, 25: 1.06, 26: 1.05. Levels ≥ 27 keep using 1.05.

### Worked table (computed with 32-bit float multiply + truncation, exactly as the IL does)

| Current level L | Multiplier applied (`XPtable[L]`) | Calculation | XP to reach L+1 | Cumulative XP from level 1 |
|---|---|---|---|---|
| 1 | — | firstLevelXP | **30** | 30 |
| 2 | 1.35 | int(30 × 1.35 = 40.5) | **40** | 70 |
| 3 | 1.35 | int(40 × 1.35 = 54.0) | **54** | 124 |
| 4 | 1.35 | int(54 × 1.35 = 72.9) | **72** | 196 |
| 5 | 1.35 | int(72 × 1.35 = 97.2) | **97** | 293 |
| 6 | 1.33 | int(97 × 1.33 = 129.01) | **129** | 422 |
| 7 | 1.30 | int(129 × 1.30 = 167.7) | **167** | 589 |
| 8 | 1.28 | int(167 × 1.28 = 213.76) | **213** | 802 |
| 9 | 1.25 | int(213 × 1.25 = 266.25) | **266** | 1068 |
| 10 | 1.23 | int(266 × 1.23 = 327.18) | **327** | 1395 |

Further values (same method): L11 392, L12 462, L13 531, L14 600, L15 660, L16 719, L17 783,
L18 845, L19 912, L20 975, L21 1043, L22 1116, L23 1182, L24 1252, L25 1327, L26 1393, L27 1462,
L28 1535, L29 1611, L30 1691, L31 1775, L32 1863, L33 1956, L34 2053, L35 2155, L36 2262,
L37 2375, L38 2493, L39 2617, L40 2747.

Example of use: a level-1 hero (XP 0) who is top performer among 4 survivors on The Gobwood gets
44 XP → bar fills (30 needed) → level 2 with 14 XP carried over; next cost 40 →
`lightBar.x = 0.82 − 1.64×14/40 = 0.246`.

---

## 6. `defeatSequence()` [IL L75745-76798]

**Started by** `PartyMember.die` when the whole party is dead (`TPK`): it sets
`motherBrain.disableInput = true`, and if `motherBrain.levelComplete` is false starts
`motherBrain.defeatSequence()` (as a coroutine on the PartyMember), then sets
`motherBrain.levelComplete = true` [IL L87503-87529].

### 6.1 Normal level (`arenaMode == false`) [IL L75813-75898]

| t (s) | Step | IL |
|---|---|---|
| 0 | `DB.populateMerchant()` | L75818-75819 |
| wait 1.8 | | L75821-75824 |
| 1.8 | `defeatText.position.y = 5.2`; `defeatTextAnim.Play("pop")` | L75828-75867 |
| wait 3.1 | | L75870-75873 |
| 4.9 | `fadeStatus = 2`; `fader.enabled = true` | L75878-75884 |
| wait 1.5 | | L75886-75889 |
| 6.4 | `DB.transferLevel = 2`; `Application.LoadLevel(4)` | L75894-75898 |

No gold, XP or loot is given and nothing is taken away. `Level.complete` is not changed.

### 6.2 Arena level (`arenaMode == true`) [IL L75903-76791]

| t (s) | Step | IL |
|---|---|---|
| 0 | `DB.populateMerchant()`; `disableInput = true`; `disableSpecials = true` | L75903-75912 |
| wait 1.2 | | L75914-75917 |
| 1.2 | if `DB.musicEnabled`: `victoryMusic.Play()`; `arenaText.position.y = 6`; `arenaTextAnim.Play("pop")` | L75922-75971 |
| wait 2.5 | | L75974-75977 |
| 3.7 | `arenaTextAnim.Play("hide")` | L75982-75984 |
| wait 0.4 | | L75987-75990 |
| 4.1 | `arenaText.position.y = 15`; `killsText.position.y = 6`; `killsTextAnim.Play("pop")` | L75994-76071 |
| wait 0.4 | | L76074-76077 |
| 4.5 | `killCountText.position.y = 5.3`; `killCountAnim.Play("pop")`; `killCountTextText[0].text = killCountTextText[1].text = totalKills.ToString()` | L76081-76143 |
| wait 0.4 | | L76145-76148 |
| 4.9 | **High score:** if `totalKills > Level.highScore`: `audioPool[4].Play()`; `Level.highScore = totalKills`; `recordText.position.y = 4.7`; `recordTextAnim.Play("pop")` | L76153-76237 |
| wait 3.0 | | L76240-76244 |
| 7.9 | `killsTextAnim`, `killCountAnim`, `recordTextAnim` `.Play("hide")` | L76249-76263 |
| wait 0.4 | | L76266-76269 |
| 8.3 | `recordText`, `killCountText`, `killsText` `.position.y = 20`; `spoilsText.position.y = 6.614`; `spoilsTextAnim.Play("pop")` | L76273-76423 |
| wait 0.4 | | L76426-76429 |
| 8.7 | **Arena loot** (below) | L76433-76723 |
| wait 3.0 | | L76726-76730 |
| 11.7 | `spoilsTextAnim.Play("hide")`; `coinIcon.enabled = false`; `goldTextAnim`, `lootFrameAnim`, `lootTextAnim` `.Play("hide")` | L76735-76760 |
| wait 0.5 | | L76763-76766 |
| 12.2 | `fadeStatus = 2`; `fader.enabled = true` | L76771-76777 |
| wait 1.5 | | L76779-76782 |
| 13.7 | `DB.transferLevel = 2`; `Application.LoadLevel(4)` | L76787-76791 |

**Arena loot roll and thresholds:**

```
availableSlot = first i with DB.inventory[i] == -1, else -1                    [L76433-76473]
if availableSlot != -1:                                                         [L76476-76478]
    lootFrame.position = (0, 5.61, -7.4); lootFrameAnim.Play("pop")             [L76482-76493]
    lootText.position  = (0, 6, -7);      lootTextAnim.Play("pop")              [L76497-76510]
    whichTable = 0                                                              [L76513-76514]
    for i = Level.arenaTable.length-1 down to 0:                                [L76518-76536, L76590-76597]
        if totalKills >= Level.arenaTable[i].requiredKills:                     [L76540-76561]
            whichTable = Level.arenaTable[i].whichTable;  break                 [L76566-76587]
    randomDrop = DB.lootTables[whichTable].tableContents[
                     Random.Range(0, DB.lootTables[whichTable].tableContents.length) ]   [L76600-76624]
    DB.inventory[availableSlot] = randomDrop                                    [L76627-76633]
    lootTextText[0].text = lootTextText[1].text = DB.itemDB[randomDrop].itemName [L76636-76671]
    lootIcon.material.mainTexture = Resources.Load(DB.itemDB[randomDrop].icon)  [L76674-76691]
else:
    lootTextText[0].text = lootTextText[1].text = "Inventory Full!"             [L76696-76707]
    lootText.position = (0, 6, -7);  lootTextAnim.Play("pop")                   [L76710-76723]
```

- The highest threshold whose `requiredKills <= totalKills` wins (scan from the end).
- `whichTable` is a direct index into `DB.lootTables` (no `rareChance`, no `+1`).
- No gold and no XP are computed in the arena path (`Level.goldReward` / `XPReward` are 0 for arena
  levels in `bh/data/maps.json` anyway, and the code never reads them here).
- The arena always gives one item, even at 0 kills (first threshold is `requiredKills` 0).

Arena thresholds from `bh/data/maps.json` (`arenaTable`), resolved to table names:

| Arena (map, level) | requiredKills → lootTables index (name) |
|---|---|
| Haggerdom Monster Arena (0, 11) | 0 → 1 (Tier 2); 40 → 2 (Tier 3); 70 → 3 (Tier 4); 85 → 4 (Tier 5); 100 → 5 (Tier 6); 115 → 6 (Tier 7) |
| Brightstone Monster Arena (1, 11) | 0 → 3 (Tier 4); 40 → 4 (Tier 5); 65 → 5 (Tier 6); 90 → 6 (Tier 7); 115 → 7 (Tier 8); 140 → 8 (Tier 9) |
| Doomvale Monster Arena (3, 4) | 0 → 4 (Tier 5); 15 → 5 (Tier 6); 30 → 6 (Tier 7); 50 → 7 (Tier 8); 70 → 8 (Tier 9) |

**Worked arena example:** Haggerdom arena, party wiped at `totalKills = 72`. Scan: 115? no; 100?
no; 85? no; 70? yes → `whichTable = 3` (Tier 4, 25 entries). `Random.Range(0,25)` → e.g. 21 →
`tableContents[21] = 37` → "Bandit's Satchel". If the stored `highScore` was below 72 it becomes 72
and the record banner shows.

---

## 7. `levelUpEnemies()` — arena difficulty tier [IL L70187-70259]

```
enemyTier += 1                                                                  [L70195-70200]
for i = 0 .. enemyScripts.length-1:                                             [L70203-70205, L70248-70256]
    if enemyScripts[i] exists:                                                  [L70207-70212]
        enemyScripts[i].maxHealth = (int)(enemyScripts[i].maxHealth * 1.1)      [L70214-70227]
        enemyScripts[i].power     = (int)(enemyScripts[i].power     * 1.1)      [L70228-70241]
    else:
        i = enemyScripts.length          # stop at the first empty slot          [L70244-70247]
```

- Truncating integer result each time; compounds per call (×1.1ⁿ with truncation).
- Only `maxHealth` and `power` are changed (current health is not touched here).
- The loop **stops at the first null entry** of `enemyScripts`.
- **Trigger** (in `enemySpawn`, outside this range): arena mode only, each time a wave is fully
  spawned and `activeEnemies == 0`: `currentWave = Random.Range(0, Level.waves.length)`, then
  `if totalKills > enemyTier * 10: levelUpEnemies()` [IL L65119-65175]. `enemyTier` starts at 1
  [IL L59281-59282], so the first bump needs more than 10 kills, the second more than 20, etc.,
  at most one bump per wave clear.

## 8. `updateScore()` [IL L70262-70336]

Called from `Awake` [IL L61646] and after each arena kill [IL L28114].
- `arenaMode`: if `score.parent != pauseTransform` → `score.parent = pauseTransform`,
  `score.localPosition = (0.2, 0, 0)` [IL L70273-70298]; `scoreText.text = "Score: " + totalKills`
  [IL L70299-70306].
- not arena: `score.position.x = 100` (moved off-screen) [IL L70309-70334].

---

## 9. Action bar

### 9.1 `updateActionBar(float timeDelay)` [IL L70852-71585]

Started from `playerControl` [IL L63415], right after `selectionCircleAnim.Play("show")`
[IL L63396-63398]; skipped while `DB.tutorial` is true and `tutorialState < 34` [IL L63402-63410].
Shows the selected hero's ability icons.

1. `freezeUI = true` [IL L70894-70897]; wait `timeDelay` seconds [IL L70898-70903].
2. `flashIcon[0] = flashIcon[1] = flashIcon[2] = false` [IL L70906-70926]; `freezeUI = false`
   [IL L70927-70930].
3. If `leaderScript` is null → end [IL L70931-70935]. Otherwise:
4. `actionBarAnimation.Play("show")` [IL L70937-70941].
5. Put away the old icons: for `n = 0,1,2`, if `currentIcons[n] != null`:
   `currentIcons[n].parent = actionBar` and `currentIcons[n].localPosition.y = 1`
   [IL L70943-71000, L71002-71059, L71061-71118].
6. **Button 1** (always): `icon = classIcons[(leaderScript.characterClass - 1) * 5]`;
   `icon.parent = actionButton1`; `icon.localPosition = (0,0,0)`; `icon.localScale = (1,1,1)`;
   `currentIcons[0] = icon` [IL L71120-71192].
7. **Button 2**: if `leaderScript.abilities[1] != 0` [IL L71193-71199]:
   `icon = classIcons[(characterClass - 1) * 5 + abilities[1] - 1]`; parent `actionButton2`,
   localPosition `(0,0,0)`, localScale `(1,1,1)`; `currentIcons[1] = icon` [IL L71201-71309];
   `actionButton2.localPosition.y = 0` (visible) [IL L71310-71345].
   Else `actionButton2.localPosition.y = 1` (hidden) [IL L71349-71384].
8. **Button 3**: same with `abilities[2]` and `actionButton3` [IL L71386-71538]; hidden branch
   `actionButton3.localPosition.y = 1` [IL L71542-71577].

Icon index rule: each class owns 5 consecutive `classIcons` entries starting at
`(characterClass-1)*5`; button 1 always shows entry +0; buttons 2/3 show entry
`+ (abilities[n] - 1)` where `abilities[n]` is the 1-based power number chosen for that slot
(0 = no ability in that slot).

**Cooldown display is not in this method.** `updateActionBar` never reads `cooldowns`,
`remainingCooldowns`, `shades` or `flashers`; it only swaps icons and clears `flashIcon`. The
cooldown shading lives elsewhere in `MotherBrain` (see §12).

### 9.2 `disableActionBar()` [IL L71657-71934]

Started from `PartyMember.die` when the dying hero is the current `leaderScript` [IL L87531-87545].

1. `selectionCircle.position.x = 10` [IL L71687-71720]; `leader = null`; `leaderScript = null`
   [IL L71725-71730]; `actionBarAnimation.Play("hide")` [IL L71733-71735].
2. wait 0.08 s [IL L71738-71741].
3. If `leader` is still null [IL L71746-71749]: for `n = 0,1,2`, if `currentIcons[n] != null`:
   `currentIcons[n].parent = actionBar`, `currentIcons[n].localPosition.y = 1`
   [IL L71753-71808, L71812-71867, L71871-71926].

### 9.3 `specialMove(int whichSpecial)` — the power-up freeze before an ability [IL L72012-72393]

Started from `playerControl` with a button index [IL L62058, L62079, L62100] and from
`debugTools` [IL L65464, L65481, L65498]. `whichSpecial` is 0, 1 or 2 (button 1/2/3).

**Preconditions** (all required, else the coroutine ends immediately) [IL L72036-72066]:
`leaderScript` exists; `leaderScript.abilities[whichSpecial] != 0`;
`leaderScript.remainingCooldowns[whichSpecial] <= 0`; `leaderScript.health > 0`.

**Phase 1** [IL L72070-72130]
- `audioPool[3].Play()`
- `leaderScript.commandPending = true`; `leaderScript.invincible = true`
- `leaderScript.browniePoints += 20` [IL L72086-72093]
- `flashIcon[0..2] = false`, then `flashIcon[whichSpecial] = true`
- `disableSpecials = true`
- wait 0.08 s

**Phase 2** (skipped to end if `leaderScript` became null [IL L72136-72138]) [IL L72142-72266]
- `flashIcon[whichSpecial] = false`; `dimBackground = true`
- `cameraShaker.Play("powerUpShake")`; `audioPool[5].Play()`
- `powerUpEffect.position = leader.position`; `powerUpAnimation.Stop()`;
  `powerUpAnimation.Play("effect")`
- `leaderScript.AIState = 5` [IL L72184-72186]
- **Cooldown assignment** [IL L72189-72226]:
  ```
  if leaderScript.noCooldownChance > 0 and Random.Range(0, 100) <= leaderScript.noCooldownChance:
      leaderScript.remainingCooldowns[whichSpecial] = 0.2
  else:
      leaderScript.remainingCooldowns[whichSpecial] = leaderScript.cooldowns[whichSpecial]
  ```
  (int `Random.Range(0,100)` gives 0..99, so the chance is `(noCooldownChance + 1) %`.)
- `leaderScript.myAnimation.Stop("hitReact")`; `leaderScript.myAnimation.Play("powerUp")`
- `Time.timeScale = 0.1` [IL L72240-72241]
- `leaderScript.colorSpeed = 4`; `leaderScript.activateColors()`;
  `leaderScript.myRenderer.material.color = (1.3, 1.3, 1.3)`
- wait 0.052 s of game time [IL L72263-72266] (at timeScale 0.1 this is 0.52 s of real time —
  engine behaviour).

**Phase 3** [IL L72271-72386]
- If `leaderScript` still exists: `powerUpEffect.position.x = 20`; `disableSpecials = false`;
  `Time.timeScale = 1`; `dimBackground = false`; `leaderScript.commandPending = false`;
  `leaderScript.invincible = false`; then
  `leaderScript.StartCoroutine(leaderScript.performSpecial(whichSpecial))` [IL L72276-72340].
- Else: `powerUpEffect.position.x = 20`; `Time.timeScale = 1`; `dimBackground = false`
  [IL L72345-72386]. Note this branch does **not** reset `disableSpecials`.

---

## 10. Small helpers

### `hideLine(int whichLine)` [IL L70681-70765]
Wait 0.5 s [IL L70699-70702]; then if `touchState[whichLine] < 2`:
`drawnDot[whichLine].parent.position.z = 10` (hides that drag line) [IL L70705-70757].

### `delayedPetCommand(PartyMember whichAlly)` [IL L76862-76908]
Started from `playerControl` [IL L63551]. Wait 0.5 s [IL L76875-76878]; then if
`whichAlly.petScript.myTarget == null`:
`whichAlly.petScript.movementTarget = whichAlly.movementTarget + (0.5, 0, 0.4)` [IL L76882-76901].

### `muteSoundEffects()` [IL L70407-70444]
If `DB.soundEnabled` is false: set `volume = 0` on every `audioPool[i]`.

### `handleBackButton()` [IL L70460-70599]
On `Input.GetKeyDown(27)` (Escape / Android back) [IL L70476-70478]:
- not paused and `Time.timeScale == 1`: `cachedTimeScale = Time.timeScale`; `Time.timeScale = 0`;
  `pauseScreen.localPosition.y = 0`; `paused = true` [IL L70480-70523].
- else if paused: `Time.timeScale = cachedTimeScale`; `paused = false`;
  `pauseScreen.localPosition.y = 10`; `disableInput = true`; every existing
  `playerScripts[i].flee = true`; `MotherBrain.flee = 0` (starts the exit timer → the party
  flees the battle; back pressed while paused = quit level) [IL L70526-70597].

---

## 11. Cross-references

| What | Where |
|---|---|
| `levelCompleteSequence` started | `MotherBrain.enemySpawn` IL L65090-65114 (method 65073–65393) |
| `levelUpEnemies` called | `MotherBrain.enemySpawn` IL L65145-65175 |
| `XPBarAnimation` started every frame | `MotherBrain.Update` IL L61763-61783 (method 61653–61850) |
| exit timer `flee`, fade, `LoadLevel(4)`, `transferLevel` 2 / 5 | `MotherBrain.Update` IL L61670-61744 |
| `defeatSequence`, `disableActionBar` started | `PartyMember.$die$1765` IL L87503-87545 (87268–88335) |
| `updateActionBar`, `delayedPetCommand`, `specialMove` started | `MotherBrain.playerControl` IL L63415, L63551, L62058/62079/62100 (61853–63786); `debugTools` IL L65464-65498 |
| `updateScore` called | `MotherBrain.Awake` IL L61646; `EnemyScript.$die$1354` IL L28114 |
| `totalKills += 1` (arena only) | `EnemyScript.$die$1354` IL L28098-28110 |
| `bonusGold` set up | `MotherBrain.Awake` IL L60905-60948, L61343-61346 |
| `PartyMember.bonusXP` set up | `PartyMember..ctor` IL L77086; `MotherBrain.Awake` IL L60963-61009; `PartyMember.initialize` IL L77993-77996 (77121–78037) |
| `browniePoints` sources | `specialMove` +20 [IL L72086-72093]; `EnemyScript.takeDamage` +20 to its PartyMember argument [IL L18944-18947], and +2 when that PartyMember's `characterClass == 7` else +4 [IL L19044-19062]; `PartyMember.heal` +5 to its PartyMember argument [IL L82583-82588] (the conditions surrounding these adds were not traced) |
| `Database.populateMerchant` | IL 2385–2542 |
| `PartyMember.performSpecial(int)` | called at IL L72336-72340 |
| `PartyMember.deselect()`, `.flash()`, `.activateColors()` | called at IL L72663, L74541 / L75078, L72251 |
| `Level.complete` / `highScore` / `finalBossKill` persisted | `Database.save` (1001–1682) reads them IL L1511, L1577, L1656; `Database.load` (1685–2337) writes them IL L2197-2208, L2240, L2319 |
| `Level.complete` read by menu/map code | IL L39619, L39715, L40033, L40359, L55592, L55802 (not analysed here) |
| data tables | `bh/data/globals.json` (firstLevelXP, XPtable, inventory), `bh/data/maps.json` (goldReward, XPReward, lootTable, rareChance, arenaTable, prereq), `bh/data/loot_tables.json`, `bh/data/items.json` (ids 36–39) |

---

## 12. Uncertain / not determined

- `finalBrowniePoints` is never allocated or assigned in code outside `levelCompleteSequence`
  (only the field declaration IL L59237 exists elsewhere). UNVERIFIED: its inspector value is
  `[-1,-1,-1,-1]`; the ranking logic only works as described if it is (it tests `== -1`).
- UNVERIFIED: the order in which `PartyMember.bonusXP` is built (ctor 100 → `Awake` adds trinket
  power → `initialize` divides by 100). The three sites are cited; the call order between
  `MotherBrain.Awake` and `PartyMember.initialize` was not traced. The only reading that yields a
  sane multiplier is `(100 + Σpower)/100`.
- **What a character gains on level-up beyond `level += 1`** (health/power/defense growth,
  ability unlocks) is not in this range. UNVERIFIED: stats are derived from `Player.level` at
  battle start (e.g. via `powerScale` / `defenseScale` / `healthScale` in `bh/data/classes.json`)
  in `PartyMember.initialize` / `MotherBrain.Awake`.
- **Level unlocking:** the only thing this code does is set `Level.complete = true`
  [IL L72680-72694]. How `Level.prereq` / `prereqLoc` use it to unlock the next node is in the
  map/menu code (reads listed in §11), not analysed here.
- **Saving:** no `Database.save()` call occurs in this range; gold, XP, level, inventory,
  `complete` and `highScore` are modified in memory only. Where the save happens after
  `LoadLevel(4)` was not traced.
- **Cooldown display** on the action bar (`shades`, `flashers`, `flashIcon` consumption) is not in
  `updateActionBar`; UNVERIFIED: it is in `MotherBrain.interfaceAnimation` (IL 64108–64611).
- Which of `darkBar` / `lightBar` is visually in front, and the text content of the banner objects
  (`victoryText`, `spoilsText`, `defeatText`, `arenaText`, `killsText`, `recordText`,
  `levelUpText`) are scene assets, not in the IL. Only "Score: ", " XP" and "Inventory Full!" are
  literal strings in code.
- `XPTextText[i+4]` and the second element of `goldTextText` / `lootTextText` /
  `killCountTextText` receive the same string as the first. UNVERIFIED: they are drop-shadow copies.
- Meaning of `AIState` values 1 and 5, `fadeStatus` 2, `transferLevel` 2 / 5, scene index 4, and
  audio clips at `audioPool[3]`, `[4]`, `[5]` are defined by other code/assets. From usage here:
  `AIState = 1` precedes every scripted walk to `movementTarget`; `AIState = 5` is set during the
  power-up pose; `fadeStatus = 2` is set together with enabling the fader before a scene change.
- Edge case derived from the code, not observed: if a survivor already had `XP >= nextLevelXP`
  before the reward (dark and light bars both at −0.82) and no other bar is moving, the level-up
  fires in the first frame while `noAnimation` is still true, so the sequence ends that frame and
  any further owed level-ups are not processed in that battle (the XP stays banked).
- Whether a level cap exists elsewhere was not determined; none is enforced here.
- `Level.goldReward 81 / XPReward 162` on "Transition to Map 3" (map 1 level 14, `waves` length 1 in
  `bh/data/maps.json`) — whether that node can actually be fought was not determined.

### Contradictions with older notes

1. `work/non-encounter-systems-research.md` (Curve row) says the loop uses `XPtable[i-2]`.
   The IL indexes `XPtable[i]` for `i = 2..level` [IL L70365-70371] and truncates to int after each
   multiply. The same note says the table values are "unextracted"; they are in
   `bh/data/globals.json`.
2. Same file (Drop rules row): "filtered by party max level; `rareChance` gates a rarer second
   roll". The IL never reads `minLevel`/`maxLevel`, and `rareChance` only switches the single roll
   to table `lootTable + 1` [IL L73344-73495].
3. Same file (Currency row) and `work/battleheart-encounter-parity.md` ("In-combat gold:
   `$goldReward`/`$randomDrop` coroutines exist (drops during fight)"): `$goldReward$1675` and
   `$randomDrop$1677` are hoisted **locals of `levelCompleteSequence`** [IL L72440-72442], and
   `$randomDrop$1734` of `defeatSequence` [IL L75706]. There are no mid-fight drops in this code.
4. Same files: "XP split among survivors". It is not a division: each survivor gets the full
   `Level.XPReward` × a fixed multiplier (4 / 2 / 1.33 / 1) × their own `bonusXP` [IL L73993-74218].
   The "Level-up UX" row's "`browniePoints` per member awarded" is also inaccurate: brownie points
   are an input (ranking → +0.25 / +0.16 / +0.08 XP multiplier), not something awarded at level-up.
5. Datamine `docs/02-damage-system.md` §7 and `battleheart-encounter-parity.md`: "`levelUpEnemies`
   trigger unknown" and "every currently-spawned enemy". Trigger is the arena wave-clear check
   `totalKills > enemyTier*10` [IL L65145-65175]; the loop covers `enemyScripts` only up to the
   first null slot [IL L70207-70247].
6. `Database` ctor defaults (`firstLevelXP = 50`, `XPscale = 1.1`) [IL L909-913] differ from
   the serialized values in `bh/data/globals.json` (30, 1.35). The serialized values are the
   live ones; `XPscale` is unused by `calculateNextLevelXP`.

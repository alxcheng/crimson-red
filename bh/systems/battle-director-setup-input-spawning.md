# Battle director: setup, touch input, wave spawning, pause (`MotherBrain`)

**Scope:** class `MotherBrain` — class header, all 150 field declarations, `.ctor`, `Awake`, `Update`,
`playerControl`, `mouseControl`, `pauseInput`, `remoteUpdates`, `interfaceAnimation`, `orientScreen`,
`hideLine` (+ its coroutine body `$hideLine$1627`), `OnApplicationPause`, `fade`, `partyEntrance`,
`populateEnemyPools`, `enemySpawn`, `debugTools`, `tutorialDriver` (summary only), `levelUpEnemies`,
`updateScore`, `calculateNextLevelXP`, `muteSoundEffects`, `handleBackButton`, `Main`, and the stubs of
the coroutines whose bodies live outside this range.
**IL range:** `Assembly-UnityScript.il` L59090–70770.

Citations are `[IL Lnnnnn]` = line numbers in that file. Data ids are resolved through `bh/data/*.json`.

---

## 1. Summary

`MotherBrain` is the single per-battle controller object. When the battle scene loads it:

- finds the persistent `Database` object, reads the chosen level (`DB.levelDB[DB.currentMap].whichLevel[DB.whichLevel]`),
  loads its background, music, and enemy set;
- instantiates the (up to 4) party members from `Resources/Allies/<playerName>`, computes their battle stats
  (base + per-level class scaling + gear + trinket effects) and attaches weapon/shield models;
- pre-instantiates **6 pooled copies of every enemy type** of the level's enemy set;
- walks the party in from the left, fades in from black, starts the music after 0.7 s.

Every frame it reads touches (tap a hero = select him and show his 3 ability buttons; press a hero and drag =
draw a line to the ground / an enemy / an ally and on release issue a move or target order; tap an ability
button = fire that special; tap the pause button = freeze time and show the pause screen), drives all
heroes and enemies (`remoteUpdate`), animates the cooldown shades / button flashes, and runs the wave
spawner: each `Wave` is an ordered list of enemy-type ids that are released one at a time with a delay,
never more than `maxEnemies` alive at once; when the list is exhausted and nobody is alive the next wave
starts; after the last wave the victory sequence runs. Arena levels pick waves at random forever and make
all enemies 10 % stronger each time the kill count passes another multiple of 10.

---

## 2. Fields

All 150 fields are declared at `[IL L59093-59242]`. "Default" = value written by the constructor
`[IL L59245-59302]`; every *public* field without a constructor default is a Unity Inspector/scene value
that is **not visible in the IL** (object references wired in the scene, or serialized numbers).
"Used here" lists the methods of this document that touch the field (r = read, w = write);
"ext" = it is also used by code outside L59090–70770 (other docs).

### 2.1 Level / wave / spawning state

| Field | Type | Decl. | Default | Meaning | Used here |
|---|---|---|---|---|---|
| `DB` | `Database` | L59188 | – | The persistent save/data object. Found by name in `Awake`. | almost all; ext |
| `whichMap` | `string` | L59131 | `"forest1"` [IL L59257] | Battlefield background name; overwritten from `Level.whichMap` | `Awake` rw |
| `enemySet` | `string` | L59132 | `"goblin"` [IL L59260] | Enemy-prefab family name; overwritten from `Level.enemySet` | `Awake` w, `populateEnemyPools` r |
| `totalEnemyTypes` | `int` | L59133 | `1` [IL L59263] | Number of enemy types in the set to pool; overwritten from `Level.totalEnemyTypes` | `Awake` w, `populateEnemyPools` r |
| `waves` | `Wave[]` | L59134 | – | **Never read or written by any code** (the spawner reads `DB…Level.waves` directly) | – |
| `currentWave` | `int` (private) | L59192 | 0 (CLR default) | Index of the wave being spawned | `Awake`, `enemySpawn` |
| `wavePosition` | `int` | L59135 | 0 | Index of the next entry in `Wave.enemies` to spawn | `enemySpawn` |
| `spawnDelay` | `float` | L59136 | 0 | Countdown (seconds) until the next spawn is allowed | `Awake` w, `enemySpawn` rw |
| `spawnCooldown` | `float` | L59137 | 0 | Value `spawnDelay` is reset to after each spawn (= `Wave.spawnDelay`) | `Awake` w, `enemySpawn` rw |
| `activeEnemies` | `int` | L59138 | 0 | Number of enemies currently alive/on the field. Incremented here on spawn; changed by `EnemyScript` elsewhere | `enemySpawn` rw; ext |
| `maxEnemies` | `int` | L59139 | `3` [IL L59266] | Concurrent-enemy cap for the current wave (= `Wave.maxEnemies`) | `Awake` w, `enemySpawn` r |
| `totalKills` | `int` | L59204 | 0 | Kill counter (incremented in `EnemyScript`, ~L28107) | `enemySpawn` r, `updateScore` r; ext |
| `enemyTier` | `int` (private) | L59205 | `1` [IL L59281] | Arena difficulty tier | `enemySpawn` r, `levelUpEnemies` rw |
| `arenaMode` | `bool` | L59206 | false | True when `Level.arena` | `Awake` w, `enemySpawn` r, `updateScore` r; ext |
| `levelComplete` | `bool` | L59229 | false | Set true by the victory/defeat sequences (outside range, L72577 / L87529) | `Update` r, `OnApplicationPause` r, `enemySpawn` r |
| `bonusGold` | `float` | L59103 | `100.0` [IL L59254] | Gold multiplier; becomes `(100 + Σ gold-trinket power)/100` in `Awake` | `Awake` rw; ext (L73011) |
| `playerScripts` | `PartyMember[]` | L59153 | – (Inspector-sized) | Party slots 0-3 (null where `DB.party[i] == -1`) | many; ext |
| `enemyScripts` | `EnemyScript[]` | L59154 | – (Inspector-sized) | Enemy pool: 6 consecutive entries per enemy type | `Awake`, `remoteUpdates`, `populateEnemyPools`, `enemySpawn`, `levelUpEnemies`, tutorial; ext |
| `cieling` (sic) | `float` | L59176 | `4.3` [IL L59272] | Upper z bound of the battlefield | `playerControl` r; ext |
| `edge` | `float` | L59177 | `3.42` [IL L59275] | ±x bound of the battlefield | ext only |
| `floor` | `float` | L59178 | `-2.8` [IL L59278] | Lower z bound of the battlefield | ext only |
| `buffDurations` | `float[]` | L59140 | – | Buff duration table (Inspector) | ext only |
| `buffMagnitudes` | `float[]` | L59141 | – | Buff magnitude table (Inspector) | ext only |
| `debuffDurations` | `float[]` | L59142 | – | Debuff duration table (Inspector) | ext only |
| `debuffMagnitudes` | `float[]` | L59143 | – | Debuff magnitude table (Inspector) | ext only |
| `finalBrowniePoints` | `int[]` | L59237 | – | ext only (victory sequence) | – |
| `partyFormUp` | `bool` | L59238 | false | ext only (written L72716, read by `PartyMember` L78917) | – |
| `finalBossFirstKill` | `bool` | L59239 | false | Written at L75645 (outside); selects the exit destination in `Update` | `Update` r |

### 2.2 Flow / timing / fade / pause

| Field | Type | Decl. | Default | Meaning | Used here |
|---|---|---|---|---|---|
| `initialDelay` | `float` (private) | L59208 | `0.7` [IL L59284] | Seconds after scene start before anything (input, AI, spawning) runs | `Update` rw |
| `disableInput` | `bool` | L59231 | `true` [IL L59296-59300] | When true `playerControl` is not called. See §11 (who clears it) | `Awake` w, `Update` r, `pauseInput` w, `handleBackButton` w, tutorial w; ext |
| `disableSpecials` | `bool` | L59230 | false | Blocks ability buttons **and** tap-selection | `Awake` w, `playerControl` r, `debugTools` r, tutorial w; ext |
| `paused` | `bool` (private) | L59186 | false | Pause screen is up | `Update` r, `playerControl` w, `pauseInput` w, `handleBackButton` rw |
| `cachedTimeScale` | `float` (private) | L59219 | 0 | `Time.timeScale` saved when pausing | `playerControl` w, `pauseInput` r, `handleBackButton` rw |
| `flee` | `float` (private) | L59222 | `-1.0` [IL L59287] | Exit timer; `< 0` = inactive, set to 0 to start leaving the battle (only counts while `disableInput` is true) | `Update` rw, `pauseInput` w, `handleBackButton` w, tutorial rw; ext (L75620) |
| `fadeStatus` | `int` | L59228 | `1` [IL L59296] | 1 = fading in (black overlay alpha ↓), 2 = fading out (alpha ↑) | `Awake` w, `Update` w, `fade` r, tutorial w; ext |
| `fader` | `Renderer` | L59227 | – | Full-screen black overlay | `Update`, `fade`, tutorial; ext |
| `freezeUI` | `bool` | L59223 | false | When true the cooldown shades are not updated | `interfaceAnimation` r; ext |
| `baseFlashDelay` | `float` | L59224 | `0.1` [IL L59290] | Period of the ability-button "flash" blink | `interfaceAnimation` r |
| `flashDelay` | `float` (private) | L59225 | `0.1` [IL L59293] | Running blink timer | `interfaceAnimation` rw |
| `musicTime` | `float` (private) | L59226 | 0 | Music position saved on app suspend | `OnApplicationPause` rw |
| `animateXPBars` | `bool` | L59236 | false | While true `Update` starts `XPBarAnimation()` every frame | `Update` r; ext |
| `dimBackground` | `bool` | L59182 | false | Background tint target: true → 0.35 grey, false → white | `interfaceAnimation` r; ext |
| `flashIcon` | `bool[]` | L59183 | – | Per ability button (0-2): blink it | `interfaceAnimation` r, `debugTools` w; ext |

### 2.3 Input state

Per-finger arrays are indexed by `Touch.fingerId`; the code loops ids 0..9 `[IL L63679, L63781]`.

| Field | Type | Decl. | Default | Meaning | Used here |
|---|---|---|---|---|---|
| `touchState` | `int[]` | L59156 | – | Per finger: 0 idle, -1 consumed, 1 pressed on a hero, 2 dragging (ally/ground line), 3 dragging (enemy/ground line) — see §5.2 | `playerControl`, `$hideLine` |
| `touchReleaseCheck` | `int[]` | L59155 | – | Per finger: 1 if that finger is still down this frame | `playerControl`, `mouseControl`, `pauseInput` |
| `touchContactPosition` | `Vector2[]` | L59157 | – | Screen position where the finger first hit a hero | `playerControl` |
| `leaderCandidate` | `Transform[]` | L59166 | – | Per finger: the hero that finger pressed | `playerControl` |
| `targetCandidate` | `Transform[]` | L59167 | – | Per finger: ally/enemy currently under the dragged finger (null = ground) | `playerControl` |
| `leader` | `Transform` | L59164 | null | Currently selected hero | `playerControl` rw, `interfaceAnimation` r, `debugTools` r; ext |
| `leaderScript` | `PartyMember` | L59165 | null | Its script | `playerControl` rw, `interfaceAnimation` r, tutorial r; ext |
| `draggingThreshold` | `float` | L59170 | `5.0` [IL L59269] | Screen-pixel distance a press must move to become a drag. Overwritten by `dynamicbackgroundhandler` to `Screen.width / 24` [IL L108096-108103] | `playerControl` r |
| `partyMask` | `LayerMask` | L59158 | – | Raycast layer of heroes | `playerControl` |
| `actionBarMask` | `LayerMask` | L59159 | – | Raycast layer of ability buttons + pause button | `playerControl` |
| `groundMask` | `LayerMask` | L59160 | – | Raycast layer of the ground plane | `playerControl` |
| `enemyMask` | `LayerMask` | L59161 | – | Raycast layer of enemies | `playerControl` |
| `okayMask` | `LayerMask` | L59220 | – | Pause-screen button that resumes | `pauseInput` |
| `cancelMask` | `LayerMask` | L59221 | – | Pause-screen button that flees the battle | `pauseInput` |
| `cameraLens` | `Camera` | L59162 | – | Camera used for `ScreenPointToRay` | `playerControl`, `pauseInput` |
| `touch` | `Touch` (private) | L59207 | – | Scratch | input methods |
| `totalTouches` | `int` (private) | L59214 | 0 | `Input.touchCount` (or 1 for a mouse) | `playerControl`, `mouseControl` |
| `theFingerId` | `int` (private) | L59215 | 0 | Finger id being processed | input methods |
| `tapPosition` | `Vector2` (private) | L59216 | – | Screen position being processed | input methods |
| `fakeTap` | `bool` (private) | L59217 | false | True when the "touch" is the mouse | `playerControl`, `mouseControl`, tutorial |
| `touchReleased` | `bool` (private) | L59218 | false | **Never referenced** | – |
| `tempRay`, `tempHit` | `Ray`, `RaycastHit` (private) | L59209-59210 | – | Scratch | `playerControl`, `pauseInput` |
| `tempAllyScript` | `PartyMember` (private) | L59211 | – | Scratch | `playerControl` |
| `tempEnemyScript` | `EnemyScript` (private) | L59212 | – | Scratch | `playerControl` |
| `tempAnimation` | `Animation` (private) | L59213 | – | **Never referenced** | – |
| `tempGO`, `tempTransform` | `GameObject`, `Transform` (private) | L59190-59191 | – | Scratch | `Awake` |

### 2.4 Scene objects used in this range (Inspector references)

| Field | Type | Decl. | Meaning | Used here |
|---|---|---|---|---|
| `BGMusic` | `AudioSource` | L59130 | Battle music | `Awake`, `Update`, `OnApplicationPause`, tutorial |
| `victoryMusic` | `AudioSource` | L59093 | Victory jingle; faded out in `fade` | `fade`; ext |
| `audioPool` | `AudioSource[]` | L59187 | UI sound effects. Indices used here: `[0]` target-order sound, `[1]` press-on-hero sound, `[2]` move-order sound, `[3]` select sound (see §5) | `playerControl`, `muteSoundEffects`, tutorial; ext |
| `backgroundRenderer` | `Renderer` | L59179 | Battlefield background quad | `Awake`, `interfaceAnimation` |
| `interfaceRenderer` | `Renderer` | L59180 | UI atlas renderer | `Awake` |
| `selectionCircleRenderer` | `Renderer` | L59181 | Selection-circle renderer | `Awake` |
| `selectionCircle` / `selectionCircleAnim` | `Transform` / `Animation` | L59168-59169 | Circle under the selected hero; clip `"show"` | `playerControl`, `interfaceAnimation`; ext |
| `drawnLine[]`, `drawnDot[]`, `drawnTip[]` | `Transform[]` | L59171-59173 | Per finger: the command line (origin/rotation), its far-end dot, its arrow tip | `playerControl`, `$hideLine`; ext |
| `lineRenderer[]` | `Renderer[]` | L59174 | Per finger: line material (texture-offset selects colour/style) | `Awake`, `playerControl` |
| `lineAnim[]` | `Animation[]` | L59175 | Per finger: clips `"idle"`, `"pulse"`, `"hide"` | `playerControl` |
| `actionBar` / `actionBarAnimation` | `Transform` / `Animation` | L59144-59145 | Ability bar; clips `"show"`, `"hide"`, `"tap1"`, `"tap2"`, `"tap3"` | `Awake`, `playerControl`, `interfaceAnimation`, `debugTools`; ext |
| `actionButton1/2/3` | `Transform` | L59146-59148 | The three ability buttons | `playerControl`, `interfaceAnimation`; ext |
| `shades[]` | `Transform[]` | L59149 | Cooldown shade over each button | `interfaceAnimation` |
| `flashers[]` | `Transform[]` | L59150 | Blink overlay for each button | `interfaceAnimation` |
| `cameraShaker` | `Animation` | L59163 | Camera shake; clips `"powerUpShake"`, `"shake"` | `Awake`, `debugTools`; ext |
| `powerUpAnimation` | `Animation` | L59185 | Clip `"effect"` | `Awake`; ext |
| `pauseScreen` | `Transform` | L59189 | Pause overlay: `localPosition.y = 0` shown, `= 10` hidden | `playerControl`, `pauseInput`, `handleBackButton` |
| `pauseTransform` | `Transform` | L59240 | Pause-button object (score label is parented to it in arenas) | `updateScore` |
| `score` / `scoreText` | `Transform` / `TextMesh` | L59241-59242 | Arena score label | `updateScore` |

### 2.5 Tutorial-only fields

| Field | Type | Decl. | Meaning |
|---|---|---|---|
| `tutorialState` | `int` (public) | L59196 | Tutorial step 1..47 (0 outside the tutorial) |
| `tutorialStrings` | `string[]` | L59232 | Tutorial texts (Inspector data, not in the IL) |
| `tutorialWindow` | `Transform` (private) | L59193 | Dialog window (`Resources/TutorialWindow`) |
| `lucilleIcon`, `shepherdIcon` | `Renderer` (private) | L59194-59195 | Speaker portraits (children `"lucille"`, `"shepherd"`) |
| `tutorialText` | `TextPrint` (private) | L59197 | Typewriter text on child `"Dialog"` |
| `tutorialHand` / `tutorialHandScript` | `Transform` / `HandScript` (private) | L59198-59199 | Animated pointing hand (`Resources/TutorialHand`) |
| `tutorialArrow`, `tutorialArrow2` | `Transform` (private) | L59200-59201 | Destination markers (`Resources/TutorialArrow`) |
| `tutorialDummy` | `EnemyScript` (private) | L59202 | Training dummy (`Resources/dummy`) |
| `tutorialReleaseCheck`, `tutorialTouchCount`, `tutorialTouchState` | `int` (private) | L59233-59235 | Tap-edge detection for "tap to continue" |

### 2.6 Declared here but only used outside this range (victory / defeat / XP / loot screens, effects)

No method in L59245–70770 reads or writes these; they are listed so the field inventory is complete.

| Field(s) | Type | Decl. |
|---|---|---|
| `killsText`, `recordText`, `killCountText`, `arenaText`, `defeatText`, `lootFrame`, `goldText`, `spoilsText`, `lootText`, `victoryText`, `powerUpEffect` | `Transform` | L59094, 59096, 59098, 59101, 59104, 59115, 59118, 59122, 59124, 59127, 59184 |
| `killsTextAnim`, `recordTextAnim`, `killCountAnim`, `arenaTextAnim`, `defeatTextAnim`, `lootFrameAnim`, `goldTextAnim`, `spoilsTextAnim`, `lootTextAnim`, `victoryTextAnim` | `Animation` | L59095, 59097, 59099, 59102, 59105, 59116, 59119, 59123, 59125, 59128 |
| `killCountTextText`, `goldTextText`, `lootTextText`, `XPTextText` | `TextMesh[]` | L59100, 59120, 59126, 59112 |
| `levelUpTextTimer` | `float[]` | L59106 |
| `levelUpText`, `darkBar`, `lightBar`, `XPBars`, `currentIcons`, `classIcons` | `Transform[]` | L59107, 59109, 59110, 59111, 59151, 59152 |
| `levelUpTextAnim`, `XPBarAnim`, `XPTextAnim` | `Animation[]` | L59108, 59113, 59114 |
| `lootIcon`, `coinIcon` | `Renderer` | L59117, 59121 |
| `loadingText` | `Renderer` | L59129 — **never referenced anywhere in the assembly** |
| `fullScreenFlash` | `EffectScript` | L59203 |

---

## 3. `Awake` — battle setup `[IL L59305-61650]`

Runs once when the battle scene loads. Below, `LEVEL` means
`DB.levelDB[DB.currentMap].whichLevel[DB.whichLevel]` (this exact chain is repeated for every access).

### 3.1 Database and level data

1. `DB = GameObject.Find("**DATABASE").GetComponent("Database")`; if no such object exists, use
   `GameObject.Find("**DATABASE_Sandboxonly")` instead `[IL L59319-59339]`.
2. If `LEVEL.arena` is true: `arenaMode = true` and `currentWave = Random.Range(0, LEVEL.waves.length)`
   (integer range, upper bound exclusive → a random starting wave) `[IL L59340-59375]`. Otherwise
   `currentWave` stays 0.
3. `whichMap = LEVEL.whichMap`; `enemySet = LEVEL.enemySet`; `totalEnemyTypes = LEVEL.totalEnemyTypes`
   `[IL L59376-59420]`.
4. `BGMusic.clip = Resources.Load(LEVEL.music)` (e.g. `"Music/BattleTheme"`) `[IL L59421-59438]`. It is not
   played yet (see `Update`).
5. If **not** `DB.tutorial` `[IL L59439-59500]`:
   - `spawnDelay    = LEVEL.waves[currentWave].initialDelay`
   - `maxEnemies    = LEVEL.waves[currentWave].maxEnemies`
   - `spawnCooldown = LEVEL.waves[currentWave].spawnDelay`
6. If `DB.tutorial` `[IL L59503-59633]`: instantiate `Resources "TutorialWindow"`, `"TutorialArrow"` (twice →
   `tutorialArrow`, `tutorialArrow2`), `"TutorialHand"`, `"dummy"` (its `EnemyScript` → `tutorialDummy`); fetch
   `HandScript` from the hand, renderers of window children `"lucille"` / `"shepherd"`, `TextPrint` of child
   `"Dialog"`; set `tutorialState = 1`, `disableInput = true`, `disableSpecials = true`,
   `tutorialWindow.localPosition.y = 2`.

### 3.2 Party creation — loop `i = 0 .. DB.party.length-1` `[IL L59634-59638, L61330-61341]`

`DB.party[i]` is an index into `DB.partyDB` (see `bh/data/party.json`), or `-1` for an empty slot. Empty slots
are skipped entirely (`playerScripts[i]` stays null) `[IL L59641-59646]`. For an occupied slot, with
`P = DB.partyDB[DB.party[i]]` and `C = DB.powerDB[P.characterClass - 1]` (so `characterClass` is **1-based**;
`bh/data/classes.json` ids are 0-based: 1 = Cleric, 2 = Knight, 3 = Rogue, 4 = Wizard, 5 = Witch, 6 = Bard,
7 = Barbarian, 8 = Monk, 9 = Ranger, 10 = Paladin):

1. `tempGO = Instantiate(Resources.Load("Allies/" + P.playerName))`; `playerScripts[i] = tempGO.GetComponent("PartyMember")`
   `[IL L59649-59680]`.
2. **Start position** (world x, y, z) by slot `[IL L59682-59730]`:

   | Slot `i` | Start position | Entrance destination (`partyEntrance`, §7) |
   |---|---|---|
   | 0 | (-3.0864179, 0, 0.5977823) | (-0.09960449, 0, 0.597781) |
   | 1 | (-3.8592241, 0, -0.30164829) | (-0.8724099, 0, -0.30164951) |
   | 2 | (-4.402369, 0, 1.110445) | (-1.415554, 0, 1.1104439) |
   | 3 (any other) | (-5.213078, 0, 0.1269366) | (-2.226263, 0, 0.12693539) |

   (Each hero walks ≈ +2.9868 in x. The battlefield spans x ∈ [-3.42, 3.42] — field `edge`.)
3. **Abilities / passives copied from the save** `[IL L59732-59825, L59895-59936]`:
   - `abilities[0..2] = P.abilities[0..2]`
   - `passives[0] = P.passives[0]`, `passives[1] = P.passives[1]`, `passives[3] = P.passives[3]`
   - `passives[2] = 1` if `P.level >= 25`, else `0` (the saved `P.passives[2]` is ignored) `[IL L59895-59918]`
4. **Health** `[IL L59827-59893]`:
   `maxHealth = P.maxHealth + C.healthScale * (P.level - 1)`; `health = maxHealth`.
   (Integer multiply, then converted to float. `party.json`: every hero has `maxHealth` 1000; `classes.json`:
   every class has `healthScale` 15.)
5. **Ability cooldowns** (`cooldowns[]` = full cooldown length in seconds; `Power.cooldown` from `classes.json`)
   `[IL L59945-60055]`:
   - `cooldowns[0] = C.whichPower[0].cooldown` (always)
   - if `abilities[1] != 0`: `cooldowns[1] = C.whichPower[abilities[1] - 1].cooldown`
   - if `abilities[2] != 0`: `cooldowns[2] = C.whichPower[abilities[2] + 1].cooldown`
   - UNVERIFIED: the index arithmetic implies `abilities[1] ∈ {2,3}` (→ powers 1/2) and `abilities[2] ∈ {4,5}`
     (→ powers 5/6, the only other powers with a non-zero cooldown in `classes.json`); the legal values are set
     by the town menu, not here.
6. **Power / defense** `[IL L60063-60243]`:
   ```
   power   = P.power   + C.powerScale   * (P.level - 1)          (float math)
   defense = P.defense + C.defenseScale * (P.level - 1)
   power  += itemDB[P.gear[0]].power                              (weapon; no -1 check)
   if P.gear[1] != -1: defense += itemDB[P.gear[1]].power         (armor)
   ```
7. **Trinkets** — loop `j = 2 .. 3` over `P.gear[j]` (the two accessory slots) `[IL L60251-60255, L61132-61139]`.
   `v = itemDB[P.gear[j]].power`. The code branches on the **item id** (first matching row wins; an id that
   matches no row — including -1/empty — does nothing):

   | Item id(s) | Items (`bh/data/items.json`) | Effect on the hero | IL |
   |---|---|---|---|
   | 12–17 | Swordsman's Gauntlet (3), Power Fist (6), Titan's Glove (10), Energy Ring (3), Firestorm Band (6), Kaimani's Bloodstone (10) | `power += v` | L60258-60316 |
   | 7, 32 | Tome of Mastery (3), Codex of Jabe (6) | `cooldowns[0] -= v; cooldowns[1] -= v; cooldowns[2] -= v` (seconds, flat) | L60319-60447 |
   | 8, 19 | Ring of Regeneration (10), Trollskin Amulet (20) | `passiveRegen += v` | L60450-60508 |
   | 18, 27 | Sprint Shoes (10), Hermes Charm (20) | `moveSpeed = moveSpeed * ((100 + v) / 100)` | L60511-60573 |
   | 20–21 | Warding Amulet (10), Phasing Lodestone (20) | `wardChance += v` (int) | L60576-60633 |
   | 22–23, 28 | Ancient Dragon Tooth (15), Truestrike Monocle (10), Rabbit's Foot (5) | `critChance += v` (int) | L60636-60708 |
   | 24–26 | Silver Armlet (3), Glyph of Stoneskin (6), Sharkul's Skull (10) | `defense += v` | L60711-60769 |
   | 29–31 | Ring of Haste (5), Tempest Stone (10), Ninja Glove (15) | `primaryActionCooldown = primaryActionCooldown * ((100 - v) / 100)` | L60772-60834 |
   | 33–35 | Broken Pocketwatch (5), Monkey's Paw (10), Azamoth's Cursed Eyeball (15) | `noCooldownChance += v` (int) | L60837-60894 |
   | 36–37 | Glove of the Thief (10), Bandit's Satchel (20) | `MotherBrain.bonusGold += v` (party-wide) | L60897-60949 |
   | 38–39 | Mystic Journal (10), Mystery Egg (20) | `bonusXP += v` | L60952-61010 |
   | 40–42 | Blood-soaked Sash (10), Vampire Tooth Pendant (20), Choker of the Red Feast (30) | `lifeDraining += v` | L61013-61071 |
   | 46–48 | Ring of Swift Recovery (5), Medic's Charm (10), Zara's Signet (15) | `bonusHealing += v` | L61074-61131 |

   (Numbers in parentheses are the item's `power` from `items.json`. `moveSpeed`, `primaryActionCooldown`,
   `passiveRegen`, etc. start from whatever the hero prefab has; those base values are not in this range.)
8. **Weapon model** `[IL L61141-61234]`: if `itemDB[P.gear[0]].ingameModel != "none"`: instantiate that resource
   (e.g. `"Weapons/sword1"`) and store its transform in `playerScripts[i].myWeapon`; additionally, if
   `playerScripts[i].characterClass == 7` (Barbarian; this is the prefab's own field), instantiate the **same
   model a second time** into `myOffhand` (dual wield).
9. **Shield model** (else-if chain) `[IL L61236-61328]`:
   - `P.playerName == "Shepherd"` → `Resources "Weapons/shield1"` → `myOffhand`
   - else `P.characterClass == 2` (Knight) → `"Weapons/shield2"` → `myOffhand`
   - else `P.characterClass == 10` (Paladin) → `"Weapons/pallyShield"` → `myOffhand`

After the loop: `bonusGold = bonusGold / 100` `[IL L61343-61347]` → `1.0` with no gold trinkets, `1.1`/`1.2`
with one, etc. (sum over all heroes and both slots).

### 3.3 Enemy pools, textures, initialisation

1. `populateEnemyPools()` (§8) `[IL L61348]`.
2. Texture quality by screen width `[IL L61349-61450]`:
   - `Screen.width > 500`: background = `Resources "Battlefields/" + whichMap`; `interfaceRenderer`, every
     `lineRenderer[k]` and `selectionCircleRenderer` get `Resources "DynamicTextures/Interface"`.
   - otherwise: background = `"Battlefields/" + whichMap + "Lo"`; the others get `"DynamicTextures/InterfaceLo"`.
3. `playerScripts[k].initialize()` for every non-null slot `[IL L61451-61475]`, then
   `enemyScripts[k].initialize()` for every non-null pool entry `[IL L61477-61502]`.
4. Animation speeds `[IL L61504-61527]`: `powerUpAnimation["effect"].speed = 10`,
   `cameraShaker["powerUpShake"].speed = 10`, `actionBarAnimation["show"].speed = 2`,
   `actionBarAnimation["hide"].speed = 2`.
5. `fadeStatus = 1` (fade in) and `partyEntrance()` `[IL L61528-61531]`.
6. Touch colliders added at runtime (`AddComponent("BoxCollider")`) `[IL L61535-61601]`:

   | Object path (`GameObject.Find`) | Collider size |
   |---|---|
   | `*CameraFocus/cameraShaker/Main Camera/actionBar/actionBar/backdrop1` | (0.5, 0.5, 0.1) |
   | `…/actionBar/actionBar/backdrop2` | (0.5, 0.5, 0.1) |
   | `…/actionBar/actionBar/backdrop3` | (0.5, 0.5, 0.1) |
   | `*CameraFocus/cameraShaker/Main Camera/actionBar/pause` | (0.5, 0.7, 0.1) |

7. Tutorial only `[IL L61602-61644]`: `playerScripts[0].takeDamage(360, Vector3(0,0,0), enemyScripts[0])`,
   `playerScripts[0].healthTimer = 2.2`, stop its `"showHealth"` animation, `healthVisible = false`;
   `playerScripts[1].dragType = 3`.
8. `updateScore()` then `muteSoundEffects()` `[IL L61646-61648]`.

---

## 4. `Update` — per-frame flow `[IL L61653-61850]`

```
if initialDelay > 0:                                   [L61660, L61796-61830]
    initialDelay -= Time.deltaTime
    if initialDelay <= 0:                              (the frame it expires)
        fadeStatus = 1
        partyEntrance()                                (second call; same targets as in Awake)
        if BGMusic.enabled and DB.musicEnabled: BGMusic.Play()
else:                                                  (initialDelay <= 0)
    if not paused:                                     [L61666]
        if not disableInput:
            playerControl()                            [L61670-61674]
        else if flee >= 0 and tutorialState != 47:     [L61678-61745]  -- leaving the battle
            flee += Time.deltaTime
            BGMusic.volume -= Time.deltaTime * 0.8
            if flee >= 1.5 and fader.enabled != true:
                fadeStatus = 2 ; fader.enabled = true  (start fade to black)
            if flee >= 3.0:
                if finalBossFirstKill: DB.transferLevel = 5 ; Application.LoadLevel(4)
                else:                  DB.transferLevel = 2 ; Application.LoadLevel(4)
        remoteUpdates()                                [L61746]
        interfaceAnimation()
        fade()
        if not DB.tutorial: enemySpawn()  else: tutorialDriver()     [L61750-61761]
        if levelComplete:                              [L61763-61784]
            BGMusic.volume -= Time.deltaTime * 0.8
            if animateXPBars: StartCoroutine(XPBarAnimation())
    else:  (paused)
        pauseInput()                                   [L61788-61792]

if Time.timeScale != 0:                                [L61831-61848]
    DB.timePlayed += Time.deltaTime * (1 / Time.timeScale)     (real-time play clock)
```

Notes:
- Nothing (input, hero/enemy AI ticks, spawning) runs during the first **0.7 s** (`initialDelay`).
- Heroes and enemies have no `Update` of their own in this flow: `remoteUpdates()` is what ticks them, so
  they stop when `paused` is true (and `Time.timeScale` is 0 anyway).
- The "leave battle" path is used by the pause-menu flee button and (via `flee = 0` written at L75620 in
  the `XPBarAnimation` coroutine body, outside this range) by the end of the victory screen; the scene always loaded is build index **4**,
  with `DB.transferLevel` telling that scene where to go next (2 normally, 5 after the first final-boss kill).

---

## 5. `playerControl` — touch input `[IL L61853-63786]`

Called every frame while not paused and `disableInput` is false.

### 5.1 Frame preamble `[IL L61921-61984]`

1. `handleBackButton()` (§10.3).
2. `touchReleaseCheck[0..9] = 0`.
3. `totalTouches = Input.touchCount`; `fakeTap = false`; `mouseControl()` (§5.6, may turn the mouse into one
   fake touch with finger id 0).
4. Loop A over `i = 0 .. totalTouches-1` (§5.3) — fingers that are down.
5. Loop B over finger ids `0..9` (§5.4) — fingers that were released.
6. Loop C over finger ids `0..9` (§5.5) — line follow-through after release.

### 5.2 `touchState[fingerId]` values

| Value | Meaning | Set at |
|---|---|---|
| 0 | No interaction in progress for this finger | Loop B end [IL L63671] |
| -1 | Touch already handled / hit nothing useful; ignored until released | [IL L62018-62024] |
| 1 | Finger went down on a hero and has not moved past `draggingThreshold` (a potential tap) | [IL L62196-62201] |
| 2 | Dragging a command line from a hero whose `PartyMember.dragType == 2`: may target **another hero** or the ground | [IL L62253-62259] |
| 3 | Dragging from a hero whose `dragType == 3`: may target **an enemy** or the ground | same |

The drag state is literally `touchState = hero.dragType`; `dragType` is a `PartyMember` field set outside
this range (the tutorial forces `playerScripts[1].dragType = 3` in `Awake` [IL L61640]). Only values 2 and 3
are handled.

### 5.3 Loop A — each finger that is down

For a real touch: `touch = Input.GetTouch(i)`, `theFingerId = touch.fingerId`,
`touchReleaseCheck[theFingerId] = 1`, `tapPosition = touch.position` `[IL L61987-62009]`. (For the fake mouse
touch these were set by `mouseControl`.) Then branch on `touchState[theFingerId]`:

**State 0 → touch began** `[IL L62011-62213]`
1. `touchState = -1`; `tempRay = cameraLens.ScreenPointToRay(tapPosition)`.
2. If `Physics.Raycast(tempRay, 100, actionBarMask)` hits **and** `disableSpecials` is false:
   - hit is `actionButton1` → `StartCoroutine(specialMove(0))`, `actionBarAnimation.Play("tap1")`
   - hit is `actionButton2` → `specialMove(1)`, `"tap2"`
   - hit is `actionButton3` → `specialMove(2)`, `"tap3"`
   - any other collider on that layer (the pause button) and `Time.timeScale == 1`: **pause** —
     `cachedTimeScale = Time.timeScale`; `Time.timeScale = 0`; `pauseScreen.localPosition.y = 0`;
     `paused = true` `[IL L62110-62148]`. (Pausing is refused while time is slowed/sped, i.e. timeScale ≠ 1.)
3. Else if `Physics.Raycast(tempRay, 100, partyMask)` hits a hero `[IL L62153-62211]`:
   - `touchContactPosition[f] = tapPosition`; `leaderCandidate[f] = hit.transform`;
     `tempAllyScript = that hero's "PartyMember"`.
   - If `tempAllyScript.commandPending` is false: `touchState[f] = 1`; `commandPending = true`;
     `tempAllyScript.pulse()`.
     (If it was already true — another finger is commanding this hero — the state stays -1.)
   - `audioPool[1].Play()` (in both cases).
4. Otherwise nothing (touch on ground/enemy without starting on a hero does nothing).

Because the action-bar test comes first and is skipped when `disableSpecials` is true, a touch on the
ability bar/pause button while specials are disabled falls through to the hero raycast.

**State 1 → start dragging** `[IL L62216-62338]` — only when
`Vector2.Distance(touchContactPosition[f], tapPosition) >= draggingThreshold` (screen pixels):
1. `tempAllyScript = leaderCandidate[f]'s PartyMember`; `targetCandidate[f] = null`.
2. `touchState[f] = tempAllyScript.dragType`.
3. Show the line: `drawnDot[f].parent.position.z = 9`; `lineAnim[f].Play("idle")`;
   `drawnLine[f].position = drawnDot[f].position = drawnTip[f].position = leaderCandidate[f].position`.

**State 2 → dragging, ally-targeting hero** `[IL L62341-62800]`
1. Ray from `tapPosition`; `targetCandidate[f] = null`.
2. If the ray hits `partyMask`: `targetCandidate[f] = hit.transform`. If that is **not** the dragging hero
   itself: call `flash()` on the hit hero, and snap the line to him:
   - `drawnLine[f].position = leaderCandidate[f].position`
   - `drawnDot[f].position = Vector3.Lerp(drawnDot[f].position, targetCandidate[f].position, Time.deltaTime * 25 * (1 / Time.timeScale))`
   - `drawnLine[f].rotation = Quaternion.FromToRotation(Vector3.forward, drawnDot[f].position - drawnLine[f].position)`, then `localEulerAngles.z = 0`
   - `drawnTip[f].position = drawnDot[f].position`
   - if `lineRenderer[f].material.mainTextureOffset.y != 0`: set it to `0` and `lineAnim[f].Play("pulse")`.
3. If `targetCandidate[f]` is null **or** is the dragging hero himself, and the ray hits `groundMask`
   `[IL L62567-62798]`: same line update but the dot lerps toward `hit.point` (same factor 25), then
   **clamp `drawnDot[f].position.z` to at most `cieling`** (4.3); if `mainTextureOffset.y != -0.086`: set it to
   `-0.086` and `lineAnim[f].Play("idle")`.

**State 3 → dragging, enemy-targeting hero** `[IL L62803-63245]` — identical structure with these differences:
- the target raycast uses `enemyMask`; on a hit (≠ the dragging hero) it calls `EnemyScript.flash()` on the
  enemy `[IL L62825-62866]`;
- the lerp factor is `Time.deltaTime * 30 * (1 / Time.timeScale)` for both the enemy snap and the ground
  follow `[IL L62896-62905, L63063-63081]`;
- the "target locked" texture offset is `-0.172` (+ `"pulse"`) `[IL L62980-63025]`;
- the ground branch runs only when `targetCandidate[f] == null`; offset `-0.086` (+ `"idle"`), same `cieling`
  clamp `[IL L63027-63245]`.

Line texture offset summary (`lineRenderer[f].material.mainTextureOffset.y`): `0` = ally target, `-0.086` =
ground (move), `-0.172` = enemy target.

Only the z-ceiling is clamped here; x-edge and floor clamping of the final move target are not done in this
method.

### 5.4 Loop B — finger released `[IL L63256-63681]`

For every id `i` in 0..9 with `touchReleaseCheck[i] == 0` and `touchState[i] != 0`:

**If `touchState[i] == 1` (tap on a hero, no drag) → selection** `[IL L63273-63430]`
- If `disableSpecials == true`: only clear `leaderCandidate[i]`'s `commandPending` (no selection possible)
  `[IL L63280-63304]`.
- Else:
  1. `audioPool[3].Play()`; `delay = 0`.
  2. If a leader exists and `leaderCandidate[i]` is a different hero: `leaderScript.deselect()`; and if not
     `DB.tutorial`: `actionBarAnimation.Play("hide")`, `delay = 0.08` `[IL L63315-63349]`.
  3. If `leaderCandidate[i] != null` and `!= leader` `[IL L63357-63417]`: `leader = leaderCandidate[i]`;
     `leaderScript = leader.GetComponent("PartyMember")`; `selectionCircle.position = leader.position`;
     `selectionCircleAnim.Stop()`; `selectionCircleAnim.Play("show")`; then
     `StartCoroutine(updateActionBar(delay))` — except in the tutorial while `tutorialState < 34`.
  4. If `leaderScript` exists: `leaderScript.commandPending = false`; `leaderScript.select()` (also when
     re-tapping the already-selected hero) `[IL L63419-63430]`.

**If `touchState[i]` is 2 or 3 (drag released) and `leaderCandidate[i]` exists → order** `[IL L63431-63670]`
`tempAllyScript = leaderCandidate[i]'s PartyMember`.
- If `tempAllyScript.AIState == 3`: only `commandPending = false` (order ignored) `[IL L63461-63466, L63654]`.
- Otherwise:
  1. If the hero has a `myTargetEnemyScript` **and** `AIType == 3`:
     `myTargetEnemyScript.purgePosition(meleeSlot)`; `myTargetEnemyScript = null`; `myTarget = null`
     (release the melee slot around the old target) `[IL L63467-63493]`.
  2. **No target under the finger (`targetCandidate[i] == null`) → move order** `[IL L63494-63554]`:
     `audioPool[2].Play()`; `movementTarget = drawnDot[i].position`; `AIState = 1`; `commandPending = false`;
     if `midAction` is true: `myAnimation.Play("run")`; if the hero has a `petScript` whose `myTarget` is null:
     `StartCoroutine(delayedPetCommand(tempAllyScript))`.
  3. **Target under the finger → target order** `[IL L63557-63650]`:
     `audioPool[0].Play()`; `myTarget = targetCandidate[i]`;
     `myTargetEnemyScript = targetCandidate[i].GetComponent("EnemyScript")` (null when the target is an ally);
     if `AIType == 3` and `myTargetEnemyScript` exists: `meleeSlot = myTargetEnemyScript.requestPosition(preferBack, tempAllyScript)`
     and, if `midAction`, `myAnimation.Play("run")`;
     `commandPending = false`; if `AIState != 2`: `AIState = 2` and `actionTimer = 100`;
     if the hero has a `petScript`: `petScript.myTarget = myTarget`, `petScript.myTargetEnemyScript = myTargetEnemyScript`.
- In all cases: `lineAnim[i].Play("hide")` and `StartCoroutine(hideLine(i))` `[IL L63658-63669]`.

Finally `touchState[i] = 0` `[IL L63671]`.

`PartyMember.AIState` values as used here: 1 = moving to `movementTarget`, 2 = engaging `myTarget`, 3 = a state
in which orders are refused (its meaning is defined in `PartyMember`, outside this range). `AIType == 3` is
the type that occupies melee slots around an enemy.

### 5.5 Loop C — line follow-through `[IL L63683-63785]`

For ids 0..9 with `touchState[i] == 0` and a non-null `targetCandidate[i]` (kept from the last drag): keep the
(fading) line glued to the target — `drawnDot[i].position = Lerp(drawnDot[i].position, targetCandidate[i].position, Time.deltaTime * 25)`
(no timeScale correction here), re-aim `drawnLine[i]` as in §5.3, `drawnTip[i].position = drawnDot[i].position`.

### 5.6 `mouseControl` — mouse as a single touch `[IL L63789-63841]`

```
if (Input.GetMouseButton(0) and totalTouches == 0) or (Input.GetMouseButtonUp(0) and totalTouches == 0):
    fakeTap = true ; totalTouches = 1 ; theFingerId = 0
    tapPosition = Input.mousePosition
    touchReleaseCheck[0] = 0 if Input.GetMouseButtonUp(0) else 1
```
So with a mouse there is exactly one "finger" (id 0); on the release frame Loop A still runs once with the
final position, then Loop B sees the release.

### 5.7 `hideLine(whichLine)` coroutine `[IL L64638-64649; body L70611-70769]`

`yield WaitForSeconds(0.5)`; then, if `touchState[whichLine] < 2` (no new drag started on that finger):
`drawnDot[whichLine].parent.position.z = 10` (moves the line rig out of view; it is put back at z = 9 when a
drag starts) `[IL L70699-70756]`.

### 5.8 Stubs whose bodies are outside this range

| Method | Stub | Body (other doc) |
|---|---|---|
| `specialMove(int whichSpecial)` — fire ability 0/1/2 of the leader | L65510-65521 | `$specialMove$1664`, L71940-72397 |
| `updateActionBar(float timeDelay)` — refresh the bar for the new leader | L64696-64707 | `$updateActionBar$1634`, L70771-71589 |
| `disableActionBar()` | L64710-64720 | `$disableActionBar$1653`, L71591-71938 |
| `delayedPetCommand(PartyMember whichAlly)` | L70447-70457 | `$delayedPetCommand$1757`, L76804-76912 |
| `levelCompleteSequence()` | L70148-70158 | `$levelCompleteSequence$1673`, L72399-74749 |
| `XPBarAnimation()` | L70161-70171 | `$XPBarAnimation$1712`, L74751-75661 |
| `defeatSequence()` | L70174-70184 | `$defeatSequence$1730`, L75663-76802 |

---

## 6. Per-frame helpers

### 6.1 `remoteUpdates` `[IL L64036-64105]`
- For every index of `playerScripts`: if non-null → `remoteUpdate()`.
- For `enemyScripts` in order: if non-null → `remoteUpdate()`; **at the first null entry the loop stops**
  (index is set to the array length) `[IL L64077-64093]`. The pool must therefore be contiguous from index 0.

### 6.2 `interfaceAnimation` `[IL L64108-64611]`
1. If `leader` exists: `selectionCircle.position = leader.position` `[IL L64143-64152]`.
2. Cooldown shades — if `leaderScript` exists and not `freezeUI`, for k = 0,1,2:
   `shades[k].localPosition.y = (leaderScript.remainingCooldowns[k] / leaderScript.cooldowns[k]) * -0.392`
   `[IL L64154-64284]`.
3. Background dim (skipped when `Time.timeScale == 0`) `[IL L64286-64349]`:
   `backgroundRenderer.material.color = Color.Lerp(current, target, Time.deltaTime * 18 * (1 / Time.timeScale))`
   with `target = (0.35, 0.35, 0.35)` if `dimBackground` else `(1, 1, 1)`.
4. Button flash, for k = 0,1,2 `[IL L64350-64609]`:
   - `flashIcon[k]` true: if `flashers[k]` is still parented to `actionBar` → re-parent to `actionButton(k+1)`,
     `localPosition = (0,0,0)`, `localScale = (1,1,1)`, `flashDelay = baseFlashDelay`. Otherwise toggle
     `flashers[k].localPosition.y` between `0` and `5` each time `flashDelay` (shared by all three) reaches ≤ 0,
     resetting it to `baseFlashDelay` (0.1 s); else `flashDelay -= Time.deltaTime`.
   - `flashIcon[k]` false and the flasher is not parented to `actionBar` → re-parent to `actionBar` and set
     world `position.y = 10` (hidden).

### 6.3 `fade` `[IL L64723-64899]`
- `fadeStatus == 1` and `fader.enabled`: while `fader.material.color.a > 0` → `a -= Time.deltaTime`
  (≈ 1 s fade-in); once `a <= 0` → `fader.enabled = false`.
- `fadeStatus == 2` and `fader.enabled` and `a < 1`: `a += Time.deltaTime`; and if `victoryMusic.isPlaying`:
  `victoryMusic.volume -= Time.deltaTime`.

### 6.4 `orientScreen` `[IL L64614-64635]`
If `Input.deviceOrientation == 4` → `Screen.orientation = 4`; else if `== 3` → `Screen.orientation = 3`
(Unity enum values 3 = LandscapeLeft, 4 = LandscapeRight). No caller found in the assembly.

### 6.5 `OnApplicationPause(bool tempBool)` `[IL L64652-64693]`
- Suspending (`true`): `musicTime = BGMusic.time`.
- Resuming (`false`): if `BGMusic.clip != null` and not `levelComplete` and `DB.musicEnabled`:
  `BGMusic.Play()`; `BGMusic.time = musicTime`.

### 6.6 `muteSoundEffects` `[IL L70407-70444]`
If `DB.soundEnabled` is false: `audioPool[k].volume = 0` for every k.

### 6.7 `updateScore` `[IL L70262-70336]`
- `arenaMode`: if `score.parent != pauseTransform` → parent it there with `localPosition = (0.2, 0, 0)`; then
  `scoreText.text = "Score: " + totalKills`.
- not arena: `score.position.x = 100` (off-screen).
Called from `Awake` and from `EnemyScript` after `totalKills` is incremented (L28107-28114, outside range).

### 6.8 `calculateNextLevelXP(int whichLevel)` `[IL L70339-70404]`
```
xp = DB.firstLevelXP                       (int; 30 in bh/data/globals.json)
for i = 2 .. whichLevel (inclusive):
    if i < DB.XPtable.length: xp = (int)(xp * DB.XPtable[i])           -- truncation toward zero each step
    else:                     xp = (int)(xp * DB.XPtable[DB.XPtable.length - 1])
return Mathf.RoundToInt(xp)
```
`XPtable` (27 entries) is in `bh/data/globals.json`; note indices 0 and 1 are never used (loop starts at 2).
`whichLevel <= 1` returns `firstLevelXP`. Callers: victory/XP coroutines at L74287, L74591, L75205, L75280.

### 6.9 `debugTools` `[IL L65396-65507]` — developer keys; **no caller found in the assembly**
`a` held → `Time.timeScale = 0.2`; `s` → `1.0`; `w` → `flashIcon[0] = true`; `e` → `flashIcon[0] = false`;
`q` → `cameraShaker.Play("shake")`; if a leader exists and not `disableSpecials`: key-down `1`/`2`/`3` →
`specialMove(0/1/2)` + `actionBarAnimation.Play("tap1"/"tap2"/"tap3")`.

### 6.10 `Main` `[IL L70602-70609]` — empty.

---

## 7. `partyEntrance` `[IL L64902-64994]`

Orders each hero to walk to his fighting position: `playerScripts[k].movementTarget = <destination>` and
`AIState = 1` for k = 0..3 (destinations in the table of §3.2). Slot 0 is **not** null-checked; slots 1-3 are.
Called from `Awake` and again from `Update` when `initialDelay` expires.

---

## 8. `populateEnemyPools` — enemy id → prefab mapping `[IL L64997-65070]`

```
index = 0
for type = 1 .. totalEnemyTypes (inclusive):
    path = "Enemies/" + enemySet + type            -- e.g. "Enemies/basic1"
    for n = 0 .. 5:                                -- exactly 6 copies per type
        go = Instantiate(Resources.Load(path))
        enemyScripts[index] = go.GetComponent("EnemyScript")
        index += 1
```

Therefore:

- **Enemy id `N` in `Wave.enemies` = prefab `Resources/Enemies/<Level.enemySet><N>`**, pooled at
  `enemyScripts[(N-1)*6 .. (N-1)*6+5]` (see §9, `[IL L65293-65315]`).
- At most **6 instances of one enemy type** can be on the field at once.
- The same id means a different monster in a different `enemySet`.
- Pool objects are created once and never destroyed here; `enemyScripts[k].initialize()` is called in `Awake`.

Enemy sets and the ids actually used (from `bh/data/maps.json`; prefab = `Enemies/<set><id>`):

| `enemySet` | Max `totalEnemyTypes` of any level | Prefabs that can be pooled | Levels (map.level) |
|---|---|---|---|
| `basic` | 8 | `Enemies/basic1` … `Enemies/basic8` | 0.0–0.3, 0.5–0.8, 0.10, 0.11 (arena), 1.1–1.6, 1.11 (arena), transition levels, tutorial 2.0 (types 1-2) |
| `advanced` | 9 | `Enemies/advanced1` … `Enemies/advanced9` | 1.8–1.10, 1.12, 3.1–3.10 (3.4 arena) |
| `boar` | 3 | `Enemies/boar1..3` (waves only list id 1) | 0.4 The Squealing Bog |
| `spider` | 3 | `Enemies/spider1..3` (waves only list id 1) | 0.9 The Silken Wildwood |
| `oozeBoss` | 2 | `Enemies/oozeBoss1..2` | 1.7 The Oozing Dark |
| `golem` | 1 | `Enemies/golem1` | 1.13 The Earthen Gate |
| `lich` | 3 | `Enemies/lich1..3` (waves only list id 1) | 3.11 Throne of Ruin |

The human-readable monster name behind each prefab (e.g. which of `basic1..8` is the goblin) is **not present
in this code range** — it lives in the prefabs / `EnemyScript`. UNVERIFIED: in boss sets the pooled types that
no wave lists (e.g. `boar2`, `boar3`) are presumably spawned by the boss's own script.

---

## 9. `enemySpawn` — wave logic `[IL L65073-65393]`

Called every frame (after `initialDelay`, when not paused, and not in the tutorial). `WAVES = LEVEL.waves`,
`W = WAVES[currentWave]`. State was primed in `Awake` (§3.1 step 5).

```
if spawnDelay <= 0:                                                            [L65084]
    if currentWave >= WAVES.length:                                            [L65090-65113]
        if not levelComplete: StartCoroutine(levelCompleteSequence())          -- victory
    else if wavePosition >= W.enemies.length and activeEnemies == 0:           [L65119-65262]  -- wave cleared
        if arenaMode:
            currentWave = Random.Range(0, WAVES.length)                        -- random next wave (may repeat)
            if totalKills > enemyTier * 10: levelUpEnemies()                   [L65167-65175]
        else:
            currentWave += 1
        wavePosition = 0
        if currentWave < WAVES.length:
            spawnDelay    = WAVES[currentWave].initialDelay
            maxEnemies    = WAVES[currentWave].maxEnemies
            spawnCooldown = WAVES[currentWave].spawnDelay
    else if activeEnemies < maxEnemies and wavePosition < W.enemies.length:    [L65265-65370]  -- spawn one
        base = (W.enemies[wavePosition] - 1) * 6
        for k = 0 .. 5:
            if enemyScripts[base + k].myTransform.position.x == 10:            -- pooled/idle marker
                enemyScripts[base + k].spawn()
                activeEnemies += 1
                spawnDelay     = spawnCooldown
                wavePosition  += 1
                break                                                          (k is set to 10)
else:                                                                          [L65375-65391]
    if activeEnemies < maxEnemies:
        spawnDelay -= Time.deltaTime
```

How the `Wave` fields (`bh/data/maps.json`) are consumed:

| `Wave` field | Used as |
|---|---|
| `initialDelay` (s) | Delay between the moment the wave starts (level start, or the previous wave being fully spawned **and** fully killed) and its first spawn. Copied into `spawnDelay` [IL L59461-59462, L65207-65225]. |
| `spawnDelay` (s) | Delay between consecutive spawns inside the wave. Copied into `spawnCooldown`; `spawnDelay` is reset to it after every successful spawn [IL L59499-59500, L65245-65261, L65354-65356]. |
| `maxEnemies` | Concurrent cap: no spawn while `activeEnemies >= maxEnemies` [IL L65265-65270]. |
| `enemies[]` | Ordered list of enemy-type ids (1-based, see §8); exactly one entry is consumed per spawn [IL L65293-65315, L65358-65361]. |

Rules worth copying exactly:

1. **One spawn per frame at most**, then the timer restarts at `spawnCooldown`.
2. **The spawn timer is frozen while the field is full**: `spawnDelay` only counts down when
   `activeEnemies < maxEnemies` `[IL L65381-65391]`. So after a kill frees a slot, the *remaining* part of the
   delay still has to elapse (if the timer had already reached 0 before the field filled up, the next enemy
   appears on the frame after the kill).
3. A wave ends only when **all its entries have been spawned and `activeEnemies == 0`**; the next wave then
   begins with its own `initialDelay`. The check happens only when `spawnDelay <= 0`; since the timer is
   usually at `spawnCooldown` after the last spawn and keeps counting while `activeEnemies < maxEnemies`,
   the transition can be delayed until that remaining `spawnCooldown` has run out.
4. If all 6 pool copies of the requested type are busy (none sits at x == 10), nothing spawns and
   `wavePosition` does not advance — the spawner retries every frame.
5. "Idle in the pool" is detected purely by `myTransform.position.x == 10` (exact float compare)
   `[IL L65324-65338]`; where the pooled enemy is parked and how `spawn()` positions it is `EnemyScript` code.
6. `activeEnemies` is only incremented here; it is decremented/adjusted in `EnemyScript` (references at
   L16949-16960, L17566-17626, L27229-27565, L28215-28218, L29182-31369 — outside this range).
7. Victory: when `currentWave` has run past the last wave (non-arena), `levelCompleteSequence()` is started
   every frame until that coroutine sets `levelComplete` (L72577).
8. A level whose `waves` array is empty (the "Transition…" levels and the tutorial level in `maps.json`)
   would trigger `levelCompleteSequence()` immediately — if it is ever loaded as a non-tutorial battle.
   In `Awake` such a level would index `waves[0]` (out of range) unless `DB.tutorial` is true.

### 9.1 Arena mode and enemy scaling — `levelUpEnemies` `[IL L70187-70259]`

```
enemyTier += 1
for each enemyScripts[k] from k = 0 until the first null entry:
    maxHealth = (int)(maxHealth * 1.1)        -- int field, truncation
    power     = (int)(power     * 1.1)
```

- It scales **every pooled enemy object** (spawned or idle), not just living ones, so the bonus persists for
  later spawns and compounds: tier t ≈ ×1.1^(t-1) with per-step integer truncation.
- Trigger (only call site in the assembly): in `enemySpawn`, **only in arena mode, at the moment a wave has
  been cleared**, if `totalKills > enemyTier * 10` `[IL L65145-65175]`. `enemyTier` starts at 1, so the first
  level-up happens at the first wave-clear with ≥ 11 kills, the second at ≥ 21 kills, etc. — at most **one tier
  per cleared wave**, even if many kills were accumulated.
- Non-arena levels never scale enemies; there is no other difficulty modifier in this range.
- Arena start: `currentWave` is random in `Awake` `[IL L59355-59375]`; arenas never reach the victory branch
  because `currentWave` is always re-rolled inside the valid range.
- Arena levels in `maps.json`: 0.11 Haggerdom Monster Arena (15 waves, `basic`, 6 types), 1.11 Brightstone
  Monster Arena (20 waves, `basic`, 8 types), 3.4 Doomvale Monster Arena (25 waves, `advanced`, 9 types).

---

## 10. Pause, flee, back button

### 10.1 Entering pause
Tap on the pause collider (any `actionBarMask` hit that is not one of the three ability buttons) while
`Time.timeScale == 1` and `disableSpecials` is false → `cachedTimeScale = Time.timeScale`,
`Time.timeScale = 0`, `pauseScreen.localPosition.y = 0`, `paused = true` `[IL L62110-62148]`.

### 10.2 `pauseInput` — while paused `[IL L63844-64033]`
Runs instead of everything else in `Update`. Does nothing unless `Input.GetMouseButton(0)` is true
(Unity also reports the first touch as mouse button 0).
1. Position: if the mouse button is down and `Input.touchCount == 0` → `tapPosition = Input.mousePosition`;
   else `touch = Input.GetTouch(0)`, `tapPosition = touch.position`. In both cases
   `touchReleaseCheck[theFingerId] = 1` `[IL L63864-63898]`.
2. Raycast (distance 100) against `okayMask` → **resume**: `Time.timeScale = cachedTimeScale`;
   `paused = false`; `pauseScreen.localPosition.y = 10` `[IL L63907-63950]`.
3. Else raycast against `cancelMask` → **flee**: same un-pause, plus `disableInput = true`,
   `playerScripts[k].flee = true` for every non-null hero, and `MotherBrain.flee = 0` `[IL L63953-64030]`.
   From then on `Update` runs the exit timer (§4): music fades at 0.8/s, fade-to-black starts at 1.5 s, scene
   index 4 loads at 3.0 s with `DB.transferLevel = 2`.

### 10.3 `handleBackButton` (Android back / Escape) `[IL L70460-70599]`
Called at the top of `playerControl` — and therefore only on frames where `paused` is false and
`disableInput` is false (§4).
On `Input.GetKeyDown(KeyCode 27 = Escape)`:
- not `paused` and `Time.timeScale == 1` → pause exactly as §10.1 `[IL L70481-70524]`;
- else if `paused` → **flee** exactly as §10.2 step 3 `[IL L70527-70597]`.
Because `playerControl` (the only caller) is not invoked while `paused` is true, the second branch cannot
execute in the `Update` flow of §4: in practice the back button only **opens** the pause screen, and the
pause screen is left through its two buttons (§10.2).

---

## 11. `tutorialDriver` (summary) `[IL L65524-70145]`

Runs instead of `enemySpawn` when `DB.tutorial` is true. It is a 47-step script (`tutorialState` 1..47):

- **Dialog steps** advance on any new tap (own tap-edge detection with `tutorialTouchCount`,
  `tutorialReleaseCheck`, `tutorialTouchState`; the mouse works too) `[IL L67074-67135, L70138-70143]`. Each
  shows `tutorialStrings[n]` through `tutorialText.Printout(...)` with the Lucille or Shepherd portrait,
  moves the window to `localPosition.y = 5.84` (shown) or `2` (hidden), plays `audioPool[0]`/`[3]`, positions
  the hand/arrows (hidden = world `y = -20`) and toggles `disableInput` / `disableSpecials`.
- **Action steps** wait for the player to do the thing: state 1 → 2 when hero 0 has walked in to `x >= -0.5`
  [IL L65832-65897]; 7 → 8 hero 0 within 0.7 of `tutorialArrow` [L65899-66000]; 11 → 12 both arrows reached
  (arrow targets (2,0,-2)→(0,0,1.3) and (-2.5,0,3)→(-1.3,0,0.5)) [L66003-66255]; 14 → 15 the training dummy
  (spawned at (1.75, 0, 0.8), installed as `enemyScripts[0]`) is dead [L66260-66329, L67672-67697]; 19 → 20
  hero 0 selected [L66332-66424]; 22 → 23 hero 0 healed to full [L66427-66504]; 28 → 29 hero 1 damaged
  [L66507-66578]; 31 → 32 `enemyScripts[7]` dead [L66580-66654]; 37 → 38 hero 1 selected [L66657-66749];
  41 → 42 (state 41 is set by `PartyMember.performSpecial`, L93810) [L66752-66853].
- Safety: in state 31, any hero below 200 health gets `wardChance = 101` [IL L66856-66895].
- Debug: key `q` jumps to state 46 [IL L65818-65825].
- **End**: state 46 → 47 on tap: `flee = 0`, both heroes get `AIState = 1` and
  `movementTarget = position + (10, 0, 0)` (run off to the right) [IL L69996-70086]; in state 47 the same
  exit timer as §4 runs inside this method (music −0.8/s, fade at 1.5 s, at 3.0 s `DB.transferLevel = 2`,
  `Application.LoadLevel(4)`) [IL L70088-70137].

The tutorial texts themselves are Inspector data (`tutorialStrings`), not in the IL.

---

## 12. Uncertain / not determined

- **Who sets `disableInput = false` in a normal battle?** The constructor sets it `true` [IL L59296-59300];
  inside the whole assembly the only writes of `false` are in `tutorialDriver` (e.g. L67771). All writes
  outside this range (L72581, L75908, L87510) write `true`. UNVERIFIED: the scene's serialized (Inspector)
  value of this public field must be `false` and override the constructor default; otherwise input would never
  work outside the tutorial.
- All Inspector-assigned values are invisible in the IL: array sizes of `playerScripts`, `enemyScripts`,
  `touchState` etc. (the code assumes ≥ 4 heroes, ≥ `totalEnemyTypes * 6` enemies — up to 54 — and 10 finger
  slots), the layer masks, `buffDurations/Magnitudes`, `debuffDurations/Magnitudes`, `tutorialStrings`, and any
  Inspector override of the constructor defaults (`cieling` 4.3, `edge` 3.42, `floor` -2.8, `maxEnemies` 3, …).
- Enemy prefab → monster name mapping (§8) is not in this range.
- `PartyMember.dragType` assignment per class (which heroes draw ally-lines vs enemy-lines), the meaning of
  `AIState == 3`, `AIType`, `midAction`, `preferBack`, `EnemyScript.spawn()` / `requestPosition` /
  `purgePosition`, and where `activeEnemies` is decremented are defined outside this range.
- UNVERIFIED: legal values of `abilities[1]`/`abilities[2]` (§3.2 step 5).
- Scene build index 4 and the meaning of `DB.transferLevel` values 2 and 5 are not defined in this range.
- `handleBackButton`'s "back while paused = flee" branch is unreachable from the `Update` flow (§10.3); whether
  that was intended is unknown.
- `orientScreen` and `debugTools` have no caller in the assembly; `waves`, `touchReleased`, `tempAnimation`,
  `loadingText` are never referenced.
- `Time.deltaTime * k * (1 / Time.timeScale)` appears in the line/dim lerps: the intent is real-time speed
  under slow motion; behaviour at `timeScale == 0` is avoided only for the dim (explicit check) — the line
  lerps run only while unpaused.

### Contradictions with older notes

- `work/non-encounter-systems-research.md` §2 step 4 says the pool check is "x≈0 (off-stage)". The IL compares
  `position.x` with **10** (`ldc.i4.s 0x0a`) `[IL L65332-65338]`. It also describes the spawn step as a
  "while" loop; the IL spawns **at most one enemy per frame**.
- `docs/02-damage-system.md` §7 and `work/battleheart-encounter-parity.md` (line 76, open question 8) say
  `levelUpEnemies` affects "every currently-spawned enemy" and that its trigger is unknown. The IL scales
  **every pooled `EnemyScript`** (alive or idle) and the trigger is: arena mode, on wave clear, when
  `totalKills > enemyTier * 10` `[IL L65145-65175, L70187-70259]`.
- `docs/01-positioning-system.md` §6 says touch-down raycasts `groundMask`. In the IL the touch-down tests
  only `actionBarMask` then `partyMask`; a drag must **start on a hero**; `groundMask`/`enemyMask` are only
  tested while dragging `[IL L62032-62211, L62589, L62825, L63036]`. It also says `purgePosition` is called on
  the move path only; the IL calls it on **both** move and re-target releases, and only when `AIType == 3`
  `[IL L63467-63493]`.
- `work/battleheart-encounter-parity.md` line 36 says touch-down raycasts "ground/party/enemy masks" — same
  correction as above.

---

## 13. Cross-references

Calls made from this range:

| Callee | Where called | Location of callee |
|---|---|---|
| `PartyMember.initialize()` | `Awake` L61463 | L77121-78037 |
| `PartyMember.remoteUpdate()` | `remoteUpdates` L64058 | L78040-78099 |
| `PartyMember.takeDamage(int, Vector3, EnemyScript)` | `Awake` (tutorial) L61614 | L81497-82407 |
| `PartyMember.pulse()`, `flash()`, `select()`, `deselect()`, `updateHealthBar(int)` | `playerControl` L62206, L62404, L63428, L63337; tutorial | `PartyMember` (L76916-105810; `deselect` L83358) |
| `EnemyScript.initialize()`, `remoteUpdate()`, `spawn()`, `flash()`, `requestPosition(int, PartyMember)`, `purgePosition(int)` | `Awake` L61489; `remoteUpdates` L64084; `enemySpawn` L65339; `playerControl` L62866, L63591, L63479 | `EnemyScript` (L5304-32635) |
| `HandScript` fields (`handState`, `startPosition`, `endPosition`, `snapTarget`) | tutorial | L32637-32871 |
| `TextPrint.Printout(string)` | tutorial | L107420-107584 |
| `Database` fields `levelDB`, `currentMap`, `whichLevel`, `party`, `partyDB`, `powerDB`, `itemDB`, `tutorial`, `musicEnabled`, `soundEnabled`, `timePlayed`, `transferLevel`, `firstLevelXP`, `XPtable` | throughout | `Database` L854-2554; data in `bh/data/*.json` |
| `Wave`, `Level`, `Map`, `Player`, `Item`, `Power`, `powerCollection` data classes | `Awake`, `enemySpawn` | L606-852 |
| Coroutine bodies `specialMove`, `updateActionBar`, `disableActionBar`, `levelCompleteSequence`, `XPBarAnimation`, `defeatSequence`, `delayedPetCommand` | see §5.8 | L70771-76912 |

Callers into this range from outside:

| Member | Caller |
|---|---|
| `updateScore()` | `EnemyScript`, L28114 (after `totalKills += 1` at L28107-28110) |
| `calculateNextLevelXP(int)` | victory / XP-bar coroutines, L74287, L74591, L75205, L75280 |
| `defeatSequence()` | `PartyMember.$die$1765` coroutine, L87522 |
| `disableActionBar()` | `PartyMember.$die$1765` coroutine, L87544 |
| `draggingThreshold` (write `Screen.width / 24`) | `dynamicbackgroundhandler`, L108096-108103 |
| `tutorialState = 41` | `PartyMember.$performSpecial`, L93810 |
| `flee = 0` (starts the exit timer of §4) | `$XPBarAnimation$1712` body, L75618-75620 |
| `finalBossFirstKill` (write) | `$XPBarAnimation$1712` body, L75645 |
| `fadeStatus` (write) | `$defeatSequence$1730` body, L75879, L76772 |
| `disableInput = true`, `disableSpecials = true` | `$levelCompleteSequence$1673` L72581-72585; `$defeatSequence$1730` L75908-75912; `PartyMember.$die$1765` L87510 |
| `cieling` / `edge` / `floor` (reads) | `EnemyScript`, `PartyMember`, `PetScript` (e.g. L6135) |

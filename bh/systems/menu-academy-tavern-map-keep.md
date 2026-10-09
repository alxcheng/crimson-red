# MenuBrain town menu: Academy (skills), Tavern (hire), World Map, Keep (reserves), Save slots

Scope: class `MenuBrain` (out-of-battle "town" controller), coroutine bodies
`$skillsInput$1531` [IL L52238-53593], `$tavernInput$1545` [IL L53595-54839], `$mapInput$1560` [IL L54841-56280],
`$keepInput$1580` [IL L56282-57190], `$loadInput$1588` [IL L57192-58699], `$startNewGame$1615` [IL L58701-58854],
`$loadExistingGame$1620` [IL L58856-59086]. To make the rules complete, this document also reads (and cites) the
parts of MenuBrain *outside* that range that carry the rules those coroutines depend on: `Update` [L33578-33716],
`Awake` [L33082-33507], `mainInput` entry branches [L48057-49466], `UpdateInventory` Academy/Tavern/Map/Keep branches
[L37271-39460, L39460-41007, L41007-41092], `InitialPartySelection` [L41775-42275], `resetMenus` [L42711-42770],
`clearDescriptionBox` [L42773-43113], `unlockPlayableCharacters` [L43570-43662], `updateLoadScreen` [L34814-35542];
and the battle-side consumers of `abilities`/`passives` (`MotherBrain.Awake` [L59731-60060], `PartyMember.initialize`
[L77556-77920]) so the ladder semantics are provably correct.

All numbers are `[IL Lnnnn]` line numbers of
`/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`. Data ids are resolved with
`bh/data/classes.json`, `party.json`, `maps.json`, `globals.json`.

---------------------------------------------------------------------------------------------------------------

## 1. Summary (player-visible behaviour)

* The town is one scene with several screens laid out side by side on a horizontal strip; "going to" a building just
  moves the camera on X and sets `activeMenu`. Every frame `Update` starts the coroutine for the active screen
  [IL L33578-33716]. Leaving a building (exit tile or Escape) always returns to `activeMenu = 0`, camera x = -20.
* **Academy** (`activeMenu 3`): pick one of your (up to 4) active party members, see his/her 12-power ladder. Power
  position 0 is always known. Positions 1/2 unlock at **level 5**, 3/4 at **level 10**, 5/6 at **level 15**, 7/8 at
  **level 20**, 9 at **level 25** (no choice, automatic), 10/11 at **level 30**. At each *pair* (1/2, 3/4, 5/6,
  7/8, 10/11) the player taps one of the two icons to choose it; tapping the other icon later **switches the choice
  for free, any time, no gold, no confirmation** (no code path touches gold or any other state).
  Choices of pairs 1/2 and 5/6 are **active abilities** (stored in `Player.abilities[1]`, `[2]`); choices of pairs
  3/4, 7/8, 10/11 are **passives** (stored as +1 / -1 in `Player.passives[0]`, `[1]`, `[3]`).
* **Tavern** (`activeMenu 4`): shows one not-yet-recruited, "available" character at a time (arrows cycle through
  the candidates). **Hire price = candidate.level x 10 gold.** A candidate becomes available when the highest
  level among *recruited* characters is >= the candidate's level (`unlockPlayableCharacters`, run when entering
  the tavern). A hired character goes into the first free active party slot (slots 1-3), else the first free
  reserve slot.
* **Map** (`activeMenu 5`): four maps (0 Haggerdom, 1 Brightstone, 2 tutorial, 3 Doomvale). Levels form a prerequisite
  tree (`prereq` = index of another level of the same map that must be `complete`). Tapping an unlocked level shows
  its name/description and a battle button; pressing the button saves the game and loads the battle scene.
  "Transition" levels are arrows that slide the map to another map (free if no prereq, otherwise only once the prereq
  level is complete). Arena levels are drawn with a crown and display a high score.
* **Keep** (`activeMenu 8`): move characters between the active party (4 slots) and reserves (12 slots). You may never
  remove the last active character.
* **Save slots** (`activeMenu 6`, camera x = 40): 3 slots with PlayerPrefs flags `"<n>saveExists"`; tap an empty slot
  to start a new game, tap a used slot to load it, tap the delete icon + OK to erase it.

---------------------------------------------------------------------------------------------------------------

## 2. Shared machinery (identical in all five coroutines)

### 2.1 `activeMenu` values and camera strip

`Update` dispatch [IL L33584-33693]: `activeMenu` 0 -> `mainInput`, 1 -> `inventoryInput` (Armory), 2 -> `storeInput`
(Merchant), 3 -> `skillsInput` (Academy), 4 -> `tavernInput`, 5 -> `mapInput`, 6 -> `loadInput`, 7 -> `introSequence`,
8 -> `keepInput`, 9 -> `tutorialInput`. (Negative -100 = "busy/fading", no handler runs.) `Update` also adds
`Time.deltaTime` to `DB.timePlayed` every frame [IL L33707-33715], so time spent in menus counts as play time.

Entering a building from the town (`mainInput`, by the *name* of the tapped object) sets `activeMenu` and the camera X
[IL L48424-49150]:

| tapped object name | activeMenu | camera X | first-visit tutorial flag |
|---|---|---|---|
| "armory" | 1 | 0 [L48432-48436] | `armoryFirstVisit` -> tutorial 4 [L48510-48529] |
| "merchant" [L48589] | 2 | -40 (0xffffffd8) [L48593-48597] | `merchantFirstVisit` -> tutorial 8 [L48671-48690] |
| "academy" | 3 | -60 (0xffffffc4) [L48746-48758] | `academyFirstVisit` -> tutorial 2 [L48795-48814] |
| "tavern" | 4 | -80 (0xffffffb0) [L48870-48885] | none; calls `unlockPlayableCharacters()` first [L48878] |
| "battle" | 5 (map) | +20 [L48927-48980], battleButton.y set to 8 (hidden) [L48935-48969] | none; `MenuBrain.currentMap` NOT reset (stays as last selected) |
| "keep" | 8 | -100 (0xffffff9c) [L49018-49030] | `keepFirstVisit` -> tutorial 11 [L49067-49086] |
| "home" | 6 (save slots) | +40 [L49142-49158] | sets `currentMap = 0` [L49154] |

After setting these, `resetMenus()` is called [L48922, 49013, ...]: it runs `clearDescriptionBox`,
`InitialPartySelection`, `UpdateInventory`, `UpdatePartyPortraits`, hides the `select` marker (y=5), resets
`displayGold = DB.gold` and the gold text [IL L42722-42762]. The town (main) screen is at camera X = -20 (every
"exit" writes -20 [e.g. L52550-52584]). Tutorial text strings (`tutorialStrings[]`) live in the scene, not in the
code, so their wording is not in the IL (UNVERIFIED content). Tutorial index 14 = arena explanation (shown in the map),
13 = "level 5 reminder" (shown at scene start, see 6.6).

### 2.2 Input prelude (every coroutine, once per frame)

[IL L52343-52440 (skills); identical blocks in the other four.] Pseudocode:

```
touchReleaseCheck = 0
totalTouches = clamp(Input.touchCount, 0, 5)
fakeTap = false
// mouse emulation of a single touch
if (mouse0 held && totalTouches==0) or (mouse0 released this frame && totalTouches==0):
    fakeTap = true; totalTouches = 1; theFingerId = 0; tapPosition = mousePosition
    touchReleaseCheck = (mouse0 released this frame) ? 0 : 1
if totalTouches > 0:
    if !fakeTap: touch = GetTouch(0); touchReleaseCheck = 1; tapPosition = touch.position
    if touchState == 0:                 // a new press: only acts once per press
        touchState = -1
        ray = cameraLens.ScreenPointToRay(tapPosition)
        ... hit-tests, in the priority order given per screen (all raycasts: length 100, a LayerMask) ...
if touchReleaseCheck == 0: touchState = 0      // release re-arms
if Input.GetKeyDown(KeyCode 0x1b = Escape): same as pressing the exit tile (see 2.3)
yield (one frame)
```

So every action fires on **press** (not release), except the map's battle button (fires on release, 5.4).
`avoidDoubleTap` (bool) blocks new actions while a timed animation sequence is running. Layer masks used:
`exitMask` (exit tile), `partyMask` (party portraits / popup buttons), `itemMask` (icons / map nodes), `upgradeMask`
(battle button on the map), `okayMask`, `cancelMask` (confirmation popups). The masks themselves are assigned in the
scene (not visible in IL).

### 2.3 Exit sequence (identical in Academy, Tavern, Map, Keep)

Exit-tile press [Academy IL L52462-52593]:
1. Raycast `exitMask`; ignored if `avoidDoubleTap` (and in the Tavern also ignored while `hireScreen.position.y == 0`,
   i.e. while the hire popup is open [IL L53845-53850]).
2. Stop + Play the tapped object's `Animation` (button press animation); `avoidDoubleTap = true`; play `sounds[3]`.
3. wait **0.06 s**; play `wiperAnim "enter"`; wait **0.22 s**.
4. `avoidDoubleTap = false`; `activeMenu = 0`; camera.x = **-20**; play `wiperAnim "exit"`.
Escape key does steps 2-4 without the button animation: `avoidDoubleTap=true; sounds[3]; wiper "enter"; wait 0.22;
activeMenu=0; camera.x=-20; wiper "exit"` [Academy L53505-53583; Tavern L54745-54829; Map L56192-56264; Keep L57102-57176].
(Hit state numbers inside the coroutines: skills 2/3 exit tile, 4 Esc; tavern 2/3 exit, 4 hire-confirm 0.2 s, 5 okay
0.2 s, 6 cancel 0.2 s, 7 Esc; map 2/3 exit, 4+5 transition A, 6+7 transition B, 8+9 battle start, 10 Esc;
keep 2/3 exit, 4 Esc; load never yields except 2/3.)

Sound slots used (indices into `sounds[]`; names are scene data, not in IL): 3 = generic click, 4 = OK/confirm,
5 = denied/error, 6 = battle start.

---------------------------------------------------------------------------------------------------------------

## 3. Fields touched by this code

| Field | Type | Meaning / default |
|---|---|---|
| `DB` | Database | the global save object (`GameObject.Find("**DATABASE")`) [L33117] |
| `activeMenu` | int | which screen (see 2.1); -100 = loading/fading |
| `selectedPlayer` | int | index into `DB.partyDB` of the character shown in Academy/Tavern; -1 = none |
| `currentMap` | int | which of `DB.levelDB[]` maps is displayed on the world map; set from `DB.currentMap` in Awake [L33305] |
| `whichSlotSelected` | int | icon index last tapped (skill icon 0-11, map node index, reserve slot index) |
| `tempValue` | int | scratch; default -1 [ctor L33072-33074] |
| `avoidDoubleTap` | bool | blocks input during animation sequences |
| `touchState`, `touchReleaseCheck`, `totalTouches`, `fakeTap`, `tapPosition`, `contactPosition`, `tempRay`, `tempHit`, `tempTransform`, `tempRenderer`, `tempAnimation` | scratch | see 2.2 |
| `draggingThreshold` | float | ctor default 20, then `Screen.width / 30` in Awake [L33064-33065, L33110] (only used by drag UIs) |
| `pickedUpSlot`, `whichSlotToDrop` | int | ctor defaults -1 (inventory drag, not used here) |
| `intro` | int | ctor default 1 [L33075-33077]; set to 1 by `startNewGame` |
| `portraitButtons2[4]` | Transform[] | Academy party portrait buttons (party slots 0-3) |
| `partySelect`, `partySelectAnim` | Transform/Animation | highlight frame on the selected portrait |
| `select`, `selectAnim` | Transform/Animation | highlight marker on a tapped icon; hidden by moving to y=5 |
| `skillIcons[12]`, `skillGreyouts[10]`, `litLines[6]`, `litSticks[5]` | Renderer[]/Transform[] | the 12 ladder icons, "not chosen" overlays, connector lines, "chosen" stick marks (Academy) |
| `skillNameText`, `skillDescText`, `classText` | TextPrint | Academy description area |
| `characterSheetModels[]` | Transform[] | one 3D model per roster id; the selected one is moved to y=-0.66 (Academy) / -0.57 (Armory) / hidden at y=5 |
| `recruitGearIcons[4]`, `recruitNameText`, `recruitDescText`, `recruitPriceText`, `recruitClassText`, `recruitNameSmall`, `recruitCoinIcon`, `powerText2`, `armorText2` | UI | Tavern candidate panel |
| `hireScreen`, `hireScreenAnim`, `hireScreenText`, `hireButtonAnim`, `goldText3` | UI | Tavern confirm popup (visible when `hireScreen.y == 0`, hidden at y=7), gold readout |
| `displayGold` | float | count-up/down gold display; changes 100 gold per second toward `DB.gold` [Tavern L54660-54745] |
| `mapIcons[]`, `mapJunk[]`, `mapGeo`, `mapAnim`, `mapNameText`, `levelNameText`, `levelDescText`, `battleButton`, `litSword`, `battleStartEffect`, `battleStartAnim`, `audioFade` | map UI | see 5 |
| `keepIcons[12]`, `keepLevels[12]` | Renderer[]/TextMesh[] | reserve slots icons and "Lv.N" labels |
| `warningScreen`, `warningScreenAnim`, `deleteRenderers[3]`, `newGame1-3`, `save1-3Name`, `save1-3Time`, `save1-3NameText`, `save1-3TimeText`, `name1-3Transform`, `fadeOutLoadScreen`, `fadeInMainMenu`, `musicRenderer`, `soundRenderer`, `BGMusic`, `musicTime`, `keyboard`, `keyBoardInput`, `weAreTyping`, `saveWeJustQuit` | save-slot UI | see 7 |
| `cameraLens`, `cameraTransform`, `wiperAnim` | Camera/Transform/Animation | screen-wipe transition |

Database fields used: `party[4]` (ints, index into `partyDB`, -1 = empty), `reserves[12]` (ints, -1 = empty),
`partyDB[]` (the 14 roster `Player`s), `powerDB[]` (10 `powerCollection`s), `levelDB[]` (4 `Map`s), `gold`, `currentMap`,
`whichLevel`, `transferLevel`, `whichSaveSlot`, `timePlayed`, `musicEnabled`, `soundEnabled`, `freshBoot`, `arenaExplanation`,
`level5reminder`, `*FirstVisit`. Sizes: `party.json` shows `party = [1,0,-1,-1]` (4 slots; initial lead is roster id 1
Shepherd, slot 1 is id 0 Lucille), `reserves` 12 slots all -1 (matches `keepIcons` loops `< 0x0c` [L33396-33419],
and keep loops [L56892-56900, L57060]), `gold = 15` in `globals.json` (the C# ctor default 100 [Database ctor] is overridden by the scene data).

`Player` fields [IL L633-650]: `playerName, characterClass, level, description, recruited, available, gear[4], XP, power,
defense, maxHealth, abilities[3], passives[4], icon`. `powerCollection` [L822]: `whichClass, powerScale, defenseScale,
healthScale, whichPower[12]`; `Power` [L665]: `powerName, description, icon, cooldown`.

---------------------------------------------------------------------------------------------------------------

## 4. ACADEMY: `skillsInput` (activeMenu 3) [IL L52238-53593]

### 4.1 What a Player's `abilities` and `passives` arrays mean (verified in battle code)

`characterClass` is **1-based**: `powerDB[characterClass - 1]` is the class's power table (used everywhere, e.g.
Academy header `characterClass; ldc.i4.1; sub` [IL L52947-52993]). 1 Cleric, 2 Knight, 3 Rogue, 4 Wizard, 5 Witch, 6 Bard,
7 Barbarian, 8 Monk, 9 Ranger, 10 Paladin. (`classes.json` ids are 0-based = `characterClass-1`.)
Every class has exactly 12 powers (`whichPower[0..11]`), in this fixed role by *position*:

| position (power index) | unlock level | kind | what the player chooses | value written |
|---|---|---|---|---|
| 0 | 1 (always) | active (class basic special) | nothing | `abilities[0]` is 1 in every initial Player (party.json); battle always uses power 0 for slot 0 |
| 1 / 2 | **5** | active (A/B) | pick one | `abilities[1] = 2` for position 1, `= 3` for position 2 |
| 3 / 4 | **10** | passive (A/B) | pick one | `passives[0] = +1` for position 3, `= -1` for position 4 |
| 5 / 6 | **15** | active (A/B) | pick one | `abilities[2] = 4` for position 5, `= 5` for position 6 |
| 7 / 8 | **20** | passive (A/B) | pick one | `passives[1] = +1` for position 7, `= -1` for position 8 |
| 9 | **25** | passive | no choice | not stored: `passives[2]` is set to 1 at battle start iff level >= 25 |
| 10 / 11 | **30** | passive (A/B) | pick one | `passives[3] = +1` for position 10, `= -1` for position 11 |

Citations: unlock levels in `UpdateInventory` `activeMenu==3` branch: `level < 5` skip pair 1/2 [IL L37396-37437
(`ldc.i4.5; blt IL_0a4d`)]; `level < 10` [IL L37710 (`0x0a`)]; `< 15` [L37993 (`0x0f`)]; `< 20` [L38276 (`0x14`)];
`< 25` [L38559 (`0x19`)]; `< 30` [L38606 (`0x1e`)]. Each unlocked pair does `litLines[k].enabled = true` and
`skillIcons[a].enabled = true` + `skillIcons[b].enabled = true` and loads `Power.icon` of positions a, b into the icon
material: pair 1/2 line 0 [L37437-37520]; pair 3/4 line 1 [L37720]; pair 5/6 line 2 [L38003]; pair 7/8 line 3 [L38286];
position 9 line 4 [L38569-38600]; pair 10/11 line 5 [L38616-38690]. Position 0 is always enabled [L37396]. Before the
loop all 12 icons are disabled (`skillIcons[i].enabled = false` for i<12 [L37340-37350]) and all greyouts hidden
(y=5 for i<10 [L37358-37392]); `litLines` (i<6) disabled [L37280-37290]; `litSticks` (i<5) moved to y=5 [L37298-37332].

Written values (Academy tap handler): icon 1 -> `abilities[1]=2` [L53244-53253]; icon 2 -> `abilities[1]=3` [L53269-53278];
icon 3 -> `passives[0]=1` [L53294-53303]; icon 4 -> `passives[0]=-1` [L53319-53328]; icon 5 -> `abilities[2]=4` [L53344-53353];
icon 6 -> `abilities[2]=5` [L53369-53378]; icon 7 -> `passives[1]=1` [L53394-53403]; icon 8 -> `passives[1]=-1` [L53419-53428];
icon 10 -> `passives[3]=1` [L53444-53453]; icon 11 -> `passives[3]=-1` [L53469-53478]. **Icons 0 and 9 have no
write branch** (the comparison chain jumps from icon 8 straight to icon 10 [L53433]).

Battle-side confirmation (so a port can trust the encoding):
* `MotherBrain.Awake` copies `Player.abilities[0..2]` and `Player.passives[0]`, `[1]`, `[3]` to the battle `PartyMember`
  [IL L59731-59824, L59925-59940]; `passives[2]` is **computed** there: `Player.level >= 0x19 (25) ? 1 : 0`
  [IL L59894-59921]. Battle max HP = `Player.maxHealth + powerCollection.healthScale * (level - 1)` [L59826-59880].
* Cooldown slots: `cooldowns[0] = whichPower[0].cooldown`; `if abilities[1] != 0: cooldowns[1] = whichPower[abilities[1] - 1].cooldown`
  (value 2 -> power 1, value 3 -> power 2); `if abilities[2] != 0: cooldowns[2] = whichPower[abilities[2] + 1].cooldown`
  (value 4 -> power 5, value 5 -> power 6) [IL L59944-60056]. So the encoding is: slot-1 value = powerIndex+1,
  slot-2 value = powerIndex-1, `0` = no ability chosen in that slot (slot unused).
* Passive examples proving the +1/-1 convention (class numbers are 1-based `characterClass`): Knight (2):
  `passives[0] == -1` -> power x1.15 (power 4 "Might") and `passives[0] == +1` -> defense x1.15 (power 3 "Chivalry")
  [IL L77555-77588]; Rogue (3): `passives[1] == -1` -> moveSpeed x1.15 (power 8 "Pursuit"), `== +1` -> defense x1.15
  (power 7 "Combat Tactics") [L77629-77662]; Rogue `passives[3] == -1` -> power x1.1 (power 11 "Aggression") [L77593-77606];
  Paladin (10) `passives[2] != 0` -> allies get `sentinelDefense = 0.25 * defense` (power 9 "Sentinel") [L77917-77959];
  Ranger (9) `passives[2] != 0` -> spawns "Allies/Dog" (power 9 "Canine Ally") [L78002-78033].
  Hence **+1 = the *first* (lower-index) icon of the pair, -1 = the *second***, consistently.
* The Paladin/Ranger/etc. level-25 power thus depends only on level (>= 25); it cannot be turned off.

### 4.2 The 12 powers per class, mapped to ladder positions (from `bh/data/classes.json`)

Each cell is the `powerName` at that position index; `characterClass` column = Player.characterClass value.

| characterClass | class | pos0 (L1) | pos1 (L5) | pos2 (L5) | pos3 (L10) | pos4 (L10) | pos5 (L15) | pos6 (L15) | pos7 (L20) | pos8 (L20) | pos9 (L25) | pos10 (L30) | pos11 (L30) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Cleric | Group Heal | Shield | Power Infusion | Passion | Discipline | Guardian Angel | Vengeful Angel | Empowering Words | Holy Embrace | Favored Soul | Binding Heal | Desperate Prayer |
| 2 | Knight | Shield Wall | Cleave | Intimidate | Chivalry | Might | War Cry | Shield Rush | Crippling Blows | Sunder Armor | Blitz | Fortress | Revenge |
| 3 | Rogue | Sneak Attack | Expose Weakness | Poisoned Knife | Flurry | Critical Strikes | Paralytic Knife | Shadowstep | Combat Tactics | Pursuit | Envenomed Blades | Lethality | Aggression |
| 4 | Wizard | Meteor | Blizzard | Time Stop | Enveloping Flames | Impact | Conflagrate | Thunderbolt | Fire Shield | Mage Armor | Teleport | Flaming Meteor | Concussive Shockwave |
| 5 | Witch | Drain Life | Plague | Debilitate | Piercing Shadow | Life Leech | Horror | Hex | Terrifying Presence | Sudden Doom | Prey on the Weak | Crushing Despair | Dark Harvest |
| 6 | Bard | Song of Renewal | Song of Vigor | Song of Sanctuary | Gusto | Stoicism | Song of War | Song of Inspiration | Healing Chords | Enduring Hope | Prestissimo | Vivace | Echo of Renewal |
| 7 | Barbarian | Enrage | Frenzy | Whirlwind | Death Wish | Iron Skin | Reckless Blow | Savage Pounce | Precision Strikes | Bloodthirsty | Adrenaline Rush | Blunt Trauma | Dismemberment |
| 8 | Monk | Wind Walk | Evasion | Ki Blast | Iron Hand | Tiger Claw | 1000 Palms | Spirit Trance | Clarity | Dragon Style | Counter | Sweep the Leg | Solar Strikes |
| 9 | Ranger | Aimed Shot | Incendiary Arrow | Vile Bolt | Sniper's Sense | Mortal Shots | Barrage | Apollo Strike | Critical Aim | Misdirection | Canine Ally | Crippling Bite | Thrash |
| 10 | Paladin | Holy Word | Wrath | Aura of Light | Stalwart | Swift Justice | Divine Intervention | Radiance | Bastion | Power of the Word | Sentinel | Word of Asylum | Word of Retribution |

Observation from data (`classes.json` cooldown field): positions 0, 1, 2, 5, 6 of every class have cooldown > 0
(= the actives: 0 basic active, 1/2 and 5/6 chosen actives); positions 3, 4, 7, 8, 9, 10, 11 all have `cooldown 0`
(= passives). This matches the code, which prints `"  (Passive)"` when `cooldown <= 0` and
`"  (<cooldown> sec cooldown)"` otherwise [IL L53098-53232]. Each class has therefore: 1 fixed active + 2 chosen actives
(levels 5 and 15) = max 3 action-bar abilities; passives chosen at 10, 20, 30 plus the automatic one at 25.
Active cooldown values (sec): Cleric 0:20 1:30 2:30 5:60 6:60; Knight all 30; Rogue 0:20 1:30 2:30 5:45 6:30;
Wizard 0:30 1:30 2:45 5:40 6:30; Witch 0:20 1:30 2:30 5:40 6:40; Bard 0:20 1:30 2:30 5:30 6:60; Barbarian all 30;
Monk 0:40 1:30 2:30 5:30 6:40; Ranger 0:20 1:30 2:30 5:30 6:30; Paladin 0:30 1:30 2:40 5:30 6:30.

Initial `abilities`/`passives` of roster members (`party.json`): everyone `abilities=[1,0,0]`, `passives=[0,0,0,0]`
except The Black Knight (id 10, Knight, level 5) and Garrick (id 11, Barbarian, level 5), who start with
`abilities=[1,2,0]` (i.e. position 1 pre-chosen, which they have unlocked at level 5). 0 in `passives[i]` = neither
choice made.

### 4.3 `skillsInput` per-frame logic (hit-test order) [IL L52335-53589]

On a new press (`touchState==0`, ray cast with each mask in turn; first match wins):

1. **Exit tile** (`exitMask`, ignored if `avoidDoubleTap`) -> exit sequence 2.3 [L52462-52593].
2. **Party portraits** (`partyMask`) -- only if `upgradeWindow.position.y != 0` (window not open; the same
   window object is shared with the Armory) and not `avoidDoubleTap` [L52595-52625]. Sets `touchState = 10`,
   `tempValue = -1`; tapped transform vs `portraitButtons2[0..3]`:
   * slot 0: `selectedPlayer = DB.party[0]` unconditionally [L52641-52665];
   * slots 1,2,3: `selectedPlayer = DB.party[i]` only if `DB.party[i] != -1` [L52667-52766].
   When a slot was selected (`tempValue == 0` [L52770]): move `partySelect` to that portrait position + replay
   `partySelectAnim`; play `sounds[3]`; set `select.y = 5` (hide the icon highlight); `clearDescriptionBox()`
   (blanks skill name/desc [L43084-43093]); `UpdateInventory()` (re-computes which ladder rungs are shown, 4.1);
   hide every `characterSheetModels[i]` (y=5) then place `characterSheetModels[selectedPlayer]` at y = **-0.66**
   [L52846-52944]; `classText` := `playerName + " - Level " + level + " " + powerDB[characterClass-1].whichClass`
   [L52947-52993]; `updateWeapons()` [L52993].
3. **Skill icons** (`itemMask`, not `avoidDoubleTap`) [L52998-53483]: play `sounds[3]`; `tempRenderer` = tapped
   object's Renderer; move `select` marker onto it and replay `selectAnim`; find `whichSlotSelected` = index i in
   `skillIcons[0..11]` equal to the tapped renderer [L53056-53087]; `clearDescriptionBox()`.
   * If the icon renderer is **enabled** (= unlocked) [L53089]: print `skillNameText = whichPower[slot].powerName`;
     `skillDescText = description + "  (" + cooldown + " sec cooldown)"` when `cooldown > 0`, else
     `description + "  (Passive)"` [L53098-53232]. Then apply the choice write from 4.1 for icons 1-8,10,11, then
     `UpdateInventory()` to refresh the highlight/grey-out state [L53481].
   * If **disabled** (= locked): `skillNameText = "???"`, `skillDescText = "You must be higher level to unlock
     this power."` [L53486-53495]. No state change.
4. After the hit-tests: if `touchReleaseCheck == 0`, `touchState = 0` [L53496-53503].

### 4.4 Choice highlighting (GUI only) [UpdateInventory L37396-38890]

For each pair the overlays are driven by the stored choice, e.g. pair 1/2 keyed by `abilities[1]`
(3 -> first icon greyed (GREY[0] y=0, STICK[0] y=-0.56); 2 -> second icon greyed (GREY[0] y=-0.97, STICK[0] y=0);
otherwise both greyed (GREY[0] y=0 and GREY[5] y=-0.97)) [L37517-37707]; pair 3/4 keyed by `passives[0]` (-1 / +1 / none)
[L37778-37990]; pair 5/6 by `abilities[2]` (5 / 4) [L38083-38250]; pair 7/8 by `passives[1]` (+1 / -1) [L38410-38556];
pair 10/11 by `passives[3]` [L38640-38880]. Exact y offsets (-0.97, -0.56, 0, 5=hidden) are pixel layout only.
Net effect to port (UNVERIFIED as to which exact overlay covers which icon; inferred from the stored-choice keys): the chosen icon is shown lit, the unchosen one greyed; with no choice both are greyed.

### 4.5 Respec rules

None: choices can be changed at any time, for free, for any number of times; there is no gold/currency, point, or
"first pick locks" logic anywhere in `skillsInput` (the only DB writes are the `abilities[]`/`passives[]` elements above;
the string `gold` does not appear in the coroutine). There is no level cap check in the Academy; level 30 is simply the
highest rung (rung 10/11 requires level >= 30). How leveling is capped is outside this range (see
`MotherBrain.XPBarAnimation`; not covered here).

---------------------------------------------------------------------------------------------------------------

## 5. TAVERN: `tavernInput` (activeMenu 4) [IL L53595-54839]

### 5.1 Who is offered (candidate list)

* Entering the tavern: `mainInput` calls `unlockPlayableCharacters()` then sets `activeMenu=4`, camera -80, then
  `resetMenus()` -> `InitialPartySelection()` [IL L48878-48922].
* `unlockPlayableCharacters` [IL L43570-43662]:
  ```
  maxLevel = 1
  for p in DB.partyDB: if p.recruited and p.level > maxLevel: maxLevel = p.level
  for p in DB.partyDB: if p.level <= maxLevel and not p.available: p.available = true
  ```
  (loop 1 = L43587-43611; loop 2 = L43626-43650). Candidate's own `level` is its fixed table level (unrecruited
  characters never gain XP; the only writes of `Player.level` are `Database.load` and MotherBrain's level-up).
  Note a character that is already `available` stays available forever.
* `InitialPartySelection` when `activeMenu == 4` [IL L42118-42275]: `selectedPlayer = -1`; scan `partyDB[0..13]`
  and take the **first** (lowest id) with `recruited == false && available == true`; reposition character models.
  If none: `selectedPlayer` stays -1 and `UpdateInventory` shows the text
  `"No recruits are currently\navailable.  Check back\nlater!"` with empty name/class/price [IL L39382-39416].
* Candidates and unlock thresholds (from `party.json`; `level` = both unlock threshold and price basis;
  `available` = initial flag):

| id | name | class (characterClass) | level (= unlock threshold, price/10) | hire price (gold) | initially available |
|---|---|---|---|---|---|
| 0 | Lucille | Cleric (1) | 1 | recruited at start | true |
| 1 | Shepherd | Knight (2) | 1 | recruited at start | true |
| 2 | Gustav | Rogue (3) | 1 | 10 | true |
| 3 | Bromswell | Wizard (4) | 1 | 10 | true |
| 4 | Baelrosh | Barbarian (7) | 2 | 20 | false |
| 5 | Wynter | Witch (5) | 2 | 20 | false |
| 12 | Oakley | Ranger (9) | 2 | 20 | false |
| 6 | Feung | Monk (8) | 3 | 30 | false |
| 13 | Heleth | Paladin (10) | 3 | 30 | false |
| 7 | Edwardo | Bard (6) | 4 | 40 | false |
| 8 | Robin | Rogue (3) | 4 | 40 | false |
| 9 | Thistle | Wizard (4) | 4 | 40 (maxHealth 800) | false |
| 10 | The Black Knight | Knight (2) | 5 | 50 | false |
| 11 | Garrick | Barbarian (7) | 5 | 50 | false |

  Start gold is 15 (`globals.json`), so only the two level-1 candidates are affordable initially.

### 5.2 Panel contents (`UpdateInventory`, activeMenu 4) [IL L38891-39458]

For the selected candidate: gear icons (4 slots, hidden when gear id == -1), name, description (the `description` string),
`recruitClassText = className + " Lv. " + level`, `recruitPriceText = ": " + (level * 10)` [IL L38961-39039]; power/armor
numbers (display only; formula `((powerScale*level + power)/5)` for Cleric [L39050], `power + powerScale*level` for
others, `+ defenseScale*level` for armor [L39116-39221]; not needed for hiring).

### 5.3 Input logic [IL L53665-54834]

Hit-test order each press: (1) `exitMask`, but only if the popup is **closed** (`hireScreen.y != 0`... precisely: skipped when
`hireScreen.position.y == 0`) [L53825-53850]; (2) `partyMask` (arrows + hire button), only when popup closed
[L53969-53994]; (3) `okayMask` [L54349]; (4) `cancelMask` [L54567].

**Arrows** (hit object's *name*, animation on its parent): `"leftArrow"` -> play `"idle"`; `"rightArrow"` -> play `"right"`;
both play `sounds[3]`. If `selectedPlayer != -1`: loop { step selectedPlayer -1 (left) / +1 (right) with wrap-around over
`partyDB` length (14); stop when `!recruited && available` } then `UpdateInventory()` [L54018-54110, L54115-54205].
(With a single candidate the loop returns to the same character.)

**Hire button** (`"hireButton"`, animation `"hire"`) [L54210-54341]:
```
if selectedPlayer != -1 and DB.gold >= partyDB[selectedPlayer].level * 10:     // ">=": exact money is enough
    sounds[3]; avoidDoubleTap = true; wait 0.2 s;
    avoidDoubleTap = false; hireScreen.y = 0 (open); hireScreenAnim "enter";
    hireScreenText = DB.gold + "\n" + level*10          // shows current gold and cost
else: sounds[5]  (denied)
```
**OK button** (`okayMask`) [L54349-54562]:
```
avoidDoubleTap = true; sounds[4]; hireScreenAnim "okay"; wait 0.2 s;
avoidDoubleTap = false; hireScreen.y = 7 (closed)
DB.gold -= partyDB[selectedPlayer].level * 10
partyDB[selectedPlayer].recruited = true
roomInParty = false
for i in 1..3: if DB.party[i] == -1: DB.party[i] = selectedPlayer; roomInParty = true; break
if not roomInParty:
    for i in 0..11: if DB.reserves[i] == -1: DB.reserves[i] = selectedPlayer; break
InitialPartySelection()   // picks the next candidate or -1
UpdateInventory()
```
(Party slot 0 is never filled by hiring; slots tried are 1,2,3.) There is no check at OK time; the check is at the Hire
button. **Cancel** (`cancelMask`): `sounds[3]`; `hireScreenAnim "cancel"`; wait 0.2 s; `hireScreen.y = 7` [L54567-54648].

Gold display each frame: `displayGold` moves toward `DB.gold` by `deltaTime * 100` per frame (up or down, clamped to
target) and writes `goldText3 = RoundToInt(displayGold)` [L54660-54748]. Escape = exit [L54748-54829].

A hired character keeps the roster `level`, `XP=0`, `gear`, `abilities`, `passives` from `party.json` (no level scaling
code exists in the hire path).

---------------------------------------------------------------------------------------------------------------

## 6. WORLD MAP: `mapInput` (activeMenu 5) [IL L54841-56280]

### 6.1 Data model

`DB.levelDB[currentMap]` is a `Map` {`mapName`, `mapScale`, `whichLevel[]`}; each `Level` {`levelName`, `description`,
`complete`, `arena`, `prereq` (index of a level in the same map, -1 none), `prereqLoc` (0-3, direction of this icon relative
to its prereq's icon), `myPosition` (only used when `prereq == -1`), `transition` (target map index or -1),
`transitionDirection`, `highScore`, plus battle data} [IL L740-779, L801-820]. The icon for level k is `mapIcons[k]` and
the tapped icon index `whichSlotSelected` is **the level index** [IL L55335-55363]. `mapScale` = 0.9 for maps 0, 1, 3.

### 6.2 Map icon building (`UpdateInventory`, activeMenu 5) [IL L39460-41005]

Called on entering the map and after every transition. It destroys all `mapIcons[]` and `mapJunk[]` objects,
sets `mapNameText = mapName` [L39521], then for each level index k (in increasing order, so a prereq's icon exists before
its dependents) instantiates a prefab from `Resources/MapElements/...` parented to `mapGeo`:

| condition (in order) | icon | connector |
|---|---|---|
| `prereq == -1`, `transition != -1` | `ArrowRight` if `transitionDirection == 2`, else `ArrowLeft` [L39548-39588] | none |
| `prereq == -1`, `transition == -1`, `arena` | `Crown` [L39590-39608] | none |
| `prereq == -1`, other, `complete` | `Checkbox` [L39610-39628] | none |
| `prereq == -1`, other, not complete | `Skullface` [L39630-39636] | none |
| (`prereq == -1` icons are placed at local position `(myPosition.x, myPosition.y, 0.5)` [L39644-39682]) | | |
| `prereq != -1`, `transition != -1`, `levels[prereq].complete` | arrow (as above) [L39684-39745] | `darkStick{prereqLoc}` |
| `prereq != -1`, level `complete` | `Crown` if arena else `Checkbox` [L40024-40062] | `darkStick{prereqLoc}` |
| `prereq != -1`, not complete, `levels[prereq].complete` | `Crown` if arena else `Skullface` [L40341-40388] | `darkStick{prereqLoc}` |
| `prereq != -1`, `levels[prereq].complete` false | `Lock` [L40667-40681] | `lightStick{prereqLoc}` |

Position of a non-root icon = position of the prereq's icon + offset by `prereqLoc` (the connector stick object is created
at the same spot): `prereqLoc 0` -> `(0, -mapScale, 0)` [L39770-39807]; `1` -> `(0, +mapScale, 0)` [L39836-39872];
`2` -> `(-mapScale, 0, 0)` [L39901-39938]; `3` -> `(+mapScale, 0, 0)` [L39967-40003]. Connector prefabs: `darkStick0-3`
(prereq complete) / `lightStick0-3` (locked) [names at L39795, 39860, 39926, 39991, 40724, ...]. Connectors are stored
in `mapJunk[]` (first free slot) [L40956-40984].

### 6.3 Tap handling on a node [IL L55223-56010]

Hit mask `itemMask` (not `avoidDoubleTap`): `touchState=-1`; `battleButton.y = 8` (hide); `sounds[3]`; find node index
`whichSlotSelected` in `mapIcons[]`; `L = levelDB[currentMap].whichLevel[whichSlotSelected]`.

1. **Free transition** -- `L.transition != -1` and `L.prereq == -1` [L55371-55404]: transition (below).
2. **Gated transition** -- `L.transition != -1`, `L.prereq != -1` and `levelDB[currentMap].whichLevel[L.prereq].complete`
   [L55551-55595]: transition.
3. Otherwise (normal level, or transition whose prereq is incomplete) [L55741+]: move `select` marker to the node, replay
   `selectAnim`, `clearDescriptionBox()`; then
   * if `L.prereq != -1` and the prereq level is **not complete**: `levelNameText = "???"`,
     `levelDescText = "You have not reached this location yet."` [L56002-56010] (battle button stays hidden);
   * else: `levelNameText = L.levelName`; if `L.arena`: `levelDescText = L.description + L.highScore` (string-concatenated
     number) and, if `DB.arenaExplanation == 1`, set it to 0, `whichTutorial = 14`, show the tutorial popup (`activeMenu = 9`)
     [L55805-55943]; else `levelDescText = L.description` [L55945-55962]; finally `battleButton.y = 0` (show) [L55963-55997].
   The default (nothing selected) text is `"    Tap a location on the map to proceed!"` [L43104].
   Completed levels remain selectable (replay is allowed -- there is no `complete` check on entry).

**Transition (map change) sequence** [L55405-55549 (case 1), L55595-55739 (case 2); identical]:
`clearDescriptionBox()`; `select.y = 5`; `avoidDoubleTap = true`; if `L.transitionDirection == 2` play `mapAnim "exitLeft"` else
`"exitRight"`; wait **0.4 s**; if direction == 2 play `"enterRight"` else `"enterLeft"`; `currentMap = L.transition`;
`UpdateInventory()` (rebuild icons for the new map); wait **0.3 s**; `avoidDoubleTap = false`.
Note: this changes only `MenuBrain.currentMap`; `DB.currentMap` is written when a battle starts (6.4) or at Awake.

### 6.4 Battle start [IL L55254-55261, L56012-56192]

* Press on the lit battle button (`upgradeMask` hit while `battleButton.y == 0`) enables `litSword` (pressed visual)
  [L55223-55254]. The action happens on **release**: when `touchReleaseCheck == 0`, `touchState = 0`, and `litSword` was
  enabled: disable `litSword`; if the release ray still hits the battle button (`upgradeMask`, `battleButton.y == 0`,
  not `avoidDoubleTap`) [L56012-56069]:
  ```
  battleStartEffect.position = select.position - (0,0,2); battleStartAnim.Play()
  select.y = 5; audioFade = true (music fades out in Update); sounds[6].Play(); avoidDoubleTap = true
  wait 1.2 s
  DB.save(); wiperAnim "enter"
  wait 0.4 s
  DB.currentMap = currentMap; DB.whichLevel = whichSlotSelected; DB.transferLevel = 3
  Application.LoadLevel(4)        // the battle scene (build index 4)
  ```
  [L56075-56190]. `DB.transferLevel = 3` is also written by other scene changes (e.g. L35990, L61734-61742); its
  meaning is outside this range.
* Escape exits to the town (2.3) [L56192-56264]. The map itself has the usual exit tile.

### 6.5 Level graph (from `bh/data/maps.json`)

Level index = `whichLevel` index; `loc` = `prereqLoc`; `trans/dir` = `transition`/`transitionDirection`;
"cmp" = initial `complete`.

Map 0 "Haggerdom" (mapScale 0.9):

| idx | name | arena | prereq | loc | trans | dir | cmp |
|---|---|---|---|---|---|---|---|
| 0 | The Gobwood (root, myPosition 2.68,-0.6) | | -1 | 0 | -1 | 0 | no |
| 1 | Westwylde Fields | | 0 | 3 | -1 | 0 | no |
| 2 | Eston Farmstead | | 1 | 1 | -1 | 2 | no |
| 3 | Summersong Ruins | | 2 | 1 | -1 | 0 | no |
| 4 | The Squealing Bog | | 2 | 3 | -1 | 2 | no |
| 5 | Chillwind Field | | 4 | 3 | -1 | 2 | no |
| 6 | St. Argus Cemetery | | 5 | 3 | -1 | 2 | no |
| 7 | The Royal Crypt | | 6 | 1 | -1 | 2 | no |
| 8 | Marrowstone Ruins | | 7 | 3 | -1 | 2 | no |
| 9 | The Silken Wildwood | | 8 | 0 | -1 | 2 | no |
| 10 | Shalestone Caverns | | 5 | 0 | -1 | 2 | no |
| 11 | Haggerdom Monster Arena | yes | 10 | 3 | -1 | 2 | no |
| 12 | Transition to Map 1 | | 9 | 3 | 1 | 2 | no |

Map 1 "Brightstone" (0.9):

| idx | name | arena | prereq | loc | trans | dir | cmp |
|---|---|---|---|---|---|---|---|
| 0 | Transition to Map 0 (root, myPosition 2.68,1.15) | | -1 | 0 | 0 | 3 | yes |
| 1 | Carrion Canyon | | 0 | 3 | -1 | 0 | no |
| 2 | Dusthide Badlands | | 1 | 0 | -1 | 0 | no |
| 3 | The Lost Grotto | | 2 | 3 | -1 | 0 | no |
| 4 | Darkmoon Forest | | 3 | 0 | -1 | 0 | no |
| 5 | Bloodrose Ruins | | 4 | 2 | -1 | 0 | no |
| 6 | St. Byron Sepulcher | | 5 | 2 | -1 | 0 | no |
| 7 | The Oozing Dark | | 4 | 3 | -1 | 0 | no |
| 8 | Whithered Hope Valley | | 7 | 3 | -1 | 0 | no |
| 9 | Cho'yuk Ravine | | 8 | 1 | -1 | 0 | no |
| 10 | Crimson Hollow | | 9 | 1 | -1 | 0 | no |
| 11 | Brightstone Monster Arena | yes | 10 | 2 | -1 | 0 | no |
| 12 | The Firelands | | 10 | 3 | -1 | 0 | no |
| 13 | The Earthen Gate | | 12 | 0 | -1 | 2 | no |
| 14 | Transition to Map 3 | | 13 | 3 | 3 | 2 | no |

Map 2 "TUTORIAL": one level "Tutorial Level" (root, complete, transition 0 dir 3).
Map 3 "Doomvale" (0.9): idx 0 "Transition to Map 1" (root, myPosition 2.68,0.32, trans 1, dir 3, complete yes);
1 Emerald Hinterlands (prereq 0, loc 3); 2 Everfrost Weald (1, 3); 3 Seaside Ruins (2, 1); 4 Doomvale Monster Arena
(arena, 3, 3); 5 Rimetooth Tundra (2, 3); 6 The Frozen Abyss (5, 0); 7 Time-Lost Canyon (6, 3); 8 Dungeon of the Lost
(7, 3); 9 Molten Wastes (8, 1); 10 The Boneyard (9, 1); 11 Throne of Ruin (10, 3). All trans -1, dir 3, complete no.
Consequences of the graph: the first map can be left only after Silken Wildwood (L9) is complete; map 1 -> map 3
only after The Earthen Gate (L13) is complete; the transition icons at index 0 of map 1/3 are always usable (root with
`prereq == -1`, pre-completed).

Who sets `Level.complete`/`highScore`: `MotherBrain` level-complete code [IL L72694] and `Database.load/save`
[IL L2197-2240]; not covered here.

---------------------------------------------------------------------------------------------------------------

## 7. KEEP: `keepInput` (activeMenu 8) [IL L56282-57190]

Roster management between `DB.party[4]` (active) and `DB.reserves[12]`. Each reserve slot shows the character's `icon`
texture and `"Lv." + level` when `reserves[i] != -1`; empty slots are hidden (`keepIcons[i].enabled=false`, text
empty) [UpdateInventory activeMenu 8, IL L41007-41090].

Hit-test order: exit tile; `partyMask` (active-party portrait buttons named by string `"PartyButton1"` .. `"PartyButton4"`);
`itemMask` (reserve icons).

**Move active -> reserve** [IL L56610-56901]: sound `sounds[3]`; tapped object name `n`.
Proceeds only if (`n == "PartyButton1"` and `DB.party[1] != -1`) or (`n != "PartyButton1"`) [L56643-56668]
-- i.e. **the lead slot (PartyButton1 = party[0]) cannot be removed unless another character exists in party[1]**,
so the party can never become empty. Then for the first `i` in 0..11 with `reserves[i] == -1`:
* `PartyButton1`: `reserves[i] = party[0]`; shift `party[0]=party[1]; party[1]=party[2]; party[2]=party[3]; party[3]=-1`
  [L56683-56747];
* `PartyButton2`: `reserves[i] = party[1]`; `party[1]=party[2]; party[2]=party[3]; party[3]=-1` [L56749-56801];
* `PartyButton3`: `reserves[i] = party[2]`; `party[2]=party[3]; party[3]=-1` [L56803-56843];
* `PartyButton4`: `reserves[i] = party[3]`; `party[3]=-1` [L56845-56871];
then `UpdateInventory(); UpdatePartyPortraits();` and the loop ends [L56873-56885]. (Tapping an empty party button just
writes -1 into the first free reserve slot, a no-op; if reserves are full nothing happens.)

**Move reserve -> active** [IL L56903-57090]: `sounds[3]`; `whichSlotSelected` = index in `keepIcons[0..11]` of the tapped
renderer [L56944-56979]. Then for `i = 1..3` (slot 0 is never auto-filled): if `party[i] == -1`: `party[i] = reserves[sel]`;
`reserves[sel] = -1`; compact the reserve list by moving every later entry down one (`reserves[j] = reserves[j+1]` for
`j = sel .. len-2`) and set `reserves[len-1] = -1`; break; `UpdateInventory(); UpdatePartyPortraits();` [L56981-57080].
If the party already has 4 members nothing happens. So the active party is a compact array (members always occupy the
lowest slots), max **4** active, **12** reserves, no gold cost, no level restrictions. Party order matters in battle
(party[0] first slot); reordering is done by moving out and back in.

---------------------------------------------------------------------------------------------------------------

## 8. LOAD / SAVE SLOTS: `loadInput` (activeMenu 6), `startNewGame`, `loadExistingGame`

### 8.1 Entry [Awake IL L33124-33150]
* `DB.freshBoot == 1` (cold start): `activeMenu = 6`, `updateLoadScreen()`; if `PlayerPrefs["cleansave"] != 2`: set it to 2,
  `DB.whichSaveSlot = 4`, `DB.save()` (writes a clean slot-4 record).
* Else (returning from a battle): `fadeInMainMenu.enabled = true`; if `DB.tutorial`: `DB.currentMap = 0`, `whichTutorial = 0`, show
  tutorial text 0, `activeMenu = 9` [L33152-33207]; else if `DB.level5reminder == 1` and any `DB.party[i] != -1` (i<4) has
  level >= 5: `level5reminder = 0`, `whichTutorial = 13`, show tutorial 13 (`activeMenu = 9`) [L33209-33299]. Always
  then `DB.tutorial = false`, `MenuBrain.currentMap = DB.currentMap`, `DB.save()` [L33301-33310]. (So the game auto-saves
  every time the town scene loads.)
* Also in Awake: BoxColliders (size 1.3x1.3x0.1) are added to `inventoryIcons` (24), `inventoryIcons2` (28), `skillIcons`
  (12), and (1.1x1.1x0.1) `keepIcons` (12) [L33319-33419]; music/sound button alpha 0.3 when disabled [L33447-33503].

### 8.2 Slot UI (`updateLoadScreen`) [IL L34814-35542]
For slot n = 1,2,3: if `PlayerPrefs.GetInt("<n>saveExists") == 1`: show `save<n>Name` (text = `PlayerPrefs.GetString("<n>PlayerName")`;
name scale 0.0531 if length > 8, 0.064 if > 6, else 0.082) and `save<n>Time` (play time formatted `H:MM:SS` from
`PlayerPrefs.GetFloat("<n>timePlayed")` rounded; minutes and seconds zero-padded), hide `newGame<n>`, delete icon alpha 1;
else show `newGame<n>` ("new game" art), hide name/time, delete icon alpha 0.3.

### 8.3 `loadInput` [IL L57275-58694]
Every frame: if camera.x != 40 set it to 40 [L57332-57377]. Hit-tests on a new press, by raycast + object **name**:
1. If `warningScreen.position.y == 0` (delete-confirm popup open):
   * OK (`okayMask`): `sounds[3]`; anim `"okay"`; wait 0.2; popup y=7 (closed); **`PlayerPrefs["<whichSaveSlot>saveExists"] = 0`**;
     `updateLoadScreen()`; `DB.whichSaveSlot = 0` [L57501-57602]. (Only the exists-flag is cleared; stored data is left.)
   * Cancel (`cancelMask`): `sounds[3]`; anim `"cancel"`; wait 0.2; popup closed; `DB.whichSaveSlot = 0` [L57609-57699].
2. Else if popup closed, raycast `exitMask` (the slot/button objects) -- `avoidDoubleTap` false:
   * `"menu_saveslot1|2|3"`: `DB.whichSaveSlot = n`; `sounds[3]`; set that slot renderer's material color to
     (0.6, 0.6, 0.25) [L57757-57780 etc.]. If `PlayerPrefs["<n>saveExists"] == 1` -> `StartCoroutine(loadExistingGame())`
     [L57850]. Else (new game): on touch devices (`Input.touchCount > 0`) open an `iPhoneKeyboard` titled
     `"Please enter your name"` (`weAreTyping = true`); set `PlayerPrefs["<n>PlayerName"] = "Game <n>"`; `DB.timePlayed = 0`;
     `updateLoadScreen()`; enable `fadeOutLoadScreen`; `activeMenu = -100`; `audioFade = true`; `StartCoroutine(startNewGame())`
     [L57788-57848].
   * `"delete1|2|3"` (only if that slot's saveExists == 1): `DB.whichSaveSlot = n`; `sounds[3]`; open the warning popup
     (y=0, anim `"enter"`) [L58063-58259].
   * `"music"` toggle: if on: `DB.musicEnabled=false`, remember `BGMusic.time`, stop, `PlayerPrefs["musicEnabled"]=1`, icon alpha 0.3, click sound;
     if off: play, restore time, `musicEnabled=true`, `PlayerPrefs["musicEnabled"]=2`, alpha 1 [L58267-58415]. (PlayerPrefs 1 = disabled, 2 = enabled.)
   * `"sound"` toggle: same pattern with `soundEnabled`, `PlayerPrefs["soundEnabled"]` (1 off, 2 on), alpha 0.3 / 1, then `muteSoundEffects()`
     (sets every `sounds[i].volume` to 0 or 1) [L58417-58535, L33510-33575].
3. Keyboard handling each frame: if `weAreTyping` and keyboard done: `weAreTyping=false`; name := keyboard text (or `"No Name"`
   if empty) into `PlayerPrefs["<n>PlayerName"]`; `DB.timePlayed=0`; `updateLoadScreen()`; fadeOut; `activeMenu=-100`; `audioFade`;
   `StartCoroutine(startNewGame())` [L58537-58619]. If keyboard text length > 10: truncate to its first 10 characters
   [L58622-58672]. (Names are max 10 chars.)
4. Escape key = `Application.Quit()` [L58684-58688].

### 8.4 `startNewGame` [IL L58762-58850]
`DB.freshBoot = false`; `DB.populateMerchant()`; wait **2 s**; `DB.save()`; `activeMenu = 7` (intro sequence); camera.x = **60**;
`intro = 1`. (Nothing else is reset here; initial gold/party/flags come from the Database as deserialized: see `globals.json`/`party.json`.)

### 8.5 `loadExistingGame` [IL L58919-59080]
`DB.freshBoot = false`; `DB.load()`; if `saveWeJustQuit != DB.whichSaveSlot`: `DB.populateMerchant()` (re-roll the merchant stock when
loading a different slot than the one just quit from -- `saveWeJustQuit` is set to `DB.whichSaveSlot` when the player presses "home"/Esc on the main town screen, [IL L49201, L49374]);
enable `fadeOutLoadScreen`; `activeMenu = -100`; wait **2 s**; `activeMenu = 0`; camera.x = **-20**; `fadeInMainMenu.idleTime = 0.1`,
enable it and its renderer, set its alpha to 1.

---------------------------------------------------------------------------------------------------------------

## 9. Uncertain / not determined

* UNVERIFIED: the *names* of `sounds[3..6]` (click/ok/deny/battle-start) -- inferred from usage only; the audio clips are scene data.
* UNVERIFIED: wording of `tutorialStrings[]` (scene-serialized, not in IL). Only the indices triggered are known (2 academy, 4 armory,
  8 merchant, 11 keep, 13 level-5 reminder, 14 arena, 0 intro tutorial).
* Layer-mask assignments (`exitMask`, `partyMask`, `itemMask`, `upgradeMask`, `okayMask`, `cancelMask`) and the exact scene objects they
  select are scene data; the code only reveals their roles (e.g. in the load screen the save-slot/delete/music/sound objects are tested
  against `exitMask`, which shows these share a mask with the exit tile in that scene).
* Maximum character level: not stated in Academy code; the highest ladder rung is level 30 (`0x1e`). The XP curve is in
  `globals.json` (`firstLevelXP 30`, `XPtable`) and `MotherBrain.calculateNextLevelXP` [IL L70339-70404]; whether leveling stops at 30 is not
  verified in this range.
* `Database.save/load` format (what is persisted of `abilities`/`passives`, PlayerPrefs keys) is outside this range (Database L1001-2337).
* What `DB.transferLevel = 3` means to the receiving scene is not determined here.
* Pixel offsets in the Academy highlight logic (y = 0 / -0.56 / -0.97 / 5) are layout only and were summarised, not listed per branch.

Contradictions with older notes (`work/non-encounter-systems-research.md`, `work/bh-town-menu-research.md`):
* Older note says the choice cadence is "~every 5 levels"; the code confirms 5/10/15/20/(25)/30 -- consistent -- but note rung 25 is an *automatic*
  passive (no choice) and rung 30 is a choice; there are 5 choices + 1 automatic passive, not a uniform "choice every 5".
* Older note: "class trainers unlock via map progression"; the code shows roster unlock is purely level-based
  (`max(level of recruited characters) >= candidate.level`), and the tavern price is `level*10`; no map-progress condition appears in the Tavern.
* Older note: hire cost "10xlevel [wiki]" -- now confirmed from IL (`level * 0x0a`, [IL L54240-54250, L54433-54452]).
* Older note leaves party/reserves sizes unrecovered; now: party 4 slots (hire loop `i < 4` [L54503]), reserves 12 slots (`keepIcons` loops
  `< 0x0c`; `party.json`).

---------------------------------------------------------------------------------------------------------------

## 10. Cross-references

* Called from here: `MenuBrain.UpdateInventory` [L36429], `UpdatePartyPortraits` [L41095], `InitialPartySelection` [L41775],
  `clearDescriptionBox` [L42773], `updateWeapons` [L42278], `muteSoundEffects` [L33510], `updateLoadScreen` [L34814], `startNewGame`/`loadExistingGame`,
  `Database.save` [L1001], `Database.load` [L1685], `Database.populateMerchant` [L2385], `Application.LoadLevel(4)`.
* Calls into here: `MenuBrain.Update` [L33578] (dispatch); `mainInput` [L48057] (entering buildings, `unlockPlayableCharacters`);
  `Awake` [L33082] (initial screen / tutorials).
* Consumers of the Academy choices: `MotherBrain.Awake` [L59731-60060] (copy to battle, cooldown slots, `passives[2]` from level >= 25, HP formula),
  `MotherBrain.updateActionBar` [L71196+], `PartyMember.initialize` [L77556-78033] (passive stat modifiers), `PartyMember.performSpecial` [L93226+]
  (ability execution by `abilities[]`), `PartyMember` AI/damage code (many `passives[3]` / `passives[2]` checks, e.g. L79163, L81553, L82374).

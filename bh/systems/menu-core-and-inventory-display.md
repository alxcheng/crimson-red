# MenuBrain: core, state machine, load screen, intro, tutorial, inventory/party display

Scope: class `MenuBrain` (the out-of-battle "town" menu controller), IL lines 32873-43673 of
`Assembly-UnityScript.il`: header + all 177 fields [IL L32873-33052], `.ctor`, `Awake`, `muteSoundEffects`, `Update`,
the seven coroutine stubs (`inventoryInput`, `mainInput`, `storeInput`, `skillsInput`, `tavernInput`, `mapInput`,
`keepInput`, `loadInput`), `updateEquipArrows`, `tutorialInput`, `updateLoadScreen`, `startNewGame` stub,
`introSequence`, `applyCorners`, `loadExistingGame` stub, `UpdateInventory`, `UpdatePartyPortraits`,
`InitialPartySelection`, `updateWeapons`, `resetMenus`, `clearDescriptionBox`, `showUpgradeWindow`,
`showVendorWindow`, `orientScreen`, `calculatePowerBonus`, `calculateArmorBonus`, `OnApplicationPause`,
`unlockPlayableCharacters`, `Main`. The coroutine BODIES (nested `$xxxInput$NNNN` classes, L43674-59086, i.e. the actual
click/drag/buy/sell logic) are NOT in this scope; where I peeked at them for cross-reference the citation says so.

Notation: `DB` = `Database` component found by `GameObject.Find("**DATABASE")`. `SEL` = `DB.partyDB[selectedPlayer]`
(a `Player`). `party[i]` = `DB.party[i]` (party slot -> partyDB index, -1 = empty). Class ids: `Player.characterClass` is
1-based; `DB.powerDB[characterClass-1]` is the class record (`powerCollection`: `whichClass`, `powerScale`, `defenseScale`,
`whichPower[]`, see `bh/data/classes.json`).

## 1. Summary

MenuBrain is the single controller for every out-of-battle screen. One integer, `activeMenu`, selects which screen is
live. Every frame `Update` starts the matching input coroutine (or runs `introSequence`/`tutorialInput` directly), adds
`Time.deltaTime` to `DB.timePlayed`, and optionally fades out the music. Screens: 0 town overview ("main"), 1 Armory
(inventory/equipment), 2 Merchant (store), 3 Academy (skills), 4 Tavern (recruit), 5 Map ("battle"), 6 Load/save-slot
screen, 7 New-game intro narrator, 8 Keep (reserve roster), 9 Tutorial text overlay; -100 is a "busy/transition" value that
matches no case in `Update`.
`UpdateInventory()` is the big screen-refresher: depending on `activeMenu` it redraws the 20 inventory icons + 4 equipment
slots + power/armor numbers (Armory), the 20 inventory + 8 merchant icons (Merchant), the skill tree (Academy), the
recruit sheet (Tavern), the level map (Map), or the 12 reserve icons (Keep). The displayed Power and Armor numbers
use explicit formulas (section 7). Limits seen in code: inventory 20 slots, equipment 4 slots per character (weapon,
armor, 2 trinket slots), party 4, reserves 12, merchant 8 slots, 3 save slots.

## 2. Fields (all 177, declaration order) [IL L32876-33052]

Many fields are scene-wired references (set in the Unity editor, so no default is visible in code). "Used here" says
whether the field is referenced inside L33054-43673; "coroutines" means only the nested input coroutines (out of scope)
touch it (reference counts taken by grepping `MenuBrain::name`). Types abbreviated: Tr=Transform, Rd=Renderer, TM=TextMesh,
Anim=Animation, TP=TextPrint (custom class with `Printout(string)`).

### 2.1 Core / state

| Field | Type | Meaning | Default / set by |
|---|---|---|---|
| DB | Database | game-state singleton | `Awake`: `GameObject.Find("**DATABASE").GetComponent("Database")` [IL L33118-33123] |
| activeMenu | int (public) | current screen id (table in section 4) | Awake sets 6 or 9 or leaves 0 [IL L33132, L33206, L33300] |
| selectedPlayer | int | partyDB index of the character shown on Armory/Academy/Tavern sheets; -1 = none | set by InitialPartySelection [IL L41834] |
| currentMap | int | map index into `DB.levelDB` shown on Map screen | `Awake`: = `DB.currentMap` [IL L33305-33309] |
| whichTutorial | int | index of the tutorial page being shown (0-16) | see section 5 |
| intro | int (private) | intro-narrator state 1..8 | ctor = 1 [IL L33076-33077] |
| audioFade | bool | when true `Update` ramps BGMusic volume down | coroutines set it |
| musicTime | float | saved BGMusic playback time across pause | OnApplicationPause |
| displayGold | float (private) | animated gold counter value | `resetMenus` sets = DB.gold [IL L42754] |
| pickedUpSlot | int (private) | slot index (0-19 inventory, 20-23 equipment; store uses 0-27) currently being dragged; its icon is hidden | ctor = -1 [IL L33067-33068] |
| whichSlotSelected | int (private) | slot chosen for upgrade/vendor windows | coroutines set it; read by showUpgradeWindow/showVendorWindow |
| whichSlotToDrop | int (private) | drop-target slot | ctor = -1 [IL L33070-33071]; used by coroutines |
| oldSlot | int (private) | coroutines only | none |
| tempValue | int (private) | scratch | ctor = -1 [IL L33073-33074] |
| itemResetTimer | float (private) | coroutines only (UNVERIFIED purpose: drag/reset timer) | none |
| draggingThreshold | float (private) | pixel distance before a press becomes a drag | ctor 20.0 [IL L33064-33065]; `Awake` overwrites with `Screen.width / 30` [IL L33111-33116] |
| avoidDoubleTap, saveWeJustQuit | bool/int (private) | coroutines only | none |

### 2.2 Input fields

| Field | Type | Meaning |
|---|---|---|
| totalTouches | int | clamp(Input.touchCount,0,5) or 1 for mouse (see section 5.3) |
| fakeTap | bool | true when the tap came from the mouse rather than a touch |
| touchReleaseCheck | int | 1 while pointer held, 0 when released/none |
| tapPosition, contactPosition | Vector2 | pointer screen position (contactPosition: coroutines only) |
| touchState | int | 0 = ready, -1 = this press already consumed |
| theFingerId | int | finger id (0 for mouse) |
| touch | Touch | `Input.GetTouch(0)` copy |
| tempRay, tempHit | Ray, RaycastHit | picking (coroutines only) |
| tempGO, tempTransform, tempTransform2 | GameObject/Tr | scratch used by map building |
| tempRenderer, tempAnimation | Rd/Anim | coroutines only |
| keyboard, keyBoardInput, weAreTyping | iPhoneKeyboard/string/bool | name-entry keyboard, coroutines only (loadInput) |
| itemMask, partyMask, upgradeMask, cancelMask, okayMask, exitMask | LayerMask | raycast masks for item / party portrait / upgrade button / cancel / okay / exit; coroutines only |
| cameraLens, cameraTransform | Camera/Tr | menu camera; coroutines only |

### 2.3 Main / Keep / portraits

| Field | Type | Meaning |
|---|---|---|
| battleButton, litSword | Tr, Rd | main-screen "battle" button and its lit sword (coroutines only) |
| keepIcons | Rd[12] | reserve portraits; `Awake` adds a BoxCollider (1.1,1.1,0.1) to each of the 12 [IL L33396-33421] |
| keepLevels | TM[] | "Lv.N" labels under keep icons [IL L41062-41079] |
| portraitModels | Tr[] | 3D party portraits indexed by partyDB id [IL L41130-41771] |
| portraitButtons, portraitButtons2, portraitButtons3 | Tr[] | party-portrait click buttons for Armory / Academy / (3 unused here) |
| characterSheetModels | Tr[] | large 3D character models for sheets, indexed by partyDB id |
| characterSheetWeapons | GameObject[2] | instantiated weapon/shield props on the sheet model (slot 0 weapon, slot 1 off-hand) |
| redSquares | Tr[] | red "cannot use" overlays for inventory slots |
| equipArrows | Rd[4] | per-party-slot up/down equip arrows in Armory; all disabled by UpdateInventory (menu 1) [IL L36608-36626] |
| partySelect, partySelectAnim | Tr/Anim | highlight box on the selected party portrait |
| closeupGroup | Tr | camera-closeup group; its x position scrolls the sheet into view |
| nameText | TM | selected character's name (Armory) |
| powerText, armorText | TM | Armory Power / Armor numbers |
| powerText2, armorText2 | TM | same on the Tavern sheet |
| goldText, goldText2, goldText3 | TM | gold displays (Armory/Merchant/other); only `goldText` touched in range |
| select, selectAnim | Tr/Anim | item-selection cursor (hidden at y=5 by resetMenus [IL L42730-42751]) |
| heldIcon, heldIconRenderer | Tr/Rd | dragged-item icon (coroutines only) |
| merchantArrowsRoot, merchantArrows | Tr / Tr[8] | 8 buy-comparison arrows (0-3 "better", 4-7 "worse") |

### 2.4 Armory / Merchant widgets

| Field | Meaning |
|---|---|
| inventoryIcons Rd[24] | Armory: 0-19 backpack, 20-23 equipment; `Awake` gives each a BoxCollider(1.3,1.3,0.1) [IL L33319-33340] |
| inventoryIcons2 Rd[28] | Merchant: 0-19 backpack, 20-27 merchant stock; BoxCollider(1.3,1.3,0.1) on 28 [IL L33346-33367] |
| itemNameText, itemDescText, itemPowerText, priceText (TP); priceIcon, anvilIcon, powerIcon, defenseIcon (Rd); upgradeButton, upgradeButtonLight | Armory description panel; cleared by clearDescriptionBox |
| itemNameText2, itemDescText2, itemPowerText2, priceText2 (TP); priceIcon2, powerIcon2, defenseIcon2 (Rd); vendorButton, vendorButtonAnim, vendorButtonLight | Merchant description panel |
| portraitCovers Tr[4] | covers over party portraits in Merchant (hidden y=5 by clearDescriptionBox menu 2 [IL L42977-43011]) |
| costLocation Tr | price-label anchor; clearDescriptionBox(menu 2) sets localPosition.x = 0.44462120532989502 [IL L43057-43072] |
| upgradeWindow, upgradeWindowAnim, upgradeWindowText (TM), upgradeWindowIcon (Rd) | upgrade confirmation popup |
| vendorWindow, vendorWindowAnim, vendorWindowIcon, vendorWindowName, vendorWindowPrice, vendorWindowText, vendorWindowText2 | buy/sell confirmation popup |

### 2.5 Academy / Tavern / Map widgets

| Field | Meaning |
|---|---|
| skillIcons Rd[12] | one per `powerCollection.whichPower[0..11]`; BoxCollider(1.3,1.3,0.1) added to all 12 in Awake [IL L33373-33394] |
| skillGreyouts Tr[10], litSticks Tr[5], litLines Rd[6] | tier decoration (see 6.3) |
| skillNameText, skillDescText, classText (TP) | skill description panel; classText shows "Name - Level N Class" |
| recruitGearIcons Rd[4], recruitNameText, recruitDescText, recruitPriceText, recruitClassText (TP), recruitNameSmall (TM), recruitCoinIcon (Rd) | Tavern recruit sheet |
| hireButtonAnim, hireScreen, hireScreenAnim, hireScreenText | hire confirmation (coroutines only) |
| mapIcons Tr[], mapJunk Tr[], mapGeo Tr, mapAnim, mapNameText (TM), levelNameText, levelDescText (TP) | Map screen |
| loadingText | referenced nowhere in MenuBrain code (0 refs) |

### 2.6 Load screen / save slots

`fadeOutLoadScreen`, `fadeInMainMenu` (TitleAnimation), `warningScreen`, `warningScreenAnim`, `deleteRenderers` Rd[3]
(delete-slot buttons), `newGame1/2/3` Rd, `save1/2/3Name` Rd, `name1/2/3Transform` Tr, `save1/2/3Time` Rd,
`save1/2/3NameText`, `save1/2/3TimeText` TM, `saveSlotRenderers` (coroutines only), `musicRenderer`, `soundRenderer`
(Rd: music/sound toggle icons, alpha 0.3 when off), `sounds` AudioSource[] (`sounds[3]` = tutorial-tap click,
`sounds[7]` = narrator speech blip; others used by coroutines), `BGMusic` AudioSource, `battleStartEffect`,
`battleStartAnim` (coroutines only).

### 2.7 Intro narrator

`narrator` Tr, `narratorAnim` Anim (clips "run", "idle", "select"), `speechBalloon` Rd, `corners` Tr[4] (speech
balloon corners), `speechText` TP, `speechTextTransform` Tr, `dialogStrings` string[] (6+ strings used: indexes 0-5),
`narratorRenderer` Rd[2] (0 = body, 1 = copy target for tint).

### 2.8 Tutorial

`tutorialText` Tr, `tutorialTextText` TM, `tutorialTextBG` Rd, `tutorialStrings` string[] (indexes 0-16 used; the string
CONTENT lives in the scene, not in code, so the wording is not available).

## 3. `.ctor` [IL L33055-33079]

draggingThreshold = 20.0; pickedUpSlot = -1; whichSlotToDrop = -1; tempValue = -1; intro = 1.

## 4. `Awake` [IL L33082-33507]

1. `draggingThreshold = Screen.width / 30` [IL L33110-33116].
2. `DB = GameObject.Find("**DATABASE").GetComponent("Database")` [IL L33118-33123].
3. **If `DB.freshBoot == 1`** (first launch of the app) [IL L33125-33128]: `activeMenu = 6` (Load screen) [L33130-33132];
   `updateLoadScreen()` [L33134]; if `PlayerPrefs.GetInt("cleansave") != 2`: set it to 2, `DB.whichSaveSlot = 4`,
   `DB.save()` [L33135-33149] (one-time migration write to slot 4; purpose UNVERIFIED).
4. **Else** (returning from a battle / scene reload) [IL L33152-33312]:
   - `fadeInMainMenu.enabled = true` [L33152-33155].
   - If `DB.tutorial` is true [L33157-33159]: `DB.currentMap = 0`; `whichTutorial = 0`; `tutorialText.localPosition.y = 0.7`
     (shown; hidden position is y = 10); `tutorialTextBG` enabled; text = `tutorialStrings[0]`; `activeMenu = 9` [L33161-33206].
   - Else if `DB.level5reminder == 1` [L33209-33213]: scan party slots 0-3; if any occupied slot has `partyDB[...].level >= 5`
     [L33215-33250]: `DB.level5reminder = 0`; `whichTutorial = 13`; show `tutorialStrings[13]` at y=0.7 with BG; `activeMenu = 9` [L33255-33300].
   - Always: `DB.tutorial = false`; `currentMap = DB.currentMap`; `DB.save()` [L33301-33312] (autosave every time the town
     scene loads).
5. Add `BoxCollider` (runtime `AddComponent("BoxCollider")`) with sizes: `inventoryIcons[0..23]` (1.3,1.3,0.1) [L33315-33340];
   `inventoryIcons2[0..27]` (1.3,1.3,0.1) [L33342-33367]; `skillIcons[0..11]` (1.3,1.3,0.1) [L33369-33394];
   `keepIcons[0..11]` (1.1,1.1,0.1) [L33396-33421].
6. `narratorAnim["select"]`: layer = 1, blendMode = 1 (Additive) [L33423-33434].
7. `muteSoundEffects()` [L33436]. If `DB.musicEnabled`: `BGMusic.Play()` [L33438-33444]; else `musicRenderer.material.color.a = 0.3`
   [L33447-33473]. If `!DB.soundEnabled`: `soundRenderer.material.color.a = 0.3` [L33475-33505].

## 5. State machine

### 5.1 `activeMenu` values

| Value | Screen | Per-frame handler in `Update` [IL L33578-33716] | Entered from |
|---|---|---|---|
| 0 | Town overview ("main") | `StartCoroutine(mainInput())` [L33584-33591] | back from other screens (their coroutines set 0: inventoryInput L45491/L48001, storeInput L50895/L52182, skillsInput L52549/L53539, tavernInput L53923/L54785, mapInput L55177/L56226, keepInput L56564/L57136, `loadExistingGame` L58981; cross-ref, out of scope); tutorial pages 1 and 13 |
| 1 | Armory (inventory + equipment) | `inventoryInput()` | mainInput button string "armory" [IL L48428-48432, cross-ref] |
| 2 | Merchant (store) | `storeInput()` | button "merchant" [L48589-48593] |
| 3 | Academy (skills) | `skillsInput()` | button "academy" [L48750-48754] |
| 4 | Tavern (recruit) | `tavernInput()` | button "tavern"; calls `unlockPlayableCharacters()` first [L48874-48881 and call at L48880] |
| 5 | Map (level select) | `mapInput()` | button "battle" [L48931, L48970] |
| 6 | Load / save-slot screen | `loadInput()` | Awake when `freshBoot`; button "home" [L49146-49150] |
| 7 | Intro narrator | `introSequence()` called directly (not a coroutine) | `startNewGame` coroutine sets 7 [L58802, cross-ref] |
| 8 | Keep (reserve roster) | `keepInput()` | button "keep" [L49022-49026] |
| 9 | Tutorial overlay | `tutorialInput()` called directly | Awake; first-visit hooks in mainInput [L48525, L48686, L48810, L49082] and mapInput [L55942] |
| -100 | busy / loading | none | loadInput [L57836, L57938, L58040, L58610] and loadExistingGame [L58969] |

Dispatch is a chain of `if/else if` comparing `activeMenu` to 0..9 [IL L33584-33693]; any other value runs nothing.
Because the coroutines are re-started EVERY frame by `Update`, the coroutine bodies must guard themselves (their own
`touchState` etc.; not analysed here).

After the dispatch, `Update` [IL L33695-33715]:
- if `audioFade`: `BGMusic.volume -= Time.deltaTime` [L33696-33706].
- `DB.timePlayed += Time.deltaTime` every frame, in every state (play-time counter shown on save slots) [L33707-33714].

### 5.2 Screen setup helper chain

`resetMenus()` [IL L42711-42770] (called by mainInput right after each screen switch: L48508, L48669, L48793, L48920,
L49011, L49065): `clearDescriptionBox(); InitialPartySelection(); UpdateInventory(); UpdatePartyPortraits();`
`select.position.y = 5` (hide cursor); `displayGold = DB.gold`; `goldText.text = DB.gold.ToString()`.

### 5.3 Pointer-input preamble (identical in `tutorialInput` and `introSequence`)

[IL L34156-34264, L35993-36066]
```
touchReleaseCheck = 0
totalTouches = Clamp(Input.touchCount, 0, 5);  fakeTap = false
if (GetMouseButton(0) && totalTouches==0) || (GetMouseButtonUp(0) && totalTouches==0):
    fakeTap = true; totalTouches = 1; theFingerId = 0; tapPosition = Input.mousePosition
    touchReleaseCheck = GetMouseButtonUp(0) ? 0 : 1
if totalTouches != 0:
    if !fakeTap: touch = GetTouch(0); touchReleaseCheck = 1; tapPosition = touch.position
    if touchState == 0:            // fresh press
        touchState = -1            // consume
        <advance page, see below>
if touchReleaseCheck == 0: touchState = 0     // re-arm only after release / no input
```
So one tap advances exactly one page; holding does not repeat.

## 6. Method sections

### 6.1 `muteSoundEffects` [IL L33510-33575]
If `!DB.soundEnabled`: every `sounds[i].volume = 0`. If `DB.soundEnabled`: every `sounds[i].volume = 1`.
(BGMusic is separate: `musicEnabled`.)

### 6.2 `OnApplicationPause(bool)` [IL L43530-43567]
Paused -> `musicTime = BGMusic.time`. Resumed -> if `BGMusic.clip != null && DB.musicEnabled`: `BGMusic.Play(); BGMusic.time = musicTime`.

### 6.3 `orientScreen` [IL L43364-43385]
If `Input.deviceOrientation == 4` -> `Screen.orientation = 4` (LandscapeRight); else if `== 3` -> `Screen.orientation = 3` (LandscapeLeft).

### 6.4 `tutorialInput` [IL L34156-34811]
Runs only while `activeMenu == 9`. Preamble in 5.3. On a fresh tap, switch on `whichTutorial`. "show(n)" = set
`tutorialTextText.text = tutorialStrings[n]`, play `sounds[3]`, set `whichTutorial = n`. "hide(nextMenu)" = play `sounds[3]`,
`tutorialText.localPosition.y = 10` (off-screen), `tutorialTextBG` disabled, `activeMenu = nextMenu`.

| whichTutorial (current) | Action on tap | Source |
|---|---|---|
| 0 | show(1) | L34271-34290 |
| 1 | hide -> activeMenu 0 (town) | L34292-34335 |
| 2 | show(3) | L34337-34357 |
| 3 | hide -> activeMenu 3 (Academy) | L34359-34402 |
| 4 | show(5) | L34404-34424 |
| 5 | show(6) | L34426-34446 |
| 6 | show(7) | L34448-34468 |
| 7 | hide -> activeMenu 1 (Armory) | L34470-34513 |
| 8 | show(9) | L34515-34535 |
| 9 | show(10) | L34537-34557 |
| 10 | hide -> activeMenu 2 (Merchant) | L34559-34602 |
| 11 | show(12) | L34604-34624 |
| 12 | hide -> activeMenu 8 (Keep) | L34626-34669 |
| 13 | hide -> activeMenu 0 | L34671-34714 |
| 14 | show(15) | L34716-34736 |
| 15 | show(16) | L34738-34758 |
| 16 | hide -> activeMenu 5 (Map) | L34760-34803 |

Which tutorial each screen starts at (cross-ref, from mainInput, out of scope): Armory first visit (`DB.armoryFirstVisit==1`,
then cleared to 0) -> activeMenu 9, `whichTutorial=4` [L48513-48529]; Merchant (`merchantFirstVisit`) -> 8 [L48674-48690];
Academy (`academyFirstVisit`) -> 2 [L48798-48814]; Keep (`keepFirstVisit`) -> 11 [L49070-49086]. New game: 0 (Awake). Level-5
reminder: 13 (Awake). Pages 14-16 (map tutorial) are started from mapInput (set at L55942 area; not verified here).
Page 1/13 hide to the town; pages 4-7 are the Armory sequence, 8-10 Merchant, 2-3 Academy, 11-12 Keep.

### 6.5 `updateLoadScreen` [IL L34814-35542]
Refreshes the three save-slot panels. Per slot n in 1..3 (identical code at L34839-35082 (slot 1), L35083-35311 (slot 2),
L35312-35540 (slot 3)):
1. `exists = PlayerPrefs.GetInt("<n>saveExists") == 1`.
2. If NOT exists: `newGameN` renderer enabled, `saveNName` and `saveNTime` renderers disabled, `deleteRenderers[n-1]`
   material alpha = 0.3 (greyed delete button) [L34856-34900 for slot 1].
3. If exists: `deleteRenderers[n-1]` alpha = 1; `newGameN` disabled; `saveNName`, `saveNTime` enabled;
   `saveNNameText.text = PlayerPrefs.GetString("<n>PlayerName")`; name label scale (uniform) by length:
   `len > 8` -> 0.0531; `len > 6` -> 0.064; else 0.082 [L34904-34991].
4. Time: `secs = RoundToInt((int) PlayerPrefs.GetFloat("<n>timePlayed"))`; `mins = secs/60`; `hrs = mins/60`; `secs -= mins*60`;
   `mins -= hrs*60`; text = `hrs + ":" + (mins<10 ? "0" : "") + mins + ":" + (secs<10 ? "0" : "") + secs`, i.e. `H:MM:SS` [L34992-35082].
Keys: `1saveExists`, `2saveExists`, `3saveExists`, `1PlayerName`..., `1timePlayed`... (PlayerPrefs). Called from Awake (fresh boot)
and from mainInput/loadInput (cross-ref L49227, L49400, L57596, L57827, L57929, L58031, L58601).

### 6.6 `introSequence` (new-game narrator) [IL L35558-36257]
Runs while `activeMenu == 7`; `intro` is the state (starts at 1). Narrator walks in, speaks 6 lines on tap, walks out,
then starts the tutorial level.
- **intro == 1 (walk-in)** [L35560-35756]: if `narratorRenderer[0].material.color.r < 0.25`: color += `Color(1,1,1) * deltaTime * 0.25`
  (fade up from black); if r >= 0.25 clamp to `Color(0.25,0.25,0.25)`; copy that colour to `narratorRenderer[1]` [L35601-35670].
  If `narrator.position.x < 60`: `x += deltaTime * 1.7` and play "run" [L35671-35720]. Else: `CrossFade("idle", 0.2)`; play "select";
  `intro = 2`; `sounds[7].Play()`; `speechBalloon` enabled; `applyCorners(3.13, -2.446, 1.063)`; `speechText.Printout(dialogStrings[0])` [L35722-35749].
- **intro == 8 (walk-out)** [L35758-35992]: if `narrator.x < 80`: `x += deltaTime*1.7`, play "run". If `x > 60.5`: body colour r,g,b each
  `-= deltaTime * 0.25` and mirrored to renderer[1] [L35812-35961]. If `narratorRenderer[0].color.r <= 0` (fully black):
  `DB.currentMap = 2; DB.whichLevel = 0; DB.tutorial = true; DB.transferLevel = 3; Application.LoadLevel(4)` [L35962-35991]
  (loads scene 4 = the tutorial battle; Awake of the next town load sees `DB.tutorial`).
- **Tap handling** (preamble 5.3) [L36073-36245]; each advance plays `sounds[7]`, plays "select", and moves the balloon:

| intro | next | applyCorners(left, right, top) | dialogStrings idx |
|---|---|---|---|
| 2 | 3 | 3.312, -2.548, 1.063 | 1 |
| 3 | 4 | 3.16, -2.447, 1.415 | 2 |
| 4 | 5 | 3.312, -2.649, 0.74 | 3 |
| 5 | 6 | 3.186, -2.472, 1.415 | 4 |
| 6 | 7 | 2.857, -2.219, 1.063 | 5 |
| 7 | 8 | `speechBalloon` disabled, `speechText.Printout("")` | - |

(Values quoted are the float constants rounded to the printed digits; exact constants: 3.1300001144, -2.4460000992, 1.0629999638, 3.3120000362, -2.5480000973, 3.1600000858, -2.4470000267, 1.4149999618, -2.6489999294, 0.7400000095, 3.1860001087, -2.4719998836, 2.8570001125, -2.2190001010.)

### 6.7 `applyCorners(left, right, top)` [IL L36260-36413]
`corners[0].localPosition.x = left; corners[1].localPosition.x = right; corners[2].localPosition.y = top; corners[3].localPosition.y = top;`
`speechTextTransform.position = corners[2].position + (0.2, -0.2, 1.5)`.

### 6.8 `startNewGame`, `loadExistingGame`, `inventoryInput`, ... stubs
Each creates its nested generator class (`$name$NNNN`) and returns its enumerator [IL L33719-33729, L34065-34153, L35545-35555, L36416-36426]. Bodies out of scope.

### 6.9 `Update` [IL L33578-33716]
See 5.1. Nothing else (no gold tween here; `displayGold` is driven by coroutines).

### 6.10 `updateEquipArrows(int whichItem)` [IL L33732-34062]
Store comparison arrows for the item `whichItem` (an item id). `merchantArrows[0..3]` = "upgrade" arrows, `[4..7]` = "downgrade"
arrows; "show" = `merchantArrows[k].position.y = 0` (hidden is y=5, set by clearDescriptionBox). For each party slot i = 0..3 with `party[i] != -1`:
1. Skip if `itemDB[whichItem].usableBy[partyDB[party[i]].characterClass - 1]` is false [L33758-33788].
2. If item is "armor": if `gear[1] == -1` -> show `merchantArrows[i]` [L33790-33845].
3. Else if "weapon": if `item.power > itemDB[gear[0]].power` -> show `[i]` [L33847-33880]. If "armor": if `item.power > itemDB[gear[1]].power` -> show `[i]` [L33882-33945].
4. Else if "weapon": if `item.power < itemDB[gear[0]].power` -> show `[i+4]` [L33949-33982]; if "armor": if `item.power < itemDB[gear[1]].power` -> show `[i+4]` [L33984-34051].
Equal power shows nothing. Trinkets (itemType "trinket") are never compared. The base item power only is compared (no level/bonus).
Called from storeInput-area coroutines (L44372, L47635; cross-ref).

### 6.11 `InitialPartySelection` [IL L41775-42275]
- **Armory (1)** [L41825-41954]: `partySelect.position = portraitButtons[0].position`; `selectedPlayer = party[0]`; hide every
  `characterSheetModels[k]` (y=5); `closeupGroup.position.x = 0`; `characterSheetModels[selectedPlayer].position.y = -0.57`;
  `nameText = SEL.playerName`; `updateWeapons()`.
- **Academy (3)** [L41956-42116]: `partySelect.position = portraitButtons2[0].position`; `selectedPlayer = party[0]`; hide models;
  `closeupGroup.position.x = -61.501930236816406`; model y = -0.66; `classText.Printout(playerName + " - Level " + level + " " + powerDB[class-1].whichClass)`; `updateWeapons()`.
- **Tavern (4)** [L42118-42274]: `selectedPlayer = -1`; loop `i` over partyDB: first entry with `!recruited && available == 1` becomes
  `selectedPlayer` (loop is ended by setting i = length) [L42126-42164]; hide models; if found: `closeupGroup.position.x = -80`, model y = -0.57, `updateWeapons()`.
- Other menus: nothing.

### 6.12 `UpdatePartyPortraits` [IL L41095-41772]
Only for activeMenu 1, 2, 3, 8. First hide all `portraitModels` (y = 5). Then place `portraitModels[party[0]]` at
`(X, 1.5071010589599609, 1.8)` with X = **-3.19** (Armory), **-43.19** (Merchant), **-63.19** (Academy), **-103.19** (Keep) [L41170, L41333, L41496, L41659];
then for k = 1,2,3: if `party[k] != -1`, `portraitModels[party[k]].position = portraitModels[party[0]].position + (1.25*k, 0, 0)` (offsets 1.25, 2.5, 3.75) [L41183-41281].
Models are indexed by partyDB id, so a party is displayed as a row of up to 4 portraits 1.25 units apart; party[0] must be non-empty.

### 6.13 `updateWeapons` [IL L42278-42708]
Rebuilds the weapon props on `characterSheetModels[selectedPlayer]`:
1. Destroy `characterSheetWeapons[0]` and `[1]` if they exist [L42278-42306].
2. If `itemDB[SEL.gear[0]].ingameModel != "none"`: instantiate `Resources.Load(ingameModel)` into slot 0, parent to bone `"arm_l/weapon"`,
   localPosition (0,0,0), localEulerAngles (0,0,0), localScale (1,1,1) [L42308-42398].
3. If `characterClass == 7` (1-based, so `classes[6]` = Barbarian in classes.json): also instantiate the SAME model into slot 1 parented to `"arm_r/weapon2"` (same local transform) = dual wield [L42399-42481]. (Dual-wield weapons in items.json are Barbarian items, e.g. "Dual Hatchets" usable by index 6.)
4. Off-hand: if `characterClass == 2` (Knight) and `playerName == "Shepherd"` -> `Weapons/shield1` on bone `"shield"` [L42482-42563]; else if class 2 -> `Weapons/shield2` [L42565-42635]; else if `characterClass == 10` (Paladin) -> `Weapons/pallyShield` [L42637-42706]. All with local pos/euler (0,0,0), scale (1,1,1).
Armor and trinkets never change the model.

### 6.14 `clearDescriptionBox` [IL L42773-43113]
- activeMenu 1 [L42777-42912]: `upgradeButton.position.y = 5` (hidden); clear `itemNameText`, `itemDescText`, `itemPowerText`, `priceText` (Printout("")); disable `priceIcon`, `anvilIcon`, `powerIcon`, `defenseIcon`; `merchantArrows[0..7].position.y = 5`.
- activeMenu 2 [L42914-43080]: `vendorButton.position.y = 5`; clear `itemNameText2`, `itemDescText2`, `itemPowerText2`, `priceText2`; disable `priceIcon2`, `powerIcon2`, `defenseIcon2`; `portraitCovers[0..3].y = 5`; `merchantArrows[0..7].y = 5`; `costLocation.localPosition.x = 0.44462120532989502`.
- activeMenu 3 [L43084-43097]: clear `skillNameText`, `skillDescText`.
- activeMenu 5 [L43099-43108]: `levelNameText = ""`; `levelDescText = "    Tap a location on the map to proceed!"`.

### 6.15 `showUpgradeWindow` [IL L43116-43227]
`upgradeWindow.position.y = 0` (move on-screen); play anim "enter" on `upgradeWindowAnim`. Item id: if `whichSlotSelected <= 19` -> `DB.inventory[whichSlotSelected]` else `SEL.gear[whichSlotSelected - 20]`. Text = `DB.gold + "\n" + RoundToInt(itemDB[ itemDB[item].upgrade ].sellPrice * 1.5)`. **Upgrade cost = round(1.5 * sellPrice of the upgrade-target item).** Icon = `Resources.Load(itemDB[item].icon)`.

### 6.16 `showVendorWindow` [IL L43230-43361]
`vendorWindow.position.y = 0`; anim "enter". If `whichSlotSelected <= 19` (backpack item, selling): item = `DB.inventory[slot]`; price text = `itemDB[item].sellPrice / 2` (integer division); texts "Sell this item?" / "Sell price:" [L43274-43310]. Else (merchant stock, buying): item = `DB.merchant[slot - 20]`; price text = `itemDB[item].sellPrice` (full); texts "Buy this item?" / "Purchase cost:" [L43312-43339]. Name = `itemName`; icon = `Resources.Load(icon)`.
**Sell value = floor(sellPrice/2); buy price = sellPrice.**

### 6.17 `calculatePowerBonus` / `calculateArmorBonus` [IL L43388-43527]
Both loop gear slots i = 2 and 3 (the two trinket slots) of `SEL` and sum `itemDB[gear[i]].power` for items whose ID is in a range:
- **Power bonus: item id 12..17 inclusive** (0x0c..0x11) [L43410-43417]. Per items.json: 12 Swordsman's Gauntlet (3), 13 Power Fist (6), 14 Titan's Glove (10), 15 Energy Ring (3), 16 Firestorm Band (6), 17 Kaimani's Bloodstone (10).
- **Armor bonus: item id 24..26 inclusive** (0x18..0x1a) [L43481-43488]: 24 Silver Armlet (3), 25 Glyph of Stoneskin (6), 26 Sharkul's Skull (10).
Other trinkets' `power` field is NOT added here (their effects are applied elsewhere in battle, out of scope). An empty slot (-1) is below the range so contributes 0. Note: an id in range sitting in gear[0]/[1] is not summed (loop starts at 2).

### 6.18 `unlockPlayableCharacters` [IL L43570-43662]
`maxLevel = 1`; for every partyDB entry that is `recruited`, `maxLevel = max(maxLevel, level)` [L43573-43620]; then for every partyDB entry with
`level <= maxLevel` and `!available`: `available = true` [L43622-43659]. So a character becomes recruitable (listed in the Tavern) when its level is <= the
highest level among already-recruited characters. Called on entering the Tavern (call at L48880).

### 6.19 `UpdateInventory` [IL L36429-41092] (the screen refresher; branches on `activeMenu`)

#### 6.19.1 Armory (activeMenu == 1) [L36601-37140]
1. `equipArrows[0..3]` disabled [L36608-36626].
2. For slot i = 0..19 (inventory size = 20): if `DB.inventory[i] == -1` or `pickedUpSlot == i`: `inventoryIcons[i]` disabled and `redSquares[i]` hidden (y=5, z=-1.3054649829864502). Else: icon enabled with `mainTexture = Resources.Load(itemDB[inv[i]].icon)`; if `!itemDB[...].usableBy[SEL.characterClass - 1]` the red square is moved to the icon's position (red overlay = class cannot use it), else hidden [L36636-36843].
3. Equipment slots i = 0..3: icon `inventoryIcons[20+i]`: disabled if `SEL.gear[i] == -1` or `pickedUpSlot == i+20`, else enabled with that item's icon [L36851-36916]. (gear[0] weapon, gear[1] armor, gear[2], gear[3] trinkets — see calculate*Bonus.)
4. **Power number (`powerText`)** [L36924-37064]:
   - Cleric (`characterClass == 1`): `P = int( (powerDB[0].powerScale * level + SEL.power) / 5 )`; `P += itemDB[gear[0]].power`; `P += calculatePowerBonus()`.
   - All other classes: `P = SEL.power + itemDB[gear[0]].power + calculatePowerBonus()`; then `P = int( P + powerScale * level )`.
   - (`powerScale`: Cleric 3.0, others 1.0 per classes.json; int() truncates.) The text is `P.ToString()`.
5. **Armor number (`armorText`)** [L37065-37139]: `A = SEL.defense`; if `gear[1] != -1`: `A += itemDB[gear[1]].power`; `A += calculateArmorBonus()`; `A = int( A + defenseScale * level )`. (`defenseScale`: Knight 1.2, Monk 1.2, Paladin 1.2, others 1.0.)
The Tavern sheet (6.19.4) uses the same two formulas into `powerText2`/`armorText2`.

#### 6.19.2 Merchant (activeMenu == 2) [L37142-37269]
`inventoryIcons2[0..19]` show `DB.inventory[i]` (hidden if -1 or `pickedUpSlot == i`); `inventoryIcons2[20+j]`, j = 0..7, show `DB.merchant[j]` (hidden if -1 or `pickedUpSlot == j+20`). Merchant stock size = 8. Icons from `itemDB[id].icon`.

#### 6.19.3 Academy (activeMenu == 3) [L37271-38889]
Resets: `litLines[0..5]` disabled; `litSticks[0..4].position.y = 5`; `skillIcons[0..11]` disabled; `skillGreyouts[0..9].position.y = 5` [L37276-37392]. The tree has 12 powers (`powerDB[class-1].whichPower[0..11]`); icon `k` shows `whichPower[k].icon`.
Unlock by character level (level values quoted from compare constants):

| Level needed | litLine | Icons shown (power idx) | Choice record | Source |
|---|---|---|---|---|
| always | - | 0 | - | L37396-37425 |
| >= 5 | litLines[0] | 1, 2 | `abilities[1]` | L37427-37710 |
| >= 10 | litLines[1] | 3, 4 | `passives[0]` | L37710-37993 |
| >= 15 | litLines[2] | 5, 6 | `abilities[2]` | L37993-38276 |
| >= 20 | litLines[3] | 7, 8 | `passives[1]` | L38276-38559 |
| >= 25 | litLines[4] | 9 | (none) | L38559-38604 |
| >= 30 | litLines[5] | 10, 11 | `passives[3]` | L38606-38889 |

Choice display (tier t with greyout g = skillGreyouts[t], stick s = litSticks[t], alternate greyout g2 = skillGreyouts[t+5]; heights are the literal y values):
- `abilities[1]`: ==3 -> g.y = 0, s.y = -0.56; ==2 -> g.y = -0.97, s.y = 0; else (unchosen) g.y = 0 and g2(`skillGreyouts[5]`).y = -0.97 [L37505-37708].
- `passives[0]` (tier 1): ==-1 -> g(`[1]`).y=0, s(`[1]`).y=-0.56; ==1 -> g.y=-0.97, s.y=0; else g.y=0 and `skillGreyouts[6].y=-0.97` [L37788-37991].
- `abilities[2]` (tier 2): ==5 -> g(`[2]`).y=0, s.y=-0.56; ==4 -> g.y=-0.97, s.y=0; else g.y=0 and `skillGreyouts[7].y=-0.97` [L38071-38274].
- `passives[1]` (tier 3): ==-1 -> `[3]`.y=0 & stick `[3]`.y=-0.56; ==1 -> greyout -0.97 & stick 0; else `[3]`=0 & `skillGreyouts[8].y=-0.97` [L38354-38557].
- `passives[3]` (tier 4): ==-1 -> `[4]`.y=0 & stick -0.56; ==1 -> -0.97 & stick 0; else `[4]`=0 & `skillGreyouts[9].y=-0.97` [L38684-38887].
(Which stored value corresponds to which option: from skillsInput, cross-ref: choosing the first option of tier 1 writes `abilities[1]=2`, second `=3` [L53244, L53269]; tier 2: `passives[0]=1` / `-1` [L53294, L53319]; `abilities[2]=4` / `5` [L53344, L53369]; `passives[1]=1` / `-1` [L53394, L53419]; `passives[3]=1` / `-1` [L53444, L53469]. `passives[2]` is never displayed here. UNVERIFIED: which physical icon each greyout y position covers; only the literal values are recorded.)
Defaults for a new character: `abilities = [1,0,0]`, `passives = [0,0,0,0]` (bh/data/party.json).

#### 6.19.4 Tavern (activeMenu == 4) [L38891-39458]
If `selectedPlayer != -1` [L38896]:
- `recruitGearIcons[0..3]`: hidden when `gear[i]==-1`, else icon of that item [L38901-38957].
- `recruitCoinIcon` enabled; `recruitNameSmall.text` and `recruitNameText.Printout` = playerName; `recruitDescText.Printout(description)`; `recruitClassText.Printout(whichClass + " Lv. " + level)` [L38961-39022].
- **Hire price text: `recruitPriceText.Printout(": " + level * 10)`** (gold = 10 x level) [L39023-39037]. (The actual deduction happens in tavernInput; verify there.)
- Power/Armor into `powerText2`/`armorText2` with the formulas of 6.19.1 [L39038-39253].
- Hide all `characterSheetModels` (y=5), then if selectedPlayer != -1: `closeupGroup.position.x = -80`, model y = -0.57, `updateWeapons()` [L39254-39362].
Else (nobody available) [L39364-39456]: hide `recruitGearIcons`, clear `powerText2`, `armorText2`, `recruitNameSmall`, `recruitNameText`, `recruitClassText`, `recruitPriceText`; `recruitDescText = "No recruits are currently\navailable.  Check back\nlater!"`; `recruitCoinIcon` disabled; hide all sheet models.

#### 6.19.5 Map (activeMenu == 5) [L39460-41005]
1. Destroy every existing `mapIcons[k]` and `mapJunk[k]` GameObject if non-null [L39465-39519].
2. `mapNameText.text = DB.levelDB[currentMap].mapName` [L39521].
3. For each level `L = levelDB[currentMap].whichLevel[i]` (loop to `whichLevel.Length`) [L39531-41003] choose an icon prefab from `Resources/MapElements/...`, parent it to `mapGeo`, position it, store in `mapIcons[i]`:

| Condition | Prefab | Connector |
|---|---|---|
| `L.prereq == -1` and `L.transition != -1` | `ArrowRight` if `transitionDirection == 2` else `ArrowLeft` | none |
| `prereq == -1`, no transition, `L.arena` | `Crown` | none |
| `prereq == -1`, none of above, `L.complete` | `Checkbox` | none |
| `prereq == -1`, else | `Skullface` | none |
| `prereq != -1`, `L.transition != -1` and `whichLevel[prereq].complete` | `ArrowRight`/`ArrowLeft` as above | `darkStick<loc>` |
| (else) `L.complete` | `Crown` if arena else `Checkbox` | `darkStick<loc>` |
| (else) `whichLevel[prereq].complete` | `Crown` if arena else `Skullface` | `darkStick<loc>` |
| (else) prerequisite not complete | `Lock` | `lightStick<loc>` |
(Sources: no-prereq branch L39535-39676; prereq+transition L39684-40017; complete L40024-40334; available L40341-40660; locked L40667-40945.)
- Position of a node WITH a prerequisite = `mapIcons[prereq].position + offset(prereqLoc)` where `s = levelDB[currentMap].mapScale`: prereqLoc 0 -> (0, -s, 0); 1 -> (0, +s, 0); 2 -> (-s, 0, 0); 3 -> (+s, 0, 0) [e.g. L39758-39995]. The connector prefab (`darkStick0..3` / `lightStick0..3`, number = prereqLoc) is instantiated at the same position.
- Position of a node WITHOUT prerequisite: `localPosition = (L.myPosition.x, L.myPosition.y, 0.5)` [L39649-39675].
- The connector transform (`tempTransform2`) is parented to `mapGeo` and stored in the first null slot of `mapJunk` [L40945-40988] so it can be destroyed on the next refresh. Unlock rule therefore = "prereq level complete"; completed levels are shown with Checkbox (arena: Crown), still selectable (UNVERIFIED: selection logic is in mapInput).

#### 6.19.6 Keep (activeMenu == 8) [L41007-41090]
For i over `DB.reserves` (12 slots): if `reserves[i] == -1`: `keepIcons[i]` disabled and `keepLevels[i].text = ""`; else icon enabled with `partyDB[reserves[i]].icon` texture and `keepLevels[i].text = "Lv." + level`.

## 7. Formula quick reference

| Quantity | Formula | Source |
|---|---|---|
| Displayed Power, Cleric | `int((3.0*level + player.power)/5) + weaponPower + trinketPowerBonus` | L36936-36993 |
| Displayed Power, other classes | `int(player.power + weaponPower + trinketPowerBonus + powerScale*level)` (powerScale 1.0) | L37002-37064 |
| Displayed Armor | `int(player.defense + armorPower(if equipped) + trinketArmorBonus + defenseScale*level)` | L37065-37139 |
| trinketPowerBonus | sum of power of gear[2],gear[3] with item id 12..17 | L43388-43456 |
| trinketArmorBonus | sum of power of gear[2],gear[3] with item id 24..26 | L43459-43527 |
| Upgrade cost | `round(1.5 * itemDB[item.upgrade].sellPrice)` (Mathf.RoundToInt; UNVERIFIED: Unity rounds .5 to even) | L43198-43211 |
| Sell price shown | `sellPrice / 2` (integer div) | L43296 |
| Buy price shown | `sellPrice` | L43312-43330 |
| Recruit price shown | `level * 10` | L39023-39037 |
| Drag threshold | `Screen.width / 30` px | L33110-33116 |
| Save-slot time | `H:MM:SS` from `timePlayed` rounded | L34992-35082 |

## 8. Lookup tables

### 8.1 Class ids (from bh/data/classes.json; `characterClass = id+1`)
1 Cleric (powerScale 3.0, defenseScale 1.0), 2 Knight (1.0/1.2), 3 Rogue (1.0/1.0), 4 Wizard, 5 Witch, 6 Bard, 7 Barbarian, 8 Monk (1.0/1.2), 9 Ranger, 10 Paladin (1.0/1.2). Class-specific code seen in this scope: class 1 (power formula), class 2 and 10 (shield prop), class 7 (second weapon prop). NOTE: `updateWeapons` special-cases `characterClass == 7` which, by classes.json ordering (id 6 = Barbarian, so characterClass 7), is Barbarian, consistent with the dual-hatchet/dual-blade items.

### 8.2 Resources loaded by this code
`MapElements/ArrowRight, ArrowLeft, Crown, Checkbox, Skullface, Lock, darkStick0-3, lightStick0-3`; `Weapons/shield1, shield2, pallyShield`; item `ingameModel` and `icon` paths from items.json; power icons from `Power.icon`. Bones: `arm_l/weapon`, `arm_r/weapon2`, `shield`.

### 8.3 PlayerPrefs / DB keys used
PlayerPrefs: `cleansave`, `1saveExists`..`3saveExists`, `1PlayerName`..`3PlayerName`, `1timePlayed`..`3timePlayed`. DB: `freshBoot`, `tutorial`, `currentMap`, `whichLevel`, `transferLevel`, `level5reminder`, `party`, `partyDB`, `itemDB`, `powerDB`, `levelDB`, `inventory`, `merchant`, `reserves`, `gold`, `timePlayed`, `musicEnabled`, `soundEnabled`, `whichSaveSlot`, `save()`.

## 9. Uncertain / not determined

- `tutorialStrings` and `dialogStrings` text content is scene data, not in code. Their wording and the full list of who sets `whichTutorial` 14-16 (map tutorial) were not read (mapInput out of scope).
- UNVERIFIED: meaning of the greyout y-values (0, -0.97) and stick y-values (-0.56, 0): only literal constants are recorded; they position scene objects.
- UNVERIFIED: purpose of `PlayerPrefs "cleansave"` / `whichSaveSlot = 4` write in `Awake`.
- Fields with zero references in the whole class: `loadingText`, `portraitButtons3`, `hireButtonAnim` (0 refs anywhere) [grep]. Field meanings in section 2 for coroutine-only fields come from names, not logic (marked "coroutines only").
- UNVERIFIED: the gold counter animation (`displayGold`) - only the initial assignment is in scope.
- `Mathf.RoundToInt` on `.5` uses round-half-to-even in Unity; upgrade cost = 1.5*sellPrice can hit .5 (e.g. odd sellPrice) so verify rounding in the port.
- Hire price `level*10` is only the DISPLAYED text; actual charge must be checked in `$tavernInput$1545` (L53595+).
- Contradictions with older notes: none checked (no older notes read). One item to watch for ports: the Power formula for Cleric divides by 5 only the (scale*level + base power) part, weapon power and trinket bonus are NOT divided.

## 10. Cross-references

- Coroutine bodies: `$inventoryInput$1428` L43674, `$mainInput$1460` L48057, `$storeInput$1493` L49468, `$skillsInput$1531` L52238, `$tavernInput$1545` L53595, `$mapInput$1560` L54841, `$keepInput$1580` L56282, `$loadInput$1588` L57192, `$startNewGame$1615` L58701, `$loadExistingGame$1620` L58856.
- Classes used: `Database` (inventory/merchant/reserves/party/partyDB/itemDB/powerDB/levelDB/save), `Player` (characterClass, level, power, defense, gear[4], abilities[3], passives[4], recruited, available, playerName, description, icon), `Item` (itemType, power, upgrade, sellPrice, usableBy[10], icon, ingameModel, itemName), `powerCollection`, `Power`, `Map`, `Level` (prereq, prereqLoc, transition, transitionDirection, arena, complete, myPosition), `TextPrint`, `TitleAnimation`.
- Callers of the helpers (from grep): `UpdateInventory` called by all input coroutines after any change; `updateWeapons` after equipment change; `showUpgradeWindow` at L45959; `showVendorWindow` at L51580 and L51697; `updateEquipArrows` at L44372 and L47635; `unlockPlayableCharacters` at L48880.

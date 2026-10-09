# MenuBrain: Armory (inventoryInput), Town menu (mainInput), Merchant (storeInput)

**Class:** `MenuBrain` (out-of-battle "town" menu controller, a MonoBehaviour).
**Coroutines covered:** `$inventoryInput$1428` [IL L43674-48055], `$mainInput$1460` [IL L48057-49466], `$storeInput$1493` [IL L49468-52236].
**Also read (needed to resolve rules):** `showUpgradeWindow` [IL L43116-43227], `showVendorWindow` [IL L43230-43361], `updateEquipArrows` [IL L33732-34062], `clearDescriptionBox` [IL L42773-43113], `calculatePowerBonus/ArmorBonus` [IL L43388-43527], `Database.populateMerchant` [IL L2385-2542], `Database` constructor-side defaults via `bh/data/globals.json`.

All line citations are lines of `/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il`.

---------------------------------------------------------------------------------------------------

## 1. Summary (player view)

* The town has buildings. Tapping one (e.g. "armory", "merchant") plays a press animation, wipes the screen, scrolls the camera to that screen and starts that screen's input coroutine. `activeMenu` says which screen is live.
* **Armory** (activeMenu 1): shows 20 backpack slots + the selected hero's 4 gear slots (weapon, armor, trinket, trinket). You tap an item to see its name/description/stat and (if it has an upgrade) the upgrade price; you drag-and-drop to move items between backpack slots, equip, unequip and swap. Items can only be equipped on a hero whose class is allowed in the item's `usableBy`. Tapping a hero portrait switches which hero's gear is shown. An **Upgrade** button (anvil) appears when the selected item has an upgrade and you can afford it; it opens a confirm window and on OK replaces the item by its upgraded version for gold.
* **Merchant** (activeMenu 2): shows the 20 backpack slots and up to 8 shop slots. Tapping a shop item shows its price; if you have enough gold AND a free backpack slot a Buy button appears. Tapping a backpack item shows its sell price (half) with a Sell button. Both open a confirm window. Coloured arrows over hero portraits tell whether the item is stronger/weaker than what that hero wears, and a cover marks heroes who cannot use it.
* **Stock** is not chosen in these coroutines; `Database.populateMerchant` picks 3-8 random items from loot tables allowed by the highest recruited hero level (section 5). It is re-rolled after every battle victory and on new game / some loads.
* There is **no item-count limit besides the 20 backpack slots** and the 4 gear slots. Selling is done only from backpack slots (equipped items cannot be sold).

---------------------------------------------------------------------------------------------------

## 2. Fields used (class `MenuBrain`, declarations [IL L32873-33051])

| Field | Type | Meaning in this code | Default |
|---|---|---|---|
| `DB` | Database | global game data: `inventory[20]`, `merchant[8]`, `gold`, `party[4]`, `partyDB[]`, `itemDB[]` | set in Awake via `GameObject.Find("**DATABASE")` [IL L33117-33123] |
| `activeMenu` | int | current screen: 0 town, 1 armory, 2 merchant, 3 academy, 4 tavern, 5 battle/map, 6 load/title, 8 keep, 9 tutorial popup | - |
| `touchState` | int | per-screen input state machine (see 3.1) | 0 |
| `touchReleaseCheck` | int | 1 while a finger/mouse is down, 0 on the frame it is released | recomputed every frame [IL L43841-43902] |
| `totalTouches` | int | `Input.touchCount` clamped 0..5, forced to 1 by mouse emulation (`fakeTap`) | [IL L43845-43879] |
| `fakeTap` | bool | true when input came from the mouse | |
| `tapPosition`, `contactPosition` | Vector2 | current pointer position / position where the press began | |
| `draggingThreshold` | float | pixels the pointer must move to turn a press into a drag | ctor 20.0 [IL L33064-33065]; Awake sets `Screen.width / 30` [IL L33111-33116] |
| `pickedUpSlot` | int | slot index being dragged, -1 = none | ctor -1 [IL L33067-33068] |
| `whichSlotSelected` | int | slot last tapped. Armory: 0-19 backpack, 20 weapon, 21 armor, 22 trinket A, 23 trinket B. Merchant: 0-19 backpack, 20-27 shop slots | - |
| `whichSlotToDrop` | int | slot under the pointer on release | ctor -1 [IL L33070-33071] |
| `oldSlot` | int | slot the dragged icon flies back to | - |
| `tempValue` | int | scratch (swap temp / "found free slot" flag) | ctor -1 |
| `itemResetTimer` | float | >0 while the swapped-out item's icon animates back (0.35 s) | 0 |
| `avoidDoubleTap` | bool | true while a button animation/wipe is running; blocks all new input | false |
| `selectedPlayer` | int | index into `DB.partyDB` of the hero shown in the Armory | |
| `displayGold`, `goldText`/`goldText2` | float/TextMesh | animated gold counter (armory/merchant) | |
| `heldIcon`, `heldIconRenderer` | Transform/Renderer | icon following the pointer while dragging. Hidden by setting y = 5 | |
| `select`, `selectAnim` | Transform/Animation | selection cursor; hidden with y = 5 | |
| `sounds[]` | AudioSource[] | UI sounds, see 3.6 | |
| `upgradeWindow(+Anim, Text, Icon)`, `upgradeButton`, `upgradeButtonLight` | | Armory upgrade UI. Window is **open when its y == 0, closed when y == 7**; upgradeButton **visible at y = -2.55, hidden at y = 5** | |
| `vendorWindow(+Anim, Name, Price, Text, Text2, Icon)`, `vendorButton`, `vendorButtonLight`, `vendorButtonAnim` | | Merchant confirm UI. Window open y == 0 / closed y == 7; vendorButton visible y = -2.168425, hidden y = 5 | |
| `merchantArrows[8]` | Transform[] | [0..3] "better than equipped" arrow for party slot 0..3; [4..7] "worse than equipped" arrow. **Shown at y = 0, hidden at y = 5** | |
| `portraitCovers[4]` | Transform[] | "this hero cannot use it" cover. Shown y = 0, hidden by `clearDescriptionBox` | |
| `inventoryIcons[24]` | Renderer[] | Armory slot icons (BoxCollider 1.3 x 1.3 x 0.1 added in Awake, loop to 24 = 0x18) [IL L33319-33340] | |
| `inventoryIcons2[28]` | Renderer[] | Merchant slot icons (28 = 0x1c) [IL L33346-33367] | |
| `redSquares[]`, `equipArrows[4]` | | drag-time highlights (see 3.4) | |
| layer masks | LayerMask | `itemMask`, `partyMask`, `upgradeMask` (also used for the vendor button), `cancelMask`, `okayMask` (also used by town buildings), `exitMask` | set in editor; not decodable here |
| `wiperAnim` | Animation | full-screen wipe: clips "enter" / "exit" | |
| `cameraTransform` | Transform | camera; screen switch is done by setting its world x | |
| `merchantArrowsRoot` | Transform | parent of the arrows; x is set to the same value as the camera x for armory (0) and merchant (-40) | |

`Database` fields used: `inventory` (int[20], -1 = empty, from `bh/data/globals.json`), `merchant` (int[8], -1 = empty), `gold`, `party` (int[4] of partyDB indices, -1 = empty), `partyDB[i].gear` (int[4], -1 = empty; index 0 weapon, 1 armor, 2 and 3 trinkets), `partyDB[i].characterClass` (1-based class number), `itemDB[id]` with `itemName, description, itemType ("weapon"/"armor"/"trinket"), power, upgrade, sellPrice, usableBy[10], icon`.

**Class numbering:** `usableBy[characterClass - 1]` is the test used everywhere [IL L45674-45678 etc.]. Index = classes.json id: 0 Cleric, 1 Knight, 2 Rogue, 3 Wizard, 4 Witch, 5 Bard, 6 Barbarian, 7 Monk, 8 Ranger, 9 Paladin (`bh/data/classes.json`).

---------------------------------------------------------------------------------------------------

## 3. `$inventoryInput$1428` - the Armory [IL L43674-48055]

`MenuBrain.Update` [IL L33578-33716] **starts a brand-new coroutine every frame** according to `activeMenu` (0 -> `mainInput`, 1 -> `inventoryInput`, 2 -> `storeInput`, 3 -> `skillsInput`, 4 -> `tavernInput`, 5 -> `mapInput`, 6 -> `loadInput`, 7 -> `introSequence()`, 8 -> `keepInput`, 9 -> `tutorialInput()`) via `StartCoroutine_Auto` [IL L33590-33694]; it also fades `BGMusic` volume down by `deltaTime` while `audioFade` and adds `deltaTime` to `DB.timePlayed` [IL L33696-33714]. So each coroutine is effectively a one-frame handler; it only stays alive across frames when it hits a `yield WaitForSeconds` (button animation / wipe delays) - during those delays other per-frame instances keep running, which is why `avoidDoubleTap` exists. A pass ends with `YieldDefault(1)` [IL L48046-48047] (state 1 simply returns false). State table of the `switch` [IL L43831-43838]: 0 = start of a pass, 1 = end, 2 = after Cancel wait, 3 = after OK wait, 4 = after exit-button wait, 5 = after wipe wait, 6 = after ESC wipe wait.

### 3.1 Input prelude and `touchState` values

Each pass [IL L43841-43907]:
1. `touchReleaseCheck = 0`; `totalTouches = Clamp(touchCount, 0, 5)`; `fakeTap = false`.
2. Mouse emulation: if (`GetMouseButton(0)` and `totalTouches == 0`) or (`GetMouseButtonUp(0)` and `totalTouches == 0)`: `fakeTap = true`, `totalTouches = 1`, `theFingerId = 0`, `tapPosition = mousePosition`; `touchReleaseCheck = 0` if the button was released this frame, otherwise `1`.
3. If `totalTouches != 0`: for a real touch read `GetTouch(0)`, `touchReleaseCheck = 1`, `tapPosition = touch.position` [IL L43909-43931]. Then the big `touchState` dispatch. If `totalTouches == 0` skip to the tail (gold ticker / ESC).

`touchState` values in the Armory:

| value | meaning |
|---|---|
| 0 | idle: a new press is examined (section 3.2) |
| -1 | press consumed (empty slot / exit button / locked); returns to 0 when the finger is released [IL L47701-47707] |
| 1 | pressed an item with the finger still near the press point; becomes 2 after moving >= `draggingThreshold` |
| 2 | dragging an item (`heldIcon` follows pointer) |
| 5 | pressed the Upgrade button (waiting for release over it) |
| 10 | pressed a hero portrait (consumed; reset on release) |

### 3.2 `touchState == 0` : a new press [IL L43934-45535]

First, if `itemResetTimer > 0` (a swapped icon is still animating back) it is cancelled: timer = 0, `pickedUpSlot = -1`, `heldIcon.y = 5`, `UpdateInventory()` [IL L43939-43992]. Then `touchState = -1`, `contactPosition = tapPosition`, a ray is cast from the camera through `tapPosition` [IL L43995-44026]. Checks run in this order; the first that hits wins:

**(a) Item slot tapped** (`itemMask` hit, `upgradeWindow.y != 0` i.e. upgrade window closed, `!avoidDoubleTap`) [IL L44027-44046]:
1. `touchState = 1`; play `sounds[3]`; move `select` cursor to the hit icon and replay `selectAnim` [IL L44048-44086].
2. `whichSlotSelected` = index (0..23) of the matching `inventoryIcons` renderer [IL L44089-44118].
3. `whichItem` = `DB.inventory[slot]` if slot <= 19 else `partyDB[selectedPlayer].gear[slot - 20]` [IL L44122-44157].
4. `clearDescriptionBox()`. If `whichItem != -1` show: name, description; if weapon: `powerIcon` + `itemPowerText = ": " + power`; if armor: `defenseIcon` + same text [IL L44168-44255]. (Trinkets show no stat line in the Armory.)
5. If `item.upgrade != -1`: show `priceIcon` and `anvilIcon`, `priceText = ": " + RoundToInt(itemDB[item.upgrade].sellPrice * 1.5)` [IL L44263-44301]. **If `DB.gold >= that same cost`** the upgrade button is made visible (`upgradeButton.y = -2.55`) [IL L44304-44359]. Otherwise the cost is displayed but there is no button.
6. If `whichSlotSelected <= 19`: `updateEquipArrows(whichItem)` (section 3.5) [IL L44364-44372].
7. If `whichItem == -1` (empty slot): `touchState = -1` (cannot be dragged) [IL L44374-44381].

**(b) Hero portrait tapped** (`partyMask`, window closed, `!avoidDoubleTap`) [IL L44386-44418]: `touchState = 10`; `tempValue = -1`. If the hit transform equals `portraitButtons[k]` (k = 0..3) **and `DB.party[k] != -1`** then `selectedPlayer = DB.party[k]` and `tempValue = 0` [IL L44432-44558]. If `tempValue == 0`: play `sounds[3]`; replay `partySelectAnim`; move `partySelect` to the portrait; if `select.position.x < 0` set `select.y = 5` (hide cursor) [IL L44566-44600]; `clearDescriptionBox()`; `UpdateInventory()`; set every `characterSheetModels[i].y = 5` (hide) then the selected hero's model `y = -0.57`; `nameText = partyDB[selectedPlayer].playerName`; `updateWeapons()` [IL L44637-44762].

**(c) Upgrade button pressed** (`upgradeMask` hit, `upgradeButton.y != 5`, window closed, `!avoidDoubleTap`): `upgradeButtonLight` on, `touchState = 5` [IL L44767-44815].

**(d) Cancel button of the upgrade window** (`cancelMask`, `!avoidDoubleTap`) [IL L44820-44862]: `avoidDoubleTap = true`; `sounds[3]`; `upgradeWindowAnim.Play("cancel")`; `yield WaitForSeconds(0.2)` -> state 2: `avoidDoubleTap = false`; `upgradeWindow.y = 7` (closed). Nothing is changed or charged [IL L44863-44902].

**(e) OK button of the upgrade window** (`okayMask`, `!avoidDoubleTap`) [IL L44906-44944]: `avoidDoubleTap = true`; `sounds[4]`; `upgradeWindowAnim.Play("okay")`; `yield WaitForSeconds(0.2)` -> state 3: `avoidDoubleTap = false`; `upgradeWindow.y = 7` (closed) [IL L44949-44990], then **the upgrade is performed** (section 3.3).

**(f) Exit / back button** (`exitMask`, `!avoidDoubleTap`, **upgrade window closed**) [IL L45395-45422]: `touchState = -1`; replay the hit object's own `Animation`; `avoidDoubleTap = true`; `sounds[3]`; wait 0.06 s (state 4) [IL L45426-45469] -> `wiperAnim.Play("enter")`; wait 0.22 s (state 5) [IL L45473-45482] -> `avoidDoubleTap = false`; `activeMenu = 0`; `cameraTransform.x = -20`; `wiperAnim.Play("exit")` [IL L45486-45533]. (Camera x -20 is the town screen.)

### 3.3 The Upgrade (OK confirmed) [IL L44990-45391]

Let `S = whichSlotSelected`, `it = item currently in S`, `target = it.upgrade`.

```
cost = RoundToInt( itemDB[ it.upgrade ].sellPrice * 1.5 )      // IL 45017-45024, 45097-45105
if S < 20:   // backpack
    DB.gold -= cost                                            // IL 44996-45026
    DB.inventory[S] = itemDB[ inventory[S] ].upgrade           // IL 45029-45048
    tempValue = DB.inventory[S]                                // the NEW id
else if S >= 20:  // equipped gear (S-20 = gear index)
    DB.gold -= cost                                            // IL 45070-45107
    gear[S-20] = itemDB[ gear[S-20] ].upgrade                  // IL 45110-45143
    tempValue = gear[S-20]
if S == 20: updateWeapons()                                    // IL 45164-45170, refresh in-hand weapon model
UpdateInventory(); selectAnim Stop+Play; clearDescriptionBox() // IL 45173-45185
re-display the new item (name, description, power/armor icon + number)   // IL 45188-45281
if newItem.upgrade != -1: show priceIcon/anvilIcon, priceText = ": " + RoundToInt(itemDB[newItem.upgrade].sellPrice*1.5)
        and show upgradeButton (y=-2.55) only if DB.gold >= that cost   // IL 45284-45391
```

Key facts:
* **The `upgrade` field is the id of the next item in the chain** (-1 = cannot be upgraded). The upgrade replaces the item id; there is no level/plus counter.
* **Upgrade cost = 1.5 x the `sellPrice` of the TARGET item**, rounded with `Mathf.RoundToInt` (round-half-to-even in .NET/Mono; UNVERIFIED for the Unity build but this is the documented behaviour of `Mathf.RoundToInt`). The same expression is used for the display text [IL L44283-44300], the can-afford test [IL L44304-44324] and the charge [IL L45003-45026], and `showUpgradeWindow` [IL L43197-43212].
* The gold check happens only when the button is shown (selection time); the OK handler does not re-check gold (gold could in principle go negative only if the state was changed in between; UNVERIFIED not reachable).
* Both backpack items and equipped items can be upgraded. Upgrading an equipped item keeps it equipped.
* There is no check of `usableBy` when upgrading (chains stay within one class family in the data).
* Full per-item list with computed costs is in section 7.

`showUpgradeWindow()` [IL L43116-43227] (called when the upgrade button is released): sets `upgradeWindow.y = 0` (open), plays "enter", resolves the item (backpack or gear), sets `upgradeWindowText = gold + "\n" + RoundToInt(itemDB[item.upgrade].sellPrice*1.5)` and `upgradeWindowIcon` texture = `Resources.Load(itemDB[item].icon)` (icon of the CURRENT item, not the upgraded one).

### 3.4 Dragging [IL L45539-45898]

* `touchState == 1`: if `Distance(tapPosition, contactPosition) >= draggingThreshold` -> `touchState = 2`; `sounds[1]` (pick-up); `pickedUpSlot = whichSlotSelected`; `UpdateInventory()`; `heldIconRenderer` texture = source icon texture; `heldIcon` placed at source icon [IL L45541-45609]. (A tap that never moves is only a selection.)
* `touchState == 2` each frame: `heldIcon.position = Lerp(heldIcon.position, ScreenToWorldPoint(tapPosition) + (0,0,7), deltaTime * 13)` [IL L45616-45645].
  * If `pickedUpSlot < 20` (dragging a backpack item): if `usableBy[class-1]` is **false** for the selected hero: `redSquares[pickedUpSlot].position = heldIcon.position` and all four `equipArrows[0..3]` disabled [IL L45648-45721]. Otherwise enable the "drop here" arrows: weapon -> `equipArrows[0]`; armor -> `equipArrows[1]`; trinket -> `equipArrows[2]` and `[3]` [IL L45725-45808]. (These are highlight sprites for the matching gear slots; assumption on their on-screen meaning: UNVERIFIED.)
  * Hover: raycast `itemMask` at the pointer; if it hits a different icon move `select` there, else `select.y = 5` [IL L45813-45898].

### 3.5 `updateEquipArrows(whichItem)` [IL L33732-34062] (also the same logic is inlined in the Merchant, 4.3)

Called only for backpack selections. First hides nothing itself (the preceding `clearDescriptionBox` already hid all arrows). For party slot `i` = 0..3 with `DB.party[i] != -1`:
1. If `itemDB[whichItem].usableBy[ partyDB[party[i]].characterClass - 1 ]` is false -> skip this hero (no arrow) [IL L33764-33788].
2. "Better" arrow `merchantArrows[i]` shown (y = 0) if:
   * item is armor AND hero's `gear[1] == -1` (no armor worn) [IL L33796-33845]; or
   * item is weapon AND `item.power > itemDB[gear[0]].power` [IL L33853-33880]; or
   * item is armor AND `item.power > itemDB[gear[1]].power` [IL L33888-33915].
3. Else "worse" arrow `merchantArrows[i + 4]` shown if item is weapon AND `item.power < itemDB[gear[0]].power`, or item is armor AND `item.power < itemDB[gear[1]].power` [IL L33955-34050].
4. Equal power: no arrow. Trinkets: never any arrow. Only equal-or-better type-matching comparison: a weapon is compared with the weapon slot, an armor with the armor slot.

### 3.6 Release (drop) rules [IL L45902-47697]

On the frame the finger lifts (`touchReleaseCheck == 0`):

* If `touchState == 5` (Upgrade button held): `upgradeButtonLight` off; `touchState = 0`; re-raycast `upgradeMask` at `tapPosition`; if it hits the button (y != 5) -> `showUpgradeWindow()` [IL L45902-45960].
* If `touchState == 2` (drop): `validMove = false`; raycast `itemMask` at `tapPosition`; find `whichSlotToDrop` = icon index 0..23 [IL L45964-46048]. If the ray hit nothing the move is invalid (jump to the invalid path [IL L46000]). Let **P = pickedUpSlot**, **D = whichSlotToDrop**, `c = partyDB[selectedPlayer].characterClass - 1`. Rules, in the order the code tests them:

| # | Condition | Extra requirement | Effect | IL |
|---|---|---|---|---|
| 1 | D < 20 and P < 20 | none | `inventory[D] <-> inventory[P]` swap (an empty destination just receives the item). `sounds[0]`. If `inventory[D] != -1` before the swap: `heldIcon` gets D's texture and `itemResetTimer = 0.35` (the displaced icon animates back to P) | 46052-46162 |
| 2 | D == 20 (weapon slot), P < 20 | `itemType(inventory[P]) == "weapon"` AND `usableBy[c]` | `gear[0] <-> inventory[P]` swap. `sounds[2]`. If a weapon was equipped: displaced-icon animation, `itemResetTimer = 0.35`. `UpdateInventory(); updateWeapons()` | 46166-46348 |
| 3 | D == 21 (armor slot), P < 20 | `itemType == "armor"` AND `usableBy[c]` | `gear[1] <-> inventory[P]` swap (armor slot may be empty -1 -> item just moves). `sounds[2]`. `updateWeapons()` | 46352-46534 |
| 4 | D < 20, P == 20 (drag equipped weapon to backpack) | destination slot **must be non-empty** and hold a weapon usable by this hero; if `inventory[D] == -1` -> **invalid** (weapon can never be removed, only swapped) | `gear[0] <-> inventory[D]`; `sounds[2]` | 46538-46713 |
| 5 | D < 20, P == 21 (equipped armor to backpack) | if `inventory[D] != -1`: must be armor usable by this hero (swap). If `inventory[D] == -1`: allowed - armor is **unequipped** (`inventory[D] = gear[1]`, `gear[1] = -1`, `sounds[0]`) | 46717-46980 |
| 6 | D >= 22 (trinket slot), P < 20 | `itemType == "trinket"` AND `usableBy[c]` | `gear[D-20] <-> inventory[P]` swap (empty trinket slot -> item moves). `sounds[2]` | 46984-47163 |
| 7 | D < 20, P >= 22 (equipped trinket to backpack) | if `inventory[D] != -1`: must be a trinket usable by this hero (swap, `sounds[2]`). If `inventory[D] == -1`: trinket unequipped (`inventory[D] = gear[P-20]`, `gear[P-20] = -1`, `sounds[0]`) | 47167-47424 |
| 8 | D >= 22 and P >= 22 | none | swap `gear[D-20] <-> gear[P-20]` (between the two trinket slots; D == P is a no-op swap). `sounds[2]` | 47428-47572 |
| - | anything else (e.g. weapon slot to armor slot, gear slot 20/21 -> 22/23, trinket onto weapon slot, wrong item type, class not allowed, empty source) | | invalid | - |

After a **valid** move: `UpdateInventory()`, `selectAnim` replay, `oldSlot = old whichSlotSelected`, `whichSlotSelected = D`.
After an **invalid** move [IL L47574-47614]: `sounds[0]`; `itemResetTimer = 0.35`; `select` cursor goes back to the original icon; `oldSlot = whichSlotSelected` (original), so the dragged icon flies back to its origin.
Then in both cases [IL L47617-47697]: `touchState = 0`; if `whichSlotSelected <= 19`: `updateEquipArrows(inventory[whichSlotSelected])`, else all 8 `merchantArrows` y = 5 (hidden).

Notes:
* Items in the backpack are never destroyed, discarded or sold by the Armory; dropping outside any slot is an invalid move and the item returns.
* The displaced item always goes into the dragged item's origin slot (that is what the swap means). There is no auto-find-free-slot.
* **The equip check is `usableBy` of the *currently selected hero*** (`selectedPlayer`). There is no level requirement and no weapon-type/class check other than `usableBy`.
* `whichSlotToDrop` is not reset to -1 before the search loop [IL L46018-46048]; stale value only matters if the ray hits a collider on `itemMask` that is not one of the 24 icons (UNVERIFIED if any exist).

### 3.7 Icon return animation and tail [IL L47710-48047]

* If `touchReleaseCheck != 0` and `touchState` is not 2... precisely: when the finger is up and `touchState` was not 5/2, `touchState = 0` [IL L47701-47707].
* If `itemResetTimer > 0`: `heldIcon.position = Lerp(heldIcon.position, inventoryIcons[oldSlot].position, deltaTime * 20)`; if `whichSlotSelected < 20 and oldSlot < 20` and the item at `oldSlot` is NOT usable by the hero, `redSquares[pickedUpSlot]` is moved to `heldIcon` [IL L47713-47797]; `itemResetTimer -= deltaTime` [IL L47802-47805].
* Else if `itemResetTimer <= 0` and `heldIcon.y != 5` and `touchState != 2`: `pickedUpSlot = -1`; `heldIcon.y = 5`; `UpdateInventory()` [IL L47810-47875].
* Gold ticker: `displayGold` moves toward `DB.gold` at **100 per second** (`+= deltaTime*100`, clamped so it does not overshoot, either direction) and `goldText = RoundToInt(displayGold).ToString()` [IL L47878-47966].
* **ESC key** (`KeyCode 0x1b`): `avoidDoubleTap = true`; `sounds[3]`; wipe "enter"; wait 0.22 s (state 6) -> `avoidDoubleTap = false`, `activeMenu = 0`, camera x = -20, wipe "exit" [IL L47967-48043]. Works even if the upgrade window is open.
* `YieldDefault(1)` ends the pass [IL L48046].

### 3.8 Sound slot usage (names not in the IL; `sounds[]` assigned in the editor)

| index | used for |
|---|---|
| 0 | item dropped into backpack slot / unequip into empty slot / invalid-drop thud |
| 1 | item picked up (drag start) |
| 2 | equip (any move that puts an item into a gear slot, or swaps within gear) |
| 3 | generic UI click: select item, select portrait, Cancel, exit/ESC |
| 4 | OK / confirm (upgrade OK, buy/sell OK) |

---------------------------------------------------------------------------------------------------

## 4. `$storeInput$1493` - the Merchant [IL L49468-52236]

Same per-frame structure and prelude as the Armory [IL L49650-49743]. State table [IL L49640-49647]: 0 start, 1 end, 2 after exit-button 0.06 s, 3 after wipe 0.22 s, 4 after vendor-Cancel 0.2 s, 5 after vendor-OK 0.2 s, 6 after ESC 0.22 s.

Slots: `inventoryIcons2[0..27]` (28 icons): 0-19 = backpack (`DB.inventory`), 20-27 = shop (`DB.merchant[slot-20]`). The merchant screen has no gear slots: **equipped items cannot be sold**.

`touchState`: 0 idle, -1 consumed, 1 pressed backpack item (draggable), 2 dragging, 5 pressed Buy/Sell button.

### 4.1 Pricing (the core rules)

| Quantity | Formula | IL |
|---|---|---|
| **Buy price** of a shop item | `itemDB[id].sellPrice` (the full value of the field `sellPrice`) | display 50172-50189, window 43324-43330, charge 51259-51282 |
| **Sell value** of a backpack item | `itemDB[id].sellPrice / 2` with **integer division** (floor for positive numbers) | display 50111-50125, window 43291-43301, payout 51172-51194 |
| Armory upgrade price | `RoundToInt(itemDB[item.upgrade].sellPrice * 1.5)` | see 3.3 |

So the field named `sellPrice` is really the item's base value: shops sell at 1.0x, buy back at 0.5x (floor), and upgrades cost 1.5x the base value of the *next* item. No other multiplier, discount, tax or stat dependence exists in this code. Because of the floor, sell values of odd-priced items lose 0.5 (e.g. 75 -> 37).

### 4.2 `touchState == 0` : new press on an item [IL L49743-50795]

Pre-step: pending icon animation is cancelled as in the Armory (timer = 0, `pickedUpSlot = -1`, `heldIcon.y = 5`, `UpdateInventory`) [IL L49748-49801]. `touchState = -1`; `contactPosition = tapPosition` [IL L49804-49811]. Ray `itemMask`; hit AND `!avoidDoubleTap` AND `vendorWindow.y != 0` (confirm window closed) [IL L49836-49852]:
1. `sounds[3]`; `select` moves to the icon, replay `selectAnim` [IL L49856-49890].
2. `whichSlotSelected` = matching index in `inventoryIcons2` (0..27) [IL L49894-49923].
3. `whichItem` = `inventory[slot]` (and `touchState = 1`, so backpack items may be dragged) when slot <= 19; else `merchant[slot-20]` (touchState stays -1: **shop items cannot be dragged**) [IL L49927-49961].
4. `clearDescriptionBox()` (menu 2 branch hides the vendor button and all arrows/covers; sets `costLocation.localX = 0.4446212`) [IL L42915-43079].
5. If `whichItem != -1`: show name (`itemNameText2`), description, and for weapon `powerIcon2` + ": " + power; for armor `defenseIcon2` + ": " + power; for trinket nothing and `costLocation.localPosition.x = 1.4911379814` (layout only) [IL L49966-50096].
6. Price/button:
   * **Backpack slot (<= 19)**: `priceIcon2` on, `priceText2 = ": " + sellPrice/2`; `vendorButton.y = -2.1684251` and `vendorButtonAnim.Play("sell")`. The Sell button is always offered for a non-empty backpack item [IL L50100-50168].
   * **Shop slot**: `priceIcon2` on, `priceText2 = ": " + sellPrice`; scan backpack: `tempValue = 1` if any `inventory[i] == -1` (i = 0..19) else 0 [IL L50172-50226]. The Buy button (`vendorButton.y = -2.1684251`, anim "buy") is shown **only if `DB.gold >= sellPrice` AND `tempValue == 1`** [IL L50230-50288]. If you cannot afford it, or the backpack is full, the price is shown but there is no button (no error message).
7. Hero hints (for both backpack and shop selections): hide all 8 `merchantArrows` (y = 5) [IL L50291-50347]; for each party slot i = 0..3 with `DB.party[i] != -1` [IL L50351-50362]:
   * if `!usableBy[class-1]` for that hero: `portraitCovers[i].y = 0` (cover shown) and nothing else [IL L50365-50434];
   * else "better" arrow `merchantArrows[i]` (y = 0) if (armor and hero `gear[1] == -1`) or (weapon and `item.power > itemDB[gear[0]].power`) or (armor and `item.power > itemDB[gear[1]].power`) [IL L50438-50640]; else "worse" arrow `merchantArrows[i+4]` if (weapon and `power < gear[0].power`) or (armor and `power < gear[1].power`) [IL L50644-50773]. Trinkets: no arrows (cover only).
8. If `whichItem == -1`: `touchState = -1` [IL L50787-50794].

### 4.3 Other buttons on press [IL L50799-51121]

* **Exit/back** (`exitMask`, `!avoidDoubleTap`, vendor window closed): `touchState = -1`; replay hit object's Animation; `avoidDoubleTap = true`; `sounds[3]`; wait 0.06 (state 2) -> wipe "enter", wait 0.22 (state 3) -> `avoidDoubleTap = false`; `activeMenu = 0`; `camera.x = -20`; wipe "exit" [IL L50810-50939].
* **Buy/Sell button** (`upgradeMask` hit, `!avoidDoubleTap`, vendor window closed, `vendorButton.y != 5`): `vendorButtonLight` on; `touchState = 5` [IL L50943-50992]. On release over it (`upgradeMask` hit) -> `showVendorWindow()`; `touchState = 0` [IL L51534-51580].
* **Window Cancel** (`cancelMask`, `!avoidDoubleTap`): `avoidDoubleTap = true`, `sounds[3]`, `vendorWindowAnim.Play("cancel")`, wait 0.2 (state 4) -> `avoidDoubleTap = false`, `vendorWindow.y = 7` [IL L50996-51078]. No change.
* **Window OK** (`okayMask`, `!avoidDoubleTap`): `avoidDoubleTap = true`, `sounds[4]`, `vendorWindowAnim.Play("okay")`, wait 0.2 (state 5) -> `avoidDoubleTap = false`, `vendorWindow.y = 7`, then the transaction (4.4) [IL L51082-51162].

`showVendorWindow()` [IL L43230-43361]: window open (y = 0), "enter" anim; if `whichSlotSelected <= 19`: `vendorWindowPrice = sellPrice/2`, texts "Sell this item?" / "Sell price:"; else shop item: `vendorWindowPrice = sellPrice`, texts "Buy this item?" / "Purchase cost:"; `vendorWindowName = itemName` and `vendorWindowIcon` = `Resources.Load(item.icon)`. (For the sell case the name/icon block is skipped: the branch jumps to IL_0109 [IL L43310], so name/icon are not refreshed for sells - UNVERIFIED visual leftovers.)

### 4.4 Transaction on OK [IL L51166-51303]

```
S = whichSlotSelected
if S <= 19:                                     // SELL
    DB.gold += itemDB[ inventory[S] ].sellPrice / 2       // integer division     IL 51172-51194
    DB.inventory[S] = -1                                   // IL 51197-51203
    UpdateInventory(); clearDescriptionBox()               // IL 51206-51209
else:                                           // BUY
    for i in 0..19:                                       // IL 51213-51256
        if DB.inventory[i] == -1:
            DB.inventory[i] = DB.merchant[S-20]
            break                                          // sets i = 20
    DB.gold -= itemDB[ merchant[S-20] ].sellPrice          // IL 51260-51282
    DB.merchant[S-20] = -1                                 // item removed from shop (no restock)  IL 51285-51293
    UpdateInventory(); clearDescriptionBox()               // IL 51296-51299
```
* Bought item goes to the **first empty backpack slot (lowest index)**.
* Gold/free-slot were only validated when the Buy button was shown; the OK handler does not re-check (gold is subtracted even if no free slot were found; UNVERIFIED unreachable in practice).
* Shop stock is single-quantity: a bought slot becomes -1 (empty) and stays empty until `populateMerchant` runs again.
* Selling gives no confirmation beyond the window; sold items vanish (they do not appear in the shop).

### 4.5 Drag in the Merchant [IL L51304-51931]

* Press -> drag identical to the Armory (touchState 1 -> 2 at `draggingThreshold`; `sounds[1]`; `pickedUpSlot`; held icon lerp `deltaTime*13` to pointer + (0,0,7)) [IL L51304-51410]; hover moves `select` over backpack icons only (loop `i < 20`; shop icons ignored for hover) [IL L51415-51530].
* Release with `touchState == 2` [IL L51585-51931]:
  1. Ray on `partyMask` hits something (the layer is named for the hero portraits; what exactly it covers on this screen is UNVERIFIED): `validMove = true`; `select` returns to the source icon; `itemResetTimer = 0`; `pickedUpSlot = -1`; `heldIcon.y = 5`; `UpdateInventory()`; **`showVendorWindow()`** -> this behaves as "drag item onto the target = open the Sell confirm" for the dragged backpack item (`whichSlotSelected` is still the source) [IL L51621-51697].
  2. Else ray on `itemMask`: find `whichSlotToDrop` (initialised to 100, search icons 0..19 only) [IL L51702-51765]. If `D < 20` and `P < 20`: **swap backpack slots** `inventory[D] <-> inventory[P]` with `sounds[0]`, and the displaced-icon animation (`itemResetTimer = 0.35`) if D was occupied [IL L51769-51877]. (Backpack can be re-ordered in the shop.)
  3. Otherwise invalid: `sounds[0]`, `itemResetTimer = 0.35`, cursor returns [IL L51880-51931].
  Then `touchState = 0`.
* Icon return animation, gold ticker (100/s) and ESC (-> same exit as the Exit button, wait 0.22 state 6) are identical to the Armory [IL L51935-52224]; gold text is `goldText2`.

---------------------------------------------------------------------------------------------------

## 5. Merchant stock: `Database.populateMerchant` [IL L2385-2542]

Not inside the three coroutines but it is what fills `DB.merchant`.

```
for i in 0 .. merchant.length-1: merchant[i] = -1                       // IL 2398-2417  (length 8, bh/data/globals.json)
maxLevel = 0
for each p in partyDB: if p.recruited and p.level > maxLevel: maxLevel = p.level   // IL 2421-2455
         // NOTE: all recruited heroes, not only the 4 in the active party
eligible = [ t for t in lootTables if t.minLevel <= maxLevel <= t.maxLevel ]        // IL 2456-2491
count = Random.Range(3, 9)          // integer overload: 3..8 inclusive                // IL 2493-2496
for i in 0 .. count-1:
    t = eligible[ Random.Range(0, eligible.length) ]      // table chosen uniformly    // IL 2503-2512
    merchant[i] = t.tableContents[ Random.Range(0, t.tableContents.length) ]   // uniform over the list (duplicates in a list weight it; duplicates across slots possible)  // IL 2513-2532
```
* Slots `count..7` stay -1 (empty). Items are packed from slot 0.
* No price, rarity or stock-count logic.

Loot tables (from `bh/data/loot_tables.json`; contents are item ids, see section 7):

| id | name | minLevel | maxLevel | #ids |
|---|---|---|---|---|
| 0 | Tier 1 Gear | 0 | 4 | 12 |
| 1 | Tier 2 Gear + 1.0 trinkets | 2 | 11 | 17 |
| 2 | Tier 3 Gear + 1.0 & 1.5 trinkets | 8 | 16 | 22 |
| 3 | Tier 4 Gear + 1.5 and 2.0 trinks | 14 | 21 | 25 |
| 4 | Tier 5 Gear + 2.0 & 2.5 trinkets | 18 | 27 | 26 |
| 5 | Tier 6 Gear + 2.5 & 3.0 trinkets | 24 | 34 | 23 |
| 6 | Tier 7 Gear + 3.0 & 3.5 trinkets | 28 | 999 | 24 |
| 7 | Tier 8 Gear + 3.5 trinkets | 0 | 0 | 19 |
| 8 | Tier 9 Gear | 0 | 0 | 12 |

Eligible tables by highest recruited level L: L=0 -> {0,7,8}; L=1 -> {0}; L 2-4 -> {0,1}; L 5-7 -> {1}; L 8-11 -> {1,2}; L 12-13 -> {2}; L 14-16 -> {2,3}; L 17 -> {3}; L 18-21 -> {3,4}; L 22-23 -> {4}; L 24-27 -> {4,5}; L 28-34 -> {5,6}; L >= 35 -> {6}. (Computed from the min/max ranges above; tables 7 and 8 have min=max=0 and are only eligible at level 0, which with the default party (levels start at 1, `bh/data/party.json`) never occurs unless no hero is recruited.)

**When it runs** (callers of `populateMerchant`):

| Where | When | IL |
|---|---|---|
| `MenuBrain.$startNewGame$1615` | new game start (after `freshBoot = false`) | 58786 |
| `MenuBrain.$loadExistingGame$1620` | after `DB.load()`, **only if `saveWeJustQuit != DB.whichSaveSlot`** (loading a different slot than the one just left) | 58947-58960 |
| `MotherBrain.$defeatSequence$1730` | after a battle victory, both in normal and in `arenaMode` paths | 75819, 75904 |
| `MotherBrain.$XPBarAnimation$1712` | in the `noAnimation` path | 75475 |

The shop contents are **not** read from or written to the save file by `Database.save/load` (no `Database::merchant` reference in L1001-2337 per grep); UNVERIFIED beyond the grep. Going into and out of the merchant screen never re-rolls stock.

---------------------------------------------------------------------------------------------------

## 6. `$mainInput$1460` - the town screen [IL L48057-49466]

Per-frame prelude identical to the Armory [IL L48222-48283]. Only `touchState` 0 / -1 are used: on the press frame the coroutine acts, then `touchState = 0` again once the finger is up [IL L49285-49291].

Press handling [IL L48312-48405]: when `touchState == 0` -> `touchState = -1`; raycast `okayMask`; if hit and `!avoidDoubleTap`: `tempTransform` = hit object. If its `name != "home"` replay its `Animation` (Stop, Play) [IL L48366-48388]. `avoidDoubleTap = true`; `sounds[3]`; wait 0.06 s (state 2) [IL L48392-48405] -> `wiperAnim.Play("enter")`; wait 0.22 s (state 3) [IL L48409-48417] -> `avoidDoubleTap = false` and branch on the object's **name** [IL L48422-49281]:

| Object name | `activeMenu` | Camera world x | Other effects | IL |
|---|---|---|---|---|
| "armory" | 1 | 0 | `merchantArrowsRoot.x = 0`; `resetMenus()`; if `DB.armoryFirstVisit == 1`: set it 0, `activeMenu = 9`, `whichTutorial = 4`, tutorial text y = 0.7, text = `tutorialStrings[4]`, show `tutorialTextBG` | 48428-48583 |
| "merchant" | 2 | -40 | `merchantArrowsRoot.x = -40`; `resetMenus()`; `merchantFirstVisit` -> tutorial 8 | 48589-48744 |
| "academy" | 3 | -60 | `resetMenus()`; `academyFirstVisit` -> tutorial 2 | 48750-48868 |
| "tavern" | 4 | -80 | `unlockPlayableCharacters()` first; `resetMenus()`; no first-visit tutorial | 48874-48925 |
| "battle" | 5 | 20 | `battleButton.y = 8`; `resetMenus()` | 48931-49016 |
| "keep" | 8 | -100 | `resetMenus()`; `keepFirstVisit` -> tutorial 11 | 49022-49140 |
| "home" | 6 | 40 | `currentMap = 0`; `saveWeJustQuit = DB.whichSaveSlot`; `DB.save()`; `DB.whichSaveSlot = 4`; `DB.load()`; `DB.whichSaveSlot = 0`; `DB.freshBoot = true`; `updateLoadScreen()`; fade-out renderer off, `idleTime = 0.1`, 3 save-slot renderers coloured (0.25,0.25,0.25); wipe "exit" | 49146-49281 |

Common to all: after the branch the wipe "exit" is played (label IL_0c83 [IL L49279-49281]). First-visit tutorials set `activeMenu = 9` after the other `activeMenu` assignment, so the popup takes over; all four first-visit flags start at 1 (`bh/data/globals.json`: academyFirstVisit, merchantFirstVisit, armoryFirstVisit, keepFirstVisit).
**ESC** (`KeyCode 0x1b`) on the town screen [IL L49292-49317]: `avoidDoubleTap = true`; `sounds[3]`; wipe "enter"; wait 0.22 (state 4) -> same as "home": `activeMenu = 6`, `currentMap = 0`, camera x = 40, save, temp slot 4 load, back to the load screen [IL L49321-49454].
Town camera x (for the return from armory / merchant) is -20 [IL L45493-45521, L50897-50921].

---------------------------------------------------------------------------------------------------

## 7. Item reference (from `bh/data/items.json`, 132 items; columns computed by the rules above)

* `buy` = `sellPrice` (price in the shop).  `sell` = `sellPrice // 2`.
* `upgrade cost` = `round_half_even(1.5 * sellPrice of upgrade target)`.
* `usableBy`: classes allowed (ALL = all 10).
* Equipment slot by type: weapon -> gear[0]; armor -> gear[1]; trinket -> gear[2] or gear[3].
* Trinket power values act as bonuses to the displayed Power/Armor via `calculatePowerBonus` (sum of `power` of gear[2..3] whose item id is in **12..17**) and `calculateArmorBonus` (item id in **24..26**) [IL L43388-43527]; other trinkets have special effects implemented elsewhere (not in this scope).

| id | name | type | power | buy | sell | upgrade -> id (name) | upgrade cost | usableBy |
|---|---|---|---|---|---|---|---|---|
| 0 | Iron Sword | weapon | 15 | 20 | 10 | 9 (Rusty Carver) | 54 | Knight,Paladin |
| 1 | Iron Dagger | weapon | 19 | 24 | 12 | 49 (Silver Dagger) | 60 | Rogue |
| 2 | Cleric's Rod | weapon | 20 | 18 | 9 | 87 (Crystal Rod) | 52 | Cleric |
| 3 | Oakwood Staff | weapon | 23 | 26 | 13 | 95 (Vined Heartwood Staff) | 75 | Wizard,Witch |
| 4 | Scale Mail | armor | 20 | 30 | 15 | 103 (Plate Mail) | 105 | Knight,Paladin |
| 5 | Soft Leather Garb | armor | 12 | 25 | 12 | 113 (Studded Leather) | 98 | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 6 | Cotton Cloak | armor | 8 | 15 | 7 | 108 (Elven Cloak) | 60 | ALL |
| 7 | Tome of Mastery | trinket | 3 | 150 | 75 | - | - | ALL |
| 8 | Ring of Regeneration | trinket | 10 | 60 | 30 | - | - | ALL |
| 9 | Rusty Carver | weapon | 18 | 36 | 18 | 10 (Longsword) | 90 | Knight,Paladin |
| 10 | Longsword | weapon | 21 | 60 | 30 | 57 (Silver Greatsword) | 120 | Knight,Paladin |
| 11 | Dual Hatchets | weapon | 20 | 25 | 12 | 79 (Dual Scimitars) | 63 | Barbarian |
| 12 | Swordsman's Gauntlet | trinket | 3 | 75 | 37 | - | - | Knight,Rogue,Barbarian,Monk,Ranger,Paladin |
| 13 | Power Fist | trinket | 6 | 140 | 70 | - | - | Knight,Rogue,Barbarian,Monk,Ranger,Paladin |
| 14 | Titan's Glove | trinket | 10 | 220 | 110 | - | - | Knight,Rogue,Barbarian,Monk,Ranger,Paladin |
| 15 | Energy Ring | trinket | 3 | 75 | 37 | - | - | Cleric,Wizard,Witch |
| 16 | Firestorm Band | trinket | 6 | 140 | 70 | - | - | Cleric,Wizard,Witch |
| 17 | Kaimani's Bloodstone | trinket | 10 | 220 | 110 | - | - | Cleric,Wizard,Witch |
| 18 | Sprint Shoes | trinket | 10 | 100 | 50 | - | - | ALL |
| 19 | Trollskin Amulet | trinket | 20 | 150 | 75 | - | - | ALL |
| 20 | Warding Amulet | trinket | 10 | 150 | 75 | - | - | ALL |
| 21 | Phasing Lodestone | trinket | 20 | 240 | 120 | - | - | ALL |
| 22 | Ancient Dragon Tooth | trinket | 15 | 300 | 150 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 23 | Truestrike Monocle | trinket | 10 | 200 | 100 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 24 | Silver Armlet | trinket | 3 | 50 | 25 | - | - | ALL |
| 25 | Glyph of Stoneskin | trinket | 6 | 120 | 60 | - | - | ALL |
| 26 | Sharkul's Skull | trinket | 10 | 200 | 100 | - | - | ALL |
| 27 | Hermes Charm | trinket | 20 | 180 | 90 | - | - | ALL |
| 28 | Rabbit's Foot | trinket | 5 | 100 | 50 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 29 | Ring of Haste | trinket | 5 | 100 | 50 | - | - | Cleric,Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 30 | Tempest Stone | trinket | 10 | 200 | 100 | - | - | Cleric,Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 31 | Ninja Glove | trinket | 15 | 300 | 150 | - | - | Cleric,Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 32 | Codex of Jabe | trinket | 6 | 300 | 150 | - | - | ALL |
| 33 | Broken Pocketwatch | trinket | 5 | 70 | 35 | - | - | ALL |
| 34 | Monkey's Paw | trinket | 10 | 150 | 75 | - | - | ALL |
| 35 | Azamoth's Cursed Eyeball | trinket | 15 | 250 | 125 | - | - | ALL |
| 36 | Glove of the Thief | trinket | 10 | 60 | 30 | - | - | ALL |
| 37 | Bandit's Satchel | trinket | 20 | 150 | 75 | - | - | ALL |
| 38 | Mystic Journal | trinket | 10 | 175 | 87 | - | - | ALL |
| 39 | Mystery Egg | trinket | 20 | 340 | 170 | - | - | ALL |
| 40 | Blood-soaked Sash | trinket | 10 | 100 | 50 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 41 | Vampire Tooth Pendant | trinket | 20 | 220 | 110 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 42 | Choker of the Red Feast | trinket | 30 | 340 | 170 | - | - | Knight,Rogue,Wizard,Witch,Barbarian,Monk,Ranger,Paladin |
| 43 | Pugilist's Tape | weapon | 16 | 22 | 11 | 63 (Cestus) | 56 | Monk |
| 44 | Karate Gi | armor | 18 | 28 | 14 | 118 (Dragon Gi) | 102 | Monk |
| 45 | Lute Strings | weapon | 5 | 18 | 9 | 71 (Silver Strings) | 50 | Bard |
| 46 | Ring of Swift Recovery | trinket | 5 | 50 | 25 | - | - | ALL |
| 47 | Medic's Charm | trinket | 10 | 130 | 65 | - | - | ALL |
| 48 | Zara's Signet | trinket | 15 | 210 | 105 | - | - | ALL |
| 49 | Silver Dagger | weapon | 23 | 40 | 20 | 50 (Mugger's Shiv) | 102 | Rogue |
| 50 | Mugger's Shiv | weapon | 27 | 68 | 34 | 51 (Golden Dagger) | 132 | Rogue |
| 51 | Golden Dagger | weapon | 31 | 88 | 44 | 52 (Mithril Kris) | 172 | Rogue |
| 52 | Mithril Kris | weapon | 36 | 115 | 57 | 53 (Guro'ji Ritual Dagger) | 218 | Rogue |
| 53 | Guro'ji Ritual Dagger | weapon | 41 | 145 | 72 | 54 (The Red Fang) | 278 | Rogue |
| 54 | The Red Fang | weapon | 46 | 185 | 92 | - | - | Rogue |
| 55 | Frozen Doomspike | weapon | 52 | 230 | 115 | - | - | Rogue |
| 56 | Vardus, the Reaper | weapon | 58 | 300 | 150 | - | - | Rogue |
| 57 | Silver Greatsword | weapon | 24 | 80 | 40 | 58 (Savage Ripsaw) | 162 | Knight,Paladin |
| 58 | Savage Ripsaw | weapon | 28 | 108 | 54 | 59 (Jade Edge) | 195 | Knight,Paladin |
| 59 | Jade Edge | weapon | 32 | 130 | 65 | 60 (Ancient Crystal Sword) | 232 | Knight,Paladin |
| 60 | Ancient Crystal Sword | weapon | 36 | 155 | 77 | - | - | Knight,Paladin |
| 61 | Holy Blade of M'ir | weapon | 40 | 205 | 102 | - | - | Knight,Paladin |
| 62 | Obsidian Soulcrusher | weapon | 45 | 275 | 137 | - | - | Knight,Paladin |
| 63 | Cestus | weapon | 19 | 37 | 18 | 64 (Brass Knuckles) | 96 | Monk |
| 64 | Brass Knuckles | weapon | 22 | 64 | 32 | 65 (Spiked Gloves) | 128 | Monk |
| 65 | Spiked Gloves | weapon | 26 | 85 | 42 | 66 (Imbued Wristwraps) | 180 | Monk |
| 66 | Imbued Wristwraps | weapon | 30 | 120 | 60 | 67 (Anointed Gauntlets) | 210 | Monk |
| 67 | Anointed Gauntlets | weapon | 34 | 140 | 70 | 68 (Fist of the North) | 248 | Monk |
| 68 | Fist of the North | weapon | 38 | 165 | 82 | - | - | Monk |
| 69 | Gloves of the Long Death | weapon | 43 | 225 | 112 | - | - | Monk |
| 70 | Taizu's Hand of Justice | weapon | 48 | 290 | 145 | - | - | Monk |
| 71 | Silver Strings | weapon | 8 | 33 | 16 | 72 (Masterwork Strings) | 78 | Bard |
| 72 | Masterwork Strings | weapon | 11 | 52 | 26 | 73 (Enchanted Strings) | 105 | Bard |
| 73 | Enchanted Strings | weapon | 15 | 70 | 35 | 74 (Strings of Swooning) | 150 | Bard |
| 74 | Strings of Swooning | weapon | 19 | 100 | 50 | 75 (Dragon Sinew) | 177 | Bard |
| 75 | Dragon Sinew | weapon | 23 | 118 | 59 | 76 (Angel Hair) | 225 | Bard |
| 76 | Angel Hair | weapon | 28 | 150 | 75 | - | - | Bard |
| 77 | Echoes of Love Lost | weapon | 33 | 196 | 98 | - | - | Bard |
| 78 | The Spirit of Battle | weapon | 39 | 260 | 130 | - | - | Bard |
| 79 | Dual Scimitars | weapon | 24 | 42 | 21 | 80 (Cold Iron Slashers) | 111 | Barbarian |
| 80 | Cold Iron Slashers | weapon | 28 | 74 | 37 | 81 (Ogre Maulers) | 142 | Barbarian |
| 81 | Ogre Maulers | weapon | 32 | 95 | 47 | 82 (Twin Battleaxes) | 188 | Barbarian |
| 82 | Twin Battleaxes | weapon | 37 | 125 | 62 | 83 (Frost-Giant Crushers) | 240 | Barbarian |
| 83 | Frost-Giant Crushers | weapon | 42 | 160 | 80 | 84 (Wyvern's Bite) | 322 | Barbarian |
| 84 | Wyvern's Bite | weapon | 47 | 215 | 107 | - | - | Barbarian |
| 85 | Hammers of the Underkings | weapon | 53 | 250 | 125 | - | - | Barbarian |
| 86 | Armageddon Blades | weapon | 60 | 330 | 165 | - | - | Barbarian |
| 87 | Crystal Rod | weapon | 24 | 35 | 17 | 88 (Medicine Cane) | 87 | Cleric |
| 88 | Medicine Cane | weapon | 28 | 58 | 29 | 89 (Emerald Rod) | 114 | Cleric |
| 89 | Emerald Rod | weapon | 32 | 76 | 38 | 90 (Blessed Sceptre) | 158 | Cleric |
| 90 | Blessed Sceptre | weapon | 36 | 105 | 52 | 91 (Sceptre of the Just) | 192 | Cleric |
| 91 | Sceptre of the Just | weapon | 41 | 128 | 64 | 92 (Rod of Singing Sapphires) | 225 | Cleric |
| 92 | Rod of Singing Sapphires | weapon | 46 | 150 | 75 | - | - | Cleric |
| 93 | Beacon of the Heavens | weapon | 52 | 198 | 99 | - | - | Cleric |
| 94 | Sanctuary | weapon | 58 | 270 | 135 | - | - | Cleric |
| 95 | Vined Heartwood Staff | weapon | 27 | 50 | 25 | 96 (Pulsing Earthstone) | 108 | Wizard,Witch |
| 96 | Pulsing Earthstone | weapon | 31 | 72 | 36 | 97 (Violet Sceptre) | 141 | Wizard,Witch |
| 97 | Violet Sceptre | weapon | 35 | 94 | 47 | 98 (Winged Staff of the Void) | 195 | Wizard,Witch |
| 98 | Winged Staff of the Void | weapon | 40 | 130 | 65 | 99 (Elementalist's Sceptre) | 243 | Wizard,Witch |
| 99 | Elementalist's Sceptre | weapon | 45 | 162 | 81 | 100 (Ill Omen) | 300 | Wizard,Witch |
| 100 | Ill Omen | weapon | 51 | 200 | 100 | - | - | Wizard,Witch |
| 101 | Pillar of the Venom Lord | weapon | 57 | 248 | 124 | - | - | Wizard,Witch |
| 102 | Ivory Staff of the Archmage | weapon | 64 | 345 | 172 | - | - | Wizard,Witch |
| 103 | Plate Mail | armor | 24 | 70 | 35 | 104 (Mithril Plate) | 180 | Knight,Paladin |
| 104 | Mithril Plate | armor | 29 | 120 | 60 | 105 (Templar's Armor) | 270 | Knight,Paladin |
| 105 | Templar's Armor | armor | 34 | 180 | 90 | 106 (Valiant Plate) | 375 | Knight,Paladin |
| 106 | Valiant Plate | armor | 39 | 250 | 125 | - | - | Knight,Paladin |
| 107 | Aegis of the Lost City | armor | 45 | 340 | 170 | - | - | Knight,Paladin |
| 108 | Elven Cloak | armor | 11 | 40 | 20 | 109 (Mystic Robes) | 120 | ALL |
| 109 | Mystic Robes | armor | 14 | 80 | 40 | 110 (Crystalweave Cloak) | 195 | ALL |
| 110 | Crystalweave Cloak | armor | 18 | 130 | 65 | 111 (Truth-Seeker's Wrap) | 292 | ALL |
| 111 | Truth-Seeker's Wrap | armor | 22 | 195 | 97 | - | - | ALL |
| 112 | Mantle of the Immortal | armor | 27 | 265 | 132 | - | - | ALL |
| 113 | Studded Leather | armor | 16 | 65 | 32 | 114 (Enchanted Leather) | 165 | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 114 | Enchanted Leather | armor | 20 | 110 | 55 | 115 (Berserker's Tunic) | 248 | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 115 | Berserker's Tunic | armor | 24 | 165 | 82 | 116 (Assassin's Garb) | 345 | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 116 | Assassin's Garb | armor | 29 | 230 | 115 | - | - | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 117 | Battlegear of the Blademaster | armor | 34 | 310 | 155 | - | - | Knight,Rogue,Bard,Barbarian,Monk,Ranger,Paladin |
| 118 | Dragon Gi | armor | 22 | 68 | 34 | 119 (Sensei's Gi) | 165 | Monk |
| 119 | Sensei's Gi | armor | 27 | 110 | 55 | 120 (Gi of the Iron Body) | 255 | Monk |
| 120 | Gi of the Iron Body | armor | 32 | 170 | 85 | 121 (Garb of the West Wind) | 360 | Monk |
| 121 | Garb of the West Wind | armor | 37 | 240 | 120 | - | - | Monk |
| 122 | Robe of the Master | armor | 43 | 325 | 162 | - | - | Monk |
| 123 | Hunter's Bow | weapon | 23 | 26 | 13 | 124 (Reflex Bow) | 75 | Ranger |
| 124 | Reflex Bow | weapon | 27 | 50 | 25 | 125 (Elven Recurve Bow) | 108 | Ranger |
| 125 | Elven Recurve Bow | weapon | 31 | 72 | 36 | 126 (Heartwood Longbow) | 141 | Ranger |
| 126 | Heartwood Longbow | weapon | 35 | 94 | 47 | 127 (Midnight Striker) | 195 | Ranger |
| 127 | Midnight Striker | weapon | 40 | 130 | 65 | 128 (Dragonheart Bow) | 243 | Ranger |
| 128 | Dragonheart Bow | weapon | 45 | 162 | 81 | 129 (Longbow of the Imperium) | 300 | Ranger |
| 129 | Longbow of the Imperium | weapon | 51 | 200 | 100 | - | - | Ranger |
| 130 | Vash'Lian, the Huntress | weapon | 57 | 248 | 124 | - | - | Ranger |
| 131 | Hurricane | weapon | 64 | 345 | 172 | - | - | Ranger |

---------------------------------------------------------------------------------------------------

## 8. Uncertain / not determined

* `UNVERIFIED:` the identity of the `sounds[]` clips (indices are described only by usage, section 3.8); layer-mask contents (`itemMask`, `partyMask`, `okayMask`, ...) are editor-assigned and not in the IL. In particular what `partyMask` hits in the Merchant screen (drag-to-sell target) is unknown.
* `UNVERIFIED:` `Mathf.RoundToInt` half-way behaviour (banker's rounding assumed; affects only upgrade costs where `1.5 * sellPrice` ends in .5, i.e. odd `sellPrice` targets; the table above uses round-half-even).
* `UNVERIFIED:` whether gold could be insufficient at OK time; code does not re-check (4.4, 3.3).
* `UNVERIFIED:` meaning of `redSquares`/`equipArrows` sprites (3.4); they are visual only.
* The tutorial strings (`tutorialStrings[4], [8], [2], [11]`) are scene data, not in the IL.
* Stat formulas shown in `UpdateInventory` (Power/Armor text) were glanced at only, not fully documented: Cleric (characterClass == 1) shows `int((powerScale*level + player.power)/5) + weapon.power + powerBonus`; other classes `int(player.power + weapon.power + powerBonus + powerScale*level)`; armor text `int(player.defense + armor.power(if gear[1] != -1) + armorBonus + defenseScale*level)` [IL L36927-37140]. This is a display formula; the battle-time stat code is elsewhere.
* Contradiction check: no older notes were consulted in this pass, so no contradictions were recorded.

## 9. Cross-references

* `MenuBrain.UpdateInventory` [IL L36429-41092] redraws icons/portraits/stat text; `updateWeapons` [IL L42278]; `resetMenus` [IL L42711]; `clearDescriptionBox` [IL L42773]; `showUpgradeWindow` [IL L43116]; `showVendorWindow` [IL L43230]; `updateEquipArrows` [IL L33732]; `unlockPlayableCharacters` [IL L43570] (called on entering the tavern).
* `Database.populateMerchant` [IL L2385]; `Database.save/load` [IL L1001/L1685].
* Callers: `MenuBrain.Update` [IL L33578-33716] starts the active coroutine by `activeMenu` every frame (section 3).
* `MotherBrain.$defeatSequence$1730` [IL L75663], `$XPBarAnimation$1712` [IL L74751] refresh stock after battles.

# BH Town-Menu Research — MenuBrain Internals (RECOVERED)

> **Status: PARTIAL recovery.** A research agent (~117 steps) investigated how BattleHeart
> implements its four town-menu screens by reading the decompiled IL
> (`Battleheart datamine/il/Assembly-UnityScript.il`, ~108k lines). It was killed mid-run by
> repeated LLM stream idle-timeouts while trying to write one giant report — the report was
> never written. This doc is reconstructed from its raw tool transcript, preserved at
> `work/bh-town-menu-research-RECOVERED-raw.txt` (8339 lines).
>
> **Read this together with the authoritative doc:** `work/non-encounter-systems-research.md`
> already covers the Shop (§4), Items (§3), and Skill-trees/Progression (§5) mechanics WITH
> IL citations, and the Director has already LOCKED those decisions (see `work/handoff.md`
> "Director's locked decisions"). **This doc adds the lower-level MenuBrain class internals**
> (the single Unity `MonoBehaviour` that IS the entire town hub) — useful only if CR wants
> exact behavioral parity. It does NOT change any locked decision.

---

## 1. The one fact that reframes everything: it's ONE screen, not four

BattleHeart does not have four separate town-menu screens. It has a **single `MenuBrain`
class** (one Unity `MonoBehaviour`, IL range ~L32873–L43672) that is the entire pre-battle
hub. The "Party / Equip / Shop / Talents" screens are **sub-panels of `MenuBrain`**, switched
by per-panel input handlers and camera moves — not separate scenes.

`[IL L32873–L43672]` — the full class body spans this range.

This validates CR's existing architecture choice: CR's four screens are separate
`screens/*.lua` files, which is a fine divergence — CR does not need to replicate the
single-class structure to get behavioral parity.

### MenuBrain method map (named, with IL line of method END) `[IL]`
Recovered clean. Method start = the `.method` directive; end line shown.

| Method | End line | Role |
|---|---|---|
| `.ctor` / `Awake` / `Main` | 33079 / 33507 / 43672 | init |
| `Update` | 33716 | per-frame dispatch |
| `mainInput` | 34075 | top-level hub input |
| `inventoryInput` | 33729 | **EQUIP/Armory** panel input |
| `storeInput` | 34088 | **SHOP/Merchant** panel input |
| `skillsInput` | 34101 | **TALENTS/Academy** panel input |
| `tavernInput` | 34114 | **HIRE/Tavern** panel input |
| `keepInput` | 34140 | **PARTY/Keep** (roster bench) panel input |
| `mapInput` | 34127 | map panel input |
| `loadInput` / `tutorialInput` | 34153 / 34811 | load + tutorial |
| `startNewGame` / `loadExistingGame` | 35555 / 36426 | save lifecycle |
| `UpdateInventory` | 41092 | rebuild equip/inventory UI |
| `UpdatePartyPortraits` | 41772 | rebuild party strip UI |
| `InitialPartySelection` | 42275 | pick starting party |
| `updateWeapons` | 42708 | refresh weapon display |
| `resetMenus` / `clearDescriptionBox` | 42770 / 43113 | UI reset |
| `showUpgradeWindow` / `showVendorWindow` | 43227 / 43361 | armory upgrade / vendor popups |
| `calculatePowerBonus` / `calculateArmorBonus` | 43456 / 43527 | gear → stat recompute |
| `unlockPlayableCharacters` | 43662 | roster unlock |
| `orientScreen` / `applyCorners` / `introSequence` / `OnApplicationPause` / `updateLoadScreen` / `muteSoundEffects` | various | chrome |

The per-panel `*Input` handlers are the behavioral core of each "screen". To port a screen's
exact behavior, read that handler's IL range (e.g. SHOP = `storeInput`, start ≈ L34078,
end L34088... note: these end-lines are close together because several are tiny dispatch
stubs; the real logic is in the coroutines they trigger, named `$storeInput$NNNN` etc.).

---

## 2. MenuBrain field map (UI state) `[IL]`
Recovered clean from the `.field` listing of the class. Grouped by the panel they serve.
This is the *view state*; the persistent data lives in `Database` (§3). Field names are
self-describing — they confirm which UI elements each panel has (and thus what CR's
equivalent screen must render).

**Shared / hub:** `DB` (the `Database` singleton), `cameraLens/cameraTransform`,
`wiperAnim`, LayerMasks (`itemMask/partyMask/upgradeMask/cancelMask/okayMask/exitMask`),
`select/selectAnim`, `battleButton`, `litSword`, `currentMap`.

**KEEP / PARTY panel:** `keepIcons[]`, `portraitButtons3[]`, `keepLevels[]`.

**MAP panel:** `mapIcons[]`, `mapJunk[]`, `mapGeo`, `mapAnim`, `mapNameText`,
`levelNameText`, `levelDescText`.

**TAVERN / HIRE panel:** `recruitGearIcons[]`, `recruitNameText`, `recruitDescText`,
`recruitPriceText`, `recruitClassText`, `recruitNameSmall`, `recruitCoinIcon`,
`hireButtonAnim`, `hireScreen`, `hireScreenAnim`, `hireScreenText`, `goldText3`,
`powerText2`, `armorText2`. → Confirms the recruit card shows name/class/desc/price/gear.

**ACADEMY / TALENTS panel:** `skillNameText`, `skillDescText`, `classText`,
`portraitButtons2[]`, `closeupGroup`, `litLines[]`, `litSticks[]`, `skillIcons[]`,
`skillGreyouts[]`. → The "greyouts" confirm locked-skill display; "litLines/litSticks"
are the connector lines between ladder nodes.

**MERCHANT / SHOP panel:** `goldText2`, `itemNameText2`, `itemDescText2`,
`inventoryIcons2[]`, `priceIcon2`, `powerIcon2`, `defenseIcon2`, `itemPowerText2`,
`priceText2`, `merchantArrowsRoot`, `merchantArrows[]`.

**ARMORY / EQUIP panel:** `portraitCovers[]`, `costLocation`, `vendorButton(+Anim/Light)`,
`upgradeButton(+Light)`, `powerText`, `armorText`, `goldText`, `nameText`, `itemNameText`,
`itemDescText`, `inventoryIcons[]`, plus `updateEquipArrows`/`merchantArrows` for nav.

> Takeaway for CR: each panel has (a) a portrait selector, (b) an info/desc bar, (c) a grid
> of icons, (d) a gold readout. CR's `equip.lua`/`shop.lua`/`talents.lua`/`party_select.lua`
> already follow exactly this shape (party strip + grid + desc bar + gold), so the layout
> parity the prior Lead built is correct.

---

## 3. Data model (Database) — what the transcript confirmed `[IL]` / partial
The agent probed `Database` fields and array sizing but was killed before finishing. What it
confirmed (consistent with the authoritative doc §5a):

- `Database.partyDB : Player[]` — the full roster. `[IL L236–L293 region, unlockPlayableCharacters]`
- `Database.party : int32[]` and `Database.reserves : int32[]` — indices into `partyDB`;
  `party` = active (max 4), `reserves` = bench. The agent's FINAL probe was sizing these
  arrays in `load` (`get_length` calls at IL_0518/0561/06e2/06f7) but did not record the
  exact constants before dying. **`reserves`/`party` exact sizes = NOT recovered.**
- `Database.gold : int32` — single currency. `[IL]`
- `Database.merchant : int32[]` — item ids for sale, refilled by `populateMerchant()`. `[IL]`
- `Database.itemDB / powerDB` — item and power tables. `[IL, per authoritative doc §5a]`

> The authoritative doc already records the OPERATIONAL facts CR needs (hire = 10×level
> `[wiki]`, sell = 50% of price, restock after each battle, merchant size Random.Range(3,10)
> — see `non-encounter-systems-research.md` §4a). The only thing this transcript adds is the
> field-level confirmation above.

### Merchant buy/sell — the agent's last finding (UNVERIFIED, treat as lead only)
Its closing message noted, from `storeInput` IL:
- **Buy** (`whichSlotSelected >= 0x14=20`, i.e. a merchant slot): `gold -= itemDB[merchant[slot-20]].sellPrice`; item moves merchant→inventory; merchant slot refilled.
- **Sell** (`whichSlotSelected < 20`, from inventory): `gold += itemDB[inventory[slot]].sellPrice` followed by `ldc.i4.2` — the agent suspected a `/2` (sell for half) but the
  opcode was filtered out of its grep, so **the divisor is UNCONFIRMED in this transcript.**
  The authoritative doc already states sell = 50% `[IL-derived]`, so treat 50% as correct;
  the `/2` here is consistent but not independently proven.

---

## 4. What is INCOMPLETE / not recovered
- Exact `party[]` / `reserves[]` array sizes (the die point).
- The four `*Input` handlers' full behavioral logic (only the method map + fields recovered;
  the per-screen click/gesture flow was still being read).
- Tavern hire cost formula re-derivation (the `10×level` figure comes from the authoritative
  doc / wiki, not re-confirmed here).
- XP/level curve for the Academy panel (covered by authoritative doc §5a instead).

**If exact parity is ever needed, re-read these IL ranges directly** (they are stable):
`storeInput` (shop), `inventoryInput` + `calculatePowerBonus/ArmorBonus` (equip),
`skillsInput` (talents), `keepInput` + `unlockPlayableCharacters` (party), `tavernInput` (hire).

## 5. Bottom line for the port
Nothing in this recovery changes the Director's locked decisions or the already-written CR
screens. The four CR screens are implemented and (after the syntax/forward-ref fixes in this
session) load clean under `./test_headless`. This doc's value is the §1–§2 MenuBrain map as a
parity reference. The raw transcript remains at
`work/bh-town-menu-research-RECOVERED-raw.txt` for any future deep-dive.

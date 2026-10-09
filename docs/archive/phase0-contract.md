# Phase 0 — Economy & Item Foundation: SHARED CONTRACT (authoritative)

Every dev agent in this workstream codes against this exact interface. Do NOT invent
parallel shapes. Values that are `[tuned]` are our placeholder guesses (BH DB is
unextractable) — keep them in this one file so they're easy to retune later.

## Save data (save.lua `M.defaultData()` — NEW fields added by Foundation)
```lua
saveData = {
  ...existing (floor, partyOrder, unlockedCharacters, inventory, mapProgression)...,
  gold = 0,                       -- NEW: unspent gold
  items = {},                     -- NEW: all owned item INSTANCES { [id]=instance }
  shopState = {                   -- NEW: dedicated shop screen state
    offers     = {},              -- gear offers: array of item INSTANCE ids (3 entries)
    hireOffer  = nil,             -- character key string, or nil if not affordable/none
    lastFloor  = 1,               -- floor the shop was last stocked for
    seeded     = true,            -- true once stocked this floor
  },
}
```
`inventory` (existing, was `{}`) now holds a flat array of item INSTANCE ids the party
carries (order = display order). Item instances live in `items[id]`.

## Item INSTANCE (the object stored in saveData.items[id])
```lua
-- itemType: "weapon" | "armor" | "trinket"
-- grade:    1 | 2 | 3   (low/mid/high)
{
  id        = <string, unique, e.g. "it_0001">,
  itemType  = "weapon",
  grade     = 2,
  name      = "Rusted Longsword",        -- generated per catalog
  icon      = "weapon",                  -- icon token for UI
  sellPrice = 12,                         -- 50% of value; [tuned]
  usableBy  = {"knight","champion"},      -- weapon class-gate; armor/trinket = {} (any)
  mods      = { ATK=3 },                 -- flat stat additions, see Stats
}
```

## Per-character equipment (saveData.unlockedCharacters[name].equipped — now 3 keys)
```lua
equipped = { weapon = <itemId or nil>, armor = <itemId or nil>, trinket = <itemId or nil> }
```

## Stats — gear is folded in at the encounter boundary ONLY
`encounter/stats.lua` is NOT modified. Instead `M.fromSave(ss, gear)` gains an optional
second arg (default nil => byte-identical to today when gear is nil/absent). When gear
is provided (a character's equipped instance ids resolved to their instance tables),
add each `mods` key to the corresponding stat's `.add`:
```lua
-- M.fromSave(ss, gear)
local s = { ...exactly as today... }
if gear then
  for _, inst in pairs(gear) do        -- gear = { weapon=instance, armor=instance, trinket=instance }
    for k, v in pairs(inst.mods or {}) do
      if s[k] then s[k].add = s[k].add + v end
    end
  end
end
return s
```
Call site (in the encounter screen / party build, WHEREVER fromSave is currently called
with save stats) must pass `gear = resolveGear(saveData, charName)`.

## Foundation API (NEW file `main-game/items.lua`, module `items`)
```lua
local M = {}

-- Catalog of base item templates per (itemType, grade). [tuned] placeholder names/mods.
-- Structure: M.CATALOG.weapon[1] = { name="...", mods={...}, usableBy={...}, value=... }
-- ~15 total templates across weapon/armor/trinket x 3 grades.

function M.makeInstance(id, itemType, grade) -- builds an instance from CATALOG (fills name,icon,sellPrice,usableBy,mods)
function M.randomItem(floor, itemType)       -- pick a template by grade ~ floor tier, return (itemType, grade)
function M.rollOffers(floor)                 -- 3 gear offers: returns { {itemType,grade}, x3 } weighted by floor
function M.rollHire(saveData)                -- pick 1 random NOT-yet-in-active-party character; respects gold affordability
function M.resolveGear(saveData, charName)   -- returns { weapon=instance?, armor=?, trinket=? } from equipped ids
function M.addGold(saveData, n)              -- saveData.gold = (saveData.gold or 0) + n
function M.spendGold(saveData, n)            -- true if enough & deducted, else false (no negatives)
function M.sellValue(inst)                    -- inst.sellPrice
function M.nextId(saveData)                   -- allocate next unique item id; store in saveData._itemIdSeq
```
Gold reward on WON encounter: `M.addGold(saveData, 10 + 5 * saveData.floor)` plus
per-kill drip `1` per enemy defeated (wire where victory/death counts are tallied).

## Shop restock rule (Director-confirmed)
The shop RESHUFFLES after every WON encounter (new 3 gear offers + 1 new hire), and
stays put otherwise. Mechanism (so the SHOP screen and the ENCOUNTER screen agree):
- `encounter.lua` victory branch (where `onEncounterWon` fires) ALSO sets
  `saveData.shopState.pendingRestock = true`. (Wired by the Manager / encounter owner.)
- The SHOP screen, on entry, calls `restockIfNeeded(saveData)`: if
  `pendingRestock` is true OR `shopState.seeded` is false OR `shopState.lastFloor`
  differs from `saveData.floor`, then mint: for each of the 3 `rollOffers(floor)`
  `{itemType,grade}` templates, `makeInstance(nextId, itemType, grade)` -> store in
  `saveData.items[id]` and push the id onto `shopState.offers`; set
  `shopState.hireOffer = rollHire(saveData)`; set `lastFloor = floor`, `seeded = true`,
  `pendingRestock = false`. Re-entering the shop with no new win does NOT reshuffle.
- `shopState.offers` therefore holds 3 minted item INSTANCE ids (array).
- Purchase: `spendGold` the item's `value` (not sellPrice), move the id out of
  `shopState.offers` and into `saveData.inventory`. (Sell-back is a SEPARATE mechanic:
  selling an owned item pays `sellValue(inst)` = 50%, used from the equip/shop sell UI.)

## What is NOT in scope for Foundation
- No screen UI. No map wiring. No talent/ladder data (that's Phase 4).
- Foundation delivers ONLY: save fields, items.lua, the fromSave(gear) arg, and the
  victory-gold hook. It must keep `./test_headless` PASS and existing save load clean.

## Values [tuned] — single source, retune here
- Victory gold: 10 + 5*floor. Per-kill drip: 1.
- Item value by grade: g1=8, g2=16, g3=30 gold; sellPrice = 50% (rounded).
- Grade by floor: floor 1-2 -> mostly g1 + some g2; floor 3-4 -> g2 + some g3; floor 5+ -> g2/g3.
- Hire cost: 60 + 20*floor.
- Weapon class-gates: knight/champion->sword line, duelist/hunter->blade/bow line,
  witch/wizard->staff line, rogue/nomad/piper/jester/cleric/paladin->mixed. (Coarse is fine.)
- mod magnitudes: weapon +ATK (g1 2 / g2 4 / g3 7), armor +DEF+maxHP (g1 DEF1+HP10 / g2 DEF2+HP20 / g3 DEF4+HP35),
  trinket one of +ATK% / +DEF / +maxHP / +XP% (g1..g3 scaling).

# Battleheart Non-Encounter Systems — Research & CR Divergence Plan

**Prepared by:** battleheart-research · **For:** Director / Manager
**Companion docs:** `work/battleheart-encounter-parity.md` (encounter foundation), `work/class-port-spec-cleric-paladin-wizard-rogue.md` (class/ability structure). No `main-game/` files modified.

## 0. Method, tooling & confidence key

**Sources used**
- **IL (authoritative logic):** `il/Assembly-UnityScript.il` (108,667 lines). Key classes read this pass: `Database`, `Map`, `Level`, `Wave`, `LootTable`, `LootThreshold`, `Item`, `Player`, `Power`, `powerCollection` (fields ~IL L606–920), `MenuBrain` (L32873+, 26k-line body — shop/tavern/armory/academy UI brain), `MotherBrain.enemySpawn` (L65074–65393), `MotherBrain.populateEnemyPools` (L64998+), `EnemyScript.spawn` (spawningStyle/floor/cieling/edge/acquireRandomTarget), `MotherBrain.levelCompleteSequence` (L70149 + nested `$levelCompleteSequence$1673` L72440+), `MotherBrain.calculateNextLevelXP` (L70340–70404), `MotherBrain.levelUpEnemies` (L70188–70259), `Database.populateMerchant` (L2386+).
- **Binary data tables (values):** ❌ **NOT extracted.** Two blockers, documented:
  1. UnityPy 1.25.2 cannot parse BH's custom MonoBehaviour types — of 444 MonoBehaviours only 1 reads (`level0` → `{m_Enabled,m_GameObject,m_Name,m_Script}`, no values); the other 443 fail "Expected to read N bytes, but only read 24" (custom type metadata missing from UnityPy). Verified with a throwaway script at DATAMINE `tools/_bh_extract.py`.
  2. **AssetStudio CLI could not be run**: it needs .NET 9; `brew install --cask dotnet-sdk@9` failed because pkg installation requires `sudo`, which is blocked in this headless environment (`sudo: a terminal is required`). The binary exists at `tools/AssetStudioModCLI/AssetStudioModCLI_net9_mac64/AssetStudioModCLI`. Exact unblock steps are in §7. Consequence: all concrete *numbers* below (item names/prices, XP curve, wave contents, hire prices) are `[wiki <url>]` or `[tuned]`; all *structures/mechanics* are IL-verified unless marked otherwise.
- **Web wikis (lower confidence):** Fandom Battleheart ([Items](https://battleheart.fandom.com/wiki/Items), [Weapons](https://battleheart.fandom.com/wiki/Weapons), [Characters](https://battleheart.fandom.com/wiki/Characters), [Arenas](https://battleheart.fandom.com/wiki/Arenas)), StrategyWiki ([Gameplay](https://strategywiki.org/wiki/Battleheart/Gameplay), [Doomvale](https://strategywiki.org/wiki/Battleheart/Doomvale)), Gamezebo walkthrough, PocketGamer. Tagged `[wiki ...]`.

**Confidence tags:** `[IL Lxxxx]` = verified in Assembly-UnityScript.il · `[data AssetStudio]` = parsed binary table (none yet available) · `[wiki <url>]` = web source · `[inferred]` = my interpretation · `[tuned]` = proposed value for CR, not a BH fact. Datamine wins on conflict.

---

## 1. Map / level traversal

### (a) How BH works
| Aspect | BH behavior | Source |
|---|---|---|
| World container | `Database.levelDB : Map[]`; each `Map{mapName, mapScale, Level[] whichLevel}`; current position `Database.currentMap` / `whichLevel` | `[IL L801-822, L854+]` |
| Level content | `Level{levelName, description, complete, arena, LootThreshold[] arenaTable, prereq, prereqLoc, Vector2 myPosition, Wave[] waves, whichMap, enemySet, totalEnemyTypes, transition, transitionDirection, music, goldReward, XPReward, lootTable, rareChance, highScore}` | `[IL L740-781]` |
| Progression gating | Each level has `prereq`/`prereqLoc` (index into another map's levels) + `complete` flag → level-select tree with unlock chains | `[IL L740+]` |
| Theme/background | Per-level `music` string + `transition`/`transitionDirection`; background textures chosen per scene (no named field in assembly) | `[IL L740+]; [inferred]` |
| Select screen | `MenuBrain` owns `mapIcons[]`, `mapGeo`, `mapAnim`, `mapNameText`, `levelNameText`, `levelDescText`, `battleButton`, `litSword`, `keepIcons[]`, `merchantArrows[]` — a graphical map with selectable level nodes | `[IL MenuBrain fields L32873+]` |
| Arena variant | `Level.arena==true` runs endless survival; `Level.arenaTable[LootThreshold{requiredKills, whichTable}]` gates drop tier by kill count; `MotherBrain.arenaMode`, `totalKills`, `highScore` | `[IL L740+, L781-801]` |
| Maps known | Haggerdom, Brightstone, Doomvale (+ their arenas) per wiki; per-map enemy sets via `Level.enemySet`/`totalEnemyTypes` feeding pooled prefabs | `[wiki Arenas]; [IL]` |
| Difficulty pacing | Manual: player picks any completed/next level; `enemyTier` only matters in arenas (§2) | `[inferred]` |

### (b) CR current state
- Single hand-drawn grid map: 21×13 tiles, one location ("DARK FOREST"), tile types empty/tree/water/**encounter**/**shop**; fog-of-war reveal; autosave per move; top bar PARTY/TALENTS/ITEMS (TALENTS & ITEMS are stubs — `onTopBar` handles only back & party). `[CR screens/map.lua:46-151, 316-322]`
- Save shape: `floor`, `partyOrder[4]`, `unlockedCharacters{name:{level, pointsToNextLevel, stats, equipped{}, skillTree{1,1,1,1,1}}}`, `inventory[]` (empty in practice), `mapProgression{playerCol/Row, revealedTiles, clearedEncounters}`. No gold, no items, no floor reset logic. `[CR save.lua]`
- Encounter launch passes no per-level config — `switchFn("encounter", sd, slot)`; encounter uses default `encounterConfig` (spawnDelay 4.0 etc.). `[CR map.lua:293-314; screens/encounter.lua:231-261]`
- Floor concept exists in save (`data.floor`) but nothing consumes it. `[CR save.lua:20-21]`

### (c) Recommended CR approach (incl. divergence)
**KEEP** the tile-grid map — it's already better than BH's static node map for CR's roguelite-floor framing, and it naturally hosts shops. **DIVERGE** in structure:
1. **One map per floor, procedurally laid out** (seeded RNG): encounter density, shop placement (1/floor), exit/portal tile that advances `floor`. Reuse existing grid code; generate `RAW_MAP` from a seed instead of a constant. `[tuned]`
2. **Encounter tiles carry generation params**, not fixed waves: each `T_ENCOUNTER` tile stores `{dangerBudget, archetypeMask, specialFlag}` produced at floor-gen time (§2). This is the hinge between map and procedural spawning.
3. **Shop tile** triggers a shop screen (§4); keep exactly one per floor.
4. **No per-level prereq tree** (BH's `prereq/prereqLoc`) — floors replace levels as the progression axis. Keep a light "boss tile" every Nth floor as the stage-clear analog. `[inferred recommendation]`
5. Store generated floor layout in save (or regenerate deterministically from `floor`+seed so saves stay small). `[tuned]`

### (d) Pri/Effort
**P1 · M** (grid map exists; add seeded generation + floor advance + tile params).

---

## 2. Enemy spawning

### (a) How BH works — EXACT data shape (for reference)
```
Database.levelDB[currentMap].whichLevel[whichLevel].waves[currentWave]   // Wave[]
Wave { float initialDelay;      // -> MotherBrain.spawnDelay when wave starts  [IL L65222]
       float spawnDelay;        // -> MotherBrain.spawnCooldown between spawns [IL L65260]
       int   maxEnemies;        // concurrent cap -> MotherBrain.maxEnemies    [IL L65241]
       int[] enemies }          // spawn ORDER list (archetype ids), consumed  [IL L65288]
                                // left-to-right via wavePosition              [IL L65310]
```
Runtime loop (`MotherBrain.enemySpawn`, every update tick) `[IL L65074-65393]`:
1. If `currentWave >= waves.Length` and no `activeEnemies` → start `levelCompleteSequence()` (normal mode) — **victory = survive all scripted waves**.
2. New wave: copy `initialDelay/spawnDelay/maxEnemies` into MotherBrain; non-arena advances `currentWave++`.
3. Arena mode instead: re-roll `currentWave = Random.Range(0, waves.Length)` (random wave cycling), and if `totalKills > enemyTier*10` call `levelUpEnemies()` (**×1.1 maxHealth & power per tier**) `[IL L65164-65175]`.
4. While `wavePosition < #enemies` and `activeEnemies < maxEnemies` and `spawnDelay<=0`: take next archetype id from `enemies[wavePosition]`, find its pre-instantiated pool object (`populateEnemyPools` creates `totalEnemyTypes` pools × 6 slots per set, `enemyScripts[i*6 + j]` from `Level.enemySet`), check its x≈0 (off-stage), call `EnemyScript.spawn()`, `activeEnemies++`, `spawnDelay = spawnCooldown`, `wavePosition++`. `[IL L65237-65370]`
5. `EnemyScript.spawn()`: resets health, applies `spawningStyle` (sets entry position using `motherBrain.edge/floor/cieling` — edge-walk vs drop-in style), plays "spawn" anim, then **`acquireRandomTarget()`** as the initial target. `[IL EnemyScript.spawn body]`
- Entry points: pool objects pre-positioned off-screen; `spawningStyle` per-enemy decides how they walk/drop in. Bats/necromancers/archers "arrive randomly" per wiki = their spawningStyle/pool placement. `[wiki Monsters]; [inferred]`

**Key insight:** BH spawning is *fully authored*: every level lists an exact ordered enemy sequence with delays and caps. Difficulty inside a fight comes only from wave composition; difficulty *between* fights comes from `enemyTier` (arenas only) — normal levels do NOT scale up on retry.

### (b) CR current state
`encounter_mgr.lua` already implements a **danger-budget generator**: `queueWave` draws `budget = random(waveMinThreat..waveMaxThreat)`, `flushPendingWave` spends budget on skeletons (danger 3 each) spawning right→left with jitter; surprise waves (15%/30 s); victory when `dangerDefeated >= encounterGoal (45)` and no live enemies. Only ONE archetype exists; no per-tile params; no floor scaling. `[CR encounter/encounter_mgr.lua]`

### (c) RECOMMENDED CR procedural generation model
**This is the deliberate divergence: CR generates, BH authors.** Implement on top of existing enc_mgr:

```
-- per encounter tile (set at floor gen, §1):
EncounterSpec { seed:int, dangerTotal:int, minWaves:int, maxWaves:int,
                archetypeMask:int-bitfield, eliteChance:float, boss:boolean }

generate(spec, floor) -> WavePlan[]   -- deterministic from seed (mulberry32/lcg):
  waveBudget[i] = baseBudget(floor) * ramp(i, nWaves)      -- e.g. 8..20 threat, rising
                   * (1 + 0.10*(floor-1))                  -- floor scaling [tuned]
  for each wave: while budget>0: pick archetype weighted from mask
                 (weights biased toward cheap early wave, elite chance late),
                 append {type, delay=jitter(baseDelay)} ; enforce maxConcurrent cap
  special flags: healerPair (add enemy-healer archetype), ambush (first wave spawns mid-arena),
                 boss tile -> final wave = 1 boss + 2 adds
```
Concrete deltas to existing code:
1. `ENEMY_DANGER` table grows: `{skeleton=3, bat=2 (ranged/flyer), caster=4, healer=4, elite_skel=6, boss=15}` `[tuned]`.
2. `flushPendingWave` iterates a generated `{type,x,y,delay}` list instead of a skeleton loop; keeps budget/surprise machinery.
3. **Floor scaling replaces `levelUpEnemies`**: multiplier `1 + 0.10·(floor−1)` applied at entity creation (hp/power), matching BH's ×1.1-per-tier spirit but driven by floor, not kills. `[tuned]` (BH trigger semantics: `[IL L65164-65175]`)
4. Seed stored per tile in save → identical encounter on revisit if desired; else fresh seed per enter.

### (d) Pri/Effort
**P0 · M** (core loop of the game; foundation systems from parity report P0 batch are prerequisites: archetypes, two-stage damage).

---

## 3. Items

### (a) How BH works
| Aspect | BH behavior | Source |
|---|---|---|
| Schema | `Item{itemName, description, icon, itemType, power, upgrade, sellPrice, bool[] usableBy, ingameModel}`; `Database.itemDB` | `[IL L606-633, L854+]` |
| Types | Exactly **3 equipment kinds: weapon, armor, trinket** (string `itemType`). Character must wield a class-appropriate weapon; armor/trinket free choice. No consumables in DB. | `[IL]; [wiki Items]` |
| Tier/rarity | 9 tiers (1–7 normal levels/merchant/upgrades; **8** arenas ≥kill-threshold or endboss-sometimes; **9** arenas only). Power varies within tier ("hidden tier level" variance on drop). No rarity *name* in schema — tier IS the quality axis. | `[wiki Items/Weapons/Arenas]` |
| Stat effect | Weapon `power` → character Power; Armor → Defense; Trinket → mixed (e.g. +%XP, +%gold). Equipment applied through `Player.gear[]` (int item ids, 4 slots: 2 weapons? / armor / trinkets per wiki "four equipment slots") and `powerCollection{powerScale, defenseScale, healthScale, Power[] whichPower}` scaling per class. | `[IL L822-854, Player.gear L633+]; [wiki Gameplay]` |
| Upgrade path | `Item.upgrade` = id of the next-tier item; Armory lets you upgrade in place for gold (expensive). Merchant also sells upgrades. | `[IL]; [wiki Gameplay/Weapons]` |
| Drop rules | Level complete: `Level.lootTable` index → `LootTable{tableName,minLevel,maxLevel,int[] tableContents}` filtered by party max level; `Level.rareChance` gates a rarer second roll; **exactly 1 item** per level. | `[IL levelCompleteSequence ops L73300-73900]` |
| Weapon families | swords (Knight/Paladin), fist weapons (Monk), rods (Cleric), staves (Witch/Wizard shared), strings (Bard), daggers (Rogue), dual axes/swords/maces (Barb), bows (Ranger) | `[wiki Weapons]` |

### (b) CR current state
- Save has `inventory = {}` and per-char `equipped = {}` — never populated; no item data anywhere; map top-bar "ITEMS" button is a stub. Stats come flat from `DEFAULT_STATS`/save, no gear contribution. `[CR save.lua; map.lua:316-322]`

### (c) Recommended CR scope — **leaner than BH (RECOMMENDATION)**
Justification: BH's 9-tier × 8-family ≈ 60+ named items with upgrade chains is content-heavy for a mod whose identity is encounters. Recommend:
1. **Keep 3 item types (weapon/armor/trinket)** — matches BH mental model and the `Player.gear[]` shape; drop the idea of consumables.
2. **Collapse 9 tiers → 3 grades** (common/fine/great) keyed to floor band. Grade sets stat delta; grade shown by tint/name suffix. `[tuned]`
3. **~12–15 items total at launch**: 1 weapon + 1 armor per class family actually shipped (tank/melee/ranged/support per parity report), + 4 universal trinkets (+ATK%, +DEF, +HP, +XP%). Names generated (prefix+base) rather than hand-authored per tier. `[tuned]`
4. **Stat hook**: item contributes `power`/`defense`/`maxHP`/xpMult into the stats system at battle init (existing `fromSave` already composes stats — add `+gear` term). Weapon gate: only own class may equip (BH rule). `[inferred]`
5. **Upgrade = replace**: skip in-place upgrade cost chain; selling old item refunds `sellPrice = f(grade)` (BH has `sellPrice` field — keep). `[tuned recommendation]`
6. Drop source: victory loot roll (§4 currency flow) using a `LootTable`-style `{minFloor,maxFloor,contents[]}` — same schema as BH, smaller tables.

### (d) Pri/Effort
**P1 · M** (needs reward loop first; small catalog keeps it contained).

---

## 4. Shop

### (a) How BH works
| Aspect | BH behavior | Source |
|---|---|---|
| Currency | Gold: `Database.gold`; sources = `Level.goldReward` on win `[IL L73003-73021]`, mid-fight drops (`$goldReward`/`$randomDrop` coroutines `[IL L72440+]`, wiki confirms spoils), and selling items (`Item.sellPrice`, merchant "pays coins for your old items"). | |
| Goods | Randomized merchandise: `Database.populateMerchant()` — finds highest recruited character level, collects all `LootTable`s whose `minLevel ≤ lvl ≤ maxLevel`, then fills `Database.merchant[]` with `Random.Range(3, 10)` random item ids drawn from those tables' `tableContents`. Restocks **after each battle** (per wiki + the function being called at menu re-entry). | `[IL L2386-2515]; [wiki Gameplay]` |
| Pricing | Item purchase price = its `power`-scaled value (exact formula not in traced methods — values in DB asset); upgrades priced separately (expensive); character hire = `10 × level`. `[wiki Tavern]; [tuned-unverified]` |
| Other vendors | **Tavern** hires characters (`recruitPriceText`, `hireButtonAnim`, `recruited`/`available` flags); **Armory** equips/upgrades; **Academy** selects active skills; **Keep** = roster bench (max 4 active). All one `MenuBrain` screen. | `[IL MenuBrain fields]; [wiki Gameplay]` |
| What you can buy | Items (weapons/armor/trinkets), upgrades, new characters. Not skills, not stats directly. | `[wiki]` |

### (b) CR current state
- Map has a `T_SHOP` tile + shop icon asset, but stepping on it does nothing (no popup, no handler). No gold in save; no price logic anywhere. `[CR map.lua:47-50, icons L359-365]`

### (c) Recommended CR shop — lightweight, tied to floors (RECOMMENDATION)
1. **Gold**: add `saveData.gold`; award `floorClearGold = 10 + 5·floor` on victory + per-enemy kill drip (small, e.g. 1–2/enemy) — mirrors BH's `Level.goldReward` + mid-fight drops without needing loot tables immediately. `[tuned]`
2. **Offerings**: 3 randomized slots per visit (like BH's 3–9 range, leaner): mix of (a) gear (when items ship, §3), (b) **character hire** (unlocks next archetype from a short list — BH's tavern function folded in), (c) a **"codex" discount token** optional later. Prices from a small per-item table (no hidden formulas needed since catalog is tiny). `[tuned]`
3. **Restock**: every time the player leaves the floor (fresh roll), plus a fixed "featured" slot that persists for the floor. Simpler than BH's per-battle restock. `[tuned recommendation]`
4. **Sell-back**: 50% of listed price on items once inventory exists. Keep BH's merchant-as-reseller role.
5. **Skip**: separate Academy/Keep/Armory buildings. CR equivalents already exist: party_select = Keep, (future) talent screen = Academy, equipping = part of party preview. One shop screen serves all purchasing. `[inferred recommendation]`

### (d) Pri/Effort
**P1 · S/M** (screen is small; hire mechanic gives it purpose before items land).

---

## 5. Skill trees / progression

### (a) How BH works
| Aspect | BH behavior | Source |
|---|---|---|
| Data | `Player{characterClass, level, XP, int[] gear, int[] abilities, int[] passives(+1/-1 variants), icon}`; `Database.partyDB[Player[]]`; powers defined in `Database.powerDB[powerCollection{whichClass, powerScale, defenseScale, healthScale, Power[]{powerName,description,icon,cooldown}}]`; `PartyMember` copies `abilities[]/passives[]/cooldowns[]/remainingCooldowns[]` at battle start. | `[IL L633-665, L665-687, L822-854, PartyMember L76916+]` |
| XP grant | On clear: `XPReward = Level.XPReward`, modified per member by `bonusXP` (equipment, e.g. mystic-egg style +XP%), then **split among `totalLivingPartyMembers` survivors**; `Player.XP += share`. | `[IL levelCompleteSequence ops L73900-74600]` |
| Curve | `calculateNextLevelXP(level)`: start `xp = DB.firstLevelXP`; loop i=2..level: `xp *= DB.XPtable[i-2]` (if index valid, else last entry). So levels cost `firstLevelXP · Π XPtable` — geometric-ish growth table, values in DB asset (unextracted). `[IL L70340-70404]` |
| Level-up UX | Post-battle `XPBarAnimation` coroutine animates each survivor's XP bar across thresholds; **multiple level-ups in one fight allowed** (loop recomputes `nextLevelXP` as `level` increments); "LEVEL UP!" text per member (`levelUpText[]`, `browniePoints` per member awarded). | `[IL $XPBarAnimation$1712; levelCompleteSequence L74600+]` |
| Unlock model | **Linear per-class ladder, choose-between-two every few levels** (Lv 1 basic; Lv 5 choice A/B; Lv 10 choice; … Lv 30) — see Knight/Cleric/Ranger tables. Learned skills registered in `abilities[]` (actives) / `passives[]` (±1 variant ints that bend formulas, e.g. ranger aimed-shot ×1.4 when `passives[1]==+1`… class-port spec cites exact IL branches). Academy = where you *select which* unlocked actives are equipped (max 3 action buttons) — selection, not spend-points. | `[wiki Knight/Cleric/Ranger]; [IL performSpecial/ability arrays]; class-port-spec §1-4` |
| Is it a "tree"? | **Not a branch-and-point tree** — it's a linear level ladder with binary choices at checkpoints + passives that are ±1 variants. (Battleheart *Legacy* added real multi-path trees; original does not.) | `[wiki-only Legacy note]; [IL]` |
| Gating | Characters hired at tavern unlock more roster; class trainers unlock via map progression (`tutorialStrings`, `academyFirstVisit` flags). Skills themselves need only level. | `[IL Database flags]; [wiki]` |

### (b) CR current state
- Save: per char `level`, `pointsToNextLevel` (fixed 100), `skillTree={1,1,1,1,1}` (flat array, unused), `stats` flat. Encounter loads stats via `stats_mod.fromSave`; skills are hardcoded per class with 4 slots; Q/W/E/R mapping. No XP grant, no level-up, no ability unlock. `[CR save.lua; entities.lua; skills.lua]`

### (c) Recommended CR progression (RECOMMENDATION)
1. **Adopt BH's model minus the bloat:** linear level ladder, **one binary choice every 3 levels** (BH uses ~every 5; CR levels should come faster given procedural floor pacing), choice recorded as `abilities[specialSlot]=id` / `passives[slot]=±1`. This keeps `performSpecial`-style slot execution already mirrored in CR's `skills.list`.
2. **XP:** grant on victory `xpBase(floor) = 40 + 15·floor` split evenly among survivors (BH's `totalLivingPartyMembers` split) + small per-kill trickle; per-char `xpMult` trinket hook later. Curve: reuse BH's shape `need(L) = round(first · Π scale)` with `[tuned] first=50, scale=1.22` until real data lands. Multi-level-ups in one clear supported (loop like BH).
3. **No point-spend, no multi-path tree** at launch — the binary-choice ladder is simpler to UI (fits CR's minimal aesthetic) and is what original BH actually is. *(If the Director wants deeper builds later, port Legacy-style branches — mark as future scope.)*
4. **Passives as ±1 variants** exactly as BH: a passive slot stores `-1/+1/0`; formulas branch on it (e.g. tank taunt strength, heal splash on/off). This matches both BH IL and the class-port-spec hooks.
5. **Unlock gating:** new archetypes unlock via shop hire (§4) + floor milestones; their ladders are just data tables (`classes/<x>/levels.json` style), same loader pattern recommended in parity report §4.3.

### (d) Pri/Effort
**P1 · M** (data-driven ability loader from parity report is a hard prerequisite; UI panel is small).

---

## 6. Where CR should diverge — consolidated decision table

| Feature | BH way | CR recommendation | Why | Effort |
|---|---|---|---|---|
| Encounters | Fixed authored `Wave[]` per level; victory = survive all waves | **Procedural generation** per tile (seeded, danger budget, archetype pool, floor ramp ×1.1) | Director mandate; enables infinite floors instead of finite authored levels; enc_mgr budget engine already exists | M |
| Difficulty scaling | `levelUpEnemies` ×1.1/tier, arena-kill triggered | Floor-index scaling applied at spawn (same ×1.1 spirit) | No arena meta planned yet; floor = natural difficulty axis | S |
| Victory condition | All scripted waves cleared | Danger goal met (`dangerDefeated ≥ goal`) + field clear — keep CR's | Fits procedural waves | – (exists) |
| Map | Static `Map[]`/`Level[]` node select w/ prereqs | Seeded single grid per floor; portal advances floor; 1 shop tile; occasional boss tile | Grid map already built; floors fit roguelite loop; simpler than BH's world tree | M |
| Resource bar for actives | Cooldowns only (no shared meter) | **KEEP CR's shared 50-max resource bar** | Director signature deviation; adds a third decision layer BH lacks | – (exists)
| Item catalog | 9 tiers × 8 weapon families, ~60+ items, in-place upgrades | **3 grades × ~12–15 items, generated names, replace-not-upgrade** | Catalog size vs mod scope; grade tints convey quality cheaply | M |
| Shop | Merchant (3–9 random, restock per battle) + Tavern (hire, 10×lvl) + Armory + Academy + Keep (separate screens) | **One shop screen per floor**: 3 offers (gear/hire/token), restock per floor, sell-back 50%; party_select doubles as Keep; talent screen doubles as Academy | Fewer screens, same functions; hiring early gives shop purpose before items | S/M |
| Currency | Gold from `Level.goldReward` + drops + sells | Same three sources; tune values per floor | Parity | S |
| Progression | Linear ladder, choice-every-~5-levels, ±1 passives, Academy selects equipped actives | **Same ladder, choice every 3 levels, ±1 passives, no point-spend, no multi-path tree** | Matches original BH (not Legacy); fast enough for floor pacing | M |
| Party size | Up to 4 (Keep bench larger) | Keep 4 active; roster bench unlimited (already in party_select) | Parity | – (exists)
| Pets/companions | Ranger pet (PetScript), summon adds | Enemies yes; player pets **deferred** | Scope control | – |
| Arenas/endless | 3 arenas with kill-tier loot (LootThreshold) | **Defer** (floor loop already provides endless difficulty) | Avoids parallel reward systems | – |

---

## 7. Open questions for the Director (decision + recommended default)

1. ~~**DB-asset extraction is blocked on .NET.**~~ **RESOLVED & EXPLORED — extraction complete, but this datamine holds no value tables.** (manager): installed .NET 9 runtime no-sudo — arm64 tarball to `~/.dotnet`, plus x86_64 tarball to `~/.dotnet-x64` because the CLI apphost is x86_64-only; run it as:
    ```
    DOTNET_ROOT=$HOME/.dotnet-x64 arch -x86_64 \
      "<DATAMINE>/tools/AssetStudioModCLI/AssetStudioModCLI_net9_mac64/AssetStudioModCLI" \
      "<DATAMINE>/decompiled/resources/assets/bin/Data" -m dump -o <out>/json
    ```
    → 1,535 assets dumped successfully (`<DATAMINE>/decompiled/resources/assets/bin/Data/_bh_extract_out/json/`). Asset-type census: **Texture2D 522 · Mesh 452 · AudioClip 87 · Shader 27 · Font 3** — VFX/sprites/audio only. Every MonoBehaviour dump is a bare stub (no custom fields — UnityPy's failure mode repeats under AssetStudio). No AssetBundle files exist anywhere in the APK extract, and ability names ("Holy Word", "DivineIntervention") appear nowhere in the scene blobs. **Conclusion:** BH's serialized DB tables (ability power/cooldowns, item list, level/wave defs, XP table) shipped in AssetBundles that were NOT part of this decompilation — they cannot be extracted from what we have. Item names/prices, exact XPtable values, wave contents therefore **stay `[wiki]`/`[tuned]`** unless a second data source appears (an APK containing `.assets` bundles, or Battleheart Legacy files). No Director action needed on tooling; the remaining decision is simply whether to accept tuned values.
2. **Floor vs. levels as the spine.** I recommend floors fully replace BH levels (including dropping BH's `prereq` tree and arenas). **Default:** yes, floors. *Alternative:* keep a few authored "story" levels interleaved between floors for narrative beats.
3. **Item depth.** Lean catalog (3 grades, ~15 items) vs. closer-to-BH (more tiers/families). **Default:** lean at launch; expand post-playtest. Trinket effects: confirm the four (+ATK%, +DEF, +HP, +XP%) or swap any.
4. **Choice cadence.** Choice every **3** levels (my default, faster than BH's ~5) vs. every 5 like BH. Affects how quickly parties feel distinct over a floor run.
5. **Hiring economics.** BH hire price = 10×level. CR default: flat per-archetype price scaled by floor (e.g. 60+20·floor). Confirm we hire *characters* (new archetypes) from the shop rather than adding a separate tavern step.
6. **Per-kill gold drip.** BH awards gold mainly per-level + loot sells. Adding a small per-kill drip makes early floors fund the first hire quickly. **Default:** yes, 1–2/enemy. Flagging since it slightly changes BH economy feel.
7. **Revisit determinism.** Should a cleared/regenerated floor use the same seed (replays reproducible) or re-roll? **Default:** same seed per floor number (stable), new floor = new seed.

**Surprises worth noting**
- BH's "skill tree" is **not a tree** — linear ladder with binary choices + ±1 passives (multi-path trees came later in Battleheart Legacy). Good news: CR's simple `skillTree` slot array maps cleanly onto this.
- The **merchant restock algorithm is verifiable in IL** (`Database.populateMerchant` L2386): 3–9 items from level-filtered loot tables — so even without the DB, the shop *mechanic* is certain; only the item values need AssetStudio.
- `MenuBrain` is a 26k-line catch-all (map select + tavern + armory + academy + hire + inventory UI in one MonoBehaviour) — there is no separate "Shop" class; shop behavior is confirmed by fields + `populateMerchant`, UI details partly `[wiki]`.
- `populateEnemyPools` reveals BH pre-instantiates **6 pool slots per enemy type per set** and reuses them (`enemyScripts[type*6+i]`) — a detail that suggests BH fights were capped well under ~30 concurrent enemies even at max `maxEnemies`.

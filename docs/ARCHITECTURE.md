# Architecture — how the code is organised

Everything lives in `main-game/`. Three layers:

1. **`data/`** — WHAT exists. Pure Lua tables, no logic. Edit these to add or tune content.
2. **`encounter/`** and the top-level modules — HOW things work (the engine).
3. **`screens/`** — one file per screen; each draws and handles input for that screen.

## The screen manager (`main.lua`)

`main.lua` holds a table of screens and forwards LÖVE's callbacks to the current one. Every
screen module exposes:

```lua
M.onEnter(canvas, postfx, switchFn, ...)   -- called when the screen becomes current
M.update(dt)    M.draw()
M.keypressed(key)   M.mousepressed(x, y, button)   M.mousereleased(x, y, button)
M.wheel(dy)     -- optional          M.onExit()   -- optional
```

A screen changes screen by calling `switchFn("name", saveData, slot)`; `main.lua` fades out,
calls `onExit`, then the new screen's `onEnter(canvas, postfx, switchFn, saveData, slot)`.
Screens read the mouse with `common.virtualMouse()` (800×450 space), never `love.mouse`.

Flow: `title` → `save_select` → `map` ⇄ `party_select` / `talents` / `equip` / `shop` /
`encounter` (battle). `sprite_dev` is a developer sprite viewer behind the title's OPTIONS.

## Files

### Top level
| File | Role |
|---|---|
| `main.lua`, `conf.lua` | Screen manager, window setup, test-mode switches (`CR_TEST_SCENE`). |
| `common.lua` | Shared drawing/UI helpers: canvas + post-fx, letterbox, virtual mouse, the animated selection box, fonts (`loadFont`, cached), text fitting (`fitText`, `printCentered`, `titleCase`), the top bar + BACK button (`drawTopBar`), hover tooltips (`drawTooltip`), UI sounds. |
| `item_ui.lua` | How an item looks in menus: its W/A/T token, grade colours, tooltip lines. Used by shop + equip. |
| `save.lua` | Save slots. **The save format is documented at the top of this file.** `migrate()` upgrades old saves. |
| `items.lua` | Item instances, equip rules (`canUse`), gold, shop stock (`rollOffers`). |
| `progression.lua` | Hero stats (`heroStats`), XP/level-ups, battle rewards, hiring. |
| `music_mgr.lua`, `json.lua`, `moonshine/` | Music, JSON, post-processing library (third-party). |
| `headless_test.lua`, `ui_smoke_test.lua` | The two test programs (`./test_headless`, `./test_ui`). |

### `data/` — content
| File | Holds |
|---|---|
| `classes.lua` | Every hero class: base stats, per-level scale, starter gear, sprite, abilities. Also `ANIM_SETS`. |
| `enemies.lua` | Every enemy type and the spawn pool. |
| `abilities.lua` | Every ability (heroes' and enemies'), as effect data. |
| `sprites.lua` | Sprite sheets to load. |
| `talents.lua` | Talent ladders and `modsFor()` (picks → stat bonuses). |
| `bh_items.lua`, `bh_rewards.lua` | **Generated** from `bh/data` by `bh/tools/gen_game_data.py`. Never edit by hand. |

### `encounter/` — the battle engine
| File | Role |
|---|---|
| `world.lua` | The battle world: unit ids + component tables. **Every component is listed and explained here.** |
| `entities.lua` | `createHero` / `createEnemy`: build a unit from its data row. |
| `stats.lua` | Stat tables (`{base, add, mult}` per stat) and `fromFlat`. |
| `skills.lua` | WHEN units act: default-action queue, ability queue ("pay at press, fire when ready"). |
| `abilities.lua` | The ability engine: runs the effect data. **All effect kinds are listed at the top.** |
| `combat.lua` | Damage: `roll` (attacker) → `resolve` (victim) → `registerHit`; heals, stagger, stun, threat, melee range. |
| `status.lua` | Buffs/debuffs (ATK_BUFF, SHIELD, WARD, DOT, SLOW, …) and `getMods`. |
| `effects.lua` | Timed effects on units (hurt flash, knockback, delayed ability impact, passives, tints). |
| `systems.lua` | Per-frame systems: melee slot ring, target following, movement, physics, stagger, stun, threat targeting, death. |
| `encounter_mgr.lua` | BH's wave spawner (one enemy at a time, `maxEnemies` cap, wave after wave) and the victory check. The rules are at the top of the file. |
| `wave_gen.lua` | Makes up a battle's waves (procedural). All difficulty knobs are in its `TUNING` table. |
| `victory.lua` | The three screens after a win: VICTORY, SPOILS (gold + the one item), EXPERIENCE (bars, level-ups). |
| `defeat.lua` | When every hero is dead: DEFEAT, fade, back to the map. No rewards; the encounter can be fought again. |
| `anim.lua`, `particles.lua`, `ui.lua` | Sprite animation, blood/heal particles, health bars + skill icons + resource bar. |

`screens/encounter.lua` owns one battle: it creates the world, spawns the party, calls the
systems in order every frame (see `M.update`), handles input, and grants rewards on victory.

## How a hero's numbers are produced

```
save record (level, equipped, skillTree)          data/classes.lua (base, scale)
              \                                         /
               progression.heroStats(saveData, name)  ->  { maxHP, ATK, DEF, CRIT }
                         |            + gear mods (items.lua)  + talent mods (data/talents.lua)
               entities.createHero(...)  ->  stats.fromFlat(...)  ->  world.stats[id]
```
Stats are never stored in the save. Change a number in `data/` and it applies everywhere.

## How an ability happens

1. The player presses Q/W/E/R → `skills.enqueue`: checks cooldown + resource, starts the
   cooldown, spends the resource, queues the slot.
2. `skills.system` (every frame): when the unit is free and its target is in range, calls the
   skill's `use` (built by `abilities.make`).
3. `use` plays the cast animation and schedules the row's `effect` after `delay` seconds.
4. `abilities.resolveEffect` applies the effect: damage → `combat.registerHit`, status →
   `status.apply`, heal → `combat.registerHeal`, and so on.

## Recipes

**Add an ability.** Add a row to `data/abilities.lua` (copy a similar one; effect kinds are
documented at the top of `encounter/abilities.lua`). Put its id in a class's `actives` (or
`auto`) in `data/classes.lua`. If it needs an effect kind that does not exist, add one branch
to `abilities.resolveEffect` and document it in that file's header.

**Add a hero class.** Add its sprite sheets to `data/sprites.lua`, an entry to `ANIM_SETS` and
a row to `CLASSES` in `data/classes.lua` (base/scale from `bh/data/party.json` +
`classes.json` when porting a BH class), its abilities to `data/abilities.lua`, and its key to
`ALL_CHARACTERS` in `save.lua`. Add an icon `assets/charicons/icon-<key>.png`. Add a talent
ladder to `data/talents.lua` (or it uses the generic one). Add it to a party in `ui_smoke_test.lua`.

**Add an enemy.** Sprite sheets → `data/sprites.lua`; an `ANIM_SETS` entry; a row in
`data/enemies.lua` (stats from `bh/data/prefabs/EnemyScript.json`); its attack in
`data/abilities.lua`; add its id to `SPAWN_POOL`. Note: the spawner currently only uses the
first pool entry (see BACKLOG).

**Change a BH-derived number.** If it comes from `bh/data`, do not edit the generated Lua:
adjust `bh/tools/gen_game_data.py` (or the mapping tables in it) and re-run it. If Crimson Red
deliberately differs from BH, write the value in the hand-written data file and tag it `[tuned]`.

**Add a screen.** Create `screens/<name>.lua` with the interface above, register it in the
`screens` table in `main.lua`, reach it with `switchFn("<name>", saveData, slot)`, and add a
`drive(...)` call for it in `ui_smoke_test.lua`.

**Change the save format.** Update the comment at the top of `save.lua`, `defaultData()`, and
add a step to `migrate()` so old saves still load.

## Testing

- `./test_headless` (`headless_test.lua`): builds a small battle and ticks the engine without
  drawing. Catches engine errors fast.
- `./test_ui` (`ui_smoke_test.lua`): enters every menu screen with synthetic saves and sweeps
  hovers, clicks, random clicks, keys and wheel over it; plays three full battles with a simple
  bot through to victory; checks save invariants and progression maths. Any Lua error in any
  handler fails the run. Add a `check(...)` there for every rule you implement.
  `drive(..., { hover = { {x, y}, ... } })` saves a screenshot with the mouse resting on each
  point (`*-1h<n>-hover.png`): use it to look at tooltips.
- `screens/encounter.lua` exposes `M.debugState()` so tests can read the live world.

## Menu screen conventions
Every menu screen (party, talents, equip, shop, save select, map) follows the same rules:
- **Top bar**: `common.drawTopBar("TITLE", backPressed)` draws the 40 px bar: BACK (text) at the
  left, the title centred, a white rule under it. Hit-test BACK with `common.overBack(x, y)`.
- **Margins**: content sits 20 px from the screen edges and 12 px under the top bar; derive
  sizes from those (see the LAYOUT block at the top of each screen) rather than typing numbers.
- **No description bars**: details go in a hover tooltip, `common.drawTooltip(lines, anchorRect)`,
  drawn last. It places itself under the hovered thing and stays on the canvas.
- **Text never leaves its box**: one-line labels inside a box go through `common.fitText` or
  `common.printCentered`. The font has ASCII glyphs only.

## Battles: waves and rewards
- `progression.battleTier(saveData)`: 1 for a floor's first battle, 2 for the second, ...
  It picks how hard the waves are and which BH reward row applies (`data/bh_rewards.lua`).
- `wave_gen.generate(tier)` returns the waves; `encounter_mgr` spawns them by BH's rules.
- On a win `progression.onEncounterWon` grants gold, one item (if the inventory has room) and
  XP to the survivors (BH's survivor multiplier, plus a bonus for the best performers — the
  score is kept by `combat.addScore`), and `victory.lua` shows what it returned.
- Debug keys in battle: K / J / L / M spawn a skeleton / goblin / bat / mushroom at the mouse.

## Recolouring sprites
`./recolor` (code in `tools/recolor/`) makes a new sprite folder from an existing one by
shifting ONE colour and leaving the rest alone (e.g. the Knight's blue clothes -> green).
`./recolor report <dir>` lists the hues a folder contains; `./recolor shift <src> <dst>
<fromHue> <toHue> [tolerance] [satScale] [valScale]` writes the copy. Cleric, Paladin, Wizard
and Rogue are recoloured Knights: see `RECOLOURS` at the bottom of `data/sprites.lua`.

## Unit size and sprite alignment
- A unit's size is ONE number: `spriteScale` on its row (`data/classes.lua`, `data/enemies.lua`).
  "This enemy is too small" = raise that number; nothing else needs touching.
- Sprite frames are much larger than the character in them. `./align_sprites` measures the
  visible box of every Idle sheet into `data/sprite_bounds.lua` (generated). From it
  `encounter/entities.lua` sets the body box (`world.size` = visible box x scale) and the
  sprite offset, so the feet are on the box's bottom edge. Run it after adding/changing an
  Idle sheet.
- Hand corrections live in `OVERRIDES` at the top of `tools/align/main.lua`: `top` (ignore
  what is above the head, e.g. the witch's staff) and `float` (a flying unit hovers above its
  feet line, e.g. the bat). Change them there, then re-run `./align_sprites`.
- Check by eye: `./test_ui align` saves `align-lineup.png` (every unit with its box), or press
  B in a battle.
- How far apart melee fighters stand: `MELEE_SPACING` in `encounter/systems.lua` (1.0 = boxes
  touch). It uses both body widths, so it follows `spriteScale` automatically.

## Tools (repo root)
| Command | What it does |
|---|---|
| `./check_syntax` | Parses every .lua file. Run it when the game or a test hangs at start-up. |
| `./align_sprites` | Measures sprites -> `data/sprite_bounds.lua`. |
| `./recolor` | Makes a recoloured copy of a sprite folder (one colour shifted). |
| `./test_ui quick` / `align` | Faster subsets of `./test_ui`. |


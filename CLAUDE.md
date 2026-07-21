# Crimson Red — Project Reference Dictionary

> **Purpose:** This file is the single source of truth for any AI agent or new contributor.
> Read it first at the start of every session. Use Ctrl+F / search to look up any term.
> Sections are alphabetically ordered after the Quick-Start block for fast lookup.

---

## Quick Start

| What | Answer |
|------|--------|
| Language | Lua |
| Framework | LÖVE2D (`love`) |
| Run a prototype | `cd prototype/title_screen && love .` (or any prototype dir) |
| Virtual resolution | 800 × 450 (16:9, letterboxed) |
| Default branch | `master` |
| Package manager | None — no rockspec, no luarocks. All deps are vendored. |
| Test suite | None yet. |
| Linter | None configured yet. |
| CI | None configured yet. |
| Build step | None — LÖVE runs Lua source directly. |

---

## A

### Assets (font)
- **Font file:** `Dedicool.ttf` located at `assets/dedicool/Dedicool.ttf` relative to each prototype's directory.
- Each prototype that needs the font has its own copy (e.g. `prototype/title_screen/assets/dedicool/Dedicool.ttf`, `prototype/save_select/assets/dedicool/Dedicool.ttf`).
- Loaded via `common.loadFont(size)` which calls `love.graphics.newFont("assets/dedicool/Dedicool.ttf", size)` with a fallback to the default LÖVE font.

### Assets (icons)
- `icon-making/charicon/` — 8 character class icons: champion, duelist, hunter, jester, knight, nomad, piper, witch (all `.png`).
- `icon-making/mapicon-*.png` — map tile icons: ocean, player, shop, tree, unknown.
- These are pre-generated PNG assets. The generator script is `icon-making/main.lua`.

---

## B

### Box Animation System
A persistent animated red outline box that glides between focusable UI items. Defined in `prototype/shared/common.lua`.

Key functions:
- `common.newBox()` → creates a box state table `{x, y, w, h, tx, ty, tw, th, shown}`.
- `common.initBox(box, x, y, w, h)` → snap box to initial position (no animation).
- `common.setBoxTarget(box, x, y, w, h)` → set new target; box animates toward it. First call snaps.
- `common.updateBox(box, dt)` → advance animation each frame using exponential lerp.
- `common.drawBox(box, pressed)` → draw: red outline normally, white fill when pressed.
- `BOX_SPEED = 14` — exponential lerp speed constant.

---

## C

### Canvas / Rendering Pipeline
Every prototype follows the same 3-step pipeline:
1. **Draw scene** into a `VW×VH` (800×450) canvas with nearest-neighbor filtering (`common.newSceneCanvas()`).
2. **Post-process** at virtual resolution via Moonshine (`postfx(function() ... end)`). Moonshine's internal buffers match the window size; `vw`/`vh` on each effect lock UV pixel steps to virtual res.
3. **Letterbox blit** to the actual window using `common.letterbox()` → returns `ox, oy, scale`.

### Color Palette
| Name | RGBA | Usage |
|------|------|-------|
| Red (crimson) | `{1, 0, 0, 1}` | Primary accent — logo, title text, menu items, box outline |
| Off-red | slightly brighter/lighter red | Hover states (not yet defined as a constant) |
| White | `{1, 1, 1, 1}` | Pressed/active states, slot outlines, text |
| Black | `{0, 0, 0, 1}` | Background, pressed-item text color |

Constants in `common.lua`: `COLOR_RED`, `COLOR_WHITE`, `COLOR_BLACK`.

### `common.lua` — Shared Module
**Path:** `prototype/shared/common.lua`
**Require pattern:** Each prototype prepends the shared path:
```lua
package.path = package.path .. ";../shared/?.lua;../shared/?/init.lua"
local common = require("common")
```

Exports (summary):
| Symbol | Type | Description |
|--------|------|-------------|
| `VW`, `VH` | number | 800, 450 — virtual resolution constants |
| `COLOR_RED/WHITE/BLACK` | table | RGBA color tables |
| `CHROMA_RADIUS` | number | 1.0 — chromatic aberration pixel offset |
| `BLOOM_MIN_LUMA` | number | 0.15 — glow luma threshold |
| `BLOOM_STRENGTH` | number | 3 — glow spread (sigma) |
| `BOX_SPEED` | number | 14 — box animation lerp speed |
| `newPostFX(moonshine)` | function | Build chromasep → glow chain |
| `newSceneCanvas()` | function | Create nearest-filter VW×VH canvas |
| `virtualMouse()` | function | Map real mouse → virtual coords |
| `letterbox()` | function | Returns ox, oy, scale for blitting |
| `newBox()` | function | Create box state |
| `initBox(box,x,y,w,h)` | function | Snap box to position |
| `setBoxTarget(box,x,y,w,h)` | function | Set animation target |
| `updateBox(box,dt)` | function | Advance box animation |
| `drawBox(box,pressed)` | function | Render box |
| `loadFont(size)` | function | Load Dedicool.ttf at given size |

---

## D

### Dependencies
- **Moonshine** (vendored at `prototype/shared/moonshine/`) — MIT-licensed LÖVE2D post-processing library by Matthias Richter. Provides shader effect chaining. Used effects: `chromasep` (chromatic aberration), `glow` (bloom). Also includes `boxblur` (not currently used).
- **No external/remote dependencies.** Everything is vendored in-tree.

### Directory Structure
```
crimson-red/
├── CLAUDE.md                          ← this file
├── icon-making/
│   ├── main.lua                       ← LÖVE app that generates icon PNGs
│   ├── charicon/                      ← 8 character class icon PNGs
│   └── mapicon-*.png                  ← 5 map tile icon PNGs
├── prototype/
│   ├── shared/
│   │   ├── common.lua                 ← shared module (constants, helpers, box system)
│   │   └── moonshine/                 ← vendored post-processing library
│   │       ├── init.lua               ← moonshine core (chain, Effect, autoloader)
│   │       ├── chromasep.lua          ← chromatic aberration effect
│   │       ├── glow.lua               ← bloom/glow effect
│   │       ├── boxblur.lua            ← box blur effect (unused)
│   │       └── effects/               ← stub files (contain "404: Not Found")
│   ├── title_screen/
│   │   ├── main.lua                   ← title screen prototype
│   │   └── assets/dedicool/Dedicool.ttf
│   └── save_select/
│       ├── main.lua                   ← save select screen prototype
│       └── assets/dedicool/Dedicool.ttf
└── main-game/                         ← (planned) final integrated game code — not yet created
```

---

## E

### Engine — LÖVE2D
- Website: https://love2d.org
- Lua-based 2D game framework. Runs Lua source directly — no compilation step.
- Entry point: `main.lua` in the working directory. Run with `love .` from that directory.
- Key callbacks used: `love.load()`, `love.update(dt)`, `love.draw()`, `love.mousepressed()`, `love.mousereleased()`, `love.keypressed()`, `love.resize()`.

---

## I

### Icon Generator
**Path:** `icon-making/main.lua`
- A LÖVE2D utility that draws shapes onto a canvas and saves them as PNGs.
- Uses `io.open` to write directly to the project source directory via `love.filesystem.getSource()`.
- Not a game screen — run it with `cd icon-making && love .` to regenerate icons.

---

## L

### Letterboxing
The game always renders at 800×450. The window can be resized, but the canvas is scaled to fit with black bars (letterboxing). Handled by `common.letterbox()` which returns `ox, oy, scale`:
```lua
local s  = math.min(sw / VW, sh / VH)
local ox = (sw - VW * s) / 2
local oy = (sh - VH * s) / 2
```

### LÖVE Callbacks Used
| Callback | Purpose |
|----------|---------|
| `love.load()` | Init window, canvas, postfx, fonts, build geometry |
| `love.update(dt)` | Mouse hit-testing, box animation |
| `love.draw()` | Render scene to canvas → postfx → letterbox blit |
| `love.mousepressed(x,y,btn)` | Track pressed item |
| `love.mousereleased(x,y,btn)` | Trigger action on release |
| `love.keypressed(key)` | Escape → quit |
| `love.resize(w,h)` | Recreate postfx buffers |

---

## M

### Moonshine (Post-Processing Library)
**Path:** `prototype/shared/moonshine/`
**Author:** Matthias Richter | **License:** MIT

Core API:
```lua
local fx = moonshine(moonshine.effects.chromasep).chain(moonshine.effects.glow)
fx.chromasep.radius = 1.0
fx.glow.strength = 3
fx(function() love.graphics.draw(canvas) end)  -- draw with effects
fx.resize(w, h)  -- call on window resize
```

**Important:** Use `.chain()` not `:chain()` — colon passes `self` as the effect arg.

Effects in use:
- **chromasep** (`chromasep.lua`): RGB chromatic aberration. Params: `angle`, `radius`, `vw`, `vh`.
- **glow** (`glow.lua`): Bloom via Gaussian blur on bright pixels. Params: `strength` (sigma), `min_luma`, `vw`, `vh`.

The `vw`/`vh` params on each effect must be set to the virtual resolution (800, 450) so the effect strength is window-size-independent.

### Mouse Input
- Raw mouse position: `love.mouse.getPosition()`
- Virtual-space mouse: `common.virtualMouse()` — maps real window coords to 800×450 virtual coords, accounting for letterbox offset and scale.

---

## P

### Post-Processing
Applied globally after scene render. Current settings (in `common.lua`):
| Parameter | Value | Notes |
|-----------|-------|-------|
| `CHROMA_RADIUS` | 1.0 | Chromatic aberration pixel offset |
| `BLOOM_MIN_LUMA` | 0.15 | Pixels brighter than this glow (pure red luma ≈ 0.21) |
| `BLOOM_STRENGTH` | 3 | Gaussian blur sigma for glow |

Pipeline: chromasep → glow (in that order).

### Prototype Pattern
Each prototype is a self-contained LÖVE2D app:
1. Lives in its own directory under `prototype/`.
2. Has its own `main.lua` (LÖVE entry point) and its own `assets/` folder.
3. Shares code via `prototype/shared/` by prepending to `package.path`.
4. No prototype has shared mutable state with another.
5. Run any prototype: `cd prototype/<name> && love .`

---

## R

### Reference Material
- Title screen visual reference: `reference-material/image.png` (4:3 ratio version) — may not exist in repo yet.
- C++ raylib reference implementation: `C:\Users\Alex\projects\the-game\crimson-red_v2.0\src\main.cpp` (local to Alex's machine, not in repo).

### Resolution
- **Virtual:** 800 × 450 (16:9). All game coordinates use this space.
- **Window:** resizable, but game renders to virtual canvas then letterbox-scales.

---

## S

### Save Select Screen
**Path:** `prototype/save_select/main.lua`

Layout:
- 3 save slots displayed horizontally, centered.
- Slot dimensions: 200×110 px, 30 px gap between.
- Back arrow in top-left corner (triangle + shaft).
- 4 focusable items: back arrow (1), save slots 1-3 (2-4).
- Red animated box highlights the focused item.
- Pressing a slot: placeholder for load/start save. Pressing back arrow: placeholder for return to title.

Key constants:
| Constant | Value |
|----------|-------|
| `SLOT_COUNT` | 3 |
| `SLOT_W` | 200 |
| `SLOT_H` | 110 |
| `SLOT_GAP` | 30 |
| `TITLE_Y` | ~39% of VH |
| `BOX_Y` | TITLE_Y + 6% of VH |

Save data: currently placeholder (`saveSlots` table with `label` and `empty` fields). Comment says "replace with JSON later."

### Security Profile
- **No network calls.** No HTTP, no sockets, no API keys, no secrets.
- **No database.** Save data is placeholder; will likely be local JSON files.
- **No authentication.** Standalone desktop game.
- **No web server.** No CORS concerns.
- **Filesystem writes:** Only in `icon-making/main.lua` (writes PNGs to project dir via `io.open`).

---

## T

### Title Screen
**Path:** `prototype/title_screen/main.lua`

Layout (at 800×450):
- **Logo:** Sierpinski triangle (3 rows, 6 upward-pointing triangles). Centered horizontally, starts at 8% from top.
  - Triangle side length: `VH * 0.11` (~49.5 px).
  - Built in `buildTriangles()` using row-by-row placement.
- **Title text:** "crimson red" centered at ~49% down. Font size: `VH * 0.08` (~36 px).
- **Menu buttons:** "PLAY", "OPTIONS", "EXIT" — centered horizontally, starting at 67% down, spaced 9% of VH apart. Font size: `VH * 0.0444` (~20 px).
- **Box:** Red outline box animates between hovered buttons. Padding: 8px horizontal, 5px vertical.
- **Interactions:** Hover → red box moves to button. Click → white fill on box + black text. "EXIT" → quit. "PLAY"/"OPTIONS" → placeholder.

### Typography
| Usage | Font | Size (at 800×450) |
|-------|------|-------------------|
| Title text | Dedicool | ~36 px (`VH * 0.08`) |
| Menu buttons | Dedicool | ~20 px (`VH * 0.0444`) |
| Save slot labels | Dedicool | 16 px |
| Save slot content | Dedicool | 12 px |

---

## V

### Virtual Resolution
Always 800 × 450. Never change this — all coordinates, font sizes, and layout values assume this resolution. The window can be any size; letterboxing handles the scaling.

---

## Conventions & Patterns

### Code Style
- Top-of-file comment block with `===` separators and section title.
- Constants in UPPER_SNAKE_CASE at module level.
- Local variables and functions in camelCase.
- Modules return a table (`local M = {} ... return M`).
- LÖVE callbacks are global functions (`function love.load()`, etc.).
- `love.keypressed("escape")` → quit in all prototypes.

### How to Add a New Prototype
1. Create `prototype/<name>/main.lua`.
2. Copy `assets/dedicool/Dedicool.ttf` into `prototype/<name>/assets/dedicool/`.
3. Prepend shared path: `package.path = package.path .. ";../shared/?.lua;../shared/?/init.lua"`.
4. Require common + moonshine. Use `common.newSceneCanvas()`, `common.newPostFX(moonshine)`, and the standard draw pipeline.
5. Run: `cd prototype/<name> && love .`

### How to Add a New Moonshine Effect
1. Create `prototype/shared/moonshine/<effectname>.lua` following the pattern in `chromasep.lua` or `glow.lua`.
2. Return a function that receives `moonshine` and returns `moonshine.Effect{name=..., draw=..., setters=..., defaults=...}`.
3. The autoloader in `init.lua` will pick it up via `moonshine.effects.<effectname>`.

### Known Stubs / Placeholders
- `prototype/shared/moonshine/effects/boxblur.lua` and `effects/glow.lua` contain only `"404: Not Found"` — these are stubs, not real effect files. The actual effects are at the `moonshine/` root level.
- Save data system: `saveSlots` in save_select is hardcoded. Comment says "replace with JSON later."
- Title screen "PLAY" and "OPTIONS" actions are placeholders.
- Save select "back" and "load save" actions are placeholders.
- `main-game/` directory does not exist yet — planned for the final integrated game.

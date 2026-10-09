# Crimson Red — project constants

**Read [`AGENTS.md`](AGENTS.md) first** — it is the entry point (roles, where things are,
how to test, rules). This file only holds the visual/technical constants.

## Engine
- LÖVE2D 11.x, Lua. Run from `main-game/` (`./playtest`).

## Resolution
- Virtual resolution **800 × 450** (16:9). Everything is drawn on an 800×450 canvas which
  is scaled to the window with letterboxing. All coordinates and sizes are virtual pixels.

## Post-processing (applied to every screen)
- Chromatic aberration + bloom via the moonshine chain built in `main-game/common.lua`
  (`CHROMA_RADIUS`, `BLOOM_MIN_LUMA`, `BLOOM_STRENGTH`).

## Palette
- Background: pure black.
- **Red (255, 0, 0)** and **white (255, 255, 255)** only. No off-white, grey, crimson or
  light red anywhere in the UI (Director, 2026-10-09). States are shown by red vs white and by
  filled vs outline, never by a dimmer shade.
- The one exception is gold, for coins and prices.

## Typography
- Font: Dedicool (`main-game/assets/dedicool/Dedicool.ttf`), loaded with `common.loadFont(size)`.
- Title ≈ 50 px, buttons ≈ 16 px. The font has no glyphs for symbols like `·`, `—`, `…`:
  use plain ASCII in UI text.

## Title screen layout (800×450)
- Logo (Sierpinski triangle) centred in the upper third; "crimson red" centred at ~50 %;
  PLAY / OPTIONS / EXIT left of centre at ~65 %, stacked. Hover: the red selection box; press: white.

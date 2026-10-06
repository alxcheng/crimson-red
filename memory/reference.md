# Crimson Red — Reference (load on demand)

Detailed, on-demand specifics. `AGENTS.md` is the always-on lean overview; `CLAUDE.md`
holds the technical constants (palette, typography, resolution, layout). This file
holds run/test steps, file map, and conventions.

## Running the game

LÖVE2D is the engine. The LÖVE `love` binary drives it.

```bash
cd main-game && love .
```

- `conf.lua` sets `identity = "crimson-red"`, title "Crimson Red", 800×450 window,
  resizable, min 400×225.
- If `love` is not on PATH, the install is typically
  `/Applications/love.app/Contents/MacOS/love` (macOS).

## Capture / test workflow (VM screenshots)

During development, screenshots are taken of the running game and saved to
`captures/` (project workspace, never `/tmp` or `~`). Files there are git-ignored.
Use the DSH screen/virtual-browser servers only as documented in the global
`~/.dsh/AGENTS.md` — for a local LÖVE window, the screen server (`:3082`) is the
fallback that captures the real screen.

Naming: descriptive, e.g. `captures/title-screen.png`, `captures/encounter-formation.png`.

## File map (main-game/)

| Path | Role |
|---|---|
| `main.lua` | Entry point; bootstraps the screen manager. |
| `conf.lua` | LÖVE window / identity config. |
| `common.lua` | Shared utilities (screen transitions, drawing helpers). |
| `json.lua` | JSON parse/dump (vendored). |
| `save.lua` | Save/load persistence. |
| `music_mgr.lua` | Music/ambient management. |
| `screens/title.lua` | Title screen (logo, PLAY/OPTIONS/EXIT menu). |
| `screens/save_select.lua` | Save slot selection. |
| `screens/party_select.lua` | Build party before a run. |
| `screens/map.lua` | Overworld map; nav nodes; encounter triggers. |
| `screens/encounter.lua` | Combat screen entry. |
| `screens/sprite_dev.lua` | Sprite dev / debug viewer. |
| `encounter/` | Combat module (see below). |

### encounter/ module
- `encounter_mgr.lua` — encounter lifecycle.
- `entities.lua` — unit/enemy entities.
- `stats.lua` — stat definitions & math.
- `skills.lua` — skill definitions & effects.
- `combat.lua` — turn resolution.
- `anim.lua` — animation sequencing.
- `effects.lua`, `particles.lua` — VFX.
- `systems.lua` — subsystem wiring.
- `ui.lua` — combat UI (HUD, targets, log).

## Assets (main-game/assets/)
- `characters/<Name>/` — sprite sheets per character (Brigand, Champion, Duelist, Knight, Nomad).
  Frames: `Idle`, `Run`, `Attack1..3`, `Death`, `Take Hit`.
- `charicons/` — portrait icons.
- `enemies/` — enemy sprites.
- `icons/`, `images/` — map icons & UI images.
- `music/`, `sounds/` — audio.
- `vfx/` — effect sprites.
- `dedicool/` — `Dedicool.ttf` font (title ~50px, buttons ~16px at 800×450).

## Conventions
- **Coordinates:** always virtual pixels @ 800×450. The render canvas is 800×450,
  then scaled/letterboxed to the window. Don't read `love.graphics` window size for layout.
- **Palette:** crimson red = accent; off-red = hover; white = pressed/active; black bg.
- **Post-processing:** chromatic aberration + bloom via a shader pass on the render
  texture, applied globally, before blitting to screen. Values tuned on the title screen.
- **Boundaries:** `main-game/` and `prototype/` are independent — no shared state.
  `prototype/` holds self-contained experiments (currently `title_screen`, `save_select`, `shared/`).

## icon-making/
Standalone tool for generating map/character icons. `main.lua` is its entry; outputs
e.g. `mapicon-*.png`, `charicon/`. Treat as a separate mini-project, not part of the game.

## Reference material (external)
- Title screen visual reference: `reference-material/image.png` (4:3).
- Prior C++/raylib implementation: `C:\Users\Alex\projects\the-game\crimson-red_v2.0\src\main.cpp`
  (Windows path; a porting reference only).

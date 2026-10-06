# Crimson Red — Project Memory

## What this is
A 2D turn-based tactical/RPG game built in **LÖVE2D (Lua)**. Virtual resolution
**800×450 (16:9)**, letterboxed to a resizable window. The current focus is the
title screen → party select → map → encounter flow, with post-processing
(chromatic aberration + bloom) applied globally.

Full technical constants (palette, typography, layout, resolution rules) live in
[`CLAUDE.md`](CLAUDE.md) — read that first for anything visual or structural.
Detailed, on-demand specifics (how to run/test, asset conventions, file map) live in
[`memory/reference.md`](memory/reference.md).

## Code layout
- **`main-game/`** — the real integrated game. Entry: `main.lua` + `conf.lua`.
  - `screens/` — one file per screen (title, save_select, party_select, map, encounter, sprite_dev).
  - `encounter/` — combat module (anim, combat, effects, entities, skills, stats, systems, ui).
  - `assets/` — sprites, charicons, music/sounds, vfx, font (`dedicool/`).
  - Top-level helpers: `common.lua`, `json.lua`, `music_mgr.lua`, `save.lua`.
- **`prototype/`** — self-contained experiments, **no shared state** with `main-game`.
- **`icon-making/`** — tooling/art for generating map & character icons.
- **`captures/`** — screenshots from testing (git-ignored).

## How to run / test
```bash
cd main-game && love .
```
See `memory/reference.md` for the VM/capture workflow used during development.

## Top rules
1. **Never guess what an asset/text/number says.** Verify against the actual file or DOM; if a screenshot is blurry, re-capture magnified.
2. **`main-game/` and `prototype/` do not share state.** Don't reach across the boundary.
3. **All coordinates are virtual pixels at 800×450.** Don't hardcode screen sizes.
4. **Keep `AGENTS.md` lean.** Detail belongs in `memory/reference.md` and skills.

## Memory / token policy
- **`AGENTS.md`** (this file) — always on; keep short.
- **`CLAUDE.md`** — project technical constants (always on for this project).
- **`memory/reference.md`** — loaded on demand for run/test steps, file map, conventions.
- **`.dsh/skills/`** — project skills; load on use.
- **`captures/`** — screenshots saved during work (never `/tmp` or `~`).

## Accounts / logins
No external accounts are used by this project. If a workflow ever hits a
login / 2FA / CAPTCHA, **stop and hand it to the user** — never enter credentials.

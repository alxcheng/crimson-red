# Crimson Red — start here

Crimson Red is a 2D real-time party battler in **LÖVE2D (Lua)**, built as a "mod" of the
mobile game **Battleheart (BH)**: same systems (party of four, tap-to-target combat, gear,
skills, shop), new classes, enemies and structure (a floor map instead of BH's level list).

This file is the entry point for any agent. Read it fully, then follow the links you need.

## Who does what

- **Director = the user.** Their only job: playtest, report bugs and tweaks, and name new
  features. They talk only to the Lead.
- **Lead = you** (the agent in the main session). You turn the Director's words into scoped
  tasks, do them or delegate them, verify the result, and report back in plain language.
- **Workers = agents the Lead starts** for one scoped task each. They report to the Lead.

The loop: Director feedback → Lead triages and scopes → work is done → tests pass → Lead
tells the Director exactly what changed and what to try → Director playtests → repeat.
The step-by-step procedure is in [`docs/LEAD_PLAYBOOK.md`](docs/LEAD_PLAYBOOK.md).

## Where everything is

| You need… | Go to |
|---|---|
| How the Lead works: triage, task briefs, delegation, definition of done | [`docs/LEAD_PLAYBOOK.md`](docs/LEAD_PLAYBOOK.md) |
| What is done, what is in progress, what the Director has not yet seen | [`docs/STATUS.md`](docs/STATUS.md) |
| Known gaps and next work, in priority order | [`docs/BACKLOG.md`](docs/BACKLOG.md) |
| Decisions the Director has made (do not reopen them) | [`docs/DECISIONS.md`](docs/DECISIONS.md) |
| How the code is organised, file by file, and how to add things | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| **Anything about how Battleheart works** (formulas, numbers, behaviour) | [`bh/README.md`](bh/README.md) |
| Visual constants (resolution, palette, font) | [`CLAUDE.md`](CLAUDE.md) |

```
main-game/     the game (run from here)
  data/        WHAT exists: classes, enemies, abilities, items, talents, rewards (pure data)
  encounter/   the battle engine (how fights run)
  screens/     one file per screen (title, save select, map, party, equip, talents, shop, battle)
  *.lua        shared modules: common (drawing/UI helpers), save, items, progression, music
bh/            Battleheart reference library: decoded data + documented source
docs/          project docs (this table)
icon-making/   separate small tool that draws the map/character icons
captures/      screenshots from test runs (not in git)
```

## Running and testing

```bash
./playtest         # run the game (for the Director)
./test_headless    # battle-engine smoke test          -> HEADLESS_PASS, exit code 0
./test_ui          # drives every screen + full battles -> UI_SMOKE_PASS, exit code 0
```

- **Run both tests after every change and read the exit code** (`echo $?`), not just the last
  line. A change is not done until both exit 0.
- `./test_ui` saves screenshots (it prints the folder). Copy them to `captures/ui_smoke/` and
  **look at them** when you changed anything visual.
- Both tests briefly open a game window; `./test_ui` takes a few minutes. Neither touches real
  save files.
- This machine has no standalone `lua`; the tests are also the syntax check.

## Rules

1. **Never guess.** A BH number or behaviour comes from `bh/` (cite the file). A Crimson Red
   value we invented is tagged `[tuned]` in a comment. If you cannot find something, say so.
2. **Data in `data/`, logic in the engine.** Adding a class, enemy, ability or item is a data
   edit. If you find yourself writing `if class == "knight"` in engine code, stop.
3. **All coordinates are virtual pixels on an 800×450 canvas.** A unit's position is its
   CENTER; its feet are at `position.y + size.h / 2`.
4. **The shared resource bar (max 50) stays.** It is a deliberate difference from BH.
5. **Do not reopen `docs/DECISIONS.md`.** If a decision blocks you, tell the Director.
6. **Keep the docs true.** When work lands, update `docs/STATUS.md` and `docs/BACKLOG.md` in
   the same change. Do not create new planning files; these are the only ones.
7. **Git:** work on a branch, small commits with clear messages, never push or merge to
   `master` unless the Director says so.
8. **Never enter passwords, 2FA codes or CAPTCHAs.** Hand those to the Director.

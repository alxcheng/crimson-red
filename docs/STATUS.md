# Status — the living record

Update this whenever work lands. Keep it short: move finished detail to git history.

**Branch:** `refactor` (off `master` @ 76a228d). Nothing here is merged or pushed.
**Tests:** `./test_headless` PASS, `./test_ui` PASS (as of 2026-10-08).

## What the game is right now
Title → save select → map (one hand-made forest floor) → battles on encounter tiles, a shop
tile, and PARTY / TALENTS / EQUIP screens from the map's top bar. A new game starts with a
Knight and a Cleric, 15 gold, and Battleheart's numbers throughout. Nine classes can fight
(knight, brigand, champion, duelist, nomad, cleric, paladin, wizard, rogue); one enemy type.

## Done on this branch (newest first)
- **Second playtest round (2026-10-08)**: auto-attack cooldowns were never applied (units
  swung every ~0.4 s) — fixed, intervals are now BH's and one knob scales them all
  (`AUTO_COOLDOWN_SCALE` in `encounter/abilities.lua`); attack-speed stat (`ATK_SPEED`) that
  only shortens the interval; uniform hero move speed; slower attack frames; costs in whole
  bars (BH abilities `cd // 10`, default 3 bars / 15 s); move orders interrupt immediately
  (`skills.interrupt`); BH's "hold position" rule so a hero and the enemy attacking it stop
  shuffling around each other.
- **Battleheart numbers adopted**: derived hero stats (class base + scale × level + gear +
  talents), BH's 132-item catalog with class restrictions, loot-table shop stock, BH XP curve
  and per-floor rewards, hiring (10 gold × level, recruit joins with starter gear), BH goblin
  as the enemy, BH attack intervals.
- **Combat engine restructured**: content moved to `data/`; one `createHero`/`createEnemy`;
  one documented world definition; legacy shims and dead code removed.
- **Battleheart reference library** (`bh/`): the whole game database and every script
  component's values decoded from the APK; 14 documents covering all of BH's source.
- **Bugs fixed along the way**: talents screen crashed on first draw; talent picks never
  registered; nobody could ever level up (no XP existed); SPACE pause never worked; shop could
  not be re-entered; melee units assigned to outer/right ring slots never moved; ability tags
  were dropped so Knight Rage and Paladin Wrath never triggered; WARD never rolled; chain
  lightning hit harder than the main hit; pause state leaked into the next battle.
- **Test harness**: `./test_ui` drives every screen and plays full battles.

## Needs the Director's eyes (not yet playtested)
Everything above. In particular, choices the Lead made that the Director has not confirmed:
1. **Starting party is Knight + Cleric** and the other heroes must be hired (old saves keep all).
2. **Classes without a BH original borrow BH base stats**: champion ← Barbarian, duelist ←
   Monk, nomad ← Bard, brigand ← Rogue (`data/classes.lua`).
3. **Hire rule**: the recruit joins one level below your best hero; cost 10 × (that level + 1).
4. **Floor-1 battle pacing**: waves of at most 2 goblins, 12 kills to win. With attack
   intervals now real, the test bot needs ~6.5 minutes with the starting pair — probably too long. Set in `screens/encounter.lua` (`waveMaxThreat`, `encounterGoal`).
5. **Talent bonuses** keep their old sizes except HP, which was multiplied by 10 to match BH's
   ~1000-HP heroes (`data/talents.lua`).
6. **Stagger** (knock-down) now triggers after a unit takes half its max HP (`encounter/stats.lua`).
7. Old item instances in existing saves are dropped on load (they predate the BH catalog).
8. **Hero move speed is 2.4** (72 px/s). The Director said "80% of the BH value"; BH heroes range
   1.3–1.65 units/s, so this takes BH's standard 1.5 at the old ports' 2× conversion (3.0) × 0.8.
9. **Knight and Nomad abilities now use the default 15 s / 3 bars** (were 10 s / 4 bars);
   Spark of Inspiration stays free.

## Director said (verbatim, newest first)
- 2026-10-08: "I want to set up a workflow in which the main thing I have to do (my only job
  if you will) is to provide feedback (bugs and tweaks) from playtests and provide new features
  to be implemented." / "go file by file and refactor it to remove unnecessary portions and
  things that obviously are inefficient" / "make the structure of this project … understandable
  to a less-powerful model Lead".
- Earlier: "core bug — if I quit, the encounter is checked completed" (fixed bb7866a);
  "get rid of the helper text on the bottom" (done); "use the simple database like in BH" (done).

## Not reviewed in the refactor pass
These files work and are covered by `./test_ui`, but were only lightly read, not cleaned up:
`screens/title.lua`, `save_select.lua`, `map.lua`, `party_select.lua`, `sprite_dev.lua`,
`encounter/ui.lua`, `anim.lua`, `particles.lua`, `music_mgr.lua`. See BACKLOG "Cleanup".

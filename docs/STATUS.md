# Status — the living record

Update this whenever work lands. Keep it short: move finished detail to git history.

**Branch:** `refactor` (off `master` @ 76a228d). Nothing here is merged or pushed.
**Tests:** `./test_headless` PASS, `./test_ui` PASS (as of 2026-10-09).

## What the game is right now
Title → save select → map (one hand-made forest floor) → battles on encounter tiles, a shop
tile, and PARTY / TALENTS / EQUIP screens from the map's top bar. A new game starts with a
Knight and a Cleric, 15 gold, and Battleheart's numbers throughout. Nine classes can fight
(knight, brigand, champion, duelist, nomad, cleric, paladin, wizard, rogue); one enemy type.

## Done on this branch (newest first)
- **BH battles, rewards, shop, enemies, recolours (2026-10-09)**:
  - *Enemies*: goblin (BH bat stats), bat (BH skeleton-archer stats: ranged, stands still,
    random target each shot, fades in inside the arena), mushroom (BH ogre stats). The
    skeleton keeps BH's goblin stats. `data/enemies.lua`.
  - *Spawning*: BH's wave rules (`encounter/encounter_mgr.lua`) fed by a procedural generator
    (`encounter/wave_gen.lua`). Battles get harder one by one (`progression.battleTier`).
  - *Victory*: VICTORY -> SPOILS (gold, one item) -> EXPERIENCE (per-hero XP, bars, level-ups);
    BH's loot roll and XP split incl. best-performer bonus (`encounter/victory.lua`,
    `progression.onEncounterWon`). Gold no longer has the +1 per kill.
  - *Shop*: up to 6 small slots (BH stock rule: 3-6 random items, duplicates possible), select
    then BUY/SELL; the inventory panel is the same one as on EQUIP (`item_ui.drawInventory`).
    Inventory holds 35 items.
  - *Recolours*: `./recolor` shifts one colour of a sprite folder; Cleric / Paladin / Wizard /
    Rogue are now recoloured Knight sheets instead of whole-sprite tints.
- **Menu clean-up (2026-10-09)**: the description bars at the bottom of TALENTS, SHOP and EQUIP
  are gone; details now show in a hover tooltip (`common.drawTooltip`), as on the PARTY screen.
  The back arrow is the word BACK everywhere. All menu screens share one top bar
  (`common.drawTopBar`) and the same 20 px margins; text that used to spill out of its box
  (sell-list names, hire stats, party slot numbers, talent names) is fitted. See "Menu screen
  conventions" in `docs/ARCHITECTURE.md`. New shared `item_ui.lua`. `./test_ui quick` added.
- **Dragged-duellist bug (2026-10-09)**: a unit standing on its slot was re-snapped to it every
  frame, so it rode along with a walking target (even while knocked down). Now it snaps once
  on arrival and knocked-down/stunned units do not follow (`systems.targetFollow`).
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
4. **Battle size and difficulty** come from the wave generator's first-guess numbers
   (`TUNING` in `encounter/wave_gen.lua`): 5 waves, ~8-10 enemies in the first battle; the bat
   appears from the 2nd battle of a floor, the mushroom from the 3rd.
5. **Talent bonuses** keep their old sizes except HP, which was multiplied by 10 to match BH's
   ~1000-HP heroes (`data/talents.lua`).
6. **Stagger** (knock-down) now triggers after a unit takes half its max HP (`encounter/stats.lua`).
7. Old item instances in existing saves are dropped on load (they predate the BH catalog).
8. **Spark of Inspiration (Nomad) is free** (0 bars, 15 s cooldown): it trades HP for
   resource, so a bar cost would cancel it out. Every other Knight/Nomad ability is 15 s / 3 bars.
9. **Battle tier = how many encounters you have entered on the floor** (1st battle easiest).
   It also picks the BH reward row, so later battles pay more gold / XP and drop better items.
10. **The CR goblin walks in from the right edge** like the skeleton, although the BH bat whose
    stats it has appears inside the arena; only the CR bat (ranged) appears inside.
11. **Shop is select-then-BUY/SELL** (one button at the bottom of the left panel), and the
    inventory is capped at 35 items (BH: 20); a won battle's item is lost if it is full (BH rule).
12. **Recolour choices**: Cleric yellow, Paladin green, Wizard purple, Rogue dark red.

Confirmed by the Director (2026-10-09): hero move speed 2.4 (`HERO_MOVE_SPEED`); Knight and
Nomad abilities on the 15 s / 3 bar default.

## Director said (verbatim, newest first)
- 2026-10-09: "Look in Battleheart for feature implementations like how enemies spawn and also
  the victory screen which shows you getting 1 item and coins as well as experience for the
  whole party" / "more things should be sold in the shop ... around 6 slots (not large boxes),
  on the left, and your inventory on the right that looks the same as the equip screen" /
  "Map BH bat stats to CR goblin, and BH skeleton archer to CR bat ... BH ogre stats to CR
  mushroom" / "work on a procedural enemy spawning system" / "reusing sprites for characters
  ... targeting a specific color and then shifting the color instead of a whole tint shift".
- 2026-10-09: "Remove description text at the bottom of talents, shop, and equip and put it as
  hover text similar to the party screen when members are hovered" / "go through each screen
  (encounter looks fine) and fix text clipping issues / also make it so that the dimensions
  look clean" / "change the back arrow just to be BACK in text".
- 2026-10-09: "two 'duelling' units were glued together, and when one of them was staggered,
  they got 'dragged' with the other one moving to a new movement target" (fixed a37d35c).
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

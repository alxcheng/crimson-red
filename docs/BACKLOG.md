# Backlog — known gaps and next work

Ordered by how much each one hurts a playtest. Each item says where to look. When you finish
one, delete it here and add a line to `docs/STATUS.md`. New Director feedback goes to the top
of the right section.

## A. Blocks or breaks a playthrough
1. **Floors never advance.** `saveData.floor` is always 1 and there is one hand-made map
   (`RAW_MAP` in `screens/map.lua`). Nothing happens when every encounter is cleared.
   Needs a Director decision on what a "floor clear" is, then: floor +1, new map. (Battles
   already get harder one by one within the floor: `progression.battleTier`.)
2. **Idle heroes do not pick targets.** A hero only fights when ordered or when hit. BH heroes
   auto-acquire nearby enemies (`bh/systems/party-member-stats-ai-damage.md` §7 "Idle").
   Code: `encounter/systems.lua` (`threat`, `targetFollow`).
3. **Four heroes cannot fight**: hunter, jester, piper, witch have no row in `data/classes.lua`
   (they are never offered for hire; in old saves selecting one fields nobody). Port them
   (BH Ranger, —, Bard, Witch: `bh/systems/hero-abilities-part1.md` / `part2.md`) or remove them.

## B. Makes the game shallow
5. **Four enemy types; BH has 30** (`bh/data/prefabs/EnemyScript.json`, behaviour in
   `bh/systems/enemy-*.md`). Not ported yet from BH's first map: basic5 (skeleton warrior),
   basic6 (goblins entering from the left: `spawn = "left"` already works), basic7 (healer that
   teleports), basic8 (cyclops), and the bosses. Add rows to `data/enemies.lua`.
5b. **The ranged enemy (bat) draws no projectile** — its target just takes the hit. Same for
   the Wizard. Needs the projectile renderer of item 12.
5c. **Wave generator tuning is a first guess** (`TUNING` in `encounter/wave_gen.lua`, `danger`
   and `minTier` in `data/enemies.lua`). Adjust from playtests.
6. **Ported ability numbers are still estimates.** Cooldowns match BH; magnitudes and
   durations in `data/abilities.lua` (Cleric, Paladin, Wizard, Rogue) are the old wiki/tuned
   guesses. Exact values: `bh/data/prefabs/MotherBrain.json` (`buffMagnitudes`, `buffDurations`,
   `debuffMagnitudes`, `debuffDurations`) + the per-ability specs in `bh/systems/hero-abilities-part1.md`
   / `part2.md`. Do one class at a time; several abilities are approximations of BH behaviour
   (Divine Intervention, Aura of Light, Wrath, Vengeful Angel) and need new effect kinds.
7. **Ten trinket effects are not implemented**, so those trinkets are never sold: cooldown,
   regen, moveSpeed, ward, haste, noCooldown, bonusGold, bonusXP, lifeDrain, bonusHealing.
   Add each to `TRINKET_STATS` in `items.lua` once the engine supports it
   (rules: `bh/systems/party-member-stats-ai-damage.md` §4.2).
8. **No item upgrades.** BH lets you upgrade gear in the Armory for 1.5 x the upgraded item's
   price (`bh/systems/menu-armory-and-merchant.md`). `data/bh_items.lua` already has `upgrade` ids.
8b. **Shop has no better/worse arrows.** BH shows, per party hero, whether the selected item
   beats what they wear (`bh/systems/menu-armory-and-merchant.md` 3.5). The tooltip only says who can use it.
9. **BH has two trinket slots; we have one** (`equipped.trinket`).

## C. Feedback and feel
10. **Gold is only visible in the SHOP and on the victory screen.** Show it on the map bar.
11. **EQUIP needs two clicks** (item, then slot). Consider one click to equip into the item's slot.
12. **Ability visuals are missing**: projectiles, meteor, blizzard tint, time-stop pulse,
    heal/shield indicators. The logic exists; only presentation is missing. (Director asked
    for this earlier and it was deferred.)
14. **OPTIONS on the title screen does nothing yet** (DEV TOOLS opens the sprite viewer, which
    predates `./align_sprites` and still has its own hand-typed numbers - update or remove it).
14a. **The 5th and 6th melee attackers on one target cannot reach it**: slot ring 3 is outside
    `combat.checkMeleeRange`. Only matters with more than 4 attackers on one unit.
14c. **The map's fog tiles and the battle HUD were not part of the red/white palette pass**
    (the map fades "?" tiles by distance; battle bars are green/yellow).

## D. Cleanup (safe, good first tasks)
15. **Duplicate hero-icon loader.** Each of `screens/equip.lua`, `shop.lua`, `talents.lua`,
    `party_select.lua` loads and draws `assets/charicons/icon-<class>.png` itself. Move one
    copy into `common.lua`. (Names, item tokens, tooltips and the top bar are already shared.)
16. **Finish the file-by-file pass** on the files listed at the bottom of `docs/STATUS.md`.
17. **Unused stats.** `RES`, `BOOST`, `CRIT_DEF` in `encounter/stats.lua` are barely used;
    decide whether BH's model needs them and remove what it does not.
18. **Tests flash a window.** LÖVE 11 cannot run without one; see if `conf.lua` can position
    or minimise it during tests.
19. **Remove the debug key** `K` (spawns a skeleton) from `screens/encounter.lua` before release.

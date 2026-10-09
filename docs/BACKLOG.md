# Backlog — known gaps and next work

Ordered by how much each one hurts a playtest. Each item says where to look. When you finish
one, delete it here and add a line to `docs/STATUS.md`. New Director feedback goes to the top
of the right section.

## A. Blocks or breaks a playthrough
1. **Losing a battle never ends it.** If every hero dies the fight just sits there (ESC
   retreats). Add a defeat sequence and decide what defeat costs.
   BH: `bh/systems/battle-end-rewards-xp-loot.md` (`defeatSequence`). Code: `screens/encounter.lua`
   next to the victory branch; `encounter_mgr.checkVictory`.
2. **Floors never advance.** `saveData.floor` is always 1 and there is one hand-made map
   (`RAW_MAP` in `screens/map.lua`). Nothing happens when every encounter is cleared.
   Needs a Director decision on what a "floor clear" is, then: floor +1, new map, harder waves.
3. **Idle heroes do not pick targets.** A hero only fights when ordered or when hit. BH heroes
   auto-acquire nearby enemies (`bh/systems/party-member-stats-ai-damage.md` §7 "Idle").
   Code: `encounter/systems.lua` (`threat`, `targetFollow`).
4. **Four heroes cannot fight**: hunter, jester, piper, witch have no row in `data/classes.lua`
   (they are never offered for hire; in old saves selecting one fields nobody). Port them
   (BH Ranger, —, Bard, Witch: `bh/systems/hero-abilities-part1.md` / `part2.md`) or remove them.

## B. Makes the game shallow
5. **One enemy type.** BH has 30 (`bh/data/prefabs/EnemyScript.json`, behaviour in
   `bh/systems/enemy-*.md`). Bat, Imp and Mushroom sprites already exist in `assets/enemies/`.
   The spawner (`encounter/encounter_mgr.lua`) only uses the first `SPAWN_POOL` entry — make it
   pick by danger budget, or port BH's authored waves (`bh/data/maps.json`).
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
8. **No loot and no item upgrades.** BH gives one item per win (`bh/systems/battle-end-rewards-xp-loot.md`)
   and lets you upgrade gear in the Armory for 1.5 × the upgraded item's price
   (`bh/systems/menu-armory-and-merchant.md`). `data/bh_items.lua` already has `upgrade` ids.
9. **BH has two trinket slots; we have one** (`equipped.trinket`).

## C. Feedback and feel
10. **No feedback for rewards.** Gold shows only in the SHOP; nothing announces gold, XP or a
    level-up after a win. Show gold on the map bar and a results panel on victory
    (`progression.onEncounterWon` already returns `{gold, levelUps}`).
11. **EQUIP needs two clicks** (item, then slot). Consider one click to equip into the item's slot.
12. **Ability visuals are missing**: projectiles, meteor, blizzard tint, time-stop pulse,
    heal/shield indicators. The logic exists; only presentation is missing. (Director asked
    for this earlier and it was deferred.)
13. **Movement speeds are not BH's.** BH speeds are in world units/second
    (`bh/data/prefabs/PartyMember.json` `moveSpeed`); pick a pixels-per-unit factor first.
14. **OPTIONS on the title screen opens the developer sprite viewer.**
14b. **Long item names overlap the price in the SHOP sell list** (e.g. "Swordsman's Gauntlet").
    Truncate or shrink the name in `drawSellSection` (`screens/shop.lua`); check the screenshot
    `shop-rich-1-enter.png` from `./test_ui`.

## D. Cleanup (safe, good first tasks)
15. **Duplicate UI helpers.** `displayName` and the hero-icon loader are copied in
    `screens/equip.lua`, `shop.lua`, `talents.lua`, `party_select.lua`; item glyph/colour code
    in `equip.lua` and `shop.lua`. Move one copy of each into `common.lua` and use it everywhere.
16. **Finish the file-by-file pass** on the files listed at the bottom of `docs/STATUS.md`.
17. **Unused stats.** `RES`, `BOOST`, `CRIT_DEF` in `encounter/stats.lua` are barely used;
    decide whether BH's model needs them and remove what it does not.
18. **Tests flash a window.** LÖVE 11 cannot run without one; see if `conf.lua` can position
    or minimise it during tests.
19. **Remove the debug key** `K` (spawns a skeleton) from `screens/encounter.lua` before release.

# Battleheart reference library (`bh/`)

Crimson Red is built as a "mod" of Battleheart (BH): same systems, new content. This folder is
the complete, verified knowledge of how BH works, extracted from the game's APK. **Look here
before porting, tuning or debating any BH mechanic. Do not guess and do not re-derive.**

Everything here is either decoded data (exact) or documentation with `[IL Lnnnn]` line citations
into the decompiled source. Older research in `docs/archive/` is superseded and contains known
errors — where it disagrees with `bh/`, `bh/` wins.

## 1. Data — exact values decoded from the game files

| File | What it holds |
|---|---|
| `data/items.json` | All 132 items: name, type, `power`, `upgrade` (id of the upgraded item), `sellPrice`, `usableBy` (per class), model. Array index = item id. |
| `data/classes.json` | The 10 hero classes: `powerScale`, `defenseScale`, `healthScale`, and 12 powers each (name, description, cooldown). |
| `data/party.json` | The 14 recruitable heroes: class, level, starting gear, base power/defense/health. |
| `data/maps.json` | 4 maps → levels → waves (spawn timing, enemy ids), gold/XP rewards, loot table, arena thresholds. |
| `data/loot_tables.json` | 9 loot tables (item ids, level range). |
| `data/globals.json` | XP curve (`firstLevelXP`, `XPtable`), starting gold/party, flags. |
| `data/prefabs/EnemyScript.json` | All 30 enemy types: `maxHealth`, `power`, `AIType`, `moveSpeed`, `likeABoss`, `specialMoves` cooldowns, spawn style, death type… Object name = `<enemySet><N>`, matching `Level.enemySet` + enemy id in `maps.json`. |
| `data/prefabs/PartyMember.json` | Per-hero battle tuning: `primaryActionCooldown` (attack interval), `meleeOffset` (wind-up), `moveSpeed`, `impactForce`, `AIType`, crit… |
| `data/prefabs/MotherBrain.json` | Battle director settings, including the **buff/debuff tables**: `buffMagnitudes`, `buffDurations`, `debuffMagnitudes`, `debuffDurations` (indexed by buff/debuff id). |
| `data/prefabs/EffectScript.json` | All 110 projectile/area-effect prefabs: speed, lifetime, damage modifier, applied debuff, flags. |
| `data/prefabs/*.json` (others) | Every other script component in the game (menus, pet, UI text…). |

Regenerate with `python3 bh/tools/extract_database.py` and `python3 bh/tools/extract_prefabs.py`
(both self-validating: they fail loudly rather than write wrong numbers).

## 2. Systems — how the code behaves

| Question | Read |
|---|---|
| How are a hero's stats built (level, class scale, gear, trinkets, passives)? How does a hero take damage, get healed, pick targets, move? | `systems/party-member-stats-ai-damage.md` |
| Basic attacks: timing, damage, crits, per-class differences | `systems/party-member-basic-attacks.md` |
| Every active ability (Cleric, Knight, Rogue, Wizard, Witch) | `systems/hero-abilities-part1.md` |
| Every active ability (Witch Hex, Bard, Barbarian, Monk, Ranger, Paladin) | `systems/hero-abilities-part2.md` |
| Projectiles, area effects, ranged damage; save/load; merchant stock; the Ranger's pet; small classes | `systems/effects-database-pets-misc.md` |
| Enemy behaviour: melee, ranged, first two bosses | `systems/enemy-ai-part1.md` |
| Enemy behaviour: spider boss, healers, ooze, golem, lich | `systems/enemy-ai-part2.md` |
| Enemies taking damage, melee slot positions around a target, spawning | `systems/enemy-combat-and-spawn.md` |
| Enemy attack sequences, deaths, boss sequences | `systems/enemy-attacks-death-bosses.md` |
| Battle setup, touch controls, wave spawning | `systems/battle-director-setup-input-spawning.md` |
| Victory/defeat, gold, XP and level-ups, loot rolls, arena scaling | `systems/battle-end-rewards-xp-loot.md` |
| Town menu states, inventory/equipment display, stat display formulas | `systems/menu-core-and-inventory-display.md` |
| Armory (equip/upgrade) and Merchant (buy/sell, prices) | `systems/menu-armory-and-merchant.md` |
| Academy (skill ladder), Tavern (hiring), world map, Keep (party/reserves), save slots | `systems/menu-academy-tavern-map-keep.md` |

Need something not covered? Find the method in `index/methods.md` (every class and method with
its line range), read that range of the IL, and follow `HOW_TO_READ_IL.md`. Add what you learn to
the matching `systems/` doc.

## 3. Conventions that trip people up

- **`characterClass` is 1-based; `classes.json` ids are 0-based.** Class N in code = `classes.json[N-1]`
  (1 Cleric, 2 Knight, 3 Rogue, 4 Wizard, 5 Witch, 6 Bard, 7 Barbarian, 8 Monk, 9 Ranger, 10 Paladin).
- **Powers:** each class has 12 (`whichPower[0..11]`). Unlock levels: 1 → power 0; 5 → 1 or 2;
  10 → 3 or 4; 15 → 5 or 6; 20 → 7 or 8; 25 → 9 (automatic); 30 → 10 or 11. Powers with
  `cooldown > 0` are active abilities, the rest are passives.
- **`passives[k]`** = +1 (first of the pair), −1 (second), 0 (none yet). `party.json`'s `passives[2]`
  is ignored; the game recomputes it as `level >= 25`.
- **Enemy id N** in a wave = prefab `<Level.enemySet><N>` (e.g. `basic1`), found by object name in
  `data/prefabs/EnemyScript.json`.
- **Prices:** shop buy price = `sellPrice`; selling pays `sellPrice / 2`; upgrade cost =
  round(1.5 × `sellPrice` of the upgraded item). Hire cost = 10 × the hero's level.
- **Chance rolls** use `Random.Range(0,100) <= chance`, so the real chance is `chance + 1` percent.
- **Enemies have no defense stat.** Only heroes subtract defense; minimum damage to a hero is 3.
- BH distances are Unity world units (melee reach 1.8). Crimson Red uses 800×450 virtual pixels —
  convert deliberately and record the factor you used.
- Statements marked `UNVERIFIED` in a systems doc are inferences. Where a doc says a value was
  "Inspector data, not in the IL", it is now in `data/prefabs/` (those docs were written before
  the prefab extraction).

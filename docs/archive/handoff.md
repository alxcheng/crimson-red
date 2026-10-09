# Crimson Red — Handoff / Compaction (seed for a cloned Manager or post-compact resume)

## Role & loop
Manager (Lead) of a playtest loop: Director (user) gives features/feedback -> Manager scopes & delegates -> dev teammates implement -> playable build -> Director playtests -> iterate. Director talks only to the Manager. CR = LÖVE2D "mod" of Battleheart: same systems, new content. KEEP the shared Clash-Royale resource bar (max 50) — deliberate deviation.

## What exists (commit 36e7113, branch master)
- Encounter P0 foundation (verified ./test_headless PASS): two-stage damage (combat.roll -> combat.resolve; enemies no defense), indexed statuses incl SLOW/SHIELD/DOT-ticks/PARALYZE, 6-slot ring formation, data-driven abilities, pay-at-press queueing, per-unit EXEC_GATE=0.4.
- 4 ported BH classes (Cleric/Paladin/Wizard/Rogue) — proof-of-port, recolored Knight frames; Cleric NO auto-attack; Paladin specials + Rogue multipliers are approximations; Meteor x2.0.
- Party select: click-to-move (verified by code read, NOT yet by Director playtest).
- 3 integration lines wired (commit 94a6e99, headless PASS): SLOW now actually slows movement (systems.moveTarget × status.getSlowFactor), SHIELD now actually reduces incoming damage (combat.resolve × shieldReduction, before min-3 floor), activation camera-punch fires on active-ability activation (skills.lua → combat.triggerActivationVFX). Also dropped unused TOPUP_FRAME local in headless_test.lua.
- Headless: ./test_headless at project root; env CR_HEADLESS/CR_TEST_MODE/CR_TEST_SCENE=headless; never open windows on Director screen; visible path byte-identical without flags.
- Research: work/battleheart-encounter-parity.md + work/non-encounter-systems-research.md (IL-verified mechanics, divergence plan, Director Qs in §7).
- [DONE @ 198e6c9] Center-Y alignment fix: unified moveTarget to center-coord convention (targetFollow/moveTarget/right-click/walk-in) — fixed infinite-repositioning + vertical drift. Director: "basically fixed."
- [DONE @ be9a043] Alignment streamlining (P0+P1+P3) mirroring BH (IL-verified): P0 combat.lua checkMeleeRange now size-aware (per-attacker reach 6+0.25*w vs horizontal body gap + flat 18px center-Y band, was size-blind dx<=6/dy<=2); P1 systems.lua slotGroundPoint scales the 6-slot ring by target width (1+0.5*max(0,(w/2-22.5)/22.5), scale>=1 so normal units byte-identical, bigger targets wider ring → melee stand flush outside boss); P3a targetFollow snaps to exact slot center on arrival (kill micro-osc, BH 0.07-settle analogue); P3b physics bottom feet clamp tightened 12px inset both sides. Headless PASS (errors=0). BH alignment model detail: work/ + Hindsight doc "BH combat alignment model (IL-verified)".
- [DONE @ f76eeaf] Anti-clumping straddle (BH parity): 2nd+ melee attacker now prefers the OPPOSITE side of the first occupant so two attackers straddle the target (one left/one right) instead of clumping on one side; 3rd+ load-balances to the less-populated side; 1st attacker byte-identical (X-based). systems.lua requestPosition rewritten + fillSide/firstOccupantSide helpers; mirrors BH EnemyScript::requestPosition 2nd-attacker branch (IL L20452-20489). Headless PASS (errors=0).
- [DONE @ 36e7113] Full class-kit effects via BH-style DATA-DRIVEN ability DB (Director: "use the simple database like in BH"). Every class ability is now pure declarative data in M.DB — ZERO kind=custom/fn closures (mechanics live in the resolver, like BH's Power/buffMagnitudes model). abilities.lua resolver: added kinds effects (list-of-primitives), healGroup, healLowestAlly, stunAll, drainHp, resourceGain; damage += buffMods/knockback/chain; aoe += centerSelf/alsoStatus/alsoKnockback; helpers _statusIndex/_applyChain/_applyKnockback. Added 5 new data-row abilities: ClericVengefulAngel, PaladinWrath (chain-lightning imbue via new CHAIN status), WizardConflagrate (burn DoT+stun), WizardThunderbolt (self-centered blast+knockback, DEFINED but not slotted), RoguePoisonedKnife (throw+poison DoT). Kits re-slotted to auto+4 actives (cleric/paladin/wizard/rogue); UI already maps q/w/e/r→slots1-4, buildClassSkills wires slot 4. status.lua += CHAIN buff idx 10 + extra param on apply. combat.lua += data-driven chain-consume hook in registerHit (melee hit + active CHAIN -> arc N nearest, consume charge). Approximations: Challenging Shout threat fixed 240 (was ATK-scaled), Mend Wounds flat 7.5HP/s (was ATK-tracked), Wrath charge-counted ~10s (not strict timer). DEFERRED (5-slot limit): Paralytic Knife, Paladin Radiance. Headless PASS (errors=0). NOTE: headless only presses slots 1-3; the new 4th-slot abilities verified by load-cleanliness + shared-path coverage, not a live press.

- [DONE @ 9887b80] VFX shake retune: removed per-hit screen shake on Wizard auto-attack fireball (vfx=true→false in abilities.lua WizardAutoFireball); added shake on EVERY valid ability press (skills.lua M.enqueue → combat.triggerActivationVFX +6). Activation-time punch kept as follow-through.
- [DONE @ 6725691→bb7866a] Pause = SPACE ONLY (P removed): encounter.lua keypressed `if key==" "` (top-right pause icon still works). Removed the bottom in-battle help-text line entirely (Director: "get rid of the helper text on the bottom").
- [DONE @ bb7866a] Encounter autosave bug fix (Director: "core bug — if I quit, the encounter is checked completed"). Root cause: map.lua autosaved player.col/row on EVERY move incl. when the player was standing ON an encounter tile (popup open, not engaged); a later quit/relaunch re-armed the popup from that saved position and the tile got recorded cleared. Fix: decoupled movement data from a visual-only `standingOnEncounter` flag (never saved). tryMove onto an encounter sets the flag and SKIPS the autosave (last OFF-tile position is what persists); onEnterPress only records clearedEncounters + saves + launches on an actual ENTER-on-encounter press (else just resets autosave to the last safe position); onEnter re-engages the popup if a pre-fix save records the player on an encounter tile (no more ghost encounter). Headless PASS (errors=0). NOTE: map screen is not covered by headless — verified by structural read, not a live Director playtest yet.

## Non-negotiable conventions
1. Feet-aligned: center stored, feet = pos.y+h/2.
2. Pay-at-press: cd+resource at press; activate front-of-queue + in-range + free; dead target dropped, NO refund.
3. Anim/timing pipeline untouched while porting data.
4. Resource bar max 50.
5. Never guess values; tag [IL]/[wiki]/[tuned].
6. No Lua interpreter on machine: structural checks + careful reads.
7. Member cap 8, ALL SEATS FILLED & IDLE: battleheart-research, savescreen-dev, damage-dev, status-dev, formation-dev, ability-dev, class-research, status-dev2. No kill/delete tool from Lead seat; reuse via send_message; seats clear only on session restart. Don't edit a file an agent owns concurrently (FS_STALE_VERSION churn lesson).

## Open items
- Playtest pending: (a) SPACE-pause + no helper text, (b) encounter autosave fix (quit no longer marks encounter cleared; switching screens w/ popup open no longer loses it), (c) the 4 NEW 4th-slot abilities (VengefulAngel/Wrath/Conflagrate/PoisonedKnife) live-pressed.
- [DEFERRED — not queued, needs Director go-ahead] Ability VFX/visuals (the "implement the effects" follow-up): fireball projectile, meteor fall+impact, blizzard frost tint, time-stop pulse, heal/shield/expose indicators, group-heal ring, paladin glows. Data/logic layer is DONE (36e7113); visuals largely are NOT.
- BH DB VALUES PERMANENTLY UNEXTRACTABLE from current datamine (no AssetBundles present; dump census VFX/sprites/audio only at <datamine>/decompiled/resources/assets/bin/Data/_bh_extract_out/json/). Do NOT retry extraction there. Values stay [wiki]/[tuned] until a new source (APK with .assets bundles, or Legacy files). .NET runtimes installed: ~/.dotnet (arm64) + ~/.dotnet-x64 (x86_64 under Rosetta).
- Director decisions queued (non-encounter report §7): floors replace levels (default yes)? lean item catalog 3 grades/~15 (yes)? hire flat-per-floor vs 10xlevel? choice every 3 vs 5 levels? per-kill gold drip 1-2? stable seed per floor number?
- [DONE @ 94a6e99] 3 flagged integration lines now wired (verified 21345e0 → fixed 94a6e99, headless PASS): SLOW→moveTarget, SHIELD→combat.resolve (before min-3 floor), activation camera-punch on active-ability activation. Previously: flagged unwired, never confirmed.
- Trivial leftovers: TOPUP_FRAME unused local headless_test.lua L83.

## Key files
main-game/encounter/{combat,status,systems,skills,abilities,entities,anim,effects,stats,ui}.lua; screens/{title,save_select,party_select,map,encounter,sprite_dev,equip,talents,shop}.lua; main-game/items.lua (NEW economy foundation); conf.lua + main.lua (headless gates); headless_test.lua; playtest; test_headless; AGENTS.md; memory/reference.md; work/*.md. Datamine: /Users/alexcheng/CascadeProjects/Battleheart datamine (il/Assembly-UnityScript.il = 108k-line truth source for mechanics).

## HANDOFF — BH Town-Menu Port (Party/Equip/Shop/Talents) — Leader transition @ 2025-10-08
> **For the incoming Lead.** The prior Lead is handing off mid-task. Everything below is on
> disk; nothing of this work is committed yet. Read top-to-bottom.

### Director's locked decisions (honour these; they OVERRIDE the old research-doc "fold into one shop")
1. Build order Phase 0 (economy) -> 1 PARTY -> 2 EQUIP -> 3 SHOP -> 4 TALENTS, each a playable, committed step.
2. Lean item catalog: 3 grades, ~12–15 items.
3. TALENTS = **linear per-class level LADDER**, binary choice **every 3 levels**, ±1 passives. **NO point-spend tree.**
4. SHOP = **dedicated full screen** (not a map overlay); reached via an encounter-style popup on the map `S` tile. **HIRING is a separate tab** in the shop (1 random party member for sale). **Shop resets/restocks after every WON encounter.**
5. CR names: KEEP->**PARTY**, ARMORY->**EQUIP**, ACADEMY->**TALENTS**, MERCHANT->**SHOP**.

### Status — ALL CODE WRITTEN, uncommitted, unplaytest-by-Director
**DONE + reviewed by prior Lead (structurally clean):**
- **Phase 0 economy** — `main-game/items.lua` (NEW), `save.lua` (+`gold`,`items`,`shopState`; old-save normalization in `M.load`), `encounter/stats.lua` (`fromSave(ss, gear)` optional 2nd arg, byte-identical when gear nil), `encounter/entities.lua` (threaded optional `gear` through all 9 party creators), `screens/encounter.lua` (per-char `gear=items.resolveGear(...)` at spawn + win-gold latch at the confirmed `checkVictory` branch), `encounter/systems.lua` (`battle.enemyDefeated` per-kill counter in the side==1 death branch). `./test_headless` was **PASS errors=0** after these (verify again).
- **Phase 1 PARTY** — `screens/party_select.lua` restyled to BH "Party Reserves" (4-slot active strip + 6x2 reserve grid + hover tooltip). Mechanic preserved (3 click behaviors + save-on-exit). No interface change.
- **Phase 2 EQUIP** — `screens/equip.lua` (NEW, 851L). Armory look: party strip, 3-slot gear rail (WEAPON/ARMOR/TRINKET), 6x4 inventory grid, parchment desc bar. Equip/unequip/swap keeps `items`+`inventory` consistent; stats recompute via `stats.fromSave(stats, items.resolveGear(...))` with a pcall+manual-mods fallback. Label fixed TRINET->TRINKET.
- **Integration (by prior Lead, in `main.lua` + `screens/map.lua` + `screens/encounter.lua`)** — registered `equip`/`talents`/`shop` in `main.lua` `screens` table; map top-bar now `{"PARTY","TALENTS","ARMORY"}` wired to party_select/talents/equip; map `T_SHOP` tile opens a shop popup (reuses encounter popup pattern, `popup.ptype="shop"`, title "SHOP", body SHOP_TEXT) whose ENTER does `switchFn("shop", saveData, slot)`; encounter win branch sets `saveData.shopState.pendingRestock=true`.
- **Phase 4 TALENTS** — `screens/talents.lua` (NEW, ~1148L). Linear ladder, choice every 3, ±1 stat-mod passives applied to `rec.stats` (ATK/DEF/maxHP/CRIT only — keys that exist in save DEFAULT_STATS), stored in `unlockedCharacters[name].skillTree` (backward-compat with old `{1,1,1,1,5}`). XP-independent (degrades to level-1 locked display). **BUGS FIXED:** (a) by prior Lead — `rebuildLayout`/`addPlainRow`/`getPartyRect`/`pointInRect` relocated before the interface; (b) by new Lead — the load-time `M._hoveredNode`/`M._hoveredOpt` forward-ref (M not yet declared) converted to plain locals; (c) by new Lead — 7 CALL-TIME forward-refs that headless CANNOT catch (it loads but never drives talents): `resolveOption`/`displayName`/`drawLadder`/`drawPlainRow`/`drawForkRow`/`drawBranchBox`/`drawDescBar` were referenced by earlier-defined closures with no local in scope -> captured a nil GLOBAL. Fixed with a forward-decl block (L512-513) + converting the 7 `local function X` to `X = function` so they assign the upvalue. `./test_headless` PASS after.

**Phase 3 SHOP — REVIEWED + FIXED by new Lead:**
- **Phase 3 SHOP** — `screens/shop.lua` (NEW). `M` interface complete; `onEnter(canvas,postfx,sw,saveData,slot)`; `restockIfNeeded()` mints 3 offers via `rollOffers`->`nextId`->`makeInstance` (trigger: `pendingRestock` OR not `seeded` OR `lastFloor~=floor`); GEAR tab = buy at `value` (spendGold, offer->inventory) + sell at `sellValue` (addGold); HIRE tab = `hireCost(floor)`, adds recruit to party/roster. **Review done:** fixed the load-time syntax error (`{...}[inst.itemType]` anonymous-table-index → named `GLYPHS` local, L587-588); forward-ref scan across its 32 local functions = CLEAN (no talents-style bug). `./test_headless` PASS. **Cleared to commit.**

### FIRST THING — RESOLVED @ new-Lead recovery (2025-10-08 ~17:20)
The syntax gate is now CLEARED. The `./test_headless` run (which `require`s every screen via `main.lua`) was the de-facto syntax checker all along — and it caught 3 real bugs that the structural read missed. All fixed; `./test_headless` now prints **HEADLESS_PASS, REAL_EXIT=0** (every screen file compiles + loads):
- **`screens/equip.lua:598`** — invalid anonymous-table-index `{weapon="W",...}[inst.itemType]` → refactored to named local `GLYPHS` table indexed on the next line.
- **`screens/shop.lua:587`** — same idiom → same fix.
- **`screens/talents.lua:481`** — forward-ref: wrote `M._hoveredNode` before `M` was declared → converted `hoveredNode`/`hoveredOpt` to plain locals (their twins already existed), deleted the broken `M._` aliases.
> NOTE: this box still has NO standalone `lua`/`luac`, but `main.lua` requires all screens at load, so a HEADLESS_PASS proves the whole screen set compiles. The earlier `tail -5` had masked a REAL_EXIT=1 — always read the exit code, not the tail.

**Also recovered this session:** the BH town-menu research agent (Agent 1, session 175e93ce) never wrote its report (LLM stream kept timing out on one giant write). Its raw transcript is preserved at `work/bh-town-menu-research-RECOVERED-raw.txt`; the distilled findings (MenuBrain method+field map, the "one MenuBrain class = all four panels" reframe) are compiled into **`work/bh-town-menu-research.md`**. Nothing in it changes the locked decisions — the authoritative mechanics remain `work/non-encounter-systems-research.md`.

### Verification state
- `./test_headless` covers ONLY the encounter path -> exercises `fromSave` (no-gear) + the entity creators, so the gear-thread + win-gold wiring is partly covered. It does NOT cover map/equip/talents/shop/party (UI screens). The win-gold LATCH site is NOT driven by headless (it never calls `checkVictory`) -> structurally verified only.
- `./test_headless` now **PASS (REAL_EXIT=0)** after the syntax + forward-ref fixes. The syntax gate is CLEARED.
- **Important caveat surfaced this session:** headless only *loads* the UI screens (it `require`s them via `main.lua`), it does NOT *drive* them. So it catches LOAD-TIME errors (syntax, forward-ref-to-nil-global at chunk scope) but NOT CALL-TIME errors inside the screens' update/draw/input handlers (the talents 7-function forward-ref was invisible to it). Those need a real Director playtest.
- Next step: hand the Director a build to playtest all 4 screens + the shop popup + gold flow. The talents screen in particular has never been exercised at runtime — verify the ladder draws, choices are clickable, and stats apply.

### Data-contract reference (authoritative)
`work/phase0-contract.md` — the item/equipment/gold/shopState schema, the `items.lua` API, the `fromSave(ss,gear)` boundary rule, and the SHOP RESTOCK RULE (the `pendingRestock` handshake between encounter win + shop entry). All BH values are `[tuned]` placeholders (BH DB unextractable) centralized in `items.lua`.

### Open decisions still for the Director
- Talents `autoBump` (small stat gain on non-choice levels) is **display-only**, NOT auto-applied (owned by the XP-grant path, which doesn't exist yet). Confirm: choices = only permanent gains, or should leveling auto-apply autoBump?
- Talents CRIT stored as a fraction (0.08 = +8%), desc says "+8%". If UI elsewhere shows CRIT as a whole number, reconcile.
- Item catalog is 9 templates (3 types x 3 grades), not the ~15 named — expand per-class weapon lines (blade/bow, staff) when wanted.
- Wheel-scroll on the talents ladder: `M.wheel(dy)` exists but `main.lua` does NOT route `love.wheel` to it (ladder is fine unscrolled for low levels; only >~16 rows needs it).
- Deferred (not queued): ability VFX/visuals.

### Team / infra notes
- Teammates (economy-dev, equip-dev, party-dev, savescreen-dev, shop-dev) are DSH seats — they persist across the lead change; seats clear only on session restart. shop-dev was stopped (its run was interrupted after writing shop.lua, so its report may be partial). If the new Lead wants a re-dispatch, prefer reusing a seat via send_message; there is no kill/delete from the Lead seat.
- Hindsight memory bank `coding-agent::crimson-red` holds the research + initiative page (id `kp-26b8c288c02c40aabb17c8144976dd1c`). Server: `docker compose -f ~/Storage/hindsight/docker-compose.yml up -d` (OrbStack). It is the persistent record of the BH mechanics (IL-verified) and the Director's decisions — new Lead should search it.
- Non-negotiables (see "Non-negotiable conventions" above): feet-aligned, pay-at-press, resource max 50, virtual px 800x450, `[IL]/[wiki]/[tuned]` value tags, no Lua interpreter on this box, palette crimson/off-red/white on black, fonts via `common.loadFont`.

## LEAD SESSION 2026-10-08 — UI screens DRIVEN for the first time; 9 runtime bugs fixed (uncommitted)
> Supersedes the "syntax-clean, cleared to commit" claims above: the town-menu port had never been
> executed. It now has been, by a new driver test. Still uncommitted, still awaiting Director playtest.

**New gate: `./test_ui`** (`main-game/ui_smoke_test.lua`, `CR_TEST_SCENE=ui`). Enters party/equip/shop/talents/map
with synthetic saves and pumps update+draw under a hover sweep, left/right click sweeps, 6k–20k random clicks,
wheel and keys; plus a directed map→S-tile→SHOP walk, a scroll sweep of a Lv21 ladder, save-contract invariants
and XP checks. `save.write`/audio are stubbed (real slots untouched). Prints `UI_SMOKE_PASS errors=0 checks=63`,
exit 0. Screenshots: LÖVE save dir `ui_smoke/` (copy to `captures/ui_smoke/` and LOOK at them).
Run BOTH `./test_headless` and `./test_ui` (read exit codes) before any handoff to the Director.
Caveat: like `./test_headless`, it flashes a LÖVE window for a few seconds (`t.window.offscreen` is not a
LÖVE 11.5 option — the "never opens a window" claim above is false). It does not drive `screens/encounter.lua`.

**Bugs found by driving + fixed:**
1. `talents.lua` crashed on its FIRST draw: negative scissor height (desc-bar constants put the bar above the
   ladder). Layout constants corrected: bar pinned to the bottom, ladder viewport between header and bar.
2. `talents.lua` picks never registered: `M.update` declared `local hoveredOpt`, shadowing the file-level one
   `mousereleased` reads.
3. Talents: default `skillTree={1,1,1,1,1}` was read as "option 1 already chosen" for 5 forks (with no mods ever
   applied) -> nothing selectable on any existing save. Numeric entries now read as unchosen; new saves use `{}`.
4. `save.lua` `defaultChar()` shared ONE `DEFAULT_STATS` table across all 12 characters -> a talent pick leaked
   into every character until a save/load round-trip. Now copied per character.
5. Talents ladder capped at 16 rows (choices go to Lv21) and `love.wheelmoved` was never routed. Both fixed
   (`main.lua` routes the wheel to `screen.wheel`); the next choice level is always previewed.
6. Talents desc truncation appended a multi-byte "…" then trimmed byte-wise (invalid UTF-8 crash risk) -> ASCII.
7. **No XP path existed** — every character was Lv1 forever, so TALENTS was unusable in a real run. Added
   `main-game/progression.lua` per research §5 plan: win XP `40+15*floor` split among SURVIVORS, curve
   `50*1.22^(L-1)`, cap Lv21, all `[tuned]`; wired at the encounter victory latch next to the gold award
   (`battle.partyNames` parallels `battle.partyIds`). No level-up UI in the victory screen yet.
8. `encounter.lua` pause checked `key == " "`; LÖVE 11 sends `"space"` -> SPACE-pause (bb7866a) never worked.
9. Map: returning from the SHOP left you on the S tile with no popup (had to step off/on). `map.onEnter` now
   re-arms the shop popup; stepping encounter-tile -> shop-tile no longer skips the autosave.
Also: titles/top-bar now use the locked CR names (EQUIP/SHOP/TALENTS, were ARMORY/MERCHANT/ACADEMY); EQUIP stat
readout no longer overlaps the gear rail; SHOP card text wraps inside cards, "+N more" on the sell list; unsold
offers are deleted from `saveData.items` on restock (was an unbounded leak).

**Known gaps to raise with the Director (not changed):**
- HIRE is cosmetic: all 12 characters start unlocked and PARTY lets you slot any of them for free. Hiring needs a
  locked roster (which starters?) to mean anything. Also `rollHire` returns nil when gold < cost at restock time.
- Weapon `usableBy` class-gates are not enforced in `equip.lua` (and all 3 weapons are "sword line").
- Gold is only visible inside the SHOP (not on the map / victory screen). No level-up feedback after a win.
- EQUIP is two-step (click item, then click the slot); talents `autoBump` still display-only.

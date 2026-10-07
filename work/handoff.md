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

## Non-negotiable conventions
1. Feet-aligned: center stored, feet = pos.y+h/2.
2. Pay-at-press: cd+resource at press; activate front-of-queue + in-range + free; dead target dropped, NO refund.
3. Anim/timing pipeline untouched while porting data.
4. Resource bar max 50.
5. Never guess values; tag [IL]/[wiki]/[tuned].
6. No Lua interpreter on machine: structural checks + careful reads.
7. Member cap 8, ALL SEATS FILLED & IDLE: battleheart-research, savescreen-dev, damage-dev, status-dev, formation-dev, ability-dev, class-research, status-dev2. No kill/delete tool from Lead seat; reuse via send_message; seats clear only on session restart. Don't edit a file an agent owns concurrently (FS_STALE_VERSION churn lesson).

## Open items
- Playtest pending: (a) encounter foundation + 4 classes, (b) party-select click feel.
- BH DB VALUES PERMANENTLY UNEXTRACTABLE from current datamine (no AssetBundles present; dump census VFX/sprites/audio only at <datamine>/decompiled/resources/assets/bin/Data/_bh_extract_out/json/). Do NOT retry extraction there. Values stay [wiki]/[tuned] until a new source (APK with .assets bundles, or Legacy files). .NET runtimes installed: ~/.dotnet (arm64) + ~/.dotnet-x64 (x86_64 under Rosetta).
- Director decisions queued (non-encounter report §7): floors replace levels (default yes)? lean item catalog 3 grades/~15 (yes)? hire flat-per-floor vs 10xlevel? choice every 3 vs 5 levels? per-kill gold drip 1-2? stable seed per floor number?
- [DONE @ 94a6e99] 3 flagged integration lines now wired (verified 21345e0 → fixed 94a6e99, headless PASS): SLOW→moveTarget, SHIELD→combat.resolve (before min-3 floor), activation camera-punch on active-ability activation. Previously: flagged unwired, never confirmed.
- Trivial leftovers: TOPUP_FRAME unused local headless_test.lua L83.

## Key files
main-game/encounter/{combat,status,systems,skills,abilities,entities,anim,effects,stats,ui}.lua; screens/{title,save_select,party_select,map,encounter,sprite_dev}.lua; conf.lua + main.lua (headless gates); headless_test.lua; playtest; test_headless; AGENTS.md; memory/reference.md; work/*.md. Datamine: /Users/alexcheng/CascadeProjects/Battleheart datamine (il/Assembly-UnityScript.il = 108k-line truth source for mechanics).

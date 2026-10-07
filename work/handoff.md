# Crimson Red — Handoff / Compaction (seed for a cloned Manager or post-compact resume)

## Role & loop
Manager (Lead) of a playtest loop: Director (user) gives features/feedback -> Manager scopes & delegates -> dev teammates implement -> playable build -> Director playtests -> iterate. Director talks only to the Manager. CR = LÖVE2D "mod" of Battleheart: same systems, new content. KEEP the shared Clash-Royale resource bar (max 50) — deliberate deviation.

## What exists (commit be9a043, branch master)
- Encounter P0 foundation (verified ./test_headless PASS): two-stage damage (combat.roll -> combat.resolve; enemies no defense), indexed statuses incl SLOW/SHIELD/DOT-ticks/PARALYZE, 6-slot ring formation, data-driven abilities, pay-at-press queueing, per-unit EXEC_GATE=0.4.
- 4 ported BH classes (Cleric/Paladin/Wizard/Rogue) — proof-of-port, recolored Knight frames; Cleric NO auto-attack; Paladin specials + Rogue multipliers are approximations; Meteor x2.0.
- Party select: click-to-move (verified by code read, NOT yet by Director playtest).
- 3 integration lines wired (commit 94a6e99, headless PASS): SLOW now actually slows movement (systems.moveTarget × status.getSlowFactor), SHIELD now actually reduces incoming damage (combat.resolve × shieldReduction, before min-3 floor), activation camera-punch fires on active-ability activation (skills.lua → combat.triggerActivationVFX). Also dropped unused TOPUP_FRAME local in headless_test.lua.
- Headless: ./test_headless at project root; env CR_HEADLESS/CR_TEST_MODE/CR_TEST_SCENE=headless; never open windows on Director screen; visible path byte-identical without flags.
- Research: work/battleheart-encounter-parity.md + work/non-encounter-systems-research.md (IL-verified mechanics, divergence plan, Director Qs in §7).
- [DONE @ 198e6c9] Center-Y alignment fix: unified moveTarget to center-coord convention (targetFollow/moveTarget/right-click/walk-in) — fixed infinite-repositioning + vertical drift. Director: "basically fixed."
- [DONE @ be9a043] Alignment streamlining (P0+P1+P3) mirroring BH (IL-verified): P0 combat.lua checkMeleeRange now size-aware (per-attacker reach 6+0.25*w vs horizontal body gap + flat 18px center-Y band, was size-blind dx<=6/dy<=2); P1 systems.lua slotGroundPoint scales the 6-slot ring by target width (1+0.5*max(0,(w/2-22.5)/22.5), scale>=1 so normal units byte-identical, bigger targets wider ring → melee stand flush outside boss); P3a targetFollow snaps to exact slot center on arrival (kill micro-osc, BH 0.07-settle analogue); P3b physics bottom feet clamp tightened 12px inset both sides. Headless PASS (errors=0). BH alignment model detail: work/ + Hindsight doc "BH combat alignment model (IL-verified)".

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

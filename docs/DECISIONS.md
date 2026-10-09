# Decisions the Director has made

Do not reopen these. If one blocks a task, tell the Director and ask. Add new decisions at
the bottom with the date, in the Director's own words where possible.

## Game design
1. Crimson Red is a "mod" of Battleheart: same underlying systems, new classes/enemies/stages.
   "Use the simple database like in BH" — content is data-driven.
2. **Keep the shared resource bar (max 50)** that abilities spend — a deliberate difference from BH.
3. **Floors replace BH's level list** as the progression spine (a map of tiles per floor).
4. **Abilities: pay at press.** Cooldown starts and resource is spent when the key is pressed;
   the ability fires when the unit is free and in range. If the target dies first, no refund.
5. Town menus use Crimson Red names: **PARTY, EQUIP, TALENTS, SHOP** (BH: Keep, Armory, Academy, Merchant).
6. **TALENTS** is a linear per-class ladder with a binary choice **every 3 levels**. No point-spend tree.
7. **SHOP** is its own full screen, entered from a shop tile on the map. **Hiring is a tab in
   the shop.** The shop restocks after every won battle.
8. Gold: a per-kill gold drip on top of the win reward.
9. **Use Battleheart's real numbers** wherever Crimson Red had placeholders (2026-10-08):
   item stats and prices, hero base stats and scaling, XP curve, gold/XP rewards, cooldowns.

## Controls / presentation
10. Pause is **SPACE only** (plus the on-screen pause button). No helper text at the bottom of the battle screen.
11. Screen shake: none on the wizard's auto-attack; a shake on every accepted ability press.
12. Virtual resolution 800×450; palette crimson / off-red / white on black; Dedicool font.

## Workflow
13. The Director's only job is playtest feedback and naming features. The Lead does the rest
    and keeps the project understandable for a less capable model.
14. Git: work happens on a branch in small commits; nothing is pushed or merged to `master`
    without the Director's say-so.

## Choices made by the Lead that the Director has NOT confirmed
These were needed to make the BH numbers work. They are listed in `docs/STATUS.md` under
"Needs the Director's eyes" until confirmed, then move up into the lists above.

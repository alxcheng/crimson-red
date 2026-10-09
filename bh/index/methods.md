# Battleheart IL — class & method index (generated)

Source: `il/Assembly-UnityScript.il` in the datamine (108668 lines). Regenerate with
`python3 bh/tools/build_il_index.py`. Line ranges are 1-based and inclusive.

Coroutines (`yield` methods) appear twice: a short stub method on the class, and the real
body in a nested `$name$NNN` class's `MoveNext` — read the nested range.

| Class | Lines | Size | Fields | Methods |
|---|---|---|---|---|
| [Blinker](#blinker) | 33–198 | 166 | 2 | 4 |
| [Congrats](#congrats) | 200–604 | 405 | 5 | 3 |
| [Item](#item) | 606–631 | 26 | 9 | 1 |
| [Player](#player) | 633–663 | 31 | 14 | 1 |
| [Power](#power) | 665–685 | 21 | 4 | 1 |
| [LootTable](#loottable) | 687–707 | 21 | 4 | 1 |
| [Wave](#wave) | 709–738 | 30 | 4 | 1 |
| [Level](#level) | 740–779 | 40 | 20 | 1 |
| [LootThreshold](#lootthreshold) | 781–799 | 19 | 2 | 1 |
| [Map](#map) | 801–820 | 20 | 3 | 1 |
| [powerCollection](#powercollection) | 822–852 | 31 | 5 | 1 |
| [Database](#database) | 854–2554 | 1701 | 29 | 8 |
| [DynamicTexture](#dynamictexture) | 2556–2674 | 119 | 2 | 3 |
| [EffectScript](#effectscript) | 2676–5280 | 2605 | 49 | 10 |
| [SpecialMove](#specialmove) | 5282–5302 | 21 | 4 | 1 |
| [EnemyScript](#enemyscript) | 5304–32635 | 27332 | 85 | 55 |
| [HandScript](#handscript) | 32637–32871 | 235 | 9 | 4 |
| [MenuBrain](#menubrain) | 32873–59088 | 26216 | 177 | 33 |
| [MotherBrain](#motherbrain) | 59090–76914 | 17825 | 150 | 30 |
| [PartyMember](#partymember) | 76916–105810 | 28895 | 107 | 45 |
| [PetScript](#petscript) | 105812–107128 | 1317 | 13 | 7 |
| [SceneTransfer](#scenetransfer) | 107130–107178 | 49 | 1 | 3 |
| [SplashScreen](#splashscreen) | 107180–107418 | 239 | 3 | 4 |
| [TextPrint](#textprint) | 107420–107584 | 165 | 4 | 5 |
| [TitleAnimation](#titleanimation) | 107586–107841 | 256 | 7 | 3 |
| [TitleMusic](#titlemusic) | 107843–108005 | 163 | 2 | 4 |
| [dynamicbackgroundhandler](#dynamicbackgroundhandler) | 108007–108601 | 595 | 11 | 3 |
| [titleinit](#titleinit) | 108603–108666 | 64 | 0 | 4 |

## Blinker

Lines 33–198. 2 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 40–49 | 10 |
| `Awake` | 52–70 | 19 |
| `Update` | 73–186 | 114 |
| `Main` | 189–196 | 8 |

## Congrats

Lines 200–604. 5 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 210–219 | 10 |
| `Awake` | 222–592 | 371 |
| `Main` | 595–602 | 8 |

## Item

Lines 606–631. 9 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 620–629 | 10 |

## Player

Lines 633–663. 14 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 652–661 | 10 |

## Power

Lines 665–685. 4 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 674–683 | 10 |

## LootTable

Lines 687–707. 4 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 696–705 | 10 |

## Wave

Lines 709–738. 4 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 718–736 | 19 |

## Level

Lines 740–779. 20 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 765–777 | 13 |

## LootThreshold

Lines 781–799. 2 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 788–797 | 10 |

## Map

Lines 801–820. 3 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 809–818 | 10 |

## powerCollection

Lines 822–852. 5 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 832–850 | 19 |

## Database

Lines 854–2554. 29 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 888–945 | 58 |
| `Awake` | 948–998 | 51 |
| `save` | 1001–1682 | 682 |
| `load` | 1685–2337 | 653 |
| `OnApplicationPause` | 2340–2362 | 23 |
| `OnApplicationQuit` | 2365–2382 | 18 |
| `populateMerchant` | 2385–2542 | 158 |
| `Main` | 2545–2552 | 8 |

## DynamicTexture

Lines 2556–2674. 2 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 2563–2575 | 13 |
| `Awake` | 2578–2662 | 85 |
| `Main` | 2665–2672 | 8 |

## EffectScript

Lines 2676–5280. 49 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 2730–2781 | 52 |
| `Awake` | 2784–2859 | 76 |
| `Update` | 2862–3369 | 508 |
| `activate` | 3372–3757 | 386 |
| `damageEnemy` | 3760–4507 | 748 |
| `damagePlayer` | 4510–4719 | 210 |
| `healPlayer` | 4722–4835 | 114 |
| `onDramaticImpact` | 4838–4848 | 11 |
| `onApolloImpact` | 4851–4864 | 14 |
| `Main` | 4867–4874 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$onDramaticImpact$1269` | 4876–5005 | 130 |
| `$onApolloImpact$1272` | 5007–5278 | 272 |

## SpecialMove

Lines 5282–5302. 4 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 5291–5300 | 10 |

## EnemyScript

Lines 5304–32635. 85 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 5394–5472 | 79 |
| `initialize` | 5475–5656 | 182 |
| `remoteUpdate` | 5659–5700 | 42 |
| `AI` | 5703–16684 | 10982 |
| `stunBolt` | 16687–16698 | 12 |
| `discharge` | 16701–16711 | 11 |
| `meteorStorm` | 16714–16724 | 11 |
| `chaosBolt` | 16727–16737 | 11 |
| `dropMeteor1` | 16740–16750 | 11 |
| `dropMeteor2` | 16753–16763 | 11 |
| `dropBoulder1` | 16766–16776 | 11 |
| `dropBoulder2` | 16779–16789 | 11 |
| `earthquake` | 16792–16802 | 11 |
| `enrage` | 16805–16815 | 11 |
| `residualEffects` | 16818–17138 | 321 |
| `spitAttack` | 17141–17152 | 12 |
| `puddleDamage` | 17155–17373 | 219 |
| `teleport` | 17376–17386 | 11 |
| `acquireHealTarget` | 17389–17525 | 137 |
| `webShot` | 17528–17538 | 11 |
| `summonSkeletonAdds` | 17541–17628 | 88 |
| `summonGoblinAdds` | 17631–17641 | 11 |
| `summonSpiderAdds` | 17644–17654 | 11 |
| `enterChargeMode` | 17657–17667 | 11 |
| `throwBomb` | 17670–17680 | 11 |
| `flash` | 17683–17703 | 21 |
| `shaderAnimation` | 17706–18371 | 666 |
| `activateColors` | 18374–18390 | 17 |
| `takeDamage` | 18393–19181 | 789 |
| `hypotheticalDamage` | 19184–19462 | 279 |
| `die` | 19465–19475 | 11 |
| `oozeBossSplit` | 19478–19488 | 11 |
| `goblinBossDeath` | 19491–19501 | 11 |
| `lichBossDeath` | 19504–19514 | 11 |
| `spiderBossDeath` | 19517–19527 | 11 |
| `updateHealthBar` | 19530–19937 | 408 |
| `healthAnimation` | 19940–20121 | 182 |
| `animateSliding` | 20124–20336 | 213 |
| `requestPosition` | 20339–20936 | 598 |
| `purgePosition` | 20939–21093 | 155 |
| `spawn` | 21096–22090 | 995 |
| `completeLichSpawn` | 22093–22103 | 11 |
| `acquireRandomTarget` | 22106–22258 | 153 |
| `meleeAttack` | 22261–22271 | 11 |
| `omegaPunch` | 22274–22284 | 11 |
| `enragedMeleeAttack` | 22287–22297 | 11 |
| `rangedAttack` | 22300–22310 | 11 |
| `castHeal` | 22313–22323 | 11 |
| `heal` | 22326–22455 | 130 |
| `handleDebuffs` | 22458–22834 | 377 |
| `clearAllAttackers` | 22837–22978 | 142 |
| `clearAllMeleeAttackers` | 22981–23132 | 152 |
| `muteSoundEffects` | 23135–23174 | 40 |
| `targetHighestArmorPlayer` | 23177–23387 | 211 |
| `Main` | 23390–23397 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$stunBolt$1281` | 23399–23853 | 455 |
| `$discharge$1290` | 23855–24156 | 302 |
| `$meteorStorm$1293` | 24158–24342 | 185 |
| `$chaosBolt$1296` | 24344–24889 | 546 |
| `$dropMeteor1$1303` | 24891–25172 | 282 |
| `$dropMeteor2$1307` | 25174–25455 | 282 |
| `$dropBoulder1$1311` | 25457–25716 | 260 |
| `$dropBoulder2$1315` | 25718–25977 | 260 |
| `$earthquake$1319` | 25979–26165 | 187 |
| `$enrage$1322` | 26167–26317 | 151 |
| `$spitAttack$1325` | 26319–26711 | 393 |
| `$teleport$1334` | 26713–26914 | 202 |
| `$webShot$1337` | 26916–27054 | 139 |
| `$summonGoblinAdds$1340` | 27056–27296 | 241 |
| `$summonSpiderAdds$1344` | 27298–27586 | 289 |
| `$enterChargeMode$1348` | 27588–27737 | 150 |
| `$throwBomb$1351` | 27739–27918 | 180 |
| `$die$1354` | 27920–28916 | 997 |
| `$oozeBossSplit$1387` | 28918–29427 | 510 |
| `$goblinBossDeath$1390` | 29429–29995 | 567 |
| `$lichBossDeath$1395` | 29997–30824 | 828 |
| `$spiderBossDeath$1400` | 30826–31380 | 555 |
| `$completeLichSpawn$1405` | 31382–31507 | 126 |
| `$meleeAttack$1408` | 31509–31751 | 243 |
| `$omegaPunch$1413` | 31753–32041 | 289 |
| `$enragedMeleeAttack$1417` | 32043–32260 | 218 |
| `$rangedAttack$1422` | 32262–32432 | 171 |
| `$castHeal$1425` | 32434–32633 | 200 |

## HandScript

Lines 32637–32871. 9 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 32651–32660 | 10 |
| `Awake` | 32663–32690 | 28 |
| `Update` | 32693–32859 | 167 |
| `Main` | 32862–32869 | 8 |

## MenuBrain

Lines 32873–59088. 177 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 33055–33079 | 25 |
| `Awake` | 33082–33507 | 426 |
| `muteSoundEffects` | 33510–33575 | 66 |
| `Update` | 33578–33716 | 139 |
| `inventoryInput` | 33719–33729 | 11 |
| `updateEquipArrows` | 33732–34062 | 331 |
| `mainInput` | 34065–34075 | 11 |
| `storeInput` | 34078–34088 | 11 |
| `skillsInput` | 34091–34101 | 11 |
| `tavernInput` | 34104–34114 | 11 |
| `mapInput` | 34117–34127 | 11 |
| `keepInput` | 34130–34140 | 11 |
| `loadInput` | 34143–34153 | 11 |
| `tutorialInput` | 34156–34811 | 656 |
| `updateLoadScreen` | 34814–35542 | 729 |
| `startNewGame` | 35545–35555 | 11 |
| `introSequence` | 35558–36257 | 700 |
| `applyCorners` | 36260–36413 | 154 |
| `loadExistingGame` | 36416–36426 | 11 |
| `UpdateInventory` | 36429–41092 | 4664 |
| `UpdatePartyPortraits` | 41095–41772 | 678 |
| `InitialPartySelection` | 41775–42275 | 501 |
| `updateWeapons` | 42278–42708 | 431 |
| `resetMenus` | 42711–42770 | 60 |
| `clearDescriptionBox` | 42773–43113 | 341 |
| `showUpgradeWindow` | 43116–43227 | 112 |
| `showVendorWindow` | 43230–43361 | 132 |
| `orientScreen` | 43364–43385 | 22 |
| `calculatePowerBonus` | 43388–43456 | 69 |
| `calculateArmorBonus` | 43459–43527 | 69 |
| `OnApplicationPause` | 43530–43567 | 38 |
| `unlockPlayableCharacters` | 43570–43662 | 93 |
| `Main` | 43665–43672 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$inventoryInput$1428` | 43674–48055 | 4382 |
| `$mainInput$1460` | 48057–49466 | 1410 |
| `$storeInput$1493` | 49468–52236 | 2769 |
| `$skillsInput$1531` | 52238–53593 | 1356 |
| `$tavernInput$1545` | 53595–54839 | 1245 |
| `$mapInput$1560` | 54841–56280 | 1440 |
| `$keepInput$1580` | 56282–57190 | 909 |
| `$loadInput$1588` | 57192–58699 | 1508 |
| `$startNewGame$1615` | 58701–58854 | 154 |
| `$loadExistingGame$1620` | 58856–59086 | 231 |

## MotherBrain

Lines 59090–76914. 150 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 59245–59302 | 58 |
| `Awake` | 59305–61650 | 2346 |
| `Update` | 61653–61850 | 198 |
| `playerControl` | 61853–63786 | 1934 |
| `mouseControl` | 63789–63841 | 53 |
| `pauseInput` | 63844–64033 | 190 |
| `remoteUpdates` | 64036–64105 | 70 |
| `interfaceAnimation` | 64108–64611 | 504 |
| `orientScreen` | 64614–64635 | 22 |
| `hideLine` | 64638–64649 | 12 |
| `OnApplicationPause` | 64652–64693 | 42 |
| `updateActionBar` | 64696–64707 | 12 |
| `disableActionBar` | 64710–64720 | 11 |
| `fade` | 64723–64899 | 177 |
| `partyEntrance` | 64902–64994 | 93 |
| `populateEnemyPools` | 64997–65070 | 74 |
| `enemySpawn` | 65073–65393 | 321 |
| `debugTools` | 65396–65507 | 112 |
| `specialMove` | 65510–65521 | 12 |
| `tutorialDriver` | 65524–70145 | 4622 |
| `levelCompleteSequence` | 70148–70158 | 11 |
| `XPBarAnimation` | 70161–70171 | 11 |
| `defeatSequence` | 70174–70184 | 11 |
| `levelUpEnemies` | 70187–70259 | 73 |
| `updateScore` | 70262–70336 | 75 |
| `calculateNextLevelXP` | 70339–70404 | 66 |
| `muteSoundEffects` | 70407–70444 | 38 |
| `delayedPetCommand` | 70447–70457 | 11 |
| `handleBackButton` | 70460–70599 | 140 |
| `Main` | 70602–70609 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$hideLine$1627` | 70611–70769 | 159 |
| `$updateActionBar$1634` | 70771–71589 | 819 |
| `$disableActionBar$1653` | 71591–71938 | 348 |
| `$specialMove$1664` | 71940–72397 | 458 |
| `$levelCompleteSequence$1673` | 72399–74749 | 2351 |
| `$XPBarAnimation$1712` | 74751–75661 | 911 |
| `$defeatSequence$1730` | 75663–76802 | 1140 |
| `$delayedPetCommand$1757` | 76804–76912 | 109 |

## PartyMember

Lines 76916–105810. 107 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 77028–77118 | 91 |
| `initialize` | 77121–78037 | 917 |
| `remoteUpdate` | 78040–78099 | 60 |
| `AI` | 78102–81244 | 3143 |
| `findMovementTarget` | 81247–81333 | 87 |
| `handleCooldowns` | 81336–81480 | 145 |
| `handleCooldowns2` | 81483–81494 | 12 |
| `takeDamage` | 81497–82407 | 911 |
| `die` | 82410–82420 | 11 |
| `heal` | 82423–82590 | 168 |
| `healthAnimation` | 82593–82778 | 186 |
| `updateHealthBar` | 82781–83186 | 406 |
| `blink` | 83189–83355 | 167 |
| `deselect` | 83358–83382 | 25 |
| `select` | 83385–83412 | 28 |
| `shaderAnimation` | 83415–84220 | 806 |
| `activateColors` | 84223–84239 | 17 |
| `pulse` | 84242–84262 | 21 |
| `flash` | 84265–84285 | 21 |
| `castHeal` | 84288–84299 | 12 |
| `castBardBuff` | 84302–84313 | 12 |
| `castFireball` | 84316–84327 | 12 |
| `shootArrow` | 84330–84341 | 12 |
| `counterAttack` | 84344–84355 | 12 |
| `meleeAttack` | 84358–84368 | 11 |
| `clericAuraAttack` | 84371–84586 | 216 |
| `flameArrowPulse` | 84589–84975 | 387 |
| `pounceAttack` | 84978–84988 | 11 |
| `requestPosition` | 84991–85546 | 556 |
| `purgePosition` | 85549–85703 | 155 |
| `animateSliding` | 85706–86022 | 317 |
| `performSpecial` | 86025–86036 | 12 |
| `handleBuffs` | 86039–86362 | 324 |
| `returnToNormal` | 86365–86421 | 57 |
| `returnToNormalFromShot` | 86424–86477 | 54 |
| `returnToNormalFromPounce` | 86480–86531 | 52 |
| `calculateDamageMultiplier` | 86534–86610 | 77 |
| `createMyEffects` | 86613–86752 | 140 |
| `drainLife` | 86755–86787 | 33 |
| `adrenalineRush` | 86790–86847 | 58 |
| `returnDamageValue` | 86850–86860 | 11 |
| `muteSoundEffects` | 86863–86901 | 39 |
| `congratsScreenInitialize` | 86904–87109 | 206 |
| `calculateCrit` | 87112–87142 | 31 |
| `Main` | 87145–87152 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$handleCooldowns2$1760` | 87154–87266 | 113 |
| `$die$1765` | 87268–88335 | 1068 |
| `$castHeal$1802` | 88337–88858 | 522 |
| `$castBardBuff$1808` | 88860–89305 | 446 |
| `$castFireball$1817` | 89307–89480 | 174 |
| `$shootArrow$1822` | 89482–89637 | 156 |
| `$counterAttack$1827` | 89639–90104 | 466 |
| `$meleeAttack$1838` | 90106–92750 | 2645 |
| `$pounceAttack$1845` | 92752–93224 | 473 |
| `$performSpecial$1850` | 93226–105808 | 12583 |

## PetScript

Lines 105812–107128. 13 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 105830–105845 | 16 |
| `Initialize` | 105848–105881 | 34 |
| `RemoteUpdate` | 105884–106451 | 568 |
| `chooseSlot` | 106454–106574 | 121 |
| `attack` | 106577–106587 | 11 |
| `clearTarget` | 106590–106608 | 19 |
| `Main` | 106611–106618 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$attack$1891` | 106620–107126 | 507 |

## SceneTransfer

Lines 107130–107178. 1 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 107136–107145 | 10 |
| `Awake` | 107148–107166 | 19 |
| `Main` | 107169–107176 | 8 |

## SplashScreen

Lines 107180–107418. 3 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 107188–107197 | 10 |
| `Awake` | 107200–107230 | 31 |
| `Update` | 107233–107406 | 174 |
| `Main` | 107409–107416 | 8 |

## TextPrint

Lines 107420–107584. 4 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 107429–107441 | 13 |
| `Awake` | 107444–107459 | 16 |
| `Update` | 107462–107552 | 91 |
| `Printout` | 107555–107572 | 18 |
| `Main` | 107575–107582 | 8 |

## TitleAnimation

Lines 107586–107841. 7 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 107598–107613 | 16 |
| `Update` | 107616–107829 | 214 |
| `Main` | 107832–107839 | 8 |

## TitleMusic

Lines 107843–108005. 2 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 107850–107859 | 10 |
| `Awake` | 107862–107881 | 20 |
| `startMusic` | 107884–107894 | 11 |
| `Main` | 107897–107904 | 8 |

Coroutine bodies / nested classes:

| Nested class | Lines | Size |
|---|---|---|
| `$startMusic$1900` | 107906–108003 | 98 |

## dynamicbackgroundhandler

Lines 108007–108601. 11 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 108023–108032 | 10 |
| `Start` | 108035–108589 | 555 |
| `Main` | 108592–108599 | 8 |

## titleinit

Lines 108603–108666. 0 fields.

| Method | Lines | Size |
|---|---|---|
| `.ctor` | 108608–108617 | 10 |
| `Start` | 108620–108629 | 10 |
| `Update` | 108632–108654 | 23 |
| `Main` | 108657–108664 | 8 |

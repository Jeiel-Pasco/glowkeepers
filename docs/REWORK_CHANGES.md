# Glowkeepers — Rework Changelog (`layer-one-5`)

Comprehensive summary of all world, combat, Grimoire, economy, gear, storyline, UI, and tooling changes implemented on branch `layer-one-5` and synced to Roblox Studio (`Glowkeepers [DEV]`, Place ID `81788809201865`, saved at Version 132).

---

## 1. World, Shared Hub & Black Clover Storyline Areas (`Lv 1–50`)

- **Unified Cohesive World (`r = 0..700`)**: Removed legacy v1 pet-plot greybox (`tools/BuildGreybox.luau`) and elemental lava/sand biome splits. Rebuilt `tools/BuildZones.luau` as a single Forest & Ancient Stone Ruins world with a central courtyard (`r = 0..80`), campfire, perimeter ring with 3 gates, mixed forest, and NightGlow lanterns/mushrooms.
- **Shared Wizard Camp Sanctuary**: Replaced the 8 individual v1 plots with one shared `Sanctuary` hub containing:
  - **Scriptorium Desk** (Grimoire Gacha & `Z/X/C/V` Skill Upgrades)
  - **Grimoire Shelf** (equip up to 2 Grimoires)
  - **Camp Bank** (extract carried loot with `+15%` Full-Bag walk-in bonus)
  - **Wizard Gear Shop** (buy visible 3D Gears with Banked Coins)
  - **South Duel Arena Ring** (`z = 114, r = 24`)
- **3 Level-Tiered Storyline Areas & Physical Quest Giver NPCs** (`Level.CAP = 50`):

| Area | Level Range | Quest Giver NPC | Story Arc | Quests |
| :--- | :--- | :--- | :--- | :--- |
| **Whispering Woods** (`area1`) | Lv 1–15 | **Elder Orsi** | Arc 1 · Hage Outskirts Trial | *Grimoire Trial* (4 Forest Wisps), *Forest Hunt* (5 Thorn Sprouts), *Rogue Poacher* (Lv 15 Runestone Brute Boss) |
| **Raider Wilds** (`area2`) | Lv 15–30 | **Scout Captain** | Arc 2 · Sosshi Frontier Mission | *Bandit Sweep* (6 Raiders), *Rogue Mist Mages* (5 Mist Callers), *Frontier Guardian* (Lv 30 Elder Treant Boss) |
| **Highland Ruins** (`area3`) | Lv 30–50 | **Knight Envoy** | Arc 3 · Midnight Sun Dungeon | *Dungeon Sentinels* (6 Ruin Sentinels), *Midnight Sun Mages* (6 Midnight Sun Casters), *Dungeon Titan* (Lv 50 Ancient Mineral Golem Boss) |

- **Wild Spawns & Raider Camps**:
  - Neutral wild enemies (`forest_wisp`, `thorn_sprout`, `ashling` / Runestone Brute) spawn dynamically via `Zones.randomWildPos`.
  - Raider Camp sites (`CAMP_SITE_R = 24`) sit in forest wedges (`60° / 180° / 300°`) with clear trail geometry (`CLIFF_IN = 270`, `CLIFF_OUT = 290`, `ZONE_D = 460`, `WORLD_R = 700`).

---

## 2. 11 Black Clover Grimoires & Fixed `Z/X/C/V` Skillsets

- **11 Grimoire Types across 6 Rarity Tiers & Clover Ranks**:
  - **Starter (3-Leaf)**: `Neutral` (*Mana Equilibrium*)
  - **Common (3-Leaf, 48%)**: `Fire` (*Ignited Soul*), `Water` (*Valkyrie Current*), `Leaf` (*Natural Grace*)
  - **Uncommon (3-Leaf, 26%)**: `Wind` (*Spirit of Zephyr*), `Earth` (*Titan's Poise*)
  - **Rare (3-Leaf, 14%)**: `Frost` (*Permafrost*)
  - **Epic (3-Leaf, 8%)**: `Lightning` (*Thunder Fiend Boots*)
  - **Legendary (3-Leaf, 3%)**: `Gravity` (*Gravity Aura*)
  - **Mythic (4-Leaf / 5-Leaf, 1%)**: `Light` (4-Leaf), `Dark` (5-Leaf)
- **Fixed `Z/X/C/V` Skills**: Added 44 fixed skills (4 per Grimoire) in `src/shared/Spells.luau` (52 total spells including legacy compatibility entries), unlocked and upgraded (`Lv 1–5`) with Universal Ink via `Writing.slotCost` / `Writing.upgradeSlot`.
- **Grimoire Gacha & Pity**: `GrimoireService` rolls new Grimoires for `5★ Stars` at the Desk with pity tracking (`data.pity`) and enforces a `1.5s` `SwapBook` cooldown.
- **Floating 3D Grimoires**: `CombatController` renders each player's equipped Grimoire floating beside their character with 3-Leaf, 4-Leaf, or 5-Leaf visual accents synced via `ActiveBook` and `Clovers` character attributes.
- **Elemental Type Curves**: PvE (`1.50x / 0.67x`, Mythic `1.25x`) and PvP (`1.30x / 0.77x`, Mythic `1.15x`) defined in `src/shared/Element.luau`.

---

## 3. 3-Currency Economy, Capped Backpack & 4 Visible 3D Gears

- **3 Separated Currencies**:
  1. **★ Stars** (from Area Quests & Bosses; never lost on death; players start with `5★`) → **Roll Grimoires** (`5★` per roll).
  2. **Universal Ink** (field drop → Backpack → Bank) → **Unlock & Upgrade `Z/X/C/V` skills**.
  3. **Coins** (field drop & Quests → Backpack → Bank) → **Buy 4 Visible 3D Gears**.
- **Capped Backpack & Risk-Reward Extraction**:
  - Backpack capacity scales from `25` (Tier 1) up to `250` (Tier 5), with death-drop share shrinking from `50%` down to `25%`.
  - Walking a **100% full Backpack** back into Camp grants a **`+15%` Full-Bag Extraction Bonus** (`Loot.FULL_BAG_BONUS = 0.15`), and the 3D Backpack visually bulges/glows when full (`BagFull` attribute).
  - War Mode grants `+25%` coin drops (`LootService`).
- **4 Visible 3D Gear Categories (`src/shared/Gears.luau`)**:
  - **Backpack**: Loot Capacity (`25 → 250`) & Death Protection (`50% → 25%` dropped on death).
  - **Robe & Cloak**: Max HP bonus (`+25` to Tier 5) & Defense (`-%` damage taken).
  - **Wizard Hat**: Spell Power (`+%` damage) & Cooldown Reduction (`-%` CD).
  - **Boots**: Movement Speed (`+%` speed), Dash Cooldown reduction, & faster Recall (`R`) channel time.
  - All 4 gears render visibly on every player's 3D character via `Gear*` attributes in `CombatController` and affect movement in `MovementController` and max HP in `ProgressionService`.

---

## 4. Enemy AI, Visuals & UI Updates

- **Elemental Enemy & Boss Abilities (`EnemyService.luau`)**: Distinct Fire, Water, and Leaf enemy/boss attack behaviors alongside wild Neutral random respawns.
- **Enemy Looks (`EnemyLooks.luau`)**: Added `forest_wisp` model; converted `ashling` into Neutral **Runestone Brute** (`hp = 340`) with cyan runes.
- **Camp & HUD UI (`CampController.luau`, `HUDController.luau`)**:
  - Rebuilt Camp UI for Grimoire Gacha, `Z/X/C/V` Skill Upgrades, Shelf, Bank, 4-Gear Shop, and Black Clover Storyline Quest Board.
  - Updated HUD with Backpack fullness bar, Banked currencies, Stars, Bounty, War Mode toggle button (`TogglePvp`), hub-only tutorial guide beam, and active Area Quest display.

---

## 5. File-by-File Change Manifest

### Added (1 file)
- `src/shared/Gears.luau` — 4 visible Gear categories (`backpack`, `robe`, `hat`, `boots`), tiers, pricing, colors, and stat aggregation (`Gears.stats`).

### Deleted (1 file)
- `tools/BuildGreybox.luau` — Removed legacy v1 pet-plot greybox builder (`-1631` lines).

### Modified (27 files)

#### Shared (`src/shared/`)
- `src/shared/Element.luau` (`+218/-`) — 11 Grimoire types, 3/4/5-Leaf clover ranks, 6 rarity tiers, `Element.PASSIVE`, `Element.rollGacha`, PvP multipliers.
- `src/shared/Spells.luau` (`+807/-`) — 44 fixed `Z/X/C/V` skills + legacy compat (52 total), `Spells.fixedFor`, `UNLOCK_INK`, `UPGRADE_INK`.
- `src/shared/Writing.luau` (`+76/-`) — `Writing.newBook`, `Writing.slotCost`, `Writing.upgradeSlot` for Universal Ink progression.
- `src/shared/Loot.luau` (`+64/-`) — `totalInk`, `spendInk`, `weight`, `isFull`, `FULL_BAG_BONUS = 0.15`.
- `src/shared/Zones.luau` (`+254/-`) — `r = 80` courtyard, `randomWildPos`, Raider Camp wedges, `QUEST_GIVERS`, and `area1 / area2 / area3` geometry.
- `src/shared/Quests.luau` (`+297/-`) — 9 Black Clover storyline quests across Areas 1–3 + NPC metadata (`Quests.NPCS`, `Quests.BOARD`, `Quests.forArea`).
- `src/shared/Enemies.luau` (`+78/-`) — Added `forest_wisp`, tuned `ashling` (Runestone Brute, `hp = 340`) and `Lv 1–50` area enemies.
- `src/shared/RaiderCamps.luau` (`+4/-`) — Updated Raider Camp alignment with new wedge positions.
- `src/shared/Level.luau` (`+2/-`) — Raised `Level.CAP` to `50`.
- `src/shared/Net/init.luau` (`+19/-`) — Added network remotes: `RollGrimoire`, `UpgradeSkill`, `BuyGear`, `TogglePvp`, `AcceptQuest`.

#### Server (`src/server/`)
- `src/server/Data/Schema.luau` (`+26/-`) — Added `gears`, `pity`, `bounty`, `activeQuest`, and starter `stars = 5`.
- `src/server/Services/CampService.luau` (`+417/-`) — Shared Sanctuary hub, South Duel Arena Ring (`z = 114, r = 24`), and 3 physical Quest Giver NPCs (`Elder Orsi`, `Scout Captain`, `Knight Envoy`).
- `src/server/Services/GrimoireService.luau` (`+215/-`) — `RollGrimoire` (`5★` + Pity), `UpgradeSkill` (Universal Ink), `1.5s` `SwapBook` cooldown, `ActiveBook` & `Clovers` attribute sync.
- `src/server/Services/LootService.luau` (`+185/-`) — Capped Backpack, `+25%` War Mode coin bonus, `+15%` Full-Bag extraction bonus, `BuyGear`, Boots-scaled Recall, Backpack-scaled death drop, `Gear*` & `BagFull` attribute sync.
- `src/server/Services/ProgressionService.luau` (`+97/-`) — `AcceptQuest` handler, Robe Max HP bonus, Star rewards.
- `src/server/Services/EnemyService.luau` (`+368/-`) — Wild Neutral random respawns and distinct Fire/Water/Leaf enemy & boss abilities.
- `src/server/Services/CombatService.luau` (`+5/-`) — Enemy slow/burn hook *(see Known Pending Item below)*.
- `src/server/World/EnemyLooks.luau` (`+60/-`) — Added `forest_wisp` visuals and Neutral cyan-rune `Runestone Brute` (`ashling`).

#### Client (`src/client/`)
- `src/client/Controllers/CampController.luau` (`+502/-`) — Desk Grimoire Gacha & Skill Upgrades, Shelf, Bank, 4-Gear Shop, and Area Quest Board UI.
- `src/client/Controllers/CombatController.luau` (`+287/-`) — Floating 3D Grimoires, 4 visible 3D Gears on characters, full-backpack bulge/glow, `1.5s` swap cooldown, Boots Dash CD.
- `src/client/Controllers/HUDController.luau` (`+180/-`) — Backpack bar, Banked currencies, Stars, Bounty, War Mode toggle button, hub-only tutorial guide beam, active Area Quest display.
- `src/client/Controllers/MovementController.luau` (`+44/-`) — Boots speed, Grimoire passive speed/jump bonuses, temporary speed boosts.

#### Tools, Tests & Docs
- `tools/BuildZones.luau` (`+696/-`) — Unified `r = 0..700` Forest & Ancient Stone Ruins world builder.
- `tests/balance.spec.luau` (`+59/-`) — Updated balance/geometry/TTK assertions for `Lv 1–50`, new zones, and `ashling` HP.
- `tests/grimoire.spec.luau` (`+84/-`) — Updated tests for 11 Grimoires, fixed `Z/X/C/V` skills, Universal Ink upgrades, and Gacha odds.
- `README.md` (`+42/-`) & `docs/LAYER_ONE.md` (`+197/-`) — Updated project overview and Layer One design documentation.

---

## 6. Verification Status

- **Formatting (`stylua --check src tests tools`)**: Clean.
- **Linter (`selene src tools`)**: 0 errors, 0 warnings.
- **Unit & Balance Specs (`lune run tests/*.spec.luau`)**: 8 suites, **49 passed / 0 failed**.
- **Build (`rojo build`)**: Succeeded cleanly.
- **Roblox Studio Live Playtest (`Glowkeepers [DEV]`, Version 132)**:
  - Verified 3 Quest Giver NPCs (`Elder Orsi`, `Scout Captain`, `Knight Envoy`), 3 Areas (`Whispering Woods`, `Raider Wilds`, `Highland Ruins`), `62` spawned enemies spanning `Lv 1..50`, and **0 Lua errors**.

---

## 7. Combat Rewrite (`CombatService.luau`)

- **Shared rules (`src/shared/CombatRules.luau`, new)**: Hat/passive offense + CDR (cap 40%), Robe/Earth defense (cap 50%), Leaf regen, Boots dash CD, 4-hit combo step, per-Grimoire finishers, Permafrost chill (3 stacks → 1.2s Freeze), PvP gate, bounty reward. Client `CombatController` uses the same rules, so displayed and enforced cooldowns match.
- **PvP**: `TogglePvp` flips `WarMode` (camp only). Players may hit each other outside camp when both are in the Duel Arena Ring (`Zones.ARENA_*`, `Zones.inArena`) or both have War Mode on. PvP damage ×0.5 with the PvP type curve.
- **Deaths**: `PlayerDied` now carries `(player, pos, killer?, duel)`. Arena duels drop nothing. A War Mode kill gives the killer +1 bounty and `20 + 30 × victim bounty` coins; the victim's bounty resets.
- **4-hit M1 combo**: the 4th hit within 1.2s deals 1.5× damage with a 1.5× bolt and the Grimoire's finisher (knockback, burn, slow, poison, chill, shock, pull).
- **Spell effects**: push (knockback/pull, bosses immune), weaken, root (slow amount 1), cleanse, Mist Veil speed boost, Repulse Field shove, blink-landing strikes, and ground-line telegraphs before beams fire.
- **Tests**: `tests/combat.spec.luau` (9 tests).

> [!NOTE]
> Solo playtest verified War Mode toggle and the combo finisher (4th bolt r 2.4, 19 dmg vs 13, Fire burn ticks), with 0 Lua errors. 2-player test (Clients and Servers) verified: arena duel hits without War Mode, the kill gives a "won the duel" toast and drops no satchel; a War Mode kill gives bounty +1 and 25 coins (20 base + War Mode 25%); with only one player in War Mode, hits deal no damage. 0 Lua errors.

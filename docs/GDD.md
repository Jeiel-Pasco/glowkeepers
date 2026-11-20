# Glowkeepers: Game Design (v2, Grimoires)

> This replaces the Glowling design (archived in `archive/GDD_v1_glowlings.md`; its market research
> still applies). `GAME_SYSTEMS.md`, `CONTENT_AND_LIVEOPS.md` and `TECH_SPEC.md` still describe v1
> and get rewritten system by system as v2 is built. Every number here is a starting value to tune
> in playtests and the economy sim.

## The pitch

A real-time action RPG in a forest ringed by mountains. You head out from your camp to fight
creatures and bosses, then carry the loot home before something takes it. Your power is your
**grimoires**: typed spell books with 4 pages each. You write spells into them with ink from the
monsters you beat. Fire beats Leaf, Leaf beats Water, Water beats Fire, so you hunt the grimoires
that counter what you're fighting. Everyone wants the near-mythical **Light** and **Dark**
grimoires.

**Rule zero:** it must be fun alone. Servers start small, so every system works for one player.
Other players add to the fun but are never required.

## Core loop

```text
camp ──► go out ──► fight (XP, coins, ink, fragments, stars) ──► carry it home ──► bank it
  ▲                                                                                   │
  └──── write spells, bind grimoires, spend stat points, upgrade camp ◄───────────────┘
```

- **Minute to minute:** fight. Clicks plus 4 spell keys, dodging, swapping books to counter types.
- **Trip to trip:** each trip is a gamble. Going further pays more, but carried loot can be lost to
  death, raiders or PvP. Banking it at camp is the relief.
- **Day to day:** levels, new spells, spell levels, new grimoire types, bosses further out.
- **Week to week:** the Light and Dark chase, bounty rank, updates that add zones and spells.

## Combat

Real time, Blox Fruits style, never turn-based.

| Input (PC) | Action |
|---|---|
| Click | Basic attack, the equipped grimoire's type |
| Z X C V | The equipped grimoire's 4 spells (cooldowns only, no mana) |
| Q | Dash |
| 1 2 3 | Swap the equipped grimoire (1.5 s swap cooldown) |
| R | Recall: 5 s channel to camp, cancelled by damage |

Mobile gets the same set: an attack button, 4 spell buttons, dash, a book wheel and Recall.

**Damage:**
`base × spell level bonus (+10% per level above 1) × (1 + 2% per Spell Power point) × type multiplier ÷ (1 + 2% per Defense point)`.

**Your type when hit** is your equipped grimoire's type. Neutral has no weakness and no
resistance. Swapping books is offence and defence at once: switch to Water when a Fire player
comes at you.

## Types

| Attack ↓ / Defender → | Neutral | Fire | Water | Leaf | Light | Dark |
|---|---|---|---|---|---|---|
| Neutral | 1 | 1 | 1 | 1 | 1 | 1 |
| Fire | 1 | 1 | 0.67 | **1.5** | 1 | 1 |
| Water | 1 | **1.5** | 1 | 0.67 | 1 | 1 |
| Leaf | 1 | 0.67 | **1.5** | 1 | 1 | 1 |
| Light | 1.25 | 1.25 | 1.25 | 1.25 | 1 | **1.5** |
| Dark | 1.25 | 1.25 | 1.25 | 1.25 | **1.5** | 1 |

- **Light and Dark balance:** nothing resists them, but their spells have about 15% lower base
  power and slightly longer cooldowns than an element spell of the same rarity. A skilled player
  with the right element book can still beat them.
- **Later types** (Stone, Storm, Frost, ...) arrive in updates, each with its own zone and boss.

## Grimoires

- **Start:** every player has a **Neutral** grimoire. Finishing the tutorial quest lets you
  **pick one free element grimoire** (Fire, Water or Leaf), with its first spell already written.
- **Blank grimoires** are sold at the camp shop for coins. Bind one into a type at your desk with
  **5 Binding Fragments** of that type plus coins. Fragments drop from that type's bosses.
- **Duplicate types are fine.** Two Fire books can carry different builds: damage and support.
- **Equipped:** 3 at a time (4 with the game pass); the rest sit on your camp shelf. Equipped
  grimoires are never dropped or lost.
- **Light and Dark:**
  - **Fragments:** drop only from Dark-zone world bosses, at about 2%.
  - **Ink:** drops only from Dark-zone enemies.
  - **Robux:** a Light or Dark grimoire can also be bought, and comes with 1 random spell from its
    pool.

## Spells

- **Pages:** each grimoire has 4.
- **Rarity:** fixed per spell; rarer spells are stronger and flashier. Element rarities are
  Common, Rare, Epic and Legendary. Mythic exists only in Light and Dark.
- **Pool per type at launch:** 6 spells covering 3 attacks, 1 defence, 1 utility and 1 movement.
  Updates add about 2 per type until each pool reaches about 10.
- **Writing:** at your camp desk, spend 1 ink of the book's type to write a random spell from
  that type's pool.
  - **Star write:** also spend stars to raise the Legendary and Mythic odds.
  - **Duplicate:** writing a spell you already have levels it up (max level 5).
  - **Full book:** you choose a page to replace, or tear the new spell out for a 50% ink refund.
    No write is ever wasted.

**Write odds (starting values):**

| Write | Common | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|---|
| Element ink | 60% | 30% | 8% | 2% | — |
| Element ink + 10 stars | 40% | 35% | 15% | 10% | — |
| Light/Dark ink | — | 55% | 33% | 10% | 2% |
| Light/Dark ink + 25 stars | — | 35% | 35% | 22% | 8% |
| Robux "Legendary+" ink | — | — | — | 85% | 15% (Light/Dark only) |

- **Disclosure:** paid odds are always shown.
- **Regional blocking:** paid random items are hidden where policy forbids them (`PolicyGate`).

### Launch spell lists

Names and roles only; numbers come with the combat prototype.

| Type | Common | Common | Rare | Rare | Epic | Legendary |
|---|---|---|---|---|---|---|
| **Neutral** | Arcane Bolt (projectile) | Pulse (burst around you) | Ward (shield) | Mend (heal over time) | Blink (short teleport) | Force Lance (piercing beam) |
| **Fire** | Ember Shot (projectile) | Flame Burst (close burst) | Heat Shield (shield that burns attackers) | Scorch Dash (dash, fire trail) | Kindle (burn debuff and power buff) | Meteor Fall (big area) |
| **Water** | Tide Bolt (projectile) | Splash Ring (burst around you) | Mist Veil (damage cut, brief fade) | Riptide (surf dash) | Undertow (slow and pull) | Tidal Wave (wave across an area) |
| **Leaf** | Thorn Dart (projectile) | Bramble Burst (close burst) | Bark Skin (damage cut) | Leaf Glide (leap and glide) | Vine Snare (root) | Elder Wrath (line of erupting roots) |

| Type | Rare | Rare | Epic | Epic | Legendary | Mythic |
|---|---|---|---|---|---|---|
| **Light** | Sunbolt (projectile) | Blessing (heal and buff) | Radiant Ward (shield that reflects) | Dawnstep (teleport) | Halo Burst (area blind) | **Judgment Ray** (huge beam) |
| **Dark** | Shade Bolt (projectile) | Hex (weaken) | Umbral Shroud (damage cut, fade) | Shadowstep (teleport behind) | Night Maw (area pull and damage) | **Eclipse** (darkens the area, huge damage) |

## Getting stronger

- **Levels:** cap 60 at launch. XP comes from enemies, bosses and quests.
- **Stat points:** 3 per level, spent on **Health**, **Spell Power** or **Defense**. A reset costs
  coins.
- **Spells:** rarity, spell levels, and the right types for the fight.
- **No gear at launch.** Wands and robes could come later.

## The world

One big, seamless map. There are no barriers: zones get more dangerous the further they are from
camp.

| Ring | Levels | Zones |
|---|---|---|
| Centre | — | **Camp hub**: plots spread round it in clearings, the shop, a quest giver, the Arena next door |
| Inner | 1–20 | **Emberfall Ridge** (Fire): red rock, ash trees, lava cracks. **Mistfall Basin** (Water): waterfalls, a misty lake, boardwalks. **Elderwood** (Leaf): giant trees, roots, glowing mushrooms |
| Middle | 20–40 | Blend zones where two elements meet (a steaming hot-spring marsh for Fire and Water, ...) |
| Outer | 40–60 | **Hollow Peaks** (Dark zones, PvP on): snowy summits in purple fog, ruined shrines. The Light temple is on the highest peak; the Dark cave is beneath |

**Each zone has:**
- **A shrine:** a quest giver and fast travel.
- **Enemies:** 3 kinds, for example a swarmer, a tank and a ranged caster.
- **A boss:** shared by the server, respawning every 5–8 minutes, with health that scales with the
  number of attackers.

**Fast travel** between discovered shrines works only with empty pockets. With loot you walk, or
Recall to camp.

**Day and night:** the cycle stays. At night enemies are tougher and Dark-tinted, and ink drops
are better.

### Enemies and bosses

- **Inner-ring starter bosses** (about level 10, for example the Cinder Golem in Emberfall) are
  beatable solo with a Neutral book.
- **Boss credit:** anyone who deals at least 10% of a boss's health gets a full drop roll and full
  stars.
- **Over-levelled players:** anyone more than 15 levels above a boss gets no drops and no stars
  from it, so high levels can't farm starter bosses.
- **Raiders:** Neutral, weaker than zone enemies, and they patrol the trails between camp and the
  zones.
  - **Targets:** players carrying the most loot; anyone with empty pockets is ignored.
  - **Stealing:** a hit steals some carried coins or ink into the raider's sack.
  - **Getting it back:** the victim who kills the raider within 60 s gets it all back plus a 10%
    bonus, capped once per raider. Anyone else gets the loot as a normal drop bag. If the raider
    escapes into the forest, the loot is gone.

## Loot, camp and risk

| Thing | Where it lives | Lost on death? |
|---|---|---|
| Coins, ink, fragments picked up on a trip | **Carried** until banked at camp | Half drops as a bag |
| Banked coins, ink, fragments | Camp bank | Never |
| Stars, XP, levels | Yours at once | Never |
| Equipped and shelved grimoires | Yours | Never |

- **Death:** respawn at camp after 5 s. Half your carried loot drops where you fell as a glowing
  bag. It lasts 2 minutes, and the killer has first claim for 10 s.
- **Leaving mid-fight:** leaving within 15 s of taking damage counts as a death. Leaving while
  safe keeps your carried loot, which is no better than a Recall.
- **Base camp:** your plot, a no-combat zone. It has:
  - **The bank.**
  - **The desk:** writing and binding.
  - **The grimoire shelf.**
  - **Upgrades bought with coins:** bank size, desk speed, shelf size, Recall speed.

## Stars

Stars are the rare currency that boosts writes toward Legendary and Mythic. They come only from
bosses, so the game works with an empty server.

| Source | Stars (starting values) |
|---|---|
| Inner-ring boss | 1 |
| Middle-ring boss | 3 |
| Arena world boss | 5 |
| Dark-zone boss | 10 |

## PvP

- **Where:** only in the Dark zones (Hollow Peaks), and in the Arena between world bosses.
  Everywhere else, including every camp, is safe.
- **The Arena:** a world boss spawns every 20 minutes and is fought together; PvP is off while it
  lives.
- **Rewards:** the victim's loot bag and **Bounty**.
  - **Earning:** a PvP kill gives bounty.
  - **Losing:** you lose some bounty when you die in PvP.
  - **Showing it:** a leaderboard, plus titles and badges at certain amounts. Status, not power.
- **Level range:** kills outside ±25% of your level give no bounty and no bag bonus, so farming
  new players pays nothing.
- **Leaving a Dark zone alive:** getting out with your loot is the thrill, and it must be
  survivable.
  - **No chokepoints:** the border is long and wide, with many ways out (ridges, paths, slopes),
    so campers can't hold one exit.
  - **Safe the moment you cross:** a camper standing just inside has to chase you back into the
    danger.
  - **Shimmer:** 2 s of protection on crossing, so nobody can one-shot you on the line.
  - **Recall works inside:** 5 s and cancelled by damage, so break line of sight first. Movement
    spells and the dash matter here.
  - **Kept in reserve:** shrines on the far side of the Peaks where you could bank part of your
    loot for a fee. Only if the playtest shows camping at the border is a real problem.

## Quests and the first 5 minutes

Each shrine has a quest giver with quests like "Defeat 8 Ember Imps" (XP and coins) and "Defeat
the Cinder Golem" (more XP plus a fragment bonus). Quests are the main way to level.

The tutorial is the hook, with a reward every minute:

| Time | Beat |
|---|---|
| 0:00 | Spawn at camp with a Neutral grimoire. A guide points to the desk |
| 1:00 | Write your first spell with a free ink |
| 3:00 | Beat a tutorial mini-boss on the trail |
| 4:00 | A raider robs you; you chase it down and get it all back, which teaches carry and bank |
| 5:00 | Bank the loot and finish quest 1. **Pick your element grimoire**, with its first spell written |

## Trading (level 20+)

- **Tradeable:** ink, fragments, blank grimoires and written grimoires.
- **Not tradeable:** stars, levels and coins, so nobody buys their way up through trades.
- **Safety:**
  - **The window** shows every item on both sides, and any change resets both confirms.
  - **Countdown:** 5 s after both confirm.
  - **Atomic:** the server swaps everything in one step, so both get their items or neither does.
  - **Session-locked saves**, so nothing can be duplicated by hopping servers.

## Monetization

Sell speed, style and convenience. The one exception is the Light and Dark grimoires, following
Blox Fruits.

| Item | Kind |
|---|---|
| 2× XP, 2× ink, 2× money | Game passes |
| +1 equipped grimoire slot (3 → 4) | Game pass |
| Bigger bank, faster Recall | Game passes |
| Grimoire covers, spell colours | Cosmetics |
| Light grimoire / Dark grimoire (+1 random spell) | Developer product, high price |
| "Legendary+" ink | Developer product, odds shown, region-gated |

## Servers

12 players per server.

## First playable slice

Build this, play it, and decide before anything else gets built.

- **The question:** is fighting, getting stronger and coming home with loot fun to you, playing
  alone?
- **In:**
  - **Places:** camp with your plot (bank, desk, shelf) and Emberfall Ridge.
  - **Grimoires:** Neutral and Fire.
  - **Enemies:** 2 enemy kinds, the Cinder Golem boss and 1 raider.
  - **Loot loop:** ink and writing, fragment drops (binding comes later), carry and bank, death
    drop, Recall.
  - **Progression:** levels 1–15 with stat points, and the tutorial beats above.
- **Cut in the same PR:** the Glowling systems. That covers:
  - **Glowlings and their economy:** rolls, lures, the Glowdex, traits, the renderer and bodies.
  - **Old v1 loops:** stealing, the base lock and shield, the night forest catch, campfire
    defence, the Stalker and downed state.
- **Kept:** the map, plots, saving, UI framework, day and night, networking, tests and build.
  Git history keeps the rest.

## Risks

- **Combat feel is the biggest risk.** There's no animator on the project. The slice uses default
  and free animation packs, plus particle and beam spell effects, and finds out whether that feels
  good enough.
- **Low player counts at launch:** shared bosses, PvP, the Arena and trading feel empty.
  Mitigated by rule zero (solo-first), solo-able starter bosses and raiders as the risk instead of
  players.
- **Spell pools run dry:** 6 per type is thin for dedicated players. Spell levels carry the chase,
  and updates add spells.
- **Pay-to-win perception:** Light and Dark are sold for Robux. Their lower base power and the
  PvP level-range rule keep a skilled free player competitive.

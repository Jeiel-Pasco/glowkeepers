# Glowkeepers: Content, Retention and Live Ops

- **Part A:** what gets built (world, creatures, art, audio, UI).
- **Part B:** how the design keeps players interested on day 1, day 30 and day 300.
- **Part C:** how the game is run after launch.

The rules and numbers this doc refers to are in [GAME_SYSTEMS.md](GAME_SYSTEMS.md).

---

# Part A: Content

## A1. Art direction

- **The hook in one image:** a dark forest, lit only by creatures. Rarer creatures glow brighter, so a rich base is visibly brighter from across the clearing. Every thumbnail and screenshot is built on that contrast.
- **Shapes:** chunky, rounded and readable at phone size. Each species is recognizable from its silhouette alone, without the glow.
- **Day:** warm, saturated and playful (a golden-hour meadow). **Dusk:** red sky, long shadows. **Night:** deep blue-black with cyan and gold light pools. The fire is the warmest light in the scene.
- **No outside IP.** Every creature is original. No meme characters.

## A2. Map: the Clearing

```
                 Deepwood (shards, rare spawns, Stalker territory)  r 160–260
          ┌───────────────────────────────────────────────┐
          │        Forest ring (wood piles, spawns)  r 100–160
          │     ┌──────────────────────────────────┐      │
          │     │   P1    P2    P3    P4           │      │
          │     │            ( FIRE )   r 0–30     │      │  Lantern Shop,
          │     │   P8    P7    P6    P5           │      │  Wisp's Stash,
          │     │   plots at r 55–95, gates face in│      │  leaderboards on the
          │     └──────────────────────────────────┘      │  inner ring
          └───────────────────────────────────────────────┘
```

**Metrics, as built in the greybox (18 Nov 2026).** These are the values in `tools/BuildGreybox.luau`, measured in Studio. They differ from the first plan in one way: eight 40-wide plots with gates 45 studs out overlap at their inner corners, which closes every gap between plots. The plots are 36 wide on a 75-stud ring instead, so the trails fit between them.

| Metric | Value |
| --- | --- |
| Fire light radius (safe from the Stalker) | 30 studs, marked by a stone circle. The light itself reaches 40, so the circle's edge is still lit. |
| Plot footprint | 36 wide × 40 deep; gate faces the fire; decoration zone 24 × 24 at the back; 30 slot pads |
| Plot ring | Plot centres at 75 studs; gates at 55, backs at 95 |
| Plot gate to fire | 55 studs (25 from the safe edge), 2.5 s at run speed |
| Plot to neighbouring plot | 57 studs centre to centre; the narrowest gap between plots is 8.8 studs |
| Steal run across the ring | Gate to opposite gate is 110 studs: 5.9 s carrying, plus the run from slot to gate inside the plot. 6–9 s in total, long enough for a chase. |
| Stations (shop, stash, boards) | On the inner ring at 42 studs, in the 4 gaps without a trail; the farthest gate is 4.3 s away |
| Trails | 4, 6 studs wide, from the stone circle out through the gaps between plots to the deepwood |
| Clearing | 0–100 studs |
| Forest ring | 100–160 studs, with 16 wood piles and 60% of wild spawns (24 points) |
| Deepwood | 160–260 studs, with 12 glow-shard points and 40% of wild spawns (16 points) |
| Total radius | 260 studs; an invisible wall, with thickening trees out to 276 |
| Greybox size | 810 trees, 2,135 parts |

The Lantern Shop, the Wisp's Stash (tutorial steal), the leaderboard boards and a "What's new" board stand on the inner ring between plots, so they're always within 10 s of any base.

## A3. Species roster (40 at launch)

Any species can come in any rarity. Rarity changes the glow, particles and scale, not the model.

**Clearing pool (16): from lures and nights**

| # | Species | Look |
| --- | --- | --- |
| 1 | Glimmermouse | Round mouse, glowing tail tip |
| 2 | Puffwick | Dandelion puff with a candle-flame top |
| 3 | Mothlet | Fat little moth with lantern wings |
| 4 | Dewdrop Slime | Clear jelly drop with a light inside |
| 5 | Lanternbug | Beetle with a paper-lantern shell |
| 6 | Sparkhop | Frog that sparks when it lands |
| 7 | Pebblepup | Puppy made of glowing river stones |
| 8 | Fuzzlight | Caterpillar with light-bulb segments |
| 9 | Bloomkit | Fox kit with a flower for a tail |
| 10 | Snailspark | Snail with a crystal shell |
| 11 | Cinderchick | Chick with ember feathers |
| 12 | Moonbun | Bunny with crescent ears |
| 13 | Acorn Imp | Acorn-capped sprite |
| 14 | Firefly Pip | Firefly the size of a fist |
| 15 | Sproutling | Seedling with a light-bulb bud |
| 16 | Mushpup | Puppy with a mushroom cap |

**Deepwood pool (24): nights only**

| # | Species | Look |
| --- | --- | --- |
| 17 | Wispfox | Fox made of smoke and light |
| 18 | Owlumen | Owl whose eyes are lamps |
| 19 | Lumoth | Giant moth with patterned wings |
| 20 | Fawnfire | Fawn with ember spots |
| 21 | Mossbear | Bear cub with glowing moss |
| 22 | Otterglow | Otter that carries a glowing pebble |
| 23 | Embercat | Cat whose tail is a flame |
| 24 | Shadebat | Bat with stained-glass wings |
| 25 | Prismbeetle | Crystal beetle that splits light |
| 26 | Thornhog | Hedgehog with light-tipped spines |
| 27 | Bramblepup | Wolf pup wrapped in glowing vines |
| 28 | Spore Toad | Toad that puffs glowing spores |
| 29 | Lightjelly | Floating jellyfish of the forest |
| 30 | Rootling | Walking root bundle with a core light |
| 31 | Lumingale | Songbird that glows when it sings |
| 32 | Antlerlight | Stag with lantern antlers |
| 33 | Comet Ferret | Ferret trailing a comet tail |
| 34 | Gloom Raven | Raven with starfield feathers |
| 35 | Glowworm Wyrm | Long, serpent-like glowworm |
| 36 | Aurora Lynx | Lynx with an aurora mane |
| 37 | Skywhale Calf | Tiny floating whale |
| 38 | Elder Sapling | Ancient treant sprout |
| 39 | Emberwing | Phoenix chick |
| 40 | Lunadrake | Moon-dragon hatchling |

**Limited species, weeks L0–L12:** Koilight (paper-lantern koi), Crimson Mothlet, Frostwhisker, Bloom Bunny, Starfall Kit, Tidepup, Auroraowl, Ember Koi, Mossling Twins, Glasswing, Comet Pup, Lantern Drake, Swamp preview species.

## A4. The Stalker, kept to a Mild rating (D16)

- **What it is:** "the Hollow", a tall, faceless silhouette made of absence-of-light, with two gold eye glints. It's eerie, not gory.
- **How it scares:** anticipation, not shock. A heartbeat layer that rises as it gets closer, light dimming at the screen edges, a breath sound, eyes in the trees. The lunge is always telegraphed.
- **What happens when it catches you:** you freeze in shadow, tinted blue, and wait for a friend. No wounds, no blood, no death animation, no screams.
- **Calm mode:** removes the stinger and screen shake, and gives the Hollow a softer, rounder silhouette.
- **Before beta:** answer the questionnaire's fear questions honestly with the real build, in week 7. If the answers land above Mild, tone the Stalker down rather than lose the 9–12 audience.

## A5. Other asset lists

**Rarity visual language** (on top of the base model):

| Rarity | Glow | Extra |
| --- | --- | --- |
| Common | Dim, steady | — |
| Uncommon | Steady, a bit brighter | Soft rim light |
| Rare | Pulsing | Slow drifting motes |
| Epic | Bright | A halo ring |
| Legendary | Very bright | Flame crown and a light beam into the sky (visible from the forest) |
| Mythic | Brilliant | Orbiting runes, its own hum, scale ×1.15 |
| Secret | Unique per species | One-off effect, a server-wide announcement, scale ×1.25 |

**Mutations:** Golden (gold sheen and sparkle), Rainbow (cycling hue, no strobe when reduced flashing is on), Moonlit (silver halo with moon-phase particles).

**Decoration set 1 (24 items, Embers):**
- Lights: string lights, paper lanterns, glow mushrooms, crystal lamp
- Banners ×3
- Paths: stepping stones, moss path, plank path
- Fences ×2, hedge
- Flower bed, stump seat, log bench, pond, little bridge
- Glowling statue (shows your trophy species)
- Owl totem, firefly jar, star arch, welcome sign

**Audio (SD):**
- Day: a light acoustic loop
- Dusk: the horn, plus a tension pad
- Night: layered ambience, adaptive to the fire % (the crackle thins as it drops) and to Stalker distance (the heartbeat layer)
- Dawn chime
- Roll stingers ×7, one per rarity, plus a near-miss whoosh
- Steal alarm, tag snap, delivery jingle, lock clunk, revive swell
- All music is either commissioned or from Roblox's licensed library, with the rights recorded.

**UI screens (GS), in priority order:**
- **P0:** HUD, roll reveal, shop, inventory/slots, dawn results, offline popup, settings
- **P1:** Glowdex with the odds tab, rebirth, quests and gift, goal tracker, store, Night Pass, trade
- **P2:** decoration mode, leaderboards, codes, what's new

## A6. Budgets

These are summarized from TECH_SPEC §11. Glowling models are at most 1,500 tris (3,000 for Legendary and above), with one atlas per species. The rarity VFX are shared emitter templates, so a new species needs no new VFX.

## A7. Weekly species pipeline

Every Friday needs 1–2 new species, so each one must take **at most 3 artist-days**:

| Day | Step |
| --- | --- |
| 1 | Concept on the shared base rig (4 rig sizes: tiny, small, medium, large). Mesh from a kit of parts (ears, tails, wings, shells). |
| 2 | Texture atlas, then idle, hop and caught animations, retargeted from the rig library |
| 3 | Add the entry to `species.json`; check it under all 7 rarity looks and 3 mutations; phone performance check |

The content bank rule (IMPLEMENTATION_PLAN §1) means the artist is always about 4 weeks ahead.

---

# Part B: Retention design

## B1. Why players lose interest, and the counter for each

Players drift away for five reasons. Each one has a counter built into the design:

| Why players quit | What it feels like | Built-in counter |
| --- | --- | --- |
| **No visible next goal** | "What do I do now?" | The goal tracker always shows 3 goals with time estimates (§19). Every screen ends with a next step. |
| **The goal is too far away** | "That'll take forever." | Goals are spaced at every horizon (B2). Pity puts a ceiling on bad luck. Rebirth time grows slowly, with a step-down after Star 8 (D8). |
| **Sameness** | "Same thing again." | Night modifiers, a daily featured species, a weekly limited species, weekend events, new biomes and Stalkers each season, and features unlocked gradually over the first week (B3). |
| **Losing social ties** | "My friends stopped playing." | Night needs other players, plus the friend bonus, invites, crews, trading, and adjacent plots for friends. |
| **Bad feelings** | "Someone stole my best one; I'm done." | Vault, shield, victim cooldown, the no-bullying rule, chase boost, tag-back, the theft-rage gate, and optional insurance. |

## B2. The goal ladder: something at every horizon

| Horizon | Example goals | Systems |
| --- | --- | --- |
| Seconds | The next catch, the next floating "+48", the next roll reveal | Income ticker, roll reveal |
| One cycle (6 min) | Survive the night; buy the next Lantern level; land a steal | Cycle, shop, stealing |
| Session (15–30 min) | Rebirth ("~2 nights"), a Glowdex page, finishing the dailies | Goal tracker, rebirth, quests |
| Day | Daily gift, 3 quests, collecting offline Glow, the featured species | Gift, quests, offline earnings |
| Week | Limited species, weekend event, weekly quests, a weekly board placing | Events, limited pages, boards |
| Season (8 weeks) | Night Pass tiers, the new biome's species, the season Stalker | Night Pass, seasons |
| Forever | Glowdex Radiant pages, Secret hunting, Star count, a trophy base | Glowdex, rebirth, decorations |

**Design rule:** every player, at every moment, has at least one goal that's at most 1 cycle away and one that's at most 5 cycles away. The goal tracker's job is to prove it.

## B3. Feature unlock schedule: new things through the first week

New players don't see every system at once. Features unlock as play goes on, so the first week keeps producing "new thing!" moments:

| When | Unlocks |
| --- | --- |
| Minute 0 | Catch, place, earn, shop, steal (tutorial), lock |
| First night | Fire, catching, revive, Embers |
| First dawn | Daily quests, daily gift, goal tracker |
| After 3 nights | Lantern and Boots upgrades get full UI, plus the Glowdex odds tab |
| First rebirth (Star 1) | The shield ends; Glowdex page rewards; leaderboards |
| Star 2 | Decorations and the trophy pedestal |
| Star 3 + 3 play days | Trading |
| Day 7 | Weekly quests highlighted; crew invites (from L4) |
| Day 14+ | Mutation stamp sets, Silver and Gold page chases |

All of these are on the server. The UI simply shows each feature when its unlock fires, with a short "New!" moment.

## B4. Variety inside the 6-minute cycle

**Night modifiers** (25% of nights, never the same twice in a row; see GAME_SYSTEMS §2):

| Modifier | Launch? | Effect |
| --- | --- | --- |
| Fog | ✓ | The Stalker hunts by sound; +25% spawns |
| Firefly Bloom | ✓ | +50% spawns, +1 catch |
| Gusty Night | ✓ | Fire drains +25%, shards ×2 |
| Starfall | ✓ | Shards rain near the fire; the fire starts at 70% |
| Silent Night | L2 | No Stalker; spawns −25% (a breather) |
| Twin Hollows | L2 | Two Stalkers, only in servers whose median player is Star 5 or higher; +1 catch |
| Aurora | S2 | Mutation odds ×2 |
| Blood Moon | Event | ×2 luck, red night (weekends) |
| Moonlit | Event | Moonlit mutation enabled |

**Day happenings** (†, from week L2; one in 3 days): Glow Rain (30 s of Glow orbs to collect), Wandering Merchant (one rare featured lure), Golden Hour (the next 60 s of income ×2).

## B5. The arc by lifecycle stage

| Stage | What the player is doing | What brings them back | KPI | If it misses (lever) |
| --- | --- | --- | --- | --- |
| **First 60 s** | Free lure, first income | — | Bounce < 15% | Faster first reward, clearer arrow |
| **Session 1** | First steal, first night, first Rare | A goal is set at dawn | Session ≥ 16 min | First-night scare, a shorter first day |
| **D1** | Offline Glow pile, gift, quests, restock | Offline earnings and the daily gift | D1 ≥ 22% | A bigger offline popup, a day-2 gift |
| **D2–7** | First Epic, rebirths 1–5, first Legendary, decorations, trading | Rebirth goals, friends, unlocks | D7 ≥ 9% | Move the first Legendary earlier (more Epic lure stock), friend invites |
| **D8–28** | Mythic hunting, Glowdex pages, limited species, Night Pass | Weekly content, social life | D30 ≥ 5% | More limited species, crew features, Fuse |
| **D29–90** | Star 10+, Silver and Gold pages, crews, season 2 | New seasons, mastery, status | Monthly returners | Eclipse, crew seasons (the rebirth step-down already ships at launch) |
| **D90+** | Radiant pages, Secret hunting, base showpiece, trading | Identity and community | Share of veterans in CCU | Veteran cosmetics, a hall of fame, creator codes |

**Casual players and Stars.** In the sim, casual players (24 minutes a day) reach Star 8 around day 30 and Star 9 by day 60. After the first month their goals have to come from the Glowdex, limited species and the Night Pass, not from Stars. Check the goal tracker with casual profiles first.

## B6. Social retention

- **The night needs people.** One player can't feed a fire for eight. Revives are rewarded more than any steal.
- **Friends get bonuses:** +10% Embers each (up to +30%), adjacent plots, invite rewards, and a friend-request prompt after a revive.
- **Crews (L4)** give a small group identity, a shared fire bonus, and a board to climb together.
- **Trading** gives veterans a reason to log in for other people, as well as for themselves.
- **Stories:** steals, saves and Mythic announcements are visible to the whole server. They're the moments players retell and record.

## B7. Comebacks and anti-frustration

- **Welcome back** (7 or more days away): a gift, plus 3 nights of +25% luck. Nothing is lost while they're away. There is no streak to reset.
- **Bad luck:** pity at 150, and the counter is always shown.
- **Theft:** see B1. If the theft-rage gate fails, turn on the GDD's levers in this order: more vault slots, then insurance, then a shorter day.
- **Failure moves you forward:** a lost night still pays Embers and XP, and costs only 5% of Glow.

## B8. Responsible design (non-negotiable)

The audience is mostly children. These rules apply to every feature and every live-ops beat:

1. **Natural stopping points:** dawn is presented as a good place to stop. The offline cap is generous, so logging off costs nothing.
2. **No streak punishment:** gifts and calendars accumulate. Missing a day never resets anything.
3. **No pressure to buy:**
   - no purchase prompts on loss, theft or failure screens
   - no countdown timers on offers
   - no fake "was" prices
   - daily caps on developer products
4. **Honest odds:** live odds for every roll are in the Glowdex, and probability boosts are shown.
5. **Nothing random for Robux, and nothing random for Robux-bought currency** (Embers).
6. **Humane fear of missing out:** every limited species comes back once within 6 months. Events announce their end date clearly, but there are no "last chance!" pop-ups.
7. **Kindness pays:** revives earn the most Embers. Quick chat includes "GG" and "Thanks!", and there are no taunt emotes.
8. **Break reminder** on by default (after 2 hours, at dawn).
9. **Notifications:** opt-in only, events only, at most once a week.
10. **Safe text:** preset names everywhere. Chat runs on TextChatService.

When a KPI lever conflicts with this list, this list wins.

---

# Part C: Live ops

## C1. Weekly operating rhythm

| Day | Activity |
| --- | --- |
| Mon | KPI review against the playbook (C7); pick this week's levers; check the bank is 4 weeks deep |
| Tue–Wed | Build the Friday feature or fixes; the artist finishes species N+4 |
| Thu | Code freeze; QA on BETA; patch notes; write the "What's new" board copy |
| Fri ~15:00 UTC | Publish with "Migrate to latest update"; the weekend event starts; post to the community; experience notification (opted-in players, events only) |
| Sat–Sun | On call; watch the Error Report and exploit flags |

**Every Friday update needs something a player can see within 10 seconds of joining:** a new species in the forest, a new item on the shop's featured slot, or a new board. It also needs patch notes in the game description and on the in-world "What's new" board.

## C2. Content bank and pipeline

- Always hold 4 weeks of finished content: species, event configs, decoration sets.
- Event configs are data (LiveConfig and `events.json`), so an event costs no code once its template exists.
- Content can slip a week. The cadence can't: if a feature slips, ship an event plus a species that Friday.

## C3. Calendar: launch to Season 3

Season 1 is "First Light", 19 Feb – 15 Apr 2027.

| Week | Friday | Update (feature) | Weekend event | Limited species |
| --- | --- | --- | --- | --- |
| L0 | 19 Feb | **Launch** | Lantern Festival: ×2 Embers; a festival lantern skin for surviving 3 nights | Koilight |
| L1 | 26 Feb | Fixes from launch data; decoration set 2 | Blood Moon (×2 luck) | Crimson Mothlet |
| L2 | 5 Mar | Night modifiers: Silent Night, Twin Hollows; day happenings | Glow Rush (×2 Glow) | Frostwhisker |
| L3 | 12 Mar | **Fuse** | Moonlit Night | Bloom Bunny |
| L4 | 19 Mar | **Crews** and the crew board | Crew Night (crew fire bonus ×2) | Starfall Kit |
| L5 | 26 Mar | **Base themes**; spring decorations | Spring Bloom, 27–28 Mar (Easter weekend) | Tidepup |
| L6 | 2 Apr | Trade quality-of-life: history, value hints | Firefly Festival (spawns ×2) | Auroraowl |
| L7 | 9 Apr | Weekly boards; 5 new badges | Blood Moon | Ember Koi |
| **L8** | **16 Apr** | **Season 2, "Swamp Lights"**: Swamp biome (+8 species), the Bog Hollow Stalker, Night Pass S2, Mossy seasonal mutation | Season launch: ×2 pass XP | Mossling Twins |
| L9 | 23 Apr | Swamp quality-of-life; Aurora modifier | Moonlit Night | Glasswing |
| L10 | 30 Apr | Community goal system v2 | Community goal weekend | Comet Pup |
| L11 | 7 May | Hall of fame (first Radiant pages) | Blood Moon | Lantern Drake |
| L12 | 14 May | Summer warm-up: decoration set 3 | Glow Rush | Swamp rerun (first limited rerun) |
| **L16** | **11 Jun** | **Season 3, "Frost Hollow"**, timed for the start of US/EU school holidays (the biggest Roblox period). Tundra biome, the Frost Hollow Stalker, and Eclipse if the D30 plateau data calls for it. | Summer kickoff | — |

Season 4 (Crystal Caves) lands around 6 Aug 2027, and a Halloween season around October. Plan both from data in May.

## C4. Event template library

| Template | Mechanics (LiveConfig) | Best for |
| --- | --- | --- |
| Blood Moon | `luckMult 2`, red night palette | A reliable weekend lift |
| Moonlit Night | Moonlit mutation on (1 in 100, ×10) | Collector excitement |
| Glow Rush | `glowMult 2` by day | Rebirth pushes |
| Firefly Festival | `spawnMult 2`, firefly VFX | New-player weekends |
| Crew Night | Crew fire bonus ×2 | Social pushes |
| Lantern / Seasonal | `embersMult 2` plus a cosmetic for N nights survived | Holidays |
| Community Goal | A global counter with tiered rewards for all participants | Big weekends |
| Double XP | `passXpMult 2` | Season start and end |

## C5. Codes and milestones

- Like and favourite milestones (10K, 50K, 100K likes…) unlock codes worth 50–200 Embers, announced on the game page and the in-world board.
- Codes only give Embers or lures, and each works once per account.

## C6. Discovery and the store page

- **Icon and thumbnails:** run one A/B test at a time, judged on play-through rate.
  - The icon shows one bright creature against darkness.
  - Thumbnail 1 shows the steal chase. Thumbnail 2 shows the night around the fire.
- **Title tag convention** while something is live: "Glowkeepers [UPDATE] 🔥" or "[EVENT] Blood Moon". Remove it when the event ends; no false urgency.
- **Roblox Events:** list each weekend event so players can tap "Notify me".
- **Sponsored ads:** a small budget at soft launch and on each season launch. Scale up only when D1 and play-through rate beat similar games.

## C7. KPI playbook: when a metric moves, do this

Review every Monday. Use Creator Analytics, the AnalyticsService funnels, and the economy dashboard.

| Signal | Threshold | Likely cause | First lever (cheapest first) |
| --- | --- | --- | --- |
| First-play bounce | > 15% | First reward too slow, or the hook isn't clear | Make the FTUE step 1 arrow more obvious; Free Lure within 5 s; cut loading time |
| Funnel: `first_dusk` → `first_dawn` | < 80% | Night too scary or confusing | Stronger near-miss; louder "stay by the fire" cues; check Calm-mode use |
| D1 | < 22% | Weak reason to return | A bigger offline popup and a day-2 gift preview; clearer goal at first dawn |
| D7 | < 9% | First Legendary too slow, or players alone | Raise Epic lure stock (the sim's biggest lever on first-Legendary timing; pity barely moves the median); friend-invite prompts; earlier decoration unlock |
| D30 | < 5% | Plateau or sameness | More limited species and modifiers; pull Fuse or Crews earlier; check rebirth wait times |
| Session length | < 16 min | Cycle feels finished after one night | Session goal at dawn, day happenings, "2 more nights" goals |
| `theft_rage_quit` rate | > 5% of steals | Theft too punishing | More vault slots, then insurance, then a longer victim cooldown |
| Steals per day phase | < 1 per server | Stealing feels pointless or scary | Shorter grab holds; better loot display; steal quest weight up |
| Fire lost rate | > 40% or < 5% of nights | Night too hard or too easy | Tune `drainPerPlayer`, the wood value, shard spawns |
| Glow inflation | Median Glow/s well above sim at the same day | A faucet leak or exploit | Audit sources; check exploit flags; retune |
| Payer conversion | Falling while D7 holds | Weak or poorly placed store offers | Improve store presentation. **Never** add pressure tactics (B8). |
| Co-play | < 40% of sessions | Weak social pull | Bigger friend bonus; invite rewards; crew promotion |

## C8. Community

- A Roblox Community (group) for the game: announcements, beta-tester roles, codes.
- Off-platform channels (such as a Discord server) are for players 13 and over only, and are never linked in-game for under-13s.
- Player feedback goes into the Monday review. Credit creators of bug reports and ideas in the patch notes, with their consent.

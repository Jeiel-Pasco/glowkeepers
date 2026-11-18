# Glowkeepers: Implementation Plan

This plan turns the design doc ([GDD.md](GDD.md), copied from *Glowkeepers Viral Roblox Game Project Plan*, 18 Nov 2026) into a Roblox experience. The target is a public launch on **Friday 19 February 2027**, then an update every Friday after that.

| Doc | What it covers | Main readers |
| --- | --- | --- |
| **IMPLEMENTATION_PLAN.md** (this) | Scope, design decisions, schedule, task lists by role, gates, QA, release checklist, launch runbook | Everyone |
| [TECH_SPEC.md](TECH_SPEC.md) | Toolchain, architecture, data schema, remotes, security, performance, analytics, ops tools | Scripters |
| [GAME_SYSTEMS.md](GAME_SYSTEMS.md) | Rules, numbers, edge cases and acceptance tests for every system | Scripters, designer |
| [CONTENT_AND_LIVEOPS.md](CONTENT_AND_LIVEOPS.md) | World, species, art/audio/UI lists, retention design, live-ops calendar, KPI playbook | Artists, designer, producer |

---

## 1. What "ready to release" means

The game goes public only when all six are true:

1. Every **Launch** item in §2 is built and has passed its acceptance test in GAME_SYSTEMS.md.
2. Playtest gates **G1–G5** (§6) have passed.
3. The closed beta reached **D1 ≥ 20%** and an **average session ≥ 15 min** (the GDD's beta gate).
4. There are no open P0/P1 bugs and no known duplication or currency exploits.
5. The release checklist (§8) is complete, including Roblox's Maturity & Compliance questionnaire.
6. **Four weeks of post-launch content is built and banked**: 4 limited species, 4 weekend events and 2 Friday feature updates. A weekly cadence only holds up if launch week isn't also content week.

Long-run targets, from the GDD KPI table: D1 ≥ 22%, D7 ≥ 9%, D30 ≥ 5%, average session ≥ 16 min, ≥ 3 sessions a day, ≥ 40% of sessions with a friend, first-play bounce under 15%.

---

## 2. Scope

### Launch (ships 19 Feb 2027)

| Area | Included at launch |
| --- | --- |
| Core cycle | 8-player server, 6-minute day/night, dusk warning, 4 night modifiers |
| Day | Glow income, display slots (8 → 30), vault, storage bag with Release, Lantern shop with a 5-minute restock, lures, upgrades (Lantern, Boots, Slots), stealing with carry, tag-back and chase boost, Base Lock, new-player shield |
| Night | Campfire meter, wood and glow-shards, wild Glowling catching, Stalker AI, downed/revive, dawn results |
| Meta | Rebirth/Stars, Glowdex (40 species, 4 page tiers), decorations, trophy pedestal, daily and weekly quests, daily gift, goal tracker, leaderboards, badges |
| Social | Trading (gated), friend invites, friend co-play bonus, server announcements, "GG" thanks |
| Season | Night Pass Season 1 (free and premium tracks) |
| Money | 4 game passes and 6 developer products (Night Pass Premium, 3 Ember packs, Lock Charge ×3, Server Luck), PolicyService gating, daily purchase caps |
| Live ops | Event engine, weekly limited-species rotation, live config with kill switches, codes |
| Platform | Phone, tablet, PC and console controls, automatic translation, settings (Calm mode, reduced flashing, break reminder), analytics, admin tools, data-deletion procedure |

### Scheduled after launch (first 8 weeks, detail in CONTENT_AND_LIVEOPS.md §C3)

Fuse (week L3), Crews (L4), base themes (L5), weekly leaderboards (L7), and Season 2 (L8).

### Later (backlog; build only if the data asks for it)

Eclipse (a second prestige layer), crew wars in private servers, companion Glowlings that follow you, an asynchronous trading post.

### Deliberately never built

Paid random items. Glow sold for Robux. Legendary-or-better sold directly. Theft immunity. Voice chat. Free-text naming (base and crew names use preset word lists).

---

## 3. Decisions that change or fill gaps in the GDD

The GDD's loop and maths hold up, but some rules conflict and some are missing. This plan makes the calls below.

- **sim**: changes the economy. Every one was run through `sim/sim_v3.py` on 18 Nov 2026, against your original `sim.py` as the baseline. Results are in [sim/README.md](../sim/README.md). **sim ✓** means verified.
- **approved**: a product call, signed off on 18 Nov 2026.

| # | The GDD says | The problem | Decision | Tag |
| --- | --- | --- | --- | --- |
| D1 | The fire starts at 60% and drains 0.1%/s per living player | With 4 or fewer players, the night's total drain is at most 48%, which is below the 60% start. The fire can't go out even if nobody feeds it, so small servers and private servers have no stakes at night. | Drain per second = **0.5% + 0.0375% × living players**. At 8 players this is the same as the GDD (0.8%/s, 96% a night). At every server size, the fire needs about 1.5 pieces per player to break even, and about 2 to be safe. | approved |
| D2 | Risks section: new players are shielded until their first rebirth. FTUE: protection ends after the first night. | The two rules contradict each other. | The shield lasts until the first rebirth or 45 minutes of play, whichever comes first. Stealing from a human ends it early. Shielded bases show a bubble. | approved |
| D3 | Rebirth wipes everything except your single best Glowling | Players lose Mythics they traded or fought for. That breaks the "my base is my trophy room" pillar and makes traded Glowlings worthless. | Rebirth **keeps what's in the vault** (3 + Stars slots), plus your single best Glowling if it isn't already in the vault. Display and storage Glowlings are still wiped. Sim: first-Legendary timing moves by a day at most. | sim ✓, approved |
| D4 | A lure "can roll higher", but "Legendary+ only from nights" | The two statements conflict. The GDD's milestone table came from a sim where lures *do* roll higher: about 60% of first Legendaries came from Epic lures. | Keep the sim's rule. A lure's **floor** is capped at Epic, but its **roll can go higher**. Capping results at Epic pushed casual players' first Legendary to day 14–16 in the sim. Correct the GDD line to "Legendary+ comes mostly from nights". | sim ✓ |
| D5 | Embers buy a "pity skip", and Embers are sold for Robux | A probability modifier bought with Robux-purchasable currency falls under Roblox's paid-random-items rules. | Remove the pity skip and show the pity counter instead ("Legendary guaranteed within 37 catches"). Rule: **Embers never buy anything random.** | approved |
| D6 | Lock Charge is "a small impulse buy at the moment of a theft" | That contradicts the GDD's own rule of no countdown pressure on purchases, for an audience of children. | Lock Charges are sold in the shop and the store only. The game never prompts a purchase during or right after a theft. | — |
| D7 | The FTUE timings start at 0:00 of a cycle | The cycle is shared by the whole server, so a new player can join at any phase, including night. | The FTUE adapts to the phase: a **Day path** and a **Night-first path**, each driven by events rather than the clock (GAME_SYSTEMS §22). | — |
| D8 | Rebirth thresholds grow 3.2× forever | Progress stalls. In the 60-day sim, engaged players reach Star 10 on day 31 and gain about 1 Star in the following month. Thresholds pass 2^53 at Star 22. | **From launch, growth drops to 2.0× after Star 8.** Engaged players then reach Stars 10/11/12 at days 30/45/60 (instead of 10/10/11), and each rebirth takes 1.1–1.4× the last. Stepping only after Star 10 barely helped. Thresholds now pass 2^53 at Star 30, so a CI test guards Star 28 and an alert fires at Star 25. | sim ✓ |
| D9 | No rule for duplicates or a full inventory | 3 or more catches a night, plus lures, overflows any base | Add a **storage bag of 60**. Release gives 60 seconds of that Glowling's income as Glow. Fuse (5 → 1 of the next tier, up to Epic) ships after launch in week L3. Sim: no measurable effect on milestones. | sim ✓ |
| D10 | The Glowdex counts "first catches only (trades don't count)" | Steals and lure rolls aren't covered | Night catches and lure rolls count. Steals and trades don't. | — |
| D11 | The thief "can be chased back" | Swift Boots (+15%) cancel the carry slow (−15%), so a thief who paid for Swift Boots can't be caught | When a Glowling is grabbed, its owner hears an alarm and gets a **+20% chase boost for 10 seconds**. | playtest (the sim can't model a chase; tune the theft rate in G2) |
| D12 | "5% Ember fee per trade" | Glowlings have no Ember value to take 5% of | A flat Ember fee per Glowling, set by rarity (GAME_SYSTEMS §17) | approved |
| D13 | The Lantern shop restocks every 5 minutes | What restocks isn't defined, and the sim assumed unlimited lures | Each player gets their own lure stock per restock: **16/8/4/2** for Common/Uncommon/Rare/Epic, plus one featured slot. The timer is aligned to UTC, so every server restocks at the same moment. Sim: 8/4/2/1 delayed casual players' first Legendary to day 8–9; 16/8/4/2 keeps it at day 7. | sim ✓ |
| D14 | Night Pass is "Pass / Embers" | Unclear | A free track and a premium track. Premium costs 399 R$ or 3,500 Embers. | approved |
| D15 | "Every number in the simulation section comes from its final run" of `sim.py` | It wasn't in the project | **Done.** `sim/sim.py` is your original. `sim/sim_v3.py` reads `config/economy.json`, the file the game will load, and reproduces sim.py's results exactly. | done |
| D16 | The audience is 9–16 and the game has a horror monster | If the Stalker is rated past Roblox's **Mild** content label, the game becomes 13+ (the age line at the time of writing; check the current rules) and loses the 9–12 audience. | Design the Stalker to Mild: no gore, scares built on telegraphing and sound, and a Calm-mode setting. Submit a practice questionnaire in week 7. | approved |
| D17 | Vault slots "can never be stolen" | Whether the vault is extra slots or part of the slot count isn't stated | Part of the slot count, as the sim models it: your top 3 + Stars slots are protected. Extra slots would raise income above every tested number. | sim ✓ |

**What the plan's changes do together** (sim, 200 players per style, 30 days). The GDD's numbers are in brackets.

| | Casual (3×8 min) | Engaged (4×20 min) | Hardcore (6×45 min) |
| --- | --- | --- | --- |
| First Legendary | day 7, 100% by D30 (day 5, 92%) | day 2 (day 2) | day 1 (day 1) |
| Mythic by D30 | 30% (26%) | 68%, median day 11 (64%, day 11.5) | 99%, day 5 (98%, day 6) |
| Secret by D30 | 4% (3%) | 13% (10%) | 42% (38%) |
| Stars at D30 | 8 (8) | 10 (9) | 13 (11) |
| First Legendary from a night catch | 52% (37%) | 52% (42%) | 54% (38%) |

Theft stays income-neutral: 99% of no-theft income (GDD: 103%). More first Legendaries now come from the co-op night, which is what the GDD wanted.

---

## 4. Team and ownership

| Role | Owns |
| --- | --- |
| **LS**: lead scripter | Server framework, data, economy services, stealing, trading, monetization, security, ops tools |
| **GS**: gameplay/UI scripter | Client controllers, input, all UI, VFX hookup, Stalker AI, tutorial |
| **AR**: 3D artist | Glowlings, rarity and mutation VFX, the Stalker, decorations, Night Pass cosmetics |
| **BL**: builder/level designer | Map, lighting, navigation, plots, forest, world performance |
| **DP**: designer-producer | Economy and sim, `config/`, FTUE script, analytics, playtests, live ops, community, store page |
| **SD**: sound (part-time) | SFX, adaptive music |
| **TA**: thumbnail/icon artist (part-time) | Icon, thumbnails, event art, update banners |

Each area has one owner who has the final say: `config/` belongs to DP, `src/server/` to LS and `src/client/` to GS. Every pull request gets reviewed by one other person. Tuning happens in config, so the designer can retune without waiting on a scripter.

---

## 5. Schedule

The GDD's 12 build weeks take 13 calendar weeks because of Christmas and New Year (calendar weeks 5–6 run at half capacity).

| Cal. week | Dates | Phase | Milestone (Fridays) |
| --- | --- | --- | --- |
| 1 | 23–29 Nov 2026 | Foundations + greybox | |
| 2 | 30 Nov – 6 Dec | Foundations + greybox | **G1** mood test, Fri 4 Dec |
| 3 | 7–13 Dec | Core-loop prototype | |
| 4 | 14–20 Dec | Core-loop prototype | **G2** flip test, Fri 18 Dec (before the break) |
| 5–6 | 21 Dec – 3 Jan | Vertical slice (half capacity) | |
| 7 | 4–10 Jan 2027 | Vertical slice | **G3** 60-second and fear tests, Fri 8 Jan |
| 8 | 11–17 Jan | Content + meta | |
| 9 | 18–24 Jan | Content + meta | **G4** closed beta opens, Fri 22 Jan |
| 10 | 25–31 Jan | Beta + tuning | |
| 11 | 1–7 Feb | Beta + tuning | **G5** beta gates, Fri 5 Feb · **feature freeze** |
| 12 | 8–14 Feb | Soft launch (public, small ad spend) | Go/no-go, Fri 12 Feb |
| 13 | 15–21 Feb | Launch | **Launch Fri 19 Feb**, plus the Lantern Festival weekend (the festival falls on Sat 20 Feb 2027) |

After the feature freeze (end of week 11), the only work is bug fixes, config tuning and building the content bank.

---

## 6. Task lists by phase, and the gates

### Phase 1: Foundations + greybox (weeks 1–2)

> **Status, 18 Nov 2026: the LS code scaffold is in the repo but hasn't run yet.**
> - **Done:**
>   - Rojo project, Rokit pins, Selene and StyLua configs, CI workflow
>   - Shared pure modules: `EconomyMath`, `Economy`, `Roll`, `Cycle`, `Fire`, `Net` (with `Validate` and `TokenBucket`), `Env`, `Types`, `Signal`
>   - Server: `NetServer`; `Schema` v1 with the migration hook; `DataService` on ProfileStore, with an in-memory fallback in DEV; `CycleService`, `SettingsService`, `Telemetry`
>   - Client: `StateController`, `InputController`, `MovementController` (auto-sprint), `CycleFXController`, and the HUD skeleton
>   - Tests: a Lune spec for every pure module and the config, plus sim parity through `sim/golden_odds.json`
> - **Still open:**
>   - Install the toolchain and run the specs
>   - Copy ProfileStore into `src/server/Vendor/`
>   - Create the three experiences and fill in `config/environments.json`
>   - The first Studio playtest and CI's first run
>   - The DP sim extensions, and every GS, AR and BL task

- **LS**
  - Repo, Rojo, Wally, Selene, StyLua and CI (TECH_SPEC §1)
  - Three experiences (DEV, BETA, PROD) under the team's Roblox Community, plus environment detection
  - Service loader, the `Net` module (remote registry and rate limiter), `Types`
  - `DataService` on ProfileStore, with schema v1 and a migration hook
  - `CycleService`, with the pure `Cycle` module and its tests
  - Config loading from `config/*.json`
- **GS**
  - `InputController`: action map for touch, keyboard/mouse and gamepad, and the context action button
  - `CycleFXController`: lighting and atmosphere tweens for dawn, day, dusk and night
  - HUD skeleton: an extrapolated Glow counter and the cycle ring
- **AR**: style test with 3 Glowling silhouettes, the 7-tier rarity glow ladder, and a light-count test on a real phone
- **BL**: greybox of the clearing, 8 plots, campfire, forest ring and paths, plus a metrics sheet (plot size, distances, fire radius)
- **DP**
  - Extend `sim/sim_v3.py` with what it doesn't model yet: Boots catches, Glowdex bonuses, Embers and the Night Pass, night modifiers, VIP and Server Luck. Rerun it after every config change.
  - The analytics event list (TECH_SPEC §9) and FTUE script v1
  - Recruit 8–10 regular playtesters

**Gate G1 (Fri 4 Dec), mood test.** 4-person session. It passes if 3 of the 4 say, unprompted, that night feels different, and players drift toward the fire at dusk.

### Phase 2: Core-loop prototype (weeks 3–4)

- **LS**
  - `GlowlingService` and `InventoryService` (UUID records), and `RollService` (pure `Roll` module and tests)
  - `IncomeService`, and `PlotService` (slots and vault)
  - `StealService` (grab, carry, tag, deliver and chase boost, all validated on the server) and `LockService`
  - `CampfireService`, `ForestService` (spawns and catching) and `DownedService` (downed and revive)
- **GS**
  - `GlowlingRenderer` (builds models on the client from plot state)
  - Context-button modes (catch, grab, feed, revive), carry visuals, roll reveal v1, fire meter, lock button
  - **Stalker AI v1** (a state machine on PathfindingService)
- **AR**: the Glowling base rig and 5 species blockouts, VFX for catch, carry and tag, and a Stalker blockout
- **BL**: forest spawn zones, wood piles, pathfinding modifiers, the fire's light-radius volume, plot gates and zones
- **DP**: tune steal timings in config, then run G2

**Gate G2 (Fri 18 Dec), flip test.** 8 testers play for 30 minutes. It passes if at least 6 of them both steal and revive, and at least 2 tell a "they stole from me, then saved me" story unprompted.

### Phase 3: Vertical slice (weeks 5–7)

- **LS**: `ShopService` (restock, stock, lures), `UpgradeService` (Lantern, Boots, Slots, Lock Charges), offline earnings, session-locked save and load end to end, the shield, pity, Release
- **GS**
  - `TutorialController` with both FTUE paths
  - The full roll reveal, including the near-miss reel
  - Shop and inventory UI, the offline-earnings popup, the dusk sequence, the dawn results screen, Settings v1
- **AR**: 10 species in all 7 rarity looks, 3 mutations, the rarity VFX ladder, the Stalker v1 model and animations
- **BL**: art pass on the clearing and campfire, lighting for day, dusk and night, mobile performance pass 1
- **SD**: dusk horn, fire crackle, night ambience, the Stalker's heartbeat layer, 7 roll stingers, steal alarm
- **DP**: tune the FTUE, run G3, and submit a practice Maturity & Compliance questionnaire (D16)

**Gate G3 (Fri 8 Jan).**
- **60-second test:** at least 9 of 10 new players catch, place and earn within 60 seconds with no instructions. Both FTUE paths are tested.
- **Fear test:** players gather at the fire at dusk without being told.
- **Reach:** at least 80% of first-session testers reach their first night, and the post-session quiz shows nobody is confused about the rules.

### Phase 4: Content + meta (weeks 8–9)

- **LS**
  - `RebirthService`, `GlowdexService`, `DecorService`
  - `QuestService`, `DailyGiftService`, the Ember wallet
  - `LeaderboardService`, `BadgeService`, `NightPassService` (data side)
  - `EventService` and `LiveConfigService`
- **GS**: Glowdex UI, rebirth flow, decoration placement mode, quests and daily-gift UI, goal tracker, Night Pass UI, mobile control polish, server announcements
- **AR**: all 40 species, decoration set 1 (24 items), the trophy pedestal, Night Pass Season 1 cosmetics (lantern skins, base banners)
- **BL**: full map art, leaderboard boards, StreamingEnabled tuning, performance pass 2 (low-end Android)
- **SD**: the full SFX list and adaptive day/night music
- **TA**: the icon and 5 thumbnail concepts
- **DP**: closed-beta setup (a group role, a survey, a bug-report form) and beta communications

**Gate G4 (Fri 22 Jan): the closed beta opens to 200–500 players.** Entry criteria:
- no P0 bugs
- saves verified across rejoins and server shutdowns
- every analytics event firing in DEV

### Phase 5: Beta + tuning (weeks 10–11)

- **LS**
  - `MonetizationService` (passes, products, an idempotent `ProcessReceipt`) and `PolicyGate`
  - `TradeService` (gated, with escrow)
  - Anti-exploit hardening and the exploit test pass (§7)
  - Admin panel, ban tools, data deletion, and handling for update migrations
- **GS**: store UI, trade UI, invite prompts, opt-in prompt for experience notifications, accessibility settings, a polish and "juice" pass
- **AR**: VIP lantern skin, Server Luck VFX, the content bank (limited species for weeks L0–L4)
- **BL**: bug fixing, and a console/gamepad navigation pass with GS
- **TA**: final thumbnails, plus the Lantern Festival banners
- **DP**
  - Retune from beta data, in config only
  - Compare sim v3 with the live milestones
  - Run the theft-rage and day-3 surveys
  - Write the store page, and plan the events for weeks L0–L4

**Gate G5 (Fri 5 Feb).**
- Beta D1 is at least 20% and the average session at least 15 minutes.
- In the theft-rage survey, fewer than 20% say theft made them want to quit.
- At least 40% of players who returned on day 2 also return on day 3.
- Live milestone days are within 50% of the sim's.
- The audit log shows no duplications, and there are no open P0/P1 bugs.

If G5 fails, fix and retest. The launch date moves by a week, but the gate doesn't change.

### Phase 6: Soft launch (week 12)

1. Make the experience public, once the questionnaire is done.
2. Run a small sponsored-ad test with 2–3 thumbnails.
3. Compare play-through rate and first-play bounce with similar games in Creator Analytics.
4. Fix the causes of bounce daily.

**Go/no-go (Fri 12 Feb).** Go only if:
- play-through rate and bounce are in the top half of similar games
- no servers are crashing
- saves are healthy

### Phase 7: Launch (week 13)

See the runbook in §9.

---

## 7. Testing and QA

**Automated, on every commit (CI):**
- StyLua check, Selene and a Rojo build
- Lune unit tests for the pure modules:
  - `EconomyMath`: costs, `trySpend`, sanitizers, `formatNumber`, including the 999,950 → "1.0M" rollover
  - `Roll`: odds sum to 1, the tier cap, the lure floor
  - `Cycle`: the phase at time t
  - fire drain, offline earnings, and rebirth thresholds under 2^53
  - migrating save data from every older schema version, using stored fixtures

**On every pull request that touches gameplay:** in Studio, Test → Server + 2–8 Clients, then run that system's acceptance list from GAME_SYSTEMS.md.

**Weekly playtest (Fridays):** the current gate test, or a full 30-minute session, with a survey and a recording.

**Device matrix (from G3 on):**

| Device class | Target |
| --- | --- |
| Low-end Android (2–3 GB RAM) | ≥ 30 fps at night with 8 players and a full base |
| Mid-range Android | 60 fps by day |
| Older iPhone (SE 2 / 8 class) | ≥ 30 fps, no memory crash over 30 minutes |
| Tablet | UI scales, no overlap with safe areas |
| Low-end PC (integrated GPU) | 60 fps |
| Xbox / PlayStation | The whole FTUE can be completed with a gamepad only |

**Exploit pass (weeks 10–11).** A DEV-only fuzzer client sends:
- wrong argument types and out-of-range ids
- spam
- other players' UUIDs
- teleports while carrying a Glowling
- purchase prompts for products that don't exist

Every one must be rejected and logged (TECH_SPEC §8).

**Data tests:**
- rejoining while a save is in flight
- a server shutting down mid-trade
- the same account in two servers (the session lock holds)
- a simulated DataStore outage: players stay in the game with a "saving paused" warning and lose nothing

**Load test:** 8 players with full bases, every decoration placed and a night modifier active. The server holds a steady heartbeat, with no script over budget in the MicroProfiler.

**Bug severity:**
- **P0**: data loss, duplication, crash, or a policy breach
- **P1**: blocks the core loop
- **P2**: wrong, but there's a workaround
- **P3**: polish

---

## 8. Release checklist (Roblox)

**Experience and compliance**
- [ ] The experience is owned by the team's Roblox Community, which handles revenue sharing and permissions
- [ ] The Maturity & Compliance questionnaire is answered honestly, with **Mild** as the target (D16)
- [ ] Genre and subgenre are set, the description opens with the one-line premise, and it has no off-platform links
- [ ] Max players is 8, and a slot is reserved so friends can join a full-ish server
- [ ] Devices enabled: phone, tablet, computer, console
- [ ] Private servers are enabled (free or cheap), with the same rules as public servers
- [ ] Voice chat is off. Text chat runs on TextChatService. No free-text naming anywhere.
- [ ] Automatic translation is on, and every UI string is in the localization table
- [ ] Studio API access is on in DEV only
- [ ] The Right-to-Erasure procedure is written and tested (TECH_SPEC §13)

**Store page**
- [ ] Icon at 512×512: a glowing creature against a dark forest, readable at thumbnail size
- [ ] 5 thumbnails at 1920×1080 and one video of 30 s or less, with A/B variants ready
- [ ] A title that is the premise, and a title-tag convention for updates and events
- [ ] Launch badges created early, since free badge creation is limited per day
- [ ] A Roblox Event entry for the launch weekend, so players can tap "Notify me"

**Monetization**
- [ ] All passes and products created, with their PROD IDs in `config/products.json` and separate DEV/BETA IDs
- [ ] `ProcessReceipt` tested for duplicate receipts, the player leaving mid-purchase, and a server shutdown
- [ ] PolicyService gating checked with test accounts
- [ ] Prices checked against comparable games, and regional pricing enabled for passes

**Operations**
- [ ] Custom, funnel and economy analytics events all appear in Creator Hub
- [ ] Every LiveConfig kill switch tested: trading, stealing, Server Luck, and each product
- [ ] The admin panel is limited to group ranks, and every admin action is audit-logged
- [ ] An on-call rota for launch weekend, and an in-game banner for status messages
- [ ] A rollback plan: the previous place version in Version History, plus a config revert

---

## 9. Launch runbook (week 13)

| Day | Actions |
| --- | --- |
| Mon 15 Feb | Final content lock. Configure the L0 event in LiveConfig, disabled. Schedule the ad campaign. |
| Tue 16 – Wed 17 | Final regression on the device matrix. Dry-run the publish to BETA. |
| Thu 18 | Publish the PROD build with the event off. Smoke test with the team in PROD. |
| **Fri 19, about 15:00 UTC** | Turn on the Lantern Festival in LiveConfig. Turn ads on. Update the title, description and thumbnails. Put the Roblox Event live. Post to the community. |
| Fri 19 – Sun 21 | LS and GS are on call. Every 2 hours, DP checks the Error Report, CCU, the first-session funnel, purchases and exploit flags. |
| Mon 22 | Data review, then a hotfix list. Lock the scope of the first Friday update (L1). |

**Hotfix rules**
1. Flip a kill switch first, then fix.
2. Config-only changes can ship at any time.
3. Code fixes are published with "Migrate to latest update", so players get moved to new servers instead of being kicked.

---

## 10. Post-launch rhythm

- **Weekly**
  - Mon: review the KPIs against the playbook (CONTENT_AND_LIVEOPS.md §C7)
  - Tue–Wed: build
  - Thu: freeze, then QA on BETA
  - Fri about 15:00 UTC: publish and turn on the event
  - Weekend: on call
- **Monthly:** an economy audit (sim versus live), an exploit and duplication audit, and a roadmap review.
- **Every 8 weeks:** a new season.

---

## 11. Risks to add to the GDD's register

| Risk | Mitigation |
| --- | --- |
| Too much scope for 12 build weeks | The Launch tier is fixed, and Fuse, Crews and themes have already moved after launch. If more has to go, cut night modifiers to 2 and decorations to 12 items before cutting polish on the core loop. |
| The Stalker pushes the rating to 13+ | D16, plus a practice questionnaire in week 7 |
| The holidays cause a slip | Weeks 5–6 are planned at half capacity, and G2 happens before the break |
| Everything runs through the lead scripter | GS owns the Stalker and all client code. DP owns config, so tuning never needs code. |
| The weekly cadence burns out the team | A 4-week content bank, and a species pipeline that costs at most 3 artist-days per species (CONTENT_AND_LIVEOPS.md §A7) |
| Copycats ship first | The night co-op twist and the Glowdex are hard to clone. Keep polishing and ship every week. |
| The sim and the game drift apart | Both read `config/economy.json`. A CI parity test compares `Roll.luau` with the sim (TECH_SPEC §14). |

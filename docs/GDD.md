# Glowkeepers: Viral Roblox Game Project Plan

Nov 18, 2026 · @jeiel

## Summary

**The finding:** today's top 98 Roblox games split into two kinds. *Hook* games win new players fast: steal-and-defend tycoons, RNG collection sims and co-op horror runs. *Home* games keep players for years: social roleplay, action-RPG grinds and round-based asymmetric games. The 6 steal-tycoons on the chart hold **23% of all live players**, with a median age of under 3 months. Games 4+ years old hold **33.5%**. Last year's biggest hooks have already burned out. Steal a Brainrot (74.5B visits) and Grow a Garden (36B) now draw about 230 live players per million average daily visits, against 11,000–16,000 for Murder Mystery 2 and Adopt Me!.

**The formula:** a Hook loop for the first 10 minutes, wrapped around a Home loop for the first 28 days.

> **Viral game = (a collect-and-flex loop with visible rarity) × (a social conflict you can see in a small server) × (a co-op reason to bring friends) × (a reason to come back tomorrow) × (a weekly update cadence)**

Roblox's recommender now judges games over 28 days instead of 7, and rewards co-play and returning players. Thumbnail-bait hooks without depth lose reach.

**The game:** *Glowkeepers* is an 8-player server around a shared campfire, on a 6-minute day/night cycle.

- **By day** you run a base of glowing creatures (Glowlings) that earn Glow per second. You can sneak into other bases and steal their Glowlings.
- **By night** stealing is off and everyone must keep the campfire alive against a monster. That is the only time rare Glowlings spawn in the dark forest.

Rivalry by day and teamwork by night makes social drama that people want to share. The steal-tycoon money engine is built on top of the 99 Nights co-op horror retention engine.

**Tested how:** the economy was run through a Monte Carlo model (200 players × 3 play styles × 30 days). The milestone pacing lands in the windows Roblox's ranking rewards: first Rare in minute 6, first Legendary on day 2–5, Mythic for most engaged players by day 11–12. Stealing is roughly income-neutral over 30 days (+3%). That validates the maths, not the fun. A paper model can't prove the fun, so the KPI and playtest section sets out the gates the real build has to pass.

## What the top 98 games look like

I pulled the live chart, the game metadata (created date, visits, likes, favourites, Roblox genre, server size) and each game's own description for all 98 games on the chart. Together they had **3.39M concurrent players**. Each game was then sorted into one of 12 loop types by its core loop. The full list is in the appendix.

&#91;embedded content: Roblox Top Playing Now chart + games API, pulled 18 Nov 2026 11:44 (UTC+8) · 98 games, 3.39M live players · loop types assigned by hand from each game's loop (appendix)\]

| Loop type | Games | Median like % | Launched in last 90 days | 2+ years old | Lifetime visits (B) |
| --- | --- | --- | --- | --- | --- |
| Steal & defend collect-tycoon | 6 | 93.4 | 3 | 0 | 86.7 |
| Social roleplay & avatar | 12 | 90.4 | 1 | 8 | 181.6 |
| Incremental / RNG collection sim | 15 | 93.6 | 5 | 5 | 56.1 |
| Co-op survival / horror run | 16 | 89.8 | 9 | 2 | 56.1 |
| PvP combat / shooter | 13 | 85.0 | 4 | 8 | 71.7 |
| Action RPG grind | 7 | 94.4 | 0 | 4 | 72.1 |
| Sports & physics sandbox | 11 | 90.4 | 4 | 3 | 13.6 |
| Asymmetric round (1 vs all) | 6 | 89.0 | 2 | 4 | 46.5 |
| Gacha tower defense | 6 | 95.4 | 1 | 4 | 16.3 |
| Build / business sim | 4 | 90.4 | 3 | 0 | 0.2 |
| Obby | 1 | 73.6 | 0 | 1 | 29.5 |
| Rhythm | 1 | 96.1 | 1 | 0 | 0.0 |

What the averages say:

- **Co-op survival/horror is where new games are launching.** 9 of its 16 games are under 90 days old. It is the clearest new trend on the chart.
- **Server size splits by loop.** Steal-tycoons run tiny servers (median 7 players), so every theft is visible and personal. Roleplay and tower defense run 28–30, and co-op survival around 21.
- **Likes don't predict size.** The median like ratio is 91.7% for the whole list. PvP is the only big loop type below 89%, because losing feels bad. Tower of Hell (73.6%) is the outlier, frustrating by design.
- **Age is bimodal.** The median game is 1.5 years old, but players are concentrated at the two ends. Games 1–6 months old hold 33% of players, and games 4+ years old hold 33.5%. Games 6–12 months old hold just 1%: that is where fads die.

## Why they go viral

Ten factors show up again and again in the games with the highest visits per day: Steal a Brainrot, Steal An Egg, Grow a Garden, 99 Nights, Brookhaven, Blox Fruits, RIVALS. A game needs most of them, not all.

| # | Factor | What it looks like | Seen in |
| --- | --- | --- | --- |
| 1 | **One-sentence premise** | The title *is* the loop: "Steal an Egg", "Throw Food For Animals", "Grow a Garden", "99 Nights in the Forest" | 27 of 98 titles are an instruction ("Steal…", "Throw…") or a countdown ("13 Days…", "100 Miles…") |
| 2 | **Fun in under 60 s** | No menus. The first reward lands within the first minute. | All steal-tycoons, Tap Sim, Sol's RNG |
| 3 | **Visible rarity** | Rarity tiers + mutations + sizes shown above the item, in your base, for others to see | Fisch (400K variants), Fish It! (1M+), Sol's RNG (400+ auras) |
| 4 | **Conflict you can see** | Small servers (5–8) where someone takes *your* thing in front of you | Steal a Brainrot, Steal An Egg, Break and Steal an Egg |
| 5 | **A reason to bring a friend** | Co-op survival, crews, revives, trading | 99 Nights, Dandy's World, Dead Rails, 13 Days to Escape |
| 6 | **Passive / offline income** | Your base or garden earns while you're away | Grow a Garden, Anime Dice ("money generates while offline") |
| 7 | **Timed scarcity** | Shop restocks, limited species, weekly events | Grow a Garden restocks every 5 min plus weekly drops |
| 8 | **Clip-worthy moments** | A steal, a 1-in-a-million roll, a monster jump-scare, a ragdoll crash | Sol's RNG, BloxNG, DONT SPLASH |
| 9 | **Meme/IP wrapper** | Rides a meme kids already share | Steal a Brainrot (Italian Brainrot), Toilet TD (Skibidi), anime TDs |
| 10 | **Relentless weekly updates** | Every top-10 game was updated within the last 4 days | Update dates in the dataset |

What outside analyses add to the dataset:

- **Grow a Garden** grew from about 2,000 concurrent players into a record-breaker. There are multiple time-sensitive components, including shops that restock with new items every five minutes and weekly drops. It peaked at 21,963,800 concurrent users on 19 July 2025. One analysis credits its AFK design: plants grew whether or not the player was actively watching, so players left it running in the background.
- **Steal a Brainrot** turned a playground meme into a game. One case study argues that knowing the latest brainrot meme is social capital on the playground, and that the game was built to use it. PC Gamer reported it hit over 15 million concurrent players a few weeks ago thanks to a competition with Grow a Garden.
- **Discovery mechanics amplify all of the above.** Roblox's recommender first shows a game to a small group of players. If that new user cohort has good engagement and monetization, Roblox is more likely to continue to recommend your game to more such user cohorts (expand). Virality on Roblox is mostly this compounding loop, not luck. Each factor above raises one of the measured signals.

## Why they're addictive

These are standard behavioural-design mechanisms. The top games stack several in one loop. The "Use in Glowkeepers" column shows where each one appears in the design, and the last section covers the guard-rails.

| Mechanism | How it works on the player | Example in the chart | Use in Glowkeepers |
| --- | --- | --- | --- |
| **Variable-ratio reward** | Unpredictable payouts (rolls, catches, hatches) keep people acting more than fixed payouts do. Every roll *might* be the one. | Sol's RNG, Fisch, every egg hatch | Night catches and lures roll rarity + mutation |
| **Near-miss & rarity display** | Showing "1 in 10,000" and the rarer tier you just missed makes the next try feel close | RNG games' roll animations | Roll reel shows the tier above what you got |
| **Loss aversion** | Losing something you own hurts about twice as much as gaining it feels good, so people guard and check in | Steal a Brainrot base locks | Day-phase theft + timed base lock |
| **Revenge / reciprocity** | Being robbed creates an immediate goal: get it back, or get even | Steal-tycoons | Thief is marked and can be chased back |
| **Compounding numbers** | Income per second keeps climbing, so every session ends richer than it started | Pet Sim 99, Tap Sim | Glow/sec, rebirth multipliers |
| **Endowed progress & collection** | An index with gaps begs to be filled | Break and Steal an Egg index, Fisch bestiary | Glowdex: 40 species × 7 rarities × 3 mutations |
| **Appointment mechanics / FOMO** | Restocks, limited species and events give a reason to log in *now* | Grow a Garden 5-min restock | Lantern shop restock, weekly limited species |
| **Social proof & flexing** | Rare items are seen by others, which gives status | Adopt Me! trading, MM2 knives | Rare Glowlings glow brighter and light the base |
| **Group commitment** | Friends depend on you in co-op, so leaving early lets them down | 99 Nights, Dandy's World | Campfire night needs everyone |
| **Short cycles** | A complete loop in a few minutes means "one more" is always cheap | Blade Ball rounds, MM2 rounds | 6-minute day/night cycle |

On session length: across Roblox, the median game session lasts 9.8 minutes. In the top 5% of games, it’s 16.6 minutes, and in the top 1%, 21.1 minutes. A 6-minute cycle fits between 1.5 cycles (a median session) and 3.5 cycles (a top-1% session).

## Longevity: fads vs long-runners

The dataset has no history, so I used a proxy: **live players today per million average daily lifetime visits**. A game that keeps its audience scores high. A game that spiked and then emptied out scores low, because its huge past visits inflate the denominator.

&#91;embedded content: Roblox games API, 18 Nov 2026 · live CCU ÷ (lifetime visits ÷ days since created) × 1M · a rough proxy, since 'created' can predate public launch\]

What this shows:

- **Pure steal and pure idle loops burn out fast.** Steal a Brainrot and Grow a Garden broke every record in mid-2025 and now sit at 13–32K concurrent players. That is still top-100, but a small fraction of their peak. Their loops run out of goals: once your base or garden is maxed, there is nothing left but waiting for the next update.
- **What lasts is identity, social life and mastery.** Adopt Me! (pets you raised, trading), Brookhaven (your house, your friends), MM2 (rounds plus knife trading), Blox Fruits (a 3,000-level climb plus PvP) and Bee Swarm (a very deep, slow hive build).
- **Co-op survival is in between.** 99 Nights and Dead Rails kept far more than the steal/idle fads, but much less than the social games. A run ends, so retention depends on new content.
- **Steal An Egg (4 months old) still looks healthy**, but it has the same structure as Steal a Brainrot. The model predicts the same fade unless it adds a long-term spine.

**Is each loop type good for the long run?**

| Loop type | Long-run verdict | Why |
| --- | --- | --- |
| Social roleplay & avatar | **Strong** | Identity, friends and self-expression never "finish". 8 of 12 are 2+ years old. |
| Action RPG grind | **Strong** | Very long level curves, PvP and trading. Blox Fruits is 7.8 years old and still #5. |
| Asymmetric rounds | **Strong** | Every round is different because people are different. MM2 is 12.8 years old. |
| Gacha tower defense | **Good** | Unit collection and new worlds keep it going, but it depends on IP and frequent updates. |
| PvP combat | **Good** | Mastery and ranked play, but a lower like ratio and a toxicity risk |
| Incremental / RNG | **Mixed** | Bee Swarm and Pet Sim last; most burn out in months |
| Co-op survival / horror | **Mixed** | Great for virality and co-play. Runs end, so it needs a meta layer. |
| Steal-tycoon | **Weak alone** | Highest peaks, fastest decay |
| Sports, physics, build | **Niche** | Viral clips, thin progression |

This is why Glowkeepers uses a steal-tycoon and co-op night as the **hook**, and adds trading, an identity base and long collection/rebirth curves as the **home**.

## The formula

Roblox publishes what its recommender rewards. In 2026 it moved from its previous 7-day view to a 28-day view that directly measures long-term retention. The signals include day 1, day 2–7, and day 8–28 retention, plus players returning to a game over time, bringing friends (co-play), and spending money. Roblox also says games that win clicks with thumbnails but offer little substance should gain less visibility. The most important signals are play through rate (how often people click after seeing the tile) and first-play bounce rate.

So a viral game has to win each of these windows in turn. Each layer of the formula maps to one signal:

| Time window | Ranking signal | Formula layer | Borrowed from |
| --- | --- | --- | --- |
| Tile impression | Play-through rate | **One-sentence premise** + a bright, readable thumbnail of the conflict | Steal a Brainrot, 99 Nights |
| First 60 seconds | First-play bounce rate | **Instant reward**: a free guaranteed catch in the tutorial | Tap Sim, steal-tycoons |
| First session | Playtime per user | **Compounding income + a short cycle**: night every 6 min | Grow a Garden, 99 Nights |
| Day 1 | D1 retention | **Offline earnings + restock timer**: come back to a pile of Glow and a fresh shop | Grow a Garden, Anime Dice |
| Days 2–7 | D2–7 retention | **Rarity chase + rebirths**: first Legendary, first 3–5 rebirths | Sol's RNG, Pet Sim 99 |
| Days 8–28 | D8–28 retention | **Long tail**: Mythic/Secret hunting, Glowdex completion, trading, a weekly limited species | Adopt Me!, Fisch |
| Every session | Co-play | **Night needs friends; day has rivals** | 99 Nights + Steal a Brainrot |
| Every week | Returning users | **Friday update + weekend event** | All top-10 games |

Written as a scorecard you can check a concept against (aim for 4+ on every row):

> **V = Premise × FirstMinute × Collect × Conflict × CoOp × ComeBack × Cadence**, each scored 1–5.

The terms multiply because a zero anywhere kills the loop. A brilliant collection game with no reason to come back tomorrow fails D1 however well it hooks.

## Currency maths used by top games

The collect-tycoons, incrementals and RNG games on the chart all run on the same handful of equations. The names differ (Cash, Coins, Honey, Bucks, Gems), but the maths is the same.

**1. Income (the faucet).** Owned units each pay per second, multiplied by every bonus.

`Income/s = Σ (base[rarity] × size × mutation) × (1 + rebirthBonus × rebirths) × passMultiplier`

Top games space base income about 4–10× apart per rarity tier, so one tier up feels like a jump rather than an increment.

**2. Exponential costs (the sink).** Each upgrade level costs a constant factor more than the last.

`Cost(n) = C0 × g^n`. Incremental games typically use g ≈ 1.07–1.15 for many small upgrades and g ≈ 1.5–2.5 for a few big ones (slots, zones).

Because income also grows geometrically, the useful number is the **payback time**: `Cost(n) ÷ Income/s`. Keep it at 1–3 cycles early on and let it stretch to hours late, which is where rebirth comes in.

**3. Rebirth / prestige (the reset).** Spend everything to restart with a permanent multiplier.

`Threshold(k) = R0 × r^k` and `Multiplier = 1 + b × k`. Each rebirth needs r× more earnings but restarts you only a little stronger, so the *time* per rebirth grows slowly instead of exploding. That sustains days 2–28.

**4. RNG odds (the hook).** A drop of 1-in-N with luck multiplier L:

- `p = min(L / N, cap)`; expected tries = `N / L`
- Chance of at least one in n tries = `1 − (1 − p)^n`. At p = 1/1000, 693 tries gives 50% and 2,302 tries gives 90%. That long tail is what a **pity counter** fixes.
- Mutations (Golden ×2, Rainbow ×5) stack a second roll on top, so even a Common can be a flex.

**5. Faucets vs sinks (inflation).** If players can trade, every currency needs sinks: consumable lures, upgrade costs, rebirth wipes and trade fees. Otherwise rare items lose value and the economy dies. Grow a Garden's trading drew an unregulated market where players buy and sell rare in-game items, such as pets or special fruits, for real money. Glowkeepers gates trading for that reason.

**6. The Robux layer (real money).**

- Players buy Robux at roughly 1,000 Robux for $10.
- On a game pass, Roblox takes a 30% marketplace fee, and you receive 70 Robux per 100.
- Cash-out runs through DevEx. One guide reports that Roblox increased the DevEx exchange rate on September 5, 2025 to $0.0038 per Robux. Several other 2026 guides still quote $0.0035, so check the Creator Dashboard. There is also a higher exchange rate of 0.0054 for certain Earned Robux from age-verified US adults.
- Net per $1 a player spends: $1 → 100 R$ → 70 R$ earned → **≈ $0.27** at $0.0038.

## Game concept: Glowkeepers

**Title line:** *Glowkeepers — catch glowing creatures at night, steal them by day.*

**Elevator pitch.** Eight players share a clearing in a dark forest. Each has a base plot facing a central campfire. Glowlings are small luminous creatures. Each one lights your base and earns **Glow** every second, and rarer ones glow brighter. **By day** (4 minutes) you upgrade, buy lures, and sneak into rivals' bases to carry their Glowlings home. **At night** (2 minutes) a truce falls automatically. The Dark comes for the campfire, everyone must feed it and revive each other, and the only rare Glowlings spawn out in the forest. If the fire survives, the whole server is rewarded. If it goes out, the Dark eats a little of every base's Glow.

**Why this combination works:**

- **It takes the two strongest new loops on the chart.** Steal-tycoons (23% of live players) for the money engine and visible conflict; co-op survival (the most new launches) for co-play and shareable scares.
- **The cycle forces both emotions every 6 minutes.** Rivalry, then needing your rival. That flip produces stories ("he stole my Mythic, then saved me from the Dark"), and stories are what kids retell and clip.
- **The Home spine fixes the fad problem.** Glowdex collection, trading, base decoration, rebirth stars and weekly limited species give D8–28 goals that pure steal games lack.
- **The theme is ownable and kid-safe.** It uses no outside IP, so there is no licensing risk. The art style (dark scenes lit by bright creatures) makes thumbnails pop on the Home grid.

| Pillar | Promise to the player |
| --- | --- |
| Catch | "Every night could be the night I find a Mythic." |
| Keep | "My base is my trophy room, and I have to guard it." |
| Take | "I can take what I want if I'm brave and fast." |
| Together | "We survive the night as a team." |

**Audience:** Roblox core of roughly 9–16 years, playing on mobile first. Mobile-first controls: auto-sprint, one tap to catch, one tap to grab or drop.

**Server:** 8 players. That is just above the median 7 of steal-tycoons, so a night crew is big enough to need coordination.

## Detailed game loop

The game runs six nested loops. Each one hands off to the next.

| Loop | Length | The action | The pay-off | Pulls you into |
| --- | --- | --- | --- | --- |
| Moment | 2–10 s | Tap to catch, grab, or feed the fire | Roll reveal, Glow ticking up | Next catch |
| Cycle | 6 min | Day: earn, buy, steal, defend → Night: catch rares and survive together | New Glowling, Embers if the fire holds | Next night |
| Session | \~10–30 min | 2–5 cycles | A slot or lantern upgrade, a rebirth, a Glowdex entry | Log off with a goal ("2 more nights to rebirth") |
| Day | 24 h | Offline Glow (10%, 6 h cap), daily quests, shop restock | Pile of Glow on return, daily Ember bonus | Tomorrow's restock and streak |
| Week | 7 days | Friday update + weekend event + weekly limited species | New species and a Glowdex page | Next Friday |
| Season | 6–8 weeks | Night Pass track, a new biome, seasonal mutation | Exclusive skins, season leaderboard | Next season |

### The 6-minute cycle, second by second

**DAY — 4:00 (theft on)**

1. **0:00 Dawn.** The night's catches drop into your carry bag, and the Glow counter rolls up. You place catches into slots; the best ones auto-place.
2. **0:00–4:00 Earn.** Every placed Glowling pays Glow/s. The numbers float up visibly.
3. **Spend.** At the Lantern shop (restocks every 5 min, so it never lines up exactly with the cycle) you can buy:
   - Lures (a guaranteed minimum rarity, up to Epic)
   - Lantern levels (+luck)
   - Boots (+speed)
   - Slots
   - Base Lock charges
4. **Steal.** Walk into any unlocked base, hold to grab one Glowling from its **display slots**, and run home. While you carry it you are slowed by 15% and glow, so you're visible. If the owner or their friend tags you, it snaps back home. If you reach your base, it's yours.
5. **Defend.** A Base Lock closes your gate for 60 s, then needs 90 s to recharge. **Vault slots** (3 at start, +1 per rebirth) can never be stolen, so your best few are always safe.
6. **3:30 Dusk warning.** The sky reddens, a horn sounds, and steals in progress get 30 s to finish.

**NIGHT — 2:00 (theft off, co-op)**

1. **Truce.** Gates open and stealing is disabled. Everyone gets a lantern.
2. **The Dark advances** from the forest edge. The **campfire meter** starts at 60% and drains 0.1%/s per living player. With 8 players, that is 96% over the night.
3. **Feed the fire.** Carry wood or glow-shards from the forest. Each piece adds 3%, so about 2 pieces per player per night keeps the fire alive. A server where half the players freeload loses it.
4. **Catch.** Wild Glowlings spawn in the dark forest; tap one to catch it. You get 3 catches a night plus 1 per 5 Boots levels. Every catch rolls rarity with your luck.
5. **The Stalker.** A monster hunts lone players in the dark. If it touches you, you're downed. A teammate revives you by holding for 3 s, or you respawn at dawn and lose your remaining catches.
6. **Dawn result.**
   - **Fire survived:** +Embers for everyone, scaled by fire % and revives, plus +25% luck for the next night.
   - **Fire went out:** each base loses 5% of its Glow balance, never Glowlings.

### First session (FTUE) — the first 10 minutes

| Time | Beat | Purpose |
| --- | --- | --- |
| 0:00 | Spawn at your empty base. A guide Glowling flies to a free Lure: "Tap!" | Reward in under 10 s |
| 0:15 | Guaranteed **Uncommon** pops out and starts paying Glow | Shows the income loop |
| 0:45 | Buy your first Lure with the Glow you earned | Shows the spend loop |
| 1:30 | Arrow to a bot's base: "Steal one!" (tutorial target can't fight back) | Teaches stealing safely |
| 3:30 | Dusk horn: "Night is coming. Stick together." | Builds tension |
| 4:00–6:00 | First night. A scripted **Rare** spawns near the fire. Feed the fire once. | First rare within 6 min, first co-op act |
| 6:00 | Dawn: "You survived! +Embers." A goal appears: "Rebirth at 250K Glow → ⭐" | Sets the session goal |
| 6:00+ | First real steal attempt against humans; protection ends after the first night | Real stakes, with a soft landing |

### Long-term spine (days 2–28+)

- **Rebirth Stars:** permanent +35% income and +6% luck each. Rebirth thresholds grow 3.2× a time.
- **Glowdex:** 40 species × 7 rarities, plus Golden/Rainbow mutations. Completing a page gives a permanent bonus and a base decoration.
- **Trading:** unlocks at Star 3 *and* 3 different play days. Both sides confirm, and there's a 2-minute cooling-off period.
- **Base decoration:** spend Embers on lights, banners and paths. This is the identity, Brookhaven-style "my place" layer.
- **Crews (week 4+):** a 4-player crew shares a fire bonus and has a crew leaderboard.

## Economy and currency spec

These are the exact numbers the simulation ran. They are tuned in the next section.

**Currencies**

| Currency | Type | Earned by | Spent on | Reset on rebirth? |
| --- | --- | --- | --- | --- |
| **Glow** | Soft, per-second | Placed Glowlings, offline (10%, 6 h cap) | Lures, Lantern, Boots, Slots, Locks | Yes |
| **Embers** | Hard-earned premium | Surviving nights, revives, daily quests, Robux packs | Decorations, Night Pass tiers, pity skip, extra Lock charges | No |
| **Stars** | Prestige | Rebirth | Nothing; a permanent multiplier | No (accumulates) |
| **Robux** | Real money | — | Passes and dev products (see Monetization) | — |

**Glowling rarity table**

| Rarity | Base odds (1 in N) | Glow/s base | Step vs tier below |
| --- | --- | --- | --- |
| Common | 2 | 1 | — |
| Uncommon | 5 | 4 | 4× |
| Rare | 20 | 20 | 5× |
| Epic | 100 | 120 | 6× |
| Legendary | 1,000 | 1,000 | 8.3× |
| Mythic | 10,000 | 10,000 | 10× |
| Secret | 100,000 | 150,000 | 15× |

Modifiers on each Glowling:

- **Size:** ×0.8–1.3
- **Golden:** ×2 (1 in 20)
- **Rainbow:** ×5 (1 in 200)
- **Moonlit:** ×10, event nights only

Luck multiplies the odds of Rare and above, capped at 50% per tier:

`Luck = (1 + 0.12 × LanternLevel) × (1 + 0.06 × Stars) × (1.25 if last fire survived) × (event boost)`

**Pity:** if 150 night catches pass without a Legendary, the next catch is one. At 3 catches per 6-minute cycle, that caps the worst case at 5 hours of play. Pity, Boots catches and the fire-survived bonus were left out of the simulation, so the real game is slightly more generous than modelled.

**Cost curves**

| Item | Cost formula | Effect | Max |
| --- | --- | --- | --- |
| Lure tier t (0 = Common … 3 = Epic) | 40 × 14^t Glow | Roll with minimum rarity t (can roll higher) | Epic floor. Legendary+ only from nights, steals and events |
| Lantern level n | 150 × 1.55^n | +12% luck | none |
| Slot k (beyond 8) | 250 × 1.9^k | +1 placed Glowling | 30 slots |
| Boots level n | 150 × 1.5^n | +4% speed, +1 night catch per 5 levels | 25 |
| Rebirth k | Earn 250,000 × 3.2^k Glow since last rebirth | +1 Star: +35% income, +6% luck, +1 vault slot | none |

**Faucet–sink balance**

- Lures are the main Glow sink. Capping lures at Epic means the best creatures only come from playing nights. That ties the economy to the co-op loop instead of to idle hoarding.
- Rebirth wipes Glow, upgrades and all but your single best Glowling. That is a 100% periodic sink, so Glow never inflates.
- Theft moves Glowlings between players but doesn't create them, so it is zero-sum per server. The simulation confirms it is income-neutral on average.
- Trading has a 5% Ember fee per trade, and the Glowdex counts first catches only (trades don't count). This keeps trading from replacing play and soaks up surplus Embers.

## Simulation results (how the design was tested)

**What was tested.** A Python Monte Carlo model of the full economy: the rarity rolls, mutations, lures, lantern, slots, rebirths, offline income and theft. It ran 200 simulated players for 30 days in each of three play styles. The session patterns come from Roblox benchmarks: the median player opens Roblox games 3 times a day and the median player session lasts 7.28 minutes.

- **Casual:** 3 × 8 min a day
- **Engaged:** 4 × 20 min a day
- **Hardcore:** 6 × 45 min a day

The simulated player spends greedily on whatever is cheapest and useful.

**Iteration 1 failed.** Lures could guarantee Legendaries and offline income was 25% for 8 h, so casual players reached Legendary in 42 minutes of play. Rebirth thresholds grew 6× a time, so engaged players' income flattened after day 7. That would hurt D8–28 retention.

**Fixes:**

- Lures capped at Epic
- Offline income cut to 10% for 6 h
- Rebirth growth cut to 3.2×
- Star bonus cut to +35% income and +6% luck

**Iteration 2 results (final):**

| Milestone | Target window | Casual (3×8 min) | Engaged (4×20 min) | Hardcore (6×45 min) |
| --- | --- | --- | --- | --- |
| First Rare | First session | Day 1 (6 min) | Day 1 (6 min) | Day 1 (6 min) |
| First Epic | Day 1–2 | Day 2 | Day 1 | Day 1 |
| First rebirth | Day 1–2 | Day 2 (24 min) | Day 1 (30 min) | Day 1 (30 min) |
| First Legendary | Days 2–7 | Day 5 (92% by D30) | Day 2 | Day 1 |
| 5th rebirth | Days 2–7 | Day 7 | Day 3 | Day 1 |
| First Mythic | Days 8–28 | 26% by D30 | 64% by D30, median day 11.5 | 98%, median day 6 |
| First Secret | Long tail | 3% | 10% | 38% |
| Stars at D30 | Still rising | 8 | 9 | 11 |

(Day = median among players who reached it. Minutes = cumulative play time.)

&#91;embedded content: sim.py Monte Carlo, 200 players per profile × 30 days, final tuning\]

**Theft check.** Across 30 days the engaged player's income with theft on was **103%** of the same seeds with theft off. You lose some and you take some, so stealing creates drama without bleeding anyone dry. Vault slots protect the top 3+ Glowlings.

**What this proves, and what it doesn't.** It proves the *maths*:

- Every play style hits a milestone inside each window the ranking system measures.
- Nothing plateaus before day 30. Casual growth does slow after day 14 (16K → 22K/s), which is where the weekly limited species and Glowdex pages have to carry the goals.
- Rebirth wipes stop inflation.
- Theft is fair on average.

It does **not** prove the game is fun, that the night is scary, or that real kids steal as often as modelled (6% per day phase). Those need the playtest gates in the KPI section. Rerun `sim.py` with any tuning change before shipping it.

## Monetization

The principle is to sell **speed, convenience, protection and style, never the win**. Recommendation now weighs retention over 28 days alongside spend, and Roblox's own explanation of its Q2 2026 shortfall was that it had begun to weigh player retention over immediate spending. Monetization that churns players costs you reach.

| Product | Type | Price (R$) | What it does | Why it's fair |
| --- | --- | --- | --- | --- |
| VIP Lantern | Game pass | 299 | ×1.5 Glow, VIP chat tag, golden lantern skin | Speed, not exclusivity |
| +2 Vault Slots | Game pass | 199 | Two more theft-proof slots | Protection; free players still get +1 per rebirth |
| Swift Boots | Game pass | 149 | +15% speed | Steals stay catchable thanks to the carry slow |
| Auto-Place | Game pass | 99 | Best Glowlings auto-fill slots offline | Convenience |
| Night Pass (season) | Pass / Embers | 399 | 50-tier track of skins, decorations, Ember rewards | Cosmetic plus a small Ember flow |
| Ember packs | Dev product | 49 / 199 / 799 | Embers for decorations, pity skip, Lock charges | Embers are also earned every night |
| Lock Charge ×3 | Dev product | 25 | Three extra 60 s base locks | Small impulse buy at the moment of a theft |
| Server Luck (15 min) | Dev product | 99 | +50% luck for **the whole server** | Social: buyers become heroes, which drives co-play |

**Deliberately not sold:**

- Robux-for-random-Glowling rolls, because paid loot boxes for a young audience are a legal and policy risk. If any paid random item is ever added, show the odds.
- Direct Legendary+ purchases.
- Immunity from theft. Vaults protect your best Glowlings, but the display slots stay at risk for everyone.

**Revenue scenario (illustrative).** One analysis assumes daily actives run roughly 4x concurrent players. My assumptions, not measured: 0.75% of daily actives buy something on a given day, spending 300 R$ on average.

| Peak CCU | DAU | Gross R$/day | Earned R$/day (70%) | USD/month at $0.0038 |
| --- | --- | --- | --- | --- |
| 1,000 | 4,000 | 9,000 | 6,300 | ≈ $720 |
| 10,000 | 40,000 | 90,000 | 63,000 | ≈ $7,200 |
| 100,000 | 400,000 | 900,000 | 630,000 | ≈ $72,000 |

The 1,000-CCU row matches the top of the range one analyst gives for that size: $360–$720 per month. Premium Payouts (engagement-based) come on top and are not modelled.

## Production plan and live ops

**Team (lean, 4–6 people):**

- 1 lead scripter (Luau, server systems)
- 1 gameplay/UI scripter
- 1 3D artist (Glowlings, VFX, lighting)
- 1 builder/level designer
- 1 designer-producer (economy, live ops, analytics)
- Part-time: a sound designer and a thumbnail/icon artist

Grow a Garden showed a tiny team can launch. Scaling to millions needs at least this.

**Timeline (12 weeks to public launch):**

| Weeks | Phase | Deliverables | Exit gate |
| --- | --- | --- | --- |
| 1–2 | Paper + greybox | Economy sim (done), one plot + campfire + forest greybox, day/night timer | Day/night switch feels like a mood change in a 4-person test |
| 3–4 | Core loop prototype | Catch/roll, Glow/s income, slots, steal + carry + tag-back, Base Lock, campfire meter, Stalker AI v1 | 8-person playtest: unprompted steals *and* unprompted revives happen |
| 5–6 | Vertical slice | 10 species × 7 rarities, roll VFX, lure shop restock, FTUE script, offline earnings, DataStore saves | First-session test: ≥ 80% reach the first night; no confusion about the rules |
| 7–8 | Content + meta | 40 species, Glowdex, rebirth, decorations, mobile controls, sound | Closed beta of 200–500 players (friends, Discord) |
| 9–10 | Beta + tuning | Analytics events, monetization, anti-exploit, trading (gated) | Beta D1 ≥ 20%, average session ≥ 15 min |
| 11 | Soft launch | Public, small Sponsored-ads test, thumbnails A/B | Play-through rate and bounce in the top half of similar games |
| 12 | Launch | First weekend event, first limited species | — |

**Technical must-haves:**

- **Server-authoritative everything.** Rolls, income and theft are resolved on the server. Clients only request actions. Steal-games are exploit magnets.
- **Session-locked saves** (a ProfileStore-style pattern) to stop duplication via trading or server-hopping.
- **Theft validation.** The server checks carry distance and time, the target slot's lock state and the carrier's speed against Boots level.
- **Analytics events** at every FTUE step and at every catch, steal, revive, rebirth and purchase.
- **Performance:** cap Glowling lights per base on mobile (the brightest 8 are real lights, the rest emissive only).

**Live-ops calendar (repeating):**

| Cadence | Content |
| --- | --- |
| Every Friday | Update: 1–2 new species or a feature; patch notes on the game page |
| Every weekend | Event night: Blood Moon (×2 luck), Moonlit mutation, or a Glow rush |
| Every week | 1 limited species, available only that week, with its own Glowdex page |
| Every 2 weeks | New Lantern shop item or base decoration set |
| Every 6–8 weeks | New season: new biome (Swamp, Tundra, Crystal Caves), new Stalker, Night Pass |
| Milestones | Like/favourite goals unlock codes for Embers (a pattern several chart games use) |

## KPIs and playtest plan

The baseline is GameAnalytics' Roblox benchmarks: Median D1 retention for a Roblox game is 10.3%, D7 is 1.6%, and D30 is 0.5%. The top 1% of games have D1 of 22.2%, D7 of 9.1%, and D30 of 4.7%. Glowkeepers targets top-1% numbers, because that is roughly what a chart game needs.

| KPI | Roblox median | Top 1% | Glowkeepers target | Main lever if missed |
| --- | --- | --- | --- | --- |
| D1 retention | 10.3% | 22.2% | ≥ 22% | FTUE pacing, first-night scare, offline Glow |
| D7 retention | 1.6% | 9.1% | ≥ 9% | First Legendary timing, rebirth goals, friends |
| D30 retention | 0.5% | 4.7% | ≥ 5% | Weekly species, trading, crews, seasons |
| Avg session | 9.8 min | 21.1 min | ≥ 16 min (about 3 cycles) | Night stakes, "2 more nights" goals |
| Sessions/day per player | 1.56 | 8.3 | ≥ 3 | Restock timer, offline cap length |
| Co-play rate | — | — | ≥ 40% of sessions with a friend | Friend invite on revive, crew bonus |
| First-play bounce (< 60 s) | — | — | < 15% | Instant tutorial Lure |

Session and sessions-per-day benchmarks are from the same report: players open the median game 1.56 times a day, and 8.3 times for the top 1%.

**Playtest gates (each must pass before moving on):**

1. **The flip test (week 4).** Eight testers, 30 minutes. Pass if at least 6 testers both steal *and* revive someone, and at least 2 tell a "he stole from me then saved me" story unprompted.
2. **The 60-second test (week 6).** Ten new players get no instructions. Pass if 9 or more catch, place and earn within 60 s.
3. **The fear test (week 6).** Pass if players gather near the fire at dusk without being told. If they scatter, the Stalker isn't scary enough.
4. **The theft-rage test (week 8).** Survey after the closed beta. Pass if fewer than 20% say theft made them want to quit. If that fails, raise vault slots, add theft insurance (refund 25% of the stolen Glowling's value as Embers), or shorten the day phase.
5. **The day-3 test (beta).** Pass if 40% or more of day-1 players who return on day 2 also return on day 3. If not, move the first Legendary earlier or add a day-2 login gift.
6. **The economy test (ongoing).** Compare live median milestone days with the simulation table. Retune if any milestone drifts more than 50% from the model.

## Risks and responsible design

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Copycats. Steal-games get cloned within weeks (Break and Steal an Egg is credited as inspired by Steal An Egg). | High | Ship fast. The day/night co-op twist and the Glowdex are harder to clone than a conveyor. Keep the weekly cadence. |
| Theft feels cruel to young players and they quit | Medium | Vault slots, a new-player shield until the first rebirth, tag-back, the theft-rage gate, optional insurance |
| Exploiters dupe Glowlings via steal/trade | High | Server authority, session locks, trade gating, an audit log of every steal and trade |
| Real-money trading and scams | Medium | Trade unlock after 3 play days, a cooling-off period, value warnings, no off-platform links |
| Fad decay like Steal a Brainrot | High if the Home spine is weak | Ship trading, decorations, crews and seasons by week 6 after launch. Watch D30. |
| Algorithm shifts | Medium | Optimize for retention and co-play, not clicks |
| Night is too hard for solo or mobile players | Medium | Fire drain scales with players alive; bots fill under-full servers at night only |

**Responsible design.** The audience is mostly children, and many of the mechanisms in "Why they're addictive" work as well on kids as they do on adults. Guard-rails worth building in from day one:

- **Natural stopping points.** Dawn is a clear save-and-quit moment. The offline cap (6 h) means there's no penalty for logging off.
- **No streak punishment.** Daily gifts accumulate; missing a day never resets anything.
- **Spending.** No loot-box purchases, clear prices in Robux, no countdown pressure on purchases, and dev products capped per day.
- **Kindness by design.** Revives earn more Embers than steals earn anything. Trash-talk emotes are excluded, but a thief can be thanked with a "GG".
- **Honest odds.** The odds of every rarity are shown in the Glowdex.

## Appendix: core loop of all 98 games

Ranked by live players on 18 Nov 2026. Arrows show the loop's order. Loop types match the chart at the top. Each loop was written from the game's own description plus general knowledge of the game, not from playing every one.

| # | Game | Loop type | Live players | Core loop |
| --- | --- | --- | --- | --- |
| 1 | Steal An Egg | Steal & defend collect-tycoon | 469,373 | Steal eggs → hatch pets → pets pay cash/sec in base → buy treadmill speed → steal rarer eggs from players & defend your own |
| 2 | Adopt Me! | Social roleplay & avatar | 215,071 | Care for pet tasks → pet ages up → earn Bucks → hatch eggs/buy pets → trade for rarer pets → show off & roleplay |
| 3 | Brookhaven RP | Social roleplay & avatar | 198,881 | Pick house/car/job → roleplay scenes with friends → unlock premium houses/cars (gamepass) → repeat with new events |
| 4 | Throw Food For Animals | Steal & defend collect-tycoon | 183,594 | Throw food (power meter) → attract animals → animals earn cash/sec → buy better food & train throw power → reach new zones |
| 5 | Blox Fruits | Action RPG grind | 155,939 | Quest/grind mobs → level & stats → find/buy fruits → bosses & sea travel → raise level cap → PvP bounty |
| 6 | 99 Nights in the Forest | Co-op survival / horror run | 78,369 | Gather wood/food by day → fuel campfire & upgrade camp → survive monster at night → rescue kids/loot → earn diamonds for classes |
| 7 | Murder Mystery 2 | Asymmetric round (1 vs all) | 76,529 | Random role per round (Innocent/Sheriff/Murderer) → survive or win → coins → unbox knives/guns → trade & flex |
| 8 | RIVALS | PvP combat / shooter | 71,157 | Queue 1v1–5v5 duels → first to 5 wins → keys/XP → unlock weapons & skins → ranked climb |
| 9 | Anime Adventures | Gacha tower defense | 62,841 | Summon units (gacha) → place on map → clear waves → gems/items → evolve units → harder modes & raids |
| 10 | Break and Steal an Egg | Steal & defend collect-tycoon | 61,840 | Break eggs with pickaxe → steal animal past guards → place in base for cash → upgrade speed/pickaxe → complete index |
| 11 | Fish It! | Incremental / RNG collection sim | 59,468 | Cast & reel minigame → sell fish → better rod/bait → new islands → hunt secret/mutated fish (1M+ variants) |
| 12 | Jujutsu Shenanigans | PvP combat / shooter | 53,523 | Pick character kit → combo-fight in free-for-all → kills → awakenings & emotes → master new characters |
| 13 | Catalog Avatar Creator | Social roleplay & avatar | 52,324 | Try on catalog items free → save outfits → browse community outfits → buy items (affiliate revenue) |
| 14 | Murderers VS Sheriffs | PvP combat / shooter | 45,286 | Queue duels as murderer/sheriff → aim-based rounds → win → weapon skins & crates |
| 15 | Practical Basketball | Sports & physics sandbox | 43,141 | Join court → pickup/ranked basketball → improve skill → cosmetics & rank |
| 16 | Dandy's World | Co-op survival / horror run | 42,722 | Pick toon → co-op floors: repair machines while dodging twisted monsters → descend → ichor currency → unlock toons/trinkets |
| 17 | Fisch | Incremental / RNG collection sim | 41,735 | Cast, reel minigame → sell/collect fish (400K variants) → buy rods → explore islands → events & rare mutations |
| 18 | Pet Simulator 99! | Incremental / RNG collection sim | 39,815 | Pets farm coins/breakables → hatch eggs → enchant/fuse pets → new zones → trade huge/titanic pets |
| 19 | Anime Crusaders X | Gacha tower defense | 38,874 | Summon anime units → place → clear waves → gems → summon & evolve → story/raids/infinite |
| 20 | Forsaken | Asymmetric round (1 vs all) | 37,909 | 1 killer vs survivors → survivors do objectives/survive timer → earn money → unlock killers/survivors & skins |
| 21 | Attack on Titan Revolution | Action RPG grind | 35,293 | ODM-gear missions kill titans → gold & upgrades → perks/families (gacha) → raids to steal shifter power |
| 22 | Tap Simulator REBORN | Incremental / RNG collection sim | 33,558 | Tap for coins → hatch pets (multipliers) → rebirth for permanent boost → unlock islands |
| 23 | Sol's RNG | Incremental / RNG collection sim | 32,707 | Press roll → aura of random rarity → craft gear with auras → potions boost luck → chase 1-in-billion auras |
| 24 | Survive Your Ideas | Co-op survival / horror run | 32,561 | Random player types a word → it spawns as a hazard → hazards stack → last alive wins (round-based) |
| 25 | Ragdoll Soccer | Sports & physics sandbox | 32,493 | Queue 4v4/8v8 physics soccer → play match → clubs with friends |
| 26 | Bee Swarm Simulator | Incremental / RNG collection sim | 32,042 | Bees collect pollen in fields → convert to honey → buy bees/gear → bear quests → climb mountain zones |
| 27 | Steal a Brainrot | Steal & defend collect-tycoon | 31,682 | Buy brainrot off conveyor → it earns cash/sec in base → steal rarer ones from others & lock base → rebirth → troll items |
| 28 | Dress To Impress | Social roleplay & avatar | 31,575 | Theme announced → dress in timer → runway walk → players vote → stars → unlock items & VIP |
| 29 | Violence District | Asymmetric round (1 vs all) | 31,559 | 5 survivors vs 1 killer → repair generators, escape → points → unlock perks/killers |
| 30 | The Strongest Battlegrounds | PvP combat / shooter | 31,272 | Pick moveset → combo-fight FFA → kills raise streak → unlock ultimates/emotes |
| 31 | STAND OUT | Action RPG grind | 29,501 | Get a stand (RNG) → fight NPCs/players → level & upgrade stand → rarer stands |
| 32 | Volleyball Legends | Sports & physics sandbox | 29,092 | 6v6 matches → spikes/blocks skill → ranked → spin for styles (abilities) → cosmetics |
| 33 | King Legacy | Action RPG grind | 26,960 | Same as Blox Fruits: quests → level (cap 5450) → fruits & swords → bosses & seas |
| 34 | Evade | Co-op survival / horror run | 25,972 | Run from nextbots across maps → revive teammates → survive rounds → currency → cosmetics & battlepass |
| 35 | BloxNG | Sports & physics sandbox | 25,509 | Drive soft-body cars → crash them spectacularly → unlock cars → watch & share the destruction |
| 36 | DONT SPLASH | Co-op survival / horror run | 25,131 | Short horror runner through poolrooms → don't touch water → reach exit → share scares |
| 37 | Illegal Soccer | Sports & physics sandbox | 23,590 | Soccer with guns, jetpacks, grapples → chaotic matches → cosmetic/weapon unlocks |
| 38 | Berry Avenue RP | Social roleplay & avatar | 22,435 | Choose house/job (school, hospital, police) → roleplay → premium items |
| 39 | Net a Fish! | Steal & defend collect-tycoon | 21,630 | Throw net → catch fish → display in pool for cash/sec → upgrade dock/nets → rebirth → crew wars |
| 40 | Driving Empire | Sports & physics sandbox | 19,818 | Drive/race open world → earn cash → buy licensed cars → limited cars & events |
| 41 | Realistic Ragdoll MMA | PvP combat / shooter | 19,185 | Physics MMA fights → unpredictable ragdoll outcomes → win/rank |
| 42 | Anime Dice | Incremental / RNG collection sim | 18,994 | Roll dice → reveal anime character (rarity+mutation) → team earns money (offline too) → upgrade dice luck |
| 43 | Clean The Ballpit! | Incremental / RNG collection sim | 18,688 | Pick up balls → deposit for cash → upgrade tools/pets → new maps released daily → speedrun leaderboard |
| 44 | Ant Evolution | Incremental / RNG collection sim | 18,200 | Eat food to grow → roll mutations (wings, fire) → fight bugs/players → boss → rebirth |
| 45 | MALAM SAMA OPAH | Co-op survival / horror run | 17,804 | Squad of 5–8 survives a Malaysian folk-horror night event → escape |
| 46 | Creatures of Sonaria | Social roleplay & avatar | 17,452 | Play as creature → find food/water → grow up → survive predators → unlock species (gacha tokens) |
| 47 | Huss Valley | Asymmetric round (1 vs all) | 17,450 | One chaser vs crowd crossing a field → caught players become chasers → last runner wins → ability levels |
| 48 | LifeTogether RP | Social roleplay & avatar | 16,729 | Life roleplay town: homes, jobs, phone apps → premium content |
| 49 | Fling Things and People | Sports & physics sandbox | 16,679 | Grab and fling objects/players with physics → build contraptions → pure social chaos |
| 50 | The Forge | Action RPG grind | 16,512 | Mine ores → forge unique weapons from combos → fight → better ores & builds |
| 51 | Criminal Simulator | Co-op survival / horror run | 16,237 | Crew robs houses at night → sneak past residents/police → sell loot before deadline → pay off debt |
| 52 | Cameraman Tower Defense | Gacha tower defense | 16,211 | Place cameraman units → defend waves of toilets → crates → better units |
| 53 | 13 Days to Escape | Co-op survival / horror run | 15,819 | Prison horror: work by day, survive nights, plan escape with up to 3 friends over 13 days |
| 54 | Drag Drive Simulator | Sports & physics sandbox | 15,576 | Realistic driving roleplay → drag races/towing jobs → buy cars → limited cars |
| 55 | Do Not Stop. | Co-op survival / horror run | 15,376 | Keep driving at all costs while a creature chases → manage car → survive the route |
| 56 | Flee the Facility | Asymmetric round (1 vs all) | 15,241 | Beast vs 4 survivors → hack computers → open exits → escape or capture → credits → cosmetics |
| 57 | Voxel Wars | PvP combat / shooter | 14,889 | 15v15 destructible-voxel war → vehicles → destroy enemy base |
| 58 | Hypershot | PvP combat / shooter | 14,797 | Fast FPS modes (TDM, CTF, gun game) → XP → weapons & skins |
| 59 | Lethal Ape Experience | Co-op survival / horror run | 14,518 | Explore facility, stay silent, collect scrap, avoid monsters → extract → upgrades |
| 60 | Toilet Tower Defense | Gacha tower defense | 14,159 | Place units vs toilet waves → crates/summons → trade units → events |
| 61 | 100 Miles Down the River | Co-op survival / horror run | 14,128 | Build raft with friends → ride river → stay in light during storms → reach farther miles |
| 62 | BedWars | PvP combat / shooter | 13,979 | Teams protect bed → gather resources → buy gear → destroy enemy beds → kits/battlepass |
| 63 | My Avatar! | Social roleplay & avatar | 13,926 | Browse catalog & build avatars → earn points from purchases → spend on free items |
| 64 | Volley Bomb | PvP combat / shooter | 13,888 | Hit an exploding ball into others' squares → dive to save → last player standing |
| 65 | Project Slayers 2 | Action RPG grind | 13,831 | Choose demon/slayer → quests & bosses → level → breathing styles/arts → rare clans (spins) |
| 66 | MOUSE | Co-op survival / horror run | 13,601 | Story horror on a ghost steamboat → solve objectives → survive chases |
| 67 | Depth Incremental | Incremental / RNG collection sim | 13,466 | Buy steps to descend → each layer gives new upgrades/dangers → go deeper |
| 68 | Grow a Garden | Incremental / RNG collection sim | 13,275 | Buy seeds at 5-min restock → plant → wait (grows offline) → harvest (mutations ×) → sell → better seeds/pets → trade |
| 69 | Welcome to Bloxburg | Social roleplay & avatar | 13,241 | Work jobs for money → build & decorate house → roleplay → bigger builds |
| 70 | Vanguards | Gacha tower defense | 13,157 | Summon units → story/raid waves → gems → summon/evolve → limited units |
| 71 | Unstable SMP FFA | PvP combat / shooter | 13,094 | Fight as SMP characters with Minecraft-Java combat → FFA kills |
| 72 | Throw a Seed | Incremental / RNG collection sim | 13,042 | Timed throw down canyon → distance boosts luck → seed grows into rarity-rolled plant → collect & upgrade |
| 73 | Dead Rails | Co-op survival / horror run | 12,893 | Drive train 80 km through zombie desert → fuel with coal/loot → fight → reach end → bonds for classes |
| 74 | Sandworm Playground | Sports & physics sandbox | 12,709 | Play as giant sandworm → destroy everything → XP → unlock worms |
| 75 | 100 Days at Sea | Co-op survival / horror run | 12,700 | Survive at sea (like 99 Nights) → upgrade boat → explore → survive 100 days |
| 76 | Build Your World! | Build / business sim | 12,560 | Get plot → build with blocks/furniture → save in private servers → troll/protect plots |
| 77 | Sweep The Moon | Incremental / RNG collection sim | 12,546 | Sweep dust → empty canister for cash → upgrade brush/canister → clean more terrain |
| 78 | NFL Universe Football | Sports & physics sandbox | 12,529 | Play football as NFL teams → matches → NFL items |
| 79 | Tower Defense Simulator | Gacha tower defense | 12,035 | Co-op place towers vs zombie waves → coins → unlock towers → harder modes |
| 80 | Steal an Anime Pack | Steal & defend collect-tycoon | 12,018 | Steal/open packs → units → cash/sec → train speed → new zones |
| 81 | Mukbang Game | Social roleplay & avatar | 11,500 | Hang out & roleplay eating/ASMR → record → social |
| 82 | My Anime Mine | Incremental / RNG collection sim | 11,321 | Anime crew breaks rocks → ores → level/mutate/enchant crew → limited summons |
| 83 | FERAL | Social roleplay & avatar | 11,151 | Born as wolf/deer → food & water → grow up → survive predators |
| 84 | Catalog Avatar Runway | Social roleplay & avatar | 11,138 | Vote theme → design avatar → runway → ratings → podium |
| 85 | PINKIE PROMISE | Co-op survival / horror run | 11,102 | Chapter-based story horror → solve & survive → wait for next chapter |
| 86 | Vox Seas | Action RPG grind | 11,101 | Sail, fight, trade, discover → level & gear |
| 87 | Blade Ball | PvP combat / shooter | 11,081 | Homing ball targets you → parry at the right moment → ball speeds up → last alive → coins → abilities/swords |
| 88 | Fatal Baboons | Co-op survival / horror run | 11,062 | Trapped in lab → escape monsters with distinct rules → complete objectives |
| 89 | Stop The Tsunami! | Build / business sim | 11,034 | Dig sand, build walls/trenches → start wave → coins for each held wave → upgrade → bigger waves |
| 90 | Run a Christmas Tree Lot | Build / business sim | 10,899 | Order/stock trees → sell to customers → hire workers → expand lot |
| 91 | Ragdoll Research | Sports & physics sandbox | 10,716 | Spawn & mess with reactive ragdolls → accessories → sandbox chaos |
| 92 | Storage Hunters | Build / business sim | 10,314 | Bid on lockers → haul loot → sell in shop for profit → rarer finds |
| 93 | ABA | PvP combat / shooter | 10,027 | Pick anime character → combo PvP arena → master characters |
| 94 | BlockSpin | PvP combat / shooter | 9,911 | Jobs in open city → unbox cases → level → PvP/crime |
| 95 | KRN: Crosshair | Asymmetric round (1 vs all) | 9,564 | Survive challenge modes → last standing → weapons → event leaderboards |
| 96 | Tower of Hell | Obby | 9,528 | Random tower, no checkpoints → climb before timer → coins → mutators/gear |
| 97 | Stack A Butter Squishy | Incremental / RNG collection sim | 9,515 | Pull lever for random squishy → dip in wax → stack on plate → sell → upgrades (ASMR) |
| 98 | Symphony Orchestra Simulator | Rhythm | 9,393 | Join orchestra → hit falling notes in sync with others → earn solo |

## Sources

**Primary data** (pulled 18 Nov 2026, 11:44 UTC+8):

- Roblox Top Playing Now chart and games API: live players, likes, visits, favourites, created/updated dates, genre, server size and description for all 98 games. [Roblox charts](https://www.roblox.com/charts/top-playing-now)

**Platform and benchmarks:**

- [Roblox: Optimizing Discovery (June 2026)](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox)
- [Roblox Creator Docs: Discovery](https://create.roblox.com/docs/en-us/discovery)
- [God is a Geek: Roblox market-cap drop and the algorithm change](https://godisageek.com/?p=310816)
- [GameAnalytics Roblox benchmarks, via GameDev Reports](https://gamedevreports.substack.com/p/gameanalytics-key-roblox-and-roblox)
- [Roblox Creator Docs: U.S. 18+ DevEx rate](https://create.roblox.com/docs/production/monetization/18-plus-devex-rate)
- [Generalist Programmer: DevEx guide (2026 rate)](https://generalistprogrammer.com/tutorials/roblox-devex-guide-how-to-cash-out-robux)
- [RoLearn: DevEx guide (marketplace fee)](https://rolearn.dev/guidance/roblox-devex-guide-requirements-rates)
- [RoWatcher: DevEx maths per 1,000 players](https://rowatcher.com/news/devex-math-in-2026-what-you-actually-take-home-per-1-000-players)

**Case studies:**

- [NZ Herald: Grow a Garden passes Fortnite](https://www.nzherald.co.nz/the-country/news/roblox-game-grow-a-garden-surpasses-fortnite-with-164m-players/VVELQVBJTFCZBIPGEPDKSZLE5A)
- [Eneba: Grow a Garden 21.9M CCU](https://www.eneba.com/hub/news/grow-a-garden-hits-21-9-million-concurrent-players-making-roblox-the-center-of-gaming)
- [RoLearn: Grow a Garden idle case study](https://rolearn.dev/case-studies/idle-garden-zero-to-20m-ccu)
- [Calcalist: Grow a Garden's underground economy](https://www.calcalistech.com/ctechnews/article/dj4lxef8r)
- [RoLearn: Steal a Brainrot and meme culture](https://rolearn.dev/case-studies/brainrot-game-meme-culture-25m-ccu)
- [PC Gamer: Steal a Brainrot](https://www.pcgamer.com/games/sim/one-of-robloxs-biggest-experiences-right-now-is-a-bizarre-italian-brainrot-character-stealing-simulator-and-lord-help-me-i-now-understand-why-its-so-popular)

**Model:** `sim.py` (Python Monte Carlo economy model). Every number in the simulation section comes from its final run.

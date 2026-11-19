# Glowkeepers: Technical Spec

How the game is built. Rules and numbers for each system are in [GAME_SYSTEMS.md](GAME_SYSTEMS.md). The schedule is in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

---

## 1. Toolchain

| Tool | Used for |
| --- | --- |
| Roblox Studio + Team Create | Map, lighting, UI layout templates, models, sounds, publishing |
| Rojo 7 | Syncs code and config from git into Studio |
| Rokit | `rokit.toml` pins rojo 7.4.4, lune 0.11.0, selene 0.27.1 and stylua 2.0.2 for the whole team |
| Vendored code | ProfileStore goes in `src/server/Vendor/` (copied from its official repo). `Signal` is ours (`Shared.Util.Signal`). Wally is added only when a second package is needed. |
| Luau `--!strict` | All code is type-checked |
| Selene + StyLua | Lint and formatting, enforced in CI |
| Lune | Runs the pure-Luau unit tests and the config validator outside Studio |
| Python 3 + numpy | `sim/sim_v3.py`, which reads the same JSON config as the game |
| GitHub + Actions | Pull requests; CI runs `stylua --check`, `selene`, `lune run tests`, `rojo build` |

**Where each thing lives**

| Kept in git (synced by Rojo) | Kept in the Team Create place file |
| --- | --- |
| Every script | Workspace map and lighting |
| `config/*.json` (Rojo turns each JSON file into a ModuleScript) | UI layout templates, so artists can edit them in Studio |
| Tests, sim, docs | Models in `ReplicatedStorage.Assets`: Glowling meshes, VFX templates, decorations, sounds |

Code finds assets by path. In Studio, an `AssetValidator` runs at startup on both server and client. If any required instance is missing, it errors and lists them all, so a renamed model is caught in Studio instead of in production.

---

## 2. Environments

| Env | Experience | DataStores | Who can play | Purpose |
| --- | --- | --- | --- | --- |
| DEV | Glowkeepers [DEV], private | Separate | The team | Daily work. Admin and debug commands on. |
| BETA | Glowkeepers [BETA], private | Separate | Group role "Beta Tester" | Closed beta, and QA before each Friday release |
| PROD | Glowkeepers | Separate | Everyone | Live |

- `config/environments.json` lists each experience's id. A place id (`game.PlaceId`) or a game id (`game.GameId`) both match. An unknown id runs as DEV with purchases disabled.
- Ids (18 Nov 2026): DEV 81788809201865, BETA 90085664037807, PROD 111315198319328.
- Developer products and passes belong to one experience each, so `config/products.json` holds a separate set of IDs for each environment.
- Studio play-solo uses a `MockDataStore` when API access is off, and DEV's DataStores when it's on. In Studio on the PROD experience, DataService always uses ProfileStore's mock store, so Studio never touches live saves.
- Without `Server.Vendor.ProfileStore`, DEV runs on an in-memory store that saves nothing, with a loud warning. BETA and PROD refuse sessions and kick players with a message.
- The beta's retention is calculated from our own profile fields (`firstJoin`, `playDays`), because Creator Analytics needs more players than a closed beta has.

---

## 3. Repo layout

```
glowkeepers/
├─ default.project.json        Rojo: maps src/ and config/ into the DataModel
├─ rokit.toml  selene.toml  stylua.toml  .luaurc
├─ config/                     single source of truth; the game and the sim both read it
│  ├─ economy.json             every number in GAME_SYSTEMS §0
│  ├─ species.json             40 species: id, name, pool (model path and colours come with the art)
│  ├─ decor.json  quests.json  pass_s1.json  badges.json
│  ├─ products.json            pass/product IDs per environment
│  └─ environments.json
├─ src/
│  ├─ server/                  → ServerScriptService.Server
│  │  ├─ Main.server.luau      boots services in a fixed ORDER: Init all, then Start all
│  │  ├─ Services/             one ModuleScript per service (§4)
│  │  ├─ Net/NetServer.luau    builds ReplicatedStorage.Remotes; rate limit + argument check before handlers
│  │  ├─ Data/Schema.luau      pure: profile template, migrations, repair, join bookkeeping
│  │  ├─ Vendor/               ProfileStore.luau (copied in by hand, see Vendor/README.md)
│  │  ├─ ServerConfig/         → ServerStorage: events.json, unreleased species (kept off the client)
│  │  └─ Admin/
│  ├─ client/                  → StarterPlayerScripts.Client
│  │  ├─ Main.client.luau      boots controllers, then sends ClientReady
│  │  ├─ Net/NetClient.luau
│  │  └─ Controllers/          one ModuleScript per controller (§4), plus StateController (own state + Wallet)
│  └─ shared/                  → ReplicatedStorage.Shared
│     ├─ Config/               ← config/*.json (client-safe files only), mapped in default.project.json
│     ├─ EconomyMath.luau      costs, trySpend, sanitizers, formatNumber, oddsPercent, pickWeighted
│     ├─ Economy.luau          pure: luck, income, rebirth thresholds, slots and vault, prices, catches
│     ├─ Roll.luau             pure: rarity, pity, lures, mutation and size from luck and an RNG
│     ├─ Cycle.luau            pure: phase and time left at server time t; night-modifier pick
│     ├─ Fire.luau             pure: drain, feed and whole-night maths
│     ├─ Inventory.luau        pure: pads, vault, storage, Place best
│     ├─ Plots.luau            pure: plot pick (next to a friend), plot view, diff and patch
│     ├─ Env.luau              game id → DEV / BETA / PROD
│     ├─ Types.luau
│     ├─ Util/Signal.luau
│     └─ Net/                  init.luau: remote definitions (names, argument schemas, rate limits);
│                              Validate.luau, TokenBucket.luau (pure)
├─ tests/                      Lune: harness.luau + one *.spec.luau per module (shared/, Data/Schema, config, golden parity)
├─ sim/                        sim.py (original, GDD numbers), sim_v3.py (reads ../config/economy.json),
│                              golden_odds.py → golden_odds.json (the values the Luau modules must reproduce)
├─ data/                       the top-98 chart dataset behind the GDD (18 Nov 2026)
├─ tools/                      Studio command-bar scripts, not synced by Rojo: BuildGreybox.luau (§6a)
└─ docs/
```

Upcoming events and unreleased species live under `ServerStorage`, so they can't be datamined from the client. A species or event is copied to `ReplicatedStorage` when it goes live.

---

## 4. Architecture

**Principles**

1. **The server decides everything.** Clients send intents ("grab slot 4 of plot 2"), never amounts, prices or results. Every roll, payout and transfer happens on the server.
2. **Data on the server, visuals on the client.** The server holds Glowlings as plain records. Each client builds the models, lights and VFX itself from replicated state. That cuts replication traffic, and lets each device choose its own level of detail and light budget.
3. **One config.** `config/*.json` is loaded by the server, the client, the Lune tests and `sim_v3.py`. Tuning is a config change, not a code change.
4. **Pure logic is tested outside Studio.** Rolls, costs, cycle timing and fire maths are pure modules with no Roblox calls, tested in Lune in CI.
5. **Time is derived, not ticked.** The cycle phase comes from a server epoch plus `workspace:GetServerTimeNow()`, so every client agrees on the countdown and nothing has to replicate each second.

```
Client intent ──► Net (type check, rate limit) ──► Service (rules, server state)
                                                     │
                                       Profile in memory (ProfileStore, session-locked)
                                                     │
   Client render ◄── snapshots + deltas (Net) ◄──────┘
```

**Server services** (`src/server/Services`)

| Service | Responsibility | Phase |
| --- | --- | --- |
| DataService | Load and save profiles with ProfileStore, migrations, sanitizing, `PlayerReady` signal | 1 |
| LiveConfigService | Polls live config every 5 min (§10): event toggles, multipliers, kill switches | 4 |
| PolicyGate | Caches `PolicyService:GetPolicyInfoForPlayerAsync` for each player; answers "can this player see X?" | 5 |
| CycleService | Server epoch, phase signals (Dawn, DuskWarning, Night), the night-modifier pick | 1 |
| PlotService | Assigns the 8 plots, slots, vault, plot zones, the shield bubble, plot snapshots and deltas | 2 |
| GlowlingService / InventoryService | Create, move and transfer Glowling records; storage cap; auto-place | 2 |
| ReleaseService | Release storage Glowlings for 60 s of their income each (Star bonus included); all or nothing; refuses placed or held ones | 3 |
| RollService | Wraps `Roll` with a per-server `Random`; pity; tutorial overrides | 2 |
| IncomeService | Recomputes Glow/s when inventory changes; 1 Hz accrual; offline payout on join (at the saved `lastIncomePerSec`, before the join recompute), shown by `OfflineEarnings (amount, away)` once the client is ready | 2 |
| ShopService | Lures for Glow from each player's own stock per restock window (`os.time() // 300`, saved in `shop` so a rejoin doesn't refill it); check and spend with no yield between, refund if the roll can't be granted | 3 |
| UpgradeService | Lantern, Boots and Slots for Glow (one level or Buy max, `Economy.upgradePurchase`), Lock Charges for Glow or Embers (5 held); applies Boots to `RunSpeed` and tonight's catches, and Slots to the layout | 3 |
| StealService | Grab, carry, tag, deliver, chase boost, victim cooldown, validation | 2 |
| LockService | Base Lock: 60 s lock then 90 s recharge (a Lock Charge skips it), none at night, pushes outsiders out of a locked zone at 10 Hz | 2 |
| ShieldService | New-player shield: 45 min of saved play time, ends early when its owner drops it to steal (or at the first rebirth, Phase 4); `Shielded` / `ShieldEndsAt` attributes; the plot view's `shield` | 3 |
| CampfireService | Fire meter, wood and shard pickups, feeding, the dawn result | 2 |
| ForestService | Wild spawn waves, catch validation, tutorial-only spawns | 2 |
| StalkerService | Stalker NPC: the brain is `Shared.Stalker` (Dormant, Prowl, Stalk, Lunge, Retreat); 10 Hz sensing; kinematic, server-owned movement, straight on line of sight, else a PathfindingService path recomputed every 0.5 s; first-night near-miss | 2 |
| DownedService | Downed, bleed-out, revive holds, spectating until dawn | 2 |
| RebirthService | Threshold check (`glowSinceRebirth` ≥ `Economy.rebirthRequirement`), the D3 wipe and keep lists (`Shared.Rebirth`), +1 Star, Place best, ends the shield, forced save | 4 |
| GlowdexService | Credits new Glowlings from night, lure, event and tutorial (`Shared.Glowdex`); page tier and milestone claims, each once; claimed pages add income (IncomeService); odds tab data later | 4 |
| TradeService | Unlock checks, sessions, escrow, atomic swap, fees, trade lock | 5 |
| DecorService | Owned and placed decorations, placement validation, base name | 4 |
| QuestService / DailyGiftService | Daily and weekly quests (UTC); the cumulative daily gift (`Shared.Gift`: one step per UTC day claimed, never reset, loops after 28) | 4 |
| ClaimService | Owns the `Claim` remote and hands each kind to the service that registered it | 4 |
| NightPassService | Season XP, tiers, claims | 4 |
| EventService | Weekend events, weekly limited species, community goals | 4 |
| MonetizationService | Passes, products, `ProcessReceipt`, daily caps, prompt gating | 5 |
| LeaderboardService / BadgeService | OrderedDataStores and badge awards | 4 |
| Telemetry | Wraps AnalyticsService (§9) | 1–5 |
| SocialService | Friend invites, the co-play bonus check, announcements | 4 |
| NotificationService | Opt-in prompt for experience notifications, and sending them | 5 |
| ModerationService / AuditService | Exploit flags, graduated responses, bans, audit log | 5 |
| WispService | Helper NPCs that guide players toward fuel in servers with fewer than 4 players. They never feed the fire (GAME_SYSTEMS §30). Low priority. | 5 |

**Client controllers** (`src/client/Controllers`)

| Controller | Responsibility |
| --- | --- |
| InputController | Action map for touch, keyboard/mouse and gamepad; one context button (Catch / Grab / Feed / Revive / Place); hold actions |
| HUDController | Glow counter extrapolated from `{balance, perSec, t}`, Embers, cycle ring, catches left, fire meter, lock button, carry indicator |
| CycleFXController | Lighting, Atmosphere and ColorCorrection tweens; dusk sky; night darkness |
| GlowlingRenderer | Builds Glowling models from plot and wild state; picks which ones get real lights by brightness and distance; LOD |
| RollRevealController | Roll reel showing the near-miss tier, stingers, and server announcements for Mythic and above |
| StalkerFXController | Screen-edge vignette (faint when the Stalker is near, growing through a stalk on this player, full at the lunge), halved in Calm mode; the heartbeat layer waits for its sound asset |
| TutorialController | Both FTUE paths, arrows, guide Wisp, funnel analytics |
| ShopUI / InventoryUI / GlowdexUI / RebirthUI / TradeUI / DecorController / QuestUI / NightPassUI / StoreUI | One screen each, built from Studio templates |
| GoalTrackerController | Shows the next 3 goals (GAME_SYSTEMS §19) |
| SettingsController / AudioController / NotificationController | Settings, the audio mixer and ducking, toasts |

**Boot and join**

1. `Main.server.luau` requires every service, calls `Init()` on all of them, then `Start()` on all of them.
2. When a player joins, DataService loads their profile and fires `PlayerReady`. Other services attach their per-player state only after that signal.
3. The client shows a loading screen until it receives `PlayerState` (target: under 5 seconds).
4. If a profile can't load (a session-lock timeout), the player is kicked with a friendly retry message. They never play on an empty profile.

---

## 5. Data

ProfileStore store `PlayerData`, key `Player_<userId>`, with the schema version in `v`. Template, migrations and repair: `src/server/Data/Schema.luau`. Types: `src/shared/Types.luau`.

**No sparse number keys in saved data.** DataStores save tables as JSON, and a number-keyed table with gaps isn't stored reliably. Slot maps and pass tiers use string keys (`"1"`, `"2"`, ...). Repair converts stray number keys.

```lua
export type Glowling = {
	id: string,          -- HttpService:GenerateGUID(false)
	sp: string,          -- species id, e.g. "glimmermouse"
	r: number,           -- rarity 1..7 (1 = Common, 7 = Secret)
	m: number,           -- mutation 0 none, 1 Golden, 2 Rainbow, 3 Moonlit
	s: number,           -- size 0.80–1.30, 2 decimal places
	src: string,         -- "lure" | "night" | "steal" | "trade" | "event" | "tutorial" | "fuse"
	at: number,          -- os.time() when acquired
	by: number,          -- userId of the original catcher
	tradeLockUntil: number?,
}

export type Profile = {
	v: number,
	glow: number, glowSinceRebirth: number, lifetimeGlow: number,
	embers: number, embersBoughtLifetime: number,
	stars: number,
	up: { lantern: number, boots: number, slots: number },  -- slots = levels bought beyond the starting 8
	lockCharges: number,
	shop: { window: number, bought: { number } }, -- lures bought per floor this restock window (os.time() // 300)
	glowlings: { [string]: Glowling },         -- every owned record
	display: { [string]: string },             -- slot "1".."n" → Glowling id (stealable)
	vault: { [string]: string },               -- vault slot "1".."n" → id (never stealable, kept on rebirth)
	pity: { sinceLegendary: number },
	dex: { [string]: { r: number, m: number } },   -- bitmasks per species
	dexClaimed: { [string]: number },          -- page tier claimed per species
	decor: { owned: { [string]: number }, placed: { { id: string, x: number, z: number, rot: number } } },
	baseName: { a: number, n: number },        -- indices into preset word lists
	quests: { day: number, daily: { any }, week: number, weekly: { any } },
	gift: { claimed: number, lastDay: number },
	pass: { season: number, xp: number, premium: boolean, free: { [string]: boolean }, prem: { [string]: boolean } },
	firstJoin: number, lastSeen: number, lastIncomePerSec: number,
	playDays: number, lastPlayDay: number,
	shield: { active: boolean, playSeconds: number },
	ftue: { step: number, path: string?, done: boolean },
	stats: { catches: number, steals: number, stolenFrom: number, revives: number,
		nightsSurvived: number, firesLost: number, rebirths: number, trades: number, piecesFed: number },
	daily: { day: number, buys: { [string]: number } },    -- purchase caps
	receipts: { [string]: number },            -- PurchaseId → time (keep the last 200)
	settings: { calm: boolean, reducedFlash: boolean, music: number, sfx: number, breakReminder: boolean },
	notifyOptIn: boolean,
	crewId: string?,
	flags: { [string]: any },                  -- moderation and exploit flags
}
```

**Rules**

- **Repair on load; never error.** Sanitize every number: NaN, infinity and negatives become 0, and levels are clamped to their current maximum. References to Glowlings that don't exist are dropped, and duplicate ids are merged. Then the migrations run in order. Every repair is logged to Telemetry.
- **Never yield between a check and a spend.** Price, check, subtract and grant all happen in one uninterrupted block.
- **Forced saves.** Call `profile:Save()` after every Robux purchase, completed trade and rebirth. Everything else rides on ProfileStore's auto-save.
- **Small profiles.** A player owns at most about 100 Glowling records: 30 slots (vault included), a 60-slot storage bag, and 10 overflow. A profile stays well under 100 KB.
- **Big numbers.** Plain doubles are exact up to 2^53, about 9e15. With D8's step-down, rebirth thresholds pass that at Star 30. A test checks thresholds up to Star 28, and an alert fires when any player reaches Star 25. That leaves time to switch Glow to log storage, or add a third curve step.
- **Offline time uses the server clock only.** `away = os.time() - lastSeen`. A missing or future `lastSeen` pays nothing.

**Other stores**

| Store | Kind | Key / use |
| --- | --- | --- |
| `LB_Stars`, `LB_Dex` | OrderedDataStore | All-time leaderboards. Written on a change, at most every 5 min per player. |
| `LB_Revives_<yyyy>W<ww>`, `LB_Nights_<yyyy>W<ww>` | OrderedDataStore | Weekly boards, with a new key each ISO week |
| `Crews` | DataStore | `Crew_<id>` → members and stats, always via `UpdateAsync` (after launch) |
| `LiveConfig` | DataStore | `current` → JSON (§10) |
| `Audit` | DataStore | `<yyyy-mm-dd>_<serverJobId>`: batched records of Legendary-or-better steals, trades and admin actions |
| Community goals | MemoryStore sorted map | Each server sends its increments every 60 s |

---

## 6. Replication

| State | Who sees it | Mechanism | Rate |
| --- | --- | --- | --- |
| Cycle phase | Everyone | Workspace attributes `CycleEpoch`, `DayLen`, `NightLen`; clients compute the phase | Changes only on events |
| Night modifier | Everyone | Workspace attribute `NightModifier`, set at dusk warning | Once a cycle |
| Fire meter | Everyone | Workspace attribute `Fire` (0–1, nil by day; 0 = the night is Lost); clients lerp | 4 Hz at night |
| Wood piles | Everyone | Each `WoodPile` model's `Available` attribute | On change |
| Plot state (owner, slots, vault, lock, shield, decorations, base name, Stars) | Everyone | `PlotSnapshot` on join, then `PlotDelta`; `lock` is the server time the Base Lock ends (0 = open) | On change |
| Lock recharge | The owner | Player attribute `LockReadyAt` (server time the recharge ends); charges are `lockCharges` in `PlayerState` | On change |
| New-player shield | The player (and everyone, through the plot view's `shield`) | Player attributes `Shielded` (true or nil) and `ShieldEndsAt` (server time it ends if they stay online); `shield` in `PlayerState` | On change |
| Wallet | Owner only | `Wallet {glow, perSec, t, embers, glowSinceRebirth}`; the client extrapolates the ticking counter and the rebirth progress | On change, plus every 10 s |
| Inventory, quests, pass, pity, stock | Owner only | `PlayerState(full = true, data)` once the client sends `ClientReady`, then `PlayerState(false, patch)` with changed top-level keys (`receipts` and `flags` are never sent) | On change |
| Wild Glowlings | Everyone (tutorial spawns: one player only) | `WildSpawned` (a list of `{ id, sp, area, x, y, z }`; every wild to a client that becomes ready mid-night) / `WildGone` (a list of ids) | Per wave, per catch, at dawn |
| Catches left | The player | Player attribute `CatchesLeft` (nil by day) | On change |
| Carrying | Everyone | Character attributes `CarrySp`, `CarryR`, `CarryM` and `CarryFrom` (the victim's userId) for a stolen Glowling, or `CarryFuel` (`"wood"`); `GrabUntil` (server time a grab's hold ends) while grabbing; `RunSpeed` while carrying or chase-boosted | On change |
| Downed and revive | Everyone | Character attributes `Life` (`"downed"` or `"wisp"`; nil = alive), `BleedUntil` (server time; nil while a revive holds it), `ReviveUntil` on the reviver, `SafeUntil` after a revive | On change |
| Stalker | Everyone | Server-owned model `Stalker` (streaming Persistent, only at night), with attributes `State`, `Target` (userId while stalking or lunging) and `LungeAt` (server time) | Engine; attributes on change |
| Announcements and toasts | All, or one player | `Announce`, `Toast` | On event |

### 6a. Map contract

The map lives in the place (Team Create), not in Rojo, as `Workspace.Map`. Code finds things by CollectionService tag and attribute, never by position or path, so the level designer can move anything.

| Tag | Instance | Attributes | Children code uses |
| --- | --- | --- | --- |
| `Plot` | Model | `PlotId` 1–8 | `Floor` (PrimaryPart), `Zone` (invisible volume over the plot), `Gate` (invisible, at the gate), `DecorZone` (24 × 24), `Slots/SlotNN` pads with `Slot` 1–30, `Trophy`, `Sign` |
| `Campfire` | Model | `LightRadius` (30, safe from the Stalker), `FeedRadius` (10) | `Pit` (PrimaryPart), `Pit.LightPoint` (the PointLight) |
| `WoodPile` | Model | `PileId` `"W01"`…; the server adds `Available` at runtime | |
| `WildSpawn` | Part (invisible) | `Area` `"Forest"` or `"Deepwood"` | |
| `ShardSpawn` | Part (invisible) | | |
| `Station` | Model | `Kind` `"LanternShop"`, `"WispStash"`, `"Leaderboards"`, `"WhatsNew"` | `Sign` |

The place has StreamingEnabled, so client code must expect tagged models whose parts haven't streamed in yet, and look parts up again when they arrive.

`Workspace.Map` carries the ring radii as attributes: `FireLightRadius`, `PlotRingRadius`, `ClearingRadius`, `ForestOuter`, `MapRadius`. Slots 1–6 sit in the plot's side strips (the vault pedestals come first); 7–30 sit in three rows in front of the decoration zone.

The greybox comes from `tools/BuildGreybox.luau` (run it in Studio's command bar). It rebuilds only a map it made itself; once the map is edited by hand, set `Map.HandEdited = true` and it refuses to overwrite it. The art pass keeps the tags and attributes above.

---

## 7. Remotes

Every remote is declared once in `shared/Net.luau`, with its argument schema and rate limit. The server-side wrapper rejects calls with the wrong type or count, or over the rate limit, *before* the handler runs.

| Remote | Direction | Arguments | Server checks | Limit |
| --- | --- | --- | --- | --- |
| `Catch` | C→S | wildId: string | Night; catcher alive (not downed or a wisp); wild exists and is visible to this player; catches left > 0; storage below its hard cap; distance ≤ 12 studs | 4/s |
| `GrabStart` | C→S | plotId: number, slot: number | Day; before the dusk cutoff; target is a display slot with a Glowling; not own plot; thief has a plot and storage room; target not locked, shielded or on victim cooldown; under the per-victim daily limit; thief not shielded (the client asks "This ends your protection. Steal anyway?" and sends `DropShield` first); within 6 studs (flat distance, `Steal.reach`); not already grabbing or carrying | 2/s |
| `GrabCancel` | C→S | — | Lets go of the thief's grab in progress (a carry can't be cancelled) | 2/s |
| `PickupFuel` | C→S | pileId: string | Night; within 8 studs; hands empty | 4/s |
| `FeedFire` | C→S | — | Carrying fuel; within 10 studs of the fire | 4/s |
| `ReviveStart` | C→S | userId: number | Night; reviver alive; target downed (not yourself, not a wisp); one revive per reviver and per target; within 8 studs; the server times the 3 s hold, pauses the target's bleed-out during it, and cancels it if the range breaks | 2/s |
| `ReviveCancel` | C→S | — | Lets go of the reviver's hold; the bleed-out carries on | 2/s |
| `Lock` | C→S | — | Day or dusk (a lock running at nightfall ends and recharges from then); owns a plot; not already locked; recharged, or spends a Lock Charge; not carrying. Grabs in progress on the plot cancel; non-owners who were inside may leave but not come back | 1/s |
| `DropShield` | C→S | — | Ends the sender's new-player shield, after the client's confirm | 1/s |
| `Place` / `Unplace` | C→S | id: string, pad: number (Place only) | Owns the id; pad unlocked (pads 1…vault are vault pads, so Place to one of them is the move to the vault; a taken pad swaps); Unplace only while storage has room; not mid-trade | 10/s |
| `PlaceBest` | C→S | — | Best earners to the vault pads, the next best to display pads (GAME_SYSTEMS §7) | 2/s |
| `Release` | C→S | ids: list of 1–20 Glowling ids (schema type `list`) | Owns all of them, no repeats; all in storage (none on a pad, held by a steal, or in a trade); Epic+ confirmed twice and Legendary+ held in the client UI | 2/s, burst 4 |
| `ShopBuy` | C→S | itemId: `"lure1"`..`"lure4"` (the rarity floor) | Stock left this window; storage below 60; can afford it (no partial charge) | 5/s |
| `UpgradeBuy` | C→S | upgradeId: `"lantern"` \| `"boots"` \| `"slots"`, all: boolean? (Buy max) | Below max; can afford the next level (Buy max buys as many as the balance covers, up to max) | 5/s |
| `LockChargeBuy` | C→S | currency: `"glow"` \| `"embers"` | Fewer than 5 held; can afford `max(200, 120 × Glow/s)` Glow or 15 Embers | 2/s |
| `Rebirth` | C→S | — | `glowSinceRebirth` ≥ threshold; not carrying; none of the player's Glowlings held (grabbed or in a trade); the client confirms with a 2 s hold | 1/10 s |
| `Claim` | C→S | kind: enum (`dex_page`, `dex_milestone`, `gift` for now; quests and pass tiers join later), id: string ≤ 32 | Quest, gift, pass tier or Glowdex page/milestone is complete and unclaimed | 5/s |
| `TradeRequest` / `TradeRespond` / `TradeOffer` / `TradeConfirm` / `TradeCancel` | C→S | Various | GAME_SYSTEMS §17 | 5/s |
| `DecorPlace` / `DecorRemove` | C→S | itemId, x, z, rot | Owned; inside own plot bounds; on the grid; no overlap; item count under the cap | 10/s |
| `SetBaseName` | C→S | a: number, n: number | Valid indices into the preset lists | 1/5 s |
| `SetSetting` | C→S | key, value | Key in an allow-list; value type and range | 10/s |
| `PromptProduct` | C→S | productKey: string | Product enabled; policy allows it; under the daily cap; not during a theft | 1/s |
| `FtueStep` | C→S | step: number | Analytics only; grants nothing | 2/s |
| `ClientReady` | C→S | — | Sent once the controllers have started; the server answers with `PlayerState` and `Wallet` | 1/5 s (burst 2) |
| `PlotSnapshot`, `PlotDelta`, `PlayerState`, `Wallet`, `OfflineEarnings`, `WildSpawned`, `WildGone`, `RollResult`, `DawnResult`, `Revived`, `Announce`, `Toast` | S→C | — | — | — |

**Rate limiting:** a token bucket per player per remote. Calls over the limit are dropped and counted. More than 3 times the limit within a minute raises an exploit flag (§8).

---

## 8. Security and anti-exploit

Stealing games attract exploiters, so these rules are not optional.

- **Never trust the client** with an amount, price, roll, distance, timer or "I finished". The server re-derives each one.
- **Carry validation**
  - While carrying, the server samples the carrier's position at 10 Hz.
  - Allowed speed = that player's expected sprint speed × Boots × Swift Boots × 0.85, plus 25% tolerance.
  - Going over it, or jumping more than 30 studs between samples, snaps the Glowling home and flags the player.
- **Delivery** happens only when the server sees the carrier's root part inside their own plot zone. The client never reports delivery.
- **Tag** is a server distance check (≤ 6 studs between the carrier and the owner or the owner's helper) at 10 Hz, not `.Touched`.
- **Range checks** on the server: catch ≤ 12 studs, fuel pickup ≤ 8, feeding ≤ 10 from the fire, revive ≤ 8.
- **Hold actions** (grab, revive) are timed by the server from the Start call. The client's progress bar is only cosmetic.
- **Physics:** Glowlings and fuel are data plus attributes, not physics parts, so nothing can be flung, and network ownership doesn't matter. The Stalker is owned by the server.
- **Duplication:** ProfileStore's session lock prevents dual sessions. Trades swap in memory, atomically, inside one server (both players are always in the same server), then force-save both profiles. Glowling ids are unique; on load, any duplicate id is collapsed and logged.
- **Graduated response** (ModerationService):
  1. Drop the request.
  2. Snap the action back.
  3. Raise a flag.
  4. Kick with a message.
  5. `Players:BanAsync`: 1 day, then 7 days, then permanent, each only after review of the logged evidence.
- **Audit:** every steal or trade of a Legendary-or-better Glowling, and every admin action, goes into the `Audit` store and Telemetry, so a support ticket can be traced.

---

## 9. Analytics

Use Roblox's `AnalyticsService`, so funnels, economy and custom events show up in Creator Hub. Keep custom field values low-cardinality (rarity names, never UUIDs).

| API | Event | Fields |
| --- | --- | --- |
| `LogOnboardingFunnelStepEvent` | FTUE steps 1–10 (GAME_SYSTEMS §22) | Step name; path (Day or Night) |
| `LogFunnelStepEvent` | `FirstRebirth` (glow 25%, 50%, 100%, rebirth), `Store` (open, view item, prompt, purchase), `Trade` (unlock, request, confirm, complete) | Funnel session id |
| `LogEconomyEvent` | Glow sources (income, offline, release, event) and sinks (lures, upgrades, slots, locks, fire loss). Embers sources (night, quests, gift, IAP, codes) and sinks (decor, fees, pass, locks). | Transaction type, item SKU |
| `LogCustomEvent` | `catch` (rarity, source), `steal_success`, `steal_tagged`, `steal_timeout`, `lock_used`, `downed`, `revive`, `fire_survived` (fire %), `fire_lost`, `rebirth` (stars), `dex_page` (tier), `daily_gift` (step, reward kind), `trade_complete`, `night_modifier`, `calm_mode_on`, `theft_rage_quit`* | Up to 3 low-cardinality fields |

\* `theft_rage_quit` = the player leaves within 60 seconds of being stolen from. It's the live version of the theft-rage gate.

---

## 10. Live config and kill switches

`LiveConfigService` reads the DataStore key `LiveConfig/current` at boot and every 5 minutes, and merges it over the defaults in `economy.json`. If Roblox's built-in experience configs are available to the team, use those instead; the merge logic stays the same.

```json
{
  "killSwitches": { "trading": false, "stealing": false, "serverLuck": false, "products": { "LockCharge3": false } },
  "event": { "id": "lantern_festival", "start": 1803049200, "end": 1803254400, "luckMult": 1.5, "embersMult": 2 },
  "limitedSpecies": { "week": "2027W07", "species": "koilight" },
  "codes": { "FIRSTLIGHT": { "embers": 50, "expires": 1803859200 } }
}
```

- An admin panel command edits the value and shows a diff before saving. Every edit is audit-logged.
- Weekly limited species rotate on a deterministic UTC schedule from `events.json`, so a rotation never needs a publish. New assets still ship in the Friday update.

---

## 11. Performance budgets

| Budget | Target |
| --- | --- |
| Frame rate | 60 fps on mid-range devices; 30 fps minimum on low-end Android and older iPhones |
| Real lights in view | Phone ≤ 16, PC ≤ 40. The 8 brightest Glowlings per base get a `PointLight`; the rest are emissive Neon only. The fire, lanterns and the Stalker's eyes always get a light. |
| Glowling model | ≤ 1,500 tris (≤ 3,000 for Legendary and above, including VFX); 1 texture atlas per species |
| Particles | ≤ 300 live particles on a phone; rarity VFX use shared emitters |
| Server | Income accrues in one 1 Hz loop over players, not per Glowling. Gameplay checks run in one 10 Hz loop. No `.Touched` for gameplay logic. |
| Network | Under 50 KB/s per client on average; no per-second remote for anything that can be derived |
| Streaming | StreamingEnabled on; the map is compact, so streaming is mostly for decorations on large bases |
| Memory | Watch client memory in the Developer Console on the low-end Android device; no growth across 10 cycles |

---

## 12. Updates, shutdown and versioning

- Ship from Studio after a Rojo sync, from a tagged git commit (`vYYYY.MM.DD`). The tag is written into a `Version` attribute, so bug reports say which build they came from.
- Friday releases use **"Migrate to latest update"**, so players move to new servers instead of being kicked. ProfileStore releases profiles in `BindToClose`.
- Show players a toast before a migration: "New update! Moving you to a fresh server…"
- **Rollback:** restore the previous version from the place's Version History. Config changes are reverted in LiveConfig. Schema migrations only ever add fields, so an older build can still read newer saves.

---

## 13. Admin and support tools

- **Admin panel** (group rank 200 and up):
  - Look up a player's profile, read-only
  - View their audit trail
  - Grant compensation (Embers, or a specific Glowling, logged with a reason)
  - Edit LiveConfig
  - Start or stop an event
  - Kick or ban
  - Item grants in PROD always need a reason and are logged.
- **Profile rollback:** ProfileStore's version queries restore a profile to a timestamp, for dupe cleanup and hacked accounts.
- **Right to Erasure:** when Roblox sends a deletion request, an admin command removes the player's profile key, their leaderboard entries and their crew membership. Log the request id, but never the data.
- **Data Stores Manager** in Creator Hub is the read-only fallback during an incident.

---

## 14. Testing details

| Layer | Tool | What |
| --- | --- | --- |
| Unit | Lune (`tests/*.spec.luau`) | `EconomyMath`, `Roll`, `Cycle`, `Fire`, offline earnings, rebirth thresholds, migration fixtures, config validation (every species referenced exists, every product has an id in every environment) |
| Sim parity | Python + Lune | `sim/golden_odds.py` writes `golden_odds.json` from the config: odds at luck 1, 2, 5, 10 and 30 for every lure floor, luck, rebirth thresholds to Star 30, every upgrade and lure price, and whole-night fire outcomes. It mirrors the sim's maths line for line (the sim's roll lives inside its simulation loop, so it can't be called directly). `tests/golden.spec.luau` fails at a difference over 1e-9, and CI fails if the JSON is stale. |
| Integration | Studio, Server + N Clients | The acceptance list in each GAME_SYSTEMS section |
| Exploit | DEV-only fuzzer LocalScript | IMPLEMENTATION_PLAN §7 |
| Data chaos | `MockDataStore` with injected failures | Saves retry, players are warned, nothing is lost |
| Device | Real devices | The device matrix in IMPLEMENTATION_PLAN §7 |

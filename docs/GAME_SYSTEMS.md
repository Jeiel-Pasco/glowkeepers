# Glowkeepers: Game Systems Spec

Each system lists its **rules**, its **numbers** (they live in `config/economy.json` unless the section says otherwise), its **edge cases**, and **acceptance** (the tests that mark it done).

- **†** marks a number or rule that is new in this plan and isn't in the GDD.
- **sim** marks anything that changes the economy. All of them were run through `sim/sim_v3.py` on 18 Nov 2026 ([sim/README.md](../sim/README.md)). Rerun it after any change.
- **D#** refers to a decision in IMPLEMENTATION_PLAN.md §3.

Contents: 0 Config · 1 Server and plots · 2 Cycle · 3 Glowlings · 4 Rolling and luck · 5 Pity · 6 Income and offline · 7 Slots, vault, storage · 8 Lantern shop · 9 Upgrades and movement · 10 Stealing · 11 Base Lock and shield · 12 Night · 13 Stalker · 14 Downed, revive, dawn · 15 Rebirth · 16 Glowdex · 17 Trading · 18 Decorations · 19 Quests, gift, goal tracker · 20 Night Pass · 21 Events · 22 FTUE · 23 Monetization · 24 Leaderboards and badges · 25 Social · 26 Settings · 27 Notifications · 28 Crews · 29 Fuse · 30 Wisps

---

## 0. Config: one source of truth

The numbers live in [`config/economy.json`](../config/economy.json). The game, the Lune tests and `sim/sim_v3.py` all load that file, so tuning is a config change, never a code change. Rarity index 1 = Common … 7 = Secret.

Values this plan set or changed from the GDD. Each was checked in the sim ([sim/README.md](../sim/README.md)):

| Key | Value | Why |
| --- | --- | --- |
| `lures.maxFloor` / `lures.resultCap` | Epic / none | D4: the floor is capped, the roll isn't |
| `lures.stockPerRestock` | 16 / 8 / 4 / 2 | D13 |
| `rebirth.stepAfterStar` / `growthAfterStep` | 8 / 2.0× | D8 |
| `rebirth.keepVault` | true | D3 |
| `storage.size` / `releaseIncomeSeconds` | 60 / 60 | D9 |
| `fire.drainBase` / `drainPerPlayer` | 0.5% / 0.0375% per living player | D1 (not an economy number; checked by hand) |
| `upgrades.lantern.max` | 60 † | Keeps luck bounded |
| `cycle.nightModifiers` | Effects per modifier (§2) | Phase 1: modifier effects are config, not code |
| `luck.serverLuckMult` / `movement.autoSprintAfter` | 1.5× / 0.5 s | Moved from prose into config (§4, §9) |

Every other number is the GDD's.

---

## 1. Server and plots

**Rules**
- 8 players a server and 8 plots in a ring around the campfire. A joining player gets the free plot **next to a friend's plot** if one is free, otherwise the lowest-numbered free plot (†).
- When a player leaves, their plot is cleared from the world (the data stays in their profile) and is free for the next joiner. A carry *from* the leaving player's plot snaps back and is cancelled.
- Each plot has:
  - a gate
  - 30 slot pads (8 unlocked at the start). The first 3 + Stars of them (+2 with the pass) are vault pedestals (§7).
  - a decoration zone of 24 × 24 studs on a 2-stud grid
  - a trophy pedestal
  - a name sign
- One player slot is kept free for friends joining.

**Acceptance**
- 8 clients join, and each gets a unique plot. Friends end up on adjacent plots when possible.
- A player leaves mid-carry: the carry is cancelled, and the thief sees "Owner left: steal cancelled".

---

## 2. Day/night cycle

| Time | Phase | What happens |
| --- | --- | --- |
| 0:00 | **Dawn** | The dawn result screen (§14); last night's catches land in the base; the modifier ends |
| 0:00–3:30 | **Day** | Income, shop, stealing on, locks on |
| 3:30 | **Dusk warning** | The sky reddens and a horn sounds; tonight's modifier is announced. **New grabs are blocked**, and carries in progress have until 4:00. |
| 4:00 | **Night** | Truce: carries snap back, gates open, locks off, lanterns on, the fire starts at 60% |
| 4:30 | Stalker active | After the 30-second grace period |
| 6:00 | Dawn | Repeat |

- The phase is derived from the workspace attribute `CycleEpoch` (TECH_SPEC §6). The epoch is picked at server start, so servers aren't in sync with each other.
- **Night modifiers** (†, **sim**): 25% of nights roll one of the modifiers below, never the same one twice in a row. The full library is in CONTENT_AND_LIVEOPS.md §B4.

| Modifier | Effect |
| --- | --- |
| Fog | Visibility down. The Stalker hunts by sound (sprinting is louder). Wild spawns +25%. |
| Firefly Bloom | Spawns +50% and +1 catch tonight |
| Gusty Night | Fire drain +25%, glow-shards ×2 |
| Starfall | Shards rain near the fire, and the fire starts at 70% |

**Edge cases:** a player who joins at any phase gets the phase-aware FTUE (§22). Event nights (Blood Moon, Moonlit) replace the random modifier.

**Acceptance**
- Every client's countdown agrees with the server to within 0.2 s.
- A grab attempted at 3:31 is rejected. A carry started at 3:29 can still be delivered until 4:00, and snaps back at 4:00.

---

## 3. Glowlings

A Glowling is a **species + rarity + mutation + size** record (TECH_SPEC §5). Its species gives it a **family**, a **trait** and a **minimum rarity** (CONTENT_AND_LIVEOPS §A3, D18).

- **Income/s** = `glowPerSec[rarity] × size × mutationMult × traitMult × (1 + 0.35 × Stars) × (1.5 if VIP) × eventMult × (1 + Glowdex bonus)`. `traitMult` comes from §31 and is at most 1.6. `glowPerSec` depends on rarity only (D19).
- **Species pools** (CONTENT_AND_LIVEOPS.md §A3):
  - **Clearing** (16 species): from lures and nights
  - **Deepwood** (24): nights only
  - **Limited and event** species: their own pools
- **Nameplate:** "Rare · Golden · Mothlet · ×1.18 · 48/s". Rarity is shown by an icon shape *and* a colour (§26).
- **Brightness** rises with rarity, so a base full of rares lights up the clearing for everyone to see.

---

## 4. Rolling, luck and odds

**Luck** = `(1 + 0.12 × Lantern) × (1 + 0.06 × Stars) × (1.25 if last night's fire survived) × eventMult × (1.5 if Server Luck is active)`

**Rarity roll (rarest first).** Every source uses this algorithm, and the odds display computes from the same code:

```
for tier = Secret down to Uncommon:
    p = 1 / oneIn[tier]
    if tier >= Rare: p = min(p × luck, 0.5)
    if rng:NextNumber() < p: return tier
return Common
```

Exact odds this produces:

| Luck | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 75.16% | 18.79% | 4.945% | 0.999% | 0.100% | 0.010% | 0.001% |
| 3 | 65.74% | 16.44% | 14.50% | 2.99% | 0.300% | 0.030% | 0.003% |
| 10 | 35.60% | 8.90% | 44.50% | 9.89% | 0.999% | 0.100% | 0.010% |

This is the algorithm `sim.py` uses, and `sim_v3.py` keeps it. The CI parity test in TECH_SPEC §14 keeps the game and the sim identical.

**Lure outcome** = the same roll with a guaranteed floor. The floor goes up to Epic, but **the roll can still land higher** (D4). At luck 1:

| Floor | Result |
| --- | --- |
| Common | 75.2% Common · 18.8% Uncommon · 4.94% Rare · 0.999% Epic · 0.1% Legendary · 0.01% Mythic · 0.001% Secret |
| Uncommon | 93.9% Uncommon · 4.94% Rare · 0.999% Epic · 0.1% Legendary · 0.01% Mythic · 0.001% Secret |
| Rare | 98.9% Rare · 0.999% Epic · 0.1% Legendary · 0.01% Mythic · 0.001% Secret |
| Epic | 99.9% Epic · 0.1% Legendary · 0.01% Mythic · 0.001% Secret |

An Epic lure gives Legendary or better 0.11% of the time at luck 1 (0.56% at luck 5). In the sim, about half of players' first Legendaries come from lures and half from nights.

**Mutation roll** (independent of rarity; luck doesn't apply): one random draw. Under 0.5% is Rainbow; under 5% is Golden (so Golden is 4.5%); otherwise none. This matches the sim. On Moonlit event nights, Moonlit (1 in 100) is checked first.

**Species:** after the rarity is rolled, the species is picked uniformly from the pool's species whose `minRarity` ≤ that rarity (D18). The odds above don't change; only which species can appear at each rarity does.

**Size:** uniform from 0.80 to 1.30, rounded to 2 decimal places. Labels: Tiny (under 0.90), Big (1.20 and up), Huge (1.28 and up).

**Odds tab.** The Glowdex has an "Odds" tab, opened by a button labelled **Details** on the shop and the catch HUD. It shows this player's live odds for night catches and for each lure, with every active modifier listed. The odds always sum to 100%, with a note about rounding.

**Acceptance**
- The Lune test reproduces the table above to 4 significant figures.
- 1 million rolls in Studio land within 3σ of the table.
- With Server Luck on, the odds tab updates within 1 second.

---

## 5. Pity

- Every night catch below Legendary adds 1 to `pity.sinceLegendary`. At 150, the next night catch is `max(roll, Legendary)`. Any night Legendary or better resets the counter to 0.
- Lure rolls neither add to the counter nor reset it (as simulated).
- The HUD and odds tab show "Legendary guaranteed within N catches" (D5). There is no paid way to skip it.

**Acceptance:** a forced counter of 150 → the next night catch is Legendary or better → the counter is 0. At 149 the roll is normal. This is the sim's rule (`pity >= 150`), and `tests/roll.spec.luau` checks both cases.

---

## 6. Income and offline earnings

- The server accrues income in a 1 Hz loop over players (`glow += perSec`). `perSec` is recomputed only when inventory, Stars, passes or events change.
- The client extrapolates the display from `{glow, perSec, t}` and floats "+48" numbers over the slots.
- **Offline:** `floor(min(away, 6 h) × lastIncomePerSec × 0.10)`, paid on join in a popup: "While you were away your Glowlings made 1.2M Glow".
- **Night lost:** −5% of the current Glow balance (never Glowlings, never Embers).

**Acceptance**
- 10 cycles with no changes: the server's balance and the client's display differ by under 1%.
- A `lastSeen` in the future pays 0.
- A 9-hour absence pays exactly the 6-hour cap.

---

## 7. Slots, vault, storage, Release

- You start with 8 slots and can buy up to 30. **Every placed Glowling earns.** The first 3 + Stars slots (+2 with the pass) are **vault slots**: they hold your best Glowlings, **can't be stolen**, and are **kept on rebirth** (D3, D17). The rest are **display slots**, which **can be stolen**.
- Right after a rebirth at Star 5 or higher, every one of the 8 slots is a vault slot, so the base can't be robbed until more slots are bought. That's intended, and it's how the sim models it.
- The **storage bag** (60, †) holds everything else. It doesn't earn.
- **Placing**
  - New Glowlings go to storage with a one-tap "Place best" prompt.
  - "Place best" fills the vault with your highest earners first, then display slots.
  - With the Auto-Place pass, this runs automatically on every inventory change, including after a theft.
- **Release** (D9, **sim**)
  - Storage only. Pays `60 × that Glowling's current income/s` in Glow.
  - Epic and above need a second confirmation. Legendary and above need a hold-to-confirm.
  - Glowdex entries are kept.
- **Full storage:** night catches still land, up to 70 (10 over the cap), with a warning. Lures can't be bought while storage is over the cap.

**Acceptance:** after a theft, "Place best" or Auto-Place refills the empty display slot from storage. Releasing a Glowling that's in a display slot, the vault or an open trade is rejected.

---

## 8. Lantern shop and lures

- **Restock** every 5 minutes, at the UTC boundary (`os.time() // 300`), so every server shows the same timer (D13, **sim**).
- **Each player has their own stock** per restock: Common lure 16, Uncommon 8, Rare 4, Epic 2. Unused stock doesn't carry over. (In the sim, 8/4/2/1 delayed casual players' first Legendary to day 8–9; 16/8/4/2 keeps it at day 7.)
- **Lure prices** = `40 × 14^(floor − 1)`, where `floor` is the rarity index:

| Lure | Common | Uncommon | Rare | Epic |
| --- | --- | --- | --- | --- |
| Price (Glow) | 40 | 560 | 7,840 | 109,760 |

- **Featured slot** (†), rotating each restock. One of:
  - a **Species Lure**: 50% chance of the featured Clearing species; the rarity rolls normally
  - a Glow-priced decoration
  - a bundle of 2 Lock Charges
- Lures roll Clearing species only. The roll uses this player's luck. Results and the roll reveal are shown at once, and Glowdex credit is given.

**Acceptance**
- Stock resets at the boundary in every server at once.
- A purchase with insufficient Glow is rejected with no partial charge.
- Two purchases sent in the same frame can't both pass one balance check.

---

## 9. Upgrades and movement

| Upgrade | Cost of the next level | Effect | Max | Reset on rebirth |
| --- | --- | --- | --- | --- |
| Lantern | `150 × 1.55^n` | +12% luck | 60 † | Yes |
| Boots | `150 × 1.5^n` | +4% run speed; +1 night catch per 5 levels | 25 | Yes |
| Slots | `250 × 1.9^k`, where k = slots already bought (slot 9 costs 250, as in `sim_v3.py`) | +1 display slot | 30 slots | Yes |
| Lock Charge | `max(200, 120 × Glow/s)` Glow, or 15 Embers | Skip the lock cooldown once | 5 held | No |

Sample prices:
- Next-level price at Lantern 1 / 5 / 10 / 20: 232 / 1,341 / 12,006 / 961,004 (prices are floored)
- Slot 9 / 13 / 18 / 30: 250 / 3,258 / 80,671 / 1.8e8 (corrected 18 Nov 2026 to match the sim; the old figures were one step ahead)

Every upgrade has a "Buy max" button, which walks the real price list and stops at the max level.

**Movement:** walk 16 studs/s; auto-sprint to 22 after 0.5 s of moving. Run speed = `22 × (1 + 0.04 × Boots) × (1.15 with Swift Boots)`, and ×0.85 while carrying.

---

## 10. Stealing

**Flow**
1. **Grab.** The thief stands within 6 studs of a display slot on another plot and holds the button.
   - Hold time: 1 s for Common to Rare, 2 s for Epic and Legendary, 3 s for Mythic and Secret (†), plus any Guardian bonus on that pad (§31).
   - The owner gets an alarm and a toast at once: "Sam is stealing your Rare Mothlet!", with an arrow.
2. **Carry.** The thief moves at ×0.85 and glows (**Marked**). The owner sees them through walls (a Highlight).
   - The owner gets the **chase boost**: ×1.2 speed for 10 s (D11, **sim**).
   - The thief can't lock their own base while carrying.
3. **Tag-back.** The owner, or any Roblox friend or crew-mate of the owner in the server, comes within 6 studs: the Glowling snaps home.
4. **Deliver.** The thief's root part enters their own plot zone. The record moves to the thief with `src = "steal"`; `by` keeps the original catcher. It's auto-placed under the §7 rules. There's no Glowdex credit (D10).

**Limits**
- Only display slots can be stolen, and only one carry at a time.
- Grabs are blocked from 3:30. Carries snap back at 4:00, after 60 s, or if the thief leaves.
- **Victim cooldown:** after losing a Glowling, a player's display slots are safe for 45 s (†).
- **No bullying:** a thief can take from the same victim at most once per day phase (†).
- Shielded players can't be stolen from (§11).

**Theft insurance** (GDD fallback, behind a flag, off at launch): refunds Embers equal to 5 × the trade fee for that rarity.

**Acceptance**
- A grab interrupted by a tag is cancelled.
- A carrier teleporting 50 studs is snapped back and flagged.
- A thief with Swift Boots and the same Boots level as the owner is caught within 10 s when the owner chases at once (playtest).
- A second steal from the same victim in the same day is rejected.

---

## 11. Base Lock and new-player shield

**Base Lock**
- A tap closes the gate for 60 s. Players outside can't enter the plot zone, and grabs in progress cancel. A thief who is already carrying out of the base keeps going.
- After the lock ends, it recharges for 90 s. A Lock Charge skips the recharge.
- No locks at night.

**Shield** (D2)
- Starts on the first join. Ends at the first rebirth or after 45 minutes of play.
- Shielded plots show a soft bubble. Nobody can steal from them.
- A shielded player's first grab on a human shows "This ends your protection. Steal anyway?" Saying yes ends the shield. The tutorial stash doesn't count.

**Acceptance:** the shield survives a rejoin, with play time accumulating. A lock while someone is mid-grab cancels the grab.

---

## 12. Night: fire, fuel and catching

**Fire** (D1)
- Starts at 60% and is capped at 100%.
- Drain/s = **0.5% + 0.0375% × living players** (downed players don't count). That's 0.8%/s at 8 players, and an unfed fire dies after about 75 s.
- **Wood** (+3%) comes from piles in the forest. Each pile gives 1 piece and respawns 20 s after it's taken.
- **Glow-shards** (+6%, †) spawn more than 150 studs out, in Stalker territory. Hands carry one piece at a time.
- Below 25%: the meter pulses red and the crackle thins.
- **At 0%, the night is Lost.** The clearing goes dark and the Stalker can enter it. Players can still catch until dawn.

**Catching**
- Wild Glowlings spawn in 3 waves (0:10, 0:40, 1:10 into the night), 4 per player in total.
- The **species is visible** (useful for Glowdex hunting). Rarity is rolled **when caught**, with the catcher's luck.
- A tap within 12 studs catches. The roll reveal plays at once, and the Glowling lands in the base at dawn.
- Catches per night = `3 + floor(Boots / 5)`.
- Catching a Mythic or better triggers a server announcement.

**Acceptance**
- Fire numbers: 1 player feeding 2 pieces survives. 8 players feeding 8 pieces in total lose.
- A catch from 20 studs is rejected.
- A 4th catch with 0 left is rejected.

---

## 13. Stalker AI

| State | Behaviour | Exit |
| --- | --- | --- |
| Dormant | First 30 s of night | Timer |
| Prowl | Wanders outside the fire's 30-stud light radius at 14 studs/s | A lone target appears |
| Stalk | Follows a **lone** player: nobody within 20 studs, and outside the fire's radius. **Telegraph:** a heartbeat that gets louder with distance, eye glints, a screen-edge vignette. | 4 s with the target still lone → Lunge. Target reaches a group or the fire → Prowl. |
| Lunge | 1.25 × the target's current speed for 1.5 s. **At least 2 s of telegraph before every lunge.** | Touch → Down. Miss → Retreat. |
| Retreat | Backs off for 10 s, then picks a new target | Timer |

- **Repelled by** the fire's radius, and by a group of 3 or more players within 12 studs (it hisses and retreats). Once the fire is out, the fire's radius no longer repels it.
- **Speed while stalking** = 0.9 × the target's current speed, so it's always just escapable by running to friends or the fire.
- **Pathfinding:** PathfindingService, with the path recomputed every 0.5 s during a chase, and `MoveTo` directly when it has line of sight.
- **First night:** the Stalker's first touch on a player in their first night is a scripted **near-miss**. The player is shoved toward the fire, not downed.
- **Calm mode** (§26): same behaviour, no stinger, no shake, softer visuals.
- **Mild-rating design:** see CONTENT_AND_LIVEOPS.md §A4.

**Acceptance**
- It never targets a player inside the fire's radius or in a group of 3.
- Every lunge has at least 2 s of telegraph (verified from logs).
- Fear test G3.

---

## 14. Downed, revive and the dawn result

- **Downed:** the player is frozen in shadow (tinted, still) and can't act. Bleed-out takes 30 s.
- **Revive:** a teammate holds for 3 s within 8 studs. The revived player gets 3 s of safety.
  - The reviver gets +5 Embers (up to 4 times a night) and 25 pass XP.
  - If they aren't already friends, the revived player gets a "Send friend request?" prompt (Roblox's own prompt).
- **Not revived in time:** the player becomes a spectator wisp until dawn and loses their unused catches. Catches already made are kept.
- **Dawn result:**

| Outcome | Rewards |
| --- | --- |
| Survived | `10 + floor(fire% / 10) + 5 × revives (max 4) + 1 × pieces fed (max 6)` Embers, × the friend bonus (§25). Next night's luck ×1.25. Night Pass XP. |
| Lost | 3 Embers, −5% Glow, 40 pass XP |

- Dawn is presented as a **natural stopping point**: "Good night's work. Your Glowlings keep earning while you're away."

---

## 15. Rebirth

- **Requirement:** earn `250,000 × 3.2^k` Glow since the last rebirth, where k = current Stars.
  - **After Star 8, growth drops to 2.0×.** This ships at launch (D8, sim-verified).
- **What you get:** +1 Star, which permanently adds +35% income, +6% luck and +1 vault slot.
- **What's wiped:** Glow, Lantern, Boots, Slots (back to 8), display and storage Glowlings.
- **What's kept:** the vault, your single best Glowling if it isn't in the vault, Embers, Stars, decorations, the Glowdex, the Night Pass, Lock Charges and quests (D3, **sim**).
- **Confirm screen:** lists exactly what will be lost and kept, with a hold-to-confirm. A short star-burst cinematic plays.
- Badges at Star 1, 5 and 10.

**Acceptance**
- Server state after rebirth matches the kept/wiped lists.
- A rebirth request below the threshold is rejected.
- The threshold test passes up to Star 28 (TECH_SPEC §5).

---

## 16. Glowdex

**Entries:** each species counts only the rarities it can be caught at (from its `minRarity` up to Secret, D18): 30 species × 7 + 5 × 5 (Rare floor) + 4 × 4 (Epic floor) + 1 × 3 (Legendary floor) = **254**, plus a Golden and a Rainbow stamp per species. Limited species add their own pages.

**Credit:** night catches, lure rolls, event catches and the tutorial. Not steals, trades or Fuse (D10).

**Page tiers per species** (†, **sim**):

| Tier | Needs | Reward |
| --- | --- | --- |
| Bronze | Every reachable rarity up to Epic (just the floor rarity if the floor is above Epic) | +0.5% income, plus a decoration of that species |
| Silver | + Legendary | +0.5% income, plus a nameplate frame |
| Gold | + Mythic | +1% income, plus a trophy statue variant |
| Radiant | + Secret | An aura for your Glowlings of that species, plus a title |

**Milestones** on total entries: 10 / 25 / 50 / 100 / 150 / 200 / 254 (all) give 25 / 50 / 100 / 200 / 300 / 500 / 1,000 Embers and titles.

**Acceptance:** a catch updates the entry within 1 s. A page reward can be claimed only once (server-checked).

---

## 17. Trading

- **Unlock:** Stars ≥ 3, **and** 3 different play days, **and** Roblox account age ≥ 7 days (†), **and** `PolicyService` allows item trading for both players, **and** the kill switch is off.
- **Flow**
  1. Request a player in the same server.
  2. Each side offers up to 4 Glowlings. **No Glow and no Embers in trades** (†; this limits real-money trading).
  3. Each Glowling's rarity, mutation, size and income are shown. If one side's income value is 5× or more the other's, a warning appears: "This trade looks uneven."
  4. Confirm unlocks 5 s after the last change to either offer.
  5. When both confirm, a **2-minute cooling-off** starts. Items are locked, and either player can cancel.
  6. When it ends, the server swaps both sides atomically and force-saves both profiles.
- **Fee** (D12): the receiver pays per Glowling received. Common 1, Uncommon 2, Rare 5, Epic 10, Legendary 25, Mythic 50, Secret 100 Embers. A player who can't pay can't confirm.
- **Limits:** traded Glowlings can't be traded again for 24 hours. At most 10 trades a day.
- If either player leaves, or the server shuts down, before the swap, nothing moves.

**Acceptance**
- Kill the server during the cooling-off: both inventories are unchanged after rejoining.
- Offering a Glowling the player doesn't own is rejected.
- An audit record is written for every trade of Legendary or above.

---

## 18. Decorations and base identity

- Decorations are bought with Embers. 24 items at launch (CONTENT_AND_LIVEOPS.md §A5), priced 20–400 Embers. They're placed on a 2-stud grid, rotate in 90° steps, and are capped at 60 placed. **Never wiped.**
- **Trophy pedestal:** shows one vault Glowling at 1.5× size, with a plaque: species, rarity, date, "caught by".
- **Base name:** a preset adjective + noun (64 × 64 word lists), for example "Mossy Hollow". No free text.
- **Base brightness** comes from the Glowlings placed there, so rare bases visibly glow brighter across the clearing.
- Base themes (ground and fence sets) arrive in week L5.

---

## 19. Quests, daily gift and goal tracker

**Daily quests:** 3 a day, reset at 00:00 UTC. Each gives 15 Embers and 150 pass XP, and one free reroll is allowed a day. Pool:
- feed the fire 4 times
- revive a teammate
- catch 3 Glowlings at night
- catch a Rare or better
- survive 2 nights
- buy 3 lures
- place 10 Glowlings
- earn N Glow (scaled to income)
- steal 1 Glowling (low weight, and never given to shielded players)

**Weekly quests:** 3 a week, reset Monday 00:00 UTC. Each gives 75 Embers and 500 XP. Examples: survive 20 nights, revive 10 times, finish 2 Bronze pages, earn a Star.

**Daily gift:** a 28-step calendar that advances **one step per day you play and never resets** (GDD). Rewards include Embers, lures and Lock Charges, a guaranteed-Epic lure on day 7, and an exclusive decoration on day 28. After that it loops with new rewards.

**Goal tracker** (†): always shows 3 goals, each with an estimate in nights, based on current income.
1. **Next** (within 1 cycle): "Lantern 5: 1,200 Glow to go"
2. **Session** (3–5 cycles): "Rebirth: 63% (~2 nights)"
3. **Long** (days): a Glowdex page, a weekly quest or a pass tier

The candidates are scored by estimated time to finish, and the closest one in each band is shown.

---

## 20. Night Pass

- 8-week seasons with 50 tiers, 1,000 XP each.
- **XP:** surviving a night 100, losing one 40, a revive 25, a daily quest 150, a weekly quest 500. In the last 2 weeks, ×1.5 XP to catch up.
- **Estimated time to finish:** engaged players about 26 days, casual players about 47. The season lasts 56 days.
- **Free track** (every 2 tiers): Embers, lures, decorations. **Premium track** (every tier): lantern skins, base banners, Glowling auras and trails, decorations, about 1,500 Embers in total. **All of it is cosmetic**, apart from the Embers.
- **Premium** is a **developer product per season** (399 R$), because a game pass would be permanent. It can also be bought for 3,500 Embers (D14).
- Anything unclaimed is claimed automatically at the end of the season.

---

## 21. Events, limited species and the daily featured species

- **Weekend event:** Friday 15:00 UTC to Monday 00:00 UTC. It's driven by LiveConfig: luck, Ember and spawn multipliers, Moonlit mutation on or off, and special spawns. The templates are in CONTENT_AND_LIVEOPS.md §C4.
- **Weekly limited species**
  - One a week, Friday to Thursday. It makes up 10% of night spawns and can be any rarity.
  - It has its own "Limited" Glowdex page.
  - **Every limited species returns once within 6 months** (†; this keeps the fear of missing out humane).
- **Daily featured species:** one Deepwood species gets 2× spawn weight for the UTC day, and appears on the HUD.
- **Community goal:** a global counter, for example "Survive 1,000,000 nights this weekend". Each tier reached rewards everyone who survived at least one night during the event.
- **Codes:** redeemed in Settings, once per account, for Embers or lures only.

---

## 22. FTUE: phase-aware (D7)

| Step id | Beat | Notes |
| --- | --- | --- |
| 1 `spawn` | Spawn at your plot. A guide Wisp flies to a glowing **Free Lure**: "Tap!" | Reward within 10 s |
| 2 `first_lure` | A guaranteed **Uncommon** Clearing Glowling, placed automatically. Glow starts ticking, with floating numbers. | The tutorial roll isn't part of the odds; it does give Glowdex credit |
| 3 `first_income` | At 40 Glow, an arrow to the shop: "Buy a Lure" | About 10 s |
| 4 `first_buy` | Buy a Common lure; roll reveal | Teaches the spend loop |
| 5 `tutorial_steal` | Arrow to the **Wisp's Stash**, a shared pedestal at the edge of the clearing: "Steal one!" Hold, carry home. Nobody can tag. | Grants a Common. Doesn't end the shield. |
| 6 `first_lock` | Tap Lock once; the recharge is shown | |
| 7 `first_dusk` | Dusk horn: "Night is coming. Stick together by the fire." | |
| 8 `first_feed` | Arrow to wood, then the fire: "Feed the fire" | First co-op act |
| 9 `first_catch` | A personal **Rare**, visible only to this player, near the fire: "Catch it!" | First Rare within the first cycle |
| 10 `first_dawn` | "You survived! +Embers." Goal: "Rebirth at 250K Glow ⭐". The shield is explained. | Sets the session goal |

**Paths**
- **Day path** (joins with more than 60 s of day left): 1 → 6, free play, then 7 → 10.
- **Late-day path** (60 s or less left): 1 → 4, then 7 → 10, then 5 → 6 at dawn.
- **Night-first path** (joins at night): the Free Lure is on the Wisp, at the fire. Then 1 → 2, 8 → 10, and 3 → 6 at dawn.

**Fail-safes**
- If a step isn't done within 20 s, the hint grows (pulsing button, bigger arrow).
- Rejoining resumes at the saved step.
- The first Stalker touch is a near-miss (§13).
- Every step fires `LogOnboardingFunnelStepEvent`.

**Acceptance:** G3, on all three paths.

---

## 23. Monetization

| Product | Kind | R$ | Exact effect |
| --- | --- | --- | --- |
| VIP Lantern | Game pass | 299 | ×1.5 Glow income (offline too), a VIP chat tag (TextChatService), a golden lantern skin |
| +2 Vault Slots | Game pass | 199 | Vault +2 |
| Swift Boots | Game pass | 149 | ×1.15 run speed (balanced by the chase boost, D11) |
| Auto-Place | Game pass | 99 | Auto-optimizes slots and vault on every inventory change |
| Night Pass Premium | Dev product, per season | 399 | Unlocks the premium track for the current season |
| Ember packs | Dev product | 49 / 199 / 799 | 120 / 550 / 2,400 Embers |
| Lock Charge ×3 | Dev product | 25 | +3 charges (up to the max of 5) |
| Server Luck | Dev product | 99 | +50% luck for **everyone in the server** for 15 min. Buying again extends it, up to 60 min queued. Announced: "Sam lit the Lucky Lantern!" |
| Roblox Premium perk (†) | — | — | +10 Embers a day |

**Rules**
- **Embers never buy anything random. Glow is never sold.** No product sells a Glowling.
- **PolicyService**
  - `ArePaidRandomItemsRestricted`: Server Luck (a paid probability modifier) is hidden.
  - Item trading not allowed: trading is disabled for that player.
- **Daily caps:** Ember packs 3, Lock Charges 5, Server Luck 2 a day per buyer. They're checked before prompting. If a receipt still arrives, **it's always granted**.
- **`ProcessReceipt`**
  1. If the profile isn't loaded, return `NotProcessedYet`.
  2. If `receipts[PurchaseId]` exists, return `PurchaseGranted`.
  3. Otherwise grant, record the id, `Save()`, and return `PurchaseGranted`.
- **No unprompted purchase pop-ups.** Never prompt during a theft, within 30 s of losing a Glowling, or on the lost-night screen (D6).
  - The store is always one HUD tap away.
  - The only nudge is a single non-blocking "Store" highlight after the first rebirth.
- Prices are shown in R$, with no fake "was" prices or countdown timers.

**Acceptance**
- A duplicate receipt is granted once.
- A purchase made while leaving is granted on the next join.
- A policy-restricted test account never sees Server Luck.

---

## 24. Leaderboards and badges

- **In-world boards:** all-time Stars, all-time Glowdex entries, weekly **Kindest Keepers** (revives), weekly nights survived. Weekly boards reset every Monday, so newcomers can place.
- **Badges at launch (15):**
  - Welcome
  - first night survived
  - first Rare, Epic, Legendary, Mythic and Secret
  - first rebirth, Star 5, Star 10
  - first Bronze page
  - 10 revives
  - saved the fire below 5%
  - 7 play days
  - first trade

---

## 25. Social

- **Friend co-play bonus:** +10% dawn Embers for each Roblox friend in the server, up to +30%.
- **Invites:** an Invite button on the HUD and the dawn screen ("Nights are easier with friends") uses `SocialService:PromptGameInvite`, with the inviter's id in the launch data. When an invited friend survives their first night, the inviter gets 25 Embers, for up to 5 friends.
- **Quick chat:** "GG", "Thanks!", "Help!", "Fire's low!" as buttons, plus a GG emote, so younger players can talk without typing.
- **Announcements:** Mythic-or-better catches, Server Luck, and a fire saved below 5%.

---

## 26. Settings and accessibility

- **Calm mode:** no stingers or screen shake, a softer Stalker look. Behaviour is unchanged.
- **Reduced flashing:** no strobe in rarity VFX.
- **Colour-blind safe:** every rarity has its own icon shape and label.
- **Subtitles for audio cues:** "[Dusk horn]", "[Stalker nearby]".
- Music and SFX sliders, UI scale, haptics on mobile.
- **Break reminder** (on by default): a gentle toast at dawn after 120 minutes of continuous play.

---

## 27. Notifications

- Roblox experience notifications are opt-in only. The opt-in is offered after the player's **first survived night**: "Want a heads-up when weekend events start?"
- Only sent for a weekend event starting or a new season, at most once a week.
- Never sent about restocks, theft or "come back" pressure.

---

## 28. Crews (week L4)

- Crews of up to 4, with names from the preset word lists.
- Created and joined only through an in-server invite from a crew member. Stored in the `Crews` DataStore via `UpdateAsync`.
- **Bonus:** with 2 or more crew members in a server, the dawn fire bonus gets +10% Embers.
- A weekly crew leaderboard counts nights survived and revives.
- **"Crew Up"** teleports you to a crew-mate's server if it has space.

---

## 29. Fuse (week L3, sim)

5 Glowlings of the same species and rarity, Common to Rare, fuse into 1 of the next tier, so the best possible result is Epic. Mutation and size are kept from the best input. It's a sink for duplicates, and gives no Glowdex credit.

---

## 30. Wisps (low priority)

The GDD added night-only bots because small servers struggled. D1's drain formula already scales the fire to the player count, so Wisps **don't feed the fire**: that would make a solo night free again. Instead, in a server with fewer than 4 players, friendly Wisps drift ahead of players toward the nearest wood and shards, and make the clearing feel alive. They can be turned off in config.

---

## 31. Pet traits (D20–D23, sim pending)

Every species has a **family** and one **trait** (CONTENT_AND_LIVEOPS §A3). Traits are rules on placed Glowlings, not physics: the server applies them when placements change (and at Overcharge start and end), with no new per-second loop. The rules live in `Shared.Traits`; numbers live in `config/species.json` (per species) and `economy.traits` (shared). All numbers are † and **sim**.

**Neighbours:** the pads that share an edge on the plot's pad grid (vault and display pads alike).

**Shipped in traits v1:** family link, Harmonizer (and the whole-plot Skywhale Calf and Lunadrake), Guardian (and Elder Sapling), the cap, species floors (with D25 for wilds), and Glowdex reachable entries. **Next:** Infuser Overcharge, Forager pouches, Aurora Lynx, then the Night Companion. With today's numbers the best stack is ×1.581 (two links, a Harmonizer, Lunadrake), so the ×1.6 cap is a guard for tuning.

**Family link (everyone):** +5% Glow/s for each neighbour of the same family, up to +10%.

**Day traits (on the plot)**

| Trait | Effect | Notes |
| --- | --- | --- |
| Harmonizer | Its same-family neighbours get +15% Glow/s | Doesn't boost itself; several Harmonizers next to one Glowling don't stack (the highest counts) |
| Guardian | Its own pad and its neighbours get +0.5 s grab time (+1.0 s if the species' floor is Rare or higher) | Highest bonus per pad counts; at most +1.5 s on any pad |
| Infuser | Every 60 s, one random neighbour gets **Overcharge**: ×1.5 Glow/s for 30 s | Overcharge never stacks, isn't saved, isn't a mutation, and ends if the Glowling moves or is stolen |
| Forager | Every 90 s, adds a Glow pouch worth 30 × its own Glow/s | Auto-collected at launch (a basket later); never Embers (D21) |

**Apex species** (floors of Epic or Legendary) use the whole-plot version of their trait. Whole-plot effects don't stack with each other: the highest applies.

| Species | Whole-plot effect |
| --- | --- |
| Aurora Lynx | Infuser: every 45 s, Overcharge on up to 6 pads for 30 s |
| Skywhale Calf | Harmonizer: +15% Glow/s to every Glowling on the plot, any family |
| Elder Sapling | Guardian: +1.0 s grab time on every display pad |
| Emberwing | Firebinder as companion: fuel value +50% |
| Lunadrake | Harmonizer: +25% Glow/s to every Glowling on the plot, any family |

**Cap:** family link × Harmonizer × Overcharge × whole-plot bonus is at most **×1.6** per Glowling (`traitMult`). Forager pouches are outside the cap but count as income for the sim.

**Night Companion (D23, ships after traits v1)**
- One companion slot, chosen from your vault Glowlings. It stays on its pad (still earning, still safe); a client-only copy floats beside you at night. It changes only at day.
- Firebinder: wood and shards you feed count +15% (Rare floor or lower) or +30% (higher floors); Emberwing +50%. Fire maths in §12 use the boosted value.
- Wayfinder: every 10 s, points to the nearest Rare-or-better wild Glowling or Glow-Shard within 60 studs.
- Savior: your revive hold is 0.6 s shorter (never under 1.8 s).
- Day traits of the companion keep working on its pad.

**Not doing (D21, D22):** Embers from traits, knockback, protection from the night-lost penalty, server-wide luck from a player's Glowling, guaranteed mutations, permanent mutations from Infusers, longer Base Lock. A rare **Dawn Jackpot** (a permanent upgrade of one unmutated Glowling) and **Sanctuary Blooms** are post-launch ideas, each only after a sim run.

**Acceptance**
- Placing two same-family Glowlings side by side raises both by 5% within 1 s; moving one away removes it.
- A thief grabbing a pad next to a Guardian sees the longer hold, and the server times it.
- Overcharge shows on the boosted Glowling, ends after 30 s, and the income returns to normal.
- No Glowling's trait multiplier ever exceeds 1.6 (a Lune test over random plots).
- A Common roll never gives a species whose floor is above Common.

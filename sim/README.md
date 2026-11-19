# Economy sim

| File | What it is |
| --- | --- |
| `sim.py` | The original model behind the GDD's simulation table. It's unchanged, so it stays the baseline. |
| `sim_v3.py` | A config-driven port. It reads `../config/economy.json`, the same file the game will load, and runs named scenarios. |
| `sim_results.json` | `sim.py`'s output |
| `results_v3_30d.json`, `results_v3_60d.json` | `sim_v3.py`'s output for 30 and 60 days (18 Nov 2026) |
| `golden_odds.py` → `golden_odds.json` | Values the game's Luau modules must reproduce: odds, luck, thresholds, prices, fire outcomes. Pure Python. Rerun after any config change; CI runs `--check`. |

```powershell
python sim_v3.py --list
```

```powershell
python sim_v3.py
```

```powershell
python sim_v3.py gdd plan --days 60
```

The scripts need Python 3 and numpy. A full run (11 scenarios × 3 play styles × 200 players) takes about 3 minutes.

**Parity:** scenario `gdd` reproduces `sim.py` exactly: every milestone, the Stars and income at day 30, and the theft ratio (1.0304). Any change to `sim_v3.py` should keep it that way.

## Results (30 days, 200 players per style)

Each cell shows the share of players who reached the milestone by day 30, then the median day they reached it.

| Scenario | Casual first Legendary | Engaged first Legendary | Engaged Mythic | Hardcore Secret | Stars D30 (C/E/H) | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `gdd` (sim.py) | 92%, day 5 | 100%, day 2 | 64%, day 11.5 | 38% | 8 / 9 / 11 | Baseline |
| `gdd+extras` (pity + fire bonus, GDD rules not modelled before) | 100%, day 6 | 100%, day 3 | 70%, day 13 | 35% | 8 / 9 / 11 | Fine |
| `D3_vault` (rebirth keeps the vault) | 94%, day 6 | 100%, day 2 | 61%, day 14 | 37% | 8 / 9 / 11 | Small effect. Keep it. |
| `D4_clamp` (lure results capped at Epic) | 78%, **day 14** | 100%, day 6 | 55%, day 15 | 36% | 7 / 9 / 11 | **Rejected** |
| `D8_step` (2.0× after Star 8) | 92%, day 5 | 100%, day 2 | 63%, day 11 | 38% | 8 / 9 / 12 | No change before day 30. Keep it. |
| `D9_storage` (storage 60 + Release refund) | 92%, day 5 | 100%, day 2 | 64%, day 11 | 37% | 8 / 9 / 11 | No effect. Keep it. |
| `D13_stock8` (lure stock 8/4/2/1) | 91%, **day 8** | 100%, day 3 | 64%, day 11 | 32% | 7 / 9 / 11 | **Rejected** |
| `D13_stock16` (lure stock 16/8/4/2) | 94%, day 7 | 100%, day 3 | 64%, day 12 | 30% | 7 / 9 / 11 | Keep it |
| **`plan`** (the committed config) | **100%, day 7** | **100%, day 2** | **68%, day 11** | **42%** | **8 / 10 / 13** | **Shipping** |
| `plan_clamp` | 98%, day 14 | 100%, day 5 | 62%, day 13 | 40% | 8 / 10 / 13 | Rejected |
| `plan_nostep` | 100%, day 7 | 100%, day 2 | 68%, day 11 | 46% | 8 / 10 / 12 | — |

- **Theft** stays income-neutral under `plan`: income with theft is 99% of income without it (GDD: 103%).
- **Where first Legendaries come from** (night / lure / steal): about 38 / 61 / 1% under `gdd`, and about 52 / 48 / 0% under `plan`.

## Long run (60 days): why D8 ships at launch

Median Stars at days 7 / 14 / 30 / 45 / 60:

| Scenario | Casual | Engaged | Hardcore |
| --- | --- | --- | --- |
| `gdd` | 5 / 6 / 8 / 8 / 9 | 7 / 8 / 9 / 10 / 10 | 9 / 10 / 11 / 12 / 13 |
| `plan_nostep` | 5 / 6 / 8 / 8 / 9 | 7 / 8 / 10 / 10 / 11 | 9 / 10 / 12 / 13 / 13 |
| `plan` (2.0× after Star 8) | 5 / 6 / 8 / 8 / 9 | 7 / 8 / 10 / 11 / 12 | 9 / 11 / 13 / 15 / 16 |

**Play-hours per rebirth for engaged players, Star 8 → 12:**
- Without the step: 9.2, 15.1, 24.2, then 17.2 h. The last figure comes from only the 18% who got that far. Each rebirth takes about 1.6× longer than the last.
- With the step after Star 8: 9.2, 10.1, 14.4, then 16.9 h, about 1.1–1.4× each.
- A step after Star 10 barely helped engaged players, because most of them don't get past Star 10 within 60 days anyway.

**Casual players** reach only Star 9 by day 60 in every scenario. Their long-term goals have to come from the Glowdex, limited species and the Night Pass.

## Not modelled yet

These are the next additions, in order of likely impact:

1. **Boots:** +1 night catch per 5 levels, and the spending on Boots
2. **Glowdex page bonuses:** +0.5–1% income per page tier
3. **Night modifiers:** Firefly Bloom gives +1 catch, Fog gives +25% spawns
4. **VIP ×1.5 Glow, and Server Luck**
5. **Embers and the Night Pass:** sources, sinks and pacing
6. **Theft rate:** a fixed 6% per day phase. The chase boost, victim cooldown and shield need real playtest numbers (gate G2).

## Assumptions (in `ASSUME`)

| Assumption | Value |
| --- | --- |
| Theft per day phase | 6% (both losing and gaining) |
| Offline time per day | 16 h (capped by the game at 6 h) |
| Nights where the fire survives | 75% |
| Chance a cycle sees a second restock | 20% |
| Lantern buying | The greedy player buys Lantern only if it costs under 60% of the balance |

Profiles come from the GDD: casual 3×8 min, engaged 4×20 min, hardcore 6×45 min. Sessions are rounded to whole 6-minute cycles, so a casual session is 1 cycle.

`sim.py` line 15 has a stale comment ("2.5e5*6^k"). The code uses `reb_g = 3.2`. It's left unedited so the baseline stays byte-for-byte the original.

## Traits (GAME_SYSTEMS §31), 19 Nov 2026

`sim/trait_income.luau` runs the real `Shared.Traits` (multipliers, Overcharge, Forager pouches) on random collections for 30 minutes of 2 s ticks and writes `trait_income.json`: income with traits ÷ income without, by slot count. `sim.traits` ("placeBest" or "arranged") multiplies the sim's income by it.

| Slots | Place best | Arranged |
| --- | --- | --- |
| 8 | ×1.11 | ×1.19 |
| 18 | ×1.12 | ×1.23 |
| 30 | ×1.14 | ×1.27 |

Pacing effect (200 seeds, 30 days):

| Scenario | casual Star 5 | engaged Star 5 | Stars d30 casual / engaged / hardcore |
| --- | --- | --- | --- |
| plan | d7 | d3 | 8 / 10 / 13 |
| plan_traits | d6 | d3 | 8 / 10 / 14 |
| plan_traits_arr | d6 | d2 | 8 / 10 / 14 |

Rarity milestones move only within noise (traits don't touch luck). Verdict: no retune needed; the ×1.6 cap is never near the average.

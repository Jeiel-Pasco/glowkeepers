"""Glowkeepers economy sim v3: a config-driven port of sim.py.

Reads ../config/economy.json, the same file the game loads. Each scenario overrides a few
config values, so the effect of every plan decision (IMPLEMENTATION_PLAN.md section 3) can be
measured on its own.

Scenario "gdd" reproduces sim.py exactly: same seeds, same RNG call order, same numbers.

Usage:
  python sim_v3.py                       # every scenario, 30 days, 200 seeds
  python sim_v3.py gdd plan --days 60    # chosen scenarios
  python sim_v3.py --list
"""
import argparse
import copy
import json
import os
from multiprocessing import Pool

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = os.path.join(HERE, "..", "config", "economy.json")
# Trait income factor by slot count, measured with the real Shared.Traits (sim/trait_income.luau).
TRAIT_PATH = os.path.join(HERE, "trait_income.json")
RAR = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
LEG = 4  # zero-based index of Legendary

# Player-behaviour assumptions. These are not game config; they describe the simulated players.
PROFILES = {"casual": (3, 8), "engaged": (4, 20), "hardcore": (6, 45)}  # sessions/day, minutes/session
ASSUME = dict(
    theft_per_day_phase=0.06,  # chance per day phase that you lose a display Glowling, and that you steal one
    offline_hours_away=16,
    fire_survival=0.75,  # share of nights the fire survives (only used when fireBonus is on)
    second_restock_chance=0.2,  # a 6-min cycle spans two 5-min restocks 20% of the time
    lantern_spend_share=0.6,  # greedy player buys Lantern only if it costs < 60% of the balance
)

# What the GDD/sim.py did, expressed as config overrides.
GDD = {
    "lures.resultCap": None,  # sim.py: lure floor capped at Epic, but the roll itself can go higher
    "lures.stockPerRestock": None,  # unlimited lures
    "rebirth.keepVault": False,  # keep only the single best Glowling
    "storage.size": None,  # inventory trimmed to 3 x slots
    "storage.releaseIncomeSeconds": 0,
    "pity.legendaryAfterNightCatches": None,  # pity not modelled
    "upgrades.lantern.max": None,
    "rebirth.stepEnabled": False,  # 3.2x growth forever
    "sim.fireBonus": False,  # +25% luck after a survived night not modelled
}

# "plan" = config/economy.json exactly as committed. The others isolate one decision each.
SCENARIOS = {
    "gdd": ("GDD / sim.py as-is", dict(GDD)),
    "gdd+extras": ("GDD + pity + fire bonus (GDD rules the old sim left out)",
                   {**GDD, "pity.legendaryAfterNightCatches": 150, "sim.fireBonus": True}),
    "D3_vault": ("GDD + rebirth keeps the vault", {**GDD, "rebirth.keepVault": True}),
    "D4_clamp": ("GDD + lure results capped at Epic (rejected)", {**GDD, "lures.resultCap": 4}),
    "D8_step": ("GDD + rebirth growth 2.0x after Star 8", {**GDD, "rebirth.stepEnabled": True}),
    "D9_storage": ("GDD + storage 60 + Release refund", {**GDD, "storage.size": 60, "storage.releaseIncomeSeconds": 60}),
    "D13_stock8": ("GDD + lure stock 8/4/2/1 per restock (rejected)", {**GDD, "lures.stockPerRestock": [8, 4, 2, 1]}),
    "D13_stock16": ("GDD + lure stock 16/8/4/2 per restock", {**GDD, "lures.stockPerRestock": [16, 8, 4, 2]}),
    "plan": ("config/economy.json as committed (all plan decisions)", {"sim.fireBonus": True}),
    "plan_clamp": ("plan + lure results capped at Epic (rejected)", {"sim.fireBonus": True, "lures.resultCap": 4}),
    "plan_nostep": ("plan without the rebirth step-down", {"sim.fireBonus": True, "rebirth.stepEnabled": False}),
    "plan_traits": ("plan + traits, Place best order (casual-like)", {"sim.fireBonus": True, "sim.traits": "placeBest"}),
    "plan_traits_arr": ("plan + traits, pads arranged for links (engaged-like)", {"sim.fireBonus": True, "sim.traits": "arranged"}),
}


def load_cfg(overrides):
    with open(CFG_PATH, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg = copy.deepcopy(cfg)
    cfg.setdefault("sim", {"fireBonus": True})
    for path, value in overrides.items():
        node = cfg
        *parents, leaf = path.split(".")
        for key in parents:
            node = node.setdefault(key, {})
        node[leaf] = value
    return cfg


def simulate(args):
    cfg, profile, days, seed, theft = args
    rng = np.random.default_rng(seed)
    sess_per_day, minutes = profile

    rar = cfg["rarities"]
    ODDS = np.array([1 / r["oneIn"] for r in rar])
    BASE = np.array([r["glowPerSec"] for r in rar], float)
    mut = {m["id"]: m for m in cfg["mutations"]}
    MUT = [(1 / mut["Golden"]["oneIn"], float(mut["Golden"]["mult"])),
           (1 / mut["Rainbow"]["oneIn"], float(mut["Rainbow"]["mult"]))]
    lk = cfg["luck"]
    luck_from = lk["appliesFromRarity"] - 1
    size_min, size_max = cfg["size"]["min"], cfg["size"]["max"]
    lures = cfg["lures"]
    max_floor = lures["maxFloor"] - 1
    result_cap = None if lures["resultCap"] is None else lures["resultCap"] - 1
    stock_cfg = lures["stockPerRestock"]
    lan_cfg, slot_cfg = cfg["upgrades"]["lantern"], cfg["upgrades"]["slots"]
    inc_cfg, rb, vault_cfg, store_cfg = cfg["income"], cfg["rebirth"], cfg["vault"], cfg["storage"]
    pity_n = cfg["pity"]["legendaryAfterNightCatches"]
    fire_bonus = cfg["sim"]["fireBonus"]
    trait_mode = cfg["sim"].get("traits")
    if trait_mode:
        with open(TRAIT_PATH, encoding="utf-8") as f:
            table = json.load(f)
        trait_x = [row["slots"] for row in table]
        trait_y = [row[trait_mode] for row in table]

    def roll(luck, floor_t=0):
        # Rarest first; luck multiplies the odds of Rare and above, capped per tier.
        p = ODDS.copy()
        p[luck_from:] = np.minimum(p[luck_from:] * luck, lk["tierCap"])
        for t in range(6, floor_t - 1, -1):
            if t == floor_t or rng.random() < p[t]:
                m = 1.0
                r = rng.random()  # one draw decides the mutation, as in sim.py
                if r < MUT[1][0]:
                    m = MUT[1][1]
                elif r < MUT[0][0]:
                    m = MUT[0][1]
                size = rng.uniform(size_min, size_max)
                return t, m, size
        raise AssertionError("unreachable: the floor tier always returns")

    def rebirth_req(k):
        if rb.get("stepEnabled") and k > rb["stepAfterStar"]:
            s = rb["stepAfterStar"]
            return rb["baseRequirement"] * rb["growth"] ** s * rb["growthAfterStep"] ** (k - s)
        return rb["baseRequirement"] * rb["growth"] ** k

    glow = 0.0
    pets = []  # (tier, value)
    slots, lan, stars, earned = slot_cfg["start"], 0, 0, 0.0
    first, first_src, log = {}, {}, []
    t_play, pity, fire_ok_last = 0.0, 0, False

    def income():
        best = sorted(pets, key=lambda x: -x[1])[:slots]
        traits = float(np.interp(slots, trait_x, trait_y)) if trait_mode else 1.0
        return sum(v for _, v in best) * (1 + inc_cfg["starBonus"] * stars) * traits

    def luck():
        return (1 + lk["perLanternLevel"] * lan) * (1 + lk["perStar"] * stars)

    def add(t, m, size, src):
        pets.append((t, BASE[t] * m * size))
        first_src.setdefault(t, src)

    add(*roll(1, 1), "tutorial")  # tutorial: free guaranteed Uncommon lure
    for day in range(days):
        if day > 0:
            off = income() * inc_cfg["offlineEfficiency"] * min(ASSUME["offline_hours_away"], inc_cfg["offlineCapHours"]) * 3600
            glow += off
            earned += off
        cycles = max(1, round(minutes / 6))
        for _ in range(sess_per_day):
            for _ in range(cycles):
                t_play += 6
                # DAY (240 s): earn, theft risk, spend
                x = income() * 240
                glow += x
                earned += x
                vault_n = vault_cfg["start"] + vault_cfg["perStar"] * stars
                if theft and len(pets) > vault_n and rng.random() < ASSUME["theft_per_day_phase"]:
                    cand = sorted(pets, key=lambda x: -x[1])[vault_n:slots]
                    if cand:
                        pets.remove(cand[rng.integers(len(cand))])
                if theft and rng.random() < ASSUME["theft_per_day_phase"]:
                    add(*roll(luck()), "steal")
                stock = None
                if stock_cfg is not None:
                    stock = list(stock_cfg)
                    if rng.random() < ASSUME["second_restock_chance"]:
                        stock = [2 * s for s in stock]
                while True:
                    lan_c = lan_cfg["baseCost"] * lan_cfg["growth"] ** lan
                    slot_c = slot_cfg["baseCost"] * slot_cfg["growth"] ** (slots - slot_cfg["start"])
                    full = len(pets) >= slots
                    weakest = min(v for _, v in sorted(pets, key=lambda x: -x[1])[:slots]) if full else 0
                    tier = (int(np.floor(np.log(max(glow, 1) / lures["baseCost"]) / np.log(lures["growth"])))
                            if glow >= lures["baseCost"] else -1)
                    tier = min(tier, max_floor)
                    if stock is not None:
                        while tier >= 0 and stock[tier] <= 0:
                            tier -= 1
                    opts = []
                    lan_ok = lan_cfg["max"] is None or lan < lan_cfg["max"]
                    if lan_ok and glow >= lan_c and lan_c < ASSUME["lantern_spend_share"] * glow:
                        opts.append(("lan", lan_c))
                    if full and slots < slot_cfg["max"] and glow >= slot_c:
                        opts.append(("slot", slot_c))
                    if tier >= 0 and (not full or BASE[tier] > weakest):
                        opts.append(("lure", lures["baseCost"] * lures["growth"] ** tier))
                    if not opts:
                        break
                    k, cost = min(opts, key=lambda x: x[1])
                    glow -= cost
                    if k == "lan":
                        lan += 1
                    elif k == "slot":
                        slots += 1
                    else:
                        if stock is not None:
                            stock[tier] -= 1
                        t, m, size = roll(luck(), tier)
                        if result_cap is not None and t > result_cap:
                            t = result_cap
                        add(t, m, size, "lure")
                # NIGHT (120 s): earn, catch
                x = income() * 120
                glow += x
                earned += x
                night_luck = luck() * (lk["fireSurvivedMult"] if fire_bonus and fire_ok_last else 1)
                for _ in range(cfg["night"]["baseCatches"]):
                    if pity_n is not None and pity >= pity_n:
                        t, m, size = roll(night_luck, LEG)
                    else:
                        t, m, size = roll(night_luck)
                    if pity_n is not None:
                        pity = 0 if t >= LEG else pity + 1
                    add(t, m, size, "night")
                if fire_bonus:
                    fire_ok_last = rng.random() < ASSUME["fire_survival"]
                # inventory cap; Release refunds Glow for what's dropped
                pets.sort(key=lambda x: -x[1])
                cap_n = slots * 3 if store_cfg["size"] is None else slots + store_cfg["size"]
                if store_cfg["releaseIncomeSeconds"] and len(pets) > cap_n:
                    refund = sum(v for _, v in pets[cap_n:]) * store_cfg["releaseIncomeSeconds"] * (1 + inc_cfg["starBonus"] * stars)
                    glow += refund
                    earned += refund
                pets[:] = pets[:cap_n]
                for tier_, _ in pets:
                    if tier_ not in first:
                        first[tier_] = (day + 1, t_play)
                # rebirth
                if earned >= rebirth_req(stars):
                    stars += 1
                    first.setdefault(f"rebirth{stars}", (day + 1, t_play))
                    if rb["keepVault"]:
                        keep = pets[: vault_cfg["start"] + vault_cfg["perStar"] * stars]
                    else:
                        keep = pets[:1]
                    pets[:] = keep
                    glow, earned, lan, slots = 0, 0, 0, slot_cfg["start"]
        log.append(dict(day=day + 1, stars=stars, income=income(), best=max(t for t, _ in pets)))
    return first, first_src, log


def summarize(runs, days):
    res = {}
    for key in [2, 3, 4, 5, 6, "rebirth1", "rebirth5", "rebirth10", "rebirth12"]:
        label = RAR[key] if isinstance(key, int) else key
        got = [f[key] for f, _, _ in runs if key in f]
        res[label] = dict(
            pct=round(100 * len(got) / len(runs)),
            median_day=float(np.median([g[0] for g in got])) if got else None,
            median_play_min=float(np.median([g[1] for g in got])) if got else None,
        )
    srcs = [s.get(LEG) for _, s, _ in runs if LEG in s]
    res["first_legendary_source"] = {k: round(100 * srcs.count(k) / max(1, len(srcs))) for k in ("night", "lure", "steal")}
    for d in (7, 14, 30, 45, 60):
        if d <= days:
            res[f"stars_d{d}"] = float(np.median([l[d - 1]["stars"] for _, _, l in runs]))
            res[f"income_d{d}"] = float(np.median([l[d - 1]["income"] for _, _, l in runs]))
    return res


def run_scenario(pool, name, days, seeds):
    cfg = load_cfg(SCENARIOS[name][1])
    out = {}
    for prof_name, prof in PROFILES.items():
        runs = pool.map(simulate, [(cfg, prof, days, s, True) for s in range(seeds)])
        out[prof_name] = summarize(runs, days)
    a = pool.map(simulate, [(cfg, PROFILES["engaged"], 30, s, True) for s in range(seeds)])
    b = pool.map(simulate, [(cfg, PROFILES["engaged"], 30, s, False) for s in range(seeds)])
    out["theft_income_ratio_engaged_d30"] = float(
        np.median([l[-1]["income"] for _, _, l in a]) / np.median([l[-1]["income"] for _, _, l in b]))
    return out


def print_table(results, days):
    cols = ["Legendary", "Mythic", "Secret", "rebirth5"]
    print(f"\n{'scenario':12s} {'profile':9s} " + " ".join(f"{c:>18s}" for c in cols)
          + f" {'stars d30':>9s} {'1st Leg src n/l/s':>18s}")
    for name, res in results.items():
        for prof in PROFILES:
            r = res[prof]
            cells = []
            for c in cols:
                d = r[c]
                cells.append(f"{d['pct']:3d}% d{d['median_day'] if d['median_day'] is not None else '-':>5}")
            src = r["first_legendary_source"]
            print(f"{name:12s} {prof:9s} " + " ".join(f"{c:>18s}" for c in cells)
                  + f" {r.get('stars_d30', float('nan')):9.0f} {src['night']:>6d}/{src['lure']}/{src['steal']}")
        print(f"{'':12s} theft income ratio (engaged d30): {res['theft_income_ratio_engaged_d30']:.3f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--seeds", type=int, default=200)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--out", default=os.path.join(HERE, "results_v3.json"))
    args = ap.parse_args()
    if args.list:
        for k, (desc, _) in SCENARIOS.items():
            print(f"{k:12s} {desc}")
        return
    names = args.scenarios or list(SCENARIOS)
    results = {}
    with Pool() as pool:
        for name in names:
            results[name] = run_scenario(pool, name, args.days, args.seeds)
            print(f"done: {name}", flush=True)
    print_table(results, args.days)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"days": args.days, "seeds": args.seeds, "assumptions": ASSUME, "results": results}, f, indent=1)


if __name__ == "__main__":
    main()

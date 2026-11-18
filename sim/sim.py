"""Economy simulation for 'Glowkeepers' — progression pacing over 30 days.
Time step: 1 cycle = 6 min (4 min Day + 2 min Night). Sessions are rounded to cycles."""
import numpy as np, json, sys

RAR = ['Common','Uncommon','Rare','Epic','Legendary','Mythic','Secret']
ODDS = np.array([1/2, 1/5, 1/20, 1/100, 1/1000, 1/10000, 1/100000])   # base "1 in N" per rarity
BASE = np.array([1, 4, 20, 120, 1000, 10000, 150000], float)          # Glow/sec per glowling
MUT = [(1/20, 2.0), (1/200, 5.0)]                                       # Golden x2, Rainbow x5

P = dict(
    start_slots=8, slot_c0=250, slot_g=1.9, max_slots=30,
    lan_c0=150, lan_g=1.55, lan_luck=0.12,          # luck +12%/lantern level
    lure_c0=40, lure_g=14,                           # Lure tier t costs 40*14^t, guarantees >= rarity t
    night_catches=3,
    reb_c0=2.5e5, reb_g=3.2,                           # rebirth k needs 2.5e5*6^k total Glow earned since last rebirth
    star_income=0.35, star_luck=0.06,
    offline_rate=0.10, offline_cap_h=6,
    theft_per_day_phase=0.06, vault_slots=3,         # chance per day-phase a display glowling is stolen from you
)

def roll(rng, luck, floor_t=0):
    # roll from rarest to commonest; luck multiplies odds of Rare+ (capped at 1)
    p = ODDS.copy(); p[2:] = np.minimum(p[2:]*luck, 0.5)
    for t in range(6, floor_t-1, -1):
        if t == floor_t or rng.random() < p[t]:
            m = 1.0
            r = rng.random()
            if r < MUT[1][0]: m = MUT[1][1]
            elif r < MUT[0][0]: m = MUT[0][1]
            size = rng.uniform(0.8, 1.3)
            return t, BASE[t]*m*size
    return floor_t, BASE[floor_t]

def simulate(profile, days=30, seed=0, theft=True):
    rng = np.random.default_rng(seed)
    sess_per_day, minutes = profile
    glow = 0.0; pets = []  # list of (tier, value)
    slots = P['start_slots']; lan = 0; stars = 0; earned = 0.0
    first = {}; log = []
    t_play = 0.0
    def income():
        best = sorted(pets, key=lambda x: -x[1])[:slots]
        return sum(v for _, v in best) * (1 + P['star_income']*stars)
    def luck(): return (1 + P['lan_luck']*lan) * (1 + P['star_luck']*stars)
    # tutorial: free guaranteed Uncommon lure
    pets.append(roll(rng, 1, 1))
    for day in range(days):
        # offline earnings between days (assume 16h away, capped)
        if day > 0:
            off = income()*P['offline_rate']*min(16, P['offline_cap_h'])*3600
            glow += off; earned += off
        cycles = max(1, round(minutes/6))
        for s in range(sess_per_day):
            for c in range(cycles):
                t_play += 6
                # DAY phase (240 s): earn, spend, theft risk
                inc = income()*240; glow += inc; earned += inc
                if theft and len(pets) > P['vault_slots'] + stars and rng.random() < P['theft_per_day_phase']:
                    cand = sorted(pets, key=lambda x: -x[1])[P['vault_slots']+stars:slots]
                    if cand: pets.remove(cand[rng.integers(len(cand))])
                if theft and rng.random() < P['theft_per_day_phase']:   # you steal one back from someone similar
                    pets.append(roll(rng, luck()))
                # spend greedily
                while True:
                    lan_c = P['lan_c0']*P['lan_g']**lan
                    slot_c = P['slot_c0']*P['slot_g']**(slots-P['start_slots'])
                    full = len(pets) >= slots
                    weakest = min(v for _, v in sorted(pets, key=lambda x:-x[1])[:slots]) if full else 0
                    # best lure tier affordable
                    tier = int(np.floor(np.log(max(glow,1)/P['lure_c0'])/np.log(P['lure_g']))) if glow >= P['lure_c0'] else -1
                    tier = min(tier, 3)   # lures cap at Epic: Legendary+ only from Night/steals/events
                    opts = []
                    if glow >= lan_c and lan_c < 0.6*glow: opts.append(('lan', lan_c))
                    if full and slots < P['max_slots'] and glow >= slot_c: opts.append(('slot', slot_c))
                    if tier >= 0 and (not full or BASE[tier] > weakest): opts.append(('lure', P['lure_c0']*P['lure_g']**tier))
                    if not opts: break
                    k, cst = min(opts, key=lambda x: x[1])
                    glow -= cst
                    if k == 'lan': lan += 1
                    elif k == 'slot': slots += 1
                    else: pets.append(roll(rng, luck(), tier))
                # NIGHT phase (120 s): co-op catches, earn at full rate
                inc = income()*120; glow += inc; earned += inc
                for _ in range(P['night_catches']):
                    pets.append(roll(rng, luck()))
                # trim inventory to 3x slots (sell extras for small Glow)
                pets.sort(key=lambda x: -x[1]); pets[:] = pets[:slots*3]
                for tier_, _ in pets:
                    if tier_ not in first: first[tier_] = (day+1, t_play)
                # rebirth
                if earned >= P['reb_c0']*P['reb_g']**stars:
                    stars += 1; first.setdefault(f'rebirth{stars}', (day+1, t_play))
                    best = pets[0]; pets[:] = [best]; glow = 0; earned = 0; lan = 0; slots = P['start_slots']
        log.append(dict(day=day+1, hours=round(t_play/60,1), stars=stars, income=income(), best=RAR[max(t for t,_ in pets)]))
    return first, log

PROFILES = {'casual (3x8 min/day)': (3, 8), 'engaged (4x20 min/day)': (4, 20), 'hardcore (6x45 min/day)': (6, 45)}

if __name__ == '__main__':
    out = {}
    for name, prof in PROFILES.items():
        firsts = []
        logs = []
        for seed in range(200):
            f, l = simulate(prof, seed=seed); firsts.append(f); logs.append(l)
        res = {}
        for key in [2,3,4,5,6,'rebirth1','rebirth3','rebirth5']:
            label = RAR[key] if isinstance(key,int) else key
            got = [f[key] for f in firsts if key in f]
            res[label] = dict(pct_by_d30=round(100*len(got)/len(firsts)),
                              median_day=float(np.median([g[0] for g in got])) if got else None,
                              median_play_min=float(np.median([g[1] for g in got])) if got else None)
        d30 = [l[-1] for l in logs]
        res['d30_median_stars'] = float(np.median([x['stars'] for x in d30]))
        res['d30_median_income'] = float(np.median([x['income'] for x in d30]))
        res['income_curve'] = [float(np.median([l[d]['income'] for l in logs])) for d in [0,1,2,6,13,29]]
        out[name] = res
    # theft impact (engaged)
    a = [simulate(PROFILES['engaged (4x20 min/day)'], seed=s, theft=True)[1][-1]['income'] for s in range(200)]
    b = [simulate(PROFILES['engaged (4x20 min/day)'], seed=s, theft=False)[1][-1]['income'] for s in range(200)]
    out['theft_income_ratio_engaged_d30'] = float(np.median(a)/np.median(b))
    print(json.dumps(out, indent=1))
    json.dump(out, open('sim_results.json','w'), indent=1)

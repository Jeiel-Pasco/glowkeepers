# Layer One — plan and status

The single source of truth for the "first outer layer" rework. Work it **one step at a time**:
one step per branch and PR, playtest before moving on, and update the status here in the same PR.

Status keys: **DONE** (merged), **WIP** (in progress), **TODO**, **UNSURE** (needs a decision or a playtest).

## What the user asked for (playtest feedback after PR #54)

1. No plain flat fields beside the zones: forest everywhere, with consistent ground tiling.
2. The wild forest is thicker and harder to walk through, but **must not block the camera**: taller trees, canopies above the view.
3. Random **raider camps**: guards kill you if you walk in; they drop XP and coins; the camp chest has a low chance of random-type ink.
4. Zones are **big circles**, not strips, and do not open straight onto the camp: you cross forest to reach them.
5. A bigger map. This first outer layer comes now. A future second layer will be twice as big, with new enemy types for grimoire binding.
6. **Distinct abilities per element**: Fire, Water and Leaf enemies and bosses currently share the same skills.
7. Each outer layer sits **higher** than the one before. You reach it with a little parkour beside a natural steep wall: hard, but not very hard.
8. Future layers add three new elements, and the previous layer's elements come back enhanced. **Not now.**

## Where things are now (main after #54)

- The camp is a clearing r<150 with 8 plots at r≈75 and a ring wall at r260, which has gates at 0°/120°/240°.
- The three zones are strips from the gate (d 262) to the boss (d 610) in `src/shared/Zones.luau`. The world edge is at r700.
- The ground outside the camp is flat Grass at y=-1. The camp forest is thinned. There is a tree wall at r715–765.
- Map builder: `tools/BuildZones.luau`, run in Studio Edit (see "Running the builder").
- Every boss uses the same three attacks (`EnemyService.bossAttack`: slam ring, 5-bolt volley, eruptions). Minions all use melee, and casters all fire the same bolt.
- Place settings: `CharacterMaxSlopeAngle` 89 (cliffs can be walked up), JumpHeight 7.2, StreamingEnabled on.

## Target layout (UNSURE until step 1 is playtested)

```
r 0–150      camp clearing (unchanged)
r 150–260    camp forest ring + ring wall (unchanged)
r 260–510    LOWLAND: dense tall forest at ground level, raider camps, roaming raiders
r ~520       CLIFF up to the plateau (~60 studs high), natural and noisy,
             ~6 parkour routes of rock ledges (~5 studs apart, ±20° of each zone's angle)
r 520–1150   PLATEAU: forest + three CIRCLE zones (radius ~180, centre r~820, at 0/120/240°)
r ~1150      sheer outer cliff + invisible wall (future layer 2; unclimbable for now)
```

- Ground: one Grass material everywhere outside the camp. Zone materials are used only inside each zone circle.
- Zone packs sit in rings inside each circle: outer L2–5, middle L6–9, inner L10–11, boss at the centre L12.
- Lower `CharacterMaxSlopeAngle` to about 50 so cliffs can only be climbed by the ledges.

## Steps

| # | Step | Status |
|---|------|--------|
| 1 | Zones v3 geometry in `Zones.luau`: radii, cliff, ledges, circle zones, pack rings, raider camp candidate sites. Update `tests/balance.spec.luau` limits. | TODO |
| 2 | Builder v2 (`tools/BuildZones.luau` rewrite): heightmap by WriteVoxels in chunks (camp r<255 preserved), noisy cliffs, parkour ledges, single ground tiling, tall forest from `WorldAssets.Forest` (jitter grid, clearings for zones, camps and routes), remove the old r700 edge, tree wall and `Map.Zones`. Run it async with a progress attribute. | TODO |
| 3 | Fix-ups for the new map: `EnemyService.groundAt` raycast start height, HUD guide hints and quest guide positions, spawn heights on the plateau. | TODO |
| 4 | Raider camps: 3 random sites from ~8 candidates, built at runtime (palisade, tents, fire, chest). New guards `raider_brute` (melee) and `raider_archer` (bolt) that attack anyone inside and drop XP and coins. The chest stays locked while guards live; on clear it has a low chance of random-type ink (otherwise coins) into carried, once per player per clear. Guards respawn after ~90 s. | TODO |
| 5 | Player status effects: slow/root via character attributes that `MovementController` respects; knockback/pull via an Fx applied by the owning client (LinearVelocity); poison reuses `burnPlayer`; a new "line" telegraph Fx. | TODO |
| 6 | Distinct element abilities (uses step 5). **Fire:** imp hits burn, caster fireball burns, Golem keeps slam/volley/eruption. **Water:** crab knockback (tanky), Mist Caller bolt slows, Tide Warden does a tidal-wave line (knockback), a whirlpool (pull + slow) and a bubble volley. **Leaf:** sprout lunge + poison, Spore Puff spore cloud (telegraphed poison), Elder Treant does root-snare circles, a thorn line, and summons sprouts + heals. Rebalance in the spec. | TODO |
| 7 | Playtest pass in DEV, tune numbers, save the place, and close this doc's open questions. | TODO |
| — | Layer 2 (twice as big, higher, three new elements + enhanced old ones, binding enemies) | FUTURE, not now |

## Open questions (UNSURE)

- Cliff height (~60) and ledge spacing: what does "a little parkour" feel like? Tune in step 7.
- Tree count (~4–5k) against performance with StreamingEnabled. The forest may need to be thinner far from paths.
- How often raider-camp ink drops ("low chance"; start ~10%?), and whether guards scale with distance.
- Whether camps should also re-roll positions per server, or stay fixed per server.
- How long the walk takes from camp to a zone after the map grows. The tutorial trail and quest guide may need a shorter route.

## Running the builder

Copy the tool to `src/server/_tmp/` (Rojo syncs it). Then in Studio **Edit**, run
`loadstring(game.ServerScriptService.Server._tmp.BuildZones.Source)()`. Delete `_tmp` afterwards and save the place.
Stop any playtest first.

## Checks (every step)

`stylua --check src tests tools`, `selene src tools`, `lune run tests/<each>.spec.luau`,
`rojo build -o $TEMP/gk.rbxl`. Tools live in `$USERPROFILE/.rokit/bin`.

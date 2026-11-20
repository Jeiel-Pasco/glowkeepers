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
             a smooth ramp cut diagonally across it toward each zone (was parkour ledges; changed in 2b)
r 520–1150   PLATEAU: forest + three CIRCLE zones (radius ~180, centre r~820, at 0/120/240°)
r ~1150      sheer outer cliff + invisible wall (future layer 2; unclimbable for now)
```

- Ground: one Grass material everywhere outside the camp. Zone materials are used only inside each zone circle.
- Zone packs sit in rings inside each circle: outer L2–5, middle L6–9, inner L10–11, boss at the centre L12.
- `CharacterMaxSlopeAngle` is 50, so the cliffs can only be climbed by the ramps.

## Steps

| # | Step | Status |
|---|------|--------|
| 1 | Zones v3 geometry in `Zones.luau`: radii, cliff, ledges, circle zones, pack rings, raider camp candidate sites. Update `tests/balance.spec.luau` limits. | DONE |
| 2 | Builder v2 (`tools/BuildZones.luau` rewrite): heightmap by WriteVoxels in chunks (camp r<255 preserved), noisy cliffs, parkour ledges, single ground tiling, tall forest from `WorldAssets.Forest` (jitter grid, clearings for zones, camps and routes), remove the old r700 edge, tree wall and `Map.Zones`. Run it async with a progress attribute. | DONE |
| 3 | Fix-ups for the new map: `EnemyService.groundAt` raycast start height, HUD guide hints and quest guide positions, spawn heights on the plateau. | DONE |
| 2b | Playtest rework: ramps replace the ledges, lantern trails to the zones, a mixed and thinner forest with floor decor all through it, mushrooms and lanterns glow at night, camp floor decor removed. | DONE |
| 4 | Raider camps: 3 random sites from ~8 candidates, built at runtime (palisade, tents, fire, chest). New guards `raider_brute` (melee) and `raider_archer` (bolt) that attack anyone inside and drop XP and coins. The chest stays locked while guards live; on clear it has a low chance of random-type ink (otherwise coins) into carried, once per player per clear. Guards respawn after ~90 s. | TODO |
| 5 | Player status effects: slow/root via character attributes that `MovementController` respects; knockback/pull via an Fx applied by the owning client (LinearVelocity); poison reuses `burnPlayer`; a new "line" telegraph Fx. | TODO |
| 6 | Distinct element abilities (uses step 5). **Fire:** imp hits burn, caster fireball burns, Golem keeps slam/volley/eruption. **Water:** crab knockback (tanky), Mist Caller bolt slows, Tide Warden does a tidal-wave line (knockback), a whirlpool (pull + slow) and a bubble volley. **Leaf:** sprout lunge + poison, Spore Puff spore cloud (telegraphed poison), Elder Treant does root-snare circles, a thorn line, and summons sprouts + heals. Rebalance in the spec. | TODO |
| 7 | Playtest pass in DEV, tune numbers, save the place, and close this doc's open questions. | TODO |
| — | Layer 2 (twice as big, higher, three new elements + enhanced old ones, binding enemies) | FUTURE, not now |

### Step 1 notes (Zones v3)

- Numbers are in `src/shared/Zones.luau`: lowland r260–510 at y=-1; cliff r510–530, 60 tall (plateau y=59);
  plateau out to `WORLD_R` 1150; zone circles radius 180 centred at r820; packs on rings 145 (L2–5),
  100 (L6–9), 45 (L10–11), with the boss at the centre; 9 raider camp candidate sites (radius 30) at
  r330/380/440; roaming raiders at r470.
- New API: `groundY(r)`, `polar(angle, r)`, `routes()` (6 ledge staircases, 11 ledges each, given as
  top-face centres), and `campSites()`. `toWorld` now returns the ground height. `PACKS` keep `d`/`s`,
  worked out from `ring`/`a`.
- `Zones.PATH` (the old strip floor) is gone. The old `tools/BuildZones.luau` no longer runs, and step 2
  rewrites it.
- **Until step 2 is built in DEV**, zone spawns sit past the old r700 wall on flat ground. The game is
  not playable between the step 1 and step 2 merges.
- The HUD "zone" hint still points at `toWorld(zone, 320, 0)`, which is now in the lowland toward the
  zone. Step 3 should point it at the nearest ledge route.

### Step 2 notes (builder v2)

- The builder ran in DEV and the place was saved (version 116). Output: `Map.Layer` with `Forest` (4,438 trees),
  `Ledges` (66), `Edge` (96 invisible wall segments at r1150) and `Zones` (decor). `Map.Zones` and `Map.WorldEdge`
  are gone, along with every tree and prop outside r255. `CharacterMaxSlopeAngle` is now 50.
- Trees are `Tree_Oak_Tall` (×3.2–4.2) and `Tree_Oak_Round` (×1.4–1.9). Canopies start about 28 studs up and
  have CanCollide, CanQuery and CanTouch off, so they never pop the camera. Trunks collide.
- The heightmap is notched under each ledge, because smoothed voxels otherwise bulge over the ledge tops.
- Playtest check: a scripted climb of one route landed on all 11 ledges and reached the top. Walking
  straight up the bare cliff fails (slope 50).
- Zone decor is the old set, moved into the circles. Mistfall pools sit between the pack rings.
- `EnemyService.groundAt` still starts its ray at y=120, which is enough for the plateau (about 60). Step 3 still
  needs to check spawns on the plateau.

### Step 3 notes (fix-ups)

- `EnemyService.groundAt` now starts its ray 80 studs above the higher of the point and `Zones.groundY`, and
  casts down past the lowland floor. An enemy in the "home" state that is more than 15 studs above or below its
  home (it fell off the cliff) is put back home.
- New `Zones.entry(zone)` gives the zone hint target, just inside each circle on the side facing camp.
  New `Zones.guide(from, target)` gives the quest beam's next waypoint: out through the nearest camp gate,
  then the first ledge of the closest route, then the next ledge up, then the target. Coming back from
  the lowland, it leads in through the nearest gate. Both are covered in `balance.spec`.
- Playtest in DEV: all 39 zone enemies spawned on the plateau (y 55–80) and stayed there. The beam
  pointed to the gate from camp, to ledge 1 from the lowland, and to the zone entry from the plateau.

### Step 2b notes (playtest rework)

- After step 3, the user asked for changes: a smooth ramp instead of parkour, a not-too-obvious lantern path
  to each zone, fewer and more varied trees, floor decor through the forest and none on the camp floor, and
  mushrooms that glow at night.
- `Zones`: `rampAt(zone, t)` and `rampFrame` describe one ramp per zone, cut diagonally across the cliff face
  (18° of arc, 12 wide, about 20° steep). `trail(zone)` gives the lantern trail points from the gate to the
  zone entry. `routes()` and the ledge constants are gone. The guide now follows the trail and the ramp.
- Builder: the ramp is a dirt shelf in the heightmap, and the trail is faint, broken dirt with 44 lanterns.
  There are 2,701 trees: oak, round oak, two pines, part-built birches and dead snags, in 7 muted leaf
  colours. There are 5,434 props in small clusters (bushes, rocks, logs, stumps, mushrooms). The camp's
  props, wood piles and flowers are gone (the fireflies stay).
- Night glow: parts tagged `NightGlow` (lanterns, about half the forest mushrooms) turn Neon from dusk to
  dawn and switch on their lights. This is handled by `CycleFXController`, and there are 304 lights in total.
- Playtest: walking up all 3 ramps reached the plateau without getting stuck. At night, the streamed-in
  glow parts were Neon with their lights on. DEV place saved (version 119).
- The step 2 and step 3 notes above about ledges are now out of date.

## Open questions (UNSURE)

- Night is very dark away from the trails. Should more of the forest glow?

- Output shows `rbxassetid://203785492 … Asset type does not match` three times at play start. I didn't
  check whether this is new; look in step 7.

- Trunks are thick (Oak_Tall scaled ×4 is about 17 wide). Is the forest too hard to walk through, or about right?
- The forest has about 16.5k instances. Check client FPS and streaming on a low-end device in step 7.

- Is the walk from camp to a zone too long now? It is about 260 studs of lowland, the climb, then about 110 studs of plateau forest before the circle edge.
- Which 3 of the 9 camp sites are used: one per gap between zones, or any 3?

- Tree count (~4–5k) against performance with StreamingEnabled. The forest may need to be thinner far from paths.
- How often raider-camp ink drops ("low chance"; start ~10%?), and whether guards scale with distance.
- Whether camps should also re-roll positions per server, or stay fixed per server.
- How long the walk takes from camp to a zone after the map grows. The tutorial trail and quest guide may need a shorter route.

## Running the builder

Copy the tool to `src/server/_tmp/` (Rojo syncs it). Then in Studio **Edit**, run
`task.spawn(loadstring(game.ServerScriptService.Server._tmp.BuildZones.Source))` (watch workspace's `BuildProgress` attribute until `done`). Delete `_tmp` afterwards and save the place.
Stop any playtest first.

## Checks (every step)

`stylua --check src tests tools`, `selene src tools`, `lune run tests/<each>.spec.luau`,
`rojo build -o $TEMP/gk.rbxl`. Tools live in `$USERPROFILE/.rokit/bin`.

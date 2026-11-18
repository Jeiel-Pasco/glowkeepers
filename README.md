# Glowkeepers

A Roblox game: collect Glowlings by day and steal them from other players' bases, then keep the campfire alive together at night.

| Doc | What it covers |
| --- | --- |
| [docs/GDD.md](docs/GDD.md) | The original design |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | Scope, decisions, schedule and phases |
| [docs/GAME_SYSTEMS.md](docs/GAME_SYSTEMS.md) | Rules and numbers for each system |
| [docs/TECH_SPEC.md](docs/TECH_SPEC.md) | Architecture, data, remotes and security |
| [docs/CONTENT_AND_LIVEOPS.md](docs/CONTENT_AND_LIVEOPS.md) | Map, species, retention and live ops |
| [sim/README.md](sim/README.md) | The economy sim and its results |

## Setup (once)

1. Install [Rokit](https://github.com/rojo-rbx/rokit). Then, in this folder, run this to get the pinned rojo, lune, selene and stylua:

   ```powershell
   rokit install
   ```

2. Copy ProfileStore into `src/server/Vendor/ProfileStore.luau` (see [the Vendor README](src/server/Vendor/README.md)). Without it, DEV runs on an in-memory store that saves nothing.
3. Install the Rojo plugin in Studio:

   ```powershell
   rojo plugin install
   ```

4. Put the game ids (universe ids) of the DEV, BETA and PROD experiences in `config/environments.json`. An unknown id runs as DEV.

## Working

```powershell
rojo serve
```

In Studio, open the Rojo plugin and connect. Code and `config/*.json` sync live. The map, UI templates and models stay in the Team Create place.

- **Skip to the next phase** (DEV and BETA only): in Studio's server view, set the Workspace attribute `DebugSkipPhase` to true.
- **New remote:** declare it in `src/shared/Net/init.luau` first, with its argument schema and rate limit.
- **New service or controller:** add it to `ORDER` in `src/server/Main.server.luau` or `src/client/Main.client.luau`.
- **HUD:** a `StarterGui.HUD` made in Studio replaces the placeholder. Set ResetOnSpawn off, and keep the element names listed at the top of `HUDController.luau`.

## Checks

Run these from the repo root. CI runs the same ones.

Run every Lune spec. Each prints a summary line and exits 1 on failure:

```powershell
Get-ChildItem tests -Filter *.spec.luau | ForEach-Object { lune run $_.FullName }
```

Run one spec:

```powershell
lune run tests/roll.spec.luau
```

After any change to `config/economy.json`, regenerate the golden values that the specs compare against:

```powershell
python sim/golden_odds.py
```

Format, then lint:

```powershell
stylua src tests
```

```powershell
selene src
```

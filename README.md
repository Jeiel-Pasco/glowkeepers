# Glowkeepers

A Roblox real-time Grimoire Action RPG: venture out from the Wizard Camp Courtyard into the wild forest and elemental valleys, fight creatures and bosses, counter elements with 4-page spellbooks, and carry your loot home to bank it before raiders take it.

| Doc | What it covers |
| --- | --- |
| [docs/GDD.md](docs/GDD.md) | Grimoire Action RPG design (v2) |
| [docs/LAYER_ONE.md](docs/LAYER_ONE.md) | Layer One world layout, unified builder and combat status |
| [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md) | Low-poly forest palette and prop rules |
| [docs/TECH_SPEC.md](docs/TECH_SPEC.md) | Architecture, data, remotes and security |

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

4. `config/environments.json` holds the DEV, BETA and PROD ids. An unknown id runs as DEV.

## Working

```powershell
rojo serve
```

In Studio, open the Rojo plugin and connect. Code and `config/*.json` sync live.

- **Build or rebuild the world map (`r = 0..650`):** copy `tools/BuildZones.luau` to `src/server/_tmp/BuildZones.luau`, then in Studio Edit mode's command bar run:
  ```luau
  task.spawn(loadstring(game.ServerScriptService.Server._tmp.BuildZones.Source))
  ```
  Watch Workspace's `BuildProgress` attribute until `done`, delete `src/server/_tmp`, and save the place.
- **Test a Grimoire in Studio:** in a Clients and Servers test, set a test player's `DebugGrimoire` attribute (server side) to a type such as `Frost`. They get that Grimoire with all four pages, in hand. It only works in Studio, for local test players.
- **PvP:** War Mode (switched in camp) and the Duel Arena Ring south of camp. Rules are in [docs/LAYER_ONE.md](docs/LAYER_ONE.md#combat--pvp).
- **New remote:** declare it in `src/shared/Net/init.luau` first, with its argument schema and rate limit.
- **New service or controller:** add it to `ORDER` in `src/server/Main.server.luau` or `src/client/Main.client.luau`.

## Checks

Run every Lune spec:

```powershell
Get-ChildItem tests -Filter *.spec.luau | ForEach-Object { lune run $_.FullName }
```

Format, then lint:

```powershell
stylua src tests tools
selene src tools
```

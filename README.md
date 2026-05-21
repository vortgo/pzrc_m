# PZRC Mod

Standalone server-side toolkit for Project Zomboid Build 42 Multiplayer. Bundles
welcome note + walkie-talkie, dynamic radio with event broadcasts, six event
types, library bookshelf restocking, infinite generators, fuel-pump refill,
starter-kit crate, and a daily-ration fridge — all in one Workshop mod, no
manual file drops to `~/Zomboid/Lua/`.

## Install

1. Subscribe in Steam Workshop, or clone this repo into `~/Zomboid/mods/pzrc_m/`.
2. Add `pzrc_m` to your server's `Mods=` in `~/Zomboid/Server/<servername>.ini`.
3. Restart the server.

## Configuration

All settings are Sandbox-backed (page **PZRC**). Defaults work out of the box
for Muldraugh. Key knobs:

| Option | Default | Meaning |
|---|---|---|
| `BaseX` / `BaseY` | 9492 / 11190 | Safe-zone coordinates for the note and radio |
| `RadioFrequencyKHz` | 95200 | Channel frequency (kHz). 100100 is recommended to avoid vanilla overlap. |
| `EventAutoSpawnIntervalMinutes` | 5 | Real-time minutes between auto-spawns |
| `EventTTLHours` | 0.05 (~3 min) | TTL before an unvisited event despawns |
| `LibraryRestockIntervalMinutes` | 5 | Library restock tick interval |
| `StarterKitCooldownHours` | 24 | Hours between starter-kit claims per SteamID |
| `FridgeRespawnIntervalGameDays` | 1 | In-game days between fridge rations per character |
| `FuelPumpMaxCapacity` | 14000 | Max fuel per pump refill |

## Admin commands

```
/event spawn <type> [x y]   — force-spawn (types: buildingstash, foreststash,
                              abandonedvehicle, airdrop, camp, helicoptercrash)
/event list                  — list active events
/event remove <id>           — remove by id
/event types                 — registered types
/radio <freq> <text>         — broadcast on any dynamic channel
/resetkit <username>         — reset starter-kit cooldown
/resetfridge <username>      — reset fridge cooldown
```

## Right-click menus

- Generator → **PZRC M → Make Infinite / Make Normal** (admin)
- Fuel pump → **Fuel: Refill / Drain** (admin)
- Bookshelf → **PZRC M → Library → Mark / Unmark** (admin)
- On the ground → **PZRC M → StarterKit → Place / Rotate** (admin) → players see "Claim Starter Kit" on the crate
- On the ground → **PZRC M → Fridge → Place / Rotate** (admin) → players see "Take Daily Ration"

## Compatibility

This mod ships its own `planb.pack` and `planb.tiles` (sprites for the starter
crate and ration fridge) plus the `szcrate.pack`. These names are inherited
from the legacy SafeZone mod and **collide with it** — do not install both at
once. Vehicle scripts live under a unique `PZRCVehicles` namespace and won't
clash with other mods.

## Subsystem map

| System | Server Lua | Client Lua |
|---|---|---|
| Note + walkie | `server/Note/PZRC_Note.lua` | `client/Note/PZRC_NoteClient.lua` |
| Radio | `server/Radio/PZRC_Radio.lua` | — |
| Events | `server/Events/PZRC_Event*.lua` | `client/Events/PZRC_EventCommandsClient.lua` |
| Library | `server/Library/PZRC_Library.lua` | `client/Library/PZRC_LibraryMenu.lua` |
| Infinite generator | `server/InfiniteGen/PZRC_InfiniteGen.lua` | `client/InfiniteGen/PZRC_InfiniteGenClient.lua` |
| Fuel pump | `server/FuelPump/PZRC_FuelPump.lua` | `client/FuelPump/PZRC_FuelPumpMenu.lua` |
| Starter kit | `server/StarterKit/PZRC_StarterKit*.lua` | `client/StarterKit/PZRC_StarterKitClient.lua` |
| Fridge | `server/Fridge/PZRC_Fridge*.lua` | `client/Fridge/PZRC_FridgeClient.lua` |
| Safe-zone marker | — | `client/SafeZoneMarker/PZRC_SafeZoneMarker.lua` |
| Shared utils | `shared/PZRC_Config.lua`, `shared/PZRC_Utils.lua`, `server/PZRC_Claimable.lua`, `client/PZRC_ContextMenu.lua` | |

## Assets

- `media/radio_messages.txt`, `media/event_messages.txt` — broadcast text shipped inside the mod and read via `getModFileReader`.
- `media/scripts/pzrc_vehicles.txt`, `pzrc_models.txt` — vehicle/model templates for airdrops, helicopter crashes, and the FEMA / Survivor supply drop containers.
- `media/models_X/vehicles/`, `models_X/WorldItems/` — FBX meshes for the above.
- `media/textures/Vehicles/`, `textures/WorldItems/`, `textures/highlights/` — diffuse and mask textures.
- `media/texturepacks/planb.pack`, `szcrate.pack` — sprite packs for the crate, fridge, and base tiles.
- `media/planb.tiles` (+ `tiledefinitions.tiles`) — tile definitions registering the planb sprites.

## License

(Pick one before publishing — MIT / CC-BY / All Rights Reserved.)

# The Midnight Express: Boiler & Bistro

First-person co-op physics management on a ramshackle steam train. Godot 4.7.2, GDScript,
Jolt physics, Mobile renderer. Models are built in Blender from `blender/build_*.py` (see `docs/ART_BRIEF.md`).

**Status: Milestone 1 (The Physics Boxcar & Yeet Prototype).** Milestones 2-4 are not started.

## Run it

- Double-click `Jouer.bat`, or open the folder in the Godot 4.7.2 editor and press F5.
- `build/MidnightExpress.exe` and `build/MidnightExpress.apk` (debug, arm64) are exports of
  this version. Rebuild with `godot --headless --path . --export-debug "Android" build/MidnightExpress.apk`.
- Try the touch overlay on PC with the mouse acting as one finger:
  `godot --path . -- --touch`

## Controls

| Action | PC (physical keys, so ZQSD on AZERTY) | Mobile |
| --- | --- | --- |
| Move | WASD | Left side: floating stick |
| Sprint | Shift | Push the stick past its ring |
| Look | Mouse | Right side: drag |
| Jump | Space | JUMP |
| Grab / open / drop | E | GRAB |
| Throw (hold, release) | Right mouse or A on AZERTY / Q on QWERTY | THROW |
| Bonk | Left mouse or F | BONK |
| Clipboard | Tab | CLIP |
| Free the mouse | Esc | |

The clipboard currently holds the test bench: train speed (0 / 50 / 100 / 150 km/h), reset
cargo and dummies, and "Back on the train".

## The test loop

1. Grab the wrench from the table on your left (or the pan on your right).
2. Bonk the dummy ahead: one hit with a tool, three with fists. A thrown wrench works too.
3. Press grab on the body, carry it to a door or window, press grab on it to open it. Only
   the doors and the windows at -4.0 and 4.5 open; the rest are rusted shut.
4. Hold throw, release. The speed counter's "yeeted" goes up.
5. Open a side door and walk out to try the rescue rope. Steer to the orange rope, press
   grab. Miss it and you land back on the train.
6. The best view of a tumble is the rear platform: go to the back of the Coach, open the door.

## Tuning

- `scripts/core/yeet_tuning.gd`: everything about how the Exterior Yeet Zone feels.
- `scripts/player/hands.gd`: hold, throw and bonk strength.
- `scripts/player/player.gd`: movement and the rescue rope drag.
- `scripts/props/prop_catalog.gd`: add a prop by adding one entry.
- `scripts/train/train.gd`: car specs, door and window positions, which windows work.
- `scripts/game/round_director.gd`: clock, stowaway count, score, ranks.

`SNATCH_FRACTION` is 0.55, not the spec's literal full speed, on purpose. A body given
exactly the ground's speed is at rest relative to the ground and lands with no tumble and
no impact. The remaining speed reaches it through the slipstream and the snow.

## How the hybrid velocity zone works

- The train never moves (`scripts/train/train.gd`). `TrainState` holds speed and distance.
- The ground is a static body with `constant_linear_velocity`, a conveyor belt.
- Obstacles are pooled kinematic chunks placed from `distance_m`, each one body holding many
  collision shapes (`scripts/world/scenery_chunk.gd`).
- `ExteriorZone` is a trigger shell around the hull. Touching it makes a body a candidate; it
  counts as gone when its anchor leaves the hull, so a dangling arm gets tugged by the wind
  instead of launching the passenger. Then it loses collision with the train and gets the
  snatch velocity, wind, and hops.

## Room left for Milestone 4 multiplayer

No networking exists yet. These choices are there so it needs no rewrite:

- `Player` and `Hands` run only from `PlayerCommand`, one per tick, from a
  `PlayerInputSource`. `LocalInput` reads devices; the tests already swap in a scripted source
  and a network source will fit the same slot, so the host can simulate every player.
- `Hands` aims from the tick-exact body, not the render camera.
- Scenery is a pure function of `route_seed` and `distance_m`. Peers replicate two numbers.
- `ExteriorZone` is guarded by `multiplayer.is_server()`.
- Players are keyed by peer id, and `Main.spawn_player/spawn_prop/spawn_dummy` are the single
  place things are created, ready to be wrapped by `MultiplayerSpawner`.
- Gameplay events go through `GameEvents`, so the Witness system and fines can subscribe.

## Tests

```bash
godot --headless --path . --import
```

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

The exit code is non-zero if anything fails. Add `-- word` to run only tests whose name
contains `word`. The runner is a scene rather than `--script` because autoload names do not
resolve under `--script`. A run is repeatable: dice come from `TrainState.next_seed()`, and the
runner fixes the salt. Set the environment variable `TEST_RNG_SALT` to any number to replay every
test under other dice when hunting a flake. Any engine or script error in the log fails its test.

`tools/capture.tscn` plays the loop in a real window and saves screenshots to `captures/`.

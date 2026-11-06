# The Midnight Express: Boiler & Bistro

First-person co-op physics train game. Godot 4.7.2, GDScript, Jolt, Mobile renderer. PC and mobile.
The full design is in `docs/SPEC.md`, written by the project owner. `README.md` covers controls,
tuning and how the moving train works. `docs/FUN_PASS.md` covers the raid loop.

## Milestones

Stop after each milestone so the owner can playtest. Do not start the next one until they say so.

1. **Physics Boxcar & Yeet Prototype: done.** Godot project, PC and mobile input, 3-car train with
   openable doors and windows, scrolling treadmill, first-person grab/throw/bonk, Exterior Yeet
   Zone, knockable test dummies, rescue rope.
2. **Boiler & Bistro Loop: not started.** Coal furnace, train speed and temperature decay, breaker
   box, raw-to-cooked stove mechanics, dirty plate cleanup.
3. **Station Stops & Passenger AI: not started.** Treadmill deceleration into station platforms,
   passenger spawning, ID and luggage inspection UI, seating behavior, food ordering, the
   Witness/Shock system when someone gets bonked.
4. **Border Raids & Multiplayer Sync: partly done, solo only.** Peer-to-peer co-op networking, the
   real Border Patrol raid, contraband hiding spots. See below for what already exists.

## Current state

Beyond Milestone 1, the game already has a solo raid loop that goes past the roadmap: a raid clock,
stowaways that flee and hide, score, ranks, fines, a results screen and restart
(`scripts/game/round_director.gd`, `scripts/npc/test_dummy.gd`). Passengers panic, but there is no
Witness/Shock system yet. Sound is synthesized (`scripts/core/sfx.gd`). Models are built in Blender
(`blender/build_*.py`, contract in `docs/ART_BRIEF.md`).

**Next step: the owner's first real playtest.** No human has played the raid loop. Balance comes
from bots only, and bots are a floor on difficulty. Let that feedback set the next work before
starting Milestone 2.

Known weak spots:

- Heaves almost never miss if you wait for the prompt, so there is no skill in them.
- Carrying a body is short, about 1.4 s per stowaway.
- A held body breaks loose on about 3% of heaves. Re-grabbing recovers it.
- Players fall out of the Locomotive and Coach doors about once every 2 rounds.
- A stowaway was seen once at y 1.2 beside the -4.0 window. Cause not traced.
- Sound has been measured, never heard. Phone feel and mobile performance are untested.

## Rules

- **Gameplay first.** No art, Blender, scenery or lighting work until the owner reopens it. When
  asked to change the game, change how it plays, not only how it looks.
- Commit or push only when asked.
- The game stays original. Named inspirations are references for mechanics and genre only: copy
  none of their names, characters, art, music or levels.
- Keep the Milestone 4 seams. Player and Hands act only from `PlayerCommand`, host-only rules stay
  behind `multiplayer.is_server()`, and scenery is a function of route seed and distance.
- Reply in the language of the owner's latest message (English or French).

## Commands

Godot may not be on PATH. Find the console build first, then:

```bash
godot --headless --path . --import
```

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

Add `-- word` to run only tests whose name contains `word`. Tests live in `tests/suite_*.gd` and
are discovered automatically. Run the import step after adding scripts or class names.

Bot playtest, real game with no window:

```bash
godot --headless --path . --fixed-fps 60 res://tools/human_playtest.tscn -- sessions=decent,sloppy,idle seeds=1 first=0 rounds=7
```

Blender models build headless, one process per script:

```bash
blender --background --python blender/build_props.py
```

`Jouer.bat` assumes Godot is in the Downloads folder of the original PC, so fix its path on a new
machine. It forces Direct3D 12 because Vulkan failed every frame on that PC, even with an empty
project. `build/` is not in git. Android export needs the Android SDK and a debug keystore set up
locally, and Windows or Android export needs the 4.7.2 export templates.

# Fun pass: stream contracts

Goal: the prototype must become a game. A round should be tense, loud, and funny within
30 seconds of launch. Keep the Milestone 4 seams from README.md: Player and Hands act only
from PlayerCommand, and host-only rules stay behind `multiplayer.is_server()`.

## The round

The train carries passengers. Some are stowaways, and each one shows a clear marker.
A raid siren gives 60 seconds on the first raid. Before it ends, find stowaways, bonk them,
drag them and yeet them. A sprint only staggers a stowaway, so the bonk is what puts it down.
Yeeting a stowaway scores points. Yeeting a paying passenger costs points, but only if the
player touched them: one who wanders out of an open door is free. Every raid starts with the
openings shut. Only doors and the -4.0 and 4.5 windows open; the rest are rusted shut.
Stowaways still aboard when the raid hits cost a heavy fine. Panicking passengers run.
Then show a results screen with a one-button restart. The next round has more stowaways
and less time.

## Pacing

The clock is the target. The old 20-30 seconds per stowaway could not fit it: raid 1 would
need 60-90 seconds, raid 3 would need 100-150. A decent pace is about 6 seconds per stowaway:

| Raid | 1 | 2 | 3 | 4 | 5 | 6 | 7+ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Stowaways | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| Seconds | 60 | 56 | 52 | 48 | 44 | 40 | 40 |

Raids 1-2 are comfortable, raids 3-4 are tight, raids 5 and up are for good runs. These numbers
come from `tools/playtest_bot.tscn`. The bot reads tags through walls and never gets lost, so
treat its times as a floor. No human has played this pace yet.

## Shared events (`GameEvents`, already declared)

Emitters and listeners never call each other directly.

| Signal | Emitted by |
| --- | --- |
| `impact(body, position, speed)` | feel: a prop or ragdoll hits something hard |
| `npc_panicked(npc, position)` | npcs |
| `body_hit_scenery(body, speed)` | feel: a yeeted body hits an obstacle |
| `score_awarded(points, reason)` | rounds |
| `round_started(number, stowaways, seconds)` | rounds |
| `raid_warning(seconds_left)` | rounds, once per second in the last 10 seconds |
| `round_ended(score, passed)` | rounds |

Existing: `object_yeeted`, `object_despawned`, `npc_bonked`, `npc_knocked_out`,
`opening_toggled`, `player_left_train`, `player_reboarded`, `player_left_behind`,
`player_respawned`.

`object_yeeted(body)` receives a Ragdoll or PhysicsProp. `Ragdoll.is_stowaway` and
`TestDummy.is_stowaway` carry the role; the npcs stream owns copying it across a knockout,
with the feel stream leaving that field alone.

## Other shared state

- `TrainState.in_tunnel: bool`, `TrainState.blizzard: float` (0..1): written by world, read
  by sound and anyone else.
- `TestDummy.brain_enabled` (static, default true): when false a dummy stands still. The test
  runner sets it false so the old tests stay deterministic. Tests of the brain set it true.
- `Main.auto_start_round` (default true): the runner sets it false before `add_child`.

## Tests

`tests/run_tests.gd` is shared and owned by nobody. Add `tests/suite_<stream>.gd`:

```gdscript
extends RefCounted
var t: Node  # The runner: t.main, t.player, t.input, t.check(), t.seconds(), t.ticks(), t.events

func test_something() -> bool:
    await t.seconds(0.5)
    t.check(true, "label")
    return true
```

The runner discovers every `tests/suite_*.gd`, and each test gets a fresh Main.

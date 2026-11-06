# Art brief: The Midnight Express

Mood: a dark, tired train at night. Warm lamp pools in dim rooms, cold snow outside the glass.
The comedy comes from silhouettes, faces and one good gag per room, never from surface noise.
The genre references are physics party games and grotesque passenger-inspection games.
Those are references for tone only. Every design here is original: never copy a character,
logo, vehicle, prop or layout from an existing game.

## Style rules

- **Dark and restrained.** Colours come from the muted `wacky.PALETTE`. Surfaces are plain.
  The room gets its warmth from lamps, so walls stay low in saturation. Skin and eye whites
  are the brightest things in a car, because faces must read in a dim room.
- **Chunky.** Thick shapes, big clean silhouettes, readable at 10 metres. No thin detail.
- **Crooked.** Nothing is quite straight, but in the outline, not in surface decoration.
- **Exaggerated.** Heads too big, hands too big, noses too big, tools oversized by 20%.
- **Flat colour.** Faceted, flat-shaded, solid materials. No textures.
- **One or two jokes per car.** No posters, decals, stickers, stains, patches or repeated
  signs. A joke is one thing you notice, like the fallen O on the bistro sign. If a surface
  has a second gag on it, cut one.
- **Passengers** keep funny shapes and readable faces, with a short colour list each. Set
  `wacky.REMAP` after `reset_scene()` to hold a character to its colours.
- **Uncanny faces.** Googly mismatched eyes, wide-set stares, tiny pupils, too many teeth.
  Silly and a bit unsettling, never gory.

No real brands, no real people, no blood or gore.

## Baked light

Cabin `Interior` meshes carry lamp pools in vertex colours: `wacky.bake_pools()` slices the
mesh and paints warm light around the ceiling lamps, sconces and furnace. Furniture gets a
floor-to-top shade from `wacky.bake_height()`. The glTF importer multiplies these onto the
materials, so the room stays dark in every lighting setup. Exports use
`export_vertex_color="ACTIVE"`.

## Technical rules

- Build scripts live in `blender/build_<group>.py` and import `wacky` from `blender/lib`:
  `sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))`.
- All numbers below are Godot coordinates: X right, Y up, -Z forward. The kit converts them.
- Each `.glb` holds exactly the objects named here, with no rotation or scale left on them.
- Collision stays in Godot and is not rebuilt, so visuals must fit the sizes below.
- Text on signs: convert a font object to mesh, or build letters from boxes. Keep it short.
- Previews go to `assets/previews/<group>/<name>.png` using `wacky.preview()`.
- Do not edit `blender/lib/`, `scripts/`, or another group's files.

## Group: train (`assets/models/train/`)

Car: 18 m long along Z, origin at floor level at the car's centre. Floor top y=0, 0.25 thick.
Half width 1.9 (outer face x=±1.9), wall 0.2 thick. Ceiling y=2.7, roof slab to y=2.9.
Holes on BOTH sides, keep them exactly clear:
- Door hole at z=-1.0: width 1.4 (z -1.7 to -0.3), y 0 to 2.2.
- Window holes at z=-6.5, -4.0, 2.0, 4.5, 7.0: width 1.5, y 0.85 to 1.95.
End walls at z=±9, 0.2 thick, with a passage 1.3 wide and 2.2 high at x=0. Exception: the
Locomotive front wall (z=-9) is solid, no passage.

| File | Objects | Notes |
| --- | --- | --- |
| `car_locomotive.glb` | `Exterior`, `Interior` | Green-black iron, plain. One gag: the legs through the ceiling |
| `car_bistro.glb` | `Exterior`, `Interior` | Oxblood and dark wood, sconces, BISTRO sign with a fallen O |
| `car_coach.glb` | `Exterior`, `Interior` | Navy, two plank patches, a bath through the ceiling |
| `gangway.glb` | `Gangway` | Origin at centre floor. 1.54 wide, 1.3 long (z), 2.2 high, walk-through, rubber bellows look |
| `rear_platform.glb` | `Platform` | Origin at floor, front edge z=0 running to z=2.4, 3.8 wide. Rail top at y=1.04 on left, right and rear |
| `nose.glb` | `Nose` | Origin at the locomotive front wall, floor level, extends to z=-8. Absurd steam engine: huge boiler, crooked funnel, cow-catcher, a grinning face on the smokebox |
| `door_panel.glb` | `Panel` | Centred, 0.08 × 2.2 × 1.4 (x y z), slides along z. Side door |
| `rear_door_panel.glb` | `Panel` | Centred, 1.3 × 2.2 × 0.08, slides along x |
| `window_panel.glb` | `Frame`, `Glass` | Centred, 0.08 × 1.1 × 1.5, slides down. Glass material alpha 0.3 |

`Exterior` is everything seen from outside, including undercarriage, bogies and wheels down
to y=-1.3 and roof clutter up to y=3.6. `Interior` is what faces the cabin: wall lining,
ceiling, carpet at y=0.01, wainscot, luggage racks above y=2.25. Interior must not intrude
past x=±1.68 below y=2.2. Max 9000 tris per car.

## Group: furniture (`assets/models/furniture/`)

One object in each file, origin at floor level at the footprint centre. Visual must fill
this footprint and stay inside it by at most 5 cm of overhang.

| File | Object | Size (x y z) | Notes |
| --- | --- | --- | --- |
| `boiler.glb` | `Boiler` | 2.4 × 2.1 × 4.5 | Furnace door faces +Z, glowing orange emission, gauges all in the red |
| `coal_bin.glb` | `CoalBin` | 1.3 × 0.6 × 4.12 | Open top, walls on -X, +Z and -Z ends, open on +X side. Hollow, props rest inside |
| `counter.glb` | `Counter` | 1.1 × 1.0 × 0.6 | Dark counter, a suspicious pie under a dome |
| `table.glb` | `Table` | 0.8 × 0.78 × 1.0 | Top surface at y=0.78, plain dull cloth, one chained fork |
| `booth_seat.glb` | `BoothSeat` | 0.8 × 0.45 × 0.45 | Plain leather, one rip with a spring |
| `coach_seat.glb` | `CoachSeat` | 0.95 × 1.0 × 0.6 | Seat 0.45 high occupying z -0.3..+0.2; backrest at z +0.25..+0.35 |
| `ceiling_lamp.glb` | `Lamp` | 0.5 × 0.2 × 0.5 | Origin at the top, hangs down from y=0. Emission 2 |

Max 900 tris each.

## Group: props (`assets/models/props/`)

One object in each file, named `Prop`, centred on its collision box. Tools point their head
at -Z. Fit the size within 15%.

| File | Size (x y z) | Notes |
| --- | --- | --- |
| `coal.glb` | 0.26 × 0.2 × 0.24 | Lump with a tiny smug face |
| `crate.glb` | 0.62 × 0.5 × 0.62 | One stencilled joke label |
| `suitcase.glb` | 0.62 × 0.42 × 0.22 | Bulging, belt round it |
| `soup_bowl.glb` | 0.26 × 0.1 × 0.26 | Grey soup, something's eye floating in it |
| `wrench.glb` | 0.14 × 0.05 × 0.56 | Comically oversized jaw at -Z |
| `frying_pan.glb` | 0.3 × 0.06 × 0.62 | Pan at -Z, handle at +Z, a dented face-print in the base |
| `broom.glb` | 0.28 × 0.08 × 1.35 | Bristles at -Z, wild and uneven |
| `hand.glb` | 0.14 × 0.14 × 0.24 | First-person fist in a tatty fingerless glove, fingers at -Z |

Max 500 tris each.

## Group: passengers (`assets/models/passengers/`)

Six original wacky passengers: `gran.glb`, `baron.glb`, `smuggler.glb`, `intern.glb`,
`stoker.glb`, `opera.glb`. Invent their look from the names: a tiny fierce old lady with a
towering hairdo, a pompous moustached aristocrat, a shifty trench-coat type, a terrified
bug-eyed clerk, a soot-covered giant-handed furnace worker, a huge-chested opera diva.

Each file holds these twelve objects: `pelvis chest head head_ko upper_arm_l forearm_l
upper_arm_r forearm_r thigh_l shin_l thigh_r shin_r`. They get split into separate rigid
bodies, so each object's **origin must sit exactly at the part position below**, and pieces
must not depend on each other. `head_ko` replaces `head` once knocked out: same head with
crossed-out eyes and a lolling tongue. Same origin as `head`.

Standing in a neutral pose, arms down, feet at y=0, facing -Z. `_l` is on -X.

| Part | Position | Collision size |
| --- | --- | --- |
| pelvis | 0, 0.98, 0 | 0.36 × 0.22 × 0.22 |
| chest | 0, 1.31, 0 | 0.42 × 0.42 × 0.24 |
| head | 0, 1.67, 0 | 0.26 × 0.26 × 0.26 |
| upper_arm_l | -0.29, 1.35, 0 | 0.11 × 0.32 × 0.11 |
| forearm_l | -0.29, 1.03, 0 | 0.1 × 0.3 × 0.1 |
| upper_arm_r | 0.29, 1.35, 0 | 0.11 × 0.32 × 0.11 |
| forearm_r | 0.29, 1.03, 0 | 0.1 × 0.3 × 0.1 |
| thigh_l | -0.11, 0.66, 0 | 0.15 × 0.42 × 0.15 |
| shin_l | -0.11, 0.22, 0 | 0.13 × 0.42 × 0.13 |
| thigh_r | 0.11, 0.66, 0 | 0.15 × 0.42 × 0.15 |
| shin_r | 0.11, 0.22, 0 | 0.13 × 0.42 × 0.13 |

Meshes may overhang collision for comedy (head up to 0.55 wide, hands and boots huge), but
each part must still sit in its joint position. Hats, hair and moustaches belong to the
head part. Hands belong to the forearm, boots to the shin. Max 2800 tris per passenger.

## Group: scenery (`assets/models/scenery/`)

One object in each file, named `Scenery`, origin on the ground at the base, y=0 is ground.
These are drawn hundreds of times, so keep them cheap. All snow-laden.

| File | Size guide | Max tris | Notes |
| --- | --- | --- | --- |
| `tree_a.glb` | 3.8 wide, 7 high | 220 | Crooked dark pine, trunk radius about 0.4, no gags: it repeats hundreds of times |
| `tree_b.glb` | 3 wide, 6 high | 220 | Dead twisted tree with a boot stuck in it |
| `rock.glb` | 2 wide, 1.2 high | 120 | Lumpy boulder, snow cap |
| `pole.glb` | 1.8 wide, 6.2 high | 150 | Leaning telegraph pole. Crossarm at y=5.7, two wires leaving along -Z for 24 m at x=±0.8, y=5.78 |
| `drift.glb` | unit: radius 1, height 2 | 80 | Lumpy snow mound, centred on origin, scaled in engine |
| `gag_sign_a.glb` | 3 wide, 3.5 high | 300 | Warning sign, text "NO REFUNDS" |
| `gag_sign_b.glb` | 3 wide, 3.5 high | 300 | Sign, text "LAST SOUP 900 KM" |
| `gag_snowman.glb` | 2 wide, 3 high | 300 | Menacing snowman with too many teeth |
| `gag_outhouse.glb` | 2 wide, 2.8 high | 300 | Lonely outhouse, door swinging open |

class_name Layers
## Physics layer bits. Names mirror [layer_names] in project.godot.

const HULL := 1 << 0       ## Train shell, furniture, doors, windows.
const GROUND := 1 << 1     ## Scrolling snow (a conveyor belt, see Treadmill).
const SCENERY := 1 << 2    ## Scrolling trees, poles, rocks.
const PLAYER := 1 << 3
const PROP := 1 << 4
const RAGDOLL := 1 << 5
const NPC := 1 << 6
const USE_VOLUME := 1 << 7 ## Area3D filling each opening, so rays can still close it.

## What a rigid body collides with once it has left the train. HULL is dropped on
## purpose: at 100 km/h nothing should snag on the outside of the carriages.
const OUTSIDE_MASK := GROUND | SCENERY | PROP

class_name BodyPlan
## Shared humanoid layout, so the standing dummy and its ragdoll match pixel for pixel.
## Positions are in dummy space: feet at the origin, facing -Z.

const PARTS := {
	&"pelvis": {"size": Vector3(0.36, 0.22, 0.22), "pos": Vector3(0.0, 0.98, 0.0), "mass": 8.0},
	&"chest": {"size": Vector3(0.42, 0.42, 0.24), "pos": Vector3(0.0, 1.31, 0.0), "mass": 14.0},
	&"head": {"size": Vector3(0.26, 0.26, 0.26), "pos": Vector3(0.0, 1.67, 0.0), "mass": 4.0},
	&"upper_arm_l": {"size": Vector3(0.11, 0.32, 0.11), "pos": Vector3(-0.29, 1.35, 0.0), "mass": 2.5},
	&"forearm_l": {"size": Vector3(0.1, 0.3, 0.1), "pos": Vector3(-0.29, 1.03, 0.0), "mass": 1.5},
	&"upper_arm_r": {"size": Vector3(0.11, 0.32, 0.11), "pos": Vector3(0.29, 1.35, 0.0), "mass": 2.5},
	&"forearm_r": {"size": Vector3(0.1, 0.3, 0.1), "pos": Vector3(0.29, 1.03, 0.0), "mass": 1.5},
	&"thigh_l": {"size": Vector3(0.15, 0.42, 0.15), "pos": Vector3(-0.11, 0.66, 0.0), "mass": 5.0},
	&"shin_l": {"size": Vector3(0.13, 0.42, 0.13), "pos": Vector3(-0.11, 0.22, 0.0), "mass": 3.0},
	&"thigh_r": {"size": Vector3(0.15, 0.42, 0.15), "pos": Vector3(0.11, 0.66, 0.0), "mass": 5.0},
	&"shin_r": {"size": Vector3(0.13, 0.42, 0.13), "pos": Vector3(0.11, 0.22, 0.0), "mass": 3.0},
}

## cone: ball joint, X axis runs down the child bone. hinge: elbow/knee around the body's X.
const JOINTS := [
	{"a": &"pelvis", "b": &"chest", "kind": &"cone", "at": Vector3(0.0, 1.09, 0.0), "dir": Vector3.UP, "swing": 28.0, "twist": 20.0},
	{"a": &"chest", "b": &"head", "kind": &"cone", "at": Vector3(0.0, 1.53, 0.0), "dir": Vector3.UP, "swing": 38.0, "twist": 35.0},
	{"a": &"chest", "b": &"upper_arm_l", "kind": &"cone", "at": Vector3(-0.27, 1.5, 0.0), "dir": Vector3.DOWN, "swing": 95.0, "twist": 40.0},
	{"a": &"upper_arm_l", "b": &"forearm_l", "kind": &"hinge", "at": Vector3(-0.29, 1.19, 0.0), "low": -2.0, "high": 125.0},
	{"a": &"chest", "b": &"upper_arm_r", "kind": &"cone", "at": Vector3(0.27, 1.5, 0.0), "dir": Vector3.DOWN, "swing": 95.0, "twist": 40.0},
	{"a": &"upper_arm_r", "b": &"forearm_r", "kind": &"hinge", "at": Vector3(0.29, 1.19, 0.0), "low": -2.0, "high": 125.0},
	{"a": &"pelvis", "b": &"thigh_l", "kind": &"cone", "at": Vector3(-0.11, 0.87, 0.0), "dir": Vector3.DOWN, "swing": 65.0, "twist": 25.0},
	{"a": &"thigh_l", "b": &"shin_l", "kind": &"hinge", "at": Vector3(-0.11, 0.44, 0.0), "low": -125.0, "high": 2.0},
	{"a": &"pelvis", "b": &"thigh_r", "kind": &"cone", "at": Vector3(0.11, 0.87, 0.0), "dir": Vector3.DOWN, "swing": 65.0, "twist": 25.0},
	{"a": &"thigh_r", "b": &"shin_r", "kind": &"hinge", "at": Vector3(0.11, 0.44, 0.0), "low": -125.0, "high": 2.0},
]

const HEIGHT := 1.8
## Passenger models in assets/models/passengers. Each holds one mesh per part above,
## plus head_ko, the knocked-out head.
const PASSENGERS: Array[String] = ["gran", "baron", "smuggler", "intern", "stoker", "opera"]
## These stand back up after a shove. The rest faint on the spot. Stowaways always get up.
const TOUGH: Array[String] = ["gran", "baron", "smuggler", "stoker"]
## How each passenger walks. sway: side-to-side roll (rad). stride: leg swing (rad).
## cadence: step rate. speed: wander speed multiplier.
const GAIT := {
	"gran": {"sway": 0.2, "stride": 0.32, "cadence": 1.5, "speed": 0.7},
	"baron": {"sway": 0.3, "stride": 0.5, "cadence": 0.8, "speed": 0.85},
	"smuggler": {"sway": 0.08, "stride": 0.6, "cadence": 1.1, "speed": 1.1},
	"intern": {"sway": 0.12, "stride": 0.65, "cadence": 1.3, "speed": 1.3},
	"stoker": {"sway": 0.24, "stride": 0.7, "cadence": 0.9, "speed": 1.0},
	"opera": {"sway": 0.36, "stride": 0.42, "cadence": 1.0, "speed": 0.9},
}


## Mesh for a body part. Part origins sit at their BodyPlan positions.
static func part_mesh(passenger: String, part_name: StringName, knocked_out := false) -> Mesh:
	var object := String(part_name)
	if knocked_out and part_name == &"head":
		object = "head_ko"
	return Models.mesh("passengers/" + passenger, object)

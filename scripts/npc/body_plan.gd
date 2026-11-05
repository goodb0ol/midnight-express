class_name BodyPlan
## Shared humanoid layout, so the standing dummy and its ragdoll match pixel for pixel.
## Positions are in dummy space: feet at the origin, facing -Z.

const PARTS := {
	&"pelvis": {"size": Vector3(0.36, 0.22, 0.22), "pos": Vector3(0.0, 0.98, 0.0), "mass": 8.0, "tint": &"pants"},
	&"chest": {"size": Vector3(0.42, 0.42, 0.24), "pos": Vector3(0.0, 1.31, 0.0), "mass": 14.0, "tint": &"shirt"},
	&"head": {"size": Vector3(0.26, 0.26, 0.26), "pos": Vector3(0.0, 1.67, 0.0), "mass": 4.0, "tint": &"skin"},
	&"upper_arm_l": {"size": Vector3(0.11, 0.32, 0.11), "pos": Vector3(-0.29, 1.35, 0.0), "mass": 2.5, "tint": &"shirt"},
	&"forearm_l": {"size": Vector3(0.1, 0.3, 0.1), "pos": Vector3(-0.29, 1.03, 0.0), "mass": 1.5, "tint": &"skin"},
	&"upper_arm_r": {"size": Vector3(0.11, 0.32, 0.11), "pos": Vector3(0.29, 1.35, 0.0), "mass": 2.5, "tint": &"shirt"},
	&"forearm_r": {"size": Vector3(0.1, 0.3, 0.1), "pos": Vector3(0.29, 1.03, 0.0), "mass": 1.5, "tint": &"skin"},
	&"thigh_l": {"size": Vector3(0.15, 0.42, 0.15), "pos": Vector3(-0.11, 0.66, 0.0), "mass": 5.0, "tint": &"pants"},
	&"shin_l": {"size": Vector3(0.13, 0.42, 0.13), "pos": Vector3(-0.11, 0.22, 0.0), "mass": 3.0, "tint": &"pants"},
	&"thigh_r": {"size": Vector3(0.15, 0.42, 0.15), "pos": Vector3(0.11, 0.66, 0.0), "mass": 5.0, "tint": &"pants"},
	&"shin_r": {"size": Vector3(0.13, 0.42, 0.13), "pos": Vector3(0.11, 0.22, 0.0), "mass": 3.0, "tint": &"pants"},
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
const PALETTES: Array[Dictionary] = [
	{&"shirt": Color(0.72, 0.56, 0.24), &"pants": Color(0.25, 0.25, 0.3), &"skin": Color(0.86, 0.72, 0.6)},
	{&"shirt": Color(0.24, 0.52, 0.42), &"pants": Color(0.32, 0.22, 0.2), &"skin": Color(0.72, 0.56, 0.44)},
	{&"shirt": Color(0.6, 0.24, 0.4), &"pants": Color(0.2, 0.26, 0.34), &"skin": Color(0.9, 0.78, 0.68)},
	{&"shirt": Color(0.3, 0.36, 0.64), &"pants": Color(0.3, 0.28, 0.22), &"skin": Color(0.52, 0.38, 0.3)},
]


static func add_face(head: Node3D, text: String) -> Label3D:
	var face := Label3D.new()
	face.name = "Face"
	face.text = text
	face.font_size = 42
	face.pixel_size = 0.0045
	face.modulate = Color(0.08, 0.05, 0.05)
	face.outline_size = 0
	face.position = Vector3(0.0, 0.0, -0.135)
	face.rotation.y = PI
	face.double_sided = false
	head.add_child(face)
	return face

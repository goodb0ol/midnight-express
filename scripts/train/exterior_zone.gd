class_name ExteriorZone
extends Area3D
## The Exterior Yeet Zone: a thick trigger shell around the train hull.
##
## Touching the shell only makes a body a candidate. It counts as gone once its
## anchor (centre of a prop, pelvis of a ragdoll, torso of a player) leaves the hull,
## so an arm dangling out of a window gets tugged by the slipstream instead of
## launching the whole passenger.
##
## Host-only in co-op: clients just see the resulting transforms.

const SHELL := 400.0

var hull := AABB()
var _candidates: Dictionary = {}  # Node3D -> true


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER | Layers.PROP | Layers.RAGDOLL
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Rebuilds the shell around [param new_hull]. Call again whenever cars are added.
func fit_to(new_hull: AABB) -> void:
	hull = new_hull
	for child in get_children():
		child.queue_free()
	var low := hull.position
	var high := hull.end
	var far_low := low - Vector3.ONE * SHELL
	var far_high := high + Vector3.ONE * SHELL
	_add_box(Vector3(far_low.x, far_low.y, far_low.z), Vector3(low.x, far_high.y, far_high.z), "Left")
	_add_box(Vector3(high.x, far_low.y, far_low.z), Vector3(far_high.x, far_high.y, far_high.z), "Right")
	_add_box(Vector3(low.x, far_low.y, high.z), Vector3(high.x, far_high.y, far_high.z), "Rear")
	_add_box(Vector3(low.x, far_low.y, far_low.z), Vector3(high.x, far_high.y, low.z), "Front")
	_add_box(Vector3(low.x, high.y, low.z), Vector3(high.x, far_high.y, high.z), "Top")
	_add_box(Vector3(low.x, far_low.y, low.z), Vector3(high.x, low.y, high.z), "Below")


func is_outside(point: Vector3) -> bool:
	return not hull.has_point(point)


func _add_box(low: Vector3, high: Vector3, label: String) -> void:
	var shape := CollisionShape3D.new()
	shape.name = label
	var box := BoxShape3D.new()
	box.size = high - low
	shape.shape = box
	shape.position = (low + high) * 0.5
	add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("on_left_train") and not body.call("is_off_train"):
		_candidates[body] = true


func _on_body_exited(body: Node3D) -> void:
	_candidates.erase(body)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body: Node3D in _candidates.keys():
		if not is_instance_valid(body):
			_candidates.erase(body)
		elif body.call("is_off_train"):
			_candidates.erase(body)
		elif is_outside(body.call("yeet_anchor")):
			body.call("on_left_train")
			_candidates.erase(body)
		elif body is RigidBody3D and is_outside(body.global_position):
			_apply_slipstream(body)


func _apply_slipstream(body: RigidBody3D) -> void:
	var strength := TrainState.speed_mps / YeetTuning.FULL_SPEED
	body.apply_central_force(Vector3.BACK * YeetTuning.PARTIAL_WIND_ACCEL * strength * body.mass)

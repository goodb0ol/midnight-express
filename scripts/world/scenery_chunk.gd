class_name SceneryChunk
extends AnimatableBody3D
## One pooled stretch of wasteland. A single kinematic body carries every obstacle's
## collision shape, so scrolling costs one body per chunk however many trees it holds.
## Contents are a pure function of (route_seed, index): every peer builds the same chunk.

const LENGTH := 48.0
const TREE_COUNT := 16
const ROCK_COUNT := 5
const DRIFT_COUNT := 3
const POLE_COUNT := 2
## Only obstacles this close to the track get a collider.
const COLLIDER_MAX_X := 26.0
## Nothing may stand closer to the track than this.
const TRACK_CLEARANCE := 4.2

var index := 0
var _trees: MultiMesh
var _rocks: MultiMesh
var _drifts: MultiMesh
var _tree_shapes: Array[CollisionShape3D] = []
var _rock_shapes: Array[CollisionShape3D] = []
var _collidable := true


func _init(shared: Dictionary) -> void:
	sync_to_physics = false
	collision_layer = Layers.SCENERY
	collision_mask = 0
	physics_material_override = shared["material"]
	_trees = _add_instances(shared["tree"], TREE_COUNT)
	_rocks = _add_instances(shared["rock"], ROCK_COUNT)
	_drifts = _add_instances(shared["drift"], DRIFT_COUNT)
	var poles := _add_instances(shared["pole"], POLE_COUNT)
	for i in POLE_COUNT:
		var spot := Vector3(-5.2, Treadmill.GROUND_Y, -LENGTH * float(i) / POLE_COUNT)
		poles.set_instance_transform(i, Transform3D(Basis.IDENTITY, spot))
		_add_shape(shared["pole_shape"]).position = spot + Vector3.UP * 3.0
	for i in TREE_COUNT:
		_tree_shapes.append(_add_shape(shared["trunk_shape"]))
	for i in ROCK_COUNT:
		_rock_shapes.append(_add_shape(shared["rock_shape"]))


## Obstacle positions, for comparing what two peers built.
func layout_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for shape in _tree_shapes + _rock_shapes:
		result.append(shape.position)
	return result


func populate(new_index: int) -> void:
	index = new_index
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([TrainState.route_seed, index])

	for i in TREE_COUNT:
		var spot := _pick_spot(rng, 6.0, 70.0)
		var scale_factor := rng.randf_range(0.8, 1.5)
		_trees.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale_factor), spot))
		_place_collider(_tree_shapes[i], spot + Vector3.UP * 2.0)
	for i in ROCK_COUNT:
		var spot := _pick_spot(rng, TRACK_CLEARANCE, 40.0)
		var rock_scale := Vector3(rng.randf_range(0.8, 1.7), rng.randf_range(0.6, 1.1), rng.randf_range(0.8, 1.6))
		_rocks.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(rock_scale), spot + Vector3.UP * 0.1))
		_place_collider(_rock_shapes[i], spot + Vector3.UP * 0.5)
	for i in DRIFT_COUNT:
		var spot := _pick_spot(rng, 9.0, 90.0)
		var drift_scale := Vector3(rng.randf_range(4.0, 11.0), rng.randf_range(0.5, 1.4), rng.randf_range(6.0, 14.0))
		_drifts.set_instance_transform(i, Transform3D(Basis.from_scale(drift_scale), spot))


func place(distance: float, collide_ahead: float, collide_behind: float) -> void:
	position.z = distance - index * LENGTH
	var should_collide := position.z > -collide_ahead and position.z < collide_behind
	if should_collide != _collidable:
		_collidable = should_collide
		collision_layer = Layers.SCENERY if should_collide else 0


## Moves a recycled chunk without the kinematic body sweeping across the world.
func teleport_to(distance: float) -> void:
	collision_layer = 0
	_collidable = false
	position.z = distance - index * LENGTH
	reset_physics_interpolation()


func _pick_spot(rng: RandomNumberGenerator, min_x: float, max_x: float) -> Vector3:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# Squared bias keeps more obstacles near the track, where bodies actually land.
	var x := min_x + (max_x - min_x) * pow(rng.randf(), 1.8)
	return Vector3(side * x, Treadmill.GROUND_Y, -rng.randf() * LENGTH)


func _place_collider(shape: CollisionShape3D, point: Vector3) -> void:
	shape.position = point
	shape.disabled = absf(point.x) > COLLIDER_MAX_X


func _add_instances(mesh: Mesh, count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)
	return multimesh


func _add_shape(shape: Shape3D) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	add_child(node)
	return node

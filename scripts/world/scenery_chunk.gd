class_name SceneryChunk
extends AnimatableBody3D
## One pooled stretch of wasteland. A single kinematic body carries every obstacle's
## collision shape, so scrolling costs one body per chunk however many trees it holds.
## Contents are a pure function of (route_seed, index): every peer builds the same chunk.
## The chunk also carries its strip of low-poly land, and its share of any tunnel or bridge.

const LENGTH := 48.0
const TREE_COUNT := 16
const CROOKED_TREES := 10  ## The rest are dead trees.
const ROCK_COUNT := 5
const DRIFT_COUNT := 3
const POLE_COUNT := 2
const PINE_COUNT := 60
const PINE_TRIES := 170
const PINE_MIN_X := 28.0
const PINE_MAX_X := 300.0
## Only obstacles this close to the track get a collider.
const COLLIDER_MAX_X := 26.0
## Nothing may stand closer to the track than this.
const TRACK_CLEARANCE := 4.2
const POLE_X := -5.2
## Small props are not drawn past this; a far chunk is land and forest only.
const DETAIL_RANGE_M := 240.0
const TREE_RANGE_M := 380.0

## Land grid: dense beside the track, coarse out on the mountains.
const COLUMNS: Array[float] = [
	-460.0, -350.0, -270.0, -210.0, -160.0, -125.0, -98.0, -78.0, -62.0, -50.0, -40.0, -32.0,
	-26.0, -21.0, -16.0, -12.0, -8.0, -4.0, 0.0,
	4.0, 8.0, 12.0, 16.0, 21.0, 26.0,
	32.0, 40.0, 50.0, 62.0, 78.0, 98.0, 125.0, 160.0, 210.0, 270.0, 350.0, 460.0,
]
const ROWS := 6
const ROW_M := LENGTH / ROWS

const SNOW_LIGHT := Color(0.7, 0.77, 0.93)
const SNOW_DARK := Color(0.62, 0.69, 0.87)
const ROCK_LIGHT := Color(0.25, 0.26, 0.32)
const ROCK_DARK := Color(0.13, 0.13, 0.18)
const ICE := Color(0.32, 0.5, 0.68)
const GORGE_ICE := Color(0.13, 0.21, 0.34)

var index := 0
var _route: Route
var _trees: MultiMesh
var _dead_trees: MultiMesh
var _rocks: MultiMesh
var _drifts: MultiMesh
var _poles: MultiMesh
var _pines: MultiMesh
var _tree_shapes: Array[CollisionShape3D] = []
var _rock_shapes: Array[CollisionShape3D] = []
var _pole_shapes: Array[CollisionShape3D] = []
var _gag: MeshInstance3D
var _gag_shape: CollisionShape3D
var _gag_meshes: Array = []
var _collidable := true
var _land: ArrayMesh
var _land_instance: MeshInstance3D
var _section: MeshInstance3D
var _section_meshes: Dictionary
var _wall_shapes: Array[CollisionShape3D] = []
var _roof_shape: CollisionShape3D
var _portal_shapes: Array[CollisionShape3D] = []
var _near: Array[Route.Piece] = []
var _settled_y := 0.0
var _land_verts := PackedVector3Array()
var _land_normals := PackedVector3Array()
var _land_colors := PackedColorArray()


func _init(shared: Dictionary) -> void:
	sync_to_physics = false
	collision_layer = Layers.SCENERY
	collision_mask = 0
	physics_material_override = shared["material"]
	_route = shared["route"]
	_section_meshes = shared["sections"]
	_land = ArrayMesh.new()
	_land_instance = MeshInstance3D.new()
	_land_instance.name = "Land"
	_land_instance.mesh = _land
	_land_instance.material_override = LowPoly.lit_material()
	_land_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_land_instance)
	_section = MeshInstance3D.new()
	_section.name = "Section"
	_section.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_section.visible = false
	add_child(_section)

	_trees = _add_instances(shared["tree"], CROOKED_TREES, TREE_RANGE_M)
	_dead_trees = _add_instances(shared["dead_tree"], TREE_COUNT - CROOKED_TREES, TREE_RANGE_M)
	_rocks = _add_instances(shared["rock"], ROCK_COUNT, DETAIL_RANGE_M)
	_drifts = _add_instances(shared["drift"], DRIFT_COUNT, DETAIL_RANGE_M)
	_pines = _add_instances(shared["pine"], PINE_COUNT, 0.0)
	_pines.visible_instance_count = 0
	_poles = _add_instances(shared["pole"], POLE_COUNT, DETAIL_RANGE_M)
	for i in POLE_COUNT:
		var spot := Vector3(POLE_X, Treadmill.GROUND_Y, -LENGTH * float(i) / POLE_COUNT)
		_poles.set_instance_transform(i, Transform3D(Basis.IDENTITY, spot))
		var shape := _add_shape(shared["pole_shape"])
		shape.position = spot + Vector3.UP * 3.0
		_pole_shapes.append(shape)
	for i in TREE_COUNT:
		_tree_shapes.append(_add_shape(shared["trunk_shape"]))
	for i in ROCK_COUNT:
		_rock_shapes.append(_add_shape(shared["rock_shape"]))
	_gag_meshes = shared["gags"]
	_gag = MeshInstance3D.new()
	_gag.visibility_range_end = DETAIL_RANGE_M
	add_child(_gag)
	_gag_shape = _add_shape(shared["gag_shape"])

	var wall_center_x := SetPieceMeshes.TUNNEL_HALF_WIDTH + 1.5
	for side: float in [-1.0, 1.0]:
		var wall := _add_shape(shared["tunnel_wall_shape"])
		wall.position = Vector3(side * wall_center_x, Treadmill.GROUND_Y + 5.0, -LENGTH * 0.5)
		wall.disabled = true
		_wall_shapes.append(wall)
		var pier := _add_shape(shared["portal_pier_shape"])
		pier.position = Vector3(side * 15.4, Treadmill.GROUND_Y + 8.0, 0.0)
		pier.disabled = true
		_portal_shapes.append(pier)
	_roof_shape = _add_shape(shared["tunnel_roof_shape"])
	_roof_shape.position = Vector3(0.0, Treadmill.GROUND_Y + SetPieceMeshes.TUNNEL_CROWN + 1.0, -LENGTH * 0.5)
	_roof_shape.disabled = true


## Obstacle positions, for comparing what two peers built.
func layout_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for shape in _tree_shapes + _rock_shapes:
		result.append(shape.position)
	return result


func populate(new_index: int) -> void:
	index = new_index
	var start_s := index * LENGTH
	_near = _route.pieces_between(start_s - 130.0, start_s + LENGTH + 130.0)
	_build_land()
	_apply_section()

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([TrainState.route_seed, index])
	for i in TREE_COUNT:
		var spot := _pick_spot(rng, 6.0, 70.0)
		var scale_factor := rng.randf_range(0.8, 1.5)
		var yaw := rng.randf() * TAU
		var free := _settle(spot)
		spot.y = _settled_y
		var tree_transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (scale_factor if free else 0.0)), spot)
		if i < CROOKED_TREES:
			_trees.set_instance_transform(i, tree_transform)
		else:
			_dead_trees.set_instance_transform(i - CROOKED_TREES, tree_transform)
		_place_collider(_tree_shapes[i], spot + Vector3.UP * 2.0, free)
	for i in ROCK_COUNT:
		var spot := _pick_spot(rng, TRACK_CLEARANCE, 40.0)
		var rock_scale := Vector3(rng.randf_range(0.8, 1.7), rng.randf_range(0.6, 1.1), rng.randf_range(0.8, 1.6))
		var yaw := rng.randf() * TAU
		var free := _settle(spot)
		spot.y = _settled_y
		_rocks.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(rock_scale if free else Vector3.ZERO), spot + Vector3.UP * 0.1))
		_place_collider(_rock_shapes[i], spot + Vector3.UP * 0.5, free)
	for i in DRIFT_COUNT:
		var spot := _pick_spot(rng, 9.0, 90.0)
		var drift_scale := Vector3(rng.randf_range(4.0, 11.0), rng.randf_range(0.5, 1.4), rng.randf_range(6.0, 14.0))
		var free := _settle(spot)
		spot.y = _settled_y
		_drifts.set_instance_transform(i, Transform3D(Basis.from_scale(drift_scale if free else Vector3.ZERO), spot))
	for i in POLE_COUNT:
		var s := start_s + LENGTH * float(i) / POLE_COUNT
		var free := _is_free(POLE_X, s, _route.height(POLE_X, s, _near))
		var spot := Vector3(POLE_X, Treadmill.GROUND_Y, -LENGTH * float(i) / POLE_COUNT)
		_poles.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE if free else Vector3.ZERO), spot))
		_pole_shapes[i].disabled = not free
	_place_pines(rng)
	_place_gag(rng)


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


## True while this chunk's tunnel walls are solid.
func has_tunnel_walls() -> bool:
	return not _wall_shapes[0].disabled


## Which part of a tunnel or bridge sits in this chunk, if any.
func _apply_section() -> void:
	var start_s := index * LENGTH
	var mesh: Mesh = null
	var tunnel := false
	var entry := false
	var exit := false
	for piece in _near:
		if start_s < piece.start_m or start_s >= piece.end_m:
			continue
		if piece.kind == Route.Kind.TUNNEL:
			tunnel = true
			entry = is_equal_approx(start_s, piece.start_m)
			exit = is_equal_approx(start_s + LENGTH, piece.end_m)
			mesh = _section_meshes["tunnel_entry" if entry else ("tunnel_exit" if exit else "tunnel")]
		elif piece.kind == Route.Kind.BRIDGE:
			mesh = _section_meshes["bridge"]
	_section.mesh = mesh
	_section.visible = mesh != null
	for shape in _wall_shapes:
		shape.disabled = not tunnel
	_roof_shape.disabled = not tunnel
	for shape in _portal_shapes:
		shape.disabled = not (entry or exit)
		shape.position.z = 0.0 if entry else -LENGTH


func _build_land() -> void:
	var cols := COLUMNS.size()
	var start_s := index * LENGTH
	var heights := PackedFloat32Array()
	heights.resize(cols * (ROWS + 1))
	for row in ROWS + 1:
		var s := start_s + row * ROW_M
		for col in cols:
			heights[row * cols + col] = _route.height(COLUMNS[col], s, _near)
	var count := (cols - 1) * ROWS * 6
	if _land_verts.size() != count:
		_land_verts.resize(count)
		_land_normals.resize(count)
		_land_colors.resize(count)
	var write := 0
	for row in ROWS:
		var z0 := -row * ROW_M
		var z1 := z0 - ROW_M
		for col in cols - 1:
			var x0: float = COLUMNS[col]
			var x1: float = COLUMNS[col + 1]
			var a := Vector3(x0, heights[row * cols + col], z0)
			var b := Vector3(x1, heights[row * cols + col + 1], z0)
			var c := Vector3(x1, heights[(row + 1) * cols + col + 1], z1)
			var d := Vector3(x0, heights[(row + 1) * cols + col], z1)
			write = _land_tri(write, a, d, c, row, col)
			write = _land_tri(write, a, c, b, row, col + 100)
	_land.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _land_verts
	arrays[Mesh.ARRAY_NORMAL] = _land_normals
	arrays[Mesh.ARRAY_COLOR] = _land_colors
	_land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _land_tri(write: int, a: Vector3, b: Vector3, c: Vector3, row: int, salt: int) -> int:
	var normal := (c - a).cross(b - a).normalized()
	var color := _land_color(a, b, c, normal, row, salt)
	_land_verts[write] = a
	_land_verts[write + 1] = b
	_land_verts[write + 2] = c
	for i in 3:
		_land_normals[write + i] = normal
		_land_colors[write + i] = color
	return write + 3


func _land_color(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, row: int, salt: int) -> Color:
	var center_y := (a.y + b.y + c.y) / 3.0
	var jitter := fposmod(sin(float(index * ROWS + row) * 0.731 + float(salt) * 12.9898) * 43758.5453, 1.0)
	var low := Treadmill.GROUND_Y - center_y
	if low > Route.GORGE_DEPTH - 6.0:
		return GORGE_ICE.lightened(jitter * 0.12)
	if low > 0.45 and low < 2.0 and absf(normal.y) > 0.98:
		return ICE.lightened(jitter * 0.12)
	var snow := SNOW_DARK.lerp(SNOW_LIGHT, jitter)
	var steep := 1.0 - smoothstep(0.62, 0.82, absf(normal.y))
	if steep <= 0.0:
		return snow
	return snow.lerp(ROCK_DARK.lerp(ROCK_LIGHT, jitter), steep)


## Finds where a spot rests, in _settled_y. False means nothing may stand here. Colliders
## stay on the flat plane near the track; further out things sit on the hill, uncollided.
func _settle(spot: Vector3) -> bool:
	var s := index * LENGTH - spot.z
	var h := _route.height(spot.x, s, _near)
	_settled_y = h if absf(spot.x) > COLLIDER_MAX_X else Treadmill.GROUND_Y
	return _is_free(spot.x, s, h)


func _is_free(x: float, s: float, h: float) -> bool:
	if _route.is_clear_zone(x, s, _near):
		return false
	var above := h - Treadmill.GROUND_Y
	if absf(x) <= COLLIDER_MAX_X:
		return absf(above) < 0.7
	return above > -0.3


func _place_pines(rng: RandomNumberGenerator) -> void:
	var used := 0
	var start_s := index * LENGTH
	for i in PINE_TRIES:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * lerpf(PINE_MIN_X, PINE_MAX_X, pow(rng.randf(), 1.5))
		var z := -rng.randf() * LENGTH
		var yaw := rng.randf() * TAU
		var size := rng.randf_range(0.8, 1.9)
		if used >= PINE_COUNT:
			break
		var s := start_s - z
		if _route.forest_at(x, s) < 0.0:
			continue
		var h := _route.height(x, s, _near)
		if not _is_free(x, s, h) or h > Treadmill.GROUND_Y + 95.0:
			continue
		_pines.set_instance_transform(used, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(x, h - 0.2, z)))
		used += 1
	_pines.visible_instance_count = used


## One joke per chunk, close enough to the track to read at speed. Signs face the train.
func _place_gag(rng: RandomNumberGenerator) -> void:
	var spot := _pick_spot(rng, 6.0, 12.0)
	var mesh: Mesh = _gag_meshes[rng.randi_range(0, _gag_meshes.size() - 1)]
	var free := _settle(spot)
	spot.y = _settled_y
	_gag.mesh = mesh if free else null
	_gag.transform = Transform3D(Basis(Vector3.UP, -signf(spot.x) * PI * 0.5), spot)
	_place_collider(_gag_shape, spot + Vector3.UP * 1.5, free)


func _pick_spot(rng: RandomNumberGenerator, min_x: float, max_x: float) -> Vector3:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# Squared bias keeps more obstacles near the track, where bodies actually land.
	var x := min_x + (max_x - min_x) * pow(rng.randf(), 1.8)
	return Vector3(side * x, Treadmill.GROUND_Y, -rng.randf() * LENGTH)


func _place_collider(shape: CollisionShape3D, point: Vector3, free := true) -> void:
	shape.position = point
	shape.disabled = not free or absf(point.x) > COLLIDER_MAX_X


func _add_instances(mesh: Mesh, count: int, visible_range: float) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if visible_range <= 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.visibility_range_end = visible_range
	add_child(instance)
	return multimesh


func _add_shape(shape: Shape3D) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.shape = shape
	add_child(node)
	return node

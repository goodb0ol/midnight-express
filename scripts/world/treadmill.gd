class_name Treadmill
extends Node3D
## The scrolling wasteland. Nothing here simulates travel: the ground is a static
## conveyor (constant_linear_velocity) and obstacles are pooled kinematic chunks
## placed from TrainState.distance_m.

const GROUND_Y := -1.45
const AHEAD_M := 430.0
const BEHIND_M := 250.0
const COLLIDE_AHEAD_M := 150.0
const COLLIDE_BEHIND_M := 235.0
const GROUND_TILE_M := 18.0
const SLEEPER_SPACING := 2.4
const SLEEPER_SPAN_M := 460.0

var ground: StaticBody3D
var _chunks: Dictionary = {}  # int -> SceneryChunk
var _free_chunks: Array[SceneryChunk] = []
var _shared: Dictionary = {}
var _snow_material: StandardMaterial3D
var _ballast_material: StandardMaterial3D
var _sleepers: MultiMeshInstance3D
var _streak_material: ShaderMaterial


func _ready() -> void:
	_build_ground()
	_build_track()
	_build_horizon()
	_build_streaks()
	_build_shared_resources()
	for i in maxi(ceili((AHEAD_M + BEHIND_M) / SceneryChunk.LENGTH) + 2, 1):
		var chunk := SceneryChunk.new(_shared)
		chunk.name = "Chunk%d" % i
		chunk.visible = false
		chunk.collision_layer = 0
		add_child(chunk)
		_free_chunks.append(chunk)
	_sync_chunks(TrainState.distance_m)


func active_chunks() -> Array:
	return _chunks.values()


func _physics_process(_delta: float) -> void:
	ground.constant_linear_velocity = TrainState.ground_velocity()
	_sync_chunks(TrainState.distance_m)


func _process(_delta: float) -> void:
	var distance := TrainState.visual_distance()
	var offset := -fposmod(distance, GROUND_TILE_M) / GROUND_TILE_M
	_snow_material.uv1_offset.y = offset
	_ballast_material.uv1_offset.y = offset
	_sleepers.position.z = fposmod(distance, SLEEPER_SPACING)
	_streak_material.set_shader_parameter(&"scroll", fposmod(distance, 240.0))
	_streak_material.set_shader_parameter(&"stretch", clampf(TrainState.speed_mps * 0.07, 0.02, 2.2))


func _sync_chunks(distance: float) -> void:
	var first := floori((distance - BEHIND_M) / SceneryChunk.LENGTH)
	var last := floori((distance + AHEAD_M) / SceneryChunk.LENGTH)
	for chunk_index: int in _chunks.keys():
		if chunk_index < first or chunk_index > last:
			var old: SceneryChunk = _chunks[chunk_index]
			_chunks.erase(chunk_index)
			old.visible = false
			old.collision_layer = 0
			_free_chunks.append(old)
	for chunk_index in range(first, last + 1):
		if not _chunks.has(chunk_index):
			var chunk: SceneryChunk = _free_chunks.pop_back()
			chunk.populate(chunk_index)
			chunk.teleport_to(distance)
			chunk.visible = true
			_chunks[chunk_index] = chunk
	for chunk: SceneryChunk in _chunks.values():
		chunk.place(distance, COLLIDE_AHEAD_M, COLLIDE_BEHIND_M)


func _build_ground() -> void:
	ground = StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.GROUND
	ground.collision_mask = 0
	var physics := PhysicsMaterial.new()
	physics.friction = 0.75
	physics.bounce = 0.3
	ground.physics_material_override = physics
	add_child(ground)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1800.0, 6.0, 1800.0)
	shape.shape = box
	shape.position = Vector3(0.0, GROUND_Y - 3.0, 0.0)
	ground.add_child(shape)

	_snow_material = StandardMaterial3D.new()
	_snow_material.albedo_texture = _make_snow_texture(Color(0.74, 0.79, 0.9), Color(0.55, 0.62, 0.78), 0.012)
	_snow_material.roughness = 0.9
	_snow_material.uv1_scale = Vector3(1800.0 / GROUND_TILE_M, 1800.0 / GROUND_TILE_M, 1.0)
	var snow := MeshInstance3D.new()
	snow.name = "Snow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800.0, 1800.0)
	plane.material = _snow_material
	snow.mesh = plane
	snow.position.y = GROUND_Y
	add_child(snow)

	_ballast_material = StandardMaterial3D.new()
	_ballast_material.albedo_texture = _make_snow_texture(Color(0.3, 0.3, 0.33), Color(0.17, 0.17, 0.2), 0.05)
	_ballast_material.roughness = 1.0
	_ballast_material.uv1_scale = Vector3(5.0 / GROUND_TILE_M, 1800.0 / GROUND_TILE_M, 1.0)
	var ballast := MeshInstance3D.new()
	ballast.name = "Ballast"
	var strip := PlaneMesh.new()
	strip.size = Vector2(5.0, 1800.0)
	strip.material = _ballast_material
	ballast.mesh = strip
	ballast.position.y = GROUND_Y + 0.02
	add_child(ballast)


func _make_snow_texture(light: Color, dark: Color, speckle: float) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = TrainState.route_seed
	noise.frequency = 0.035
	var source := noise.get_seamless_image(128, 128)
	var image := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrainState.route_seed
	for y in 128:
		for x in 128:
			var color := dark.lerp(light, clampf(source.get_pixel(x, y).r * 1.6 - 0.2, 0.0, 1.0))
			if rng.randf() < speckle:
				color = color.darkened(0.45)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _build_track() -> void:
	var rail_material := MeshBatch.flat(Color(0.34, 0.33, 0.35))
	var batch := MeshBatch.new()
	for side: float in [-1.0, 1.0]:
		batch.add_box(Vector3(0.1, 0.14, 900.0), Vector3(side * 0.78, GROUND_Y + 0.2, -200.0), rail_material)
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = batch.build()
	add_child(rails)

	var sleeper := BoxMesh.new()
	sleeper.size = Vector3(2.5, 0.12, 0.34)
	sleeper.material = MeshBatch.flat(Color(0.2, 0.15, 0.12))
	var count := int(SLEEPER_SPAN_M / SLEEPER_SPACING)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sleeper
	multimesh.instance_count = count
	for i in count:
		var z := -SLEEPER_SPAN_M * 0.5 + i * SLEEPER_SPACING
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, GROUND_Y + 0.08, z)))
	_sleepers = MultiMeshInstance3D.new()
	_sleepers.name = "Sleepers"
	_sleepers.multimesh = multimesh
	# Scrolled at render rate in _process, so it must skip tick interpolation.
	_sleepers.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sleepers.custom_aabb = AABB(Vector3(-5.0, -5.0, -SLEEPER_SPAN_M), Vector3(10.0, 10.0, SLEEPER_SPAN_M * 2.0))
	add_child(_sleepers)


func _build_horizon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TrainState.route_seed
	var batch := MeshBatch.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var rock := MeshBatch.flat(Color(0.2, 0.25, 0.36))
	for i in 46:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(820.0, 1150.0)
		var width := rng.randf_range(120.0, 300.0)
		var height := rng.randf_range(90.0, 230.0)
		var center := Vector3(cos(angle) * radius, GROUND_Y + height * 0.5, sin(angle) * radius)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width))
		batch.add_mesh(cone, Transform3D(basis, center), rock)
	var horizon := MeshInstance3D.new()
	horizon.name = "Horizon"
	horizon.mesh = batch.build()
	add_child(horizon)


## Blowing snow past the windows: one cheap instanced draw call, scrolled in a shader.
func _build_streaks() -> void:
	_streak_material = ShaderMaterial.new()
	_streak_material.shader = load("res://scripts/world/snow_streak.gdshader")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 1.0)
	mesh.material = _streak_material
	var rng := RandomNumberGenerator.new()
	rng.seed = TrainState.route_seed + 1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 420
	for i in multimesh.instance_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * rng.randf_range(2.3, 26.0), rng.randf_range(-1.2, 7.0), rng.randf_range(-120.0, 120.0))
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, spot))
	var streaks := MultiMeshInstance3D.new()
	streaks.name = "SnowStreaks"
	streaks.multimesh = multimesh
	streaks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	streaks.custom_aabb = AABB(Vector3(-30.0, -5.0, -140.0), Vector3(60.0, 20.0, 280.0))
	add_child(streaks)


func _build_shared_resources() -> void:
	var physics := PhysicsMaterial.new()
	physics.friction = 0.5
	physics.bounce = 0.45
	_shared["material"] = physics

	var trunk := CylinderShape3D.new()
	trunk.radius = 0.4
	trunk.height = 4.0
	_shared["trunk_shape"] = trunk
	var boulder := BoxShape3D.new()
	boulder.size = Vector3(1.8, 1.2, 1.8)
	_shared["rock_shape"] = boulder
	var post := BoxShape3D.new()
	post.size = Vector3(0.34, 6.0, 0.34)
	_shared["pole_shape"] = post

	_shared["tree"] = _make_tree_mesh()
	_shared["rock"] = _make_rock_mesh()
	_shared["pole"] = _make_pole_mesh()
	_shared["drift"] = _make_drift_mesh()


func _make_tree_mesh() -> ArrayMesh:
	var batch := MeshBatch.new()
	var bark := MeshBatch.flat(Color(0.2, 0.14, 0.11))
	var needles := MeshBatch.flat(Color(0.1, 0.2, 0.2))
	var frost := MeshBatch.flat(Color(0.8, 0.86, 0.95))
	batch.add_box(Vector3(0.5, 2.0, 0.5), Vector3(0.0, 1.0, 0.0), bark)
	var layers: Array[Array] = [[1.9, 2.4, 2.6], [1.5, 2.2, 4.0], [1.0, 2.0, 5.4]]
	for layer in layers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = layer[0]
		cone.height = layer[1]
		cone.radial_segments = 6
		cone.rings = 1
		batch.add_mesh(cone, Transform3D(Basis.IDENTITY, Vector3(0.0, layer[2], 0.0)), needles)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 0.55
	cap.height = 1.0
	cap.radial_segments = 6
	cap.rings = 1
	batch.add_mesh(cap, Transform3D(Basis.IDENTITY, Vector3(0.0, 6.0, 0.0)), frost)
	return batch.build()


func _make_rock_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 1.5
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = MeshBatch.flat(Color(0.3, 0.32, 0.38))
	return mesh


func _make_pole_mesh() -> ArrayMesh:
	var batch := MeshBatch.new()
	var wood := MeshBatch.flat(Color(0.17, 0.13, 0.1))
	var wire := MeshBatch.flat(Color(0.05, 0.05, 0.06))
	batch.add_box(Vector3(0.24, 6.2, 0.24), Vector3(0.0, 3.1, 0.0), wood)
	batch.add_box(Vector3(1.8, 0.12, 0.12), Vector3(0.0, 5.7, 0.0), wood)
	var span := SceneryChunk.LENGTH / SceneryChunk.POLE_COUNT
	for offset: float in [-0.8, 0.8]:
		batch.add_box(Vector3(0.03, 0.03, span), Vector3(offset, 5.78, -span * 0.5), wire)
	return batch.build()


func _make_drift_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 3
	mesh.material = MeshBatch.flat(Color(0.7, 0.75, 0.87))
	return mesh

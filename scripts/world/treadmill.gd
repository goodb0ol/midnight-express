class_name Treadmill
extends Node3D
## The scrolling wasteland. Nothing here simulates travel: the ground is a static
## conveyor (constant_linear_velocity) and obstacles are pooled kinematic chunks
## placed from TrainState.distance_m. The land you see is low-poly height-field strips
## on those chunks; the flat box below is still what bodies land on near the track.

const GROUND_Y := -1.45
const AHEAD_M := 560.0
const BEHIND_M := 480.0
const COLLIDE_AHEAD_M := 150.0
const COLLIDE_BEHIND_M := 235.0
const GROUND_TILE_M := 18.0
const SLEEPER_SPACING := 2.4
const SLEEPER_SPAN_M := 700.0
const STREAKS_CALM := 420
const STREAKS_STORM := 1000
const STREAK_OPACITY_CALM := 0.22
const STREAK_OPACITY_STORM := 0.5

var ground: StaticBody3D
var route: Route
var weather: Weather
var _chunks: Dictionary = {}  # int -> SceneryChunk
var _free_chunks: Array[SceneryChunk] = []
var _shared: Dictionary = {}
var _set_pieces: Dictionary = {}  # Route.Kind -> SetPiece
var _ballast_material: StandardMaterial3D
var _sleepers: MultiMeshInstance3D
var _streak_material: ShaderMaterial
var _streaks: MultiMesh
var _streak_node: MultiMeshInstance3D
var _lake_ice: MeshInstance3D


func _ready() -> void:
	route = Route.new(TrainState.route_seed)
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
	_build_set_pieces()
	_sync_chunks(TrainState.distance_m)
	_sync_set_pieces(TrainState.distance_m)
	weather = Weather.new()
	weather.name = "Weather"
	weather.route = route
	add_child(weather)


func active_chunks() -> Array:
	return _chunks.values()


func _physics_process(_delta: float) -> void:
	ground.constant_linear_velocity = TrainState.ground_velocity()
	_sync_chunks(TrainState.distance_m)
	_sync_set_pieces(TrainState.distance_m)
	TrainState.in_tunnel = route.in_tunnel(TrainState.distance_m)


func _process(_delta: float) -> void:
	var distance := TrainState.visual_distance()
	var offset := -fposmod(distance, GROUND_TILE_M) / GROUND_TILE_M
	_ballast_material.uv1_offset.y = offset
	_sleepers.position.z = fposmod(distance, SLEEPER_SPACING)
	_streak_material.set_shader_parameter(&"scroll", fposmod(distance, 240.0))
	var storm := TrainState.blizzard
	_streak_material.set_shader_parameter(&"stretch", clampf(TrainState.speed_mps * 0.07, 0.02, 2.2) * (1.0 + storm))
	_streak_material.set_shader_parameter(&"opacity", lerpf(STREAK_OPACITY_CALM, STREAK_OPACITY_STORM, storm))
	_streaks.visible_instance_count = roundi(lerpf(STREAKS_CALM, STREAKS_STORM, storm))
	_streak_node.visible = not TrainState.in_tunnel


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


## One pooled body per landmark kind, picked up when the line reaches one.
func _sync_set_pieces(distance: float) -> void:
	var wanted: Dictionary = {}
	for piece in route.pieces_between(distance - BEHIND_M - 120.0, distance + AHEAD_M + 120.0):
		if _set_pieces.has(piece.kind):
			wanted[piece.kind] = piece
	for kind: int in _set_pieces:
		var node: SetPiece = _set_pieces[kind]
		var piece: Route.Piece = wanted.get(kind)
		if piece == null:
			if node.piece != null:
				node.retire()
			continue
		if node.piece != piece:
			node.assign(piece, distance)
			if kind == Route.Kind.LAKE:
				_fit_lake(piece)
		node.place(distance, COLLIDE_AHEAD_M, COLLIDE_BEHIND_M)


func _fit_lake(piece: Route.Piece) -> void:
	var radius := Vector2(Route.LAKE_RADIUS_X, piece.length_m() * 0.5) * 0.97
	var center := Vector3(absf(route.lake_center_x(piece)), -0.32, 0.0)
	_lake_ice.transform = Transform3D(Basis.from_scale(Vector3(radius.x, 1.0, radius.y)), center)


func _build_set_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([TrainState.route_seed, "landmarks"])
	var physics: PhysicsMaterial = _shared["material"]
	var ground_level := Vector3(0.0, GROUND_Y, 0.0)

	var station := _add_set_piece(Route.Kind.STATION, physics)
	_fill_set_piece(station, SetPieceMeshes.station(Route.SNAP_M * 3.0, rng))
	for z: float in [-36.0, 0.0, 36.0]:
		station.add_lamp(ground_level + Vector3(4.2, 5.2, z), Color(1.0, 0.72, 0.4), 3.2, 26.0)
	var sign_board := Label3D.new()
	sign_board.text = "NOWHERE HALT"
	sign_board.font_size = 96
	sign_board.pixel_size = 0.016
	sign_board.modulate = Color(1.0, 0.86, 0.55)
	sign_board.position = ground_level + Vector3(6.1, 4.2, 0.0)
	sign_board.rotation.y = -PI * 0.5
	sign_board.shaded = false
	sign_board.double_sided = false
	station.add_child(sign_board)

	var wreck := _add_set_piece(Route.Kind.WRECK, physics)
	_fill_set_piece(wreck, SetPieceMeshes.wreck(Route.SNAP_M * 3.0, rng))
	wreck.add_lamp(ground_level + Vector3(18.0, 3.0, 20.0), Color(1.0, 0.42, 0.14), 5.0, 34.0)
	wreck.add_lamp(ground_level + Vector3(24.0, 3.0, -30.0), Color(1.0, 0.42, 0.14), 4.0, 30.0)

	var bones := _add_set_piece(Route.Kind.SKELETON, physics)
	_fill_set_piece(bones, SetPieceMeshes.skeleton(Route.SNAP_M * 4.0, rng))

	var ice_material := StandardMaterial3D.new()
	ice_material.albedo_color = Color(0.3, 0.46, 0.62)
	ice_material.roughness = 0.12
	ice_material.metallic = 0.65
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 28
	disc.rings = 1
	disc.material = ice_material
	var lake := _add_set_piece(Route.Kind.LAKE, physics)
	_lake_ice = lake.add_model(disc)
	lake.position.y = GROUND_Y

	var river_material := ice_material.duplicate() as StandardMaterial3D
	river_material.albedo_color = Color(0.1, 0.16, 0.27)
	var strip := BoxMesh.new()
	strip.size = Vector3(1800.0, 0.02, 80.0)
	strip.material = river_material
	var river := _add_set_piece(Route.Kind.BRIDGE, physics)
	river.add_model(strip).position = Vector3(0.0, GROUND_Y - Route.GORGE_DEPTH + 1.5, 0.0)


func _add_set_piece(kind: Route.Kind, physics: PhysicsMaterial) -> SetPiece:
	var node := SetPiece.new(physics)
	node.name = Route.Kind.keys()[kind].capitalize() + "Piece"
	add_child(node)
	_set_pieces[kind] = node
	return node


func _fill_set_piece(node: SetPiece, built: Dictionary) -> void:
	var ground_level := Vector3(0.0, GROUND_Y, 0.0)
	var model := built["mesh"] as LowPoly
	node.add_model(model.build()).position = ground_level
	for entry: Array in built["boxes"]:
		node.add_box_collider([entry[0], (entry[1] as Vector3) + ground_level, entry[2]])


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
		batch.add_box(Vector3(0.1, 0.14, 1500.0), Vector3(side * 0.78, GROUND_Y + 0.2, 0.0), rail_material)
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
	multimesh.instance_count = STREAKS_STORM
	multimesh.visible_instance_count = STREAKS_CALM
	for i in multimesh.instance_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * rng.randf_range(2.3, 26.0), rng.randf_range(-1.2, 7.0), rng.randf_range(-120.0, 120.0))
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, spot))
	_streaks = multimesh
	_streak_node = MultiMeshInstance3D.new()
	_streak_node.name = "SnowStreaks"
	_streak_node.multimesh = multimesh
	_streak_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_streak_node.custom_aabb = AABB(Vector3(-30.0, -5.0, -140.0), Vector3(60.0, 20.0, 280.0))
	add_child(_streak_node)


func _build_shared_resources() -> void:
	var physics := PhysicsMaterial.new()
	physics.friction = 0.5
	physics.bounce = 0.45
	_shared["material"] = physics
	_shared["route"] = route

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

	var gag_box := BoxShape3D.new()
	gag_box.size = Vector3(1.6, 3.0, 1.6)
	_shared["gag_shape"] = gag_box

	var tunnel_wall := BoxShape3D.new()
	tunnel_wall.size = Vector3(3.0, 12.0, SceneryChunk.LENGTH)
	_shared["tunnel_wall_shape"] = tunnel_wall
	var tunnel_roof := BoxShape3D.new()
	tunnel_roof.size = Vector3(12.0, 2.0, SceneryChunk.LENGTH)
	_shared["tunnel_roof_shape"] = tunnel_roof
	var portal_pier := BoxShape3D.new()
	portal_pier.size = Vector3(22.0, 16.0, 2.4)
	_shared["portal_pier_shape"] = portal_pier

	var section_rng := RandomNumberGenerator.new()
	section_rng.seed = hash([TrainState.route_seed, "sections"])
	var bore := SetPieceMeshes.tunnel_section(SceneryChunk.LENGTH).build()
	var portal := SetPieceMeshes.tunnel_portal(section_rng).build()
	_shared["sections"] = {
		"tunnel": _section_mesh([bore], [0.0]),
		"tunnel_entry": _section_mesh([bore, portal], [0.0, 0.0]),
		"tunnel_exit": _section_mesh([bore, portal], [0.0, -SceneryChunk.LENGTH]),
		"bridge": _section_mesh([SetPieceMeshes.bridge_section(SceneryChunk.LENGTH).build()], [0.0]),
	}
	_shared["pine"] = SetPieceMeshes.pine().build()

	_shared["tree"] = Models.mesh("scenery/tree_a")
	_shared["dead_tree"] = Models.mesh("scenery/tree_b")
	_shared["rock"] = Models.mesh("scenery/rock")
	_shared["pole"] = Models.mesh("scenery/pole")
	_shared["drift"] = Models.mesh("scenery/drift")
	_shared["gags"] = [
		Models.mesh("scenery/gag_sign_a"), Models.mesh("scenery/gag_sign_b"),
		Models.mesh("scenery/gag_snowman"), Models.mesh("scenery/gag_outhouse"),
	]


## Copies meshes authored with y = 0 at ground level into one mesh at world height, each
## moved along the chunk by its entry in [param shifts].
func _section_mesh(parts: Array, shifts: Array) -> ArrayMesh:
	var merged := ArrayMesh.new()
	for part_index in parts.size():
		var part: ArrayMesh = parts[part_index]
		var shift := Vector3(0.0, GROUND_Y, shifts[part_index])
		for surface in part.get_surface_count():
			var arrays := part.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] += shift
			arrays[Mesh.ARRAY_VERTEX] = verts
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			merged.surface_set_material(merged.get_surface_count() - 1, part.surface_get_material(surface))
	return merged

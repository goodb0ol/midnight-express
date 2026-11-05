class_name TrainCar
extends Node3D
## One graybox carriage, built from a spec dictionary so later modular cars
## (casino, greenhouse...) are one more entry in Train.CAR_SPECS.
## Local origin: floor level at the centre of the car. +Z points to the rear.

const HALF_WIDTH := 1.9
const WALL := 0.2
const HEIGHT := 2.7
const FLOOR_THICKNESS := 0.25
const DOOR_WIDTH := 1.4
const DOOR_HEIGHT := 2.2
const WINDOW_WIDTH := 1.5
const WINDOW_SILL := 0.85
const WINDOW_TOP := 1.95
const PASSAGE_WIDTH := 1.3
const PASSAGE_HEIGHT := 2.2
const PANEL_THICKNESS := 0.08
## Render layer of interior surfaces. The moon skips it (see Main), so the lamps alone
## light the cabin and thin walls can't show shadow acne.
const INTERIOR_RENDER_LAYER := 1 << 1

var spec: Dictionary
var length := 18.0
var openings: Array[TrainOpening] = []

var _body: StaticBody3D
var _batch: MeshBatch
var _interior: MeshBatch
var _hull_material: Material
var _liner_material: Material
var _trim_material: Material
var _door_material: Material
var _glass_material: Material


func build(car_spec: Dictionary, has_car_ahead: bool, has_car_behind: bool) -> void:
	spec = car_spec
	length = spec["length"]
	name = String(spec["id"])
	_hull_material = MeshBatch.flat(spec["hull"])
	_liner_material = MeshBatch.flat(spec["liner"])
	_trim_material = MeshBatch.flat(Color(0.16, 0.14, 0.13))
	_door_material = MeshBatch.flat(Color(0.32, 0.27, 0.22))
	_glass_material = MeshBatch.flat(Color(0.65, 0.8, 0.95, 0.28))
	_batch = MeshBatch.new()
	_interior = MeshBatch.new()

	_body = StaticBody3D.new()
	_body.name = "Shell"
	_body.collision_layer = Layers.HULL
	_body.collision_mask = 0
	add_child(_body)

	_solid(Vector3(HALF_WIDTH * 2.0, FLOOR_THICKNESS, length), Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0), _trim_material)
	_solid(Vector3(HALF_WIDTH * 2.0, 0.2, length), Vector3(0.0, HEIGHT + 0.1, 0.0), _hull_material)
	_inner(Vector3(HALF_WIDTH * 2.0 - WALL * 2.0, 0.02, length), Vector3(0.0, HEIGHT - 0.01, 0.0), _liner_material)
	_inner(Vector3(HALF_WIDTH * 2.0 - WALL * 2.0, 0.02, length), Vector3(0.0, 0.01, 0.0), MeshBatch.flat(spec["carpet"]))
	_build_side(-1.0)
	_build_side(1.0)
	_build_end(-1.0, has_car_ahead)
	_build_end(1.0, true)
	if not has_car_behind:
		_add_rear_door()
	_build_bogies()

	match spec["layout"]:
		&"locomotive":
			_furnish_locomotive()
		&"bistro":
			_furnish_bistro()
		&"coach":
			_furnish_coach()

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _batch.build()
	add_child(mesh)
	var interior := MeshInstance3D.new()
	interior.name = "Interior"
	interior.mesh = _interior.build()
	interior.layers = INTERIOR_RENDER_LAYER
	interior.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(interior)
	_add_lights()


func _solid(size: Vector3, center: Vector3, material: Material) -> void:
	_visual(size, center, material)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	_body.add_child(shape)


func _visual(size: Vector3, center: Vector3, material: Material) -> void:
	_batch.add_box(size, center, material)


func _inner(size: Vector3, center: Vector3, material: Material) -> void:
	_interior.add_box(size, center, material)


## Solid furniture: collides like the shell, renders with the interior.
func _furniture(size: Vector3, center: Vector3, material: Material) -> void:
	_inner(size, center, material)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	_body.add_child(shape)


func _build_side(side: float) -> void:
	var cuts: Array[Dictionary] = []
	for z: float in spec["doors"]:
		cuts.append({"z": z, "half": DOOR_WIDTH * 0.5, "bottom": 0.0, "top": DOOR_HEIGHT, "kind": TrainOpening.Kind.DOOR})
	for z: float in spec["windows"]:
		cuts.append({"z": z, "half": WINDOW_WIDTH * 0.5, "bottom": WINDOW_SILL, "top": WINDOW_TOP, "kind": TrainOpening.Kind.WINDOW})
	cuts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["z"] < b["z"])

	var cursor := -length * 0.5
	for cut in cuts:
		var z: float = cut["z"]
		var half: float = cut["half"]
		var bottom: float = cut["bottom"]
		var top: float = cut["top"]
		_wall_span(side, cursor, z - half, 0.0, HEIGHT)
		if bottom > 0.0:
			_wall_span(side, z - half, z + half, 0.0, bottom)
		_wall_span(side, z - half, z + half, top, HEIGHT)
		cursor = z + half
		_add_side_opening(side, cut)
	_wall_span(side, cursor, length * 0.5, 0.0, HEIGHT)


func _wall_span(side: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var size := Vector3(WALL, y1 - y0, z1 - z0)
	var center := Vector3(side * (HALF_WIDTH - WALL * 0.5), (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	_solid(size, center, _hull_material)
	var liner := Vector3(0.02, size.y, size.z)
	_inner(liner, Vector3(side * (HALF_WIDTH - WALL - 0.01), center.y, center.z), _liner_material)


func _add_side_opening(side: float, cut: Dictionary) -> void:
	var opening := TrainOpening.new()
	var kind: TrainOpening.Kind = cut["kind"]
	var z: float = cut["z"]
	var half: float = cut["half"]
	var bottom: float = cut["bottom"]
	var top: float = cut["top"]
	var size := Vector3(PANEL_THICKNESS, top - bottom, half * 2.0)
	opening.name = "%s_%s_%d" % ["Door" if kind == TrainOpening.Kind.DOOR else "Window", "L" if side < 0.0 else "R", roundi(z * 10.0)]
	opening.position = Vector3(side * (HALF_WIDTH - WALL * 0.5), (bottom + top) * 0.5, z)
	add_child(opening)
	if kind == TrainOpening.Kind.DOOR:
		opening.setup(kind, size, Vector3(0.0, 0.0, half * 2.0 - 0.05), _door_material)
	else:
		opening.setup(kind, size, Vector3(0.0, -(top - bottom) + 0.06, 0.0), _glass_material)
	openings.append(opening)


func _build_end(z_sign: float, with_passage: bool) -> void:
	var z := z_sign * (length * 0.5 - WALL * 0.5)
	if not with_passage:
		_solid(Vector3(HALF_WIDTH * 2.0, HEIGHT, WALL), Vector3(0.0, HEIGHT * 0.5, z), _hull_material)
		_inner(Vector3(HALF_WIDTH * 2.0, HEIGHT, 0.02), Vector3(0.0, HEIGHT * 0.5, z - z_sign * (WALL * 0.5 + 0.01)), _liner_material)
		return
	var side_width := HALF_WIDTH - PASSAGE_WIDTH * 0.5
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * (PASSAGE_WIDTH * 0.5 + side_width * 0.5), HEIGHT * 0.5, z)
		_solid(Vector3(side_width, HEIGHT, WALL), center, _hull_material)
		_inner(Vector3(side_width, HEIGHT, 0.02), center - Vector3(0.0, 0.0, z_sign * (WALL * 0.5 + 0.01)), _liner_material)
	var header_height := HEIGHT - PASSAGE_HEIGHT
	_solid(Vector3(PASSAGE_WIDTH, header_height, WALL), Vector3(0.0, HEIGHT - header_height * 0.5, z), _hull_material)


func _add_rear_door() -> void:
	var opening := TrainOpening.new()
	opening.name = "Door_Rear"
	var z := length * 0.5 - WALL * 0.5
	opening.position = Vector3(0.0, PASSAGE_HEIGHT * 0.5, z)
	add_child(opening)
	opening.setup(TrainOpening.Kind.DOOR, Vector3(PASSAGE_WIDTH, PASSAGE_HEIGHT, PANEL_THICKNESS), Vector3(PASSAGE_WIDTH - 0.05, 0.0, 0.0), _door_material)
	openings.append(opening)


func _build_bogies() -> void:
	var wheel_material := MeshBatch.flat(Color(0.09, 0.09, 0.1))
	for z: float in [-length * 0.33, length * 0.33]:
		_visual(Vector3(2.2, 0.6, 2.8), Vector3(0.0, -0.6, z), wheel_material)
		for offset: float in [-0.8, 0.8]:
			for side: float in [-1.0, 1.0]:
				_visual(Vector3(0.12, 0.8, 0.8), Vector3(side * 0.82, -0.95, z + offset), wheel_material)


func _add_lights() -> void:
	for z: float in [-length * 0.25, length * 0.25]:
		var light := OmniLight3D.new()
		light.position = Vector3(0.0, HEIGHT - 0.3, z)
		light.omni_range = 8.5
		light.light_color = spec["lamp"]
		light.light_energy = 1.6
		light.omni_attenuation = 0.8
		add_child(light)
		_inner(Vector3(0.5, 0.06, 0.5), Vector3(0.0, HEIGHT - 0.04, z), MeshBatch.flat(spec["lamp"], 2.0))


func _furnish_locomotive() -> void:
	var iron := MeshBatch.flat(Color(0.2, 0.2, 0.22))
	var coal_bin := MeshBatch.flat(Color(0.24, 0.17, 0.12))
	_furniture(Vector3(2.4, 2.1, 4.5), Vector3(0.0, 1.05, -6.6), iron)
	_inner(Vector3(0.9, 0.7, 0.04), Vector3(0.0, 0.8, -4.33), MeshBatch.flat(Color(1.0, 0.42, 0.1), 2.5))
	_furniture(Vector3(1.3, 0.6, 0.12), Vector3(1.05, 0.3, 3.0), coal_bin)
	_furniture(Vector3(1.3, 0.6, 0.12), Vector3(1.05, 0.3, 7.0), coal_bin)
	_furniture(Vector3(0.12, 0.6, 4.0), Vector3(0.46, 0.3, 5.0), coal_bin)


func _furnish_bistro() -> void:
	var wood := MeshBatch.flat(Color(0.42, 0.28, 0.17))
	var cushion := MeshBatch.flat(Color(0.5, 0.2, 0.18))
	# Service counter across the galley end.
	_furniture(Vector3(1.1, 1.0, 0.6), Vector3(1.15, 0.5, 0.2), wood)
	for z: float in [-6.5, 4.5]:
		for side: float in [-1.0, 1.0]:
			_table(side, z, wood, cushion)


func _table(side: float, z: float, wood: Material, cushion: Material) -> void:
	var x := side * 1.28
	_furniture(Vector3(0.8, 0.06, 1.0), Vector3(x, 0.75, z), wood)
	_furniture(Vector3(0.12, 0.72, 0.12), Vector3(x, 0.36, z), wood)
	for offset: float in [-0.85, 0.85]:
		_furniture(Vector3(0.8, 0.45, 0.45), Vector3(x, 0.225, z + offset), cushion)


func _furnish_coach() -> void:
	var cushion := MeshBatch.flat(Color(0.2, 0.28, 0.42))
	for z: float in [-7.0, -5.0, 3.0, 5.0, 7.0]:
		for side: float in [-1.0, 1.0]:
			var x := side * 1.22
			_furniture(Vector3(0.95, 0.45, 0.5), Vector3(x, 0.225, z), cushion)
			_furniture(Vector3(0.95, 1.0, 0.1), Vector3(x, 0.5, z + 0.3), cushion)

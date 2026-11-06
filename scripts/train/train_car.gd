class_name TrainCar
extends Node3D
## One carriage, from a spec dictionary so later modular cars (casino, greenhouse...)
## are one more entry in Train. Visuals come from Blender; the collision below stays
## code-built so it can't drift from the gameplay numbers.
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


func build(car_spec: Dictionary, has_car_ahead: bool, has_car_behind: bool) -> void:
	spec = car_spec
	length = spec["length"]
	name = String(spec["id"])

	_body = StaticBody3D.new()
	_body.name = "Shell"
	_body.collision_layer = Layers.HULL
	_body.collision_mask = 0
	add_child(_body)

	_solid(Vector3(HALF_WIDTH * 2.0, FLOOR_THICKNESS, length), Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0))
	_solid(Vector3(HALF_WIDTH * 2.0, 0.2, length), Vector3(0.0, HEIGHT + 0.1, 0.0))
	_build_side(-1.0)
	_build_side(1.0)
	_build_end(-1.0, has_car_ahead)
	_build_end(1.0, true)
	if not has_car_behind:
		_add_rear_door()

	match spec["layout"]:
		&"locomotive":
			_furnish_locomotive()
		&"bistro":
			_furnish_bistro()
		&"coach":
			_furnish_coach()

	var model: String = "train/" + String(spec["model"])
	Models.place(self, model, "Exterior", Vector3.ZERO).name = "Exterior"
	_interior_piece(model, "Interior", Vector3.ZERO).name = "Interior"
	_add_lights()


func _solid(size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	_body.add_child(shape)


## Cabin mesh: lit by the lamps only, and casts no shadow.
func _interior_piece(file: String, object: String, at: Vector3) -> MeshInstance3D:
	var piece := Models.place(self, file, object, at)
	piece.layers = INTERIOR_RENDER_LAYER
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return piece


func _furniture(file: String, at: Vector3) -> void:
	_interior_piece("furniture/" + file, "", at)


func _build_side(side: float) -> void:
	var cuts: Array[Dictionary] = []
	for z: float in spec["doors"]:
		cuts.append({"z": z, "half": DOOR_WIDTH * 0.5, "bottom": 0.0, "top": DOOR_HEIGHT, "kind": TrainOpening.Kind.DOOR})
	for z: float in spec["windows"]:
		cuts.append({"z": z, "half": WINDOW_WIDTH * 0.5, "bottom": WINDOW_SILL, "top": WINDOW_TOP, "kind": TrainOpening.Kind.WINDOW,
			"jammed": not spec["working_windows"].has(z)})
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
	_solid(size, Vector3(side * (HALF_WIDTH - WALL * 0.5), (y0 + y1) * 0.5, (z0 + z1) * 0.5))


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
		opening.setup(kind, size, Vector3(0.0, 0.0, half * 2.0 - 0.05), "train/door_panel")
	else:
		opening.setup(kind, size, Vector3(0.0, -(top - bottom) + 0.06, 0.0), "train/window_panel")
	if cut.get("jammed", false):
		opening.jam()
	else:
		openings.append(opening)


func _build_end(z_sign: float, with_passage: bool) -> void:
	var z := z_sign * (length * 0.5 - WALL * 0.5)
	if not with_passage:
		_solid(Vector3(HALF_WIDTH * 2.0, HEIGHT, WALL), Vector3(0.0, HEIGHT * 0.5, z))
		return
	var side_width := HALF_WIDTH - PASSAGE_WIDTH * 0.5
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side_width, HEIGHT, WALL), Vector3(side * (PASSAGE_WIDTH * 0.5 + side_width * 0.5), HEIGHT * 0.5, z))
	var header_height := HEIGHT - PASSAGE_HEIGHT
	_solid(Vector3(PASSAGE_WIDTH, header_height, WALL), Vector3(0.0, HEIGHT - header_height * 0.5, z))


func _add_rear_door() -> void:
	var opening := TrainOpening.new()
	opening.name = "Door_Rear"
	var z := length * 0.5 - WALL * 0.5
	opening.position = Vector3(0.0, PASSAGE_HEIGHT * 0.5, z)
	add_child(opening)
	opening.setup(TrainOpening.Kind.DOOR, Vector3(PASSAGE_WIDTH, PASSAGE_HEIGHT, PANEL_THICKNESS), Vector3(PASSAGE_WIDTH - 0.05, 0.0, 0.0), "train/rear_door_panel")
	openings.append(opening)


func _add_lights() -> void:
	for z: float in [-length * 0.25, length * 0.25]:
		var light := OmniLight3D.new()
		light.position = Vector3(0.0, HEIGHT - 0.3, z)
		light.omni_range = 8.5
		light.light_color = spec["lamp"]
		light.light_energy = 1.6
		light.omni_attenuation = 0.8
		add_child(light)
		_furniture("ceiling_lamp", Vector3(0.0, HEIGHT, z))


func _furnish_locomotive() -> void:
	_solid(Vector3(2.4, 2.1, 4.5), Vector3(0.0, 1.05, -6.6))
	# Plug the 0.5 m slots beside the boiler: a player can't fit, so a body landing in one
	# could never be reached and its raid could never be cleared. Stops short of the -4.0 window.
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(0.5, 2.1, 4.05), Vector3(side * 1.45, 1.05, -6.775))
	_furniture("boiler", Vector3(0.0, 0.0, -6.6))
	_solid(Vector3(1.3, 0.6, 0.12), Vector3(1.05, 0.3, 3.0))
	_solid(Vector3(1.3, 0.6, 0.12), Vector3(1.05, 0.3, 7.0))
	_solid(Vector3(0.12, 0.6, 4.0), Vector3(0.46, 0.3, 5.0))
	_furniture("coal_bin", Vector3(1.05, 0.0, 5.0))


func _furnish_bistro() -> void:
	# Service counter across the galley end.
	_solid(Vector3(1.1, 1.0, 0.6), Vector3(1.15, 0.5, 0.2))
	_furniture("counter", Vector3(1.15, 0.0, 0.2))
	for z: float in [-6.5, 4.5]:
		for side: float in [-1.0, 1.0]:
			_table(side, z)


func _table(side: float, z: float) -> void:
	var x := side * 1.28
	_solid(Vector3(0.8, 0.06, 1.0), Vector3(x, 0.75, z))
	_solid(Vector3(0.12, 0.72, 0.12), Vector3(x, 0.36, z))
	_furniture("table", Vector3(x, 0.0, z))
	for offset: float in [-0.85, 0.85]:
		_solid(Vector3(0.8, 0.45, 0.45), Vector3(x, 0.225, z + offset))
		_furniture("booth_seat", Vector3(x, 0.0, z + offset))


func _furnish_coach() -> void:
	for z: float in [-7.0, -5.0, 3.0, 5.0, 7.0]:
		for side: float in [-1.0, 1.0]:
			var x := side * 1.22
			_solid(Vector3(0.95, 0.45, 0.5), Vector3(x, 0.225, z))
			_solid(Vector3(0.95, 1.0, 0.1), Vector3(x, 0.5, z + 0.3))
			_furniture("coach_seat", Vector3(x, 0.0, z))

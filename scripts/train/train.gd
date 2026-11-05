class_name Train
extends Node3D
## The stationary train at world origin. Cars run along Z with the locomotive at -Z
## (the direction of travel) and the rear platform at +Z.

const GAP := 1.2
const PLATFORM_DEPTH := 2.4
const CAR_LENGTH := 18.0

## Same opening layout for every car in Milestone 1; each spec can diverge later.
const DOORS: Array[float] = [-1.0]
const WINDOWS: Array[float] = [-6.5, -4.0, 2.0, 4.5, 7.0]

var cars: Array[TrainCar] = []
## Everything inside this box is aboard; anything whose anchor leaves it has left the train.
var hull := AABB()
var exterior_zone: ExteriorZone
var rope: RescueRope


func _ready() -> void:
	var specs: Array[Dictionary] = [
		{"id": &"Locomotive", "layout": &"locomotive", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS,
			"hull": Color(0.2, 0.26, 0.24), "liner": Color(0.42, 0.42, 0.4), "carpet": Color(0.2, 0.19, 0.18), "lamp": Color(1.0, 0.72, 0.45)},
		{"id": &"Bistro", "layout": &"bistro", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS,
			"hull": Color(0.46, 0.15, 0.13), "liner": Color(0.72, 0.62, 0.5), "carpet": Color(0.36, 0.13, 0.13), "lamp": Color(1.0, 0.85, 0.6)},
		{"id": &"Coach", "layout": &"coach", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS,
			"hull": Color(0.15, 0.22, 0.38), "liner": Color(0.58, 0.6, 0.62), "carpet": Color(0.15, 0.2, 0.3), "lamp": Color(0.95, 0.9, 0.75)},
	]
	_build_cars(specs)
	_build_nose()
	_build_platform()
	_compute_hull()

	exterior_zone = ExteriorZone.new()
	exterior_zone.name = "ExteriorZone"
	add_child(exterior_zone)
	exterior_zone.fit_to(hull)

	rope = RescueRope.new()
	rope.name = "RescueRope"
	add_child(rope)
	rope.setup(rear_z())


func rear_z() -> float:
	return cars.back().position.z + cars.back().length * 0.5 + PLATFORM_DEPTH


func front_z() -> float:
	return cars.front().position.z - cars.front().length * 0.5


## Stable, ordered list of everything that can be opened.
func openings() -> Array[TrainOpening]:
	var result: Array[TrainOpening] = []
	for car in cars:
		result.append_array(car.openings)
	return result


## Open holes in the shell. Milestone 2's cabin temperature reads this.
func open_opening_count() -> int:
	var count := 0
	for opening in openings():
		if opening.is_open:
			count += 1
	return count


func car_by_id(id: StringName) -> TrainCar:
	for car in cars:
		if car.spec["id"] == id:
			return car
	return null


func _build_cars(specs: Array[Dictionary]) -> void:
	var total := 0.0
	for spec in specs:
		var car_length: float = spec["length"]
		total += car_length
	total += GAP * (specs.size() - 1)
	var cursor := -total * 0.5
	for i in specs.size():
		var car := TrainCar.new()
		var car_length: float = specs[i]["length"]
		car.position.z = cursor + car_length * 0.5
		add_child(car)
		car.build(specs[i], i > 0, i < specs.size() - 1)
		cars.append(car)
		cursor += car_length
		if i < specs.size() - 1:
			_build_gangway(cursor + GAP * 0.5)
			cursor += GAP


func _build_gangway(z: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Gangway"
	body.collision_layer = Layers.HULL
	body.collision_mask = 0
	body.position.z = z
	add_child(body)
	var batch := MeshBatch.new()
	var material := MeshBatch.flat(Color(0.16, 0.14, 0.13))
	var half := TrainCar.PASSAGE_WIDTH * 0.5 + 0.12
	var pieces: Array[Array] = [
		[Vector3(half * 2.0, TrainCar.FLOOR_THICKNESS, GAP + 0.1), Vector3(0.0, -TrainCar.FLOOR_THICKNESS * 0.5, 0.0)],
		[Vector3(half * 2.0, 0.1, GAP + 0.1), Vector3(0.0, TrainCar.PASSAGE_HEIGHT + 0.05, 0.0)],
		[Vector3(0.1, TrainCar.PASSAGE_HEIGHT, GAP + 0.1), Vector3(-half, TrainCar.PASSAGE_HEIGHT * 0.5, 0.0)],
		[Vector3(0.1, TrainCar.PASSAGE_HEIGHT, GAP + 0.1), Vector3(half, TrainCar.PASSAGE_HEIGHT * 0.5, 0.0)],
	]
	for piece in pieces:
		var size: Vector3 = piece[0]
		var center: Vector3 = piece[1]
		batch.add_box(size, center, material)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = center
		body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = batch.build()
	body.add_child(mesh)


func _build_nose() -> void:
	var batch := MeshBatch.new()
	var iron := MeshBatch.flat(Color(0.13, 0.15, 0.15))
	var brass := MeshBatch.flat(Color(0.62, 0.46, 0.2))
	var front := front_z()
	var boiler := CylinderMesh.new()
	boiler.top_radius = 1.25
	boiler.bottom_radius = 1.25
	boiler.height = 7.0
	boiler.radial_segments = 10
	batch.add_mesh(boiler, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.0, front - 3.5)), iron)
	var funnel := CylinderMesh.new()
	funnel.top_radius = 0.55
	funnel.bottom_radius = 0.32
	funnel.height = 1.6
	funnel.radial_segments = 8
	batch.add_mesh(funnel, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.8, front - 5.5)), iron)
	batch.add_box(Vector3(2.9, 0.3, 8.0), Vector3(0.0, -0.3, front - 3.8), iron)
	batch.add_box(Vector3(2.6, 0.9, 0.3), Vector3(0.0, -0.5, front - 7.9), brass)
	var mesh := MeshInstance3D.new()
	mesh.name = "Nose"
	mesh.mesh = batch.build()
	add_child(mesh)


func _build_platform() -> void:
	var body := StaticBody3D.new()
	body.name = "RearPlatform"
	body.collision_layer = Layers.HULL
	body.collision_mask = 0
	add_child(body)
	var rear_wall: float = cars.back().position.z + cars.back().length * 0.5
	var batch := MeshBatch.new()
	var steel := MeshBatch.flat(Color(0.2, 0.19, 0.18))
	var half := TrainCar.HALF_WIDTH
	var end := rear_wall + PLATFORM_DEPTH
	var pieces: Array[Array] = [
		[Vector3(half * 2.0, TrainCar.FLOOR_THICKNESS, PLATFORM_DEPTH), Vector3(0.0, -TrainCar.FLOOR_THICKNESS * 0.5, rear_wall + PLATFORM_DEPTH * 0.5)],
		[Vector3(0.08, 0.08, PLATFORM_DEPTH), Vector3(-half + 0.04, 1.0, rear_wall + PLATFORM_DEPTH * 0.5)],
		[Vector3(0.08, 0.08, PLATFORM_DEPTH), Vector3(half - 0.04, 1.0, rear_wall + PLATFORM_DEPTH * 0.5)],
		[Vector3(half * 2.0, 0.08, 0.08), Vector3(0.0, 1.0, end - 0.04)],
		[Vector3(0.08, 1.0, 0.08), Vector3(-half + 0.04, 0.5, end - 0.04)],
		[Vector3(0.08, 1.0, 0.08), Vector3(half - 0.04, 0.5, end - 0.04)],
	]
	for piece in pieces:
		var size: Vector3 = piece[0]
		var center: Vector3 = piece[1]
		batch.add_box(size, center, steel)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = center
		body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = batch.build()
	body.add_child(mesh)


func _compute_hull() -> void:
	var half := TrainCar.HALF_WIDTH
	var front := front_z()
	var rear := rear_z()
	hull = AABB(Vector3(-half, -0.6, front), Vector3(half * 2.0, TrainCar.HEIGHT + 1.2, rear - front))

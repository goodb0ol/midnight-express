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
## The rest are rusted shut, so a body has to be carried to a way out. How much carrying a
## raid takes hangs on this list more than on any speed.
const WORKING_WINDOWS: Array[float] = [-4.0, 4.5]

var cars: Array[TrainCar] = []
## Everything inside this box is aboard; anything whose anchor leaves it has left the train.
var hull := AABB()
var exterior_zone: ExteriorZone
var rope: RescueRope


func _ready() -> void:
	var specs: Array[Dictionary] = [
		{"id": &"Locomotive", "layout": &"locomotive", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS, "working_windows": WORKING_WINDOWS,
			"model": &"car_locomotive", "lamp": Color(1.0, 0.72, 0.45)},
		{"id": &"Bistro", "layout": &"bistro", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS, "working_windows": WORKING_WINDOWS,
			"model": &"car_bistro", "lamp": Color(1.0, 0.85, 0.6)},
		{"id": &"Coach", "layout": &"coach", "length": CAR_LENGTH, "doors": DOORS, "windows": WINDOWS, "working_windows": WORKING_WINDOWS,
			"model": &"car_coach", "lamp": Color(0.95, 0.9, 0.75)},
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


## A new raid starts sealed, so a retry is no easier than the first try.
func close_all_openings() -> void:
	for opening in openings():
		opening.set_open(false)


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
	var half := TrainCar.PASSAGE_WIDTH * 0.5 + 0.12
	_add_box(body, Vector3(half * 2.0, TrainCar.FLOOR_THICKNESS, GAP + 0.1), Vector3(0.0, -TrainCar.FLOOR_THICKNESS * 0.5, 0.0))
	_add_box(body, Vector3(half * 2.0, 0.1, GAP + 0.1), Vector3(0.0, TrainCar.PASSAGE_HEIGHT + 0.05, 0.0))
	_add_box(body, Vector3(0.1, TrainCar.PASSAGE_HEIGHT, GAP + 0.1), Vector3(-half, TrainCar.PASSAGE_HEIGHT * 0.5, 0.0))
	_add_box(body, Vector3(0.1, TrainCar.PASSAGE_HEIGHT, GAP + 0.1), Vector3(half, TrainCar.PASSAGE_HEIGHT * 0.5, 0.0))
	Models.place(body, "train/gangway", "Gangway", Vector3.ZERO)


func _build_nose() -> void:
	Models.place(self, "train/nose", "Nose", Vector3(0.0, 0.0, front_z())).name = "Nose"


func _build_platform() -> void:
	var body := StaticBody3D.new()
	body.name = "RearPlatform"
	body.collision_layer = Layers.HULL
	body.collision_mask = 0
	add_child(body)
	var rear_wall: float = cars.back().position.z + cars.back().length * 0.5
	var half := TrainCar.HALF_WIDTH
	var end := rear_wall + PLATFORM_DEPTH
	var middle := rear_wall + PLATFORM_DEPTH * 0.5
	_add_box(body, Vector3(half * 2.0, TrainCar.FLOOR_THICKNESS, PLATFORM_DEPTH), Vector3(0.0, -TrainCar.FLOOR_THICKNESS * 0.5, middle))
	_add_box(body, Vector3(0.08, 0.08, PLATFORM_DEPTH), Vector3(-half + 0.04, 1.0, middle))
	_add_box(body, Vector3(0.08, 0.08, PLATFORM_DEPTH), Vector3(half - 0.04, 1.0, middle))
	_add_box(body, Vector3(half * 2.0, 0.08, 0.08), Vector3(0.0, 1.0, end - 0.04))
	_add_box(body, Vector3(0.08, 1.0, 0.08), Vector3(-half + 0.04, 0.5, end - 0.04))
	_add_box(body, Vector3(0.08, 1.0, 0.08), Vector3(half - 0.04, 0.5, end - 0.04))
	Models.place(body, "train/rear_platform", "Platform", Vector3(0.0, 0.0, rear_wall))


func _add_box(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)


func _compute_hull() -> void:
	var half := TrainCar.HALF_WIDTH
	var front := front_z()
	var rear := rear_z()
	hull = AABB(Vector3(-half, -0.6, front), Vector3(half * 2.0, TrainCar.HEIGHT + 1.2, rear - front))

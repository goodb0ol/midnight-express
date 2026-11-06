extends RefCounted
## Pins the art contract in docs/ART_BRIEF.md: file and object names code loads, sizes that
## must match collision, the baked lamp light, and the restrained colour budget.

var t: Node

const PASSENGERS := ["gran", "baron", "smuggler", "intern", "stoker", "opera"]
const PARTS := ["pelvis", "chest", "head", "head_ko", "upper_arm_l", "forearm_l", "upper_arm_r",
	"forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r"]
const SINGLE := {
	"train/gangway": "Gangway", "train/rear_platform": "Platform", "train/nose": "Nose",
	"train/door_panel": "Panel", "train/rear_door_panel": "Panel",
	"furniture/boiler": "Boiler", "furniture/coal_bin": "CoalBin", "furniture/counter": "Counter",
	"furniture/table": "Table", "furniture/booth_seat": "BoothSeat", "furniture/coach_seat": "CoachSeat",
	"furniture/ceiling_lamp": "Lamp",
}
const CARS := ["train/car_locomotive", "train/car_bistro", "train/car_coach"]


func _colour_of(surface_material: Material) -> Color:
	return (surface_material as BaseMaterial3D).albedo_color


func test_art_every_object_code_loads_exists() -> bool:
	for file: String in SINGLE:
		t.check(Models.all(file).has(SINGLE[file]), "%s holds %s" % [file, SINGLE[file]])
	for file: String in CARS:
		t.check(Models.all(file).has("Exterior") and Models.all(file).has("Interior"), file + " has both shells")
	var window := Models.all("train/window_panel")
	t.check(window.has("Frame") and window.has("Glass"), "window panel has frame and glass")
	for passenger: String in PASSENGERS:
		var meshes := Models.all("passengers/" + passenger)
		for part: String in PARTS:
			t.check(meshes.has(part), "%s has %s" % [passenger, part])
	return true


func test_art_car_shell_keeps_the_collision_size() -> bool:
	for file: String in CARS:
		var box: AABB = Models.mesh(file, "Interior").get_aabb()
		t.check(absf(box.size.z - 18.0) < 0.6, file + " interior spans the car")
		t.check(box.position.y > -0.15 and box.end.y < 2.95, file + " interior stays in the cabin height")
		t.check(absf(box.position.x) < 1.95 and box.end.x < 1.95, file + " interior stays inside the hull")
	return true


func test_art_cabins_hold_baked_lamp_pools() -> bool:
	for file: String in CARS:
		var mesh: ArrayMesh = Models.mesh(file, "Interior")
		var darkest := 9.0
		var brightest := 0.0
		for surface in mesh.get_surface_count():
			var colours: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			t.check(colours.size() > 0, "%s surface %d has baked light" % [file, surface])
			for colour in colours:
				darkest = minf(darkest, colour.get_luminance())
				brightest = maxf(brightest, colour.get_luminance())
		t.check(darkest < 0.3, file + " has dark corners")
		t.check(brightest > darkest * 2.5, file + " has a pool brighter than its corners")
	return true


func test_art_palette_is_dark_and_restrained() -> bool:
	# Cabin walls must never come back as a sticker sheet: few materials, none of them loud.
	for file: String in CARS:
		var mesh: ArrayMesh = Models.mesh(file, "Interior")
		t.check(mesh.get_surface_count() <= 22, "%s uses %d materials" % [file, mesh.get_surface_count()])
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material.emission_enabled:
				continue
			var colour := material.albedo_color
			var loud := colour.s > 0.75 and colour.get_luminance() > 0.45
			t.check(not loud, "%s has no loud colour, got %s" % [file, colour])
	return true


func test_art_passengers_keep_to_a_few_colours() -> bool:
	for passenger: String in PASSENGERS:
		var colours := {}
		var meshes := Models.all("passengers/" + passenger)
		for part: String in PARTS:
			var mesh: Mesh = meshes[part]
			for surface in mesh.get_surface_count():
				colours[_colour_of(mesh.surface_get_material(surface)).to_html()] = true
		t.check(colours.size() <= 17, "%s uses %d colours" % [passenger, colours.size()])
	return true


func test_art_lamp_and_furnace_glow() -> bool:
	var lit := false
	var mesh: Mesh = Models.mesh("furniture/ceiling_lamp", "Lamp")
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		lit = lit or material.emission_enabled
	t.check(lit, "ceiling lamp glows")
	lit = false
	mesh = Models.mesh("furniture/boiler", "Boiler")
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		lit = lit or material.emission_enabled
	t.check(lit, "furnace door glows")
	return true

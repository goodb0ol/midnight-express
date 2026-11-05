class_name Main
extends Node3D
## Assembles the Milestone 1 test level. Everything dynamic is created through
## spawn_player / spawn_prop / spawn_dummy, which is the seam Milestone 4's
## MultiplayerSpawner functions will wrap.

const PLAYER_SPAWN := Vector3(0.0, 0.05, -7.7)
const PLAYER_SPAWN_YAW := PI

## kind, car id, position relative to the car.
const CARGO: Array[Array] = [
	[&"wrench", &"Bistro", Vector3(-1.28, 0.86, -6.5)],
	[&"frying_pan", &"Bistro", Vector3(1.28, 0.86, -6.5)],
	[&"soup_bowl", &"Bistro", Vector3(-1.28, 0.86, 4.3)],
	[&"soup_bowl", &"Bistro", Vector3(-1.28, 0.86, 4.7)],
	[&"soup_bowl", &"Bistro", Vector3(1.28, 0.86, 4.5)],
	[&"crate", &"Bistro", Vector3(-1.3, 0.3, 0.9)],
	[&"crate", &"Bistro", Vector3(-1.3, 0.85, 0.9)],
	[&"suitcase", &"Bistro", Vector3(1.3, 0.25, -2.5)],
	[&"broom", &"Coach", Vector3(1.3, 0.2, 0.5)],
	[&"suitcase", &"Coach", Vector3(-1.2, 0.25, 0.5)],
	[&"suitcase", &"Coach", Vector3(-1.2, 0.72, 0.5)],
	[&"wrench", &"Locomotive", Vector3(-1.2, 0.2, 3.0)],
	[&"coal", &"Locomotive", Vector3(0.9, 0.2, 3.8)],
	[&"coal", &"Locomotive", Vector3(1.2, 0.2, 4.2)],
	[&"coal", &"Locomotive", Vector3(0.9, 0.2, 4.7)],
	[&"coal", &"Locomotive", Vector3(1.3, 0.2, 5.2)],
	[&"coal", &"Locomotive", Vector3(0.9, 0.2, 5.8)],
	[&"coal", &"Locomotive", Vector3(1.2, 0.5, 4.5)],
]
const DUMMIES: Array[Array] = [
	[&"Bistro", Vector3(0.2, 0.05, -3.4)],
	[&"Bistro", Vector3(-0.4, 0.05, 2.4)],
	[&"Bistro", Vector3(0.5, 0.05, 6.9)],
	[&"Coach", Vector3(0.1, 0.05, -6.0)],
	[&"Coach", Vector3(0.5, 0.05, -2.5)],
	[&"Coach", Vector3(-0.4, 0.05, 6.0)],
	[&"Locomotive", Vector3(-0.6, 0.05, 0.6)],
]

var train: Train
var treadmill: Treadmill
var hud: Hud
var touch: TouchControls
var local_player: Player
var players: Dictionary = {}  # peer id -> Player

var _props_root: Node3D
var _npcs_root: Node3D
var _players_root: Node3D


func _ready() -> void:
	_build_environment()
	train = Train.new()
	train.name = "Train"
	add_child(train)
	treadmill = Treadmill.new()
	treadmill.name = "Treadmill"
	add_child(treadmill)
	_props_root = _add_root("Props")
	_npcs_root = _add_root("Npcs")
	_players_root = _add_root("Players")

	var ui := CanvasLayer.new()
	ui.name = "TouchLayer"
	add_child(ui)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	ui.add_child(touch)
	if OS.has_feature("mobile"):
		touch.enable()
	elif "--touch" in OS.get_cmdline_user_args():
		# Desktop preview of the overlay: the mouse acts as a single finger.
		Input.emulate_touch_from_mouse = true
		touch.enable()

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.clipboard.reset_cargo_requested.connect(reset_cargo)
	hud.clipboard.respawn_requested.connect(_respawn_local_player)

	spawn_cargo()
	spawn_local_player(multiplayer.get_unique_id())


## Solo play. Milestone 4 calls spawn_player for each peer, with a network input source.
func spawn_local_player(peer_id: int) -> Player:
	var input := LocalInput.new()
	input.name = "LocalInput"
	input.touch = touch
	input.yaw = PLAYER_SPAWN_YAW
	var player := spawn_player(peer_id, input)
	input.player = player
	local_player = player

	var camera := PlayerCamera.new()
	camera.name = "Camera"
	camera.player = player
	camera.input = input
	player.add_child(camera)
	hud.bind_local_player(player, input, touch)
	if not touch.enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return player


func spawn_player(peer_id: int, input: PlayerInputSource) -> Player:
	var player := Player.create(peer_id, train)
	player.position = PLAYER_SPAWN + Vector3(0.7 * (players.size() % 2), 0.0, 0.0)
	player.spawn_point = player.position
	_players_root.add_child(player)
	player.input_source = input
	player.add_child(input)
	players[peer_id] = player
	return player


func spawn_prop(kind: StringName, at: Transform3D) -> PhysicsProp:
	var prop := PhysicsProp.create(kind)
	prop.transform = at
	_props_root.add_child(prop)
	return prop


func spawn_dummy(at: Transform3D, palette_index: int) -> TestDummy:
	var dummy := TestDummy.create(palette_index)
	dummy.transform = at
	_npcs_root.add_child(dummy)
	return dummy


func spawn_cargo() -> void:
	for entry in CARGO:
		var car := train.car_by_id(entry[1])
		var local: Vector3 = entry[2]
		spawn_prop(entry[0], Transform3D(Basis.IDENTITY, car.position + local))
	for i in DUMMIES.size():
		var car := train.car_by_id(DUMMIES[i][0])
		var local: Vector3 = DUMMIES[i][1]
		var facing := Basis(Vector3.UP, PI * float(i % 2))
		spawn_dummy(Transform3D(facing, car.position + local), i)


## Clears every loose body and restocks the train. Clipboard test-bench button.
func reset_cargo() -> void:
	for player: Player in players.values():
		player.hands.force_release()
	for root: Node3D in [_props_root, _npcs_root]:
		for child in root.get_children():
			child.queue_free()
	spawn_cargo()


func _respawn_local_player() -> void:
	if local_player != null:
		local_player.respawn()


func _add_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	return root


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.03, 0.05, 0.13)
	sky_material.sky_horizon_color = Color(0.2, 0.27, 0.42)
	sky_material.ground_bottom_color = Color(0.1, 0.13, 0.2)
	sky_material.ground_horizon_color = Color(0.2, 0.27, 0.42)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.3
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.2, 0.27, 0.42)
	environment.fog_density = 0.0028
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	add_child(world)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-38.0, -130.0, 0.0)
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 140.0
	moon.light_cull_mask = ~TrainCar.INTERIOR_RENDER_LAYER
	add_child(moon)

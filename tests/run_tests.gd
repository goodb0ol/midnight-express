extends Node
## Headless Milestone 1 checks. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Optional filter:  ... res://tests/test_runner.tscn -- door
## (A scene, not --script: autoload names only resolve in a normal scene run.)
## Exit code is 0 only if every test finished and every assertion held.

const BISTRO_WINDOW_Z := -4.0
const ErrorWatch := preload("res://tests/error_watch.gd")

var passed := 0
var failed := 0
var main: Main
var player: Player
var input: ScriptedInput
var events: Array[String] = []
## Fixed dice. Set TEST_RNG_SALT to replay every test under other dice and hunt flakes.
var rng_salt := 0
var _error_watch := ErrorWatch.new()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	get_window().size = Vector2i(1280, 720)
	OS.add_logger(_error_watch)
	rng_salt = OS.get_environment("TEST_RNG_SALT").to_int()
	GameEvents.object_yeeted.connect(_note.bind("yeeted").unbind(1))
	GameEvents.object_despawned.connect(_note.bind("despawned").unbind(1))
	GameEvents.npc_knocked_out.connect(_note.bind("knocked_out").unbind(3))
	GameEvents.npc_bonked.connect(_note.bind("bonked").unbind(3))
	GameEvents.player_left_train.connect(_note.bind("player_left").unbind(1))
	GameEvents.player_reboarded.connect(_note.bind("player_back").unbind(1))
	GameEvents.player_left_behind.connect(_note.bind("player_lost").unbind(1))
	var filter := ""
	if not OS.get_cmdline_user_args().is_empty():
		filter = OS.get_cmdline_user_args()[0]
	TestDummy.brain_enabled = false
	var tests: Array[Array] = []
	_add_tests(self, tests, filter)
	for file: String in DirAccess.get_files_at("res://tests"):
		if file.begins_with("suite_") and file.ends_with(".gd"):
			var suite: RefCounted = load("res://tests/" + file).new()
			suite.set("t", self)
			_add_tests(suite, tests, filter)
	for entry in tests:
		var test_owner: Object = entry[0]
		var test_name: String = entry[1]
		await _fresh_main()
		var before := failed
		var finished: Variant = await test_owner.call(test_name)
		if finished != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % test_name)
		await _teardown()
		for line in _error_watch.take():
			check(false, "the log stays clean: %s" % line)
		print("%s %s" % ["FAIL" if failed > before else "ok  ", test_name])
	print("Results: %d passed, %d failed, %d tests" % [passed, failed, tests.size()])
	get_tree().quit(1 if failed > 0 else 0)


func _add_tests(source: Object, tests: Array[Array], filter: String) -> void:
	for method: Dictionary in source.get_script().get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and (filter.is_empty() or method_name.contains(filter)):
			tests.append([source, method_name])


func _fresh_main() -> void:
	TrainState.distance_m = 0.0
	TrainState.speed_mps = 100.0 / 3.6
	TrainState.target_speed_mps = 100.0 / 3.6
	TrainState.rng_salt = rng_salt
	TrainState.rng_serial = 0
	# Sound dice and the whistle timer: they count hits and can land inside a measurement.
	Sfx._rng.seed = rng_salt
	Sfx._next_whistle = Sfx._clock + 1000.0
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_start_round = false
	get_tree().root.add_child(main)
	player = main.local_player
	var old_input := player.input_source
	input = ScriptedInput.new()
	input.name = "ScriptedInput"
	input.yaw = old_input.yaw
	player.add_child(input)
	player.input_source = input
	events.clear()
	await ticks(30)


func _teardown() -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _note(label: String) -> void:
	events.append(label)


func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func seconds(duration: float) -> void:
	await ticks(roundi(duration * 60.0))


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s" % label)


func check_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s: expected %.3f +-%.3f, got %.3f" % [label, expected, tolerance, actual])


func stand_player(at: Vector3, look_at_point: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	input.aim_at(at + Vector3.UP * Player.EYE_HEIGHT, look_at_point)
	await ticks(2)


## Walks with real input (so a held body comes along) until within 0.25 m of [param goal].
func walk_to(goal: Vector3, limit_seconds := 6.0) -> void:
	var left := limit_seconds
	while left > 0.0:
		var flat := Vector3(goal.x, player.global_position.y, goal.z)
		var to_goal := flat - player.global_position
		if to_goal.length() < 0.25:
			break
		var local := Basis(Vector3.UP, input.yaw).inverse() * to_goal.normalized()
		input.move = Vector2(local.x, -local.z)
		await ticks(1)
		left -= 1.0 / 60.0
	input.move = Vector2.ZERO
	await ticks(6)


func clear_dummies() -> void:
	for child in main.get_node("Npcs").get_children():
		child.queue_free()
	await ticks(1)


func first_dummy() -> TestDummy:
	return main.get_node("Npcs").get_child(0)


func nearest_prop(kind: StringName) -> PhysicsProp:
	var best: PhysicsProp = null
	for child in main.get_node("Props").get_children():
		var prop := child as PhysicsProp
		if prop != null and prop.kind == kind:
			if best == null or prop.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = prop
	return best


func opening_named(car_id: StringName, opening_name: String) -> TrainOpening:
	return main.train.car_by_id(car_id).get_node(opening_name) as TrainOpening


func knock_out(dummy: TestDummy) -> Ragdoll:
	var ragdolls_before := _ragdolls().size()
	dummy.receive_bonk(3, Vector3.FORWARD, player)
	await ticks(2)
	check(_ragdolls().size() == ragdolls_before + 1, "knock_out spawned a ragdoll")
	return _ragdolls().back()


func _ragdolls() -> Array[Ragdoll]:
	var result: Array[Ragdoll] = []
	for child in main.get_node("Npcs").get_children():
		if child is Ragdoll and not child.is_queued_for_deletion():
			result.append(child)
	return result


# ---------------------------------------------------------------------------------
# Setup and input map
# ---------------------------------------------------------------------------------

func test_project_setup() -> bool:
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Jolt is the 3D engine")
	check(main.train.cars.size() == 3, "three cars")
	check(main.train.global_transform.is_equal_approx(Transform3D.IDENTITY), "train at world origin")
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"grab", &"throw", &"use", &"clipboard"]:
		check(InputMap.has_action(action), "action %s exists" % action)
		check(not InputMap.action_get_events(action).is_empty(), "action %s has a default binding" % action)
	check(main.train.openings().size() == 19, "3 cars x 6 working openings + rear door, got %d" % main.train.openings().size())
	return true


func test_keys_are_physical_positions() -> bool:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	check(key.is_action(&"move_forward"), "physical W is move_forward, so Z on AZERTY")
	var letter_only := InputEventKey.new()
	letter_only.keycode = KEY_Z
	letter_only.physical_keycode = KEY_Y
	letter_only.pressed = true
	check(not letter_only.is_action(&"move_forward"), "bindings ignore the printed letter")
	return true


# ---------------------------------------------------------------------------------
# Treadmill
# ---------------------------------------------------------------------------------

func test_treadmill_scrolls_and_train_stays_put() -> bool:
	var chunk: SceneryChunk = null
	for candidate: SceneryChunk in main.treadmill.active_chunks():
		if absf(candidate.position.z) < 60.0:
			chunk = candidate
	var chunk_index := chunk.index
	var start_distance := TrainState.distance_m
	await seconds(2.0)
	check_near(TrainState.distance_m - start_distance, 100.0 / 3.6 * 2.0, 0.1, "distance after 2 s at 100 km/h")
	check_near(chunk.position.z, TrainState.distance_m - chunk_index * SceneryChunk.LENGTH, 0.01, "chunk follows distance")
	check(main.train.global_transform.is_equal_approx(Transform3D.IDENTITY), "train never moved")
	check(main.treadmill.ground.constant_linear_velocity.is_equal_approx(TrainState.ground_velocity()), "ground conveyor matches speed")
	return true


func test_scenery_pool_is_bounded_over_long_run() -> bool:
	var expected := main.treadmill.active_chunks().size()
	var total_nodes := main.treadmill.get_child_count()
	for step in 30:
		TrainState.distance_m += 900.0
		await ticks(3)
		check(absi(main.treadmill.active_chunks().size() - expected) <= 1, "active chunk count stays bounded")
	check(main.treadmill.get_child_count() == total_nodes, "no nodes leaked by recycling")
	return true


func test_scenery_is_deterministic_from_seed() -> bool:
	var a: SceneryChunk = main.treadmill.active_chunks()[0]
	var b: SceneryChunk = main.treadmill.active_chunks()[1]
	a.populate(777)
	b.populate(777)
	await ticks(1)
	check(a.layout_points() == b.layout_points(), "same seed and index give identical chunks, so peers need only distance")
	var first_layout := a.layout_points()
	b.populate(778)
	check(b.layout_points() != first_layout, "a different index gives a different chunk")
	return true


func test_ground_is_a_conveyor() -> bool:
	var prop := main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(9.0, Treadmill.GROUND_Y + 0.6, 40.0)))
	prop.off_train = true
	await seconds(5.0)
	check_near(prop.linear_velocity.z, TrainState.speed_mps, 2.0, "friction drags a resting crate up to ground speed")
	return true


func test_stopping_the_train_stops_the_world() -> bool:
	TrainState.set_target_kmh(0.0)
	await seconds(5.0)
	check(TrainState.speed_mps == 0.0, "train decelerated to zero")
	var distance := TrainState.distance_m
	await seconds(1.0)
	check(TrainState.distance_m == distance, "treadmill holds still when stopped")
	return true


func test_interior_is_zero_velocity_space_at_speed() -> bool:
	await seconds(2.0)
	var start: Dictionary = {}
	for child in main.get_node("Props").get_children():
		start[child] = (child as Node3D).global_position
	await seconds(5.0)
	var worst := 0.0
	var fastest := 0.0
	for prop: PhysicsProp in start.keys():
		worst = maxf(worst, prop.global_position.distance_to(start[prop]))
		fastest = maxf(fastest, prop.linear_velocity.length())
	check(TrainState.speed_mps > 27.0, "train is at speed during the check")
	check(worst < 0.03, "resting props did not creep at 100 km/h, worst %.4f m" % worst)
	check(fastest < 0.05, "resting props stay at rest, fastest %.4f m/s" % fastest)
	return true


# ---------------------------------------------------------------------------------
# Doors and windows
# ---------------------------------------------------------------------------------

func _ray_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.HULL)
	return not get_tree().root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func test_door_opens_and_closes_from_the_crosshair() -> bool:
	var door := opening_named(&"Bistro", "Door_R_-10")
	check(door != null, "door node exists")
	await stand_player(Vector3(0.6, 0.05, -1.0), door.global_position)
	var inside := Vector3(1.0, 1.0, -1.0)
	var outside := Vector3(2.6, 1.0, -1.0)
	check(_ray_blocked(inside, outside), "closed door blocks")
	await ticks(2)
	input.press_grab()
	await seconds(0.7)
	check(door.is_open, "grab opened the door")
	check(not _ray_blocked(inside, outside), "open door leaves a clear hole")
	input.press_grab()
	await seconds(0.7)
	check(not door.is_open, "crosshair on the open hole closes it again")
	check(_ray_blocked(inside, outside), "closed again")
	return true


func test_window_opens_with_clear_hole() -> bool:
	var window := opening_named(&"Bistro", "Window_R_-40")
	await stand_player(Vector3(0.9, 0.05, BISTRO_WINDOW_Z), window.global_position)
	var inside := Vector3(1.0, 1.4, BISTRO_WINDOW_Z)
	var outside := Vector3(2.6, 1.4, BISTRO_WINDOW_Z)
	check(_ray_blocked(inside, outside), "closed window blocks")
	input.press_grab()
	await seconds(0.7)
	check(window.is_open, "grab opened the window")
	check(not _ray_blocked(inside, outside), "window hole is clear")
	check(main.train.open_opening_count() == 1, "open count tracks it, for Milestone 2 heat loss")
	return true


# ---------------------------------------------------------------------------------
# Player controller
# ---------------------------------------------------------------------------------

func test_player_walks_stops_jumps() -> bool:
	await clear_dummies()
	await stand_player(Vector3(0.0, 0.05, -7.7), Vector3(0.0, 1.6, 0.0))
	await seconds(0.3)
	var start := player.global_position
	input.move = Vector2(0.0, 1.0)
	await seconds(1.0)
	check_near(player.global_position.z - start.z, Player.WALK_SPEED, 0.6, "walked about one second of WALK_SPEED")
	input.move = Vector2.ZERO
	await seconds(0.3)
	check(player.velocity.length() < 0.1, "stops when input stops")
	check(player.is_on_floor(), "stands on the carriage floor")
	input.jump = true
	await seconds(0.25)
	input.jump = false
	check(player.global_position.y > 0.2, "jumped")
	await seconds(1.0)
	check(player.is_on_floor(), "landed")
	return true


func test_player_walks_whole_train_to_rear_platform() -> bool:
	var rear_door := main.train.car_by_id(&"Coach").get_node("Door_Rear") as TrainOpening
	await clear_dummies()
	await stand_player(Vector3(0.0, 0.05, -27.0 + 8.0), Vector3(0.0, 1.6, 40.0))
	input.move = Vector2(0.0, 1.0)
	input.sprint = true
	await seconds(9.0)
	var blocked_z := player.global_position.z
	check(blocked_z < rear_door.global_position.z, "closed rear door stops the walk, z=%.2f" % blocked_z)
	check(blocked_z > 20.0, "walked through both gangways, z=%.2f" % blocked_z)
	input.move = Vector2.ZERO
	rear_door.set_open(true)
	await seconds(0.7)
	input.move = Vector2(0.0, 1.0)
	await seconds(1.5)
	check(player.global_position.z > rear_door.global_position.z + 0.5, "stepped onto the platform")
	check(player.is_aboard(), "platform still counts as aboard")
	check(player.global_position.z < main.train.rear_z(), "the rail stops the player")
	return true


# ---------------------------------------------------------------------------------
# Grab, throw, bonk
# ---------------------------------------------------------------------------------

func _grab_wrench() -> PhysicsProp:
	var wrench := nearest_prop(&"wrench")
	await stand_player(wrench.global_position + Vector3(0.9, -0.8, 0.5), wrench.global_position)
	await ticks(1)
	input.press_grab()
	await ticks(4)
	check(player.hands.held == wrench, "wrench grabbed")
	return wrench


func test_grab_hold_drop() -> bool:
	var wrench := await _grab_wrench()
	await seconds(0.6)
	var offset := wrench.global_position.distance_to(player.eye_position())
	check(offset < 1.5, "held tool floats near the view, %.2f m" % offset)
	await stand_player(Vector3(0.0, 0.05, -5.0), Vector3(0.0, 1.5, 0.0))
	await seconds(0.5)
	input.press_grab()
	await ticks(2)
	check(player.hands.held == null, "second grab drops")
	await seconds(1.0)
	check(wrench.global_position.y < 0.4, "dropped tool fell to the floor")
	return true


func test_throw_strength_follows_charge() -> bool:
	var wrench := await _grab_wrench()
	await stand_player(Vector3(0.0, 0.05, -5.0), Vector3(0.0, 1.6, 5.0))
	await seconds(0.3)
	input.throw_held = true
	await ticks(1)
	input.throw_held = false
	await ticks(1)
	var tap_speed := wrench.linear_velocity.length()
	check(player.hands.held == null, "tap released the tool")

	await seconds(1.0)
	input.aim_at(player.eye_position(), wrench.global_position)
	await ticks(2)
	var at := wrench.global_position
	await stand_player(at + Vector3(0.0, 0.0, -1.2), at)
	await ticks(1)
	input.press_grab()
	await ticks(4)
	check(player.hands.held == wrench, "grabbed again")
	input.yaw = PI
	input.pitch = 0.1
	await seconds(0.3)
	input.throw_held = true
	await seconds(1.0)
	input.throw_held = false
	await ticks(1)
	var full_speed := wrench.linear_velocity.length()
	check(full_speed > tap_speed * 1.8, "full charge beats a tap: %.1f vs %.1f m/s" % [full_speed, tap_speed])
	return true


func test_fist_takes_three_bonks() -> bool:
	var dummy := first_dummy()
	var chest := dummy.global_position + Vector3.UP * 1.3
	await stand_player(dummy.global_position + Vector3(0.0, 0.0, -1.3), chest)
	for swing in 3:
		check(events.count("knocked_out") == 0, "still standing before punch %d" % (swing + 1))
		input.aim_at(player.eye_position(), dummy.global_position + Vector3.UP * 1.3 if is_instance_valid(dummy) else chest)
		input.press_use()
		await seconds(0.45)
	check(events.count("bonked") == 3, "three punches landed, got %d" % events.count("bonked"))
	check(events.count("knocked_out") == 1, "third punch knocks out")
	check(_ragdolls().size() == 1, "dummy became a ragdoll")
	return true


func test_tool_knocks_out_in_one() -> bool:
	await _grab_wrench()
	var dummy := first_dummy()
	await stand_player(dummy.global_position + Vector3(0.0, 0.0, -1.3), dummy.global_position + Vector3.UP * 1.3)
	await seconds(0.3)
	input.press_use()
	await seconds(0.45)
	check(events.count("knocked_out") == 1, "wrench is a one-hit knockout")
	return true


func test_thrown_prop_bonks() -> bool:
	var wrench := await _grab_wrench()
	var dummy := first_dummy()
	await stand_player(dummy.global_position + Vector3(0.0, 0.0, -2.0), dummy.global_position + Vector3.UP * 1.2)
	await seconds(0.3)
	check(player.hands.held == wrench, "still holding")
	input.throw_held = true
	await seconds(0.8)
	input.throw_held = false
	await seconds(0.5)
	check(events.count("knocked_out") == 1, "a thrown wrench knocks a dummy out")
	return true


func test_ragdoll_is_stable_and_holds_together() -> bool:
	var ragdoll := await knock_out(first_dummy())
	await seconds(4.0)
	var pelvis := ragdoll.pelvis.global_position
	check(pelvis.y > -0.1 and pelvis.y < 0.6, "ragdoll collapsed onto the floor, y=%.2f" % pelvis.y)
	var widest := 0.0
	for part in ragdoll.parts:
		widest = maxf(widest, part.global_position.distance_to(pelvis))
		check(part.global_position.is_finite(), "part position finite")
	check(widest < 1.3, "joints held, farthest part %.2f m from pelvis" % widest)
	return true


## Walks around the body until the crosshair sits on a limb, and returns that limb. How a
## body lands is a matter of dice: from one side a limb can lie under the rest of it.
func _aim_at_a_limb(ragdoll: Ragdoll) -> RagdollPart:
	var limbs: Array[RagdollPart] = ragdoll.parts.filter(func(p: RagdollPart) -> bool: return p.part_name in [&"forearm_l", &"forearm_r", &"shin_l", &"shin_r"])
	for limb in limbs:
		for reach: float in [0.9, 0.6]:
			for i in 8:
				var spot := limb.global_position + Vector3(0.0, 0.0, -reach).rotated(Vector3.UP, TAU * i / 8.0)
				if absf(spot.x) > TrainCar.HALF_WIDTH - 0.4:
					continue
				await stand_player(Vector3(spot.x, 0.05, spot.z), limb.global_position)
				await ticks(8)  # Let the feet settle, then aim from the real eye height.
				input.aim_at(player.eye_position(), limb.global_position)
				await ticks(2)
				if player.hands._aim_hit.get("collider") == limb:
					return limb
	return null


func test_grab_ragdoll_by_a_limb_and_drag_it() -> bool:
	var ragdoll := await knock_out(first_dummy())
	await seconds(2.0)
	for i in 180:  # Some landings take a while to settle, and a small limb moves off the aim.
		if ragdoll.center_velocity().length() < 0.02:
			break
		await ticks(1)
	var limb := await _aim_at_a_limb(ragdoll)
	check(limb != null, "a limb can be aimed at")
	if limb == null:
		return true
	await ticks(1)
	input.press_grab()
	await ticks(3)
	check(player.hands.held == limb, "grabbed one limb")
	input.pitch = 0.0
	await seconds(0.6)
	check(limb.global_position.y > 0.8, "limb lifted, y=%.2f" % limb.global_position.y)
	var pelvis_before := ragdoll.pelvis.global_position
	input.yaw = 0.0
	input.pitch = 0.0
	input.move = Vector2(0.0, 1.0)
	await seconds(1.0)
	input.move = Vector2.ZERO
	var pulled := ragdoll.pelvis.global_position.distance_to(pelvis_before)
	check(pulled > 1.0, "the rest of the body followed, %.2f m" % pulled)
	var widest := 0.0
	for part in ragdoll.parts:
		widest = maxf(widest, part.global_position.distance_to(ragdoll.pelvis.global_position))
	check(widest < 1.3, "dragging did not stretch joints, %.2f m" % widest)
	return true


# ---------------------------------------------------------------------------------
# Exterior Yeet Zone
# ---------------------------------------------------------------------------------

## The full Milestone 1 promise: bonk, drag, open a window, heave, gone.
func test_full_yeet_loop_through_a_window() -> bool:
	var wrench := await _grab_wrench()
	var dummy := first_dummy()
	await stand_player(dummy.global_position + Vector3(0.0, 0.0, -1.3), dummy.global_position + Vector3.UP * 1.3)
	await seconds(0.3)
	input.press_use()
	await seconds(0.45)
	check(events.count("knocked_out") == 1, "dummy down")
	player.hands.drop()
	await seconds(1.0)
	var ragdoll := _ragdolls()[0]

	var chest := ragdoll.chest
	await walk_to(chest.global_position + Vector3(0.0, 0.0, -0.9))
	input.aim_at(player.eye_position(), chest.global_position)
	await ticks(2)
	input.press_grab()
	await ticks(3)
	check(player.hands.held is RagdollPart, "picked the body up")

	var window := opening_named(&"Bistro", "Window_R_-40")
	input.pitch = 0.0
	await walk_to(Vector3(0.1, 0.05, BISTRO_WINDOW_Z))
	check(player.hands.held is RagdollPart, "carried the body to the window")
	input.aim_at(player.eye_position(), window.global_position)
	await ticks(2)
	input.press_grab()
	await seconds(0.7)
	check(window.is_open, "opened the window while holding the body")
	check(player.hands.held is RagdollPart, "still holding the body after interacting")
	await seconds(0.6)

	var start_velocity_z := ragdoll.pelvis.linear_velocity.z
	input.throw_held = true
	await seconds(0.8)
	input.throw_held = false
	var seen_snatch := 0.0
	for i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(ragdoll):
			break
		seen_snatch = maxf(seen_snatch, ragdoll.pelvis.linear_velocity.z)
		if ragdoll.off_train:
			break
	check(is_instance_valid(ragdoll) and ragdoll.off_train, "body crossed out of the hull")
	check(events.count("yeeted") >= 1, "object_yeeted fired")
	check(player.hands.held == null, "hands are empty")
	check(player.is_aboard(), "player stayed on the train")
	await ticks(2)
	check(ragdoll.pelvis.linear_velocity.z > start_velocity_z + TrainState.speed_mps * 0.4, "train speed was applied, vz=%.1f" % ragdoll.pelvis.linear_velocity.z)

	await seconds(2.0)
	check(ragdoll.anchor().z > main.train.rear_z(), "body is behind the train after 2 s, z=%.1f" % ragdoll.anchor().z)
	check(ragdoll.anchor().y < 2.5, "body came down to the snow, y=%.2f" % ragdoll.anchor().y)
	var deadline := 25.0
	while is_instance_valid(ragdoll) and deadline > 0.0:
		await seconds(0.25)
		deadline -= 0.25
	check(not is_instance_valid(ragdoll), "body disappeared into the distance")
	check(events.count("despawned") >= 1, "object_despawned fired")
	check(is_instance_valid(wrench), "the wrench stayed aboard")
	return true


func test_closed_window_keeps_things_in() -> bool:
	var coal := main.spawn_prop(&"coal", Transform3D(Basis.IDENTITY, Vector3(0.5, 1.4, BISTRO_WINDOW_Z)))
	coal.linear_velocity = Vector3(16.0, 0.3, 0.0)
	coal.continuous_cd = true
	await seconds(1.5)
	check(not coal.off_train, "glass stopped it")
	check(coal.global_position.x < TrainCar.HALF_WIDTH, "coal stayed inside, x=%.2f" % coal.global_position.x)
	return true


func test_prop_through_open_door_is_snatched() -> bool:
	opening_named(&"Bistro", "Door_L_-10").set_open(true)
	await seconds(0.7)
	var crate := main.spawn_prop(&"suitcase", Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.6, -1.0)))
	crate.linear_velocity = Vector3(-7.0, 0.5, 0.0)
	await seconds(0.6)
	check(crate.off_train, "suitcase left through the open door")
	check(crate.linear_velocity.z > TrainState.speed_mps * 0.5, "scrolled backward, vz=%.1f" % crate.linear_velocity.z)
	return true


func test_rear_platform_is_an_exit() -> bool:
	var coach := main.train.car_by_id(&"Coach")
	var bag := main.spawn_prop(&"suitcase", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, coach.position.z + coach.length * 0.5 + 1.2)))
	bag.linear_velocity = Vector3(0.0, 1.0, 8.0)
	await seconds(1.0)
	check(bag.off_train, "over the rear rail counts as leaving the train")
	return true


func test_nothing_scrolls_when_stopped() -> bool:
	TrainState.speed_mps = 0.0
	TrainState.target_speed_mps = 0.0
	opening_named(&"Bistro", "Door_L_-10").set_open(true)
	await seconds(0.7)
	var bag := main.spawn_prop(&"suitcase", Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.6, -1.0)))
	bag.linear_velocity = Vector3(-5.0, 0.5, 0.0)
	await seconds(2.5)
	check(bag.off_train, "still counts as outside")
	check(absf(bag.global_position.z + 1.0) < 1.0, "stopped train adds no scroll, z=%.2f" % bag.global_position.z)
	check(bag.global_position.y < Treadmill.GROUND_Y + 0.5, "lands on the ground")
	return true


func test_arm_out_of_window_does_not_yeet_the_body() -> bool:
	opening_named(&"Bistro", "Window_R_-40").set_open(true)
	await seconds(0.7)
	var dummy := first_dummy()
	dummy.global_position = Vector3(1.05, 0.05, BISTRO_WINDOW_Z)
	await ticks(1)
	var ragdoll := await knock_out(dummy)
	for part in ragdoll.parts:
		part.freeze = part.part_name != &"forearm_r" and part.part_name != &"upper_arm_r"
	var arm: RagdollPart = ragdoll.parts.filter(func(p: RagdollPart) -> bool: return p.part_name == &"forearm_r")[0]
	await seconds(0.2)
	arm.linear_velocity = Vector3(5.0, 3.0, 0.0)
	await seconds(1.0)
	check(not main.train.exterior_zone.is_outside(ragdoll.anchor()), "pelvis is still inside")
	check(not ragdoll.off_train, "a dangling limb alone doesn't launch the body")
	return true


func test_held_prop_gets_ripped_away_outside() -> bool:
	opening_named(&"Bistro", "Window_R_-40").set_open(true)
	await seconds(0.7)
	var wrench := await _grab_wrench()
	input.yaw = -PI * 0.5
	input.pitch = 0.0
	await walk_to(Vector3(1.3, 0.05, BISTRO_WINDOW_Z))
	await seconds(0.6)
	check(wrench.off_train, "tool held out of the window crossed the hull")
	check(player.hands.held == null, "the slipstream ripped it out of the hands")
	return true


func test_body_hits_scrolling_obstacles() -> bool:
	# Park a yeeted crate directly in the path of a real scenery tree.
	var chosen: Vector3 = Vector3.INF
	for chunk: SceneryChunk in main.treadmill.active_chunks():
		for child in chunk.get_children():
			var shape := child as CollisionShape3D
			if shape != null and not shape.disabled and shape.shape is CylinderShape3D:
				var world := chunk.global_transform * shape.position
				if world.z < -30.0 and world.z > -120.0 and absf(world.x) > 6.0:
					chosen = world
	check(chosen != Vector3.INF, "found a tree ahead of the train")
	if chosen == Vector3.INF:
		return true
	var crate := main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(chosen.x, Treadmill.GROUND_Y + 1.4, chosen.z + 32.0)))
	crate.off_train = true
	crate.collision_mask = Layers.OUTSIDE_MASK
	crate.continuous_cd = true
	crate.linear_velocity = Vector3(0.0, 0.0, TrainState.speed_mps * 0.3)
	var fastest := 0.0
	for i in 150:
		await get_tree().physics_frame
		if is_instance_valid(crate):
			fastest = maxf(fastest, crate.linear_velocity.z)
	check(fastest > TrainState.speed_mps * 0.9, "tree hit the crate at ground speed, vz peak %.1f" % fastest)
	return true


# ---------------------------------------------------------------------------------
# Player fall-out
# ---------------------------------------------------------------------------------

func _walk_out_of_bistro_door() -> void:
	opening_named(&"Bistro", "Door_R_-10").set_open(true)
	await seconds(0.7)
	await stand_player(Vector3(1.2, 0.05, -1.0), Vector3(5.0, 1.6, -1.0))
	input.move = Vector2(0.0, 1.0)
	await seconds(0.7)
	input.move = Vector2.ZERO


func test_player_falls_out_and_uses_the_rope() -> bool:
	await _walk_out_of_bistro_door()
	check(player.state == Player.State.DRAGGED, "stepping out means being dragged")
	check(events.count("player_left") == 1, "player_left_train fired")
	input.yaw = PI * 0.5
	input.pitch = 0.0
	input.move = Vector2(0.0, 1.0)  # Steer toward the track centre line.
	var deadline := 8.0
	while not main.train.rope.in_reach(player.global_position) and deadline > 0.0:
		await ticks(1)
		deadline -= 1.0 / 60.0
	check(main.train.rope.in_reach(player.global_position), "rope came within reach")
	input.move = Vector2.ZERO
	input.press_grab()
	await ticks(2)
	check(player.state == Player.State.ROPE, "grabbed the rope")
	await seconds(5.0)
	check(player.is_aboard(), "reeled back aboard")
	check(player.global_position.z > main.train.cars.back().position.z + 9.0, "landed on the rear platform")
	check(events.count("player_back") == 1, "player_reboarded fired")
	await seconds(1.0)
	check(player.is_on_floor(), "stands on the platform")
	return true


func test_player_outside_a_stopped_train_can_walk() -> bool:
	TrainState.speed_mps = 0.0
	TrainState.target_speed_mps = 0.0
	await _walk_out_of_bistro_door()
	check(player.state == Player.State.DRAGGED, "outside the hull even when stopped")
	var start := player.global_position
	await seconds(1.0)
	check(player.global_position.distance_to(start) < 0.5 or absf(player.global_position.z - start.z) < 0.1, "nothing drags the player when stopped")
	input.yaw = PI
	input.pitch = 0.0
	input.move = Vector2(0.0, 1.0)
	await seconds(1.0)
	check(absf(player.global_position.z - start.z) > 3.0, "can walk on the snow")
	player.global_position = Vector3(0.0, Treadmill.GROUND_Y + 0.1, main.train.rear_z() + 2.0)
	input.move = Vector2.ZERO
	await ticks(2)
	input.press_grab()
	await seconds(3.0)
	check(player.is_aboard(), "the rope also works when stopped")
	return true


func test_player_missing_the_rope_is_left_behind() -> bool:
	await _walk_out_of_bistro_door()
	await seconds(8.0)
	check(events.count("player_lost") == 1, "player_left_behind fired")
	check(player.is_aboard(), "respawned aboard")
	check(player.global_position.distance_to(player.spawn_point) < 0.5, "back at the spawn point")
	return true


# ---------------------------------------------------------------------------------
# Touch parity (synthetic events)
# ---------------------------------------------------------------------------------

func _touch_event(finger: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = point
	event.pressed = pressed
	return event


func _drag_event(finger: int, point: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = point
	event.relative = relative
	return event


func _use_touch_input() -> LocalInput:
	var local := LocalInput.new()
	local.touch = main.touch
	local.player = player
	local.yaw = input.yaw
	player.add_child(local)
	player.input_source = local
	main.touch.enable()
	return local


func test_touch_stick_look_and_buttons_at_once() -> bool:
	var local := _use_touch_input()
	var touch := main.touch
	var view := touch.size
	check(view.x > 0.0, "overlay has a size")
	var thumb := Vector2(view.x * 0.2, view.y * 0.7)
	touch._input(_touch_event(0, thumb, true))
	touch._input(_drag_event(0, thumb + Vector2(0.0, -80.0), Vector2(0.0, -80.0)))
	check(touch.stick.y > 0.7, "dragging up on the stick is forward, %.2f" % touch.stick.y)

	var look_point := Vector2(view.x * 0.6, view.y * 0.3)
	touch._input(_touch_event(1, look_point, true))
	var yaw_before := local.yaw
	touch._input(_drag_event(1, look_point + Vector2(40.0, 0.0), Vector2(40.0, 0.0)))
	var grab_button: Dictionary = TouchControls.BUTTONS.filter(func(b: Dictionary) -> bool: return b["action"] == &"grab")[0]
	touch._input(_touch_event(2, touch.button_center(grab_button), true))
	check(Input.is_action_pressed(&"grab"), "button presses the same action as the keyboard")

	var start := player.global_position
	await seconds(0.5)
	check(player.global_position.distance_to(start) > 1.0, "stick walks the player, moved %.2f" % player.global_position.distance_to(start))
	check(absf(local.yaw - yaw_before) > 0.1, "right side drag turns the camera")

	touch._input(_touch_event(2, touch.button_center(grab_button), false))
	check(not Input.is_action_pressed(&"grab"), "button released")
	touch._input(_touch_event(0, thumb, false))
	check(touch.stick == Vector2.ZERO, "stick recentres")
	touch._input(_touch_event(1, look_point, false))
	return true


func test_touch_tap_does_not_fire_bonk_via_mouse_emulation() -> bool:
	_use_touch_input()
	var mouse_click := InputEventMouseButton.new()
	mouse_click.button_index = MOUSE_BUTTON_LEFT
	mouse_click.pressed = true
	check(not mouse_click.is_action(&"use"), "emulated left click is not Bonk in touch mode")
	check(not mouse_click.is_action(&"throw"), "emulated left click is not Throw in touch mode")
	InputMap.load_from_project_settings()
	return true


func test_touch_sprint_past_the_ring() -> bool:
	_use_touch_input()
	var touch := main.touch
	var thumb := Vector2(touch.size.x * 0.2, touch.size.y * 0.7)
	touch._input(_touch_event(0, thumb, true))
	touch._input(_drag_event(0, thumb + Vector2(0.0, -150.0), Vector2(0.0, -150.0)))
	check(Input.is_action_pressed(&"sprint"), "pushing past the ring sprints")
	touch._input(_touch_event(0, thumb, false))
	check(not Input.is_action_pressed(&"sprint"), "sprint ends with the thumb")
	InputMap.load_from_project_settings()
	return true


func test_touch_aim_magnetism_pulls_toward_targets() -> bool:
	var local := _use_touch_input()
	var dummy := first_dummy()
	var chest := dummy.global_position + Vector3.UP * 1.3
	await stand_player(dummy.global_position + Vector3(0.0, 0.0, -1.8), chest)
	local.yaw = input.yaw + deg_to_rad(5.0)
	local.pitch = input.pitch
	await ticks(1)
	var before := player.aim_forward().angle_to(chest - player.eye_position())
	var touch := main.touch
	var thumb := Vector2(touch.size.x * 0.2, touch.size.y * 0.7)
	touch._input(_touch_event(0, thumb, true))
	touch._input(_drag_event(0, thumb + Vector2(0.0, -6.0), Vector2(0.0, -6.0)))
	await seconds(0.5)
	var after := player.aim_forward().angle_to(chest - player.eye_position())
	touch._input(_touch_event(0, thumb, false))
	check(after < before * 0.7, "aim drifted toward the dummy: %.2f to %.2f deg" % [rad_to_deg(before), rad_to_deg(after)])
	check(after > 0.001 or before < 0.02, "drift is a nudge, not a snap")
	InputMap.load_from_project_settings()
	return true


func test_clipboard_opens_and_freezes_input() -> bool:
	var local := LocalInput.new()
	local.touch = main.touch
	local.player = player
	player.add_child(local)
	player.input_source = local
	main.hud._local_input = local
	Input.action_press(&"move_forward")
	await ticks(2)
	main.hud.toggle_clipboard()
	check(main.hud.clipboard.visible, "clipboard shows")
	check(local.sample().move == Vector2.ZERO, "world gets no input while it is open")
	main.hud.toggle_clipboard()
	check(not main.hud.clipboard.visible, "clipboard hides")
	check(local.sample().move != Vector2.ZERO, "input returns")
	Input.action_release(&"move_forward")
	return true


func test_reset_cargo_restocks() -> bool:
	await knock_out(first_dummy())
	main.reset_cargo()
	await ticks(3)
	var dummies := 0
	for child in main.get_node("Npcs").get_children():
		if child is TestDummy and not child.is_queued_for_deletion():
			dummies += 1
	check(dummies == Main.DUMMIES.size(), "all dummies back, got %d" % dummies)
	check(_ragdolls().is_empty(), "ragdolls cleared")
	return true


# ---------------------------------------------------------------------------------
# Soak
# ---------------------------------------------------------------------------------

func test_yeet_holds_up_at_150_kmh() -> bool:
	TrainState.speed_mps = 150.0 / 3.6
	TrainState.target_speed_mps = 150.0 / 3.6
	opening_named(&"Bistro", "Door_R_-10").set_open(true)
	await seconds(0.7)
	var dummy := first_dummy()
	dummy.global_position = Vector3(0.6, 0.05, -1.0)
	await ticks(1)
	var ragdoll := await knock_out(dummy)
	ragdoll.throw(Vector3(9.0, 1.0, 0.0))
	var fastest := 0.0
	var widest := 0.0
	for i in 240:
		await get_tree().physics_frame
		if not is_instance_valid(ragdoll):
			break
		for part in ragdoll.parts:
			fastest = maxf(fastest, part.linear_velocity.length())
			widest = maxf(widest, part.global_position.distance_to(ragdoll.pelvis.global_position))
	check(events.count("yeeted") == 1, "body left the train")
	check(fastest < 120.0, "no explosion at 150 km/h, fastest %.1f m/s" % fastest)
	check(widest < 2.0, "joints held through the tumble, widest %.2f m" % widest)
	return true


func test_soak_many_bodies_overboard() -> bool:
	opening_named(&"Bistro", "Door_R_-10").set_open(true)
	opening_named(&"Bistro", "Door_L_-10").set_open(true)
	await seconds(0.7)
	var ragdolls: Array[Ragdoll] = []
	for child in main.get_node("Npcs").get_children():
		if child is TestDummy:
			(child as TestDummy).global_position = Vector3(0.0, 0.05, -1.0 + ragdolls.size() * 0.1)
			await ticks(1)
			var ragdoll := await knock_out(child)
			ragdoll.throw(Vector3(9.0 if ragdolls.size() % 2 == 0 else -9.0, 1.0, 0.0))
			ragdolls.append(ragdoll)
			await seconds(0.4)
	var fastest := 0.0
	for i in 1000:
		await get_tree().physics_frame
		for ragdoll in ragdolls:
			if is_instance_valid(ragdoll):
				for part in ragdoll.parts:
					fastest = maxf(fastest, part.linear_velocity.length())
					if not part.global_position.is_finite():
						check(false, "part position went non-finite")
						return true
	check(fastest < 120.0, "no physics explosions, fastest part %.1f m/s" % fastest)
	var left := 0
	for ragdoll in ragdolls:
		if is_instance_valid(ragdoll):
			left += 1
	check(events.count("yeeted") == ragdolls.size(), "all %d bodies left the train, got %d" % [ragdolls.size(), events.count("yeeted")])
	check(left == 0, "all bodies despawned, %d left" % left)
	return true

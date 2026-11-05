extends Node
## Windowed verification run: plays the Milestone 1 loop with scripted input, saves
## screenshots to captures/ and prints telemetry, then quits. Not part of the game.
##   godot --path . res://tools/capture.tscn
##   godot --path . res://tools/capture.tscn -- --touch     (touch overlay shots)

const OUT_DIR := "res://captures/"

var main: Main
var player: Player
var input: ScriptedInput
var spectator: Camera3D
var camera: PlayerCamera


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Keep the editor from importing verification screenshots.
	FileAccess.open(OUT_DIR + ".gdignore", FileAccess.WRITE)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player = main.local_player
	camera = player.get_node("Camera")
	if "--touch" not in OS.get_cmdline_user_args():
		await _pc_device_check()
		await _smoothness_check()
	input = ScriptedInput.new()
	input.name = "ScriptedInput"
	input.yaw = player.input_source.yaw
	player.add_child(input)
	player.input_source = input
	camera.input = input

	if "--touch" in OS.get_cmdline_user_args():
		await _touch_shots()
	else:
		await _main_scenario()
	print("capture finished")
	get_tree().quit()


## Real InputEvents through the OS-facing path: Input -> InputMap -> LocalInput -> Player.
func _pc_device_check() -> void:
	await seconds(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	var local := player.input_source as LocalInput
	var yaw_before := local.yaw
	var start := player.global_position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120.0, 0.0)
	Input.parse_input_event(motion)
	await seconds(0.4)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await ticks(2)
	print("pc_device_check: mouse_mode=%d yaw_change=%.3f moved=%.2f" % [
		Input.mouse_mode, local.yaw - yaw_before, player.global_position.distance_to(start)])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.global_position = player.spawn_point
	player.reset_physics_interpolation()
	local.yaw = yaw_before
	await ticks(2)


## On a display faster than 60 Hz, un-interpolated motion moves only every few frames.
func _smoothness_check() -> void:
	var chunk: SceneryChunk = null
	for candidate: SceneryChunk in main.treadmill.active_chunks():
		if absf(candidate.position.z) < 60.0:
			chunk = candidate
	var camera_steps: Array[float] = []
	var chunk_steps: Array[float] = []
	var last_camera := camera.global_position.z
	var last_chunk := chunk.get_global_transform_interpolated().origin.z
	Input.action_press(&"move_back")
	await seconds(0.2)
	var frames := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 700:
		await get_tree().process_frame
		frames += 1
		var camera_z := camera.global_position.z
		var chunk_z := chunk.get_global_transform_interpolated().origin.z
		camera_steps.append(absf(camera_z - last_camera))
		chunk_steps.append(absf(chunk_z - last_chunk))
		last_camera = camera_z
		last_chunk = chunk_z
	Input.action_release(&"move_back")
	var seconds_spent := (Time.get_ticks_msec() - started) * 0.001
	print("smoothness: render_fps=%.0f physics=60  camera_stalled_frames=%d/%d  scenery_stalled_frames=%d/%d" % [
		frames / seconds_spent, _stalled(camera_steps), frames, _stalled(chunk_steps), frames])
	await seconds(0.4)
	player.global_position = player.spawn_point
	player.reset_physics_interpolation()
	await ticks(2)


func _stalled(steps: Array[float]) -> int:
	var count := 0
	for step in steps:
		if step < 0.0001:
			count += 1
	return count


func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func seconds(duration: float) -> void:
	await ticks(roundi(duration * 60.0))


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR + shot_name + ".png")
	print("shot %s  fps=%d draws=%d prims=%d physics=%.1fms" % [
		shot_name, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	])


func stand(at: Vector3, look: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	input.aim_at(at + Vector3.UP * Player.EYE_HEIGHT, look)
	await ticks(3)


func walk_to(goal: Vector3, limit := 6.0) -> void:
	var left := limit
	while left > 0.0:
		var to_goal := Vector3(goal.x, player.global_position.y, goal.z) - player.global_position
		if to_goal.length() < 0.25:
			break
		var local := Basis(Vector3.UP, input.yaw).inverse() * to_goal.normalized()
		input.move = Vector2(local.x, -local.z)
		await ticks(1)
		left -= 1.0 / 60.0
	input.move = Vector2.ZERO
	await ticks(6)


func prop(kind: StringName) -> PhysicsProp:
	var best: PhysicsProp = null
	for child in main.get_node("Props").get_children():
		var candidate := child as PhysicsProp
		if candidate != null and candidate.kind == kind:
			if best == null or candidate.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = candidate
	return best


func dummy() -> TestDummy:
	for child in main.get_node("Npcs").get_children():
		if child is TestDummy and not child.is_queued_for_deletion():
			return child
	return null


## Newest body, so an older one still rolling away is not picked up.
func ragdoll() -> Ragdoll:
	var children := main.get_node("Npcs").get_children()
	children.reverse()
	for child in children:
		if child is Ragdoll and not child.is_queued_for_deletion():
			return child
	return null


func _main_scenario() -> void:
	await seconds(1.2)
	await shot("01_spawn")

	var window := main.train.car_by_id(&"Bistro").get_node("Window_R_-40") as TrainOpening
	var wrench := prop(&"wrench")
	await stand(wrench.global_position + Vector3(0.9, -0.8, 0.5), wrench.global_position)
	await ticks(2)
	await shot("02_wrench_prompt")
	input.press_grab()
	await seconds(0.5)
	input.pitch = -0.05
	await seconds(0.3)
	await shot("03_holding_wrench")

	var target := dummy()
	await stand(target.global_position + Vector3(0.0, 0.0, -1.5), target.global_position + Vector3.UP * 1.4)
	await seconds(0.3)
	input.press_use()
	await seconds(0.12)
	await shot("04_bonk_swing")
	await seconds(1.2)
	player.hands.drop()
	await shot("05_ragdoll_down")

	var body := ragdoll()
	await walk_to(body.chest.global_position + Vector3(0.0, 0.0, -0.9))
	input.aim_at(player.eye_position(), body.chest.global_position)
	await ticks(2)
	input.press_grab()
	await ticks(3)
	input.pitch = 0.0
	await walk_to(Vector3(0.2, 0.05, -4.0))
	input.aim_at(player.eye_position(), window.global_position)
	await ticks(2)
	input.press_grab()
	await seconds(0.8)
	await shot("06_carrying_body_window_open")

	input.throw_held = true
	await seconds(0.8)
	input.throw_held = false
	await _telemetry_and_view(body, "07_window_view", false)

	await _chase_camera_yeet()

	main.hud.toggle_clipboard()
	await ticks(4)
	await shot("09_clipboard")
	main.hud.toggle_clipboard()

	await _fall_out_scenario()


## Follows the yeeted body from the player's eye for four seconds, logging its motion.
func _telemetry_and_view(body: Ragdoll, prefix: String, chase: bool) -> void:
	var frames := 0
	var next_print := 0
	var shots: Array[int] = [8, 24, 48, 66, 84, 102, 126, 150, 200]
	var peak_height := -INF
	var max_gap := 0.0
	while frames < 300 and is_instance_valid(body):
		if body.off_train and not chase:
			input.aim_at(player.eye_position(), body.anchor())
		if chase:
			_aim_spectator(body)
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(body):
			break
		var at := body.anchor()
		peak_height = maxf(peak_height, at.y)
		var ground_gap := TrainState.speed_mps - body.pelvis.linear_velocity.z
		max_gap = maxf(max_gap, ground_gap)
		if frames >= next_print:
			next_print += 15
			print("t=%.2f off=%s pos=(%.1f %.1f %.1f) vz=%.1f vy=%.1f spin=%.1f gap_to_ground=%.1f" % [
				frames / 60.0, body.off_train, at.x, at.y, at.z, body.pelvis.linear_velocity.z,
				body.pelvis.linear_velocity.y, body.pelvis.angular_velocity.length(), ground_gap])
		if frames in shots:
			await shot("%s_%03d" % [prefix, frames])


func _aim_spectator(body: Ragdoll) -> void:
	var at := body.anchor()
	spectator.global_position = at + Vector3(signf(at.x) * 7.0, 2.6, -7.0)
	spectator.look_at(at)


func _chase_camera_yeet() -> void:
	var target := dummy()
	if target == null:
		return
	spectator = Camera3D.new()
	spectator.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spectator.far = 2600.0
	spectator.fov = 60.0
	main.add_child(spectator)
	var door := main.train.car_by_id(&"Bistro").get_node("Door_R_-10") as TrainOpening
	door.set_open(true)
	await seconds(0.6)
	target.global_position = Vector3(0.6, 0.05, -1.0)
	await ticks(2)
	target.receive_bonk(3, Vector3.RIGHT, player)
	await ticks(2)
	var body := ragdoll()
	spectator.make_current()
	_aim_spectator(body)
	await ticks(2)
	body.throw(Vector3(9.0, 1.2, 0.0))
	await _telemetry_and_view(body, "08_chase", true)
	spectator.current = false
	camera.current = true
	spectator.queue_free()
	door.set_open(false)


func _fall_out_scenario() -> void:
	var door := main.train.car_by_id(&"Coach").get_node("Door_R_-10") as TrainOpening
	door.set_open(true)
	await seconds(0.6)
	await stand(door.global_position + Vector3(-0.9, -1.0, 0.0), door.global_position + Vector3(3.0, -0.4, 0.0))
	await ticks(2)
	await shot("10_open_door_at_speed")
	input.move = Vector2(0.0, 1.0)
	await seconds(0.6)
	input.move = Vector2.ZERO
	input.yaw = 0.0
	input.pitch = 0.05
	await seconds(0.9)
	await shot("11_dragged_looking_at_train")
	input.yaw = PI * 0.5
	input.move = Vector2(0.0, 1.0)
	while player.state == Player.State.DRAGGED and absf(player.global_position.x) > 0.8:
		await ticks(1)
	input.move = Vector2.ZERO
	input.yaw = PI
	input.pitch = -0.2
	await ticks(6)
	await shot("12_rope_prompt")
	input.yaw = 0.0
	input.pitch = 0.0
	input.press_grab()
	await seconds(1.0)
	await shot("13_reeling_in")
	await seconds(3.0)
	print("aboard=%s pos=%s" % [player.is_aboard(), player.global_position])
	input.yaw = 0.0
	await ticks(4)
	await shot("14_back_on_platform")
	input.yaw = PI
	input.pitch = -0.1
	await ticks(4)
	await shot("15_rear_view_rope")


func _touch_shots() -> void:
	await seconds(1.0)
	await shot("20_touch_overlay")
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = Vector2(180.0, 520.0)
	event.pressed = true
	main.touch._input(event)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(180.0, 450.0)
	drag.relative = Vector2(0.0, -70.0)
	main.touch._input(drag)
	await ticks(4)
	await shot("21_touch_stick")

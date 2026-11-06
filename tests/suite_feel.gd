extends RefCounted
## Game feel: events from contacts, the meaty swing, throw assist, flail and drag.

var t: Node


func _body_on_floor(at: Vector3) -> Ragdoll:
	var dummy := t.first_dummy() as TestDummy
	dummy.global_position = at
	await t.ticks(1)
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	await t.seconds(1.5)
	return ragdoll


func _grab_body(ragdoll: Ragdoll) -> void:
	var chest := ragdoll.chest
	await t.stand_player(Vector3(chest.global_position.x, 0.05, chest.global_position.z - 1.0), chest.global_position)
	await t.ticks(1)
	t.player.hands._grab(chest)
	await t.ticks(3)
	t.check(t.player.hands.held is RagdollPart, "picked the body up")


func _standing_dummies() -> Array[TestDummy]:
	var result: Array[TestDummy] = []
	for child in t.main.get_node("Npcs").get_children():
		if child is TestDummy and not child.is_queued_for_deletion():
			result.append(child)
	return result


func test_time_scale_is_never_touched() -> bool:
	var dummy := t.first_dummy() as TestDummy
	await t.knock_out(dummy)
	t.check(Engine.time_scale == 1.0, "slow motion stays a camera effect")
	return true


func test_prop_collision_emits_impact() -> bool:
	var hits: Array[float] = []
	var note := func(_body: Node3D, _at: Vector3, speed: float) -> void: hits.append(speed)
	GameEvents.impact.connect(note)
	var coal: PhysicsProp = t.main.spawn_prop(&"coal", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, -4.0)))
	await t.ticks(1)
	coal.linear_velocity = Vector3(16.0, 0.0, 0.0)
	coal.arm_thrown(t.player)
	await t.seconds(0.6)
	GameEvents.impact.disconnect(note)
	t.check(not hits.is_empty(), "a thrown prop hitting the wall reports an impact")
	t.check(not hits.is_empty() and hits[0] > 8.0, "impact speed is the speed before the hit")
	await t.seconds(3.0)
	t.check(not coal.contact_monitor, "contact monitoring turns off again")
	return true


func test_ragdoll_collision_emits_impact() -> bool:
	var count := [0]
	var note := func(_body: Node3D, _at: Vector3, _speed: float) -> void: count[0] += 1
	GameEvents.impact.connect(note)
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, -4.0))
	count[0] = 0
	ragdoll.throw(Vector3(14.0, 1.0, 0.0))
	await t.seconds(0.7)
	GameEvents.impact.disconnect(note)
	t.check(count[0] > 0, "a thrown body hitting the wall reports an impact")
	t.check(count[0] < 12, "impacts are rate limited, got %d" % count[0])
	await t.seconds(3.0)
	t.check(not ragdoll.pelvis.contact_monitor, "contact monitoring turns off again")
	return true


func test_yeeted_body_hitting_a_tree_is_reported() -> bool:
	var chosen := Vector3.INF
	for chunk: SceneryChunk in t.main.treadmill.active_chunks():
		for child in chunk.get_children():
			var shape := child as CollisionShape3D
			if shape != null and not shape.disabled and shape.shape is CylinderShape3D:
				var world: Vector3 = chunk.global_transform * shape.position
				if world.z < -30.0 and world.z > -120.0 and absf(world.x) > 6.0:
					chosen = world
	t.check(chosen != Vector3.INF, "found a tree ahead of the train")
	if chosen == Vector3.INF:
		return true
	var hits: Array[float] = []
	var note := func(_body: Node3D, speed: float) -> void: hits.append(speed)
	GameEvents.body_hit_scenery.connect(note)
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(chosen.x, Treadmill.GROUND_Y + 1.4, chosen.z + 32.0)))
	await t.ticks(1)
	crate.on_left_train()
	crate.global_position = Vector3(chosen.x, Treadmill.GROUND_Y + 1.4, chosen.z + 32.0)
	crate.linear_velocity = Vector3.ZERO
	await t.seconds(2.5)
	GameEvents.body_hit_scenery.disconnect(note)
	t.check(not hits.is_empty(), "the tree hit fired body_hit_scenery")
	t.check(not hits.is_empty() and hits[0] > 10.0, "speed is measured against the scrolling tree")
	return true


func test_swing_has_wind_up_and_follow_through() -> bool:
	var hands: Hands = t.player.hands
	t.input.press_use()
	await t.ticks(2)
	t.check(hands.is_swinging(), "the swing started")
	await t.ticks(3)
	t.check(hands.swing_amount() < -0.1, "first it pulls back, got %.2f" % hands.swing_amount())
	await t.ticks(6)
	t.check(hands.swing_amount() > 0.3, "then it comes through, got %.2f" % hands.swing_amount())
	await t.seconds(0.4)
	t.check(not hands.is_swinging(), "and it settles")
	return true


func test_bonks_hit_much_harder() -> bool:
	var dummy := t.first_dummy() as TestDummy
	await t.stand_player(dummy.global_position + Vector3(0.0, 0.0, -1.3), dummy.global_position + Vector3.UP * 1.3)
	var start: Vector3 = dummy.global_position
	t.input.press_use()
	await t.seconds(0.5)
	t.check(dummy.global_position.distance_to(start) > 0.4, "a punch shoves the dummy, %.2f m" % dummy.global_position.distance_to(start))
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	await t.seconds(0.05)
	t.check(ragdoll.center_velocity().length() < 2.0, "the victim hangs for a beat")
	await t.seconds(0.1)
	t.check(ragdoll.center_velocity().length() > 6.0, "then it is launched, %.1f m/s" % ragdoll.center_velocity().length())
	t.check(ragdoll.is_flailing(), "and it flails")
	return true


func test_heave_bends_into_an_open_window() -> bool:
	var ragdoll := await _body_on_floor(Vector3(-0.5, 0.05, -4.0))
	await _grab_body(ragdoll)
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	window.set_open(true)
	await t.seconds(0.6)
	await t.walk_to(Vector3(-0.4, 0.05, -4.0))
	# Aimed off the hole, at the edge of its frame.
	t.input.aim_at(t.player.eye_position(), window.global_position + Vector3(0.0, 0.0, 0.8))
	await t.seconds(0.4)
	t.input.throw_held = true
	await t.seconds(0.8)
	t.check(t.player.hands.assist_point != null, "the charge found the window")
	t.input.throw_held = false
	await t.ticks(2)
	t.check(ragdoll.is_guided(), "the heave is being steered")
	await t.seconds(1.0)
	t.check(is_instance_valid(ragdoll) and ragdoll.off_train, "a sloppy heave still went through")
	t.check(t.events.count("yeeted") == 1, "object_yeeted fired")
	return true


func test_heave_down_the_aisle_at_a_far_window_goes_through_the_hole() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, 3.0))
	await _grab_body(ragdoll)
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	window.set_open(true)
	await t.seconds(0.6)
	await t.walk_to(Vector3(0.6, 0.05, 2.0))
	t.input.aim_at(t.player.eye_position(), window.global_position)
	await t.seconds(0.5)
	t.input.throw_held = true
	await t.seconds(0.8)
	t.check(t.player.hands.assist_point != null, "a window seen along the wall still counts")
	t.input.throw_held = false
	var exit_z := 99.0
	for i in 90:
		await t.ticks(1)
		if is_instance_valid(ragdoll) and ragdoll.off_train:
			exit_z = ragdoll.anchor().z
			break
	t.check(is_instance_valid(ragdoll) and ragdoll.off_train, "the body left the train")
	t.check(absf(exit_z - window.global_position.z) < TrainCar.WINDOW_WIDTH * 0.5 + 0.5, "through the hole, not the wall, z=%.2f" % exit_z)
	return true


func test_heave_out_of_rear_door_clears_the_rail() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, 24.0))
	await _grab_body(ragdoll)
	var door := t.main.train.car_by_id(&"Coach").get_node("Door_Rear") as TrainOpening
	door.set_open(true)
	await t.seconds(0.6)
	await t.walk_to(Vector3(0.0, 0.05, 24.0))
	t.input.aim_at(t.player.eye_position(), door.global_position + Vector3(0.6, 0.3, 0.0))
	await t.seconds(0.4)
	t.input.throw_held = true
	await t.seconds(0.8)
	t.input.throw_held = false
	await t.seconds(1.5)
	t.check(is_instance_valid(ragdoll) and ragdoll.off_train, "over the rail and gone")
	return true


func test_heave_well_off_the_hole_or_too_far_gets_no_help() -> bool:
	var ragdoll := await _body_on_floor(Vector3(-0.5, 0.05, -4.0))
	await _grab_body(ragdoll)
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	window.set_open(true)
	await t.seconds(0.6)
	await t.walk_to(Vector3(-0.4, 0.05, -4.0))
	t.input.aim_at(t.player.eye_position(), window.global_position + Vector3(0.0, 0.0, 1.2))
	await t.seconds(0.3)
	t.input.throw_held = true
	await t.seconds(0.3)
	t.check(t.player.hands.assist_point == null, "the wall beside a window is no target")
	t.input.throw_held = false
	await t.ticks(2)
	t.check(not ragdoll.is_guided(), "the throw flies straight")
	t.check(YeetTuning.ASSIST_RANGE < Train.CAR_LENGTH * 0.5, "a heave reaches only the nearest holes")
	return true


func test_no_assist_for_closed_openings_or_behind_you() -> bool:
	var ragdoll := await _body_on_floor(Vector3(-0.5, 0.05, -4.0))
	await _grab_body(ragdoll)
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	await t.walk_to(Vector3(0.0, 0.05, -4.0))
	t.input.aim_at(t.player.eye_position(), window.global_position)
	await t.seconds(0.3)
	t.input.throw_held = true
	await t.seconds(0.3)
	t.check(t.player.hands.assist_point == null, "a closed window is no target")
	t.input.throw_held = false
	await t.ticks(2)
	t.check(not ragdoll.is_guided(), "the throw flies straight")
	await t.seconds(2.0)
	t.check(not ragdoll.off_train, "the wall stops it")
	for part in ragdoll.parts:
		t.check(part.collision_mask & Layers.HULL != 0, "the hull is solid again")
	return true


func test_guided_body_gets_its_hull_back_if_it_stays_inside() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, -4.0))
	var path: Array[Vector3] = [ragdoll.center_of_mass() + Vector3(0.0, 0.0, 1.5)]
	ragdoll.guide_to(path, 12.0)
	t.check(ragdoll.pelvis.collision_mask & Layers.HULL == 0, "guided bodies ignore the hull")
	await t.seconds(1.0)
	t.check(ragdoll.pelvis.collision_mask & Layers.HULL != 0, "and get it back")
	return true


func test_yeeted_body_flails_and_arcs_high() -> bool:
	t.opening_named(&"Bistro", "Door_R_-10").set_open(true)
	await t.seconds(0.7)
	var dummy := t.first_dummy() as TestDummy
	dummy.global_position = Vector3(0.6, 0.05, -1.0)
	await t.ticks(1)
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	ragdoll.throw(Vector3(9.0, 1.0, 0.0))
	var peak := -10.0
	var limb_spin := 0.0
	for i in 90:
		await t.ticks(1)
		if not is_instance_valid(ragdoll):
			break
		if ragdoll.off_train:
			peak = maxf(peak, ragdoll.anchor().y)
			for part in ragdoll.parts:
				if part.part_name == &"forearm_l":
					limb_spin = maxf(limb_spin, (part.angular_velocity - ragdoll.chest.angular_velocity).length())
	t.check(peak > 2.0, "the yeet arcs well above the floor, peak %.2f" % peak)
	t.check(limb_spin > 4.0, "limbs flail in the air, %.1f rad/s" % limb_spin)
	return true


func test_held_body_swung_into_an_npc_knocks_it_over() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, -4.0))
	await _grab_body(ragdoll)
	var dummies := _standing_dummies()
	var victim: TestDummy = dummies[0]
	t.input.pitch = 0.0
	await t.seconds(0.5)
	var start_yaw: float = t.input.yaw
	var toward_victim := Basis(Vector3.UP, start_yaw - 0.9) * Vector3.FORWARD
	victim.global_position = t.player.global_position + toward_victim * 1.4
	await t.ticks(2)
	t.input.yaw = start_yaw + 0.5  # Point away first, so the flick travels.
	await t.seconds(0.6)
	for i in 30:
		t.input.yaw = t.input.yaw - 0.09
		await t.ticks(1)
		if t.events.count("knocked_out") > 1:
			break
	t.check(t.events.count("bonked") >= 2, "the flying body bonked the bystander")
	t.check(t.events.count("knocked_out") == 2, "and knocked it over")
	return true


func test_clubbing_with_a_held_body_bonks() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, -4.0))
	await _grab_body(ragdoll)
	var victim: TestDummy = _standing_dummies()[0]
	await t.stand_player(t.player.global_position, t.player.eye_position() + Vector3.FORWARD)
	victim.global_position = t.player.global_position + Vector3(0.0, 0.0, -1.9)
	await t.ticks(2)
	t.input.aim_at(t.player.eye_position(), victim.global_position + Vector3.UP * 1.3)
	await t.ticks(1)
	t.input.press_use()
	await t.seconds(0.45)
	t.check(t.events.count("knocked_out") == 2, "a held body is a heavy club")
	t.check(t.player.hands.held is RagdollPart, "and it stays in hand")
	return true


func test_a_slow_drag_does_not_bonk() -> bool:
	var ragdoll := await _body_on_floor(Vector3(0.0, 0.05, -4.0))
	await _grab_body(ragdoll)
	await t.seconds(0.3)  # The aim just jumped to the body, and a jump reads as a flick.
	var before: int = t.events.count("bonked")
	var victim: TestDummy = _standing_dummies()[0]
	victim.global_position = ragdoll.chest.global_position + Vector3(0.0, -1.0, 0.5)
	await t.seconds(0.5)
	t.check(t.events.count("bonked") == before, "bumping along at walking pace is not a hit")
	return true


func test_dragging_is_slow_heavy_and_swaying() -> bool:
	await t.clear_dummies()
	var dummy: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, -6.0)), 0)
	await t.ticks(1)
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	await t.seconds(1.5)
	await _grab_body(ragdoll)
	var hands: Hands = t.player.hands
	await t.seconds(0.5)
	t.input.yaw = PI
	t.input.pitch = 0.0
	t.input.move = Vector2(0.0, 1.0)
	var fastest := 0.0
	var lowest := INF
	var highest := -INF
	var first_tick_speed := -1.0
	for i in 120:
		await t.ticks(1)
		if i == 1:
			first_tick_speed = t.player.velocity.length()
		fastest = maxf(fastest, t.player.velocity.length())
		lowest = minf(lowest, hands.drag_sway())
		highest = maxf(highest, hands.drag_sway())
	t.input.move = Vector2.ZERO
	t.check(hands.held is RagdollPart, "still holding the body")
	t.check(fastest < Player.WALK_SPEED * 0.85, "a body slows you down, %.2f m/s" % fastest)
	t.check(first_tick_speed < 2.0, "it takes time to get moving, %.2f m/s" % first_tick_speed)
	t.check(highest > 0.7 and lowest < -0.7, "the body sways side to side")
	return true


func test_full_charge_shows_on_camera_and_sprint_leans() -> bool:
	var camera: PlayerCamera = t.player.get_node("Camera")
	await t.clear_dummies()
	await t.stand_player(Vector3(0.0, 0.05, -7.7), Vector3(0.0, 1.6, 0.0))
	await t.seconds(0.4)
	var fov_at_rest: float = camera.fov
	t.input.move = Vector2(0.0, 1.0)
	t.input.sprint = true
	await t.seconds(1.0)
	t.check(t.player.sprinting, "the player knows it is sprinting")
	t.check(camera.fov > fov_at_rest + 2.0 or DisplayServer.get_name() == "headless", "sprint widens the view")
	t.input.move = Vector2.ZERO
	t.input.sprint = false
	await t.seconds(0.1)
	var wrench: PhysicsProp = t.nearest_prop(&"wrench")
	await t.stand_player(wrench.global_position + Vector3(0.9, -0.8, 0.5), wrench.global_position)
	await t.ticks(1)
	t.input.press_grab()
	await t.ticks(4)
	t.input.throw_held = true
	await t.seconds(0.85)
	t.check(is_equal_approx(t.player.hands.charge_fraction(), 1.0), "the charge fills")
	t.input.throw_held = false
	await t.ticks(2)
	t.check(t.player.hands.charge_fraction() == 0.0, "and empties on release")
	return true


func test_effects_fire_from_events_without_errors() -> bool:
	var camera: PlayerCamera = t.player.get_node("Camera")
	var fx: ImpactFx = camera.get_node("ImpactFx")
	var dummy := t.first_dummy() as TestDummy
	await t.knock_out(dummy)
	t.check(fx.active_word_count() == 1, "one word per hit: the knockout")
	await t.seconds(2.0)
	t.check(fx.active_word_count() == 0, "and they clear away")
	return true

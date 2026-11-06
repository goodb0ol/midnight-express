extends RefCounted
## NPC brain checks. Each test owns its passengers: it clears the defaults, spawns what it
## needs far from the player, and turns the brain off again before returning.

const GET_UP := preload("res://scripts/npc/get_up.gd")

var t: Node
var panicked: Array[Node3D] = []


func _start() -> void:
	await t.clear_dummies()
	# Park the player in the Locomotive, away from every test unless it moves them.
	t.player.global_position = Vector3(-1.0, 0.05, -19.0)
	panicked.clear()
	if not GameEvents.npc_panicked.is_connected(_on_panicked):
		GameEvents.npc_panicked.connect(_on_panicked)
	TestDummy.brain_enabled = true
	await t.ticks(1)


func _finish() -> bool:
	TestDummy.brain_enabled = false
	GameEvents.npc_panicked.disconnect(_on_panicked)
	return true


func _on_panicked(npc: Node3D, _position: Vector3) -> void:
	panicked.append(npc)


func _spawn(at: Vector3, passenger := "gran") -> TestDummy:
	var dummy: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, at), BodyPlan.PASSENGERS.find(passenger))
	return dummy


## Puts the player [param gap] metres before [param z] and sprints them toward +Z.
func _sprint_into(z: float, gap := 5.0) -> void:
	await t.stand_player(Vector3(0.0, 0.05, z - gap), Vector3(0.0, 1.0, z + 5.0))
	t.input.sprint = true
	t.input.move = Vector2(0.0, 1.0)


func _stop_player() -> void:
	t.input.move = Vector2.ZERO
	t.input.sprint = false


func _npc_ragdolls() -> Array[Ragdoll]:
	return t._ragdolls()


func _dummies() -> Array[TestDummy]:
	var result: Array[TestDummy] = []
	for child: Node in t.main.get_node("Npcs").get_children():
		if child is TestDummy and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _wait_for_ragdoll(limit_seconds: float) -> Ragdoll:
	for i in roundi(limit_seconds * 60.0):
		await t.ticks(1)
		if not _npc_ragdolls().is_empty():
			return _npc_ragdolls()[0]
	return null


func test_npc_brain_off_stands_still() -> bool:
	await _start()
	TestDummy.brain_enabled = false
	var dummy := _spawn(Vector3(0.0, 0.05, 3.0))
	await t.seconds(4.0)
	t.check_near(dummy.global_position.z, 3.0, 0.01, "stays put")
	t.check(dummy.mode == TestDummy.Mode.IDLE, "stays idle")
	return _finish()


func test_npc_walks_through_gangway_and_swings_limbs() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 6.0))
	await t.ticks(2)
	dummy.walk_to(14.0)
	var thigh := dummy.get_node("Visual/pelvis/thigh_l") as Node3D
	var arm := dummy.get_node("Visual/pelvis/chest/upper_arm_r") as Node3D
	var thigh_range := 0.0
	var arm_range := 0.0
	var roll_range := 0.0
	for i in 60 * 9:
		await t.ticks(1)
		thigh_range = maxf(thigh_range, absf(thigh.rotation.x))
		arm_range = maxf(arm_range, absf(arm.rotation.x))
		roll_range = maxf(roll_range, absf((dummy.get_node("Visual") as Node3D).rotation.z))
	t.check(dummy.global_position.z > 11.0, "crossed into the Coach, z %.2f" % dummy.global_position.z)
	t.check(thigh_range > 0.2, "legs walk, %.2f rad" % thigh_range)
	t.check(arm_range > 0.2, "arms swing, %.2f rad" % arm_range)
	t.check(roll_range > 0.05, "body waddles, %.2f rad" % roll_range)
	return _finish()


func test_npc_wanders_on_its_own() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 3.0))
	var travelled := 0.0
	var last := dummy.global_position
	for i in 60 * 14:
		await t.ticks(1)
		travelled += last.distance_to(dummy.global_position)
		last = dummy.global_position
	t.check(travelled > 2.0, "wandered %.1f m" % travelled)
	return _finish()


func test_npc_turns_to_face_nearby_player() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 3.0))
	await t.ticks(2)
	await t.stand_player(Vector3(1.0, 0.05, 1.0), Vector3(0.0, 1.0, 3.0))
	await t.seconds(1.0)
	var forward := -dummy.global_basis.z
	var to_player: Vector3 = (t.player.global_position - dummy.global_position).normalized()
	if dummy.mode == TestDummy.Mode.IDLE:  # A wander may have begun; only idlers turn.
		t.check(forward.dot(to_player) > 0.8, "faces the player, dot %.2f" % forward.dot(to_player))
	return _finish()


func test_npc_panic_spreads_and_runs_with_arms_up() -> bool:
	await _start()
	var victim := _spawn(Vector3(0.0, 0.05, 2.0))
	var witness := _spawn(Vector3(0.0, 0.05, 6.0))
	await t.ticks(2)
	var z_before := witness.global_position.z
	victim.receive_bonk(3, Vector3.BACK, t.player)
	await t.ticks(1)
	t.check(panicked.has(witness), "witness shrieked through npc_panicked")
	t.check(panicked.count(witness) == 1, "one shriek per panic")
	t.check(witness.mode == TestDummy.Mode.PANIC, "witness panics")
	await t.seconds(1.2)
	t.check(witness.global_position.z > z_before + 3.0, "sprints away, moved %.2f m" % (witness.global_position.z - z_before))
	var arm := witness.get_node("Visual/pelvis/chest/upper_arm_l") as Node3D
	t.check(arm.rotation.x > 2.0, "arms up, %.2f rad" % arm.rotation.x)
	await t.seconds(TestDummy.PANIC_TIME_MAX)
	t.check(witness.mode != TestDummy.Mode.PANIC, "calms down after a few seconds")
	return _finish()


func test_npc_non_fatal_bonk_panics_the_victim() -> bool:
	await _start()
	var victim := _spawn(Vector3(0.0, 0.05, 2.0))
	await t.ticks(2)
	victim.receive_bonk(1, Vector3.BACK, t.player)
	await t.ticks(1)
	t.check(victim.mode == TestDummy.Mode.PANIC, "bonked passenger runs")
	return _finish()


func test_npc_panic_range_and_sight() -> bool:
	await _start()
	var victim := _spawn(Vector3(0.0, 0.05, 0.0))
	# Beyond 8 m, but down the open aisle through the gangway.
	var seen := _spawn(Vector3(0.0, 0.05, 14.0))
	# Beyond 8 m and out of line with the gangway door.
	var hidden := _spawn(Vector3(1.4, 0.05, -12.0))
	await t.ticks(2)
	victim.receive_bonk(1, Vector3.BACK, t.player)
	await t.ticks(1)
	t.check(seen.mode == TestDummy.Mode.PANIC, "panics on sight past 8 m")
	t.check(hidden.mode != TestDummy.Mode.PANIC, "no sight and no earshot, no panic")
	return _finish()


func test_npc_stowaway_marker_and_copy_to_ragdoll() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 3.0))
	await t.ticks(1)
	t.check(not dummy.has_node("StowawayMarker"), "a passenger has no marker")
	dummy.is_stowaway = true
	t.check(dummy.has_node("StowawayMarker"), "marker appears when the role is set after spawn")
	await t.ticks(1)
	var marker := dummy.get_node("StowawayMarker") as Node3D
	var height := marker.global_position.y
	t.check(height > 2.0, "marker floats above the head, %.2f" % height)
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	t.check(ragdoll.is_stowaway, "role copied onto the ragdoll")
	t.check(ragdoll.chest.has_node("StowawayMarker"), "the body stays marked")
	return _finish()


func test_npc_passenger_body_is_not_stowaway() -> bool:
	await _start()
	var ragdoll: Ragdoll = await t.knock_out(_spawn(Vector3(0.0, 0.05, 3.0)))
	t.check(not ragdoll.is_stowaway, "paying passenger stays one")
	return _finish()


func test_npc_stowaway_flees_and_hides() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 15.0))
	dummy.is_stowaway = true
	await t.ticks(2)
	await t.stand_player(Vector3(0.0, 0.05, 11.0), Vector3(0.0, 1.0, 15.0))
	await t.seconds(0.5)
	t.check(dummy.mode == TestDummy.Mode.FLEE, "bolts when the player is near")
	await t.seconds(5.0)
	t.check(dummy.mode == TestDummy.Mode.HIDE, "reached a hiding place, mode %d" % dummy.mode)
	t.check(dummy.global_position.z > 20.0, "ran for the far end, z %.2f" % dummy.global_position.z)
	t.check(absf(dummy.global_position.x) > 0.9, "tucked between seats, x %.2f" % dummy.global_position.x)
	await t.seconds(0.5)
	t.check(((dummy.get_node("Visual/pelvis/thigh_l") as Node3D).rotation.x) > 1.0, "crouches")
	var player_z: float = dummy.global_position.z - 2.0
	await t.stand_player(Vector3(0.0, 0.05, player_z), dummy.global_position)
	await t.seconds(0.4)
	t.check(dummy.mode != TestDummy.Mode.HIDE, "breaks cover when found")
	await t.seconds(2.0)
	t.check(dummy.global_position.z < player_z - 1.0, "bolted past the player to the open train, z %.2f, player %.2f" % [dummy.global_position.z, player_z])
	return _finish()


func test_npc_bolt_is_not_cancelled_by_the_player_in_the_way() -> bool:
	await _start()
	var dummy := _spawn(Vector3(-1.2, 0.05, 23.25), "smuggler")
	dummy.is_stowaway = true
	await t.ticks(2)
	dummy.mode = TestDummy.Mode.HIDE
	await t.stand_player(Vector3(0.0, 0.05, 21.0), Vector3(-1.2, 1.0, 23.25))
	var deepest := -INF
	var mode_flips := 0
	var last_mode := dummy.mode
	for i in 60 * 2:
		await t.ticks(1)
		deepest = maxf(deepest, dummy.global_position.z)
		mode_flips += 1 if dummy.mode != last_mode else 0
		last_mode = dummy.mode
	t.check(deepest < 23.6, "never turned back into the dead end, deepest z %.2f" % deepest)
	t.check(dummy.global_position.z < 20.0, "came out the far side of the player, z %.2f" % dummy.global_position.z)
	t.check(mode_flips <= 1, "one clean break, %d flips" % mode_flips)
	t.check(not dummy._bolting, "bolt finished once clear of the player")
	t.check(not dummy.get_collision_exceptions().has(t.player), "solid to the player again")
	t.check(not t.player.get_collision_exceptions().has(dummy), "player solid to it again")
	return _finish()


func test_npc_cornered_stowaway_cowers_then_bolts() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 27.0), "smuggler")
	dummy.is_stowaway = true
	await t.ticks(2)
	await t.stand_player(Vector3(0.0, 0.05, 25.0), Vector3(0.0, 1.0, 27.0))
	for i in 120:
		await t.ticks(1)
		if dummy._winded_left > 0.0:
			break
	t.check(dummy.mode == TestDummy.Mode.HIDE, "cowers when found at the train end, mode %d" % dummy.mode)
	t.check(dummy._winded_left > 0.0, "winded")
	var kept_hiding := true
	var low_z := INF
	var high_z := -INF
	for i in roundi(TestDummy.WINDED_TIME * 60.0) - 6:
		await t.ticks(1)
		kept_hiding = kept_hiding and dummy.mode == TestDummy.Mode.HIDE
		low_z = minf(low_z, dummy.global_position.z)
		high_z = maxf(high_z, dummy.global_position.z)
	t.check(kept_hiding, "stayed in HIDE for WINDED_TIME")
	t.check(high_z - low_z < 0.1, "no shuttling, moved %.2f m" % (high_z - low_z))
	t.check(((dummy.get_node("Visual/pelvis/thigh_l") as Node3D).rotation.x) > 1.0, "crouched the whole time")
	await t.seconds(2.0)
	t.check(dummy.global_position.z < 25.0, "then ducks past the player, z %.2f" % dummy.global_position.z)
	return _finish()


func test_npc_cowering_stowaway_can_be_hit_without_running() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 27.0), "smuggler")
	dummy.is_stowaway = true
	await t.ticks(2)
	await t.stand_player(Vector3(0.0, 0.05, 25.0), Vector3(0.0, 1.0, 27.0))
	for i in 120:
		await t.ticks(1)
		if dummy._winded_left > 0.0:
			break
	dummy.receive_bonk(1, Vector3.BACK, t.player)
	await t.ticks(30)
	t.check(dummy.mode == TestDummy.Mode.HIDE, "a bonk does not end the cower, mode %d" % dummy.mode)
	return _finish()


func test_npc_hider_with_open_side_runs_the_open_way() -> bool:
	await _start()
	var dummy := _spawn(Vector3(1.2, 0.05, 13.25), "smuggler")
	dummy.is_stowaway = true
	await t.ticks(2)
	dummy.mode = TestDummy.Mode.HIDE
	await t.stand_player(Vector3(0.0, 0.05, 11.0), Vector3(1.2, 1.0, 13.25))
	await t.seconds(0.4)
	t.check(dummy.mode == TestDummy.Mode.FLEE and not dummy._bolting, "no need to pass the player")
	t.check(dummy._goal.z > 13.25, "runs on down the train, goal z %.2f" % dummy._goal.z)
	return _finish()


func test_npc_body_cap_spares_stowaways_and_still_reacts() -> bool:
	await _start()
	var passenger := _spawn(Vector3(0.0, 0.05, 2.0), "baron")
	var stowaway := _spawn(Vector3(0.0, 0.05, 8.0), "stoker")
	stowaway.is_stowaway = true
	await t.ticks(2)
	var real_bodies := TestDummy._loose_bodies.duplicate()
	TestDummy._loose_bodies.resize(TestDummy.MAX_BODIES_DOWN)
	passenger.tip_over(Vector3.BACK, 5.0, t.player)
	stowaway.tip_over(Vector3.BACK, 5.0, t.player)
	TestDummy._loose_bodies = real_bodies
	await t.ticks(2)
	t.check(is_instance_valid(passenger) and passenger.mode == TestDummy.Mode.PANIC, "capped passenger reels and runs")
	t.check(_npc_ragdolls().size() == 1 and _npc_ragdolls()[0].is_stowaway, "stowaway tips regardless of the cap")
	return _finish()


func test_npc_shove_stops_at_a_wall() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 6.0), "baron")
	await t.ticks(2)
	dummy._immune_left = 0.0
	TestDummy.brain_enabled = false
	t.player.global_position = Vector3(0.0, 0.05, 5.2)
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.HULL
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 0.1)
	shape.shape = box
	wall.add_child(shape)
	t.main.add_child(wall)
	wall.global_position = Vector3(0.0, 1.0, 5.6)
	await t.ticks(2)
	t.player.velocity = Vector3(0.0, 0.0, TestDummy.SHOVE_TIP_SPEED + 1.0)
	dummy._tick_contacts()
	t.check(not dummy.is_queued_for_deletion(), "no shove through a wall")
	wall.queue_free()
	await t.ticks(2)
	t.player.velocity = Vector3(0.0, 0.0, TestDummy.SHOVE_TIP_SPEED + 1.0)
	dummy._tick_contacts()
	t.check(dummy.is_queued_for_deletion(), "same shove lands with the wall gone")
	return _finish()


func test_npc_unseen_limbs_update_slowly() -> bool:
	await _start()
	await t.stand_player(Vector3(0.0, 0.05, 3.0), Vector3(0.0, 1.0, 9.0))
	var seen := _spawn(Vector3(0.0, 0.05, 7.0))
	var behind := _spawn(Vector3(0.0, 0.05, -1.0))
	var walled := _spawn(Vector3(0.0, 0.05, 9.6 + 8.0))
	walled.global_position.x = 1.4
	await t.ticks(20)
	t.check(seen._anim_step == 0.0, "visible passenger animates every frame")
	t.check(behind._anim_step == TestDummy.HIDDEN_ANIM_STEP, "behind the camera is skipped")
	t.check(walled._anim_step == TestDummy.HIDDEN_ANIM_STEP, "behind a bulkhead is skipped")
	return _finish()


func test_npc_sprint_shove_tips_tough_passenger_who_gets_up() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 6.0), "baron")
	dummy.hp = 2
	await t.ticks(2)
	await _sprint_into(6.0)
	var ragdoll := await _wait_for_ragdoll(2.0)
	_stop_player()
	t.check(ragdoll != null, "sprint tips the passenger over")
	if ragdoll == null:
		return _finish()
	t.check(t.events.count("knocked_out") == 0, "a shove is not a knockout")
	t.check(_dummies().is_empty(), "standing passenger replaced by the body")
	await t.seconds(GET_UP.STAY_DOWN + GET_UP.MAX_WAIT + 0.5)
	t.check(not is_instance_valid(ragdoll), "body gone")
	var up := _dummies()
	t.check(up.size() == 1, "passenger stood back up")
	if not up.is_empty():
		t.check(up[0].hp == 2, "bruises carry over")
		t.check(up[0].passenger == "baron", "same passenger")
		t.check(absf(up[0].global_position.x) <= TestDummy.AISLE_LANE, "stands in the aisle")
	await t.ticks(5)
	t.check(GET_UP.active == 0, "watch released")
	return _finish()


func test_npc_shove_then_grab_keeps_body_down() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 6.0), "stoker")
	dummy.is_stowaway = true
	await t.ticks(2)
	dummy.tip_over(Vector3.BACK, 5.0, t.player)
	var ragdoll := await _wait_for_ragdoll(5.0)
	t.check(ragdoll != null and ragdoll.is_stowaway, "shoved over, role kept")
	if ragdoll == null:
		return _finish()
	ragdoll.holder = t.player.hands
	await t.seconds(GET_UP.STAY_DOWN + GET_UP.MAX_WAIT + 0.5)
	ragdoll.holder = null
	t.check(is_instance_valid(ragdoll), "dragged body stays a body")
	t.check(_dummies().is_empty(), "nobody stood up")
	return _finish()


func test_npc_bonk_on_shoved_body_keeps_it_down() -> bool:
	await _start()
	_spawn(Vector3(0.0, 0.05, 6.0), "gran")
	await t.ticks(2)
	await _sprint_into(6.0)
	var ragdoll := await _wait_for_ragdoll(2.0)
	_stop_player()
	if ragdoll == null:
		t.check(false, "shove landed")
		return _finish()
	# A body on the move slides out of the swing, so wait for it to come to rest.
	await t.seconds(1.0)
	for i in 60:
		if ragdoll.chest.linear_velocity.length() < 0.3:
			break
		await t.ticks(1)
	var chest := ragdoll.chest.global_position
	await t.stand_player(Vector3(chest.x, 0.05, chest.z - 1.3), chest)
	t.input.press_use()
	await t.seconds(0.3)
	t.check(t.events.count("knocked_out") == 1, "the bonk counts as a knockout")
	await t.seconds(GET_UP.STAY_DOWN + GET_UP.MAX_WAIT)
	t.check(is_instance_valid(ragdoll), "a bonked body stays down")
	t.check(_dummies().is_empty(), "nobody stood up")
	return _finish()


func test_npc_fragile_passenger_faints_from_shove() -> bool:
	await _start()
	_spawn(Vector3(0.0, 0.05, 6.0), "intern")
	await t.ticks(2)
	await _sprint_into(6.0)
	var ragdoll := await _wait_for_ragdoll(2.0)
	_stop_player()
	t.check(ragdoll != null, "tipped")
	t.check(t.events.count("knocked_out") == 1, "fainting is a knockout")
	await t.seconds(GET_UP.STAY_DOWN + GET_UP.MAX_WAIT + 0.5)
	t.check(_dummies().is_empty(), "stays down")
	return _finish()


func test_npc_walk_shove_stumbles_without_tipping() -> bool:
	await _start()
	var dummy := _spawn(Vector3(0.0, 0.05, 6.0))
	await t.ticks(2)
	await t.stand_player(Vector3(0.0, 0.05, 3.0), Vector3(0.0, 1.0, 9.0))
	t.input.move = Vector2(0.0, 1.0)
	await t.seconds(1.0)
	_stop_player()
	t.check(_npc_ragdolls().is_empty(), "a walking shove leaves them standing")
	t.check(dummy.global_position.z > 6.3, "passenger was pushed, z %.2f" % dummy.global_position.z)
	return _finish()


func test_npc_panicked_runner_bumps_others_over() -> bool:
	await _start()
	var hit_anyone := false
	for round_number in 6:
		var standing := _spawn(Vector3(0.0, 0.05, 14.0))
		var runner := _spawn(Vector3(0.0, 0.05, 11.0))
		await t.ticks(2)
		runner._hear_alarm(Vector3(0.0, 0.05, 7.0))
		await t.seconds(1.5)
		var scattered := not is_instance_valid(standing) or standing.mode == TestDummy.Mode.PANIC
		hit_anyone = hit_anyone or scattered
		for child: Node in t.main.get_node("Npcs").get_children():
			child.queue_free()
		await t.ticks(2)
		if hit_anyone:
			break
	t.check(hit_anyone, "a sprinting passenger upends the one in the way")
	return _finish()


func test_npc_thrown_body_bowls_passenger_over() -> bool:
	await _start()
	var pin := _spawn(Vector3(0.0, 0.05, 5.0), "stoker")
	var ball := _spawn(Vector3(0.0, 0.05, 2.0), "intern")
	await t.ticks(2)
	TestDummy.brain_enabled = false
	var ragdoll: Ragdoll = await t.knock_out(ball)
	TestDummy.brain_enabled = true
	ragdoll.throw(Vector3(0.0, 1.0, 11.0))
	await t.seconds(1.0)
	t.check(not is_instance_valid(pin) or pin.is_queued_for_deletion(), "thrown body knocks the passenger over")
	return _finish()


func test_npc_shoved_out_of_open_door_is_yeeted() -> bool:
	await _start()
	t.opening_named(&"Bistro", "Door_R_-10").set_open(true)
	await t.seconds(0.7)
	var dummy := _spawn(Vector3(1.0, 0.05, -1.0), "stoker")
	await t.ticks(2)
	dummy._knockback = Vector3(9.0, 0.0, 0.0)
	dummy.tip_over(Vector3.RIGHT, 9.0, t.player)
	await t.seconds(1.5)
	t.check(t.events.count("yeeted") == 1, "the shove carried them overboard")
	return _finish()


func test_npc_twelve_stay_aboard_and_cheap() -> bool:
	await _start()
	var dummies: Array[TestDummy] = []
	for i in 12:
		var dummy := _spawn(Vector3(0.0, 0.05, -6.0 + i * 3.0))
		dummy.is_stowaway = i % 4 == 0
		dummies.append(dummy)
	await t.ticks(2)
	dummies[5].receive_bonk(3, Vector3.BACK, t.player)
	t.player.global_position = Vector3(0.0, 0.05, 2.0)
	var started := Time.get_ticks_usec()
	var frames := 0
	for i in 60 * 25:
		await t.ticks(1)
		frames += 1
		if i == 300 and is_instance_valid(dummies[2]):
			dummies[2].receive_bonk(1, Vector3.BACK, t.player)
	var per_tick := float(Time.get_ticks_usec() - started) / frames / 1000.0
	var hull: AABB = t.main.train.hull
	var inside := 0
	var alive := _dummies()
	for dummy in alive:
		if hull.has_point(dummy.global_position + Vector3.UP * 0.9):
			inside += 1
	t.check(inside == alive.size(), "all %d stayed aboard, %d inside" % [alive.size(), inside])
	t.check(alive.size() >= 8, "crowd survived, %d left" % alive.size())
	print("  12 npcs: %.2f ms per tick (whole game, headless)" % per_tick)
	t.check(per_tick < 16.0, "fits a 60 Hz tick, %.2f ms" % per_tick)
	return _finish()

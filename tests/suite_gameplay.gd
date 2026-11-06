extends RefCounted
## Rules, controls and bugs that cut across the other suites: stowaways that keep a decision,
## shoves that work, the mid-swing fall, the sound after a respawn, a clean log.

var t: Node


func _spawn(at: Vector3, passenger := "gran", stowaway := false) -> TestDummy:
	var transform := Transform3D(Basis.IDENTITY, at)
	return t.main.spawn_dummy(transform, BodyPlan.PASSENGERS.find(passenger), stowaway)


func _dummies() -> Array[TestDummy]:
	var result: Array[TestDummy] = []
	for child: Node in t.main.get_node("Npcs").get_children():
		if child is TestDummy and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _nearest_to_player() -> TestDummy:
	var nearest: TestDummy = null
	var best := INF
	for dummy in _dummies():
		var distance: float = dummy.global_position.distance_to(t.player.global_position)
		if distance < best:
			best = distance
			nearest = dummy
	return nearest


func _park_player() -> void:
	t.player.global_position = Vector3(-1.0, 0.05, -19.0)
	await t.ticks(1)


## A body lying at [param at], picked up and held. The brain stays off until it is in hand.
func _carry_body_from(at: Vector3) -> Ragdoll:
	var ragdoll: Ragdoll = await t.knock_out(_spawn(at))
	await t.seconds(1.5)
	var chest: RagdollPart = ragdoll.chest
	await t.stand_player(Vector3(chest.global_position.x, 0.05, chest.global_position.z - 1.0), chest.global_position)
	t.player.hands._grab(chest)
	await t.ticks(3)
	t.check(t.player.hands.held is RagdollPart, "picked the body up")
	return ragdoll


func _modes_changed(dummy: TestDummy, seconds: float) -> int:
	var flips := 0
	var last := dummy.mode
	for i in roundi(seconds * 60.0):
		await t.ticks(1)
		if not is_instance_valid(dummy):
			break
		flips += 1 if dummy.mode != last else 0
		last = dummy.mode
	return flips


func test_dice_repeat_for_the_same_salt_and_spawn_order() -> bool:
	await t.clear_dummies()
	TrainState.rng_serial = 500
	var first := _spawn(Vector3(0.0, 0.05, 3.0))
	await t.ticks(1)
	TrainState.rng_serial = 500
	var second := _spawn(Vector3(0.0, 0.05, 4.0))
	await t.ticks(1)
	t.check(first._time_offset == second._time_offset, "same spawn slot, same dice")
	TrainState.rng_salt += 1
	TrainState.rng_serial = 500
	var third := _spawn(Vector3(0.0, 0.05, 5.0))
	await t.ticks(1)
	t.check(first._time_offset != third._time_offset, "another salt, other dice")
	return true


func test_stowaway_decisions_hold_when_cornered() -> bool:
	# Dead ends at both ends of the train, with the player standing right on the hider.
	var cases: Array[Array] = [
		[Vector3(1.2, 0.05, 25.25), Vector3(0.0, 0.05, 23.5)],
		[Vector3(-1.2, 0.05, 23.25), Vector3(0.0, 0.05, 22.0)],
		[Vector3(0.0, 0.05, 27.0), Vector3(0.0, 0.05, 25.5)],
		[Vector3(-1.2, 0.05, -21.5), Vector3(-0.6, 0.05, -20.0)],
		[Vector3(-1.3, 0.05, -19.2), Vector3(-0.8, 0.05, -17.8)],
	]
	TestDummy.brain_enabled = true
	for entry in cases:
		await t.clear_dummies()
		await _park_player()
		var dummy := _spawn(entry[0], "smuggler", true)
		await t.ticks(2)
		dummy.mode = TestDummy.Mode.HIDE
		await t.stand_player(entry[1], entry[0])
		var flips: int = await _modes_changed(dummy, 5.0)
		t.check(flips <= 5, "at %s it changed its mind %d times in 5 s" % [str(entry[0]), flips])
	TestDummy.brain_enabled = false
	return true


func test_a_stowaway_decision_lasts_the_commit_time() -> bool:
	await t.clear_dummies()
	TestDummy.brain_enabled = true
	await _park_player()
	var dummy := _spawn(Vector3(1.2, 0.05, 13.25), "smuggler", true)
	await t.ticks(2)
	dummy._enter_hide()
	await t.stand_player(Vector3(0.0, 0.05, 11.5), Vector3(1.2, 1.0, 13.25))
	var held_hide := true
	for i in roundi(TestDummy.COMMIT_TIME * 54.0):
		await t.ticks(1)
		held_hide = held_hide and dummy.mode == TestDummy.Mode.HIDE
	t.check(held_hide, "just hid, so it stays hid with the player on top of it")
	await t.seconds(0.4)
	t.check(dummy.mode == TestDummy.Mode.FLEE, "then it runs")
	var goal := dummy._goal
	dummy._hear_alarm(dummy.global_position + Vector3(0.0, 0.0, 2.0))
	await t.ticks(2)
	t.check(dummy._goal == goal, "a noise does not turn a runner around")
	TestDummy.brain_enabled = false
	return true


func test_walking_player_gets_through_a_centred_idle_passenger() -> bool:
	await t.clear_dummies()
	TestDummy.brain_enabled = true
	var dummy := _spawn(Vector3(0.0, 0.05, 4.0), "stoker")
	await t.ticks(2)
	dummy._mode_left = 60.0  # It stands there and has no plans.
	await t.stand_player(Vector3(0.0, 0.05, 2.0), Vector3(0.0, 1.0, 9.0))
	t.input.move = Vector2(0.0, 1.0)
	await t.seconds(3.0)
	t.input.move = Vector2.ZERO
	t.check(t.player.global_position.z > 6.5, "kept walking, z %.2f" % t.player.global_position.z)
	t.check(dummy.global_position.distance_to(Vector3(0.0, 0.05, 4.0)) > 1.0, "the passenger gave way")
	t.check(t.main.get_node("Npcs").get_child_count() == 1 and is_instance_valid(dummy), "still on their feet")
	TestDummy.brain_enabled = false
	return true


func test_leaning_on_a_passenger_is_felt_with_no_velocity_left() -> bool:
	await t.clear_dummies()
	var dummy := _spawn(Vector3(0.0, 0.05, 3.0), "stoker")
	await t.stand_player(Vector3(0.0, 0.05, 2.3), Vector3(0.0, 1.0, 9.0))
	t.player.velocity = Vector3.ZERO
	t.player.wish_velocity = Vector3(0.0, 0.0, Player.WALK_SPEED)
	dummy._tick_contacts()
	t.check(dummy._knockback.z > 0.0, "the wish alone shoves, %.2f" % dummy._knockback.z)
	return true


func test_a_walk_does_not_stop_a_bolt() -> bool:
	await t.clear_dummies()
	TestDummy.brain_enabled = true
	await _park_player()
	var dummy := _spawn(Vector3(-1.2, 0.05, 23.25), "smuggler", true)
	await t.ticks(2)
	dummy.mode = TestDummy.Mode.HIDE
	await t.stand_player(Vector3(0.0, 0.05, 21.0), Vector3(-1.2, 1.0, 23.25))
	t.input.move = Vector2(0.0, 1.0)
	await t.seconds(1.0)
	t.input.move = Vector2.ZERO
	t.check(dummy.global_position.z < t.player.global_position.z, "ran past a walking player, z %.2f" % dummy.global_position.z)
	TestDummy.brain_enabled = false
	return true


func test_first_stowaway_holds_for_the_card_then_runs_without_a_stampede() -> bool:
	TestDummy.brain_enabled = true
	var knocked: int = t.events.count("knocked_out")
	var director: RoundDirector = t.main.start_rounds()
	await t.ticks(2)
	var starts: Dictionary = {}
	for dummy in _dummies():
		starts[dummy] = dummy.global_position
	var first := _nearest_to_player()
	t.check(first.is_stowaway, "the first body met is a stowaway")
	t.check(first.global_position.distance_to(t.player.global_position) < TestDummy.FLEE_RADIUS, "and it starts inside flee range")
	await t.seconds(RoundDirector.TITLE_SECONDS - 0.2)
	for dummy: TestDummy in starts:
		t.check(dummy.global_position.distance_to(starts[dummy]) < 0.01, "%s holds behind the card" % dummy.name)
		t.check(dummy.mode == TestDummy.Mode.IDLE, "%s has not reacted yet" % dummy.name)
	await t.seconds(4.0)
	t.check(director.phase == RoundDirector.Phase.RAID, "raid running")
	t.check(is_instance_valid(first), "the runner stayed on its feet")
	t.check(t._ragdolls().is_empty(), "nobody was bowled over, %d down" % t._ragdolls().size())
	t.check(t.events.count("knocked_out") == knocked, "and nobody fainted")
	TestDummy.brain_enabled = false
	return true


func test_sound_respawn_puts_the_train_back() -> bool:
	if not Sfx.is_baked:
		await Sfx.baked
	await t.seconds(1.0)
	var aboard: float = Sfx.rumble.volume_db
	t.player.on_left_train()
	await t.seconds(2.0)
	t.check(Sfx._off_train, "off the train")
	t.check(Sfx.rumble.volume_db < aboard - 6.0, "the train fades away")
	t.player.respawn()
	t.check(not Sfx._off_train, "a respawn is aboard")
	await t.seconds(1.5)
	t.check_near(Sfx.rumble.volume_db, aboard, 1.0, "the train is back")
	return true


func test_sound_new_raid_while_dragged_sounds_aboard() -> bool:
	if not Sfx.is_baked:
		await Sfx.baked
	t.player.on_left_train()
	await t.ticks(2)
	t.main.start_rounds()
	await t.ticks(2)
	t.check(t.player.is_aboard(), "the raid starts aboard")
	t.check(not Sfx._off_train, "and sounds like it")
	return true


func test_sound_both_reverbs_cut_the_rumble() -> bool:
	t.check(Sfx.REVERB_HIPASS > 0.0, "a highpass exists")
	t.check_near(Sfx._sfx_reverb.hipass, Sfx.REVERB_HIPASS, 0.001, "on the effects reverb")
	t.check_near(Sfx._ambience_reverb.hipass, Sfx.REVERB_HIPASS, 0.001, "on the ambience reverb")
	return true


func test_falling_off_mid_swing_drops_the_swing() -> bool:
	var hands: Hands = t.player.hands
	var dummy := t.first_dummy() as TestDummy
	var stand: Vector3 = dummy.global_position + Vector3(0.0, 0.0, -1.3)
	await t.stand_player(stand, dummy.global_position + Vector3.UP * 1.3)
	t.input.press_use()
	t.input.press_use()
	await t.ticks(4)
	t.check(hands.is_swinging(), "wound up")
	t.player.on_left_train()
	t.check(not hands.is_swinging(), "no swing outside")
	t.check(hands.swing_amount() == 0.0, "no fist frozen in the air")
	await t.ticks(4)
	t.player._board()
	await t.stand_player(stand, dummy.global_position + Vector3.UP * 1.3)
	await t.seconds(0.6)
	t.check(t.events.count("bonked") == 0, "nothing lands on reboarding, got %d" % t.events.count("bonked"))
	t.check(not hands.is_swinging(), "and nothing was queued")
	return true


func test_a_fresh_swing_works_after_reboarding() -> bool:
	var dummy := t.first_dummy() as TestDummy
	var stand: Vector3 = dummy.global_position + Vector3(0.0, 0.0, -1.3)
	await t.stand_player(stand, dummy.global_position + Vector3.UP * 1.3)
	t.input.press_use()
	await t.ticks(4)
	t.player.on_left_train()
	await t.ticks(2)
	t.player._board()
	await t.stand_player(stand, dummy.global_position + Vector3.UP * 1.3)
	t.input.press_use()
	await t.seconds(0.45)
	t.check(t.events.count("bonked") == 1, "the new punch lands")
	return true


func test_heave_prompt_beats_the_door_prompt() -> bool:
	var dummy := t.first_dummy() as TestDummy
	dummy.global_position = Vector3(-0.5, 0.05, -4.0)
	await t.ticks(1)
	var ragdoll: Ragdoll = await t.knock_out(dummy)
	await t.seconds(1.5)
	var chest: RagdollPart = ragdoll.chest
	await t.stand_player(Vector3(chest.global_position.x, 0.05, chest.global_position.z - 1.0), chest.global_position)
	t.player.hands._grab(chest)
	await t.ticks(3)
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	window.set_open(true)
	await t.seconds(0.6)
	await t.walk_to(Vector3(0.8, 0.05, -4.0))
	t.input.aim_at(t.player.eye_position(), window.global_position)
	await t.seconds(0.4)
	var hands: Hands = t.player.hands
	t.check(hands._aimed_interactable() != null, "the crosshair is on the opening")
	t.check(hands._prompt_action == &"grab", "before charging it offers to close it")
	t.input.throw_held = true
	await t.seconds(0.4)
	t.check(hands.assist_point != null, "the heave found the opening")
	t.check(hands._prompt_text == "Let go: YEET!", "the heave wins, got '%s'" % hands._prompt_text)
	t.check(hands._prompt_action == &"throw", "and it names the throw key")
	t.input.throw_held = false
	return true


func test_sprinting_with_a_body_leaves_a_coach_standing() -> bool:
	await t.clear_dummies()
	var ragdoll := await _carry_body_from(Vector3(0.0, 0.05, 12.0))
	for z: float in [15.0, 17.5, 20.0, 22.5, 25.0]:
		_spawn(Vector3(0.0, 0.05, z), "intern")
	var knocked: int = t.events.count("knocked_out")
	var bonked: int = t.events.count("bonked")
	await t.ticks(2)
	TestDummy.brain_enabled = true
	for dummy in _dummies():
		dummy._mode_left = 60.0
	t.input.aim_at(t.player.eye_position(), Vector3(0.0, 1.0, 40.0))
	await t.ticks(2)
	t.input.sprint = true
	t.input.move = Vector2(0.0, 1.0)
	await t.seconds(4.0)
	t.input.move = Vector2.ZERO
	t.input.sprint = false
	TestDummy.brain_enabled = false
	t.check(t.player.hands.held is RagdollPart and is_instance_valid(ragdoll), "still carrying")
	t.check(t.player.global_position.z > 17.0, "the run got somewhere, z %.2f" % t.player.global_position.z)
	t.check(t.events.count("knocked_out") == knocked, "no knockouts, got %d" % (t.events.count("knocked_out") - knocked))
	t.check(t.events.count("bonked") == bonked, "no bonks, got %d" % (t.events.count("bonked") - bonked))
	t.check(t._ragdolls().size() == 1, "only the carried body is down, %d" % t._ragdolls().size())
	return true


func test_a_real_swing_with_a_body_still_floors_a_bystander() -> bool:
	await t.clear_dummies()
	await _carry_body_from(Vector3(0.0, 0.05, 3.0))
	var victim := _spawn(t.player.global_position + Vector3(0.0, 0.0, 1.7), "intern")
	await t.ticks(2)
	t.input.aim_at(t.player.eye_position(), victim.global_position + Vector3.UP * 1.3)
	await t.ticks(2)
	var knocked: int = t.events.count("knocked_out")
	t.input.press_use()
	await t.seconds(0.45)
	t.check(t.events.count("knocked_out") == knocked + 1, "the club lands")
	return true


func test_prop_freed_while_its_drop_timer_runs_logs_nothing() -> bool:
	var wrench: PhysicsProp = t.nearest_prop(&"wrench")
	await t.stand_player(wrench.global_position + Vector3(0.9, -0.8, 0.5), wrench.global_position)
	await t.ticks(1)
	t.input.press_grab()
	await t.ticks(4)
	t.check(t.player.hands.held == wrench, "wrench in hand")
	t.player.hands.drop()
	wrench.free()
	await t.seconds(0.5)
	# The runner's error watch fails this test if the timer choked on the dead prop.
	t.check(t.player.hands.held == null, "hands empty")
	return true


## Plays a raid badly and fast: chase, punch, grab, heave, restart. A runtime error anywhere
## fails this through the runner's error watch.
func test_soak_a_scrappy_raid_stays_error_free() -> bool:
	TestDummy.brain_enabled = true
	var director: RoundDirector = t.main.start_rounds()
	await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
	t.opening_named(&"Bistro", "Door_R_-10").set_open(true)
	var hands: Hands = t.player.hands
	for step in 60:
		var target := _nearest_to_player()
		if target != null and step % 3 != 2:
			await t.stand_player(target.global_position + Vector3(0.0, 0.0, -1.2), target.global_position + Vector3.UP * 1.3)
			t.input.press_use()
			await t.ticks(14)
		elif not t._ragdolls().is_empty():
			var ragdoll: Ragdoll = t._ragdolls()[0]
			var chest: Vector3 = ragdoll.chest.global_position
			await t.stand_player(Vector3(chest.x, 0.05, chest.z - 1.0), chest)
			t.input.press_grab()
			await t.ticks(4)
			t.input.throw_held = hands.held != null
			await t.ticks(20)
			t.input.throw_held = false
			await t.ticks(4)
		if step == 30:
			t.player.on_left_train()
			await t.ticks(10)
			t.player.respawn()
		if step == 45:
			var pan: PhysicsProp = t.nearest_prop(&"frying_pan")
			await t.stand_player(pan.global_position + Vector3(0.0, -0.8, -0.9), pan.global_position)
			t.input.press_grab()
			await t.ticks(4)
			hands.drop()
			director.restart_round()
			await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
		if director.phase == RoundDirector.Phase.RESULTS:
			director.next_round()
			await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
	TestDummy.brain_enabled = false
	t.check(t.player.is_aboard(), "still aboard at the end")
	return true

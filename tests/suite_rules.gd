extends RefCounted
## Rules and fixes that came out of the bot playtest: dead hands, the raid wave, openings,
## blame for passengers, tackles, ranks.

var t: Node


func _body_at(at: Vector3) -> Ragdoll:
	await t.clear_dummies()
	var dummy: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, at), 0)
	await t.ticks(1)
	return await t.knock_out(dummy)


func _held_body(at: Vector3) -> Ragdoll:
	var ragdoll: Ragdoll = await _body_at(at)
	await t.seconds(1.5)
	var chest := ragdoll.chest.global_position
	await t.stand_player(Vector3(chest.x, 0.05, chest.z + 1.2), chest)
	t.input.press_grab()
	await t.ticks(2)
	t.check(t.player.hands.held is RagdollPart, "picked the body up")
	return ragdoll


## --- Hands -----------------------------------------------------------------------

func test_grab_refuses_a_body_on_its_way_out() -> bool:
	var ragdoll: Ragdoll = await _body_at(Vector3(0.0, 0.05, -4.0))
	var hands: Hands = t.player.hands
	hands._aim_hit = {"collider": ragdoll.pelvis}
	t.check(hands._aimed_grabbable() == ragdoll.pelvis, "a body on the floor can be grabbed")
	ragdoll.queue_free()
	t.check(hands._aimed_grabbable() == null, "one that just stood up cannot")
	await t.ticks(2)
	return true


func test_hands_survive_a_held_body_being_freed() -> bool:
	var ragdoll: Ragdoll = await _held_body(Vector3(0.0, 0.05, -4.0))
	var hands: Hands = t.player.hands
	t.input.throw_held = true
	await t.ticks(5)
	t.check(hands.charging, "mid heave")
	t.input.throw_held = false
	ragdoll.free()
	await t.ticks(2)
	t.check(hands.held == null and not hands.charging, "hands are empty again")
	t.check(hands.move_speed_factor() == 1.0 and not hands.is_dragging(), "back to full speed")
	var wrench: PhysicsProp = t.nearest_prop(&"wrench")
	var at := wrench.global_position
	await t.stand_player(Vector3(at.x + 0.9, 0.05, at.z), at)
	t.input.press_grab()
	await t.ticks(2)
	t.check(hands.held == wrench, "and they still work")
	return true


func test_grab_press_near_a_shut_window_opens_it_and_keeps_the_body() -> bool:
	var ragdoll: Ragdoll = await _held_body(Vector3(0.0, 0.05, -4.0))
	var window: TrainOpening = t.opening_named(&"Bistro", "Window_R_-40")
	await t.walk_to(Vector3(-0.4, 0.05, -4.0))
	t.input.aim_at(t.player.eye_position(), window.global_position + Vector3(0.0, 0.0, 1.0))
	await t.ticks(2)
	t.check(t.player.hands._aimed_interactable() == null, "the crosshair is on bare wall")
	t.input.press_grab()
	await t.ticks(2)
	t.check(window.is_open, "the press opened the window")
	t.check(t.player.hands.held is RagdollPart and t.player.hands.held.ragdoll == ragdoll, "the body stays in hand")
	return true


func test_grab_press_away_from_any_opening_still_drops() -> bool:
	await _held_body(Vector3(0.0, 0.05, -2.0))
	await t.walk_to(Vector3(0.0, 0.05, -2.0))
	t.input.aim_at(t.player.eye_position(), Vector3(0.0, 0.5, 6.0))
	await t.ticks(2)
	t.input.press_grab()
	await t.ticks(2)
	t.check(t.player.hands.held == null, "an empty press lets go")
	return true


func test_a_snagged_body_slows_the_player_before_it_tears_loose() -> bool:
	await _held_body(Vector3(0.0, 0.05, -4.0))
	var hands: Hands = t.player.hands
	var free_speed := hands.move_speed_factor()
	t.check(hands._leash_factor() == 1.0, "no drag with the body at hand, %.2f" % hands._leash_factor())
	for part in (hands.held as RagdollPart).ragdoll.parts:
		part.global_position += Vector3(0.0, 0.0, 5.0)
	t.check(hands.move_speed_factor() < free_speed * 0.6, "a body far behind drags on the arm")
	return true


func test_gangway_keeps_a_dragged_body_centred() -> bool:
	var hands: Hands = t.player.hands
	t.check_near(hands._through_pinch(Vector3(1.0, 1.0, 9.6)).x, Hands.PINCH_LANE, 0.001, "inside the gangway")
	t.check_near(hands._through_pinch(Vector3(-1.0, 1.0, -9.6)).x, -Hands.PINCH_LANE, 0.001, "the other gangway")
	t.check(hands._through_pinch(Vector3(1.0, 1.0, 3.0)).x == 1.0, "free elsewhere")
	return true


func test_open_door_does_not_shield_what_lies_past_it() -> bool:
	var door: TrainOpening = t.opening_named(&"Bistro", "Door_R_-10")
	door.set_open(true)
	await t.seconds(0.6)
	# In the thickness of the use volume, and still inside the hull.
	var at := Vector3(door.global_position.x + 0.05, 1.4, -1.0)
	var prop: PhysicsProp = t.main.spawn_prop(&"soup_bowl", Transform3D(Basis.IDENTITY, at))
	prop.freeze = true
	await t.stand_player(Vector3(0.6, 0.05, -1.0), at)
	await t.ticks(2)
	t.check(t.player.hands._aim_hit.get("collider") == prop, "the crosshair finds it, got %s" % str(t.player.hands._aim_hit.get("collider")))
	t.input.press_grab()
	await t.ticks(2)
	t.check(door.is_open, "the door stays open")
	t.check(t.player.hands.held == prop, "and the grab took the crate")
	return true


## --- Openings --------------------------------------------------------------------

func test_jammed_window_stays_shut_and_says_so() -> bool:
	var jammed: TrainOpening = t.opening_named(&"Bistro", "Window_R_-65")
	t.check(jammed.jammed, "the -6.5 window is rusted")
	t.check(not t.opening_named(&"Bistro", "Window_R_-40").jammed, "the -4.0 window works")
	t.check(not t.main.train.openings().has(jammed), "not on the list of ways out")
	jammed.interact(t.player)
	await t.seconds(0.6)
	t.check(not jammed.is_open, "it does not open")
	t.check(jammed.get_prompt() == "Rusted shut", "the prompt says why")
	t.check(jammed.get_node_or_null("UseVolume") == null, "no use volume left in the hole")
	return true


func test_new_raid_closes_every_opening() -> bool:
	var director: RoundDirector = t.main.start_rounds()
	await t.ticks(2)
	for opening in t.main.train.openings():
		opening.set_open(true)
	director.restart_round()
	await t.ticks(2)
	t.check(t.main.train.open_opening_count() == 0, "sealed, %d still open" % t.main.train.open_opening_count())
	return true


func test_no_body_can_land_out_of_reach_beside_the_boiler() -> bool:
	var car: TrainCar = t.main.train.car_by_id(&"Locomotive")
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var solid := func(local: Vector3) -> bool:
		var query := PhysicsPointQueryParameters3D.new()
		query.position = car.to_global(local)
		query.collision_mask = Layers.HULL
		return not space.intersect_point(query, 1).is_empty()
	for side: float in [-1.0, 1.0]:
		for z: float in [-8.7, -7.0, -5.0, -4.8]:
			t.check(solid.call(Vector3(side * 1.45, 1.0, z)), "slot beside the boiler is plugged at z %.1f" % z)
		t.check(not solid.call(Vector3(side * 1.45, 1.4, -4.7)), "the -4.0 window stays reachable")
	return true


func test_no_hiding_spot_beside_a_door() -> bool:
	for spot in TestDummy.HIDE_SPOTS:
		for car in t.main.train.cars:
			var door_z: float = car.position.z + Train.DOORS[0]
			t.check(absf(spot.z - door_z) >= TrainCar.DOOR_WIDTH * 0.5 + 0.8, "%s is clear of the door at z=%.1f" % [spot, door_z])
	return true


## --- Tackles ---------------------------------------------------------------------

func test_sprint_staggers_a_stowaway_and_flattens_a_passenger() -> bool:
	await t.clear_dummies()
	var stowaway: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 2.0)), 0, true)
	var passenger: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 6.0)), 0, false)
	await t.ticks(2)
	stowaway._feel_shove(Vector3.BACK, Player.SPRINT_SPEED, t.player)
	t.check(not stowaway.is_queued_for_deletion(), "the stowaway stays up")
	t.check(stowaway._stumble_left > 0.0, "but staggers")
	passenger._feel_shove(Vector3.BACK, Player.SPRINT_SPEED, t.player)
	t.check(passenger.is_queued_for_deletion(), "a passenger goes over")
	await t.ticks(2)
	return true


func test_a_sprint_still_stops_a_bolt() -> bool:
	await t.clear_dummies()
	var stowaway: TestDummy = t.main.spawn_dummy(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 2.0)), 0, true)
	await t.ticks(2)
	stowaway._bolting = true
	stowaway._feel_shove(Vector3.BACK, Player.WALK_SPEED, t.player)
	t.check(not stowaway.is_queued_for_deletion() and stowaway._stumble_left == 0.0, "a walk does not touch it")
	stowaway._feel_shove(Vector3.BACK, Player.SPRINT_SPEED, t.player)
	t.check(stowaway.is_queued_for_deletion(), "a sprint brings it down")
	await t.ticks(2)
	return true


## --- Score -----------------------------------------------------------------------

func test_passenger_who_walks_out_costs_nothing() -> bool:
	var director: RoundDirector = t.main.start_rounds()
	await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
	var stowaway: TestDummy = director.stowaway_bodies()[0]
	stowaway.receive_bonk(TestDummy.MAX_HP, Vector3.FORWARD, t.player)
	await t.ticks(2)
	for body in t.main.npc_bodies():
		if body is Ragdoll and not body.is_queued_for_deletion():
			body.on_left_train()
	await t.ticks(1)
	var score := director.score
	var combo := director.combo
	var paying: TestDummy = null
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_stowaway and not body.is_queued_for_deletion():
			paying = body
	paying._knock_out(Vector3.RIGHT, null)
	await t.ticks(1)
	var walked := _loose_ragdoll()
	walked.on_left_train()
	await t.ticks(1)
	t.check(director.score == score, "no fine for a stranger's exit")
	t.check(director.combo == combo, "the chain holds")
	t.check(director.passengers_yeeted == 0, "not on the results")
	return true


func test_passenger_shoved_out_is_the_players_fault() -> bool:
	var director: RoundDirector = t.main.start_rounds()
	await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
	var paying: TestDummy = null
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_stowaway and not body.is_queued_for_deletion():
			paying = body
	var score := director.score
	paying._feel_shove(Vector3.RIGHT, 1.0, t.player)
	paying._knock_out(Vector3.RIGHT, null)
	await t.ticks(1)
	_loose_ragdoll().on_left_train()
	await t.ticks(1)
	t.check(director.score == score - RoundDirector.PASSENGER_PENALTY, "a push counts")
	t.check(director.passengers_yeeted == 1, "and shows on the results")
	return true


func _loose_ragdoll() -> Ragdoll:
	for body in t.main.npc_bodies():
		if body is Ragdoll and not body.off_train and not body.is_queued_for_deletion():
			return body
	return null


func test_top_rank_takes_more_than_a_clean_win() -> bool:
	var clean_win := 3 * 550
	var par := 3 * RoundDirector.YEET_POINTS * RoundDirector.PAR_YEETS
	t.check(RoundDirector.rank_for(clean_win, 3, true) != RoundDirector.RANKS.back(), "550 a stowaway is not the top")
	t.check(RoundDirector.rank_for(par, 3, true) == RoundDirector.RANKS.back(), "par is")
	return true


func test_clock_leaves_room_for_the_last_raids() -> bool:
	t.check(RoundDirector.seconds_for(1) == 60, "raid 1 keeps its minute")
	var last := RoundDirector.seconds_for(99)
	t.check(last == RoundDirector.MIN_SECONDS, "the clock bottoms out")
	t.check(float(last) / RoundDirector.MAX_STOWAWAYS >= 4.0, "the last raid is hard, not impossible")
	return true


## --- Raid wave -------------------------------------------------------------------

func test_raid_wave_survives_someone_freed_mid_wave() -> bool:
	var director: RoundDirector = t.main.start_rounds()
	await t.ticks(2)
	var strike: RaidStrike = director.get_node("RaidStrike")
	var keep: TestDummy = director.stowaway_bodies()[0]
	var gone: TestDummy = director.stowaway_bodies()[1]
	strike._to_tip = [keep, gone]
	strike.set_physics_process(true)
	gone.free()
	await t.ticks(3)
	t.check(strike._to_tip.is_empty(), "the wave ran to the end")
	t.check(not is_instance_valid(keep) or keep.is_queued_for_deletion(), "and still tipped the one left")
	await t.ticks(2)
	return true

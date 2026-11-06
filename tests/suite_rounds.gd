extends RefCounted
## The raid loop: roles, clock, score, fines, results, escalation, and the HUD reading it.

var t: Node

var _started: Array = []
var _ended: Array = []
var _warnings: Array[int] = []
var _awards: Array[int] = []


func _note_started(number: int, stowaways: int, seconds: int) -> void:
	_started.append([number, stowaways, seconds])


func _note_ended(score: int, passed: bool) -> void:
	_ended.append([score, passed])


func _note_warning(seconds_left: int) -> void:
	_warnings.append(seconds_left)


func _note_award(points: int, _reason: String) -> void:
	_awards.append(points)


func _start() -> RoundDirector:
	_started.clear()
	_ended.clear()
	_warnings.clear()
	_awards.clear()
	for pair: Array in [
		[GameEvents.round_started, _note_started], [GameEvents.round_ended, _note_ended],
		[GameEvents.raid_warning, _note_warning], [GameEvents.score_awarded, _note_award],
	]:
		if not pair[0].is_connected(pair[1]):
			pair[0].connect(pair[1])
	return t.main.start_rounds()


func _into_raid(director: RoundDirector) -> void:
	await t.seconds(RoundDirector.TITLE_SECONDS + 0.1)
	t.check(director.phase == RoundDirector.Phase.RAID, "raid is running")


func _bodies(stowaway: bool) -> Array[TestDummy]:
	var found: Array[TestDummy] = []
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_queued_for_deletion() and body.is_stowaway == stowaway:
			found.append(body)
	return found


## Real knockout through the bonk path; returns the ragdoll it leaves.
func _knock_out(dummy: TestDummy) -> Ragdoll:
	dummy.receive_bonk(TestDummy.MAX_HP, Vector3.FORWARD, t.player)
	await t.ticks(2)
	for body in t.main.npc_bodies():
		if body is Ragdoll and not body.off_train and not body.is_queued_for_deletion():
			return body
	return null


func _yeet(dummy: TestDummy) -> Ragdoll:
	var ragdoll: Ragdoll = await _knock_out(dummy)
	ragdoll.on_left_train()
	await t.ticks(1)
	return ragdoll


func test_sandbox_runs_without_a_round() -> bool:
	t.check(t.main.round_director == null, "no director while auto_start_round is false")
	t.check(not t.main.hud.round_hud.visible, "no raid readout in the sandbox")
	t.check(_bodies(false).size() == Main.DUMMIES.size(), "sandbox dummies are all plain")
	return true


func test_round_one_assigns_roles() -> bool:
	var director := _start()
	await t.ticks(2)
	t.check(_started == [[1, 3, 60]], "round_started(1, 3, 60), got %s" % str(_started))
	t.check(_bodies(true).size() == 3, "three stowaways, got %d" % _bodies(true).size())
	t.check(_bodies(false).size() == 4, "four paying passengers, got %d" % _bodies(false).size())
	t.check(director.stowaways_left == 3, "readout counts them")
	var nearest: TestDummy = null
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_queued_for_deletion():
			if nearest == null or body.global_position.distance_to(t.player.global_position) < nearest.global_position.distance_to(t.player.global_position):
				nearest = body
	t.check(nearest.is_stowaway, "the first body the player meets is a stowaway")
	return true


func test_title_card_then_countdown() -> bool:
	var director := _start()
	await t.seconds(1.0)
	t.check(director.phase == RoundDirector.Phase.TITLE, "title card holds")
	t.check(director.time_left == 60.0, "clock waits for the card")
	await t.seconds(RoundDirector.TITLE_SECONDS)
	t.check(director.phase == RoundDirector.Phase.RAID, "countdown started")
	t.check(director.time_left < 60.0, "clock runs")
	return true


func test_role_survives_knockout_and_body_still_counts() -> bool:
	var director := _start()
	await _into_raid(director)
	var ragdoll: Ragdoll = await _knock_out(_bodies(true)[0])
	t.check(ragdoll != null and ragdoll.is_stowaway, "ragdoll keeps the role")
	await t.ticks(2)
	t.check(director.stowaways_left == 3, "out cold is not gone, left=%d" % director.stowaways_left)
	return true


func test_yeets_score_and_combo_multiplies() -> bool:
	var director := _start()
	await _into_raid(director)
	await _yeet(_bodies(true)[0])
	t.check(director.score >= RoundDirector.YEET_POINTS, "first yeet pays, score=%d" % director.score)
	t.check(_awards[0] == RoundDirector.YEET_POINTS, "first yeet is the base award")
	t.check(director.combo == 1, "chain started")
	await _yeet(_bodies(true)[0])
	t.check(director.combo == 2, "quick yeet chains")
	t.check(_awards.has(RoundDirector.YEET_POINTS * 2), "second yeet is doubled, awards=%s" % str(_awards))
	t.check(director.stowaways_yeeted == 2, "two stowaways counted")
	t.check(director.stowaways_left == 1, "one left, got %d" % director.stowaways_left)
	director.combo_left = 0.05
	await t.ticks(6)
	t.check(director.combo == 0, "chain expires")
	return true


func test_paying_passenger_costs_and_breaks_the_chain() -> bool:
	var director := _start()
	await _into_raid(director)
	await _yeet(_bodies(true)[0])
	var before := director.score
	await _yeet(_bodies(false)[0])
	t.check(director.score == before - RoundDirector.PASSENGER_PENALTY, "penalty applied")
	t.check(director.combo == 0, "chain broken")
	t.check(director.passengers_yeeted == 1, "counted on the results")
	t.check(director.stowaways_left == 2, "does not count as a stowaway")
	return true


func test_flying_prop_scores_nothing() -> bool:
	var director := _start()
	await _into_raid(director)
	var prop: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D.IDENTITY)
	GameEvents.object_yeeted.emit(prop)
	t.check(director.score == 0, "props are not people")
	return true


func test_flight_distance_pays_on_landing() -> bool:
	var director := _start()
	await _into_raid(director)
	var ragdoll: Ragdoll = await _knock_out(_bodies(true)[0])
	ragdoll.global_position = ragdoll.global_position
	ragdoll.on_left_train()
	await t.seconds(2.5)
	t.check(_awards.size() >= 2, "airtime paid after landing, awards=%s" % str(_awards))
	t.check(_awards[1] > 0 and _awards[1] <= RoundDirector.DISTANCE_POINTS_CAP, "airtime award in range: %s" % str(_awards))
	return true


func test_scenery_hits_pay_with_a_limit() -> bool:
	var director := _start()
	await _into_raid(director)
	var ragdoll: Ragdoll = await _yeet(_bodies(true)[0])
	var passenger: Ragdoll = await _yeet(_bodies(false)[0])
	var before := director.score
	GameEvents.body_hit_scenery.emit(passenger, 20.0)
	t.check(director.score == before, "only stowaways pay")
	GameEvents.body_hit_scenery.emit(ragdoll.pelvis, 20.0)
	t.check(director.score == before + RoundDirector.SCENERY_POINTS + 40, "a limb counts for its body, +%d" % (director.score - before))
	var after_first := director.score
	GameEvents.body_hit_scenery.emit(ragdoll, 20.0)
	t.check(director.score == after_first, "one impact pays once")
	for i in 5:
		await t.seconds(RoundDirector.SCENERY_HIT_COOLDOWN + 0.05)
		GameEvents.body_hit_scenery.emit(ragdoll, 20.0)
	var paid := _awards.count(RoundDirector.SCENERY_POINTS + 40)
	t.check(paid == RoundDirector.SCENERY_HITS_PER_BODY, "capped per body, paid %d" % paid)
	return true


func test_raid_warning_counts_down_then_fines() -> bool:
	var director := _start()
	await _into_raid(director)
	director.time_left = 3.5
	await t.seconds(3.6)
	t.check(_warnings == [3, 2, 1] or _warnings == [4, 3, 2, 1], "one warning a second, got %s" % str(_warnings))
	t.check(director.phase == RoundDirector.Phase.ENDING, "raid hit")
	t.check(director.raid_hit, "flagged for the HUD")
	await t.seconds(RoundDirector.ENDING_SECONDS + 0.1)
	var expected := -RoundDirector.FINE_PER_STOWAWAY * 3
	t.check(_ended == [[expected, false]], "round_ended(%d, false), got %s" % [expected, str(_ended)])
	t.check(director.rank_title == RoundDirector.RANKS[0], "worst rank for a negative score")
	return true


func test_warnings_start_at_ten() -> bool:
	var director := _start()
	await _into_raid(director)
	director.time_left = 10.02
	await t.seconds(0.1)
	t.check(_warnings == [10], "first warning at 10, got %s" % str(_warnings))
	return true


func test_clear_train_ends_early_and_button_escalates() -> bool:
	var director := _start()
	await _into_raid(director)
	var round_hud: RoundHud = t.main.hud.round_hud
	for dummy in _bodies(true):
		await _yeet(dummy)
	await t.ticks(2)
	t.check(director.phase == RoundDirector.Phase.ENDING, "last stowaway ends the raid")
	t.check(director.time_bonus > 0, "time left pays")
	await t.seconds(RoundDirector.ENDING_SECONDS + 0.1)
	t.check(director.phase == RoundDirector.Phase.RESULTS, "results")
	t.check(_ended.size() == 1 and _ended[0][1] == true, "passed, got %s" % str(_ended))
	t.check(round_hud.results_panel.visible, "results screen shows")
	t.check(round_hud.restart_button.text == "NEXT RAID", "button says what it does")
	t.check(RoundDirector.RANKS.has(director.rank_title), "rank assigned")
	t.check(director.total_score == director.score, "run total adds up")
	round_hud.restart_button.pressed.emit()
	await t.ticks(2)
	t.check(director.round_number == 2, "next raid")
	t.check(_started.back() == [2, 4, RoundDirector.seconds_for(2)], "more stowaways, less time: %s" % str(_started.back()))
	t.check(_bodies(true).size() == 4, "four stowaways aboard, got %d" % _bodies(true).size())
	t.check(not round_hud.results_panel.visible, "results gone")
	t.check(director.score == 0, "round score resets")
	return true


func test_lost_raid_retries_the_same_raid() -> bool:
	var director := _start()
	await _into_raid(director)
	director.time_left = 0.05
	await t.seconds(RoundDirector.ENDING_SECONDS + 0.3)
	t.check(t.main.hud.round_hud.restart_button.text == "TRY AGAIN", "button says retry")
	director.next_round()
	await t.ticks(2)
	t.check(director.round_number == 1, "same raid again")
	t.check(director.total_score == 0, "run score wiped")
	return true


func test_next_round_only_from_results() -> bool:
	var director := _start()
	await _into_raid(director)
	director.next_round()
	t.check(director.round_number == 1, "a stray press does nothing mid-raid")
	t.check(director.phase == RoundDirector.Phase.RAID, "raid untouched")
	return true


func test_escalation_fits_the_train() -> bool:
	var seconds := RoundDirector.seconds_for(1)
	var stowaways := RoundDirector.stowaways_for(1)
	t.check(seconds == 60, "the contract's 60 seconds")
	for number in range(2, 30):
		var next_seconds := RoundDirector.seconds_for(number)
		var next_stowaways := RoundDirector.stowaways_for(number)
		t.check(next_seconds <= seconds and next_seconds >= RoundDirector.MIN_SECONDS, "time only shrinks")
		t.check(next_stowaways >= stowaways, "stowaways only grow")
		t.check(next_stowaways + RoundDirector.passengers_for(number) <= RoundDirector.SPOTS.size(), "everyone has a spot")
		seconds = next_seconds
		stowaways = next_stowaways
	return true


func test_people_spawn_standing_free() -> bool:
	var director := _start()
	director.round_number = 20
	director.restart_round()
	await t.ticks(2)
	var starts: Dictionary = {}
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_queued_for_deletion():
			starts[body] = body.global_position
	t.check(starts.size() == RoundDirector.SPOTS.size(), "train is full, got %d" % starts.size())
	await t.seconds(1.0)
	for body: TestDummy in starts:
		t.check(body.global_position.distance_to(starts[body]) < 0.6, "%s stayed put at %s" % [body.name, starts[body]])
		t.check(absf(body.global_position.y) < 0.2, "%s stands on the floor, y=%.2f" % [body.name, body.global_position.y])
	return true


func test_ranks_climb_with_score() -> bool:
	t.check(RoundDirector.rank_for(-1, 3, true) == RoundDirector.RANKS[0], "negative is the bottom")
	t.check(RoundDirector.rank_for(100000, 3, true) == RoundDirector.RANKS.back(), "huge win is the top")
	t.check(RoundDirector.RANKS.find(RoundDirector.rank_for(100000, 3, false)) <= 3, "a lost raid stays low")
	var previous := 0
	for points in range(0, 1200, 50):
		var index := RoundDirector.RANKS.find(RoundDirector.rank_for(points, 3, true))
		t.check(index >= previous, "rank never drops as score rises")
		previous = index
	return true


func test_hud_readout_and_warning() -> bool:
	var director := _start()
	var round_hud: RoundHud = t.main.hud.round_hud
	await t.ticks(2)
	t.check(round_hud.visible, "readout on")
	t.check(round_hud._title_band.visible, "title card up")
	await _into_raid(director)
	await t.ticks(2)
	t.check(not round_hud._vignette.visible, "calm before the warning")
	director.time_left = 6.0
	await t.ticks(2)
	t.check(round_hud._vignette.visible, "red warning on")
	t.check(round_hud._raid_warning.visible, "warning text on")
	GameEvents.score_awarded.emit(100, "TEST")
	await t.ticks(1)
	t.check(round_hud._popups.get_child_count() == 1, "score popup floats")
	return true


func test_results_freeze_and_release_the_player() -> bool:
	var director := _start()
	var hud: Hud = t.main.hud
	var local: LocalInput = hud._local_input
	await _into_raid(director)
	hud.toggle_clipboard()
	director.time_left = 0.05
	await t.seconds(RoundDirector.ENDING_SECONDS + 0.3)
	t.check(not hud.clipboard.visible, "results close the clipboard")
	t.check(local.frozen, "player frozen behind the results")
	t.check(hud.round_hud.restart_button.disabled, "button locked against mashing")
	await t.seconds(RoundHud.BUTTON_LOCK + 0.1)
	t.check(not hud.round_hud.restart_button.disabled, "button unlocks")
	hud.round_hud.restart_button.pressed.emit()
	await t.ticks(2)
	t.check(not local.frozen, "player released")
	return true


func test_clipboard_reset_restarts_the_raid() -> bool:
	var director := _start()
	await _into_raid(director)
	await _yeet(_bodies(true)[0])
	t.main.reset_cargo()
	await t.ticks(3)
	t.check(director.phase == RoundDirector.Phase.TITLE, "back to the title card")
	t.check(director.score == 0, "score cleared")
	t.check(_bodies(true).size() == 3, "stowaways restocked")
	return true


func test_people_hold_still_behind_the_title_card() -> bool:
	TestDummy.brain_enabled = true
	var director := _start()
	await t.ticks(2)
	var first: TestDummy = _nearest_to_player()
	var start := first.global_position
	await t.seconds(RoundDirector.TITLE_SECONDS - 0.4)
	var drift := first.global_position.distance_to(start)
	await t.seconds(1.5)
	var moved := 0.0
	if is_instance_valid(first):
		moved = first.global_position.distance_to(start)
	TestDummy.brain_enabled = false
	t.check(drift < 0.2, "nobody runs behind the card, drifted %.2f m" % drift)
	t.check(director.phase == RoundDirector.Phase.RAID, "raid running")
	t.check(moved > 1.0, "the first stowaway bolts once the clock starts, moved %.2f m" % moved)
	return true


func test_popups_stay_on_screen_and_clear_of_the_clock() -> bool:
	_start()
	var round_hud: RoundHud = t.main.hud.round_hud
	await t.ticks(2)
	var height: float = round_hud.size.y
	for i in 7:
		GameEvents.score_awarded.emit(100 * (i + 1), "TEST")
		await t.ticks(3)
	var lines: Array[float] = []
	for popup: Control in round_hud._popups.get_children():
		if popup.is_queued_for_deletion():
			continue
		t.check(popup.position.y > height * 0.5, "popup below the crosshair, y=%.0f" % popup.position.y)
		t.check(popup.position.y + 80.0 < height + 20.0, "popup on screen, y=%.0f" % popup.position.y)
		for other in lines:
			t.check(absf(other - popup.position.y) > 40.0, "popups do not stack: %.0f and %.0f" % [other, popup.position.y])
		lines.append(popup.position.y)
	t.check(lines.size() == RoundHud.POPUP_SLOTS, "a full column, got %d" % lines.size())
	await t.seconds(RoundHud.POPUP_SECONDS + 0.1)
	GameEvents.score_awarded.emit(100, "TEST")
	await t.ticks(1)
	var live: Array[Control] = []
	for popup: Control in round_hud._popups.get_children():
		if not popup.is_queued_for_deletion():
			live.append(popup)
	t.check(live.size() == 1, "faded popups free their lines, got %d" % live.size())
	t.check_near(live[0].position.y, RoundHud.popup_line_y(0, height), 2.0, "a lone popup takes the top line")
	return true


func test_popup_lines_fit_small_windows() -> bool:
	for height: float in [720.0, 1080.0, 480.0]:
		var last := RoundHud.popup_line_y(RoundHud.POPUP_SLOTS - 1, height)
		t.check(last <= height - RoundHud.POPUP_BOTTOM_ROOM + 0.1, "last line fits %d, y=%.0f" % [height, last])
		t.check(RoundHud.popup_line_y(1, height) > RoundHud.popup_line_y(0, height), "lines descend at %d" % height)
	return true


func test_combo_shows_from_two() -> bool:
	var director := _start()
	var round_hud: RoundHud = t.main.hud.round_hud
	await _into_raid(director)
	await _yeet(_bodies(true)[0])
	await t.ticks(2)
	t.check(not round_hud._combo.visible, "a single yeet is not a combo")
	await _yeet(_bodies(true)[0])
	await t.ticks(2)
	t.check(round_hud._combo.visible, "x2 shows")
	t.check(round_hud._combo.text == "COMBO x2", "text reads the chain, got %s" % round_hud._combo.text)
	return true


func test_countdown_turns_red_and_back() -> bool:
	var director := _start()
	var round_hud: RoundHud = t.main.hud.round_hud
	await _into_raid(director)
	director.time_left = 6.0
	await t.ticks(2)
	t.check(round_hud._countdown.get_theme_color("font_color") == RoundHud.COLOR_RED, "red in the last ten seconds")
	director.restart_round()
	await t.ticks(2)
	t.check(round_hud._countdown.get_theme_color("font_color") == RoundHud.COLOR_CREAM, "calm again next raid")
	return true


func test_title_names_the_wrench() -> bool:
	_start()
	await t.ticks(2)
	t.check(t.main.hud.round_hud._title_help.text.to_lower().contains("wrench"), "card says to grab the wrench")
	return true


func test_tag_text_fits_its_box() -> bool:
	var font := ThemeDB.fallback_font
	for text: String in [RoundMarkers.tag_text(3.0, 1), RoundMarkers.tag_text(3.0, 9), RoundMarkers.tag_text(120.0, 9)]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, RoundMarkers.TAG_FONT_SIZE).x
		t.check(width < RoundMarkers.TAG_WIDTH, "%s fits, %.0f px" % [text, width])
	t.check(RoundMarkers.tag_text(3.0, 1) == "STOWAWAY", "close tag names the target")
	t.check(RoundMarkers.tag_text(12.0, 2) == "12 m x2", "merged tag counts")
	return true


func test_tags_pin_to_the_edge_from_any_direction() -> bool:
	var limit := Vector2(586.0, 306.0)
	var cases: Array[Vector2] = [
		Vector2.ZERO, Vector2(0.001, 0.0), Vector2(3.0, 1.0), Vector2(-500.0, 40.0), Vector2(5000.0, -9000.0),
		RoundMarkers.behind_direction(Vector3.ZERO), RoundMarkers.behind_direction(Vector3(0.0, 0.1, 6.0)),
		RoundMarkers.behind_direction(Vector3(-4.0, 0.0, 1.0)),
	]
	for direction in cases:
		var pinned := RoundMarkers.pin_to_edge(direction, limit)
		var reach := maxf(absf(pinned.x) / limit.x, absf(pinned.y) / limit.y)
		t.check_near(reach, 1.0, 0.01, "%s reaches the edge, got %s" % [str(direction), str(pinned)])
	t.check(RoundMarkers.behind_direction(Vector3(0.0, 2.0, 6.0)).y > 0.0, "behind never pins on the clock")
	return true


func test_tags_in_one_place_merge() -> bool:
	var tags: Array[Dictionary] = [
		{"at": Vector2(100.0, 100.0), "direction": Vector2.LEFT, "pinned": true, "metres": 20.0, "count": 1},
		{"at": Vector2(100.0, 130.0), "direction": Vector2.LEFT, "pinned": true, "metres": 9.0, "count": 1},
		{"at": Vector2(900.0, 100.0), "direction": Vector2.RIGHT, "pinned": true, "metres": 30.0, "count": 1},
	]
	var merged := RoundMarkers.merge_tags(tags)
	t.check(merged.size() == 2, "two places, got %d" % merged.size())
	t.check(merged[0]["count"] == 2 and merged[0]["metres"] == 9.0, "nearest keeps the tag: %s" % str(merged[0]))
	t.check(merged[1]["count"] == 1, "the far one stands alone")
	t.check(tags[1]["count"] == 1, "the input is left alone")
	return true


func test_the_raid_hit_is_physical() -> bool:
	var director := _start()
	await _into_raid(director)
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, t.main.train.car_by_id(&"Coach").position + Vector3(0.0, 0.3, 4.0)))
	await t.seconds(0.3)
	var crate_z := crate.global_position.z
	var kmh := TrainState.target_speed_mps
	director.time_left = 0.02
	await t.seconds(0.3)
	t.check(director.raid_hit, "raid hit")
	t.check(director.score == -RoundDirector.FINE_PER_STOWAWAY * 3, "the slam itself scores nothing, got %d" % director.score)
	var strike: RaidStrike = director._strike
	t.check(TrainState.target_speed_mps == 0.0, "emergency brake")
	t.check(TrainState.speed_mps < kmh, "the train is slowing")
	t.check(crate.global_position.z < crate_z - 0.3, "loose cargo slides forward, %.2f to %.2f" % [crate_z, crate.global_position.z])
	t.check(_bodies(true).is_empty(), "stowaways were thrown off their feet")
	t.check(strike.stamps.size() == 3, "one fine stamped per stowaway, got %d" % strike.stamps.size())
	t.check(strike.lamps.size() == RaidStrike.CARS.size(), "cars strobe red")
	await t.seconds(RoundDirector.ENDING_SECONDS)
	t.check(director.phase == RoundDirector.Phase.RESULTS, "results follow")
	t.check(not strike.stamps[0].visible, "stamps do not float over the results")
	director.next_round()
	await t.ticks(2)
	t.check(TrainState.target_speed_mps == kmh, "train picks up again")
	t.check(strike.stamps.is_empty() and strike.lamps.is_empty(), "the strike is swept up")
	t.check(not strike.active, "strike over")
	return true


func test_a_cleared_train_has_no_strike() -> bool:
	var director := _start()
	await _into_raid(director)
	var kmh := TrainState.target_speed_mps
	for dummy in _bodies(true):
		await _yeet(dummy)
	await t.ticks(4)
	t.check(not director._strike.active, "no strike on a win")
	t.check(TrainState.target_speed_mps == kmh, "no brake on a win")
	t.check(_bodies(false).size() == 4, "passengers stay on their feet")
	return true


func test_freeing_the_game_mid_strike_restores_the_train() -> bool:
	var director := _start()
	await _into_raid(director)
	var kmh := TrainState.target_speed_mps
	director.time_left = 0.02
	await t.seconds(0.5)
	t.check(TrainState.target_speed_mps == 0.0, "braking")
	director.queue_free()
	await t.ticks(2)
	t.check(TrainState.target_speed_mps == kmh, "brake released with the director")
	t.check_near(TrainState.speed_mps, kmh, 8.0, "speed back for whatever comes next")
	t.main.round_director = null
	return true


func test_results_hide_the_play_prompts() -> bool:
	var director := _start()
	var hud: Hud = t.main.hud
	await _into_raid(director)
	director.time_left = 0.05
	await t.seconds(RoundDirector.ENDING_SECONDS + 0.3)
	t.check(not hud._prompt.visible, "no use prompt behind the results")
	t.check(not hud._crosshair.visible, "no crosshair behind the results")
	director.next_round()
	await t.ticks(2)
	t.check(hud._prompt.visible, "prompt back for the next raid")
	return true


func _nearest_to_player() -> TestDummy:
	var nearest: TestDummy = null
	for body in t.main.npc_bodies():
		if body is TestDummy and not body.is_queued_for_deletion():
			if nearest == null or body.global_position.distance_to(t.player.global_position) < nearest.global_position.distance_to(t.player.global_position):
				nearest = body
	return nearest

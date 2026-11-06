extends Node
## Headless playtester. Plays real raids through ScriptedInput, the same seam a human's
## LocalInput uses: real Player, real Hands, real RoundDirector, TestDummy brains on.
## It only ever sends a PlayerCommand, and it reacts late, turns at a limited rate and aims
## with a wobble, so its times are a decent human's and not a perfect one's.
##   godot --headless --path . --fixed-fps 60 res://tools/playtest_bot.tscn -- sessions=fists,tool,idle,paying seeds=2 rounds=7
## Prints one "ROUND {json}" line per raid and "STUCK {json}" per stuck report.

enum Brain { PLAY, IDLE }

const ErrorWatch := preload("res://tests/error_watch.gd")
const DEFAULT_ROUTE := 20261105
const TICK := 1.0 / 60.0

## turn: rad/s. react: seconds. noise: radians. predict: share of the delay a player leads by.
const POLICIES := {
	"fists": {"turn": 6.0, "react": 0.3, "noise": 0.03, "predict": 0.5, "sprint": true, "tool": false, "prey": "stowaways"},
	"tool": {"turn": 6.0, "react": 0.3, "noise": 0.03, "predict": 0.5, "sprint": true, "tool": true, "prey": "stowaways"},
	"human": {"turn": 4.5, "react": 0.3, "noise": 0.05, "predict": 0.3, "sprint": true, "tool": true, "prey": "stowaways", "hesitate": 0.8},
	"walker": {"turn": 6.0, "react": 0.3, "noise": 0.03, "predict": 0.5, "sprint": false, "tool": true, "prey": "stowaways"},
	"novice": {"turn": 3.5, "react": 0.5, "noise": 0.06, "predict": 0.0, "sprint": true, "tool": false, "prey": "stowaways"},
	"paying": {"turn": 6.0, "react": 0.3, "noise": 0.03, "predict": 0.5, "sprint": true, "tool": false, "prey": "passengers"},
}

const CLICK_GAP := 0.45
const GRAB_GAP := 0.3
const BONK_AT := 2.4
const GRAB_AT := 1.5
const OPEN_AT := 2.2
const HEAVE_AT := 3.2
const HEAVE_FROM := 4.5
const HEAVE_WAIT := 3.0
const RELEASE_CHARGE := 0.6
const STUCK_AFTER := 0.35
const UNSTICK_TIME := 0.5
const NEAR_LIMIT := 7.0
const WEDGE_LIMIT := 1.5
const LIMBO_LIMIT := 2.0
const BUNKER_PENALTY := 3.0
const CLOSED_PENALTY := 2.0

var sessions: Array[String] = ["fists", "tool", "idle", "paying"]
var seeds := 2
var rounds := 7
var trace := false

var main: Main
var director: RoundDirector
var player: Player
var input: ScriptedInput

var _watch := ErrorWatch.new()
var _active := false
var _brain := Brain.IDLE
var _skill: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _session := ""

var _target: Node3D = null
var _opening: TrainOpening = null
var _history: Array[Vector3] = []
var _react_left := 0.0
var _click_left := 0.0
var _grab_left := 0.0
var _hold_left := 0.0
var _carry_time := 0.0
var _heave_time := 0.0
var _part_index := 0
var _part_time := 0.0
var _noise_yaw := 0.0
var _noise_pitch := 0.0
var _last_move := Vector2.ZERO
var _stuck_time := 0.0
var _unstick_left := 0.0
var _unstick_side := 1.0
var _want_tool := false
var _tool_time := 0.0
var _carried: Ragdoll = null
var _threw_now := false

var _stats: Dictionary = {}
var _chase_time := 0.0
var _cycle_time := 0.0
var _near_time := 0.0
var _pending: Dictionary = {}       # Ragdoll -> seconds left to leave the train
var _wedge: Dictionary = {}         # instance id -> seconds
var _limbo: Dictionary = {}         # instance id -> seconds
var _ragdolls_seen: Dictionary = {} # instance id -> true
var _stuck_reports: Array[Dictionary] = []
var _issues: Array[String] = []
var _raid_end: Array = []
var _held_note := ""


func _ready() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"sessions":
				sessions.assign(pair[1].split(","))
			"seeds":
				seeds = pair[1].to_int()
			"rounds":
				rounds = pair[1].to_int()
			"trace":
				trace = pair[1] == "1"


func _run() -> void:
	await get_tree().process_frame
	OS.add_logger(_watch)
	GameEvents.object_yeeted.connect(_on_yeeted)
	GameEvents.player_left_train.connect(_on_player_left.unbind(1))
	GameEvents.npc_knocked_out.connect(_on_knocked_out)
	if "race" in sessions:
		await _probe_stand_up_race()
		sessions.erase("race")
	for name_ in sessions:
		for index in seeds:
			var route := DEFAULT_ROUTE if index < 2 else DEFAULT_ROUTE + index * 101
			await _play_session(name_, route, 1000 + index * 37)
	var errors := _watch.take()
	for line in errors:
		print("LOGERROR " + line)
	print("ISSUES " + JSON.stringify(_issues))
	print("DONE errors=%d" % errors.size())
	get_tree().quit(0)


## Presses grab on the exact tick a shoved body stands up.
func _probe_stand_up_race() -> void:
	for ticks_early: float in [1.5, 0.5, -0.5, -1.5, -3.0, -6.0]:
		await _probe_once(ticks_early)


func _probe_once(ticks_early: float) -> void:
	await _fresh_main(DEFAULT_ROUTE, 5)
	while director.phase != RoundDirector.Phase.RAID:
		await get_tree().physics_frame
	var dummy: TestDummy = director.stowaway_bodies()[0]
	player.global_position = dummy.global_position + Vector3(0.0, 0.0, -1.6)
	dummy.tip_over(Vector3.FORWARD, 1.0, null)
	await get_tree().physics_frame
	var ragdoll: Ragdoll = null
	for body in director.stowaway_bodies():
		if body is Ragdoll:
			ragdoll = body
	var watch := ragdoll.get_node("GetUp")
	while is_instance_valid(watch) and watch._age < watch.STAY_DOWN - TICK * ticks_early:
		# The limb furthest from the pelvis: the standing capsule that replaces the body misses it.
		var far: RagdollPart = ragdoll.parts[0]
		for part in ragdoll.parts:
			if part.global_position.distance_to(ragdoll.anchor()) > far.global_position.distance_to(ragdoll.anchor()):
				far = part
		var stand_at := far.global_position + (far.global_position - ragdoll.anchor()).normalized() * 1.0
		player.global_position = Vector3(stand_at.x, 0.05, stand_at.z)
		input.aim_at(player.eye_position(), far.global_position)
		await get_tree().physics_frame
	input.press_grab()
	await get_tree().physics_frame
	await get_tree().process_frame
	var hands := player.hands
	print("RACE early=%.1f ragdoll_alive=%s held_nonnull=%s held_valid=%s" % [ticks_early, is_instance_valid(ragdoll), hands.held != null, is_instance_valid(hands.held)])
	hands.held = null
	await _teardown()


func _play_session(session: String, route: int, salt: int) -> void:
	_session = session
	var idle_open := session == "idle_open"
	var idle := session == "idle" or idle_open
	_brain = Brain.IDLE if idle else Brain.PLAY
	_skill = POLICIES.get(session, POLICIES["fists"])
	_rng.seed = hash([session, salt])
	await _fresh_main(route, salt)
	if idle_open:
		for opening in main.train.openings():
			opening.set_open(true)
	var last_round := 2 if session == "paying" else rounds
	var number := 1
	var attempt := 1
	var budget := last_round + 4
	while budget > 0:
		budget -= 1
		var record := await _play_round(number, attempt, route, salt)
		print("ROUND " + JSON.stringify(record))
		var passed: bool = record["passed"]
		var done := passed and number >= last_round
		var retry := not passed and attempt == 1 and not idle and session != "paying"
		if not passed and not retry and number >= last_round:
			done = true
		if done:
			break
		if passed or not retry:
			number += 1
			attempt = 1
			if not passed:
				director.round_number = number  # Forced on, to see the later rounds anyway.
		else:
			attempt += 1
		await _press_restart(number)
	await _teardown()


func _fresh_main(route: int, salt: int) -> void:
	TrainState.distance_m = 0.0
	TrainState.speed_mps = 100.0 / 3.6
	TrainState.target_speed_mps = 100.0 / 3.6
	TrainState.route_seed = route
	TrainState.rng_salt = salt
	TrainState.rng_serial = 0
	TestDummy.brain_enabled = true
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	director = main.round_director
	player = main.local_player
	var old := player.input_source
	input = ScriptedInput.new()
	input.name = "BotInput"
	input.yaw = old.yaw
	player.add_child(input)
	player.input_source = input
	player.hands.threw.connect(_on_threw.unbind(1))
	player.hands.swung.connect(_on_swung)


func _teardown() -> void:
	_active = false
	main.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


## --- Round bookkeeping -----------------------------------------------------------

func _play_round(number: int, attempt: int, route: int, salt: int) -> Dictionary:
	_reset_for_round()
	_active = true
	var guard := 0
	while director.phase != RoundDirector.Phase.RESULTS and guard < 60 * 160:
		await get_tree().physics_frame
		guard += 1
	_active = false
	input.throw_held = false
	input.move = Vector2.ZERO
	if guard >= 60 * 160:
		_issue("round %d never reached RESULTS" % number)
	return _round_record(number, attempt, route, salt)


func _reset_for_round() -> void:
	_target = null
	_opening = null
	_history.clear()
	_react_left = _skill["react"]
	_click_left = 0.0
	_grab_left = 0.0
	_hold_left = 0.0
	_carry_time = 0.0
	_heave_time = 0.0
	_part_time = 0.0
	_last_move = Vector2.ZERO
	_stuck_time = 0.0
	_unstick_left = 0.0
	_want_tool = _skill["tool"]
	_tool_time = 0.0
	_carried = null
	_chase_time = 0.0
	_cycle_time = 0.0
	_near_time = 0.0
	_pending.clear()
	_wedge.clear()
	_limbo.clear()
	_ragdolls_seen.clear()
	_stuck_reports.clear()
	_raid_end = []
	_stats = {
		"used": 0.0, "chases": [], "cycles": [], "carries": [], "heaves": 0, "heave_ok": 0, "heave_miss": 0,
		"blind": 0, "hold_breaks": 0, "got_ups": 0, "player_left": 0, "bot_stuck": 0, "self_yeets": 0,
		"swings": 0, "swing_hits": 0, "self_stow": 0, "self_paying": 0, "ko": 0, "downs": 0, "out_time": 0.0, "falls": [],
	}


func _round_record(number: int, attempt: int, route: int, salt: int) -> Dictionary:
	var left := _raid_end
	var record := {
		"session": _session, "route": route, "salt": salt, "round": number, "attempt": attempt,
		"seconds": director.seconds_total, "total": director.stowaways_total, "yeeted": director.stowaways_yeeted,
		"left": director.stowaways_left, "passed": director.last_passed, "used": snappedf(_stats["used"], 0.01),
		"score": director.score, "run_score": director.total_score, "rank": director.rank_title,
		"paying_yeeted": director.passengers_yeeted, "fines": director.fines_paid, "bonus": director.time_bonus,
		"stuck": _stuck_reports.duplicate(), "remaining": left,
	}
	record.merge(_stats)
	return record


func _snapshot() -> Array:
	var left: Array = [{"player": _round3(player.global_position)}]
	for body in director.stowaway_bodies():
		left.append({"kind": "ragdoll" if body is Ragdoll else "dummy", "at": _round3(_body_point(body)), "mode": body.mode if body is TestDummy else -1})
	return left


func _press_restart(number: int) -> void:
	var button: Button = main.hud.round_hud.restart_button
	var guard := 0
	while button.disabled and guard < 60 * 8:
		await get_tree().process_frame
		guard += 1
	if button.disabled:
		_issue("restart button never enabled")
	button.pressed.emit()
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	_check_restart(number)


func _check_restart(number: int) -> void:
	var dummies := 0
	var bodies := 0
	for body in main.npc_bodies():
		if body.is_queued_for_deletion():
			continue
		if body is TestDummy:
			dummies += 1
		elif body is Ragdoll:
			bodies += 1
	var wanted := RoundDirector.stowaways_for(number) + RoundDirector.passengers_for(number)
	if director.phase != RoundDirector.Phase.TITLE:
		_issue("restart: phase %d" % director.phase)
	if director.round_number != number:
		_issue("restart: round %d, wanted %d" % [director.round_number, number])
	if director.score != 0:
		_issue("restart: score %d" % director.score)
	if not is_equal_approx(director.time_left, float(RoundDirector.seconds_for(number))):
		_issue("restart: clock %.2f" % director.time_left)
	if dummies != wanted or bodies != 0:
		_issue("restart: %d dummies %d bodies, wanted %d" % [dummies, bodies, wanted])
	if director.stowaway_bodies().size() != RoundDirector.stowaways_for(number):
		_issue("restart: wrong stowaway count")
	if player.hands.held != null or not player.is_aboard():
		_issue("restart: player not clean")
	if player.global_position.distance_to(player.spawn_point) > 0.3:
		_issue("restart: player not at spawn")
	if TrainState.target_speed_mps < 1.0:
		_issue("restart: train still braked")
	if main.train.open_opening_count() > 0:
		_stats_note_open(main.train.open_opening_count())


func _stats_note_open(count: int) -> void:
	print("NOTE restart left %d openings open" % count)


func _issue(text: String) -> void:
	if text not in _issues:
		_issues.append(text)
	print("ISSUE " + text)


func _on_yeeted(body: Node3D) -> void:
	if not _active or not (body is Ragdoll):
		return
	if _pending.has(body):
		_pending.erase(body)
		_stats["heave_ok"] += 1
	else:
		_stats["self_yeets"] += 1
		_stats["self_stow" if body.is_stowaway else "self_paying"] += 1
	var counts: bool = body.is_stowaway if _skill["prey"] == "stowaways" else not body.is_stowaway
	if counts:
		_stats["cycles"].append(snappedf(_cycle_time, 0.01))
		_cycle_time = 0.0


func _on_threw() -> void:
	_threw_now = true
	if _active and is_instance_valid(_carried):
		_stats["heaves"] += 1
		_pending[_carried] = 3.0


func _on_swung(hit: bool) -> void:
	if _active and hit:
		_stats["swing_hits"] += 1


func _on_player_left() -> void:
	if _active:
		_stats["player_left"] += 1
		_stats["falls"].append({"at": _round3(player.global_position), "t": snappedf(_stats["used"], 0.1), "carry": _carried != null})


func _on_knocked_out(npc: Node3D, _ragdoll: Node3D, _attacker: Node3D) -> void:
	if _active and npc is TestDummy and npc.is_stowaway:
		_stats["ko"] += 1


## --- Every tick ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active or _stats.is_empty():
		return
	_measure(delta)
	if director.phase == RoundDirector.Phase.ENDING and _raid_end.is_empty():
		_raid_end = _snapshot()
	if _brain == Brain.PLAY:
		_think(delta)
	_threw_now = false


func _measure(delta: float) -> void:
	if director.phase != RoundDirector.Phase.RAID:
		return
	_stats["used"] = director.seconds_total - director.time_left
	_cycle_time += delta
	for ragdoll: Variant in _pending.keys():
		if not is_instance_valid(ragdoll):
			_pending.erase(ragdoll)
			continue
		_pending[ragdoll] -= delta
		if _pending[ragdoll] <= 0.0:
			_pending.erase(ragdoll)
			_stats["heave_miss"] += 1
			_report("heave_miss", ragdoll, _body_point(ragdoll))
	for body in director.stowaway_bodies():
		var id := body.get_instance_id()
		if body is TestDummy:
			_measure_dummy(body, id, delta)
		elif body is Ragdoll:
			_measure_body(body, id, delta)


func _measure_dummy(body: TestDummy, id: int, delta: float) -> void:
	var at := body.global_position
	if absf(at.x) > 1.9 or at.y > 0.7 or at.y < -0.4:
		_report("npc_out_of_bounds", body, at)
	var fleeing: bool = body.mode == TestDummy.Mode.FLEE or body.mode == TestDummy.Mode.PANIC
	if fleeing and body.get_real_velocity().length() < 0.2 and body._stumble_left <= 0.0:
		_wedge[id] = _wedge.get(id, 0.0) + delta
		if _wedge[id] > WEDGE_LIMIT:
			_wedge[id] = 0.0
			_report("npc_wedged", body, at)
	else:
		_wedge[id] = 0.0


func _measure_body(body: Ragdoll, id: int, delta: float) -> void:
	if not _ragdolls_seen.has(id):
		_ragdolls_seen[id] = true
		_stats["downs"] += 1
		body.tree_exiting.connect(_on_ragdoll_gone.bind(body))
	var at := body.anchor()
	if body.holder == null and (absf(at.x) > 1.95 or at.y < -0.7 or at.y > 2.8):
		_limbo[id] = _limbo.get(id, 0.0) + delta
		if _limbo[id] > LIMBO_LIMIT:
			_limbo[id] = 0.0
			_report("body_in_limbo", body, at)
	else:
		_limbo[id] = 0.0


func _on_ragdoll_gone(body: Ragdoll) -> void:
	if _active and director.phase == RoundDirector.Phase.RAID and not body.off_train:
		_stats["got_ups"] += 1


func _report(kind: String, body: Node3D, at: Vector3) -> void:
	var entry := {"kind": kind, "at": _round3(at), "t": snappedf(_stats["used"], 0.1), "player": _round3(player.global_position)}
	if body is TestDummy:
		entry["mode"] = body.mode
	_stuck_reports.append(entry)
	print("STUCK " + JSON.stringify(entry))


func _round3(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


func _think(delta: float) -> void:
	_click_left -= delta
	_grab_left -= delta
	_react_left -= delta
	_noise_yaw = lerpf(_noise_yaw, _rng.randfn(0.0, _skill["noise"] * 5.0), 0.04)
	_noise_pitch = lerpf(_noise_pitch, _rng.randfn(0.0, _skill["noise"] * 5.0), 0.04)
	input.sprint = false
	input.jump = false
	if director.phase != RoundDirector.Phase.RAID:
		input.move = Vector2.ZERO
		input.throw_held = false
		return
	if not player.is_aboard():
		_think_reboard()
		return
	var hands := player.hands
	if not is_instance_valid(hands.held) and str(hands.held) != "<null>":
		_issue("hands.held dangling: session %s salt %d round %d t=%.1f last=%s" % [_session, TrainState.rng_salt, director.round_number, _stats["used"], _held_note])
		hands.held = null  # Only so the run can go on: a player has no way out of this.
	_note_held()
	if _at_rear_door():
		_think_rear_door(delta)
		return
	if hands.is_dragging():
		_carried = (hands.held as RagdollPart).ragdoll
		_think_carry(delta)
		return
	if _carried != null:
		if not _threw_now and is_instance_valid(_carried) and not _carried.off_train:
			_stats["hold_breaks"] += 1
			_report("hold_broke", _carried, _carried.anchor())
		_carried = null
		_opening = null
		input.throw_held = false
		_carry_time = 0.0
	if _want_tool:
		_think_tool(delta)
		return
	_pick_target()
	if _target == null:
		input.move = Vector2.ZERO
		return
	var seen := _perceived(_target)
	if _react_left > 0.0:
		input.move = _last_move
		input.sprint = _skill["sprint"]
		_aim(seen, delta)
		return
	if _target is Ragdoll:
		_think_pickup(_target, seen, delta)
	else:
		_think_chase(seen, delta)
	_watch_near(seen, delta)


## The body a tag on screen would send a player to. A body already down comes first.
func _note_held() -> void:
	var held := player.hands.held
	if held is RagdollPart:
		var ragdoll: Ragdoll = (held as RagdollPart).ragdoll
		_held_note = "body t=%.2f stowaway=%s off_train=%s getup=%s queued=%s at=%s" % [_stats["used"], ragdoll.is_stowaway, ragdoll.off_train, ragdoll.has_node("GetUp"), ragdoll.is_queued_for_deletion(), ragdoll.anchor()]
	elif held != null:
		_held_note = "prop %s t=%.2f at=%s queued=%s" % [held.name, _stats["used"], held.global_position, held.is_queued_for_deletion()]


func _pick_target() -> void:
	var at := player.global_position
	var best: Node3D = null
	var best_cost := INF
	for body in _prey():
		var point := _body_point(body)
		var cost := absf(point.z - at.z) + absf(point.x - at.x)
		if body is Ragdoll:
			cost -= 6.0
		if body == _target:
			cost -= 3.0
		if cost < best_cost:
			best_cost = cost
			best = body
	if best != _target:
		if is_instance_valid(_target) and _target is TestDummy and best is Ragdoll or _target == null or not is_instance_valid(_target):
			if _chase_time > 0.0 and best is Ragdoll:
				_stats["chases"].append(snappedf(_chase_time, 0.01))
				_chase_time = 0.0
		_target = best
		_history.clear()
		_near_time = 0.0
		_part_time = 0.0
		_react_left = _beat()


## A change of plan costs a reaction, plus a human moment of working out what comes next.
func _beat() -> float:
	return _skill["react"] + _rng.randf_range(0.0, _skill.get("hesitate", 0.0))


func _prey() -> Array[Node3D]:
	if _skill["prey"] == "stowaways":
		return director.stowaway_bodies().filter(func(body: Node3D) -> bool: return not _pending.has(body) and not (body is Ragdoll and body.holder != null))
	var found: Array[Node3D] = []
	for body in main.npc_bodies():
		if body.is_queued_for_deletion():
			continue
		if body is TestDummy and not body.is_stowaway:
			found.append(body)
		elif body is Ragdoll and not body.is_stowaway and not body.off_train and not _pending.has(body):
			found.append(body)
	return found


func _body_point(body: Node3D) -> Vector3:
	if body is Ragdoll:
		return body.chest.global_position
	return body.global_position + Vector3.UP * 1.2


## Where the player thinks it is: where it was a reaction ago, partly led.
func _perceived(body: Node3D) -> Vector3:
	var now := _body_point(body)
	var delay := roundi(_skill["react"] / TICK)
	_history.append(now)
	if _history.size() > delay + 1:
		_history.pop_front()
	var old: Vector3 = _history[0]
	if _history.size() < 2:
		return now
	var seconds := (_history.size() - 1) * TICK
	var velocity := (now - old) / seconds
	return old + velocity * seconds * float(_skill["predict"])


func _think_chase(seen: Vector3, delta: float) -> void:
	_chase_time += delta
	var distance := _flat(seen - player.global_position).length()
	_steer(seen, _skill["sprint"], delta)
	_aim(seen, delta)
	if distance < BONK_AT and _click_left <= 0.0 and _aim_error(seen) < 0.3:
		input.press_use()
		_click_left = CLICK_GAP
		_stats["swings"] += 1


func _think_pickup(body: Ragdoll, seen: Vector3, delta: float) -> void:
	var hands := player.hands
	var distance := _flat(seen - player.global_position).length()
	_part_time += delta
	if _part_time > 0.8:
		_part_time = 0.0
		_part_index += 1
	var point := seen
	if _part_index % 3 != 0:
		point = body.parts[_part_index % body.parts.size()].global_position
	var close := GRAB_AT if _near_time < 1.2 else 0.5  # Crosshair blocked: step right up to it.
	if distance > close:
		_steer(seen, _skill["sprint"], delta)
	else:
		input.move = Vector2.ZERO
		_last_move = input.move
	_aim(point, delta)
	if _grab_left > 0.0:
		return
	if hands.held != null:
		input.press_grab()
		_grab_left = GRAB_GAP
		return
	var aimed := _aimed()
	if aimed is RagdollPart and (aimed as RagdollPart).ragdoll == body:
		input.press_grab()
		_grab_left = GRAB_GAP


func _think_tool(delta: float) -> void:
	_tool_time += delta
	var hands := player.hands
	if hands.held != null or _tool_time > 3.0:
		_want_tool = false
		_react_left = _skill["react"]
		return
	var best: PhysicsProp = null
	for prop in main.prop_bodies():
		if prop is PhysicsProp and prop.is_tool and prop.bonk_power >= 3:
			if best == null or prop.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = prop
	if best == null:
		_want_tool = false
		return
	var point := best.global_position
	if _flat(point - player.global_position).length() > 1.4:
		_steer(point, false, delta)
	else:
		input.move = Vector2.ZERO
	_aim(point, delta)
	if _grab_left <= 0.0 and _aimed() == best:
		input.press_grab()
		_grab_left = GRAB_GAP


func _think_carry(delta: float) -> void:
	var hands := player.hands
	_carry_time += delta
	if _opening == null:
		_opening = _best_opening()
		_heave_time = 0.0
		_react_left = _beat()
		_stats["carries"].append(0.0)
	var carries: Array = _stats["carries"]
	carries[-1] = snappedf(_carry_time, 0.01)
	var center := _opening.global_position
	if _react_left > 0.0:
		input.move = _last_move
		input.sprint = _skill["sprint"]
		_aim(center, delta)
		return
	var eye_distance := player.eye_position().distance_to(center)
	var stand := Vector3(TestDummy.aisle_x(center.z, signf(center.x) * 0.42), 0.0, center.z)
	_aim(center, delta)
	if not _opening.is_open:
		input.throw_held = false
		if eye_distance > OPEN_AT:
			_steer(stand, _skill["sprint"], delta)
		else:
			input.move = Vector2.ZERO
		if _grab_left <= 0.0 and _aimed_opening() == _opening:
			input.press_grab()
			_grab_left = GRAB_GAP
			_react_left = _beat()
		if _carry_time > 12.0:
			_opening = _best_opening(_opening)
			_carry_time = 0.0
		return
	if eye_distance > HEAVE_AT or (input.throw_held and hands.assist_point == null and _flat(stand - player.global_position).length() > 0.4):
		_steer(stand, _skill["sprint"], delta)
	else:
		input.move = Vector2.ZERO
	if eye_distance < HEAVE_FROM and _aim_error(center) < 0.5:
		input.throw_held = true
	if not input.throw_held:
		return
	_heave_time += delta
	if hands.assist_point != null and hands.charge_fraction() >= RELEASE_CHARGE:
		input.throw_held = false
	elif _heave_time > HEAVE_WAIT:
		input.throw_held = false
		_stats["blind"] += 1
		_report("blind_heave", _carried, _carried.anchor())


func _best_opening(skip: TrainOpening = null) -> TrainOpening:
	var at := player.global_position
	var best: TrainOpening = null
	var best_cost := INF
	for opening in main.train.openings():
		var center := opening.global_position
		if opening == skip or opening.name == "Door_Rear" or center.z < TestDummy.AISLE_MIN_Z:
			continue
		var cost := absf(center.z - at.z) + absf(center.x - at.x) * 0.5
		if not opening.is_open:
			cost += CLOSED_PENALTY
		if center.x > 0.0 and center.z > TestDummy.COAL_BUNKER_MIN_Z and center.z < TestDummy.COAL_BUNKER_MAX_Z:
			cost += BUNKER_PENALTY
		if cost < best_cost:
			best_cost = cost
			best = opening
	return best


## Reboarding lands on the rear platform, behind the rear door.
func _at_rear_door() -> bool:
	var door := main.train.openings().back() as TrainOpening
	return player.global_position.z > 28.0 and not door.is_open


func _think_rear_door(delta: float) -> void:
	var door := main.train.openings().back() as TrainOpening
	_aim(door.global_position, delta)
	input.move = Vector2.ZERO
	if _react_left <= 0.0 and _grab_left <= 0.0 and _aimed_opening() == door:
		input.press_grab()
		_grab_left = GRAB_GAP


func _think_reboard() -> void:
	input.throw_held = false
	_stats["out_time"] += TICK
	_react_left = _skill["react"]
	var rope := main.train.rope
	var at := player.global_position
	input.yaw = 0.0
	input.move = Vector2(clampf(-at.x, -1.0, 1.0), 0.0)
	if rope.in_reach(at):
		input.press_grab()


func _watch_near(seen: Vector3, delta: float) -> void:
	if _flat(seen - player.global_position).length() < 3.0:
		_near_time += delta
		if _near_time > NEAR_LIMIT:
			_near_time = 0.0
			_report("near_target_no_progress", _target, seen)
	else:
		_near_time = 0.0


## --- Hands and feet --------------------------------------------------------------

func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


## What the crosshair was on at the last Hands tick. The body may have been freed since.
func _aimed() -> Object:
	var collider: Variant = player.hands._aim_hit.get("collider")
	return collider if is_instance_valid(collider) else null


func _aimed_opening() -> Object:
	var collider := _aimed()
	if collider != null and collider.has_meta(&"interactable"):
		return collider.get_meta(&"interactable")
	return null


func _steer(goal: Vector3, sprint: bool, delta: float) -> void:
	var at := player.global_position
	var along := goal.z - at.z
	var way := Vector3(goal.x, 0.0, goal.z)
	if absf(along) > 1.5:
		var ahead := at.z + signf(along) * 1.5
		way = Vector3(TestDummy.aisle_x(ahead, 0.0), 0.0, ahead)
		if absf(at.x) > 0.75 and not (at.z > TestDummy.COAL_BUNKER_MIN_Z and at.z < TestDummy.COAL_BUNKER_MAX_Z):
			way = Vector3(0.0, 0.0, at.z)
	var direction := _flat(way - at).normalized()
	if _unstick_left > 0.0:
		_unstick_left -= delta
		direction = (direction + Vector3.RIGHT * _unstick_side).normalized()
		input.jump = _unstick_left > UNSTICK_TIME * 0.5
	elif _flat(player.velocity).length() < 0.6 and input.move.length() > 0.1:
		_stuck_time += delta
		if _stuck_time > STUCK_AFTER:
			_stuck_time = 0.0
			_unstick_left = UNSTICK_TIME
			_unstick_side = -_unstick_side
			_stats["bot_stuck"] += 1
	else:
		_stuck_time = 0.0
	var local := Basis(Vector3.UP, -player.yaw) * direction
	input.move = Vector2(local.x, -local.z)
	input.sprint = sprint
	_last_move = input.move


func _aim(point: Vector3, delta: float) -> void:
	var to_point := (point - player.eye_position()).normalized()
	var wanted_yaw := atan2(-to_point.x, -to_point.z) + _noise_yaw
	var wanted_pitch := clampf(asin(to_point.y) + _noise_pitch, -1.4, 1.4)
	var step: float = _skill["turn"] * delta
	input.yaw += clampf(wrapf(wanted_yaw - input.yaw, -PI, PI), -step, step)
	input.pitch = move_toward(input.pitch, wanted_pitch, step)


func _aim_error(point: Vector3) -> float:
	return player.aim_forward().angle_to(point - player.eye_position())

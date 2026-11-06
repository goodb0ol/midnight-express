extends Node
## Independent playtester, written to attack what tools/playtest_bot.gd cannot show. It drives
## the real Player and Hands through ScriptedInput, with the real RoundDirector and brains on.
## Unlike that bot it has no x-ray list of targets: it only knows a stowaway once its marker
## has been inside the view cone for a reaction time, it remembers last-seen spots, it searches
## the aisle when nothing is known, and it heaves off-centre, sometimes from far away.
##   godot --headless --path . --fixed-fps 60 res://tools/human_playtest.tscn -- sessions=decent,sloppy,idle,idle_open,paying seeds=1 first=0 rounds=7
## Prints "ROUND {json}", "STUCK {json}", "ISSUE text", "LOGERROR line", then "DONE errors=N".

enum Brain { PLAY, IDLE }

const ErrorWatch := preload("res://tests/error_watch.gd")
const BASE_ROUTE := 20261106
const TICK := 1.0 / 60.0

## turn rad/s, react s, beat: extra s of thinking at a change of plan, noise rad, sight: half
## cone in degrees, far: marker read distance in m, heave_sd: degrees off the hole per heave,
## heave_from: furthest m a heave is tried from, knows: which windows open from the start.
const SKILLS := {
	"decent": {"turn": 5.0, "react": 0.3, "beat": 0.7, "noise": 0.04, "sight": 42.0, "far": 34.0, "heave_sd": 6.0, "heave_from": 4.5, "knows": true, "tool": true, "prey": "stowaways"},
	"sloppy": {"turn": 3.5, "react": 0.45, "beat": 1.2, "noise": 0.07, "sight": 38.0, "far": 24.0, "heave_sd": 13.0, "heave_from": 6.5, "knows": false, "tool": false, "prey": "stowaways"},
	"impatient": {"turn": 3.5, "react": 0.45, "beat": 1.2, "noise": 0.07, "sight": 38.0, "far": 24.0, "heave_sd": 22.0, "heave_from": 6.5, "knows": true, "tool": false, "prey": "stowaways", "no_wait": true},
	"paying": {"turn": 5.0, "react": 0.3, "beat": 0.7, "noise": 0.04, "sight": 42.0, "far": 34.0, "heave_sd": 6.0, "heave_from": 4.5, "knows": true, "tool": false, "prey": "passengers"},
}

const CLICK_GAP := 0.45
const GRAB_GAP := 0.3
const BONK_AT := 2.4
const GRAB_AT := 1.5
const OPEN_AT := 2.3
const HEAVE_WAIT := 3.0
const AIM_FIX_AFTER := 1.0
const STUCK_AFTER := 0.35
const UNSTICK_TIME := 0.5
const SPIN_TIME := 0.8
const NEAR_LIMIT := 7.0
const LONG_CHASE := 15.0
const WEDGE_LIMIT := 1.5
const LIMBO_LIMIT := 2.0
const CARRY_LIMIT := 14.0
const PENDING_TIME := 3.0
const PICKUP_LIMIT := 8.0
const BOILER_FACE_Z := -23.25  ## Where a player's capsule stops, in front of the boiler.
const SLIT_MOUTH_X := 1.38     ## Closest a capsule gets to the gap between boiler and wall.

var sessions: Array[String] = ["decent", "sloppy", "idle", "idle_open", "paying"]
var seeds := 1
var first := 0
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
var _session := ""
var _rng := RandomNumberGenerator.new()

var _memory: Dictionary = {}    # instance id -> {"body": Variant, "at": Vector3}
var _seen_for: Dictionary = {}  # instance id -> seconds in view
var _target: Variant = null
var _opening: TrainOpening = null
var _rusted: Array[TrainOpening] = []
var _history: Array[Vector3] = []
var _react_left := 0.0
var _click_left := 0.0
var _grab_left := 0.0
var _noise_yaw := 0.0
var _noise_pitch := 0.0
var _last_move := Vector2.ZERO
var _stuck_time := 0.0
var _unstick_left := 0.0
var _unstick_side := 1.0
var _spin_left := 0.0
var _search_dir := 1.0
var _searching := false
var _part_time := 0.0
var _part_index := 0
var _pickup_time := 0.0
var _given_up: Dictionary = {}  # instance id -> true: tried, could not get a hand on it.
var _want_tool := false
var _tool_time := 0.0
var _carried: Variant = null
var _carry_time := 0.0
var _heave_time := 0.0
var _heave_off := 0.0
var _heave_dist := 3.0
var _heave_charge := 0.6
var _threw_now := false
var _opened_all := false

var _stats: Dictionary = {}
var _chase_time := 0.0
var _cycle_time := 0.0
var _near_time := 0.0
var _pending: Dictionary = {}
var _wedge: Dictionary = {}
var _limbo: Dictionary = {}
var _reports: Array[Dictionary] = []
var _remaining: Array = []
var _issues: Array[String] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"sessions":
				sessions.assign(pair[1].split(","))
			"seeds":
				seeds = pair[1].to_int()
			"first":
				first = pair[1].to_int()
			"rounds":
				rounds = pair[1].to_int()
			"trace":
				trace = pair[1] == "1"
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	OS.add_logger(_watch)
	GameEvents.object_yeeted.connect(_on_yeeted)
	GameEvents.player_left_train.connect(_on_player_left.unbind(1))
	GameEvents.npc_knocked_out.connect(_on_knocked_out)
	if "slit" in sessions:
		await _probe_slit()
		sessions.erase("slit")
	for session in sessions:
		for index in range(first, first + seeds):
			await _play_session(session, BASE_ROUTE + index * 101, 3000 + index * 41)
	var errors := _watch.take()
	for line in errors:
		print("LOGERROR " + line)
	print("ISSUES " + JSON.stringify(_issues))
	print("DONE errors=%d" % errors.size())
	get_tree().quit(0)


## Drops a stowaway's body in the gap beside the boiler, walks to the closest legal spot and
## sweeps the crosshair over it, the same ray Hands uses.
func _probe_slit() -> void:
	for side: float in [-1.0, 1.0]:
		for z: float in [-24.0, -24.8, -25.6, -26.4, -27.2]:
			await _fresh_main(BASE_ROUTE, 3000)
			while director.phase != RoundDirector.Phase.RAID:
				await get_tree().physics_frame
			var dummy: TestDummy = director.stowaway_bodies()[1]
			dummy.global_position = Vector3(side * 1.45, 0.1, z)
			await get_tree().physics_frame
			dummy.receive_bonk(3, Vector3(0.0, 0.05, -0.02), player)
			await get_tree().physics_frame
			var ragdoll: Ragdoll = null
			for body in director.stowaway_bodies():
				if body is Ragdoll:
					ragdoll = body
			for i in 90:
				await get_tree().physics_frame
			player.global_position = Vector3(side * 1.38, 0.02, -23.24)
			await get_tree().physics_frame
			var parts_hit := 0
			var rest: Vector3 = ragdoll.anchor()
			for part in ragdoll.parts:
				var hit := false
				for offset: Vector3 in [Vector3.ZERO, Vector3.UP * 0.08, Vector3.DOWN * 0.08, Vector3.RIGHT * 0.08, Vector3.LEFT * 0.08]:
					input.aim_at(player.eye_position(), part.global_position + offset)
					player.yaw = input.yaw
					player.pitch = input.pitch
					if player.hands._cast_aim().get("collider") is RagdollPart:
						hit = true
				if hit:
					parts_hit += 1
			print("SLIT side=%d placed_z=%.1f rest=%s player=%s parts_grabbable=%d of %d" % [side, z, _round3(rest), _round3(player.global_position), parts_hit, ragdoll.parts.size()])
			await _teardown()


func _play_session(session: String, route: int, salt: int) -> void:
	_session = session
	var idle := session.begins_with("idle")
	_brain = Brain.IDLE if idle else Brain.PLAY
	_skill = SKILLS.get(session, SKILLS["decent"])
	_rng.seed = hash([session, salt])
	await _fresh_main(route, salt)
	var last_round := rounds
	if session == "paying":
		last_round = 2
	elif idle:
		last_round = 4
	var number := 1
	var attempt := 1
	while true:
		var record := await _play_round(number, attempt, route, salt)
		print("ROUND " + JSON.stringify(record))
		var passed: bool = record["passed"]
		var retry := not passed and attempt == 1 and not idle and session != "paying"
		if number >= last_round and not retry:
			break
		var run_before: int = director.total_score
		if retry:
			attempt += 1
		else:
			number += 1
			attempt = 1
			if not passed:
				director.round_number = number  # Forced on after a second loss, to see later raids.
		await _press_restart(number, passed, run_before)
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
	input.name = "HumanInput"
	input.yaw = old.yaw
	player.add_child(input)
	player.input_source = input
	player.hands.threw.connect(_on_threw.unbind(1))


func _teardown() -> void:
	_active = false
	main.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


## --- Rounds ----------------------------------------------------------------------

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
	var record := {
		"session": _session, "route": route, "salt": salt, "round": number, "attempt": attempt,
		"seconds": director.seconds_total, "total": director.stowaways_total, "yeeted": director.stowaways_yeeted,
		"left": director.stowaways_left, "passed": director.last_passed, "used": snappedf(_stats["used"], 0.01),
		"score": director.score, "run_score": director.total_score, "rank": director.rank_title,
		"paying_yeeted": director.passengers_yeeted, "fines": director.fines_paid, "bonus": director.time_bonus,
		"stuck": _reports.duplicate(), "remaining": _remaining,
	}
	record.merge(_stats)
	return record


func _reset_for_round() -> void:
	_memory.clear()
	_seen_for.clear()
	_target = null
	_opening = null
	_rusted.clear()
	_history.clear()
	_react_left = _skill["react"]
	_click_left = 0.0
	_grab_left = 0.0
	_last_move = Vector2.ZERO
	_stuck_time = 0.0
	_unstick_left = 0.0
	_spin_left = 0.0
	_searching = false
	_part_time = 0.0
	_pickup_time = 0.0
	_given_up.clear()
	_want_tool = _skill["tool"]
	_tool_time = 0.0
	_carried = null
	_carry_time = 0.0
	_opened_all = false
	_chase_time = 0.0
	_cycle_time = 0.0
	_near_time = 0.0
	_pending.clear()
	_wedge.clear()
	_limbo.clear()
	_reports.clear()
	_remaining = []
	_stats = {
		"used": 0.0, "search": 0.0, "chases": [], "cycles": [], "carries": [], "heaves": 0, "heave_ok": 0, "heave_miss": 0,
		"heave_log": [], "no_prompt": 0, "blind": 0, "hold_breaks": 0, "player_left": 0, "fall_drops": 0, "bot_stuck": 0, "falls": [], "stick_spots": [],
		"self_stow": 0, "self_paying": 0, "ko": 0, "swings": 0, "rusted": 0, "out_time": 0.0,
	}


func _press_restart(number: int, passed: bool, run_before: int) -> void:
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
		_issue("restart: %d openings left open" % main.train.open_opening_count())
	if passed and director.total_score != run_before:
		_issue("restart: run score changed after a win")
	if not passed and director.total_score != 0:
		_issue("restart: run score not cleared after a loss")


func _issue(text: String) -> void:
	if text not in _issues:
		_issues.append(text)
	print("ISSUE " + text)


func _report(kind: String, body: Variant, at: Vector3) -> void:
	var entry := {"kind": kind, "at": _round3(at), "t": snappedf(_stats["used"], 0.1), "player": _round3(player.global_position), "round": director.round_number}
	if is_instance_valid(body) and body is TestDummy:
		entry["mode"] = body.mode
	_reports.append(entry)
	print("STUCK " + JSON.stringify(entry))


func _round3(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## --- Events ----------------------------------------------------------------------

func _on_yeeted(body: Node3D) -> void:
	if not _active or not (body is Ragdoll):
		return
	if _pending.has(body):
		var log_entry: Dictionary = _pending[body]["log"]
		log_entry["ok"] = true
		_pending.erase(body)
		_stats["heave_ok"] += 1
	else:
		_stats["self_stow" if body.is_stowaway else "self_paying"] += 1
	var counts: bool = body.is_stowaway if _skill.get("prey", "stowaways") == "stowaways" else not body.is_stowaway
	if counts:
		_stats["cycles"].append(snappedf(_cycle_time, 0.01))
		_cycle_time = 0.0


func _on_threw() -> void:
	_threw_now = true
	if not _active or not is_instance_valid(_carried) or not (_carried is Ragdoll):
		return
	_stats["heaves"] += 1
	var entry := {"dist": snappedf(_stats_heave_distance(), 0.1), "off": snappedf(rad_to_deg(_heave_off), 0.1), "charge": snappedf(_heave_charge, 0.01), "ok": false}
	_stats["heave_log"].append(entry)
	_pending[_carried] = {"left": PENDING_TIME, "log": entry}


func _stats_heave_distance() -> float:
	return -1.0 if _opening == null else player.eye_position().distance_to(_opening.global_position)


func _on_player_left() -> void:
	if not _active:
		return
	_stats["player_left"] += 1
	_stats["falls"].append({"at": _round3(player.global_position), "t": snappedf(_stats["used"], 0.1), "carry": _carried != null})
	if _carried != null:
		_stats["fall_drops"] += 1


func _on_knocked_out(npc: Node3D, ragdoll: Node3D, _attacker: Node3D) -> void:
	if not _active:
		return
	if npc is TestDummy and npc.is_stowaway:
		_stats["ko"] += 1
	if ragdoll is Ragdoll and npc.global_position.distance_to(player.global_position) < 6.0:
		_memory[ragdoll.get_instance_id()] = {"body": ragdoll, "at": npc.global_position}  # Just watched it drop.


## --- Every tick ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active or _stats.is_empty():
		return
	_measure(delta)
	if director.phase == RoundDirector.Phase.ENDING and _remaining.is_empty():
		_remaining = _snapshot()
	if _session == "idle_open" and director.phase == RoundDirector.Phase.RAID and not _opened_all:
		_opened_all = true
		for opening in main.train.openings():
			if not opening.jammed:
				opening.set_open(true)
	if _brain == Brain.PLAY:
		_think(delta)
	if trace and Engine.get_physics_frames() % 60 == 0:
		_trace_line()
	_threw_now = false


func _trace_line() -> void:
	var target := "none"
	if is_instance_valid(_target):
		target = "%s %s" % ["body" if _target is Ragdoll else "dummy", _round3(_point(_target))]
	var left: Array = []
	for body in director.stowaway_bodies():
		left.append([("R" if body is Ragdoll else "D"), _round3(_point(body)), _memory.has(body.get_instance_id())])
	print("TRACE t=%.0f at=%s yaw=%.2f held=%s target=%s search=%s dir=%d left=%s" % [_stats["used"], _round3(player.global_position), input.yaw, player.hands.held != null, target, _searching, _search_dir, left])


func _snapshot() -> Array:
	var left: Array = [{"player": _round3(player.global_position)}]
	for body in director.stowaway_bodies():
		var entry := {"kind": "ragdoll" if body is Ragdoll else "dummy", "at": _round3(_point(body)), "known": _memory.has(body.get_instance_id())}
		if body is TestDummy:
			entry["mode"] = body.mode
		left.append(entry)
	return left


func _measure(delta: float) -> void:
	if director.phase != RoundDirector.Phase.RAID:
		return
	_stats["used"] = director.seconds_total - director.time_left
	_cycle_time += delta
	for ragdoll: Variant in _pending.keys():
		if not is_instance_valid(ragdoll):
			_pending.erase(ragdoll)
			continue
		_pending[ragdoll]["left"] -= delta
		if _pending[ragdoll]["left"] <= 0.0:
			_pending.erase(ragdoll)
			_stats["heave_miss"] += 1
			_report("heave_miss", ragdoll, ragdoll.anchor())
	for body in director.stowaway_bodies():
		var id := body.get_instance_id()
		if body is TestDummy:
			var at: Vector3 = body.global_position
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
		elif body is Ragdoll:
			var at: Vector3 = body.anchor()
			if body.holder == null and (absf(at.x) > 1.95 or at.y < -0.7 or at.y > 2.8):
				_limbo[id] = _limbo.get(id, 0.0) + delta
				if _limbo[id] > LIMBO_LIMIT:
					_limbo[id] = 0.0
					_report("body_in_limbo", body, at)
			else:
				_limbo[id] = 0.0


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
		_reboard()
		return
	_look(delta)
	var hands := player.hands
	if player.global_position.z > 28.0 and not (main.train.openings().back() as TrainOpening).is_open:
		_rear_door(delta)
		return
	if hands.is_dragging():
		_carried = (hands.held as RagdollPart).ragdoll
		_carry(delta)
		return
	if _carried != null:
		if not _threw_now and is_instance_valid(_carried) and not _carried.off_train:
			_stats["hold_breaks"] += 1
			_report("hold_broke", _carried, _carried.anchor())
		_carried = null
		_opening = null
		input.throw_held = false
		_carry_time = 0.0
		_react_left = _beat()
	if _want_tool:
		_get_tool(delta)
		return
	_choose_target()
	if _target == null:
		_search(delta)
		return
	_searching = false
	var seen := _perceived(_target)
	if _react_left > 0.0:
		input.move = _last_move
		input.sprint = true
		_aim(seen, delta)
		return
	if _target is Ragdoll:
		if _chase_time > 0.0:
			_stats["chases"].append(snappedf(_chase_time, 0.01))
			_chase_time = 0.0
		_pick_up(_target, seen, delta)
	else:
		_chase(seen, delta)
	if _flat(seen - player.global_position).length() < 3.0:
		_near_time += delta
		if _near_time > NEAR_LIMIT:
			_near_time = 0.0
			_report("near_target_no_progress", _target, seen)
	else:
		_near_time = 0.0


## --- Eyes ------------------------------------------------------------------------

## Markers draw through walls, so sight is a view cone and a read distance. Passengers have no
## marker and need a clear line.
func _look(delta: float) -> void:
	var eye := player.eye_position()
	var forward := player.aim_forward()
	var half := deg_to_rad(_skill["sight"])
	var far: float = _skill["far"]
	var marked: bool = _skill["prey"] == "stowaways"
	for body in _prey():
		var id := body.get_instance_id()
		var point := _point(body) + Vector3.UP * (1.1 if body is TestDummy else 0.9)
		var offset := point - eye
		var visible: bool = forward.angle_to(offset) < half and offset.length() < far
		if offset.length() < 4.0 and _clear_line(eye, point):
			visible = true  # Too close to lose, whatever the cone says.
		elif visible and not marked:
			visible = offset.length() < 16.0 and _clear_line(eye, point)
		if visible:
			_seen_for[id] = _seen_for.get(id, 0.0) + delta
			if _seen_for[id] >= _skill["react"]:
				_memory[id] = {"body": body, "at": _point(body)}
		else:
			_seen_for[id] = 0.0


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.HULL, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _prey() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if _skill["prey"] == "stowaways":
		for body in director.stowaway_bodies():
			if not (_pending.has(body) or (body is Ragdoll and body.holder != null) or _given_up.has(body.get_instance_id())):
				found.append(body)
		return found
	for body in main.npc_bodies():
		if body.is_queued_for_deletion():
			continue
		if body is TestDummy and not body.is_stowaway:
			found.append(body)
		elif body is Ragdoll and not body.is_stowaway and not body.off_train and not _pending.has(body) and body.holder == null:
			found.append(body)
	return found


func _point(body: Node3D) -> Vector3:
	if body is Ragdoll:
		return body.chest.global_position
	return body.global_position + Vector3.UP * 1.2


func _choose_target() -> void:
	var live := _prey()
	var at := player.global_position
	var best: Variant = null
	var best_cost := INF
	for id: int in _memory.keys():
		var entry: Dictionary = _memory[id]
		var body: Variant = entry["body"]
		if not is_instance_valid(body) or body not in live:
			_memory.erase(id)
			continue
		var point: Vector3 = entry["at"]
		if _seen_for.get(id, 0.0) <= 0.0 and _flat(point - at).length() < 1.8:
			_memory.erase(id)  # Got to where it was. Not there now.
			continue
		var cost := absf(point.z - at.z) + absf(point.x - at.x)
		if body is Ragdoll:
			cost -= 6.0
		if is_same(body, _target):
			cost -= 3.0
		if cost < best_cost:
			best_cost = cost
			best = body
	if not is_same(best, _target):
		_target = best
		_history.clear()
		_near_time = 0.0
		_part_time = 0.0
		_pickup_time = 0.0
		if best != null:
			_react_left = _beat()


func _beat() -> float:
	return _skill["react"] + _rng.randf_range(0.0, _skill["beat"])


## Where the player thinks it is: a reaction ago, half led; last seen if out of view.
func _perceived(body: Variant) -> Vector3:
	var id: int = body.get_instance_id()
	if _seen_for.get(id, 0.0) <= 0.0:
		var entry: Dictionary = _memory.get(id, {})
		return entry.get("at", _point(body))
	var now := _point(body)
	var delay := roundi(float(_skill["react"]) / TICK)
	_history.append(now)
	if _history.size() > delay + 1:
		_history.pop_front()
	var old: Vector3 = _history[0]
	if _history.size() < 2:
		return now
	return old + (now - old) * 0.4


func _search(delta: float) -> void:
	_stats["search"] += delta
	var at := player.global_position
	if not _searching:
		_searching = true
		_spin_left = SPIN_TIME
		_search_dir = 1.0 if TestDummy.AISLE_MAX_Z - at.z > at.z - TestDummy.AISLE_MIN_Z else -1.0
	if _spin_left > 0.0:
		_spin_left -= delta
		_aim(at + Vector3(0.0, 1.4, _search_dir * 8.0), delta)
		input.move = Vector2.ZERO
		_last_move = input.move
		return
	var end := TestDummy.AISLE_MAX_Z - 1.0 if _search_dir > 0.0 else TestDummy.AISLE_MIN_Z + 1.0
	if absf(at.z - end) < 1.5:
		_search_dir = -_search_dir
		_spin_left = SPIN_TIME
		return
	_steer(Vector3(0.0, 0.0, end), true, delta)
	_aim(at + Vector3(sin(_stats["used"] * 1.4) * 2.5, 1.4, _search_dir * 8.0), delta)


## --- Hands -----------------------------------------------------------------------

func _chase(seen: Vector3, delta: float) -> void:
	_chase_time += delta
	if _chase_time > LONG_CHASE:
		_chase_time = 0.0
		_stats["chases"].append(LONG_CHASE)
		_report("long_chase", _target, seen)
	var distance := _flat(seen - player.global_position).length()
	_steer(seen, true, delta)
	_aim(seen, delta)
	if distance < BONK_AT and _click_left <= 0.0 and _aim_error(seen) < 0.3:
		input.press_use()
		_click_left = CLICK_GAP
		_stats["swings"] += 1


func _pick_up(body: Ragdoll, seen: Vector3, delta: float) -> void:
	var hands := player.hands
	var distance := _flat(seen - player.global_position).length()
	_pickup_time += delta
	if _pickup_time > PICKUP_LIMIT:
		_report("body_out_of_reach", body, body.anchor())
		_given_up[body.get_instance_id()] = true
		_memory.erase(body.get_instance_id())
		_target = null
		return
	_part_time += delta
	if _part_time > 0.8:
		_part_time = 0.0
		_part_index += 1
	var point := seen
	if _part_index % 3 != 0:
		point = body.parts[_part_index % body.parts.size()].global_position
	if seen.z < BOILER_FACE_Z:
		_steer(Vector3(signf(seen.x) * SLIT_MOUTH_X, 0.0, BOILER_FACE_Z), false, delta)  # Best a player can do.
	elif distance > (GRAB_AT if _near_time < 1.2 else 0.5):
		_steer(seen, true, delta)
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


func _get_tool(delta: float) -> void:
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


func _carry(delta: float) -> void:
	var hands := player.hands
	_carry_time += delta
	if _opening == null:
		_plan_exit()
	var carries: Array = _stats["carries"]
	carries[-1] = snappedf(_carry_time, 0.01)
	var center := _opening.global_position
	if _react_left > 0.0:
		input.move = _last_move
		input.sprint = true
		_aim(center, delta)
		return
	var eye_distance := player.eye_position().distance_to(center)
	var stand := Vector3(TestDummy.aisle_x(center.z, signf(center.x) * 0.42), 0.0, center.z)
	if not _opening.is_open:
		input.throw_held = false
		_aim(center, delta)
		if eye_distance > OPEN_AT:
			_steer(stand, true, delta)
		else:
			input.move = Vector2.ZERO
		if _grab_left <= 0.0 and hands._use_target() == _opening:
			if _opening.jammed:
				_rusted.append(_opening)
				_stats["rusted"] += 1
				_plan_exit()
				return
			input.press_grab()
			_grab_left = GRAB_GAP
			_react_left = _skill["react"]
		if _carry_time > CARRY_LIMIT:
			_rusted.append(_opening)
			_plan_exit()
			_carry_time = 0.0
		return
	var off := _heave_off if _heave_time < AIM_FIX_AFTER else 0.0
	_aim(center, delta, off)
	if eye_distance > _heave_dist or (_heave_time >= AIM_FIX_AFTER and hands.assist_point == null):
		_steer(stand, true, delta)
	else:
		input.move = Vector2.ZERO
	if eye_distance < YeetTuning.ASSIST_RANGE and _aim_error(center) < 0.7:
		input.throw_held = true
	if not input.throw_held:
		return
	_heave_time += delta
	if hands.charge_fraction() >= _heave_charge and (hands.assist_point != null or _skill.get("no_wait", false)):
		input.throw_held = false
	elif hands.charge_fraction() >= 1.0 and hands.assist_point == null and _stats_note_prompt():
		pass
	if input.throw_held and _heave_time > HEAVE_WAIT:
		input.throw_held = false
		_stats["blind"] += 1
		_report("blind_heave", _carried, _carried.anchor())


## One count per heave of a full charge with no "Let go: YEET!" prompt on screen.
func _stats_note_prompt() -> bool:
	if _heave_time < AIM_FIX_AFTER + TICK * 1.5 and _heave_time >= AIM_FIX_AFTER:
		_stats["no_prompt"] += 1
	return true


func _plan_exit() -> void:
	var at := player.global_position
	var best: TrainOpening = null
	var best_cost := INF
	var knows: bool = _skill["knows"]
	for opening in main.train.openings():
		var center := opening.global_position
		if opening.name == "Door_Rear" or center.z < TestDummy.AISLE_MIN_Z or opening in _rusted:
			continue
		if knows and opening.jammed:
			continue
		var cost := absf(center.z - at.z) + absf(center.x - at.x) * 0.5
		if not opening.is_open:
			cost += 2.0
		if center.x > 0.0 and center.z > TestDummy.COAL_BUNKER_MIN_Z and center.z < TestDummy.COAL_BUNKER_MAX_Z:
			cost += 3.0
		if cost < best_cost:
			best_cost = cost
			best = opening
	if best == null:
		_rusted.clear()
		_plan_exit()
		return
	if _opening == null:
		_stats["carries"].append(0.0)
	_opening = best
	_heave_time = 0.0
	_heave_off = deg_to_rad(_rng.randfn(0.0, _skill["heave_sd"]))
	_heave_dist = _rng.randf_range(2.2, _skill["heave_from"])
	_heave_charge = _rng.randf_range(0.3, 1.0)
	_react_left = _beat()


func _reboard() -> void:
	input.throw_held = false
	_stats["out_time"] += TICK
	_react_left = _skill["react"]
	var at := player.global_position
	input.yaw = 0.0
	input.move = Vector2(clampf(-at.x, -1.0, 1.0), 0.0)
	if main.train.rope.in_reach(at):
		input.press_grab()


func _rear_door(delta: float) -> void:
	var door := main.train.openings().back() as TrainOpening
	_aim(door.global_position, delta)
	input.move = Vector2.ZERO
	if _react_left <= 0.0 and _grab_left <= 0.0 and player.hands._aimed_interactable() == door:
		input.press_grab()
		_grab_left = GRAB_GAP


## --- Feet ------------------------------------------------------------------------

func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _aimed() -> Object:
	var collider: Variant = player.hands._aim_hit.get("collider")
	return collider if is_instance_valid(collider) else null


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
			_stats["stick_spots"].append(_round3(at))
	else:
		_stuck_time = 0.0
	var local := Basis(Vector3.UP, -player.yaw) * direction
	input.move = Vector2(local.x, -local.z)
	input.sprint = sprint
	_last_move = input.move


func _aim(point: Vector3, delta: float, yaw_off := 0.0) -> void:
	var to_point := (point - player.eye_position()).normalized()
	var wanted_yaw := atan2(-to_point.x, -to_point.z) + _noise_yaw + yaw_off
	var wanted_pitch := clampf(asin(to_point.y) + _noise_pitch, -1.4, 1.4)
	var step: float = _skill["turn"] * delta
	input.yaw += clampf(wrapf(wanted_yaw - input.yaw, -PI, PI), -step, step)
	input.pitch = move_toward(input.pitch, wanted_pitch, step)


func _aim_error(point: Vector3) -> float:
	return player.aim_forward().angle_to(point - player.eye_position())

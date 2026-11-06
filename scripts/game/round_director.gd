class_name RoundDirector
extends Node
## The round: title card, raid countdown, score, fines, results, next raid.
##
## Host-only rules. The clock, the score and the spawning only run on the server; a
## client HUD reads the public state below, which Milestone 4 replicates. Everything
## else in the game hears about the round through GameEvents.

enum Phase { IDLE, TITLE, RAID, ENDING, RESULTS }

const TITLE_SECONDS := 2.6
## Pause between the end of the raid and the results, so last bodies can still land.
const ENDING_SECONDS := 2.2

## Pace, from the bot's human policy (a floor, a real player is slower): about 6 s a
## stowaway, so 30% of the clock on raid 1, 75% on raid 4, and raid 6 on is beyond it.
const START_SECONDS := 60
const SECONDS_LOST_PER_ROUND := 4
const MIN_SECONDS := 40
const START_STOWAWAYS := 3
const MAX_STOWAWAYS := 9
const START_PASSENGERS := 4
const WARNING_SECONDS := 10

const YEET_POINTS := 100
const COMBO_WINDOW := 9.0     ## Seconds to land the next yeet and keep the chain.
const MAX_COMBO := 5
const PASSENGER_PENALTY := 150  ## Only for a body the player had a hand in; see Ragdoll.
## Par per stowaway, in base yeets. A clean win pays about 5.5 of them, so the top rank
## takes a fast chain with airtime and scenery on top.
const PAR_YEETS := 7
const FINE_PER_STOWAWAY := 300
const TIME_BONUS_PER_SECOND := 10
const DISTANCE_POINTS_PER_M := 3
const DISTANCE_POINTS_CAP := 200
const MIN_FLIGHT_M := 3.0
const SCENERY_POINTS := 75
const SCENERY_POINTS_PER_MPS := 2
const SCENERY_POINTS_CAP := 250
const SCENERY_HITS_PER_BODY := 3
const SCENERY_HIT_COOLDOWN := 0.5
## Height above the snow that ends a flight.
const LANDED_HEIGHT := 0.7
const MIN_FLIGHT_SECONDS := 0.25

## Standing room: car id, position relative to the car. The first spot is right in front
## of the player's spawn and always holds a stowaway. Nobody moves until the clock starts,
## so that stowaway is in plain view when the card clears, and it bolts on the first second.
const SPOTS: Array[Array] = [
	[&"Bistro", Vector3(0.2, 0.05, -3.4)],
	[&"Bistro", Vector3(-0.4, 0.05, 2.4)],
	[&"Bistro", Vector3(0.5, 0.05, 6.9)],
	[&"Bistro", Vector3(-0.2, 0.05, 0.2)],
	[&"Bistro", Vector3(0.2, 0.05, 5.5)],
	[&"Bistro", Vector3(-0.2, 0.05, -5.2)],
	[&"Coach", Vector3(0.1, 0.05, -6.0)],
	[&"Coach", Vector3(0.5, 0.05, -2.5)],
	[&"Coach", Vector3(-0.4, 0.05, 6.0)],
	[&"Coach", Vector3(-1.0, 0.05, -2.0)],
	[&"Coach", Vector3(0.0, 0.05, 1.5)],
	[&"Coach", Vector3(0.2, 0.05, 4.0)],
	[&"Locomotive", Vector3(-0.6, 0.05, 0.6)],
	[&"Locomotive", Vector3(-1.0, 0.05, -2.2)],
	[&"Locomotive", Vector3(-0.9, 0.05, 5.5)],
	[&"Locomotive", Vector3(1.0, 0.05, 0.5)],
]

## Worst to best. Every one of them is an insult, some are just better paid.
const RANKS: Array[String] = [
	"Absolute Caboose",
	"Lukewarm Ticket Goblin",
	"Part-Time Doorstop",
	"Soup Spiller, Second Class",
	"Adequate Flinger of Strangers",
	"Certified Window Menace",
	"Baron of Blunt Hospitality",
	"Grand Conductor of Unplanned Exits",
]
const SCENERY_LINES: Array[String] = ["MET THE SCENERY", "FULL BODY CONTACT", "THE LANDSCAPE WON", "NATURE SAYS NO"]

var phase := Phase.IDLE
var round_number := 1
var seconds_total := START_SECONDS
var stowaways_total := 0
var stowaways_left := 0
var time_left := 0.0
var score := 0
var total_score := 0   ## Sum of every cleared raid in this run.
var best_score := 0
var combo := 0
var combo_left := 0.0
var last_passed := false
var raid_hit := false  ## True once the clock has run out this round.
var rank_title := ""
var stowaways_yeeted := 0
var passengers_yeeted := 0
var fines_paid := 0
var time_bonus := 0

var _main: Main
var _phase_left := 0.0
var _last_warning := 0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _strike: RaidStrike
var _flights: Dictionary = {}       # Ragdoll -> {"start", "last", "age"}
var _scenery_hits: Dictionary = {}  # Ragdoll -> {"count", "at"}


func setup(main: Main) -> void:
	_main = main


func _ready() -> void:
	_strike = RaidStrike.new()
	_strike.name = "RaidStrike"
	add_child(_strike)
	GameEvents.object_yeeted.connect(_on_object_yeeted)
	GameEvents.npc_knocked_out.connect(_on_npc_knocked_out)
	GameEvents.body_hit_scenery.connect(_on_body_hit_scenery)


static func seconds_for(number: int) -> int:
	return maxi(START_SECONDS - SECONDS_LOST_PER_ROUND * (number - 1), MIN_SECONDS)


static func stowaways_for(number: int) -> int:
	return mini(START_STOWAWAYS + number - 1, MAX_STOWAWAYS)


static func passengers_for(number: int) -> int:
	return mini(START_PASSENGERS + number - 1, SPOTS.size() - stowaways_for(number))


## A failed raid never ranks above the middle of the table.
static func rank_for(points: int, stowaways: int, passed: bool) -> String:
	if points < 0:
		return RANKS[0]
	var par := stowaways * YEET_POINTS * PAR_YEETS
	var index := 1 + floori(float(points) / float(par) * (RANKS.size() - 2))
	return RANKS[clampi(index, 1, RANKS.size() - 1 if passed else 3)]


## Starts a fresh run at raid 1.
func begin() -> void:
	round_number = 1
	total_score = 0
	_start_round()


## The one big button: next raid after a win, the same raid after a loss.
func next_round() -> void:
	if phase != Phase.RESULTS:
		return
	if last_passed:
		round_number += 1
	else:
		total_score = 0
	_start_round()


## Clipboard test bench: same raid from the top.
func restart_round() -> void:
	_start_round()


## Stowaways still aboard, standing or out cold. Scanned rather than counted, so it
## stays right whatever happens to a body between knockout and yeet.
func stowaway_bodies() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if _main == null:
		return found
	for body in _main.npc_bodies():
		if body.is_queued_for_deletion():
			continue
		if body is Ragdoll:
			if body.is_stowaway and not body.off_train:
				found.append(body)
		elif body is TestDummy and body.is_stowaway:
			found.append(body)
	return found


func _start_round() -> void:
	if not multiplayer.is_server():
		return
	_flights.clear()
	_scenery_hits.clear()
	seconds_total = seconds_for(round_number)
	stowaways_total = stowaways_for(round_number)
	time_left = float(seconds_total)
	score = 0
	combo = 0
	combo_left = 0.0
	raid_hit = false
	last_passed = false
	rank_title = ""
	stowaways_yeeted = 0
	passengers_yeeted = 0
	fines_paid = 0
	time_bonus = 0
	_last_warning = WARNING_SECONDS + 1
	_strike.clear()
	_main.restock_props()
	_main.train.close_all_openings()
	_spawn_people()
	stowaways_left = stowaways_total
	phase = Phase.TITLE
	_phase_left = TITLE_SECONDS
	GameEvents.round_started.emit(round_number, stowaways_total, seconds_total)


func _spawn_people() -> void:
	_rng.seed = hash([TrainState.route_seed, round_number])
	var order: Array[int] = []
	for i in range(1, SPOTS.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var other := _rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[other]
		order[other] = swap
	order.push_front(0)
	var people := stowaways_total + passengers_for(round_number)
	for i in people:
		var spot: Array = SPOTS[order[i]]
		var car := _main.train.car_by_id(spot[0])
		var local: Vector3 = spot[1]
		var facing := Basis(Vector3.UP, _rng.randf_range(-PI, PI))
		var dummy := _main.spawn_dummy(Transform3D(facing, car.position + local), _rng.randi_range(0, 255), i < stowaways_total)
		# Held still behind the title card, or the nearest stowaway spends the card running.
		dummy.set_physics_process(false)


func _release_people() -> void:
	for body in _main.npc_bodies():
		if body is TestDummy:
			body.set_physics_process(true)


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE or phase == Phase.RESULTS or not multiplayer.is_server():
		return
	_clock += delta
	_tick_flights(delta)
	match phase:
		Phase.TITLE:
			stowaways_left = stowaway_bodies().size()
			_phase_left -= delta
			if _phase_left <= 0.0:
				phase = Phase.RAID
				_release_people()
		Phase.RAID:
			_tick_raid(delta)
		Phase.ENDING:
			_phase_left -= delta
			if _phase_left <= 0.0:
				_finish()


func _tick_raid(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	stowaways_left = stowaway_bodies().size()
	if combo_left > 0.0:
		combo_left -= delta
		if combo_left <= 0.0:
			combo = 0
			combo_left = 0.0
	if stowaways_left == 0:
		_end_raid(true)
		return
	if time_left <= 0.0:
		_end_raid(false)
		return
	var whole := ceili(time_left)
	if whole <= WARNING_SECONDS and whole < _last_warning:
		_last_warning = whole
		GameEvents.raid_warning.emit(whole)


func _end_raid(cleared: bool) -> void:
	phase = Phase.ENDING
	_phase_left = ENDING_SECONDS
	last_passed = cleared
	raid_hit = not cleared
	if cleared:
		time_bonus = ceili(time_left) * TIME_BONUS_PER_SECOND
		if time_bonus > 0:
			_award(time_bonus, "EARLY ARRIVAL")
	else:
		fines_paid = stowaways_left * FINE_PER_STOWAWAY
		_strike.hit(_main, stowaway_bodies(), FINE_PER_STOWAWAY)
		_award(-fines_paid, "FINE: %d STOWAWAY%s ABOARD" % [stowaways_left, "" if stowaways_left == 1 else "S"])


func _finish() -> void:
	_settle_flights()
	phase = Phase.RESULTS
	total_score += score
	best_score = maxi(best_score, total_score)
	rank_title = rank_for(score, stowaways_total, last_passed)
	GameEvents.round_ended.emit(score, last_passed)


func _award(points: int, reason: String) -> void:
	score += points
	GameEvents.score_awarded.emit(points, reason)


func _scoring_open() -> bool:
	return phase == Phase.TITLE or phase == Phase.RAID


func _on_npc_knocked_out(npc: Node3D, ragdoll: Node3D, _attacker: Node3D) -> void:
	if npc is TestDummy and npc.is_stowaway and ragdoll is Ragdoll:
		ragdoll.is_stowaway = true


func _on_object_yeeted(body: Node3D) -> void:
	if not (body is Ragdoll) or not _scoring_open() or not multiplayer.is_server():
		return
	var ragdoll := body as Ragdoll
	if ragdoll.is_stowaway:
		stowaways_yeeted += 1
		combo = mini(combo + 1, MAX_COMBO) if combo_left > 0.0 else 1
		combo_left = COMBO_WINDOW
		var chain := "  x%d" % combo if combo > 1 else ""
		_award(YEET_POINTS * combo, "STOWAWAY YEETED" + chain)
		var at := ragdoll.anchor()
		_flights[ragdoll] = {"start": at, "last": at, "age": 0.0}
	else:
		if not ragdoll.player_touched:
			return  # Walked out of an open door by itself: not the player's doing.
		passengers_yeeted += 1
		combo = 0
		combo_left = 0.0
		_award(-PASSENGER_PENALTY, "THAT ONE PAID")


## Flight distance: how far the body got, in the train's frame, before first touching snow.
func _tick_flights(delta: float) -> void:
	for ragdoll: Variant in _flights.keys():
		var flight: Dictionary = _flights[ragdoll]
		if not is_instance_valid(ragdoll):
			_pay_flight(flight)
			_flights.erase(ragdoll)
			continue
		flight["last"] = ragdoll.anchor()
		flight["age"] += delta
		if flight["age"] > MIN_FLIGHT_SECONDS and flight["last"].y < Treadmill.GROUND_Y + LANDED_HEIGHT:
			_pay_flight(flight)
			_flights.erase(ragdoll)


func _settle_flights() -> void:
	for flight: Dictionary in _flights.values():
		_pay_flight(flight)
	_flights.clear()


func _pay_flight(flight: Dictionary) -> void:
	var from: Vector3 = flight["start"]
	var to: Vector3 = flight["last"]
	var metres := Vector2(to.x - from.x, to.z - from.z).length()
	if metres >= MIN_FLIGHT_M:
		_award(mini(roundi(metres) * DISTANCE_POINTS_PER_M, DISTANCE_POINTS_CAP), "%d M OF AIRTIME" % roundi(metres))


func _on_body_hit_scenery(body: Node3D, speed: float) -> void:
	if not multiplayer.is_server() or (not _scoring_open() and phase != Phase.ENDING):
		return
	var target: Node3D = body.ragdoll if body is RagdollPart else body
	if not (target is Ragdoll) or not target.is_stowaway:
		return
	var record: Dictionary = _scenery_hits.get(target, {"count": 0, "at": -INF})
	if record["count"] >= SCENERY_HITS_PER_BODY or _clock - record["at"] < SCENERY_HIT_COOLDOWN:
		return
	record["count"] += 1
	record["at"] = _clock
	_scenery_hits[target] = record
	var points := mini(SCENERY_POINTS + roundi(speed) * SCENERY_POINTS_PER_MPS, SCENERY_POINTS_CAP)
	_award(points, SCENERY_LINES[_rng.randi_range(0, SCENERY_LINES.size() - 1)])

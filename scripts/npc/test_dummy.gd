class_name TestDummy
extends CharacterBody3D
## A passenger. Keeps the Milestone 1 contract (receive_bonk() and the npc_* events on
## GameEvents) and adds a brain: wander the aisle, idle, turn to face the player, stumble,
## panic, and, for stowaways, run and hide. The train is one corridor along Z, so steering
## needs no navmesh. Decisions run a few times per second, host only. Limbs are posed in
## _process on every peer.

enum Mode { IDLE, WANDER, PANIC, FLEE, HIDE }

const GetUpWatch := preload("res://scripts/npc/get_up.gd")
const StowawayMarker := preload("res://scripts/npc/stowaway_marker.gd")

const MAX_HP := 3
## Tests turn this off so a dummy stands where it was put.
static var brain_enabled := true
const KNOCKBACK_FRICTION := 18.0
const GRAVITY := 16.0
const WOBBLE_DECAY := 9.0

const THINK_INTERVAL := 0.2
const TURN_RATE := 9.0
const WANDER_SPEED := 1.4
const SNEAK_SPEED := 1.9
const PANIC_SPEED := 4.6
const FLEE_SPEED := 5.7      ## Faster than a walking player, slower than a sprinting one.
const FACE_RADIUS := 3.5
const FLEE_RADIUS := 7.0     ## A stowaway bolts when a player gets this close.
const BOLT_RADIUS := 2.6     ## A hiding stowaway breaks cover at this range.
const CALM_RADIUS := 13.0
const PANIC_RADIUS := 8.0
const SIGHT_RADIUS := 22.0
const PANIC_TIME_MIN := 3.0
const PANIC_TIME_MAX := 5.0
const WINDED_TIME := 3.0     ## A cornered stowaway cowers this long, wide open to a hit.
const BOLT_ROOM := 6.0       ## With less room than this behind it, a hider runs past the player.
const BOLT_TIME := 2.5       ## A bolt that has not got past the player by now has failed.
const BOLT_CLEAR := 1.2      ## Metres beyond the player before a bolt counts as done.
const TRAIN_END_MARGIN := 2.0 ## This close to a train end, found by the player, it cowers first.
const COMMIT_TIME := 1.0     ## A stowaway keeps a flee or hide decision at least this long.

const SHOVE_RADIUS := 1.05
const SHOVE_NUDGE_SPEED := 0.4
const SHOVE_STUMBLE_SPEED := 2.5
const SHOVE_TIP_SPEED := 5.4 ## Above any walk, and above a sprint with a body in hand.
const BLAME_TIME := 3.0      ## Seconds a player's hit or shove stays their fault.
const SHOVE_COOLDOWN := 0.5
const SHOVE_PUSH_SPEED := 2.4 ## Leaned on between stumbles, a passenger gives way this fast.
const SHOVE_SIDESTEP := 1.3  ## m/s to the side, so nobody blocks the aisle head on.
const BUMP_SPEED := 3.0
const BUMP_TIP_CHANCE := 0.45
const BODY_HIT_RADIUS := 0.9
const BODY_HIT_SPEED := 4.4  ## A flying ragdoll bowls people over; see Ragdoll.hits_hard.
const RISE_TIME := 0.7
const RISE_IMMUNITY := 2.0
const MAX_BODIES_DOWN := 4   ## Ragdolls allowed at once. Past that, a passenger only stumbles.
const CONTACT_RAY_HEIGHT := 0.6 ## Waist high: shoves and flying bodies stop at a counter.

## Walkable length of the train: boiler face to the Coach's rear wall.
const AISLE_MIN_Z := -23.0
const AISLE_MAX_Z := 27.6
const AISLE_LANE := 0.42
const ARRIVE_DISTANCE := 0.35
const TUCK_DISTANCE := 0.15  ## A hiding spot is a gap: stopping short leaves it in the aisle.
const STUCK_TIME := 0.5
const SEAT_EDGE_X := 0.62    ## Further out than this a walker is between seats.
const GANGWAY_Z := 9.6
const GANGWAY_PINCH := 1.5
const COAL_BUNKER_MIN_Z := -17.2 ## The Locomotive's bunker wall forces the aisle left.
const COAL_BUNKER_MAX_Z := -11.1
const COAL_AISLE_X := -0.8
const OFF_TRAIN_X := 2.1
const OFF_TRAIN_Y := -1.0
## Gaps between Coach seats, the bunker side of the Locomotive, behind the Bistro counter.
const HIDE_SPOTS: Array[Vector3] = [
	Vector3(-1.2, 0.0, 25.25), Vector3(1.2, 0.0, 25.25),
	Vector3(-1.2, 0.0, 23.25), Vector3(1.2, 0.0, 23.25),
	Vector3(-1.2, 0.0, 13.25), Vector3(1.2, 0.0, 13.25),
	Vector3(1.2, 0.0, 1.2),
	Vector3(-1.3, 0.0, -13.2), Vector3(-1.3, 0.0, -18.2), Vector3(-1.2, 0.0, -22.4),
]

const FAR_DISTANCE_SQUARED := 400.0 ## Beyond 20 m limbs update at a third of the rate.
const FAR_ANIM_STEP := 0.05
const HIDDEN_ANIM_STEP := 0.25 ## Off screen or behind a bulkhead: barely worth posing.
const VIEW_RADIUS := 1.4     ## Bounding sphere for the on-screen check.
const HEAD_HEIGHT := 1.5
const MARKER_HEIGHT := 2.3
const BODY_MARKER_HEIGHT := 0.9
const SPEECH_TIME := 1.1
const PANIC_LINES: Array[String] = ["AAAH!", "EEEK!", "HELP!", "NOT THE SOUP!", "MADMAN!", "CONDUCTOR!"]
const FLEE_LINES: Array[String] = ["NOPE!", "YOU SAW NOTHING!", "TICKET? WHAT TICKET?", "NEVER!"]
const BUMP_LINES: Array[String] = ["OOF!", "HEY!", "RUDE!", "WATCH IT!"]
const RISE_LINES: Array[String] = ["MY BACK...", "OW.", "I'LL WRITE A LETTER!"]
const BOLT_LINES: Array[String] = ["TOO SLOW!", "EXCUSE ME!", "COMING THROUGH!", "CAN'T STOP!"]
const COWER_LINES: Array[String] = ["NOT THE FACE!", "I HAVE A TICKET! SOMEWHERE!", "MERCY!", "OK OK OK OK"]

## Every passenger aboard, for alarms that are not GameEvents.
static var _roster: Array[TestDummy] = []
## Ragdolls that can bowl passengers over. Untyped: read while bodies are being freed.
static var _loose_bodies: Array = []

var hp := MAX_HP
var passenger := "gran"
var is_stowaway := false:
	set(value):
		is_stowaway = value
		_refresh_marker()
var mode := Mode.IDLE

var _main: Main
var _host := true
var _rng := RandomNumberGenerator.new()
var _think_left := 0.0
var _mode_left := 0.0
var _goal := Vector3.ZERO
var _lane := 0.0
var _at_goal := false
var _walk_speed := WANDER_SPEED
var _face_direction := Vector3.ZERO
var _stuck_time := 0.0
var _stuck_count := 0
var _stumble_left := 0.0
var _stumble_clock := 0.0
var _shove_cooldown := 0.0
var _immune_left := 0.0
var _blame_left := 0.0
var _winded_left := 0.0
var _commit_left := 0.0
var _flee_line_left := 0.0
var _cowered := false
var _bolting := false
var _bolt_left := 0.0
var _bolt_direction := 0.0
var _bolt_from: Player = null

var _knockback := Vector3.ZERO
var _visual: Node3D
var _wobble := 0.0
var _wobble_axis := Vector3.RIGHT
var _flash := 0.0
var _flash_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _marker: MeshInstance3D = null
var _speech: Label3D = null
var _speech_left := 0.0

var _style: Dictionary
var _anim_step := 0.0
var _anim_elapsed := 0.0
var _time_offset := 0.0
var _phase := 0.0
var _gait := 0.0
var _fear := 0.0
var _crouch := 0.0
var _windmill := 0.0
var _rise := 0.0
var _pelvis: Node3D
var _chest: Node3D
var _head: Node3D
var _upper_arm_l: Node3D
var _upper_arm_r: Node3D
var _forearm_l: Node3D
var _forearm_r: Node3D
var _thigh_l: Node3D
var _thigh_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D


static func create(passenger_index: int) -> TestDummy:
	var dummy := TestDummy.new()
	dummy.passenger = BodyPlan.PASSENGERS[passenger_index % BodyPlan.PASSENGERS.size()]
	return dummy


## X of the aisle at [param z] for a walker keeping to [param lane]: narrow through
## gangways, pushed left past the Locomotive's coal bunker.
static func aisle_x(z: float, lane: float) -> float:
	if absf(absf(z) - GANGWAY_Z) < GANGWAY_PINCH:
		return clampf(lane, -0.1, 0.1)
	if z > COAL_BUNKER_MIN_Z and z < COAL_BUNKER_MAX_Z:
		return COAL_AISLE_X + lane * 0.5
	return clampf(lane, -AISLE_LANE, AISLE_LANE)


## Makes everyone near [param source] panic, for scares that are not a GameEvents hit.
static func alarm(source: Vector3) -> void:
	for dummy in _roster:
		dummy._hear_alarm(source)


static func _forget_body(body: Ragdoll) -> void:
	_loose_bodies.erase(body)


static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _enter_tree() -> void:
	_roster.append(self)


func _exit_tree() -> void:
	_end_bolt()
	_roster.erase(self)


func _ready() -> void:
	collision_layer = Layers.NPC
	collision_mask = Layers.HULL | Layers.PROP | Layers.PLAYER | Layers.NPC
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = BodyPlan.HEIGHT
	shape.shape = capsule
	shape.position.y = BodyPlan.HEIGHT * 0.5
	add_child(shape)
	_build_visual()
	_rng.seed = TrainState.next_seed()
	_style = BodyPlan.GAIT[passenger]
	_time_offset = _rng.randf_range(0.0, 100.0)
	_think_left = _rng.randf_range(0.0, THINK_INTERVAL)
	_mode_left = _rng.randf_range(0.5, 3.0)
	_host = multiplayer.is_server()
	_main = get_parent().get_parent() as Main
	GameEvents.npc_bonked.connect(_on_npc_bonked)
	GameEvents.npc_knocked_out.connect(_on_npc_knocked_out)
	_refresh_marker()


## One pivot per joint, so a pose is a handful of rotations. At rest the meshes land exactly
## on their BodyPlan positions, matching the ragdoll.
func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var bones: Dictionary = {}
	var origins: Dictionary = {}
	var pelvis_at: Vector3 = BodyPlan.PARTS[&"pelvis"]["pos"]
	bones[&"pelvis"] = _add_bone(&"pelvis", _visual, pelvis_at, pelvis_at)
	origins[&"pelvis"] = pelvis_at
	for joint: Dictionary in BodyPlan.JOINTS:
		var child: StringName = joint["b"]
		var parent: StringName = joint["a"]
		var at: Vector3 = joint["at"]
		var origin: Vector3 = origins[parent]
		bones[child] = _add_bone(child, bones[parent], at - origin, at)
		origins[child] = at
	_pelvis = bones[&"pelvis"]
	_chest = bones[&"chest"]
	_head = bones[&"head"]
	_upper_arm_l = bones[&"upper_arm_l"]
	_upper_arm_r = bones[&"upper_arm_r"]
	_forearm_l = bones[&"forearm_l"]
	_forearm_r = bones[&"forearm_r"]
	_thigh_l = bones[&"thigh_l"]
	_thigh_r = bones[&"thigh_r"]
	_shin_l = bones[&"shin_l"]
	_shin_r = bones[&"shin_r"]
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 0.25, 0.15, 0.0)


func _add_bone(part_name: StringName, parent: Node3D, local: Vector3, at: Vector3) -> Node3D:
	var bone := Node3D.new()
	bone.name = String(part_name)
	bone.position = local
	parent.add_child(bone)
	var def: Dictionary = BodyPlan.PARTS[part_name]
	var part_at: Vector3 = def["pos"]
	var mesh := MeshInstance3D.new()
	mesh.mesh = BodyPlan.part_mesh(passenger, part_name)
	mesh.position = part_at - at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bone.add_child(mesh)
	_meshes.append(mesh)
	return bone


func _refresh_marker() -> void:
	if not is_node_ready():
		return
	if is_stowaway and _marker == null:
		_marker = _attach_marker(self, MARKER_HEIGHT)
	elif not is_stowaway and _marker != null:
		_marker.queue_free()
		_marker = null


func _attach_marker(target: Node3D, height: float) -> MeshInstance3D:
	var marker := StowawayMarker.new()
	marker.name = "StowawayMarker"
	marker.target = target
	marker.height = height
	target.add_child(marker)
	return marker


func receive_bonk(power: int, direction: Vector3, attacker: Node3D) -> void:
	if hp <= 0 or is_queued_for_deletion():
		return
	hp -= power
	_note_blame(attacker)
	GameEvents.npc_bonked.emit(self, attacker, power)
	if hp <= 0:
		_knock_out(direction, attacker)
		return
	_knockback = Vector3(direction.x, 0.0, direction.z) * 3.0
	_wobble = 0.35
	_wobble_axis = Vector3.UP.cross(direction).normalized()
	_flash = 1.0
	for mesh in _meshes:
		mesh.material_overlay = _flash_material


func _knock_out(direction: Vector3, attacker: Node3D) -> void:
	var ragdoll := _become_ragdoll(direction * 5.0 + Vector3.UP * 1.5)
	GameEvents.npc_knocked_out.emit(self, ragdoll, attacker)
	queue_free()


func _become_ragdoll(launch: Vector3) -> Ragdoll:
	var ragdoll := Ragdoll.spawn(get_parent(), global_transform, passenger, launch)
	ragdoll.is_stowaway = is_stowaway
	ragdoll.player_touched = _blame_left > 0.0
	if is_stowaway:
		_attach_marker(ragdoll.chest, BODY_MARKER_HEIGHT)
	_loose_bodies.append(ragdoll)
	ragdoll.tree_exiting.connect(_forget_body.bind(ragdoll))
	return ragdoll


## Shoved over, not bonked: a real ragdoll that the player can grab. Tough passengers and
## all stowaways stand back up if left alone. The others faint and stay down.
func tip_over(direction: Vector3, force: float, attacker: Node3D) -> void:
	if hp <= 0 or is_queued_for_deletion():
		return
	_note_blame(attacker)
	if _loose_bodies.size() >= MAX_BODIES_DOWN and not is_stowaway:
		# Too many bodies down. The hit still has to land: reel back and run.
		_knockback = _flat(direction) * force
		_wobble = 0.3
		_wobble_axis = Vector3.UP.cross(_flat(direction))
		_stumble(0.7)
		_say(BUMP_LINES[_rng.randi() % BUMP_LINES.size()])
		_hear_alarm(global_position - _flat(direction))
		return
	var ragdoll := _become_ragdoll(_flat(direction) * force + Vector3.UP * 1.8)
	if is_stowaway or passenger in BodyPlan.TOUGH:
		var watch := GetUpWatch.new()
		watch.name = "GetUp"
		watch.ragdoll = ragdoll
		watch.passenger = passenger
		watch.hp = hp
		watch.is_stowaway = is_stowaway
		ragdoll.add_child(watch)
		alarm(global_position)
	else:
		GameEvents.npc_knocked_out.emit(self, ragdoll, attacker)
	queue_free()


## Called on a dummy that replaces a shoved ragdoll: it swings up from the floor, dazed.
func rise() -> void:
	_rise = 1.0
	_immune_left = RISE_IMMUNITY
	_stumble(RISE_TIME + 0.5)
	_say(RISE_LINES[_rng.randi() % RISE_LINES.size()])
	_go_idle()


## Sends a wandering passenger to [param z]. The round and tests can steer a crowd with it.
func walk_to(z: float) -> void:
	_end_bolt()
	mode = Mode.WANDER
	_at_goal = false
	_mode_left = 40.0
	_walk_speed = WANDER_SPEED
	_goal.z = clampf(z, AISLE_MIN_Z, AISLE_MAX_Z)
	_keep_right()
	_goal.x = aisle_x(_goal.z, _lane)


func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	if brain_enabled and _host:
		_tick_timers(delta)
		_think_left -= delta
		if _think_left <= 0.0:
			_think_left += THINK_INTERVAL
			_think()
		_tick_contacts()
		if is_queued_for_deletion():
			return
		wish = _steer(delta)
		var at_rest := wish == Vector3.ZERO and _knockback == Vector3.ZERO
		if at_rest and is_on_floor():
			velocity = Vector3.ZERO
			return
	velocity.x = _knockback.x + wish.x
	velocity.z = _knockback.z + wish.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	move_and_slide()
	if brain_enabled and _host:
		_after_slide(wish, delta)


func _tick_timers(delta: float) -> void:
	_stumble_left = maxf(_stumble_left - delta, 0.0)
	_stumble_clock += delta
	_shove_cooldown = maxf(_shove_cooldown - delta, 0.0)
	_immune_left = maxf(_immune_left - delta, 0.0)
	_blame_left = maxf(_blame_left - delta, 0.0)
	_winded_left = maxf(_winded_left - delta, 0.0)
	_commit_left = maxf(_commit_left - delta, 0.0)
	_flee_line_left = maxf(_flee_line_left - delta, 0.0)


## --- Decisions -------------------------------------------------------------------

func _think() -> void:
	_host = multiplayer.is_server()
	_anim_step = _pick_anim_step(get_viewport().get_camera_3d())
	var threat := _nearest_player()
	var distance := INF
	if threat != null:
		distance = _flat(threat.global_position - global_position).length()
	_mode_left -= THINK_INTERVAL
	match mode:
		Mode.IDLE, Mode.WANDER:
			if is_stowaway and distance < FLEE_RADIUS:
				_start_flee(threat.global_position.z, false)
			elif _mode_left <= 0.0:
				if mode == Mode.WANDER:
					_go_idle()
				else:
					_start_wander(threat)
			elif mode == Mode.WANDER and _rng.randf() < 0.006:
				_stumble(0.7)
			elif mode == Mode.IDLE:
				_face_direction = Vector3.ZERO
				if distance < FACE_RADIUS and not is_stowaway:
					_face_direction = _flat(threat.global_position - global_position).normalized()
		Mode.PANIC:
			if _mode_left <= 0.0:
				_go_idle()
		Mode.FLEE:
			if _bolting:
				_think_bolt(threat)
			elif threat == null or (distance > CALM_RADIUS and _mode_left <= 0.0):
				_go_idle()
			elif _commit_left <= 0.0 and distance < 3.5 and (_goal.z - global_position.z) * (threat.global_position.z - global_position.z) > 0.0:
				_start_flee(threat.global_position.z, false)
		Mode.HIDE:
			if _commit_left > 0.0 or _winded_left > 0.0:
				pass
			elif distance < BOLT_RADIUS:
				_break_cover(threat)
			elif distance > CALM_RADIUS and _mode_left <= 0.0:
				_go_idle()


## Limbs update every frame only for someone the camera can see.
func _pick_anim_step(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	var head := global_position + Vector3.UP * HEAD_HEIGHT
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(head) > VIEW_RADIUS:
			return HIDDEN_ANIM_STEP
	if not _clear_line(camera.global_position, head):
		return HIDDEN_ANIM_STEP
	if camera.global_position.distance_squared_to(global_position) > FAR_DISTANCE_SQUARED:
		return FAR_ANIM_STEP
	return 0.0


func _nearest_player() -> Player:
	if _main == null:
		return null
	var best: Player = null
	var best_distance := INF
	for player: Player in _main.players.values():
		var distance := player.global_position.distance_squared_to(global_position)
		if player.is_aboard() and distance < best_distance:
			best = player
			best_distance = distance
	return best


func _go_idle() -> void:
	_end_bolt()
	mode = Mode.IDLE
	_at_goal = false
	_commit_left = 0.0
	_mode_left = _rng.randf_range(1.5, 4.5)
	_stuck_count = 0


func _start_wander(threat: Player) -> void:
	var direction := -1.0 if _rng.randf() < 0.5 else 1.0
	if is_stowaway and threat != null:
		direction = signf(global_position.z - threat.global_position.z)
	var z := clampf(global_position.z + direction * _rng.randf_range(3.0, 14.0), AISLE_MIN_Z, AISLE_MAX_Z)
	if absf(z - global_position.z) < 1.0:
		z = global_position.z - direction * 5.0
	walk_to(z)
	_mode_left = 25.0
	_walk_speed = SNEAK_SPEED if is_stowaway else WANDER_SPEED * float(_style["speed"])


func _keep_right() -> void:
	var travel := signf(_goal.z - global_position.z)
	_lane = travel * _rng.randf_range(0.2, AISLE_LANE)


func _on_npc_bonked(npc: Node3D, _attacker: Node3D, _power: int) -> void:
	if npc == self and hp <= 0:
		return
	_hear_alarm(npc.global_position)


func _on_npc_knocked_out(npc: Node3D, _ragdoll: Node3D, _attacker: Node3D) -> void:
	if npc != self:
		_hear_alarm(npc.global_position)


func _hear_alarm(source: Vector3) -> void:
	if not brain_enabled or not _host or is_queued_for_deletion():
		return
	var distance := global_position.distance_to(source)
	if distance > PANIC_RADIUS and (distance > SIGHT_RADIUS or not _can_see(source)):
		return
	_panic(source)


func _can_see(point: Vector3) -> bool:
	return _clear_line(global_position + Vector3.UP * 1.6, point + Vector3.UP * 1.2)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.HULL)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _panic(source: Vector3) -> void:
	var fresh := mode != Mode.PANIC and mode != Mode.FLEE
	if fresh:
		_say(PANIC_LINES[_rng.randi() % PANIC_LINES.size()])
		GameEvents.npc_panicked.emit(self, global_position)
	if is_stowaway:
		if fresh and _commit_left <= 0.0:
			_start_flee(source.z, false)
		return
	mode = Mode.PANIC
	_at_goal = false
	_stuck_count = 0
	_mode_left = _rng.randf_range(PANIC_TIME_MIN, PANIC_TIME_MAX)
	var away := signf(global_position.z - source.z)
	if away == 0.0:
		away = 1.0 if _rng.randf() < 0.5 else -1.0
	var end := AISLE_MAX_Z if away > 0.0 else AISLE_MIN_Z
	_goal = Vector3(0.0, 0.0, end - away * _rng.randf_range(0.0, 2.0))
	_keep_right()


## Stowaway running from a threat at [param threat_z]. With [param bolt] it breaks cover and
## runs past the threat instead of away from it.
func _start_flee(threat_z: float, bolt: bool) -> void:
	if mode == Mode.HIDE and _winded_left > 0.0:
		return
	_end_bolt()
	var away := signf(global_position.z - threat_z)
	if away == 0.0:
		away = 1.0
	if bolt:
		away = -away
	else:
		_cowered = false
	mode = Mode.FLEE
	_at_goal = false
	_stuck_count = 0
	_commit_left = COMMIT_TIME
	_mode_left = 2.0
	_goal = _pick_hide_spot(away, threat_z)
	_keep_right()
	if bolt:
		_lane = -_lane
	if _flee_line_left <= 0.0:
		_flee_line_left = 3.0
		var lines := BOLT_LINES if bolt else FLEE_LINES
		_say(lines[_rng.randi() % lines.size()])


## A hider has been found. Run the open way if there is one. In a dead end, cower first at
## the very end of the train, then duck past the player.
func _break_cover(threat: Player) -> void:
	var threat_z := threat.global_position.z
	var away := signf(global_position.z - threat_z)
	var room := AISLE_MAX_Z - global_position.z if away >= 0.0 else global_position.z - AISLE_MIN_Z
	if room >= BOLT_ROOM:
		_start_flee(threat_z, false)
	elif room < TRAIN_END_MARGIN and not _cowered:
		_cower()
	else:
		_start_bolt(threat)


## Runs through the player's capsule: the aisle is too narrow to pass any other way, and a
## target that squeezes under the player's arm is the fun part. Only a sprint tackle stops it.
func _start_bolt(threat: Player) -> void:
	_start_flee(threat.global_position.z, true)
	_bolting = true
	_bolt_left = BOLT_TIME
	_bolt_direction = signf(threat.global_position.z - global_position.z)
	_bolt_from = threat
	add_collision_exception_with(threat)
	threat.add_collision_exception_with(self)
	if threat.global_position.x != 0.0:
		_lane = -signf(threat.global_position.x) * AISLE_LANE


func _think_bolt(threat: Player) -> void:
	_bolt_left -= THINK_INTERVAL
	if threat == null:
		_end_bolt()
	elif (global_position.z - threat.global_position.z) * _bolt_direction > BOLT_CLEAR:
		_end_bolt()
	elif _bolt_left <= 0.0:
		_cower()


func _end_bolt() -> void:
	_bolting = false
	if is_instance_valid(_bolt_from):
		remove_collision_exception_with(_bolt_from)
		_bolt_from.remove_collision_exception_with(self)
	_bolt_from = null


## Out of options. Crouches and shakes, and for WINDED_TIME nothing makes it run.
func _cower() -> void:
	_winded_left = WINDED_TIME
	_cowered = true
	_enter_hide()
	_say(COWER_LINES[_rng.randi() % COWER_LINES.size()])


## A hiding place beyond the threat, favouring far ones, or the end of the train.
func _pick_hide_spot(away: float, threat_z: float) -> Vector3:
	var best := Vector3(0.0, 0.0, AISLE_MAX_Z if away > 0.0 else AISLE_MIN_Z)
	var best_score := -INF
	for spot in HIDE_SPOTS:
		var ahead := (spot.z - threat_z) * away
		if ahead < 5.0:
			continue
		var score := ahead + _rng.randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best = spot
	return best


func _stumble(seconds: float) -> void:
	_stumble_left = maxf(_stumble_left, seconds)


## --- Contact: shoves, bumps, flying bodies ----------------------------------------

func _tick_contacts() -> void:
	if _immune_left > 0.0:
		return
	if _main != null:
		for player: Player in _main.players.values():
			var offset := _flat(global_position - player.global_position)
			var distance := offset.length()
			if distance < SHOVE_RADIUS and distance > 0.01:
				var away := offset / distance
				# The wish counts too: a player already leaning on this body has no velocity left.
				var speed := maxf(_flat(player.velocity).dot(away), player.wish_velocity.dot(away))
				if speed >= SHOVE_NUDGE_SPEED and _clear_line(_contact_point(player), _contact_point(self)):
					_feel_shove(away, speed, player)
				if is_queued_for_deletion():
					return
	for body: Ragdoll in _loose_bodies:
		var moving := body.pelvis.linear_velocity
		if not body.hits_hard(moving, BODY_HIT_SPEED):
			continue
		var offset := _flat(global_position - body.pelvis.global_position)
		if offset.length_squared() < BODY_HIT_RADIUS * BODY_HIT_RADIUS and _clear_line(body.pelvis.global_position, _contact_point(self)):
			tip_over(moving.normalized(), 3.5, body)
			return


func _contact_point(body: Node3D) -> Vector3:
	return _flat(body.global_position) + Vector3.UP * (global_position.y + CONTACT_RAY_HEIGHT)


## A sprint flattens a passenger. A stowaway only staggers, which sets up the bonk that puts
## it down, unless it is bolting past: then the tackle is the one thing that stops it.
func _feel_shove(away: Vector3, speed: float, player: Node3D) -> void:
	if speed < SHOVE_NUDGE_SPEED or (_bolting and speed < SHOVE_TIP_SPEED):
		return  # Only a sprint stops a bolt.
	_note_blame(player)
	if _shove_cooldown > 0.0:
		_give_way(away, speed)
	elif speed >= SHOVE_TIP_SPEED and (_bolting or not is_stowaway):
		tip_over(away, 5.0, player)
	elif speed >= SHOVE_STUMBLE_SPEED:
		_shove_cooldown = SHOVE_COOLDOWN
		_knockback = away * 3.5
		_wobble = 0.3
		_wobble_axis = Vector3.UP.cross(away)
		_stumble(0.6)
		_say(BUMP_LINES[_rng.randi() % BUMP_LINES.size()])
		if is_stowaway and not _bolting and _commit_left <= 0.0:
			_start_flee(player.global_position.z, false)
	else:
		_knockback = away * 1.6


func _note_blame(attacker: Node3D) -> void:
	if attacker is Player or (attacker is Ragdoll and (attacker as Ragdoll).player_touched):
		_blame_left = BLAME_TIME


## Still being leaned on: keep sliding, and drift off the player's line so they can pass.
func _give_way(away: Vector3, speed: float) -> void:
	var side := signf(global_position.x)
	if side == 0.0:
		side = 1.0 if _lane >= 0.0 else -1.0
	var push := away * minf(speed, SHOVE_PUSH_SPEED) + Vector3.RIGHT * side * SHOVE_SIDESTEP
	if _knockback.length_squared() < push.length_squared():
		_knockback = push


## Another passenger ran into this one. Stowaways are nimble: they barge, but tip nobody.
func _bumped(direction: Vector3, by: TestDummy) -> void:
	if _shove_cooldown > 0.0 or _immune_left > 0.0:
		return
	_shove_cooldown = SHOVE_COOLDOWN * 2.0
	if not by.is_stowaway and not is_stowaway and _rng.randf() < BUMP_TIP_CHANCE:
		tip_over(direction, 3.8, by)
		return
	_knockback = _flat(direction) * 3.0
	_stumble(0.6)
	_say(BUMP_LINES[_rng.randi() % BUMP_LINES.size()])
	_panic(by.global_position)


func _after_slide(wish: Vector3, delta: float) -> void:
	if absf(global_position.x) > OFF_TRAIN_X or global_position.y < OFF_TRAIN_Y:
		# Shoved through an open door: the Exterior Yeet Zone takes it from here.
		_knock_out(Vector3(signf(global_position.x), 0.0, 0.0), null)
		return
	var speed := wish.length()
	if speed < 0.1:
		_stuck_time = 0.0
		return
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is TestDummy:
			if speed >= BUMP_SPEED:
				(collider as TestDummy)._bumped(wish / speed, self)
				_stumble(0.3)
		elif collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse(wish * Player.PUSH_STRENGTH * delta)
	if get_real_velocity().length() < speed * 0.3:
		_stuck_time += delta
		if _stuck_time > STUCK_TIME:
			_stuck_time = 0.0
			_on_stuck()
	else:
		_stuck_time = 0.0
		_stuck_count = 0


func _on_stuck() -> void:
	_stuck_count += 1
	_lane = -_lane
	match mode:
		Mode.WANDER:
			if _stuck_count >= 2:
				_go_idle()
		Mode.PANIC:
			if absf(_goal.z - global_position.z) < 4.0:
				_at_goal = true
			elif _stuck_count >= 2:
				var back := AISLE_MIN_Z if _goal.z > global_position.z else AISLE_MAX_Z
				_goal = Vector3(0.0, 0.0, back)
				_stuck_count = 0
		Mode.FLEE:
			if _stuck_count >= 2 or _bolting:
				_cower()


func _enter_hide() -> void:
	_end_bolt()
	mode = Mode.HIDE
	_commit_left = COMMIT_TIME
	_mode_left = _rng.randf_range(5.0, 9.0)


## --- Steering --------------------------------------------------------------------

func _steer(delta: float) -> Vector3:
	var speed := 0.0
	match mode:
		Mode.WANDER:
			speed = _walk_speed
		Mode.PANIC:
			speed = 0.0 if _at_goal else PANIC_SPEED
		Mode.FLEE:
			speed = FLEE_SPEED
	if speed <= 0.0:
		if _face_direction != Vector3.ZERO and mode == Mode.IDLE:
			_turn_toward(_face_direction, delta)
		return Vector3.ZERO
	var to_point := _flat(_aisle_point() - global_position)
	var hiding_spot := mode == Mode.FLEE and _goal.x != 0.0 and not _bolting
	if _flat(_goal - global_position).length() < (TUCK_DISTANCE if hiding_spot else ARRIVE_DISTANCE):
		_arrived()
		return Vector3.ZERO
	var direction := to_point.normalized()
	_turn_toward(direction, delta)
	if _stumble_left > 0.0:
		# Lurch off line, slowly, as if the floor just moved.
		var side := Vector3(direction.z, 0.0, -direction.x)
		return direction * speed * 0.35 + side * sin(_stumble_clock * 12.0) * 1.2
	return direction * speed


## Next point to walk to: down the aisle while far, then straight to the goal. A walker
## sitting between seats steps into the aisle first.
func _aisle_point() -> Vector3:
	var at := global_position
	var along := _goal.z - at.z
	if absf(along) <= 0.6:
		return _goal
	var aisle := aisle_x(at.z, _lane)
	var off_lane := absf(at.x - aisle)
	var ahead := 0.3 if off_lane > 0.55 else 1.5
	if absf(at.x) > SEAT_EDGE_X and off_lane > 0.25:
		ahead = 0.1  # Straight out: on a diagonal it snags on the corner of the seat beside it.
	return Vector3(aisle, 0.0, at.z + signf(along) * ahead)


func _arrived() -> void:
	match mode:
		Mode.WANDER:
			_go_idle()
		Mode.PANIC:
			_at_goal = true
		Mode.FLEE:
			_enter_hide()


func _turn_toward(direction: Vector3, delta: float) -> void:
	var wanted := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, wanted, 1.0 - exp(-TURN_RATE * delta))


## --- Speech ----------------------------------------------------------------------

func _say(line: String) -> void:
	if _speech == null:
		_speech = Label3D.new()
		_speech.name = "Speech"
		_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_speech.position.y = MARKER_HEIGHT + 0.35 if is_stowaway else 2.1
		_speech.font_size = 56
		_speech.outline_size = 14
		_speech.pixel_size = 0.005
		_speech.modulate = Color(1.0, 0.95, 0.5)
		_speech.outline_modulate = Color(0.15, 0.05, 0.05)
		add_child(_speech)
	_speech.text = line
	_speech.visible = true
	_speech_left = SPEECH_TIME


## --- Animation -------------------------------------------------------------------

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		_flash_material.albedo_color.a = _flash * 0.6
		if _flash <= 0.0:
			for mesh in _meshes:
				mesh.material_overlay = null
	if _speech_left > 0.0:
		_speech_left -= delta
		if _speech_left <= 0.0:
			_speech.visible = false
	if brain_enabled:
		_anim_elapsed += delta
		if _anim_elapsed >= _anim_step:
			_animate(_anim_elapsed)
			_anim_elapsed = 0.0
	elif _wobble > 0.001:
		_decay_wobble(delta)
		_visual.rotation = _wobble_axis * _wobble * cos(Time.get_ticks_msec() * 0.03)


func _decay_wobble(delta: float) -> void:
	_wobble = lerpf(_wobble, 0.0, 1.0 - exp(-WOBBLE_DECAY * delta))


func _animate(delta: float) -> void:
	var time := Time.get_ticks_msec() * 0.001 + _time_offset
	var speed := Vector2(velocity.x, velocity.z).length()
	var cowering := mode == Mode.HIDE or (mode == Mode.PANIC and _at_goal)
	var hands_up := mode == Mode.PANIC and not is_stowaway
	_decay_wobble(delta)
	_gait = move_toward(_gait, minf(speed / 1.2, 1.0), delta * 7.0)
	_fear = move_toward(_fear, 1.0 if hands_up else 0.0, delta * 6.0)
	_crouch = move_toward(_crouch, 1.0 if cowering else 0.0, delta * 5.0)
	_windmill = move_toward(_windmill, 1.0 if _stumble_left > 0.0 else 0.0, delta * 8.0)
	_rise = move_toward(_rise, 0.0, delta / RISE_TIME)
	var cadence: float = _style["cadence"]
	_phase += delta * (4.5 + speed * 2.3) * cadence
	var step := sin(_phase)
	var lift := cos(_phase)

	var stride: float = _style["stride"]
	var swing := stride * (0.75 + minf(speed / 5.0, 1.0) * 0.6) * _gait
	_pose_leg(_thigh_l, _shin_l, step * swing, maxf(lift, 0.0) * (0.4 + swing) * _gait)
	_pose_leg(_thigh_r, _shin_r, -step * swing, maxf(-lift, 0.0) * (0.4 + swing) * _gait)

	# Arms: opposite the legs, stowaways held back and sly, flung up in panic, windmilling
	# in a stumble.
	var rest := -0.5 if is_stowaway else 0.0
	var flail := sin(time * 26.0) * 0.3
	var mill := sin(time * 15.0) * 2.2
	var cover := 0.75 if cowering else 0.0
	_pose_arm(_upper_arm_l, _forearm_l, -1.0, rest - step * 0.6 * _gait, flail, mill, cover)
	_pose_arm(_upper_arm_r, _forearm_r, 1.0, rest + step * 0.6 * _gait, -flail, -mill, cover)

	var sway: float = _style["sway"]
	var hunch := 0.35 if is_stowaway else 0.0
	_pelvis.rotation.y = -step * 0.18 * _gait
	_chest.rotation.x = -hunch - _fear * 0.25 + sin(time * 1.8) * 0.02 - _crouch * 0.4
	_chest.rotation.y = step * 0.25 * _gait
	_head.rotation.x = hunch * 0.8 + _fear * 0.3
	_head.rotation.y = -step * 0.1 * _gait
	if is_stowaway and mode != Mode.FLEE:
		_head.rotation.y = sin(time * 2.4) * 0.9  # Shifty eyes, with the whole head.

	var tilt := sin(time * 9.0) * 0.3 * _windmill + 1.5 * _rise * _rise
	var roll := lift * sway * _gait + cos(time * 7.0) * 0.3 * _windmill
	_visual.rotation = Vector3(tilt, 0.0, roll) + _wobble_axis * _wobble * cos(time * 30.0)
	var tremble := sin(time * 43.0) * 0.015 * _crouch
	_visual.position = Vector3(tremble, absf(step) * 0.05 * _gait - 0.42 * _crouch, 0.0)


func _pose_leg(thigh: Node3D, shin: Node3D, swing: float, knee: float) -> void:
	thigh.rotation.x = lerpf(swing, 1.35, _crouch)
	shin.rotation.x = lerpf(-knee, -2.1, _crouch)


func _pose_arm(upper: Node3D, fore: Node3D, side: float, walk: float, flail: float, mill: float, cover: float) -> void:
	var raised := lerpf(walk, 2.8 + flail, _fear)
	raised = lerpf(raised, mill, _windmill)
	upper.rotation.x = lerpf(raised, 2.5, cover)
	upper.rotation.z = side * (0.08 + _fear * 0.35 + _windmill * 0.5)
	fore.rotation.x = lerpf(0.25 + absf(walk) * 0.4, 0.7, _fear) + cover

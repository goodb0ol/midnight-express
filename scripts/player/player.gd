class_name Player
extends CharacterBody3D
## First-person body. Consumes one PlayerCommand per tick from its input source; on the
## host in co-op, remote players will run this same script from network commands.

signal shake_requested(amount: float)

enum State { ABOARD, DRAGGED, ROPE }

const EYE_HEIGHT := 1.62
const CAPSULE_HEIGHT := 1.78
const CAPSULE_RADIUS := 0.3
const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.2
const GROUND_ACCEL := 46.0
const AIR_ACCEL := 12.0
const JUMP_SPEED := 5.0
const GRAVITY := 16.0
const COYOTE_TIME := 0.1
const PUSH_STRENGTH := 14.0
const ABOARD_MASK := Layers.HULL | Layers.PROP | Layers.NPC
## Fraction of ground speed a dragged player travels at: enough to feel hopeless,
## slow enough to leave a few seconds along the rope.
const DRAG_FACTOR := 0.72
const DRAG_STEER_SPEED := 3.4
const REEL_SPEED := 22.0
const LEFT_BEHIND_MARGIN := 14.0

var peer_id := 1
var input_source: PlayerInputSource
var hands: Hands
var train: Train
var state := State.ABOARD
var yaw := 0.0
var pitch := 0.0
var spawn_point := Vector3.ZERO
var sprinting := false  ## Moving at a run this tick; rendering leans into it.
## Where the legs are trying to go. Unlike velocity, move_and_slide does not zero this on
## contact, so a body in the way can tell it is being leaned on.
var wish_velocity := Vector3.ZERO

var _coyote := 0.0
var _jump_was_held := false


## [param peer] is the multiplayer peer that owns this body; 1 is the host/solo player.
static func create(peer: int, on_train: Train) -> Player:
	var player := Player.new()
	player.peer_id = peer
	player.train = on_train
	player.name = "Player%d" % peer
	return player


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = ABOARD_MASK
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50.0)
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	shape.position.y = CAPSULE_HEIGHT * 0.5
	add_child(shape)

	hands = Hands.new()
	hands.name = "Hands"
	hands.player = self
	add_child(hands)


func is_aboard() -> bool:
	return state == State.ABOARD


func eye_position() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func aim_forward() -> Vector3:
	return -aim_basis().z


func _physics_process(delta: float) -> void:
	if input_source == null:
		return
	var command := input_source.sample()
	yaw = command.yaw
	pitch = command.pitch
	rotation.y = yaw
	match state:
		State.ABOARD:
			_tick_aboard(command, delta)
			hands.tick(command, delta)
		State.DRAGGED:
			_tick_dragged(command, delta)
		State.ROPE:
			_tick_rope(delta)


func _wish_direction(command: PlayerCommand) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(command.move.x, 0.0, -command.move.y)


func _tick_aboard(command: PlayerCommand, delta: float) -> void:
	var on_floor := is_on_floor()
	_coyote = COYOTE_TIME if on_floor else _coyote - delta
	var top_speed := SPRINT_SPEED if command.sprint else WALK_SPEED
	top_speed *= hands.move_speed_factor()
	sprinting = command.sprint and command.move.length() > 0.1
	var target := _wish_direction(command) * top_speed
	wish_velocity = target
	var accel := (GROUND_ACCEL if on_floor else AIR_ACCEL) * hands.move_accel_factor()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not on_floor:
		velocity.y -= GRAVITY * delta
	if command.jump and not _jump_was_held and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_coyote = 0.0
	_jump_was_held = command.jump
	move_and_slide()
	_push_rigid_bodies()


func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue
		var push := -collision.get_normal()
		push.y = 0.0
		var impulse := push * minf(velocity.length(), SPRINT_SPEED) * PUSH_STRENGTH * get_physics_process_delta_time()
		body.apply_impulse(impulse, collision.get_position() - body.global_position)


## Steps into a bonk. The ground acceleration eats it within a few ticks.
func lunge(push: Vector3) -> void:
	velocity += push


## --- Exterior Yeet Zone contract -------------------------------------------------

func yeet_anchor() -> Vector3:
	return global_position + Vector3.UP * 0.9


func is_off_train() -> bool:
	return state != State.ABOARD


func on_left_train() -> void:
	if state != State.ABOARD:
		return
	state = State.DRAGGED
	sprinting = false
	wish_velocity = Vector3.ZERO
	collision_mask = Layers.GROUND
	hands.force_release()
	hands.cancel_swing()
	shake_requested.emit(0.5)
	GameEvents.player_left_train.emit(self)


func _tick_dragged(command: PlayerCommand, delta: float) -> void:
	var speed := TrainState.speed_mps
	var free_walk := 1.0 - clampf(speed / 8.0, 0.0, 1.0)
	var wish := _wish_direction(command)
	velocity.x = wish.x * lerpf(DRAG_STEER_SPEED, WALK_SPEED, free_walk)
	velocity.z = speed * DRAG_FACTOR + wish.z * lerpf(1.0, WALK_SPEED, free_walk)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if command.grab_pressed and train.rope.in_reach(global_position):
		state = State.ROPE
		collision_mask = 0
		velocity = Vector3.ZERO
		return
	if global_position.z > train.rope.end_z() + LEFT_BEHIND_MARGIN:
		GameEvents.player_left_behind.emit(self)
		respawn()


func _tick_rope(delta: float) -> void:
	var goal := train.rope.boarding_point()
	global_position = global_position.move_toward(goal, REEL_SPEED * delta)
	if global_position.is_equal_approx(goal):
		_board()
		GameEvents.player_reboarded.emit(self)


func _board() -> void:
	state = State.ABOARD
	collision_mask = ABOARD_MASK
	velocity = Vector3.ZERO


## Puts the player back on the train at their spawn point.
func respawn() -> void:
	hands.force_release()
	hands.cancel_swing()
	_board()
	wish_velocity = Vector3.ZERO
	global_position = spawn_point
	reset_physics_interpolation()
	GameEvents.player_respawned.emit(self)

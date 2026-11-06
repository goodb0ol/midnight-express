class_name Hands
extends Node
## Grab / interact / drop, hold-to-throw, and bonk. Works only from PlayerCommand and
## the player's tick-exact aim, so it can run on the host for every player.

signal prompt_changed(action: StringName, text: String)
signal charge_changed(fraction: float)
signal swung(hit: bool)
signal threw(fraction: float)

const REACH := 2.7
const AIM_MASK := Layers.HULL | Layers.PROP | Layers.RAGDOLL | Layers.NPC | Layers.USE_VOLUME
const BONK_MASK := Layers.PROP | Layers.RAGDOLL | Layers.NPC

const HOLD_DISTANCE := 1.3
const HOLD_DROP := 0.22         ## Metres below the eye line.
const HOLD_GAIN := 14.0         ## 1/s; how hard the held body chases its target.
const HOLD_MAX_SPEED := 16.0
const HOLD_MAX_FORCE := 1500.0  ## Newtons. Lifts a 50 kg body off the floor by one limb.
const BREAK_DISTANCE := 3.6
## A body caught on something drags on the arm from here, and slows the player to
## LEASH_MIN_SPEED just before it would tear loose, so a snag reads as a tug and not a drop.
const LEASH_DISTANCE := 2.2
const LEASH_MIN_SPEED := 0.2
const PINCH_LANE := 0.2         ## Metres off centre a body is held inside a gangway.
## With a body in hand, a shut opening this close to the crosshair takes the grab press.
const OPEN_ASSIST_CONE := deg_to_rad(30.0)
const TOOL_GAIN := 16.0

const THROW_CHARGE_TIME := 0.75
const THROW_PROP_MIN := 5.0
const THROW_PROP_MAX := 24.0
const THROW_BODY_MIN := 8.0
const THROW_BODY_MAX := 20.0
const THROW_LIFT := 1.8         ## m/s of arc added to a thrown body.

## A swing is wind-up, strike at SWING_HIT_TIME, then follow-through to SWING_TIME.
const SWING_TIME := 0.42
const SWING_HIT_TIME := 0.15
const SWING_WINDUP_SHARE := 0.7 ## Part of the time before the hit spent pulling back.
const SWING_WINDUP_DEPTH := 0.7 ## How far back the wind-up reaches, against 1.0 forward.
const BONK_RANGE := 2.8
const BONK_RADIUS := 0.75
const FIST_POWER := 1
const BODY_CLUB_POWER := 3      ## Clubbing someone with a held body.
const BONK_KNOCKBACK := 1.6     ## Length of the direction given to receive_bonk.
const BONK_LIFT := 0.18         ## Upward share of that direction.
const BONK_LUNGE := 3.0         ## m/s the player steps into a hit that lands.

## Dragging a body: slow, staggering, and it swings about on the end of the arm.
const DRAG_GAIN := 9.0
const DRAG_DROP := 0.5          ## Metres below the eye line.
const DRAG_SPEED := 0.5         ## Fraction of walking speed.
const DRAG_STAGGER := 0.16      ## Share of that speed which comes and goes with each step.
const DRAG_ACCEL := 0.4         ## Fraction of normal acceleration: heavy to start and stop.
const DRAG_STEP_RATE := 6.5     ## rad/s of the sway at full walking speed.
const DRAG_SWAY := 0.3          ## Metres side to side.
const DRAG_BOB := 0.12          ## Metres up and down.
const BODY_CLUB_REACH := 1.1    ## Metres a body is shoved forward by a swing.

const FLICK_TURN_RATE := 4.5    ## rad/s of aim that count as swinging a held body by hand.
const FLICK_LINGER := 0.2       ## Seconds a flick keeps counting: the body lags the view.

const MAGNET_CONE := deg_to_rad(9.0)

var player: Player
var held: RigidBody3D = null
var charging := false
## Exit point a heave would be steered to, or null. Rendering reads it to mark the opening.
var assist_point: Variant = null
var _assist_approach: Variant = null  ## Point just inside that opening, or null.

var _charge_time := 0.0
var _swing_time := -1.0
var _swing_did_hit := false
var _swing_queued := false
var _drag_clock := 0.0
var _last_aim := Vector3.ZERO
var _flick_left := 0.0
var _aim_hit: Dictionary = {}
var _prompt_action: StringName = &""
var _prompt_text := ""
var _bonk_sphere := SphereShape3D.new()
var _magnet_sphere := SphereShape3D.new()


func _ready() -> void:
	_bonk_sphere.radius = BONK_RADIUS
	_magnet_sphere.radius = REACH


func tick(command: PlayerCommand, delta: float) -> void:
	_forget_freed_held()
	_aim_hit = _cast_aim()
	if command.grab_pressed:
		_on_grab_pressed()
	_tick_throw(command, delta)
	if command.use_pressed:
		_start_swing()
	_tick_swing(delta)
	_tick_flick(delta)
	_tick_drag(delta)
	if held != null:
		_drive_held(delta)
	_refresh_prompt()


func move_speed_factor() -> float:
	if not is_instance_valid(held):
		return 1.0
	if held is RagdollPart:
		var stagger := DRAG_SPEED * (1.0 - DRAG_STAGGER + DRAG_STAGGER * absf(sin(_drag_clock)) * 2.0)
		return stagger * _leash_factor()
	return clampf(1.05 - held.mass / 40.0, 0.6, 1.0)


func move_accel_factor() -> float:
	return DRAG_ACCEL if is_dragging() else 1.0


## Read between ticks too, so it must survive a body freed since the last one.
func is_dragging() -> bool:
	return is_instance_valid(held) and held is RagdollPart


## -1..1 with the step: the body's weight swinging from one side to the other.
func drag_sway() -> float:
	return sin(_drag_clock)


func charge_fraction() -> float:
	return _charge_time / THROW_CHARGE_TIME


func is_swinging() -> bool:
	return _swing_time >= 0.0


## True while the player is putting their back into what they hold: a swing or a hard flick.
func is_striking() -> bool:
	return is_swinging() or _flick_left > 0.0


## Where the swing is: below 0 pulling back, 1 at the strike, easing to 0 after it.
func swing_amount() -> float:
	if _swing_time < 0.0:
		return 0.0
	if _swing_time >= SWING_HIT_TIME:
		return cos((_swing_time - SWING_HIT_TIME) / (SWING_TIME - SWING_HIT_TIME) * PI * 0.5)
	var progress := _swing_time / SWING_HIT_TIME
	if progress < SWING_WINDUP_SHARE:
		return -SWING_WINDUP_DEPTH * sin(progress / SWING_WINDUP_SHARE * PI * 0.5)
	return lerpf(-SWING_WINDUP_DEPTH, 1.0, (progress - SWING_WINDUP_SHARE) / (1.0 - SWING_WINDUP_SHARE))


## --- Aim -------------------------------------------------------------------------

## An open opening's use volume fills the hole, so whatever lies past it would be out of
## reach: anything the hands could take beyond it wins over closing the door.
func _cast_aim() -> Dictionary:
	var eye := player.eye_position()
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, eye + player.aim_forward() * REACH, AIM_MASK, _ignored_rids())
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.get("collider") is Area3D:
		var excluded := query.exclude
		excluded.append((hit["collider"] as Area3D).get_rid())
		query.exclude = excluded
		var beyond := space.intersect_ray(query)
		var collider: Object = beyond.get("collider")
		if collider is PhysicsProp or collider is RagdollPart or collider is TestDummy:
			return beyond
	return hit


func _ignored_rids() -> Array[RID]:
	var ignored: Array[RID] = [player.get_rid()]
	if held is RagdollPart:
		ignored.append_array((held as RagdollPart).ragdoll.rids())
	elif held != null:
		ignored.append(held.get_rid())
	return ignored


func _aimed_interactable() -> Object:
	var collider: Object = _aim_hit.get("collider")
	if collider != null and collider.has_meta(&"interactable"):
		return collider.get_meta(&"interactable")
	return null


## What a grab press would work. A crosshair a little off a window must not drop the body.
func _use_target() -> Object:
	var aimed := _aimed_interactable()
	if aimed == null and is_dragging():
		return _shut_opening_ahead()
	return aimed


func _shut_opening_ahead() -> TrainOpening:
	var eye := player.eye_position()
	var forward := player.aim_forward()
	var best: TrainOpening = null
	var best_angle := OPEN_ASSIST_CONE
	for opening in player.train.openings():
		var center := opening.global_position
		var angle := forward.angle_to(center - eye)
		if not opening.is_open and angle < best_angle and eye.distance_to(center) < REACH and _clear_view(eye, _approach_point(center)):
			best_angle = angle
			best = opening
	return best


func _aimed_grabbable() -> RigidBody3D:
	var collider: Object = _aim_hit.get("collider")
	if collider is PhysicsProp and not collider.is_queued_for_deletion():
		return collider
	# A body that stood up this very tick is already on its way out.
	if collider is RagdollPart and not collider.is_queued_for_deletion() and not (collider as RagdollPart).ragdoll.is_queued_for_deletion():
		return collider
	return null


## World point of the best target near the crosshair, or null. Touch aim magnetism
## nudges the view toward it.
func magnet_target() -> Variant:
	var eye := player.eye_position()
	var forward := player.aim_forward()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _magnet_sphere
	query.transform = Transform3D(Basis.IDENTITY, eye)
	query.collision_mask = BONK_MASK | Layers.USE_VOLUME
	query.collide_with_areas = true
	query.exclude = _ignored_rids()
	var best: Variant = null
	var best_angle := MAGNET_CONE
	for hit: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider := hit["collider"] as Node3D
		if collider == null:
			continue
		var point := collider.global_position
		if collider is TestDummy:
			point += Vector3.UP * 1.3
		var angle := forward.angle_to(point - eye)
		if angle < best_angle and _has_line_of_sight(eye, point, collider):
			best_angle = angle
			best = point
	return best


func _has_line_of_sight(eye: Vector3, point: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye, point, Layers.HULL, _ignored_rids())
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target


## --- Grab / interact / drop ------------------------------------------------------

func _on_grab_pressed() -> void:
	var interactable := _use_target()
	if interactable != null:
		interactable.call("interact", player)
	elif held != null:
		drop()
	else:
		var target := _aimed_grabbable()
		if target != null:
			_grab(target)


func _grab(body: RigidBody3D) -> void:
	held = body
	body.sleeping = false
	if body is PhysicsProp:
		var prop := body as PhysicsProp
		prop.grabbed_by(self)
		prop.add_collision_exception_with(player)
	elif body is RagdollPart:
		(body as RagdollPart).ragdoll.grabbed_by(self)


func drop() -> void:
	_release()


## A freed object reads as null to a comparison, so nothing else would notice it went.
func _forget_freed_held() -> void:
	if not is_instance_valid(held):
		held = null
		if charging:
			_release()


## The held object was taken away (ripped out of a window, player fell out, ...).
func force_release() -> void:
	if held != null:
		_release()


func _release() -> void:
	var body := held
	held = null
	charging = false
	assist_point = null
	_charge_time = 0.0
	charge_changed.emit(0.0)
	if body == null:
		return
	if body is PhysicsProp:
		var prop := body as PhysicsProp
		prop.released()
		# Let a dropped prop clear the capsule before it can collide with it again.
		get_tree().create_timer(0.3).timeout.connect(_restore_collision.bind(prop))
	elif body is RagdollPart:
		(body as RagdollPart).ragdoll.released()


## Untyped: the prop can be freed while the timer runs, and a freed object fails a typed
## argument before the body gets to check it.
func _restore_collision(prop: Variant) -> void:
	if is_instance_valid(prop):
		(prop as PhysicsProp).remove_collision_exception_with(player)


## --- Holding ---------------------------------------------------------------------

func _hold_target() -> Vector3:
	var basis := player.aim_basis()
	var eye := player.eye_position()
	var swing := swing_amount()
	if held is PhysicsProp and (held as PhysicsProp).is_tool:
		var reach := 0.8 + swing * 0.55
		return eye - basis.z * reach + basis.x * (0.32 - swing * 0.18) + basis.y * (minf(swing, 0.0) * -0.3 - 0.28)
	# The heave pulls the load in and up over the shoulder, then it trembles at full charge.
	var charge := charge_fraction()
	var heave := basis.z * charge * 0.55 + basis.x * charge * 0.3 + basis.y * charge * 0.25
	if charge >= 1.0:
		heave += basis.x * sin(_drag_clock * 9.0) * 0.03
	if held is RagdollPart:
		var sway := basis.x * sin(_drag_clock) * DRAG_SWAY + basis.y * absf(cos(_drag_clock)) * DRAG_BOB
		var club := -basis.z * swing * BODY_CLUB_REACH
		return _through_pinch(eye - basis.z * HOLD_DISTANCE - basis.y * DRAG_DROP + sway + club + heave)
	var extent := (held as PhysicsProp).get_extent()
	return eye - basis.z * (HOLD_DISTANCE + extent + swing * 0.3) - basis.y * HOLD_DROP + heave


## Gangways are one body wide: inside one a dragged body keeps to the middle, clear of the jambs.
func _through_pinch(target: Vector3) -> Vector3:
	if absf(absf(target.z) - TestDummy.GANGWAY_Z) < TestDummy.GANGWAY_PINCH:
		target.x = clampf(target.x, -PINCH_LANE, PINCH_LANE)
	return target


func _leash_factor() -> float:
	var stretch := _hold_target().distance_to(held.global_position)
	return remap(clampf(stretch, LEASH_DISTANCE, BREAK_DISTANCE), LEASH_DISTANCE, BREAK_DISTANCE, 1.0, LEASH_MIN_SPEED)


func _drive_held(delta: float) -> void:
	var body := held
	var error := _hold_target() - body.global_position
	if error.length() > BREAK_DISTANCE:
		drop()
		return
	var gain := DRAG_GAIN if body is RagdollPart else HOLD_GAIN
	var wanted := (error * gain).limit_length(HOLD_MAX_SPEED) + player.velocity
	var impulse := (wanted - body.linear_velocity) * body.mass
	body.apply_central_impulse(impulse.limit_length(HOLD_MAX_FORCE * delta))
	if body is PhysicsProp and (body as PhysicsProp).is_tool:
		_drive_tool_rotation(body)


func _drive_tool_rotation(body: RigidBody3D) -> void:
	# Head of the tool (local -Z) up at rest, chopping forward through the swing.
	var tilt := lerpf(deg_to_rad(65.0), deg_to_rad(-40.0), swing_amount())
	var wanted := player.aim_basis() * Basis(Vector3.RIGHT, tilt)
	var current := body.global_basis.orthonormalized().get_rotation_quaternion()
	var difference := (wanted.get_rotation_quaternion() * current.inverse()).normalized()
	var angle := difference.get_angle()
	if angle > PI:
		angle -= TAU
	if absf(angle) < 0.001:
		body.angular_velocity = Vector3.ZERO
		return
	body.angular_velocity = difference.get_axis() * angle * TOOL_GAIN


## --- Throw -----------------------------------------------------------------------

func _tick_throw(command: PlayerCommand, delta: float) -> void:
	if command.throw_held:
		if held != null:
			charging = true
			_charge_time = minf(_charge_time + delta, THROW_CHARGE_TIME)
			charge_changed.emit(charge_fraction())
			assist_point = _find_assist_point() if held is RagdollPart else null
			_assist_approach = _assist_approach if assist_point != null else null
	elif charging:
		_throw(charge_fraction())


func _throw(fraction: float) -> void:
	var body := held
	var direction := player.aim_forward()
	var exit_point: Variant = assist_point
	var approach: Variant = _assist_approach
	_release()
	if body == null:
		return
	if body is RagdollPart:
		var ragdoll := (body as RagdollPart).ragdoll
		var speed := lerpf(THROW_BODY_MIN, THROW_BODY_MAX, fraction)
		if exit_point != null and fraction >= YeetTuning.ASSIST_MIN_CHARGE:
			var center := ragdoll.center_of_mass()
			var path: Array[Vector3] = [exit_point]
			# Line up on the hole first, unless the body is already past that point.
			if approach != null and center.distance_to(exit_point) > (approach as Vector3).distance_to(exit_point):
				path.push_front(approach)
			speed = maxf(speed, YeetTuning.GUIDE_MIN_SPEED)
			var launch := (path[0] - center).normalized() * speed
			launch.y = clampf(launch.y, -YeetTuning.GUIDE_MAX_CLIMB, YeetTuning.GUIDE_MAX_CLIMB)
			ragdoll.throw(launch + player.velocity * 0.5, player)
			ragdoll.guide_to(path, speed)
		else:
			ragdoll.throw(direction * speed + Vector3.UP * THROW_LIFT + player.velocity * 0.5, player)
	else:
		var prop := body as PhysicsProp
		var speed := lerpf(THROW_PROP_MIN, THROW_PROP_MAX, fraction) * clampf(sqrt(6.0 / prop.mass), 0.45, 1.1)
		prop.linear_velocity = direction * speed + player.velocity * 0.5
		prop.angular_velocity = player.aim_basis().x * -8.0
		prop.arm_thrown(player)
	threw.emit(fraction)


## The open door or window a heave would go through, as a point just outside the hull.
## Forgiving, not free: aim at the hole from inside the car, or the body hits the wall.
func _find_assist_point() -> Variant:
	var eye := player.eye_position()
	var forward := player.aim_forward()
	var train := player.train
	_assist_approach = null
	if eye.z > train.rear_z() - Train.PLATFORM_DEPTH and forward.z > -0.2:
		# Out on the rear platform: anywhere past the rail will do.
		return eye + Vector3(forward.x, 0.0, forward.z).normalized() * 3.5 + Vector3.UP * 0.2
	var best: Variant = null
	var best_angle := YeetTuning.ASSIST_CONE
	for opening in train.openings():
		if not opening.is_open:
			continue
		var center := opening.global_position
		var exit := _exit_point(center)
		var approach := _approach_point(center)
		var angle := minf(forward.angle_to(center - eye), forward.angle_to(exit - eye))
		if angle < best_angle and eye.distance_to(center) < YeetTuning.ASSIST_RANGE and _clear_view(eye, approach):
			best_angle = angle
			best = exit
			_assist_approach = approach
	return best


func _exit_point(center: Vector3) -> Vector3:
	if absf(center.x) > 1.0:
		return Vector3(center.x + signf(center.x) * 2.2, center.y + 0.1, center.z)
	return Vector3(0.0, 1.7, player.train.rear_z() + 1.2)  # The rear door, over the rail.


## Inside the car, in front of the hole. Looking along the wall the hole itself is hidden
## by its own frame, so sight is checked to here rather than to the hole.
func _approach_point(center: Vector3) -> Vector3:
	if absf(center.x) > 1.0:
		return Vector3(center.x - signf(center.x) * YeetTuning.OPENING_APPROACH, center.y, center.z)
	return center + Vector3.FORWARD * YeetTuning.OPENING_APPROACH


func _clear_view(eye: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye, point, Layers.HULL, _ignored_rids())
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## --- Bonk ------------------------------------------------------------------------

## Off the train nothing ticks the hands, so a swing would hang there and land on reboarding.
func cancel_swing() -> void:
	_swing_time = -1.0
	_swing_did_hit = false
	_swing_queued = false
	_flick_left = 0.0
	_last_aim = Vector3.ZERO


func _start_swing() -> void:
	if _swing_time >= 0.0:
		_swing_queued = true
		return
	_swing_time = 0.0
	_swing_did_hit = false


func _tick_swing(delta: float) -> void:
	if _swing_time < 0.0:
		return
	_swing_time += delta
	if not _swing_did_hit and _swing_time >= SWING_HIT_TIME:
		_swing_did_hit = true
		var hit := _deliver_bonk()
		swung.emit(hit)
	if _swing_time >= SWING_TIME:
		_swing_time = -1.0
		if _swing_queued:
			_swing_queued = false
			_start_swing()


func _deliver_bonk() -> bool:
	var target := _find_bonk_target()
	if target == null:
		return false
	var power := FIST_POWER
	if held is PhysicsProp:
		power = (held as PhysicsProp).bonk_power
	elif held is RagdollPart:
		power = BODY_CLUB_POWER
	var push := (player.aim_forward() + Vector3.UP * BONK_LIFT) * BONK_KNOCKBACK
	target.call("receive_bonk", power, push, player)
	player.lunge(Basis(Vector3.UP, player.yaw) * Vector3.FORWARD * BONK_LUNGE)
	return true


func _tick_flick(delta: float) -> void:
	var aim := player.aim_forward()
	_flick_left = maxf(_flick_left - delta, 0.0)
	if _last_aim != Vector3.ZERO and aim.angle_to(_last_aim) / delta >= FLICK_TURN_RATE:
		_flick_left = FLICK_LINGER
	_last_aim = aim


## The step counter for the sway, stagger and tremble. It only runs while it shows.
func _tick_drag(delta: float) -> void:
	if held == null:
		return
	var flat_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_drag_clock += delta * (1.2 + DRAG_STEP_RATE * flat_speed / Player.WALK_SPEED)


func _find_bonk_target() -> Node3D:
	var eye := player.eye_position()
	var forward := player.aim_forward()
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + forward * BONK_RANGE, Layers.HULL | BONK_MASK, _ignored_rids())
	var hit := space.intersect_ray(ray)
	var wall_distance := BONK_RANGE
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider.has_method("receive_bonk"):
			return collider as Node3D
		wall_distance = eye.distance_to(hit["position"])
	# Forgiving second pass: anything close to the crosshair and in front of the wall.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _bonk_sphere
	query.transform = Transform3D(Basis.IDENTITY, eye + forward * minf(1.3, wall_distance))
	query.collision_mask = BONK_MASK
	query.exclude = _ignored_rids()
	var best: Node3D = null
	var best_distance := INF
	for candidate: Dictionary in space.intersect_shape(query, 16):
		var node := candidate["collider"] as Node3D
		if node == null or not node.has_method("receive_bonk"):
			continue
		var distance := eye.distance_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


## --- Prompt ----------------------------------------------------------------------

func _refresh_prompt() -> void:
	var action: StringName = &""
	var text := ""
	var interactable := _use_target()
	var collider: Object = _aim_hit.get("collider")
	if assist_point != null:
		# First: the crosshair is usually on the very opening the heave is aimed at.
		action = &"throw"
		text = "Let go: YEET!"
	elif interactable != null:
		action = &"grab"
		text = interactable.call("get_prompt")
	elif held is RagdollPart:
		action = &"throw"
		text = "Hold to heave at an open door or window"
	elif held != null:
		action = &"grab"
		text = "Drop  (hold Throw to heave)"
	elif collider is PhysicsProp:
		action = &"grab"
		text = "Grab " + (collider as PhysicsProp).label
	elif collider is RagdollPart:
		action = &"grab"
		text = "Drag body"
	elif collider is TestDummy:
		action = &"use"
		text = "Bonk"
	if action != _prompt_action or text != _prompt_text:
		_prompt_action = action
		_prompt_text = text
		prompt_changed.emit(action, text)

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
const BREAK_DISTANCE := 3.2
const TOOL_GAIN := 16.0

const THROW_CHARGE_TIME := 0.75
const THROW_PROP_MIN := 5.0
const THROW_PROP_MAX := 19.0
const THROW_BODY_MIN := 6.0
const THROW_BODY_MAX := 13.0
const THROW_LIFT := 1.4         ## m/s of arc added to a thrown body.

const SWING_TIME := 0.34
const SWING_HIT_TIME := 0.12
const BONK_RANGE := 2.5
const BONK_RADIUS := 0.55
const FIST_POWER := 1

const MAGNET_CONE := deg_to_rad(9.0)

var player: Player
var held: RigidBody3D = null
var charging := false

var _charge_time := 0.0
var _swing_time := -1.0
var _swing_did_hit := false
var _aim_hit: Dictionary = {}
var _prompt_action: StringName = &""
var _prompt_text := ""
var _bonk_sphere := SphereShape3D.new()
var _magnet_sphere := SphereShape3D.new()


func _ready() -> void:
	_bonk_sphere.radius = BONK_RADIUS
	_magnet_sphere.radius = REACH


func tick(command: PlayerCommand, delta: float) -> void:
	_aim_hit = _cast_aim()
	if command.grab_pressed:
		_on_grab_pressed()
	_tick_throw(command, delta)
	if command.use_pressed:
		_start_swing()
	_tick_swing(delta)
	if held != null:
		_drive_held(delta)
	_refresh_prompt()


func move_speed_factor() -> float:
	if held == null:
		return 1.0
	if held is RagdollPart:
		return 0.72
	return clampf(1.05 - held.mass / 40.0, 0.6, 1.0)


func swing_amount() -> float:
	if _swing_time < 0.0:
		return 0.0
	return sin(clampf(_swing_time / SWING_TIME, 0.0, 1.0) * PI)


## --- Aim -------------------------------------------------------------------------

func _cast_aim() -> Dictionary:
	var eye := player.eye_position()
	var query := PhysicsRayQueryParameters3D.create(eye, eye + player.aim_forward() * REACH, AIM_MASK, _ignored_rids())
	query.collide_with_areas = true
	return player.get_world_3d().direct_space_state.intersect_ray(query)


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


func _aimed_grabbable() -> RigidBody3D:
	var collider: Object = _aim_hit.get("collider")
	if collider is PhysicsProp or collider is RagdollPart:
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
	var interactable := _aimed_interactable()
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
		var ragdoll := (body as RagdollPart).ragdoll
		ragdoll.holder = self
		ragdoll.wake()


func drop() -> void:
	_release()


## The held object was taken away (ripped out of a window, player fell out, ...).
func force_release() -> void:
	if held != null:
		_release()


func _release() -> void:
	var body := held
	held = null
	charging = false
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
		(body as RagdollPart).ragdoll.holder = null


func _restore_collision(prop: PhysicsProp) -> void:
	if is_instance_valid(prop):
		prop.remove_collision_exception_with(player)


## --- Holding ---------------------------------------------------------------------

func _hold_target() -> Vector3:
	var basis := player.aim_basis()
	var eye := player.eye_position()
	if held is PhysicsProp and (held as PhysicsProp).is_tool:
		var reach := 0.8 + swing_amount() * 0.35
		return eye - basis.z * reach + basis.x * 0.32 - basis.y * 0.28
	var extent := 0.0
	if held is PhysicsProp:
		extent = (held as PhysicsProp).get_extent()
	return eye - basis.z * (HOLD_DISTANCE + extent) - basis.y * HOLD_DROP


func _drive_held(delta: float) -> void:
	var body := held
	var error := _hold_target() - body.global_position
	if error.length() > BREAK_DISTANCE:
		drop()
		return
	var wanted := (error * HOLD_GAIN).limit_length(HOLD_MAX_SPEED) + player.velocity
	var impulse := (wanted - body.linear_velocity) * body.mass
	body.apply_central_impulse(impulse.limit_length(HOLD_MAX_FORCE * delta))
	if body is PhysicsProp and (body as PhysicsProp).is_tool:
		_drive_tool_rotation(body)


func _drive_tool_rotation(body: RigidBody3D) -> void:
	# Head of the tool (local -Z) up at rest, chopping forward through the swing.
	var tilt := lerpf(deg_to_rad(65.0), deg_to_rad(-25.0), swing_amount())
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
			charge_changed.emit(_charge_time / THROW_CHARGE_TIME)
	elif charging:
		_throw(_charge_time / THROW_CHARGE_TIME)


func _throw(fraction: float) -> void:
	var body := held
	var direction := player.aim_forward()
	_release()
	if body == null:
		return
	if body is RagdollPart:
		var speed := lerpf(THROW_BODY_MIN, THROW_BODY_MAX, fraction)
		(body as RagdollPart).ragdoll.throw(direction * speed + Vector3.UP * THROW_LIFT + player.velocity * 0.5)
	else:
		var prop := body as PhysicsProp
		var speed := lerpf(THROW_PROP_MIN, THROW_PROP_MAX, fraction) * clampf(sqrt(6.0 / prop.mass), 0.45, 1.1)
		prop.linear_velocity = direction * speed + player.velocity * 0.5
		prop.angular_velocity = player.aim_basis().x * -8.0
		prop.arm_thrown(player)
	threw.emit(fraction)


## --- Bonk ------------------------------------------------------------------------

func _start_swing() -> void:
	if _swing_time >= 0.0:
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


func _deliver_bonk() -> bool:
	var target := _find_bonk_target()
	if target == null:
		return false
	var power := FIST_POWER
	if held is PhysicsProp:
		power = (held as PhysicsProp).bonk_power
	target.call("receive_bonk", power, player.aim_forward(), player)
	return true


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
	var interactable := _aimed_interactable()
	var collider: Object = _aim_hit.get("collider")
	if interactable != null:
		action = &"grab"
		text = interactable.call("get_prompt")
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

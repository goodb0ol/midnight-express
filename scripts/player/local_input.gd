class_name LocalInput
extends PlayerInputSource
## Device input for the local player: keyboard + mouse, or the touch overlay.
## Both end up as the same named actions and the same PlayerCommand.

const MOUSE_SENSITIVITY := 0.0024
const TOUCH_SENSITIVITY := 0.0048
const PITCH_LIMIT := 1.5
## Aim magnetism, touch only: how fast the view drifts toward a target, in 1/s.
const MAGNET_RATE := 2.2

var player: Player
var touch: TouchControls
## True while a menu has the screen; the world then gets no input.
var frozen := false

var _physics_step := 1.0 / 60.0


func _ready() -> void:
	_physics_step = 1.0 / Engine.physics_ticks_per_second


func _unhandled_input(event: InputEvent) -> void:
	if touch != null and touch.enabled:
		return
	if event.is_action_pressed(&"pause"):
		_set_mouse_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		return
	if frozen:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			_set_mouse_captured(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_add_look(event.relative * MOUSE_SENSITIVITY)


func set_frozen(value: bool) -> void:
	frozen = value
	if touch == null or not touch.enabled:
		_set_mouse_captured(not value)


func sample() -> PlayerCommand:
	var command := PlayerCommand.new()
	if frozen:
		command.yaw = yaw
		command.pitch = pitch
		return command
	var touch_active := touch != null and touch.enabled
	var touch_look := Vector2.ZERO
	if touch_active:
		touch_look = touch.consume_look()
		_add_look(touch_look * TOUCH_SENSITIVITY)

	command.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if touch_active:
		command.move = (command.move + touch.stick).limit_length(1.0)
		if touch_look != Vector2.ZERO or command.move != Vector2.ZERO:
			_apply_aim_magnetism()
	command.yaw = yaw
	command.pitch = pitch
	command.jump = Input.is_action_pressed(&"jump")
	command.sprint = Input.is_action_pressed(&"sprint")
	command.grab_pressed = Input.is_action_just_pressed(&"grab")
	command.throw_held = Input.is_action_pressed(&"throw")
	command.use_pressed = Input.is_action_just_pressed(&"use")
	return command


func _add_look(delta_radians: Vector2) -> void:
	yaw = wrapf(yaw - delta_radians.x, -PI, PI)
	pitch = clampf(pitch - delta_radians.y, -PITCH_LIMIT, PITCH_LIMIT)


func _apply_aim_magnetism() -> void:
	if player == null or not player.is_aboard():
		return
	var target: Variant = player.hands.magnet_target()
	if target == null:
		return
	var to_target: Vector3 = (target as Vector3 - player.eye_position()).normalized()
	var wanted_yaw := atan2(-to_target.x, -to_target.z)
	var wanted_pitch := asin(to_target.y)
	var weight := 1.0 - exp(-MAGNET_RATE * _physics_step)
	yaw = lerp_angle(yaw, wanted_yaw, weight)
	pitch = lerpf(pitch, wanted_pitch, weight)


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

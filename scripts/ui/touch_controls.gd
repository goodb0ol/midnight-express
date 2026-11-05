class_name TouchControls
extends Control
## Mobile overlay. Tracks every finger itself so stick, look and buttons work at the
## same time: left side is a floating joystick, right side drags the camera, and the
## buttons press the same named actions as the keyboard.

const STICK_RADIUS := 95.0
const SPRINT_PUSH := 1.25    ## Push past the ring to sprint.
const STICK_ZONE := 0.42     ## Fraction of screen width owned by the joystick.
const INK := Color(1.0, 1.0, 1.0, 0.72)
const FILL := Color(0.06, 0.08, 0.14, 0.34)
const FILL_DOWN := Color(1.0, 0.72, 0.28, 0.5)
const BUTTONS: Array[Dictionary] = [
	{"action": &"use", "label": "BONK", "from_right": 112.0, "from_bottom": 128.0, "radius": 72.0},
	{"action": &"throw", "label": "THROW", "from_right": 262.0, "from_bottom": 92.0, "radius": 60.0},
	{"action": &"grab", "label": "GRAB", "from_right": 118.0, "from_bottom": 290.0, "radius": 60.0},
	{"action": &"jump", "label": "JUMP", "from_right": 262.0, "from_bottom": 238.0, "radius": 46.0},
	{"action": &"clipboard", "label": "CLIP", "from_right": 66.0, "from_bottom": -1.0, "radius": 40.0},
]

var enabled := false
var stick := Vector2.ZERO  ## x right, y forward, length <= 1.
## While the clipboard is open only its own button stays live.
var suspended := false

var _look := Vector2.ZERO
var _fingers: Dictionary = {}  # finger index -> {"role": StringName, "action": StringName}
var _stick_origin := Vector2.ZERO
var _stick_tip := Vector2.ZERO
var _stick_finger := -1
var _safe_margin := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process_input(false)
	resized.connect(_refresh_safe_area)


func enable() -> void:
	enabled = true
	visible = true
	set_process_input(true)
	# Touches also arrive as emulated mouse clicks (the clipboard buttons rely on that).
	# Unbind the mouse so a tap on the screen can't fire Bonk or Throw by itself.
	for action: StringName in [&"use", &"throw"]:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)
	_refresh_safe_area()
	queue_redraw()


func consume_look() -> Vector2:
	var look := _look
	_look = Vector2.ZERO
	return look


func button_center(button: Dictionary) -> Vector2:
	var from_bottom: float = button["from_bottom"]
	var from_right: float = button["from_right"]
	var y := 66.0 + _safe_margin.y if from_bottom < 0.0 else size.y - from_bottom - _safe_margin.y
	return Vector2(size.x - from_right - _safe_margin.x, y)


func _refresh_safe_area() -> void:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or size.x <= 0.0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var scale_x := size.x / float(window.x)
	var inset := maxf(float(window.x - safe.end.x), 0.0) * scale_x
	# A window on a desktop reports the whole monitor; only trust plausible phone notches.
	_safe_margin = Vector2(inset, 0.0) if inset < size.x * 0.1 else Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_finger_down(event.index, event.position)
		else:
			_on_finger_up(event.index)
	elif event is InputEventScreenDrag:
		_on_finger_drag(event.index, event.position, event.relative)


func _on_finger_down(finger: int, point: Vector2) -> void:
	var button := _button_at(point)
	if not button.is_empty():
		var action: StringName = button["action"]
		_fingers[finger] = {"role": &"button", "action": action}
		Input.action_press(action)
		queue_redraw()
		return
	if suspended:
		return
	if point.x < size.x * STICK_ZONE and _stick_finger < 0:
		_fingers[finger] = {"role": &"stick", "action": &""}
		_stick_finger = finger
		_stick_origin = point
		_stick_tip = point
		queue_redraw()
	else:
		_fingers[finger] = {"role": &"look", "action": &""}


func _on_finger_drag(finger: int, point: Vector2, relative: Vector2) -> void:
	if not _fingers.has(finger):
		return
	var role: StringName = _fingers[finger]["role"]
	if role == &"look":
		_look += relative
	elif role == &"stick":
		_stick_tip = point
		var offset := (point - _stick_origin) / STICK_RADIUS
		_set_sprint(offset.length() > SPRINT_PUSH)
		offset = offset.limit_length(1.0)
		stick = Vector2(offset.x, -offset.y)
		queue_redraw()


func _on_finger_up(finger: int) -> void:
	if not _fingers.has(finger):
		return
	var info: Dictionary = _fingers[finger]
	_fingers.erase(finger)
	if info["role"] == &"button":
		Input.action_release(info["action"])
	elif info["role"] == &"stick":
		_stick_finger = -1
		stick = Vector2.ZERO
		_set_sprint(false)
	queue_redraw()


func _set_sprint(on: bool) -> void:
	if on:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _button_at(point: Vector2) -> Dictionary:
	for button in BUTTONS:
		if suspended and button["action"] != &"clipboard":
			continue
		var radius: float = button["radius"]
		if point.distance_to(button_center(button)) <= radius * 1.15:
			return button
	return {}


func _is_button_down(action: StringName) -> bool:
	for info: Dictionary in _fingers.values():
		if info["role"] == &"button" and info["action"] == action:
			return true
	return false


func _draw() -> void:
	if not enabled:
		return
	var font := ThemeDB.fallback_font
	for button in BUTTONS:
		if suspended and button["action"] != &"clipboard":
			continue
		var center := button_center(button)
		var radius: float = button["radius"]
		var action: StringName = button["action"]
		var label: String = button["label"]
		draw_circle(center, radius, FILL_DOWN if _is_button_down(action) else FILL)
		draw_arc(center, radius, 0.0, TAU, 48, INK, 2.0, true)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(font, center + Vector2(-text_size.x * 0.5, 7.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	if _stick_finger >= 0:
		draw_circle(_stick_origin, STICK_RADIUS, FILL)
		draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, INK, 2.0, true)
		var tip := _stick_origin + (_stick_tip - _stick_origin).limit_length(STICK_RADIUS)
		draw_circle(tip, 34.0, Color(1.0, 1.0, 1.0, 0.45))
	elif not suspended:
		var hint := Vector2(130.0, size.y - 150.0)
		draw_arc(hint, STICK_RADIUS * 0.7, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.18), 2.0, true)

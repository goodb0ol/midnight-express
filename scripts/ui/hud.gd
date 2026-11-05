class_name Hud
extends CanvasLayer
## Crosshair, context prompt, throw charge, status line, toasts, clipboard.

const TOAST_SECONDS := 2.4

var clipboard: Clipboard
var clipboard_open := false
var touch_mode := false

var _player: Player
var _local_input: LocalInput
var _touch: TouchControls
var _prompt: Label
var _status: Label
var _toast: Label
var _charge: ProgressBar
var _rope_hint: Label
var _toast_left := 0.0
var _yeet_count := 0
var _status_timer := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var crosshair := ColorRect.new()
	crosshair.color = Color(1.0, 1.0, 1.0, 0.85)
	crosshair.custom_minimum_size = Vector2(5.0, 5.0)
	crosshair.size = Vector2(5.0, 5.0)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(2.5, 2.5)
	root.add_child(crosshair)

	_prompt = _add_label(root, Control.PRESET_CENTER, Vector2(-300.0, 34.0), 600.0, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_rope_hint = _add_label(root, Control.PRESET_CENTER, Vector2(-300.0, -120.0), 600.0, 30, HORIZONTAL_ALIGNMENT_CENTER)
	_rope_hint.modulate = Color(1.0, 0.72, 0.3)
	_toast = _add_label(root, Control.PRESET_CENTER_TOP, Vector2(-300.0, 70.0), 600.0, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_status = _add_label(root, Control.PRESET_TOP_LEFT, Vector2(16.0, 12.0), 700.0, 18, HORIZONTAL_ALIGNMENT_LEFT)

	_charge = ProgressBar.new()
	_charge.show_percentage = false
	_charge.max_value = 1.0
	_charge.custom_minimum_size = Vector2(220.0, 10.0)
	_charge.size = Vector2(220.0, 10.0)
	_charge.set_anchors_preset(Control.PRESET_CENTER)
	_charge.position += Vector2(-110.0, 66.0)
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge.visible = false
	root.add_child(_charge)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	clipboard = Clipboard.new()
	clipboard.name = "Clipboard"
	clipboard.visible = false
	center.add_child(clipboard)

	GameEvents.object_yeeted.connect(_on_object_yeeted)
	GameEvents.npc_knocked_out.connect(func(_npc: Node3D, _body: Node3D, _by: Node3D) -> void: show_toast("OUT COLD"))
	GameEvents.player_left_train.connect(func(_who: Node3D) -> void: show_toast("YOU FELL OFF THE TRAIN"))
	GameEvents.player_left_behind.connect(func(_who: Node3D) -> void: show_toast("LEFT BEHIND"))
	GameEvents.player_reboarded.connect(func(_who: Node3D) -> void: show_toast("BACK ABOARD"))


func _add_label(parent: Control, preset: Control.LayoutPreset, offset: Vector2, width: float, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.position += offset
	label.custom_minimum_size.x = width
	label.size.x = width
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


func bind_local_player(player: Player, local_input: LocalInput, touch: TouchControls) -> void:
	_player = player
	_local_input = local_input
	_touch = touch
	touch_mode = touch.enabled
	player.hands.prompt_changed.connect(_on_prompt_changed)
	player.hands.charge_changed.connect(_on_charge_changed)


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_left = TOAST_SECONDS


func toggle_clipboard() -> void:
	clipboard_open = not clipboard_open
	clipboard.visible = clipboard_open
	if _local_input != null:
		_local_input.set_frozen(clipboard_open)
	if _touch != null:
		_touch.suspended = clipboard_open
		_touch.queue_redraw()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"clipboard"):
		toggle_clipboard()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.2
		_status.text = "%d km/h    %d m    yeeted: %d" % [roundi(TrainState.speed_kmh()), roundi(TrainState.distance_m), _yeet_count]
	_update_rope_hint()


func _update_rope_hint() -> void:
	if _player == null or _player.is_aboard():
		_rope_hint.text = ""
	elif _player.state == Player.State.ROPE:
		_rope_hint.text = "HOLD ON"
	elif _player.train.rope.in_reach(_player.global_position):
		_rope_hint.text = "GRAB THE ROPE  [%s]" % ("GRAB" if touch_mode else InputHelp.label_for(&"grab"))
	else:
		_rope_hint.text = "STEER TO THE ROPE"


func _on_prompt_changed(action: StringName, text: String) -> void:
	if text.is_empty():
		_prompt.text = ""
	elif touch_mode:
		_prompt.text = text
	else:
		_prompt.text = "[%s]  %s" % [InputHelp.label_for(action), text]


func _on_charge_changed(fraction: float) -> void:
	_charge.visible = fraction > 0.0
	_charge.value = fraction


func _on_object_yeeted(body: Node3D) -> void:
	_yeet_count += 1
	show_toast("BODY OVERBOARD" if body is Ragdoll else "YEET")

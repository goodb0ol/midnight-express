class_name Clipboard
extends PanelContainer
## Core action 4. Milestone 3 turns this into the manifest and ID inspection overlay;
## for now it holds the controls list and the test bench.

signal reset_cargo_requested
signal respawn_requested

const SPEEDS_KMH: Array[float] = [0.0, 50.0, 100.0, 150.0]


func _ready() -> void:
	custom_minimum_size = Vector2(560.0, 0.0)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "CLIPBOARD  -  Milestone 1 test bench"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var controls := Label.new()
	controls.name = "Controls"
	controls.text = _controls_text()
	column.add_child(controls)

	column.add_child(HSeparator.new())
	var speed_label := Label.new()
	speed_label.text = "Train speed"
	column.add_child(speed_label)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	column.add_child(speed_row)
	for kmh in SPEEDS_KMH:
		var button := Button.new()
		button.text = "Stopped" if kmh == 0.0 else "%d km/h" % kmh
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 52.0
		button.pressed.connect(TrainState.set_target_kmh.bind(kmh))
		speed_row.add_child(button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	_add_action(actions, "Reset cargo and dummies", reset_cargo_requested.emit)
	_add_action(actions, "Back on the train", respawn_requested.emit)


func _add_action(row: HBoxContainer, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 52.0
	button.pressed.connect(on_pressed)
	row.add_child(button)


func _controls_text() -> String:
	var keys := "%s %s %s %s" % [
		InputHelp.label_for(&"move_forward"), InputHelp.label_for(&"move_left"),
		InputHelp.label_for(&"move_back"), InputHelp.label_for(&"move_right"),
	]
	return "\n".join([
		"Move: %s    Sprint: %s    Jump: %s" % [keys, InputHelp.label_for(&"sprint"), InputHelp.label_for(&"jump")],
		"Grab / open / drop: %s" % InputHelp.label_for(&"grab"),
		"Throw (hold, release): %s" % InputHelp.label_for(&"throw"),
		"Bonk: %s" % InputHelp.label_for(&"use"),
		"Clipboard: %s    Free the mouse: %s" % [InputHelp.label_for(&"clipboard"), InputHelp.label_for(&"pause")],
		"",
		"Wrench or pan: one bonk knocks out. Fists: three.",
		"Fell out? Press grab near the orange rope behind the train.",
	])

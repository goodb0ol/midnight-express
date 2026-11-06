class_name RoundHud
extends Control
## Everything the player reads during a raid: countdown, stowaways left, score, combo,
## floating score popups, the red raid warning, the title card and the results screen.
## Listens to GameEvents and reads RoundDirector's public state; it never changes rules.

signal restart_pressed
signal menu_changed(open: bool)

const COLOR_GOLD := Color(1.0, 0.82, 0.3)
const COLOR_CREAM := Color(1.0, 0.95, 0.85)
const COLOR_RED := Color(1.0, 0.2, 0.13)
const COLOR_GOOD := Color(0.55, 1.0, 0.45)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.9)
const TITLE_HOLD := 2.2
const POPUP_SECONDS := 1.5
const POPUP_SLOTS := 3
const POPUP_SLOT_HEIGHT := 58.0
## First popup line, below the crosshair, the use prompt and the throw charge bar.
const POPUP_BELOW_CENTER := 110.0
const POPUP_BOTTOM_ROOM := 90.0
## Less than a slot, so a popup never drifts into the line above it.
const POPUP_DRIFT := 30.0
## Stops a player still mashing jump or grab from dismissing the results unread.
const BUTTON_LOCK := 0.8

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float edge = smoothstep(0.35, 1.0, length(UV - vec2(0.5)) * 1.41);
	COLOR = vec4(0.95, 0.04, 0.02, clamp(strength * edge + strength * 0.12, 0.0, 1.0));
}
"""

var director: RoundDirector
var menu_open := false
var restart_button: Button
var results_panel: Control

var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _markers: RoundMarkers
var _countdown: Label
var _raid_warning: Label
var _score: Label
var _stowaways: Label
var _combo: Label
var _combo_bar: ColorRect
var _popups: Control
var _title_band: ColorRect
var _title_heading: Label
var _title_line: Label
var _title_help: Label
var _banner: Label
var _result_heading: Label
var _result_score: Label
var _result_rank: Label
var _result_lines: Label
var _lock_left := 0.0
var _title_left := 0.0
var _popup_lines: Array[Control] = []  # One entry per slot, null when free.
var _popup_serial := 0
var _shown_score := 0
var _urgent := false
var _touch_mode := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_popup_lines.resize(POPUP_SLOTS)
	_build_vignette()
	_markers = RoundMarkers.new()
	_markers.name = "Markers"
	add_child(_markers)
	_build_counters()
	_popups = Control.new()
	_popups.name = "Popups"
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	_build_title_card()
	_build_results()
	GameEvents.round_started.connect(_on_round_started)
	GameEvents.score_awarded.connect(_on_score_awarded)
	GameEvents.raid_warning.connect(_on_raid_warning)
	GameEvents.round_ended.connect(_on_round_ended)


func bind(round_director: RoundDirector, touch_mode: bool) -> void:
	director = round_director
	_markers.director = round_director
	_touch_mode = touch_mode
	visible = true
	set_process(true)


func _label(parent: Control, text: String, font_size: int, color: Color, outline := 10) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	parent.add_child(label)
	return label


func _centered_top(parent: Control, text: String, font_size: int, color: Color, top: float, width := 700.0) -> Label:
	var label := _label(parent, text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -width * 0.5
	label.offset_right = width * 0.5
	label.offset_top = top
	return label


func _build_vignette() -> void:
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette = ColorRect.new()
	_vignette.name = "RaidVignette"
	_vignette.material = _vignette_material
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)


func _build_counters() -> void:
	_countdown = _centered_top(self, "1:00", 76, COLOR_CREAM, 2.0, 300.0)
	_countdown.add_theme_constant_override("outline_size", 14)
	_raid_warning = _centered_top(self, "", 34, COLOR_RED, 92.0)
	_combo = _centered_top(self, "", 40, COLOR_GOLD, 92.0)
	_combo_bar = ColorRect.new()
	_combo_bar.color = COLOR_GOLD
	_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_bar.offset_top = 142.0
	_combo_bar.offset_bottom = 149.0
	add_child(_combo_bar)

	_score = _label(self, "0", 46, COLOR_GOLD)
	_score.position = Vector2(16.0, 36.0)
	_stowaways = _label(self, "", 30, COLOR_RED, 8)
	_stowaways.position = Vector2(16.0, 94.0)


func _build_title_card() -> void:
	_title_band = ColorRect.new()
	_title_band.name = "TitleCard"
	_title_band.color = Color(0.03, 0.03, 0.06, 0.82)
	_title_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_band.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	_title_band.anchor_top = 0.5
	_title_band.anchor_bottom = 0.5
	_title_band.offset_top = -135.0
	_title_band.offset_bottom = 135.0
	_title_band.visible = false
	add_child(_title_band)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_band.add_child(column)
	_title_heading = _label(column, "", 84, COLOR_RED, 14)
	_title_line = _label(column, "", 38, COLOR_CREAM)
	_title_help = _label(column, "", 24, COLOR_GOLD, 6)
	for label: Label in [_title_heading, _title_line, _title_help]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_banner = _label(self, "", 96, COLOR_RED, 16)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -560.0
	_banner.offset_right = 560.0
	_banner.offset_top = -200.0  # Clear of the middle: the fines land down the aisle.
	_banner.visible = false


func _build_results() -> void:
	var dim := ColorRect.new()
	dim.name = "Results"
	dim.color = Color(0.02, 0.02, 0.05, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	add_child(dim)
	results_panel = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size.x = 860.0
	center.add_child(column)
	_result_heading = _label(column, "", 56, COLOR_RED, 12)
	_result_score = _label(column, "", 84, COLOR_GOLD, 14)
	_result_rank = _label(column, "", 38, COLOR_CREAM)
	_result_rank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_lines = _label(column, "", 24, Color(0.8, 0.82, 0.9), 6)
	for label: Label in [_result_heading, _result_score, _result_rank, _result_lines]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.custom_minimum_size = Vector2(0.0, 120.0)
	restart_button.add_theme_font_size_override("font_size", 52)
	restart_button.add_theme_color_override("font_color", Color(0.1, 0.03, 0.02))
	restart_button.add_theme_color_override("font_hover_color", Color(0.1, 0.03, 0.02))
	restart_button.add_theme_color_override("font_pressed_color", Color(0.1, 0.03, 0.02))
	restart_button.add_theme_color_override("font_focus_color", Color(0.1, 0.03, 0.02))
	restart_button.add_theme_color_override("font_disabled_color", Color(0.1, 0.03, 0.02, 0.55))
	restart_button.add_theme_stylebox_override("normal", _button_style(COLOR_GOLD))
	restart_button.add_theme_stylebox_override("hover", _button_style(COLOR_GOLD.lightened(0.25)))
	restart_button.add_theme_stylebox_override("pressed", _button_style(COLOR_GOLD.darkened(0.2)))
	restart_button.add_theme_stylebox_override("focus", _button_style(Color(0.0, 0.0, 0.0, 0.0), COLOR_CREAM))
	restart_button.add_theme_stylebox_override("disabled", _button_style(COLOR_GOLD.darkened(0.45)))
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	column.add_child(restart_button)


func _button_style(fill: Color, border := Color(0.0, 0.0, 0.0, 0.0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(14)
	style.set_border_width_all(4 if border.a > 0.0 else 0)
	style.border_color = border
	return style


func _process(delta: float) -> void:
	if director == null:
		return
	var in_play := director.phase != RoundDirector.Phase.RESULTS and director.phase != RoundDirector.Phase.IDLE
	for item: Control in [_countdown, _score, _stowaways]:
		item.visible = in_play
	if in_play:
		_update_counters()
	_update_warning()
	_update_combo()
	_update_banner()
	if _title_left > 0.0:
		_title_left -= delta
		if _title_left <= 0.0:
			var fade := create_tween()
			fade.tween_property(_title_band, "modulate:a", 0.0, 0.25)
			fade.tween_callback(func() -> void: _title_band.visible = false)
	if _lock_left > 0.0:
		_lock_left -= delta
		if _lock_left <= 0.0:
			restart_button.disabled = false
			restart_button.grab_focus()


func _update_counters() -> void:
	var seconds := ceili(director.time_left)
	_countdown.text = "%d:%02d" % [seconds / 60, seconds % 60]
	var urgent := director.time_left <= RoundDirector.WARNING_SECONDS
	if urgent != _urgent:
		_urgent = urgent
		_countdown.add_theme_color_override("font_color", COLOR_RED if urgent else COLOR_CREAM)
	if _shown_score != director.score:
		_shown_score = director.score
		_score.text = "%d" % _shown_score
		_punch(_score)
	_stowaways.text = "STOWAWAYS LEFT: %d" % director.stowaways_left


func _update_warning() -> void:
	var active: bool = director.phase == RoundDirector.Phase.RAID and director.time_left <= RoundDirector.WARNING_SECONDS
	var hit: bool = director.phase == RoundDirector.Phase.ENDING and director.raid_hit
	_vignette.visible = active or hit
	_raid_warning.visible = active
	if hit:
		_vignette_material.set_shader_parameter("strength", 0.9)
	elif active:
		# Throbs once a second, on the beat of the countdown, and swells as it runs out.
		var beat := fposmod(director.time_left, 1.0)
		var dread := 1.0 - director.time_left / RoundDirector.WARNING_SECONDS
		_vignette_material.set_shader_parameter("strength", 0.25 + 0.35 * dread + 0.4 * beat)
		_raid_warning.text = "RAID WARNING  -  HIDE THE EVIDENCE"
		_raid_warning.modulate.a = 0.75 + 0.25 * beat


func _update_combo() -> void:
	var show_combo: bool = director.combo > 1 and director.phase == RoundDirector.Phase.RAID and director.time_left > RoundDirector.WARNING_SECONDS
	_combo.visible = show_combo
	_combo_bar.visible = show_combo
	if show_combo:
		_combo.text = "COMBO x%d" % director.combo
		var half := 150.0 * director.combo_left / RoundDirector.COMBO_WINDOW
		_combo_bar.offset_left = -half
		_combo_bar.offset_right = half


func banner_showing() -> bool:
	return _banner.visible


func _update_banner() -> void:
	var ending: bool = director.phase == RoundDirector.Phase.ENDING
	if ending and not _banner.visible:
		_banner.text = "THE RAID HITS" if director.raid_hit else "TRAIN CLEAR"
		_banner.add_theme_color_override("font_color", COLOR_RED if director.raid_hit else COLOR_GOOD)
	_banner.visible = ending


func _punch(item: Control) -> void:
	item.pivot_offset = Vector2(0.0, item.size.y * 0.5)
	item.scale = Vector2.ONE * 1.3
	create_tween().tween_property(item, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _on_round_started(number: int, stowaways: int, seconds: int) -> void:
	_set_results(false)
	_shown_score = 0
	_score.text = "0"
	_title_heading.text = "RAID %d" % number
	_title_line.text = "%d STOWAWAYS.  %d SECONDS.  THROW THEM OFF THE TRAIN." % [stowaways, seconds]
	_title_help.text = _help_line()
	_title_band.visible = true
	_title_band.modulate.a = 1.0
	_title_left = TITLE_HOLD
	_title_band.pivot_offset = _title_band.size * 0.5
	_title_band.scale = Vector2(1.0, 0.1)
	create_tween().tween_property(_title_band, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _help_line() -> String:
	if _touch_mode:
		return "GRAB THE WRENCH beside you: one bonk and they drop.\nBONK the red tags.  GRAB the body.  GRAB a window to open it.  THROW."
	return "GRAB THE WRENCH beside you [%s]: one bonk and they drop.\n[%s] bonk the red tags    [%s] grab the body, open a window    [%s] hold and throw" % [
		InputHelp.label_for(&"grab"), InputHelp.label_for(&"use"), InputHelp.label_for(&"grab"), InputHelp.label_for(&"throw"),
	]


func _on_score_awarded(points: int, reason: String) -> void:
	var size_for_points := clampi(32 + absi(points) / 20, 32, 62)
	var text := "%+d  %s" % [points, reason]
	var popup := _label(_popups, text, size_for_points, COLOR_GOLD if points > 0 else COLOR_RED, 12)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.size = Vector2(1000.0, 80.0)
	var slot := _free_popup_slot()
	_popup_serial += 1
	popup.set_meta(&"serial", _popup_serial)
	_popup_lines[slot] = popup
	var start := Vector2(size.x * 0.5 - 500.0, popup_line_y(slot, size.y))
	popup.position = start
	popup.pivot_offset = popup.size * 0.5
	popup.scale = Vector2.ONE * 1.5
	# Bound to the popup, so a popup retired early takes its tween with it.
	var tween := popup.create_tween().set_parallel()
	tween.tween_property(popup, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "position:y", start.y - POPUP_DRIFT, POPUP_SECONDS)
	tween.tween_property(popup, "modulate:a", 0.0, 0.45).set_delay(POPUP_SECONDS - 0.45)
	tween.chain().tween_callback(popup.queue_free)


## Lines fill downward from just under the crosshair and fit any window height.
static func popup_line_y(slot: int, height: float) -> float:
	var top := height * 0.5 + POPUP_BELOW_CENTER
	var room := height - POPUP_BOTTOM_ROOM - top
	return top + slot * minf(POPUP_SLOT_HEIGHT, room / float(POPUP_SLOTS - 1))


## The highest free line. With every line busy the oldest popup gives up its place.
func _free_popup_slot() -> int:
	var oldest := 0
	for slot in POPUP_SLOTS:
		var line := _popup_lines[slot]
		if not is_instance_valid(line) or line.is_queued_for_deletion():
			return slot
		if line.get_meta(&"serial") < _popup_lines[oldest].get_meta(&"serial"):
			oldest = slot
	_popup_lines[oldest].queue_free()
	return oldest


func _on_raid_warning(_seconds_left: int) -> void:
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2.ONE * 1.35
	create_tween().tween_property(_countdown, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _on_round_ended(round_score: int, passed: bool) -> void:
	if director == null:
		return
	_result_heading.text = "RAID %d SURVIVED" % director.round_number if passed else "RAID %d LOST" % director.round_number
	_result_heading.add_theme_color_override("font_color", COLOR_GOOD if passed else COLOR_RED)
	_result_score.text = "%d" % round_score
	_result_rank.text = director.rank_title.to_upper()
	var lines: Array[String] = [
		"Stowaways yeeted: %d of %d      Paying passengers yeeted: %d" % [director.stowaways_yeeted, director.stowaways_total, director.passengers_yeeted],
	]
	if director.fines_paid > 0:
		lines.append("Fines: -%d" % director.fines_paid)
	lines.append("Run total: %d      Best: %d" % [director.total_score, director.best_score])
	_result_lines.text = "\n".join(lines)
	restart_button.text = "NEXT RAID" if passed else "TRY AGAIN"
	_set_results(true)


func _set_results(open: bool) -> void:
	results_panel.visible = open
	if open == menu_open:
		return
	menu_open = open
	if open:
		restart_button.disabled = true
		_lock_left = BUTTON_LOCK
		results_panel.modulate.a = 0.0
		create_tween().tween_property(results_panel, "modulate:a", 1.0, 0.2)
	menu_changed.emit(open)

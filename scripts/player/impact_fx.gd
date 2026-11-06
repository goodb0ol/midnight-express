class_name ImpactFx
extends Node3D
## Local-only eye candy. Listens to GameEvents and never touches gameplay: comic hit
## words, burst particles, flight trails and the marker on the opening a heave will hit.
## Pools its nodes, so a pile-up reuses the oldest effect instead of allocating.

const BURST_POOL := 10
const WORD_POOL := 8
const VISIBLE_RANGE := 140.0
const BURST_MIN_SPEED := 6.0
const SCENERY_WORD_SPEED := 10.0
const GROUND_BAND := 1.2     ## Metres above the snow where a hit throws up snow.
const BONK_WORDS: Array[String] = ["BONK!", "THWACK!", "CLONK!", "WHAP!"]
const SCENERY_WORDS: Array[String] = ["SPLAT!", "CRUNCH!", "OOF!", "WHAM!"]
const COLOR_HIT := Color(1.0, 0.82, 0.25)
const COLOR_KNOCKOUT := Color(1.0, 0.36, 0.2)
const COLOR_SNOW := Color(0.92, 0.96, 1.0)
const COLOR_YEET := Color(0.45, 0.95, 1.0)

var _bursts: Array[CPUParticles3D] = []
var _words: Array[Label3D] = []
var _word_tweens: Array[Tween] = []
var _next_burst := 0
var _next_word := 0
var _last_bonk_word: Label3D = null
var _last_bonk_tick := -1
var _chip: Mesh
var _marker: MeshInstance3D
var _marker_clock := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.045
	box.material = material
	_chip = box
	for i in BURST_POOL:
		_bursts.append(_make_burst())
	for i in WORD_POOL:
		_words.append(_make_word())
		_word_tweens.append(null)
	_build_marker()
	GameEvents.npc_bonked.connect(_on_npc_bonked)
	GameEvents.npc_knocked_out.connect(_on_npc_knocked_out)
	GameEvents.impact.connect(_on_impact)
	GameEvents.body_hit_scenery.connect(_on_body_hit_scenery)
	GameEvents.object_yeeted.connect(_on_object_yeeted)


## Marks the exit a heave will take, or hides the marker when [param point] is null.
func show_assist(point: Variant, delta: float) -> void:
	_marker.visible = point != null
	if point == null:
		return
	_marker_clock += delta
	var eye := get_viewport().get_camera_3d().global_position
	_marker.global_position = point
	_marker.look_at(eye, Vector3.UP, true)
	_marker.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_marker.scale = Vector3.ONE * (0.8 + sin(_marker_clock * 11.0) * 0.14)


## How many hit words are up; lets tests and tools see the effects fire.
func active_word_count() -> int:
	var count := 0
	for word in _words:
		if word.visible:
			count += 1
	return count


func _make_burst() -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.emitting = false
	burst.amount = 26
	burst.lifetime = 0.7
	burst.explosiveness = 1.0
	burst.local_coords = false
	burst.mesh = _chip
	burst.direction = Vector3.UP
	burst.spread = 80.0
	burst.gravity = Vector3(0.0, -13.0, 0.0)
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.5
	add_child(burst)
	return burst


func _make_word() -> Label3D:
	var word := Label3D.new()
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.no_depth_test = true
	word.shaded = false
	word.double_sided = true
	word.fixed_size = false
	word.pixel_size = 0.0034
	word.font_size = 120
	word.outline_size = 34
	word.outline_modulate = Color(0.08, 0.04, 0.02)
	word.render_priority = 10
	word.outline_render_priority = 9
	word.visible = false
	add_child(word)
	return word


func _build_marker() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.72
	ring.rings = 24
	ring.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.6, 0.12)
	ring.material = material
	_marker = MeshInstance3D.new()
	_marker.name = "AssistMarker"
	_marker.mesh = ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func _burst(at: Vector3, color: Color, speed: float) -> void:
	var burst := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % BURST_POOL
	burst.global_position = at
	burst.color = color
	burst.initial_velocity_min = speed * 0.35
	burst.initial_velocity_max = speed
	burst.restart()


func _say(text: String, at: Vector3, color: Color, size := 1.0) -> Label3D:
	var index := _next_word
	_next_word = (_next_word + 1) % WORD_POOL
	var word := _words[index]
	if _word_tweens[index] != null:
		_word_tweens[index].kill()
	word.text = text
	word.modulate = color
	word.global_position = at
	word.scale = Vector3.ONE * 0.2
	word.visible = true
	var tween := create_tween()
	_word_tweens[index] = tween
	tween.tween_property(word, "scale", Vector3.ONE * size, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(word, "global_position", at + Vector3.UP * 0.7, 0.75).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.25)
	tween.tween_property(word, "modulate:a", 0.0, 0.3)
	tween.tween_property(word, "outline_modulate:a", 0.0, 0.01)
	tween.tween_callback(_hide_word.bind(word))
	return word


func _hide_word(word: Label3D) -> void:
	word.visible = false
	word.outline_modulate.a = 1.0


func _in_range(at: Vector3) -> bool:
	return at.distance_to(get_viewport().get_camera_3d().global_position) < VISIBLE_RANGE


static func _body_point(body: Node3D) -> Vector3:
	if body is Ragdoll:
		return (body as Ragdoll).anchor()
	return body.global_position


func _on_npc_bonked(npc: Node3D, _attacker: Node3D, power: int) -> void:
	var at := npc.global_position + Vector3.UP * 1.5
	_last_bonk_word = _say(BONK_WORDS.pick_random(), at + Vector3.UP * 0.3, COLOR_HIT, 0.8 + power * 0.15)
	_last_bonk_tick = Engine.get_physics_frames()
	_burst(at, COLOR_HIT, 5.0 + power * 1.5)


func _on_npc_knocked_out(npc: Node3D, _ragdoll: Node3D, _attacker: Node3D) -> void:
	var at := npc.global_position + Vector3.UP * 1.4
	if _last_bonk_word != null and _last_bonk_tick == Engine.get_physics_frames():
		_last_bonk_word.visible = false  # One word per hit: the knockout outranks the bonk.
	_say("OUT COLD!", at + Vector3.UP * 0.5, COLOR_KNOCKOUT, 1.3)
	_burst(at, COLOR_KNOCKOUT, 11.0)


func _on_impact(_body: Node3D, at: Vector3, speed: float) -> void:
	if speed < BURST_MIN_SPEED or not _in_range(at):
		return
	if at.y < Treadmill.GROUND_Y + GROUND_BAND:
		_burst(at, COLOR_SNOW, minf(speed * 0.55, 14.0))
	else:
		_burst(at, COLOR_HIT, minf(speed * 0.4, 9.0))


func _on_body_hit_scenery(body: Node3D, speed: float) -> void:
	var at := _body_point(body)
	if speed < SCENERY_WORD_SPEED or not _in_range(at):
		return
	_say(SCENERY_WORDS.pick_random(), at + Vector3.UP * 1.2, COLOR_KNOCKOUT, 1.6)
	_burst(at, COLOR_SNOW, 15.0)


func _on_object_yeeted(body: Node3D) -> void:
	var at := _body_point(body)
	if body is Ragdoll:
		_say("YEET!", at + Vector3.UP * 0.8, COLOR_YEET, 1.5)
		(body as Ragdoll).pelvis.add_child(_make_trail(0.8))
	elif body is PhysicsProp and body.mass >= 5.0:
		body.add_child(_make_trail(0.45))


## Sparks streaming off a body in flight. Freed along with it.
func _make_trail(size: float) -> CPUParticles3D:
	var trail := CPUParticles3D.new()
	trail.name = "YeetTrail"
	trail.amount = 42
	trail.lifetime = 0.9
	trail.local_coords = false
	trail.mesh = _chip
	trail.color = COLOR_YEET
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 1.4
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = size
	trail.scale_amount_max = size * 1.8
	return trail

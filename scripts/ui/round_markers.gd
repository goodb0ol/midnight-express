class_name RoundMarkers
extends Control
## Red tags over every stowaway still aboard, seen through walls and pinned to the
## screen edge when off camera, so "where is the next one" never stalls the round.
## Tags that would land on top of each other merge into one with a count.

const SIZE := 16.0
const EDGE := 54.0
const CLOSE_M := 7.0
const COLOR_MARK := Color(1.0, 0.16, 0.1)
const COLOR_LINE := Color(0.08, 0.0, 0.0, 0.9)
const STANDING_HEIGHT := 2.15
const BODY_HEIGHT := 0.8
const TAG_WIDTH := 140.0
const TAG_FONT_SIZE := 18
const MERGE_PIXELS := 96.0
## How far a point behind the camera leans toward the bottom edge, as a share of its depth.
const BEHIND_LEAN := 0.35

var director: RoundDirector


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if director == null:
		return
	if director.phase != RoundDirector.Phase.TITLE and director.phase != RoundDirector.Phase.RAID:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var tags: Array[Dictionary] = []
	for body in director.stowaway_bodies():
		if body is Ragdoll and body.holder != null:
			continue
		tags.append(_place(camera, _anchor(body)))
	var bob := sin(Time.get_ticks_msec() * 0.006) * 4.0
	for tag in merge_tags(tags):
		_draw_tag(tag, bob)


func _anchor(body: Node3D) -> Vector3:
	if body is Ragdoll:
		return body.anchor() + Vector3.UP * BODY_HEIGHT
	return body.global_position + Vector3.UP * STANDING_HEIGHT


func _place(camera: Camera3D, point: Vector3) -> Dictionary:
	var middle := size * 0.5
	var limit := middle - Vector2.ONE * EDGE
	var metres := camera.global_position.distance_to(point)
	var offset: Vector2
	var pinned := true
	if camera.is_position_behind(point):
		offset = behind_direction(camera.to_local(point))
	else:
		offset = camera.unproject_position(point) - middle
		pinned = absf(offset.x) > limit.x or absf(offset.y) > limit.y
	if not pinned:
		return {"at": middle + offset, "direction": Vector2.DOWN, "pinned": false, "metres": metres, "count": 1}
	offset = pin_to_edge(offset, limit)
	return {"at": middle + offset, "direction": offset.normalized(), "pinned": true, "metres": metres, "count": 1}


## Screen direction toward a point behind the camera, from its camera-space position.
## Always leans down, so "turn around" reads along the bottom and sides, never on the clock.
static func behind_direction(local: Vector3) -> Vector2:
	return Vector2(local.x, maxf(absf(local.z) * BEHIND_LEAN, 0.01))


## Pushes a direction out to the rectangle of half-size [param limit]. A zero direction,
## such as a point dead behind the camera, pins to the bottom edge.
static func pin_to_edge(direction: Vector2, limit: Vector2) -> Vector2:
	var aim := direction.normalized() if direction.length_squared() > 0.000001 else Vector2.DOWN
	return aim * minf(limit.x / maxf(absf(aim.x), 0.001), limit.y / maxf(absf(aim.y), 0.001))


## The nearest stowaway keeps the arrow; any tag within reach of it joins its count.
static func merge_tags(tags: Array[Dictionary]) -> Array[Dictionary]:
	var nearest_first := tags.duplicate()
	nearest_first.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["metres"] < b["metres"])
	var merged: Array[Dictionary] = []
	for tag: Dictionary in nearest_first:
		var joined := false
		for group: Dictionary in merged:
			if group["at"].distance_to(tag["at"]) < MERGE_PIXELS:
				group["count"] += 1
				joined = true
				break
		if not joined:
			merged.append(tag.duplicate())
	return merged


static func tag_text(metres: float, count: int) -> String:
	var text := "STOWAWAY" if metres < CLOSE_M else "%d m" % roundi(metres)
	return text if count < 2 else "%s x%d" % [text, count]


func _draw_tag(tag: Dictionary, bob: float) -> void:
	var tip: Vector2 = tag["at"]
	var direction: Vector2 = tag["direction"]
	if not tag["pinned"]:
		tip.y += bob
	_draw_arrow(tip, direction)
	var center_x := clampf(tip.x, TAG_WIDTH * 0.5, size.x - TAG_WIDTH * 0.5)
	var label_y := tip.y - SIZE - 8.0 if direction.y >= 0.0 else tip.y + SIZE + 24.0
	var label_at := Vector2(center_x - TAG_WIDTH * 0.5, label_y)
	var text := tag_text(tag["metres"], tag["count"])
	var font := ThemeDB.fallback_font
	draw_string_outline(font, label_at, text, HORIZONTAL_ALIGNMENT_CENTER, TAG_WIDTH, TAG_FONT_SIZE, 6, COLOR_LINE)
	draw_string(font, label_at, text, HORIZONTAL_ALIGNMENT_CENTER, TAG_WIDTH, TAG_FONT_SIZE, COLOR_MARK)


func _draw_arrow(tip: Vector2, direction: Vector2) -> void:
	var side := direction.orthogonal()
	var back := tip - direction * SIZE * 1.5
	var points := PackedVector2Array([tip, back + side * SIZE, back - side * SIZE])
	var outline := PackedVector2Array([
		tip + direction * 5.0, back + side * (SIZE + 5.0) - direction * 3.0, back - side * (SIZE + 5.0) - direction * 3.0,
	])
	draw_colored_polygon(outline, COLOR_LINE)
	draw_colored_polygon(points, COLOR_MARK)

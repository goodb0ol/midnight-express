class_name Route
extends RefCounted
## The line the train runs on: a pure function of route_seed. Set pieces, blizzards and
## terrain height all come from here, so a peer needs only (route_seed, distance_m).
##
## Along-track coordinate "s" is in metres from the start of the line. A point at s sits
## at world z = distance_m - s, so ahead of the train is -z. Pieces are generated strictly
## in order from their own RNG and cached, so the answer never depends on who asked first.

enum Kind { TUNNEL, BRIDGE, STATION, WRECK, SKELETON, CUTTING, LAKE }

const SNAP_M := 48.0  ## Equals SceneryChunk.LENGTH: tunnels and bridges are chunk sections.
const FIRST_START_M := 288.0  ## About 10 s after departure.
## Start-to-start spacing: 20-40 s at 100 km/h.
const SPACING_MIN_M := 556.0
const SPACING_MAX_M := 1112.0
const BREATHER_M := 192.0  ## Open country kept after any set piece.
const MAJOR_KINDS: Array[Kind] = [Kind.TUNNEL, Kind.BRIDGE, Kind.STATION, Kind.WRECK, Kind.SKELETON]

const FLAT_HALF_WIDTH := 26.0  ## Inside this the land matches the flat collision conveyor.
const GORGE_DEPTH := 52.0
const LAKE_BED := 0.9  ## Below the flat ground.
const LAKE_RADIUS_X := 95.0
const TUNNEL_ROOF_M := 20.0  ## Rock above the rails at the tunnel crown.
const STATION_CLEAR_X := 34.0
const WRECK_CLEAR_X := 80.0
const SKELETON_CLEAR_X := 60.0

const BLIZZARD_FIRST_M := 820.0  ## About 30 s in.
const BLIZZARD_RAMP_M := 130.0
const BLIZZARD_GAP_MIN_M := 900.0
const BLIZZARD_GAP_MAX_M := 1700.0
const BLIZZARD_LENGTH_MIN_M := 420.0
const BLIZZARD_LENGTH_MAX_M := 760.0
## How far around the train's middle a tunnel counts as swallowing it.
const TUNNEL_MARGIN_M := 10.0


class Piece:
	extends RefCounted
	var kind: Kind
	var start_m: float
	var end_m: float
	var side: float  ## -1 or 1: the side of the track it stands on.

	func _init(new_kind: Kind, start: float, end: float, new_side: float) -> void:
		kind = new_kind
		start_m = start
		end_m = end
		side = new_side

	func mid_m() -> float:
		return (start_m + end_m) * 0.5

	func length_m() -> float:
		return end_m - start_m


var pieces: Array[Piece] = []  ## Sorted by start_m, major and scenic mixed.
var route_seed: int

var _rng := RandomNumberGenerator.new()
var _storm_rng := RandomNumberGenerator.new()
var _bag: Array[Kind] = []
var _last_kinds: Array[Kind] = []
var _next_start_m := FIRST_START_M
var _generated_to_m := 0.0
var _storms: PackedVector2Array = PackedVector2Array()  # x = start, y = end
var _next_storm_m := BLIZZARD_FIRST_M
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _ripple := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(new_seed: int) -> void:
	route_seed = new_seed
	_rng.seed = hash([new_seed, "route"])
	_storm_rng.seed = hash([new_seed, "storms"])
	_setup_noise(_hills, new_seed, 0.0055)
	_setup_noise(_ridges, new_seed + 1, 0.0034)
	_setup_noise(_ripple, new_seed + 2, 0.085)
	_setup_noise(_forest, new_seed + 3, 0.0042)


func _setup_noise(noise: FastNoiseLite, new_seed: int, frequency: float) -> void:
	noise.seed = new_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3


## Every piece overlapping [from_m, to_m], in order.
func pieces_between(from_m: float, to_m: float) -> Array[Piece]:
	_extend(to_m)
	var result: Array[Piece] = []
	for piece in pieces:
		if piece.start_m > to_m:
			break
		if piece.end_m >= from_m:
			result.append(piece)
	return result


## The major piece covering s, or null.
func major_at(s: float) -> Piece:
	for piece in pieces_between(s, s):
		if piece.kind in MAJOR_KINDS:
			return piece
	return null


## True while the middle of the train is under rock.
func in_tunnel(distance: float) -> bool:
	for piece in pieces_between(distance - TUNNEL_MARGIN_M, distance + TUNNEL_MARGIN_M):
		if piece.kind == Kind.TUNNEL:
			return distance >= piece.start_m - TUNNEL_MARGIN_M and distance <= piece.end_m + TUNNEL_MARGIN_M
	return false


## 0..1 storm strength at this point of the line.
func blizzard_at(s: float) -> float:
	_extend_storms(s + BLIZZARD_RAMP_M)
	for i in _storms.size():
		var storm := _storms[i]
		if s >= storm.x and s <= storm.y:
			return smoothstep(storm.x, storm.x + BLIZZARD_RAMP_M, s) * (1.0 - smoothstep(storm.y - BLIZZARD_RAMP_M, storm.y, s))
	return 0.0


## Visual height of the land. Inside FLAT_HALF_WIDTH it stays on the collision plane apart
## from tiny drifts, unless a piece says otherwise. [param near] is pieces_between around s.
func height(x: float, s: float, near: Array[Piece]) -> float:
	var ground := Treadmill.GROUND_Y
	var ax := absf(x)
	var broad := clampf(0.5 + 0.8 * _hills.get_noise_2d(x, s), 0.0, 1.0)
	var ridge := 1.0 - clampf(absf(_ridges.get_noise_2d(x, s)) * 1.7, 0.0, 1.0)
	var rise := smoothstep(FLAT_HALF_WIDTH, 78.0, ax)
	var far := smoothstep(120.0, 380.0, ax)
	var hills := rise * (5.0 + 30.0 * broad + 42.0 * ridge * ridge * ridge)
	hills += far * (60.0 + 150.0 * ridge * ridge * ridge * ridge)
	for piece in near:
		var clear_x := _clear_width(piece)
		if clear_x > 0.0:
			var along := smoothstep(piece.start_m - 70.0, piece.start_m, s) * (1.0 - smoothstep(piece.end_m, piece.end_m + 70.0, s))
			hills *= lerpf(1.0, smoothstep(clear_x, clear_x + 60.0, ax), along)
	var h := ground + hills + 0.26 * smoothstep(4.0, 10.0, ax) * _ripple.get_noise_2d(x, s)
	for piece in near:
		match piece.kind:
			Kind.LAKE:
				var dx := (x - lake_center_x(piece)) / LAKE_RADIUS_X
				var ds := (s - piece.mid_m()) / (piece.length_m() * 0.5)
				var inside := 1.0 - smoothstep(0.84, 1.0, sqrt(dx * dx + ds * ds))
				h = lerpf(h, ground - LAKE_BED, inside)
			Kind.CUTTING:
				var along := smoothstep(piece.start_m, piece.start_m + 50.0, s) * (1.0 - smoothstep(piece.end_m - 50.0, piece.end_m, s))
				var wall := ground + 8.0 + 11.0 * broad + 0.08 * ax
				h = maxf(h, lerpf(ground, wall, along * smoothstep(12.0, 20.0, ax)))
			Kind.TUNNEL:
				var narrow := smoothstep(piece.start_m, piece.start_m + 7.9, s) * (1.0 - smoothstep(piece.end_m - 7.9, piece.end_m, s))
				var wide := smoothstep(piece.start_m - 90.0, piece.start_m - 4.0, s) * (1.0 - smoothstep(piece.end_m + 4.0, piece.end_m + 90.0, s))
				var mix := lerpf(narrow, wide, smoothstep(7.0, 16.0, ax))
				var top := ground + TUNNEL_ROOF_M + 10.0 * broad + 0.25 * ax
				h = lerpf(h, maxf(h, top), mix)
			Kind.BRIDGE:
				var half := piece.length_m() * 0.5
				var wander := 26.0 * _hills.get_noise_2d(x * 0.5, 77.0) * smoothstep(12.0, 110.0, ax)
				var off := absf(s - piece.mid_m() + wander)
				var gorge := 1.0 - smoothstep(half - 46.0, half - 3.0, off)
				var floor_y := ground - GORGE_DEPTH + 1.6 * _ripple.get_noise_2d(x * 0.3, s * 0.3)
				h = lerpf(h, floor_y, gorge)
	return h


## Forest density at a point: positive inside a belt.
func forest_at(x: float, s: float) -> float:
	return _forest.get_noise_2d(x * 0.8, s) + 0.08


## Whether a set piece's footprint forbids ordinary scenery here.
func is_clear_zone(x: float, s: float, near: Array[Piece]) -> bool:
	for piece in near:
		var clear_x := _clear_width(piece)
		if clear_x > 0.0 and s >= piece.start_m - 12.0 and s <= piece.end_m + 12.0 and absf(x) < clear_x:
			return true
	return false


func lake_center_x(piece: Piece) -> float:
	return piece.side * (34.0 + LAKE_RADIUS_X)


func _clear_width(piece: Piece) -> float:
	match piece.kind:
		Kind.STATION:
			return STATION_CLEAR_X
		Kind.WRECK:
			return WRECK_CLEAR_X
		Kind.SKELETON:
			return SKELETON_CLEAR_X
	return 0.0


func _extend(to_m: float) -> void:
	while _generated_to_m < to_m:
		_add_next_major()


func _add_next_major() -> void:
	var kind := _draw_kind()
	var start := _next_start_m
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var length: float
	match kind:
		Kind.TUNNEL:
			length = SNAP_M * _rng.randi_range(8, 12)
		Kind.BRIDGE:
			length = SNAP_M * _rng.randi_range(6, 9)
		Kind.SKELETON:
			length = SNAP_M * 4.0
		_:
			length = SNAP_M * 3.0
	var piece := Piece.new(kind, start, start + length, side)
	pieces.append(piece)
	var spacing := _rng.randf_range(SPACING_MIN_M, SPACING_MAX_M)
	var next_start := snappedf(start + spacing, SNAP_M)
	next_start = maxf(next_start, ceilf((piece.end_m + BREATHER_M) / SNAP_M) * SNAP_M)
	_add_scenic(piece.end_m, next_start)
	_next_start_m = next_start
	_generated_to_m = next_start


## Lakes and cuttings fill the open stretch between two set pieces.
func _add_scenic(from_m: float, to_m: float) -> void:
	var room := to_m - from_m
	var roll := _rng.randf()
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	if room < 240.0 or roll < 0.25:
		return
	var margin := 40.0
	if roll < 0.65:
		pieces.append(Piece.new(Kind.LAKE, from_m + margin, to_m - margin, side))
	else:
		var length := minf(room - margin * 2.0, _rng.randf_range(150.0, 260.0))
		var start := from_m + (room - length) * 0.5
		pieces.append(Piece.new(Kind.CUTTING, start, start + length, side))


## Shuffled bag, so every kind turns up soon. The line opens with a tunnel, because going
## black ten seconds in is the loudest possible hello, and the same kind never repeats
## inside three pieces, which is what lets one pooled body serve each kind.
func _draw_kind() -> Kind:
	if pieces.is_empty():
		_last_kinds.append(Kind.TUNNEL)
		return Kind.TUNNEL
	var pick := _first_fresh_kind()
	if pick < 0:
		_refill_bag()
		pick = _first_fresh_kind()
	var kind: Kind = _bag[pick]
	_bag.remove_at(pick)
	_last_kinds.append(kind)
	if _last_kinds.size() > 2:
		_last_kinds.remove_at(0)
	return kind


func _first_fresh_kind() -> int:
	for i in _bag.size():
		if _bag[i] not in _last_kinds:
			return i
	return -1


func _refill_bag() -> void:
	_bag.assign(MAJOR_KINDS)
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held := _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = held


func _extend_storms(to_m: float) -> void:
	while _next_storm_m < to_m:
		var length := _storm_rng.randf_range(BLIZZARD_LENGTH_MIN_M, BLIZZARD_LENGTH_MAX_M)
		_storms.append(Vector2(_next_storm_m, _next_storm_m + length))
		_next_storm_m += length + _storm_rng.randf_range(BLIZZARD_GAP_MIN_M, BLIZZARD_GAP_MAX_M)

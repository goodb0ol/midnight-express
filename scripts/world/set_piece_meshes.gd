class_name SetPieceMeshes
## Every set piece model, built in code once at start-up from LowPoly boxes and cones.
## Local frame: y = 0 is the top of the flat ground, +x is the piece's side of the track,
## z is centred on the piece (sections run from z = 0 to z = -LENGTH like a chunk).

const STONE_A := Color(0.2, 0.2, 0.26)
const STONE_B := Color(0.27, 0.27, 0.33)
const SNOW := Color(0.8, 0.86, 0.98)
const TIMBER := Color(0.16, 0.11, 0.08)
const IRON := Color(0.09, 0.09, 0.11)
const BONE := Color(0.72, 0.76, 0.72)
const BONE_DARK := Color(0.43, 0.48, 0.5)
const LAMP := Color(1.0, 0.72, 0.32)
const WINDOW_LIT := Color(1.0, 0.76, 0.38)
const EMBER := Color(1.0, 0.36, 0.08)
const FIGURE := Color(0.035, 0.035, 0.06)

const TUNNEL_HALF_WIDTH := 4.4
const TUNNEL_CROWN := 7.6
## Half-section of the bore, from the rail level up to the crown.
const BORE: Array[Vector2] = [
	Vector2(4.4, -0.2), Vector2(4.4, 4.4), Vector2(3.4, 6.2), Vector2(1.7, 7.3), Vector2(0.0, 7.6),
]
const LAMP_SPACING := 16.0


## One lit length of bore. Walls are painted with their own light, so they read the same
## whatever the weather, and bands of lamplight strobe past the windows.
static func tunnel_section(length: float) -> LowPoly:
	var mesh := LowPoly.new()
	var band := 4.0
	var bands := int(length / band)
	for i in bands:
		var z0 := -float(i) * band
		var z1 := z0 - band
		var lamp_distance := absf(fposmod(z0 - band * 0.5, LAMP_SPACING) - LAMP_SPACING * 0.5)
		var lit := pow(1.0 - clampf(lamp_distance / (LAMP_SPACING * 0.5), 0.0, 1.0), 2.0)
		var rock := Color(0.02, 0.02, 0.03).lerp(Color(0.26, 0.15, 0.08), lit)
		if i % 3 == 0:
			rock = rock.darkened(0.2)
		for side: float in [-1.0, 1.0]:
			for p in BORE.size() - 1:
				var a := BORE[p]
				var b := BORE[p + 1]
				var inward := Vector3(-side * (a.x + b.x), 5.0 - (a.y + b.y), 0.0)
				mesh.quad(
					Vector3(side * a.x, a.y, z0), Vector3(side * b.x, b.y, z0),
					Vector3(side * b.x, b.y, z1), Vector3(side * a.x, a.y, z1),
					inward, rock.lightened(0.04 * p), true)
	var ribs := int(length / LAMP_SPACING)
	for i in ribs:
		var z := -LAMP_SPACING * (float(i) + 0.5)
		for side: float in [-1.0, 1.0]:
			# Timber set hugging the wall, then the lamp hanging from it.
			mesh.box(Vector3(0.3, 4.9, 0.4), Transform3D(Basis.IDENTITY, Vector3(side * 4.2, 2.3, z)), Color(0.09, 0.06, 0.04), true)
			mesh.box(Vector3(0.22, 0.34, 0.5), Transform3D(Basis.IDENTITY, Vector3(side * 4.08, 3.5, z)), LAMP, true)
		mesh.box(Vector3(7.4, 0.3, 0.4), Transform3D(Basis.IDENTITY, Vector3(0.0, 6.5, z)), Color(0.09, 0.06, 0.04), true)
	return mesh


## A carved stone face around the bore, at z = 0. Wide enough to dress the hill behind it.
static func tunnel_portal(rng: RandomNumberGenerator) -> LowPoly:
	var mesh := LowPoly.new()
	var course := 1.5
	for row in 11:
		var y := float(row) * course
		var x := -26.0 + (0.0 if row % 2 == 0 else 1.5)
		while x < 26.0:
			var width := rng.randf_range(2.2, 3.4)
			var center := x + width * 0.5
			var hole := absf(center) < TUNNEL_HALF_WIDTH + width * 0.5 - 0.3 and y < TUNNEL_CROWN - 0.4
			if not hole:
				var tone := STONE_A.lerp(STONE_B, rng.randf())
				mesh.box(Vector3(width - 0.05, course - 0.05, 2.0 + rng.randf() * 0.3), Transform3D(Basis.IDENTITY, Vector3(center, y + course * 0.5, 0.0)), tone)
			x += width
	# Heavy arch stones and a keystone, then a thick cap of snow.
	mesh.box(Vector3(1.0, TUNNEL_CROWN, 2.6), Transform3D(Basis.IDENTITY, Vector3(-TUNNEL_HALF_WIDTH - 0.5, TUNNEL_CROWN * 0.5, 0.0)), STONE_B.lightened(0.15))
	mesh.box(Vector3(1.0, TUNNEL_CROWN, 2.6), Transform3D(Basis.IDENTITY, Vector3(TUNNEL_HALF_WIDTH + 0.5, TUNNEL_CROWN * 0.5, 0.0)), STONE_B.lightened(0.15))
	mesh.box(Vector3(TUNNEL_HALF_WIDTH * 2.0 + 2.0, 1.2, 2.6), Transform3D(Basis.IDENTITY, Vector3(0.0, TUNNEL_CROWN + 0.6, 0.0)), STONE_B.lightened(0.15))
	mesh.box(Vector3(2.0, 2.4, 3.0), Transform3D(Basis.IDENTITY, Vector3(0.0, TUNNEL_CROWN + 1.0, 0.0)), STONE_B.lightened(0.3))
	mesh.box(Vector3(54.0, 0.7, 3.4), Transform3D(Basis.IDENTITY, Vector3(0.0, course * 11.0 + 0.3, 0.0)), SNOW)
	for side: float in [-1.0, 1.0]:
		mesh.box(Vector3(0.5, 0.5, 0.3), Transform3D(Basis.IDENTITY, Vector3(side * 5.4, 6.4, 1.4)), Color(1.0, 0.2, 0.1), true)
		mesh.box(Vector3(0.5, 0.5, 0.3), Transform3D(Basis.IDENTITY, Vector3(side * 5.4, 6.4, -1.4)), Color(1.0, 0.2, 0.1), true)
	return mesh


## One span of timber trestle under the track, down to the gorge floor.
static func bridge_section(length: float) -> LowPoly:
	var mesh := LowPoly.new()
	var depth := Route.GORGE_DEPTH + 6.0
	var bent_spacing := 16.0
	var bents := int(length / bent_spacing)
	var level := 11.0
	var levels := int(depth / level)
	var batter := 0.24
	var timber := Color(0.42, 0.33, 0.27)
	for i in bents:
		var z := -(float(i) + 0.5) * bent_spacing
		for side: float in [-1.0, 1.0]:
			for leg: float in [1.7, 3.0]:
				var foot := leg + depth * batter
				mesh.beam(Vector3(side * leg, -0.1, z), Vector3(side * foot, -depth, z), 0.7, timber)
		for l in levels:
			var y0 := -float(l) * level
			var y1 := y0 - level
			var w0 := 3.0 - y0 * batter
			var w1 := 3.0 - y1 * batter
			mesh.beam(Vector3(-w1, y1, z), Vector3(w1, y1, z), 0.5, timber.lightened(0.08))
			mesh.beam(Vector3(-w0, y0, z), Vector3(w1, y1, z), 0.34, timber)
			mesh.beam(Vector3(w0, y0, z), Vector3(-w1, y1, z), 0.34, timber)
			if l % 2 == 1:
				for side: float in [-1.0, 1.0]:
					mesh.beam(Vector3(side * w1, y1, z + bent_spacing * 0.5), Vector3(side * w1, y1, z - bent_spacing * 0.5), 0.42, timber)
	for side: float in [-1.0, 1.0]:
		# Deck stringers, a dusting of snow, and a thin rail so the drop reads from a window.
		mesh.box(Vector3(0.5, 0.9, length), Transform3D(Basis.IDENTITY, Vector3(side * 2.75, -0.35, -length * 0.5)), TIMBER)
		mesh.box(Vector3(0.55, 0.12, length), Transform3D(Basis.IDENTITY, Vector3(side * 2.75, 0.14, -length * 0.5)), SNOW)
		mesh.box(Vector3(0.1, 0.1, length), Transform3D(Basis.IDENTITY, Vector3(side * 2.95, 1.1, -length * 0.5)), IRON)
		var posts := int(length / 4.0)
		for p in posts:
			mesh.box(Vector3(0.12, 1.1, 0.12), Transform3D(Basis.IDENTITY, Vector3(side * 2.95, 0.6, -(float(p) + 0.5) * 4.0)), IRON)
	# Boulders and tiny frozen pines far below: nothing else tells the eye how deep it is.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 11:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * rng.randf_range(16.0, 60.0), -Route.GORGE_DEPTH + 1.0, -rng.randf() * length)
		if i % 3 == 0:
			mesh.blob(Vector3(rng.randf_range(2.0, 5.0), rng.randf_range(1.5, 4.0), rng.randf_range(2.0, 5.0)), Transform3D(Basis.IDENTITY, spot), SNOW.darkened(0.25), 3, 6)
		else:
			mesh.cone(1.6, 0.0, 6.0, 5, Transform3D(Basis.IDENTITY, spot), Color(0.05, 0.1, 0.11))
	return mesh


## Platform, hall, lamps and a crowd waiting for a train that does not stop.
static func station(length: float, rng: RandomNumberGenerator) -> Dictionary:
	var mesh := LowPoly.new()
	var boxes: Array[Array] = []  # [size, center]
	var half := length * 0.5
	var platform_y := 0.95
	var edge := 3.4
	var wall := 11.0
	_solid(mesh, boxes, Vector3(wall - edge, platform_y, length), Vector3((edge + wall) * 0.5, platform_y * 0.5, 0.0), STONE_B)
	mesh.box(Vector3(0.5, 0.06, length), Transform3D(Basis.IDENTITY, Vector3(edge + 0.3, platform_y + 0.03, 0.0)), Color(0.9, 0.72, 0.15))
	mesh.box(Vector3(wall - edge - 0.6, 0.05, length), Transform3D(Basis.IDENTITY, Vector3((edge + wall) * 0.5 + 0.3, platform_y + 0.02, 0.0)), Color(0.42, 0.42, 0.5))
	# The hall: long, dark, warm windows, snow on the roof.
	var hall_length := length * 0.6
	_solid(mesh, boxes, Vector3(8.0, 6.0, hall_length), Vector3(wall + 4.0, platform_y + 3.0, 0.0), Color(0.2, 0.13, 0.11))
	var roof_tilt := Basis(Vector3.BACK, 0.42)
	mesh.box(Vector3(10.0, 0.5, hall_length + 2.0), Transform3D(roof_tilt, Vector3(wall + 2.0, platform_y + 7.8, 0.0)), Color(0.18, 0.2, 0.26))
	mesh.box(Vector3(10.0, 0.25, hall_length + 2.0), Transform3D(roof_tilt, Vector3(wall + 2.0 - 0.1, platform_y + 8.1, 0.0)), SNOW)
	var window_z := -hall_length * 0.5 + 5.0
	while window_z < hall_length * 0.5 - 3.0:
		mesh.box(Vector3(0.1, 2.6, 3.0), Transform3D(Basis.IDENTITY, Vector3(wall - 0.04, platform_y + 2.2, window_z)), WINDOW_LIT, true)
		mesh.box(Vector3(0.14, 2.8, 0.2), Transform3D(Basis.IDENTITY, Vector3(wall - 0.06, platform_y + 2.2, window_z)), Color(0.1, 0.07, 0.05))
		window_z += 7.0
	# A canopy with a row of columns.
	mesh.box(Vector3(5.2, 0.25, hall_length), Transform3D(Basis.IDENTITY, Vector3(8.4, platform_y + 4.1, 0.0)), Color(0.16, 0.17, 0.22))
	mesh.box(Vector3(5.2, 0.2, hall_length), Transform3D(Basis.IDENTITY, Vector3(8.4, platform_y + 4.32, 0.0)), SNOW)
	var column_z := -hall_length * 0.5 + 6.0
	while column_z < hall_length * 0.5:
		_solid(mesh, boxes, Vector3(0.35, 4.1, 0.35), Vector3(6.3, platform_y + 2.05, column_z), IRON)
		column_z += 12.0
	# Lamps the whole length, each one a post you can hit at speed.
	var lamp_z := -half + 7.0
	while lamp_z < half:
		_solid(mesh, boxes, Vector3(0.24, 5.0, 0.24), Vector3(4.6, platform_y + 2.5, lamp_z), IRON)
		mesh.box(Vector3(1.3, 0.14, 0.14), Transform3D(Basis.IDENTITY, Vector3(4.2, platform_y + 5.0, lamp_z)), IRON)
		mesh.blob(Vector3(0.42, 0.42, 0.42), Transform3D(Basis.IDENTITY, Vector3(3.7, platform_y + 4.75, lamp_z)), LAMP, 3, 6, true)
		lamp_z += 18.0
	# The crowd: dark overcoats against the windows, a few with hats and luggage.
	for i in 46:
		var at := Vector3(rng.randf_range(4.9, 10.2), platform_y, rng.randf_range(-hall_length * 0.55, hall_length * 0.55))
		_figure(mesh, at, rng)
	# Far end of the platform: a low fence and a ramp of snow.
	for side: float in [-1.0, 1.0]:
		mesh.box(Vector3(wall - edge, 1.2, 0.3), Transform3D(Basis.IDENTITY, Vector3((edge + wall) * 0.5, platform_y + 0.6, side * half)), TIMBER)
	return {"mesh": mesh, "boxes": boxes}


static func _figure(mesh: LowPoly, at: Vector3, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(1.45, 1.85)
	var body := Basis(Vector3.UP, rng.randf() * TAU)
	mesh.cone(0.3, 0.16, height * 0.8, 5, Transform3D(body, at), FIGURE)
	var head := at + Vector3.UP * (height * 0.8 + 0.1)
	mesh.blob(Vector3(0.14, 0.15, 0.14), Transform3D(Basis.IDENTITY, head), FIGURE, 3, 5)
	var roll := rng.randf()
	if roll < 0.35:
		mesh.box(Vector3(0.46, 0.05, 0.46), Transform3D(body, head + Vector3.UP * 0.1), FIGURE)
		mesh.box(Vector3(0.24, 0.2, 0.24), Transform3D(body, head + Vector3.UP * 0.2), FIGURE)
	elif roll < 0.6:
		mesh.box(Vector3(0.58, 0.42, 0.22), Transform3D(body, at + body.x * 0.5 + Vector3.UP * 0.21), Color(0.07, 0.05, 0.04))


## A derailed train lying across the snow, still smouldering.
static func wreck(length: float, rng: RandomNumberGenerator) -> Dictionary:
	var mesh := LowPoly.new()
	var boxes: Array[Array] = []
	var half := length * 0.5
	# The locomotive, on its side, nose dug into a bank of snow.
	var loco_at := Vector3(12.5, 2.6, half - 26.0)
	var loco_basis := Basis(Vector3.UP, 0.42) * Basis(Vector3.BACK, 1.1) * Basis(Vector3.RIGHT, 0.12)
	var iron := Color(0.26, 0.27, 0.32)
	var trim := Color(0.8, 0.16, 0.1)
	mesh.cone(2.1, 2.1, 12.0, 9, Transform3D(loco_basis * Basis(Vector3.RIGHT, -PI * 0.5), loco_at + loco_basis * Vector3(0.0, 0.0, 6.0)), iron)
	mesh.cone(2.5, 1.5, 1.6, 9, Transform3D(loco_basis * Basis(Vector3.RIGHT, PI * 0.5), loco_at + loco_basis * Vector3(0.0, 0.0, 5.6)), trim)
	mesh.cone(1.3, 0.2, 2.4, 9, Transform3D(loco_basis * Basis(Vector3.RIGHT, PI * 0.5), loco_at + loco_basis * Vector3(0.0, -1.8, 6.6)), trim.darkened(0.3))
	mesh.cone(0.7, 1.1, 3.2, 7, Transform3D(loco_basis, loco_at + loco_basis * Vector3(0.0, 1.8, 3.0)), iron.darkened(0.35))
	mesh.box(Vector3(4.6, 4.6, 5.0), Transform3D(loco_basis, loco_at + loco_basis * Vector3(0.0, 0.9, -8.0)), Color(0.42, 0.12, 0.1))
	mesh.box(Vector3(5.0, 0.3, 5.6), Transform3D(loco_basis, loco_at + loco_basis * Vector3(0.0, 3.3, -8.0)), SNOW)
	for w in 3:
		for wheel_side: float in [-1.0, 1.0]:
			var offset := Vector3(wheel_side * 2.3, -2.2, -3.4 + w * 3.2)
			mesh.cone(1.5, 1.5, 0.35, 12, Transform3D(loco_basis * Basis(Vector3.BACK, PI * 0.5), loco_at + loco_basis * offset), trim)
	mesh.blob(Vector3(6.0, 1.3, 4.5), Transform3D(Basis.IDENTITY, loco_at + Vector3(0.0, -2.6, 12.0)), SNOW, 3, 8)
	boxes.append([Vector3(6.0, 5.0, 16.0), loco_at, Basis(Vector3.UP, 0.42)])
	# Carriages scattered behind it: one flat, one on its side, one rearing out of the snow.
	var yaw := 0.5
	var at := Vector3(20.0, 2.2, half - 48.0)
	for i in 4:
		yaw += rng.randf_range(-0.8, 0.8)
		var roll := rng.randf_range(-0.3, 0.3) + (1.3 if i % 2 == 0 else 0.0)
		var pitch := 0.55 if i == 2 else rng.randf_range(-0.1, 0.2)
		var car := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch)
		var color := Color(0.62, 0.2, 0.16) if i % 2 == 0 else Color(0.26, 0.4, 0.46)
		mesh.box(Vector3(3.0, 3.0, 15.0), Transform3D(car, at), color)
		mesh.box(Vector3(3.4, 0.34, 15.5), Transform3D(car, at + car * Vector3(0.0, 1.65, 0.0)), Color(0.2, 0.2, 0.24))
		mesh.box(Vector3(2.6, 0.2, 15.0), Transform3D(car, at + car * Vector3(0.0, 1.9, 0.0)), SNOW)
		for w in 4:
			var side := -1.0 if w % 2 == 0 else 1.0
			mesh.box(Vector3(0.06, 1.0, 1.3), Transform3D(car, at + car * Vector3(side * 1.53, 0.3, -5.0 + w * 3.2)), WINDOW_LIT.darkened(0.3), true)
		for bogie: float in [-5.0, 5.0]:
			mesh.box(Vector3(2.4, 0.9, 2.4), Transform3D(car, at + car * Vector3(0.0, -1.9, bogie)), IRON)
		if at.x < 26.0:
			boxes.append([Vector3(3.4, 3.4, 15.0), at, car])
		at += Vector3(rng.randf_range(1.0, 7.0), 0.0, -rng.randf_range(17.0, 21.0))
	# Fires and scattered wreckage. The lights are in the set piece, only while on screen.
	for i in 7:
		var spot := Vector3(rng.randf_range(10.0, 34.0), 0.0, rng.randf_range(-half + 8.0, half - 8.0))
		mesh.blob(Vector3(1.6, 0.5, 1.6), Transform3D(Basis.IDENTITY, spot), Color(0.05, 0.04, 0.04), 3, 6)
		mesh.cone(0.7, 0.0, rng.randf_range(1.4, 3.0), 5, Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.2), EMBER, true)
		mesh.cone(0.35, 0.0, rng.randf_range(0.9, 1.6), 5, Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.2), Color(1.0, 0.8, 0.3), true)
	for i in 16:
		var spot := Vector3(rng.randf_range(7.0, 44.0), 0.3, rng.randf_range(-half, half))
		var tumble := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU)
		mesh.box(Vector3(rng.randf_range(0.5, 2.4), 0.2, rng.randf_range(0.6, 3.5)), Transform3D(tumble, spot), Color(0.14, 0.09, 0.08))
	return {"mesh": mesh, "boxes": boxes}


## Something enormous died here. The rails run straight through its ribcage.
static func skeleton(length: float, rng: RandomNumberGenerator) -> Dictionary:
	var mesh := LowPoly.new()
	var boxes: Array[Array] = []
	var half := length * 0.5
	var spine_height := 21.0
	var rib_width := 13.0
	var ribs := 15
	var spine_start := half - 34.0
	var spine_step := 8.0
	for r in ribs:
		var z := spine_start - float(r) * spine_step
		var scale_factor := 1.0 - absf(float(r) - 5.0) / 18.0
		var rib_x := rib_width * scale_factor
		var rib_y := spine_height
		for side: float in [-1.0, 1.0]:
			var broken := rng.randf() < 0.18 and r > 2
			var steps := 5 if broken else 9
			var last := Vector3(0.0, rib_y, z)
			for i in range(1, steps + 1):
				var t := float(i) / 9.0
				var angle := t * PI * 0.56
				var point := Vector3(side * sin(angle) * rib_x * 1.05, rib_y * cos(angle) + 1.0, z + t * 3.0)
				var width := lerpf(1.5, 0.75, t)
				mesh.beam(last, point, width, BONE if i % 2 == 0 else BONE.darkened(0.08))
				last = point
			if not broken:
				var foot := Vector3(last.x, 0.0, last.z)
				mesh.beam(last, foot, 0.8, BONE_DARK)
				boxes.append([Vector3(1.4, 7.0, 1.4), foot + Vector3.UP * 3.5, Basis.IDENTITY])
		# One vertebra per rib, with a spike along the back.
		mesh.blob(Vector3(2.3, 1.7, 3.0), Transform3D(Basis.IDENTITY, Vector3(0.0, spine_height + 0.6, z)), BONE, 3, 7)
		mesh.cone(1.2, 0.0, 5.2 * scale_factor, 5, Transform3D(Basis.IDENTITY, Vector3(0.0, spine_height + 1.6, z)), BONE_DARK)
	# The neck dips forward and away from the rails, the skull resting in the snow.
	var neck := Vector3(0.0, spine_height, spine_start + spine_step)
	var skull_at := Vector3(24.0, 6.0, half - 10.0)
	var segments := 8
	for i in segments:
		var t := float(i + 1) / segments
		var point := neck.lerp(skull_at, t)
		point.y += sin(t * PI) * 4.0
		mesh.blob(Vector3(2.0, 1.6, 2.0).lerp(Vector3(1.4, 1.2, 1.4), t), Transform3D(Basis.IDENTITY, point), BONE, 3, 6)
	var look := Basis(Vector3.UP, -PI * 0.5 - 0.5) * Basis(Vector3.RIGHT, 0.2)
	mesh.blob(Vector3(6.5, 5.0, 8.0), Transform3D(look, skull_at), BONE, 4, 8)
	mesh.blob(Vector3(4.2, 2.2, 8.0), Transform3D(look, skull_at + look * Vector3(0.0, -2.0, 7.0)), BONE.darkened(0.06), 3, 7)
	mesh.blob(Vector3(3.8, 1.2, 7.0), Transform3D(look, skull_at + look * Vector3(0.0, -5.2, 5.0)), BONE_DARK, 3, 7)
	for side: float in [-1.0, 1.0]:
		var socket := skull_at + look * Vector3(side * 4.3, 1.4, 3.8)
		mesh.blob(Vector3(1.8, 1.9, 1.9), Transform3D(look, socket), Color(0.02, 0.02, 0.04), 3, 6)
		mesh.blob(Vector3(0.6, 0.6, 0.6), Transform3D(look, socket + look * Vector3(side * 0.9, 0.0, 0.8)), Color(0.35, 0.85, 1.0), 3, 5, true)
		var horn := Transform3D(look * Basis(Vector3.BACK, -side * 0.7) * Basis(Vector3.RIGHT, -0.8), skull_at + look * Vector3(side * 3.8, 3.8, -2.0))
		mesh.cone(1.7, 0.0, 15.0, 6, horn, BONE_DARK)
		for tooth in 6:
			var fang := Transform3D(look * Basis(Vector3.RIGHT, PI), skull_at + look * Vector3(side * (3.4 - tooth * 0.4), -3.3, 8.5 + tooth * 0.85))
			mesh.cone(0.5, 0.0, 2.6, 4, fang, BONE)
	boxes.append([Vector3(11.0, 10.0, 16.0), skull_at, look])
	# The tail wanders off behind it, half sunk.
	var tail := Vector3(0.0, spine_height, spine_start - float(ribs) * spine_step)
	for i in 12:
		var t := float(i) / 12.0
		var point := tail + Vector3(sin(t * 3.0) * 9.0 * t, -spine_height * t * 1.02, -t * 30.0)
		mesh.blob(Vector3.ONE * lerpf(2.0, 0.7, t), Transform3D(Basis.IDENTITY, point), BONE, 3, 6)
	# Ice crusting the bones where they meet the ground.
	for i in 12:
		var spot := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-half, half))
		if absf(spot.x) > 4.5:
			mesh.blob(Vector3(rng.randf_range(2.0, 5.0), 0.8, rng.randf_range(2.0, 5.0)), Transform3D(Basis.IDENTITY, spot), SNOW, 3, 6)
	return {"mesh": mesh, "boxes": boxes}


## Adds a box to the model and to the list of colliders.
static func _solid(mesh: LowPoly, boxes: Array[Array], size: Vector3, center: Vector3, color: Color) -> void:
	mesh.box(size, Transform3D(Basis.IDENTITY, center), color)
	boxes.append([size, center, Basis.IDENTITY])


## A forest conifer, about 9 m tall. Snow on the shoulders so belts read at night.
static func pine() -> LowPoly:
	var mesh := LowPoly.new()
	mesh.cone(0.3, 0.2, 1.4, 5, Transform3D.IDENTITY, Color(0.1, 0.07, 0.06))
	var green := Color(0.075, 0.15, 0.15)
	var snow := Color(0.72, 0.8, 0.94)
	mesh.cone(2.5, 0.8, 3.2, 6, Transform3D(Basis.IDENTITY, Vector3.UP * 1.1), green)
	mesh.cone(1.95, 0.55, 3.0, 6, Transform3D(Basis.IDENTITY, Vector3.UP * 3.4), green.lightened(0.05))
	mesh.cone(1.4, 0.3, 2.6, 6, Transform3D(Basis.IDENTITY, Vector3.UP * 5.4), green.lerp(snow, 0.45))
	mesh.cone(0.75, 0.0, 2.4, 6, Transform3D(Basis.IDENTITY, Vector3.UP * 7.2), snow)
	return mesh

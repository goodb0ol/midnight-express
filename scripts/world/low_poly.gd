class_name LowPoly
extends RefCounted
## Builds flat-shaded, vertex-coloured meshes in code. Everything goes into at most two
## surfaces, one lit and one self-lit, so a whole set piece costs two draw calls.

static var _lit_material: StandardMaterial3D
static var _glow_material: StandardMaterial3D

class Surface:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()


var _lit := Surface.new()
var _glow := Surface.new()


static func lit_material() -> StandardMaterial3D:
	if _lit_material == null:
		_lit_material = StandardMaterial3D.new()
		_lit_material.vertex_color_use_as_albedo = true
		_lit_material.vertex_color_is_srgb = true
		_lit_material.roughness = 0.95
		_lit_material.metallic_specular = 0.2
	return _lit_material


## Unshaded and a little over-bright, so lamps and embers catch the environment glow.
static func glow_material() -> StandardMaterial3D:
	if _glow_material == null:
		_glow_material = StandardMaterial3D.new()
		_glow_material.vertex_color_use_as_albedo = true
		_glow_material.vertex_color_is_srgb = true
		_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_material.albedo_color = Color(1.5, 1.5, 1.5)
	return _glow_material


func tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color, glow := false) -> void:
	var normal := (c - a).cross(b - a)
	if normal.dot(outward) < 0.0:
		var held := b
		b = c
		c = held
		normal = -normal
	normal = normal.normalized()
	var target: Surface = _glow if glow else _lit
	target.verts.append(a)
	target.verts.append(b)
	target.verts.append(c)
	for i in 3:
		target.normals.append(normal)
		target.colors.append(color)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color, glow := false) -> void:
	tri(a, b, c, outward, color, glow)
	tri(a, c, d, outward, color, glow)


func box(size: Vector3, xform: Transform3D, color: Color, glow := false) -> void:
	var half := size * 0.5
	var corner := func(x: float, y: float, z: float) -> Vector3:
		return xform * Vector3(x * half.x, y * half.y, z * half.z)
	var right: Vector3 = xform.basis.x
	var up: Vector3 = xform.basis.y
	var back: Vector3 = xform.basis.z
	quad(corner.call(1, -1, -1), corner.call(1, 1, -1), corner.call(1, 1, 1), corner.call(1, -1, 1), right, color, glow)
	quad(corner.call(-1, -1, -1), corner.call(-1, 1, -1), corner.call(-1, 1, 1), corner.call(-1, -1, 1), -right, color, glow)
	quad(corner.call(-1, 1, -1), corner.call(1, 1, -1), corner.call(1, 1, 1), corner.call(-1, 1, 1), up, color, glow)
	quad(corner.call(-1, -1, -1), corner.call(1, -1, -1), corner.call(1, -1, 1), corner.call(-1, -1, 1), -up, color, glow)
	quad(corner.call(-1, -1, 1), corner.call(1, -1, 1), corner.call(1, 1, 1), corner.call(-1, 1, 1), back, color, glow)
	quad(corner.call(-1, -1, -1), corner.call(1, -1, -1), corner.call(1, 1, -1), corner.call(-1, 1, -1), -back, color, glow)


## A square timber or bone from a to b.
func beam(a: Vector3, b: Vector3, width: float, color: Color, glow := false) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var z := along / length
	var hint := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := hint.cross(z).normalized()
	var y := z.cross(x)
	box(Vector3(width, width, length), Transform3D(Basis(x, y, z), (a + b) * 0.5), color, glow)


## A many-sided cone or tube. Base at the origin of [param xform], pointing along its +Y.
func cone(bottom_radius: float, top_radius: float, height: float, sides: int, xform: Transform3D, color: Color, glow := false) -> void:
	var center := xform * Vector3(0.0, height * 0.5, 0.0)
	var top_center := xform * Vector3(0.0, height, 0.0)
	var bottom_center := xform.origin
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var b0 := xform * Vector3(cos(a0) * bottom_radius, 0.0, sin(a0) * bottom_radius)
		var b1 := xform * Vector3(cos(a1) * bottom_radius, 0.0, sin(a1) * bottom_radius)
		var t0 := xform * Vector3(cos(a0) * top_radius, height, sin(a0) * top_radius)
		var t1 := xform * Vector3(cos(a1) * top_radius, height, sin(a1) * top_radius)
		var outward := (b0 + b1 + t0 + t1) * 0.25 - center
		if top_radius > 0.001:
			quad(b0, b1, t1, t0, outward, color, glow)
			tri(t0, t1, top_center, top_center - center, color, glow)
		else:
			tri(b0, b1, top_center, outward, color, glow)
		tri(b0, b1, bottom_center, bottom_center - center, color, glow)


## Rough rock or skull: a squashed sphere of flat facets.
func blob(radius: Vector3, xform: Transform3D, color: Color, rings := 4, sides := 7, glow := false) -> void:
	var center := xform.origin
	var point := func(ring: int, side: int) -> Vector3:
		var lat := PI * float(ring) / rings - PI * 0.5
		var lon := TAU * float(side) / sides
		return xform * Vector3(cos(lat) * cos(lon) * radius.x, sin(lat) * radius.y, cos(lat) * sin(lon) * radius.z)
	for ring in rings:
		for side in sides:
			var a: Vector3 = point.call(ring, side)
			var b: Vector3 = point.call(ring, side + 1)
			var c: Vector3 = point.call(ring + 1, side + 1)
			var d: Vector3 = point.call(ring + 1, side)
			quad(a, b, c, d, (a + c) * 0.5 - center, color, glow)


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_commit(mesh, _lit, lit_material())
	_commit(mesh, _glow, glow_material())
	return mesh


func vertex_count() -> int:
	return _lit.verts.size() + _glow.verts.size()


func _commit(mesh: ArrayMesh, source: Surface, material: Material) -> void:
	if source.verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = source.verts
	arrays[Mesh.ARRAY_NORMAL] = source.normals
	arrays[Mesh.ARRAY_COLOR] = source.colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

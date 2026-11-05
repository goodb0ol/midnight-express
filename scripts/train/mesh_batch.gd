class_name MeshBatch
extends RefCounted
## Merges many primitive pieces into one ArrayMesh (one surface per material), so a
## whole carriage or tree costs a handful of draw calls on mobile.

var _tools: Dictionary = {}  # Material -> SurfaceTool
var _unit_box: BoxMesh


func _init() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE


func add_box(size: Vector3, center: Vector3, material: Material, rotation := Basis.IDENTITY) -> void:
	add_mesh(_unit_box, Transform3D(rotation * Basis.from_scale(size), center), material)


func add_mesh(mesh: Mesh, xform: Transform3D, material: Material) -> void:
	var tool: SurfaceTool = _tools.get(material)
	if tool == null:
		tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[material] = tool
	tool.append_from(mesh, 0, xform)


func build() -> ArrayMesh:
	var merged := ArrayMesh.new()
	for material: Material in _tools:
		var tool: SurfaceTool = _tools[material]
		tool.commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, material)
	return merged


## Flat-shaded material helper; the same colour always returns the same instance so
## batches and auto-instancing can share it.
static func flat(color: Color, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), emission_energy]
	if _palette.has(key):
		return _palette[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	_palette[key] = material
	return material


static var _palette: Dictionary = {}

class_name Models
## Loads meshes from the Blender-built .glb files in assets/models.
## Source scripts live in blender/, the visual contract in docs/ART_BRIEF.md.

const ROOT := "res://assets/models/"

static var _cache: Dictionary = {}  # path -> {node name -> Mesh}


## All meshes in a model file, by Blender object name.
static func all(file: String) -> Dictionary:
	if _cache.has(file):
		return _cache[file]
	var scene: PackedScene = load(ROOT + file + ".glb")
	var meshes: Dictionary = {}
	var root := scene.instantiate()
	_collect(root, meshes)
	root.free()
	_cache[file] = meshes
	return meshes


## One mesh. With no [param object], the first mesh in the file.
static func mesh(file: String, object := "") -> Mesh:
	var meshes := all(file)
	if object.is_empty():
		return meshes.values()[0]
	return meshes[object]


## New MeshInstance3D at [param at] under [param parent].
static func place(parent: Node3D, file: String, object: String, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh(file, object)
	instance.position = at
	parent.add_child(instance)
	return instance


static func _collect(node: Node, meshes: Dictionary) -> void:
	if node is MeshInstance3D:
		meshes[String(node.name)] = (node as MeshInstance3D).mesh
	for child in node.get_children():
		_collect(child, meshes)

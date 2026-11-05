class_name TrainOpening
extends Node3D
## A door or window that can be opened. The sliding panel is the solid part; a thin
## use volume stays in the hole so the crosshair still finds an open door to close it.

enum Kind { DOOR, WINDOW }

const SLIDE_SECONDS := 0.45

var kind := Kind.DOOR
var is_open := false

var _panel: AnimatableBody3D
var _closed_position := Vector3.ZERO
var _open_position := Vector3.ZERO
var _progress := 0.0


func setup(opening_kind: Kind, size: Vector3, open_offset: Vector3, material: Material) -> void:
	kind = opening_kind
	_open_position = open_offset

	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.sync_to_physics = false
	_panel.collision_layer = Layers.HULL
	_panel.collision_mask = 0
	_panel.set_meta(&"interactable", self)
	add_child(_panel)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_panel.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh.mesh = box_mesh
	_panel.add_child(mesh)

	var volume := Area3D.new()
	volume.name = "UseVolume"
	volume.collision_layer = Layers.USE_VOLUME
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_meta(&"interactable", self)
	var volume_shape := CollisionShape3D.new()
	var volume_box := BoxShape3D.new()
	# Fill the hole but stay thin along the slide-free axis.
	var thin := size
	thin[_thin_axis(size)] = 0.3
	volume_box.size = thin
	volume_shape.shape = volume_box
	volume.add_child(volume_shape)
	add_child(volume)

	set_physics_process(false)


func interact(_by: Node3D) -> void:
	set_open(not is_open)


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	set_physics_process(true)
	GameEvents.opening_toggled.emit(self, is_open)


func get_prompt() -> String:
	var noun := "door" if kind == Kind.DOOR else "window"
	return ("Close " if is_open else "Open ") + noun


func _physics_process(delta: float) -> void:
	var goal := 1.0 if is_open else 0.0
	_progress = move_toward(_progress, goal, delta / SLIDE_SECONDS)
	_panel.position = _closed_position.lerp(_open_position, ease(_progress, -2.0))
	if is_equal_approx(_progress, goal):
		set_physics_process(false)


static func _thin_axis(size: Vector3) -> int:
	return size.min_axis_index()

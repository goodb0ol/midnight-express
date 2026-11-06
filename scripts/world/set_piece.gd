class_name SetPiece
extends AnimatableBody3D
## One pooled landmark: a mesh, its colliders and a few lamps. Exactly one body exists per
## kind (Route never repeats a kind close enough to need two), and it scrolls from
## distance_m exactly as a SceneryChunk does.

var piece: Route.Piece = null
var _collidable := false


func _init(physics: PhysicsMaterial) -> void:
	sync_to_physics = false
	collision_layer = 0
	collision_mask = 0
	physics_material_override = physics
	visible = false


func add_model(mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## [param entry] is [size, center, optional Basis].
func add_box_collider(entry: Array) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = entry[0]
	shape.shape = box
	shape.position = entry[1]
	if entry.size() > 2:
		shape.basis = entry[2]
	add_child(shape)


func add_lamp(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = false
	add_child(lamp)


## Claims the body for a piece, moving it there without sweeping through the world.
func assign(new_piece: Route.Piece, distance: float) -> void:
	piece = new_piece
	collision_layer = 0
	_collidable = false
	# Built for the +x side; turning it round keeps its face toward the rails.
	basis = Basis.IDENTITY if piece.side > 0.0 else Basis(Vector3.UP, PI)
	position.z = distance - piece.mid_m()
	visible = true
	reset_physics_interpolation()


func retire() -> void:
	piece = null
	visible = false
	collision_layer = 0
	_collidable = false


func place(distance: float, collide_ahead: float, collide_behind: float) -> void:
	position.z = distance - piece.mid_m()
	var half := piece.length_m() * 0.5
	var should_collide := position.z > -collide_ahead - half and position.z < collide_behind + half
	if should_collide != _collidable:
		_collidable = should_collide
		collision_layer = Layers.SCENERY if should_collide else 0

extends MeshInstance3D
## Bright spinning diamond above a stowaway, standing or knocked out. It draws through
## walls so a player can spot the target from the next car. One mesh and one material are
## shared by every marker.

const BOB_HEIGHT := 0.1
const BOB_RATE := 5.0
const SPIN_RATE := 3.2
const COLOR := Color(1.0, 0.86, 0.1)

static var _mesh: SphereMesh
static var _material: StandardMaterial3D

## Node to follow. Marker must be its child, so it is freed with it.
var target: Node3D
var height := 2.3


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mesh == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = COLOR
		_material.no_depth_test = true
		_material.render_priority = 1
		_mesh = SphereMesh.new()
		_mesh.radius = 0.17
		_mesh.height = 0.5
		_mesh.radial_segments = 4
		_mesh.rings = 2
		_mesh.material = _material
	mesh = _mesh


func _process(delta: float) -> void:
	var bob := sin(Time.get_ticks_msec() * 0.001 * BOB_RATE) * BOB_HEIGHT
	global_position = target.global_position + Vector3.UP * (height + bob)
	rotate_y(SPIN_RATE * delta)

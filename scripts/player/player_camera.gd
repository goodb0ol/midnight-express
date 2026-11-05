class_name PlayerCamera
extends Camera3D
## Local-only view. Runs at render rate: position follows the physics-interpolated body,
## look comes straight from the input source, so mouse aim never waits for a tick.

const FOV_BASE := 82.0
const SHAKE_DECAY := 5.0
const RATTLE := 0.0035        ## Metres of constant train rattle at full speed.
const DRAGGED_SHAKE := 0.11

var player: Player
var input: PlayerInputSource

var _shake := 0.0
var _fov_punch := 0.0
var _fist: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = FOV_BASE
	near = 0.05
	far = 2600.0
	current = true
	player.shake_requested.connect(add_shake)
	player.hands.swung.connect(_on_swung)
	player.hands.threw.connect(_on_threw)

	_fist = MeshInstance3D.new()
	_fist.name = "Fist"
	var box := BoxMesh.new()
	box.size = Vector3(0.11, 0.11, 0.2)
	box.material = MeshBatch.flat(Color(0.86, 0.68, 0.55))
	_fist.mesh = box
	_fist.visible = false
	add_child(_fist)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _on_swung(hit: bool) -> void:
	if hit:
		add_shake(0.09)
		_fov_punch = -3.0


func _on_threw(fraction: float) -> void:
	add_shake(0.03 + fraction * 0.05)
	_fov_punch = 2.0 + fraction * 4.0


func _process(delta: float) -> void:
	var origin := player.get_global_transform_interpolated().origin + Vector3.UP * Player.EYE_HEIGHT
	var speed_ratio := clampf(TrainState.speed_mps / YeetTuning.FULL_SPEED, 0.0, 1.2)
	var time := Time.get_ticks_msec() * 0.001
	var offset := Vector3.ZERO
	var roll := 0.0
	if player.is_aboard():
		offset.y = sin(time * 37.0) * RATTLE * speed_ratio
		roll = sin(time * 1.3) * 0.004 * speed_ratio
	else:
		_shake = maxf(_shake, DRAGGED_SHAKE * speed_ratio)
	if _shake > 0.001:
		offset += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake * 0.3
		roll += _rng.randf_range(-1.0, 1.0) * _shake * 0.08
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-SHAKE_DECAY * delta))
	global_transform = Transform3D(Basis.from_euler(Vector3(input.pitch, input.yaw, roll)), origin + offset)
	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-9.0 * delta))
	fov = FOV_BASE + _fov_punch

	var swing := player.hands.swing_amount()
	_fist.visible = swing > 0.0 and player.hands.held == null
	_fist.position = Vector3(0.24, -0.22, -0.42 - swing * 0.4)

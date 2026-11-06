class_name PlayerCamera
extends Camera3D
## Local-only view. Runs at render rate: position follows the physics-interpolated body,
## look comes straight from the input source, so mouse aim never waits for a tick.
## Everything here is decoration on top of that aim: kicks, leans, zooms and overlays
## never reach Player or Hands. The "slow motion" moments are this camera's, the
## simulation keeps its speed and the player keeps control.

const FOV_BASE := 82.0
const SHAKE_DECAY := 5.0
const RATTLE := 0.0035        ## Metres of constant train rattle at full speed.
const DRAGGED_SHAKE := 0.11

const KICK_STIFFNESS := 190.0 ## Spring back to centre after a kick; 1/s^2.
const KICK_DAMPING := 17.0    ## Low enough to overshoot once, which reads as weight.
const NEAR_IMPACT_RANGE := 9.0
const SPRINT_LEAN := 0.055    ## Radians forward at a run.
const SPRINT_FOV := 7.0
const STRAFE_LEAN := 0.045    ## Radians of roll at a full-speed strafe.
const BOB_RATE := 1.75        ## Radians of bob per metre walked.
const BOB_HEIGHT := 0.022
const CHARGE_PULL_BACK := 0.26 ## Metres. Stays inside the capsule, so it can't clip a wall.
const CHARGE_FOV := 15.0
const DRAG_ROLL := 0.05       ## Radians of roll with the body's sway.
const DRAG_DIP := 0.07        ## Metres the head sinks under the weight.
const MOMENT_SECONDS := 0.5   ## Length of the zoom after a knockout.
const MOMENT_FOV := 14.0
const YEET_SECONDS := 0.9     ## Length of the zoom when your own heave goes overboard.
const YEET_FOV := 20.0
const THROW_MEMORY := 1.5     ## A yeet this soon after a throw counts as yours.

var player: Player
var input: PlayerInputSource

var _shake := 0.0
var _fov_punch := 0.0
var _fist: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _kick := Vector3.ZERO        ## Pitch, yaw, roll offset in radians.
var _kick_velocity := Vector3.ZERO
var _kick_side := 1.0
var _lean := 0.0
var _strafe := 0.0
var _bob_phase := 0.0
var _bob_amount := 0.0
var _smooth_charge := 0.0
var _smooth_sway := 0.0
var _drag_weight := 0.0
var _moment := 0.0
var _yeet_moment := 0.0
var _since_throw := INF
var _overlay: ColorRect
var _overlay_material: ShaderMaterial
var _fx: ImpactFx


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
	GameEvents.npc_knocked_out.connect(_on_npc_knocked_out)
	GameEvents.object_yeeted.connect(_on_object_yeeted)
	GameEvents.impact.connect(_on_impact)

	_fist = Models.place(self, "props/hand", "", Vector3.ZERO)
	_fist.name = "Fist"
	_fist.visible = false
	_build_overlay()

	_fx = ImpactFx.new()
	_fx.name = "ImpactFx"
	add_child(_fx)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Knocks the view; the spring brings it back. x is pitch, y yaw, z roll, in rad/s.
func kick(impulse: Vector3) -> void:
	_kick_velocity += impulse


func _on_swung(hit: bool) -> void:
	_kick_side = -_kick_side
	if hit:
		add_shake(0.26)
		_fov_punch = -7.0
		kick(Vector3(-2.6, 0.5 * _kick_side, 1.5 * _kick_side))
	else:
		kick(Vector3(-0.9, 0.25 * _kick_side, 0.5 * _kick_side))


func _on_threw(fraction: float) -> void:
	_since_throw = 0.0
	add_shake(0.05 + fraction * 0.16)
	_fov_punch = 4.0 + fraction * 12.0
	kick(Vector3(-1.0 - fraction * 2.8, 0.0, 0.7 * _kick_side))


func _on_npc_knocked_out(_npc: Node3D, _ragdoll: Node3D, attacker: Node3D) -> void:
	if attacker == player:
		_moment = 1.0
		add_shake(0.4)


func _on_object_yeeted(body: Node3D) -> void:
	if body != player and _since_throw < THROW_MEMORY:
		_yeet_moment = 1.0


func _on_impact(_body: Node3D, at: Vector3, speed: float) -> void:
	var distance := at.distance_to(global_position)
	if distance < NEAR_IMPACT_RANGE:
		add_shake(clampf(speed * 0.012, 0.0, 0.2) * (1.0 - distance / NEAR_IMPACT_RANGE))


func _process(delta: float) -> void:
	var hands := player.hands
	var step := minf(delta, 1.0 / 30.0)
	_tick_kick(step)
	_since_throw += delta
	_moment = maxf(_moment - delta / MOMENT_SECONDS, 0.0)
	_yeet_moment = maxf(_yeet_moment - delta / YEET_SECONDS, 0.0)
	_smooth_charge = lerpf(_smooth_charge, hands.charge_fraction(), 1.0 - exp(-16.0 * delta))
	_drag_weight = lerpf(_drag_weight, 1.0 if hands.is_dragging() else 0.0, 1.0 - exp(-7.0 * delta))
	_smooth_sway = lerpf(_smooth_sway, hands.drag_sway(), 1.0 - exp(-10.0 * delta))

	var origin := player.get_global_transform_interpolated().origin + Vector3.UP * Player.EYE_HEIGHT
	var speed_ratio := clampf(TrainState.speed_mps / YeetTuning.FULL_SPEED, 0.0, 1.2)
	var time := Time.get_ticks_msec() * 0.001
	var offset := Vector3.ZERO
	var roll := _kick.z
	var pitch_offset := _kick.x
	var sprint_amount := 0.0
	if player.is_aboard():
		offset.y = sin(time * 37.0) * RATTLE * speed_ratio
		roll += sin(time * 1.3) * 0.004 * speed_ratio
		sprint_amount = _tick_walk(delta)
		offset.y += sin(_bob_phase * 2.0) * BOB_HEIGHT * _bob_amount
		offset.y -= DRAG_DIP * _drag_weight
		roll += _strafe + _smooth_sway * DRAG_ROLL * _drag_weight
		pitch_offset -= _lean
		# The whole view follows the arm through wind-up and strike.
		pitch_offset -= hands.swing_amount() * 0.035
	else:
		_shake = maxf(_shake, DRAGGED_SHAKE * speed_ratio)
	if _shake > 0.001:
		offset += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake * 0.3
		roll += _rng.randf_range(-1.0, 1.0) * _shake * 0.08
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-SHAKE_DECAY * delta))
	var view := Basis.from_euler(Vector3(input.pitch + pitch_offset, input.yaw + _kick.y, roll))
	offset += view * Vector3(0.0, -0.04, CHARGE_PULL_BACK) * _smooth_charge
	global_transform = Transform3D(view, origin + offset)

	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-9.0 * delta))
	fov = FOV_BASE + _fov_punch + sprint_amount * SPRINT_FOV + _smooth_charge * CHARGE_FOV
	fov -= ease(_moment, 0.5) * MOMENT_FOV + ease(_yeet_moment, 0.5) * YEET_FOV
	_update_overlay()
	_update_fist(hands)
	_fx.show_assist(hands.assist_point, delta)


func _tick_kick(step: float) -> void:
	_kick_velocity += (-_kick * KICK_STIFFNESS - _kick_velocity * KICK_DAMPING) * step
	_kick += _kick_velocity * step


## Lean, strafe roll and head bob. Returns how much of a sprint is showing, 0 to 1.
func _tick_walk(delta: float) -> float:
	var local := player.global_basis.inverse() * player.velocity
	var flat_speed: float = Vector2(local.x, local.z).length()
	var running: bool = player.sprinting and flat_speed > Player.WALK_SPEED * 0.6
	var sharpness := 1.0 - exp(-8.0 * delta)
	_lean = lerpf(_lean, SPRINT_LEAN if running else 0.0, sharpness)
	_strafe = lerpf(_strafe, -local.x / Player.SPRINT_SPEED * STRAFE_LEAN, sharpness)
	_bob_phase += flat_speed * BOB_RATE * delta
	var bob_goal := clampf(flat_speed / Player.WALK_SPEED, 0.0, 1.6) * (1.0 + _drag_weight * 2.5)
	_bob_amount = lerpf(_bob_amount, bob_goal if player.is_on_floor() else 0.0, sharpness)
	return _lean / SPRINT_LEAN


func _update_fist(hands: Hands) -> void:
	var swing := hands.swing_amount()
	if hands.is_dragging():
		# A straining arm out to the body, jerking with each step.
		_fist.visible = true
		_fist.position = Vector3(0.24 + _smooth_sway * 0.05, -0.3, -0.5 - swing * 0.35 + _smooth_charge * 0.22)
		_fist.rotation = Vector3(0.0, 0.0, _smooth_sway * 0.2)
		return
	_fist.visible = hands.is_swinging() and hands.held == null
	# Back past the ear on the wind-up, then a hook across the view on the strike.
	var windup := maxf(-swing, 0.0)
	var strike := maxf(swing, 0.0)
	_fist.position = Vector3(0.3 - strike * 0.26 + windup * 0.08, -0.22 + windup * 0.12 + strike * 0.06, -0.42 + windup * 0.24 - strike * 0.5)
	_fist.rotation = Vector3(windup * 0.7 - strike * 0.5, windup * -0.6 + strike * 0.7, strike * -0.5)


## --- Screen overlay: a vignette with comic speed lines ----------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FeelOverlay"
	add_child(layer)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float lines = 0.0;
uniform vec3 tint = vec3(1.0, 0.7, 0.2);

void fragment() {
	vec2 from_center = (UV - 0.5) * vec2(1.0, 0.72);
	float edge = smoothstep(0.32, 0.72, length(from_center));
	float angle = atan(from_center.y, from_center.x);
	float slice = floor(angle * 26.0);
	float seed = fract(sin(slice * 12.9898) * 43758.5453);
	float flicker = step(0.62, fract(seed + floor(TIME * 18.0) * 0.37));
	float streak = flicker * smoothstep(0.26 + seed * 0.14, 0.62, length(from_center));
	COLOR = vec4(tint, clamp(edge * amount + streak * lines, 0.0, 0.85));
}
"""
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = shader
	_overlay = ColorRect.new()
	_overlay.name = "Vignette"
	_overlay.material = _overlay_material
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	layer.add_child(_overlay)


func _update_overlay() -> void:
	var flash := maxf(_moment, _yeet_moment)
	var strength := maxf(_smooth_charge * 0.65, flash * 0.6)
	_overlay.visible = strength > 0.01
	if not _overlay.visible:
		return
	var tint := Color(1.0, 0.62, 0.15).lerp(Color(1.0, 0.95, 0.8), flash)
	_overlay_material.set_shader_parameter(&"amount", strength)
	_overlay_material.set_shader_parameter(&"lines", maxf(_smooth_charge * _smooth_charge * 0.42, flash * 0.4))
	_overlay_material.set_shader_parameter(&"tint", Vector3(tint.r, tint.g, tint.b))

class_name Weather
extends Node
## Child of Treadmill. Owns the mood: deep night under a huge moon, aurora, blizzard bursts
## and the blackout in tunnels. Storms come from Route, so they are a pure function of
## distance_m and every peer sees the same one. Fog is depth-based, starting past the
## train, so the carriages stay readable while everything outside whites out.

const CLEAR_FOG_BEGIN := 90.0
const CLEAR_FOG_END := 900.0
const CLEAR_FOG_COLOR := Color(0.055, 0.085, 0.17)
const STORM_FOG_BEGIN := 14.0
const STORM_FOG_END := 140.0
const STORM_FOG_COLOR := Color(0.42, 0.47, 0.58)
const TUNNEL_FOG_COLOR := Color(0.012, 0.01, 0.012)
const CLEAR_AMBIENT := Color(0.34, 0.43, 0.68)
const STORM_AMBIENT := Color(0.46, 0.5, 0.6)
const CLEAR_AMBIENT_ENERGY := 0.82
const STORM_AMBIENT_ENERGY := 0.8
const TUNNEL_AMBIENT_ENERGY := 0.42
const MOON_ENERGY := 1.5
const MOON_STORM_ENERGY := 0.28
## Low and well off to the side, to fill the left windows and the rear platform.
const MOON_ROTATION := Vector3(-31.0, -62.0, 0.0)
const TUNNEL_FADE_SECONDS := 0.16
const FLASH_SPACING_M := 170.0
const FLASH_LENGTH_M := 16.0

var route: Route

var _environment: Environment
var _moon: DirectionalLight3D
var _dark := 0.0
var _aurora: ShaderMaterial
var _aurora_node: MeshInstance3D


func _ready() -> void:
	var root := get_parent().get_parent()
	var world := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		_environment = world.environment
	_moon = root.get_node_or_null("Moon") as DirectionalLight3D
	if _moon != null:
		_moon.rotation_degrees = MOON_ROTATION
		_moon.light_color = Color(0.72, 0.8, 1.0)
	if _environment != null:
		_build_sky()
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.fog_mode = Environment.FOG_MODE_DEPTH
		_environment.fog_density = 1.0
		_environment.fog_depth_curve = 1.0
		_environment.glow_enabled = true
		_environment.glow_intensity = 0.7
		_environment.glow_bloom = 0.02
		_environment.glow_hdr_threshold = 1.0
	_build_aurora()
	_apply(0.0, 0.0)


func _physics_process(_delta: float) -> void:
	TrainState.blizzard = route.blizzard_at(TrainState.distance_m)


func _process(delta: float) -> void:
	var target := 1.0 if TrainState.in_tunnel else 0.0
	_dark = move_toward(_dark, target, delta / TUNNEL_FADE_SECONDS)
	_apply(TrainState.blizzard, _lightning(TrainState.visual_distance()))


## 0..1 white flash, only inside a strong storm. Bucketed on distance so peers agree.
func _lightning(distance: float) -> float:
	if TrainState.blizzard < 0.55:
		return 0.0
	var bucket := floori(distance / FLASH_SPACING_M)
	if posmod(hash([route.route_seed, bucket]), 3) != 0:
		return 0.0
	var into := distance - bucket * FLASH_SPACING_M
	if into > FLASH_LENGTH_M:
		return 0.0
	var flicker := 0.65 + 0.35 * cos(into * 1.7)
	return flicker * (1.0 - into / FLASH_LENGTH_M)


func _apply(storm: float, flash: float) -> void:
	# Mountains and sky stay visible right up until the storm has properly closed in.
	var thick := smoothstep(0.0, 0.8, storm) * (1.0 - _dark)
	var open := 1.0 - _dark
	if _environment != null:
		var fog := CLEAR_FOG_COLOR.lerp(STORM_FOG_COLOR, thick).lerp(TUNNEL_FOG_COLOR, _dark)
		_environment.fog_light_color = fog.lerp(Color(0.85, 0.9, 1.0), flash * open)
		_environment.fog_depth_begin = lerpf(CLEAR_FOG_BEGIN, STORM_FOG_BEGIN, thick)
		_environment.fog_depth_end = lerpf(CLEAR_FOG_END, STORM_FOG_END, thick)
		_environment.fog_sky_affect = lerpf(0.0, 1.0, thick)
		_environment.ambient_light_color = CLEAR_AMBIENT.lerp(STORM_AMBIENT, thick)
		var ambient := lerpf(CLEAR_AMBIENT_ENERGY, STORM_AMBIENT_ENERGY, thick)
		_environment.ambient_light_energy = lerpf(ambient, TUNNEL_AMBIENT_ENERGY, _dark) + flash * 2.0 * open
	if _moon != null:
		_moon.light_energy = lerpf(MOON_ENERGY, MOON_STORM_ENERGY, thick) * open + flash * 2.0 * open
	if _aurora != null:
		_aurora.set_shader_parameter(&"strength", (1.0 - thick))


func _build_sky() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/world/night_sky.gdshader")
	var to_moon := Vector3.BACK
	if _moon != null:
		to_moon = _moon.basis.z.normalized()
	material.set_shader_parameter(&"moon_direction", to_moon)
	var sky := _environment.sky
	if sky == null:
		sky = Sky.new()
		_environment.sky = sky
	sky.sky_material = material


## One long ribbon wrapped round the far sky. The curtain ripple is all in the vertex
## shader, so it costs one draw call and no updates.
func _build_aurora() -> void:
	_aurora = ShaderMaterial.new()
	_aurora.shader = load("res://scripts/world/aurora.gdshader")
	var ribbon := PlaneMesh.new()
	ribbon.size = Vector2(1.0, 1.0)
	ribbon.subdivide_width = 96
	ribbon.subdivide_depth = 1
	ribbon.orientation = PlaneMesh.FACE_Y
	ribbon.material = _aurora
	_aurora_node = MeshInstance3D.new()
	_aurora_node.name = "Aurora"
	_aurora_node.mesh = ribbon
	_aurora_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aurora_node.custom_aabb = AABB(Vector3(-2000.0, -2000.0, -2000.0), Vector3(4000.0, 4000.0, 4000.0))
	add_child(_aurora_node)

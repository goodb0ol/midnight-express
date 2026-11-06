class_name RaidStrike
extends Node
## What the raid does to the train when the clock runs out. The emergency brake throws
## everyone down the car, the cars strobe red, and a fine is stamped in the air over each
## stowaway it caught. RoundDirector calls hit() on the host and clear() on the next raid.

const SLAM_SPEED := 7.0        ## m/s thrown forward along the car.
const SLAM_LIFT := 2.2
const TIPS_PER_TICK := 2       ## Spread over a few ticks: it reads as a wave and costs less.
const SHAKE := 0.45
const KICK := Vector3(-3.5, 0.0, 2.0)
const LAMP_HEIGHT := 2.3
const LAMP_RANGE := 15.0
const LAMP_ENERGY := 7.0
const STROBE_HZ := 2.5
const STAMP_HEIGHT := 2.0
const STAMP_COLOR := Color(1.0, 0.16, 0.1)
const CARS: Array[StringName] = [&"Bistro", &"Coach", &"Locomotive"]

var active := false
var stamps: Array[Label3D] = []
var lamps: Array[OmniLight3D] = []

var _to_tip: Array[Node] = []
var _braked := false
var _kmh_before := 0.0
var _strobe := 0.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	GameEvents.round_ended.connect(_on_round_ended)


func _exit_tree() -> void:
	if _braked:
		TrainState.speed_mps = _kmh_before / TrainState.KMH_PER_MPS
	_release_brake()


func hit(main: Main, caught: Array[Node3D], fine: int) -> void:
	active = true
	_to_tip = main.npc_bodies().duplicate()
	_kmh_before = TrainState.target_speed_mps * TrainState.KMH_PER_MPS
	_braked = true
	TrainState.set_target_kmh(0.0)
	_throw_loose_bodies(main)
	_light_up(main)
	for body in caught:
		_stamp(body, fine)
	main.jolt_local_camera(SHAKE, KICK)
	_strobe = 0.0
	set_process(true)
	set_physics_process(true)


func clear() -> void:
	active = false
	_to_tip.clear()
	_release_brake()
	for stamp in stamps:
		stamp.queue_free()
	stamps.clear()
	for lamp in lamps:
		lamp.queue_free()
	lamps.clear()
	set_process(false)
	set_physics_process(false)


func _release_brake() -> void:
	if _braked:
		_braked = false
		TrainState.set_target_kmh(_kmh_before)


func _throw_loose_bodies(main: Main) -> void:
	var slam := Vector3.FORWARD * SLAM_SPEED + Vector3.UP * SLAM_LIFT
	for prop in main.prop_bodies():
		if prop is RigidBody3D and not prop.freeze and prop.global_position.y > Treadmill.GROUND_Y + 1.0:
			prop.apply_central_impulse(slam * prop.mass)
	for body in main.npc_bodies():
		if body is Ragdoll and not body.off_train and body.holder == null:
			for part in body.parts:
				part.apply_central_impulse(slam * part.mass)


func _light_up(main: Main) -> void:
	for id in CARS:
		var lamp := OmniLight3D.new()
		lamp.name = "RaidLamp%s" % id
		lamp.light_color = STAMP_COLOR
		lamp.omni_range = LAMP_RANGE
		lamp.omni_attenuation = 0.6
		lamp.light_energy = LAMP_ENERGY
		add_child(lamp)
		lamp.global_position = main.train.car_by_id(id).position + Vector3.UP * LAMP_HEIGHT
		lamps.append(lamp)


func _stamp(body: Node3D, fine: int) -> void:
	var stamp := Label3D.new()
	stamp.text = "FINED\n-%d" % fine
	stamp.modulate = STAMP_COLOR
	stamp.outline_modulate = Color(0.08, 0.0, 0.0)
	stamp.font_size = 96
	stamp.outline_size = 28
	stamp.pixel_size = 0.0012
	stamp.fixed_size = true
	stamp.no_depth_test = true
	stamp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(stamp)
	stamp.global_position = _body_point(body) + Vector3.UP * STAMP_HEIGHT
	stamp.scale = Vector3.ONE * 2.2
	stamp.create_tween().tween_property(stamp, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stamps.append(stamp)


## Stamps ignore depth, so they would float through the results screen.
func _on_round_ended(_score: int, _passed: bool) -> void:
	for stamp in stamps:
		stamp.visible = false


static func _body_point(body: Node3D) -> Vector3:
	return body.anchor() if body is Ragdoll else body.global_position


## Everyone still standing goes over, a couple a tick.
func _physics_process(_delta: float) -> void:
	for i in TIPS_PER_TICK:
		if _to_tip.is_empty():
			set_physics_process(false)
			return
		# Untyped: anyone queued can be freed mid-wave, bowled over by a slammed body.
		var body: Variant = _to_tip.pop_back()
		if is_instance_valid(body) and body is TestDummy:
			body.tip_over(Vector3.FORWARD, SLAM_SPEED, null)


func _process(delta: float) -> void:
	_strobe += delta
	var energy := LAMP_ENERGY * (0.15 + 0.85 * pow(0.5 + 0.5 * sin(_strobe * TAU * STROBE_HZ), 2.0))
	for lamp in lamps:
		lamp.light_energy = energy

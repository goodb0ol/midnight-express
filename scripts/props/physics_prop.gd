class_name PhysicsProp
extends RigidBody3D
## Any loose rigid object: coal, suitcases, tools. Built from PropCatalog.

const INSIDE_MASK := Layers.HULL | Layers.GROUND | Layers.SCENERY | Layers.PLAYER | Layers.PROP | Layers.RAGDOLL | Layers.NPC

var kind: StringName
var label := "prop"
var is_tool := false
var bonk_power := 1
var holder: Hands = null
var off_train := false

var _thrower: Node3D = null
var _thrown_direction := Vector3.FORWARD
var _thrown_time := 0.0
var _off_train_time := 0.0
var _bounces_left := 0
var _rng := RandomNumberGenerator.new()
var _watch_left := 0.0
var _impact_wait := 0.0
var _scenery_wait := 0.0
var _pre_velocity := Vector3.ZERO


static func create(prop_kind: StringName) -> PhysicsProp:
	var prop := PhysicsProp.new()
	prop._configure(prop_kind)
	return prop


func _configure(prop_kind: StringName) -> void:
	kind = prop_kind
	var def: Dictionary = PropCatalog.DEFS[prop_kind]
	name = String(prop_kind)
	label = def["label"]
	mass = def["mass"]
	bonk_power = def["bonk"]
	is_tool = def.get("tool", false)
	collision_layer = Layers.PROP
	collision_mask = INSIDE_MASK
	continuous_cd = is_tool
	var physics := PhysicsMaterial.new()
	physics.friction = 0.7
	physics.bounce = 0.15
	physics_material_override = physics

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = def["size"]
	shape.shape = box
	add_child(shape)

	Models.place(self, "props/" + String(prop_kind), "", Vector3.ZERO)


func _ready() -> void:
	set_physics_process(false)
	_rng.seed = TrainState.next_seed()
	contact_monitor = false
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


## Called by Hands. Holding switches gravity off so the hold drive stays smooth.
func grabbed_by(hands: Hands) -> void:
	holder = hands
	gravity_scale = 0.0
	angular_damp = 8.0
	sleeping = false
	_watch_contacts(INF)


func released() -> void:
	holder = null
	gravity_scale = 1.0
	angular_damp = 0.0
	_watch_left = YeetTuning.WATCH_AFTER_HOLD


## Contact reports cost, so they run only while this prop can do something funny.
func _watch_contacts(seconds: float) -> void:
	_watch_left = maxf(_watch_left, seconds)
	_pre_velocity = linear_velocity
	contact_monitor = true
	set_physics_process(true)


## After a hard throw, the first hit on a bonkable target counts as a bonk.
func arm_thrown(thrower: Node3D) -> void:
	if linear_velocity.length() < YeetTuning.THROWN_BONK_SPEED:
		return
	_thrower = thrower
	_thrown_direction = linear_velocity.normalized()
	_thrown_time = 1.5
	continuous_cd = true
	_watch_contacts(YeetTuning.WATCH_AFTER_THROW)


## Half the largest dimension: how much further out Hands must hold this prop.
func get_extent() -> float:
	var size: Vector3 = PropCatalog.DEFS[kind]["size"]
	return size[size.max_axis_index()] * 0.5


## Bat it across the carriage. A prop hit hard enough becomes a thrown prop, so a good
## swing at the coal can knock a passenger over.
func receive_bonk(power: int, direction: Vector3, attacker: Node3D) -> void:
	sleeping = false
	linear_velocity += (direction * (6.0 + power * 3.0) + Vector3.UP * 2.0) * clampf(sqrt(6.0 / mass), 0.45, 1.4)
	angular_velocity += Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0))
	if attacker != null:
		arm_thrown(attacker)


func yeet_anchor() -> Vector3:
	return global_position


func is_off_train() -> bool:
	return off_train


func on_left_train() -> void:
	if off_train:
		return
	off_train = true
	if holder != null:
		holder.force_release()
	collision_mask = Layers.OUTSIDE_MASK
	continuous_cd = true
	can_sleep = false
	linear_damp = 0.0
	var speed := TrainState.speed_mps
	linear_velocity += YeetTuning.snatch_velocity(speed, signf(global_position.x))
	angular_velocity += YeetTuning.random_spin(_rng, speed)
	_bounces_left = YeetTuning.GROUND_BOUNCES if speed > 1.0 else 0
	_watch_contacts(0.0)
	GameEvents.object_yeeted.emit(self)


func _physics_process(delta: float) -> void:
	_impact_wait -= delta
	_scenery_wait -= delta
	if _thrown_time > 0.0:
		_thrown_time -= delta
		if _thrown_time <= 0.0:
			continuous_cd = is_tool or off_train
	if off_train:
		_tick_outside(delta)
	else:
		_watch_left -= delta
		if _watch_left <= 0.0 and _thrown_time <= 0.0:
			contact_monitor = false
			set_physics_process(false)
	_pre_velocity = linear_velocity


func _tick_outside(delta: float) -> void:
	var air_gap := TrainState.ground_velocity() - linear_velocity
	apply_central_force(air_gap * YeetTuning.WIND_RATE * mass)
	if _bounces_left > 0 and global_position.y < Treadmill.GROUND_Y + 0.5 and linear_velocity.y < -0.5:
		linear_velocity.y = YeetTuning.hop_speed(_bounces_left, TrainState.speed_mps)
		angular_velocity = YeetTuning.tumble_spin(_rng, TrainState.speed_mps - linear_velocity.z)
		_bounces_left -= 1
	if TrainState.speed_mps > 0.5:
		_off_train_time += delta
	if global_position.z > YeetTuning.DESPAWN_Z or global_position.y < YeetTuning.DESPAWN_Y or _off_train_time > YeetTuning.MAX_LIFETIME:
		GameEvents.object_despawned.emit(self)
		queue_free()


func _on_body_entered(body: Node) -> void:
	var speed := (_pre_velocity - YeetTuning.surface_velocity(body)).length()
	if _thrown_time > 0.0 and body.has_method("receive_bonk") and not body is PhysicsProp:
		body.call("receive_bonk", bonk_power, _thrown_direction, _thrower)
		_thrown_time = 0.0
		_impact_wait = 0.0
	if speed < YeetTuning.IMPACT_MIN_SPEED:
		return
	if _impact_wait <= 0.0:
		_impact_wait = YeetTuning.IMPACT_COOLDOWN
		GameEvents.impact.emit(self, global_position, speed)
	if off_train and YeetTuning.is_scenery(body) and _scenery_wait <= 0.0:
		_scenery_wait = YeetTuning.SCENERY_COOLDOWN
		GameEvents.body_hit_scenery.emit(self, speed)

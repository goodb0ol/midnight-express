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

	var parts: Array = def.get("parts", [[def["size"], Vector3.ZERO, def["color"]]])
	var batch := MeshBatch.new()
	for part: Array in parts:
		batch.add_box(part[0], part[1], MeshBatch.flat(part[2]))
	var mesh := MeshInstance3D.new()
	mesh.mesh = batch.build()
	add_child(mesh)


func _ready() -> void:
	set_physics_process(false)
	_rng.seed = hash([name, get_instance_id()])
	contact_monitor = false
	body_entered.connect(_on_body_entered)


## Called by Hands. Holding switches gravity off so the hold drive stays smooth.
func grabbed_by(hands: Hands) -> void:
	holder = hands
	gravity_scale = 0.0
	angular_damp = 8.0
	sleeping = false


func released() -> void:
	holder = null
	gravity_scale = 1.0
	angular_damp = 0.0


## After a hard throw, the first hit on a bonkable target counts as a bonk.
func arm_thrown(thrower: Node3D) -> void:
	if linear_velocity.length() < YeetTuning.THROWN_BONK_SPEED:
		return
	_thrower = thrower
	_thrown_direction = linear_velocity.normalized()
	_thrown_time = 1.5
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	set_physics_process(true)


## Half the largest dimension: how much further out Hands must hold this prop.
func get_extent() -> float:
	var size: Vector3 = PropCatalog.DEFS[kind]["size"]
	return size[size.max_axis_index()] * 0.5


func receive_bonk(power: int, direction: Vector3, _attacker: Node3D) -> void:
	apply_central_impulse(direction * (3.0 + power * 2.0))


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
	set_physics_process(true)
	GameEvents.object_yeeted.emit(self)


func _physics_process(delta: float) -> void:
	if _thrown_time > 0.0:
		_thrown_time -= delta
		if _thrown_time <= 0.0:
			contact_monitor = false
			continuous_cd = is_tool or off_train
			if not off_train:
				set_physics_process(false)
	if off_train:
		_tick_outside(delta)


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
	if _thrown_time <= 0.0 or not body.has_method("receive_bonk") or body is PhysicsProp:
		return
	body.call("receive_bonk", bonk_power, _thrown_direction, _thrower)
	_thrown_time = 0.0

class_name Ragdoll
extends Node3D
## A knocked-out body: one rigid body per limb, jointed from BodyPlan.

const INSIDE_MASK := Layers.HULL | Layers.GROUND | Layers.SCENERY | Layers.PROP | Layers.NPC
const INSIDE_ANGULAR_DAMP := 3.0
const OUTSIDE_ANGULAR_DAMP := 0.3

var parts: Array[RagdollPart] = []
var pelvis: RagdollPart
var chest: RagdollPart
var holder: Hands = null
var off_train := false

var _bounces_left := 0
var _off_train_time := 0.0
var _rng := RandomNumberGenerator.new()
var _physics_material: PhysicsMaterial


## Replaces a standing dummy at [param origin] with a ragdoll moving at [param velocity].
static func spawn(parent: Node, origin: Transform3D, palette: Dictionary, velocity: Vector3) -> Ragdoll:
	var ragdoll := Ragdoll.new()
	ragdoll.name = "Ragdoll"
	parent.add_child(ragdoll)
	ragdoll._build(origin, palette, velocity)
	return ragdoll


func _ready() -> void:
	set_physics_process(false)
	_rng.seed = get_instance_id()


func _build(origin: Transform3D, palette: Dictionary, velocity: Vector3) -> void:
	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = 0.8
	_physics_material.bounce = 0.2
	var by_name: Dictionary = {}
	for part_name: StringName in BodyPlan.PARTS:
		var def: Dictionary = BodyPlan.PARTS[part_name]
		var part := _make_part(part_name, def, origin, palette)
		part.linear_velocity = velocity
		by_name[part_name] = part
	pelvis = by_name[&"pelvis"]
	chest = by_name[&"chest"]
	for joint_def: Dictionary in BodyPlan.JOINTS:
		_make_joint(joint_def, by_name, origin)


func _make_part(part_name: StringName, def: Dictionary, origin: Transform3D, palette: Dictionary) -> RagdollPart:
	var part := RagdollPart.new()
	part.name = String(part_name)
	part.ragdoll = self
	part.part_name = part_name
	part.mass = def["mass"]
	part.collision_layer = Layers.RAGDOLL
	part.collision_mask = INSIDE_MASK
	part.physics_material_override = _physics_material
	part.angular_damp = INSIDE_ANGULAR_DAMP
	part.linear_damp = 0.15
	var size: Vector3 = def["size"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	part.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = MeshBatch.flat(palette[def["tint"]])
	mesh.mesh = box_mesh
	part.add_child(mesh)
	var position_in_dummy: Vector3 = def["pos"]
	part.transform = origin * Transform3D(Basis.IDENTITY, position_in_dummy)
	add_child(part)
	parts.append(part)
	if part_name == &"head":
		BodyPlan.add_face(part, "x_x")
	return part


func _make_joint(joint_def: Dictionary, by_name: Dictionary, origin: Transform3D) -> void:
	var part_a: RagdollPart = by_name[joint_def["a"]]
	var part_b: RagdollPart = by_name[joint_def["b"]]
	var at: Vector3 = joint_def["at"]
	var joint: Joint3D
	var basis := Basis.IDENTITY
	if joint_def["kind"] == &"cone":
		var cone := ConeTwistJoint3D.new()
		cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(joint_def["swing"]))
		cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(joint_def["twist"]))
		# Cone axis is the joint's local X; aim it along the child bone.
		var along: Vector3 = joint_def["dir"]
		basis = Basis(Quaternion(Vector3.RIGHT, along))
		joint = cone
	else:
		var hinge := HingeJoint3D.new()
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(joint_def["low"]))
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(joint_def["high"]))
		# Hinge axis is the joint's local Z; aim it across the body.
		basis = Basis(Vector3.UP, PI * 0.5)
		joint = hinge
	joint.exclude_nodes_from_collision = true
	joint.transform = origin * Transform3D(basis, at)
	add_child(joint)
	joint.node_a = joint.get_path_to(part_a)
	joint.node_b = joint.get_path_to(part_b)


## Hit the snow hard: hop back up and cartwheel. The spin goes on as a whole-body
## rotation (each limb also gets the velocity of its orbit around the centre of mass),
## otherwise every limb would spin on its own axis and fight the joints.
func _tick_tumble() -> void:
	if _bounces_left <= 0:
		return
	var center := Vector3.ZERO
	var center_velocity := Vector3.ZERO
	for part in parts:
		center += part.global_position * part.mass
		center_velocity += part.linear_velocity * part.mass
	var mass_sum := total_mass()
	center /= mass_sum
	center_velocity /= mass_sum
	if center.y > Treadmill.GROUND_Y + 0.55 or center_velocity.y > -0.3:
		return
	var hop := YeetTuning.hop_speed(_bounces_left, TrainState.speed_mps)
	var spin := YeetTuning.tumble_spin(_rng, TrainState.speed_mps - center_velocity.z)
	_bounces_left -= 1
	for part in parts:
		var orbit := spin.cross(part.global_position - center)
		part.linear_velocity = Vector3(center_velocity.x, hop, center_velocity.z) + orbit
		part.angular_velocity = spin


## Point the Exterior Yeet Zone tests: the body counts as gone once its pelvis is out.
func anchor() -> Vector3:
	return pelvis.global_position


func total_mass() -> float:
	var total := 0.0
	for part in parts:
		total += part.mass
	return total


func rids() -> Array[RID]:
	var result: Array[RID] = []
	for part in parts:
		result.append(part.get_rid())
	return result


func wake() -> void:
	for part in parts:
		part.sleeping = false


## Launches the whole body so the limbs don't whip behind the grabbed one.
func throw(velocity: Vector3) -> void:
	wake()
	for part in parts:
		part.linear_velocity = velocity
		part.continuous_cd = true


func on_left_train() -> void:
	if off_train:
		return
	off_train = true
	if holder != null:
		holder.force_release()
	var speed := TrainState.speed_mps
	var snatch := YeetTuning.snatch_velocity(speed, signf(anchor().x))
	var spin := YeetTuning.random_spin(_rng, speed)
	for part in parts:
		part.collision_mask = Layers.OUTSIDE_MASK
		part.continuous_cd = true
		part.can_sleep = false
		part.sleeping = false
		part.linear_damp = 0.0
		part.angular_damp = OUTSIDE_ANGULAR_DAMP
		part.linear_velocity += snatch
		part.angular_velocity += spin
	_bounces_left = YeetTuning.GROUND_BOUNCES if speed > 1.0 else 0
	set_physics_process(true)
	GameEvents.object_yeeted.emit(self)


func _physics_process(delta: float) -> void:
	var air := TrainState.ground_velocity()
	for part in parts:
		part.apply_central_force((air - part.linear_velocity) * YeetTuning.WIND_RATE * part.mass)
	_tick_tumble()
	if TrainState.speed_mps > 0.5:
		_off_train_time += delta
	var at := anchor()
	if at.z > YeetTuning.DESPAWN_Z or at.y < YeetTuning.DESPAWN_Y or _off_train_time > YeetTuning.MAX_LIFETIME:
		GameEvents.object_despawned.emit(self)
		queue_free()

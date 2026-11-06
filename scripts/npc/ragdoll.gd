class_name Ragdoll
extends Node3D
## A knocked-out body: one rigid body per limb, jointed from BodyPlan.

const INSIDE_MASK := Layers.HULL | Layers.GROUND | Layers.SCENERY | Layers.PROP | Layers.NPC
const INSIDE_ANGULAR_DAMP := 3.0
const OUTSIDE_ANGULAR_DAMP := 0.3
## A dragged body is all noodle: little damping, so the limbs swing and trail.
const HELD_ANGULAR_DAMP := 0.5
## Knockouts fly further than the standing dummy's knockback suggests.
const LAUNCH_SCALE := 1.6
## Hit-stop on the victim alone: it hangs for a beat, then goes. The world keeps its speed.
const HIT_STOP_SECONDS := 0.1
const HIT_STOP_DRIFT := 0.08
## Limb, wave phase. Arms and legs run out of step so it reads as panic, not a walk cycle.
const FLAIL_LIMBS := {
	&"upper_arm_l": 0.0, &"upper_arm_r": PI, &"forearm_l": 1.2, &"forearm_r": 4.3,
	&"thigh_l": PI, &"thigh_r": 0.0, &"shin_l": 2.0, &"shin_r": 5.1,
}

var parts: Array[RagdollPart] = []
var pelvis: RagdollPart
var chest: RagdollPart
var holder: Hands = null
var off_train := false
var is_stowaway := false
var player_touched := false  ## A player bonked, shoved, dragged or threw this one.

var _bounces_left := 0
var _off_train_time := 0.0
var _rng := RandomNumberGenerator.new()
var _physics_material: PhysicsMaterial
var _hit_stop_left := 0.0
var _launch := Vector3.ZERO
var _watch_left := 0.0
var _watching := false
var _impact_wait := 0.0
var _scenery_wait := 0.0
var _flail_left := 0.0
var _flail_clock := 0.0
var _guide_left := 0.0
var _guide_path: Array[Vector3] = []
var _guide_speed := 0.0
var _bowler: Node3D = null  ## Whoever swings or threw this body; it bonks in their name.


## Replaces a standing dummy at [param origin] with a ragdoll moving at [param velocity].
static func spawn(parent: Node, origin: Transform3D, passenger: String, velocity: Vector3) -> Ragdoll:
	var ragdoll := Ragdoll.new()
	ragdoll.name = "Ragdoll"
	parent.add_child(ragdoll)
	ragdoll._build(origin, passenger, velocity)
	ragdoll._begin_hit_stop(velocity * LAUNCH_SCALE)
	return ragdoll


func _ready() -> void:
	set_physics_process(false)
	_rng.seed = TrainState.next_seed()


func _build(origin: Transform3D, passenger: String, velocity: Vector3) -> void:
	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = 0.8
	_physics_material.bounce = 0.2
	var by_name: Dictionary = {}
	for part_name: StringName in BodyPlan.PARTS:
		var def: Dictionary = BodyPlan.PARTS[part_name]
		var part := _make_part(part_name, def, origin, passenger)
		part.linear_velocity = velocity
		by_name[part_name] = part
	pelvis = by_name[&"pelvis"]
	chest = by_name[&"chest"]
	for joint_def: Dictionary in BodyPlan.JOINTS:
		_make_joint(joint_def, by_name, origin)


func _make_part(part_name: StringName, def: Dictionary, origin: Transform3D, passenger: String) -> RagdollPart:
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
	part.max_contacts_reported = 2
	var size: Vector3 = def["size"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	part.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BodyPlan.part_mesh(passenger, part_name, true)
	part.add_child(mesh)
	var position_in_dummy: Vector3 = def["pos"]
	part.transform = origin * Transform3D(Basis.IDENTITY, position_in_dummy)
	add_child(part)
	parts.append(part)
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
	var center := center_of_mass()
	var drift := center_velocity()
	if center.y > Treadmill.GROUND_Y + 0.55 or drift.y > -0.3:
		return
	var hop := YeetTuning.hop_speed(_bounces_left, TrainState.speed_mps)
	var spin := YeetTuning.tumble_spin(_rng, TrainState.speed_mps - drift.z)
	_bounces_left -= 1
	for part in parts:
		var orbit := spin.cross(part.global_position - center)
		part.linear_velocity = Vector3(drift.x, hop, drift.z) + orbit
		part.angular_velocity = spin


## Point the Exterior Yeet Zone tests: the body counts as gone once its pelvis is out.
func anchor() -> Vector3:
	return pelvis.global_position


func center_of_mass() -> Vector3:
	var center := Vector3.ZERO
	for part in parts:
		center += part.global_position * part.mass
	return center / total_mass()


func center_velocity() -> Vector3:
	var drift := Vector3.ZERO
	for part in parts:
		drift += part.linear_velocity * part.mass
	return drift / total_mass()


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


## Called by Hands. From here on any part moving fast enough bonks an NPC it meets.
func grabbed_by(hands: Hands) -> void:
	holder = hands
	player_touched = true
	_bowler = hands.player
	_end_hit_stop()
	wake()
	_watch_left = INF
	for part in parts:
		part.angular_damp = HELD_ANGULAR_DAMP
	set_physics_process(true)


func released() -> void:
	holder = null
	_watch_left = YeetTuning.WATCH_AFTER_HOLD
	if off_train:
		return
	for part in parts:
		part.angular_damp = INSIDE_ANGULAR_DAMP


## Launches the whole body so the limbs don't whip behind the grabbed one.
func throw(velocity: Vector3, attacker: Node3D = null) -> void:
	wake()
	_end_hit_stop()
	for part in parts:
		part.linear_velocity = velocity
		part.continuous_cd = true
	_bowler = attacker
	player_touched = player_touched or attacker != null
	_flail_left = YeetTuning.FLAIL_AFTER_THROW
	_watch_left = maxf(_watch_left, YeetTuning.WATCH_AFTER_THROW)
	set_physics_process(true)


## Adds [param velocity] to a body that is already down: a punt, not a throw.
func launch(velocity: Vector3, attacker: Node3D = null) -> void:
	wake()
	_end_hit_stop()
	for part in parts:
		part.linear_velocity += velocity
		part.continuous_cd = true
	_bowler = attacker
	player_touched = player_touched or attacker != null
	_flail_left = maxf(_flail_left, YeetTuning.FLAIL_AFTER_LAUNCH)
	_watch_left = maxf(_watch_left, YeetTuning.WATCH_AFTER_LAUNCH)
	set_physics_process(true)


## Steers the flying body along [param path], ending outside the hull, and lets it slip
## past window frames, so a heave aimed roughly at an opening always goes through it.
func guide_to(path: Array[Vector3], speed: float) -> void:
	_guide_path = path.duplicate()
	_guide_speed = speed
	var length := 0.0
	var from := center_of_mass()
	for point in path:
		length += from.distance_to(point)
		from = point
	_guide_left = length / speed + YeetTuning.GUIDE_MARGIN
	for part in parts:
		part.collision_mask = INSIDE_MASK & ~Layers.HULL
	set_physics_process(true)


func is_guided() -> bool:
	return _guide_left > 0.0


func is_flailing() -> bool:
	return _flail_left > 0.0


## Report from one part. Runs where the physics runs, so the host decides every bonk.
func on_part_contact(part: RagdollPart, other: Node) -> void:
	var speed := (part.pre_velocity - YeetTuning.surface_velocity(other)).length()
	if speed < YeetTuning.IMPACT_MIN_SPEED:
		return
	if _bowler != null and hits_hard(part.pre_velocity, YeetTuning.BODY_BONK_SPEED) and _is_bonkable(other) and multiplayer.is_server():
		var push := (other as Node3D).global_position - part.global_position
		push.y = 0.0
		other.call("receive_bonk", YeetTuning.BODY_BONK_POWER, push.normalized() * 1.6, _bowler)
		_impact_wait = 0.0
	if _impact_wait <= 0.0:
		_impact_wait = YeetTuning.IMPACT_COOLDOWN
		GameEvents.impact.emit(self, part.global_position, speed)
	if off_train and YeetTuning.is_scenery(other) and _scenery_wait <= 0.0:
		_scenery_wait = YeetTuning.SCENERY_COOLDOWN
		GameEvents.body_hit_scenery.emit(self, speed)


## Whether a limb moving at [param velocity] hits like a blow. A carried body moves with its
## carrier and its limbs flop, so a run alone is no blow: it takes a swing or a flick.
func hits_hard(velocity: Vector3, free_speed: float) -> bool:
	if holder == null:
		return velocity.length() >= free_speed
	return holder.is_striking() and (velocity - holder.player.velocity).length() >= YeetTuning.STRUCK_BLOW_SPEED


func _is_bonkable(other: Node) -> bool:
	return other.has_method("receive_bonk") and not other is RagdollPart and not other is PhysicsProp


func on_left_train() -> void:
	if off_train:
		return
	off_train = true
	if holder != null:
		holder.force_release()
	_end_hit_stop()
	var speed := TrainState.speed_mps
	var snatch := YeetTuning.snatch_velocity(speed, signf(anchor().x))
	# Whatever speed it had toward the locomotive, the slipstream eats on the way out.
	var drift := center_velocity()
	snatch.z += maxf(-drift.z, 0.0)
	if _guide_left > 0.0:
		snatch.y -= maxf(drift.y - YeetTuning.GUIDE_EXIT_CLIMB, 0.0)
	_guide_left = 0.0
	_flail_left = YeetTuning.FLAIL_OUTSIDE
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
	_impact_wait -= delta
	_scenery_wait -= delta
	if _hit_stop_left > 0.0:
		_tick_hit_stop(delta)
	if _guide_left > 0.0:
		_tick_guide(delta)
	if off_train:
		_tick_outside(delta)
		if is_queued_for_deletion():
			return
	if _flail_left > 0.0 or (off_train and pelvis.global_position.y > Treadmill.GROUND_Y + 0.7):
		_tick_flail(delta)
	_sync_contact_watch(delta)
	if not _needs_tick():
		set_physics_process(false)


func _tick_outside(delta: float) -> void:
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


func _begin_hit_stop(launch_velocity: Vector3) -> void:
	_launch = launch_velocity
	_hit_stop_left = HIT_STOP_SECONDS
	_watch_left = YeetTuning.WATCH_AFTER_LAUNCH + HIT_STOP_SECONDS
	for part in parts:
		part.linear_velocity = launch_velocity * HIT_STOP_DRIFT
		part.gravity_scale = 0.0
	set_physics_process(true)


func _end_hit_stop() -> void:
	if _hit_stop_left <= 0.0:
		return
	_hit_stop_left = 0.0
	for part in parts:
		part.gravity_scale = 1.0


func _tick_hit_stop(delta: float) -> void:
	_hit_stop_left -= delta
	if _hit_stop_left > 0.0:
		return
	_hit_stop_left = 0.001  # Let _end_hit_stop run even when this tick landed exactly on zero.
	_end_hit_stop()
	var side := Vector3(_launch.z, 0.0, -_launch.x).normalized()
	var spin := side * _rng.randf_range(3.0, 7.0)
	for part in parts:
		part.linear_velocity = _launch
		part.angular_velocity = spin
		part.continuous_cd = true
	_flail_left = YeetTuning.FLAIL_AFTER_LAUNCH


func _tick_guide(delta: float) -> void:
	_guide_left -= delta
	var center := center_of_mass()
	if _guide_path.size() > 1 and center.distance_to(_guide_path[0]) < YeetTuning.GUIDE_WAYPOINT_RADIUS:
		_guide_path.pop_front()
	var to_target := _guide_path[0] - center
	if off_train or _guide_left <= 0.0 or to_target.length() < 0.5:
		_end_guide()
		return
	var wanted := to_target.normalized() * _guide_speed
	wanted.y = clampf(wanted.y, -YeetTuning.GUIDE_MAX_CLIMB, YeetTuning.GUIDE_MAX_CLIMB)
	var change := (wanted - center_velocity()).limit_length(YeetTuning.GUIDE_TURN * delta)
	for part in parts:
		part.linear_velocity += change


func _end_guide() -> void:
	_guide_left = 0.0
	if off_train:
		return
	for part in parts:
		part.collision_mask = INSIDE_MASK


## Windmills the limbs around the chest while the body is in the air. Velocities rather
## than torques: the joint limits then clip the wave instead of winding up against it.
func _tick_flail(delta: float) -> void:
	_flail_left -= delta
	_flail_clock += delta
	var across := chest.global_basis.x
	var fore := chest.global_basis.z
	for part in parts:
		if not FLAIL_LIMBS.has(part.part_name):
			continue
		var phase: float = FLAIL_LIMBS[part.part_name]
		var wave := sin(_flail_clock * YeetTuning.FLAIL_RATE + phase)
		var side := cos(_flail_clock * YeetTuning.FLAIL_RATE * 0.63 + phase)
		var wanted := chest.angular_velocity + (across * wave + fore * side * 0.5) * YeetTuning.FLAIL_SPIN
		part.angular_velocity = part.angular_velocity.lerp(wanted, YeetTuning.FLAIL_BLEND)


## Contact reports are only on while this body can do something with them.
func _sync_contact_watch(delta: float) -> void:
	if not off_train and holder == null:
		_watch_left -= delta
	var wanted := _watch_left > 0.0 or off_train
	if wanted != _watching:
		_watching = wanted
		if not wanted:
			_bowler = null
		for part in parts:
			part.contact_monitor = wanted
	if _watching:
		for part in parts:
			part.pre_velocity = part.linear_velocity


func _needs_tick() -> bool:
	return off_train or holder != null or _watching or _hit_stop_left > 0.0 or _guide_left > 0.0 or _flail_left > 0.0

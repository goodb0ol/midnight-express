class_name TestDummy
extends CharacterBody3D
## Standing target for Milestone 1. Milestone 3 passengers will keep this contract:
## receive_bonk() and the npc_* events on GameEvents.

const MAX_HP := 3
const KNOCKBACK_FRICTION := 18.0
const GRAVITY := 16.0
const WOBBLE_DECAY := 9.0

var hp := MAX_HP
var palette: Dictionary

var _knockback := Vector3.ZERO
var _visual: Node3D
var _face: Label3D
var _wobble := 0.0
var _wobble_axis := Vector3.RIGHT
var _flash := 0.0
var _materials: Array[StandardMaterial3D] = []


static func create(palette_index: int) -> TestDummy:
	var dummy := TestDummy.new()
	dummy.palette = BodyPlan.PALETTES[palette_index % BodyPlan.PALETTES.size()]
	return dummy


func _ready() -> void:
	collision_layer = Layers.NPC
	collision_mask = Layers.HULL | Layers.PROP | Layers.PLAYER
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = BodyPlan.HEIGHT
	shape.shape = capsule
	shape.position.y = BodyPlan.HEIGHT * 0.5
	add_child(shape)
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	for part_name: StringName in BodyPlan.PARTS:
		var def: Dictionary = BodyPlan.PARTS[part_name]
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = def["size"]
		var material := MeshBatch.flat(palette[def["tint"]]).duplicate() as StandardMaterial3D
		box.material = material
		_materials.append(material)
		mesh.mesh = box
		mesh.position = def["pos"]
		_visual.add_child(mesh)
		if part_name == &"head":
			_face = BodyPlan.add_face(mesh, ":|")


func receive_bonk(power: int, direction: Vector3, attacker: Node3D) -> void:
	if hp <= 0:
		return
	hp -= power
	GameEvents.npc_bonked.emit(self, attacker, power)
	if hp <= 0:
		_knock_out(direction, attacker)
		return
	_knockback = Vector3(direction.x, 0.0, direction.z) * 3.0
	_wobble = 0.35
	_wobble_axis = Vector3.UP.cross(direction).normalized()
	_flash = 1.0
	_face.text = "o_O" if hp == 1 else ">_<"


func _knock_out(direction: Vector3, attacker: Node3D) -> void:
	var ragdoll := Ragdoll.spawn(get_parent(), global_transform, palette, direction * 5.0 + Vector3.UP * 1.5)
	GameEvents.npc_knocked_out.emit(self, ragdoll, attacker)
	queue_free()


func _physics_process(delta: float) -> void:
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	move_and_slide()


func _process(delta: float) -> void:
	if _wobble > 0.001:
		_wobble = lerpf(_wobble, 0.0, 1.0 - exp(-WOBBLE_DECAY * delta))
		_visual.rotation = _wobble_axis * _wobble * cos(Time.get_ticks_msec() * 0.03)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		for material in _materials:
			material.emission_enabled = _flash > 0.0
			material.emission = Color(1.0, 0.3, 0.2)
			material.emission_energy_multiplier = _flash * 1.5

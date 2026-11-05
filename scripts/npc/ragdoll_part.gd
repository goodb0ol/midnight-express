class_name RagdollPart
extends RigidBody3D
## One limb of a Ragdoll. Answers the same questions as a PhysicsProp, so Hands and
## the ExteriorZone need no special cases beyond telling them apart.

var ragdoll: Ragdoll
var part_name: StringName


func receive_bonk(power: int, direction: Vector3, _attacker: Node3D) -> void:
	apply_central_impulse(direction * (6.0 + power * 4.0))


func yeet_anchor() -> Vector3:
	return ragdoll.anchor()


func is_off_train() -> bool:
	return ragdoll.off_train


func on_left_train() -> void:
	ragdoll.on_left_train()

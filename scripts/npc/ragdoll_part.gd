class_name RagdollPart
extends RigidBody3D
## One limb of a Ragdoll. Answers the same questions as a PhysicsProp, so Hands and
## the ExteriorZone need no special cases beyond telling them apart.

var ragdoll: Ragdoll
var part_name: StringName
## Velocity going into this physics step: by the time a contact is reported the solver
## has already stopped the limb, so the report alone can't say how hard it hit.
var pre_velocity := Vector3.ZERO


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Punting a body that is already down throws the whole thing, not one limb.
func receive_bonk(power: int, direction: Vector3, attacker: Node3D) -> void:
	ragdoll.launch(direction * (4.0 + power * 1.5) + Vector3.UP * (2.0 + power), attacker)
	GameEvents.impact.emit(ragdoll, global_position, 8.0 + power * 2.0)


func yeet_anchor() -> Vector3:
	return ragdoll.anchor()


func is_off_train() -> bool:
	return ragdoll.off_train


func on_left_train() -> void:
	ragdoll.on_left_train()


func _on_body_entered(other: Node) -> void:
	ragdoll.on_part_contact(self, other)

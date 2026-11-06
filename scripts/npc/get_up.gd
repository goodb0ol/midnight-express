extends Node
## Child of a Ragdoll that was shoved, not bonked. Left alone, the body stands back up as a
## passenger. Grabbing it, bonking it or yeeting it keeps it down for good, which gives the
## player a few seconds to finish the job after knocking someone over.

const STAY_DOWN := 3.5        ## Seconds on the floor before standing.
const MAX_WAIT := 2.5         ## Extra seconds allowed for the body to stop moving.
const STILL_SPEED := 1.5
const BONK_AIM_DOT := 0.75    ## How squarely a landed swing must point at the body.

## How many shoved bodies are waiting to stand up.
static var active := 0

var ragdoll: Ragdoll
var passenger := "gran"
var hp := TestDummy.MAX_HP
var is_stowaway := false

var _age := 0.0


func _enter_tree() -> void:
	active += 1


func _exit_tree() -> void:
	active -= 1


func _ready() -> void:
	var main := ragdoll.get_parent().get_parent() as Main
	if main != null:
		for player: Player in main.players.values():
			player.hands.swung.connect(_on_swung.bind(player))


func _physics_process(delta: float) -> void:
	if ragdoll.off_train or ragdoll.holder != null:
		queue_free()
		return
	_age += delta
	if _age < STAY_DOWN:
		return
	if ragdoll.pelvis.linear_velocity.length() < STILL_SPEED or _age > STAY_DOWN + MAX_WAIT:
		_stand_up()


## RagdollPart.receive_bonk raises no event, so a landed swing aimed at this body counts.
func _on_swung(hit: bool, player: Player) -> void:
	if not hit or is_queued_for_deletion():
		return
	var to_body := ragdoll.chest.global_position - player.eye_position()
	if to_body.length() > Hands.BONK_RANGE + 0.6 or player.aim_forward().dot(to_body.normalized()) < BONK_AIM_DOT:
		return
	TestDummy.alarm(ragdoll.anchor())
	# The pelvis stands in for the npc: it has a real world position.
	GameEvents.npc_knocked_out.emit(ragdoll.pelvis, ragdoll, player)
	queue_free()


func _stand_up() -> void:
	var at := ragdoll.anchor()
	var z := clampf(at.z, TestDummy.AISLE_MIN_Z, TestDummy.AISLE_MAX_Z)
	var x := TestDummy.aisle_x(z, clampf(at.x, -TestDummy.AISLE_LANE, TestDummy.AISLE_LANE))
	var spot := Transform3D(Basis(Vector3.UP, ragdoll.pelvis.rotation.y), Vector3(x, 0.05, z))
	var index := BodyPlan.PASSENGERS.find(passenger)
	var npcs := ragdoll.get_parent()
	var main := npcs.get_parent() as Main
	var dummy: TestDummy
	if main != null:
		dummy = main.spawn_dummy(spot, index)
	else:
		dummy = TestDummy.create(index)
		dummy.transform = spot
		npcs.add_child(dummy)
	dummy.hp = hp
	dummy.is_stowaway = is_stowaway
	dummy.rise()
	ragdoll.queue_free()

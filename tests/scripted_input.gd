class_name ScriptedInput
extends PlayerInputSource
## Test double for LocalInput. Proves Player and Hands run from commands alone, which
## is the same seam the network input source will use in Milestone 4.

var move := Vector2.ZERO
var sprint := false
var jump := false
var throw_held := false

var _grab_next := false
var _use_next := false


func press_grab() -> void:
	_grab_next = true


func press_use() -> void:
	_use_next = true


func aim_at(eye: Vector3, point: Vector3) -> void:
	var to_point := (point - eye).normalized()
	yaw = atan2(-to_point.x, -to_point.z)
	pitch = asin(to_point.y)


func sample() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = move
	command.yaw = yaw
	command.pitch = pitch
	command.sprint = sprint
	command.jump = jump
	command.throw_held = throw_held
	command.grab_pressed = _grab_next
	command.use_pressed = _use_next
	_grab_next = false
	_use_next = false
	return command

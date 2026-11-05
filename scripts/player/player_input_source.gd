class_name PlayerInputSource
extends Node
## Where a Player's commands come from. LocalInput reads devices, tests use a scripted
## source, and Milestone 4 adds one fed by the network. Player never touches Input.

var yaw := 0.0
var pitch := 0.0


func sample() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	return command

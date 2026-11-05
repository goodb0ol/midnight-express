class_name PlayerCommand
extends RefCounted
## One physics tick of player intent. Plain values only, so a client can send it to
## the host in Milestone 4 and the host can run the exact same Player and Hands code.

var move := Vector2.ZERO  ## x = strafe right, y = forward; length <= 1.
var yaw := 0.0            ## Absolute view yaw, radians.
var pitch := 0.0          ## Absolute view pitch, radians.
var jump := false
var sprint := false
var grab_pressed := false ## Edge: grab / interact / drop.
var throw_held := false   ## Level: hold to charge, release to throw.
var use_pressed := false  ## Edge: swing held tool or fist.

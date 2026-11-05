class_name RescueRope
extends Node3D
## Emergency rope trailing behind the rear platform. Runs along the track centre line.

const LENGTH := 70.0
const REACH := 2.3
const END_Y := -1.05  ## Rope rests just above the snow.

var start_z := 0.0


func setup(rear_z: float) -> void:
	start_z = rear_z
	var batch := MeshBatch.new()
	var fibre := MeshBatch.flat(Color(0.86, 0.55, 0.18), 0.6)
	# Sloped first stretch from the platform to the snow, then flat along the track.
	var drop := 0.9 - END_Y
	var slope_length := 6.0
	var slope_angle := atan2(drop, slope_length)
	var slope_center := Vector3(0.0, (0.9 + END_Y) * 0.5, start_z + slope_length * 0.5)
	batch.add_box(Vector3(0.07, 0.07, sqrt(drop * drop + slope_length * slope_length)), slope_center, fibre, Basis(Vector3.RIGHT, slope_angle))
	batch.add_box(Vector3(0.07, 0.07, LENGTH - slope_length), Vector3(0.0, END_Y, start_z + (LENGTH + slope_length) * 0.5), fibre)
	batch.add_box(Vector3(0.5, 0.2, 0.5), Vector3(0.0, END_Y, end_z()), MeshBatch.flat(Color(1.0, 0.3, 0.12), 1.2))
	var mesh := MeshInstance3D.new()
	mesh.name = "RopeMesh"
	mesh.mesh = batch.build()
	add_child(mesh)


func end_z() -> float:
	return start_z + LENGTH


func in_reach(point: Vector3) -> bool:
	return absf(point.x) <= REACH and point.z >= start_z - 6.0 and point.z <= end_z() + 1.0


## Where a reeled-in player ends up: middle of the rear platform.
func boarding_point() -> Vector3:
	return Vector3(0.0, 0.05, start_z - Train.PLATFORM_DEPTH * 0.5)

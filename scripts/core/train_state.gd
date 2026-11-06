extends Node
## Single source of truth for the train's motion (autoload).
##
## The train never moves: speed and distance only drive the treadmill. The exterior
## is a pure function of (route_seed, distance_m), so in co-op the host only has to
## replicate those two numbers for every peer to see identical scenery.

const KMH_PER_MPS := 3.6
const DEFAULT_SPEED_KMH := 100.0
const ACCELERATION := 7.0  ## m/s². Milestone 3 will brake into stations with this.

var speed_mps := DEFAULT_SPEED_KMH / KMH_PER_MPS
var target_speed_mps := DEFAULT_SPEED_KMH / KMH_PER_MPS
var distance_m := 0.0
var route_seed := 20261105
var in_tunnel := false
var blizzard := 0.0  ## 0..1, written by the world stream.
## Seeds for per-body dice. Random each launch; the test runner fixes it and resets the count.
var rng_salt := 0
var rng_serial := 0

var _previous_distance := 0.0


func _ready() -> void:
	rng_salt = randi()


func _physics_process(delta: float) -> void:
	_previous_distance = distance_m
	speed_mps = move_toward(speed_mps, target_speed_mps, ACCELERATION * delta)
	distance_m += speed_mps * delta


## A fresh seed per body, in spawn order. Instance ids differ from run to run, so a seed
## built from one makes every run of the same inputs play out differently.
func next_seed() -> int:
	rng_serial += 1
	return hash([rng_salt, rng_serial])


## World velocity of everything outside the train (+Z is backward along the track).
func ground_velocity() -> Vector3:
	return Vector3(0.0, 0.0, speed_mps)


func speed_kmh() -> float:
	return speed_mps * KMH_PER_MPS


func set_target_kmh(kmh: float) -> void:
	target_speed_mps = kmh / KMH_PER_MPS


## Render-rate distance for purely visual scrolling (texture offsets, sleepers).
func visual_distance() -> float:
	return lerpf(_previous_distance, distance_m, Engine.get_physics_interpolation_fraction())

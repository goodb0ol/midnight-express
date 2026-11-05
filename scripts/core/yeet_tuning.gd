class_name YeetTuning
## Every number that shapes the Exterior Yeet Zone, in one place.

## Fraction of train speed applied the instant a body leaves the hull. At 1.0 the
## body would exactly match the scrolling ground and land dead still relative to it,
## with no tumble and no impact. Below 1.0 the leftover speed is what the ground and
## the passing obstacles slam into it.
const SNATCH_FRACTION := 0.55
## Rate (1/s) at which the slipstream pulls a body up to full ground speed.
const WIND_RATE := 0.35
const SIDE_KICK := 2.5     ## m/s outward, so a body clears the carriage flank.
const UP_KICK := 1.2       ## m/s upward at the moment of the snatch.
const SPIN := 7.0          ## rad/s random tumble at the moment of the snatch.
const GROUND_BOUNCES := 4  ## Scripted hops on top of the physical bounce.
const BOUNCE_SPEED := 6.5  ## m/s of the first hop; later hops shrink.
const TUMBLE_RADIUS := 0.7 ## Metres. Spin per hop = speed gap to the ground / this.
const MAX_TUMBLE := 15.0   ## rad/s cap on the end-over-end spin.
## Pull on anything only partly out of a window, in m/s² at 100 km/h.
const PARTIAL_WIND_ACCEL := 9.0
const DESPAWN_Z := 300.0   ## Metres behind the train origin.
const DESPAWN_Y := -40.0
const MAX_LIFETIME := 25.0 ## Seconds; applies only while the train is moving.
const THROWN_BONK_SPEED := 5.0 ## m/s a thrown prop needs to count as a bonk.
const FULL_SPEED := 27.8   ## m/s (100 km/h): the speed the kicks above are tuned for.


## Velocity added at the moment a body leaves the train.
## [param side_x] is the sign of the body's X position (0 for the rear platform).
static func snatch_velocity(train_speed: float, side_x: float) -> Vector3:
	var strength := clampf(train_speed / FULL_SPEED, 0.0, 1.0)
	return Vector3(side_x * SIDE_KICK * strength, UP_KICK * strength, train_speed * SNATCH_FRACTION)


## Upward speed of hop number [param hops_left] (counting down to 1).
static func hop_speed(hops_left: int, train_speed: float) -> float:
	return BOUNCE_SPEED * (float(hops_left) / GROUND_BOUNCES) * minf(train_speed / FULL_SPEED, 1.0)


## Spin from the snow grabbing a body's underside: the bottom is dragged backward, so
## it tumbles end over end, with a little random yaw and roll.
static func tumble_spin(rng: RandomNumberGenerator, speed_gap: float) -> Vector3:
	var pitch := minf(maxf(speed_gap, 5.0) / TUMBLE_RADIUS, MAX_TUMBLE)
	return Vector3(-pitch, rng.randf_range(-2.5, 2.5), rng.randf_range(-4.0, 4.0))


static func random_spin(rng: RandomNumberGenerator, train_speed: float) -> Vector3:
	var strength := clampf(train_speed / FULL_SPEED, 0.0, 1.0)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return axis.normalized() * SPIN * strength

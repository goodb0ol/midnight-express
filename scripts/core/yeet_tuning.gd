class_name YeetTuning
## Every number that shapes the Exterior Yeet Zone, in one place.

## Fraction of train speed applied the instant a body leaves the hull. At 1.0 the
## body would exactly match the scrolling ground and land dead still relative to it,
## with no tumble and no impact. Below 1.0 the leftover speed is what the ground and
## the passing obstacles slam into it.
const SNATCH_FRACTION := 0.55
## Rate (1/s) at which the slipstream pulls a body up to full ground speed.
const WIND_RATE := 0.6
const SIDE_KICK := 5.0     ## m/s outward, so a body clears the carriage flank.
const UP_KICK := 7.0       ## m/s upward at the moment of the snatch: the big arc.
const SPIN := 11.0         ## rad/s random tumble at the moment of the snatch.
const GROUND_BOUNCES := 5  ## Scripted hops on top of the physical bounce.
const BOUNCE_SPEED := 6.5  ## m/s of the first hop; later hops shrink.
const TUMBLE_RADIUS := 0.7 ## Metres. Spin per hop = speed gap to the ground / this.
const MAX_TUMBLE := 18.0   ## rad/s cap on the end-over-end spin.
## Pull on anything only partly out of a window, in m/s² at 100 km/h.
const PARTIAL_WIND_ACCEL := 9.0
const DESPAWN_Z := 300.0   ## Metres behind the train origin.
const DESPAWN_Y := -40.0
const MAX_LIFETIME := 25.0 ## Seconds; applies only while the train is moving.
const THROWN_BONK_SPEED := 5.0 ## m/s a thrown prop needs to count as a bonk.
const FULL_SPEED := 27.8   ## m/s (100 km/h): the speed the kicks above are tuned for.

## --- Game feel: contacts --------------------------------------------------------
const IMPACT_MIN_SPEED := 4.0   ## m/s against the surface for a hit to count as an impact.
const IMPACT_COOLDOWN := 0.12   ## Seconds between impact events from one body.
const SCENERY_COOLDOWN := 0.5   ## Seconds between body_hit_scenery events from one body.
const WATCH_AFTER_THROW := 2.5  ## Seconds of contact monitoring after a throw.
const WATCH_AFTER_LAUNCH := 1.2 ## Seconds of contact monitoring after a bonk.
const WATCH_AFTER_HOLD := 1.0   ## Seconds of contact monitoring after letting go.
const BODY_BONK_SPEED := 5.0    ## m/s a loose flying body needs to bonk an NPC.
const STRUCK_BLOW_SPEED := 3.5  ## m/s past its carrier a body swung on purpose needs.
const BODY_BONK_POWER := 3      ## A body hit at speed knocks a passenger over.

## --- Game feel: flailing --------------------------------------------------------
const FLAIL_RATE := 17.0        ## rad/s of the limb wave.
const FLAIL_SPIN := 12.0        ## rad/s a limb is whipped around the shoulder or hip.
const FLAIL_BLEND := 0.4        ## Fraction of the way to the wanted spin, per tick.
const FLAIL_AFTER_THROW := 1.4  ## Seconds.
const FLAIL_AFTER_LAUNCH := 0.7 ## Seconds.
const FLAIL_OUTSIDE := 3.0      ## Seconds at least after leaving the train.

## --- Game feel: heave aim assist ------------------------------------------------
const ASSIST_CONE := deg_to_rad(22.0) ## How far from the crosshair an opening still counts.
const ASSIST_RANGE := 8.0       ## Metres from the eye.
const ASSIST_MIN_CHARGE := 0.2  ## A tap is a drop, not a heave.
const GUIDE_TURN := 90.0        ## m/s^2 of steering toward the opening.
const GUIDE_MIN_SPEED := 11.0   ## m/s a guided body always reaches.
const GUIDE_MAX_CLIMB := 6.0    ## m/s; a body hanging low must not shoot up over the sill.
const GUIDE_EXIT_CLIMB := 1.0   ## m/s kept on leaving, so UP_KICK alone sets the arc.
const GUIDE_MARGIN := 0.5       ## Extra seconds a guided body keeps ignoring the hull.
const GUIDE_WAYPOINT_RADIUS := 0.8 ## Metres from a waypoint that count as having reached it.
const OPENING_APPROACH := 0.5   ## Metres inside an opening a heave lines up on.


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


## Velocity of whatever was hit, to measure how hard a contact really was. Scenery and
## snow scroll past at train speed even though their nodes look static.
static func surface_velocity(other: Node) -> Vector3:
	if other is RigidBody3D:
		return (other as RigidBody3D).linear_velocity
	if other is CharacterBody3D:
		return (other as CharacterBody3D).velocity
	if other is CollisionObject3D and (other as CollisionObject3D).collision_layer & (Layers.GROUND | Layers.SCENERY):
		return TrainState.ground_velocity()
	return Vector3.ZERO


static func is_scenery(other: Node) -> bool:
	return other is CollisionObject3D and ((other as CollisionObject3D).collision_layer & Layers.SCENERY) != 0

extends RefCounted
## World stream: the route, the land, set pieces and weather.

var t: Node


func _treadmill() -> Treadmill:
	return t.main.treadmill


func _first_piece(kind: Route.Kind) -> Route.Piece:
	var route := _treadmill().route
	for piece in route.pieces_between(0.0, 40000.0):
		if piece.kind == kind:
			return piece
	return null


## Jumps the line to [param s] and lets the chunks catch up.
func _go_to(s: float) -> void:
	TrainState.distance_m = s
	await t.ticks(3)


func test_route_is_a_pure_function_of_seed() -> bool:
	var a := Route.new(4242)
	var b := Route.new(4242)
	var late := b.pieces_between(9000.0, 9500.0)
	var early := a.pieces_between(0.0, 9500.0)
	t.check(early.size() > late.size(), "asking for the far end first changes nothing")
	var same := late.size() > 0
	for piece in late:
		var found := false
		for other in early:
			found = found or (other.kind == piece.kind and other.start_m == piece.start_m and other.end_m == piece.end_m)
		same = same and found
	t.check(same, "two peers build the same pieces whatever order they ask in")
	t.check_near(a.height(70.0, 1234.0, []), b.height(70.0, 1234.0, []), 0.0001, "same land")
	t.check_near(a.blizzard_at(5000.0), b.blizzard_at(5000.0), 0.0001, "same storms")
	var other_seed := Route.new(4243)
	t.check(not is_equal_approx(a.height(70.0, 1234.0, []), other_seed.height(70.0, 1234.0, [])), "another seed is another line")
	return true


func test_set_pieces_come_every_20_to_40_seconds() -> bool:
	var route := Route.new(TrainState.route_seed)
	var majors: Array[Route.Piece] = []
	var seen := {}
	for piece in route.pieces_between(0.0, 30000.0):
		if piece.kind in Route.MAJOR_KINDS:
			majors.append(piece)
			seen[piece.kind] = true
	t.check(seen.size() == Route.MAJOR_KINDS.size(), "every kind of set piece turns up")
	t.check(majors[0].start_m < 400.0, "the first one arrives inside 15 seconds")
	for i in majors.size() - 1:
		var seconds := (majors[i + 1].start_m - majors[i].start_m) / (100.0 / 3.6)
		t.check(seconds >= 19.0 and seconds <= 42.0, "spacing %.1f s after piece %d" % [seconds, i])
		t.check(majors[i + 1].kind != majors[i].kind, "no kind twice running")
		if i + 2 < majors.size():
			t.check(majors[i + 2].kind != majors[i].kind, "one body per kind is always enough")
	return true


func test_land_is_flat_near_track_and_rises_beyond() -> bool:
	var route := _treadmill().route
	var flat_worst := 0.0
	var hills := 0.0
	var samples := 0
	for s in range(0, 40000, 37):
		var near := route.pieces_between(s - 130.0, s + 130.0)
		var open := near.is_empty()
		if open:
			flat_worst = maxf(flat_worst, absf(route.height(20.0, s, near) - Treadmill.GROUND_Y))
			hills += route.height(-90.0, s, near) - Treadmill.GROUND_Y
			samples += 1
	t.check(samples > 20, "some open country exists")
	t.check(flat_worst < 0.4, "land stays on the collision plane inside x=26, worst %.2f" % flat_worst)
	t.check(hills / samples > 12.0, "hills rise past x=30, mean %.1f m at x=90" % (hills / samples))
	return true


func test_tunnel_sets_flag_and_has_solid_walls() -> bool:
	var tunnel := _first_piece(Route.Kind.TUNNEL)
	await _go_to(tunnel.start_m - 300.0)
	t.check(not TrainState.in_tunnel, "not in the tunnel before it")
	await _go_to(tunnel.mid_m())
	t.check(TrainState.in_tunnel, "in_tunnel set inside")
	var walled := 0
	for chunk: SceneryChunk in _treadmill().active_chunks():
		if chunk.index * SceneryChunk.LENGTH >= tunnel.start_m and chunk.index * SceneryChunk.LENGTH < tunnel.end_m:
			t.check(chunk.has_tunnel_walls(), "chunk %d in the bore has walls" % chunk.index)
			walled += 1
		else:
			t.check(not chunk.has_tunnel_walls(), "chunk %d outside has none" % chunk.index)
	t.check(walled > 3, "several chunks of bore are live")
	await t.seconds(0.5)
	# A body thrown sideways in the tunnel bounces off the moving wall, not through it.
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(3.2, 0.6, 2.0)))
	crate.off_train = true
	crate.collision_mask = Layers.OUTSIDE_MASK
	crate.continuous_cd = true
	crate.linear_velocity = Vector3(16.0, 0.0, 10.0)
	var furthest := 0.0
	for i in 60:
		await t.get_tree().physics_frame
		if is_instance_valid(crate):
			furthest = maxf(furthest, crate.global_position.x)
	t.check(furthest < SetPieceMeshes.TUNNEL_HALF_WIDTH + 0.7, "wall stopped the crate at x=%.2f" % furthest)
	await _go_to(tunnel.end_m + 300.0)
	t.check(not TrainState.in_tunnel, "flag clears after the exit")
	return true


func test_each_landmark_turns_up_pooled() -> bool:
	var count_before := _treadmill().get_child_count()
	for kind: Route.Kind in [Route.Kind.STATION, Route.Kind.WRECK, Route.Kind.SKELETON]:
		var piece := _first_piece(kind)
		t.check(piece != null, "kind %d exists" % kind)
		await _go_to(piece.mid_m() + 5.0)
		var node := _treadmill().get_node(Route.Kind.keys()[kind].capitalize() + "Piece") as SetPiece
		t.check(node.visible and node.piece == piece, "landmark %d is on screen" % kind)
		t.check_near(node.position.z, TrainState.distance_m - piece.mid_m(), 0.5, "landmark %d scrolls with distance" % kind)
		t.check(node.collision_layer == Layers.SCENERY, "landmark %d is solid" % kind)
		await _go_to(piece.end_m + 900.0)
		t.check(node.piece != piece, "landmark %d released after passing" % kind)
	t.check(_treadmill().get_child_count() == count_before, "no nodes leaked")
	return true


func test_station_platform_stops_a_body() -> bool:
	var piece := _first_piece(Route.Kind.STATION)
	await _go_to(piece.mid_m())
	await t.ticks(6)
	var side := piece.side
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(side * 2.4, Treadmill.GROUND_Y + 0.5, 0.0)))
	crate.off_train = true
	crate.collision_mask = Layers.OUTSIDE_MASK
	crate.continuous_cd = true
	crate.linear_velocity = Vector3(side * 12.0, 0.0, TrainState.speed_mps)
	var furthest := 0.0
	for i in 40:
		await t.get_tree().physics_frame
		if is_instance_valid(crate):
			furthest = maxf(furthest, absf(crate.global_position.x))
	t.check(furthest < 4.0, "platform edge stopped the crate at %.2f" % furthest)
	return true


func test_bridge_drops_the_land_but_not_the_collision() -> bool:
	var bridge := _first_piece(Route.Kind.BRIDGE)
	var route := _treadmill().route
	var near := route.pieces_between(bridge.mid_m() - 50.0, bridge.mid_m() + 50.0)
	t.check(route.height(30.0, bridge.mid_m(), near) < Treadmill.GROUND_Y - Route.GORGE_DEPTH + 5.0, "the gorge is deep under the deck")
	await _go_to(bridge.mid_m())
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(9.0, Treadmill.GROUND_Y + 0.8, 0.0)))
	crate.off_train = true
	await t.seconds(0.7)
	t.check(crate.global_position.y > Treadmill.GROUND_Y - 0.5, "flat conveyor still holds bodies up")
	return true


func test_weather_writes_blizzard_and_drives_the_scene() -> bool:
	var route := _treadmill().route
	var environment: Environment = (t.main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var moon := t.main.get_node("Moon") as DirectionalLight3D
	t.check(environment.sky.sky_material is ShaderMaterial, "night sky installed")
	var storm := -1.0
	for s in range(0, 30000, 24):
		if route.blizzard_at(s) > 0.99 and route.major_at(s) == null:
			storm = s
			break
	t.check(storm > 0.0, "a full blizzard exists on the line")
	await t.ticks(4)
	var clear_fog := environment.fog_depth_end
	var clear_moon := moon.light_energy
	await _go_to(storm)
	await t.ticks(4)
	t.check_near(TrainState.blizzard, 1.0, 0.05, "TrainState.blizzard follows the route")
	t.check(environment.fog_depth_end < clear_fog * 0.3, "fog closes in")
	t.check(moon.light_energy < clear_moon, "moon dims")
	return true


func test_tunnel_blacks_out_the_sky_light() -> bool:
	var moon := t.main.get_node("Moon") as DirectionalLight3D
	var tunnel := _first_piece(Route.Kind.TUNNEL)
	await _go_to(tunnel.mid_m())
	await t.seconds(0.5)
	t.check(moon.light_energy < 0.05, "moonlight off under rock")
	return true


func test_no_invisible_ramps_out_past_the_flat() -> bool:
	var lake := _first_piece(Route.Kind.LAKE)
	await _go_to(lake.mid_m())
	var space := _treadmill().get_world_3d().direct_space_state
	for x: float in [-300.0, -124.0, -60.0, -36.0, 36.0, 60.0, 124.0, 300.0]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 150.0, 0.0), Vector3(x, -20.0, 0.0), Layers.GROUND)
		var hit := space.intersect_ray(query)
		t.check(not hit.is_empty(), "ground under x=%.0f" % x)
		if not hit.is_empty():
			t.check_near(hit["position"].y, Treadmill.GROUND_Y, 0.01, "nothing hangs above the ground at x=%.0f" % x)
	var crate: PhysicsProp = t.main.spawn_prop(&"crate", Transform3D(Basis.IDENTITY, Vector3(lake.side * 124.0, 36.0, 0.0)))
	crate.off_train = true
	crate.collision_mask = Layers.GROUND
	var lowest := INF
	for i in 60 * 4:
		await t.ticks(1)
		lowest = minf(lowest, crate.global_position.y)
	t.check(lowest < Treadmill.GROUND_Y + 1.0, "a crate over the lake comes down, lowest y=%.2f" % lowest)
	return true

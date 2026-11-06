extends RefCounted
## Audio checks. Headless runs through the dummy driver, so these pin what gets triggered
## and how the mix responds, plus the rendered samples themselves. The driver still mixes
## headless, so the test_sound_mix_ tests measure what really reaches the master bus.

const Synth := preload("res://scripts/core/sfx_synth.gd")
const MEAN_WINDOW := 4410  ## Frames, about 100 ms.

var t: Node
var _heard: Array[Array] = []


func _ready_bank() -> void:
	if not Sfx.is_baked:
		await Sfx.baked


## The route writes in_tunnel and blizzard each physics frame. Stop it so a test can set them.
func _take_over_weather() -> void:
	for node: Node in t.main.find_children("*", "Treadmill", true, false):
		node.set_physics_process(false)
	for node: Node in t.main.find_children("*", "Weather", true, false):
		node.set_physics_process(false)
	TrainState.in_tunnel = false
	TrainState.blizzard = 0.0
	t.check(not t.main.treadmill.is_physics_processing(), "the route no longer writes in_tunnel")
	t.check(not t.main.treadmill.weather.is_physics_processing(), "the route no longer writes blizzard")


func _note(sound: StringName, volume_db: float, pitch: float) -> void:
	_heard.append([sound, volume_db, pitch])


func _listen() -> void:
	_heard.clear()
	if not Sfx.sound_played.is_connected(_note):
		Sfx.sound_played.connect(_note)


func _sounds_heard() -> Array[StringName]:
	var names: Array[StringName] = []
	for entry in _heard:
		names.append(entry[0])
	return names


## Sounds played one frame apart are rate limited, so give the mixer's clock room.
func _gap() -> void:
	await t.seconds(0.4)


func _peak(stream: AudioStreamWAV) -> float:
	var highest := 0
	var data := stream.data
	for i in range(0, data.size(), 2):
		highest = maxi(highest, absi(data.decode_s16(i)))
	return highest / 32768.0


## Runs in real seconds: the mixer ignores --fixed-fps, and game frames race ahead of it.
func _measure(capture: AudioEffectCapture, seconds: float) -> Dictionary:
	capture.clear_buffer()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await t.get_tree().process_frame
	var frames := capture.get_buffer(capture.get_frames_available())
	var power := 0.0
	var peak := 0.0
	var worst_mean := 0.0
	var window_sum := 0.0
	for i in frames.size():
		var sample := frames[i].x
		power += sample * sample
		peak = maxf(peak, absf(sample))
		window_sum += sample
		if (i + 1) % MEAN_WINDOW == 0:
			worst_mean = maxf(worst_mean, absf(window_sum) / MEAN_WINDOW)
			window_sum = 0.0
	var rms := sqrt(power / maxi(frames.size(), 1))
	return {"frames": frames.size(), "rms_db": linear_to_db(rms + 0.000001), "peak_db": linear_to_db(peak + 0.000001), "mean": worst_mean}


func _add_capture() -> AudioEffectCapture:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(0, capture)
	# Nothing random in the measurement, and nothing left ringing from the last test.
	Sfx._next_whistle = Sfx._clock + 1000.0
	for player in Sfx._pool_2d:
		player.stop()
	for player in Sfx._pool_3d:
		player.stop()
	return capture


func _remove_capture() -> void:
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)


func _set_speed(mps: float) -> void:
	TrainState.speed_mps = mps
	TrainState.target_speed_mps = mps


## Mean level of one thud [param metres] in front of the listener, over a few hits.
func _thud_db(capture: AudioEffectCapture, speed: float, metres: float) -> float:
	var camera := t.main.get_viewport().get_camera_3d() as Camera3D
	var at := camera.global_position - camera.global_basis.z * metres
	var total := 0.0
	for i in 3:
		GameEvents.impact.emit(null, at, speed)
		total += (await _measure(capture, 0.35)).rms_db
		await _measure(capture, 0.3)  # Let the tail die in real time, not in game frames.
	return total / 3.0


func test_sound_bank_has_every_sound_with_real_samples() -> bool:
	await _ready_bank()
	for sound: StringName in Synth.BANK:
		var streams: Array = Sfx._bank.get(sound, [])
		t.check(streams.size() == Synth.BANK[sound], "%s has all variants" % sound)
		for stream: AudioStreamWAV in streams:
			t.check(stream.data.size() > 1000, "%s has samples" % sound)
			var peak := _peak(stream)
			t.check(peak > 0.5 and peak <= 1.0, "%s is loud, not clipped: %.2f" % [sound, peak])
			var looped: bool = stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
			t.check(looped == Synth.LOOPS.has(sound), "%s loop flag" % sound)
	return true


func test_sound_buses_and_loops_run() -> bool:
	await _ready_bank()
	for bus: StringName in [Sfx.BUS_SFX, Sfx.BUS_AMBIENCE, Sfx.BUS_STINGER]:
		t.check(AudioServer.get_bus_index(bus) > 0, "%s bus exists" % bus)
	t.check(AudioServer.get_bus_effect_count(0) > 0, "master has a limiter")
	await t.seconds(0.2)
	t.check(Sfx.rumble.playing, "rumble playing")
	t.check(Sfx.clack.playing, "clack playing")
	t.check(Sfx.wind.playing, "wind playing")
	return true


func test_sound_every_event_makes_a_noise() -> bool:
	await _ready_bank()
	_listen()
	var dummy := Node3D.new()
	t.main.add_child(dummy)
	GameEvents.npc_bonked.emit(dummy, t.player, 3)
	GameEvents.npc_bonked.emit(dummy, t.player, 1)
	GameEvents.npc_knocked_out.emit(dummy, null, t.player)
	GameEvents.impact.emit(dummy, Vector3.ZERO, 9.0)
	GameEvents.npc_panicked.emit(dummy, Vector3.ZERO)
	GameEvents.body_hit_scenery.emit(dummy, 25.0)
	GameEvents.opening_toggled.emit(dummy, true)
	GameEvents.object_yeeted.emit(t.main.find_children("*", "PhysicsProp", true, false)[0])
	GameEvents.score_awarded.emit(100, "stowaway")
	GameEvents.score_awarded.emit(-50, "passenger")
	GameEvents.round_started.emit(1, 3, 60)
	GameEvents.raid_warning.emit(5)
	GameEvents.round_ended.emit(500, true)
	await _gap()
	GameEvents.round_ended.emit(0, false)
	GameEvents.opening_toggled.emit(dummy, false)
	var heard := _sounds_heard()
	for sound: StringName in [&"bonk", &"punch", &"ko", &"clatter", &"shriek", &"crunch", &"window", &"yeet", &"ding", &"buzzer", &"round_start", &"tick", &"win", &"lose"]:
		t.check(heard.has(sound), "heard %s" % sound)
	return true


func test_sound_real_door_clanks_and_real_throw_whooshes() -> bool:
	await _ready_bank()
	_listen()
	var doors := 0
	for opening: TrainOpening in t.main.find_children("*", "TrainOpening", true, false):
		if opening.kind == TrainOpening.Kind.DOOR:
			opening.set_open(true)
			doors += 1
			await _gap()
			opening.set_open(false)
			break
	t.check(doors == 1, "found a door")
	t.check(_sounds_heard().has(&"door"), "door clanked")
	var hands: Hands = t.player.find_children("*", "Hands", true, false)[0]
	hands.threw.emit(1.0)
	t.check(_sounds_heard().has(&"whoosh"), "throw whooshed")
	return true


func test_sound_impacts_scale_with_speed_and_ignore_nudges() -> bool:
	await _ready_bank()
	_listen()
	var part := RagdollPart.new()
	GameEvents.impact.emit(part, Vector3.ZERO, 0.3)
	t.check(_heard.is_empty(), "a nudge is silent")
	GameEvents.impact.emit(part, Vector3.ZERO, 2.0)
	await _gap()
	GameEvents.impact.emit(part, Vector3.ZERO, 14.0)
	part.free()
	t.check(_heard.size() == 2, "two thuds")
	t.check(_heard[0][0] == &"thud", "a body thuds")
	t.check(_heard[1][1] > _heard[0][1] + 6.0, "faster is louder")
	return true


func test_sound_impacts_are_rate_limited() -> bool:
	await _ready_bank()
	_listen()
	for i in 20:
		GameEvents.impact.emit(null, Vector3.ZERO, 8.0)
	t.check(_heard.size() == 1, "one thud for a burst, got %d" % _heard.size())
	return true


func test_sound_ding_rises_with_combo_and_resets_on_a_penalty() -> bool:
	await _ready_bank()
	await t.seconds(Sfx.COMBO_WINDOW + 0.2)
	_listen()
	for i in 3:
		GameEvents.score_awarded.emit(100, "stowaway")
	GameEvents.score_awarded.emit(-100, "passenger")
	GameEvents.score_awarded.emit(100, "stowaway")
	t.check(_heard[1][2] > _heard[0][2] and _heard[2][2] > _heard[1][2], "each ding rises")
	t.check(_heard[3][0] == &"buzzer", "a penalty buzzes")
	t.check_near(_heard[4][2], _heard[0][2], 0.01, "combo reset")
	return true


func test_sound_train_loops_follow_speed() -> bool:
	await _ready_bank()
	TrainState.speed_mps = 150.0 / 3.6
	TrainState.target_speed_mps = TrainState.speed_mps
	await t.seconds(1.0)
	var fast_pitch: float = Sfx.clack.pitch_scale
	var fast_level: float = Sfx.rumble.volume_db
	t.check_near(fast_pitch, 1.5, 0.02, "clack at 150 km/h")
	TrainState.speed_mps = 10.0 / 3.6
	TrainState.target_speed_mps = TrainState.speed_mps
	await t.seconds(1.5)
	t.check(Sfx.clack.pitch_scale < 0.5, "clack slows down")
	t.check(Sfx.rumble.volume_db < fast_level - 3.0, "rumble drops")
	return true


func test_sound_wind_swells_per_opening_and_with_blizzard() -> bool:
	await _ready_bank()
	_take_over_weather()
	await t.seconds(1.5)
	var closed: float = Sfx.wind.volume_db
	var openings: Array[Node] = t.main.find_children("*", "TrainOpening", true, false)
	(openings[0] as TrainOpening).set_open(true)
	await t.seconds(1.0)
	var one: float = Sfx.wind.volume_db
	t.check(Sfx.open_openings() == 1, "one gust")
	t.check(one > closed + 2.0, "open window is windier")
	(openings[1] as TrainOpening).set_open(true)
	await t.seconds(1.0)
	t.check(Sfx.wind.volume_db > one + 1.0, "two openings windier still")
	(openings[0] as TrainOpening).set_open(false)
	(openings[1] as TrainOpening).set_open(false)
	await t.seconds(1.5)
	t.check(Sfx.open_openings() == 0, "gusts gone")
	t.check_near(Sfx.wind.volume_db, closed, 1.0, "back to quiet")
	TrainState.blizzard = 1.0
	await t.seconds(1.5)
	t.check(Sfx.wind.volume_db > closed + 6.0, "blizzard howls")
	TrainState.blizzard = 0.0
	return true


func test_sound_tunnel_muffles_and_echoes() -> bool:
	await _ready_bank()
	_take_over_weather()
	var sfx := AudioServer.get_bus_index(Sfx.BUS_SFX)
	TrainState.in_tunnel = true
	await t.seconds(1.0)
	t.check(Sfx.tunnel_amount > 0.99, "fully in the tunnel")
	t.check(Sfx.ambience_filter.cutoff_hz < 1000.0, "ambience muffled")
	t.check(AudioServer.is_bus_effect_enabled(sfx, 0), "echo on")
	TrainState.in_tunnel = false
	await t.seconds(1.0)
	t.check(Sfx.ambience_filter.cutoff_hz > 15000.0, "ambience clear again")
	t.check(not AudioServer.is_bus_effect_enabled(sfx, 0), "echo off")
	return true


func test_sound_siren_runs_during_warning_and_stops_with_the_round() -> bool:
	await _ready_bank()
	_listen()
	GameEvents.raid_warning.emit(10)
	await t.seconds(1.0)
	t.check(Sfx.siren.playing, "siren on")
	t.check(Sfx.siren.volume_db > -20.0, "siren audible")
	GameEvents.raid_warning.emit(1)
	GameEvents.round_ended.emit(0, false)
	await t.seconds(1.0)
	t.check(not Sfx.siren.playing, "siren off")
	return true


func test_sound_real_bonks_are_heard() -> bool:
	await _ready_bank()
	_listen()
	var dummies: Array[Node] = t.main.find_children("*", "TestDummy", true, false)
	t.check(not dummies.is_empty(), "a dummy exists")
	(dummies[0] as TestDummy).receive_bonk(1, Vector3.FORWARD, t.player)
	await t.seconds(0.1)
	(dummies[0] as TestDummy).receive_bonk(5, Vector3.FORWARD, t.player)
	var heard := _sounds_heard()
	t.check(heard.has(&"punch"), "fist punches")
	t.check(heard.has(&"bonk"), "tool bonks")
	t.check(heard.has(&"ko"), "knockout rings")
	return true


func test_sound_autoload_needs_no_class_cache() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/core/sfx.gd")
	t.check(not source.contains("SfxSynth"), "a stale class cache cannot stop the autoload")
	t.check(Sfx.Synth.BANK.has(&"bonk"), "synth reached by path")
	return true


func test_sound_mix_tunnel_is_muffled_not_swamped() -> bool:
	await _ready_bank()
	_take_over_weather()
	var capture := _add_capture()
	await t.seconds(2.0)
	var open: Dictionary = await _measure(capture, 1.0)
	TrainState.in_tunnel = true
	await t.seconds(2.0)
	await _measure(capture, 2.5)  # Game frames outrun the mixer: let the entry whoosh pass.
	var tunnel: Dictionary = await _measure(capture, 1.2)
	TrainState.in_tunnel = false
	_remove_capture()
	t.check(open.frames > 20000 and tunnel.frames > 20000, "the mixer ran")
	t.check(tunnel.rms_db < open.rms_db + 4.0, "tunnel %.1f dB against %.1f dB" % [tunnel.rms_db, open.rms_db])
	t.check(tunnel.peak_db < -2.5, "limiter not pinned, peak %.1f dB" % tunnel.peak_db)
	t.check(tunnel.mean < 0.2, "no subsonic swing, mean %.3f" % tunnel.mean)
	return true


func test_sound_mix_hard_hits_are_really_louder_up_close() -> bool:
	await _ready_bank()
	_take_over_weather()
	_set_speed(0.0)
	var capture := _add_capture()
	await t.seconds(2.0)
	# The train would prop up the quiet hits and shrink the gap being measured.
	var ambience := AudioServer.get_bus_index(Sfx.BUS_AMBIENCE)
	AudioServer.set_bus_mute(ambience, true)
	await _measure(capture, 0.3)
	var soft: float = await _thud_db(capture, 3.0, 2.0)
	var hard: float = await _thud_db(capture, 14.0, 2.0)
	var soft_close: float = await _thud_db(capture, 3.0, 1.0)
	var hard_close: float = await _thud_db(capture, 14.0, 1.0)
	AudioServer.set_bus_mute(ambience, false)
	_remove_capture()
	t.check(hard > soft + 8.0, "at 2 m: %.1f dB against %.1f dB" % [hard, soft])
	t.check(hard_close > soft_close + 7.0, "at 1 m: %.1f dB against %.1f dB" % [hard_close, soft_close])
	return true


func test_sound_near_sounds_clear_the_3d_cap() -> bool:
	var gain_at_arms_length := linear_to_db(Sfx.NEAR_UNIT_SIZE / 2.0)
	t.check(Sfx.IMPACT_LOUD_DB + gain_at_arms_length <= Sfx.MAX_3D_DB, "loud thud under the cap")
	var gain_at_one_metre := linear_to_db(Sfx.NEAR_UNIT_SIZE / 1.0)
	t.check(Sfx.IMPACT_LOUD_DB + gain_at_one_metre <= Sfx.MAX_3D_DB, "at one metre too")
	t.check(Sfx._pool_3d[0].max_db == Sfx.MAX_3D_DB, "the players really use that cap, %.1f dB" % Sfx._pool_3d[0].max_db)
	return true


func test_sound_mix_whistle_rises_over_the_train() -> bool:
	await _ready_bank()
	_take_over_weather()
	var capture := _add_capture()
	await t.seconds(2.0)
	var train: Dictionary = await _measure(capture, 1.0)
	Sfx._next_whistle = Sfx._clock
	await t.ticks(2)
	Sfx._next_whistle = Sfx._clock + 1000.0
	var blast: Dictionary = await _measure(capture, 1.0)
	_remove_capture()
	t.check(Sfx.play_count(&"whistle") > 0, "whistle fired")
	t.check(blast.rms_db > train.rms_db + 3.0, "%.1f dB against %.1f dB" % [blast.rms_db, train.rms_db])
	return true


func test_sound_weather_flags_stay_where_a_test_puts_them() -> bool:
	_take_over_weather()
	TrainState.in_tunnel = true
	TrainState.blizzard = 0.75
	await t.ticks(10)
	t.check(TrainState.in_tunnel, "in_tunnel held")
	t.check(TrainState.blizzard == 0.75, "blizzard held")
	TrainState.in_tunnel = false
	TrainState.blizzard = 0.0
	return true


func test_sound_train_noise_leaves_with_the_train() -> bool:
	await _ready_bank()
	_take_over_weather()
	await t.seconds(1.5)
	var rumble_aboard: float = Sfx.rumble.volume_db
	var wind_aboard: float = Sfx.wind.volume_db
	GameEvents.player_left_train.emit(t.player)
	await t.seconds(3.0)
	t.check(Sfx.rumble.volume_db < rumble_aboard - 10.0, "rumble fades away")
	t.check(Sfx.wind.volume_db > wind_aboard + 6.0, "open air takes over")
	GameEvents.player_reboarded.emit(t.player)
	await t.seconds(1.5)
	t.check_near(Sfx.rumble.volume_db, rumble_aboard, 1.0, "rumble back aboard")
	GameEvents.player_left_train.emit(t.player)
	await t.seconds(0.5)
	GameEvents.player_left_behind.emit(t.player)
	await t.seconds(1.5)
	t.check_near(Sfx.rumble.volume_db, rumble_aboard, 1.0, "respawn is aboard too")
	return true


func test_sound_clock_ignores_hit_stop() -> bool:
	await _ready_bank()
	var scale := Engine.time_scale
	Engine.time_scale = 0.1
	var start: float = Sfx._clock
	for i in 30:
		await t.get_tree().process_frame
	Engine.time_scale = scale
	# Scaled time would give 0.05. Fixed-fps frame pacing makes the exact figure wobble.
	t.check(Sfx._clock - start > 0.3, "rate limits run on real time, got %.2f" % (Sfx._clock - start))
	return true


func test_sound_long_combo_stays_fat() -> bool:
	await _ready_bank()
	await t.seconds(Sfx.COMBO_WINDOW + 0.2)
	_listen()
	for i in 20:
		GameEvents.score_awarded.emit(100, "stowaway")
	var highest := 0.0
	var lowest_late := 100.0
	for entry in _heard.slice(-2):
		lowest_late = minf(lowest_late, entry[2])
	for entry in _heard:
		highest = maxf(highest, entry[2])
	t.check(highest <= 4.01, "ding stops climbing at two octaves, got %.2f" % highest)
	t.check_near(lowest_late, highest * 0.5, 0.01, "an octave under the top note")
	return true

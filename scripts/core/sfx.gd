extends Node
## All game audio (autoload). Listens to GameEvents only; nothing calls into gameplay.
## Sounds come from Synth, rendered on a background thread at startup: no audio files.
##
## Buses (built in code):
##   Master   : limiter, so a pile-up is loud instead of broken.
##   Sfx      : hits and voices. A tunnel adds echo.
##   Ambience : train and wind. A tunnel muffles it.
##   Stinger  : yeets, score, siren and jingles. Stays clear of the world.

signal baked
signal sound_played(sound: StringName, volume_db: float, pitch: float)

## Reached by path, not by its class name: an autoload that needs a global class stops the
## game when the class cache predates the file, and Jouer.bat never imports.
const Synth := preload("res://scripts/core/sfx_synth.gd")

const BUS_SFX := &"Sfx"
const BUS_AMBIENCE := &"Ambience"
const BUS_STINGER := &"Stinger"
const SFX_DB := 0.0
const AMBIENCE_DB := -9.0
const STINGER_DB := -1.0
const DUCK_DB := -9.0            ## Ambience drop under a stinger.
const DUCK_RECOVERY := 12.0      ## dB per second.

const POOL_3D := 24
const POOL_2D := 10

## 3D reach: inside the carriage, versus a body hitting a tree far behind the train.
## Distance gain plus volume_db is capped at MAX_3D_DB. Keep the sum for a loud hit one metre
## from the listener under the cap, or a hard hit and a soft one come out the same.
const NEAR_UNIT_SIZE := 3.0
const FAR_UNIT_SIZE := 45.0
const MAX_3D_DB := 13.0

## Shortest gap between two plays of a sound, in seconds. Physics can fire many a frame.
const MIN_GAP: Dictionary = {
	&"thud": 0.05, &"clatter": 0.05, &"clink": 0.05, &"bonk": 0.04, &"punch": 0.04,
	&"crunch": 0.08, &"shriek": 0.16, &"yeet": 0.3, &"ko": 0.1, &"whoosh": 0.06,
}

const BONK_HEAVY_RANGE := 3.0    ## Bonk power above 2 that counts as the heaviest tool.
const IMPACT_MIN_SPEED := 1.0    ## m/s. Slower contacts are silent.
const IMPACT_LOUD_SPEED := 15.0
const IMPACT_QUIET_DB := -17.0
const IMPACT_LOUD_DB := 3.0
const METAL_PROPS: Array[StringName] = [&"wrench", &"frying_pan"]

const COMBO_WINDOW := 9.0        ## Seconds between scores that keep a combo alive.
## Semitones above the base ding, one per combo step.
## The climb stops at two octaves: above that the ding is a thin whine.
const COMBO_STEPS: Array[int] = [0, 4, 7, 12, 16, 19, 24]
const COMBO_BODY_STEP := 12      ## From here an octave-down ding keeps the note fat.

const REFERENCE_SPEED := 100.0 / 3.6  ## m/s at which the clack loop plays at pitch 1.
const WIND_PER_OPENING := 0.55
const WIND_BLIZZARD := 1.6
const GUST_LEVEL := 1.6         ## The 3D wind right at an open door.
const WIND_MAX := 2.2
const WIND_FADE_RATE := 2.5      ## Linear volume per second.
const LOOP_FADE_RATE := 1.6
const TUNNEL_RATE := 2.5         ## 0..1 per second.
const TUNNEL_CUTOFF_HZ := 620.0
const OPEN_CUTOFF_HZ := 20000.0
## The reverb tank has gain near DC. Without this a tunnel full of rumble pins the limiter.
const REVERB_HIPASS := 0.2

const WHISTLE_FIRST := Vector2(9.0, 15.0)
const WHISTLE_GAP := Vector2(28.0, 55.0)
const WHISTLE_DUCK_DB := -6.0
const SIREN_TIMEOUT := 2.5       ## Seconds without a raid_warning before the siren gives up.

## Thrown off the train: the carriage noise drains away and the open air takes over.
const OFF_TRAIN_LEVEL := 0.12
const OFF_TRAIN_FADE := 0.45     ## 0..1 per second going away.
const REBOARD_FADE := 2.5        ## 0..1 per second coming back.
const OFF_TRAIN_WIND := 1.1

var is_baked := false
var counts: Dictionary = {}      ## sound -> plays so far.
var rumble: AudioStreamPlayer
var clack: AudioStreamPlayer
var wind: AudioStreamPlayer
var siren: AudioStreamPlayer
var tunnel_amount := 0.0
var ambience_filter: AudioEffectLowPassFilter
var combo := 0

var _bank: Dictionary = {}       ## sound -> Array[AudioStreamWAV].
var _waiting: Dictionary = {}    ## sound -> play() arguments, for events during the bake.
var _last_played: Dictionary = {}
var _last_variant: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _cursor_3d := 0
var _cursor_2d := 0
var _gusts: Dictionary = {}      ## open TrainOpening -> looping AudioStreamPlayer3D.
var _dying_gusts: Array[AudioStreamPlayer3D] = []
var _clock := 0.0
var _last_score_at := -1000.0
var _next_whistle := 0.0
var _siren_level := 0.0
var _siren_quiet_for := 0.0
var _tock_next := false
var _duck_db := 0.0
var _was_in_tunnel := false
var _train_presence := 1.0       ## 1 aboard, falling while the train leaves the player behind.
var _off_train := false
var _ambience_reverb: AudioEffectReverb
var _sfx_reverb: AudioEffectReverb
var _sfx_delay: AudioEffectDelay
var _rng := RandomNumberGenerator.new()
var _thread: Thread
var _stop_baking := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_next_whistle = _rng.randf_range(WHISTLE_FIRST.x, WHISTLE_FIRST.y)
	_build_buses()
	_build_players()
	_listen()
	_thread = Thread.new()
	_thread.start(_bake)


func _exit_tree() -> void:
	_stop_baking = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	for child in get_children():
		child.call("stop")


## Plays a sound. [param at] is a Vector3 for a positioned sound, null for a flat one.
## Returns false if the rate limit dropped it, or it is waiting for the bake.
func play(sound: StringName, volume_db := 0.0, pitch := 1.0, at: Variant = null, far := false, bus := BUS_SFX) -> bool:
	if not _bank.has(sound):
		if not is_baked:
			_waiting[sound] = [volume_db, pitch, at, far, bus]
		return false
	if _clock - _last_played.get(sound, -1000.0) < MIN_GAP.get(sound, 0.0):
		return false
	_last_played[sound] = _clock
	counts[sound] = counts.get(sound, 0) + 1
	var stream := _pick_variant(sound)
	if at == null:
		var flat := _take_2d()
		flat.stream = stream
		flat.bus = bus
		flat.volume_db = volume_db
		flat.pitch_scale = pitch
		flat.play()
	else:
		var positioned := _take_3d()
		positioned.global_position = at
		positioned.stream = stream
		positioned.bus = bus
		positioned.volume_db = volume_db
		positioned.pitch_scale = pitch
		positioned.unit_size = FAR_UNIT_SIZE if far else NEAR_UNIT_SIZE
		positioned.attenuation_filter_db = 0.0 if far else -18.0
		positioned.play()
	sound_played.emit(sound, volume_db, pitch)
	return true


func play_count(sound: StringName) -> int:
	return counts.get(sound, 0)


func open_openings() -> int:
	return _gusts.size()


## --- Startup -------------------------------------------------------------------------

func _build_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, limiter)

	var sfx := _add_bus(BUS_SFX, SFX_DB)
	_sfx_delay = AudioEffectDelay.new()
	_sfx_delay.tap1_active = true
	_sfx_delay.tap1_delay_ms = 170.0
	_sfx_delay.tap1_level_db = -8.0
	_sfx_delay.tap2_active = true
	_sfx_delay.tap2_delay_ms = 330.0
	_sfx_delay.tap2_level_db = -13.0
	_sfx_delay.feedback_active = true
	_sfx_delay.feedback_delay_ms = 410.0
	_sfx_delay.feedback_level_db = -14.0
	AudioServer.add_bus_effect(sfx, _sfx_delay)
	_sfx_reverb = AudioEffectReverb.new()
	_sfx_reverb.room_size = 0.85
	_sfx_reverb.damping = 0.3
	_sfx_reverb.wet = 0.0
	_sfx_reverb.hipass = REVERB_HIPASS
	AudioServer.add_bus_effect(sfx, _sfx_reverb)
	AudioServer.set_bus_effect_enabled(sfx, 0, false)
	AudioServer.set_bus_effect_enabled(sfx, 1, false)

	var ambience := _add_bus(BUS_AMBIENCE, AMBIENCE_DB)
	ambience_filter = AudioEffectLowPassFilter.new()
	ambience_filter.cutoff_hz = OPEN_CUTOFF_HZ
	AudioServer.add_bus_effect(ambience, ambience_filter)
	_ambience_reverb = AudioEffectReverb.new()
	_ambience_reverb.room_size = 0.35
	_ambience_reverb.wet = 0.08
	_ambience_reverb.hipass = REVERB_HIPASS
	AudioServer.add_bus_effect(ambience, _ambience_reverb)

	_add_bus(BUS_STINGER, STINGER_DB)


func _add_bus(bus_name: StringName, volume_db: float) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_db(index, volume_db)
	return index


func _build_players() -> void:
	for i in POOL_3D:
		var positioned := AudioStreamPlayer3D.new()
		positioned.attenuation_filter_cutoff_hz = 3500.0
		positioned.max_db = MAX_3D_DB
		add_child(positioned)
		_pool_3d.append(positioned)
	for i in POOL_2D:
		var flat := AudioStreamPlayer.new()
		add_child(flat)
		_pool_2d.append(flat)
	rumble = _add_loop_player(BUS_AMBIENCE)
	clack = _add_loop_player(BUS_AMBIENCE)
	wind = _add_loop_player(BUS_AMBIENCE)
	siren = _add_loop_player(BUS_STINGER)


func _add_loop_player(bus: StringName) -> AudioStreamPlayer:
	var loop := AudioStreamPlayer.new()
	loop.bus = bus
	loop.volume_db = -80.0
	add_child(loop)
	return loop


func _listen() -> void:
	GameEvents.npc_bonked.connect(_on_npc_bonked)
	GameEvents.npc_knocked_out.connect(_on_npc_knocked_out)
	GameEvents.impact.connect(_on_impact)
	GameEvents.npc_panicked.connect(_on_npc_panicked)
	GameEvents.body_hit_scenery.connect(_on_body_hit_scenery)
	GameEvents.opening_toggled.connect(_on_opening_toggled)
	GameEvents.object_yeeted.connect(_on_object_yeeted)
	GameEvents.score_awarded.connect(_on_score_awarded)
	GameEvents.round_started.connect(_on_round_started)
	GameEvents.raid_warning.connect(_on_raid_warning)
	GameEvents.round_ended.connect(_on_round_ended)
	GameEvents.player_left_train.connect(_on_player_left_train)
	GameEvents.player_left_behind.connect(_on_player_left_behind)
	GameEvents.player_reboarded.connect(_on_player_reboarded)
	GameEvents.player_respawned.connect(_on_player_respawned)
	# Throws and swings live on each player's Hands, which come and go with Main.
	get_tree().node_added.connect(_on_node_added)


## Background thread. Touches nothing but Synth and hands results back deferred.
func _bake() -> void:
	for sound: StringName in Synth.BANK:
		var streams: Array[AudioStreamWAV] = []
		for variant in int(Synth.BANK[sound]):
			if _stop_baking:
				return
			streams.append(Synth.render(sound, variant))
		_publish.call_deferred(sound, streams)
	_finish_bake.call_deferred()


func _publish(sound: StringName, streams: Array[AudioStreamWAV]) -> void:
	_bank[sound] = streams
	match sound:
		&"rumble": _start_loop(rumble, streams[0])
		&"clack": _start_loop(clack, streams[0])
		&"wind":
			_start_loop(wind, streams[0])
			for gust: AudioStreamPlayer3D in _gusts.values():
				_start_gust(gust)
		&"siren": siren.stream = streams[0]
	if _waiting.has(sound):
		var call_args: Array = _waiting[sound]
		_waiting.erase(sound)
		play(sound, call_args[0], call_args[1], call_args[2], call_args[3], call_args[4])


func _finish_bake() -> void:
	is_baked = true
	_waiting.clear()
	baked.emit()


func _start_loop(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stream = stream
	player.play()


func _pick_variant(sound: StringName) -> AudioStreamWAV:
	var streams: Array = _bank[sound]
	if streams.size() == 1:
		return streams[0]
	var variant := _rng.randi_range(0, streams.size() - 2)
	if variant >= int(_last_variant.get(sound, -1)):
		variant += 1
	_last_variant[sound] = variant
	return streams[variant]


func _take_3d() -> AudioStreamPlayer3D:
	for i in POOL_3D:
		var index := (_cursor_3d + i) % POOL_3D
		if not _pool_3d[index].playing:
			_cursor_3d = (index + 1) % POOL_3D
			return _pool_3d[index]
	var oldest := _pool_3d[_cursor_3d]
	_cursor_3d = (_cursor_3d + 1) % POOL_3D
	return oldest


func _take_2d() -> AudioStreamPlayer:
	for i in POOL_2D:
		var index := (_cursor_2d + i) % POOL_2D
		if not _pool_2d[index].playing:
			_cursor_2d = (index + 1) % POOL_2D
			return _pool_2d[index]
	var oldest := _pool_2d[_cursor_2d]
	_cursor_2d = (_cursor_2d + 1) % POOL_2D
	return oldest


## --- Continuous sound ----------------------------------------------------------------

func _process(scaled_delta: float) -> void:
	# Hit-stop slows Engine.time_scale. The mixer keeps real time, so the sound logic does too.
	var delta := scaled_delta / maxf(Engine.time_scale, 0.01)
	_clock += delta
	var speed := clampf(TrainState.speed_mps / REFERENCE_SPEED, 0.0, 2.0)
	_tick_tunnel(delta)
	_tick_presence(delta)
	_tick_train(speed, delta)
	_tick_wind(speed, delta)
	_tick_siren(delta)
	_tick_whistle()
	_duck_db = move_toward(_duck_db, 0.0, DUCK_RECOVERY * delta)
	var ambience := AudioServer.get_bus_index(BUS_AMBIENCE)
	AudioServer.set_bus_volume_db(ambience, AMBIENCE_DB + _duck_db)


func _tick_presence(delta: float) -> void:
	var target := OFF_TRAIN_LEVEL if _off_train else 1.0
	var rate := OFF_TRAIN_FADE if _off_train else REBOARD_FADE
	_train_presence = move_toward(_train_presence, target, rate * delta)


func _tick_train(speed: float, delta: float) -> void:
	var boom := (1.0 + tunnel_amount * 0.4) * _train_presence
	var openings := minf(_gusts.size() * 0.08, 0.3)
	var rumble_level := (0.16 + 0.62 * minf(speed, 1.3) + openings) * boom
	_fade_to(rumble, rumble_level, delta)
	rumble.pitch_scale = 0.62 + 0.42 * speed
	_fade_to(clack, minf(speed * 3.0, 1.0) * (0.72 + openings) * boom, delta)
	clack.pitch_scale = clampf(speed, 0.3, 2.0)


func _tick_wind(speed: float, delta: float) -> void:
	var count := 0
	for opening: Variant in _gusts.keys():
		var gust: AudioStreamPlayer3D = _gusts[opening]
		if not is_instance_valid(opening):
			_retire_gust(opening)
			continue
		count += 1
		gust.global_position = (opening as Node3D).global_position
		gust.volume_db = linear_to_db(move_toward(db_to_linear(gust.volume_db), minf(speed * GUST_LEVEL, GUST_LEVEL * 1.3), WIND_FADE_RATE * delta))
	for gust in _dying_gusts.duplicate():
		var fading := move_toward(db_to_linear(gust.volume_db), 0.0, WIND_FADE_RATE * delta)
		if fading <= 0.001:
			_dying_gusts.erase(gust)
			gust.queue_free()
		else:
			gust.volume_db = linear_to_db(fading)
	var level := 0.05 + 0.1 * speed + count * WIND_PER_OPENING * minf(speed, 1.3) + TrainState.blizzard * WIND_BLIZZARD
	level *= 1.0 - tunnel_amount * 0.5
	level += (1.0 - _train_presence) * OFF_TRAIN_WIND
	_fade_to(wind, minf(level, WIND_MAX), delta, WIND_FADE_RATE)
	wind.pitch_scale = 0.85 + 0.2 * speed + 0.25 * TrainState.blizzard


func _tick_tunnel(delta: float) -> void:
	if TrainState.in_tunnel != _was_in_tunnel:
		_was_in_tunnel = TrainState.in_tunnel
		play(&"whoosh", 2.0, 0.42, null, false, BUS_STINGER)
	var target := 1.0 if TrainState.in_tunnel else 0.0
	if is_equal_approx(tunnel_amount, target):
		return
	tunnel_amount = move_toward(tunnel_amount, target, TUNNEL_RATE * delta)
	ambience_filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF_HZ), log(TUNNEL_CUTOFF_HZ), tunnel_amount))
	_ambience_reverb.wet = lerpf(0.08, 0.6, tunnel_amount)
	_ambience_reverb.room_size = lerpf(0.35, 0.8, tunnel_amount)
	_sfx_reverb.wet = lerpf(0.0, 0.45, tunnel_amount)
	var sfx := AudioServer.get_bus_index(BUS_SFX)
	AudioServer.set_bus_effect_enabled(sfx, 0, tunnel_amount > 0.0)
	AudioServer.set_bus_effect_enabled(sfx, 1, tunnel_amount > 0.0)


func _tick_siren(delta: float) -> void:
	if not siren.playing:
		return
	_siren_quiet_for += delta
	if _siren_quiet_for > SIREN_TIMEOUT:
		_siren_level = 0.0
	_fade_to(siren, _siren_level, delta, 3.0)
	if _siren_level <= 0.0 and db_to_linear(siren.volume_db) <= 0.001:
		siren.stop()


func _tick_whistle() -> void:
	if _clock < _next_whistle:
		return
	_next_whistle = _clock + _rng.randf_range(WHISTLE_GAP.x, WHISTLE_GAP.y)
	# On Sfx, not Ambience: the train would bury it, and a tunnel should echo it.
	if play(&"whistle", -1.5, _rng.randf_range(0.94, 1.03)):
		_duck(WHISTLE_DUCK_DB)


func _fade_to(player: AudioStreamPlayer, level: float, delta: float, rate := LOOP_FADE_RATE) -> void:
	var current := db_to_linear(player.volume_db)
	player.volume_db = linear_to_db(maxf(move_toward(current, level, rate * delta), 0.0001))


func _duck(amount_db := DUCK_DB) -> void:
	_duck_db = minf(_duck_db, amount_db)


## --- Events --------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Hands:
		var hands := node as Hands
		_off_train = false  # A new player starts aboard; Main is rebuilt under this autoload.
		hands.threw.connect(_on_threw.bind(hands))
		hands.swung.connect(_on_swung.bind(hands))


func _on_threw(fraction: float, hands: Hands) -> void:
	play(&"whoosh", lerpf(-8.0, 1.0, fraction), lerpf(0.8, 1.35, fraction), _hands_position(hands))


func _on_swung(hit: bool, hands: Hands) -> void:
	# Hands emit this right after the bonk lands, so a hit on an npc already sounded.
	if hit:
		if _last_played.get(&"bonk", -1.0) != _clock and _last_played.get(&"punch", -1.0) != _clock:
			play(&"thud", -6.0, _rng.randf_range(1.0, 1.3), _hands_position(hands))
		return
	play(&"whoosh", -11.0, _rng.randf_range(1.5, 1.9), _hands_position(hands))


func _hands_position(hands: Hands) -> Variant:
	if hands.player != null and hands.player.is_inside_tree():
		return hands.player.global_position
	return null


func _on_npc_bonked(npc: Node3D, _attacker: Node3D, power: int) -> void:
	if power >= 2:
		# A heavier tool is louder and lower.
		var weight := clampf((power - 2) / BONK_HEAVY_RANGE, 0.0, 1.0)
		var pitch := lerpf(1.3, 0.75, weight) * _rng.randf_range(0.9, 1.1)
		play(&"bonk", lerpf(-3.0, 4.0, weight), pitch, npc.global_position)
	else:
		play(&"punch", -3.0, _rng.randf_range(0.85, 1.25), npc.global_position)


func _on_npc_knocked_out(npc: Node3D, _ragdoll: Node3D, _attacker: Node3D) -> void:
	play(&"ko", 1.0, _rng.randf_range(0.92, 1.08), npc.global_position)


func _on_impact(body: Node3D, position: Vector3, speed: float) -> void:
	if speed < IMPACT_MIN_SPEED:
		return
	var strength := clampf(inverse_lerp(IMPACT_MIN_SPEED, IMPACT_LOUD_SPEED, speed), 0.0, 1.0)
	var volume := lerpf(IMPACT_QUIET_DB, IMPACT_LOUD_DB, sqrt(strength))
	var pitch := lerpf(1.3, 0.72, strength) * _rng.randf_range(0.9, 1.1)
	play(_impact_sound(body), volume, pitch, position)


func _impact_sound(body: Node3D) -> StringName:
	if not is_instance_valid(body) or body is Ragdoll or body is RagdollPart:
		return &"thud"
	var prop := body as PhysicsProp
	if prop != null and METAL_PROPS.has(prop.kind):
		return &"clink"
	return &"clatter"


func _on_npc_panicked(_npc: Node3D, position: Vector3) -> void:
	play(&"shriek", 1.0, _rng.randf_range(0.9, 1.18), position)


func _on_body_hit_scenery(body: Node3D, speed: float) -> void:
	var volume := lerpf(-3.0, 6.0, clampf(speed / 30.0, 0.0, 1.0))
	var pitch := _rng.randf_range(0.82, 1.15)
	if is_instance_valid(body):
		play(&"crunch", volume, pitch, _body_position(body), true)
	else:
		play(&"crunch", volume, pitch)


func _body_position(body: Node3D) -> Vector3:
	if body.has_method("anchor"):
		return body.call("anchor")
	return body.global_position


func _on_opening_toggled(opening: Node3D, is_open: bool) -> void:
	var sound := &"window"
	if opening is TrainOpening and (opening as TrainOpening).kind == TrainOpening.Kind.DOOR:
		sound = &"door"
	var pitch := 1.08 if is_open else 0.9
	play(sound, 1.0, pitch * _rng.randf_range(0.97, 1.03), opening.global_position)
	if is_open:
		if not _gusts.has(opening):
			_add_gust(opening)
	elif _gusts.has(opening):
		_retire_gust(opening)


func _add_gust(opening: Node3D) -> void:
	var gust := AudioStreamPlayer3D.new()
	gust.bus = BUS_AMBIENCE
	gust.unit_size = 5.0
	gust.volume_db = -60.0
	gust.pitch_scale = _rng.randf_range(0.9, 1.2)
	add_child(gust)
	gust.global_position = opening.global_position
	_gusts[opening] = gust
	if _bank.has(&"wind"):
		_start_gust(gust)


func _start_gust(gust: AudioStreamPlayer3D) -> void:
	gust.stream = _bank[&"wind"][0]
	gust.play(_rng.randf_range(0.0, 4.0))


func _retire_gust(opening: Variant) -> void:
	_dying_gusts.append(_gusts[opening])
	_gusts.erase(opening)


func _on_object_yeeted(body: Node3D) -> void:
	var is_person := body is Ragdoll or body is RagdollPart
	if play(&"yeet", 3.0 if is_person else -1.0, _rng.randf_range(0.97, 1.05), null, false, BUS_STINGER):
		_duck()


func _on_score_awarded(points: int, _reason: String) -> void:
	if points > 0:
		combo = combo + 1 if _clock - _last_score_at < COMBO_WINDOW else 0
		_last_score_at = _clock
		var step := COMBO_STEPS[mini(combo, COMBO_STEPS.size() - 1)]
		var volume := minf(-3.0 + combo * 0.6, 2.0)
		var pitch := pow(2.0, step / 12.0)
		play(&"ding", volume, pitch, null, false, BUS_STINGER)
		if step >= COMBO_BODY_STEP:
			play(&"ding", volume - 4.0, pitch * 0.5, null, false, BUS_STINGER)
	elif points < 0:
		_reset_combo()
		play(&"buzzer", 0.0, 1.0, null, false, BUS_STINGER)


func _reset_combo() -> void:
	combo = 0
	_last_score_at = -1000.0


func _on_round_started(_number: int, _stowaways: int, _seconds: int) -> void:
	_reset_combo()
	_siren_level = 0.0
	play(&"round_start", 0.0, 1.0, null, false, BUS_STINGER)


func _on_raid_warning(seconds_left: int) -> void:
	var urgency := 1.0 - clampf(seconds_left / 10.0, 0.0, 1.0)
	var sound := &"tock" if _tock_next else &"tick"
	_tock_next = not _tock_next
	play(sound, lerpf(-1.0, 5.0, urgency), lerpf(1.0, 1.3, urgency), null, false, BUS_STINGER)
	if not _bank.has(&"siren"):
		return
	_siren_quiet_for = 0.0
	_siren_level = lerpf(0.3, 0.8, urgency)
	siren.pitch_scale = lerpf(1.0, 1.32, urgency)
	if not siren.playing:
		siren.volume_db = -40.0
		siren.play()


func _on_round_ended(_score: int, passed: bool) -> void:
	_siren_level = 0.0
	_reset_combo()
	_duck()
	play(&"win" if passed else &"lose", 2.0, 1.0, null, false, BUS_STINGER)


func _on_player_left_train(player: Node3D) -> void:
	_off_train = true
	play(&"whoosh", 3.0, 0.7, player.global_position)


func _on_player_left_behind(_player: Node3D) -> void:
	_off_train = false  # The player respawns aboard straight after this event.
	play(&"buzzer", -2.0, 0.8, null, false, BUS_STINGER)


## Quiet on purpose. Every round start respawns the player, and so does the clipboard.
func _on_player_respawned(_player: Node3D) -> void:
	_off_train = false


func _on_player_reboarded(_player: Node3D) -> void:
	_off_train = false
	play(&"ding", -4.0, 0.75, null, false, BUS_STINGER)

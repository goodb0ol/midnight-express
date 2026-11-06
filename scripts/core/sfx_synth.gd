class_name SfxSynth
extends RefCounted
## Every sound in the game, synthesized from nothing. Pure functions over sample buffers,
## with no scene tree access, so Sfx can run them on a background thread.
##
## Add a sound: add an entry to BANK, then a case in _recipe(). Hear it by triggering its
## event; tune by ear with the numbers in its recipe.

const RATE := 22050
const DT := 1.0 / RATE

## name -> number of variants. Rendered in this order, so the first sounds of a round
## and the loops that stop the game being silent come first.
const BANK: Dictionary = {
	&"round_start": 1, &"rumble": 1, &"clack": 1, &"wind": 1,
	&"bonk": 3, &"punch": 2, &"whoosh": 1, &"yeet": 1, &"ding": 1, &"buzzer": 1,
	&"thud": 2, &"clatter": 2, &"clink": 1, &"crunch": 2, &"shriek": 3, &"ko": 1,
	&"door": 1, &"window": 1, &"tick": 1, &"tock": 1, &"siren": 1,
	&"win": 1, &"lose": 1, &"whistle": 1,
}
const LOOPS: Array[StringName] = [&"rumble", &"clack", &"wind", &"siren"]

const SINE := 0
const TRIANGLE := 1
const SAW := 2
const SQUARE := 3

## First three formants in Hz.
const AH := Vector3(850.0, 1250.0, 2900.0)
const EE := Vector3(300.0, 2500.0, 3300.0)
const EH := Vector3(620.0, 1800.0, 2600.0)
const OH := Vector3(480.0, 850.0, 2800.0)

const SVF_MAX_HZ := 4500.0  ## Above this the filter is unstable at this sample rate.


## Renders one variant of one sound into a ready-to-play stream.
static func render(sound: StringName, variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound) + variant * 7919
	var samples := _recipe(sound, variant, rng)
	return to_stream(samples, LOOPS.has(sound))


static func _recipe(sound: StringName, variant: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		&"bonk": return _bonk(rng, [310.0, 395.0, 250.0][variant])
		&"punch": return _punch(rng, [230.0, 185.0][variant])
		&"whoosh": return _whoosh(rng)
		&"yeet": return _yeet(rng)
		&"ding": return _ding()
		&"buzzer": return _buzzer()
		&"thud": return _thud(rng, [190.0, 160.0][variant])
		&"clatter": return _clatter(rng, [310.0, 430.0][variant])
		&"clink": return _clink()
		&"crunch": return _crunch(rng)
		&"shriek": return _shriek(rng, [1.0, 1.28, 0.8][variant])
		&"ko": return _knockout()
		&"door": return _door(rng)
		&"window": return _window(rng)
		&"tick": return _tick(rng, 2100.0)
		&"tock": return _tick(rng, 1380.0)
		&"siren": return _siren_loop()
		&"round_start": return _round_start()
		&"win": return _win()
		&"lose": return _lose()
		&"rumble": return _rumble_loop(rng)
		&"clack": return _clack_loop(rng)
		&"wind": return _wind_loop(rng)
		&"whistle": return _steam_whistle(rng)
	push_error("SfxSynth: no recipe for %s" % sound)
	return buffer(0.1)


## --- Building blocks -----------------------------------------------------------------

static func buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(roundi(seconds * RATE))
	out.fill(0.0)
	return out


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Adds an oscillator. With options.glide > 0 the pitch drops from f0 and settles on f1
## at that rate per second (the cartoon "bwop"); otherwise it slides evenly across dur.
## Options: decay, glide, wave, vib_hz, vib, attack, release.
static func tone(out: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float, options: Dictionary = {}) -> void:
	var decay: float = options.get("decay", 0.0)
	var glide: float = options.get("glide", 0.0)
	var wave: int = options.get("wave", SINE)
	var vib_hz: float = options.get("vib_hz", 0.0)
	var vib: float = options.get("vib", 0.0)
	var attack: float = options.get("attack", 0.002)
	var release: float = options.get("release", 0.008)
	var from := roundi(start * RATE)
	var count := mini(roundi(dur * RATE), out.size() - from)
	var ratio := f1 / f0
	var phase := 0.0
	for i in count:
		var t := i * DT
		var freq: float
		if glide > 0.0:
			freq = f1 + (f0 - f1) * exp(-t * glide)
		else:
			freq = f0 * pow(ratio, t / dur)
		if vib > 0.0:
			freq *= 1.0 + vib * sin(TAU * vib_hz * t)
		phase += freq * DT
		phase -= floorf(phase)
		var s: float
		if wave == SINE:
			s = sin(TAU * phase)
		elif wave == SAW:
			s = 2.0 * phase - 1.0
		elif wave == SQUARE:
			s = 1.0 if phase < 0.5 else -1.0
		else:
			s = 4.0 * absf(phase - 0.5) - 1.0
		var envelope := amp * exp(-t * decay)
		if t < attack:
			envelope *= t / attack
		var left := dur - t
		if left < release:
			envelope *= left / release
		out[from + i] += s * envelope


## Adds band-limited noise. Options: decay, attack, release.
static func noise(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float, amp: float, low_hz: float, high_hz: float, options: Dictionary = {}) -> void:
	var decay: float = options.get("decay", 0.0)
	var attack: float = options.get("attack", 0.001)
	var release: float = options.get("release", 0.008)
	var from := roundi(start * RATE)
	var count := mini(roundi(dur * RATE), out.size() - from)
	var low_rate := 1.0 - exp(-TAU * high_hz * DT)
	var high_rate := 1.0 - exp(-TAU * low_hz * DT)
	var low := 0.0
	var high := 0.0
	for i in count:
		var t := i * DT
		low += (rng.randf_range(-1.0, 1.0) - low) * low_rate
		high += (low - high) * high_rate
		var envelope := amp * exp(-t * decay)
		if t < attack:
			envelope *= t / attack
		var left := dur - t
		if left < release:
			envelope *= left / release
		out[from + i] += (low - high) * envelope


## Adds noise through a resonant band that sweeps from f0 to f1, in a smooth swell.
static func swept_noise(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float, amp: float, f0: float, f1: float, resonance: float) -> void:
	var from := roundi(start * RATE)
	var count := mini(roundi(dur * RATE), out.size() - from)
	var damping := 1.0 / resonance
	var low := 0.0
	var band := 0.0
	for i in count:
		var progress := float(i) / count
		var f := 2.0 * sin(PI * minf(f0 * pow(f1 / f0, progress), SVF_MAX_HZ) * DT)
		var high := rng.randf_range(-1.0, 1.0) - low - damping * band
		band += f * high
		low += f * band
		var swell := sin(PI * pow(progress, 0.7))
		out[from + i] += band * amp * swell * swell


## Adds a sawtooth voice through three formant filters, gliding between two vowels.
## Options: vib_hz, vib, attack, release, breath.
static func voice(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float, f0: float, f1: float, amp: float, vowel_from: Vector3, vowel_to: Vector3, options: Dictionary = {}) -> void:
	var vib_hz: float = options.get("vib_hz", 0.0)
	var vib: float = options.get("vib", 0.0)
	var attack: float = options.get("attack", 0.02)
	var release: float = options.get("release", 0.05)
	var breath: float = options.get("breath", 0.15)
	var from := roundi(start * RATE)
	var count := mini(roundi(dur * RATE), out.size() - from)
	var phase := 0.0
	var lows := Vector3.ZERO
	var bands := Vector3.ZERO
	var coefficients := Vector3.ZERO
	for i in count:
		var t := i * DT
		var progress := float(i) / count
		if i % 32 == 0:
			var vowel := vowel_from.lerp(vowel_to, progress)
			coefficients = Vector3(
				2.0 * sin(PI * minf(vowel.x, SVF_MAX_HZ) * DT),
				2.0 * sin(PI * minf(vowel.y, SVF_MAX_HZ) * DT),
				2.0 * sin(PI * minf(vowel.z, SVF_MAX_HZ) * DT))
		var freq := f0 * pow(f1 / f0, progress) * (1.0 + vib * sin(TAU * vib_hz * t))
		phase += freq * DT
		phase -= floorf(phase)
		var source := 2.0 * phase - 1.0 + rng.randf_range(-breath, breath)
		var s := 0.0
		for formant in 3:
			var high := source - lows[formant] - 0.12 * bands[formant]
			bands[formant] += coefficients[formant] * high
			lows[formant] += coefficients[formant] * bands[formant]
			s += bands[formant] * (1.0 if formant == 0 else 0.6)
		var envelope := amp
		if t < attack:
			envelope *= t / attack
		var left := dur - t
		if left < release:
			envelope *= left / release
		out[from + i] += s * envelope


static func lowpass(out: PackedFloat32Array, cutoff_hz: float) -> void:
	var rate := 1.0 - exp(-TAU * cutoff_hz * DT)
	var low := 0.0
	for i in out.size():
		low += (out[i] - low) * rate
		out[i] = low


## Soft-clips, which is most of what makes a hit sound fat.
static func drive(out: PackedFloat32Array, gain: float) -> void:
	for i in out.size():
		var s := out[i] * gain
		out[i] = s / (1.0 + absf(s))


static func normalize(out: PackedFloat32Array, peak: float) -> void:
	var highest := 0.0
	for s in out:
		highest = maxf(highest, absf(s))
	if highest < 0.000001:
		return
	var gain := peak / highest
	for i in out.size():
		out[i] *= gain


## Folds the last fade seconds over the start so noise loops have no seam, and trims them off.
static func close_loop(out: PackedFloat32Array, fade: float) -> void:
	var fade_samples := roundi(fade * RATE)
	var loop_samples := out.size() - fade_samples
	for i in fade_samples:
		var mix := float(i) / fade_samples * PI * 0.5
		out[i] = out[i] * sin(mix) + out[loop_samples + i] * cos(mix)
	out.resize(loop_samples)


static func to_stream(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## --- Hits ----------------------------------------------------------------------------

## A hollow wooden knock whose pitch falls off a cliff, over a sub drop and a little wobble.
static func _bonk(rng: RandomNumberGenerator, root: float) -> PackedFloat32Array:
	var out := buffer(0.5)
	tone(out, 0.0, 0.42, root * 4.0, root, 1.0, {"decay": 11.0, "glide": 42.0})
	tone(out, 0.0, 0.2, root * 7.0, root * 2.76, 0.7, {"decay": 22.0, "glide": 60.0})
	tone(out, 0.0, 0.5, root * 0.6, root * 0.33, 0.75, {"decay": 9.0, "glide": 20.0})
	tone(out, 0.05, 0.36, root * 1.5, root * 1.14, 0.22, {"decay": 7.0, "vib_hz": 24.0, "vib": 0.11, "attack": 0.02})
	noise(out, rng, 0.0, 0.02, 2.2, 700.0, 7000.0, {"decay": 150.0})
	drive(out, 3.0)
	normalize(out, 0.98)
	return out


static func _punch(rng: RandomNumberGenerator, root: float) -> PackedFloat32Array:
	var out := buffer(0.26)
	tone(out, 0.0, 0.24, root * 3.0, root * 1.6, 0.8, {"decay": 17.0, "glide": 55.0})
	noise(out, rng, 0.0, 0.07, 3.6, 400.0, 3400.0, {"decay": 55.0})
	drive(out, 3.5)
	normalize(out, 0.9)
	return out


static func _thud(rng: RandomNumberGenerator, root: float) -> PackedFloat32Array:
	var out := buffer(0.3)
	tone(out, 0.0, 0.3, root * 3.0, root * 1.7, 0.8, {"decay": 15.0, "glide": 38.0})
	noise(out, rng, 0.0, 0.1, 2.6, 200.0, 1400.0, {"decay": 32.0})
	noise(out, rng, 0.0, 0.03, 0.7, 900.0, 3000.0, {"decay": 110.0})
	drive(out, 2.4)
	normalize(out, 0.92)
	return out


static func _clatter(rng: RandomNumberGenerator, root: float) -> PackedFloat32Array:
	var out := buffer(0.28)
	for hit in 3:
		var at := [0.0, 0.055, 0.12][hit] as float
		var level := [1.0, 0.45, 0.25][hit] as float
		tone(out, at, 0.12, root * rng.randf_range(0.95, 1.1), root * 0.9, level, {"decay": 42.0})
		tone(out, at, 0.08, root * 2.71, root * 2.6, level * 0.5, {"decay": 70.0})
		noise(out, rng, at, 0.02, level * 0.8, 800.0, 5000.0, {"decay": 180.0})
	drive(out, 1.8)
	normalize(out, 0.85)
	return out


## Metal on anything: wrench, frying pan.
static func _clink() -> PackedFloat32Array:
	var out := buffer(0.45)
	for partial: Vector3 in [Vector3(640.0, 1.0, 9.0), Vector3(1730.0, 0.7, 13.0), Vector3(2870.0, 0.5, 19.0), Vector3(4120.0, 0.3, 27.0)]:
		tone(out, 0.0, 0.45, partial.x, partial.x * 0.998, partial.y, {"decay": partial.z})
	normalize(out, 0.8)
	return out


## Crackling twigs and bad decisions over a wet thump.
static func _crunch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(0.5)
	tone(out, 0.0, 0.3, 190.0, 58.0, 1.0, {"decay": 11.0, "glide": 30.0})
	noise(out, rng, 0.0, 0.16, 2.2, 160.0, 1100.0, {"decay": 22.0})
	var at := 0.0
	for crack in 11:
		var level := 1.5 * exp(-at * 7.0)
		noise(out, rng, at, 0.022, level, rng.randf_range(700.0, 1500.0), rng.randf_range(3000.0, 7000.0), {"decay": 170.0})
		at += rng.randf_range(0.012, 0.05)
	tone(out, 0.19, 0.2, 340.0, 120.0, 0.4, {"decay": 19.0, "wave": SQUARE})
	drive(out, 4.0)
	normalize(out, 0.98)
	return out


## Bonk, cartoon bell clang, then a sagging spring: somebody is out cold.
static func _knockout() -> PackedFloat32Array:
	var out := buffer(1.15)
	for partial: Vector3 in [Vector3(392.0, 1.0, 4.0), Vector3(1047.0, 0.8, 6.0), Vector3(1730.0, 0.6, 9.0), Vector3(2640.0, 0.4, 14.0)]:
		tone(out, 0.0, 0.9, partial.x, partial.x, partial.y, {"decay": partial.z})
	tone(out, 0.0, 0.4, 320.0, 72.0, 1.2, {"decay": 9.0, "glide": 30.0})
	tone(out, 0.16, 0.95, 980.0, 170.0, 0.55, {"vib_hz": 17.0, "vib": 0.16, "wave": TRIANGLE, "attack": 0.02, "release": 0.2})
	drive(out, 1.6)
	normalize(out, 0.95)
	return out


static func _whoosh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(0.42)
	swept_noise(out, rng, 0.0, 0.42, 1.0, 420.0, 2900.0, 3.0)
	swept_noise(out, rng, 0.02, 0.32, 0.6, 1100.0, 3600.0, 5.0)
	normalize(out, 0.9)
	return out


## --- Voices --------------------------------------------------------------------------

static func _shriek(rng: RandomNumberGenerator, scale: float) -> PackedFloat32Array:
	var out := buffer(0.72)
	var top := 1120.0 * scale
	voice(out, rng, 0.0, 0.2, 560.0 * scale, top, 0.9, AH * 1.15, EE * 1.1, {"attack": 0.015, "release": 0.02})
	voice(out, rng, 0.17, 0.55, top, 520.0 * scale, 1.0, EE * 1.1, EH * 1.2, {"vib_hz": 12.0, "vib": 0.05, "attack": 0.02, "release": 0.16})
	drive(out, 1.6)
	normalize(out, 0.75)
	return out


## The shout, a brass stab under it, and a slide whistle falling away with the body.
static func _yeet(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(1.55)
	voice(out, rng, 0.0, 0.46, 340.0, 470.0, 1.0, EH, EE * 1.1, {"attack": 0.03, "release": 0.03, "vib_hz": 9.0, "vib": 0.02})
	voice(out, rng, 0.0, 0.46, 172.0, 236.0, 0.9, EH, EE, {"attack": 0.03, "release": 0.03})
	noise(out, rng, 0.46, 0.04, 2.0, 2200.0, 8000.0, {"decay": 90.0})
	for midi: float in [55.0, 62.0, 67.0, 74.0]:
		tone(out, 0.02, 0.4, hz(midi), hz(midi), 0.32, {"wave": SAW, "attack": 0.01, "release": 0.1, "decay": 3.0})
	drive(out, 1.5)
	tone(out, 0.4, 1.12, 2350.0, 310.0, 0.62, {"vib_hz": 7.5, "vib": 0.018, "attack": 0.03, "release": 0.16})
	tone(out, 0.4, 1.12, 4700.0, 620.0, 0.1, {"vib_hz": 7.5, "vib": 0.018, "attack": 0.03, "release": 0.16})
	noise(out, rng, 0.4, 1.1, 0.14, 1200.0, 5000.0, {"attack": 0.03, "release": 0.3})
	normalize(out, 0.98)
	return out


## --- The train's bits ----------------------------------------------------------------

## Heavy iron: a latch, the slide, the stop.
static func _door(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(0.62)
	for hit in 2:
		var at := 0.0 if hit == 0 else 0.1
		var level := 0.7 if hit == 0 else 1.0
		for partial: Vector3 in [Vector3(138.0, 1.0, 11.0), Vector3(311.0, 0.8, 15.0), Vector3(587.0, 0.6, 21.0), Vector3(1166.0, 0.4, 32.0)]:
			tone(out, at, 0.5, partial.x, partial.x * 0.97, partial.y * level, {"decay": partial.z})
		noise(out, rng, at, 0.03, 1.2 * level, 500.0, 5000.0, {"decay": 120.0})
	noise(out, rng, 0.02, 0.32, 0.3, 200.0, 900.0, {"release": 0.1})
	drive(out, 2.6)
	normalize(out, 0.92)
	return out


## Thin frame and rattling glass.
static func _window(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(0.4)
	for partial: Vector3 in [Vector3(420.0, 0.9, 20.0), Vector3(980.0, 0.7, 28.0), Vector3(2230.0, 0.5, 34.0), Vector3(3470.0, 0.35, 42.0)]:
		tone(out, 0.0, 0.3, partial.x, partial.x, partial.y, {"decay": partial.z})
		tone(out, 0.07, 0.25, partial.x * 1.03, partial.x * 1.03, partial.y * 0.4, {"decay": partial.z * 1.3})
	for rattle in 5:
		noise(out, rng, 0.04 + rattle * 0.045, 0.02, 0.5 * exp(-rattle * 0.6), 1500.0, 6000.0, {"decay": 140.0})
	drive(out, 1.8)
	normalize(out, 0.85)
	return out


static func _tick(rng: RandomNumberGenerator, pitch: float) -> PackedFloat32Array:
	var out := buffer(0.09)
	tone(out, 0.0, 0.09, pitch, pitch * 0.96, 1.0, {"decay": 72.0})
	tone(out, 0.0, 0.05, pitch * 0.37, pitch * 0.33, 0.8, {"decay": 90.0})
	noise(out, rng, 0.0, 0.008, 0.8, 1500.0, 7000.0, {"decay": 300.0})
	drive(out, 2.0)
	normalize(out, 0.9)
	return out


## A wailing siren with a buzz in it. Whole cycles, so this loop has no seam.
static func _siren_loop() -> PackedFloat32Array:
	var seconds := 2.0
	var out := buffer(seconds)
	var center := 700.0  # 1400 whole cycles in the loop, so the phase closes exactly.
	var depth := 300.0
	var phase := 0.0
	var count := out.size()
	for i in count:
		var progress := float(i) / count
		var freq := center + depth * sin(TAU * progress - PI * 0.5)
		phase += freq * DT
		phase -= floorf(phase)
		var s := 4.0 * absf(phase - 0.5) - 1.0
		s += 0.55 * (2.0 * phase - 1.0)
		s += 0.35 * sin(TAU * fposmod(phase * 2.0, 1.0))
		out[i] = s
	drive(out, 1.8)
	normalize(out, 0.9)
	return out


## One long wail up and down with a warning bell on top: the raid is coming.
static func _round_start() -> PackedFloat32Array:
	var out := buffer(2.7)
	tone(out, 0.0, 1.1, 240.0, 930.0, 0.75, {"wave": TRIANGLE, "attack": 0.1, "release": 0.01})
	tone(out, 0.0, 1.1, 243.0, 936.0, 0.3, {"wave": SAW, "attack": 0.1, "release": 0.01})
	tone(out, 1.09, 0.5, 930.0, 930.0, 0.75, {"wave": TRIANGLE, "attack": 0.01, "release": 0.01})
	tone(out, 1.09, 0.5, 936.0, 936.0, 0.3, {"wave": SAW, "attack": 0.01, "release": 0.01})
	tone(out, 1.58, 1.1, 930.0, 210.0, 0.75, {"wave": TRIANGLE, "attack": 0.01, "release": 0.3})
	tone(out, 1.58, 1.1, 936.0, 212.0, 0.3, {"wave": SAW, "attack": 0.01, "release": 0.3})
	for ring in 6:
		var at := ring * 0.22
		tone(out, at, 0.22, 1568.0, 1568.0, 0.28, {"decay": 11.0})
		tone(out, at, 0.22, 2489.0, 2489.0, 0.16, {"decay": 15.0})
	lowpass(out, 5200.0)
	drive(out, 1.5)
	normalize(out, 0.92)
	return out


static func _rumble_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var fade := 0.3
	var out := buffer(4.0 + fade)
	var deep := 0.0
	var growl := 0.0
	for i in out.size():
		var t := i * DT
		var white := rng.randf_range(-1.0, 1.0)
		deep += (white - deep) * 0.018
		growl += (white - growl) * 0.09
		var throb := 0.75 + 0.25 * sin(TAU * 1.75 * t)
		out[i] = (deep * 9.0 + (growl - deep) * 1.1) * throb + 0.2 * sin(TAU * 47.0 * t) + 0.12 * sin(TAU * 71.0 * t)
	close_loop(out, fade)
	drive(out, 1.6)
	normalize(out, 0.9)
	return out


## Two bogies crossing a rail joint, and the engine chuffing underneath.
## Played at pitch 1.0 at REFERENCE speed, so faster train means faster clicks.
static func _clack_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(1.6)
	for at: float in [0.0, 0.4, 0.8, 1.2]:
		noise(out, rng, at, 0.3, 0.5, 220.0, 1500.0, {"decay": 13.0, "attack": 0.02, "release": 0.05})
	var joints := [[0.02, 1.0], [0.145, 0.8], [0.82, 0.92], [0.945, 0.72]]
	for joint: Array in joints:
		var at: float = joint[0]
		var level: float = joint[1]
		noise(out, rng, at, 0.06, 1.7 * level, 900.0, 5000.0, {"decay": 75.0})
		tone(out, at, 0.1, 340.0, 170.0, 0.9 * level, {"decay": 38.0, "glide": 70.0})
		tone(out, at, 0.05, 1480.0, 1450.0, 0.3 * level, {"decay": 100.0})
	drive(out, 1.7)
	normalize(out, 0.9)
	return out


static func _wind_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var fade := 0.4
	var out := buffer(5.0 + fade)
	var low := 0.0
	var band := 0.0
	var low_two := 0.0
	var band_two := 0.0
	for i in out.size():
		var t := i * DT
		var gust := 0.5 + 0.5 * sin(TAU * 0.4 * t) * sin(TAU * 0.6 * t + 1.0)
		var white := rng.randf_range(-1.0, 1.0)
		var f := 2.0 * sin(PI * (340.0 + 520.0 * gust) * DT)
		var high := white - low - 0.22 * band
		band += f * high
		low += f * band
		var f_two := 2.0 * sin(PI * (1100.0 + 900.0 * gust) * DT)
		var high_two := white - low_two - 0.09 * band_two
		band_two += f_two * high_two
		low_two += f_two * band_two
		out[i] = (band * 0.8 + band_two * 0.18 * gust) * (0.55 + 0.45 * gust)
	close_loop(out, fade)
	normalize(out, 0.85)
	return out


## Three sagging notes a long way off. A steam chime in a sad key.
static func _steam_whistle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := buffer(5.2)
	_blast(out, rng, 0.0, 1.1, 0.0)
	_blast(out, rng, 1.25, 1.1, -1.0)
	_blast(out, rng, 2.5, 2.7, -3.0)
	lowpass(out, 2800.0)
	normalize(out, 0.85)
	return out


## One note of the chime, [param drop] semitones under the first, sagging as it dies.
static func _blast(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float, drop: float) -> void:
	var shape := {"wave": TRIANGLE, "vib_hz": 4.6, "vib": 0.004, "attack": 0.18, "release": 0.65}
	for note: float in [51.0, 58.0, 62.0, 66.0]:
		var pitch := hz(note + 12.0 + drop)
		tone(out, start, dur, pitch, pitch * 0.96, 0.3, shape)
		tone(out, start, dur, pitch * 1.005, pitch * 0.965, 0.12, shape)
	noise(out, rng, start, dur, 0.5, 700.0, 2600.0, {"attack": 0.12, "release": 0.7})


## --- Score and result ----------------------------------------------------------------

static func _ding() -> PackedFloat32Array:
	var out := buffer(0.75)
	for partial: Vector3 in [Vector3(880.0, 1.0, 5.0), Vector3(1760.0, 0.5, 8.0), Vector3(2649.0, 0.3, 13.0), Vector3(3520.0, 0.14, 20.0)]:
		tone(out, 0.0, 0.75, partial.x, partial.x, partial.y, {"decay": partial.z, "attack": 0.001, "release": 0.05})
	normalize(out, 0.85)
	return out


static func _buzzer() -> PackedFloat32Array:
	var out := buffer(0.6)
	for blip in 2:
		var at := blip * 0.3
		tone(out, at, 0.25, 166.0, 147.0, 0.5, {"wave": SQUARE, "release": 0.02})
		tone(out, at, 0.25, 176.0, 156.0, 0.5, {"wave": SAW, "release": 0.02})
	lowpass(out, 1800.0)
	drive(out, 2.0)
	normalize(out, 0.8)
	return out


static func _brass(out: PackedFloat32Array, start: float, dur: float, midi: float, amp: float) -> void:
	var pitch := hz(midi)
	var shape := {"wave": SAW, "attack": 0.012, "release": 0.04, "decay": 1.6}
	tone(out, start, dur, pitch, pitch, amp, shape)
	tone(out, start, dur, pitch * 1.004, pitch * 1.004, amp * 0.6, shape)
	tone(out, start, dur, pitch * 0.5, pitch * 0.5, amp * 0.4, {"wave": SQUARE, "attack": 0.012, "release": 0.04, "decay": 1.6})


## A bouncing little brass run that lands on a big chord and two toots of the whistle.
static func _win() -> PackedFloat32Array:
	var out := buffer(2.5)
	var at := 0.0
	for step: Vector2 in [Vector2(65, 0.11), Vector2(69, 0.11), Vector2(72, 0.11), Vector2(77, 0.2), Vector2(74, 0.11), Vector2(77, 0.2), Vector2(81, 0.11)]:
		_brass(out, at, step.y + 0.05, step.x, 0.42)
		at += step.y
	for midi: float in [65.0, 72.0, 77.0, 81.0, 84.0]:
		_brass(out, at, 0.8, midi, 0.3)
	at += 0.72
	for toot in 2:
		for midi: float in [77.0, 81.0, 84.0]:
			tone(out, at + toot * 0.26, 0.22, hz(midi), hz(midi), 0.26, {"wave": TRIANGLE, "attack": 0.02, "release": 0.05})
	lowpass(out, 3600.0)
	drive(out, 1.4)
	normalize(out, 0.95)
	return out


## A tuba losing the will to continue.
static func _lose() -> PackedFloat32Array:
	var out := buffer(3.0)
	var at := 0.0
	for midi: float in [46.0, 45.0, 44.0]:
		tone(out, at, 0.42, hz(midi) * 1.02, hz(midi), 0.8, {"wave": SAW, "attack": 0.03, "release": 0.08, "glide": 18.0})
		tone(out, at, 0.42, hz(midi + 12.0), hz(midi + 12.0), 0.3, {"wave": SAW, "attack": 0.03, "release": 0.08})
		at += 0.46
	tone(out, at, 1.3, hz(43.0), hz(35.0), 0.9, {"wave": SAW, "vib_hz": 5.5, "vib": 0.035, "attack": 0.03, "release": 0.3})
	tone(out, at, 1.3, hz(55.0), hz(47.0), 0.3, {"wave": SAW, "vib_hz": 5.5, "vib": 0.035, "attack": 0.03, "release": 0.3})
	lowpass(out, 1500.0)
	drive(out, 1.5)
	normalize(out, 0.92)
	return out

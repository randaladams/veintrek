extends Node
## Synthesised sound effects (autoload "Sfx"). No audio files needed:
## every sound is generated into an AudioStreamWAV at startup.

const RATE := 22050
const HEART_PERIOD := 0.9

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _heart: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_build()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_heart = AudioStreamPlayer.new()
	_heart.stream = _streams["heart"]
	_heart.volume_db = -3.0
	add_child(_heart)
	_hum = AudioStreamPlayer.new()
	_hum.stream = _streams["hum"]
	_hum.volume_db = -12.0
	add_child(_hum)


func start_ambience() -> void:
	if not _heart.playing:
		_heart.play()
	if not _hum.playing:
		_hum.play()


func play(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(id):
		return
	var p: AudioStreamPlayer = null
	for k in _players.size():
		var cand := _players[(_next + k) % _players.size()]
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## 0..1 pulse that follows the "lub-dub" of the heartbeat loop.
func beat_value() -> float:
	var t: float
	if _heart and _heart.playing:
		t = fmod(_heart.get_playback_position(), HEART_PERIOD)
	else:
		t = fmod(Time.get_ticks_msec() / 1000.0, HEART_PERIOD)
	var v := exp(-t * 9.0)
	if t > 0.27:
		v += 0.6 * exp(-(t - 0.27) * 9.0)
	return clampf(v, 0.0, 1.0)


# --- Synthesis ----------------------------------------------------------------

func _build() -> void:
	_streams["laser"] = _wav(_laser())
	_streams["enemy_shot"] = _wav(_enemy_shot())
	_streams["splat"] = _wav(_splat())
	_streams["thud"] = _wav(_thud())
	_streams["crack"] = _wav(_crack(0.3))
	_streams["scrape"] = _wav(_scrape())
	_streams["shatter"] = _wav(_crack(1.3))
	_streams["repair"] = _wav(_arp([523.0, 659.0, 784.0, 1047.0], 0.08, 0.5))
	_streams["upgrade"] = _wav(_arp([392.0, 523.0, 659.0, 784.0, 1047.0], 0.06, 0.6, true))
	_streams["victory"] = _wav(_arp([392.0, 494.0, 587.0, 784.0, 988.0, 1175.0], 0.12, 1.4))
	_streams["squish"] = _wav(_squish())
	_streams["alarm"] = _wav(_alarm())
	_streams["blip"] = _wav(_arp([880.0, 1320.0], 0.07, 0.2))
	_streams["go"] = _wav(_arp([660.0, 990.0], 0.1, 0.3, true))
	_streams["heart"] = _wav(_heartbeat(), true)
	_streams["hum"] = _wav(_hum_loop(), true)


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _laser() -> PackedFloat32Array:
	var b := _buf(0.16)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 1700.0 * exp(-t * 20.0) + 260.0
		ph += f / RATE
		var sq := 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		b[i] = (sq * 0.5 + saw * 0.5) * exp(-t * 20.0) * 0.45
	return b


func _enemy_shot() -> PackedFloat32Array:
	var b := _buf(0.22)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 180.0 + 520.0 * (t / 0.22) + 40.0 * sin(t * 90.0)
		ph += f / RATE
		b[i] = sin(ph * TAU) * sin(ph * TAU * 0.5) * exp(-t * 9.0) * 0.5
	return b


func _splat() -> PackedFloat32Array:
	var b := _buf(0.4)
	var lp := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cutoff := clampf(0.5 * exp(-t * 6.0), 0.02, 0.5)
		lp += (_rng.randf_range(-1, 1) - lp) * cutoff
		ph += (120.0 * exp(-t * 8.0) + 50.0) / RATE
		b[i] = (lp * 1.6 * exp(-t * 9.0) + sin(ph * TAU) * exp(-t * 18.0) * 0.6) * 0.6
	return b


func _thud() -> PackedFloat32Array:
	var b := _buf(0.35)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (90.0 * exp(-t * 10.0) + 40.0) / RATE
		b[i] = sin(ph * TAU) * exp(-t * 12.0) * 0.8
	return b


func _crack(dur: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var hp_prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1, 1)
		var hp := n - hp_prev
		hp_prev = n
		var spike := 0.0
		if _rng.randf() < 0.012 * exp(-t * 3.0):
			spike = _rng.randf_range(-1, 1)
		b[i] = (hp * 0.35 * exp(-t * (14.0 / dur)) + spike * 0.9) * 0.7
	return b


func _scrape() -> PackedFloat32Array:
	var b := _buf(0.45)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.15
		var grit := 1.0 + 0.6 * sin(t * 260.0)
		b[i] = lp * grit * sin(PI * t / 0.45) * 0.9
	return b


func _arp(notes: Array, step: float, dur: float, square: bool = false) -> PackedFloat32Array:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var idx := mini(int(t / step), notes.size() - 1)
		var nt := t - idx * step
		var f: float = notes[idx]
		var w := sin(TAU * f * t)
		if square:
			w = 0.6 * signf(w) + 0.4 * w
		var env := exp(-nt * 10.0) * 0.7 + 0.3 * exp(-t * 3.0)
		b[i] = w * env * 0.32 * (1.0 - t / dur)
	return b


func _squish() -> PackedFloat32Array:
	var b := _buf(0.35)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (160.0 * exp(-t * 4.0) + 55.0 + 30.0 * sin(t * 60.0)) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.05
		b[i] = (sin(ph * TAU) * 0.6 + lp * 1.5) * sin(PI * t / 0.35) * 0.6
	return b


func _alarm() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var on := 1.0 if fmod(t, 0.15) < 0.1 else 0.0
		b[i] = signf(sin(TAU * 880.0 * t)) * on * 0.18
	return b


func _heartbeat() -> PackedFloat32Array:
	var b := _buf(HEART_PERIOD)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for pulse in [[0.0, 58.0, 0.9], [0.27, 72.0, 0.6]]:
			var dt: float = t - float(pulse[0])
			if dt >= 0.0:
				var f: float = float(pulse[1]) * (1.0 + 0.6 * exp(-dt * 30.0))
				v += sin(TAU * f * dt) * exp(-dt * 16.0) * float(pulse[2]) * minf(dt * 200.0, 1.0)
		b[i] = v * 0.9
	return b


func _hum_loop() -> PackedFloat32Array:
	var dur := 3.0
	var fade := int(0.3 * RATE)
	var raw := _buf(dur + 0.3)
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		raw[i] = lp2 * 6.0 + sin(TAU * 41.0 * t) * 0.05
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	# Crossfade the tail into the head so the loop is seamless.
	for i in fade:
		var k := float(i) / fade
		out[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	return out

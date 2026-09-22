extends Node
## Runtime audio: procedural music, tiny OGG loops and SFX. play_theme()
## renders a runtime score (THEMES is the whole score); play_music_loop()
## crossfades to a seamless loop; "Generated music" off swaps themes for
## mood-matched loops. play_sfx() plays an OGG or synthesizes the blip.
## Music->Music bus, SFX->SFX; Pause/Panic mute Master, state untouched.


const SAMPLE_RATE: int = 22050        ## rate of every generated stream
const MAX_PUSH_PER_FRAME: int = 4096  ## ~0.19 s of audio per process frame
const LOOKAHEAD: float = 0.6          ## notes scheduled this far ahead
const BLOCK: int = 256                ## render quantum; events snap to blocks
const MUSIC_GAIN: float = 0.5         ## peak theme level on top of the bus slider
const LOOP_DB: float = -8.0           ## OGG loop level ...
const LOOP_SILENT_DB: float = -60.0   ## ... and its faded-out floor (dB)

## Mood-matched loop fallbacks per theme.
const THEME_LOOPS: Dictionary = {
	&"calm": "res://assets/music/day.ogg",
	&"warm": "res://assets/music/day.ogg",
	&"tense": "res://assets/music/night.ogg",
	&"night": "res://assets/music/night.ogg",
}

## The procedural score: chords as scale degrees (wrapping across octaves);
## plucks = arpeggio notes per bar, bass_hits = bass pulses per bar.
const THEMES: Dictionary = {
	&"calm": {
		"bpm": 72.0, "root": 60, "scale": [0, 2, 4, 7, 9],
		"prog": [[0, 2, 4], [3, 5, 0], [5, 0, 2], [3, 0, 4]],
		"pad": 0.52, "pluck": 0.30, "bass": 0.40, "plucks": 4, "bass_hits": 1,
	},
	&"warm": {
		"bpm": 66.0, "root": 65, "scale": [0, 2, 4, 7, 9],
		"prog": [[0, 2, 4], [5, 0, 2], [3, 5, 0], [4, 6, 1]],
		"pad": 0.54, "pluck": 0.26, "bass": 0.38, "plucks": 4, "bass_hits": 1,
	},
	&"tense": {
		"bpm": 96.0, "root": 62, "scale": [0, 2, 3, 5, 7, 8, 10],
		"prog": [[0, 2, 4], [0, 2, 4], [5, 0, 2], [6, 1, 3]],
		"pad": 0.42, "pluck": 0.28, "bass": 0.46, "plucks": 8, "bass_hits": 2,
	},
	&"night": {
		"bpm": 60.0, "root": 57, "scale": [0, 3, 5, 7, 10],
		"prog": [[0, 2, 4], [3, 0, 2], [5, 0, 4], [0, 2, 4]],
		"pad": 0.50, "pluck": 0.22, "bass": 0.36, "plucks": 2, "bass_hits": 1,
	},
}


# Introspection for tests/tools.
var music_source: String = ""          ## "", "procedural" or "loop"
var current_theme: StringName = &""    ## active theme ("" when none)
var procedural_enabled: bool = true    ## Settings "Generated music" toggle
var notes_scheduled: int = 0           ## scheduler events emitted so far
var frames_pushed: int = 0             ## samples pushed to the generator
var sfx_played: int = 0                ## play_sfx() calls (ogg + synth)
var last_sfx: String = ""              ## key of the most recent SFX
var last_sfx_source: String = ""       ## "ogg" or "synth"
var last_sfx_pitch: float = 1.0        ## pitch of the most recent SFX
var typing_ticks: int = 0              ## typewriter tick requests
var music_seed: int = 20260921         ## fixed arpeggio RNG seed

var _gen: AudioStreamGenerator
var _gen_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _theme: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## Generator timeline (seconds of pushed audio), bar cursor and event queue
## ({t, midi, kind, dur, peak, pan}, sorted by t).
var _playhead: float = 0.0
var _next_bar: float = 0.0
var _bar_index: int = 0
var _queue: Array[Dictionary] = []

## Live voices as parallel arrays (fast mix loop): kind 0 pad, 1 pluck, 2 bass.
var _v_px := PackedFloat64Array()
var _v_py := PackedFloat64Array()
var _v_dx := PackedFloat64Array()
var _v_dy := PackedFloat64Array()
var _v_t := PackedFloat64Array()
var _v_dur := PackedFloat64Array()
var _v_atk := PackedFloat64Array()
var _v_rel := PackedFloat64Array()
var _v_peak := PackedFloat64Array()
var _v_tau := PackedFloat64Array()
var _v_gl := PackedFloat64Array()
var _v_gr := PackedFloat64Array()
var _v_kind := PackedFloat64Array()
var _voice_count: int = 0

## Crossfade gain for the engine + last theme (for the toggle).
var _gain: float = 0.0
var _gain_target: float = 0.0
var _last_theme: StringName = &""


var _loop_a: AudioStreamPlayer
var _loop_b: AudioStreamPlayer
var _loop_path: String = ""
var _auto_loop: bool = false   ## true when the loop was a procedural fallback

var _sfx_pool: Array[AudioStreamPlayer] = []
var _synth_cache: Dictionary = {}   ## synthesized blips, rendered on first use
var _last_tick_ms: int = -1000
var _tick_parity: int = 0


func _ready() -> void:
	_ensure_audio_buses()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = SAMPLE_RATE
	_gen.buffer_length = 0.25
	_gen_player = AudioStreamPlayer.new()
	_gen_player.stream = _gen
	_gen_player.bus = &"Music"
	_gen_player.name = "ProceduralMusic"
	add_child(_gen_player)
	_loop_a = _make_music_player("LoopA")
	_loop_b = _make_music_player("LoopB")
	for i: int in 6:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	_rng.seed = music_seed


func _make_music_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = &"Music"
	p.volume_db = LOOP_SILENT_DB
	add_child(p)
	return p


func _process(delta: float) -> void:
	if music_source != "procedural" and _gain <= 0.0005 and _gain_target <= 0.0005:
		return
	_ramp_gain(delta)
	_pump()


## Drop stream refs before teardown (fewer shutdown leaks).
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		var players: Array[AudioStreamPlayer] = [_gen_player, _loop_a, _loop_b]
		players.append_array(_sfx_pool)
		for p: AudioStreamPlayer in players:
			if is_instance_valid(p):
				p.stop()
				p.stream = null
		_synth_cache.clear()
		_playback = null


## Ramp the crossfade gain toward its target (~0.6 s).
func _ramp_gain(delta: float) -> void:
	_gain = move_toward(_gain, _gain_target, delta * 0.85)



## Start/switch a procedural theme. "stop"/unknown names stop the music;
## with generation disabled this plays the mood-matched OGG loop instead.
func play_theme(theme: StringName) -> void:
	if theme == &"stop" or not THEMES.has(theme):
		stop_music()
		return
	_last_theme = theme
	if not procedural_enabled:
		play_music_loop(String(THEME_LOOPS.get(theme, "res://assets/music/day.ogg")), true)
		return
	if music_source == "procedural" and current_theme == theme:
		return
	_fade_out_loops()
	_theme = THEMES[theme]
	current_theme = theme
	music_source = "procedural"
	_auto_loop = false
	_rng.seed = hash(String(theme)) ^ music_seed
	_bar_index = 0
	_queue.clear()
	_next_bar = _playhead + 0.05
	_gain_target = MUSIC_GAIN
	if not _gen_player.playing:
		_gen_player.play()
	if _playback == null:
		_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback


## Crossfade to an OGG loop. `as_fallback` marks a stand-in for procedural
## music so the settings toggle can restore the engine.
func play_music_loop(path: String, as_fallback: bool = false) -> void:
	if music_source == "loop" and _loop_path == path:
		return
	_gain_target = 0.0  # fade the procedural engine out under the loop
	current_theme = &""
	music_source = "loop"
	_loop_path = path
	_auto_loop = as_fallback
	var stream: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if stream == null:
		push_warning("AudioDirector: missing loop %s" % path)
		music_source = ""
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	var fresh := _loop_b if _loop_a.playing else _loop_a
	var stale := _loop_a if fresh == _loop_b else _loop_b
	fresh.stream = stream
	fresh.volume_db = LOOP_SILENT_DB
	fresh.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fresh, "volume_db", LOOP_DB, 0.8)
	if stale.playing:  # crossfade the previous loop out under the new one
		tw.tween_property(stale, "volume_db", LOOP_SILENT_DB, 0.8)
		tw.chain().tween_callback(stale.stop)


## Fade everything out.
func stop_music(fade: float = 0.8) -> void:
	_gain_target = 0.0
	current_theme = &""
	_last_theme = &""
	_auto_loop = false
	_loop_path = ""
	music_source = ""
	for p: AudioStreamPlayer in [_loop_a, _loop_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", LOOP_SILENT_DB, fade)
			tw.tween_callback(p.stop)


## Fade out and stop the sounding loop player.
func _fade_out_loops() -> void:
	_loop_path = ""
	for p: AudioStreamPlayer in [_loop_a, _loop_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", LOOP_SILENT_DB, 0.5)
			tw.tween_callback(p.stop)


## "Generated music" setting: swap engine <-> fallback loops.
func set_procedural_enabled(on: bool) -> void:
	procedural_enabled = on
	if on:
		if music_source == "loop" and _auto_loop and _last_theme != &"":
			play_theme(_last_theme)
	else:
		if music_source == "procedural":
			var theme: StringName = current_theme if current_theme != &"" else _last_theme
			_last_theme = theme
			play_music_loop(String(THEME_LOOPS.get(theme, "res://assets/music/day.ogg")), true)


## Tag helper: #music=stop | loop:<file> | <theme>.
func request_music(spec: String) -> void:
	if spec == "stop":
		stop_music()
	elif spec.begins_with("loop:"):
		var key: String = spec.substr(5)
		var path: String = key if key.begins_with("res://") else "res://assets/music/%s.ogg" % key
		play_music_loop(path)
	else:
		play_theme(StringName(spec))



## Play SFX by key: assets/sfx/<key>.ogg, else a synthesized equivalent.
func play_sfx(key: String, pitch: float = 1.0) -> void:
	sfx_played += 1
	last_sfx = key
	last_sfx_pitch = pitch
	var path: String = "res://assets/sfx/%s.ogg" % key
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		last_sfx_source = "ogg"
		_play_stream(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE),
			pitch + _rng.randf_range(-0.02, 0.02))
	else:
		last_sfx_source = "synth"
		_play_stream(_synth_stream(key), pitch + _rng.randf_range(-0.05, 0.05))


## Typewriter tick: silent on whitespace, throttled, pitch varies per letter.
func typing_tick(letter: String) -> void:
	typing_ticks += 1
	if letter.strip_edges().is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_tick_ms < 30:
		return
	_last_tick_ms = now
	_tick_parity += 1
	if _tick_parity % 2 != 0:
		return
	var bucket: int = absi(letter.hash()) % 6
	_play_stream(_synth_stream("tick%d" % bucket), 0.55 + _rng.randf_range(-0.05, 0.05))


func _play_stream(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null:
		return
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.play()
			return
	# All busy: steal the first.
	_sfx_pool[0].stream = stream
	_sfx_pool[0].pitch_scale = pitch
	_sfx_pool[0].play()



func _pump() -> void:
	if _playback == null:
		if _gen_player.playing:
			_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	var frames: int = mini(_playback.get_frames_available(), MAX_PUSH_PER_FRAME)
	if frames <= 0:
		return
	# Schedule upcoming bars while the theme plays.
	if music_source == "procedural" and not _theme.is_empty():
		var bar_len: float = 60.0 / float(_theme["bpm"]) * 4.0
		while _next_bar < _playhead + LOOKAHEAD:
			_schedule_bar(_bar_index, _next_bar)
			_next_bar += bar_len
			_bar_index += 1
	_playback.push_buffer(_render_frames(frames))
	frames_pushed += frames


func _render_frames(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	var pos: int = 0
	var inv_sr: float = 1.0 / SAMPLE_RATE
	while pos < n:
		var block: int = mini(BLOCK, n - pos)
		var block_end: float = _playhead + float(block) * inv_sr
		while not _queue.is_empty() and _queue[0]["t"] <= block_end:
			_spawn_voice(_queue.pop_front())
		for i in block:
			var l: float = 0.0
			var r: float = 0.0
			var vi: int = 0
			while vi < _voice_count:
				var t: float = _v_t[vi]
				var env: float
				var kind: float = _v_kind[vi]
				if kind > 0.5 and kind < 1.5:  # pluck: fast attack, exp decay
					env = exp(-t / _v_tau[vi])
					if t < _v_atk[vi]:
						env *= t / _v_atk[vi]
				elif t < _v_atk[vi]:  # pad/bass: linear attack, hold, release
					env = t / _v_atk[vi]
				elif t < _v_dur[vi] - _v_rel[vi]:
					env = 1.0
				else:
					env = maxf(0.0, (_v_dur[vi] - t) / _v_rel[vi])
				if env <= 0.0002 and t > _v_atk[vi]:
					# Dead voice: swap-remove, arrays stay == _voice_count.
					_voice_count -= 1
					_copy_voice(vi, _voice_count)
					_trim_voices()
					continue
				var s: float = _v_py[vi] * env * _v_peak[vi]
				l += s * _v_gl[vi]
				r += s * _v_gr[vi]
				# Rotate the phasor.
				var px: float = _v_px[vi]
				var py: float = _v_py[vi]
				_v_px[vi] = px * _v_dx[vi] - py * _v_dy[vi]
				_v_py[vi] = px * _v_dy[vi] + py * _v_dx[vi]
				_v_t[vi] = t + inv_sr
				vi += 1
			# Soft saturation against clipping.
			l = l / (1.0 + absf(l)) * 1.4
			r = r / (1.0 + absf(r)) * 1.4
			out[pos + i] = Vector2(l * _gain, r * _gain)
		pos += block
		_playhead += float(block) * inv_sr
	return out


func _voice_arrays() -> Array:
	return [_v_px, _v_py, _v_dx, _v_dy, _v_t, _v_dur, _v_atk, _v_rel,
		_v_peak, _v_tau, _v_gl, _v_gr, _v_kind]


func _copy_voice(from_i: int, to_i: int) -> void:
	if from_i != to_i:
		for a: PackedFloat64Array in _voice_arrays():
			a[from_i] = a[to_i]


## Size the parallel arrays to the live count after a swap-remove.
func _trim_voices() -> void:
	for a: PackedFloat64Array in _voice_arrays():
		a.resize(_voice_count)


## Scale degree -> MIDI note (wraps across octaves).
func _degree_midi(deg: int, root: int, scale: Array) -> int:
	var n: int = scale.size()
	var oct: int = deg / n if deg >= 0 else -((-deg + n - 1) / n)
	return root + 12 * oct + scale[posmod(deg, n)]


## Queue one 4/4 bar of pad, bass and arpeggio at time `bt`.
func _schedule_bar(bar: int, bt: float) -> void:
	var bar_len: float = 60.0 / float(_theme["bpm"]) * 4.0
	var prog: Array = _theme["prog"]
	var chord: Array = prog[bar % prog.size()]
	var root: int = int(_theme["root"])
	var scale: Array = _theme["scale"]
	# Pad: chord tones up an octave, slight overlap into the next bar.
	for i: int in chord.size():
		_queue.append({"t": bt, "midi": _degree_midi(int(chord[i]) + 7, root, scale),
			"kind": 0, "dur": bar_len * 1.15, "peak": float(_theme["pad"]) / chord.size(),
			"pan": 0.22 if i % 2 == 1 else -0.22})
		notes_scheduled += 1
	# Bass on the root.
	var hits: int = int(_theme["bass_hits"])
	for h: int in hits:
		var t: float = bt + bar_len * 0.5 * h
		_queue.append({"t": t, "midi": _degree_midi(int(chord[0]), root, scale) - 12,
			"kind": 2, "dur": bar_len * 0.45, "peak": float(_theme["bass"]), "pan": 0.0})
		notes_scheduled += 1
	# Arpeggio: one pluck per plucks-th of the bar.
	var plucks: int = int(_theme["plucks"])
	for k in plucks:
		var t: float = bt + bar_len * (float(k) / plucks)
		var deg: int = int(chord[(k + bar) % chord.size()])
		var midi: int = _degree_midi(deg, root, scale) + 12
		if plucks >= 8 and k % 3 == 2:
			midi += 12
		_queue.append({"t": t, "midi": midi, "kind": 1, "dur": bar_len * 0.6,
			"peak": float(_theme["pluck"]), "pan": _rng.randf_range(-0.35, 0.35)})
		notes_scheduled += 1


func _spawn_voice(ev: Dictionary) -> void:
	var kind: int = int(ev["kind"])
	var peak: float = float(ev["peak"])
	var pan: float = float(ev.get("pan", 0.0))
	if kind == 0:
		# Two detuned partials per pad note (soft chorus).
		_add_voice(ev, peak * 0.5, pan, -0.0022)
		_add_voice(ev, peak * 0.5, -pan, 0.0022)
	else:
		_add_voice(ev, peak, pan, 0.0)


func _add_voice(ev: Dictionary, peak: float, pan: float, detune: float) -> void:
	if _voice_count >= 48:
		return
	var freq: float = 440.0 * pow(2.0, (float(ev["midi"]) - 69.0) / 12.0) * (1.0 + detune)
	var ang: float = TAU * freq / SAMPLE_RATE
	var kind: int = int(ev["kind"])
	_voice_count += 1
	_v_px.append(1.0)
	_v_py.append(0.0)
	_v_dx.append(cos(ang))
	_v_dy.append(sin(ang))
	_v_t.append(0.0)
	_v_dur.append(float(ev["dur"]))
	if kind == 1:
		_v_atk.append(0.004)
		_v_rel.append(0.05)
		_v_tau.append(float(ev["dur"]) / 4.5)
	elif kind == 2:
		_v_atk.append(0.02)
		_v_rel.append(0.18)
		_v_tau.append(1.0)
	else:
		_v_atk.append(minf(0.6, float(ev["dur"]) * 0.35))
		_v_rel.append(minf(0.8, float(ev["dur"]) * 0.4))
		_v_tau.append(1.0)
	_v_peak.append(peak)
	_v_gl.append(1.0 - 0.6 * maxf(pan, 0.0))
	_v_gr.append(1.0 - 0.6 * maxf(-pan, 0.0))
	_v_kind.append(float(kind))



## Render + cache a synthesized blip; unknown kinds fall back to the click.
func _synth_stream(kind: String) -> AudioStream:
	if _synth_cache.has(kind):
		return _synth_cache[kind]
	var samples := PackedFloat32Array()
	if kind.begins_with("tick"):
		samples = _synth_tick(float(kind.substr(4)) if kind.length() > 4 else 0.0)
	elif kind == "open":
		samples = _synth_sweep(420.0, 950.0, 0.13)
	elif kind == "close":
		samples = _synth_sweep(900.0, 380.0, 0.13)
	elif kind == "confirm":
		samples = _synth_chime([659.25, 880.0], 0.07)
	elif kind == "save" or kind == "chime":
		samples = _synth_chime([523.25, 659.25, 783.99], 0.1)
	elif kind == "error":
		samples = _synth_buzz()
	elif kind == "hold":
		samples = _synth_hold()
	elif kind == "click":
		samples = _synth_click()
	else:
		samples = _synth_click()
	var stream := _to_wav(samples)
	_synth_cache[kind] = stream
	return stream


## 12 ms sine blip; bucket shifts the pitch so typing has texture.
func _synth_tick(bucket: float) -> PackedFloat32Array:
	var n: int = int(0.012 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var freq: float = 1150.0 + bucket * 55.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		out[i] = sin(TAU * freq * t) * exp(-t / 0.0045) * 0.3
	return out


func _synth_click() -> PackedFloat32Array:
	var n: int = int(0.025 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var e: float = exp(-t / 0.0045)
		out[i] = (_noise_rng.randf_range(-0.5, 0.5) + sin(TAU * 1600.0 * t) * 0.8) * e * 0.7
	return out


func _synth_sweep(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n: int = int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i in n:
		var x: float = float(i) / n
		var freq: float = f0 * pow(f1 / f0, x)
		phase += TAU * freq / SAMPLE_RATE
		var t: float = float(i) / SAMPLE_RATE
		out[i] = sin(phase) * exp(-t / (dur * 0.7)) * 0.8
	return out


func _synth_chime(freqs: Array, step: float) -> PackedFloat32Array:
	var n: int = int((step * freqs.size() + 0.2) * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in freqs.size():
		var start: int = int(k * step * SAMPLE_RATE)
		var f: float = float(freqs[k])
		for i in range(start, n):
			var t: float = float(i - start) / SAMPLE_RATE
			out[i] += (sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t)) * exp(-t / 0.09) * 0.55
	return out


func _synth_buzz() -> PackedFloat32Array:
	var beep: int = int(0.09 * SAMPLE_RATE)
	var gap: int = int(0.05 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(beep * 2 + gap)
	for i in beep:
		var t: float = float(i) / SAMPLE_RATE
		var e: float = exp(-t / 0.035)
		var v: float = (0.6 if fposmod(196.0 * t, 1.0) < 0.5 else -0.6) + sin(TAU * 196.0 * t) * 0.5
		out[i] = v * e * 0.7
		out[beep + gap + i] = v * e * 0.7
	return out


## Rising blip announcing a hold gesture (~90 ms).
func _synth_hold() -> PackedFloat32Array:
	var n: int = int(0.09 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var x: float = float(i) / n
		phase += TAU * (220.0 + 140.0 * x) / SAMPLE_RATE
		out[i] = sin(phase) * (0.25 + 0.45 * x) * 0.8
	return out


var _noise_rng := RandomNumberGenerator.new()


## Wrap raw samples in a 16-bit mono AudioStreamWAV.
func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav



## Idempotent with the balloon's own bus setup.
func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Voice", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")

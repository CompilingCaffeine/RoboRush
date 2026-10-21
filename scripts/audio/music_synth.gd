class_name MusicSynth
extends RefCounted
## Renders one `MusicScore.Track` into a looping AudioStreamWAV, a slice at a time.
##
##     var synth := MusicSynth.new(MusicScore.track(&"explore"))
##     while not synth.step(Time.get_ticks_usec() + 2000):
##         await get_tree().process_frame
##     player.stream = synth.stream
##
## Resumable rather than a function that returns a stream, because of where the game runs. The Web
## build is single-threaded, so there is no worker to hand a render to: whatever does it does it on
## the frame. A track costs under 10 ms of synthesis per second of music, in a browser as much as on
## a desktop — a few hundred milliseconds at most for a whole loop, which is cheap as a total and a
## string of dropped frames if spent at once. `step` stops at a deadline and picks up where it left off, so the cost
## goes in a couple of milliseconds a frame wherever there is room for it. `render` is the same thing
## with no deadline, for tests and tools.
##
## The synthesis is tools/generate_music.py's, which rendered the WAVs the game used to ship: the same
## voices, the same percussion, the same rounding of note edges to samples, and the same peak
## normalisation. Two things differ, and neither can be heard. The noise in the snare and the hat
## comes from Godot's generator rather than Python's, so it is different noise with the same seed
## discipline; and a percussion hit stops being computed once it has decayed below anything 16-bit
## audio can represent, rather than running out its full four sixteenths in silence.

const SAMPLE_RATE := 22050

## Music sits under the sound effects, which peak around 0.35. Spec section 22 warns against
## fatiguing audio, and a loop the player hears for ten minutes is the easiest thing in the game to
## get wrong in that direction.
const AMPLITUDE := 0.20

## Deterministic percussion, so a track sounds the same every time it is rendered.
const NOISE_SEED := 20260802

## Parts may differ in length by a few samples, because a melodic part rounds each note to whole
## samples while the drum part rounds each sixteenth, and the two accumulate differently over a bar.
## Anything larger than this is a miscounted pattern.
const LENGTH_TOLERANCE_SAMPLES := 16

## Samples rendered between looks at the clock: about a tenth of a millisecond of work, so a deadline
## is overshot by at most that much.
const SLICE := 1024

## A percussion envelope below this is silent: even at the quietest normalisation in the game it is
## a small fraction of one 16-bit step. Hits are not computed past it.
const INAUDIBLE := 1e-6

## [duty, attack rate, decay sharpness, gain] per voice.
##
## The lead is a narrow-duty square with a soft attack: the melody. The bass is a half-duty square
## an octave or two down, held longer: the retro synth bass. The arpeggio is very short, very narrow
## pulses that fill the gaps the lead leaves without competing with it.
const VOICES := {
	MusicScore.Voice.LEAD: [0.30, 14.0, 2.2, 0.55],
	MusicScore.Voice.BASS: [0.5, 0.0, 1.1, 0.75],
	MusicScore.Voice.ARP: [0.14, 0.0, 6.0, 0.35],
}

const SEMITONES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

enum Stage { PARTS, DRUMS, PEAK, ENCODE, DONE }

## The finished loop, once `step` has returned true. Null before that.
var stream: AudioStreamWAV

var _track: MusicScore.Track
var _mix := PackedFloat32Array()
var _noise := RandomNumberGenerator.new()
var _stage := Stage.PARTS

## Where the render has got to: the part, the event within it (a note, or a sixteenth of the drum
## pattern), how many beats came before that event, and how far into the event.
var _part := 0
var _event := 0
var _elapsed := 0.0
var _done_samples := 0
var _length := 0

## The note being rendered. Phase is carried across notes rather than reset, which is what keeps a
## repeated note from clicking at its boundary; it restarts only with a new part.
var _start := 0
var _phase := 0.0
var _phase_step := 0.0
var _duty := 0.0
var _envelope := 0.0
var _envelope_ratio := 0.0
var _attack := 0.0
var _attack_step := 0.0

## The drum hit being rendered: its symbol and the precomputed shape it is drawn from. See `_hit`.
var _symbol := ""
var _hit_tone := PackedFloat32Array()
var _hit_noise := PackedFloat32Array()
var _hit_shapes: Dictionary[String, Array] = {}

var _peak := 0.0
var _pcm := PackedByteArray()


func _init(track: MusicScore.Track) -> void:
	_track = track
	_noise.seed = NOISE_SEED
	var length := _drum_samples(track)
	for part: Array in track.parts:
		length = maxi(length, _part_samples(track, part[1]))
	_mix.resize(length)


## Renders `track` start to finish and returns the loop.
static func render(track: MusicScore.Track) -> AudioStreamWAV:
	var synth := MusicSynth.new(track)
	synth.step(Time.get_ticks_usec() + 3_600_000_000)
	return synth.stream


## What is wrong with `track`, as sentences, or nothing if it is fine.
##
## The check is the whole reason a track carries a beat count. The first version of every track had
## a bass line and a drum pattern half the length of its melody, so the back half of each loop played
## the tune over silence — which sounds like the music has stopped rather than like a mistake, and is
## invisible in the score unless something counts the beats.
static func problems(track: MusicScore.Track) -> PackedStringArray:
	var found := PackedStringArray()
	var expected := _samples(track.beats * track.beat_seconds)
	var lengths: Dictionary[String, int] = {"drums": _drum_samples(track)}
	for index: int in track.parts.size():
		lengths["part %d" % index] = _part_samples(track, track.parts[index][1])
		for event: Array in track.parts[index][1]:
			if event[0] != "." and _note_hz(event[0]) <= 0.0:
				found.append("part %d has a note named '%s', which is not one" % [index, event[0]])
	for name: String in lengths:
		var drift := absi(lengths[name] - expected)
		if drift > LENGTH_TOLERANCE_SAMPLES:
			found.append("%s is %d samples, expected about %d (%s beats): off by %d" % [
				name, lengths[name], expected, track.beats, drift,
			])
	for symbol: String in track.drums:
		if symbol not in "ksh.":
			found.append("the drum pattern has a '%s', which is not k, s, h or ." % symbol)
	return found


## Renders until the track is finished or the clock passes `deadline_usec`, whichever comes first,
## and says whether it is finished. Call again to carry on.
func step(deadline_usec: int) -> bool:
	while _stage != Stage.DONE:
		match _stage:
			Stage.PARTS:
				_step_parts()
			Stage.DRUMS:
				_step_drums()
			Stage.PEAK:
				_step_peak()
			Stage.ENCODE:
				_step_encode()
		if _stage != Stage.DONE and Time.get_ticks_usec() >= deadline_usec:
			return false
	return true


# --- Melodic parts -------------------------------------------------------------------


## One slice of the current note, starting the next note first if the last one is finished.
func _step_parts() -> void:
	if _part >= _track.parts.size():
		_stage = Stage.DRUMS
		_event = 0
		return
	var events: Array = _track.parts[_part][1]
	if _event >= events.size():
		_part += 1
		_event = 0
		_elapsed = 0.0
		_phase = 0.0
		return
	if _length == 0 and not _begin_note(events[_event], _track.parts[_part][0]):
		_event += 1
		return

	var end := mini(_done_samples + SLICE, _length)
	var phase := _phase
	var envelope := _envelope
	var offset := _start
	if _attack_step > 0.0:
		var attack := _attack
		for index: int in range(_done_samples, end):
			phase += _phase_step
			if phase >= 1.0:
				phase -= 1.0
			var amplitude := envelope * minf(1.0, attack)
			_mix[offset + index] += amplitude if phase < _duty else -amplitude
			envelope *= _envelope_ratio
			attack += _attack_step
		_attack = attack
	else:
		for index: int in range(_done_samples, end):
			phase += _phase_step
			if phase >= 1.0:
				phase -= 1.0
			_mix[offset + index] += envelope if phase < _duty else -envelope
			envelope *= _envelope_ratio
	_phase = phase
	_envelope = envelope
	_done_samples = end
	if _done_samples >= _length:
		_length = 0
		_event += 1


## Sets up `event` as the note being rendered, or returns false for a rest or a note too short to
## occupy a sample.
##
## Both edges come from the cumulative beat position rather than from a per-note rounded length.
## Rounding each note independently drifts by a sample or two per note, which over a thirty-two beat
## bar puts the parts tens of samples out of step and the loop point in the wrong place.
func _begin_note(event: Array, voice: int) -> bool:
	_start = _samples(_elapsed * _track.beat_seconds)
	_elapsed += float(event[1])
	var count := _samples(_elapsed * _track.beat_seconds) - _start
	if event[0] == "." or count <= 0:
		return false
	var shape: Array = VOICES[voice]
	_length = count
	_done_samples = 0
	_phase_step = _note_hz(event[0]) / SAMPLE_RATE
	_duty = shape[0]
	# The envelope is exp(-sharpness * progress) and the attack min(1, progress * rate), with
	# progress running 0 to 1 over the note. Both are kept as running values — one multiply and one
	# add a sample rather than an exp — which come to the same numbers to within float rounding.
	_envelope = shape[3]
	_envelope_ratio = exp(-float(shape[2]) / count)
	_attack = 0.0
	_attack_step = float(shape[1]) / count
	return true


# --- Percussion ----------------------------------------------------------------------


## One slice of the current drum hit, starting the next hit first if the last one is finished.
##
## Industrial percussion in the sense spec section 22 means it: the kick is a pitch-swept sine (a
## press dropping), the snare is a noise burst with a tone under it, the hat is a very short high
## noise tick. All three are machinery rather than a drum kit.
func _step_drums() -> void:
	if _length == 0:
		if _event >= _track.drums.length():
			_stage = Stage.PEAK
			_done_samples = 0
			return
		_symbol = _track.drums[_event]
		if _symbol == ".":
			_event += 1
			return
		# Same reasoning as `_begin_note`: position from the exact step index, not from a rounded
		# step length multiplied out. Hits ring past their own step, so the tail of a kick overlaps
		# the next sixteenth instead of being cut off square, but never past the end of the loop.
		var step_seconds := _track.beat_seconds / 4.0
		_start = _samples(_event * step_seconds)
		var ring := mini(int(step_seconds * SAMPLE_RATE * 4), _drum_samples(_track) - _start)
		var shape := _hit(_symbol, ring)
		_hit_tone = shape[0]
		_hit_noise = shape[1]
		_length = maxi(_hit_tone.size(), _hit_noise.size())
		_done_samples = 0
		if _length == 0:
			_event += 1
			return

	var end := mini(_done_samples + SLICE, _length)
	var offset := _start
	if _symbol == "k":
		for index: int in range(_done_samples, end):
			_mix[offset + index] += _hit_tone[index]
	elif _symbol == "s":
		for index: int in range(_done_samples, end):
			_mix[offset + index] += _hit_tone[index] + _noise.randf_range(-1.0, 1.0) * _hit_noise[index]
	else:
		for index: int in range(_done_samples, end):
			_mix[offset + index] += _noise.randf_range(-1.0, 1.0) * _hit_noise[index]
	_done_samples = end
	if _done_samples >= _length:
		_length = 0
		_event += 1


## The deterministic part of a hit of `symbol` lasting `ring` samples, as [tone, noise envelope]:
## each sample of the hit is tone + noise * envelope, with the noise drawn fresh. Computed once per
## symbol and length and reused, because everything in a hit except the noise is the same every time
## it plays.
##
## Each is cut where it falls below `INAUDIBLE`, which for the hat is a fifth of the way through.
func _hit(symbol: String, ring: int) -> Array:
	var key := "%s%d" % [symbol, ring]
	if _hit_shapes.has(key):
		return _hit_shapes[key]
	var tone := PackedFloat32Array()
	var noise := PackedFloat32Array()
	var phase := 0.0
	for index: int in maxi(ring, 0):
		var progress := float(index) / ring
		if symbol == "k":
			phase += 92.0 * pow(38.0 / 92.0, progress) / SAMPLE_RATE
			tone.append(sin(phase * TAU) * exp(-7.0 * progress) * 0.9)
		elif symbol == "s":
			var envelope := exp(-16.0 * progress)
			if envelope < INAUDIBLE:
				break
			phase += 190.0 / SAMPLE_RATE
			tone.append((0.3 if fposmod(phase, 1.0) < 0.5 else -0.3) * envelope)
			noise.append(0.7 * envelope)
		else:
			var envelope := exp(-60.0 * progress) * 0.35
			if envelope < INAUDIBLE:
				break
			noise.append(envelope)
	_hit_shapes[key] = [tone, noise]
	return _hit_shapes[key]


# --- Output --------------------------------------------------------------------------


func _step_peak() -> void:
	var end := mini(_done_samples + SLICE * 8, _mix.size())
	var peak := _peak
	for index: int in range(_done_samples, end):
		peak = maxf(peak, absf(_mix[index]))
	_peak = peak
	_done_samples = end
	if _done_samples >= _mix.size():
		_stage = Stage.ENCODE
		_done_samples = 0
		_pcm.resize(_mix.size() * 2)


## Scaled so the loudest sample sits at `AMPLITUDE`, then truncated to 16 bits, as the WAVs were.
func _step_encode() -> void:
	var end := mini(_done_samples + SLICE * 4, _mix.size())
	var scale := AMPLITUDE / (_peak if _peak > 0.0 else 1.0) * 32767.0
	for index: int in range(_done_samples, end):
		_pcm.encode_s16(index * 2, clampi(int(_mix[index] * scale), -32768, 32767))
	_done_samples = end
	if _done_samples < _mix.size():
		return
	stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = _pcm
	# `loop_end` is a frame index and must be the end of the sample. A zero-length loop region is not
	# "loop the whole thing": the playback hits the end of the loop on its first mix and goes
	# inactive, which once left every track silent from the moment it started.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = _mix.size()
	_mix = PackedFloat32Array()
	_pcm = PackedByteArray()
	_hit_shapes.clear()
	_stage = Stage.DONE


# --- Arithmetic ----------------------------------------------------------------------


static func _part_samples(track: MusicScore.Track, events: Array) -> int:
	var beats := 0.0
	for event: Array in events:
		beats += float(event[1])
	return _samples(beats * track.beat_seconds)


static func _drum_samples(track: MusicScore.Track) -> int:
	return _samples(track.drums.length() * track.beat_seconds / 4.0)


## Seconds to a sample index, rounding exact halves to even. That is Python's `round`, which is what
## placed every note edge in the WAVs; rounding halves up instead moves some edges by a sample.
static func _samples(seconds: float) -> int:
	var exact := seconds * SAMPLE_RATE
	var below := floorf(exact)
	if exact - below == 0.5:
		return int(below) + (int(below) & 1)
	return roundi(exact)


## "A4" is 440 Hz and "C#5" 554.4. Equal temperament from A4 = MIDI 69. Zero for a name that is not
## a note.
static func _note_hz(name: String) -> float:
	var letter := name.left(1).to_upper()
	if not SEMITONES.has(letter):
		return 0.0
	var accidental := 0
	var digits := name.substr(1)
	if digits.begins_with("#") or digits.begins_with("b"):
		accidental = 1 if digits.begins_with("#") else -1
		digits = digits.substr(1)
	if not digits.is_valid_int():
		return 0.0
	var midi := (int(digits) + 1) * 12 + int(SEMITONES[letter]) + accidental
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

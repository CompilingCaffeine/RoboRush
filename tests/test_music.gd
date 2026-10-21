extends TestCase
## The score and the synthesiser that turns it into the game's music.
##
## The music used to ship as thirteen rendered WAVs, so "is every track there and does it loop" was
## a question about files. It is a question about code now: a track exists only once `MusicSynth`
## has rendered it from `MusicScore`, so a miscounted bar or a misspelt note is a bug in a script,
## and this is where it is caught rather than in a browser as a loop that plays its tune over
## silence. Whether the music is any good is not checkable; every way of it quietly not working is.
##
## The synthesis was ported from tools/generate_music.py, which made the WAVs, and checked against
## it when it was: every track came out the same length to the sample, and every sample of every
## part matched to float precision apart from a few square-wave edges per track that land a sample
## to one side — which is a 45 microsecond shift in a single edge, nothing anyone can hear. The
## checks here hold the properties that comparison established, so that they cannot drift.

## The track the timing and resumption checks render. Short, and the one most of a run plays.
const PROBE_TRACK := &"explore"


func run() -> void:
	_test_every_track_has_a_score()
	_test_every_score_adds_up()
	_test_every_track_renders_a_loop()
	_test_rendering_in_slices_changes_nothing()
	_test_a_slice_stops_near_its_deadline()
	_test_notes_and_note_edges()
	_test_broken_scores_are_reported()


func _test_every_track_has_a_score() -> void:
	check(not MusicScore.TRACK_IDS.is_empty(), "the score names some tracks")
	for id: StringName in MusicScore.TRACK_IDS:
		check(MusicScore.track(id) != null, "track '%s' has a score" % id)
		check(MusicScore.has(id), "and is known by its id '%s'" % id)
	check(MusicScore.track(&"__no_such_track") == null, "an id that is not a track has no score")
	check(not MusicScore.has(&"__no_such_track"), "and is not known")


## The check the generator's first version needed: a bass line or a drum pattern half the length of
## its melody, so the back half of the loop played the tune over silence.
func _test_every_score_adds_up() -> void:
	for id: StringName in MusicScore.TRACK_IDS:
		var problems := MusicSynth.problems(MusicScore.track(id))
		check(problems.is_empty(), "every part of '%s' is the loop's length and plays real notes%s" % [
			id, "" if problems.is_empty() else ": " + "; ".join(problems),
		])


## Every track is a loop, and a loop flag left off plays once and leaves the game silent for the
## rest of the run.
func _test_every_track_renders_a_loop() -> void:
	for id: StringName in MusicScore.TRACK_IDS:
		var track := MusicScore.track(id)
		var wav := MusicSynth.render(track)
		if not require(wav, "track '%s' renders" % id):
			continue
		# Read once: the property hands back a fresh copy of the whole sample every time it is read.
		var data := wav.data
		var frames := data.size() / 2
		check(wav.format == AudioStreamWAV.FORMAT_16_BITS and not wav.stereo, "'%s' is 16-bit mono" % id)
		check(wav.mix_rate == MusicSynth.SAMPLE_RATE, "'%s' is at %d Hz" % [id, MusicSynth.SAMPLE_RATE])
		check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "'%s' is set to loop forward" % id)
		# A loop region has to contain something. `loop_end` is a frame index, and leaving it at 0
		# means the loop ends where it begins, which is not "loop the whole track".
		check(
			wav.loop_begin == 0 and wav.loop_end == frames,
			"'%s' loops over the whole sample (frames %d..%d of %d)" % [id, wav.loop_begin, wav.loop_end, frames],
		)
		check(wav.get_length() > 4.0, "'%s' is long enough to be a loop, not a sting" % id)
		check_near(
			wav.get_length(), track.beats * track.beat_seconds,
			"'%s' lasts its %s beats" % [id, track.beats], 0.01,
		)
		var peak := 0
		for index: int in frames:
			peak = maxi(peak, absi(data.decode_s16(index * 2)))
		check(
			absi(peak - int(MusicSynth.AMPLITUDE * 32767.0)) <= 1,
			"'%s' peaks at the music's level, under the sound effects (%d)" % [id, peak],
		)


## The game renders a few milliseconds a frame and the tests render in one go, so the two had better
## be the same thing.
func _test_rendering_in_slices_changes_nothing() -> void:
	var whole := MusicSynth.render(MusicScore.track(PROBE_TRACK))
	var synth := MusicSynth.new(MusicScore.track(PROBE_TRACK))
	var steps := 1
	# A deadline already passed: every call does the least it can, one slice, and stops.
	while not synth.step(0):
		steps += 1
	check(steps > 100, "a render with no time to spare takes many steps rather than one (%d)" % steps)
	check(synth.stream.data == whole.data, "and comes out sample for sample the same as one done at once")
	check(
		MusicSynth.render(MusicScore.track(PROBE_TRACK)).data == whole.data,
		"rendering a track twice gives the same loop, noise included",
	)


## Loose on purpose. A slice is about a tenth of a millisecond of work, and what is being pinned is
## that `step` stops, not how precisely: a render that ignored its deadline would spend the whole
## track's hundred-odd milliseconds here.
func _test_a_slice_stops_near_its_deadline() -> void:
	var synth := MusicSynth.new(MusicScore.track(PROBE_TRACK))
	var started := Time.get_ticks_usec()
	var finished := synth.step(started + 1000)
	var spent := Time.get_ticks_usec() - started
	check(not finished, "a millisecond is not enough for a whole track")
	check(spent < 20_000, "and a step given a millisecond stops soon after it (%d us)" % spent)


func _test_notes_and_note_edges() -> void:
	check_near(MusicSynth._note_hz("A4"), 440.0, "A4 is 440 Hz", 0.001)
	check_near(MusicSynth._note_hz("A2"), 110.0, "A2 is 110 Hz", 0.001)
	check_near(MusicSynth._note_hz("C#5"), 554.365, "C#5 is a semitone above C5", 0.01)
	check_near(MusicSynth._note_hz("Bb4"), MusicSynth._note_hz("A#4"), "Bb and A# are the same note", 0.001)
	check(MusicSynth._note_hz("H4") == 0.0, "a letter that is not a note is not one")
	check(MusicSynth._note_hz("A") == 0.0, "nor is a note with no octave")
	# Exact halves round to even, as Python's `round` did when it placed every note edge in the
	# WAVs. 1.25 s at 22050 Hz is 27562.5 samples: the menu's first two-beat note.
	check(MusicSynth._samples(27562.5 / 22050.0) == 27562, "a half sample rounds down to an even edge")
	check(MusicSynth._samples(27563.5 / 22050.0) == 27564, "and up to an even edge")
	check(MusicSynth._samples(0.1) == 2205, "a whole number of samples is that number")


func _test_broken_scores_are_reported() -> void:
	var short_bass := MusicScore.Track.new(120.0, 4)
	short_bass.add(MusicScore.Voice.LEAD, [["A4", 4]]).add(MusicScore.Voice.BASS, [["A2", 2]])
	short_bass.with_drums("k...".repeat(4))
	check(
		MusicSynth.problems(short_bass).size() == 1,
		"a part half the loop's length is reported (%s)" % "; ".join(MusicSynth.problems(short_bass)),
	)
	var misspelt := MusicScore.Track.new(120.0, 4).add(MusicScore.Voice.LEAD, [["Q4", 4]])
	misspelt.with_drums("k...".repeat(4))
	check(MusicSynth.problems(misspelt).size() == 1, "a note that is not one is reported")
	var bad_drum := MusicScore.Track.new(120.0, 4).add(MusicScore.Voice.LEAD, [["A4", 4]])
	bad_drum.with_drums("k..x".repeat(4))
	check(not MusicSynth.problems(bad_drum).is_empty(), "a drum symbol that is not one is reported")

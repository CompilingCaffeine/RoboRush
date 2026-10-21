class_name MusicScore
extends RefCounted
## Robo Rush's music, as notes. `MusicSynth` turns a track into sound the first time the game asks
## for it.
##
## Spec section 22 asks for chiptune, industrial percussion, retro synth bass, and fast arcade loops.
## That is a 1990s cabinet's sound chip: two or three square-wave voices and a noise channel, which
## is exactly what is here — a lead, a bass, and percussion built from filtered noise and a pitched
## thump. No sampled instruments, because a sampled instrument next to square-wave sound effects
## sounds like two different games.
##
## Written as a tiny tracker rather than as a wall of arithmetic. A track is a tempo, a key, and
## three channels of [note, length] pairs, so a melody can be read and edited as a melody. The
## alternative — hand-computing phase per bar — is unreadable and unmaintainable, and would make
## "the boss theme is one semitone off" a debugging session rather than a one-character fix.
##
## Loops are seamless by construction: every channel is a whole number of beats long and every
## note's envelope decays before the bar line, so there is no click at the join and no fade needed
## (a fade would put an audible dip in a loop that repeats every twenty seconds).
##
## The game used to ship these rendered, as thirteen WAVs that were 2.15 MB of a 3.3 MB package and
## the one part of the download no compression could shrink. The notes are a few kilobytes, and
## rendering them takes a fraction of a second, so the score is what ships now. The WAVs were made
## from this same score by tools/generate_music.py, which this replaces, and the port is note for
## note: what changed is only where the synthesis runs.
##
## Every track is in A minor, so that a crossfade between any two of them is a key change nobody
## notices, which is the difference between a transition and an interruption.

enum Voice { LEAD, BASS, ARP }

## Every track the game can ask for. The ids are what `FloorTheme` names and `AudioManager` plays.
const TRACK_IDS: Array[StringName] = [
	&"menu", &"explore", &"boss",
	&"dev_explore", &"dev_boss",
	&"data_explore", &"data_boss",
	&"cloud_explore", &"cloud_boss",
	&"exec_explore", &"exec_boss",
	&"core_explore", &"core_boss",
]


## One loop: a tempo, a length, melodic parts, and a drum pattern.
class Track:
	extends RefCounted

	var beat_seconds: float

	## How long the loop is meant to be. Every part is checked against it (see `MusicSynth.problems`),
	## which is the whole reason it is written down rather than worked out from the parts.
	var beats: float

	## [voice, events] pairs. Events are [note, length in beats] pairs, and "." is a rest.
	var parts: Array[Array] = []

	## One character per sixteenth note: k kick, s snare, h hat, . nothing.
	var drums := ""

	func _init(bpm: float, loop_beats: float) -> void:
		beat_seconds = 60.0 / bpm
		beats = loop_beats

	func add(voice: Voice, events: Array) -> Track:
		parts.append([voice, events])
		return self

	func with_drums(pattern: String) -> Track:
		drums = pattern
		return self


static func has(id: StringName) -> bool:
	return id in TRACK_IDS


## The track named `id`, or null for an id that is not one.
static func track(id: StringName) -> Track:
	match id:
		&"menu":
			return _menu()
		&"explore":
			return _explore()
		&"boss":
			return _boss()
		&"dev_explore":
			return _dev_explore()
		&"dev_boss":
			return _dev_boss()
		&"data_explore":
			return _data_explore()
		&"data_boss":
			return _data_boss()
		&"cloud_explore":
			return _cloud_explore()
		&"cloud_boss":
			return _cloud_boss()
		&"exec_explore":
			return _executive(false)
		&"exec_boss":
			return _executive(true)
		&"core_explore":
			return _core(false)
		&"core_boss":
			return _core(true)
	return null


# --- The tracks ----------------------------------------------------------------------
#
# One per situation the player can be in for minutes at a time: reading the menu, clearing rooms,
# and fighting a boss, with a pair of the last two for each floor.


## Slow, sparse, unresolved. The title screen is the one place the player is not under pressure,
## and a driving loop there makes the menu feel like a countdown.
static func _menu() -> Track:
	var lead := [
		["A4", 2], ["C5", 1], ["E5", 1], ["D5", 2], [".", 2],
		["F4", 2], ["A4", 1], ["C5", 1], ["B4", 3], [".", 1],
		["A4", 2], ["E5", 1], ["D5", 1], ["C5", 2], [".", 2],
		["G4", 2], ["B4", 1], ["D5", 1], ["A4", 3], [".", 1],
	]
	var bass := [["A2", 4], ["F2", 4], ["A2", 4], ["G2", 4]]
	# Just a pulse and an offbeat tick: percussion here is a clock, not a groove. Sixteen characters
	# is four beats, so eight repeats covers the melody's thirty-two.
	return Track.new(96.0, 32).add(Voice.LEAD, lead).add(Voice.BASS, _times(bass, 2)) \
		.with_drums("k...h...k...h...".repeat(8))


## The room-clearing loop. Fast arcade, per spec section 22, and the track the player hears for
## most of a run — so it moves without ever arriving anywhere.
static func _explore() -> Track:
	var lead := [
		["A4", 1], ["A4", 0.5], ["C5", 0.5], ["E5", 1], ["D5", 1],
		["C5", 1], ["A4", 0.5], ["B4", 0.5], ["C5", 2],
		["F4", 1], ["F4", 0.5], ["A4", 0.5], ["C5", 1], ["B4", 1],
		["A4", 1], ["G4", 0.5], ["A4", 0.5], ["E4", 2],
		["A4", 1], ["C5", 0.5], ["E5", 0.5], ["G5", 1], ["E5", 1],
		["D5", 1], ["C5", 0.5], ["B4", 0.5], ["A4", 2],
		["G4", 1], ["B4", 0.5], ["D5", 0.5], ["F5", 1], ["D5", 1],
		["C5", 1], ["B4", 0.5], ["A4", 0.5], ["A4", 2],
	]
	var bass := _times([
		["A2", 0.5], ["A2", 0.5], ["A3", 0.5], ["A2", 0.5],
		["A2", 0.5], ["A2", 0.5], ["E3", 0.5], ["A2", 0.5],
		["F2", 0.5], ["F2", 0.5], ["F3", 0.5], ["F2", 0.5],
		["C3", 0.5], ["C3", 0.5], ["G3", 0.5], ["C3", 0.5],
	], 2)
	var arp := _times([["A5", 0.25], ["E5", 0.25], ["C5", 0.25], ["E5", 0.25]], 32)
	return Track.new(138.0, 32).add(Voice.LEAD, lead).add(Voice.BASS, _times(bass, 2)) \
		.add(Voice.ARP, arp).with_drums("k..hs..hk..hs.hh".repeat(8))


## The Merge Conflict. Faster than the explore loop, and built on a tritone that never resolves —
## the fight is two things that do not agree, so neither does the music.
static func _boss() -> Track:
	var lead := [
		["A4", 0.5], ["D#5", 0.5], ["A4", 0.5], ["E5", 0.5],
		["A4", 0.5], ["D#5", 0.5], ["F5", 1],
		["G#4", 0.5], ["D5", 0.5], ["G#4", 0.5], ["D#5", 0.5],
		["G#4", 0.5], ["D5", 0.5], ["E5", 1],
		["A4", 0.5], ["E5", 0.5], ["A5", 0.5], ["E5", 0.5],
		["F5", 0.5], ["E5", 0.5], ["D#5", 1],
		["D5", 0.5], ["A4", 0.5], ["D5", 0.5], ["F4", 0.5],
		["E4", 2],
	]
	var bass := _times([
		["A2", 0.5], ["A2", 0.5], ["D#3", 0.5], ["A2", 0.5],
		["A2", 0.5], ["A2", 0.5], ["A2", 0.5], ["A2", 0.5],
		["G#2", 0.5], ["G#2", 0.5], ["D3", 0.5], ["G#2", 0.5],
		["G#2", 0.5], ["G#2", 0.5], ["G#2", 0.5], ["G#2", 0.5],
	], 2)
	# Two passes of the melody, the second an octave up, so a fight that outlasts one loop does not
	# sound like the same four bars on repeat.
	return Track.new(156.0, 32).add(Voice.LEAD, lead + _up_octave(lead)).add(Voice.BASS, _times(bass, 2)) \
		.with_drums("ks.hks.hks.hkshh".repeat(8))


## Development's room-clearing loop. The Help Desk's explore theme is a robot doing its rounds; this
## one is a build running — mechanical, unhurried on the surface, and never quite settling.
##
## Still A minor, like every other track here, so descending a floor mid-crossfade is not a key
## change. What makes it a different floor is everything else: a sixteenth-note arpeggio running
## underneath the whole loop like a progress bar, a lead that keeps landing on the flat second (Bb)
## instead of the comfortable B, and a bass on the offbeat so the groove never sits down. Phrygian
## colour rather than a new key is the cheapest way to sound unfamiliar while staying compatible.
static func _dev_explore() -> Track:
	var lead := [
		["A4", 1], ["Bb4", 0.5], ["A4", 0.5], ["E5", 1], ["D5", 1],
		["C5", 0.5], ["Bb4", 0.5], ["A4", 1], ["Bb4", 2],
		["A4", 1], ["C5", 0.5], ["D5", 0.5], ["E5", 1], ["F5", 1],
		["E5", 0.5], ["D5", 0.5], ["C5", 1], ["A4", 2],
		["F4", 1], ["G4", 0.5], ["A4", 0.5], ["Bb4", 1], ["A4", 1],
		["G4", 0.5], ["F4", 0.5], ["E4", 1], ["E4", 2],
		["A4", 1], ["E5", 0.5], ["F5", 0.5], ["E5", 1], ["C5", 1],
		["Bb4", 1], ["A4", 0.5], ["Bb4", 0.5], ["A4", 2],
	]
	# Offbeat: the downbeat is a rest, so the bass answers the drum instead of doubling it.
	var bass := _times([
		[".", 0.5], ["A2", 0.5], [".", 0.5], ["A2", 0.5],
		[".", 0.5], ["Bb2", 0.5], [".", 0.5], ["A2", 0.5],
		[".", 0.5], ["F2", 0.5], [".", 0.5], ["F2", 0.5],
		[".", 0.5], ["E2", 0.5], [".", 0.5], ["E2", 0.5],
	], 2)
	# The progress bar. Four sixteenths per beat, climbing and never arriving.
	var arp := _times([
		["A5", 0.25], ["C6", 0.25], ["E6", 0.25], ["C6", 0.25],
		["Bb5", 0.25], ["D6", 0.25], ["F6", 0.25], ["D6", 0.25],
	], 16)
	return Track.new(150.0, 32).add(Voice.LEAD, lead).add(Voice.BASS, _times(bass, 2)) \
		.add(Voice.ARP, arp).with_drums("k.h.s.hkk.h.s.h.".repeat(8))


## Runtime Error. The Merge Conflict's theme is two things that do not agree; this one is one thing
## coming apart.
##
## Built on a descending chromatic line — A, G#, G, F# — under a lead that keeps restating the same
## figure a semitone lower each time, so the whole loop sinks. That is the fight: the boss does not
## get angrier, it degrades, and the player's job is to predict where the next failure lands. The
## tritone is here too, but as a passing note rather than the hook, so the two boss themes are
## recognisably from the same game and not the same fight.
static func _dev_boss() -> Track:
	var lead := [
		["A5", 0.5], ["E5", 0.5], ["A5", 0.5], ["C6", 0.5],
		["A5", 0.5], ["E5", 0.5], ["D#5", 1],
		["G#5", 0.5], ["D#5", 0.5], ["G#5", 0.5], ["B5", 0.5],
		["G#5", 0.5], ["D#5", 0.5], ["D5", 1],
		["G5", 0.5], ["D5", 0.5], ["G5", 0.5], ["Bb5", 0.5],
		["G5", 0.5], ["D5", 0.5], ["C#5", 1],
		["F#5", 0.5], ["C#5", 0.5], ["F#5", 0.5], ["A5", 0.5],
		["E5", 1], ["A4", 1],
	]
	# The collapse, one semitone per bar.
	var bass := [
		["A2", 0.5], ["A2", 0.5], ["A2", 0.5], ["E3", 0.5],
		["A2", 0.5], ["A2", 0.5], ["A2", 0.5], ["A2", 0.5],
		["G#2", 0.5], ["G#2", 0.5], ["G#2", 0.5], ["D#3", 0.5],
		["G#2", 0.5], ["G#2", 0.5], ["G#2", 0.5], ["G#2", 0.5],
		["G2", 0.5], ["G2", 0.5], ["G2", 0.5], ["D3", 0.5],
		["G2", 0.5], ["G2", 0.5], ["G2", 0.5], ["G2", 0.5],
		["F#2", 0.5], ["F#2", 0.5], ["F#2", 0.5], ["C#3", 0.5],
		["F#2", 0.5], ["F#2", 0.5], ["F#2", 0.5], ["F#2", 0.5],
	]
	# Both the melody and the collapse run twice, so the loop is thirty-two beats and the bass
	# descends A - G# - G - F# twice rather than once over a longer bar.
	return Track.new(168.0, 32).add(Voice.LEAD, lead + lead).add(Voice.BASS, _times(bass, 2)) \
		.with_drums("ksh.ks.hksh.kshh".repeat(8))


## The Data Center's room-clearing loop. A machine hall at steady load.
##
## Where Development never settles, this one settles *too much*, and that is the joke: the bass is
## on the downbeat, the pattern repeats almost exactly, and a sixteenth-note hat runs underneath
## like cooling fans that never change speed. It is the sound of a room that is fine, in a floor
## whose whole mechanic is that standing still in it is not.
##
## Still A minor. What makes it cold rather than merely calm is the lead sitting on bare fifths and
## fourths instead of thirds — no third means no major or minor colour, which is what a room full of
## machines with no opinion should sound like.
static func _data_explore() -> Track:
	var lead := [
		["A4", 2], ["E5", 2], ["A4", 1], ["D5", 1], ["E5", 2],
		["A4", 2], ["E5", 2], ["G4", 1], ["A4", 1], ["E5", 2],
		["D5", 2], ["A4", 2], ["E5", 1], ["D5", 1], ["A4", 2],
		["E4", 2], ["A4", 2], ["D5", 1], ["E5", 1], ["A4", 2],
	]
	# On the downbeat, and holding. The room is not going anywhere.
	var bass := [
		["A2", 2], ["A2", 2], ["A2", 2], ["A2", 2],
		["G2", 2], ["G2", 2], ["D2", 2], ["D2", 2],
		["A2", 2], ["A2", 2], ["A2", 2], ["A2", 2],
		["F2", 2], ["F2", 2], ["E2", 2], ["E2", 2],
	]
	# The fans: an unvarying sixteenth pulse on two notes a fifth apart.
	var arp := _times([["A5", 0.25], ["E5", 0.25]], 64)
	return Track.new(132.0, 32).add(Voice.LEAD, lead).add(Voice.BASS, bass).add(Voice.ARP, arp) \
		.with_drums("k.h.h.h.k.h.h.h.".repeat(8))


## Thermal runaway. The explore loop is a room holding steady; this is the same room losing the
## argument with its own heat.
##
## Built by taking that loop's calm and speeding it past the point where calm is possible: the same
## bare fifths, now at 176, with the fan pulse doubled into thirty-second notes and a bass that
## climbs instead of holding. Nothing about it is chromatic — this boss is not coming apart the way
## Runtime Error does, it is running too hot, and heat is a rising line.
static func _data_boss() -> Track:
	var lead := [
		["A5", 0.5], ["E5", 0.5], ["A5", 0.5], ["E5", 0.5],
		["B5", 0.5], ["E5", 0.5], ["B5", 0.5], ["E5", 0.5],
		["C6", 0.5], ["G5", 0.5], ["C6", 0.5], ["G5", 0.5],
		["D6", 1], ["A5", 1],
		["E6", 0.5], ["B5", 0.5], ["E6", 0.5], ["B5", 0.5],
		["D6", 0.5], ["A5", 0.5], ["C6", 0.5], ["G5", 0.5],
		["B5", 1], ["E5", 1], ["A5", 2],
	]
	# The climb: each bar starts a step higher than the last, and the last bar drops back to the
	# bottom so the loop can do it again.
	var bass := _times([
		["A2", 0.5], ["A2", 0.5], ["A2", 0.5], ["E3", 0.5],
		["B2", 0.5], ["B2", 0.5], ["B2", 0.5], ["F#3", 0.5],
		["C3", 0.5], ["C3", 0.5], ["C3", 0.5], ["G3", 0.5],
		["D3", 0.5], ["D3", 0.5], ["A2", 0.5], ["A2", 0.5],
	], 4)
	# The climb runs twice, like Runtime Error's collapse does, so the loop is thirty-two beats and
	# the rise happens twice rather than once at half the speed.
	return Track.new(176.0, 32).add(Voice.LEAD, lead + lead).add(Voice.BASS, bass) \
		.add(Voice.ARP, _times([["A6", 0.25], ["E6", 0.25]], 64)).with_drums("ksh.ksh.ksh.kshh".repeat(8))


## Cloud Operations' room-clearing loop, and the first track in the game built out of an idea rather
## than a mood.
##
## The floor's mechanic is that a place can also be a different place, so the melody is a call and
## an answer: a three-note figure low, then the *same figure* an octave up, then a tail that belongs
## to neither. Nothing is transposed for colour — it is the identical shape in a different register,
## which is what a migration is. Played once it sounds like a sequence. Played round the loop it
## stops being obvious which of the two is the original, which is the point.
##
## Forty-eight beats rather than the thirty-two every track before it runs to: the only cost of
## longer music is writing more bars, so this floor writes more bars. At 126 it comes out near
## twenty-three seconds.
##
## A minor with a raised sixth — F# instead of F. One note, and it is what stops the hall sounding
## like a crypt: the sixth is the interval that decides whether a minor key is sad or merely
## spacious, and this floor is enormous rather than sad.
static func _cloud_explore() -> Track:
	# The call, its answer an octave up, and a tail that resolves neither. Four of these.
	var call := [["A4", 1], ["C5", 1], ["E5", 2]]
	var answer := [["A5", 1], ["C6", 1], ["E6", 2]]
	var lead: Array = (
		call + answer + [["G5", 2], ["E5", 2]]
		+ call + answer + [["F#5", 2], ["D5", 2]]
		+ call + answer + [["E5", 2], ["C5", 2]]
		+ call + answer + [["D5", 2], ["A4", 2]]
	)
	# Two bars a chord, held. The ground does not move; only what is standing on it does.
	var bass := []
	for root: String in ["A2", "A2", "G2", "G2", "A2", "A2", "F#2", "F#2", "A2", "A2", "E2", "E2"]:
		bass.append([root, 4])
	# An eighth-note pulse rather than the Data Center's sixteenths: this hall's air moves overhead
	# and slowly, and the floor before it already owns the sound of fans at full tilt.
	var arp := _times([["A5", 0.5], ["E5", 0.5]], 48)
	return Track.new(126.0, 48).add(Voice.LEAD, lead).add(Voice.BASS, bass).add(Voice.ARP, arp) \
		.with_drums("k...h...k...h...".repeat(12))


## Failover. The explore loop's call and answer, with the answer arriving first.
##
## Same two registers and very nearly the same figure, reordered so the high line leads and the low
## one catches up half a beat late. That is the fight: the boss commits to being somewhere else and
## the player is trying to get there before it does. A listener does not have to know any of that —
## what it sounds like is a track permanently a fraction ahead of itself, which is the useful part.
##
## Also forty-eight beats, at 168. It ends on the tonic under a held fifth rather than climbing like
## the Data Center's boss does, because this fight is not a runaway; it is the same event three
## times, and the loop should be able to come round without having escalated.
static func _cloud_boss() -> Track:
	# The answer, then the call, then the gap the player is running through.
	var ahead := [["A5", 0.5], ["C6", 0.5], ["E6", 1]]
	var behind := [["A4", 0.5], ["C5", 0.5], ["E5", 1]]
	var lead := _times(
		ahead + behind + [["G5", 1], ["E5", 1]]
		+ ahead + behind + [["F#5", 1], ["D5", 1]]
		+ ahead + behind + [["E6", 1], ["B5", 1]]
		+ ahead + behind + [["A5", 2]],
		2
	)
	var bass := _times([
		["A2", 0.5], ["A2", 0.5], ["E3", 0.5], ["A2", 0.5],
		["G2", 0.5], ["G2", 0.5], ["D3", 0.5], ["G2", 0.5],
		["F#2", 0.5], ["F#2", 0.5], ["C#3", 0.5], ["F#2", 0.5],
		["A2", 0.5], ["A2", 0.5], ["E3", 0.5], ["E3", 0.5],
	], 6)
	return Track.new(168.0, 48).add(Voice.LEAD, lead).add(Voice.BASS, bass) \
		.add(Voice.ARP, _times([["A6", 0.25], ["E6", 0.25]], 96)).with_drums("k.s.h.s.k.s.h.hh".repeat(12))


## Sixteen bars of a clipped command motif, varied through four harmonies.
##
## The high voice answers the bass in the second half. Sixty-four beats gives a mature encounter a
## longer phrase before repeating (30 s explore, 24 s boss).
static func _executive(boss: bool) -> Track:
	var harmonies := [["D", "F", "A"], ["Bb", "D", "F"], ["G", "Bb", "D"], ["A", "C#", "E"]]
	var lead := []
	var bass := []
	var arp := []
	for bar: int in 16:
		var harmony: Array = harmonies[(bar / 2) % 4]
		var root: String = harmony[0]
		var third: String = harmony[1]
		var fifth: String = harmony[2]
		var octave := "5" if bar >= 8 else "4"
		lead += [
			[root + octave, 0.5], [third + octave, 0.5], [fifth + octave, 1],
			[".", 0.5], [third + octave, 0.5], [root + octave, 1],
		]
		bass += [[root + "2", 1], [".", 0.5], [root + "2", 0.5], [fifth + "2", 1], [root + "2", 1]]
		arp += _times([[root + "5", 0.5], [fifth + "5", 0.5]], 4)
	var drums := "k.s.h.s.k.s.h.hh" if boss else "k...h.s.k...h.s."
	return Track.new(160.0 if boss else 128.0, 64).add(Voice.LEAD, lead).add(Voice.BASS, bass) \
		.add(Voice.ARP, arp).with_drums(drums.repeat(16))


## The campaign's six-floor motif compressed into one long, unresolved machine pulse.
##
## Explore states the six-note cell in ascending registers. The boss reverses it and doubles the
## percussion, so the finale feels like the run being evaluated rather than a seventh mood.
static func _core(boss: bool) -> Track:
	var cell: Array[String] = ["A", "C", "D", "E", "G", "B"]
	if boss:
		cell.reverse()
	var roots: Array[String] = ["A", "F", "D", "E"]
	var lead := []
	var bass := []
	var arp := []
	for bar: int in 16:
		var root := roots[(bar / 4) % roots.size()]
		for step: int in cell.size():
			var octave := "5" if (bar + step) % 4 != 0 else "6"
			lead.append([cell[step] + octave, 0.5])
		lead.append([root + "5", 1.0])
		bass += [[root + "2", 1.0], [".", 0.5], [root + "3", 0.5], ["E2", 1.0], [root + "2", 1.0]]
		arp += _times([[root + "5", 0.25], ["E5", 0.25]], 8)
	var drums := "kshhkshhkshhkshh" if boss else "k...h.s.k...h.s."
	return Track.new(172.0 if boss else 136.0, 64).add(Voice.LEAD, lead).add(Voice.BASS, bass) \
		.add(Voice.ARP, arp).with_drums(drums.repeat(16))


# --- Helpers -------------------------------------------------------------------------


## `events` played `count` times over.
static func _times(events: Array, count: int) -> Array:
	var out := []
	for _index: int in count:
		out += events
	return out


## The same events an octave higher: "D#5" becomes "D#6". Rests pass through unchanged.
static func _up_octave(events: Array) -> Array:
	var out := []
	for event: Array in events:
		var note: String = event[0]
		if note != ".":
			note = note.left(-1) + str(int(note.right(1)) + 1)
		out.append([note, event[1]])
	return out

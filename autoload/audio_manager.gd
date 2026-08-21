extends Node
## Pooled one-shot sound playback, and the music.
##
## A dumb service on purpose: it knows how to make a noise, not when to. The mapping
## from gameplay events to sounds lives in FeedbackDirector, so there is exactly one
## file to read when asking "why did it make that sound". Music is the same deal —
## `play_music` takes a track id and nothing here knows what a boss is.
##
## Players are pooled and reused round-robin. Creating an AudioStreamPlayer per shot
## would churn nodes at four allocations a second, and the pool doubles as a natural
## voice cap: the oldest sound is cut rather than fifty overlapping copies summing
## into clipping.
##
## Music gets two players rather than one, which is the whole reason it is not just
## `play_sfx` with a loop flag. Cutting from the explore loop to the boss loop is jarring
## in a way that has nothing to do with the tracks and everything to do with the cut, and
## a crossfade needs both playing at once for a moment.

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const POOL_SIZE := 16

## Godot's floor for an inaudible player. Anything lower is the same silence.
const SILENT_DB := -80.0

const LIBRARY := {
	&"fire": "res://audio/sfx/fire.wav",
	&"enemy_hit": "res://audio/sfx/enemy_hit.wav",
	&"enemy_death": "res://audio/sfx/enemy_death.wav",
	&"player_hurt": "res://audio/sfx/player_hurt.wav",
	&"dash": "res://audio/sfx/dash.wav",
	&"room_clear": "res://audio/sfx/room_clear.wav",
	&"low_integrity": "res://audio/sfx/low_integrity.wav",
	&"pickup": "res://audio/sfx/pickup.wav",
	&"door": "res://audio/sfx/door.wav",
	&"item_pickup": "res://audio/sfx/item_pickup.wav",
	&"explosion": "res://audio/sfx/explosion.wav",
	&"zap": "res://audio/sfx/zap.wav",
	&"ui_move": "res://audio/sfx/ui_move.wav",
	&"ui_confirm": "res://audio/sfx/ui_confirm.wav",
	&"ui_back": "res://audio/sfx/ui_back.wav",
	&"purchase": "res://audio/sfx/purchase.wav",
	&"boss_phase": "res://audio/sfx/boss_phase.wav",
	&"victory": "res://audio/sfx/victory.wav",
	&"game_over": "res://audio/sfx/game_over.wav",
}

## Spec section 22: chiptune, industrial percussion, fast arcade loops. One track per
## situation the player can be in for minutes at a time, and *all five* in A minor so a
## crossfade between any two is a key change nobody notices.
##
## That rule is why Development sounds different without being in a different key: its two
## loops are told apart by tempo, by an offbeat bass, and by leaning on the flat second rather
## than by moving the tonic. Descending a floor crossfades between two of these mid-phrase,
## and it should sound like the same game changing its mind, not like a track ending.
##
## Which floor gets which pair is `FloorTheme`'s business, not this file's. Nothing here knows
## what a floor is; it owns the library and the crossfade and nothing else.
const MUSIC_LIBRARY := {
	&"menu": "res://audio/music/menu.wav",
	&"explore": "res://audio/music/explore.wav",
	&"boss": "res://audio/music/boss.wav",
	&"dev_explore": "res://audio/music/dev_explore.wav",
	&"dev_boss": "res://audio/music/dev_boss.wav",
	&"data_explore": "res://audio/music/data_explore.wav",
	&"data_boss": "res://audio/music/data_boss.wav",
}

## Seconds to crossfade between tracks. Long enough not to read as a cut, short enough that
## walking into the boss room feels like it caused something.
const MUSIC_FADE_SECONDS := 1.2

## How many mix cycles to wait for at teardown (see `_drain_mixer`). A stopped playback is faded
## out on one mix and released on a later one, so one is not enough.
const MIXER_DRAIN_MIXES := 2

## Gives up after this long. A driver that has already been torn down will never mix again, and an
## untidy exit is a much better outcome than an exit that hangs.
const MIXER_DRAIN_TIMEOUT_MS := 500

## Polling interval, short against the shortest mix period worth waiting for.
const MIXER_POLL_MS := 1

## How long the mixer may go without running before the output is presumed dead.
##
## The audio thread mixes on its own clock and does not care how long a game frame took, so this is
## not a frame-rate measurement: on a healthy driver `get_time_since_last_mix` oscillates inside one
## mix period and never climbs. Measured here, that is about 3 ms on CoreAudio, 11-37 ms through
## the Dummy driver the headless suite uses, and a comparable figure on WASAPI. A full second is
## therefore two orders of magnitude past anything a working driver produces, which is where a
## watchdog threshold belongs: nowhere near the noise, so a trip means something.
const OUTPUT_STALL_SECONDS := 1.0

## How long after one recovery attempt before another is allowed. A driver that is going to come
## back does so on the next mix; one that is not will not be helped by being asked ten times a
## second, and the log line matters more than the retry.
const OUTPUT_RECOVERY_COOLDOWN := 5.0

var _streams: Dictionary[StringName, AudioStream] = {}
var _music_streams: Dictionary[StringName, AudioStream] = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_index := 0

## Two music players, crossfaded between. `_music_active` indexes whichever is fading *in*.
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id: StringName = &""

## 0..1 progress of the current crossfade. Reaches 1 and stays there between changes.
var _fade := 1.0

## Seconds the mixer has been observed not running, and how long until another recovery may be
## attempted. See `_step_output_watchdog`.
var _output_stalled_for := 0.0
var _output_recovery_cooldown := 0.0

## How many times the output has been re-opened this session. Surfaced by `describe_state` rather
## than kept private, because a number that is not zero is the whole answer to a bug report.
var _output_recoveries := 0


func _ready() -> void:
	# Sound must keep playing through a hit pause and through the pause menu — a game whose
	# music stops when paused sounds like it crashed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_library()
	_build_pool()
	_build_music_players()


## Plays a sound by id. `pitch_variation` randomises pitch by +/- that fraction,
## which is what stops a repeated sound becoming fatiguing (spec section 22).
func play_sfx(id: StringName, pitch_variation := 0.0, volume_db := 0.0) -> void:
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		push_warning("AudioManager: unknown sound id '%s'." % id)
		return

	var player := _pool[_next_index]
	_next_index = (_next_index + 1) % _pool.size()

	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## Crossfades to `id`, or does nothing if it is already the track that is playing. The
## no-op case is the important one: this is called on every room entry, and restarting the
## explore loop each time the player walks through a door would be worse than no music.
func play_music(id: StringName) -> void:
	if id == _music_id:
		return
	var stream: AudioStream = _music_streams.get(id)
	if stream == null:
		push_warning("AudioManager: unknown music id '%s'." % id)
		return

	_music_id = id
	_music_active = 1 - _music_active
	_fade = 0.0

	var incoming := _music[_music_active]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()


## Fades the music out and leaves it out. Called when a run ends: the victory fanfare and the
## power-down both need the room to themselves.
func stop_music() -> void:
	if _music_id.is_empty():
		return
	_music_id = &""
	_fade = 0.0
	# Swapping to the other player with nothing loaded makes the outgoing track fade out
	# through exactly the same code path as a normal change, rather than a second one.
	_music_active = 1 - _music_active
	_music[_music_active].stop()


func _process(delta: float) -> void:
	# Before the fade and outside its early-out, deliberately. The watchdog has to run on every
	# frame of a session that is *not* changing tracks, which is almost all of them.
	_step_output_watchdog(delta, AudioServer.get_time_since_last_mix())
	_step_fade(delta)


## Both music players are driven every frame rather than by a Tween, because a fade that is
## interrupted by another fade has to pick up from wherever it got to. A tween would have to
## be killed and replaced, and the killed one occasionally lands its final value afterwards.
func _step_fade(delta: float) -> void:
	if _fade >= 1.0:
		return
	_fade = minf(_fade + delta / MUSIC_FADE_SECONDS, 1.0)

	for index: int in _music.size():
		var player := _music[index]
		var gain := _fade if index == _music_active else 1.0 - _fade
		player.volume_db = linear_to_db(gain) if gain > 0.001 else SILENT_DB
		if gain <= 0.001 and player.playing and index != _music_active:
			player.stop()


## Notices that the audio output has stopped running, says so, and asks for it back.
##
## **This is a mitigation for a cause that has not been confirmed, and it is written to be honest
## about that.** The report it exists for was: on Windows, mid-run, the music and every sound effect
## went at the same moment, nothing was printed, and nothing about the run explained it. Everything
## above this line was measured and cleared — the crossfade, the loop across its wrap, the sixteen
## voice pool under a minute of combat-rate playback, and the bus layout the two buses send through.
## What is left is below all of it: the AudioServer's own output. A driver that has lost its device
## takes the music and the sound effects together, needs no trigger, and on Windows can do it
## without raising anything the game would see, which is the whole of the shape reported.
##
## So the check is on the one thing that is true of a dead output and false of everything else: the
## mixer has stopped running. That is a fact, not an inference, and it is measured rather than
## guessed at — `get_time_since_last_mix` climbing past a second means no audio has been produced
## for a second, whatever the reason.
##
## **The log line is the deliverable; the recovery is a bonus.** Re-selecting the output device is
## the documented way to make a driver re-open it, and if the failure is a lost device it is the fix.
## If it is something else, re-selecting the device it already has costs a glitch nobody will hear
## and the warning still lands — which turns "it went quiet and there was nothing in the console"
## into a timestamped line naming the cause. That is worth more than the retry.
##
## Skipped on the web, where the mixer runs on the same thread as the game: there a long frame really
## can stall it, so the one platform where this could produce a false positive is the one platform
## where the failure it looks for cannot happen.
func _step_output_watchdog(delta: float, seconds_since_mix: float) -> void:
	if OS.has_feature("web"):
		return

	_output_recovery_cooldown = maxf(_output_recovery_cooldown - delta, 0.0)
	if seconds_since_mix < OUTPUT_STALL_SECONDS:
		_output_stalled_for = 0.0
		return

	# Counted as well as compared, so a single sampling artefact cannot trip it: the mixer has to
	# have been missing for a second *and* have been observed missing across a second of frames.
	_output_stalled_for += delta
	if _output_stalled_for < OUTPUT_STALL_SECONDS or _output_recovery_cooldown > 0.0:
		return

	_output_stalled_for = 0.0
	_output_recovery_cooldown = OUTPUT_RECOVERY_COOLDOWN
	_output_recoveries += 1
	push_warning(
		("AudioManager: the audio output has not mixed for %.1fs (attempt %d). Re-opening '%s'. "
		+ "If sound does not come back, the driver has gone and the process needs restarting.")
		% [seconds_since_mix, _output_recoveries, AudioServer.output_device]
	)
	# Assigning the device is what asks the driver to re-open it. Assigned rather than toggled
	# through another name, because a device list read from a broken driver is not something to
	# trust, and picking a device the player did not choose is a worse outcome than not recovering.
	AudioServer.output_device = AudioServer.output_device


## Silences everything. Called on the way out, and it is not merely tidy: a stream that is
## still playing when the engine tears down is still *referenced* when the engine checks for
## leaks, which reported "1 resources still in use at exit" plus two leaked ObjectDB
## instances.
##
## The reproduced trigger was narrow — the pause menu's QUIT button played `ui_back` and
## called `quit()` on the same frame, so the sound could not possibly finish. Quitting a few
## frames after ordinary gameplay sounds was measured and did *not* leak, because those are
## short enough to have ended. This is kept anyway as the general guard, since "no audio is
## mid-playback at teardown" is a cheaper thing to guarantee than to audit call by call.
##
## Stopping is only half of it, though: see `_drain_mixer`.
func stop_all() -> void:
	for player: AudioStreamPlayer in _pool:
		player.stop()
	for player: AudioStreamPlayer in _music:
		player.stop()
	_music_id = &""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		stop_all()
	# The stopping above is not enough on its own, and this is the last moment it can be
	# corrected — nothing gets another frame after this.
	if what == NOTIFICATION_EXIT_TREE:
		_drain_mixer()


## Waits for the mixer to run, because stopping a stream does not release it: it marks the
## playback for deletion and the audio thread does the deleting on its next mix. On the quit paths
## the game controls that mix has already happened, since `get_tree().quit()` only takes effect at
## the end of the frame. On an exit the game gets no notice of — `--quit-after`, the editor's stop
## button — the tree tears down between mixes and the marked playback is still in the audio
## server's list when the engine counts leaked objects, which is the same
## "1 resources still in use at exit" and two leaked instances as before, reported for the music
## rather than for a menu sound.
##
## Waiting on the mixer's own clock rather than sleeping a fixed span, because the mix period is
## the driver's business and differs by an order of magnitude between them: ~3 ms of CoreAudio
## here against ~93 ms of the Dummy driver the headless test runs use.
func _drain_mixer() -> void:
	var deadline := Time.get_ticks_msec() + MIXER_DRAIN_TIMEOUT_MS
	var mixes := 0
	var previous := AudioServer.get_time_since_last_mix()
	while mixes < MIXER_DRAIN_MIXES and Time.get_ticks_msec() < deadline:
		OS.delay_msec(MIXER_POLL_MS)
		var since := AudioServer.get_time_since_last_mix()
		# The clock counts up from each mix, so it only ever goes down by starting again.
		if since < previous:
			mixes += 1
		previous = since


## What the manager believes it is doing, for the debug overlay.
##
## It exists because "the audio cut out" is a report nobody can act on. Silence has two completely
## different causes and they need opposite fixes: either this file has stopped asking for sound — a
## track that ended, a fade that stalled, a `stop_music` nothing followed — or it is still asking and
## nothing downstream is listening, which is the bus layout, the mixer, or the driver. From the
## player's chair those are the same event. This line tells them apart on sight: if it reads
## `data_explore PLAYING 7.2s` while the room is silent, the game is fine and the problem is below
## it; if it reads `STOPPED`, the problem is here.
##
## Reported rather than logged, and polled rather than pushed, for the reason every other row in the
## overlay is: it changes every frame, and something that only prints when it thinks something is
## wrong cannot report the case where it does not know.
func describe_state() -> String:
	var player := _music[_music_active]
	var track := String(_music_id) if not _music_id.is_empty() else "none"
	var voices := 0
	for sfx: AudioStreamPlayer in _pool:
		if sfx.playing:
			voices += 1
	# `mix` is the one that matters when everything has gone quiet at once: it is milliseconds since
	# the audio output last ran, so a healthy driver holds it in the tens and a dead one lets it
	# climb without bound. `recovered` counts what the watchdog has had to do about it.
	#
	# `lat` catches the failure `mix` cannot see, and it is a different failure with a different
	# feel: the driver is still mixing on time, but the audio it has been handed is queued behind
	# a backlog that keeps growing, so every sound arrives later than the last. Nothing goes quiet
	# and nothing warns — the shots just drift out of sync with the firing and keep drifting. Two
	# numbers apart tell it from a healthy output on a high-latency device: it is the *growth* that
	# is the fault, so a number sitting at 30 ms is fine and the same number climbing is not.
	var recovered := "" if _output_recoveries == 0 else "  recovered %d" % _output_recoveries
	return "%s %s %.1fs  fade %.2f  sfx %d/%d  mix %.0fms  lat %.0fms%s" % [
		track,
		"PLAYING" if player.playing else "STOPPED",
		player.get_playback_position(),
		_fade,
		voices,
		_pool.size(),
		AudioServer.get_time_since_last_mix() * 1000.0,
		AudioServer.get_output_latency() * 1000.0,
		recovered,
	]


func set_bus_volume_db(bus: StringName, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, volume_db)


## Creates the SFX and Music buses if the bus layout is missing or was replaced.
## Volume settings (spec section 21) target these by name, so a missing bus would
## silently make those settings do nothing.
##
## A fallback, and only a fallback. The buses this game plays into are authored in
## `data/audio/default_bus_layout.tres` and loaded by the engine before any autoload runs, which
## on the web is not a tidiness preference but the difference between a game with sound and one
## without. Godot's web export defaults `audio/general/default_playback_type.web` to *Sample*:
## an `AudioStreamWAV` is handed to WebAudio as a buffer and routed through a JavaScript-side
## mirror of the bus graph, and that mirror is built once, from the bus layout, at startup. A bus
## added afterwards by the line below exists to the AudioServer and to nothing else, so every
## player targeting it plays into a bus the web side has never heard of, and the whole game — SFX
## and music alike — is silent. Desktop mixes buses itself and never noticed, which is why this
## survived the desktop milestones and broke in a browser.
##
## So this stays for the case it was written for — a layout file that is missing or has been
## replaced by one that dropped a bus — and on a normal launch it finds both buses already there
## and does nothing.
func _ensure_buses() -> void:
	for bus: StringName in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")


func _load_library() -> void:
	for id: StringName in LIBRARY:
		var stream := load(LIBRARY[id]) as AudioStream
		if stream == null:
			push_warning("AudioManager: failed to load '%s'." % LIBRARY[id])
			continue
		_streams[id] = stream

	for id: StringName in MUSIC_LIBRARY:
		var stream := load(MUSIC_LIBRARY[id]) as AudioStream
		if stream == null:
			push_warning("AudioManager: failed to load '%s'." % MUSIC_LIBRARY[id])
			continue
		# Set here rather than trusted from the .import file. A loop flag lost in a reimport
		# turns a twenty-second loop into twenty seconds of music followed by silence, which
		# is the kind of bug that gets reported as "the music is broken sometimes".
		#
		# `loop_end` is a frame index and must be the end of the sample, not 0. A zero-length
		# loop region is not "loop the whole thing" — the playback hits the end of the loop on
		# its first mix and goes inactive, so every track was silent from the moment it started.
		# The importer spells the same idea as -1, but that is wrapped to the length at import
		# time only; the property itself has no such convenience.
		var wav := stream as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		_music_streams[id] = stream


func _build_music_players() -> void:
	for _index: int in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = SILENT_DB
		add_child(player)
		_music.append(player)


func _build_pool() -> void:
	for _index: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_pool.append(player)

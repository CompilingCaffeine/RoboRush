extends TestCase
## The sound library, the music library, and the crossfade. Spec section 22.
##
## Audio is the part of the game a test cannot judge — whether the boss theme is any good is
## not a checkable proposition. What *is* checkable is every way it silently stops working,
## and those are worth pinning down precisely because nobody notices them by playing: a
## missing sound id is a warning in a log nobody reads, and a loop flag lost in a reimport
## turns a twenty-second loop into twenty seconds of music followed by silence.
##
## Runs headless, where there is no audio device. That is fine — Godot's AudioServer still
## reports bus and player state, which is all of this.

## Restored in _teardown: the suites after this one should not inherit a boss theme.
var _entry_music: StringName


func run() -> void:
	_entry_music = AudioManager._music_id

	_test_the_buses_come_from_the_layout_file()
	_test_every_sound_in_the_library_loads()
	_test_every_priority_sound_from_the_spec_exists()
	_test_unknown_ids_are_survivable()
	_test_music_loops()
	await _test_music_keeps_playing()
	await _test_music_crossfades()
	await _test_repeating_a_track_does_not_restart_it()
	await _test_stopping_music_fades_it_out()
	await _test_stop_all_leaves_nothing_playing()
	_test_the_mixer_drain_ends_on_the_mixer()
	_test_a_healthy_output_never_trips_the_watchdog()
	_test_a_stalled_output_is_noticed_and_reopened()
	await _test_the_watchdog_runs_when_nothing_is_fading()
	await _test_the_director_plays_the_floors_own_tracks()

	_teardown()


## `FeedbackDirector` decides *when* the music changes and the floor's theme decides *which*
## tracks it changes between. Checked here rather than in the floor suite because the failure
## it guards is an audio one: a director that kept its old hardcoded `&"boss"`/`&"explore"`
## would pass every floor check — the theme would load, the textures would apply — and
## Development would simply play the Help Desk's soundtrack.
func _test_the_director_plays_the_floors_own_tracks() -> void:
	var director := FeedbackDirector.new()
	add_child(director)
	await advance_physics(1)

	var development := load("res://data/floors/floor_2_development.tres") as FloorConfig
	if development == null or development.theme == null:
		fail("Development's theme is needed to check the director")
		director.queue_free()
		return

	director.set_floor_theme(development.theme)

	AudioManager.stop_music()
	director._on_room_entered(RoomTemplate.Type.COMBAT, 0)
	check(
		AudioManager._music_id == development.theme.explore_music,
		"an ordinary room plays the floor's explore loop (got '%s')" % AudioManager._music_id,
	)

	director._on_room_entered(RoomTemplate.Type.BOSS, 1)
	check(
		AudioManager._music_id == development.theme.boss_music,
		"the boss arena plays the floor's boss loop (got '%s')" % AudioManager._music_id,
	)

	# A floor with no theme falls back rather than keeping the last floor's tracks, which is
	# the difference between "authored no music" and "inherited someone else's".
	director.set_floor_theme(null)
	AudioManager.stop_music()
	director._on_room_entered(RoomTemplate.Type.COMBAT, 2)
	check(
		AudioManager._music_id == FeedbackDirector.DEFAULT_EXPLORE_MUSIC,
		"an unthemed floor falls back to the default loop (got '%s')" % AudioManager._music_id,
	)

	director.queue_free()
	await advance_physics(2)


func _teardown() -> void:
	AudioManager.stop_music()
	if not _entry_music.is_empty():
		AudioManager.play_music(_entry_music)


## The whole browser build was silent because of this, and nothing in the game could tell.
##
## `AudioManager._ensure_buses` creates Music and SFX at startup if they are missing, and for
## several milestones that was the only thing that created them: the project shipped no bus layout,
## the desktop mixer did not care, and every suite passed. The web export plays an `AudioStreamWAV`
## as a WebAudio buffer through a JavaScript-side mirror of the bus graph that is built once, from
## the layout file, before any autoload runs — so both buses were created too late to exist there,
## every player was routed to a bus the web side had never heard of, and the game made no sound at
## all. Measured in a real browser: zero samples reached the audio destination through a whole menu
## and a whole run, and 0.13 peak through the same run once the layout existed.
##
## Checked against the file rather than against `AudioServer`, which is the distinction that
## matters: by the time a test can ask, `_ensure_buses` has already run and would answer yes on a
## project that is about to ship silence.
func _test_the_buses_come_from_the_layout_file() -> void:
	var path := str(ProjectSettings.get_setting("audio/buses/default_bus_layout", ""))
	if not require(not path.is_empty(), "the project names a default bus layout"):
		return
	var layout := ResourceLoader.load(path) as AudioBusLayout
	if not require(layout != null, "the bus layout at %s loads" % path):
		return

	# AudioBusLayout exposes nothing about its buses to script, so the layout is asked the only
	# way it can be: applied to the server, which is what the engine does with it at startup.
	var restore := AudioServer.generate_bus_layout()
	AudioServer.set_bus_layout(layout)
	var names: Array[StringName] = []
	for index: int in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(index))
	AudioServer.set_bus_layout(restore)

	for bus: StringName in [&"Master", AudioManager.MUSIC_BUS, AudioManager.SFX_BUS]:
		check(
			bus in names,
			"the layout file defines the '%s' bus, so the web build has it before a sound plays"
					% bus,
		)


func _test_every_sound_in_the_library_loads() -> void:
	for id: StringName in AudioManager.LIBRARY:
		check(
			AudioManager._streams.has(id),
			"sound '%s' loaded from %s" % [id, AudioManager.LIBRARY[id]],
		)
	for id: StringName in AudioManager.MUSIC_LIBRARY:
		check(
			AudioManager._music_streams.has(id),
			"track '%s' loaded from %s" % [id, AudioManager.MUSIC_LIBRARY[id]],
		)


## Spec section 22 lists ten priority sounds by name. This is the list, and it is a test
## rather than a comment because "we have a sound for that" is the kind of claim that stops
## being true quietly.
func _test_every_priority_sound_from_the_spec_exists() -> void:
	var required: Array[StringName] = [
		&"fire",          # 1. player firing
		&"enemy_hit",     # 2. enemy hit
		&"enemy_death",   # 3. enemy death
		&"player_hurt",   # 4. player damage
		&"item_pickup",   # 5. item pickup
		&"room_clear",    # 6. room clear
		&"door",          # 7. door opening
		&"dash",          # 8. dash
		&"boss_phase",    # 9. boss phase transition
		&"low_integrity", # 10. low health warning
	]
	for id: StringName in required:
		check(AudioManager._streams.has(id), "spec section 22 priority sound '%s' exists" % id)


## A bad id must be a warning and nothing else. These are called from presentation code during
## combat, and a hard failure there would take the run down over a sound.
func _test_unknown_ids_are_survivable() -> void:
	AudioManager.play_sfx(&"__no_such_sound")
	AudioManager.play_music(&"__no_such_track")
	check(true, "an unknown sound or track id does not bring the game down")
	check(
		AudioManager._music_id != &"__no_such_track",
		"a failed music request does not become the current track",
	)


## The one that matters most. Every track is a loop, and a WAV whose loop mode is off plays
## once and leaves the game silent for the rest of the run.
func _test_music_loops() -> void:
	for id: StringName in AudioManager.MUSIC_LIBRARY:
		var wav := AudioManager._music_streams[id] as AudioStreamWAV
		if not require(wav, "track '%s' is a WAV" % id):
			continue
		check(
			wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"track '%s' is set to loop forward" % id,
		)
		check(wav.get_length() > 4.0, "track '%s' is long enough to be a loop, not a sting" % id)
		# A loop region has to contain something. `loop_end` is a frame index, and leaving it
		# at 0 means the loop ends where it begins, which is not "loop the whole track".
		check(
			wav.loop_end > wav.loop_begin,
			"track '%s' loops over the sample rather than over nothing (frames %d..%d)"
					% [id, wav.loop_begin, wav.loop_end],
		)


## The one the loop flags were supposed to protect, from the other side: not "is the resource
## configured to loop" but "did the stream get anywhere". This is the check that was missing when
## every track was silent for a whole milestone — `loop_end` was left at 0, so the loop region was
## empty, the playback went inactive on its first mix, and nothing in the manager's own state said
## so. `_music_id` was right, the fade ran to full volume, and the game played no music at all.
func _test_music_keeps_playing() -> void:
	AudioManager.stop_music()
	AudioManager.play_music(&"explore")
	var player := AudioManager._music[AudioManager._music_active]

	await advance_physics(30)

	check(player.playing, "the track is still playing, not stopped on its first mix")
	var position := player.get_playback_position()
	check(position > 0.0, "the playback position has advanced (%.3fs in)" % position)


func _test_music_crossfades() -> void:
	AudioManager.stop_music()
	AudioManager.play_music(&"explore")
	check(AudioManager._music_id == &"explore", "requesting a track makes it the current one")

	var incoming := AudioManager._music[AudioManager._music_active]
	check(incoming.playing, "the incoming player starts immediately")
	check(
		incoming.volume_db <= AudioManager.SILENT_DB,
		"the incoming player starts silent and fades up",
	)

	AudioManager.play_music(&"boss")
	var previous := AudioManager._music[1 - AudioManager._music_active]
	check(
		previous.playing,
		"the outgoing track keeps playing during the fade rather than cutting",
	)

	# Long enough to finish a MUSIC_FADE_SECONDS crossfade, at 60 physics ticks per second.
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)

	check_near(AudioManager._fade, 1.0, "the crossfade reaches its end", 0.01)
	check(
		AudioManager._music[AudioManager._music_active].volume_db > -1.0,
		"the incoming track ends the fade at full volume",
	)
	check(
		not AudioManager._music[1 - AudioManager._music_active].playing,
		"the outgoing track is stopped once it is inaudible, rather than left running",
	)


## Called on every room entry, so this is the common case rather than an edge one.
func _test_repeating_a_track_does_not_restart_it() -> void:
	AudioManager.play_music(&"explore")
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)

	var player := AudioManager._music[AudioManager._music_active]
	var position := player.get_playback_position()
	var active_before := AudioManager._music_active

	AudioManager.play_music(&"explore")

	check(
		AudioManager._music_active == active_before,
		"asking for the track already playing does not swap players",
	)
	check(
		player.get_playback_position() >= position,
		"asking for the track already playing does not restart it",
	)
	check_near(AudioManager._fade, 1.0, "and does not begin a new crossfade", 0.01)


func _test_stopping_music_fades_it_out() -> void:
	AudioManager.play_music(&"explore")
	await advance_physics(20)
	AudioManager.stop_music()

	check(AudioManager._music_id.is_empty(), "stopping clears the current track")

	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)

	var anything_audible := false
	for player: AudioStreamPlayer in AudioManager._music:
		if player.playing and player.volume_db > AudioManager.SILENT_DB:
			anything_audible = true
	check(not anything_audible, "nothing is still playing once the fade out finishes")


## The invariant behind a real bug: the pause menu's QUIT button played a sound and called
## `quit()` on the same frame, so the stream was still playing when the engine tore down and
## was still referenced when it checked for leaks — "1 resources still in use at exit", plus
## two leaked ObjectDB instances, reported from an actual playthrough.
##
## The leak itself only happens at process exit and cannot be observed from inside a suite.
## What can be pinned is the mechanism: after `stop_all` nothing is playing, so there is
## nothing left to be referenced.
func _test_stop_all_leaves_nothing_playing() -> void:
	AudioManager.play_music(&"explore")
	for id: StringName in [&"ui_back", &"fire", &"enemy_hit"]:
		AudioManager.play_sfx(id)
	await advance_physics(1)

	var playing_before := 0
	for player: AudioStreamPlayer in AudioManager._pool:
		if player.playing:
			playing_before += 1
	check(playing_before > 0, "there is something to stop (%d voices)" % playing_before)

	AudioManager.stop_all()

	var still_playing := 0
	for player: AudioStreamPlayer in AudioManager._pool + AudioManager._music:
		if player.playing:
			still_playing += 1
	check(still_playing == 0, "stop_all leaves nothing playing (%d still going)" % still_playing)
	check(AudioManager._music_id.is_empty(), "stop_all forgets the current track")


## Stopping a stream only marks its playback for deletion; the audio thread releases it on a later
## mix, and an exit that arrives in between leaks it. The guard is therefore a wait for the mixer,
## and a wait that times out is indistinguishable from one that worked except in how long the game
## takes to close. This pins the part that can quietly stop being true: that the mixer's clock is
## observable, so the wait ends on the mixer rather than on its own timeout.
func _test_the_mixer_drain_ends_on_the_mixer() -> void:
	AudioManager.play_sfx(&"fire")
	AudioManager.stop_all()

	var started := Time.get_ticks_msec()
	AudioManager._drain_mixer()
	var elapsed := Time.get_ticks_msec() - started

	check(
		elapsed < AudioManager.MIXER_DRAIN_TIMEOUT_MS,
		"waiting for %d mixes returns before the %d ms timeout (took %d ms)" % [
			AudioManager.MIXER_DRAIN_MIXES, AudioManager.MIXER_DRAIN_TIMEOUT_MS, elapsed,
		],
	)


# --- The output watchdog -------------------------------------------------------
#
# From a bug report with no reproduction: on Windows, mid-run, the music and every sound effect
# stopped at the same moment, with nothing in the console and no pattern to what preceded it.
# Everything in this file above this line was already passing at the time and still is, which is
# most of what makes the driver the remaining suspect — the crossfade, the loop, the pool and the
# bus layout were all measured and cleared.
#
# The watchdog is therefore a mitigation for an unconfirmed cause, and these checks are written to
# hold the two things that actually have to be true of one: it must not fire on a working game, and
# it must fire on a dead output. The first is the important one. A watchdog that cries wolf is worse
# than no watchdog, because the first thing anybody does with one is turn it off.


## The whole session, at every mix period this project has ever run on. Nothing here may trip.
func _test_a_healthy_output_never_trips_the_watchdog() -> void:
	var before := AudioManager._output_recoveries

	# CoreAudio's ~3 ms, the Dummy driver's ~93 ms, and a deliberately awful 300 ms — six times the
	# worst real period measured and still a third of the threshold.
	for period: float in [0.003, 0.011, 0.037, 0.093, 0.3]:
		AudioManager._output_stalled_for = 0.0
		for _frame: int in 600:
			# The value the AudioServer would report: it climbs inside a mix period and resets, which
			# is the shape that must never be read as a stall however long the period is.
			AudioManager._step_output_watchdog(1.0 / 60.0, randf() * period)

	check(
		AudioManager._output_recoveries == before,
		"ten seconds at each of five mix periods trips nothing (%d attempts)"
			% [AudioManager._output_recoveries - before],
	)


## And the case it exists for. Driven by handing it the reading rather than by breaking a real
## driver, because there is no way to break a real driver from inside the game — which is also why
## the check has to be written this way round rather than not written.
func _test_a_stalled_output_is_noticed_and_reopened() -> void:
	AudioManager._output_stalled_for = 0.0
	AudioManager._output_recovery_cooldown = 0.0
	var before := AudioManager._output_recoveries

	# Half a second of frames with the mixer already a second behind. Past the threshold on the
	# reading, short of it on the duration — a single bad sample must not be enough.
	for _frame: int in 30:
		AudioManager._step_output_watchdog(1.0 / 60.0, 1.5)
	check(
		AudioManager._output_recoveries == before,
		"half a second of missing mixer is not yet a failure",
	)

	# The rest of the second.
	for _frame: int in 40:
		AudioManager._step_output_watchdog(1.0 / 60.0, 1.5)
	check(
		AudioManager._output_recoveries == before + 1,
		"a full second of it is, and the output is re-opened once (%d)"
			% [AudioManager._output_recoveries - before],
	)

	# And exactly once. A driver that has gone will keep reading stalled for as long as the game
	# runs, and a warning per frame would bury the one line that matters in thousands of copies.
	for _frame: int in 120:
		AudioManager._step_output_watchdog(1.0 / 60.0, 1.5)
	check(
		AudioManager._output_recoveries == before + 1,
		"and not again inside the cooldown (%d)" % [AudioManager._output_recoveries - before],
	)

	check(
		"recovered" in AudioManager.describe_state(),
		"the overlay says it happened: '%s'" % AudioManager.describe_state(),
	)

	AudioManager._output_recovery_cooldown = 0.0
	AudioManager._output_stalled_for = 0.0


## The ordering bug this was one line away from shipping with. `_process` used to return early
## whenever no crossfade was running, which is almost every frame of a session — a watchdog added
## after that return would have been a watchdog that only ran during the 1.2 seconds after a track
## change, and the reported failure had no pattern at all.
func _test_the_watchdog_runs_when_nothing_is_fading() -> void:
	AudioManager.stop_music()
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 10)
	check(AudioManager._fade >= 1.0, "no crossfade is running (fade %.2f)" % AudioManager._fade)

	AudioManager._output_stalled_for = 0.0
	# The cooldown is the probe, because it is the one piece of watchdog state that moves on *every*
	# frame regardless of what the mixer is doing. If `_process` returns before reaching the
	# watchdog, this number does not change — which is exactly the bug being guarded against, and it
	# is measurable without needing a stalled driver to measure it with.
	AudioManager._output_recovery_cooldown = 1.0
	# Through `_process` rather than through the step function, so the early-out is what is measured.
	AudioManager._process(0.25)

	check(
		is_equal_approx(AudioManager._output_recovery_cooldown, 0.75),
		"a frame with no crossfade in flight still reaches the watchdog (cooldown %.2f, expected 0.75)"
			% AudioManager._output_recovery_cooldown,
	)
	AudioManager._output_recovery_cooldown = 0.0
	AudioManager._output_stalled_for = 0.0

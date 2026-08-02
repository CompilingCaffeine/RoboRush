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

	_test_every_sound_in_the_library_loads()
	_test_every_priority_sound_from_the_spec_exists()
	_test_unknown_ids_are_survivable()
	_test_music_loops()
	await _test_music_crossfades()
	await _test_repeating_a_track_does_not_restart_it()
	await _test_stopping_music_fades_it_out()
	await _test_stop_all_leaves_nothing_playing()

	_teardown()


func _teardown() -> void:
	AudioManager.stop_music()
	if not _entry_music.is_empty():
		AudioManager.play_music(_entry_music)


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

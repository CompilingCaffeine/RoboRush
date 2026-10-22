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

## How many frames a track may take to render through the manager's own queue. A track is a few
## hundred milliseconds of work at a couple of milliseconds a frame, so this is several times what
## the longest needs and only there so a render that never finishes fails rather than hangs.
const RENDER_FRAMES_MAX := 2000

## Restored in _teardown: the suites after this one should not inherit a boss theme.
var _entry_music: StringName


func run() -> void:
	_entry_music = AudioManager._music_id

	_test_the_buses_come_from_the_layout_file()
	_test_every_sound_in_the_library_loads()
	_test_every_priority_sound_from_the_spec_exists()
	_test_unknown_ids_are_survivable()
	# The tracks the checks below play, rendered the way the game renders them. Everything after
	# this point can then expect a request for either to start at once, as it does in a run.
	await _render(&"explore")
	await _render(&"boss")
	_test_music_loops()
	await _test_music_keeps_playing()
	await _test_music_crossfades()
	await _test_repeating_a_track_does_not_restart_it()
	await _test_stopping_music_fades_it_out()
	await _test_stop_all_leaves_nothing_playing()
	await _test_a_track_still_rendering_starts_when_ready()
	await _test_a_request_overtaken_before_it_is_ready_starts_nothing()
	await _test_stopping_while_rendering_keeps_it_stopped()
	_test_the_track_wanted_now_is_rendered_first()
	_test_rendering_takes_more_of_a_frame_when_nobody_is_playing()
	_test_the_mixer_drain_ends_on_the_mixer()
	_test_a_healthy_output_never_trips_the_watchdog()
	_test_a_stalled_output_is_noticed_and_reopened()
	await _test_the_watchdog_runs_when_nothing_is_fading()
	await _test_the_director_plays_the_floors_own_tracks()
	# Last, because it forgets the explore loop that everything above expects to start at once.
	await _test_the_title_screen_prepares_the_music_a_run_opens_on()

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
	# The music is rendered on demand rather than loaded, so what can be checked up front is that
	# every track the manager offers has a score to render. `test_music` renders each of them.
	for id: StringName in AudioManager.MUSIC_LIBRARY:
		check(MusicScore.track(id) != null, "track '%s' has a score" % id)


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
## once and leaves the game silent for the rest of the run. `test_music` holds every track the
## synthesiser makes to this; here it is the streams the manager itself ended up with.
func _test_music_loops() -> void:
	for id: StringName in [&"explore", &"boss"]:
		var wav: AudioStreamWAV = AudioManager._music_streams.get(id)
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


## The music is rendered the first time it is wanted, so a request can arrive before its track
## exists. What has to hold is that nothing goes quiet waiting for it: the track already playing
## carries on, and the crossfade happens when the new one is ready, through the same path as ever.
func _test_a_track_still_rendering_starts_when_ready() -> void:
	AudioManager.play_music(&"explore")
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)
	var playing := AudioManager._music[AudioManager._music_active]
	_forget(&"dev_boss")

	AudioManager.play_music(&"dev_boss")
	check(AudioManager._music_id == &"dev_boss", "a track still rendering is the current one at once")
	check(AudioManager._audible_id == &"explore", "but what is heard is still the last one")
	check(playing.playing and playing.volume_db > -1.0, "which carries on at full volume")
	check(
		"(rendering)" in AudioManager.describe_state(),
		"and the overlay says why (%s)" % AudioManager.describe_state(),
	)

	var frames := await _wait_until_ready(&"dev_boss")
	var incoming := AudioManager._music[AudioManager._music_active]
	check(AudioManager._audible_id == &"dev_boss", "once rendered (%d frames), the track starts" % frames)
	check(incoming != playing and incoming.playing, "on the other player")
	check(incoming.stream == AudioManager._music_streams.get(&"dev_boss"), "playing what was rendered")
	check(AudioManager._fade < 1.0, "and fading in, rather than cutting")


## A request replaced before it is ready must not start late. Walking into the boss room and straight
## back out is the shape of it: the explore loop is asked for again while the boss loop is still
## rendering, and the boss loop must not cut in a second later over a room that did not want it.
func _test_a_request_overtaken_before_it_is_ready_starts_nothing() -> void:
	AudioManager.play_music(&"explore")
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)
	var active := AudioManager._music_active
	_forget(&"boss")

	AudioManager.play_music(&"boss")
	AudioManager.play_music(&"explore")
	check(AudioManager._music_id == &"explore", "the track asked for last is the current one")
	check(AudioManager._music_active == active, "and the one playing was never swapped out")

	await _wait_until_ready(&"boss")
	check(AudioManager._audible_id == &"explore", "the overtaken track does not start once it is ready")
	check(AudioManager._music_active == active, "and the explore loop was not restarted for it")


func _test_stopping_while_rendering_keeps_it_stopped() -> void:
	_forget(&"data_boss")
	AudioManager.play_music(&"data_boss")
	AudioManager.stop_music()

	await _wait_until_ready(&"data_boss")
	await advance_physics(int(AudioManager.MUSIC_FADE_SECONDS * 60.0) + 20)

	check(AudioManager._audible_id.is_empty(), "a track that finishes rendering after a stop does not start")
	var anything_audible := false
	for player: AudioStreamPlayer in AudioManager._music:
		if player.playing and player.volume_db > AudioManager.SILENT_DB:
			anything_audible = true
	check(not anything_audible, "and nothing is playing")


## The order the queue works in. A floor asks for both of its tracks as it begins, and the one its
## opening room plays has to be the first one ready.
func _test_the_track_wanted_now_is_rendered_first() -> void:
	_forget(&"cloud_boss")
	_forget(&"core_boss")
	AudioManager.prepare_music(&"cloud_boss")
	AudioManager.prepare_music(&"core_boss")
	var queue := AudioManager._render_queue
	check(
		queue.find(&"cloud_boss") < queue.find(&"core_boss"),
		"tracks asked for ahead are rendered in the order they were asked for",
	)

	AudioManager.play_music(&"core_boss")
	check(queue.front() == &"core_boss", "a track wanted now goes to the front of the queue")
	AudioManager.prepare_music(&"core_boss")
	check(queue.count(&"core_boss") == 1, "asking for it again does not queue it twice")
	AudioManager.prepare_music(&"cloud_boss")
	check(queue.front() == &"core_boss", "and asking ahead for another does not push it back")

	AudioManager.prepare_music(&"__no_such_track")
	check(not queue.has(&"__no_such_track"), "an id that is not a track is never queued")
	AudioManager.stop_music()


## The renderer's share of a frame follows the run's clock rather than the game state, which starts
## as RUN: on the boot screen that would hand the gameplay rate to a screen whose only job is to
## wait, and the menu loop would still be rendering when the menu opened.
func _test_rendering_takes_more_of_a_frame_when_nobody_is_playing() -> void:
	var was_timing := RunManager.is_timing()

	RunManager.set_timing(true)
	check(
		AudioManager._render_budget_usec() == AudioManager.MUSIC_RENDER_BUDGET_USEC,
		"a run being played gives the renderer its small share of the frame",
	)
	RunManager.set_timing(false)
	check(
		AudioManager._render_budget_usec() == AudioManager.MUSIC_RENDER_IDLE_BUDGET_USEC,
		"and a game nobody is playing gives it the large one",
	)
	check(
		AudioManager.MUSIC_RENDER_IDLE_BUDGET_USEC > AudioManager.MUSIC_RENDER_BUDGET_USEC,
		"which is the larger of the two",
	)

	RunManager.set_timing(was_timing)


## The title screen renders the explore loop of the floor a run would open on, so that a run starts
## on its own music rather than on the menu's. With a run to continue, that floor goes first, since
## CONTINUE is the entry the menu puts first.
func _test_the_title_screen_prepares_the_music_a_run_opens_on() -> void:
	var first := MainMenu.CAMPAIGN.load_theme(0)
	var later := MainMenu.CAMPAIGN.load_theme(1)
	if not require(first, "the first floor's theme loads without its floor") \
			or not require(later, "and so does the second's"):
		return
	check(first.explore_music != later.explore_music, "the first two floors open on different loops")

	_forget(first.explore_music)
	await _open_title_screen()
	check(
		AudioManager._render_queue.has(first.explore_music),
		"the title screen queues the first floor's explore loop ('%s')" % first.explore_music,
	)
	var queue := AudioManager._render_queue
	if queue.has(&"menu"):
		check(
			queue.find(&"menu") < queue.find(first.explore_music),
			"behind the title screen's own track",
		)
	await _wait_until_ready(first.explore_music)
	await _close_title_screen()

	# A saved run on the second floor. Set directly rather than stored, so nothing is written.
	var saved := SaveManager._checkpoint
	var checkpoint := RunCheckpoint.new()
	checkpoint.floor_id = MainMenu.CAMPAIGN.floor_id_at(1)
	SaveManager._checkpoint = checkpoint
	_forget(first.explore_music)
	_forget(later.explore_music)
	await _open_title_screen()
	queue = AudioManager._render_queue
	check(
		queue.has(later.explore_music) and queue.has(first.explore_music)
		and queue.find(later.explore_music) < queue.find(first.explore_music),
		"with a run to continue, its floor's loop is queued ahead of the first floor's (%s)" % [queue],
	)
	SaveManager._checkpoint = saved
	await _wait_until_ready(first.explore_music)
	await _close_title_screen()
	AudioManager.stop_music()


var _title_screen: MainMenu


func _open_title_screen() -> void:
	_title_screen = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_title_screen)
	await advance_physics(1)


func _close_title_screen() -> void:
	_title_screen.queue_free()
	_title_screen = null
	await advance_physics(1)


## Renders `id` through the manager's own queue, the way the game does, at the front of it.
func _render(id: StringName) -> void:
	AudioManager._queue_render(id, true)
	await _wait_until_ready(id)


## Advances frames until `id` is rendered, and returns how many that took.
func _wait_until_ready(id: StringName) -> int:
	var frames := 0
	while not AudioManager.is_music_ready(id) and frames < RENDER_FRAMES_MAX:
		await advance_physics(1)
		frames += 1
	check(
		AudioManager.is_music_ready(id),
		"'%s' renders within %d frames (took %d)" % [id, RENDER_FRAMES_MAX, frames],
	)
	return frames


## Puts `id` back to not rendered, so a check can watch it being rendered. On the web this would leave
## the old copy in the browser's audio memory; a test run is never on the web.
func _forget(id: StringName) -> void:
	AudioManager._music_streams.erase(id)
	AudioManager._render_queue.erase(id)
	AudioManager._render_jobs.erase(id)


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

extends TestCase
## Settings, the save format, and the lifetime record. Spec sections 21 and 24.
##
## The whole point of this system is that it survives things — a restart, a corrupt file, a
## build that predates a field. None of that can be checked by playing the game once, which
## makes it the part of milestone 6 most worth having a suite for.
##
## Almost nothing here writes to disk. `SaveManager.persistence_enabled` is false for the whole
## test run (see the runner), and the round-trip checks go through `to_dict`/`from_dict` directly,
## which is the pair a file would exercise anyway. The one exception is the failed-write check,
## which has to touch a real file to be worth anything — it points the manager at a disposable
## path first, because a test that wrote to the real one would clobber the save of whoever ran it.

## Restored in `_teardown`, because the suite mutates the live manager and every suite after
## this one shares it.
var _saved_settings: GameSettings
var _saved_best: BestRunStats


func run() -> void:
	_saved_settings = SaveManager.settings
	_saved_best = SaveManager.best

	_test_defaults_are_sane()
	_test_settings_round_trip()
	_test_settings_survive_a_corrupt_file()
	_test_volume_bottoms_out_at_silence()
	_test_applying_settings_reaches_the_mixer_and_feedback()
	_test_best_stats_only_move_upwards()
	_test_victory_time_is_a_lower_is_better_record()
	_test_best_stats_round_trip()
	_test_unlocks_are_recorded_once()
	await _test_a_finished_run_files_exactly_one_result()
	await _test_a_failed_write_stays_pending_and_recovers()

	_teardown()


func _teardown() -> void:
	SaveManager.settings = _saved_settings
	SaveManager.best = _saved_best
	SaveManager.apply_settings()


func _test_defaults_are_sane() -> void:
	var settings := GameSettings.new()
	check(settings.damage_numbers, "damage numbers default on")
	check(not settings.crt_enabled, "the CRT filter defaults off (spec section 21: optional)")
	check(not settings.fullscreen, "the game defaults to windowed")
	check_near(settings.screen_shake, 1.0, "screen shake defaults to the authored intensity")
	check(
		settings.master_volume > 0.0 and settings.master_volume <= 1.0,
		"master volume defaults to something audible",
	)


func _test_settings_round_trip() -> void:
	var written := GameSettings.new()
	written.master_volume = 0.42
	written.music_volume = 0.0
	written.sfx_volume = 1.0
	written.fullscreen = true
	written.screen_shake = 0.0
	written.flash_intensity = 1.75
	written.crt_enabled = true
	written.damage_numbers = false

	var read := GameSettings.from_dict(written.to_dict())

	check_near(read.master_volume, 0.42, "master volume survives a round trip")
	check_near(read.music_volume, 0.0, "a zeroed slider survives rather than reverting")
	check_near(read.sfx_volume, 1.0, "effects volume survives a round trip")
	check(read.fullscreen, "fullscreen survives a round trip")
	check_near(read.screen_shake, 0.0, "screen shake off survives — an accessibility setting")
	check_near(read.flash_intensity, 1.75, "flash intensity survives a round trip")
	check(read.crt_enabled, "the CRT toggle survives a round trip")
	check(not read.damage_numbers, "damage numbers off survives a round trip")


## Spec section 24: "handle missing or outdated fields gracefully". Every one of these is a
## file someone could actually end up with — truncated by a crash, hand-edited, or written by
## a build that had different fields.
func _test_settings_survive_a_corrupt_file() -> void:
	var defaults := GameSettings.new()

	var empty := GameSettings.from_dict({})
	check_near(empty.master_volume, defaults.master_volume, "an empty save gives defaults")

	var wrong_types := GameSettings.from_dict({
		"master_volume": "loud",
		"damage_numbers": 3,
		"screen_shake": null,
	})
	check_near(
		wrong_types.master_volume, defaults.master_volume, "a string volume falls back rather than crashing"
	)
	check(
		wrong_types.damage_numbers == defaults.damage_numbers,
		"a numeric boolean falls back rather than being coerced",
	)
	check_near(wrong_types.screen_shake, defaults.screen_shake, "a null intensity falls back")

	var partial := GameSettings.from_dict({"music_volume": 0.25})
	check_near(partial.music_volume, 0.25, "a field that is present is read")
	check_near(
		partial.sfx_volume, defaults.sfx_volume, "a field that is absent costs only that field"
	)

	var out_of_range := GameSettings.from_dict({"screen_shake": 400.0, "master_volume": -5.0})
	check_near(
		out_of_range.screen_shake,
		GameSettings.INTENSITY_MAX,
		"a hand-edited intensity is clamped, not trusted",
	)
	check_near(out_of_range.master_volume, 0.0, "a negative volume is clamped to silence")


func _test_volume_bottoms_out_at_silence() -> void:
	check(
		GameSettings.volume_to_db(0.0) <= -80.0,
		"a slider at zero is actual silence, not a very quiet sound",
	)
	check_near(GameSettings.volume_to_db(1.0), 0.0, "a slider at full is unity gain")
	check(
		GameSettings.volume_to_db(0.5) < 0.0 and GameSettings.volume_to_db(0.5) > -80.0,
		"a slider in the middle is attenuated but audible",
	)


## The coupling that matters: changing a setting has to reach the things that obey it, or the
## screen is a row of switches wired to nothing.
func _test_applying_settings_reaches_the_mixer_and_feedback() -> void:
	var settings := GameSettings.new()
	settings.master_volume = 1.0
	settings.sfx_volume = 0.0
	settings.screen_shake = 0.0
	settings.flash_intensity = 0.5
	settings.damage_numbers = false
	SaveManager.settings = settings
	SaveManager.apply_settings()

	var sfx_index := AudioServer.get_bus_index(&"SFX")
	check(sfx_index >= 0, "the SFX bus exists to be set")
	if sfx_index >= 0:
		check(
			AudioServer.get_bus_volume_db(sfx_index) <= -80.0,
			"an effects slider at zero silences the SFX bus",
		)

	var feedback := GameManager.feedback
	if require(feedback, "the feedback config is loaded"):
		check_near(feedback.screen_shake_scale, 0.0, "screen shake off reaches FeedbackConfig")
		check_near(feedback.flash_intensity, 0.5, "flash intensity reaches FeedbackConfig")
		check(not feedback.damage_numbers_enabled, "the damage number toggle reaches FeedbackConfig")

	var emitted: Array[GameSettings] = []
	var probe := func(value: GameSettings) -> void: emitted.append(value)
	SaveManager.settings_changed.connect(probe)
	SaveManager.apply_settings()
	SaveManager.settings_changed.disconnect(probe)
	check(emitted.size() == 1, "applying settings tells whatever else is listening, exactly once")


func _test_best_stats_only_move_upwards() -> void:
	var best := BestRunStats.new()

	var strong := RunStats.new()
	strong.rooms_cleared = 9
	strong.enemies_defeated = 40
	strong.scrap_collected = 120
	strong.highest_hit = 14.5
	strong.longest_clean_streak = 4
	var first := best.absorb(strong, false)

	check(best.most_rooms_cleared == 9, "a first run sets every record")
	check(first.size() == 5, "a first run reports every record it set (got %d)" % first.size())

	var weak := RunStats.new()
	weak.rooms_cleared = 2
	weak.enemies_defeated = 3
	weak.scrap_collected = 5
	weak.highest_hit = 1.0
	weak.longest_clean_streak = 1
	var second := best.absorb(weak, false)

	check(best.most_rooms_cleared == 9, "a worse run does not lower a record")
	check(best.highest_hit > 14.0, "a worse hit does not lower the highest hit")
	check(second.is_empty(), "a worse run reports no records beaten")
	check(best.runs_won == 0, "a run that was not won is not counted as a victory")


func _test_victory_time_is_a_lower_is_better_record() -> void:
	var best := BestRunStats.new()

	var lost := RunStats.new()
	lost.duration = 30.0
	best.absorb(lost, false)
	check_near(best.fastest_victory, 0.0, "a fast *loss* is not a fast run")

	var slow_win := RunStats.new()
	slow_win.duration = 600.0
	var slow_records := best.absorb(slow_win, true)
	check_near(best.fastest_victory, 600.0, "the first victory sets the time record whatever it was")
	check("TIME" in slow_records, "the first victory reports a new best time")
	check(best.runs_won == 1, "a victory is counted")

	var fast_win := RunStats.new()
	fast_win.duration = 420.0
	best.absorb(fast_win, true)
	check_near(best.fastest_victory, 420.0, "a faster victory lowers the time record")

	var slower_win := RunStats.new()
	slower_win.duration = 900.0
	var slower_records := best.absorb(slower_win, true)
	check_near(best.fastest_victory, 420.0, "a slower victory does not raise the time record")
	check(not ("TIME" in slower_records), "a slower victory is not reported as a record")
	check(best.runs_won == 3, "every victory is counted, record or not")


func _test_best_stats_round_trip() -> void:
	var best := BestRunStats.new()
	best.fastest_victory = 305.5
	best.most_rooms_cleared = 10
	best.runs_started = 7
	best.runs_won = 2
	best.highest_hit = 33.25

	var read := BestRunStats.from_dict(best.to_dict())
	check_near(read.fastest_victory, 305.5, "the best time survives a round trip")
	check(read.most_rooms_cleared == 10, "a count survives a round trip as an integer")
	check(read.runs_started == 7, "the run count survives a round trip")
	check_near(read.highest_hit, 33.25, "the highest hit survives a round trip")

	var hostile := BestRunStats.from_dict({"runs_won": -4, "most_rooms_cleared": "lots"})
	check(hostile.runs_won == 0, "a negative record is treated as absent, not trusted")
	check(hostile.most_rooms_cleared == 0, "a non-numeric record falls back to zero")

	check(not BestRunStats.new().has_history(), "a fresh record has no history to show")
	check(read.has_history(), "a record with runs in it has history")


func _test_unlocks_are_recorded_once() -> void:
	var before := SaveManager.unlocked_items.size()
	var item := ItemConfig.new()
	item.id = &"__test_only_item"
	item.display_name = "Test Item"

	EventBus.item_collected.emit(item)
	EventBus.item_collected.emit(item)

	check(
		SaveManager.unlocked_items.count(&"__test_only_item") == 1,
		"picking the same item up twice records one unlock",
	)
	check(
		SaveManager.unlocked_items.size() == before + 1,
		"recording an unlock does not disturb the others",
	)
	SaveManager.unlocked_items.erase(&"__test_only_item")


## The end of a run has two callers on some frames — the player dying and the state machine
## settling — and a double count would inflate a record permanently.
func _test_a_finished_run_files_exactly_one_result() -> void:
	SaveManager.best = BestRunStats.new()

	RunManager.begin_run(4242)
	check(SaveManager.best.runs_started == 1, "beginning a run counts it")

	RunManager.stats.rooms_cleared = 6
	RunManager.end_run(true)
	RunManager.end_run(true)
	RunManager.end_run(false)

	check(SaveManager.best.runs_won == 1, "a run that ends three times is won once")
	check(SaveManager.best.most_rooms_cleared == 6, "the finished run's numbers are filed")
	check(
		"ROOMS CLEARED" in RunManager.records_beaten,
		"the run remembers which records it beat, for the summary screen",
	)

	# Left in a clean state: the suites that follow begin their own runs.
	RunManager.begin_run(1)
	await advance_physics(1)


## Reported: a transient save failure cleared the "needs saving" flag before the write
## succeeded, suppressing retries.
##
## `save_game` set `_dirty = false` on its first line, before it had even opened the file. Both
## failure paths then returned with the flag already down, and the flag is the only thing that
## makes anything try again — `_process` retries while dirty, and so does the flush on quit. So
## one blip lost every setting, record and unlock for the rest of the session, with nothing but
## a warning to show for it.
##
## The failure here is real rather than mocked: a directory sitting where the temporary file
## needs to go, which makes FileAccess.open fail exactly as a permissions problem or a full disk
## would, and which can then be cleared to prove the retry recovers.
func _test_a_failed_write_stays_pending_and_recovers() -> void:
	var was_enabled := SaveManager.persistence_enabled
	var real_save: String = SaveManager._save_path
	var real_temp: String = SaveManager._temp_path

	# Never the real paths: a test that wrote there would clobber the save of whoever ran it.
	SaveManager._save_path = "user://test_only_save.json"
	SaveManager._temp_path = SaveManager._save_path + ".tmp"
	SaveManager.persistence_enabled = true

	var blocker := ProjectSettings.globalize_path(SaveManager._temp_path)
	DirAccess.remove_absolute(blocker)
	check(
		DirAccess.make_dir_absolute(blocker) == OK,
		"a directory can be put in the way of the temporary file",
	)

	SaveManager.request_save()
	SaveManager.save_game()

	check(SaveManager._dirty, "a failed write leaves the save pending rather than forgetting it")
	check(
		not FileAccess.file_exists(SaveManager._save_path),
		"and nothing was written",
	)
	# Without a backoff, _process would call save_game every frame from here on.
	check(
		SaveManager._save_countdown > SaveManager.SAVE_DEBOUNCE_SECONDS,
		"the retry is backed off (%.1fs) rather than run every frame"
			% SaveManager._save_countdown,
	)

	# A second failure must not multiply the warnings, and must stay pending.
	SaveManager.save_game()
	check(SaveManager._dirty, "still pending after a second failure")

	# Clear the condition: the next attempt should land.
	DirAccess.remove_absolute(blocker)
	SaveManager.save_game()

	check(not SaveManager._dirty, "the retry succeeds once the condition clears")
	check(
		FileAccess.file_exists(SaveManager._save_path),
		"and the save file is actually there",
	)

	var written: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SaveManager._save_path)
	)
	check(written is Dictionary, "what landed is readable JSON")
	if written is Dictionary:
		check(
			(written as Dictionary).get("save_version") == SaveManager.SAVE_VERSION,
			"and it is a save file, not a half-written one",
		)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager._save_path))
	DirAccess.remove_absolute(blocker)
	SaveManager._save_path = real_save
	SaveManager._temp_path = real_temp
	SaveManager.persistence_enabled = was_enabled
	SaveManager._dirty = false
	SaveManager._failed_writes = 0
	await advance_physics(1)

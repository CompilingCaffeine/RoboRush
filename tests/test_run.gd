extends TestCase
## Checks for the run lifecycle: spec section 25's statistics and spec section 23's states.
##
## Every check here touches process-wide autoload state, which makes this the one suite
## that can break every other suite if it leaves a mess. Two things in particular: a run
## left in GAME_OVER leaves `get_tree().paused` true, and a paused tree stops every enemy
## and projectile in the suites that run afterwards. So each state check restores the run
## before it returns, and `run()` restores it again at the end regardless.

const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const SUMMARY_SCENE := preload("res://scenes/ui/run_summary.tscn")


func run() -> void:
	_test_stats_start_empty()
	_test_stats_record_combat()
	_test_clean_streak_survives_only_clean_rooms()
	_test_favourite_weapon_is_measured()
	_test_duration_formatting()
	_test_describe_covers_the_spec()

	await _test_event_bus_feeds_the_statistics()
	await _test_cause_of_death_names_the_enemy()
	await _test_begin_run_resets_everything()

	await _test_pause_and_resume()
	await _test_a_run_ends_once()
	await _test_victory_is_a_different_ending()
	await _test_duration_stops_when_the_run_does()
	await _test_summary_appears_when_the_run_ends()

	_restore()


# --- RunStats in isolation ----------------------------------------------------


func _test_stats_start_empty() -> void:
	var stats := RunStats.new()
	check(stats.rooms_cleared == 0, "a new run has cleared no rooms")
	check(stats.enemies_defeated == 0, "and defeated nothing")
	check(stats.cause_of_death.is_empty(), "and has no cause of death")
	check(stats.get_favourite_weapon() == "none", "and no favourite weapon yet")


func _test_stats_record_combat() -> void:
	var stats := RunStats.new()
	stats.record_damage_dealt(1.0)
	stats.record_damage_dealt(4.5)
	stats.record_damage_dealt(2.0)

	check_near(stats.damage_dealt, 7.5, "damage dealt accumulates")
	check_near(stats.highest_hit, 4.5, "the highest single hit is the highest, not the last")

	stats.record_damage_taken(2.0)
	check_near(stats.damage_taken, 2.0, "damage taken accumulates separately")


func _test_clean_streak_survives_only_clean_rooms() -> void:
	var stats := RunStats.new()
	stats.record_room_cleared()
	stats.record_room_cleared()
	stats.record_room_cleared()
	check(stats.longest_clean_streak == 3, "three rooms without a scratch is a streak of three")

	stats.record_damage_taken(1.0)
	check(stats.current_clean_streak == 0, "taking a hit ends the streak")
	check(stats.longest_clean_streak == 3, "but the best streak is remembered")

	stats.record_room_cleared()
	check(stats.longest_clean_streak == 3, "a shorter later streak does not replace it")


func _test_favourite_weapon_is_measured() -> void:
	var stats := RunStats.new()
	stats.record_shot("Rivet Blaster")
	stats.record_shot("Rivet Blaster")
	stats.record_shot("Saw Launcher")
	check(
		stats.get_favourite_weapon() == "Rivet Blaster",
		"the favourite weapon is the one most shots came out of",
	)


func _test_duration_formatting() -> void:
	check(RunStats.format_duration(0.0) == "0:00", "zero reads as 0:00")
	check(RunStats.format_duration(65.0) == "1:05", "65 seconds reads as 1:05")
	check(RunStats.format_duration(600.0) == "10:00", "ten minutes reads as 10:00")


## Spec section 25 lists twelve things to track. A summary missing one of them is a summary
## that quietly stopped answering a question the design asked it to answer.
func _test_describe_covers_the_spec() -> void:
	var stats := RunStats.new()
	stats.cause_of_death = "Memory Leech"
	stats.items_collected.append("Fork Bomb")

	var labels := PackedStringArray()
	for row: Array in stats.describe():
		labels.append(row[0])
	var joined := " ".join(labels)

	for expected: String in [
		"TIME", "ROOMS", "ENEMIES", "BOSSES", "DAMAGE DEALT", "DAMAGE TAKEN",
		"SCRAP", "ITEMS", "HIGHEST HIT", "CLEAN STREAK", "WEAPON", "DESTROYED BY",
	]:
		check(joined.contains(expected), "the summary reports %s" % expected)


# --- The EventBus wiring ------------------------------------------------------


func _test_event_bus_feeds_the_statistics() -> void:
	RunManager.begin_run(99)
	var stats := RunManager.stats

	var enemy := Node2D.new()
	add_child(enemy)

	EventBus.enemy_damaged.emit(enemy, DamageInfo.new(2.5), 1.0)
	EventBus.enemy_damaged.emit(enemy, DamageInfo.new(1.0), 0.0)
	EventBus.enemy_killed.emit(enemy, Vector2.ZERO)
	EventBus.room_cleared.emit()
	RunManager.add_scrap(7)

	check_near(stats.damage_dealt, 3.5, "enemy_damaged feeds damage dealt")
	check_near(stats.highest_hit, 2.5, "and the highest hit")
	check(stats.enemies_defeated == 1, "enemy_killed feeds the defeated count")
	check(stats.rooms_cleared == 1, "room_cleared feeds the room count")
	check(stats.scrap_collected == 7, "scrap collected is counted as it is picked up")

	# Spending must not inflate what was collected, or the summary rewards shopping.
	RunManager.try_spend_scrap(5)
	check(stats.scrap_collected == 7, "spending scrap does not change how much was collected")
	check(RunManager.scrap == 2, "but it does change how much is held")

	enemy.queue_free()
	await advance_physics(1)


## The summary must name the thing that killed the player, not the node that happened to
## hold the weapon.
func _test_cause_of_death_names_the_enemy() -> void:
	RunManager.begin_run(99)

	var bot: TicketBot = TICKET_BOT_SCENE.instantiate()
	add_child(bot)
	await advance_physics(2)

	EventBus.player_damaged.emit(DamageInfo.new(1.0, bot), 3.0)
	check(
		RunManager.stats.cause_of_death.is_empty(),
		"a survivable hit records no cause of death",
	)

	EventBus.player_damaged.emit(DamageInfo.new(1.0, bot), 0.0)
	check(
		RunManager.stats.cause_of_death == "Ticket Bot",
		"the fatal hit records the enemy's display name (got '%s')" % RunManager.stats.cause_of_death,
	)

	bot.queue_free()
	await advance_physics(2)


## Statistics are replaced wholesale rather than reset field by field, so this also guards
## against a field added later being left behind by the reset.
func _test_begin_run_resets_everything() -> void:
	RunManager.begin_run(1)
	RunManager.add_scrap(30)
	RunManager.stats.enemies_defeated = 12
	RunManager.stats.cause_of_death = "something"

	RunManager.begin_run(2)
	check(RunManager.scrap == 0, "a new run starts with no scrap")
	check(RunManager.stats.enemies_defeated == 0, "and no kills")
	check(RunManager.stats.cause_of_death.is_empty(), "and no cause of death")
	check(RunManager.stats.duration < 0.5, "and no elapsed time")
	check(RunManager.offered_item_ids.is_empty(), "and an untouched item pool")
	await advance_physics(1)


# --- Game states --------------------------------------------------------------


func _test_pause_and_resume() -> void:
	_restore()
	check(GameManager.is_playing(), "a fresh run is playing")
	check(not get_tree().paused, "and the tree is running")

	GameManager.pause_game()
	check(GameManager.state == GameManager.State.PAUSED, "pausing enters the paused state")
	check(get_tree().paused, "and pauses the tree, which is what stops the player acting")
	check(not GameManager.is_playing(), "a paused game is not being played")

	GameManager.resume_game()
	check(GameManager.is_playing(), "resuming returns to the run")
	check(not get_tree().paused, "and unpauses the tree")
	await advance_physics(1)


## The player can be killed by two things in the same frame. A run that ended twice would
## show the summary, hide it, and show it again.
func _test_a_run_ends_once() -> void:
	_restore()
	var transitions := [0]
	var handler := func(_s: GameManager.State) -> void: transitions[0] += 1
	GameManager.state_changed.connect(handler)

	GameManager.end_run()
	GameManager.end_run()
	GameManager.win_run()

	check(transitions[0] == 1, "the run ends exactly once however many times it is told to")
	check(GameManager.state == GameManager.State.GAME_OVER, "and stays ended the first way")
	check(GameManager.is_run_over(), "which reports as over")
	check(get_tree().paused, "and pauses the tree")

	GameManager.state_changed.disconnect(handler)
	_restore()
	await advance_physics(1)


func _test_victory_is_a_different_ending() -> void:
	_restore()
	GameManager.win_run()
	check(GameManager.state == GameManager.State.VICTORY, "winning enters the victory state")
	check(GameManager.is_run_over(), "which is also a run being over")
	check(not GameManager.is_playing(), "and is not play")
	_restore()
	await advance_physics(1)


## A summary that counted the time spent reading it would report a duration nobody spent
## playing.
func _test_duration_stops_when_the_run_does() -> void:
	_restore()
	RunManager.begin_run(5)
	await advance_physics(6)

	var while_playing := RunManager.stats.duration
	check(while_playing > 0.0, "the clock runs during play")

	GameManager.end_run()
	var at_death := RunManager.stats.duration
	await advance_physics(10)

	check_near(
		RunManager.stats.duration, at_death, "the clock stops when the run ends", 0.02
	)

	_restore()
	await advance_physics(1)


func _test_summary_appears_when_the_run_ends() -> void:
	_restore()
	RunManager.begin_run(7)

	var summary: RunSummary = SUMMARY_SCENE.instantiate()
	add_child(summary)
	await advance_physics(2)

	check(not summary.visible, "the summary is hidden during play")

	GameManager.end_run()
	await advance_physics(2)
	check(summary.visible, "and appears when the run ends")

	var grid := summary.get_node("%Grid")
	check(grid.get_child_count() > 0, "with the statistics filled in")
	# Two labels per row.
	check(grid.get_child_count() % 2 == 0, "as label and value pairs")

	var title := summary.get_node("%Title") as Label
	check(title.text == "SYSTEM FAILURE", "headed by what happened")

	GameManager.win_run()
	await advance_physics(2)
	check(title.text == "SYSTEM FAILURE", "and a run already over cannot be re-ended as a win")

	# Deliberately not exercising restart_run here: it reloads the current scene, which in
	# this process is the test runner itself, and the suite would restart the entire run
	# forever. Restarting is verified by hand instead.
	_restore()
	await advance_physics(2)
	check(not summary.visible, "and hides again once a run is under way")

	summary.queue_free()
	await advance_physics(2)


# --- Fixtures -----------------------------------------------------------------


## Puts the process back into a playable run. Called between state checks and once at the
## end, because a leaked paused tree would silently stop every suite that runs after this
## one — and that failure would look like the *other* suite being broken.
func _restore() -> void:
	GameManager.start_run()

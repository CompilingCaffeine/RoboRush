extends TestCase
## The floor-boundary checkpoint, and the save file that has to survive holding it.
##
## Two halves, and they fail for completely different reasons.
##
## The first is the *run*: a descent writes a checkpoint, a restore puts the run back, and every
## way a run can end takes the checkpoint away. What makes this worth a suite is that the
## interesting failures are all silent — a resume that hands back a run with the boss it already
## beat still unfought, or one that files a second "run started" per interruption, looks exactly
## like a working game until somebody reads their statistics.
##
## The second is the *file*: corruption, a backup, an orphaned temporary, and a save written by a
## build that does not exist yet. None of that can be exercised by playing, all of it is what
## stands between a player and losing an hour-long run, and it needs real files on disk to mean
## anything — so unlike most of `test_save.gd`, this suite writes. Never to the real save: every
## path is redirected to a disposable one first, and a test that clobbered the save file of
## whoever ran it would be a worse bug than any it could find.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Where this suite's files go. A directory of its own so cleaning up is unambiguous, and under
## `user://` because the point is to exercise the real `FileAccess`.
const TEST_DIR := "user://test_checkpoint"

var _campaign: RunDefinition

## Restored in `_teardown`: this suite replaces the live manager's state and every suite after it
## shares the same node.
var _saved_settings: GameSettings
var _saved_best: BestRunStats
var _saved_unlocks: Array[StringName]
var _saved_bosses: Array[StringName]
var _saved_paths: PackedStringArray


func run() -> void:
	_campaign = load(CAMPAIGN_PATH) as RunDefinition
	if not require(_campaign, "the campaign loads"):
		return

	await _test_a_boundary_writes_a_checkpoint()
	await _test_a_mid_floor_save_does_not_pay_the_floor_twice()
	await _test_saving_and_exiting_keeps_the_run_the_menu_just_saved()
	_test_a_boundary_checkpoint_records_no_floor_progress()
	await _test_a_restore_reproduces_the_run()
	await _test_a_restore_does_not_duplicate_credit()
	await _test_every_ending_clears_the_checkpoint()
	await _test_the_title_screen_offers_the_saved_run()
	await _test_the_game_scene_resumes_the_saved_run()
	await _test_the_game_scene_refuses_a_checkpoint_it_cannot_play()
	_test_a_captured_checkpoint_is_valid()
	_test_validation_refuses_a_tampered_checkpoint()
	_test_a_checkpoint_round_trips_through_json()
	await _test_a_checkpoint_survives_a_write_and_a_reload()
	await _test_a_corrupt_save_is_recovered_from_the_backup()
	await _test_an_unrecoverable_save_is_kept_rather_than_deleted()
	await _test_an_orphaned_temporary_is_used_only_as_a_last_resort()
	await _test_an_oversized_file_is_refused()
	await _test_a_future_version_save_is_never_overwritten()

	_teardown()
	await advance_physics(1)


# --- The run --------------------------------------------------------------------


## The end-to-end claim: fight a floor's boss, take the reward, and the run the player would come
## back to is on the floor below with everything they were carrying.
##
## Driven through a real `FloorController` descent rather than by calling `capture` directly,
## because the thing most likely to break is not the capture — it is *when* it happens. A
## checkpoint taken a line earlier would describe the floor being torn down.
## The invariant the pause menu's SAVE GAME rests on, and the one thing that made saving mid-floor
## unfair rather than merely lossy.
##
## A resume rebuilds the floor from its seed and puts the player back at the top of it — that much
## is by design and is what `RunCheckpoint` has always done. What must not come back with the floor
## is its *rewards*. Without the cleared-room list, a player who saved in the last room of a floor
## and reloaded would find every room they had fought through full of enemies again, with the scrap
## and items from clearing them the first time still in the run: the floor pays out twice, and
## again, for as long as they care to repeat it.
##
## So the check is not "the ids round-trip" but the thing a player would actually exploit: on the
## way back in, a room recorded as done is empty, and a room they never reached is not. The second
## half is what stops this passing on a build that simply forgot to spawn anything.
func _test_a_mid_floor_save_does_not_pay_the_floor_twice() -> void:
	SaveManager.clear_checkpoint()
	SceneRouter._resume_requested = false
	var game := await _open_game_scene()
	var floor_node := game.get_node("%Floor") as FloorController
	if not require(floor_node != null and floor_node.layout != null, "a floor to fight through"):
		game.queue_free()
		await advance_physics(1)
		return

	# Two combat rooms that really did get enemies, so "empty afterwards" means something.
	var fought: Array[int] = []
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type != RoomTemplate.Type.COMBAT:
			continue
		var room := floor_node.get_room(plan.id)
		if room != null and room.has_living_enemies():
			fought.append(plan.id)
	if not require(fought.size() >= 2, "the floor has two populated combat rooms (%d)" % fought.size()):
		game.queue_free()
		await advance_physics(1)
		return

	var done_id: int = fought[0]
	var untouched_id: int = fought[1]

	# Stands in for the player having fought through that one room. Reaching into the controller
	# rather than killing ten enemies through the physics server: what is under test is what a save
	# records and a resume rebuilds, and driving a real fight would test the fight.
	floor_node._cleared[done_id] = true
	floor_node.visited[done_id] = true
	floor_node._clears = 3
	RunManager.add_scrap(40)
	var scrap_at_save := RunManager.scrap

	check(floor_node.save_run_now(), "the pause menu's save writes a checkpoint")
	var checkpoint := SaveManager.get_checkpoint()
	if not require(checkpoint, "and there is a checkpoint to resume from"):
		game.queue_free()
		await advance_physics(1)
		return

	check(done_id in checkpoint.floor_cleared_room_ids, "it records the room already cleared")
	check(done_id in checkpoint.floor_visited_room_ids, "and that the player had been in it")
	check(checkpoint.floor_clears == 3, "and the floor's reward cadence (%d)" % checkpoint.floor_clears)
	check(
		checkpoint.floor_id == floor_node.config.id,
		"and it is a checkpoint of the floor being stood on, not the next one",
	)
	check(checkpoint.validate(_campaign).is_empty(), "a mid-floor checkpoint is playable")

	game.queue_free()
	await advance_physics(1)

	SceneRouter._resume_requested = true
	var resumed := await _open_game_scene()
	var resumed_floor := resumed.get_node("%Floor") as FloorController
	if not require(resumed_floor != null and resumed_floor.layout != null, "the run resumes"):
		resumed.queue_free()
		await advance_physics(1)
		return

	check(resumed_floor.is_room_cleared(done_id), "the room already fought through comes back cleared")
	var done_room := resumed_floor.get_room(done_id)
	check(
		done_room != null and not done_room.has_living_enemies(),
		"and comes back empty, so clearing it cannot pay a second time",
	)
	var untouched_room := resumed_floor.get_room(untouched_id)
	check(
		untouched_room != null and untouched_room.has_living_enemies(),
		"while a room the player never reached still has its enemies waiting",
	)
	check(
		resumed_floor._clears == 3,
		"the reward cadence resumes where it was (%d)" % resumed_floor._clears,
	)
	check(RunManager.scrap == scrap_at_save, "and the run comes back with the scrap it saved with")

	resumed.queue_free()
	await advance_physics(1)
	SaveManager.clear_checkpoint()


## SAVE AND EXIT has to survive the walk back to the title screen, and by default it would not.
##
## Everything that leaves a run goes through `GameManager._set_state(MAIN_MENU)`, which ends the
## open run — and ending a run clears its checkpoint and files it into the lifetime bests as an
## abandonment. Both of those are right for ABANDON RUN and catastrophic for the button next to it:
## the checkpoint the player just asked for would be deleted on the way out, by the same press, and
## a player who took five breaks would find five abandoned runs folded into records they cannot
## repair. `RunManager.suspend_run` is what stands between those, and this is the check that says so.
##
## Both halves are exercised against the same transition, one suspended and one not, because the
## claim is not "suspending works" but "suspending is the only difference". The transition is driven
## directly rather than through `SceneRouter`: a test that let the router run would call
## `change_scene_to_file` and replace the test runner, mid-suite, with the title screen.
func _test_saving_and_exiting_keeps_the_run_the_menu_just_saved() -> void:
	SaveManager.clear_checkpoint()
	SceneRouter._resume_requested = false
	var game := await _open_game_scene()
	var floor_node := game.get_node("%Floor") as FloorController
	if not require(floor_node != null and floor_node.layout != null, "a run to put down"):
		game.queue_free()
		await advance_physics(1)
		return

	RunManager.add_scrap(SaveManager.best.most_scrap_collected + 25)
	var banked := RunManager.stats.scrap_collected
	var best_scrap_before := SaveManager.best.most_scrap_collected

	check(floor_node.save_run_now(), "the run is written down before anything leaves")
	if not require(SaveManager.has_checkpoint(), "there is a checkpoint to protect"):
		game.queue_free()
		await advance_physics(1)
		return

	# What SAVE AND EXIT does, minus the scene change. Twice, because the real path arrives here
	# twice — once from the router and once from the title screen's own `_ready` — and a guard that
	# only held for the first would delete the run a frame later.
	RunManager.suspend_run()
	GameManager.enter_main_menu()
	GameManager.enter_main_menu()

	check(SaveManager.has_checkpoint(), "the checkpoint survives the trip to the title screen")
	check(
		SaveManager.best.most_scrap_collected == best_scrap_before,
		"and the run is not filed as finished on the way out (best scrap %d, was %d)"
				% [SaveManager.best.most_scrap_collected, best_scrap_before],
	)

	game.queue_free()
	await advance_physics(1)

	# The other half of the pair: the same transition without the suspend really does end the run,
	# so the guard above is doing the work rather than the run having been unfileable anyway.
	SceneRouter._resume_requested = false
	var abandoned := await _open_game_scene()
	RunManager.add_scrap(banked + 25)
	var expected_scrap := RunManager.stats.scrap_collected
	GameManager.enter_main_menu()

	check(not SaveManager.has_checkpoint(), "abandoning to the title screen still clears the run")
	check(
		SaveManager.best.most_scrap_collected == expected_scrap,
		"and still files it (best scrap %d, expected %d)"
				% [SaveManager.best.most_scrap_collected, expected_scrap],
	)

	abandoned.queue_free()
	await advance_physics(1)
	SaveManager.clear_checkpoint()


## The automatic checkpoint is unchanged by all of the above: a floor nobody has walked into yet
## has nothing to record, so a boundary save carries two empty lists and a zero. Worth pinning
## because the cheapest way to break it would be to have the descent record the floor being left.
func _test_a_boundary_checkpoint_records_no_floor_progress() -> void:
	var checkpoint := _capture_synthetic_checkpoint(9412)
	check(
		checkpoint.floor_cleared_room_ids.is_empty(),
		"a boundary checkpoint names no cleared rooms (%d)"
				% checkpoint.floor_cleared_room_ids.size(),
	)
	check(checkpoint.floor_visited_room_ids.is_empty(), "and no visited ones")
	check(checkpoint.floor_clears == 0, "and no clears on the floor it is arriving at")

	# Through a save file and back, because these are the newest fields in the format and the
	# failure they would have is being written and never read.
	var restored := RunCheckpoint.from_dict(checkpoint.to_dict())
	checkpoint.record_floor_progress([4, 1], [1, 4, 6], 2)
	var with_progress := RunCheckpoint.from_dict(checkpoint.to_dict())
	check(restored.floor_clears == 0, "an empty floor progress survives the round trip")
	var expected_cleared: Array[int] = [1, 4]
	var expected_visited: Array[int] = [1, 4, 6]
	check(
		with_progress.floor_cleared_room_ids == expected_cleared,
		"and a recorded one comes back sorted and intact (%s)"
				% str(with_progress.floor_cleared_room_ids),
	)
	check(with_progress.floor_visited_room_ids == expected_visited, "visited rooms included")
	check(with_progress.floor_clears == 2, "and the clear count with them")


func _test_a_boundary_writes_a_checkpoint() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node := _open_first_floor(arena, 5150)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var player := arena.get_node("Player") as Player
	var health := player.get_health_component()
	var item := _campaign.load_floor(0).get_items()[0]

	# A run with something to lose: scrap, an item, damage taken, and a boss already fought.
	RunManager.add_scrap(46)
	player.get_item_inventory().add(item)
	health.restore(health.max_health - 1.0)
	var integrity := health.current
	var fought := RunManager.fought_boss_ids.duplicate()

	await _descend(floor_node)

	var checkpoint := SaveManager.get_checkpoint()
	if not require(checkpoint, "a boundary writes a checkpoint"):
		arena.queue_free()
		await advance_physics(1)
		return

	check(checkpoint.floor_id == _campaign.floor_id_at(1), "it names the floor descended into")
	check(checkpoint.floor_number == 2, "and that floor's number (%d)" % checkpoint.floor_number)
	check(checkpoint.run_seed == 5150, "it carries the run's seed (%d)" % checkpoint.run_seed)
	check(checkpoint.campaign_id == _campaign.id, "and the campaign it was played against")
	check(checkpoint.content_version == _campaign.content_version, "and that campaign's version")
	check(checkpoint.scrap == RunManager.scrap, "the run's scrap is in it (%d)" % checkpoint.scrap)
	check_near(checkpoint.integrity, integrity, "the robot's integrity is what it descended with")
	var expected_build: Array[StringName] = [item.id]
	check(checkpoint.item_ids == expected_build, "and the build it was carrying")
	check(
		checkpoint.fought_boss_ids.size() == fought.size() + 1,
		"the boss just beaten is recorded as fought",
	)

	# The invariant that makes this a boundary checkpoint rather than a snapshot taken anywhere:
	# the statistics have floor 2 open, so a resume continues that floor rather than entering it a
	# second time.
	var open_floor := checkpoint.stats.current_floor()
	if require(open_floor, "its statistics have a floor open"):
		check(open_floor.floor_id == checkpoint.floor_id, "and it is the floor being resumed onto")

	arena.queue_free()
	await advance_physics(1)


## The other direction: a checkpoint put back is the run it came from, including the seed the
## floor it is standing on will be generated from.
##
## The seed check is the one that matters most and looks the least interesting. A resumed run that
## derived its floor from anything but the run seed plus the floor's stable id would build a
## different floor 2 than the run had descended into — the whole reason
## `RunDefinition.floor_seed_for` exists.
func _test_a_restore_reproduces_the_run() -> void:
	var checkpoint := _capture_synthetic_checkpoint(777)

	# Through the file format rather than the object, because that is the trip a real resume makes
	# and a field that survives one and not the other is the failure this is looking for.
	var restored := RunCheckpoint.from_dict(checkpoint.to_dict())

	RunManager.begin_run(1, _campaign)
	RunManager.restore_run(restored, _campaign)

	check(RunManager.get_run_seed() == 777, "the run seed comes back (%d)" % RunManager.get_run_seed())
	check(RunManager.scrap == checkpoint.scrap, "scrap comes back (%d)" % RunManager.scrap)
	check(RunManager.rooms_cleared == checkpoint.rooms_cleared, "the cleared-room count comes back")
	check(RunManager.floor_number == checkpoint.floor_number, "the floor number comes back")
	check_near(RunManager.enemy_health_scale, checkpoint.enemy_health_scale, "enemy scaling comes back")
	check_near(
		RunManager.max_integrity_penalty, checkpoint.max_integrity_penalty, "the integrity debt comes back"
	)
	check(RunManager.death_saves_spent == checkpoint.death_saves_spent, "spent death saves come back")
	check(RunManager.offered_item_ids == checkpoint.offered_item_ids, "the offered-item history comes back")
	check(RunManager.fought_boss_ids == checkpoint.fought_boss_ids, "the fought-boss history comes back")
	check(RunManager.stats.enemies_defeated == 23, "the run's statistics come back")
	check(
		RunManager.floor_seed == _campaign.floor_seed_for(777, _campaign.index_of(checkpoint.floor_id)),
		"and the floor is the one the run's seed and that floor's id derive",
	)

	# The robot's half of the restore, which is `main.gd`'s to do rather than `RunManager`'s.
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	var floor_config := _campaign.load_floor_by_id(checkpoint.floor_id)
	var items := restored.resolve_items(floor_config)
	check(items.size() == checkpoint.item_ids.size(), "every held item resolves against the floor's pool")
	player.restore_build(items, checkpoint.integrity)

	check(player.get_item_inventory().size() == items.size(), "the build is back on the robot")
	check_near(player.get_health_component().current, checkpoint.integrity, "and its integrity")
	check(
		player.get_health_component().max_health >= checkpoint.integrity,
		"restored integrity fits inside the ceiling the build earned",
	)

	arena.queue_free()
	await advance_physics(1)


## Resuming is continuing, not starting. Everything a run is credited for exactly once has to
## still be credited exactly once on the other side of an interruption.
func _test_a_restore_does_not_duplicate_credit() -> void:
	var checkpoint := _capture_synthetic_checkpoint(4242)
	var collected := checkpoint.stats.items_collected.size()
	var runs_started := SaveManager.best.runs_started

	RunManager.restore_run(checkpoint, _campaign)

	check(
		SaveManager.best.runs_started == runs_started,
		"a resumed run is not counted as another run started (%d, was %d)"
			% [SaveManager.best.runs_started, runs_started],
	)

	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	var floor_config := _campaign.load_floor_by_id(checkpoint.floor_id)
	player.restore_build(checkpoint.resolve_items(floor_config), checkpoint.integrity)
	await advance_physics(1)

	check(
		RunManager.stats.items_collected.size() == collected,
		"restoring the build does not collect its items a second time (%d, was %d)"
			% [RunManager.stats.items_collected.size(), collected],
	)
	check(
		RunManager.offered_item_ids == checkpoint.offered_item_ids,
		"and does not spend anything from the pool again",
	)
	check(
		RunManager.fought_boss_ids == checkpoint.fought_boss_ids,
		"and does not credit a boss twice",
	)

	arena.queue_free()
	await advance_physics(1)


## All four endings. A checkpoint that outlived any of them would offer the player a run they had
## already finished — with the scrap, the build, and the boss credit they finished it with.
func _test_every_ending_clears_the_checkpoint() -> void:
	for ending: Array in [
		[func() -> void: RunManager.end_run(true), "winning"],
		[func() -> void: RunManager.end_run(false), "being destroyed"],
		[func() -> void: RunManager.end_run(false, true), "abandoning the run"],
		[func() -> void: RunManager.begin_run(99, _campaign), "starting a new run"],
	]:
		RunManager.begin_run(1234, _campaign)
		SaveManager.store_checkpoint(_capture_synthetic_checkpoint(1234))
		check(SaveManager.has_checkpoint(), "there is a checkpoint to clear before %s" % ending[1])

		(ending[0] as Callable).call()
		check(not SaveManager.has_checkpoint(), "%s clears the checkpoint" % ending[1])

	await advance_physics(1)


## A saved run the player cannot see is a saved run that does not exist. The entry is built from
## the checkpoint, so this is also the check that a run written by one session is *recognisable* to
## the player in the next one — the label carries the floor and the time for exactly that reason.
func _test_the_title_screen_offers_the_saved_run() -> void:
	# No run open, or building the menu would abandon it and clear the very checkpoint under test.
	# That is the correct behaviour — walking out to the title screen ends a run — and it is why
	# this has to start from a run that has already ended.
	RunManager.end_run(false)
	SaveManager.clear_checkpoint()

	var without := await _open_main_menu()
	if require(without, "the title screen builds"):
		check(
			_menu_entry_starting_with(without, MainMenu.CONTINUE_LABEL) == null,
			"a player with no saved run is not offered one",
		)
		without.queue_free()
		await advance_physics(1)

	# Captured, then the run ended, then stored — in that order. Ending a run clears the checkpoint,
	# which is the whole point of it, so a fixture that stored first would be testing that the
	# clearing works rather than that the menu offers what survives.
	var waiting := _capture_synthetic_checkpoint(2468)
	RunManager.end_run(false)
	SaveManager.store_checkpoint(waiting)

	var with_run := await _open_main_menu()
	if require(with_run, "the title screen builds with a run waiting"):
		var entry := _menu_entry_starting_with(with_run, MainMenu.CONTINUE_LABEL)
		if require(entry, "a saved run is offered on the title screen"):
			check(
				entry.get_index() == MainMenu.CONTINUE_INDEX,
				"as the first entry, above the one that would throw it away",
			)
			check("FLOOR 2" in entry.text, "named by the floor it is on (%s)" % entry.text.strip_edges())
		with_run.queue_free()
		await advance_physics(1)

	SaveManager.clear_checkpoint()


## The composition the player actually gets: the game scene, asked to continue, builds the floor
## the run was left on with the run and the robot it was left with.
##
## Built as a child of this suite rather than through `SceneRouter.resume_run`, which would replace
## the running test scene with it. The router's flag is set directly instead — the same flag the
## router sets — because everything worth checking here happens in `main.gd` after that flag is
## read.
func _test_the_game_scene_resumes_the_saved_run() -> void:
	var checkpoint := _capture_synthetic_checkpoint(13579)
	RunManager.end_run(false)
	SaveManager.store_checkpoint(checkpoint)
	var runs_started := SaveManager.best.runs_started
	var records := checkpoint.stats.floors.size()

	SceneRouter._resume_requested = true
	var game := await _open_game_scene()
	if not require(game, "the game scene builds"):
		return

	var floor_node := game.get_node("%Floor") as FloorController
	var player := game.get_node("%Player") as Player
	check(
		floor_node.config.id == _campaign.floor_id_at(1),
		"a resumed run opens on the floor it was left on (%s)" % floor_node.config.id,
	)
	check(RunManager.floor_number == 2, "and the run says so (floor %d)" % RunManager.floor_number)
	check(RunManager.get_run_seed() == 13579, "with the seed it was played on")
	check(
		RunManager.floor_seed == _campaign.floor_seed_for(13579, 1),
		"and the floor the run's own seed derives, not a fresh one",
	)
	check(RunManager.scrap == checkpoint.scrap, "the scrap is back (%d)" % RunManager.scrap)
	check(
		player.get_item_inventory().size() == checkpoint.item_ids.size(),
		"the build is back on the robot (%d items)" % player.get_item_inventory().size(),
	)
	check_near(player.get_health_component().current, checkpoint.integrity, "and its integrity")
	check(
		SaveManager.best.runs_started == runs_started,
		"and continuing is not counted as starting a run",
	)
	check(SaveManager.has_checkpoint(), "the checkpoint survives being resumed from")

	# Reported by driving the Web build in a browser: the resumed run played floor 2 with `HELP
	# DESK` written along the bottom of the screen. The strip is pushed rather than polled, and
	# nothing pushed it when a floor began — so it kept whatever name it had, which on a resume is
	# the default rather than the floor before.
	var strip := (game.get_node("%CombatHUD") as CombatHUD).get_node("%TopLabel") as Label
	check(
		floor_node.config.display_name.to_upper() in strip.text,
		"the HUD names the floor being resumed onto, not the one it defaults to (%s)" % strip.text,
	)

	# Opening the floor calls `RunManager.begin_floor` for a floor whose record the checkpoint
	# already has open. A second record would mean the run reported seven floors for a six-floor
	# campaign, and every per-floor duration after it would be wrong.
	check(
		RunManager.stats.floors.size() == records,
		"resuming re-enters the floor without opening a second record for it (%d records, was %d)"
			% [RunManager.stats.floors.size(), records],
	)

	# The run being played and the checkpoint it came from have to be separate objects. Sharing one
	# would let the floor being played write itself into the file — and the result would be a
	# checkpoint whose statistics disagree with its own counters, which is a file that no longer
	# loads.
	RunManager.stats.record_room_cleared()
	check(
		SaveManager.get_checkpoint().stats.rooms_cleared == checkpoint.rooms_cleared,
		"and playing on does not edit the saved run underneath it",
	)

	game.queue_free()
	await advance_physics(1)
	RunManager.end_run(false)
	SaveManager.clear_checkpoint()


## A checkpoint the campaign can no longer play — the shape a content update leaves behind. The
## run is discarded and the player is put back on the title screen, rather than being dropped into
## a *new* run they did not ask for.
func _test_the_game_scene_refuses_a_checkpoint_it_cannot_play() -> void:
	print("    (the next Main errors are expected: refusing a checkpoint from another campaign)")
	var stale := _capture_synthetic_checkpoint(2469)
	stale.campaign_id = &"a_campaign_that_no_longer_exists"
	RunManager.end_run(false)
	SaveManager.store_checkpoint(stale)
	var runs_started := SaveManager.best.runs_started

	SceneRouter._resume_requested = true
	var game := await _open_game_scene()
	if not require(game, "the game scene builds"):
		return

	check(not SaveManager.has_checkpoint(), "a checkpoint that cannot be played is discarded")
	check(
		SaveManager.best.runs_started == runs_started,
		"and no run is started in its place (%d, was %d)"
			% [SaveManager.best.runs_started, runs_started],
	)
	check(
		(game.get_node("%Floor") as FloorController).get_session() == null,
		"the refused scene builds no floor at all",
	)

	game.queue_free()
	await advance_physics(1)


func _open_game_scene() -> Node2D:
	var game: Node2D = load("res://main.tscn").instantiate()
	add_child(game)
	# Two frames: the build happens in `_ready`, and the player is placed on the frame after.
	await advance_physics(2)
	return game


func _open_main_menu() -> MainMenu:
	var menu: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await advance_physics(1)
	return menu


## The first entry whose label contains `label`. Contains rather than starts with, because every
## entry is written with either a focus marker or the padding that stands in for one.
func _menu_entry_starting_with(menu: MainMenu, label: String) -> Button:
	for child: Node in (menu.get_node("%Buttons") as Node).get_children():
		var button := child as Button
		if button != null and label in button.text:
			return button
	return null


# --- Validation -----------------------------------------------------------------


func _test_a_captured_checkpoint_is_valid() -> void:
	var problems := _capture_synthetic_checkpoint(31337).validate(_campaign)
	check(
		problems.is_empty(),
		"a checkpoint this build wrote is accepted by this build (%s)" % ", ".join(problems),
	)


## Every refusal, one mutation at a time.
##
## A table rather than a function each, because the interesting property is *coverage*: the
## question is not whether one bad field is caught but whether the categories the plan names —
## collection counts, string lengths, known ids, duplicates, numeric ranges — are all reachable.
## A row that stops failing is a hole, and it shows up as one failed check with its own name.
func _test_validation_refuses_a_tampered_checkpoint() -> void:
	var mutations: Array = [
		["another campaign", func(c: RunCheckpoint) -> void: c.campaign_id = &"not_this_one"],
		["a content version that has moved on",
			func(c: RunCheckpoint) -> void: c.content_version += 1],
		["a floor the campaign does not have",
			func(c: RunCheckpoint) -> void: c.floor_id = &"floor_of_the_moon"],
		["a floor number that is not that floor's",
			func(c: RunCheckpoint) -> void: c.floor_number = 5],
		["a negative seed", func(c: RunCheckpoint) -> void: c.run_seed = -1],
		["a destroyed robot", func(c: RunCheckpoint) -> void: c.integrity = 0.0],
		["impossible integrity",
			func(c: RunCheckpoint) -> void: c.integrity = RunCheckpoint.MAX_INTEGRITY + 1.0],
		["negative scrap", func(c: RunCheckpoint) -> void: c.scrap = -5],
		["more scrap than a run can hold",
			func(c: RunCheckpoint) -> void: c.scrap = RunCheckpoint.MAX_SCRAP + 1],
		["a negative integrity debt",
			func(c: RunCheckpoint) -> void: c.max_integrity_penalty = -1.0],
		["negative death saves", func(c: RunCheckpoint) -> void: c.death_saves_spent = -1],
		["enemy scaling below one", func(c: RunCheckpoint) -> void: c.enemy_health_scale = 0.5],
		["enemy scaling past the run's ceiling",
			func(c: RunCheckpoint) -> void:
				c.enemy_health_scale = RunManager.MAX_ENEMY_HEALTH_SCALE + 0.1],
		["a duration no run has",
			func(c: RunCheckpoint) -> void:
				c.stats.duration = RunCheckpoint.MAX_DURATION_SECONDS * 2.0],
		["an item the game does not have",
			func(c: RunCheckpoint) -> void: c.item_ids.append(&"item_of_pure_gold")],
		["an unknown item marked as spent",
			func(c: RunCheckpoint) -> void: c.offered_item_ids.append(&"item_of_pure_gold")],
		["an empty id", func(c: RunCheckpoint) -> void: c.item_ids.append(&"")],
		["an id longer than any id",
			func(c: RunCheckpoint) -> void:
				c.item_ids.append(StringName("x".repeat(RunCheckpoint.MAX_ID_LENGTH + 1)))],
		["more items than an inventory holds",
			func(c: RunCheckpoint) -> void:
				for index: int in RunCheckpoint.MAX_ITEMS + 1:
					c.item_ids.append(&"padding")],
		["a duplicate in the offered list",
			func(c: RunCheckpoint) -> void:
				c.offered_item_ids.append(c.offered_item_ids[0])],
		["a boss fought twice",
			func(c: RunCheckpoint) -> void: c.fought_boss_ids.append(c.fought_boss_ids[0])],
		["statistics from a different run",
			func(c: RunCheckpoint) -> void: c.stats.run_seed += 1],
		["a room count its statistics disagree with",
			func(c: RunCheckpoint) -> void: c.rooms_cleared += 1],
		["no floor open, so it was not taken at a boundary",
			func(c: RunCheckpoint) -> void:
				c.stats.finish_floor(FloorRecord.Outcome.DESCENDED)],
		["an open floor that is not the one it is on",
			func(c: RunCheckpoint) -> void:
				c.stats.current_floor().floor_id = &"somewhere_else"],
		["more floor records than a campaign has floors",
			func(c: RunCheckpoint) -> void:
				for index: int in RunCheckpoint.MAX_FLOOR_RECORDS + 1:
					c.stats.floors.append(FloorRecord.new())],
	]

	for mutation: Array in mutations:
		var checkpoint := _capture_synthetic_checkpoint(2024)
		(mutation[1] as Callable).call(checkpoint)
		check(
			not checkpoint.validate(_campaign).is_empty(),
			"a checkpoint with %s is refused" % mutation[0],
		)

	# Holding more of an item than it stacks needs a real item id to be about stacking rather than
	# about the id, so it is built rather than mutated.
	var overstacked := _capture_synthetic_checkpoint(2024)
	var unique := _first_unique_item()
	if require(unique, "the item pool has a unique item to over-stack"):
		var doubled: Array[StringName] = [unique.id, unique.id]
		overstacked.item_ids = doubled
		check(
			not overstacked.validate(_campaign).is_empty(),
			"a checkpoint holding two of a one-of-a-kind item is refused",
		)


func _test_a_checkpoint_round_trips_through_json() -> void:
	var written := _capture_synthetic_checkpoint(8675309)
	var text := JSON.stringify(written.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	if not require(parsed is Dictionary, "a checkpoint stringifies to a JSON object"):
		return

	var read := RunCheckpoint.from_dict(parsed as Dictionary)
	check(read.run_seed == written.run_seed, "the seed survives JSON")
	check(read.floor_id == written.floor_id, "the floor id survives JSON as a StringName")
	check(read.item_ids == written.item_ids, "the build survives JSON in order")
	check_near(read.integrity, written.integrity, "integrity survives JSON")
	check(read.stats.floors.size() == written.stats.floors.size(), "the floor records survive JSON")
	check(read.validate(_campaign).is_empty(), "and what comes back is still playable")

	var junk := RunCheckpoint.from_dict({
		"run_seed": "over there", "items": {"not": "a list"}, "stats": 7,
	})
	check(junk.run_seed == 0, "a string where the seed goes reads as no seed, not a crash")
	check(junk.item_ids.is_empty(), "a dictionary where the build goes reads as no build")
	check(not junk.validate(_campaign).is_empty(), "and the result is refused rather than played")


# --- The file -------------------------------------------------------------------


## The whole path, through an actual file: store a checkpoint, write it, read it back with a
## freshly loaded manager, and get the same run.
func _test_a_checkpoint_survives_a_write_and_a_reload() -> void:
	_begin_file_test("round_trip")

	var written := _capture_synthetic_checkpoint(606)
	SaveManager.store_checkpoint(written)
	check(FileAccess.file_exists(SaveManager._save_path), "storing a checkpoint writes the save now")

	SaveManager.load_game()
	var read := SaveManager.get_checkpoint()
	if require(read, "the checkpoint is read back"):
		check(read.run_seed == written.run_seed, "with the run it was written for")
		check(read.item_ids == written.item_ids, "and the build it was carrying")
		check(read.validate(_campaign).is_empty(), "and it is playable")

	SaveManager.clear_checkpoint()
	SaveManager.load_game()
	check(not SaveManager.has_checkpoint(), "clearing it reaches the file too")

	_end_file_test()
	await advance_physics(1)


## A save written whole and then destroyed. The rename makes a *torn* file impossible; nothing
## stops a file being replaced with garbage by something else, and one generation of backup is the
## difference between losing everything and losing the last save.
##
## The run is the exception, and deliberately. A backup is one generation old, so its checkpoint
## may describe a run that has since been finished — resuming that would hand back its scrap and
## its boss credit and file a second result for it. Records only ever move forward and are safe to
## recover; a run is not, so it is dropped.
func _test_a_corrupt_save_is_recovered_from_the_backup() -> void:
	_begin_file_test("recovery")

	SaveManager.best.most_rooms_cleared = 41
	SaveManager.store_checkpoint(_capture_synthetic_checkpoint(909))
	# A second write, so there is a backup: the first save has nothing to back up.
	SaveManager.request_save()
	SaveManager.save_game()
	check(FileAccess.file_exists(SaveManager._backup_path), "a second save leaves a backup behind")

	_write_text(SaveManager._save_path, "{ this is not json")
	SaveManager.load_game()

	check(SaveManager.best.most_rooms_cleared == 41, "a corrupt save falls back to the backup")
	check(
		not SaveManager.has_checkpoint(),
		"but a recovered save does not offer a run that may already be over",
	)
	check(
		FileAccess.file_exists(SaveManager._corrupt_path),
		"the unreadable file is kept rather than deleted",
	)

	var promoted: Variant = JSON.parse_string(_read_text(SaveManager._save_path))
	if require(promoted is Dictionary, "the recovered save is promoted to the primary"):
		check(
			(promoted as Dictionary).get("checkpoint") == null,
			"and the promoted file has no run in it, so the next launch cannot resume one either",
		)

	_end_file_test()
	await advance_physics(1)


## Nothing readable anywhere. Defaults are the only answer, and the bytes that caused it are still
## on disk afterwards — a player who has just lost a save is owed at least that.
func _test_an_unrecoverable_save_is_kept_rather_than_deleted() -> void:
	_begin_file_test("unrecoverable")

	_write_text(SaveManager._save_path, "not a save at all")
	SaveManager.load_game()

	check(not SaveManager.has_checkpoint(), "an unreadable save with no backup offers no run")
	check(SaveManager.best.runs_started == 0, "and starts from defaults")
	check(
		_read_text(SaveManager._corrupt_path) == "not a save at all",
		"the bytes that could not be read are preserved exactly",
	)
	check(not FileAccess.file_exists(SaveManager._save_path), "and are not left where they would be read again")

	_end_file_test()
	await advance_physics(1)


## The temporary file is the state of a write that got as far as the disk and no further. It is
## newer than the backup and less proven, so it is worth adopting only when nothing else survives —
## and worth deleting the moment a readable save exists, or the *next* recovery would restore a run
## older than the one it is recovering from.
func _test_an_orphaned_temporary_is_used_only_as_a_last_resort() -> void:
	_begin_file_test("orphan")

	SaveManager.store_checkpoint(_capture_synthetic_checkpoint(1010))
	_write_text(SaveManager._temp_path, _read_text(SaveManager._save_path))
	SaveManager.load_game()

	check(SaveManager.has_checkpoint(), "a readable save is used")
	check(
		not FileAccess.file_exists(SaveManager._temp_path),
		"and the orphaned temporary beside it is cleared away",
	)

	# Now the other way round: nothing but the orphan. Read back through the records rather than the
	# checkpoint, because a recovery deliberately drops the run — see the backup check above.
	SaveManager.best.most_rooms_cleared = 17
	SaveManager.request_save()
	SaveManager.save_game()
	_write_text(SaveManager._temp_path, _read_text(SaveManager._save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager._save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager._backup_path))
	SaveManager.best = BestRunStats.new()
	SaveManager.load_game()

	check(SaveManager.best.most_rooms_cleared == 17, "with nothing else left, the orphan is adopted")

	_end_file_test()
	await advance_physics(1)


func _test_an_oversized_file_is_refused() -> void:
	_begin_file_test("oversized")
	print("    (the next SaveManager warning is expected: refusing an oversized file)")

	# Valid JSON, and far too big to be a save. Refused on its size before it is parsed, which is
	# the point: a ceiling that only applies to files it has already read is not a ceiling.
	_write_text(
		SaveManager._save_path,
		'{"save_version": 2, "padding": "%s"}' % "x".repeat(SaveManager.MAX_SAVE_BYTES)
	)
	SaveManager.load_game()

	check(SaveManager.best.runs_started == 0, "an oversized file is not read")
	check(FileAccess.file_exists(SaveManager._corrupt_path), "and is kept for whoever has to explain it")

	_end_file_test()
	await advance_physics(1)


## The rollback case. An older build reading a newer save must not write its own idea of that save
## back over it: every field the newer build added would be gone, silently and for good.
func _test_a_future_version_save_is_never_overwritten() -> void:
	_begin_file_test("future")
	print("    (the next SaveManager warning is expected: refusing to write over a newer save)")

	var future := {
		"save_version": SaveManager.SAVE_VERSION + 1,
		"statistics": {"runs_started": 12},
		"something_this_build_has_never_heard_of": [1, 2, 3],
	}
	_write_text(SaveManager._save_path, JSON.stringify(future))
	SaveManager.load_game()

	check(SaveManager.best.runs_started == 12, "what is recognised in a newer save is still read")
	check(not SaveManager.has_checkpoint(), "but a newer build's run is not resumed by an older one")

	SaveManager.best.runs_started = 1
	SaveManager.request_save()
	SaveManager.save_game()

	var on_disk: Variant = JSON.parse_string(_read_text(SaveManager._save_path))
	if require(on_disk is Dictionary, "the newer save is still on disk"):
		var data := on_disk as Dictionary
		check(
			data.get("save_version") == SaveManager.SAVE_VERSION + 1,
			"and is still the newer version",
		)
		check(
			data.has("something_this_build_has_never_heard_of"),
			"with the fields this build does not understand intact",
		)
	check(
		not FileAccess.file_exists(SaveManager._backup_path),
		"and nothing was written anywhere else either",
	)

	_end_file_test()
	await advance_physics(1)


# --- Harness --------------------------------------------------------------------


## A run that has just descended onto the campaign's second floor, without playing one.
##
## Built through the same `RunManager` the game uses and captured through the same `capture`, so
## what this suite validates is what a boundary produces — a hand-built `RunCheckpoint.new()` would
## drift from the real one the first time a field was added.
func _capture_synthetic_checkpoint(seed_value: int) -> RunCheckpoint:
	var floor_config := _campaign.load_floor(1)
	RunManager.begin_run(seed_value, _campaign)
	RunManager.add_scrap(64)
	RunManager.add_enemy_health_growth(0.24)
	# A death save spent from six points down to one, which is a two-point debt rather than a five:
	# `spend_death_save` charges the difference between the ceiling at the time and the floor it was
	# dropped to, and this fixture's robot had already lost some ceiling. Kept deliberately small so
	# the three points of integrity below still fit inside what the build is left with — a fixture
	# whose integrity exceeded its own ceiling would be testing the clamp rather than the restore.
	RunManager.spend_death_save(3.0, 1.0)
	RunManager.stats.enemies_defeated = 23
	RunManager.stats.items_collected.append("Cooling Fan")
	RunManager.fought_boss_ids.append(&"merge_conflict")

	# Floor 1 entered and left, floor 2 entered and still open — the shape a checkpoint is taken in.
	RunManager.begin_floor(1, _campaign.floor_id_at(0), _campaign.floor_seed_for(seed_value, 0), "One")
	RunManager.finish_floor(FloorRecord.Outcome.DESCENDED)
	RunManager.begin_floor(
		2, _campaign.floor_id_at(1), _campaign.floor_seed_for(seed_value, 1), "Two"
	)

	var held: Array[ItemConfig] = []
	var unique := _first_unique_item()
	if unique != null:
		held.append(unique)
		RunManager.offered_item_ids.append(unique.id)

	return RunCheckpoint.capture(_campaign, floor_config, 3.0, held)


## An item no run may hold twice, for the stacking checks. Read out of the floor's own pool rather
## than named, so this keeps working when the pool changes.
func _first_unique_item() -> ItemConfig:
	var pool := _campaign.load_floor(1).get_items()
	for item: ItemConfig in pool:
		if item != null and not item.is_repeatable():
			return item
	return null


## Builds the campaign's first floor with a player on it, exactly as `main.gd` would.
func _open_first_floor(arena: Node2D, seed_value: int) -> FloorController:
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.campaign = _campaign
	floor_node.config = _campaign.load_floor(0)
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)

	GameManager.start_run()
	RunManager.begin_run(seed_value, _campaign)
	if not floor_node.build(player, _campaign.floor_seed_for(seed_value, 0)):
		fail("the campaign's first floor would not build")
		return null
	return floor_node


## Beats this floor's boss and takes the reward, which is the only thing that descends. Drives the
## handlers directly, the way every floor-advance check in `test_floor.gd` does.
func _descend(floor_node: FloorController) -> void:
	var boss_room: Room = null
	for room: Room in floor_node._rooms.values():
		if room.plan.type == RoomTemplate.Type.BOSS:
			boss_room = room
			break
	if boss_room == null:
		fail("floor %d has no boss room to descend from" % floor_node.config.floor_number)
		return

	# Freed rather than left to the collector: `Node` is not reference counted.
	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()
	await advance_physics(1)

	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	# The rebuild is deferred, and so is the physics flush that follows it.
	await advance_physics(4)


## Points the manager at disposable files and turns writing on. Every file check calls this, and
## every one of them calls `_end_file_test` after: the real save belongs to whoever is running the
## suite, and nothing here may touch it.
func _begin_file_test(label: String) -> void:
	if _saved_paths.is_empty():
		_saved_settings = SaveManager.settings
		_saved_best = SaveManager.best
		_saved_unlocks = SaveManager.unlocked_items
		_saved_bosses = SaveManager.bosses_defeated
		_saved_paths = PackedStringArray([
			SaveManager._save_path, SaveManager._temp_path,
			SaveManager._backup_path, SaveManager._corrupt_path,
		])

	if not DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.make_dir_recursive_absolute(TEST_DIR)

	# A fresh name per check, so one file check cannot be passing on another's leftovers.
	SaveManager._save_path = "%s/%s.json" % [TEST_DIR, label]
	SaveManager._temp_path = SaveManager._save_path + ".tmp"
	SaveManager._backup_path = SaveManager._save_path + ".bak"
	SaveManager._corrupt_path = SaveManager._save_path + ".corrupt"
	_remove_test_files()

	SaveManager.best = BestRunStats.new()
	SaveManager.persistence_enabled = true


func _end_file_test() -> void:
	_remove_test_files()
	SaveManager.persistence_enabled = false
	SaveManager._dirty = false
	SaveManager._failed_writes = 0


func _remove_test_files() -> void:
	for path: String in [
		SaveManager._save_path, SaveManager._temp_path,
		SaveManager._backup_path, SaveManager._corrupt_path,
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("could not write the test file %s" % path)
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## Everything this suite replaced on the shared manager, put back. The suites after this one run
## against the same node, and one of them asserts against the lifetime records.
func _teardown() -> void:
	if not _saved_paths.is_empty():
		SaveManager._save_path = _saved_paths[0]
		SaveManager._temp_path = _saved_paths[1]
		SaveManager._backup_path = _saved_paths[2]
		SaveManager._corrupt_path = _saved_paths[3]
		SaveManager.settings = _saved_settings
		SaveManager.best = _saved_best
		SaveManager.unlocked_items = _saved_unlocks
		SaveManager.bosses_defeated = _saved_bosses
		SaveManager.apply_settings()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR))
	SaveManager.persistence_enabled = false
	SaveManager.clear_checkpoint()
	# The suites that follow begin their own runs; this leaves no half-finished one behind.
	RunManager.begin_run(1, _campaign)
	RunManager.end_run(false)

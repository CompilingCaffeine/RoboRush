extends TestCase
## The end of the campaign: what the last boss leaves behind, what taking it does, and what the
## title screen holds afterwards.
##
## The finale used to pay out exactly as the five floors before it did — three rare items on
## stands, choose one — and then win the run half a second later. Every one of those choices was a
## decision about a run that was already over: the player read three names, weighed a build they
## would never fire a shot with, and pressed E to be shown a statistics screen. What replaces it is
## a single object with no effect and no price, and the campaign ends when they walk into it.
##
## Three claims are checked here, and they are the three ways this can quietly stop working:
##
## - **The last floor pays out in a trophy and every other floor does not.** One `is_final_floor`
##   decides both the prize and whether the floor descends or wins, so a floor cannot offer a
##   trophy and then descend into a seventh.
## - **Taking it is the win, and it loses the same races the item stands lose.** A hazard the boss
##   committed before it fell can still kill the player on the walk over, and a run that has ended
##   does not then win — the post-boss contract in `tests/test_post_boss.gd`, on the one floor
##   where losing it costs the whole campaign.
## - **The trophy outlives the session.** It is written to the save, the title screen reads it back,
##   and a run saved in the seconds between the killing blow and the pickup comes back to a trophy
##   still standing rather than to an unwinnable arena.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/combat_hud.tscn")
const VICTORY_CARD_SCENE := preload("res://scenes/ui/victory_card.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

## Long enough for `Trophy.ARM_DELAY` to have passed at sixty frames a second, with room to spare.
const FRAMES_TO_ARM := 40

## How long a check will wait for a physics flush to deliver an overlap. Overlaps are reported on
## the server's own schedule, and a fixed wait makes the first one in a run behave unlike the rest —
## the lesson `tests/test_post_boss.gd` records at length.
const OVERLAP_FRAMES := 120

var _campaign: RunDefinition
var _arena: Node2D
var _floor: FloorController
var _player: Player


func run() -> void:
	_campaign = load(CAMPAIGN_PATH) as RunDefinition
	if not require(_campaign, "the campaign loads"):
		return

	await _test_the_last_floor_stands_a_trophy_and_no_stands()
	await _test_every_other_floor_still_offers_the_choice()
	await _test_walking_into_it_wins_the_campaign()
	await _test_it_cannot_be_taken_in_the_frame_it_appears()
	await _test_a_death_in_the_window_still_beats_it()
	await _test_a_run_saved_over_the_trophy_comes_back_to_it()
	await _test_the_hud_names_the_prize_that_is_actually_there()
	await _test_the_win_is_announced_before_the_statistics()
	await _test_the_title_screen_keeps_the_trophy()
	await _test_the_trophy_survives_a_restart()


# --- What the last boss leaves ------------------------------------------------


## The headline change. The sixth boss falls and there is one thing in the arena, it is a trophy,
## and no item has been struck off the run to put it there.
##
## The pool check is the half that is easy to lose: the three stands *spend* what they offer
## (`FloorController._take_reward`), and a finale that drew a choice and then threw it away to put a
## trophy up instead would look identical on screen while quietly consuming the last three uniques
## in the run.
func _test_the_last_floor_stands_a_trophy_and_no_stands() -> void:
	if not await _open_floor(_campaign.size() - 1, 24680):
		return

	var arena := _boss_room()
	if not require(arena, "the last floor has a boss arena"):
		await _close()
		return

	check(_floor.is_final_floor(), "and the campaign says it is the last floor")
	var spent_before := RunManager.offered_item_ids.size()

	_defeat_the_boss()
	await advance_physics(2)

	check(_trophies_in(arena).size() == 1, "the finale leaves exactly one trophy in the arena")
	check(_stands_in(arena).is_empty(), "and no stands to choose between")
	check(
		RunManager.offered_item_ids.size() == spent_before,
		"and takes nothing out of the run's item pool to do it (%d ids, was %d)"
			% [RunManager.offered_item_ids.size(), spent_before],
	)
	check(GameManager.state == GameManager.State.RUN, "winning still waits on the pickup")

	await _close()


## The other side of the same rule, and the one that would go unnoticed: a mistake in
## `is_final_floor` that answered true everywhere would replace every boss reward in the game with a
## trophy, and the first five floors would end the run.
func _test_every_other_floor_still_offers_the_choice() -> void:
	for index: int in _campaign.size() - 1:
		if not await _open_floor(index, 13579 + index):
			return

		var arena := _boss_room()
		if not require(arena, "floor %d has a boss arena" % (index + 1)):
			await _close()
			return

		check(not _floor.is_final_floor(), "floor %d is not the campaign's last" % (index + 1))
		_defeat_the_boss()
		await advance_physics(2)

		check(
			_stands_in(arena).size() == FloorController.BOSS_REWARD_COUNT,
			"floor %d still offers its choice of three" % (index + 1),
		)
		check(_trophies_in(arena).is_empty(), "and no trophy" )

		await _close()


# --- Taking it ----------------------------------------------------------------


## The pickup itself, driven by walking a real robot into it rather than by calling the handler.
## Everything else in this suite could pass with the trophy on a collision layer nothing touches.
func _test_walking_into_it_wins_the_campaign() -> void:
	var was_claimed := SaveManager.trophy_claimed
	SaveManager.trophy_claimed = false

	if not await _open_floor(_campaign.size() - 1, 112358):
		SaveManager.trophy_claimed = was_claimed
		return

	var arena := _boss_room()
	if not require(arena, "the last floor has a boss arena"):
		await _close()
		SaveManager.trophy_claimed = was_claimed
		return

	var announcements := [0]
	var counter := func(_at: Vector2) -> void: announcements[0] += 1
	EventBus.trophy_claimed.connect(counter)

	# Standing well clear of the reward point, so the walk is a walk.
	_player.global_position = arena.get_interior_rect().get_center()
	_defeat_the_boss()
	await advance_physics(FRAMES_TO_ARM)

	var trophies := _trophies_in(arena)
	if not require(trophies.size() == 1, "there is a trophy to walk into"):
		EventBus.trophy_claimed.disconnect(counter)
		await _close()
		SaveManager.trophy_claimed = was_claimed
		return

	check(GameManager.state == GameManager.State.RUN, "the run is still going before the pickup")
	_player.global_position = trophies[0].global_position
	await _wait_for_victory()

	check(GameManager.state == GameManager.State.VICTORY, "walking into the trophy wins the run")
	check(announcements[0] == 1, "and announces itself exactly once (%d)" % announcements[0])
	check(SaveManager.trophy_claimed, "and the save is told, without the trophy knowing it exists")

	EventBus.trophy_claimed.disconnect(counter)
	await _close()
	SaveManager.trophy_claimed = was_claimed


## The arming window. A player mid-dash through the boss's last position when it falls has not
## chosen to end the campaign, and a run that ends inside the same tenth of a second as the fight
## reads as the game deciding for them.
func _test_it_cannot_be_taken_in_the_frame_it_appears() -> void:
	if not await _open_floor(_campaign.size() - 1, 314159):
		return

	var arena := _boss_room()
	if not require(arena, "the last floor has a boss arena"):
		await _close()
		return

	# Standing exactly where the trophy is about to appear.
	_player.global_position = arena.get_reward_position()
	_defeat_the_boss()
	await advance_physics(4)

	check(
		GameManager.state == GameManager.State.RUN,
		"a trophy that appears under the player is not collected on arrival",
	)
	check(_trophies_in(arena).size() == 1, "and it is still standing there")

	# The same overlap, once the delay has passed: the guard is a delay rather than a refusal.
	await _wait_for_victory()
	check(GameManager.state == GameManager.State.VICTORY, "and it is collectable a moment later")

	await _close()


## The post-boss danger contract, on the floor where it costs the most. A hazard committed before
## the last boss fell can kill the player while the trophy stands unclaimed, and the loss wins:
## the campaign is not won by a robot that is already scrap.
func _test_a_death_in_the_window_still_beats_it() -> void:
	if not await _open_floor(_campaign.size() - 1, 271828):
		return

	var arena := _boss_room()
	if not require(arena, "the last floor has a boss arena"):
		await _close()
		return

	_defeat_the_boss()
	await advance_physics(2)
	var trophies := _trophies_in(arena)
	if not require(trophies.size() == 1, "the trophy is standing unclaimed"):
		await _close()
		return

	# The committed hazard, resolved: the run is over before the trophy is reached.
	GameManager.end_run()
	trophies[0].claim()
	await advance_physics(4)

	check(
		GameManager.state == GameManager.State.GAME_OVER,
		"a run lost with the trophy unclaimed stays lost",
	)

	await _close()


# --- Coming back to it --------------------------------------------------------


## The failure `floor_boss_reward_ids` exists to prevent, in the one form no list of item ids can
## fix: a run saved between the last killing blow and the pickup. The arena is marked cleared the
## moment the boss falls, so a resumed floor builds it empty — and on the last floor that is a
## campaign with no way left to finish it.
##
## Nothing about the trophy is written to the checkpoint, deliberately. A cleared arena on the final
## floor can only mean one is standing in it, because the only thing that takes it also ends the run
## and clears the checkpoint.
func _test_a_run_saved_over_the_trophy_comes_back_to_it() -> void:
	var index := _campaign.size() - 1
	if not await _open_floor(index, 161803):
		return

	var arena := _boss_room()
	if not require(arena, "the last floor has a boss arena"):
		await _close()
		return

	_defeat_the_boss()
	await advance_physics(2)
	check(_floor.save_run_now(), "the run saves with the trophy still standing")

	var checkpoint := SaveManager.get_checkpoint()
	if not require(checkpoint, "and there is a checkpoint to come back to"):
		await _close()
		return
	check(
		checkpoint.floor_boss_reward_ids.is_empty(),
		"the checkpoint carries no offer, because a trophy is not a choice",
	)

	# The run put down and picked up again, as `main.gd` does it.
	_floor.queue_free()
	await advance_physics(2)
	RunManager.restore_run(checkpoint, _campaign)
	_floor = FLOOR_SCENE.instantiate()
	_floor.campaign = _campaign
	_floor.config = _campaign.load_floor(index)
	_arena.add_child(_floor)
	_floor.resume_floor_progress(
		checkpoint.floor_cleared_room_ids,
		checkpoint.floor_visited_room_ids,
		checkpoint.floor_clears,
		checkpoint.floor_shop,
		checkpoint.floor_boss_reward_ids,
	)
	check(_floor.build(_player, RunManager.floor_seed), "the saved finale resumes")
	await advance_physics(2)

	var resumed := _boss_room()
	if not require(resumed, "the resumed floor has its boss arena"):
		await _close()
		return
	check(
		_trophies_in(resumed).size() == 1,
		"and the trophy is standing where the run left it",
	)

	await _close()


# --- What the player is told --------------------------------------------------


## The banner over a dead boss sends the player at whatever is actually in the room. Five floors of
## "choose one reward" is exactly the training that walks a player into the last arena looking for
## three stands.
func _test_the_hud_names_the_prize_that_is_actually_there() -> void:
	var hud: CombatHUD = HUD_SCENE.instantiate()
	add_child(hud)
	await advance_physics(1)
	var banner := hud.get_node("%Banner") as Label

	hud.bind_boss("CORE INTELLIGENCE", "THE CORE IS DOWN", [], true)
	EventBus.boss_defeated.emit(null)
	check(
		CombatHUD.CLAIM_TROPHY_PROMPT in banner.text,
		"the last boss sends the player at the trophy ('%s')" % banner.text,
	)

	hud.bind_boss("THE SCRAP KING", "THE KING IS DEAD", [], false)
	EventBus.boss_defeated.emit(null)
	check(
		CombatHUD.CHOOSE_REWARD_PROMPT in banner.text,
		"and every other boss at its choice of three ('%s')" % banner.text,
	)

	hud.queue_free()
	await advance_physics(1)


## The celebration. Sixty rooms and six bosses used to end on the same grey statistics panel a
## death produces, with two different words at the top of it.
func _test_the_win_is_announced_before_the_statistics() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var card: VictoryCard = VICTORY_CARD_SCENE.instantiate()
	layer.add_child(card)
	await advance_physics(1)

	GameManager.start_run()
	await advance_physics(1)
	check(not card.visible, "the card is not up during a run")

	var dismissals := [0]
	var counter := func() -> void: dismissals[0] += 1
	card.closed.connect(counter)

	GameManager.win_run()
	await advance_physics(2)
	check(card.visible, "winning the run puts it up")
	check((card.get_node("%Title") as Label).text == VictoryCard.TITLE, "saying YOU WIN!")
	check(
		(card.get_node("%Trophy") as TextureRect).texture != null,
		"with the trophy the player just picked up on it",
	)

	card.close()
	await advance_physics(1)
	check(not card.visible, "pressing something takes it down")
	check(dismissals[0] == 1, "and hands the screen underneath back exactly once")

	# A loss is not a celebration, and never was: the game over screen is its own thing.
	GameManager.start_run()
	GameManager.end_run()
	await advance_physics(2)
	check(not card.visible, "losing does not put it up")

	card.closed.disconnect(counter)
	GameManager.start_run()
	RunManager.end_run(false)
	layer.queue_free()
	await advance_physics(2)


## What "keep the trophy on the home screen" means: not this session, and not this run.
func _test_the_title_screen_keeps_the_trophy() -> void:
	var was_claimed := SaveManager.trophy_claimed

	SaveManager.trophy_claimed = false
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate()
	add_child(menu)
	await advance_physics(1)
	check(
		not (menu.get_node("%Trophy") as TextureRect).visible,
		"a player who has not finished the campaign is not shown a trophy",
	)
	menu.queue_free()
	await advance_physics(1)

	SaveManager.trophy_claimed = true
	menu = MAIN_MENU_SCENE.instantiate()
	add_child(menu)
	await advance_physics(1)
	check(
		(menu.get_node("%Trophy") as TextureRect).visible,
		"a player who has is shown it on the title screen",
	)
	check(
		(menu.get_node("%TrophyLabel") as Label).visible,
		"with a line saying what it is for",
	)
	menu.queue_free()
	await advance_physics(1)

	SaveManager.trophy_claimed = was_claimed
	# The menu leaves the game in its own state and the suites after this one expect a run.
	GameManager.start_run()
	await advance_physics(1)


## The whole of "from thereafter": the flag has to survive the process, not just the session. A
## disposable file, because the real save belongs to whoever is running the suite.
func _test_the_trophy_survives_a_restart() -> void:
	var real_save: String = SaveManager._save_path
	var real_temp: String = SaveManager._temp_path
	var real_backup: String = SaveManager._backup_path
	var was_enabled: bool = SaveManager.persistence_enabled
	var was_claimed: bool = SaveManager.trophy_claimed

	SaveManager._save_path = "user://test_only_trophy_save.json"
	SaveManager._temp_path = "user://test_only_trophy_save.json.tmp"
	SaveManager._backup_path = "user://test_only_trophy_save.json.bak"
	SaveManager.persistence_enabled = true

	SaveManager.trophy_claimed = false
	SaveManager.record_trophy_claimed()
	SaveManager.save_game()
	check(SaveManager.trophy_claimed, "picking up the trophy records it")

	# The relaunch: the field back to what a fresh process holds, then a load.
	SaveManager.trophy_claimed = false
	SaveManager.load_game()
	check(SaveManager.trophy_claimed, "and it comes back from the file on the next launch")

	# A save written before the trophy existed says nothing about one, and must read as "not won"
	# rather than as corrupt or as won.
	var older := FileAccess.open(SaveManager._save_path, FileAccess.WRITE)
	older.store_string(JSON.stringify({"save_version": 2, "tutorial_completed": true}))
	older.close()
	SaveManager.trophy_claimed = true
	SaveManager.load_game()
	check(
		not SaveManager.trophy_claimed,
		"a save from before the trophy existed reads as a campaign not yet finished",
	)

	for path: String in [SaveManager._save_path, SaveManager._temp_path, SaveManager._backup_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveManager._save_path = real_save
	SaveManager._temp_path = real_temp
	SaveManager._backup_path = real_backup
	SaveManager.persistence_enabled = was_enabled
	SaveManager.trophy_claimed = was_claimed
	SaveManager._dirty = false
	await advance_physics(1)


# --- Fixtures -----------------------------------------------------------------


## Opens the campaign's floor at `index` with a player standing on it, the way `main.gd` does.
func _open_floor(index: int, seed_value: int) -> bool:
	_arena = Node2D.new()
	add_child(_arena)
	_floor = FLOOR_SCENE.instantiate()
	_floor.campaign = _campaign
	_floor.config = _campaign.load_floor(index)
	_arena.add_child(_floor)
	_player = PLAYER_SCENE.instantiate()
	_arena.add_child(_player)

	GameManager.start_run()
	RunManager.begin_run(seed_value, _campaign)
	if not _floor.build(_player, _campaign.floor_seed_for(seed_value, index)):
		fail("floor %d would not build" % (index + 1))
		await _close()
		return false
	await advance_physics(1)
	return true


## Tears the floor down and leaves the game in a state the next check can open a run in. Winning
## pauses the tree, so a suite that left it paused would break every suite after it.
func _close() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_floor = null
	_player = null
	GameManager.start_run()
	RunManager.end_run(false)
	await advance_physics(2)


## Kills the boss the way the floor hears about it, with a stand-in for the body — freed rather
## than dropped, because `Node` is not reference counted.
func _defeat_the_boss() -> void:
	var stand_in := Node.new()
	_floor._on_boss_defeated(stand_in, _boss_room())
	stand_in.free()


func _boss_room() -> Room:
	for room: Room in _floor._rooms.values():
		if room.plan.type == RoomTemplate.Type.BOSS:
			return room
	return null


func _trophies_in(room: Room) -> Array[Trophy]:
	var found: Array[Trophy] = []
	for child: Node in room.get_children():
		var trophy := child as Trophy
		if trophy != null and not trophy.is_queued_for_deletion():
			found.append(trophy)
	return found


func _stands_in(room: Room) -> Array[ShopStand]:
	var found: Array[ShopStand] = []
	for child: Node in room.get_children():
		var shop := child as ShopRoom
		if shop == null:
			continue
		found.append_array(shop.get_stands())
	return found


## Waits for the overlap that ends the run, rather than for a fixed number of frames. See
## `OVERLAP_FRAMES`.
func _wait_for_victory() -> void:
	var waited := 0
	while GameManager.state != GameManager.State.VICTORY and waited < OVERLAP_FRAMES:
		await advance_physics(1)
		waited += 1

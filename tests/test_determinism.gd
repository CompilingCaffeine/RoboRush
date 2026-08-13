extends TestCase
## Checks that one seed reproduces a run, and keeps reproducing it when unrelated code changes.
##
## "The same seed produces the same floor" was already true and already tested (`test_floor`), and
## it was a much weaker promise than it read as. Two things broke it quietly.
##
## A floor's seed was `hash()` of the floor before it, so floor 4's layout was a function of floors
## 1 through 3 as well as of the run seed. Renaming a floor, reordering the campaign, or editing
## floor 2 moved every floor after it, and a seed from a bug report stopped reproducing the floor it
## was filed about without anything saying so.
##
## And `FloorController` drew its boss, populated its rooms, seeded its shop and shuffled its boss
## reward from *one* generator, which made those four subsystems one stream separated only by how
## many numbers had already been taken. One extra draw anywhere reshuffled everything after it, so
## the promise held only until the next commit touched an unrelated system — which is the same as
## not holding.
##
## Both are structural, so the checks here are structural too: seeds are derived by name, streams are
## separate generators, and the suite asserts the derivation rather than a golden layout. A test
## pinning specific room cells would fail on every legitimate content edit and teach everybody to
## update the expectation without reading it.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## How many numbers to take out of one stream before asking another whether it noticed. Large enough
## that a shared generator could not possibly land back on the same value by luck.
const DRAIN_DRAWS := 25


func run() -> void:
	_test_a_floor_seed_is_the_run_seed_and_the_floors_own_id()
	_test_reordering_the_campaign_moves_no_floors_seed()
	_test_a_content_bump_changes_what_a_seed_means()
	_test_streams_are_distinct_and_independent()
	await _test_one_seed_rebuilds_the_same_floor()
	await _test_every_subsystem_draws_from_its_own_named_stream()
	await _test_a_change_to_one_subsystems_content_leaves_the_others_alone()
	await _test_a_run_records_its_seed_and_every_floor_it_entered()
	await _test_a_run_that_ends_records_how_the_floor_ended()
	_test_the_manifest_names_every_floor_and_the_content_it_will_build()
	await _test_the_debug_overlay_reports_what_reproduces_the_run()


# --- Seed derivation ---------------------------------------------------------------------


## The rule, stated once: a floor's seed is the run's seed, the campaign's content version, and the
## floor's stable id. Nothing about the floors before it, and nothing about where it sits.
func _test_a_floor_seed_is_the_run_seed_and_the_floors_own_id() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var seeds: Dictionary[int, int] = {}
	for index: int in campaign.size():
		var derived := campaign.floor_seed_for(4242, index)
		check(
			derived == RunRng.floor_seed(4242, campaign.content_version, campaign.floor_id_at(index)),
			"floor %d derives from the run seed, the version, and its id" % (index + 1),
		)
		check(
			derived == campaign.floor_seed_for(4242, index),
			"and derives to the same number every time it is asked",
		)
		check(not seeds.has(derived), "and to a number no other floor got (%d)" % derived)
		seeds[derived] = index

	check(
		campaign.floor_seed_for(4242, 0) != campaign.floor_seed_for(4243, 0),
		"a different run seed builds a different first floor",
	)

	# The chain's actual defect, as a check: floor 2 must not care what floor 1 is called.
	var renamed := _campaign_of([&"renamed_first", campaign.floor_id_at(1)], campaign.content_version)
	check(
		renamed.floor_seed_for(4242, 0) != campaign.floor_seed_for(4242, 0),
		"renaming a floor changes that floor's seed",
	)
	check(
		renamed.floor_seed_for(4242, 1) == campaign.floor_seed_for(4242, 1),
		"and leaves the floor after it exactly where it was",
	)


## Floor order is not floor identity. Inserting a floor, or swapping two, has to leave every other
## floor's seed alone — otherwise adding Data Center between two existing floors would silently
## relay everything after it, and every recorded seed would be describing a different run.
func _test_reordering_the_campaign_moves_no_floors_seed() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	check(campaign.size() >= 2, "the campaign has two floors to reorder")
	if campaign.size() < 2:
		return

	var first := campaign.floor_id_at(0)
	var second := campaign.floor_id_at(1)
	var swapped := _campaign_of([second, first], campaign.content_version)
	var inserted := _campaign_of([first, &"data_center", second], campaign.content_version)

	for floor_id: StringName in [first, second]:
		var original := RunRng.floor_seed(99, campaign.content_version, floor_id)
		check(
			swapped.floor_seed_for(99, swapped.index_of(floor_id)) == original,
			"'%s' keeps its seed when the campaign is reordered" % floor_id,
		)
		check(
			inserted.floor_seed_for(99, inserted.index_of(floor_id)) == original,
			"and when a floor is inserted between them",
		)


## A seed is only meaningful against the content it was drawn on, so a content bump has to change
## what seeds mean rather than leaving old ones pointing at floors that have moved underneath them.
func _test_a_content_bump_changes_what_a_seed_means() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var bumped := _campaign_of([campaign.floor_id_at(0)], campaign.content_version + 1)
	check(
		bumped.floor_seed_for(4242, 0)
			!= RunRng.floor_seed(4242, campaign.content_version, campaign.floor_id_at(0)),
		"the same seed against a newer content version derives a different floor",
	)


# --- Named streams -----------------------------------------------------------------------


## Every stream of a floor is its own generator, and the whole point is that they cannot reach each
## other: one subsystem taking more numbers than it used to must not move another's results.
func _test_streams_are_distinct_and_independent() -> void:
	var floor_seed := RunRng.floor_seed(4242, 1, &"help_desk")

	var seen: Dictionary[int, StringName] = {}
	for stream: StringName in RunRng.STREAMS:
		var stream_seed := RunRng.stream_seed(floor_seed, stream)
		check(
			stream_seed == RunRng.stream_seed(floor_seed, stream),
			"the '%s' stream seeds the same way twice" % stream,
		)
		check(
			not seen.has(stream_seed),
			"and differently from '%s'" % seen.get(stream_seed, &"every other stream"),
		)
		check(
			stream_seed != RunRng.stream_seed(RunRng.floor_seed(4242, 1, &"development"), stream),
			"and differently on another floor",
		)
		seen[stream_seed] = stream

	check(
		RunRng.stream_seeds(floor_seed).size() == RunRng.STREAMS.size(),
		"every stream is reported in the seed table",
	)

	# The regression itself, in three lines: drain one stream and ask another for its next number.
	# Against a single shared generator this is exactly what silently changed the shop's stock when
	# the boss draw grew.
	var drained := RunRng.stream(floor_seed, RunRng.BOSS)
	var shop := RunRng.stream(floor_seed, RunRng.SHOP)
	for _draw: int in DRAIN_DRAWS:
		drained.randi()
	check(
		shop.randi() == RunRng.stream(floor_seed, RunRng.SHOP).randi(),
		"and draining one stream leaves another's next number untouched",
	)


## The floor's four generators, checked against the derivation rather than against each other's
## output. `RandomNumberGenerator.seed` still reports the value it was set to after any number of
## draws, so this reads what the controller actually seeded them with.
func _test_every_subsystem_draws_from_its_own_named_stream() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_floor(arena, campaign, 5150)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var floor_seed := campaign.floor_seed_for(5150, 0)
	check(RunManager.floor_seed == floor_seed, "the floor was opened on its derived seed")

	for pair: Array in [
		[floor_node._boss_rng, RunRng.BOSS],
		[floor_node._encounter_rng, RunRng.ENCOUNTER],
		[floor_node._shop_rng, RunRng.SHOP],
		[floor_node._reward_rng, RunRng.REWARD],
		[floor_node.get_session().loot._rng, RunRng.LOOT],
	]:
		var rng: RandomNumberGenerator = pair[0]
		var stream: StringName = pair[1]
		check(
			rng.seed == RunRng.stream_seed(floor_seed, stream),
			"the '%s' subsystem is seeded from the '%s' stream" % [stream, stream],
		)

	# The layout is the one stream nobody holds a generator for: generation happens before a session
	# exists, because it is the only step of a descent that may fail. Its seed is checked through the
	# layout it produced instead.
	check(
		floor_node.layout.seed_value == RunRng.stream_seed(floor_seed, RunRng.LAYOUT),
		"and the layout was generated from the 'layout' stream",
	)

	arena.queue_free()
	await advance_physics(1)


# --- Reproduction ------------------------------------------------------------------------


## The promise, end to end: the same run seed builds the same floor — the same rooms, the same
## enemies in them, the same shop stock, the same boss, and the same three items it offers.
func _test_one_seed_rebuilds_the_same_floor() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var first := await _describe_floor(campaign, 8675309)
	var second := await _describe_floor(campaign, 8675309)
	var other := await _describe_floor(campaign, 8675310)
	if first.is_empty() or second.is_empty() or other.is_empty():
		fail("three floors must build to compare them")
		return

	# Each part is checked for having something in it before the parts are compared. An empty
	# signature compares equal to another empty signature, so a helper that quietly found no shop
	# would report "the same seed reproduces the floor's shop" while testing nothing at all.
	for pair: Array in [
		["layout", "rooms"], ["enemies", "enemies in them"], ["shop", "a stocked shop"],
		["boss", "a boss"], ["reward", "items on the reward stands"],
	]:
		var described: String = first[pair[0]]
		check(
			not described.is_empty() and described != "no shop" and described != "none",
			"the floor was built with %s ('%s')" % [pair[1], described.left(40)],
		)

	for key: String in first:
		check(first[key] == second[key], "the same seed reproduces the floor's %s" % key)

	# And that the comparison could have failed. A signature that never varies would pass the block
	# above with the seed ignored entirely, which is the way this kind of test dies quietly.
	var differences := 0
	for key: String in first:
		if first[key] != other[key]:
			differences += 1
	check(differences > 0, "a different seed builds a different floor (%d parts differ)" % differences)


## The practical form of "one subsystem's changes stay in that subsystem": add a boss to a floor's
## pool, and its layout, its encounters and its shop must come out identical. Which boss is drawn may
## legitimately change — that is the subsystem being edited.
func _test_a_change_to_one_subsystems_content_leaves_the_others_alone() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	var config := campaign.load_floor(0)
	if not require(config, "floor 1 loads"):
		return
	check(not config.boss_pool.is_empty(), "floor 1 has a boss to copy")
	if config.boss_pool.is_empty():
		return

	# Shallow duplicate with `boss_pool` *reassigned*, never edited in place: the array is shared
	# with the resource every other suite loads, and appending to it here would give the Help Desk a
	# third boss for the rest of the run.
	var extended := config.duplicate() as FloorConfig
	var pool: Array[BossEncounter] = config.boss_pool.duplicate()
	var extra := config.boss_pool[0].duplicate() as BossEncounter
	extra.id = &"determinism_extra_boss"
	pool.append(extra)
	extended.boss_pool = pool

	var before := await _describe_floor(campaign, 31415)
	var after := await _describe_floor(campaign, 31415, extended)
	if before.is_empty() or after.is_empty():
		fail("both floors must build to compare them")
		return

	# That the perturbation was real, before asserting what it did not touch: the floor's content
	# fingerprint has to move, or this is two identical floors agreeing about nothing.
	check(
		before["content"] != after["content"],
		"a third boss in the pool changes the floor's content fingerprint",
	)
	for key: String in ["layout", "enemies", "shop"]:
		check(
			before[key] == after[key],
			"and leaves the floor's %s alone" % key,
		)


# --- What the run records ----------------------------------------------------------------


## A run has to be able to say what it was: its seed, the campaign and version it was played
## against, how deep it got, and what each floor cost. None of that was recorded, so a report of
## "floor 2 took forever and then killed me" had a total duration and nothing else.
func _test_a_run_records_its_seed_and_every_floor_it_entered() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_floor(arena, campaign, 246810)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var stats := RunManager.stats
	check(stats.run_seed == 246810, "the run records the seed it opened on")
	check(stats.campaign_id == campaign.id, "and which campaign it was playing")
	check(stats.content_version == campaign.content_version, "and that campaign's content version")
	check(RunManager.get_run_seed() == 246810, "and the run seed is readable while it runs")

	if require(stats.current_floor(), "the floor it is standing on has an open record"):
		check(stats.current_floor().floor_id == campaign.floor_id_at(0), "named by the campaign's id")
		check(
			stats.current_floor().seed_value == campaign.floor_seed_for(246810, 0),
			"and carrying the seed it was generated from",
		)
		check(
			not stats.current_floor().boss_id.is_empty(),
			"and the boss that was drawn for it",
		)

	# Cleared on floor 1 and nowhere else, so the per-floor counts below are a division of the run's
	# total rather than a copy of it. Emitted rather than fought: what is being checked is the
	# bookkeeping, and `RunManager` counts this signal.
	for _clear: int in 2:
		EventBus.room_cleared.emit()
	await advance_physics(2)

	# Every floor the campaign has, so this keeps meaning what it says at six.
	for index: int in campaign.size():
		if campaign.is_terminal(index):
			break
		await _descend(floor_node)
		check(
			RunManager.get_run_seed() == 246810,
			"the run seed survives the boundary into floor %d" % (index + 2),
		)
		check(
			RunManager.floor_seed == campaign.floor_seed_for(246810, index + 1),
			"and floor %d is generated from its own derived seed" % (index + 2),
		)
		check(
			stats.floors[index].outcome == FloorRecord.Outcome.DESCENDED,
			"floor %d is recorded as descended from" % (index + 1),
		)
		check(
			stats.deepest_floor == index + 2,
			"and the run's deepest floor is %d (is %d)" % [index + 2, stats.deepest_floor],
		)

	check(
		stats.floors.size() == campaign.size(),
		"a run through the campaign records %d floors (recorded %d)" % [
			campaign.size(), stats.floors.size(),
		],
	)
	check(
		stats.describe_floors().count("\n") == campaign.size() - 1,
		"and describes one line per floor:\n%s" % stats.describe_floors(),
	)

	# The last floor's reward wins the run, which closes the last record.
	await _claim_reward(floor_node)
	check(GameManager.state == GameManager.State.VICTORY, "the campaign's last floor wins the run")
	var last := stats.floors[stats.floors.size() - 1]
	check(last.outcome == FloorRecord.Outcome.WON, "and its record says the run was won there")
	check(stats.current_floor() == null, "with no floor left open")

	# Each floor's duration and room count is a *delta* against the run's totals, so a finished run's
	# floors divide those totals rather than each reporting the whole run. Getting that wrong is the
	# obvious way to implement this and reads as plausible right up to the summary screen.
	var floor_time := 0.0
	var floor_rooms := 0
	for record: FloorRecord in stats.floors:
		check(record.duration >= 0.0, "floor %d's duration is not negative" % record.floor_number)
		floor_time += record.duration
		floor_rooms += record.rooms_cleared
	check(stats.duration > 0.0, "the run's clock ran (%.3fs)" % stats.duration)
	check(
		floor_time > 0.0 and floor_time <= stats.duration + 0.001,
		"and the floors' own durations add up to no more than it (%.3fs of %.3fs)" % [
			floor_time, stats.duration,
		],
	)
	check(
		floor_rooms == stats.rooms_cleared,
		"the floors account for every room the run cleared (%d of %d)" % [
			floor_rooms, stats.rooms_cleared,
		],
	)
	check(
		stats.floors[0].rooms_cleared == 2 and stats.floors[1].rooms_cleared == 0,
		"and attribute them to the floor they were cleared on (%d then %d)" % [
			stats.floors[0].rooms_cleared, stats.floors[1].rooms_cleared,
		],
	)

	# Winning pauses the tree; every suite after this one needs frames.
	GameManager.start_run()
	arena.queue_free()
	await advance_physics(1)


## The other two ways a floor ends. Both are filed as losses, and the floor still has to say which:
## "floor 5 destroyed nine players" and "nine players quit on floor 5" are different problems with
## the same total.
func _test_a_run_that_ends_records_how_the_floor_ended() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	for pair: Array in [
		[GameManager.State.GAME_OVER, FloorRecord.Outcome.LOST, "destroyed"],
		[GameManager.State.MAIN_MENU, FloorRecord.Outcome.ABANDONED, "abandoned"],
	]:
		var arena := Node2D.new()
		add_child(arena)
		var floor_node := await _open_floor(arena, campaign, 1337)
		if floor_node == null:
			arena.queue_free()
			await advance_physics(1)
			continue

		if pair[0] == GameManager.State.GAME_OVER:
			GameManager.end_run()
		else:
			GameManager.enter_main_menu()

		var stats := RunManager.stats
		check(stats.floors.size() == 1, "a run ended on its first floor records one floor")
		if stats.floors.size() == 1:
			check(
				stats.floors[0].outcome == pair[1],
				"a run %s on floor 1 records it that way (recorded %s)" % [
					pair[2], FloorRecord.Outcome.keys()[stats.floors[0].outcome],
				],
			)
			check(stats.deepest_floor == 1, "and got no deeper than floor 1")

			# Filing the run twice must not reopen or rewrite the floor it ended on.
			RunManager.end_run(true)
			check(
				stats.floors[0].outcome == pair[1],
				"and a second attempt to file the run does not rewrite it",
			)

		GameManager.start_run()
		arena.queue_free()
		await advance_physics(1)


# --- The content manifest ----------------------------------------------------------------


## What `--manifest` prints, and what makes a seed reproducible across content edits: every floor's
## derived seed plus a fingerprint of the content that seed will be spent on.
func _test_the_manifest_names_every_floor_and_the_content_it_will_build() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var rows := RunManifest.build(campaign, 4242)
	check(rows.size() == campaign.size(), "the manifest has a row per floor")
	if rows.size() != campaign.size():
		return

	var digests: Dictionary[String, int] = {}
	for index: int in rows.size():
		var row := rows[index]
		check(row["id"] == campaign.floor_id_at(index), "row %d names floor %d" % [index, index + 1])
		check(
			row["seed"] == campaign.floor_seed_for(4242, index),
			"and carries the seed that floor derives",
		)
		check(
			row["streams"] == RunRng.stream_seeds(row["seed"]),
			"and every stream that seed feeds",
		)
		var digest: String = row["fingerprint"]
		check(
			digest.length() == RunManifest.FINGERPRINT_DIGITS,
			"and a %d-digit content fingerprint ('%s')" % [RunManifest.FINGERPRINT_DIGITS, digest],
		)
		check(not digests.has(digest), "distinct from every other floor's")
		digests[digest] = index

	var text := RunManifest.describe(campaign, 4242)
	check(text.contains(String(campaign.id)), "the printed manifest names the campaign")
	for index: int in campaign.size():
		check(
			text.contains(String(campaign.floor_id_at(index))),
			"and floor %d" % (index + 1),
		)

	check(
		RunManifest.fingerprint(campaign, 4242) == RunManifest.fingerprint(campaign, 4242),
		"a campaign fingerprints the same way twice",
	)
	check(
		RunManifest.fingerprint(campaign, 4242) != RunManifest.fingerprint(campaign, 4243),
		"and differently for another run seed",
	)

	# The fingerprint's whole job: content changing has to show, even when the seed does not.
	var config := campaign.load_floor(0)
	if require(config, "floor 1 loads"):
		var seed_value := campaign.floor_seed_for(4242, 0)
		var same := RunManifest.row_for(config, 0, config.id, seed_value)
		check(same["fingerprint"] == rows[0]["fingerprint"], "the same content fingerprints the same")

		var edited := config.duplicate() as FloorConfig
		edited.room_count = config.room_count + 1
		check(
			RunManifest.row_for(edited, 0, config.id, seed_value)["fingerprint"]
				!= rows[0]["fingerprint"],
			"and an edited floor fingerprints differently on the same seed",
		)

	# A campaign asked about a floor it does not have describes it rather than refusing, because the
	# manifest is most wanted exactly when the campaign is broken.
	var missing := RunManifest.floor_row(campaign, 4242, campaign.size())
	check(missing["fingerprint"].is_empty(), "a floor the campaign does not have has no fingerprint")
	check(
		RunManifest.describe(null, 4242) == "no campaign",
		"and no campaign at all is said rather than crashed on",
	)


## Where a bug report gets its numbers from. All of this is recorded and none of it is any use if
## the only way to read it is a debugger — the overlay is the one place a player or a tester can see
## the seed, and the reason it shows the *run* seed as well as the floor's is that only the run seed
## is what `--seed=` takes.
func _test_the_debug_overlay_reports_what_reproduces_the_run() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_floor(arena, campaign, 112358)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var hud: DebugHUD = load("res://scenes/ui/debug_hud.tscn").instantiate()
	arena.add_child(hud)
	hud.bind_player(arena.get_node("Player") as Player)
	hud.bind_floor(floor_node)
	await advance_physics(1)
	hud._refresh()

	var seeds: String = hud._values["SEED"].text
	check(seeds.contains("112358"), "the overlay shows the run seed ('%s')" % seeds)
	check(
		seeds.contains(str(campaign.floor_seed_for(112358, 0))),
		"and the floor seed it derived ('%s')" % seeds,
	)

	var content: String = hud._values["CONTENT"].text
	check(content.contains(String(campaign.id)), "and which campaign is being played ('%s')" % content)
	check(
		content.contains("v%d" % campaign.content_version),
		"and its content version ('%s')" % content,
	)
	check(
		content.contains(floor_node.get_content_fingerprint()),
		"and this floor's content fingerprint ('%s')" % content,
	)

	arena.queue_free()
	await advance_physics(1)


# --- Helpers -----------------------------------------------------------------------------


## A campaign over `ids`, pointing every floor at the shipped Help Desk.
##
## The content is deliberately irrelevant: everything these campaigns are used for is seed
## derivation, which reads the ids and the content version and nothing else. Pointing them at real
## content keeps `load_floor` honest if one of them is ever built.
func _campaign_of(ids: Array, version: int) -> RunDefinition:
	var campaign := RunDefinition.new()
	campaign.id = &"determinism_campaign"
	campaign.content_version = version
	var floors: Array[FloorEntry] = []
	for floor_id: StringName in ids:
		var entry := FloorEntry.new()
		entry.id = floor_id
		entry.config_path = "res://data/floors/floor_1_help_desk.tres"
		floors.append(entry)
	campaign.floors = floors
	campaign.target_floor_count = floors.size()
	return campaign


## Opens a run on `campaign`'s first floor, the way `main.gd` does: the campaign's derived seed for
## floor 1, not the run seed raw.
func _open_floor(
	arena: Node2D, campaign: RunDefinition, run_seed: int, config: FloorConfig = null
) -> FloorController:
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.campaign = campaign
	floor_node.config = config if config != null else campaign.load_floor(0)
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)
	await advance_physics(1)

	GameManager.start_run()
	RunManager.begin_run(run_seed, campaign)
	if not floor_node.build(player, campaign.floor_seed_for(run_seed, 0)):
		fail("floor 1 of the campaign would not build")
		return null
	return floor_node


## Everything about a built floor that a seed is supposed to decide, as comparable strings. Returns
## an empty dictionary if the floor would not build, so a caller can report that once.
func _describe_floor(
	campaign: RunDefinition, run_seed: int, config: FloorConfig = null
) -> Dictionary:
	var described: Dictionary[String, String] = {}
	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_floor(arena, campaign, run_seed, config)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return described

	described["layout"] = _describe_layout(floor_node.layout)
	described["enemies"] = _describe_enemies(floor_node)
	described["shop"] = _describe_shop(floor_node)
	described["content"] = floor_node.get_content_fingerprint()
	var encounter := floor_node.get_boss_encounter()
	described["boss"] = String(encounter.id) if encounter != null else "none"
	described["reward"] = _describe_items(floor_node._draw_boss_reward())

	arena.queue_free()
	await advance_physics(1)
	return described


func _describe_layout(layout: FloorLayout) -> String:
	if layout == null:
		return "no layout"
	var parts := PackedStringArray()
	for room: RoomPlan in layout.rooms:
		parts.append("%d@%v:%d:%s" % [
			room.id, room.cell, room.type,
			room.template.id if room.template != null else &"none",
		])
	return " ".join(parts)


## Which enemies stand where, room by room. The `encounter` stream's whole output.
func _describe_enemies(floor_node: FloorController) -> String:
	var parts := PackedStringArray()
	for plan: RoomPlan in floor_node.layout.rooms:
		var room := floor_node.get_room(plan.id)
		if room == null:
			continue
		for node: Node in room.get_node("%Enemies").get_children():
			var enemy := node as Enemy
			parts.append("%d:%s@%v" % [
				plan.id,
				enemy.config.display_name if enemy != null and enemy.config != null else "unknown",
				node.position if node is Node2D else Vector2.ZERO,
			])
	return " ".join(parts)


## What the floor's shop has on its shelves, in stand order.
func _describe_shop(floor_node: FloorController) -> String:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type != RoomTemplate.Type.SHOP:
			continue
		var room := floor_node.get_room(plan.id)
		if room == null:
			continue
		for child: Node in room.get_children():
			var shop := child as ShopRoom
			if shop == null:
				continue
			var parts := PackedStringArray()
			for stand: ShopStand in shop.get_stands():
				parts.append("%d:%s:%d" % [
					stand.kind,
					stand.item.id if stand.item != null else &"none",
					stand.price,
				])
			return " ".join(parts)
	return "no shop"


func _describe_items(items: Array[ItemConfig]) -> String:
	var parts := PackedStringArray()
	for item: ItemConfig in items:
		parts.append(String(item.id))
	return " ".join(parts)


## Fights the floor's boss and claims the reward, which is the only thing that descends. Drives the
## handlers directly, as every other floor-advance check in the project does.
func _descend(floor_node: FloorController) -> void:
	var boss_room := _find_boss_room(floor_node)
	if boss_room == null:
		fail("floor %d has no boss room to descend from" % floor_node.config.floor_number)
		return

	# Freed rather than left to the collector: `Node` is not reference counted, so a stand-in boss
	# dropped here is an object still alive at exit.
	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()
	await advance_physics(1)
	await _claim_reward(floor_node)


func _claim_reward(floor_node: FloorController) -> void:
	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	# The rebuild is deferred, and so is the physics flush after it. One frame is not enough.
	await advance_physics(4)


func _find_boss_room(floor_node: FloorController) -> Room:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			return floor_node.get_room(plan.id)
	return null

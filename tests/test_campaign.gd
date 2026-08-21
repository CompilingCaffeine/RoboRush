extends TestCase
## Checks the campaign — the run's floor order — and the validator that has to refuse a broken one.
##
## Everything here is a failure that used to be invisible until the worst possible moment.
## `FloorGenerator` refuses a floor with no eligible template, but it refuses it *during the
## descent*, after the floor the player was on has been torn down, so a content typo on floor 4
## presents as a run that ends in an empty world four floors in. A pool too small for the offers a
## campaign promises does not error at all — `RunManager.draw_item` returns null, every caller has
## a graceful fallback, and the run just stops handing out items. Both are decidable from the data
## before a run starts, which is the only time anybody can act on them.
##
## The faults are injected rather than described: each one writes a deliberately broken floor to
## `user://`, points a campaign at it, and asserts the validator says so. A validator tested only
## against valid content is a validator that passes with its checks commented out.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_CONFIG_PATH := "res://data/floors/floor_1_help_desk.tres"

## Something that loads perfectly well and is not a floor, for the "points at the wrong kind of
## resource" case. Any .tres that is not a `FloorConfig` would do.
const NOT_A_FLOOR_PATH := "res://data/pools/run_item_pool.tres"

## Where the deliberately broken floors are written. Under `user://` because the campaign resolves
## floors by path, so a fault has to be injected as a *file* — the validator is being asked
## whether it can load what the campaign names, and handing it an in-memory object would skip the
## half of the question that fails in practice.
const TEMP_DIR := "user://test_campaign"

const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Paths written during the run, removed at the end of it.
var _written: PackedStringArray = []


func run() -> void:
	_test_the_shipped_campaign_is_playable()
	_test_floors_are_found_by_id_and_by_index()
	_test_only_the_last_floor_is_terminal()
	_test_a_valid_synthetic_campaign_passes()
	_test_the_validator_catches_structural_faults()
	_test_the_validator_catches_content_faults()
	_test_the_validator_counts_the_reward_budget()
	_test_the_validator_reports_an_incomplete_campaign()
	await _test_direct_start_and_arrival_agree_on_a_floor()
	_clean_up()


## The campaign the game actually boots with. Errors fail the suite outright — `main.gd` refuses
## to start a run on any of them, so an error here is a game that does not open.
##
## Warnings are held to an exact count rather than merely allowed. The campaign is three floors
## into a declared six, so exactly one warning is expected and correct; a second one appearing is
## either a real regression or a floor landing, and both are worth being told about.
##
## The Data Center landing is what this check caught, which is the point of writing the expected
## text out rather than counting warnings alone: the count did not move, and the message did.
func _test_the_shipped_campaign_is_playable() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "main_campaign.tres loads as a RunDefinition"):
		return

	var report := CampaignValidator.validate(campaign)
	check(report.is_valid(), "the shipped campaign has no errors:\n%s" % report.describe())
	check(
		report.warnings.size() == 1,
		"and exactly one warning, that it is %d floors into its declared %d:\n%s" % [
			campaign.size(), campaign.target_floor_count, report.describe(),
		],
	)
	check(
		_mentions(report.warnings, "floors 5-6 are missing"),
		"which names the floors still to be written",
	)

	check(campaign.id == &"main_campaign", "the campaign has a stable id")
	check(campaign.content_version >= 1, "and a content version to record a seed against")


## A floor has to be findable by name, not only by walking the run from the start. This is what
## `--floor=`, a checkpoint, and a run result all need, and it is the thing a chain of
## `next_floor` links could not do.
func _test_floors_are_found_by_id_and_by_index() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	for index: int in campaign.size():
		var floor_id := campaign.floor_id_at(index)
		check(not floor_id.is_empty(), "floor %d has an id" % (index + 1))
		check(
			campaign.index_of(floor_id) == index,
			"'%s' is found back at index %d" % [floor_id, index],
		)
		var config := campaign.load_floor(index)
		if require(config, "floor %d loads from its path" % (index + 1)):
			check(config.id == floor_id, "and calls itself '%s'" % floor_id)
			check(
				config.floor_number == index + 1,
				"and reports floor_number %d" % (index + 1),
			)

	check(campaign.index_of(&"no_such_floor") == -1, "an unknown floor id is not found")
	check(not campaign.has_floor(-1), "index -1 is not a floor")
	check(not campaign.has_floor(campaign.size()), "nor is one past the last")
	check(campaign.entry_at(campaign.size()) == null, "and asking for it yields nothing")
	check(campaign.load_floor(-1) == null, "as does loading it")
	check(campaign.floor_id_at(campaign.size()).is_empty(), "and it has no id")


## Which floor wins the run. The rule is "the last one the campaign lists" and nothing else — the
## old rule was "the floor whose next_floor is null", which was the same fact restated once per
## floor with five chances to be wrong.
func _test_only_the_last_floor_is_terminal() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var terminal := 0
	for index: int in campaign.size():
		if campaign.is_terminal(index):
			terminal += 1
			check(
				index == campaign.size() - 1,
				"the terminal floor is the last one (floor %d of %d)" % [
					index + 1, campaign.size(),
				],
			)
	check(terminal == 1, "exactly one floor ends the run (%d do)" % terminal)

	# A controller running content the campaign has never heard of ends the run rather than
	# descending into whatever happens to sit at index 0.
	check(campaign.is_terminal(-1), "content outside the campaign has nothing after it")


## The harness itself, before any fault is injected. Without this, a validator that rejected
## everything would pass every test below it.
func _test_a_valid_synthetic_campaign_passes() -> void:
	var first := _write_floor("valid_1", &"alpha", 1)
	var second := _write_floor("valid_2", &"beta", 2)
	if first.is_empty() or second.is_empty():
		return

	var report := CampaignValidator.validate(
		_campaign([[&"alpha", first], [&"beta", second]])
	)
	check(report.is_valid(), "a two-floor synthetic campaign is valid:\n%s" % report.describe())


## The faults that are about the campaign's shape rather than any one floor's content.
func _test_the_validator_catches_structural_faults() -> void:
	check(
		not CampaignValidator.validate(null).is_valid(),
		"no campaign at all is an error rather than an empty run",
	)
	check(
		not CampaignValidator.validate(_campaign([])).is_valid(),
		"a campaign declaring no floors is an error",
	)

	var first := _write_floor("structural_1", &"alpha", 1)
	var second := _write_floor("structural_2", &"beta", 2)
	if first.is_empty() or second.is_empty():
		return

	_expect_error(
		_campaign([[&"alpha", first], [&"alpha", second]]),
		"reuses the floor id",
		"two floors sharing one id",
	)
	_expect_error(
		_campaign([[&"alpha", first], [&"beta", first]]),
		"is the same content as floor 1",
		"one floor listed twice",
	)
	_expect_error(
		_campaign([[&"alpha", first], [&"gamma", second]]),
		"calls itself",
		"a floor listed under an id it does not answer to",
	)
	_expect_error(
		_campaign([[&"alpha", first], [&"missing", "res://data/floors/no_such_floor.tres"]]),
		"does not exist",
		"a path with nothing behind it",
	)
	_expect_error(
		_campaign([[&"alpha", first], [&"wrong", NOT_A_FLOOR_PATH]]),
		"is not a FloorConfig",
		"a path pointing at something that is not a floor",
	)

	# Position and floor_number are two statements of the same fact, and content eligibility reads
	# the second while the campaign reads the first. A floor that disagrees with itself draws the
	# wrong rooms under the right banner.
	var misnumbered := _write_floor("structural_misnumbered", &"beta", 5)
	if not misnumbered.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", misnumbered]]),
			"reports floor_number 5",
			"a floor numbered differently from where it sits",
		)

	# The campaign is the only floor order there is. `FloorConfig` used to name the floor after it,
	# and the reason that cannot come back is not a validator rule — the property is gone, so a
	# floor has nowhere left to hold a second answer.
	var properties := _property_names(load(FLOOR_CONFIG_PATH) as FloorConfig)
	# Asserted first, and it is not decoration: a check for the absence of a property passes just
	# as happily when the lookup itself has stopped working, and this is the one line that tells
	# the two apart.
	check(&"floor_number" in properties, "a floor's own exported fields are visible to this check")
	check(not (&"next_floor" in properties), "and a floor has no way to name the floor after it")


## The faults inside one floor: content the generator would refuse, and presentation that names
## things the game does not have.
func _test_the_validator_catches_content_faults() -> void:
	var first := _write_floor("content_1", &"alpha", 1)
	if first.is_empty():
		return

	var no_start := _write_floor("content_no_start", &"beta", 2, func(config: FloorConfig) -> void:
		# Reassigned, never cleared in place: a shallow duplicate shares its arrays with the
		# shipped resource, and emptying one here would delete the Help Desk's start template for
		# every suite that runs after this file.
		config.start_templates = [] as Array[RoomTemplate]
	)
	if not no_start.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", no_start]]),
			"no eligible START template",
			"a floor the generator could not place a start room on",
		)

	var too_small := _write_floor("content_small", &"beta", 2, func(config: FloorConfig) -> void:
		config.room_count = 3
	)
	if not too_small.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", too_small]]),
			"the generator needs at least",
			"a floor with no room for its own special rooms",
		)

	var late_item := _write_floor("content_late_item", &"beta", 2, func(config: FloorConfig) -> void:
		config.item_clear_indices = [99] as Array[int]
	)
	if not late_item.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", late_item]]),
			"but has only",
			"a floor promising an item on a clear it never reaches",
		)

	var bad_track := _write_floor("content_track", &"beta", 2, func(config: FloorConfig) -> void:
		var theme := config.theme.duplicate() as FloorTheme
		theme.explore_music = &"__no_such_track"
		config.theme = theme
	)
	if not bad_track.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", bad_track]]),
			"not in the library",
			"a floor asking for music that does not exist",
		)

	var no_boss := _write_floor("content_no_boss", &"beta", 2, func(config: FloorConfig) -> void:
		config.boss_pool = [] as Array[BossEncounter]
	)
	if not no_boss.is_empty():
		_expect_error(
			_campaign([[&"alpha", first], [&"beta", no_boss]]),
			"has no boss",
			"a floor with nothing at the end of it",
		)


## The reason a six-floor campaign cannot simply be four more `FloorConfig` resources.
##
## The item pool is spent cumulatively — `RunManager.offered_item_ids` is run-scoped — so the
## floor that runs it dry is the one after the last one that fits. Twenty-one items against eight
## offers a floor means the fourth floor is already short, and nothing in the running game reports
## it: the treasure room drops a repair cell and the boss offers two choices instead of three.
func _test_the_validator_counts_the_reward_budget() -> void:
	var config := load(FLOOR_CONFIG_PATH) as FloorConfig
	if not require(config, "floor 1 loads"):
		return

	# Two combat clears, one treasure, two shop stands, three boss choices.
	check(
		CampaignValidator.offers_required(config) == 8,
		"the Help Desk promises 8 item offers (counted %d)"
			% CampaignValidator.offers_required(config),
	)

	# A pool of four one-time items and nothing repeatable, against four floors of eight offers.
	# The shipped pool covers the campaign, which is the point of having expanded it — so the
	# starvation case has to be built rather than found.
	var starved := ItemPool.new()
	var few: Array[ItemConfig] = []
	for item: ItemConfig in config.item_pool.items:
		if not item.is_repeatable() and few.size() < 4:
			few.append(item)
	starved.items = few

	var entries: Array = []
	for index: int in 4:
		var path := _write_floor(
			"budget_%d" % index,
			StringName("budget_%d" % index),
			index + 1,
			# The boss pool is trimmed to two here as well as the item pool being starved, because
			# the second half of this test is about a *boss* shortfall and it used to get one for
			# free: these floors are Help Desk copies, and the Help Desk shipped with exactly two
			# bosses. It has four now, four floors with four distinct bosses is legal, and the
			# check below stopped describing anything. A test about a rule should build the
			# condition the rule is for rather than inherit it from content that can move.
			func(floor_config: FloorConfig) -> void:
				floor_config.item_pool = starved
				floor_config.boss_pool = floor_config.boss_pool.slice(0, 2),
		)
		if path.is_empty():
			return
		entries.append([StringName("budget_%d" % index), path])

	var report := CampaignValidator.validate(_campaign(entries))
	check(
		not report.is_valid() and _mentions(report.errors, "come up empty"),
		"a pool of four one-time items cannot fill four floors of offers:\n%s" % report.describe(),
	)

	# And the other side of the same rule: with a repeatable in the pool an offer can always be
	# filled, so running the uniques dry is reported as a change in what the run hands out rather
	# than as a campaign that must not start.
	#
	# Written as its own set of floors rather than by mutating `starved` and validating again. The
	# floors are resolved from disk, so a pool edited in memory after they were saved is a pool the
	# validator never sees — and the check would pass or fail for reasons unrelated to the rule.
	# The array is rebuilt typed for a similar reason: `few + [chip]` yields an untyped `Array`,
	# which `ItemPool.items` refuses at runtime, leaving the pool silently unchanged.
	var padded_pool := ItemPool.new()
	var padded_items: Array[ItemConfig] = few.duplicate()
	padded_items.append(_first_repeatable(config))
	padded_pool.items = padded_items

	var padded_entries: Array = []
	for index: int in 4:
		var path := _write_floor(
			"padded_%d" % index,
			StringName("padded_%d" % index),
			index + 1,
			func(floor_config: FloorConfig) -> void: floor_config.item_pool = padded_pool,
		)
		if path.is_empty():
			return
		padded_entries.append([StringName("padded_%d" % index), path])

	# Asserted against the capacity rule alone rather than against overall validity. These floors
	# are Help Desk copies standing in for floors 3 and 4, whose templates stop at floor 2 — a real
	# error, reported correctly, and nothing to do with whether a repeatable item fills an offer.
	var padded := CampaignValidator.validate(_campaign(padded_entries))
	check(
		not _mentions(padded.errors, "come up empty")
			and _mentions(padded.warnings, "repeatable items"),
		"but one repeatable item turns the shortfall into a warning:\n%s" % padded.describe(),
	)
	# The other thing four floors and two bosses means, from the `starved` set above, whose pools
	# were trimmed to two for exactly this. The campaign policy is one distinct boss per floor, so
	# this is refused rather than noted: `_draw_boss_encounter` no longer falls back to the full
	# pool, which makes an under-supplied campaign a run that breaks at floor 3.
	check(
		_mentions(report.errors, "distinct bosses"),
		"and four floors sharing two bosses cannot each be given one of their own",
	)


## An incomplete campaign plays and says so; a campaign that claims to be finished and is not
## refuses to start. That switch is what lets the validator be strict from the first floor rather
## than being turned on once the last one lands.
func _test_the_validator_reports_an_incomplete_campaign() -> void:
	var first := _write_floor("length_1", &"alpha", 1)
	var second := _write_floor("length_2", &"beta", 2)
	if first.is_empty() or second.is_empty():
		return

	var entries: Array = [[&"alpha", first], [&"beta", second]]

	var short_campaign := _campaign(entries, 6)
	var short_report := CampaignValidator.validate(short_campaign)
	check(short_report.is_valid(), "two floors of a declared six still play")
	check(
		_mentions(short_report.warnings, "floors 3-6 are missing"),
		"and are reported as four floors short",
	)

	short_campaign.require_complete = true
	check(
		not CampaignValidator.validate(short_campaign).is_valid(),
		"but a campaign that says it is complete and is not refuses to start",
	)

	_expect_error(
		_campaign(entries, 1),
		"lists 2 floors but targets 1",
		"a campaign longer than it says it is",
	)


## The acceptance criterion for direct start: `--floor=2` has to build the floor 2 that a run
## fighting its way there would have built, from the same run seed. A debug jump that produced a
## different floor is only useful for floors nobody reports bugs about.
##
## What it deliberately does *not* reproduce is the run — the items, the scrap, the integrity, and
## the bosses already fought. The boss draw in particular depends on `RunManager.fought_boss_ids`,
## so a direct start may legitimately draw the boss an arrival could not. What must agree is the
## floor: its derived seed, the layout that seed produces, and the content manifest it was spent
## against.
func _test_direct_start_and_arrival_agree_on_a_floor() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	var second_config := campaign.load_floor(1)
	if not require(second_config, "the campaign has a second floor"):
		return

	var run_seed := 4242
	for index: int in campaign.size():
		check(
			campaign.floor_seed_for(run_seed, index)
				== RunRng.floor_seed(run_seed, campaign.content_version, campaign.floor_id_at(index)),
			"floor %d's seed comes from the run seed and its own id" % (index + 1),
		)

	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	GameManager.start_run()
	RunManager.begin_run(run_seed, campaign)
	if require(
		floor_node.build(player, campaign.floor_seed_for(run_seed, 0)),
		"floor 1 builds from its derived seed",
	):
		var boss_room := _find_boss_room(floor_node)
		if require(boss_room, "floor 1 has a boss room to fight through"):
			# Freed rather than left to the collector: `Node` is not reference counted, and a
			# stand-in boss dropped on the floor here is an object still alive at exit.
			var stand_in := Node.new()
			floor_node._on_boss_defeated(stand_in, boss_room)
			stand_in.free()
			await advance_physics(1)
			floor_node._on_boss_reward_taken(campaign.load_floor(0).get_items()[0])
			await advance_physics(2)

			var derived := campaign.floor_seed_for(run_seed, 1)
			check(
				RunManager.floor_seed == derived,
				"arriving on floor 2 uses the seed a direct start derives for it",
			)
			check(floor_node.floor_index == 1, "and the controller knows it is floor 2")

			var direct := FloorGenerator.generate(
				second_config, RunRng.stream_seed(derived, RunRng.LAYOUT)
			)
			check(
				_signature(floor_node.layout) == _signature(direct),
				"and both routes lay out the same floor 2",
			)
			# The other half of the criterion, and the half a seed cannot state on its own: both
			# routes have to agree about the *content* the seed is spent on, or the same number
			# builds two different floors and nothing says which.
			check(
				floor_node.get_content_fingerprint()
					== RunManifest.floor_row(campaign, run_seed, 1)["fingerprint"],
				"and on floor 2's content manifest",
			)

	GameManager.start_run()
	arena.queue_free()
	await advance_physics(1)


## Writes a copy of the Help Desk under a new id and number, optionally broken by `mutate`.
##
## A copy of real content rather than a `FloorConfig.new()`, so every fault below is one thing
## wrong with an otherwise valid floor — a blank floor fails every check at once and proves
## nothing about which one fired.
##
## The duplicate is shallow, so `mutate` must *reassign* whole properties and never edit one in
## place: the arrays are shared with the shipped resource, and a test that emptied one would break
## the Help Desk for every suite after this file.
func _write_floor(
	basename: String, floor_id: StringName, floor_number: int, mutate := Callable()
) -> String:
	var source := load(FLOOR_CONFIG_PATH) as FloorConfig
	if source == null:
		fail("floor 1 must load to build a test floor from")
		return ""

	var config := source.duplicate() as FloorConfig
	config.id = floor_id
	config.floor_number = floor_number
	# The Help Desk's own templates are tagged `help_desk` and capped at floor 2, so a copy standing
	# in for a later floor has to keep the tags that make its own rooms eligible.
	if mutate.is_valid():
		mutate.call(config)

	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path := "%s/%s.tres" % [TEMP_DIR, basename]
	var status := ResourceSaver.save(config, path)
	if status != OK:
		fail("could not write the test floor %s (error %d)" % [path, status])
		return ""
	_written.append(path)
	return path


## A campaign over `entries`, each `[id, config_path]`. Targets its own length unless told
## otherwise, so a test about one fault is not also a test about the campaign being short.
func _campaign(entries: Array, target := -1) -> RunDefinition:
	var campaign := RunDefinition.new()
	campaign.id = &"test_campaign"
	var floors: Array[FloorEntry] = []
	for pair: Array in entries:
		var entry := FloorEntry.new()
		entry.id = pair[0]
		entry.config_path = pair[1]
		floors.append(entry)
	campaign.floors = floors
	campaign.target_floor_count = target if target > 0 else maxi(floors.size(), 1)
	return campaign


## Asserts `campaign` is refused, and refused *for the stated reason* rather than incidentally.
func _expect_error(campaign: RunDefinition, fragment: String, description: String) -> void:
	var report := CampaignValidator.validate(campaign)
	check(
		not report.is_valid() and _mentions(report.errors, fragment),
		"%s is refused, saying '%s':\n%s" % [description, fragment, report.describe()],
	)


## The pool's first stackable chip. Fails the check rather than returning null, because every
## assertion that depends on one is meaningless without it.
func _first_repeatable(config: FloorConfig) -> ItemConfig:
	for item: ItemConfig in config.item_pool.items:
		if item.is_repeatable():
			return item
	fail("the shipped pool must contain at least one repeatable item")
	return null


## Every property a resource exposes, by name. Used to assert that one is *gone* — a check the
## validator cannot make, because a rule about a property that no longer exists is a rule that
## silently stops running.
func _property_names(resource: Resource) -> Array[StringName]:
	var names: Array[StringName] = []
	if resource == null:
		return names
	for entry: Dictionary in resource.get_property_list():
		names.append(entry["name"])
	return names


## Substring rather than equality, because the messages carry the names and numbers that make them
## actionable and a test should not have to restate them to assert the rule fired.
func _mentions(lines: PackedStringArray, fragment: String) -> bool:
	for line: String in lines:
		if fragment in line:
			return true
	return false


## Everything about a generated floor that two routes to it have to agree on: which cells hold
## which kind of room, and which template each one drew.
func _signature(layout: FloorLayout) -> String:
	if layout == null:
		return "<no layout>"
	var parts: PackedStringArray = []
	for room: RoomPlan in layout.rooms:
		parts.append("%d@%s:%s:%s" % [
			room.id,
			room.cell,
			RoomTemplate.Type.keys()[room.type],
			room.template.id if room.template != null else &"none",
		])
	return " ".join(parts)


func _find_boss_room(floor_node: FloorController) -> Room:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			return floor_node.get_room(plan.id)
	return null


## The broken floors are deliberately broken content sitting in the user's data directory. Left
## behind, they would be read by the next run of the suite from a build that had since changed
## what a valid floor looks like.
func _clean_up() -> void:
	for path: String in _written:
		DirAccess.remove_absolute(path)
	_written.clear()
	DirAccess.remove_absolute(TEMP_DIR)

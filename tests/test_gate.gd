extends TestCase
## The Floor 3 gate, from the six-floor plan, as a suite.
##
## `SIX_FLOOR_SCALING_GAMEPLAN.md` gives each floor a list of conditions that have to hold before
## the next one is worth starting. Floor 3's are not about the Data Center — they are about the
## *architecture* it is the first real test of, which is why the plan calls that floor the
## "architecture-proving vertical slice". Two floors can produce one transition, and one transition
## cannot show a trend. Three can.
##
## The five criteria, and where each is answered:
##
## 1. Floors 1 -> 2 -> 3 complete with no stale object from either prior floor.
## 2. All three floors pass at least 120 generation seeds.
## 3. Both transitions preserve every declared run-wide field and reset every declared floor-local
##    field.
## 4. Death, abandon, restart, reward claim, and checkpoint restore each file the run at most once.
## 5. Post-boss committed hazards retain their intended behaviour.
##
## All five are checked here, against the **shipped campaign** rather than against a greybox one.
## That is the difference between this suite and the parts of `tests/test_floor.gd` it overlaps
## with. Those checks use a synthetic six-floor campaign precisely so they can produce five
## boundaries before five floors exist; this one is the same questions asked of the content the
## player will actually be handed, and it can only be asked now that a third real floor exists.
##
## The third criterion is the one that needed something building for it. "Every declared field" is
## not a property a test can discover — somebody has to have declared them — so `RunManager` now
## carries `RUN_WIDE_FIELDS` and `FLOOR_LOCAL_FIELDS`, and the first check below is that those two
## lists between them account for every script variable on the node. A field added without a
## decision fails here rather than surfacing three floors later as a run that lost its scrap.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CASCADE_SCENE := preload("res://scenes/bosses/cascade_failure.tscn")
const CASCADE_CONFIG := "res://data/bosses/cascade_failure.tres"

## The plan's number, and `tests/test_floor.gd` uses the same one. Written as its own constant
## rather than read from that suite because the requirement belongs to the plan, not to whichever
## file happens to satisfy it first.
const SEED_COUNT := 120

## The arena a boss fights in, for the committed-hazard check.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## How much of the run seed space to walk for the generation sweep. Spread rather than consecutive,
## so the seeds exercised are not 120 neighbours that hash to nearly the same layout.
const SEED_STRIDE := 37

var _campaign: RunDefinition


func run() -> void:
	_campaign = load(CAMPAIGN_PATH) as RunDefinition
	if not require(_campaign, "the shipped campaign loads"):
		return

	_test_the_campaign_is_three_playable_floors()
	_test_every_field_of_the_run_is_classified()
	_test_every_floor_generates_across_seeds()

	await _test_one_two_three_leaves_nothing_behind()
	await _test_both_transitions_carry_the_run_and_replace_the_floor()
	await _test_each_ending_files_the_run_at_most_once()
	await _test_the_data_centers_boss_leaves_its_committed_heat()


# --- The content ---------------------------------------------------------------


## Before anything is generated or driven: the campaign really is three distinct, valid floors, and
## the validator agrees. Every check below builds on this, and a failure here would otherwise
## present as five unrelated ones.
func _test_the_campaign_is_three_playable_floors() -> void:
	check(_campaign.size() == 3, "the campaign is three floors long (%d)" % _campaign.size())

	var report := CampaignValidator.validate(_campaign)
	check(report.is_valid(), "and passes validation:\n%s" % report.describe())

	var expected: Array[StringName] = [&"help_desk", &"development", &"data_center"]
	for index: int in mini(expected.size(), _campaign.size()):
		var config := _campaign.load_floor(index)
		if not require(config, "floor %d's content loads" % (index + 1)):
			continue
		check(
			config.id == expected[index],
			"floor %d is '%s' (is '%s')" % [index + 1, expected[index], config.id],
		)
		check(
			config.floor_number == index + 1,
			"and knows which floor it is (%d)" % config.floor_number,
		)


## Criterion three's precondition. "Every declared run-wide field" is only a meaningful phrase if
## the declaration is complete, so this is the check that keeps the two lists honest as the run
## grows fields.
func _test_every_field_of_the_run_is_classified() -> void:
	var declared: Dictionary[StringName, int] = {}
	for list: Array in [
		RunManager.RUN_WIDE_FIELDS, RunManager.RUN_LEDGER_FIELDS, RunManager.FLOOR_LOCAL_FIELDS,
	]:
		for name: StringName in list:
			declared[name] = declared.get(name, 0) + 1

	var actual: Dictionary[StringName, bool] = {}
	for property: Dictionary in RunManager.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		actual[property["name"] as StringName] = true

	var unclassified: PackedStringArray = []
	for name: StringName in actual:
		if not declared.has(name):
			unclassified.append(String(name))
	check(
		unclassified.is_empty(),
		"every field of the run is declared run-wide, a ledger, or floor-local (%s is not)"
			% ", ".join(unclassified),
	)

	var phantom: PackedStringArray = []
	var doubled: PackedStringArray = []
	for name: StringName in declared:
		if not actual.has(name):
			phantom.append(String(name))
		elif declared[name] > 1:
			doubled.append(String(name))
	check(
		phantom.is_empty(),
		"and every declared field still exists (%s does not)" % ", ".join(phantom),
	)
	check(
		doubled.is_empty(),
		"and none is declared in two of the lists (%s is)" % ", ".join(doubled),
	)


## Criterion two. The plan asks for 120 seeds a floor, which at three floors is 360 layouts, and
## what it is really asking is whether a floor's *own* content can fill its own room count — the
## generator is shared but its input is not.
##
## Leaner than `tests/test_floor.gd`'s sweep on purpose. That one asserts every structural invariant
## spec section 9 names; this one asks the gate's question, which is narrower and blunter: does a
## layout come out, does it have the rooms the floor promised, and can the player reach the boss.
func _test_every_floor_generates_across_seeds() -> void:
	for index: int in _campaign.size():
		var config := _campaign.load_floor(index)
		if not require(config, "floor %d's content loads to sweep" % (index + 1)):
			continue

		var failures := PackedStringArray()
		for offset: int in SEED_COUNT:
			var seed_value := 1000 + offset * SEED_STRIDE
			var layout := FloorGenerator.generate(config, seed_value)
			if layout == null:
				failures.append("seed %d produced no layout" % seed_value)
				continue
			if layout.rooms.size() != config.room_count:
				failures.append(
					"seed %d built %d rooms of %d" % [seed_value, layout.rooms.size(), config.room_count]
				)
			var has_boss := false
			for plan: RoomPlan in layout.rooms:
				if plan.type == RoomTemplate.Type.BOSS:
					has_boss = true
			if not has_boss:
				failures.append("seed %d has no boss room" % seed_value)

		check(
			failures.is_empty(),
			"floor %d ('%s') generates on all %d seeds%s" % [
				index + 1, config.id, SEED_COUNT,
				"" if failures.is_empty() else ": " + ", ".join(failures.slice(0, 3)),
			],
		)


# --- The transitions -----------------------------------------------------------


## Criterion one, on the shipped campaign. Two boundaries, and after each one exactly one of
## everything a floor owns.
##
## Two rather than five, which is all three floors can produce and is the honest number to check
## here — `tests/test_floor.gd` runs five against a greybox campaign precisely because a trend needs
## more boundaries than this game has floors. What this adds is that the objects being counted are
## the real ones: the Help Desk's rooms, Development's, and the Data Center's.
func _test_one_two_three_leaves_nothing_behind() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_the_campaign(arena, 8675309)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(2)
		return

	for boundary: int in 2:
		await _descend(floor_node)
		var number := boundary + 2
		check(
			floor_node.config.floor_number == number,
			"boundary %d lands on floor %d (landed on %d)"
				% [boundary + 1, number, floor_node.config.floor_number],
		)
		check(
			_sessions_under(floor_node) == 1,
			"and floor %d is the only floor in the tree (%d are)"
				% [number, _sessions_under(floor_node)],
		)
		check(
			_containers_under(floor_node) == 1,
			"and owns the only projectile container (%d do)" % _containers_under(floor_node),
		)
		check(
			floor_node._rooms.size() == floor_node.config.room_count,
			"and has %d rooms, not two floors' worth (%d)"
				% [floor_node.config.room_count, floor_node._rooms.size()],
		)
		check(
			floor_node.get_session().generation == number,
			"and is the %dth session opened (is %d)" % [number, floor_node.get_session().generation],
		)

	check(
		floor_node.get_session().pending_count() == 0,
		"nothing is left queued after both boundaries",
	)
	check(
		floor_node.config.id == &"data_center",
		"and the run has arrived on the Data Center ('%s')" % floor_node.config.id,
	)

	arena.queue_free()
	await advance_physics(2)


## Criterion three, and the reason `RunManager` declares its fields at all.
##
## Snapshotted immediately either side of the descent and nothing else in between, so a field that
## differs differs *because of the boundary*. Run-wide values must be identical; floor-local ones
## must be the new floor's, and are checked against what the campaign says they should be rather
## than merely against "something changed" — a boundary that reset the floor seed to zero would
## satisfy the weaker version.
func _test_both_transitions_carry_the_run_and_replace_the_floor() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node := await _open_the_campaign(arena, 271828)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(2)
		return

	# Something on every run-wide field worth moving, so "unchanged" is a claim about real values
	# rather than about a pile of zeroes that would look preserved however badly it was handled.
	RunManager.add_scrap(17)
	RunManager.add_enemy_health_growth(0.24)
	RunManager.spend_death_save(6.0, 1.0)
	RunManager.offered_item_ids.append(&"__gate_probe")

	for boundary: int in 2:
		var before := _snapshot(RunManager.RUN_WIDE_FIELDS)
		var ledgers_before := _snapshot(RunManager.RUN_LEDGER_FIELDS)
		var stats_before := RunManager.stats
		await _descend(floor_node)
		var after := _snapshot(RunManager.RUN_WIDE_FIELDS)

		var moved: PackedStringArray = []
		for name: StringName in before:
			if not _same(before[name], after[name]):
				moved.append("%s (%s -> %s)" % [name, before[name], after[name]])
		check(
			moved.is_empty(),
			"transition %d carries every run-wide field (%s)"
				% [boundary + 1, "none moved" if moved.is_empty() else ", ".join(moved)],
		)

		# The ledgers, which are allowed to grow and not to shrink. Opening a floor draws its boss
		# and reserves the items it will offer, so both of these are longer on the other side of a
		# boundary — but nothing already spent may fall out of them, or the run repeats a boss or
		# hands out an item twice.
		var lost: PackedStringArray = []
		for name: StringName in ledgers_before:
			var kept: Array = RunManager.get(name)
			for entry: Variant in ledgers_before[name] as Array:
				if entry not in kept:
					lost.append("%s dropped %s" % [name, entry])
		check(
			lost.is_empty(),
			"transition %d loses nothing from the run's ledgers (%s)"
				% [boundary + 1, "none" if lost.is_empty() else ", ".join(lost)],
		)
		# Identity, not contents: the statistics object goes on accumulating across a boundary and
		# is *supposed* to — what must not happen is a descent handing the run a different one,
		# which would silently reset every per-run total the summary screen reads.
		check(
			is_same(RunManager.stats, stats_before),
			"and keeps the same statistics object rather than starting a new one",
		)

		var expected_index := boundary + 1
		var config := _campaign.load_floor(expected_index)
		if not require(config, "the floor descended into has content"):
			continue
		check(
			RunManager.floor_number == expected_index + 1,
			"transition %d resets the floor number to %d (is %d)"
				% [boundary + 1, expected_index + 1, RunManager.floor_number],
		)
		check(
			RunManager.floor_name == config.display_name,
			"and the floor name to '%s' (is '%s')" % [config.display_name, RunManager.floor_name],
		)
		check(
			RunManager.floor_seed == _campaign.floor_seed_for(RunManager.get_run_seed(), expected_index),
			"and the floor seed to the campaign's derived one for that position (%d)"
				% RunManager.floor_seed,
		)

	arena.queue_free()
	await advance_physics(2)


# --- The endings ---------------------------------------------------------------


## Criterion four. Five ways a run can stop being the run in progress, and none of them may write a
## result twice.
##
## Counted at the only place a result is actually filed — `BestRunStats.absorb`, which
## `SaveManager.record_run_finished` calls — rather than at a state change that happens to precede
## it. Two of the five are supposed to file nothing at all, and a check that measured "the game
## reached game over" could not tell the difference between filing nothing and filing twice.
func _test_each_ending_files_the_run_at_most_once() -> void:
	var previous := SaveManager.best
	var counter := CountingRecords.new()
	SaveManager.best = counter

	# Death, twice over: the run ends, and then something tells it to end again. The second call is
	# not hypothetical — a hazard resolving in the same frame as a death does exactly this.
	RunManager.begin_run(11)
	counter.filed = 0
	RunManager.end_run(false)
	RunManager.end_run(false)
	check(counter.filed == 1, "a death files the run exactly once (%d)" % counter.filed)

	RunManager.begin_run(22)
	counter.filed = 0
	RunManager.end_run(false, true)
	RunManager.end_run(false, true)
	check(counter.filed == 1, "so does abandoning it (%d)" % counter.filed)

	# The reward claim on the terminal floor, which is the only way a run is won.
	RunManager.begin_run(33)
	counter.filed = 0
	RunManager.end_run(true)
	RunManager.end_run(false)
	check(counter.filed == 1, "and winning it (%d)" % counter.filed)
	check(SaveManager.best.runs_won == 1, "and it is filed as a win")

	# A restart files nothing: it starts a run, it does not finish one. The run it replaces was
	# already filed when it ended, and filing it again on the way out would double every loss.
	RunManager.begin_run(44)
	counter.filed = 0
	var started := counter.runs_started
	RunManager.begin_run(55)
	check(counter.filed == 0, "restarting files no result (%d)" % counter.filed)
	check(counter.runs_started == started + 1, "and counts exactly one more run started")

	# And a resume files nothing and counts nothing. A player who saves and quits between every
	# floor would otherwise finish a six-floor campaign having "started" six runs.
	var checkpoint := RunCheckpoint.capture(_campaign, _campaign.load_floor(0), 3.0, [])
	counter.filed = 0
	started = counter.runs_started
	RunManager.restore_run(checkpoint, _campaign)
	check(counter.filed == 0, "resuming from a checkpoint files no result (%d)" % counter.filed)
	check(
		counter.runs_started == started,
		"and does not count a run started (%d, was %d)" % [counter.runs_started, started],
	)

	SaveManager.best = previous
	RunManager.begin_run(0)
	await advance_physics(1)


## Criterion five, for this floor's own boss. `tests/test_post_boss.gd` owns the contract in
## general and checks it with a hazard placed by hand; what the gate wants to know is that the
## Data Center's boss really puts its heat somewhere that outlives it.
##
## The two are different questions and the second is where the mistake would be. A `ThermalZone`
## was, until this floor, a room's furniture — built with the room and freed with it — and a boss
## that dropped one under itself would have been dropping it into its own subtree, where dying
## takes it with you.
func _test_the_data_centers_boss_leaves_its_committed_heat() -> void:
	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)

	GameManager.start_run()
	RunManager.begin_run(31337)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = ARENA.get_center()
	arena.add_child(player)
	player.get_health_component().configure(9999.0, 0.0)

	var boss: CascadeFailure = CASCADE_SCENE.instantiate()
	# Slow enough to fill that a vent is still climbing when the rack dies, which is the state the
	# whole criterion is about.
	var tuning: CascadeFailureConfig = (load(CASCADE_CONFIG) as CascadeFailureConfig).duplicate()
	tuning.vent_interval = 0.2
	tuning.vent_seconds = 3.0
	boss.config = tuning
	arena.add_child(boss)
	boss.begin(ARENA)
	await advance_physics(30)

	var climbing := _zones_in(container)
	check(climbing > 0, "the rack has heat climbing on the floor (%d vents)" % climbing)

	for part: BossPart in boss.get_parts():
		part.took_damage.emit(DamageInfo.new(9999.0))
	await advance_physics(4)

	check(_zones_in(container) == climbing, "and killing it takes none of it away")
	# Still climbing rather than merely still present: a zone orphaned from whatever was ticking it
	# would also survive, and would never vent.
	await advance_physics(30)
	var hottest := 0.0
	for child: Node in container.get_children():
		var zone := child as ThermalZone
		if zone != null:
			hottest = maxf(hottest, zone.get_heat())
	check(hottest > 0.0, "and it goes on heating without the boss (%.2f)" % hottest)

	GameManager.start_run()
	arena.queue_free()
	await advance_physics(2)


# --- Fixtures ------------------------------------------------------------------


## A `BestRunStats` that keeps count of being written to. Everything else about it is the real
## thing, so the values it produces are the values a run would really have recorded.
class CountingRecords extends BestRunStats:
	var filed := 0

	func absorb(stats: RunStats, won: bool) -> PackedStringArray:
		filed += 1
		return super(stats, won)


## Opens the shipped campaign on its first floor, the way a real run does — the campaign's own
## derived seed for position zero, not the run seed raw.
func _open_the_campaign(arena: Node2D, seed_value: int) -> FloorController:
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
		fail("the shipped campaign's first floor would not build from seed %d" % seed_value)
		return null
	await advance_physics(2)
	return floor_node


## Kills the boss and claims its reward, which is the whole of a descent as the game performs it.
func _descend(floor_node: FloorController) -> void:
	var boss_room := _boss_room(floor_node)
	if boss_room == null:
		fail("floor %d has no boss room to descend from" % floor_node.config.floor_number)
		return

	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()
	await advance_physics(1)

	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	# The rebuild is deferred, and so is the physics flush that follows it. One frame is not enough.
	await advance_physics(4)


func _boss_room(floor_node: FloorController) -> Room:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			return floor_node.get_room(plan.id)
	return null


## The named fields of the run, read off by name, with collections copied so the snapshot is a
## reading rather than a live view of the very thing it is meant to be compared against.
func _snapshot(names: Array[StringName]) -> Dictionary[StringName, Variant]:
	var reading: Dictionary[StringName, Variant] = {}
	for name: StringName in names:
		var value: Variant = RunManager.get(name)
		reading[name] = value.duplicate() if value is Array else value
	return reading


## Equality that works for the mix of scalars, arrays and objects the run holds. Objects are
## compared by identity, which is the question worth asking about them here — see the note in
## `_test_both_transitions_carry_the_run_and_replace_the_floor`.
func _same(before: Variant, after: Variant) -> bool:
	if before is Array and after is Array:
		return (before as Array) == (after as Array)
	if before is Object or after is Object:
		return is_same(before, after)
	return before == after


func _sessions_under(floor_node: FloorController) -> int:
	var found := 0
	for child: Node in floor_node.get_children():
		if child is FloorSession:
			found += 1
	return found


func _containers_under(node: Node) -> int:
	var found := 0
	for candidate: Node in node.get_tree().get_nodes_in_group(ProjectileFactory.CONTAINER_GROUP):
		if node.is_ancestor_of(candidate):
			found += 1
	return found


func _zones_in(container: Node) -> int:
	var found := 0
	for child: Node in container.get_children():
		if child is ThermalZone:
			found += 1
	return found

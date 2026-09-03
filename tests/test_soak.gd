extends TestCase
## Complete shipped campaigns, run end to end, many times over.
##
## Every other suite checks a boundary in isolation: that one descent keeps the run's state, that
## one released floor takes its projectiles with it, that five boundaries leave one floor graph.
## This one asks the question none of those can — whether a *campaign* survives being played, over
## and over, without anything accumulating.
##
## That distinction is not academic. The failures this exists to catch have a shape: they are
## invisible once, plausible twice, and obvious at a hundred. A room graph that survives its floor
## by one frame, a signal connected on every build and disconnected on none, a resource cached
## against a key that includes the floor number — none of them fail a single descent, and all of
## them end a long session. The engine reports the symptom as one number at exit ("N instances were
## leaked") with no owner, which is exactly the diagnostic the test runner's per-suite orphan
## accounting exists to replace.
##
## The completed campaign makes the workload the shipped six floors. This soak carries the actual
## content and claims the final reward, rather than stopping at a synthetic boundary.

## Complete campaigns to play: 600 floors built and released, 500 transitions committed,
## and 100 terminal rewards claimed.
##
## The number is the plan's, and it is a soak rather than a sweep: the seeds are distinct so the
## layouts differ, but what is being measured is what is left behind after each one rather than
## whether any particular layout is correct — `tests/test_floor.gd` sweeps that, 120 seeds per
## floor.
const CAMPAIGNS := 100

const FLOORS_PER_CAMPAIGN := 6

const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func run() -> void:
	await _test_a_hundred_campaigns_leave_nothing_behind()


func _test_a_hundred_campaigns_leave_nothing_behind() -> void:
	var campaign := load("res://data/runs/main_campaign.tres") as RunDefinition
	if campaign == null:
		fail("the shipped campaign must load")
		return
	check(campaign.size() == FLOORS_PER_CAMPAIGN, "the soak covers every shipped floor")

	var arena := Node2D.new()
	add_child(arena)
	# One player for every campaign, which is what a real run does too: the robot is the thing that
	# crosses a boundary, and rebuilding it per campaign would hide anything that accumulates on it.
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)
	await advance_physics(1)

	var failures: PackedStringArray = []
	var completed := 0
	var orphans_before := _orphan_count()
	var nodes_after_first := 0

	for index: int in CAMPAIGNS:
		var seed_value := 7919 + index * 104_729
		GameManager.start_run()
		RunManager.begin_run(seed_value, campaign)

		var floor_node: FloorController = FLOOR_SCENE.instantiate()
		floor_node.campaign = campaign
		floor_node.config = campaign.load_floor(0)
		arena.add_child(floor_node)

		if not floor_node.build(player, campaign.floor_seed_for(seed_value, 0)):
			failures.append("seed %d: floor 1 would not build" % seed_value)
			floor_node.queue_free()
			await advance_physics(1)
			continue

		var reached := await _play_out(floor_node, seed_value, failures)
		if reached == FLOORS_PER_CAMPAIGN:
			completed += 1

		# Ended the way a run ends, so the run-scoped state is closed rather than abandoned
		# half-open into the next campaign.
		RunManager.end_run(true)
		floor_node.queue_free()
		await advance_physics(2)

		# Measured after the first campaign rather than before it: the first one populates every
		# resource cache in the project, and a growth check that included that would be measuring
		# the caches filling rather than anything leaking.
		if index == 0:
			nodes_after_first = _node_count()

	check(
		failures.is_empty(),
		"%d complete %d-floor campaigns run end to end" % [CAMPAIGNS, FLOORS_PER_CAMPAIGN],
	)
	for failure: String in failures.slice(0, 6):
		fail(failure)

	check(
		completed == CAMPAIGNS,
		"every campaign reaches floor %d (%d of %d did)"
			% [FLOORS_PER_CAMPAIGN, completed, CAMPAIGNS],
	)

	# The point of the whole suite. An orphan is a node that exists in no tree, which is what a
	# floor released without being freed becomes.
	var orphaned := _orphan_count() - orphans_before
	check(orphaned == 0, "and leaves no orphaned node behind (%d orphans)" % orphaned)

	# Node count is the coarser measure and catches what orphan count cannot: something still *in*
	# the tree that should have gone with the floor that made it. The tolerance is for the arena
	# and the player, which are deliberately kept, plus whatever a cache legitimately holds.
	var growth := _node_count() - nodes_after_first
	check(
		growth <= 0,
		"and nothing accumulates in the tree across %d campaigns (%+d nodes after the first)"
			% [CAMPAIGNS, growth],
	)

	arena.queue_free()
	await advance_physics(1)


## Descends from floor 1 to the campaign's last floor, returning the floor number it ended on.
func _play_out(
	floor_node: FloorController, seed_value: int, failures: PackedStringArray
) -> int:
	for boundary: int in FLOORS_PER_CAMPAIGN - 1:
		var expected := boundary + 2
		if not await _descend(floor_node, seed_value, failures):
			return floor_node.config.floor_number

		if floor_node.config.floor_number != expected:
			failures.append("seed %d: boundary %d landed on floor %d, not %d"
				% [seed_value, boundary + 1, floor_node.config.floor_number, expected])
			return floor_node.config.floor_number

		# Checked every boundary rather than only at the end, because "exactly one floor" is the
		# invariant that a hundred campaigns are here to stress — and the boundary that broke it is
		# worth more than the fact that something broke it.
		var sessions := 0
		for child: Node in floor_node.get_children():
			if child is FloorSession:
				sessions += 1
		if sessions != 1:
			failures.append("seed %d: %d floor sessions after boundary %d"
				% [seed_value, sessions, boundary + 1])
			return floor_node.config.floor_number

	# Claim the last reward too: reaching the final floor is not completing the campaign.
	if not await _descend(floor_node, seed_value, failures):
		return 0
	if GameManager.state != GameManager.State.VICTORY:
		failures.append("seed %d: the final reward did not win the run" % seed_value)
		return 0
	return floor_node.config.floor_number


## Beats this floor's boss and claims the reward, which is the only thing that descends.
func _descend(
	floor_node: FloorController, seed_value: int, failures: PackedStringArray
) -> bool:
	var boss_room: Room = null
	for room: Room in floor_node._rooms.values():
		if room.plan.type == RoomTemplate.Type.BOSS:
			boss_room = room
			break
	if boss_room == null:
		failures.append("seed %d: floor %d has no boss room"
			% [seed_value, floor_node.config.floor_number])
		return false

	# Freed rather than left to the collector: `Node` is not reference counted, and this runs five
	# hundred times.
	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()
	await advance_physics(1)

	var items := floor_node.config.get_items()
	if items.is_empty():
		failures.append("seed %d: floor %d has no reward to claim"
			% [seed_value, floor_node.config.floor_number])
		return false

	floor_node._on_boss_reward_taken(items[0])
	# The rebuild is deferred, and so is the physics flush that follows it.
	await advance_physics(4)
	return true


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

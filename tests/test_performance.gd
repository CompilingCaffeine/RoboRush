extends TestCase
## Checks the cost of the things that run hundreds of times a frame.
##
## This is the project's first timing suite, and it is written to be *stable* rather than precise,
## because a check that fails on a busy machine teaches everybody to ignore it. Two rules follow from
## that.
##
## **Prefer ratios to stopwatches.** The claim that matters — "enemies the player has not reached
## cost nothing" — is a comparison between two measurements taken seconds apart on the same machine,
## so the machine cancels out. An absolute budget is asserted too, because a ratio cannot catch
## everything getting slower together, but it is set as a tripwire well above the measured value
## rather than as a target.
##
## **Take the best of several rounds.** The minimum is the least noisy statistic available here: it
## is the round that was interrupted least, and no amount of background load can make a run of the
## same code faster than it really is.
##
## What is being defended is the measurement from the scaling plan: 100 homing projectiles cost about
## 3.95 ms a frame against 0.43 for 100 plain ones, and effectively all of that difference was target
## selection walking every enemy on the floor for every shot in flight.

const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")

## Enemies in an active room, at the high end of what a template places.
const AWAKE_ENEMIES := 8

## Enemies asleep elsewhere on the floor. The scaling plan's criterion names a hundred.
const DORMANT_ENEMIES := 100

## Queries per measured round. A hundred homing projectiles asking once each is one frame's worth of
## the workload this suite exists for.
const QUERIES_PER_ROUND := 100

const MEASURED_ROUNDS := 9

## What one frame of that workload may cost before something has gone wrong. The scaling plan asks
## for a p95 at or below 1 ms in the worst legal room; this is that number, and like every number in
## `test_balance.gd` it is a tripwire rather than a claim about what the game needs.
const TARGETING_BUDGET_USEC := 1000.0

## How much a hundred sleeping enemies may add to the cost of targeting the awake ones. Zero is the
## honest expectation — they are not walked at all — so ten percent is entirely measurement noise.
const DORMANT_TOLERANCE := 0.10

## How much faster the registry must be than the group walk it replaced, on a scene with a floor's
## worth of sleeping enemies. Far below what was measured, so this fails on a regression rather than
## on a slow morning.
const MINIMUM_SPEEDUP := 4

## Query radius used by every measurement here, wide enough to reach the awake enemies and nowhere
## near the sleeping ones — the point being that distance is not what excludes them.
const TARGET_RADIUS := 400.0


func run() -> void:
	await _test_the_registry_beats_the_walk_it_replaced()
	await _test_dormant_enemies_cost_nothing()
	await _test_targeting_stays_inside_its_budget()
	await _test_the_registry_matches_the_tree()
	await _test_a_boss_playing_dead_is_not_a_target()
	_test_the_next_floor_is_loaded_before_it_is_needed()


## The change itself, measured rather than asserted: the group walk this replaced is reimplemented
## here and the two are timed against the same scene, in the same process, seconds apart.
##
## Keeping the old code in the suite is the point. A speed-up nobody can reproduce is a claim, and
## the number in a commit message ages badly — a future change that quietly reintroduces a scan (a
## new item asking the group directly, say) shows up here as the ratio collapsing rather than as a
## frame-rate complaint months later.
##
## The bar is deliberately far below what was measured. Four times is a tripwire; the observed figure
## is printed either way, and it is the reason to read this suite's output at all.
func _test_the_registry_beats_the_walk_it_replaced() -> void:
	var arena := Node2D.new()
	add_child(arena)

	var awake := Node2D.new()
	arena.add_child(awake)
	for index: int in AWAKE_ENEMIES:
		_add_bot(awake, Vector2(120.0 + float(index) * 24.0, 0.0))

	var dormant := Node2D.new()
	arena.add_child(dormant)
	for index: int in DORMANT_ENEMIES:
		_add_bot(dormant, Vector2(-600.0 - float(index) * 8.0, 0.0))
	await advance_physics(2)
	dormant.process_mode = Node.PROCESS_MODE_DISABLED
	await advance_physics(2)

	var walk := _measure(func(at: Vector2) -> void: _walk_for_nearest(arena, at))
	var registry := _measure(func(at: Vector2) -> void:
		Targeting.nearest_hostile(arena, at, TARGET_RADIUS, Teams.Id.PLAYER))

	print("    targeting, %d queries against %d awake + %d dormant: walk %.0fus, registry %.0fus (%.1fx)" % [
		QUERIES_PER_ROUND, AWAKE_ENEMIES, DORMANT_ENEMIES, walk, registry,
		walk / maxf(registry, 0.001),
	])
	check(
		registry * MINIMUM_SPEEDUP <= walk,
		"the registry is at least %dx faster than the group walk (%.0fus against %.0fus)" % [
			MINIMUM_SPEEDUP, registry, walk,
		],
	)
	# Both answers have to be the same answer, or the fast one is fast for the wrong reason.
	check(
		Targeting.nearest_hostile(arena, Vector2.ZERO, TARGET_RADIUS, Teams.Id.PLAYER)
			== _walk_for_nearest(arena, Vector2.ZERO),
		"and finds the same enemy the walk did",
	)

	arena.queue_free()
	await advance_physics(2)


## Targeting exactly as it was before the registry: walk the group, filter, sort, take the first.
## Kept for the comparison above and for nothing else.
func _walk_for_nearest(source: Node, centre: Vector2) -> Node2D:
	var found: Array[Node2D] = []
	var radius_squared := TARGET_RADIUS * TARGET_RADIUS
	for node: Node in source.get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var body := node as Node2D
		if body == null or not body.can_process():
			continue
		if body.global_position.distance_squared_to(centre) > radius_squared:
			continue
		var health := HealthComponent.find_on(body)
		if health == null or not health.is_alive():
			continue
		found.append(body)

	found.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.global_position.distance_squared_to(centre)
				< b.global_position.distance_squared_to(centre)
			)
	)
	return found[0] if not found.is_empty() else null


## The criterion, directly: a hundred enemies in rooms the player has not entered must not make
## targeting the eight in front of them measurably slower.
##
## This is what the group walk could not do. Every dormant enemy was inspected on every query — an
## ancestor walk for `can_process`, a child walk for a health component — so a floor got slower to
## shoot in as it got bigger, and it did so invisibly.
func _test_dormant_enemies_cost_nothing() -> void:
	var arena := Node2D.new()
	add_child(arena)

	var awake := Node2D.new()
	arena.add_child(awake)
	for index: int in AWAKE_ENEMIES:
		_add_bot(awake, Vector2(120.0 + float(index) * 24.0, 0.0))
	await advance_physics(2)

	check(
		HostileRegistry.count(Teams.Id.ENEMY) == AWAKE_ENEMIES,
		"the registry holds the %d awake enemies (holds %d)" % [
			AWAKE_ENEMIES, HostileRegistry.count(Teams.Id.ENEMY),
		],
	)
	var alone := _measure_targeting(arena)

	# A second room's worth of enemies, asleep exactly the way a floor puts them to sleep.
	var dormant := Node2D.new()
	arena.add_child(dormant)
	for index: int in DORMANT_ENEMIES:
		_add_bot(dormant, Vector2(-600.0 - float(index) * 8.0, 0.0))
	await advance_physics(2)
	dormant.process_mode = Node.PROCESS_MODE_DISABLED
	await advance_physics(2)

	check(
		HostileRegistry.count(Teams.Id.ENEMY) == AWAKE_ENEMIES,
		"putting %d enemies to sleep leaves the registry holding %d (holds %d)" % [
			DORMANT_ENEMIES, AWAKE_ENEMIES, HostileRegistry.count(Teams.Id.ENEMY),
		],
	)
	check(
		HostileRegistry.known_count() >= AWAKE_ENEMIES + DORMANT_ENEMIES,
		"while still knowing about all %d of them" % (AWAKE_ENEMIES + DORMANT_ENEMIES),
	)

	var crowded := _measure_targeting(arena)
	var growth := (crowded - alone) / maxf(alone, 0.001)
	check(
		growth <= DORMANT_TOLERANCE,
		"%d sleeping enemies change targeting cost by %.1f%% (%.0fus to %.0fus), under %.0f%%" % [
			DORMANT_ENEMIES, growth * 100.0, alone, crowded, DORMANT_TOLERANCE * 100.0,
		],
	)

	arena.queue_free()
	await advance_physics(2)


## The absolute half of the same claim. Reported whether it passes or not, because the number is the
## point: a run of this suite is the only place anybody finds out what targeting actually costs.
func _test_targeting_stays_inside_its_budget() -> void:
	var arena := Node2D.new()
	add_child(arena)
	for index: int in AWAKE_ENEMIES:
		_add_bot(arena, Vector2(120.0 + float(index) * 24.0, 0.0))
	await advance_physics(2)

	var cost := _measure_targeting(arena)
	check(
		cost <= TARGETING_BUDGET_USEC,
		"%d homing queries against %d enemies cost %.0fus, under the %.0fus budget" % [
			QUERIES_PER_ROUND, AWAKE_ENEMIES, cost, TARGETING_BUDGET_USEC,
		],
	)

	# Radius queries are the other shape of the same question — an explosion asking who is in range.
	var blast := _measure_blast(arena)
	check(
		blast <= TARGETING_BUDGET_USEC,
		"and %d blast queries cost %.0fus" % [QUERIES_PER_ROUND, blast],
	)

	arena.queue_free()
	await advance_physics(2)


## The guard that makes the registry safe to rely on: it must agree with the tree.
##
## A registry is a cache, and the failure mode of a cache is being quietly incomplete — an enemy
## scene added later that forgets to register would simply never be shot at by a homing projectile,
## which reads as an item being broken rather than as a missing line in a scene. So the old question
## is asked the old way, directly of the group, and the two answers are compared.
func _test_the_registry_matches_the_tree() -> void:
	var arena := Node2D.new()
	add_child(arena)

	var awake := Node2D.new()
	arena.add_child(awake)
	for index: int in 4:
		_add_bot(awake, Vector2(100.0 + float(index) * 30.0, 0.0))

	var asleep := Node2D.new()
	arena.add_child(asleep)
	for index: int in 3:
		_add_bot(asleep, Vector2(-300.0 - float(index) * 30.0, 0.0))
	await advance_physics(2)
	asleep.process_mode = Node.PROCESS_MODE_DISABLED
	await advance_physics(2)

	var from_tree: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var body := node as CollisionObject2D
		if body == null or not body.can_process() or body.collision_layer == 0:
			continue
		var health := HealthComponent.find_on(body)
		if health != null and health.is_alive():
			from_tree.append(body)

	var from_registry: Array[Node] = []
	for entry: HostileRegistry.Entry in HostileRegistry.shootable(Teams.Id.ENEMY):
		from_registry.append(entry.body)

	check(
		from_registry.size() == from_tree.size(),
		"the registry knows every shootable enemy the tree does (%d against %d)" % [
			from_registry.size(), from_tree.size(),
		],
	)
	var missing := 0
	for body: Node in from_tree:
		if body not in from_registry:
			missing += 1
	check(missing == 0, "and names the same ones (%d missing)" % missing)

	arena.queue_free()
	await advance_physics(2)


## A bug the registry fixes rather than an optimisation it makes.
##
## `BossPart.set_inert` is the boss playing dead between phases: invisible, and off its collision
## layer so nothing can hit it. It stays in the enemy group, stays alive and keeps processing, so the
## old group walk returned it as a target — homing shots curved toward a body the player could not
## see, and chain lightning spent jumps on it. Targetability now means "a projectile could hit this",
## which is the same question the projectile itself asks.
func _test_a_boss_playing_dead_is_not_a_target() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var bot := _add_bot(arena, Vector2(150.0, 0.0))
	await advance_physics(2)

	check(
		Targeting.nearest_hostile(arena, Vector2.ZERO, 400.0, Teams.Id.PLAYER) == bot,
		"an ordinary enemy is a target",
	)

	# The same move `set_inert` makes, on a body that is not a boss part, so this check does not
	# depend on a boss scene to state a rule about collision layers.
	bot.collision_layer = 0
	check(
		Targeting.nearest_hostile(arena, Vector2.ZERO, 400.0, Teams.Id.PLAYER) == null,
		"and one taken off its collision layer is not",
	)
	check(
		Targeting.hostiles_near(arena, Vector2.ZERO, 400.0, Teams.Id.PLAYER).is_empty(),
		"for blasts as well as for homing",
	)

	bot.collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	check(
		Targeting.nearest_hostile(arena, Vector2.ZERO, 400.0, Teams.Id.PLAYER) == bot,
		"and it is a target again when it gets up",
	)

	arena.queue_free()
	await advance_physics(2)


## Microseconds for one frame's worth of queries, best of several rounds. The minimum rather than the
## mean: it is the round that was interrupted least, and nothing can run faster than it really does.
func _measure(query: Callable) -> float:
	var best := INF
	for round_index: int in MEASURED_ROUNDS:
		var started := Time.get_ticks_usec()
		for index: int in QUERIES_PER_ROUND:
			query.call(Vector2(float(index), 0.0))
		best = minf(best, float(Time.get_ticks_usec() - started))
	return best


func _measure_targeting(source: Node) -> float:
	return _measure(func(at: Vector2) -> void:
		Targeting.nearest_hostile(source, at, TARGET_RADIUS, Teams.Id.PLAYER))


func _measure_blast(source: Node) -> float:
	return _measure(func(at: Vector2) -> void:
		Targeting.hostiles_near(source, at, TARGET_RADIUS, Teams.Id.PLAYER))


func _add_bot(parent: Node, at: Vector2) -> Enemy:
	var bot: Enemy = TICKET_BOT_SCENE.instantiate()
	bot.position = at
	parent.add_child(bot)
	return bot


## The other half of the package: a floor arrives before the frame that needs it.
##
## What is checked here is that preloading is *transparent* — same floor, same content, and a floor
## that was never preloaded still loads. The saving itself is not asserted, deliberately: in a suite
## the request and the collection happen microseconds apart, so any number measured here would be
## measuring the harness rather than the game. The gain is real in play, where a floor has the whole
## previous floor to arrive in, and it is bounded by construction — a transition can now only be
## faster than the synchronous load it replaced, never slower, because collecting an unfinished load
## is exactly that load.
func _test_the_next_floor_is_loaded_before_it_is_needed() -> void:
	var campaign := load("res://data/runs/main_campaign.tres") as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	var entry := campaign.entry_at(1)
	if not require(entry, "the campaign has a second floor to preload"):
		return

	var direct := campaign.load_floor(1)
	check(entry.is_preloading() == false, "a floor nobody asked for is not being preloaded")

	campaign.preload_floor(1)
	check(entry.is_preloading(), "asking for it starts a background load")

	var preloaded := campaign.load_floor(1)
	check(not entry.is_preloading(), "collecting it clears the request")
	check(preloaded == direct, "and hands back the same floor the synchronous load did")
	check(
		preloaded != null and preloaded.id == campaign.floor_id_at(1),
		"named as the campaign names it",
	)

	# Past the end of the campaign, which is where the last floor asks for its successor every run.
	campaign.preload_floor(campaign.size())
	check(campaign.load_floor(campaign.size()) == null, "preloading past the last floor is harmless")

extends TestCase
## Checks for the Data Center's boss, Cascade Failure.
##
## The two suites before this one pin what their fights *are*: The Scrap King's pins a deception,
## Runtime Error's pins an honesty. This fight's whole idea is a single number — load, which is
## `node_count / nodes_alive` — and almost everything below is an assertion about what that number
## is allowed to do.
##
## Three of those matter more than the rest, because all three are promises the class doc makes
## that nothing in the code would break if they stopped being true:
##
## 1. **The failures land at the same fractions for every player.** The pool is shared and nodes
##    blow out at even fractions of it, which is what stops "spread your damage evenly" from being
##    a line that holds the fight at load one and then skips its last two phases. Checked by
##    driving the pool down and counting bodies.
## 2. **The heat per second is the same at every load.** Four nodes venting every three seconds and
##    one node venting every 0.75 put the same amount of hot ground down; what changes is that it
##    concentrates. That is the arithmetic keeping the last phase survivable, and it is checked by
##    *counting vents in real time* at load one and at load four rather than by re-deriving the
##    division, which would only prove that division works.
## 3. **Nothing it puts on the floor is aimed at the player.** Every vent is centred on a node, so
##    every patch was announced by a body already on screen, and every patch starts cold. Checked
##    the way the player meets it: run the fight and catch each zone on the frame it appears.
##
## The third one was written the wrong way round first — as "it never vents under the player" — and
## the suite caught it doing exactly that, three times in forty-seven. The claim was false rather
## than the code being wrong: a node can be standing on the robot, because bodies on that team pass
## through it. What the fight actually promises is that it never *chooses* the player's feet, and
## that is what is checked here. A test that measured the appealing version of a rule instead of the
## true one would have had to be weakened later by somebody who did not know which of the two the
## fight was built on.
##
## The boss is damaged through its nodes rather than by reaching into its pool, because a node is
## the only thing a projectile can hit and the forwarding between them is exactly what could break.

const BOSS_SCENE := preload("res://scenes/bosses/cascade_failure.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")

const BOSS_CONFIG_PATH := "res://data/bosses/cascade_failure.tres"
const ENCOUNTER_PATH := "res://data/bosses/cascade_failure_encounter.tres"
const FLOOR_3_CONFIG_PATH := "res://data/floors/floor_3_data_center.tres"
const RIVET_PATH := "res://data/projectiles/rivet.tres"

## The room interior a boss arena actually is: 26x12 tiles. The ring is sized against this, so
## measuring it against anything else would be measuring the test's own arithmetic.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## What the fight is compressed to for the tests. The shipped numbers are tuned for a player's
## reading speed and a suite that waited them out would spend a minute proving what a second
## proves. The shipped values are checked as values in `_test_config_is_a_fight`; these only have
## to preserve the *relationships* the fight depends on — a vent still takes long enough to read,
## and the interval is still longer than the fill.
const TEST_VENT_INTERVAL := 0.6
const TEST_VENT_SECONDS := 0.4

## How many frames of node positions to keep, for the check that every vent was centred on a body.
##
## More than one, and the reason is the failure vent: a node blowing out drops a zone on the ground
## it is vacating and is gone from the rack in the same call, so "a node is standing there right
## now" would be a frame too strict — and would call the most clearly announced vent in the fight,
## the one where a body visibly exploded, the one unannounced one.
const TRACK_FRAMES := 8

## Long enough to cover a whole breath at the shipped `ring_breath_speed`, so the sweep test sees
## the ring at both extents rather than catching it mid-inhale.
const BREATH_SECONDS := 8.0

var _config: CascadeFailureConfig
var _arena: Node2D
var _boss: CascadeFailure
var _player: Player

## Zones seen so far, by instance id, so each one is inspected exactly once and on the frame it
## appeared. A count alone would not do: the interesting question about a vent is *where* it was
## put, and that is only answerable before the player has had time to walk away from it.
var _seen_zones: Dictionary[int, bool] = {}

## Where the nodes have stood over the last `TRACK_FRAMES` frames, oldest first.
var _node_tracks: Array[Vector2] = []


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as CascadeFailureConfig
	if not require(_config, "cascade_failure.tres loads as a CascadeFailureConfig"):
		return

	_test_config_is_a_fight()
	_test_the_hud_calls_it_by_its_name()
	_test_every_floor_can_draw_it()

	await _test_it_starts_as_a_whole_rack()
	await _test_nodes_fail_at_even_fractions_of_the_pool()
	await _test_the_player_chooses_which_node_fails()
	await _test_one_huge_hit_costs_more_than_one_node()
	await _test_every_node_damages_the_same_pool()
	await _test_the_bar_falls_and_never_refills()
	await _test_the_fight_ends_once()
	await _test_the_lines_degenerate_with_the_rack()
	await _test_the_rack_stays_inside_its_arena()
	await _test_the_breathing_sweeps_the_middle()
	await _test_the_heat_per_second_does_not_rise_with_load()
	await _test_every_vent_is_announced_by_a_body()
	await _test_the_floor_stays_walkable_at_every_load()
	await _test_the_last_node_comes_for_the_player()
	await _test_real_projectiles_drive_the_whole_fight()
	await _test_the_floor_spawns_it_in_a_real_boss_room()


# --- Configuration ------------------------------------------------------------


func _test_config_is_a_fight() -> void:
	check(_config.node_count >= 2, "the rack has nodes to lose (%d)" % _config.node_count)
	check(_config.max_health > 0.0, "and a pool to lose them from")
	check(
		_config.ring_inhale > 0.0 and _config.ring_inhale < 1.0,
		"the ring breathes rather than holding one radius (%.2f)" % _config.ring_inhale,
	)
	# A vent nobody can read is a trap, and this floor is not built out of traps. Half a second is
	# roughly the reaction time the rest of the game's telegraphs are written to.
	check(
		_config.vent_seconds >= 0.5,
		"a vent takes long enough to read (%.2fs)" % _config.vent_seconds,
	)
	check(
		_config.vent_tiles.x >= 1 and _config.vent_tiles.y >= 1,
		"a vent covers real ground (%s tiles)" % _config.vent_tiles,
	)
	# The last phase is a chase the player is meant to win on foot. Its threat is the trail, not
	# the body, and a node faster than the robot would make it the body.
	check(
		_config.runaway_speed < 160.0,
		"the last node cannot outrun the robot (%.0f against 160)" % _config.runaway_speed,
	)


func _test_the_hud_calls_it_by_its_name() -> void:
	var encounter := load(ENCOUNTER_PATH) as BossEncounter
	if not require(encounter, "the encounter loads"):
		return
	check(encounter.is_valid(), "and names a scene to instantiate")
	check(encounter.id == _config.id, "the encounter and the config agree on its id")
	check(not encounter.display_name.is_empty(), "the banner has something to say")
	check(not encounter.defeat_banner.is_empty(), "and so does the one for killing it")
	# Three phases, three entries — the first deliberately blank, since the fight opening is not a
	# change to announce. A fourth would be a banner for a phase that does not exist.
	check(
		encounter.phase_banners.size() == 3,
		"it has a banner slot per phase (%d)" % encounter.phase_banners.size(),
	)


## This boss used to have a floor of its own, and this test used to be the check that nobody added
## it to floor 1 "for variety". The reasoning was that the fight is written in the Data Center's
## visual language and so must not turn up before the floor that teaches it — and the fight itself
## does not bear that out. Every hazard it puts down is a `ThermalZone` that starts cold, climbs
## visibly for `vent_seconds`, and sits on ground the player is not obliged to be on; that is a
## telegraph read the same way on any floor. What the lock cost was the campaign's last fight, which
## was the same fight every run.
##
## So the assertion is inverted rather than deleted, and this is now the check that notices somebody
## quietly re-locking it — which would look like a fix if the pools drifted back to one entry.
func _test_every_floor_can_draw_it() -> void:
	var campaign := load("res://data/runs/main_campaign.tres") as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		var draws := false
		for encounter: BossEncounter in config.boss_pool:
			if encounter != null and encounter.id == _config.id:
				draws = true
		check(
			draws,
			"floor %d ('%s') may draw Cascade Failure" % [index + 1, config.id],
		)


# --- The rack -----------------------------------------------------------------


func _test_it_starts_as_a_whole_rack() -> void:
	await _begin()

	check(_boss.get_nodes_alive() == _config.node_count, "the fight opens with every node standing")
	check_near(_boss.get_load(), 1.0, "and at load one")
	check(_boss.get_phase() == CascadeFailure.Phase.NOMINAL, "in its first phase")
	check_near(_boss.get_health_ratio(), 1.0, "with a full bar")

	var bodies := 0
	for slot: int in _config.node_count:
		if _boss.get_node_at(slot) != null:
			bodies += 1
	check(bodies == _config.node_count, "and a body per slot (%d)" % bodies)

	await _teardown()


## The promise that keeps all three phases in every player's fight: the failures are a function of
## the pool and of nothing the player chooses.
##
## Walked down in small steps rather than jumped to each threshold, so a build that failed a node
## early — or late, or twice — is caught at the fraction where it went wrong rather than at the end.
func _test_nodes_fail_at_even_fractions_of_the_pool() -> void:
	await _begin()

	var slots := _config.node_count
	for step: int in 20:
		var ratio := 1.0 - float(step + 1) / 20.0
		_hurt_any(_boss.get_health() - _config.max_health * ratio)
		await advance_physics(2)

		var expected := clampi(ceili(ratio * float(slots)), 1, slots)
		if ratio <= 0.0:
			break
		check(
			_boss.get_nodes_alive() == expected,
			"at %.0f%% of the pool, %d nodes stand (%d do)"
				% [ratio * 100.0, expected, _boss.get_nodes_alive()],
		)
		check_near(
			_boss.get_load(),
			float(slots) / float(expected),
			"and the load is the rack divided between them (%.2f)" % _boss.get_load(),
		)

	await _teardown()


## What the player *does* get to decide. Damage is credited per node purely so that the one being
## pushed is the one that goes, which is how a player chooses the shape of the ring they are left
## with without choosing how long they fight it.
func _test_the_player_chooses_which_node_fails() -> void:
	for target: int in [1, 3]:
		await _begin()

		# A little into every node, so the choice is a preference rather than the only candidate,
		# and then the rest into the one that should go.
		for slot: int in _config.node_count:
			_hurt(slot, 1.0)
		_hurt(target, _boss.get_health() - _config.max_health * 0.74)
		await advance_physics(2)

		check(
			_boss.get_nodes_alive() == _config.node_count - 1,
			"pushing one node still costs exactly one node",
		)
		check(
			_boss.get_node_at(target) == null,
			"and it is the node that took the damage that goes (slot %d)" % target,
		)

		await _teardown()


## A hit big enough to cross two thresholds costs two nodes. The Scrap King floors damage at each
## boundary to protect its feigned death; this fight has no trick to protect, and a player who has
## deleted half the rack in one shot has earned that half.
func _test_one_huge_hit_costs_more_than_one_node() -> void:
	await _begin()

	_hurt(0, _config.max_health * 0.55)
	await advance_physics(2)

	check(
		_boss.get_nodes_alive() == 2,
		"one hit across two thresholds leaves two nodes (%d)" % _boss.get_nodes_alive(),
	)
	check(
		_boss.get_phase() == CascadeFailure.Phase.REROUTING,
		"and lands in the phase it earned rather than the one after the first",
	)

	await _teardown()


## The pool is the rack's, so which body absorbs a hit changes nothing about how much the fight has
## left. This is the check that would fail the day somebody gives the nodes health of their own.
func _test_every_node_damages_the_same_pool() -> void:
	await _begin()

	var before := _boss.get_health()
	_hurt(0, 3.0)
	_hurt(1, 3.0)
	_hurt(2, 3.0)
	await advance_physics(2)

	check_near(
		_boss.get_health(), before - 9.0, "three nodes hit for three each cost the rack nine"
	)

	await _teardown()


func _test_the_bar_falls_and_never_refills() -> void:
	await _begin()

	var readings: Array[float] = []
	var watcher := func(ratio: float) -> void: readings.append(ratio)
	EventBus.boss_health_changed.connect(watcher)

	for step: int in 6:
		_hurt_any(_config.max_health * 0.15)
		await advance_physics(2)

	EventBus.boss_health_changed.disconnect(watcher)

	var monotonic := true
	for index: int in range(1, readings.size()):
		if readings[index] > readings[index - 1] + 0.0001:
			monotonic = false
	check(readings.size() >= 6, "the bar is told about every hit (%d)" % readings.size())
	check(monotonic, "and only ever falls — no phase refills it")

	await _teardown()


func _test_the_fight_ends_once() -> void:
	await _begin()

	var defeats := [0]
	var watcher := func(_boss_node: Node) -> void: defeats[0] += 1
	EventBus.boss_defeated.connect(watcher)

	_hurt_any(_config.max_health * 2.0)
	await advance_physics(4)
	# And again, into a rack that no longer exists.
	_hurt_any(_config.max_health)
	await advance_physics(4)

	EventBus.boss_defeated.disconnect(watcher)
	check(defeats[0] == 1, "the fight is won exactly once (%d)" % defeats[0])
	check(_boss.get_nodes_alive() == 0, "and nothing is left standing")

	await _teardown()


## Four nodes close into a quadrilateral, three into a triangle, two share a single line, and one
## has nowhere to send load at all. The last phase looks and plays like a different fight without a
## rule being written for it, and this is that falling out of the geometry rather than being
## claimed.
func _test_the_lines_degenerate_with_the_rack() -> void:
	await _begin()

	var expected := {4: 4, 3: 3, 2: 1, 1: 0}
	for alive: int in [4, 3, 2, 1]:
		await _drive_to_nodes(alive)
		if _boss.get_nodes_alive() != alive:
			continue
		check(
			_boss.get_packet_positions().size() == expected[alive],
			"%d nodes carry %d packets (%d)"
				% [alive, expected[alive], _boss.get_packet_positions().size()],
		)

	await _teardown()


func _test_the_rack_stays_inside_its_arena() -> void:
	await _begin()

	var strays := 0
	for _frame: int in _frames(BREATH_SECONDS):
		await advance_physics(1)
		for slot: int in _config.node_count:
			var node := _boss.get_node_at(slot)
			if node != null and not ARENA.has_point(node.global_position):
				strays += 1
	check(strays == 0, "no node leaves the room over a whole breath (%d frames outside)" % strays)

	await _teardown()


## The reason the ring breathes at all: a fixed radius leaves a permanently safe centre, and a boss
## with a safe centre — on the floor about not standing still — would be arguing with its own room.
##
## Measured as the closest any node comes to the middle over one breath, against the closest it
## would come if the ring never contracted. A build that quietly stopped breathing would still pass
## every other check in this suite and would have removed the fight's whole reason to move.
func _test_the_breathing_sweeps_the_middle() -> void:
	await _begin()

	var centre := ARENA.get_center()
	var closest := INF
	for _frame: int in _frames(BREATH_SECONDS):
		await advance_physics(1)
		for slot: int in _config.node_count:
			var node := _boss.get_node_at(slot)
			if node != null:
				closest = minf(closest, node.global_position.distance_to(centre))

	# What the ring would never come inside of if `ring_inhale` were one. Anything at or beyond it
	# means the middle was never swept.
	var fixed_reach := minf(_config.ring_radius.x, _config.ring_radius.y)
	check(
		closest < fixed_reach * 0.75,
		"the rack closes on the middle of the arena (%.0f px, against %.0f at a fixed radius)"
			% [closest, fixed_reach],
	)

	await _teardown()


# --- Heat ---------------------------------------------------------------------


## The arithmetic that keeps the last phase survivable, measured rather than re-derived.
##
## Per node the interval is `vent_interval / load`, and there are `node_count / load` nodes, so the
## rack's total vent rate is the same at every load. Counting them in real time is the version of
## that claim which fails if somebody scales the interval by something other than load, or adds a
## second vent source to the last phase because it felt thin.
func _test_the_heat_per_second_does_not_rise_with_load() -> void:
	await _begin()

	var window := TEST_VENT_INTERVAL * 6.0
	var whole := await _count_vents_over(window)

	await _drive_to_nodes(1)
	var last := await _count_vents_over(window)

	check(whole > 0, "a whole rack vents (%d in %.1fs)" % [whole, window])
	check(last > 0, "and so does a single node under full load (%d)" % last)
	# A quarter either way. The clocks are staggered and the window does not divide the interval
	# exactly, so a strict equality here would be a check on the sampling rather than on the rate.
	check(
		absf(float(last - whole)) <= maxf(float(whole) * 0.25, 1.0),
		"one node at full load vents as often as four did (%d against %d)" % [last, whole],
	)

	await _teardown()


## The fairness rule, checked the way the player meets it. Every zone is caught on the frame it
## appears and asked two questions: was a node standing in it, and was it cold?
##
## Both halves are the warning. A vent centred on a node is a hazard the player was shown before it
## existed; a vent that starts cold is one they have the whole of `vent_seconds` to leave. A boss
## that broke either would throw no error and fail no other check in this file — it would simply
## put damage where no warning had been, on the one floor whose entire promise is that heat is
## something you can see coming.
func _test_every_vent_is_announced_by_a_body() -> void:
	await _begin()

	var caught := 0
	var orphaned := 0
	var born_hot := 0
	for phase_target: int in [4, 2, 1]:
		await _drive_to_nodes(phase_target)
		for _frame: int in _frames(TEST_VENT_INTERVAL * 4.0):
			_track_nodes()
			await advance_physics(1)
			# The robot keeps moving, because a stationary player is the easy case: parked in a
			# corner it would sit clear of the ring by accident. Circling puts it where the nodes
			# are, which is the only place this rule can be tested.
			_orbit_player(0.06)
			for zone: ThermalZone in _new_zones():
				caught += 1
				# Grown by a pixel: `_drop_vent` clamps a rect at the wall back into the arena, so a
				# node right against the edge ends up exactly on its boundary rather than inside it.
				if not _is_on_a_node(zone.get_rect().grow(1.0)):
					orphaned += 1
				# A quarter, not zero. Zones are inspected on the frame after they appear at the
				# earliest, and a couple of frames later when one arrives during a phase change, so
				# a strict zero here would be measuring the polling rather than the boss. What it
				# has to catch is a vent that appears already dangerous.
				if zone.get_heat() > 0.25:
					born_hot += 1

	check(caught > 0, "the rack put heat on the floor to inspect (%d vents)" % caught)
	check(
		orphaned == 0,
		"and every one of them was centred on a node (%d of %d were not)" % [orphaned, caught],
	)
	check(
		born_hot == 0,
		"and every one started cold, so it can be walked out of (%d of %d did not)"
			% [born_hot, caught],
	)

	await _teardown()


## What the fight is allowed to take away, measured rather than reasoned about.
##
## The rack's total vent rate does not rise with load — see the check above this one — but "the rate
## is constant" and "the floor stays walkable" are different claims, and only the second one is what
## keeps the last phase winnable. This measures the second directly: the hot ground on screen, every
## frame, at every load, as a fraction of the arena.
##
## Summed rather than unioned, which overstates the coverage wherever two zones overlap. That is the
## safe direction for a ceiling — the real figure is never worse than the one asserted here.
func _test_the_floor_stays_walkable_at_every_load() -> void:
	await _begin()

	var arena_area := ARENA.size.x * ARENA.size.y
	var worst := 0.0
	for phase_target: int in [4, 3, 2, 1]:
		await _drive_to_nodes(phase_target)
		for _frame: int in _frames(TEST_VENT_INTERVAL * 5.0):
			await advance_physics(1)
			worst = maxf(worst, _hot_area() / arena_area)

	# A quarter. Well clear of the point at which a route across the room stops existing, and low
	# enough that a build creeping toward it — a second vent source, a longer fill, a bigger
	# footprint — trips this before a player has to find out by dying to it.
	check(
		worst < 0.25,
		"hot ground never covers more than a quarter of the arena (peaked at %.0f%%)"
			% (worst * 100.0),
	)

	await _teardown()


func _test_the_last_node_comes_for_the_player() -> void:
	await _begin()
	await _drive_to_nodes(1)

	var node := _boss.get_node_at(_last_slot())
	if not require(node, "one node is left standing"):
		await _teardown()
		return

	check(_boss.get_phase() == CascadeFailure.Phase.RUNAWAY, "and the fight is in its last phase")
	check(_boss.get_packet_positions().is_empty(), "with no lines left to move load along")

	var before := node.global_position.distance_to(_player.global_position)
	await advance_physics(_frames(1.0))
	var after := node.global_position.distance_to(_player.global_position)

	check(
		after < before,
		"the last node closes on the player (%.0f px, was %.0f)" % [after, before],
	)

	await _teardown()


# --- Integration --------------------------------------------------------------


## The whole fight driven by real player projectiles rather than by synthesised damage, because
## every check above reaches the pool through `took_damage` and a node whose collision shape or
## layer was wrong would satisfy all of them while being impossible to shoot.
func _test_real_projectiles_drive_the_whole_fight() -> void:
	await _begin()

	var before := _boss.get_health()
	var fired := 0
	for _shot: int in 40:
		var slot := _first_living_slot()
		var node := _boss.get_node_at(slot)
		if node == null:
			break
		_shoot(node, 4.0)
		fired += 1
		await advance_physics(8)

	check(fired > 0, "there was something to shoot at")
	check(
		_boss.get_health() < before,
		"real rivets reach the pool (%.1f, was %.1f)" % [_boss.get_health(), before],
	)
	check(
		_boss.get_nodes_alive() < _config.node_count,
		"and shooting it blows nodes out (%d left)" % _boss.get_nodes_alive(),
	)

	await _teardown()


## The floor's own boss room, built by the generator, with the encounter the floor's pool names.
## Everything above builds the boss by hand; this is the check that the campaign hands the same
## thing to a player who walks in.
func _test_the_floor_spawns_it_in_a_real_boss_room() -> void:
	var config := load(FLOOR_3_CONFIG_PATH) as FloorConfig
	if not require(config, "the Data Center's config loads"):
		return

	var holder := Node2D.new()
	add_child(holder)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = config
	holder.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	holder.add_child(player)
	await advance_physics(1)

	RunManager.begin_run(31415)
	if floor_node.build(player, 20250814):
		var encounter := floor_node.get_boss_encounter()
		if require(encounter, "the floor drew a boss"):
			check(encounter.id == _config.id, "and it is Cascade Failure ('%s')" % encounter.id)
	else:
		fail("the Data Center generates from seed 20250814")

	holder.queue_free()
	await advance_physics(2)


# --- Harness ------------------------------------------------------------------


func _begin() -> void:
	RunManager.begin_run(90210)
	_seen_zones.clear()
	_node_tracks.clear()

	_arena = Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	_arena.add_child(container)
	add_child(_arena)

	_player = PLAYER_SCENE.instantiate()
	_player.position = ARENA.get_center() + Vector2(0.0, 70.0)
	_arena.add_child(_player)
	# The boss is what is being measured, not the robot's survival — and this fight puts heat
	# across most of the arena on purpose.
	_player.get_health_component().configure(9999.0, 0.0)

	_boss = _new_boss()
	_arena.add_child(_boss)
	_boss.begin(ARENA)
	await advance_physics(2)


func _teardown() -> void:
	_arena.queue_free()
	await advance_physics(2)


## The shipped fight with its clocks wound in. Everything that decides *shape* — the ring, the
## load arithmetic, the failure thresholds — is left exactly as shipped, because that is what the
## suite is here to measure.
func _new_boss() -> CascadeFailure:
	var boss: CascadeFailure = BOSS_SCENE.instantiate()
	var fast: CascadeFailureConfig = _config.duplicate()
	fast.vent_interval = TEST_VENT_INTERVAL
	fast.vent_seconds = TEST_VENT_SECONDS
	boss.config = fast
	return boss


## Damages the boss the way a projectile does: through a node, which forwards it.
func _hurt(slot: int, amount: float) -> void:
	var node := _boss.get_node_at(slot)
	if node != null:
		node.took_damage.emit(DamageInfo.new(amount))


## The same, into whichever node is still standing. For the checks that are about the pool rather
## than about which body took it.
func _hurt_any(amount: float) -> void:
	if amount > 0.0:
		_hurt(_first_living_slot(), amount)


## Drives the pool down until `alive` nodes are left, computed from the threshold rather than
## guessed, so this still works if `node_count` moves.
func _drive_to_nodes(alive: int) -> void:
	# Before the damage, because the failure it is about to cause drops a vent on the ground the
	# failing node is standing on right now.
	_track_nodes()
	var slots := _config.node_count
	# Halfway into the band that leaves `alive` standing, so nothing that follows sits on a
	# boundary. The band for `alive` runs from `(alive - 1) / slots` up to `alive / slots`.
	var ratio := (float(alive) - 0.5) / float(slots)
	var wanted := _config.max_health * ratio
	if _boss.get_health() > wanted:
		_hurt_any(_boss.get_health() - wanted)
	await advance_physics(2)


## Zones that have appeared in the session's container since the last time this was asked. Driven
## zones free themselves after venting, so a plain count of the container would fall as well as
## rise; tracking ids is what makes "new" mean new.
func _new_zones() -> Array[ThermalZone]:
	var fresh: Array[ThermalZone] = []
	var container := get_tree().get_first_node_in_group(ProjectileFactory.CONTAINER_GROUP)
	if container == null:
		return fresh
	for child: Node in container.get_children():
		var zone := child as ThermalZone
		if zone == null or _seen_zones.has(zone.get_instance_id()):
			continue
		_seen_zones[zone.get_instance_id()] = true
		fresh.append(zone)
	return fresh


## Records where every living node is standing this frame, dropping the oldest reading once the
## window is full.
func _track_nodes() -> void:
	for slot: int in _config.node_count:
		var node := _boss.get_node_at(slot)
		if node != null:
			_node_tracks.append(node.global_position)
	var window := TRACK_FRAMES * _config.node_count
	while _node_tracks.size() > window:
		_node_tracks.remove_at(0)


## Whether a node has stood inside `rect` recently. See `TRACK_FRAMES`.
func _is_on_a_node(rect: Rect2) -> bool:
	for position: Vector2 in _node_tracks:
		if rect.has_point(position):
			return true
	return false


## Total ground currently covered by the boss's vents, in square pixels.
func _hot_area() -> float:
	var area := 0.0
	var container := get_tree().get_first_node_in_group(ProjectileFactory.CONTAINER_GROUP)
	if container == null:
		return area
	for child: Node in container.get_children():
		var zone := child as ThermalZone
		if zone != null:
			area += zone.get_rect().size.x * zone.get_rect().size.y
	return area


func _count_vents_over(seconds: float) -> int:
	var _drain := _new_zones()
	var total := 0
	for _frame: int in _frames(seconds):
		await advance_physics(1)
		total += _new_zones().size()
	return total


## Walks the player around the middle of the arena, so the vent check is asked about a robot that
## is where the fight is rather than one parked in a corner.
func _orbit_player(step: float) -> void:
	var centre := ARENA.get_center()
	var offset := _player.global_position - centre
	if offset.is_zero_approx():
		offset = Vector2.RIGHT * 40.0
	_player.global_position = centre + offset.rotated(step)


func _first_living_slot() -> int:
	for slot: int in _config.node_count:
		if _boss.get_node_at(slot) != null:
			return slot
	return 0


func _last_slot() -> int:
	return _first_living_slot()


## Fires a real player projectile into `target` from just outside it.
func _shoot(target: Node2D, damage: float) -> void:
	if target == null:
		return
	var shot := (load(RIVET_PATH) as ProjectileConfig).spawn_copy()
	shot.damage = damage
	var origin := target.global_position - Vector2(36.0, 0.0)
	var shooter := Node2D.new()
	_arena.add_child(shooter)
	ProjectileFactory.spawn_configured(
		shooter, shot, Vector2.RIGHT, origin, Teams.Id.PLAYER, shooter
	)


## Physics frames covering `seconds`, plus a couple so a boundary lands inside the window rather
## than exactly on its edge.
func _frames(seconds: float) -> int:
	return int(seconds * 60.0) + 2

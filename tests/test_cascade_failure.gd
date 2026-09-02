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
## 3. **Every patch of heat starts cold.** Wherever a vent lands — under a node, under the robot,
##    in an empty corner — it fills from nothing over `vent_seconds`, so there is no hazard in this
##    fight the player could not have walked out of. Checked the way the player meets it: run the
##    fight and catch each zone on the frame it appears.
##
## The third one has been written the wrong way round twice, which is worth recording because both
## mistakes were the same mistake.
##
## It began as "it never vents under the player", and the suite caught the fight doing exactly that,
## three times in forty-seven: a node can be *standing* on the robot, because bodies on that team
## pass through it. So it was weakened to "it never *chooses* the player's feet" — true at the time,
## and still the wrong thing to have pinned. It described where the heat went rather than why the
## heat was fair, and pinning it made the fight's own sentence unsayable: the boss whose subject is
## *keep moving* could not put anything under a player who had stopped, so a player who found ground
## the ring did not sweep was free to stand on it and shoot.
##
## The fight now aims and leads (see `CascadeFailure._step_aimed_vent` and `_step_lead_vent`) and
## the promise is the one that was doing the work all along: the telegraph, not the aim. That is
## checked below on every vent from every source, and the two aiming sources get a check each that
## they exist at all — because a promise about telegraphs is trivially kept by a boss that has
## stopped venting.
##
## Nothing in this fight is random any more, which is why the check that used to sample thirty
## intervals of a uniform draw is gone. A lead vent lands at one computable point, so the check that
## replaced it asserts that point directly rather than a distribution over it.
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

## What the rack's own vent clock is compressed to for the tests, and the only number here that is
## chosen. The shipped clocks are tuned for a player's reading speed, and a suite that waited them
## out would spend a minute proving what a second proves; the shipped values are checked as values
## in `_test_config_is_a_fight`.
##
## Every other vent clock is derived from this one by the ratio it represents — see `_new_boss`.
## That was not always true: the fill used to be its own chosen number, which quietly gave the
## suite a fight with a third more hot ground on screen at once than the shipped one has, and it
## was `_test_the_floor_stays_walkable_at_every_load` that noticed by creeping toward its ceiling
## while the real fight sat nowhere near it. A compression that changes a ratio is not a
## compression.
const TEST_VENT_INTERVAL := 0.6

## Long enough to cover a whole breath at the shipped `ring_breath_speed`, so the sweep test sees
## the ring at both extents rather than catching it mid-inhale.
const BREATH_SECONDS := 8.0

## A corner the ring cannot reach: the ellipse at full extension spans x 58-358 and y 34-158, and a
## 3x3 vent centred anywhere on it never covers this point. So a patch that lands here came from
## one of the two clocks that follow the robot, and with the robot standing still those two are the
## same clock: a stationary robot is led nowhere, so the lead patch lands on the square the aimed
## one chose. Both aimed-vent checks stand the robot here for that reason, and the ramp check
## silences the lead clock so that the count it takes is the aimed one alone.
##
## Absolute, which is the same thing as inset from the corner: `ARENA` starts at the origin.
const UNREACHABLE_CORNER := Vector2(20.0, 20.0)

var _config: CascadeFailureConfig
var _arena: Node2D
var _boss: CascadeFailure
var _player: Player

## Zones seen so far, by instance id, so each one is inspected exactly once and on the frame it
## appeared. A count alone would not do: the interesting question about a vent is *where* it was
## put, and that is only answerable before the player has had time to walk away from it.
var _seen_zones: Dictionary[int, bool] = {}


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
	await _test_every_vent_starts_cold()
	await _test_it_heats_the_ground_the_player_is_standing_on()
	await _test_each_failure_tightens_the_clock_that_aims()
	await _test_it_heats_the_ground_the_player_is_heading_for()
	await _test_a_stationary_robot_is_led_nowhere()
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
	# Both aimed and lead clocks have to be longer than the fill, and that is the tuning that
	# makes "keep moving" a rhythm rather than a treadmill: the ground the player is standing on has
	# to be cold some of the time, or moving stops being a decision and becomes the only input.
	# Asked of the *tightest* end of the aimed ramp rather than of its resting value, because the
	# tightest end is the one that can break it: the clock steps down one node at a time and the
	# fight is only as fair as the last step leaves it.
	check(
		_config.aimed_vent_interval_runaway > _config.vent_seconds,
		"the ground under the robot is cold between aimed vents at the end too (%.2fs, %.2fs fill)"
			% [_config.aimed_vent_interval_runaway, _config.vent_seconds],
	)
	# A ramp that goes the other way would be a fight that relaxes as it escalates.
	check(
		_config.aimed_vent_interval_runaway <= _config.aimed_vent_interval,
		"and losing a node never buys the player a slower clock (%.2fs from %.2fs)"
			% [_config.aimed_vent_interval_runaway, _config.aimed_vent_interval],
	)
	check(
		_config.lead_vent_interval > _config.vent_seconds,
		"and the ground ahead of them is too (%.2fs against a %.2fs fill)"
			% [_config.lead_vent_interval, _config.vent_seconds],
	)
	# The lead is short of the fill, and that is the number that decides whether the player reads a
	# boss predicting them or a boss painting the walls. At the robot's 160 px/s a lead of
	# `vent_seconds` is 256 pixels, which clamps into the far wall on most headings in a 416-pixel
	# room. See `CascadeFailureConfig.lead_seconds`.
	check(
		_config.lead_seconds > 0.0 and _config.lead_seconds < _config.vent_seconds,
		"the lead is real and shorter than the fill it is read against (%.2fs against %.2fs)"
			% [_config.lead_seconds, _config.vent_seconds],
	)
	# Two vent widths, give or take, at the robot's walking speed. Close enough to be visibly about
	# the robot; far enough that holding a heading walks into it.
	var lead_px := _config.lead_seconds * 160.0
	var vent_px := float(_config.vent_tiles.x * Room.TILE_SIZE)
	check(
		lead_px > vent_px * 0.5 and lead_px < vent_px * 3.0,
		"and it lands between half a vent and three ahead of the chassis (%.0fpx against %.0fpx)"
			% [lead_px, vent_px],
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
## that claim which fails if somebody scales the interval by something other than load.
##
## It counts *every* vent, not only the ones the nodes drop, and that is what makes it still the
## right check now that the fight aims and leads as well. The lead clock is flat and the aimed clock
## steps down by a second across the whole fight — see `CascadeFailureConfig.aimed_vent_interval` —
## so adding them moved the whole line up and left it very nearly level, which is why the tolerance
## below is a quarter rather than a tenth. A source that *quadrupled* alongside the rack would show
## here as a last phase putting four times the heat down, which is what this arithmetic exists to
## forbid; one second on one of three clocks is nowhere near it.
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


## The fairness rule, checked the way the player meets it: every zone is caught on the frame it
## appears and asked whether it was cold.
##
## This is the whole warning, and since the fight started aiming it is the only warning. A vent that
## starts cold is one the player has the whole of `vent_seconds` to leave, wherever it landed and
## whoever it was meant for. A boss that broke it would throw no error and fail no other check in
## this file — it would simply put damage where no warning had been, on the one floor whose entire
## promise is that heat is something you can see coming.
##
## Asked of every vent from every source, deliberately. The aimed vent is the one most likely to be
## "improved" into landing hot, because that is what aiming usually means; this is the check that
## says no.
##
## It also asserts the vents land inside the arena. `_drop_vent` clamps them, and a clamp that
## stopped working would paint half a hazard through a wall — visible to nobody reading the code and
## obvious to anyone playing it.
func _test_every_vent_starts_cold() -> void:
	await _begin()

	var caught := 0
	var born_hot := 0
	var outside := 0
	var walls := ARENA.grow(1.0)
	for phase_target: int in [4, 2, 1]:
		await _drive_to_nodes(phase_target)
		for _frame: int in _frames(TEST_VENT_INTERVAL * 4.0):
			await advance_physics(1)
			# The robot keeps moving, because a stationary player is the easy case: parked in a
			# corner it would sit clear of the ring by accident. Circling puts it where the nodes
			# are, which is where the most vents of every kind land at once.
			_orbit_player(0.06)
			for zone: ThermalZone in _new_zones():
				caught += 1
				# A quarter, not zero. Zones are inspected on the frame after they appear at the
				# earliest, and a couple of frames later when one arrives during a phase change, so
				# a strict zero here would be measuring the polling rather than the boss. What it
				# has to catch is a vent that appears already dangerous.
				if zone.get_heat() > 0.25:
					born_hot += 1
				if not walls.encloses(zone.get_rect()):
					outside += 1

	check(caught > 0, "the rack put heat on the floor to inspect (%d vents)" % caught)
	check(
		born_hot == 0,
		"and every one started cold, so it can be walked out of (%d of %d did not)"
			% [born_hot, caught],
	)
	check(
		outside == 0,
		"and every one landed inside the arena (%d of %d did not)" % [outside, caught],
	)

	await _teardown()


## The half of the fight the ring cannot do, and the reason the aimed vent exists: a player who
## stops moving is charged for it wherever in the room they stopped.
##
## Parked deliberately in a corner the ring never reaches, which is the ground that used to be a
## free firing position. A vent still has to arrive there, and it has to arrive *centred* on the
## robot rather than led — a boss that aimed where the player was going would be a boss whose
## telegraph the player cannot answer by standing still, and standing still has to remain a real
## (bad) choice rather than an impossible one.
func _test_it_heats_the_ground_the_player_is_standing_on() -> void:
	await _begin()

	var expected := 6
	var counts := await _count_vents_under_the_robot(
		UNREACHABLE_CORNER, _boss.config.aimed_vent_interval * float(expected + 1)
	)

	check(counts.y > 0, "the fight put heat down while the robot stood still (%d vents)" % counts.y)
	# A count rather than "at least one", because at least one is a check a stray clock could
	# pass on its own. Two thirds of the aimed vents the window is long enough for, which leaves
	# room for the polling and for one landing across a frame boundary but none for the aiming
	# having quietly stopped.
	check(
		counts.x >= expected * 2 / 3,
		"and the ground the robot was standing on was heated repeatedly (%d of %d vents, over %d)"
			% [counts.x, counts.y, expected * 2 / 3],
	)

	await _teardown()


## Losing a node is felt in the one clock that is about the player, and that is what this counts:
## the same robot, in the same corner the ring cannot reach, with the whole rack up and then with
## half of it gone.
##
## Counted rather than read off `get_aimed_vent_interval`, for the reason the vent-rate check above
## is counted: a getter returning a smaller number proves the getter. What can actually break here
## is the clock being *reset* from `config.aimed_vent_interval` when it fires — which is the shape
## this code had before the ramp existed, and which passes every other check in this file.
##
## **Two nodes rather than one, and that is not timidity.** With a single node left the fight is a
## chase: the node walks onto a robot that has stopped and lays its own trail across it, and the
## corner stops being ground only the aimed clock can reach. Measured there, the covered count
## quintuples — a number that would still quintuple with the ramp deleted, which makes it no check
## at all. Two nodes is the furthest point at which the ring is still a ring, so the corner is still
## the aimed clock's alone, and it is two thirds of the way along the ramp: three seconds to 2.33.
##
## The rise asserted is a seventh against an expected quarter. The slack is for the window dividing
## neither interval exactly and for the one lead vent the fight opens on; what it does not leave
## room for is the ramp having gone flat.
func _test_each_failure_tightens_the_clock_that_aims() -> void:
	await _begin()

	# The lead clock is silenced for the length of this check. A robot pinned in a corner has no
	# velocity to lead, so the lead patch collapses onto the square the aimed clock is already
	# choosing — see `CascadeFailureConfig.lead_seconds` — and left running it would add the same
	# flat count to both halves of the comparison and flatten the ramp this test exists to measure.
	# The half-interval the fight opens on still lands one patch here, which is the slack above.
	_boss.config.lead_vent_interval = 1_000_000.0

	# Long enough that a count is a rate: thirty intervals, so the whole rack is expected to land
	# about thirty patches here and half a rack about thirty-nine, and one vent either side of a
	# frame boundary cannot decide the check.
	var window := _boss.config.aimed_vent_interval * 30.0
	var whole := await _count_vents_under_the_robot(UNREACHABLE_CORNER, window)

	await _drive_to_nodes(2)
	var half := await _count_vents_under_the_robot(UNREACHABLE_CORNER, window)

	check(whole.x > 0, "the whole rack aims at a robot that has stopped (%d patches)" % whole.x)
	check(
		float(half.x) >= float(whole.x) * 1.15,
		"and two failures later it aims at it more often (%d against %d in the same window)"
			% [half.x, whole.x],
	)

	await _teardown()


## The other half of the pincer, and the reason the lead vent replaced a die roll: heat arrives in
## front of a robot that is holding a heading.
##
## The robot is driven along a fixed heading at its own walking speed rather than parked, because a
## parked robot has no velocity to lead and the lead vent deliberately collapses onto the aimed one
## — see `CascadeFailureConfig.lead_seconds`. What is measured is the vents that land *ahead*: the
## offset from the robot to the patch, projected onto the heading, against the lead the config asks
## for.
##
## Held to a heading that runs along the arena's long axis and starts from the far side of it, so
## the whole window is spent with real room in front of the robot. A heading into a nearby wall
## would be measuring `_drop_vent`'s clamp instead of the lead.
##
## Deliberately not a check that *every* vent leads. Three clocks are putting heat down and only one
## of them is this one; the rack's own nodes and the aimed vent land elsewhere by design. What must
## be true is that patches keep arriving in front of the robot, which no other source in the fight
## can produce.
func _test_it_heats_the_ground_the_player_is_heading_for() -> void:
	await _begin()

	var heading := Vector2.RIGHT
	var speed := 160.0
	var start := Vector2(ARENA.position.x + 40.0, ARENA.get_center().y)
	_player.global_position = start

	var expected := 5
	var ahead := 0
	var seen := 0
	# Walked rather than teleported: `velocity` is what the boss reads, so a robot moved by
	# assignment alone would be standing still as far as the lead is concerned.
	for _frame: int in _frames(_boss.config.lead_vent_interval * float(expected + 1)):
		await advance_physics(1)
		_player.velocity = heading * speed
		_player.global_position = Vector2(
			minf(_player.global_position.x, ARENA.end.x - 60.0), start.y
		)
		var where := _player.global_position
		for zone: ThermalZone in _new_zones():
			seen += 1
			var reach := (zone.get_rect().get_center() - where).dot(heading)
			# Half a lead clear of the chassis. Far enough that neither the aimed vent, which is
			# centred, nor a node standing beside the robot can be counted as having led it.
			if reach > speed * _boss.config.lead_seconds * 0.5:
				ahead += 1

	check(seen > 0, "the fight put heat down while the robot held a heading (%d vents)" % seen)
	check(
		ahead >= expected * 2 / 3,
		"and it kept landing in front of it (%d of %d vents led, over %d)"
			% [ahead, seen, expected * 2 / 3],
	)

	await _teardown()


## And it stops leading when there is nothing to lead. A robot standing still is heated where it
## stands, by both clocks, which is the one state in which the fight offers no choice of which vent
## to answer.
##
## Parked in the same corner the aimed-vent check uses — ground the ellipse at full extension never
## covers — so a patch landing on the robot came from a clock that aims and not from a node that
## wandered past. What separates this from that check is the *count*: with the lead vent collapsed
## onto the aimed one, a stationary robot is covered by both, so the ground under it is heated more
## often than the aimed clock alone could manage.
func _test_a_stationary_robot_is_led_nowhere() -> void:
	await _begin()

	var corner := ARENA.position + Vector2(20.0, 20.0)
	_player.global_position = corner
	_player.velocity = Vector2.ZERO

	# Long enough for both clocks to come round several times each.
	var window := maxf(_boss.config.aimed_vent_interval, _boss.config.lead_vent_interval) * 4.0
	var covered := 0
	var seen := 0
	for _frame: int in _frames(window):
		await advance_physics(1)
		_player.global_position = corner
		_player.velocity = Vector2.ZERO
		for zone: ThermalZone in _new_zones():
			seen += 1
			if zone.get_rect().has_point(corner):
				covered += 1

	check(seen > 0, "the fight put heat down to inspect (%d vents)" % seen)
	# Both clocks run four times in the window; two thirds of one of them is the floor, which no
	# single aiming source could clear on its own if the other had stopped aiming.
	var floor_count := int(window / maxf(_boss.config.aimed_vent_interval, 0.001)) * 2 / 3
	check(
		covered >= maxi(floor_count, 2),
		"and standing still was charged for by both clocks at once (%d of %d vents, over %d)"
			% [covered, seen, maxi(floor_count, 2)],
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
##
## **The margin is no longer generous, and that is a fact worth carrying rather than hiding.** The
## fight used to peak around thirteen percent here; the aimed and lead clocks put it at twenty,
## against a ceiling of twenty-five. Two of those five remaining points are an artefact of the
## compression — the 0.18s vent flash is a fixed cost that does not wind down with the clocks, so a
## wound-in zone spends proportionally longer on screen than a shipped one, and the shipped fight
## measures nearer eleven percent. What is left is still real headroom, but it is headroom a third
## vent source would spend. Anyone adding one should expect to move a rate down to pay for it.
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
##
## Every vent clock is wound by **one ratio** rather than each being given a chosen number. What the
## fight's fairness rests on is the relationships between them — the aimed and lead clocks
## against the rack's own, and all of them against the fill, which is what decides how many patches
## are on the floor at once. Winding one down without the others leaves this suite measuring a fight
## nobody plays. It also means a fourth vent source added tomorrow is one line here rather than a
## silent gap in every check below.
func _new_boss() -> CascadeFailure:
	var boss: CascadeFailure = BOSS_SCENE.instantiate()
	var fast: CascadeFailureConfig = _config.duplicate()
	var winding := TEST_VENT_INTERVAL / maxf(_config.vent_interval, 0.001)
	fast.vent_interval = TEST_VENT_INTERVAL
	fast.aimed_vent_interval = _config.aimed_vent_interval * winding
	# Both ends of the aimed ramp, by the same ratio, so the wound fight tightens by the fraction
	# the shipped one does. Winding only the resting end would leave the suite measuring a ramp
	# that gets *shallower* as the clocks come down, which is the opposite of the thing under test.
	fast.aimed_vent_interval_runaway = _config.aimed_vent_interval_runaway * winding
	fast.lead_vent_interval = _config.lead_vent_interval * winding
	fast.vent_seconds = _config.vent_seconds * winding
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


## Parks the robot at `at` for `seconds` and counts what lands on it: `x` is the vents that covered
## the point it was standing on, `y` is every vent the fight put down in the window.
##
## The pair rather than either half, because both checks that use this need both numbers — the
## interesting figure is the covered count, and the total is what says a covered count of zero means
## "it stopped aiming" rather than "it stopped venting".
##
## The player is pinned every frame rather than once: `move_and_slide` runs on the robot whatever
## the test wants, and a player that had drifted a few pixels would turn a centred vent into a near
## miss.
func _count_vents_under_the_robot(at: Vector2, seconds: float) -> Vector2i:
	var _drain := _new_zones()
	var counts := Vector2i.ZERO
	for _frame: int in _frames(seconds):
		await advance_physics(1)
		_player.global_position = at
		_player.velocity = Vector2.ZERO
		for zone: ThermalZone in _new_zones():
			counts.y += 1
			if zone.get_rect().has_point(at):
				counts.x += 1
	return counts


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

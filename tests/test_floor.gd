extends TestCase
## Checks the floor generator against spec section 9's hard requirements.
##
## This is the highest-value suite in the project. Floor generation is the one system whose
## bugs are *invisible* while playing: a floor with an unreachable room or a treasure room
## sitting on the only route onward looks completely normal until the specific seed that
## produces it comes up, which might be the hundredth run. The invariants are exact, so they
## are cheap to assert and expensive to discover by hand.
##
## Every requirement is checked across many seeds rather than one, because "works on the seed
## I happened to try" is exactly the failure mode here.

const FLOOR_CONFIG_PATH := "res://data/floors/floor_1_help_desk.tres"
const FLOOR_2_CONFIG_PATH := "res://data/floors/floor_2_development.tres"
const FLOOR_3_CONFIG_PATH := "res://data/floors/floor_3_data_center.tres"
const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"

## Seeds to sweep. Enough that a rare structural bug has to be very rare to survive.
const SEED_COUNT := 120

var _config: FloorConfig

## Room ids `EventBus.room_entered` reported while a descent was in progress. See
## `_test_a_descent_enters_only_the_new_floors_start_room`.
var _entered_during_descent: Array[int] = []


const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func run() -> void:
	_config = load(FLOOR_CONFIG_PATH) as FloorConfig
	if not require(_config, "floor_1_help_desk.tres loads as a FloorConfig"):
		return

	_test_config_has_content()
	_test_generation_is_deterministic()
	_test_invariants_across_seeds()
	_test_room_geometry_matches_the_grid()
	_test_templates_keep_doorways_clear()
	_test_layout_rejects_overlap()
	_test_generator_refuses_impossible_configs()
	_test_forced_enemies_never_exceed_their_spawn_points()
	_test_combat_templates_skew_easier_near_the_start()
	_test_every_authored_combat_room_reaches_a_player()
	_test_every_rostered_enemy_reaches_a_player()
	_test_the_data_centers_own_enemies_turn_up_in_it()
	_test_no_template_can_strand_a_chassis()
	_test_each_floor_looks_and_sounds_like_itself()
	await _test_a_duct_stops_a_chassis_and_not_a_shot()
	await _test_a_run_never_fights_the_same_boss_twice()
	await _test_walking_into_a_room_buys_a_moment_of_grace()
	await _test_the_doorway_window_is_not_shown()
	await _test_a_room_wears_its_floors_theme()
	await _test_repair_cells_drop_on_every_third_clear()
	await _test_boss_defeat_advances_to_the_next_floor_and_only_the_last_wins()
	await _test_a_descent_enters_only_the_new_floors_start_room()
	await _test_five_boundaries_leave_exactly_one_floor()
	await _test_nothing_from_a_floor_survives_its_boundary()
	await _test_a_boundary_keeps_run_state_and_resets_floor_state()
	await _test_an_ungeneratable_destination_keeps_the_current_floor()
	_greybox.clean_up()


func _test_config_has_content() -> void:
	check(_config.room_count >= 2, "the floor asks for at least two rooms")
	check(not _config.start_templates.is_empty(), "the floor has a start template")
	check(not _config.combat_templates.is_empty(), "the floor has combat templates")
	check(not _config.treasure_templates.is_empty(), "the floor has a treasure template")
	check(not _config.shop_templates.is_empty(), "the floor has a shop template")
	check(not _config.boss_templates.is_empty(), "the floor has a boss template")
	check(_config.shop != null, "the floor has shop prices")
	# Spec section 28: milestone 5 asks for eight to twelve rooms.
	check(
		_config.room_count >= 8 and _config.room_count <= 12,
		"the floor is eight to twelve rooms (is %d)" % _config.room_count,
	)
	check(not _config.enemy_spawns.is_empty(), "the floor has an enemy roster")

	for type: RoomTemplate.Type in [
		RoomTemplate.Type.START, RoomTemplate.Type.COMBAT, RoomTemplate.Type.TREASURE,
		RoomTemplate.Type.SHOP, RoomTemplate.Type.BOSS,
	]:
		check(
			not _config.templates_for(type).is_empty(),
			"eligible templates exist for room type %s" % RoomTemplate.Type.keys()[type],
		)


## Determinism is what makes every other check here meaningful, and it is what lets a bad
## layout be reproduced from the seed printed in the debug overlay.
func _test_generation_is_deterministic() -> void:
	var first := FloorGenerator.generate(_config, 12345)
	var second := FloorGenerator.generate(_config, 12345)
	var different := FloorGenerator.generate(_config, 999)

	if not require(first, "generation succeeds") or not require(second, "regeneration succeeds"):
		return

	check(_describe(first) == _describe(second), "the same seed produces the same floor")
	if require(different, "a second seed also generates"):
		check(
			_describe(first) != _describe(different),
			"different seeds produce different floors",
		)


## The four requirements from spec section 9, swept across many seeds — on every floor the
## campaign lists, independently.
##
## It used to sweep floor 1 alone, on the reasoning that the generator is shared so one floor's
## worth of seeds exercises it. That reasoning is wrong in the one direction that matters: the
## generator is shared but its *input* is not, and a floor's room count, template pool, and
## eligibility rules are what decide whether a layout is possible at all. A floor whose templates
## cannot fill its room count fails on every seed, and floor 1 passing says nothing about it.
##
## Per floor rather than pooled, so a failure names the floor rather than the seed alone.
func _test_invariants_across_seeds() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads, to sweep every floor it lists"):
		return

	check(campaign.size() > 0, "the campaign has floors to sweep")
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if not require(config, "floor %d's content loads" % (index + 1)):
			continue
		_sweep_seeds(config, "floor %d ('%s')" % [index + 1, config.id])


## `SEED_COUNT` seeds against one floor, asserting every structural invariant on each.
func _sweep_seeds(config: FloorConfig, where: String) -> void:
	var failures := PackedStringArray()
	var dead_end_specials := 0
	var multi_door_rooms := 0
	var boss_is_farthest := 0

	for offset: int in SEED_COUNT:
		var seed_value := 1000 + offset * 37
		var layout := FloorGenerator.generate(config, seed_value)
		if layout == null:
			failures.append("seed %d failed to generate" % seed_value)
			continue

		if layout.rooms.size() != config.room_count:
			failures.append("seed %d produced %d rooms, expected %d" % [
				seed_value, layout.rooms.size(), config.room_count,
			])

		# 9.3 / 9.1: nothing disconnected, so everything is reachable from the start.
		if not layout.is_fully_connected():
			failures.append("seed %d produced a disconnected floor" % seed_value)

		# 9.4: no overlaps. One cell holds one room, so distinct cells prove it.
		var cells := {}
		for room: RoomPlan in layout.rooms:
			if cells.has(room.cell):
				failures.append("seed %d put two rooms in cell %v" % [seed_value, room.cell])
			cells[room.cell] = true

		# Exactly one of every special room.
		var starts := layout.find_by_type(RoomTemplate.Type.START)
		if starts.size() != 1:
			failures.append("seed %d produced %d start rooms" % [seed_value, starts.size()])

		# 9.2 generalised: none of the three special rooms may block progression, and a dead
		# end cannot be on the route to anywhere, so degree 1 is a sufficient guarantee.
		for type: RoomTemplate.Type in [
			RoomTemplate.Type.TREASURE, RoomTemplate.Type.SHOP, RoomTemplate.Type.BOSS
		]:
			var label: String = RoomTemplate.Type.keys()[type]
			var found := layout.find_by_type(type)
			if found.size() != 1:
				failures.append("seed %d produced %d %s rooms" % [seed_value, found.size(), label])
				continue

			var special: RoomPlan = found[0]
			if special.get_degree() != 1:
				failures.append("seed %d gave the %s room %d doors" % [
					seed_value, label, special.get_degree(),
				])
			else:
				dead_end_specials += 1
			if _removing_room_disconnects_floor(layout, special):
				failures.append("seed %d routes progression through the %s room" % [
					seed_value, label,
				])

		# The boss is the end of the floor, so it must be the furthest thing from the door
		# the player came in through — not something they stumble into on the way past.
		var bosses := layout.find_by_type(RoomTemplate.Type.BOSS)
		if bosses.size() == 1:
			var distances := layout.distances_from(layout.get_start_room())
			var boss_distance: int = distances.get(bosses[0].id, -1)
			var furthest := 0
			for room: RoomPlan in layout.rooms:
				furthest = maxi(furthest, distances.get(room.id, 0))
			if boss_distance >= furthest:
				boss_is_farthest += 1

		# Every door must be symmetric, or a player could walk somewhere they cannot leave.
		for room: RoomPlan in layout.rooms:
			for direction: Vector2i in room.doors:
				var neighbour := layout.get_room(room.doors[direction])
				if neighbour.doors.get(-direction, -1) != room.id:
					failures.append("seed %d has a one-way door from room %d" % [
						seed_value, room.id,
					])
				if neighbour.cell - room.cell != direction:
					failures.append("seed %d has a door to a non-adjacent room" % seed_value)

		# Every room must have a template, or it would build as an empty box.
		for room: RoomPlan in layout.rooms:
			if room.template == null:
				failures.append("seed %d left room %d without a template" % [seed_value, room.id])

		for room: RoomPlan in layout.rooms:
			if room.get_degree() > 1:
				multi_door_rooms += 1

	check(failures.is_empty(), "%s: all invariants hold across %d seeds" % [where, SEED_COUNT])
	for failure: String in failures.slice(0, 6):
		fail("%s: %s" % [where, failure])

	check(
		dead_end_specials == SEED_COUNT * 3,
		"%s: every seed's treasure, shop, and boss rooms are all dead ends" % where,
	)
	check(
		boss_is_farthest == SEED_COUNT,
		"%s: the boss room is always the furthest from the start (%d of %d seeds)" % [
			where, boss_is_farthest, SEED_COUNT,
		],
	)
	# Guards against the generator degenerating into a single corridor, which would satisfy
	# every requirement above and still be dull.
	check(multi_door_rooms > SEED_COUNT, "%s: floors branch rather than forming one chain" % where)


## Verifies the treasure room is not a cut vertex, by checking connectivity of the rest of the
## floor without it. This is the actual meaning of "must not block progression".
func _removing_room_disconnects_floor(layout: FloorLayout, excluded: RoomPlan) -> bool:
	var start := layout.get_start_room()
	if start.id == excluded.id:
		return true

	var seen := {start.id: true}
	var queue: Array[int] = [start.id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbour_id: int in layout.get_room(current).doors.values():
			if neighbour_id == excluded.id or seen.has(neighbour_id):
				continue
			seen[neighbour_id] = true
			queue.append(neighbour_id)

	return seen.size() != layout.rooms.size() - 1


## Room geometry has to agree with the grid the generator lays out, or doors will not line up
## with the gaps left in the wall rings.
func _test_room_geometry_matches_the_grid() -> void:
	check(
		Room.OUTER_SIZE == Room.INTERIOR_SIZE + Vector2i.ONE * Room.WALL_THICKNESS * 2,
		"the outer footprint is the interior plus a wall on each side",
	)
	check(
		Room.INTERIOR_SIZE.x % Room.TILE_SIZE == 0 and Room.INTERIOR_SIZE.y % Room.TILE_SIZE == 0,
		"the interior is a whole number of tiles",
	)

	# A doorway must start and end on a tile boundary, or a template cannot describe the tiles
	# beside a door. This is why the door is four tiles wide and not three.
	var horizontal_gap := Room.INTERIOR_SIZE.x / 2 - Room.DOOR_WIDTH / 2
	var vertical_gap := Room.INTERIOR_SIZE.y / 2 - Room.DOOR_WIDTH / 2
	check(horizontal_gap % Room.TILE_SIZE == 0, "top and bottom doorways are tile-aligned")
	check(vertical_gap % Room.TILE_SIZE == 0, "side doorways are tile-aligned")
	check(
		Room.DOOR_WIDTH < Room.INTERIOR_SIZE.y,
		"a doorway is narrower than the wall it sits in",
	)


## No template may put an obstacle in a doorway corridor or an enemy inside a wall.
##
## Both are content mistakes that look fine in the data and only show up as "the robot cannot get
## out of this room" or "an enemy is stuck in a pillar" on the one seed that pairs the template
## with the wrong door. Cheap to assert, tedious to find by playing — this check was written
## after a template was found sitting squarely across the only straight line between two doors.
func _test_templates_keep_doorways_clear() -> void:
	var templates: Array[RoomTemplate] = []
	templates.append_array(_config.start_templates)
	templates.append_array(_config.combat_templates)
	templates.append_array(_config.treasure_templates)
	check(not templates.is_empty(), "there are templates to check")

	# Door corridors in tile coordinates, derived from the room geometry rather than restated.
	var tiles := Room.INTERIOR_TILES
	var door_tiles := Room.DOOR_TILES
	var vertical_corridor := Vector2i(tiles.x / 2 - door_tiles / 2, tiles.x / 2 + door_tiles / 2)
	var horizontal_corridor := Vector2i(tiles.y / 2 - door_tiles / 2, tiles.y / 2 + door_tiles / 2)

	for template: RoomTemplate in templates:
		for obstacle: Rect2i in template.obstacles:
			check(
				Rect2i(Vector2i.ZERO, tiles).encloses(obstacle),
				"%s obstacle %s stays inside the interior" % [template.id, obstacle],
			)
			# An obstacle may sit in the middle of the room; what it must not do is straddle a
			# doorway corridor at the wall it opens through.
			var in_vertical := obstacle.position.x < vertical_corridor.y and obstacle.end.x > vertical_corridor.x
			var touches_top := obstacle.position.y <= 1
			var touches_bottom := obstacle.end.y >= tiles.y - 1
			check(
				not (in_vertical and (touches_top or touches_bottom)),
				"%s obstacle %s does not block a top or bottom doorway" % [template.id, obstacle],
			)

			var in_horizontal := obstacle.position.y < horizontal_corridor.y and obstacle.end.y > horizontal_corridor.x
			var touches_left := obstacle.position.x <= 1
			var touches_right := obstacle.end.x >= tiles.x - 1
			check(
				not (in_horizontal and (touches_left or touches_right)),
				"%s obstacle %s does not block a side doorway" % [template.id, obstacle],
			)

		for spawn: Vector2i in template.enemy_spawns:
			check(
				Rect2i(Vector2i.ZERO, tiles).has_point(spawn),
				"%s enemy spawn %v is inside the interior" % [template.id, spawn],
			)
			var inside_obstacle := false
			for obstacle: Rect2i in template.obstacles:
				if obstacle.has_point(spawn):
					inside_obstacle = true
			check(
				not inside_obstacle,
				"%s enemy spawn %v is not inside an obstacle" % [template.id, spawn],
			)

		var reward_blocked := false
		for obstacle: Rect2i in template.obstacles:
			if obstacle.has_point(template.reward_spawn):
				reward_blocked = true
		check(not reward_blocked, "%s reward spawn is not inside an obstacle" % template.id)


## The overlap guarantee is enforced by FloorLayout itself, so it is worth proving the guard
## exists rather than trusting the generator never to try.
func _test_layout_rejects_overlap() -> void:
	var layout := FloorLayout.new()
	layout.add_room(Vector2i.ZERO, RoomTemplate.Type.START)
	check(layout.by_cell.has(Vector2i.ZERO), "the cell is recorded as occupied")
	check(layout.rooms.size() == 1, "one room was added")

	var first := layout.get_room(0)
	var second := layout.add_room(Vector2i.RIGHT, RoomTemplate.Type.COMBAT)
	layout.link(first, second)
	check(first.doors.get(Vector2i.RIGHT, -1) == second.id, "linking records the forward door")
	check(second.doors.get(Vector2i.LEFT, -1) == first.id, "linking records the return door")
	check(layout.is_fully_connected(), "two linked rooms are connected")

	var lone := layout.add_room(Vector2i(5, 5), RoomTemplate.Type.COMBAT)
	check(lone != null, "an unlinked room can be added")
	check(not layout.is_fully_connected(), "an unlinked room is reported as disconnected")


## A config that cannot produce a floor must fail loudly and return nothing, rather than
## handing back a half-built layout that fails somewhere else later.
func _test_generator_refuses_impossible_configs() -> void:
	# The two errors this prints are the point of the check. Godot offers no way to silence
	# push_error, so they are announced instead to stop a reader treating them as failures.
	print("    (the next two FloorGenerator errors are expected: refusing bad configs)")
	var too_small := FloorConfig.new()
	too_small.room_count = 1
	check(
		FloorGenerator.generate(too_small, 1) == null,
		"a floor of one room is refused",
	)

	var no_templates := FloorConfig.new()
	no_templates.room_count = 4
	check(
		FloorGenerator.generate(no_templates, 1) == null,
		"a floor with no templates is refused",
	)


## `RoomTemplate.forced_enemies` pairs with `enemy_spawns` by index; a template author
## resizing one and forgetting the other is exactly the authoring-time mistake this is cheap
## to catch here and expensive to notice by playing (see the field's own doc comment).
func _test_forced_enemies_never_exceed_their_spawn_points() -> void:
	var templates: Array[RoomTemplate] = []
	templates.append_array(_config.start_templates)
	templates.append_array(_config.combat_templates)
	templates.append_array(_config.treasure_templates)
	templates.append_array(_config.shop_templates)
	templates.append_array(_config.boss_templates)
	for template: RoomTemplate in templates:
		check(
			template.forced_enemies.size() <= template.enemy_spawns.size(),
			"%s does not force more enemies than it has spawn points" % template.id,
		)


## Distance-biased template selection (`FloorGenerator._capped_by_distance`) is what makes
## README's Floor 2 encounter curve possible at all: an easy template near the start, the
## hardest reserved for the approach to the boss. Swept across many seeds, because "worked
## on the seed I happened to try" is exactly the failure mode a single generation would hide.
func _test_combat_templates_skew_easier_near_the_start() -> void:
	var dev_config := load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(dev_config, "floor_2_development.tres loads as a FloorConfig"):
		return

	var near_start: Array[int] = []
	var near_boss: Array[int] = []

	for offset: int in 60:
		var seed_value := 5000 + offset * 41
		var layout := FloorGenerator.generate(dev_config, seed_value)
		if layout == null:
			fail("seed %d failed to generate" % seed_value)
			continue

		var distances := layout.distances_from(layout.get_start_room())
		var max_distance := 0
		for room: RoomPlan in layout.rooms:
			max_distance = maxi(max_distance, distances.get(room.id, 0))
		if max_distance <= 0:
			continue

		for room: RoomPlan in layout.rooms:
			if room.type != RoomTemplate.Type.COMBAT or room.template == null:
				continue
			var progress := float(distances.get(room.id, 0)) / float(max_distance)
			if progress <= 0.34:
				near_start.append(room.template.difficulty)
			elif progress >= 0.66:
				near_boss.append(room.template.difficulty)

	if not require(not near_start.is_empty(), "some combat rooms landed near the start across the sweep"):
		return
	if not require(not near_boss.is_empty(), "some combat rooms landed near the boss across the sweep"):
		return

	var start_average := _average(near_start)
	var boss_average := _average(near_boss)
	check(
		start_average < boss_average,
		"combat rooms near the start average an easier difficulty than rooms near the boss (%.2f vs %.2f)"
			% [start_average, boss_average],
	)


## Authored content that never ships is the most expensive kind of bug in this project, because it
## is invisible from both ends: the data is there and correct, the generator throws no error, and
## the only symptom is a floor that feels thinner than it reads.
##
## It had happened on every floor at once. `_capped_by_distance` scales a room's allowance by how far
## it is from the start as a fraction of the floor's maximum distance — but the maximum was taken
## over *every* room, and the three special rooms are attached last as dead ends with the boss
## deliberately claiming the furthest cell. No combat room could ever score a full one, so no combat
## room could ever draw the top of its floor's ladder. Measured over four hundred floors: the Help
## Desk's `combat_ring` drew 0.23 times per floor, Development's `dev_server_ring` 0.26, and the Data
## Center's `data_grid_floor` — the room its whole floor is built to end on — three times in four
## hundred.
##
## So this sweeps the shipped campaign and asks the only question that would have caught it: does
## every combat template a floor lists actually turn up? A twentieth of a floor is the bar, which is
## far below where any of them should sit and far above zero.
func _test_every_authored_combat_room_reaches_a_player() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue

		var draws: Dictionary[StringName, int] = {}
		for template: RoomTemplate in config.combat_templates:
			draws[template.id] = 0
		var floors := 0
		for offset: int in SEED_COUNT:
			var layout := FloorGenerator.generate(config, 900000 + offset * 7919)
			if layout == null:
				continue
			floors += 1
			for room: RoomPlan in layout.rooms:
				if room.type == RoomTemplate.Type.COMBAT and room.template != null:
					draws[room.template.id] = draws.get(room.template.id, 0) + 1

		if not require(floors > 0, "floor %d generates" % (index + 1)):
			continue
		for id: StringName in draws:
			check(
				float(draws[id]) / float(floors) >= 0.05,
				"'%s' reaches a player on floor %d (%.2f rooms per floor)"
					% [id, index + 1, float(draws[id]) / float(floors)],
			)


## The same question about the other half of a floor's content. A roster entry is a decision about
## what this floor is *about*, and one drawn less than once per floor is an enemy most players will
## finish the level without meeting.
##
## Simulated rather than played: the rolls `Room.populate` makes are reproduced exactly — forced
## entries first, `FloorConfig.pick_enemy` for the rest, one shared encounter stream per floor — which
## is the whole of what decides a floor's population. Building ten rooms of real enemies a hundred and
## twenty times over would measure the same numbers and take a minute doing it.
func _test_every_rostered_enemy_reaches_a_player() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		var tally := _sweep_population(config)
		if not require(tally["floors"] > 0, "floor %d generates" % (index + 1)):
			continue
		var counts: Dictionary[String, int] = tally["counts"]
		for spawn: EnemySpawn in config.enemy_spawns:
			if spawn == null or spawn.scene == null:
				continue
			var name := spawn.scene.resource_path.get_file().get_basename()
			check(
				float(counts.get(name, 0)) / float(tally["floors"]) >= 1.0,
				"floor %d puts at least one '%s' on the ground per floor (%.2f)"
					% [index + 1, name, float(counts.get(name, 0)) / float(tally["floors"])],
			)


## The bug report this floor's rebalance came from, as a check: *"I often go through it without
## encountering many of the new enemies."*
##
## The Load Balancer and the Stale Replica are the two enemies the Data Center exists to introduce —
## nothing else in the campaign lists either — and a floor whose own enemies are optional is a floor
## teaching nothing. They were: at a shared weight of 1.0 and 0.9 against a roster totalling 7.3,
## each came to about 1.4 per floor and was missing entirely from more than a fifth of them.
##
## Nine floors in ten is the bar, and it is deliberately about *presence* rather than about count.
## How many of a thing a floor holds is tuning and will move; whether the floor's own idea is in it
## at all is a promise.
func _test_the_data_centers_own_enemies_turn_up_in_it() -> void:
	var config := load(FLOOR_3_CONFIG_PATH) as FloorConfig
	if not require(config, "floor_3_data_center.tres loads as a FloorConfig"):
		return

	var tally := _sweep_population(config)
	if not require(tally["floors"] > 0, "the Data Center generates"):
		return
	var present: Dictionary[String, int] = tally["present"]
	for name: String in ["load_balancer", "stale_replica"]:
		check(
			float(present.get(name, 0)) / float(tally["floors"]) >= 0.9,
			"the Data Center puts a '%s' in front of the player (%.0f%% of floors)"
				% [name, 100.0 * float(present.get(name, 0)) / float(tally["floors"])],
		)


## Reproduces `Room.populate`'s draws across `SEED_COUNT` floors. Returns the number of floors swept,
## how many of each enemy were placed in total, and how many floors held at least one of each.
func _sweep_population(config: FloorConfig) -> Dictionary:
	var counts: Dictionary[String, int] = {}
	var present: Dictionary[String, int] = {}
	var floors := 0
	for offset: int in SEED_COUNT:
		var seed_value := 900000 + offset * 7919
		var layout := FloorGenerator.generate(config, seed_value)
		if layout == null:
			continue
		floors += 1
		# One stream for the whole floor, drawn in room order, exactly as `FloorController` does.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var here: Dictionary[String, bool] = {}
		for room: RoomPlan in layout.rooms:
			if room.template == null:
				continue
			var forced := room.template.forced_enemies
			for point: int in room.template.enemy_spawns.size():
				var scene: PackedScene = forced[point] if point < forced.size() else null
				if scene == null:
					scene = config.pick_enemy(room.template.difficulty, rng)
				if scene == null:
					continue
				var name := scene.resource_path.get_file().get_basename()
				counts[name] = counts.get(name, 0) + 1
				here[name] = true
		for name: String in here:
			present[name] = present.get(name, 0) + 1
	return {"floors": floors, "counts": counts, "present": present}


## Spec section 6.6: never trap the player in geometry. Every template in the campaign, flood-filled.
##
## It became worth asserting when `CableDuct` arrived. A wall is easy to reason about because it also
## stops the shot, so a template author looking at a sealed pocket sees a sealed pocket; a duct is
## transparent to everything except a chassis, so the same mistake looks like open floor on screen
## and reads like open floor in the data. The failure it produces is the worst one this game has: a
## robot in a room it cannot leave, in a room whose door has already locked behind it.
##
## Three claims, and the first is the one that matters. The template's walkable tiles must be a
## *single* connected region — not "the doors connect to each other", which a sealed pocket in a
## corner would also satisfy, and which is exactly where the loot spawner would eventually drop a
## repair cell nobody can reach.
func _test_no_template_can_strand_a_chassis() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var checked := 0
	var seen: Dictionary[StringName, bool] = {}
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		var templates: Array[RoomTemplate] = []
		templates.append_array(config.start_templates)
		templates.append_array(config.combat_templates)
		templates.append_array(config.treasure_templates)
		templates.append_array(config.shop_templates)
		templates.append_array(config.boss_templates)
		for template: RoomTemplate in templates:
			if template == null or seen.has(template.id):
				continue
			seen[template.id] = true
			checked += 1
			_check_template_is_one_room(template)
	check(checked > 0, "there were templates to walk (%d)" % checked)


func _check_template_is_one_room(template: RoomTemplate) -> void:
	var tiles := Room.INTERIOR_TILES
	var solid: Dictionary[Vector2i, bool] = {}
	for blocked: Array[Rect2i] in [template.obstacles, template.ducts]:
		for rect: Rect2i in blocked:
			for y: int in rect.size.y:
				for x: int in rect.size.x:
					solid[rect.position + Vector2i(x, y)] = true

	var free: Array[Vector2i] = []
	for y: int in tiles.y:
		for x: int in tiles.x:
			if not solid.has(Vector2i(x, y)):
				free.append(Vector2i(x, y))
	if not require(not free.is_empty(), "%s has floor in it at all" % template.id):
		return

	var reached: Dictionary[Vector2i, bool] = {free[0]: true}
	var pending: Array[Vector2i] = [free[0]]
	while not pending.is_empty():
		var tile: Vector2i = pending.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := tile + step
			if next.x < 0 or next.y < 0 or next.x >= tiles.x or next.y >= tiles.y:
				continue
			if solid.has(next) or reached.has(next):
				continue
			reached[next] = true
			pending.append(next)

	check(
		reached.size() == free.size(),
		"%s is one connected room (%d of %d walkable tiles reachable)"
			% [template.id, reached.size(), free.size()],
	)

	# Every doorway a floor could open in this room, whichever walls the layout happens to give it.
	#
	# Pinched is allowed; sealed is not. `data_hot_aisle` deliberately narrows both of its vertical
	# doorways to a single tile on each side of a central block, and a single tile is sixteen pixels
	# against a ten-pixel robot — tight on purpose and passable. What must never happen is a doorway
	# with no walkable tile left in it at all, which is a door that opens onto a wall.
	var door := Room.DOOR_TILES
	var walls := {
		"top": [], "bottom": [], "left": [], "right": [],
	}
	for offset: int in door:
		var x := tiles.x / 2 - door / 2 + offset
		var y := tiles.y / 2 - door / 2 + offset
		walls["top"].append(Vector2i(x, 0))
		walls["bottom"].append(Vector2i(x, tiles.y - 1))
		walls["left"].append(Vector2i(0, y))
		walls["right"].append(Vector2i(tiles.x - 1, y))
	for side: String in walls:
		var open_tiles := 0
		for mouth: Vector2i in walls[side]:
			if reached.has(mouth):
				open_tiles += 1
		check(
			open_tiles > 0,
			"%s leaves a way in through its %s doorway (%d of %d tiles)"
				% [template.id, side, open_tiles, door],
		)

	for spawn: Vector2i in template.enemy_spawns:
		check(reached.has(spawn), "%s enemy spawn %v stands on reachable floor" % [template.id, spawn])
	check(
		reached.has(template.reward_spawn),
		"%s reward spawn %v stands on reachable floor" % [template.id, template.reward_spawn],
	)
	for stand: Vector2i in template.shop_stands:
		check(reached.has(stand), "%s shop stand %v stands on reachable floor" % [template.id, stand])


## `CableDuct`'s whole reason to exist, as the two queries the game actually makes.
##
## The mechanic is a difference between two collision masks and nothing else, which makes it exactly
## the kind of thing that is one edited scene away from silently becoming a wall — or, worse, from
## becoming nothing at all, at which point the room templates built on it are open floor with a
## decoration on it and the floor is easier than it reads.
##
## So both halves are asserted against a wall block standing beside the duct, in the same arena, at
## the same distance. A duct that has quietly become a wall fails the second check; a duct that has
## quietly become scenery fails the first; and the wall's own two checks are what say the arena is
## wired up at all rather than the queries silently missing everything.
func _test_a_duct_stops_a_chassis_and_not_a_shot() -> void:
	var arena := Node2D.new()
	add_child(arena)

	var duct: CableDuct = load("res://scenes/rooms/cable_duct.tscn").instantiate()
	duct.size = Vector2i(16, 64)
	duct.position = Vector2(0.0, -32.0)
	arena.add_child(duct)

	var wall: WallBlock = load("res://scenes/rooms/wall_block.tscn").instantiate()
	wall.size = Vector2i(16, 64)
	wall.position = Vector2(200.0, -32.0)
	arena.add_child(wall)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(-40.0, 0.0)
	arena.add_child(player)
	await advance_physics(2)

	var space := arena.get_world_2d().direct_space_state

	# The two predicates, named as the game names them. `Enemy.has_line_of_sight`, `FirewallNode`'s
	# beams and `Projectile._cast_to_wall` all trace against the world layer; every body on the floor
	# masks `Teams.body_mask`, and the loot spawner and the Pop Up Drone ask the same question of the
	# ground before they use it.
	for pair: Array in [[duct.position.x + 8.0, "a duct", false], [wall.position.x + 8.0, "a wall", true]]:
		var x: float = pair[0]
		var label: String = pair[1]
		var stops_shots: bool = pair[2]
		var from := Vector2(x - 40.0, 0.0)
		var to := Vector2(x + 40.0, 0.0)

		var chassis := PhysicsRayQueryParameters2D.create(from, to, Teams.body_mask())
		check(
			not space.intersect_ray(chassis).is_empty(),
			"%s stops a chassis" % label,
		)

		var shot := PhysicsRayQueryParameters2D.create(from, to, Teams.LAYER_WORLD)
		var blocked := not space.intersect_ray(shot).is_empty()
		check(
			blocked == stops_shots,
			"%s %s a shot" % [label, "stops" if stops_shots else "lets through"],
		)

	# And the robot itself, with its own mask, rather than a ray standing in for it. `test_move`
	# answers the question `move_and_slide` would answer a frame later, without needing input.
	check(
		player.test_move(player.global_transform, Vector2(60.0, 0.0)),
		"the robot cannot drive across a duct",
	)
	check(
		not player.test_move(player.global_transform, Vector2(0.0, 60.0)),
		"and can drive past the end of one",
	)

	arena.queue_free()
	await advance_physics(2)


func _average(values: Array[int]) -> float:
	var total := 0
	for value: int in values:
		total += value
	return float(total) / float(values.size())


## A stable text form of a layout, for comparing two generations.
func _describe(layout: FloorLayout) -> String:
	var parts := PackedStringArray()
	for room: RoomPlan in layout.rooms:
		var directions := PackedStringArray()
		for direction: Vector2i in room.doors:
			directions.append("%v" % direction)
		directions.sort()
		parts.append("%d:%v:%d:%s:%s" % [
			room.id, room.cell, room.type,
			room.template.id if room.template != null else &"none",
			"|".join(directions),
		])
	return ";".join(parts)


## Reported: repair cells dropped on clears 1 and 4 instead of 3 and 6.
##
## The cause was an ordering assumption across two objects. RoomCombat emits its own `cleared`
## signal — the one that runs FloorController's handler — *before* the EventBus signal that
## RunManager counts, so `RunManager.rooms_cleared` was still one behind while the drop was
## being decided. Clear 1 read 0, and 0 % 3 == 0, so the very first room paid out a repair cell
## to a player still on full integrity who could not use it.
##
## The check drives clears in the same order the real signals fire, because that order *is* the
## bug: anything that steps a counter itself and then asks would pass over it.
## The Development plan asks for a floor that "reads as an unfinished development lab rather
## than another Help Desk". Two floors sharing a theme resource would satisfy every other
## check in this suite and look identical in play, so the distinctness is the assertion.
func _test_each_floor_looks_and_sounds_like_itself() -> void:
	var second := load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(second, "floor_2_development.tres loads") :
		return
	if not require(_config.theme, "the Help Desk has a theme"):
		return
	if not require(second.theme, "Development has a theme"):
		return

	for pair: Array in [[_config, "Help Desk"], [second, "Development"]]:
		var theme: FloorTheme = (pair[0] as FloorConfig).theme
		check(theme.floor_texture != null, "%s names a floor texture" % pair[1])
		check(theme.wall_texture != null, "%s names a wall texture" % pair[1])

	check(
		_config.theme.floor_texture != second.theme.floor_texture
			and _config.theme.wall_texture != second.theme.wall_texture,
		"the two floors are built out of different tiles",
	)
	check(
		_config.theme.explore_music != second.theme.explore_music
			and _config.theme.boss_music != second.theme.boss_music,
		"and play different music in both situations",
	)

	# A theme naming a track the library does not have is silent, not loud — `play_music`
	# warns and returns, so the floor would simply have no soundtrack.
	for config: FloorConfig in [_config, second]:
		for id: StringName in [config.theme.explore_music, config.theme.boss_music]:
			check(
				AudioManager.MUSIC_LIBRARY.has(id),
				"'%s' names a track that exists in the library" % id,
			)


## Either boss may guard either floor, which is only a feature if a run cannot draw the same
## one twice — a two-floor run that fought The Scrap King on both floors would be a run missing
## a boss, and the player would have no way to know they had been shortchanged.
##
## Driven through real `FloorController.build` calls rather than by reimplementing the draw,
## because the property being checked is that the *shuffle spans floors*, and the thing that
## makes it span them (`RunManager.fought_boss_ids` surviving a floor rebuild) is exactly what a
## reimplementation would assume rather than test.
func _test_a_run_never_fights_the_same_boss_twice() -> void:
	var second := load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(second, "floor_2_development.tres loads"):
		return

	var first_seen: Dictionary[StringName, bool] = {}
	var repeats := 0
	var runs := 0

	for seed_value: int in [1, 7, 12, 20, 33, 41, 58, 64, 77, 91]:
		var arena := Node2D.new()
		add_child(arena)
		var floor_node: FloorController = FLOOR_SCENE.instantiate()
		floor_node.config = _config
		arena.add_child(floor_node)
		var player: Player = PLAYER_SCENE.instantiate()
		arena.add_child(player)
		await advance_physics(1)

		RunManager.begin_run(seed_value)
		if floor_node.build(player, seed_value):
			var one := floor_node.get_boss_encounter()
			# The same controller rebuilds itself for the next floor, which is how a descent
			# actually works — see `FloorController._advance_to_next_floor`.
			floor_node.config = second
			if floor_node.build(player, seed_value + 1):
				var two := floor_node.get_boss_encounter()
				if one != null and two != null:
					runs += 1
					first_seen[one.id] = true
					if one.id == two.id:
						repeats += 1

		arena.queue_free()
		await advance_physics(2)

	check(runs > 0, "the two-floor draw ran (%d times)" % runs)
	check(repeats == 0, "no run fought the same boss on both floors (%d did)" % repeats)
	# Derived from the pool rather than typed as a literal, for the reason
	# `_test_repair_cells_drop_on_every_third_clear` derives its cadence from the constant: the
	# floors went from two bosses each to three, and an expectation written as a number turns that
	# into a failure somebody has to work out rather than one that moved with the content.
	check(
		first_seen.size() == _config.boss_pool.size(),
		"and every boss in the pool turns up first across seeds (%d of %d did)" % [
			first_seen.size(), _config.boss_pool.size(),
		],
	)


## The textures have to reach the geometry, not just sit on the resource. Walls and obstacles
## are checked separately from the floor because they are built by different code paths and
## an obstacle wearing the wrong sheet is exactly the kind of half-themed room that reads as
## a bug rather than as a style.
## The cheap shot, and the window that answers it.
##
## Beta reports were all the same shape: walk through a door, lose a point before the room is on
## screen. `FloorController._enter_room` wakes the room and *then* announces the entry, so anything
## already aimed at the doorway fires into a player who has not seen it — which is a point spent on
## a decision they were never offered.
##
## Driven through a real `_enter_room` on a real floor rather than by emitting `room_entered` by
## hand, because the ordering is the whole claim. A grace window granted before `Room.set_active`
## would test just as green against a bare signal and would still leave the player exposed on the
## frame that matters.
##
## The expiry half is checked too, and it is the half that keeps this honest: an immunity that
## never ends is not a grace window, it is a cheat, and nothing else in the suite would notice.
func _test_walking_into_a_room_buys_a_moment_of_grace() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)

	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	RunManager.begin_run(20260816)
	if not require(floor_node.build(player, 20260816), "the floor builds"):
		arena.queue_free()
		await advance_physics(1)
		return

	var grace: float = player.config.room_entry_grace
	check(grace > 0.0, "the config grants a window at all (%.2fs)" % grace)

	var health := player.get_health_component()
	# Out of any window the build itself started, so what is measured is the door and nothing else.
	health.grant_invulnerability(0.0)
	await advance_physics(int(grace * 60.0) + 4)
	check(not health.is_invulnerable(), "the robot is takeable before it walks anywhere")

	# Any room other than the one the floor opened on. The start bay is empty, so entering it is
	# not the case anybody complained about.
	var destination := -1
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.id != floor_node.current_room_id:
			destination = plan.id
			break
	if not require(destination >= 0, "the floor has a second room to walk into"):
		arena.queue_free()
		await advance_physics(1)
		return

	floor_node._enter_room(destination)
	check(health.is_invulnerable(), "crossing the threshold makes the robot untouchable")

	var landed := health.apply_damage(DamageInfo.new(1.0))
	check(not landed, "and a shot waiting on the doorway takes nothing")

	# One frame short of the window, then past it. Two checks rather than one, so a window of the
	# wrong length fails as loudly as a window that never closes.
	await advance_physics(int(grace * 60.0) - 2)
	check(health.is_invulnerable(), "the window is still open just before it expires")

	await advance_physics(4)
	check(not health.is_invulnerable(), "and shut just after")
	check(
		health.apply_damage(DamageInfo.new(1.0)),
		"a room the player has had time to read costs what it always did",
	)

	arena.queue_free()
	await advance_physics(1)


## The other half of the doorway window: the player must not be able to *see* it.
##
## The window itself is worth having — the check above says why — but the flash that came with it
## was not. `PlayerVisuals` strobes the robot at twelve hertz while it is immune, which is the right
## readout for a window the player has to play around and the wrong one for a window they are handed
## for walking through a door. Forty rooms a run, it read as the game glitching on every transition.
##
## Two claims, and the second is the one that keeps this from being a licence to delete the flash
## outright. A doorway window is silent; a window the player is still holding from a *hit* survives
## being carried through a door, because that one has a deadline they are meant to be watching.
func _test_the_doorway_window_is_not_shown() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)

	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	RunManager.begin_run(20260817)
	if not require(floor_node.build(player, 20260817), "the floor builds"):
		arena.queue_free()
		await advance_physics(1)
		return

	var health := player.get_health_component()
	var destinations: Array[int] = []
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.id != floor_node.current_room_id:
			destinations.append(plan.id)
	if not require(destinations.size() >= 2, "the floor has two rooms to walk into"):
		arena.queue_free()
		await advance_physics(1)
		return

	health.grant_invulnerability(0.0)
	await advance_physics(int(player.config.room_entry_grace * 60.0) + 4)

	floor_node._enter_room(destinations[0])
	check(health.is_invulnerable(), "walking through a door still grants the window")
	check(not player.should_flash(), "and the robot does not strobe about it")

	# Now the same doorway, entered by a robot that has just been hit. The window it is watching is
	# its own, and carrying it through a door must not turn the readout off.
	health.grant_invulnerability(0.0)
	await advance_physics(int(player.config.room_entry_grace * 60.0) + 4)
	check(health.apply_damage(DamageInfo.new(1.0)), "a hit lands once the window has shut")
	check(player.should_flash(), "and that window is shown")

	floor_node._enter_room(destinations[1])
	check(player.should_flash(), "carrying it through a door does not silence it")

	arena.queue_free()
	await advance_physics(1)


func _test_a_room_wears_its_floors_theme() -> void:
	var second := load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if second == null or second.theme == null:
		return

	# A template with obstacles, so there is something in the middle of the room to check.
	var template: RoomTemplate = null
	for candidate: RoomTemplate in second.combat_templates:
		if not candidate.obstacles.is_empty():
			template = candidate
			break
	if not require(template, "Development has a combat template with obstacles"):
		return

	var plan := RoomPlan.new(0, Vector2i.ZERO, RoomTemplate.Type.COMBAT)
	plan.template = template

	var room: Room = load("res://scenes/rooms/room.tscn").instantiate()
	add_child(room)
	room.build(plan, second.theme)
	await advance_physics(1)

	check(
		(room.get_node("%Floor") as Sprite2D).texture == second.theme.floor_texture,
		"the room's floor wears the theme's tile sheet",
	)

	var walls := room.get_node("%Walls").get_children()
	var obstacles := room.get_node("%Obstacles").get_children()
	check(not walls.is_empty() and not obstacles.is_empty(), "the room built walls and obstacles")

	# Ducts are skipped, and the skip is the rule rather than an exemption: a `CableDuct` is the one
	# piece of level geometry that must *never* wear the floor's wall sheet, because looking like the
	# wall beside it is exactly what a thing bullets pass through must not do. See `CableDuct`.
	var themed := 0
	var wrong := 0
	for block: Node in walls + obstacles:
		if block is CableDuct:
			continue
		themed += 1
		if (block as WallBlock).get_node("Sprite").texture != second.theme.wall_texture:
			wrong += 1
	check(wrong == 0, "every wall and obstacle wears it too (%d of %d did not)" % [wrong, themed])
	room.queue_free()
	await advance_physics(2)

	# And a room built without one keeps what its scene was authored with, which is what every
	# test arena in the suite relies on.
	var bare: Room = load("res://scenes/rooms/room.tscn").instantiate()
	add_child(bare)
	bare.build(plan)
	await advance_physics(1)
	check(
		(bare.get_node("%Floor") as Sprite2D).texture != second.theme.floor_texture,
		"a room built with no theme keeps its authored textures",
	)
	bare.queue_free()
	await advance_physics(2)


func _test_repair_cells_drop_on_every_third_clear() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)

	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	RunManager.begin_run(4242)
	var built := floor_node.build(player, 4242)
	check(built, "the floor builds")
	if not built:
		arena.queue_free()
		await advance_physics(1)
		return

	var ids: Array[int] = []
	for plan: RoomPlan in floor_node.layout.rooms:
		ids.append(plan.id)

	var repairs_on: Array[int] = []
	for clear_index: int in range(1, 8):
		var before := _count_repair_cells()
		# The two emissions in RoomCombat's order: the local signal first, the EventBus one
		# after. Reversing these two lines is the entire defect.
		floor_node._on_room_cleared(ids[clear_index % ids.size()])
		EventBus.room_cleared.emit()
		await advance_physics(1)
		if _count_repair_cells() > before:
			repairs_on.append(clear_index)

	# Derived from the constant rather than typed as 3 and 6, so retuning the cadence moves the
	# expectation with it instead of turning this into a failure to explain.
	var expected: Array[int] = [
		FloorController.REPAIR_EVERY_CLEARS, FloorController.REPAIR_EVERY_CLEARS * 2
	]
	check(
		repairs_on == expected,
		"repair cells drop on clears %s, got %s" % [expected, repairs_on],
	)
	check(
		not (1 in repairs_on),
		"nothing drops on the first clear, when the player is still at full integrity",
	)

	arena.queue_free()
	await advance_physics(1)


## Defeating a boss must advance the run into the next floor rather than end it, and only the
## *last floor the campaign lists* may reach victory. Drives the boss-defeat handlers directly,
## the same way `_test_repair_cells_drop_on_every_third_clear` drives `_on_room_cleared` above.
##
## Read off the campaign rather than off floor 1, because the campaign is now the floor order:
## a controller that still descended correctly while ignoring it would be the second authority
## this package exists to remove.
func _test_boss_defeat_advances_to_the_next_floor_and_only_the_last_wins() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	var floor_config := campaign.load_floor(0)
	var next_config := campaign.load_floor(1)
	if not require(floor_config, "the campaign's first floor loads"):
		return
	if not require(next_config, "the campaign has a floor to descend into"):
		return
	check(campaign.is_terminal(campaign.size() - 1), "only the campaign's last floor is terminal")
	check(not campaign.is_terminal(0), "and the first floor is not")

	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	GameManager.start_run()
	RunManager.begin_run(9001, campaign)
	check(floor_node.build(player, campaign.floor_seed_for(9001, 0)), "floor 1 builds")

	# Every floor the campaign declares, rather than the two that exist. The interesting claim is
	# "each floor advances and only the last one wins", and a test that spelled out two floors
	# would keep passing against a six-floor campaign that won on the second.
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		var number := index + 1
		var boss_room := _find_boss_room(floor_node)
		if not require(boss_room, "floor %d has a boss room" % number):
			break

		_defeat_boss(floor_node, boss_room)
		await advance_physics(1)
		# Victory waits on the claim, not on the killing blow, on every floor including the last.
		check(
			GameManager.state == GameManager.State.RUN,
			"defeating floor %d's boss does not end the run on its own" % number,
		)

		floor_node._on_boss_reward_taken(config.get_items()[0])
		await advance_physics(1)

		if campaign.is_terminal(index):
			check(
				GameManager.state == GameManager.State.VICTORY,
				"taking the last floor's reward wins the run",
			)
			break

		check(
			GameManager.state == GameManager.State.RUN,
			"taking floor %d's reward advances, not wins" % number,
		)
		check(RunManager.floor_number == number + 1, "RunManager reports floor %d" % (number + 1))
		check(
			floor_node.config == campaign.load_floor(index + 1),
			"the controller rebuilt from floor %d's config" % (number + 1),
		)
		check(
			floor_node.floor_index == index + 1,
			"and knows it is standing on floor %d" % (number + 1),
		)
		check(floor_node._clears == 0, "floor %d starts with a clean clear count" % (number + 1))
		check(
			floor_node.visited.size() == 1,
			"floor %d starts with only its own start room visited" % (number + 1),
		)

	# Winning pauses the tree (GameManager._set_state); leaving it paused would break every
	# suite that runs after this one and needs physics frames to actually advance.
	GameManager.start_run()
	arena.queue_free()
	await advance_physics(1)


## A floor begins in its start room and nowhere else. This looks like a statement too obvious
## to spend a test on, and it is the one that shipped broken.
##
## `build()` instantiates the new floor's rooms before `_place_player_in_start_room` moves the
## player off the old floor's coordinates, so the new room that lands on the spot where the
## player took the boss reward registers an overlap on its entry Area2D. Godot delivers that
## `body_entered` on the next physics flush — after the start room was entered explicitly,
## which is what lets it win. The room ids are assigned in a fixed order
## (`FloorGenerator.SPECIAL_TYPES`), so on a ten-room floor the boss is always id 7 and the
## spurious entry lands on the *boss room* whenever the two floors put their boss on the same
## cell. That spawned Development's boss into an empty arena the moment the floor opened and
## left its health bar on screen for the entire floor.
##
## The seeds below are three that reproduced it; the sweep is what stops the fix from being
## "those three seeds". Nothing here spawns floor 1's boss, because the trigger depends only
## on where the player is standing when the floor is rebuilt under them.
func _test_a_descent_enters_only_the_new_floors_start_room() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return
	var floor_config := campaign.load_floor(0)
	if not require(floor_config, "the campaign's first floor loads"):
		return
	if not require(campaign.load_floor(1), "there is a floor to descend into"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	var wrong_rooms: Array[String] = []
	var bosses_spawned := 0
	# The three known-bad seeds first, then the same sweep width the rest of this file uses. The
	# bug was a coincidence between two floors' layouts that held on 2% of seeds, so a handful
	# of them would pass against a fix that merely moved the coincidence somewhere else. This
	# was briefly cut to six while the runner still paced itself in real time; it costs about a
	# second now, and this is the check that most repays the seeds.
	var seeds: Array[int] = [177, 187, 198]
	for seed_value: int in range(1, SEED_COUNT + 1):
		seeds.append(seed_value)

	# Watched rather than read afterwards: the spurious entry is corrected a frame later by the
	# player's own overlap with the start room, so `current_room_id` looks innocent by the time
	# the dust settles. What the boss room does on the way through is the whole bug.
	_entered_during_descent.clear()
	EventBus.room_entered.connect(_on_room_entered_during_descent)

	for seed_value: int in seeds:
		GameManager.start_run()
		RunManager.begin_run(seed_value)

		var floor_node: FloorController = FLOOR_SCENE.instantiate()
		floor_node.config = floor_config
		arena.add_child(floor_node)
		if not floor_node.build(player, seed_value):
			floor_node.queue_free()
			await advance_physics(1)
			continue

		# Where the player is standing when they take the reward: inside floor 1's boss room.
		var boss_room := _find_boss_room(floor_node)
		if boss_room == null:
			floor_node.queue_free()
			await advance_physics(1)
			continue
		player.global_position = boss_room.get_interior_rect().get_center()
		floor_node._enter_room(boss_room.plan.id)
		await advance_physics(2)

		_defeat_boss(floor_node, boss_room)
		_entered_during_descent.clear()
		floor_node._on_boss_reward_taken(floor_config.get_items()[0])
		# Long enough for the deferred rebuild and for the physics flush that delivers a
		# body_entered the rebuild caused — one frame is not.
		await advance_physics(8)

		var start_id: int = floor_node.layout.get_start_room().id
		for id: int in _entered_during_descent:
			if id == start_id:
				continue
			var entered: Room = floor_node.get_room(id)
			wrong_rooms.append("seed %d entered %s#%d" % [
				seed_value,
				RoomTemplate.Type.keys()[entered.plan.type] if entered else "?",
				id,
			])
		if floor_node._boss != null:
			bosses_spawned += 1

		floor_node.queue_free()
		await advance_physics(1)

	EventBus.room_entered.disconnect(_on_room_entered_during_descent)

	check(
		wrong_rooms.is_empty(),
		"a descent enters the new floor's start room and nothing else (%s)" % (
			"across %d seeds" % seeds.size() if wrong_rooms.is_empty() else ", ".join(wrong_rooms)
		),
	)
	check(
		bosses_spawned == 0,
		"and none of them spawns the new floor's boss before the player walks into its room (%d did)"
			% bosses_spawned,
	)

	# The other half of that fix, and the half it could quietly break: a player who really is in
	# the room must still be registered as entering it, through the Area2D rather than through a
	# direct `_enter_room` call. A guard that rejected real entries would leave doors unlocked
	# behind an uncleared room and never spawn a boss at all.
	GameManager.start_run()
	RunManager.begin_run(9001)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = floor_config
	arena.add_child(floor_node)
	if require(floor_node.build(player, 9001), "a floor builds to check real entries still land"):
		var start_id: int = floor_node.layout.get_start_room().id
		var walked_into := -1
		for plan: RoomPlan in floor_node.layout.rooms:
			if plan.id != start_id:
				walked_into = plan.id
				break
		var destination := floor_node.get_room(walked_into)
		player.global_position = destination.get_interior_rect().get_center()
		await advance_physics(4)
		check(
			floor_node.current_room_id == walked_into,
			"a player standing in room %d is registered as entering it (current room is %d)"
				% [walked_into, floor_node.current_room_id],
		)
	floor_node.queue_free()

	arena.queue_free()
	await advance_physics(1)


## Reports a boss defeat to `floor_node` without a boss.
##
## The handler only needs something non-null to name as the source, so a bare `Node` stands in for
## the fight. It has to be *freed*, which is the part that was missed at two of the call sites:
## `Node` is not reference counted, so a stand-in dropped on the floor is an object alive for the
## rest of the process — and one of those call sites is inside a 123-seed loop, which is where 123
## of this project's 125 reported exit leaks came from. One helper rather than the same three lines
## at each site, so the next call site cannot forget.
func _defeat_boss(floor_node: FloorController, boss_room: Room) -> void:
	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()


func _on_room_entered_during_descent(_type: int, id: int) -> void:
	_entered_during_descent.append(id)


func _find_boss_room(floor_node: FloorController) -> Room:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			return floor_node.get_room(plan.id)
	return null


func _count_repair_cells() -> int:
	var found := 0
	for node: Node in get_tree().get_nodes_in_group(Pickup.GROUP):
		var pickup: Pickup = node
		if pickup.config != null and pickup.config.kind == PickupConfig.Kind.REPAIR_CELL:
			found += 1
	return found


# --- Floor session lifecycle -------------------------------------------------------------
#
# A floor is one node now (`FloorSession`), and a boundary frees it whole. The checks below are
# the ones that were impossible to write when "what dies with a floor" was a list in `_teardown`:
# the interesting failure was never a room surviving, it was the things nobody had listed.


## Long enough for a lane to still be telegraphing when the floor under it is released. Its damage
## is zero as well: this is a check on ownership, not on whether a lane can hit anybody.
const LANE_TELEGRAPH_SECONDS := 10.0

## The floors this suite's multi-floor checks are built from. See `GreyboxCampaign`, which owns
## what a greybox floor is; this suite owns only when to clean them up.
var _greybox := GreyboxCampaign.new()


## Five boundaries, and after each one exactly one of everything a floor owns.
##
## Five rather than one because the failure this exists for is *accumulation*: one leaked room
## graph looks like a working game, and the probe that found the original bug only found it by
## counting across transitions. A greybox campaign rather than the shipped two floors, because two
## floors can only produce one boundary and one boundary cannot show a trend.
func _test_five_boundaries_leave_exactly_one_floor() -> void:
	var campaign := _greybox_campaign(6)
	if not require(campaign, "a six-floor greybox campaign builds"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := _open_greybox(arena, campaign, 31337)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var expected_rooms := floor_node.config.room_count
	for boundary: int in 5:
		await _descend(floor_node)
		var number := boundary + 2
		check(
			floor_node.config.floor_number == number,
			"boundary %d lands on floor %d (landed on %d)"
				% [boundary + 1, number, floor_node.config.floor_number],
		)
		check(
			_sessions_under(floor_node) == 1,
			"floor %d is the only floor in the tree (%d are)"
				% [number, _sessions_under(floor_node)],
		)
		check(
			_containers_under(floor_node) == 1,
			"and owns the only projectile container (%d do)" % _containers_under(floor_node),
		)
		check(
			floor_node._rooms.size() == expected_rooms,
			"and has %d rooms, not %d floors' worth" % [expected_rooms, floor_node._rooms.size()],
		)
		check(
			floor_node.get_session().generation == number,
			"and is the %dth session opened (is %d)"
				% [number, floor_node.get_session().generation],
		)

	check(
		floor_node.get_session().pending_count() == 0,
		"nothing is left queued after five boundaries",
	)

	arena.queue_free()
	await advance_physics(1)


## One of everything a floor can leave behind, then a boundary, then none of it.
##
## The queued pickup is the one that matters most. It is a spawn that has been *asked for* and has
## not happened yet — the state deleting the current children cannot reach, because at that moment
## the pickup is not a child of anything. That is the shape of the original bug: loot and
## projectiles are added deferred, so a floor can end between the request and the arrival.
func _test_nothing_from_a_floor_survives_its_boundary() -> void:
	var campaign := _greybox_campaign(6)
	if not require(campaign, "the greybox campaign builds"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := _open_greybox(arena, campaign, 4711)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var session := floor_node.get_session()
	var origin := floor_node.get_current_room().get_interior_centre()

	# A pickup that has landed, a projectile in flight, and a lane mid-telegraph.
	session.loot._spawn(LootSpawner.SCRAP_CONFIG, origin)
	await advance_physics(2)
	var pickup := _first_pickup_under(floor_node)
	# Stationary, long-lived, and on the player's own team, so that the *only* thing which can end
	# this projectile is the floor it belongs to. Both halves of that were learned by watching this
	# check pass against a deliberately broken build: a rivet's 1.4s lifetime expires inside the
	# descent, and an enemy-team shot spawned on the room's centre point is a shot spawned on top
	# of the player, which despawns it on contact. Either way the assertion held for a reason that
	# had nothing to do with floor ownership.
	var shot := (load("res://data/projectiles/rivet.tres") as ProjectileConfig).spawn_copy()
	shot.speed = 0.0
	shot.lifetime = 600.0
	shot.damage = 0.0
	var projectile := ProjectileFactory.spawn_configured(
		session.projectiles, shot, Vector2.RIGHT, origin, Teams.Id.PLAYER
	)
	var lane := CompileLane.spawn(
		floor_node, Rect2(origin, Vector2(16.0, 16.0)), 0.0, LANE_TELEGRAPH_SECONDS, 1.0
	)
	var enemy := _first_enemy_under(floor_node)
	var door := _first_door(floor_node)

	# And two that have been asked for and have not arrived. Queued last, so the boundary happens
	# before the idle frame that would have delivered them.
	#
	# `stranded` is held by name because it is the case with no other symptom: a node queued
	# through `add_child.call_deferred` against a parent that is then freed is not added, not
	# freed, and not referenced by anything — it simply stays alive for the rest of the process
	# with nothing pointing at it. Nothing observable happens, which is why it needs asserting
	# directly rather than through a count of what is in the tree.
	session.loot._spawn(LootSpawner.SCRAP_CONFIG, origin)
	var stranded := Node2D.new()
	session.add_deferred(session.projectiles, stranded)

	var present := (
		pickup != null and projectile != null and lane != null and enemy != null and door != null
	)
	check(present, "a floor with loot, a shot, a lane, an enemy, and a door to leave behind")
	check(session.pending_count() == 2, "and two spawns queued against it (%d)" % session.pending_count())
	if not present:
		arena.queue_free()
		await advance_physics(1)
		return

	await _descend(floor_node)

	for pair: Array in [
		[pickup, "pickup"], [projectile, "projectile"], [lane, "compile lane"],
		[enemy, "enemy"], [door, "door"], [session, "session"],
	]:
		check(
			not is_instance_valid(pair[0]),
			"the previous floor's %s does not survive the boundary" % pair[1],
		)

	check(
		not is_instance_valid(stranded),
		"a spawn queued against the old floor is freed rather than stranded outside the tree",
	)

	var opened := floor_node.get_session()
	check(opened.pending_count() == 0, "the new floor inherits no queued spawn")
	check(_first_pickup_under(floor_node) == null, "and no loot")
	check(opened.projectiles.get_child_count() == 0, "and nothing in its projectile container")


	arena.queue_free()
	await advance_physics(1)


## The other half of the boundary: what must *not* be reset. The run is the thing that crosses,
## and it crosses by not being inside the floor — so this is really a check that the session
## boundary was drawn in the right place.
func _test_a_boundary_keeps_run_state_and_resets_floor_state() -> void:
	var campaign := _greybox_campaign(6)
	if not require(campaign, "the greybox campaign builds"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := _open_greybox(arena, campaign, 8080)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var player: Player = arena.get_node("Player")
	var health := player.get_health_component()
	var inventory := player.get_item_inventory()

	RunManager.add_scrap(37)
	RunManager.enemy_health_scale = 1.5
	RunManager.rooms_cleared = 4
	RunManager.stats.enemies_defeated = 9
	health.apply_damage(DamageInfo.new(1.0, null, Vector2.RIGHT))
	inventory.add(_config.get_items()[0])
	floor_node._clears = 3

	var integrity := health.current
	var offered_before := RunManager.offered_item_ids.size()
	var bosses_before := RunManager.fought_boss_ids.size()

	await _descend(floor_node)

	check(arena.get_node("Player") == player, "the same player node crosses the boundary")
	check_near(health.current, integrity, "and keeps the integrity it arrived with")
	check(inventory.size() == 1, "and its inventory (%d items)" % inventory.size())
	check(RunManager.scrap == 37, "scrap survives (%d)" % RunManager.scrap)
	check_near(RunManager.enemy_health_scale, 1.5, "enemy scaling survives")
	check(RunManager.rooms_cleared == 4, "the cumulative room count survives")
	check(RunManager.stats.enemies_defeated == 9, "run statistics survive")
	check(
		RunManager.offered_item_ids.size() > offered_before,
		"the offered-item history is added to, not cleared",
	)
	check(
		RunManager.fought_boss_ids.size() == bosses_before + 1,
		"and the new floor's boss is recorded alongside the old one's",
	)

	check(floor_node._clears == 0, "the floor-local clear count resets")
	check(floor_node.visited.size() == 1, "only the new start room has been visited")
	check(
		floor_node.current_room_id == floor_node.layout.get_start_room().id,
		"and the player is standing in it",
	)

	arena.queue_free()
	await advance_physics(1)


## A destination that loads and will not generate. The old order tore the floor down first, so this
## left the run in `RUN` with no rooms, no doors, and a player in a void — reachable from a typo in
## a `.tres` and not recoverable from at all.
func _test_an_ungeneratable_destination_keeps_the_current_floor() -> void:
	print("    (the next FloorGenerator error is expected: refusing an impossible floor 2)")
	var campaign := _greybox_campaign(2, func(config: FloorConfig, index: int) -> void:
		if index == 1:
			config.room_count = 1
	)
	if not require(campaign, "a campaign with an impossible second floor builds"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node := _open_greybox(arena, campaign, 9119)
	if floor_node == null:
		arena.queue_free()
		await advance_physics(1)
		return

	var session := floor_node.get_session()
	var rooms := floor_node._rooms.size()

	await _descend(floor_node)

	check(GameManager.state == GameManager.State.RUN, "the run is still running")
	check(floor_node.get_session() == session, "the player keeps the floor they were standing on")
	check(is_instance_valid(session), "which has not been released")
	check(floor_node.config.floor_number == 1, "and is still floor 1")
	check(floor_node._rooms.size() == rooms, "with all %d of its rooms" % rooms)
	check(_sessions_under(floor_node) == 1, "and is the only floor in the tree")

	arena.queue_free()
	await advance_physics(1)


## Fights this floor's boss and takes its reward, which is the only thing that descends. Drives the
## handlers directly, the way every other floor-advance check in this file does.
func _descend(floor_node: FloorController) -> void:
	var boss_room := _find_boss_room(floor_node)
	if boss_room == null:
		fail("floor %d has no boss room to descend from" % floor_node.config.floor_number)
		return

	_defeat_boss(floor_node, boss_room)
	await advance_physics(1)

	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	# The rebuild is deferred, and so is the physics flush that follows it. One frame is not enough.
	await advance_physics(4)


## Builds a controller on `campaign`'s first floor. Returns null and records the failure if it will
## not open, so each check above can bail without repeating the reporting.
func _open_greybox(arena: Node2D, campaign: RunDefinition, seed_value: int) -> FloorController:
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.campaign = campaign
	floor_node.config = campaign.load_floor(0)
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)

	GameManager.start_run()
	RunManager.begin_run(seed_value, campaign)
	# The campaign's own derived seed for its first floor, not the run seed raw. Either builds a
	# floor, but only this one is the floor a real run would have opened on — and these checks are
	# about what a real descent does.
	if not floor_node.build(player, campaign.floor_seed_for(seed_value, 0)):
		fail("the greybox campaign's first floor would not build")
		return null
	return floor_node


## Delegates to `GreyboxCampaign`, reporting a build failure against this suite rather than
## letting it surface as a null nobody attributes.
func _greybox_campaign(count: int, mutate := Callable()) -> RunDefinition:
	var campaign := _greybox.build(count, mutate)
	if campaign == null:
		fail(_greybox.error)
	return campaign


func _sessions_under(floor_node: FloorController) -> int:
	var found := 0
	for child: Node in floor_node.get_children():
		if child is FloorSession:
			found += 1
	return found


## Nodes answering as the projectile container beneath `node`. Tree-wide rather than by reading the
## session's own child, because the failure is a *second* container answering first — a session
## left in the tree while the next one is built — and asking the session would never see it.
func _containers_under(node: Node) -> int:
	var found := 0
	for candidate: Node in node.get_tree().get_nodes_in_group(ProjectileFactory.CONTAINER_GROUP):
		if node.is_ancestor_of(candidate):
			found += 1
	return found


func _first_pickup_under(node: Node) -> Pickup:
	for candidate: Node in node.get_tree().get_nodes_in_group(Pickup.GROUP):
		if node.is_ancestor_of(candidate):
			return candidate as Pickup
	return null


func _first_enemy_under(node: Node) -> Node:
	for candidate: Node in node.get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		if node.is_ancestor_of(candidate):
			return candidate
	return null


func _first_door(floor_node: FloorController) -> Door:
	for doors: Array in floor_node._doors_by_room.values():
		for door: Door in doors:
			if is_instance_valid(door):
				return door
	return null

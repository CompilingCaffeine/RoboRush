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

## Seeds to sweep. Enough that a rare structural bug has to be very rare to survive.
const SEED_COUNT := 120

var _config: FloorConfig


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
	await _test_repair_cells_drop_on_every_third_clear()
	await _test_boss_defeat_advances_to_the_next_floor_and_only_the_last_wins()


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


## The four requirements from spec section 9, swept across many seeds.
func _test_invariants_across_seeds() -> void:
	var failures := PackedStringArray()
	var dead_end_specials := 0
	var multi_door_rooms := 0
	var boss_is_farthest := 0

	for offset: int in SEED_COUNT:
		var seed_value := 1000 + offset * 37
		var layout := FloorGenerator.generate(_config, seed_value)
		if layout == null:
			failures.append("seed %d failed to generate" % seed_value)
			continue

		if layout.rooms.size() != _config.room_count:
			failures.append("seed %d produced %d rooms, expected %d" % [
				seed_value, layout.rooms.size(), _config.room_count,
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

	check(failures.is_empty(), "all invariants hold across %d seeds" % SEED_COUNT)
	for failure: String in failures.slice(0, 6):
		fail(failure)

	check(
		dead_end_specials == SEED_COUNT * 3,
		"every seed's treasure, shop, and boss rooms are all dead ends",
	)
	check(
		boss_is_farthest == SEED_COUNT,
		"the boss room is always the furthest room from the start (%d of %d seeds)" % [
			boss_is_farthest, SEED_COUNT,
		],
	)
	# Guards against the generator degenerating into a single corridor, which would satisfy
	# every requirement above and still be dull.
	check(multi_door_rooms > SEED_COUNT, "floors branch rather than forming one chain")


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


## Step 1 of multi-level: floor 1 chains to a duplicate as floor 2 via `FloorConfig.next_floor`.
## Defeating a boss must advance the run into the next floor rather than end it, and only the
## *last* floor's boss may reach victory. Drives the boss-defeat handlers directly, the same way
## `_test_repair_cells_drop_on_every_third_clear` drives `_on_room_cleared` directly above.
func _test_boss_defeat_advances_to_the_next_floor_and_only_the_last_wins() -> void:
	var floor_config: FloorConfig = load(FLOOR_CONFIG_PATH) as FloorConfig
	if not require(floor_config.next_floor, "floor 1 has a next floor configured"):
		return

	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	GameManager.start_run()
	RunManager.begin_run(9001)
	check(floor_node.build(player, 9001), "floor 1 builds")

	var boss_room := _find_boss_room(floor_node)
	if require(boss_room, "floor 1 has a boss room"):
		floor_node._on_boss_defeated(Node.new(), boss_room)
		await advance_physics(1)
		check(
			GameManager.state == GameManager.State.RUN,
			"defeating floor 1's boss does not end the run",
		)

		floor_node._on_boss_reward_taken(floor_config.item_pool[0])
		await advance_physics(1)
		check(
			GameManager.state == GameManager.State.RUN,
			"taking floor 1's reward advances, not wins",
		)
		check(RunManager.floor_number == 2, "RunManager reports floor 2")
		check(
			floor_node.config == floor_config.next_floor,
			"the controller rebuilt from floor 2's config",
		)
		check(floor_node._clears == 0, "floor 2 starts with a clean clear count")
		check(floor_node.visited.size() == 1, "floor 2 starts with only its own start room visited")

		var boss_room_2 := _find_boss_room(floor_node)
		if require(boss_room_2, "floor 2 has a boss room"):
			floor_node._on_boss_defeated(Node.new(), boss_room_2)
			floor_node._on_boss_reward_taken(floor_config.next_floor.item_pool[0])
			await advance_physics(1)
			check(
				GameManager.state == GameManager.State.VICTORY,
				"defeating the last floor's boss wins the run",
			)

	# Winning pauses the tree (GameManager._set_state); leaving it paused would break every
	# suite that runs after this one and needs physics frames to actually advance.
	GameManager.start_run()
	arena.queue_free()
	await advance_physics(1)


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

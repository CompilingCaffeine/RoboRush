class_name FloorGenerator
extends RefCounted
## Builds a floor's room graph from a FloorConfig and a seed.
##
## Spec section 9 sets four hard requirements, and each is met by construction rather than
## by generating a candidate and testing it:
##
## 1. **No overlapping rooms** — rooms live in grid cells and a cell is claimed exactly
##    once, so two rooms cannot occupy the same space.
## 2. **No disconnected rooms** — every room after the first is attached to a room that
##    already exists, so the graph is a connected tree the moment it is built.
## 3. **The far room is reachable** — follows from 2.
## 4. **Treasure must not block progression** — the treasure room is added *last*, attached
##    to a single existing room, which makes it a dead end. A dead end can never be a
##    cut vertex, so no path to anything else can run through it.
##
## The shop and the boss room are attached the same way and for the same reason: three
## special rooms, all dead ends, none of them on the route to anything. The boss takes the
## cell furthest from the start, because the end of a floor should be somewhere the player
## walked *to* rather than somewhere they passed on the way.
##
## Generation is seeded and deterministic: the same seed always produces the same floor,
## which is what makes the layout testable at all.

const MAX_PLACEMENT_ATTEMPTS := 400


## The special rooms every floor gets exactly one of, in the order they are attached. The
## boss goes first so it can claim the furthest cell before the others take it.
const SPECIAL_TYPES: Array[RoomTemplate.Type] = [
	RoomTemplate.Type.BOSS,
	RoomTemplate.Type.TREASURE,
	RoomTemplate.Type.SHOP,
]


## Returns null and pushes an error if the config cannot produce a valid floor, rather than
## handing back a half-built layout.
static func generate(config: FloorConfig, seed_value: int) -> FloorLayout:
	var minimum := SPECIAL_TYPES.size() + 1
	if config.room_count < minimum:
		push_error(
			"FloorGenerator: room_count must be at least %d (a start, a boss, a treasure, and a shop)."
			% minimum
		)
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var layout := FloorLayout.new()
	layout.seed_value = seed_value

	layout.add_room(Vector2i.ZERO, RoomTemplate.Type.START)

	# Grow combat rooms, leaving a slot for each special room attached afterwards.
	var combat_target := config.room_count - SPECIAL_TYPES.size()
	if not _grow(layout, combat_target, rng):
		push_error("FloorGenerator: ran out of room to place %d rooms." % combat_target)
		return null

	for type: RoomTemplate.Type in SPECIAL_TYPES:
		# Only the boss insists on the furthest cell. Letting the treasure and the shop take
		# whichever dead end is going keeps them from always landing in the same corner.
		var farthest := type == RoomTemplate.Type.BOSS
		if not _attach_dead_end(layout, type, rng, farthest):
			push_error("FloorGenerator: could not attach a %s room." % RoomTemplate.Type.keys()[type])
			return null

	if not _assign_templates(layout, config, rng):
		return null

	# Cheap belt-and-braces on the two invariants worth crashing over in a debug build.
	assert(layout.is_fully_connected(), "FloorGenerator produced a disconnected floor.")
	assert(layout.rooms.size() == config.room_count, "FloorGenerator produced the wrong room count.")
	return layout


## Attaches rooms one at a time to a random room that still has a free neighbouring cell.
## Growing from a random existing room (rather than always the newest) produces branching
## floors with dead ends instead of one long corridor.
static func _grow(layout: FloorLayout, target_count: int, rng: RandomNumberGenerator) -> bool:
	var attempts := 0
	while layout.rooms.size() < target_count:
		attempts += 1
		if attempts > MAX_PLACEMENT_ATTEMPTS:
			return false

		var anchor := layout.rooms[rng.randi_range(0, layout.rooms.size() - 1)]
		var free := _free_neighbour_cells(layout, anchor)
		if free.is_empty():
			continue

		var cell: Vector2i = free[rng.randi_range(0, free.size() - 1)]
		var room := layout.add_room(cell, RoomTemplate.Type.COMBAT)
		layout.link(anchor, room)

		# Also connect to any other already-placed neighbours. Without this the floor is a
		# tree and every route is forced; with it, rooms that happen to touch are joined and
		# the player gets loops to move through.
		for direction: Vector2i in FloorLayout.DIRECTIONS:
			var neighbour_cell := cell + direction
			if not layout.by_cell.has(neighbour_cell):
				continue
			var neighbour := layout.get_room(layout.by_cell[neighbour_cell])
			if neighbour.id == anchor.id or room.doors.has(direction):
				continue
			layout.link(room, neighbour)

	return true


## Attaches one room of `type` to exactly one existing room, which makes it a guaranteed
## dead end. Extra adjacent links are deliberately NOT added here — that is the whole point,
## and adding them could put a route to somewhere else through a special room.
##
## `farthest` picks the anchor furthest from the start; otherwise any room with a free
## neighbouring cell will do. Combat rooms are preferred as anchors either way, so the
## special rooms hang off the floor rather than off each other — a shop reachable only
## through the treasure vault is a worse floor than one where both are their own detour.
static func _attach_dead_end(
	layout: FloorLayout, type: RoomTemplate.Type, rng: RandomNumberGenerator, farthest: bool
) -> bool:
	var distances := layout.distances_from(layout.get_start_room())

	var candidates: Array[RoomPlan] = []
	var best_distance := -1
	for room: RoomPlan in layout.rooms:
		if room.type != RoomTemplate.Type.COMBAT and room.type != RoomTemplate.Type.START:
			continue
		if _free_neighbour_cells(layout, room).is_empty():
			continue
		if not farthest:
			candidates.append(room)
			continue

		var distance: int = distances.get(room.id, -1)
		if distance > best_distance:
			best_distance = distance
			candidates = [room]
		elif distance == best_distance:
			candidates.append(room)

	if candidates.is_empty():
		return false

	var anchor: RoomPlan = candidates[rng.randi_range(0, candidates.size() - 1)]
	var free := _free_neighbour_cells(layout, anchor)
	var cell: Vector2i = free[rng.randi_range(0, free.size() - 1)]
	var room := layout.add_room(cell, type)
	layout.link(anchor, room)
	return true


static func _free_neighbour_cells(layout: FloorLayout, room: RoomPlan) -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for direction: Vector2i in FloorLayout.DIRECTIONS:
		var cell := room.cell + direction
		if not layout.by_cell.has(cell):
			free.append(cell)
	return free


## Picks a template per room. Combat templates are capped by distance from the start before
## the existing no-immediate-repeat filter, and drawn without immediate repetition where
## possible, so a floor does not present the same layout twice in a row.
static func _assign_templates(
	layout: FloorLayout, config: FloorConfig, rng: RandomNumberGenerator
) -> bool:
	var distances := layout.distances_from(layout.get_start_room())
	var max_distance := 0
	for room: RoomPlan in layout.rooms:
		max_distance = maxi(max_distance, distances.get(room.id, 0))

	var last_combat_id := &""
	for room: RoomPlan in layout.rooms:
		var pool := config.templates_for(room.type)
		if pool.is_empty():
			push_error("FloorGenerator: no eligible templates for room type %d on floor %d." % [
				room.type, config.floor_number,
			])
			return false

		if room.type == RoomTemplate.Type.COMBAT:
			pool = _capped_by_distance(pool, distances.get(room.id, 0), max_distance)
			if pool.size() > 1:
				var filtered: Array[RoomTemplate] = []
				for template: RoomTemplate in pool:
					if template.id != last_combat_id:
						filtered.append(template)
				pool = filtered

		room.template = pool[rng.randi_range(0, pool.size() - 1)]
		if room.type == RoomTemplate.Type.COMBAT:
			last_combat_id = room.template.id

	return true


## Combat rooms near the start draw only from the floor's easier templates; rooms near the
## boss may draw anything, capped linearly in between. This is what makes "introduce the new
## enemy near the entrance, save the hardest combinations for the approach to the boss"
## (README's Floor 2 plan) actually happen, rather than being left to an independent weighted
## roll that has no idea where in the floor it is running.
##
## Falls back to the unfiltered pool if the cap would leave nothing eligible — a floor whose
## easiest template is still harder than the cap allows must still generate a room.
static func _capped_by_distance(
	pool: Array[RoomTemplate], distance: int, max_distance: int
) -> Array[RoomTemplate]:
	var hardest := 0
	for template: RoomTemplate in pool:
		hardest = maxi(hardest, template.difficulty)
	if hardest <= 1:
		return pool

	var progress := float(distance) / float(maxi(max_distance, 1))
	var cap := 1 + roundi(progress * float(hardest - 1))

	var capped: Array[RoomTemplate] = []
	for template: RoomTemplate in pool:
		if template.difficulty <= cap:
			capped.append(template)
	return capped if not capped.is_empty() else pool

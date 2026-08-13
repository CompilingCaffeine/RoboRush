class_name FloorLayout
extends RefCounted
## A generated floor: which rooms exist, where, and what connects to what.
##
## Pure data with no nodes in it, so the floor can be generated and checked before anything
## is built. Every spec section 9 requirement is answerable from here alone.

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var rooms: Array[RoomPlan] = []

## Grid cell -> room id, so occupancy is a lookup rather than a scan.
var by_cell: Dictionary[Vector2i, int] = {}

## The seed this layout was generated from, which is the floor's *layout stream* rather than the
## floor's own seed — `RunRng.stream_seed(floor_seed, RunRng.LAYOUT)`. Worth the distinction: this
## number reproduces the layout when handed back to `FloorGenerator.generate`, and it is not the
## number `--seed=` takes.
var seed_value: int = 0


func get_room(id: int) -> RoomPlan:
	return rooms[id]


func get_start_room() -> RoomPlan:
	for room: RoomPlan in rooms:
		if room.type == RoomTemplate.Type.START:
			return room
	return rooms[0] if not rooms.is_empty() else null


func find_by_type(type: RoomTemplate.Type) -> Array[RoomPlan]:
	var found: Array[RoomPlan] = []
	for room: RoomPlan in rooms:
		if room.type == type:
			found.append(room)
	return found


## Adds a room and returns it. Refuses to reuse an occupied cell, which is what makes
## "rooms must not overlap" (spec section 9.4) structurally impossible to violate.
func add_room(cell: Vector2i, type: RoomTemplate.Type) -> RoomPlan:
	assert(not by_cell.has(cell), "FloorLayout: cell %v is already occupied." % cell)
	var room := RoomPlan.new(rooms.size(), cell, type)
	rooms.append(room)
	by_cell[cell] = room.id
	return room


## Connects two adjacent rooms with a door in both directions. A one-way door would be a
## bug, so the link is always symmetric.
func link(first: RoomPlan, second: RoomPlan) -> void:
	var offset := second.cell - first.cell
	assert(offset in DIRECTIONS, "FloorLayout: %v and %v are not adjacent." % [
		first.cell, second.cell,
	])
	first.doors[offset] = second.id
	second.doors[-offset] = first.id


## Breadth-first distance in doors from `origin` to every reachable room. Rooms that cannot
## be reached are absent from the result, which is how the connectivity check works.
func distances_from(origin: RoomPlan) -> Dictionary[int, int]:
	var distances: Dictionary[int, int] = {origin.id: 0}
	var queue: Array[int] = [origin.id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var distance: int = distances[current]
		for neighbour_id: int in rooms[current].doors.values():
			if distances.has(neighbour_id):
				continue
			distances[neighbour_id] = distance + 1
			queue.append(neighbour_id)
	return distances


## Spec section 9.3: the map must not contain disconnected rooms.
func is_fully_connected() -> bool:
	if rooms.is_empty():
		return true
	return distances_from(get_start_room()).size() == rooms.size()


## The grid rectangle the floor occupies, in cells. Used to size the minimap.
func get_cell_bounds() -> Rect2i:
	if rooms.is_empty():
		return Rect2i()
	var bounds := Rect2i(rooms[0].cell, Vector2i.ONE)
	for room: RoomPlan in rooms:
		bounds = bounds.expand(room.cell).expand(room.cell + Vector2i.ONE)
	return bounds

class_name FloorDoors
extends RefCounted
## Which doors belong to which room on one floor, and the one operation anything asks of them:
## seal a room, or open it.
##
## A door is shared by the two rooms it joins, so it is listed under both. Locking one room's doors
## therefore also closes that passage from the neighbour's side, which is what sealing a room means.
##
## Holds references, not nodes: the doors themselves are children of the floor session and are freed
## with it. `FloorController` makes a new one of these per floor, so a stale list cannot outlive the
## floor it describes.

var _by_room: Dictionary[int, Array] = {}


## Lists `door` under each room it joins.
func add(door: Door, room_ids: Array[int]) -> void:
	for id: int in room_ids:
		if not _by_room.has(id):
			_by_room[id] = []
		_by_room[id].append(door)


## The doors of one room, in the order they were built. Empty for a room with none.
func of_room(id: int) -> Array:
	return _by_room.get(id, [])


## Every door on the floor, each once, in the order it was built.
func all() -> Array[Door]:
	var seen: Array[Door] = []
	for doors: Array in _by_room.values():
		for door: Door in doors:
			if door not in seen:
				seen.append(door)
	return seen


## Locks or unlocks a room's doors, and reports a change only when a door actually moved, so
## re-entering a cleared room does not replay the door sound every time.
func set_locked(id: int, locked: bool) -> void:
	var changed := false
	for door: Door in of_room(id):
		if door.is_locked() == locked:
			continue
		if locked:
			door.lock()
		else:
			door.unlock()
		changed = true

	if changed:
		EventBus.doors_changed.emit(locked)

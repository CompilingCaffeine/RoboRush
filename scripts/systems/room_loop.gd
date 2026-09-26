class_name RoomLoop
extends Node
## Spec section 4's room loop, for one floor: enter a room, doors lock, enemies are live, kill them,
## doors unlock, a reward drops.
##
## Floor-local, and parented inside the floor's session like the rest of the floor: it is made when a
## floor opens, and it and everything it knows — which room the player is in, what they have seen,
## what they have cleared — go when the floor does. `FloorController` owns that lifecycle and the
## floor's public face; this owns what happens between two doors.
##
## It knows about the boss only as a room that stays sealed until it is cleared. Who is in that room
## and what they leave behind is `BossArena`'s, and the two meet in exactly two places: entering an
## uncleared arena (`boss_room_entered`) and the arena being won (`open_after_boss`).

## Emitted whenever the player enters a room, including re-entering a cleared one, after the room is
## awake, sealed or opened, and announced on the EventBus.
signal room_entered(plan: RoomPlan)

## Emitted when the player walks into an arena that has not been won. The floor wakes the boss in
## answer. Emitted before the doors seal and before the entry is announced, so the fight is named
## by the time anything listening to the entry looks for it.
signal boss_room_entered()

## Where an item drops relative to the reward point, so it does not land underneath the scrap that
## drops alongside it.
const ITEM_REWARD_OFFSET := Vector2(0.0, -18.0)

## The room the player is in, by id. -1 before they are placed.
var current_room_id := -1

## Room ids the player has been inside, for the minimap.
var visited: Dictionary[int, bool] = {}

## Combat rooms cleared on this floor, counted here rather than read from RunManager. The floor is
## notified through the room's own `cleared` signal, which fires before the EventBus one that
## RunManager counts — so reading that counter here would silently be reading the number from
## *before* this clear.
var clears := 0

## This floor's rooms by id, handed over once they are built (`attach`).
var rooms: Dictionary[int, Room] = {}

var _cleared: Dictionary[int, bool] = {}
var _doors := FloorDoors.new()
var _config: FloorConfig
var _player: Player
var _loot: LootSpawner

## Frames the camera on a room — `FloorController.get_view_rect_for`, which knows the viewport.
var _view_for := Callable()


## Readies the loop for a floor before its rooms are built, carrying over what a resumed run had
## already done here: the rooms it cleared and visited, and how many combat clears it had counted.
## The rooms need the cleared set while they are built, which is why it arrives first.
func setup(
	config: FloorConfig,
	player: Player,
	loot: LootSpawner,
	view_for: Callable,
	cleared_ids: Array[int],
	visited_ids: Array[int],
	clear_count: int,
) -> void:
	_config = config
	_player = player
	_loot = loot
	_view_for = view_for
	clears = clear_count
	for id: int in cleared_ids:
		_cleared[id] = true
	for id: int in visited_ids:
		visited[id] = true


## The rooms and doors this floor was built with, and the loop wired to every room: the player
## walking in, and its enemies all falling.
func attach(built_rooms: Dictionary[int, Room], doors: FloorDoors) -> void:
	rooms = built_rooms
	_doors = doors
	for id: int in rooms:
		rooms[id].player_entered.connect(_on_player_entered_room)
		rooms[id].get_room_combat().cleared.connect(record_clear.bind(id))


## The cleared set, live, for the builder: combat rooms a resumed run had already fought through
## are built empty.
func cleared_set() -> Dictionary[int, bool]:
	return _cleared


func get_doors() -> FloorDoors:
	return _doors


func get_room(id: int) -> Room:
	return rooms.get(id)


func get_current_room() -> Room:
	return rooms.get(current_room_id)


func is_room_cleared(id: int) -> bool:
	return _cleared.get(id, false)


## Records a room as cleared without opening it — for putting back a saved run's progress. The loop
## itself clears rooms through `record_clear` and `open_after_boss`, which also open the doors.
func mark_cleared(id: int) -> void:
	_cleared[id] = true


## Cleared room ids, for a checkpoint.
func cleared_room_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _cleared:
		if _cleared[id]:
			ids.append(id)
	return ids


## Visited room ids, for a checkpoint.
func visited_room_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in visited:
		if visited[id]:
			ids.append(id)
	return ids


## Puts the player in the start room and enters it. The entry Area2D will not fire for a body
## already inside it at spawn, so the start room is entered explicitly.
func place_player_at_start(start_id: int) -> void:
	var room := rooms[start_id]
	_player.global_position = room.get_interior_centre()
	_player.frame_room(_view_for.call(room), true)
	enter(start_id)


## Enters room `id`: frames it, wakes it, puts the previous room to sleep, and seals or opens it.
func enter(id: int) -> void:
	var previous_id := current_room_id
	current_room_id = id
	visited[id] = true

	var room := rooms[id]
	# Not snapped: the camera pans across the doorway, which shows the player where they came
	# from and reads as one continuous space rather than a cut.
	_player.frame_room(_view_for.call(room), false)

	if previous_id >= 0 and previous_id != id:
		rooms[previous_id].set_active(false)
	room.set_active(true)

	# Not for an arena a resumed run had already won. Without the clearing check a player who saved
	# after killing the boss and before taking the reward would walk back into a second one — and
	# `fought_boss_ids` would deny them the credit for it, so it would be a fight for nothing.
	if room.plan.type == RoomTemplate.Type.BOSS and not is_room_cleared(id):
		boss_room_entered.emit()

	if _needs_clearing(id):
		_doors.set_locked(id, true)
	else:
		_doors.set_locked(id, false)
		_award_first_visit(id)

	EventBus.room_entered.emit(room.plan.type, room.plan.id)
	room_entered.emit(room.plan)


## A combat room has been cleared: open it and pay out. Connected to each room's `RoomCombat.cleared`
## in `attach`.
func record_clear(id: int) -> void:
	_cleared[id] = true
	_doors.set_locked(id, false)
	clears += 1

	var room := rooms[id]
	# Every third room clear (see `FloorConfig.repair_every_clears`) also drops a repair cell, so
	# integrity is recoverable without making it so plentiful that damage stops mattering.
	#
	# Counted from `clears` above, not from `RunManager.rooms_cleared`. RoomCombat emits its local
	# `cleared` signal — which is what brought us here — *before* the EventBus one that RunManager
	# counts, so that value is still one behind while this runs. Reading it dropped repair cells on
	# clears 1 and 4 instead of 3 and 6: the first arriving while the player was still at full
	# integrity and could not use it.
	_loot.spawn_room_reward(room.get_reward_position(), _config.clear_drops_repair(clears))

	# Items are the reason to keep fighting rather than to run for the exit, so most of a floor's
	# items come from clearing rooms rather than from the one treasure vault.
	if _config.clear_drops_item(clears):
		_loot.spawn_item(room.get_reward_position() + ITEM_REWARD_OFFSET)


## The boss has fallen: the arena is cleared and its doors open, before the prize goes up. See
## `BossArena` for why nothing else is made safe at this moment.
func open_after_boss(room_id: int) -> void:
	_cleared[room_id] = true
	_doors.set_locked(room_id, false)


## The trigger is not taken at its word, because a descent can make it lie. The floor puts the new
## floor's rooms into the world before `place_player_at_start` moves the player off the old floor's
## coordinates, so the new room that lands on the spot the player took the boss reward from registers
## an overlap the moment it is added. Godot delivers that `body_entered` on the next physics flush —
## after the start room was entered explicitly, which is what let it win — and the room it names is a
## room the player has never been in.
##
## Cosmetic for a combat room, which is re-entered properly a moment later. Not cosmetic for the
## boss room: entering it wakes the boss, so Development opened with its boss already awake in an
## empty arena and its health bar on screen for the whole floor. Room ids are assigned in a fixed
## order (`FloorGenerator.SPECIAL_TYPES`), so the boss is id 7 on every ten-room floor and the two
## floors' boss rooms landing on the same cell is all it takes.
##
## Asking where the player actually is costs one rect test and never rejects a real entry: the entry
## Area2D is inset from the interior this is testing against, so a player far enough in to trip the
## trigger is comfortably inside the rect.
func _on_player_entered_room(room: Room) -> void:
	if room.plan.id == current_room_id:
		return
	if _player == null or not room.get_interior_rect().has_point(_player.global_position):
		return
	enter(room.plan.id)


## A room needs clearing if something in it is still alive and it has not already been cleared,
## which is also exactly when its doors should be shut. The boss counts: sealing the player in with
## it is the point of a boss room.
func _needs_clearing(id: int) -> bool:
	if is_room_cleared(id):
		return false
	if rooms[id].plan.type == RoomTemplate.Type.BOSS:
		# Not "is the boss alive": the boss is added a frame late (see `BossArena._add_boss`), and a
		# boss room whose doors stayed open for that frame is a boss room the player can walk straight
		# back out of. A boss room is sealed until it is cleared, full stop.
		return true
	return rooms[id].has_living_enemies()


## Payout for walking into a room that needs no fighting. The treasure room is the reason to explore
## a dead end rather than heading straight on.
func _award_first_visit(id: int) -> void:
	if _cleared.get(id, false):
		return
	_cleared[id] = true

	var room := rooms[id]
	if room.plan.type != RoomTemplate.Type.TREASURE:
		return
	if _config.treasure_grants_item:
		_loot.spawn_treasure(room.get_reward_position())
	else:
		_loot.spawn_room_reward(room.get_reward_position(), true)

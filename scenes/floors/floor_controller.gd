class_name FloorController
extends Node2D
## Builds a floor from a generated layout and runs the room loop.
##
## Every room is instantiated up front and laid out on the grid, the way a room-based shooter
## has always done it: the player walks through a doorway into the next room rather than
## triggering a scene load, so there is no transition to hide and no state to serialise. Rooms
## the player is not in have their enemies disabled, so ten rooms of AI is not ten rooms of
## work.
##
## The room loop from spec section 4 lives in `_on_player_entered_room` and
## `_on_room_cleared`: enter a room, doors lock, enemies are live, kill them, doors unlock, a
## reward drops. Everything else here is composition.

## Emitted when the player enters a room for any reason, including re-entering a cleared one.
signal room_entered(plan: RoomPlan)

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const DOOR_SCENE := preload("res://scenes/rooms/door.tscn")
const SHOP_ROOM_SCENE := preload("res://scenes/shop/shop_room.tscn")

## How far below the top of the screen a room's outer wall sits. The remaining space at the
## bottom is the HUD strip, so the HUD never covers playable floor.
const ROOM_TOP_MARGIN := 4

## Where an item drops relative to the reward point, so it does not land underneath the
## scrap that drops alongside it.
const ITEM_REWARD_OFFSET := Vector2(0.0, -18.0)

@export var config: FloorConfig

var layout: FloorLayout
var current_room_id := -1

## Room ids the player has been inside, for the minimap.
var visited: Dictionary[int, bool] = {}

var _rooms: Dictionary[int, Room] = {}
var _doors_by_room: Dictionary[int, Array] = {}
var _cleared: Dictionary[int, bool] = {}
var _player: Player
var _rng := RandomNumberGenerator.new()

## Combat rooms cleared on this floor, counted here rather than read from RunManager. The
## floor is notified through the room's own `cleared` signal, which fires before the
## EventBus one that RunManager counts — so reading that counter here would silently be
## reading the number from *before* this clear.
var _clears := 0

@onready var _rooms_container: Node2D = %Rooms
@onready var _doors_container: Node2D = %Doors
@onready var _loot: LootSpawner = %LootSpawner


## Generates and builds the floor. Returns false if generation failed, so the caller can
## report it rather than presenting an empty world.
func build(player: Player, seed_value: int) -> bool:
	assert(config != null, "FloorController.config is unset: assign a FloorConfig resource.")
	_player = player
	_rng.seed = seed_value

	layout = FloorGenerator.generate(config, seed_value)
	if layout == null:
		return false

	_loot.setup(config, seed_value)
	RunManager.floor_number = config.floor_number
	RunManager.floor_name = config.display_name
	RunManager.floor_seed = seed_value

	_instantiate_rooms()
	_instantiate_doors()
	_place_player_in_start_room()
	return true


func get_room(id: int) -> Room:
	return _rooms.get(id)


func get_current_room() -> Room:
	return _rooms.get(current_room_id)


func is_room_cleared(id: int) -> bool:
	return _cleared.get(id, false)


## The 480x270 view rectangle that frames a room. Horizontally centred; vertically pushed up
## so the HUD strip along the bottom does not cover the room.
func get_view_rect_for(room: Room) -> Rect2i:
	var view_size := Vector2i(get_viewport_rect().size)
	var outer := room.get_outer_rect()
	return Rect2i(
		Vector2i(outer.position.x - (view_size.x - outer.size.x) / 2, outer.position.y - ROOM_TOP_MARGIN),
		view_size
	)


func _instantiate_rooms() -> void:
	for plan: RoomPlan in layout.rooms:
		var room: Room = ROOM_SCENE.instantiate()
		# Grid cell to world: the room's interior origin sits one wall inside its cell.
		room.position = Vector2(plan.cell * Room.OUTER_SIZE + Vector2i.ONE * Room.WALL_THICKNESS)
		_rooms_container.add_child(room)

		room.build(plan)
		if plan.type == RoomTemplate.Type.COMBAT:
			room.populate(config, _rng)
		room.set_active(false)
		room.player_entered.connect(_on_player_entered_room)
		room.get_room_combat().cleared.connect(_on_room_cleared.bind(plan.id))
		_rooms[plan.id] = room


## Builds the shop's stands. Stocked at floor build time rather than on entry, so the
## items it holds are drawn from the pool before any room reward can take them — a shop
## whose stock depended on when the player happened to walk in would be a shop that got
## worse the longer they explored.
func _stock_shop(room: Room) -> void:
	var positions := room.get_shop_positions()
	if config.shop == null or positions.is_empty():
		return
	var shop: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	room.add_child(shop)
	shop.stock(config.shop, config.item_pool, positions, _rng.randi())


## One door per link, filling the passage between two rooms. Each link is visited once — the
## adjacency is symmetric, so iterating every room's doors would build each door twice.
func _instantiate_doors() -> void:
	for plan: RoomPlan in layout.rooms:
		for direction: Vector2i in plan.doors:
			var neighbour_id: int = plan.doors[direction]
			if neighbour_id < plan.id:
				continue

			var horizontal := direction.x != 0
			var passage := (
				Vector2i(Room.WALL_THICKNESS * 2, Room.DOOR_WIDTH) if horizontal
				else Vector2i(Room.DOOR_WIDTH, Room.WALL_THICKNESS * 2)
			)

			var door: Door = DOOR_SCENE.instantiate()
			_doors_container.add_child(door)
			door.global_position = _door_centre(plan, direction)
			door.setup(passage)

			for id: int in [plan.id, neighbour_id]:
				if not _doors_by_room.has(id):
					_doors_by_room[id] = []
				_doors_by_room[id].append(door)


## The midpoint of the shared boundary between a room's cell and its neighbour's.
func _door_centre(plan: RoomPlan, direction: Vector2i) -> Vector2:
	var outer_centre := Vector2(plan.cell * Room.OUTER_SIZE) + Vector2(Room.OUTER_SIZE) * 0.5
	return outer_centre + Vector2(direction) * Vector2(Room.OUTER_SIZE) * 0.5


func _place_player_in_start_room() -> void:
	var start := layout.get_start_room()
	var room := _rooms[start.id]
	_player.global_position = room.get_interior_centre()
	_player.frame_room(get_view_rect_for(room), true)
	# The entry Area2D will not fire for a body already inside it at spawn, so the start room
	# is entered explicitly.
	_enter_room(start.id)


func _on_player_entered_room(room: Room) -> void:
	if room.plan.id == current_room_id:
		return
	_enter_room(room.plan.id)


func _enter_room(id: int) -> void:
	var previous_id := current_room_id
	current_room_id = id
	visited[id] = true

	var room := _rooms[id]
	# Not snapped: the camera pans across the doorway, which shows the player where they came
	# from and reads as one continuous space rather than a cut.
	_player.frame_room(get_view_rect_for(room), false)

	if previous_id >= 0 and previous_id != id:
		_rooms[previous_id].set_active(false)
	room.set_active(true)

	if _needs_clearing(id):
		_set_doors_locked(id, true)
	else:
		_set_doors_locked(id, false)
		_award_first_visit(id)

	EventBus.room_entered.emit(room.plan.type, room.plan.id)
	room_entered.emit(room.plan)


## A room needs clearing if it is a combat room with enemies still alive and has not already
## been cleared, which is also exactly when its doors should be shut.
func _needs_clearing(id: int) -> bool:
	return not is_room_cleared(id) and _rooms[id].has_living_enemies()


func _on_room_cleared(id: int) -> void:
	_cleared[id] = true
	_set_doors_locked(id, false)
	_clears += 1

	var room := _rooms[id]
	# Every third room clear also drops a repair cell, so integrity is recoverable without
	# making it so plentiful that damage stops mattering.
	var include_repair := RunManager.rooms_cleared % 3 == 0
	_loot.spawn_room_reward(room.get_reward_position(), include_repair)

	# Items are the reason to keep fighting rather than to run for the exit, so most of a
	# floor's items come from clearing rooms rather than from the one treasure vault.
	if _clears in config.item_clear_indices:
		_loot.spawn_item(room.get_reward_position() + ITEM_REWARD_OFFSET)


## Payout for walking into a room that needs no fighting. The treasure room is the reason to
## explore a dead end rather than heading straight on.
func _award_first_visit(id: int) -> void:
	if _cleared.get(id, false):
		return
	_cleared[id] = true

	var room := _rooms[id]
	if room.plan.type != RoomTemplate.Type.TREASURE:
		return
	if config.treasure_grants_item:
		_loot.spawn_treasure(room.get_reward_position())
	else:
		_loot.spawn_room_reward(room.get_reward_position(), true)


## Only reports a change when a door actually moved, so re-entering a cleared room does not
## replay the door sound every time.
func _set_doors_locked(id: int, locked: bool) -> void:
	var changed := false
	for door: Door in _doors_by_room.get(id, []):
		if door.is_locked() == locked:
			continue
		if locked:
			door.lock()
		else:
			door.unlock()
		changed = true

	if changed:
		EventBus.doors_changed.emit(locked)

class_name FloorBuilder
extends RefCounted
## Turns a generated layout into rooms, doors and a shop inside a floor session.
##
## Construction only. It runs once per floor, holds nothing afterwards, and decides nothing about
## how the floor is played: `FloorController` owns the room loop, the boss and the boundary, and
## hands this the streams and callbacks it needs. Keeping the two apart is what keeps the
## controller about *running* a floor.
##
## The encounter and shop streams are consumed here in a fixed order — rooms in layout order, the
## shop at its place among them — and that order is part of what a seed reproduces. Change the
## iteration and every floor after the change populates differently.

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const DOOR_SCENE := preload("res://scenes/rooms/door.tscn")
const SHOP_ROOM_SCENE := preload("res://scenes/shop/shop_room.tscn")

## Which tile row of the shop room carries its sign. The second row from the top: above the stands
## and the two lines their tags are allowed to wrap onto, and below nothing — a shop room's own
## scenery is four corner blocks, and none of them is in the middle of this row.
const SHOP_SIGN_ROW := 1

## The rooms this floor was built with, by id, and its shop — null for a floor whose layout has no
## shop room or whose template declares no stands.
var rooms: Dictionary[int, Room] = {}
var shop: ShopRoom


## Instantiates every room in `layout` under `session.rooms`, populated and asleep.
##
## `cleared` is the set of room ids a resumed run had already fought through; those combat rooms are
## built empty. `populate` still draws from the encounter stream for them — see `Room.populate` — so
## the rooms after them get the same enemies they got the first time, and the floor stays the floor
## its seed describes rather than a different one that merely starts the same.
##
## `resumed_shop` is the shelf a resumed run left in this floor's shop, or null for a floor being
## opened for the first time.
##
## `on_entered` is connected to every room's `player_entered`, and `on_cleared` — bound to the room's
## id — to every room's `RoomCombat.cleared`.
func build_rooms(
	session: FloorSession,
	layout: FloorLayout,
	config: FloorConfig,
	encounter_rng: RandomNumberGenerator,
	shop_rng: RandomNumberGenerator,
	cleared: Dictionary[int, bool],
	resumed_shop: ShopStock,
	on_entered: Callable,
	on_cleared: Callable,
) -> void:
	for plan: RoomPlan in layout.rooms:
		var room: Room = ROOM_SCENE.instantiate()
		# Grid cell to world: the room's interior origin sits one wall inside its cell.
		room.position = Vector2(plan.cell * Room.OUTER_SIZE + Vector2i.ONE * Room.WALL_THICKNESS)
		session.rooms.add_child(room)

		room.build(plan, config.theme)
		if plan.type == RoomTemplate.Type.COMBAT:
			room.populate(config, encounter_rng, cleared.get(plan.id, false))
		elif plan.type == RoomTemplate.Type.SHOP:
			_stock_shop(room, config, shop_rng, resumed_shop)
		room.set_active(false)
		room.player_entered.connect(on_entered)
		room.get_room_combat().cleared.connect(on_cleared.bind(plan.id))
		rooms[plan.id] = room


## One door per link, filling the passage between two rooms, under `session.doors`. Each link is
## visited once — the adjacency is symmetric, so iterating every room's doors would build each door
## twice.
func build_doors(session: FloorSession, layout: FloorLayout) -> FloorDoors:
	var doors := FloorDoors.new()
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
			session.doors.add_child(door)
			door.global_position = door_centre(plan, direction)
			door.setup(passage)
			doors.add(door, [plan.id, neighbour_id] as Array[int])
	return doors


## The midpoint of the shared boundary between a room's cell and its neighbour's.
static func door_centre(plan: RoomPlan, direction: Vector2i) -> Vector2:
	var outer_centre := Vector2(plan.cell * Room.OUTER_SIZE) + Vector2(Room.OUTER_SIZE) * 0.5
	return outer_centre + Vector2(direction) * Vector2(Room.OUTER_SIZE) * 0.5


## Builds the shop's stands. Stocked at floor build time rather than on entry, so the items it holds
## are drawn from the pool before any room reward can take them — a shop whose stock depended on
## when the player happened to walk in would be a shop that got worse the longer they explored.
##
## The shop is handed one number from this floor's shop stream and seeds itself from it, rather than
## sharing a generator: the room it stands in is instantiated among nine others, and a shop reading
## from the stream the rooms are populated from would restock itself every time an enemy placement
## changed.
##
## `resumed_shop` is a shelf to put back rather than to draw. Handed straight to `stock`, which is
## what decides between the two — see `ShopRoom.stock` and `ShopStock` for why a resumed shop must
## not draw: its items were taken out of the run's pool the first time this floor was built, and
## drawing again would spend two more that the player never sees.
func _stock_shop(
	room: Room, config: FloorConfig, shop_rng: RandomNumberGenerator, resumed_shop: ShopStock
) -> void:
	var positions := room.get_shop_positions()
	if config.shop == null or positions.is_empty():
		return
	var built: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	room.add_child(built)
	built.stock(config.shop, config.get_items(), positions, shop_rng.randi(), resumed_shop)
	# The sign, above the stands and clear of their tags. Placed from here because the shop knows
	# where its stands are and nothing else, while the room knows where its walls are — see
	# `ShopRoom.place_sign` for why a shop says which key buys twice, in two different voices.
	built.place_sign(room.get_row_rect(SHOP_SIGN_ROW).get_center())
	shop = built

class_name RoomPlan
extends RefCounted
## One room's place in a generated floor, before anything is instantiated.
##
## The plan and the scene are kept separate on purpose: the layout can be generated,
## validated, and tested without building a single node, which is what makes the floor
## invariants in spec section 9 cheap to assert.

## Index into FloorLayout.rooms, and this room's identity everywhere else.
var id: int

## Grid cell. One cell is exactly one room, so distinct cells cannot overlap.
var cell: Vector2i

var type: RoomTemplate.Type

var template: RoomTemplate

## Grid direction -> neighbouring room id. A key present here means a door exists.
var doors: Dictionary[Vector2i, int] = {}


func _init(p_id: int, p_cell: Vector2i, p_type: RoomTemplate.Type) -> void:
	id = p_id
	cell = p_cell
	type = p_type


## Number of doors, i.e. this room's degree in the graph. A degree of 1 is a dead end.
func get_degree() -> int:
	return doors.size()


func get_door_directions() -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	for direction: Vector2i in doors:
		directions.append(direction)
	return directions

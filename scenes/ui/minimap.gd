class_name Minimap
extends Control
## The floor map, drawn from the generated layout.
##
## Spec section 9.5 and 9.6: explored rooms are shown, and *unexplored room types stay
## hidden*. That second half is the interesting one — a room the player has seen a door to is
## drawn as a blank cell, so the map tells them where they can go without telling them what is
## waiting. An item that reveals room types later only has to flip `reveal_all`.
##
## Drawn with _draw() rather than built from nodes: it is a dozen rectangles that change only
## when the player changes room, so a redraw is cheaper than keeping thirty nodes in sync.

const CELL := Vector2(9.0, 6.0)
const GAP := Vector2(3.0, 3.0)

const VISITED_COLOR := Color("3c4654")
const CURRENT_COLOR := Color("58f0c8")
const UNKNOWN_COLOR := Color("222a36")
const LINK_COLOR := Color("2f3947")
const TREASURE_COLOR := Color("f2a13c")
const START_COLOR := Color("6d7a8c")

## Inset from the top-right corner of the screen.
const MARGIN := 5.0

var _layout: FloorLayout
var _floor: FloorController

## Set by a future utility item (spec section 11: "Reveal secret rooms").
var reveal_all := false


func bind_floor(floor_controller: FloorController) -> void:
	_floor = floor_controller
	_layout = floor_controller.layout
	floor_controller.room_entered.connect(_on_room_entered)
	_resize_to_layout()
	queue_redraw()


func _on_room_entered(_plan: RoomPlan) -> void:
	queue_redraw()


## Sized from the floor's grid extent and pinned to the top-right corner through its anchors,
## so a wide floor grows leftwards instead of off the screen.
func _resize_to_layout() -> void:
	if _layout == null:
		return
	var bounds := _layout.get_cell_bounds()
	var wanted := Vector2(bounds.size) * (CELL + GAP) - GAP
	offset_left = -MARGIN - wanted.x
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + wanted.y


func _draw() -> void:
	if _layout == null:
		return

	var origin := _layout.get_cell_bounds().position

	# Links first, so room cells draw over the connector stubs.
	for room: RoomPlan in _layout.rooms:
		if not _is_known(room):
			continue
		for direction: Vector2i in room.doors:
			var neighbour := _layout.get_room(room.doors[direction])
			if not _is_known(neighbour):
				continue
			draw_line(
				_centre_of(room.cell - origin),
				_centre_of(neighbour.cell - origin),
				LINK_COLOR,
				1.0,
			)

	for room: RoomPlan in _layout.rooms:
		if not _is_known(room):
			continue
		var rect := Rect2(_top_left_of(room.cell - origin), CELL)
		draw_rect(rect, _colour_for(room))
		if room.id == _floor.current_room_id:
			# Outline rather than fill, so the current room reads even against its own colour.
			draw_rect(rect.grow(1.0), CURRENT_COLOR, false, 1.0)


## A room is drawn if the player has been in it, or if it is next to somewhere they have been
## — that is what makes the map show reachable doors without revealing the floor.
func _is_known(room: RoomPlan) -> bool:
	if reveal_all or _floor.visited.has(room.id):
		return true
	for neighbour_id: int in room.doors.values():
		if _floor.visited.has(neighbour_id):
			return true
	return false


## Unvisited rooms deliberately share one neutral colour: the shape of the floor is
## information the player has earned, the contents are not.
func _colour_for(room: RoomPlan) -> Color:
	if not (_floor.visited.has(room.id) or reveal_all):
		return UNKNOWN_COLOR
	match room.type:
		RoomTemplate.Type.START:
			return START_COLOR
		RoomTemplate.Type.TREASURE:
			return TREASURE_COLOR
		_:
			return VISITED_COLOR


func _top_left_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * (CELL + GAP)


func _centre_of(cell: Vector2i) -> Vector2:
	return _top_left_of(cell) + CELL * 0.5

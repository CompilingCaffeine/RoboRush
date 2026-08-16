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

## Set by a future utility item (spec section 11: "Reveal secret rooms"). Resizes as well as
## redrawing, because revealing the floor is the largest change the drawn extent ever makes and the
## frame is sized to that extent.
var reveal_all := false:
	set(value):
		if value == reveal_all:
			return
		reveal_all = value
		_resize_to_layout()
		queue_redraw()


func bind_floor(floor_controller: FloorController) -> void:
	# Guarded because a floor advance rebinds the same controller a second time: without this,
	# room_entered would end up double-connected and every room entry would redraw twice.
	if _floor != null and _floor.room_entered.is_connected(_on_room_entered):
		_floor.room_entered.disconnect(_on_room_entered)
	_floor = floor_controller
	_layout = floor_controller.layout
	floor_controller.room_entered.connect(_on_room_entered)
	_resize_to_layout()
	queue_redraw()


func _on_room_entered(_plan: RoomPlan) -> void:
	# Resized as well as redrawn: entering a room can reveal the ring of cells around it, and the
	# frame is sized to what is drawn rather than to the floor. See `_known_bounds`.
	_resize_to_layout()
	queue_redraw()


## Sized from the cells it is actually drawing and pinned to the top-right corner through its
## anchors, so a wide floor grows leftwards instead of off the screen.
func _resize_to_layout() -> void:
	if _layout == null:
		return
	var bounds := _known_bounds()
	if bounds.size == Vector2i.ZERO:
		return
	var wanted := Vector2(bounds.size) * (CELL + GAP) - GAP
	offset_left = -MARGIN - wanted.x
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + wanted.y


## The extent of the cells the map is drawing: visited rooms and the ring of doors leading off
## them, which is exactly what `_is_known` admits.
##
## Deliberately not `FloorLayout.get_cell_bounds`, which is the extent of the whole floor. Sized to
## that, the frame reserves room for cells it is not allowed to draw yet, and on the first room of
## a floor the player gets a panel several times wider than its contents with the four cells they
## know sitting wherever the generator happened to put the start room — off-centre, against
## whichever edge, with blank panel beside them. It reads as a map that has come loose from its
## frame. It also *is* the floor's width and height, which is the one thing about an unexplored
## floor this map is not supposed to be saying (spec section 9.6).
##
## The cost is that the map shifts when a reveal extends the bounds towards a pinned edge — the
## right one or the top one. That is the frame growing as the floor is explored, which is what the
## player has just done, and it beats a permanent hole in the corner of the screen.
func _known_bounds() -> Rect2i:
	var bounds := Rect2i()
	var found := false
	for room: RoomPlan in _layout.rooms:
		if not _is_known(room):
			continue
		if not found:
			bounds = Rect2i(room.cell, Vector2i.ONE)
			found = true
		else:
			bounds = bounds.expand(room.cell).expand(room.cell + Vector2i.ONE)
	return bounds


## How far the backing panel extends past the cells on each side.
const BACKING_PAD := 3.0


func _draw() -> void:
	if _layout == null:
		return

	# An opaque panel behind the cells, for the same reason the HUD strip has one: the map is
	# pinned to a corner of the screen and the room's own wall tiles are what is behind it.
	# A dim grey cell over a grey wall tile is not a map (spec section 21: keep gameplay
	# information readable).
	var panel := Rect2(Vector2.ZERO, size).grow(BACKING_PAD)
	draw_rect(panel, UIPalette.VOID)
	draw_rect(panel, UIPalette.PANEL_BORDER, false, 1.0)

	# The same origin the frame was sized from, or the cells would be drawn outside it.
	var origin := _known_bounds().position

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

extends TestCase
## The minimap's frame against the cells it is drawing.
##
## Reported from a browser playtest as the map being "not quite centred" in its corner, and it was
## not a centring problem at all: the frame was sized to the floor's full grid extent while `_draw`
## is only allowed to draw the rooms the player knows about. On the first room of a floor that is a
## panel several times wider than its contents, with the handful of known cells sitting wherever the
## generator happened to put the start room and blank panel filling the rest.
##
## So what is checked here is the relationship the bug broke — the frame is exactly the extent of
## what is drawn — rather than any particular size, which would only restate the arithmetic. The
## expected extent is worked out from the layout independently of the minimap, so a minimap that
## agreed with itself and disagreed with the floor still fails.
##
## Driven over several seeds because the defect is invisible on a floor whose known cells happen to
## span it: a single seed could pass a minimap that was never fixed. One seed where the floor is
## genuinely wider than the opening view is required, so this cannot quietly stop testing anything.

const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MINIMAP_SCENE := preload("res://scenes/ui/minimap.tscn")

const SEEDS: Array[int] = [4242, 9001, 17, 555_555]

var _arena: Node2D
var _floor: FloorController
var _map: Minimap


func run() -> void:
	await _test_the_frame_hugs_what_is_drawn()
	await _test_the_frame_still_hugs_after_walking_into_a_room()
	await _test_revealing_the_floor_grows_the_frame_to_it()


# --- Checks -------------------------------------------------------------------


## The bug itself, pinned on the opening view of a floor — one visited room and the ring of doors
## leading off it, which is the least the map ever draws and therefore the worst case for a frame
## sized to anything else.
func _test_the_frame_hugs_what_is_drawn() -> void:
	var any_floor_bigger_than_its_opening_view := false

	for seed_value: int in SEEDS:
		if not await _build(seed_value):
			continue

		var known := _known_extent()
		check(
			_map.size.is_equal_approx(_frame_for(known)),
			"seed %d: the frame is the extent of the cells drawn (%v for %v cells, got %v)"
			% [seed_value, _frame_for(known), known, _map.size],
		)
		check(
			_drawn_cells_fit_inside_the_frame(),
			"seed %d: and every drawn cell sits inside it" % seed_value,
		)
		check(
			_is_pinned_to_the_top_right_corner(),
			"seed %d: still pinned to the corner at %v (viewport %v)"
			% [seed_value, _map.position, get_viewport().get_visible_rect().size],
		)

		if _floor.layout.get_cell_bounds().size != known:
			any_floor_bigger_than_its_opening_view = true

		await _teardown()

	check(
		any_floor_bigger_than_its_opening_view,
		"at least one seed opens on a floor wider than the map may draw, or this suite is vacuous",
	)


## The half that is easy to break by fixing the other half. The frame is recomputed on room entry,
## so an entry that revealed new cells and did not resize would draw them outside the panel — the
## same bug wearing the opposite sign.
func _test_the_frame_still_hugs_after_walking_into_a_room() -> void:
	if not await _build(SEEDS[0]):
		return

	var start := _floor.layout.get_start_room()
	var opening := _map.size
	var moved := false

	for neighbour_id: int in start.doors.values():
		_floor._enter_room(neighbour_id)
		await advance_physics(1)
		moved = true

		var known := _known_extent()
		check(
			_map.size.is_equal_approx(_frame_for(known)),
			"after entering room %d the frame is %v, got %v"
			% [neighbour_id, _frame_for(known), _map.size],
		)
		check(
			_drawn_cells_fit_inside_the_frame(),
			"and every drawn cell still sits inside it",
		)
		check(
			_is_pinned_to_the_top_right_corner(),
			"and it is still pinned to the corner",
		)

	check(moved, "the start room has a door to walk through")
	check(
		_map.size != opening or not moved,
		"and the map grew as rooms were revealed (opening %v, now %v)" % [opening, _map.size],
	)

	await _teardown()


## `reveal_all` is the one thing that changes the drawn extent without a room being entered, so it
## has to resize on its own. Sets it twice, because the setter short-circuits on an unchanged value
## and a guard written the other way round would resize on nothing and never on the flip.
func _test_revealing_the_floor_grows_the_frame_to_it() -> void:
	if not await _build(SEEDS[0]):
		return

	_map.reveal_all = true
	await advance_physics(1)

	check(
		_map.size.is_equal_approx(_frame_for(_floor.layout.get_cell_bounds().size)),
		"a revealed floor sizes the frame to the whole floor (%v, got %v)"
		% [_frame_for(_floor.layout.get_cell_bounds().size), _map.size],
	)
	check(
		_is_pinned_to_the_top_right_corner(),
		"and the wider frame still fits in the corner it is pinned to",
	)

	_map.reveal_all = false
	await advance_physics(1)
	check(
		_map.size.is_equal_approx(_frame_for(_known_extent())),
		"and putting it back shrinks the frame to what is known again",
	)

	await _teardown()


# --- What the minimap should be showing ---------------------------------------


## The cells the map is allowed to draw, worked out from the floor rather than from the minimap:
## rooms the player has visited, plus every room a visited one has a door to. Deliberately a second
## implementation of `Minimap._is_known` — the point of the checks above is that the frame and the
## drawing agree, and asking the minimap what it thinks it is drawing would assume that.
func _known_extent() -> Vector2i:
	var lowest := Vector2i.MAX
	var highest := Vector2i.MIN

	for room: RoomPlan in _floor.layout.rooms:
		if not _is_known(room):
			continue
		lowest = lowest.min(room.cell)
		highest = highest.max(room.cell)

	if lowest == Vector2i.MAX:
		return Vector2i.ZERO
	return highest - lowest + Vector2i.ONE


func _is_known(room: RoomPlan) -> bool:
	if _floor.visited.has(room.id):
		return true
	for neighbour_id: int in room.doors.values():
		if _floor.visited.has(neighbour_id):
			return true
	return false


## The panel a grid of `extent` cells asks for: cells with a gap between them and none outside.
func _frame_for(extent: Vector2i) -> Vector2:
	return Vector2(extent) * (Minimap.CELL + Minimap.GAP) - Minimap.GAP


func _drawn_cells_fit_inside_the_frame() -> bool:
	var frame := Rect2(Vector2.ZERO, _map.size)
	for room: RoomPlan in _floor.layout.rooms:
		if not _is_known(room):
			continue
		var cell := Rect2(_map._top_left_of(room.cell - _map._known_bounds().position), Minimap.CELL)
		if not frame.encloses(cell):
			return false
	return true


func _is_pinned_to_the_top_right_corner() -> bool:
	var viewport := get_viewport().get_visible_rect().size
	return (
		is_equal_approx(_map.position.x + _map.size.x, viewport.x - Minimap.MARGIN)
		and is_equal_approx(_map.position.y, Minimap.MARGIN)
	)


# --- Fixtures -----------------------------------------------------------------


## A real floor and a real minimap bound to it. Nothing here is a stand-in: the defect was in what
## the minimap made of a generated layout, and a hand-built layout would have been built to suit.
func _build(seed_value: int) -> bool:
	_arena = Node2D.new()
	add_child(_arena)

	_floor = FLOOR_SCENE.instantiate()
	_arena.add_child(_floor)

	var player: Player = PLAYER_SCENE.instantiate()
	_arena.add_child(player)
	await advance_physics(1)

	RunManager.begin_run(seed_value)
	if not _floor.build(player, seed_value):
		fail("seed %d: the floor does not build" % seed_value)
		await _teardown()
		return false

	# In a CanvasLayer, as it is in main.tscn: a Control anchored to the right edge resolves its
	# anchors against the viewport there, and against a Node2D's transform anywhere else.
	var layer := CanvasLayer.new()
	_arena.add_child(layer)
	_map = MINIMAP_SCENE.instantiate()
	layer.add_child(_map)
	await advance_physics(1)

	_map.bind_floor(_floor)
	await advance_physics(1)
	return true


func _teardown() -> void:
	if _arena != null:
		_arena.queue_free()
		_arena = null
	_floor = null
	_map = null
	await advance_physics(2)

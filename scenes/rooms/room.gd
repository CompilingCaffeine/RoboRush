class_name Room
extends Node2D
## One room, built from a RoomTemplate.
##
## Every room in the game is exactly the same size, which is what lets the floor lay them
## out on a grid where one cell is one room. Two consequences fall out of that and both are
## load-bearing: rooms can never overlap (spec section 9.4), and the camera can frame a whole
## room at once with no scrolling, which is what makes combat readable — the player can see
## every enemy and every projectile in the room they are standing in.
##
## The room's origin is the top-left of its *interior*, so a template's tile coordinates map
## straight to local pixels and the wall ring lives at negative coordinates.
##
## Walls are built in code rather than as a TileMap because a Godot TileMap's cell data is a
## binary blob that cannot be authored or reviewed as text. Building from a template's
## Rect2i list keeps room layouts diffable.

## Emitted when the player crosses into this room's interior.
signal player_entered(room: Room)

const TILE_SIZE := 16
const WALL_THICKNESS := TILE_SIZE

## Interior size in tiles. Roughly 2:1, close to the proportions of an arcade room.
const INTERIOR_TILES := Vector2i(26, 12)
const INTERIOR_SIZE := Vector2i(INTERIOR_TILES.x * TILE_SIZE, INTERIOR_TILES.y * TILE_SIZE)

## Outer footprint including the wall ring. This is the grid spacing the floor uses.
const OUTER_SIZE := Vector2i(
	INTERIOR_SIZE.x + WALL_THICKNESS * 2, INTERIOR_SIZE.y + WALL_THICKNESS * 2
)

## Width of a doorway opening, in tiles. Four rather than three so the opening centres on a
## tile boundary: the interior is 26x12 tiles, and an odd door width would put the gap on a
## half-tile and leave template coordinates unable to describe the space beside a door.
const DOOR_TILES := 4
const DOOR_WIDTH := DOOR_TILES * TILE_SIZE

## How far inside the interior the player must be before the room counts as entered. Stops a
## door locking while the player is still standing in the doorway.
const ENTRY_INSET := 20

const WALL_BLOCK := preload("res://scenes/rooms/wall_block.tscn")
const CABLE_DUCT := preload("res://scenes/rooms/cable_duct.tscn")

@onready var _floor: Sprite2D = %Floor
@onready var _walls: Node2D = %Walls
@onready var _thermals: Node2D = %Thermals
@onready var _pads: Node2D = %Pads
@onready var _obstacles: Node2D = %Obstacles
@onready var _enemies: Node2D = %Enemies
@onready var _bounds: Area2D = %Bounds
@onready var _bounds_shape: CollisionShape2D = %BoundsShape
@onready var _room_combat: RoomCombat = %RoomCombat

var plan: RoomPlan

## The floor's look, or null for a room built without one. Kept because walls and obstacles
## are built lazily during `build` and again nowhere else — but a room that later grows a
## destructible block would want it too.
var theme: FloorTheme


## Builds the room's geometry. Must be called after the room is in the tree.
##
## `room_theme` is optional and defaults to null, which keeps the textures authored into
## `room.tscn` and `wall_block.tscn`. Every test arena in the suite builds a room without one
## and should keep working without knowing themes exist.
func build(room_plan: RoomPlan, room_theme: FloorTheme = null) -> void:
	plan = room_plan
	theme = room_theme

	if theme != null and theme.floor_texture != null:
		_floor.texture = theme.floor_texture
	_floor.region_rect = Rect2(Vector2.ZERO, Vector2(INTERIOR_SIZE))
	_build_wall_ring(plan.get_door_directions())
	_build_obstacles()
	_build_ducts()
	_build_thermal_zones()
	_build_pads()
	_build_bounds()

	_bounds.body_entered.connect(_on_body_entered)


## Fills the template's spawn points with enemies drawn from the floor's roster.
##
## The template's own `difficulty` decides which enemies are eligible, so a harder layout
## gets a harder encounter without the generator having to know what either means. A point
## with a matching `forced_enemies` entry skips the roll entirely — see that field's doc.
##
## `already_cleared` builds the room empty, for a run resumed from a save taken after this room was
## fought through. The rolls still happen — every one of them, in the same order — and only the
## placing is skipped: `rng` is the floor's shared encounter stream, so a room that drew nothing
## would leave every room built after it holding the enemies of the room before, and a resumed
## floor would quietly stop being the floor its seed describes.
func populate(
	floor_config: FloorConfig, rng: RandomNumberGenerator, already_cleared := false
) -> void:
	if plan.template == null or floor_config == null:
		return

	var spawns := plan.template.enemy_spawns
	var forced := plan.template.forced_enemies
	for index: int in spawns.size():
		var scene: PackedScene = forced[index] if index < forced.size() else null
		if scene == null:
			scene = floor_config.pick_enemy(plan.template.difficulty, rng)
		if scene == null or already_cleared:
			continue
		var enemy: Node2D = scene.instantiate()
		enemy.position = _tile_centre(spawns[index])
		_enemies.add_child(enemy)

	# Called either way, and with nothing in it for a cleared room. `RoomCombat` treats a room that
	# never had an enemy as one that was never in combat, so it will not announce a clear for a
	# room whose clear was counted before the save.
	_room_combat.begin(_enemies)


## Enemies in rooms the player is not standing in must not think, shoot, or chase — both
## because it would be unfair and because ten rooms of active AI is wasted work.
func set_active(active: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_enemies.process_mode = mode
	# The throughput zones stop with the enemies. A zone left running in a room the player is not
	# in would heat nothing, hurt nobody, and still cost a physics step and a group lookup per
	# frame — and on the frame it filled, it would announce a vent into an empty room.
	_thermals.process_mode = mode
	# And the pads, for the same reason: each one asks the tree for the player every physics frame,
	# which is work worth nothing at all in a room the player is demonstrably not in.
	_pads.process_mode = mode


func get_room_combat() -> RoomCombat:
	return _room_combat


func has_living_enemies() -> bool:
	return _room_combat.get_alive_count() > 0


## The room's footprint including walls, in global coordinates. This is the grid cell the
## room occupies and what the camera frames.
func get_outer_rect() -> Rect2i:
	var top_left := Vector2i(global_position) - Vector2i.ONE * WALL_THICKNESS
	return Rect2i(top_left, OUTER_SIZE)


func get_interior_centre() -> Vector2:
	return global_position + Vector2(INTERIOR_SIZE) * 0.5


## The playable floor, in global coordinates — the outer rect without its wall ring. What
## anything that needs to place itself "somewhere in this room" should ask for.
func get_interior_rect() -> Rect2:
	return Rect2(global_position, Vector2(INTERIOR_SIZE))


## The full width of one tile row, in global coordinates. `row` is clamped into the interior,
## so a caller does not have to bounds-check before asking — a compile lane is always drawn
## somewhere real, never off the edge of the room it was told to appear in.
func get_row_rect(row: int) -> Rect2:
	var clamped := clampi(row, 0, INTERIOR_TILES.y - 1)
	return Rect2(
		global_position + Vector2(0.0, clamped * TILE_SIZE), Vector2(INTERIOR_SIZE.x, TILE_SIZE)
	)


## The full height of one tile column, in global coordinates. See `get_row_rect` for why `col`
## is clamped rather than asserted.
func get_column_rect(col: int) -> Rect2:
	var clamped := clampi(col, 0, INTERIOR_TILES.x - 1)
	return Rect2(
		global_position + Vector2(clamped * TILE_SIZE, 0.0), Vector2(TILE_SIZE, INTERIOR_SIZE.y)
	)


## An arbitrary block of tiles, in global coordinates. `size_tiles` is clamped to at least
## one tile per axis and at most the interior, and `top_left_tile` is then clamped so the
## whole block lands inside the room. Same contract as `get_row_rect` and `get_column_rect`
## for the same reason: a caller describing a hazard should never have to bounds-check
## before asking, and a compile lane should never be drawn half outside the room it is in.
func get_tile_block_rect(top_left_tile: Vector2i, size_tiles: Vector2i) -> Rect2:
	var span := Vector2i(
		clampi(size_tiles.x, 1, INTERIOR_TILES.x), clampi(size_tiles.y, 1, INTERIOR_TILES.y)
	)
	var tile := Vector2i(
		clampi(top_left_tile.x, 0, INTERIOR_TILES.x - span.x),
		clampi(top_left_tile.y, 0, INTERIOR_TILES.y - span.y)
	)
	return Rect2(global_position + Vector2(tile * TILE_SIZE), Vector2(span * TILE_SIZE))


## The interior tile containing a global point, clamped into the room. A point outside the
## room resolves to the nearest edge tile rather than to a negative index, so an enemy
## aiming at a player standing in a doorway still names a real tile.
func get_tile_at(point: Vector2) -> Vector2i:
	var local := point - global_position
	return Vector2i(
		clampi(floori(local.x / TILE_SIZE), 0, INTERIOR_TILES.x - 1),
		clampi(floori(local.y / TILE_SIZE), 0, INTERIOR_TILES.y - 1)
	)


## Where this room's shop stands go, in global coordinates. Empty for anything but a shop.
func get_shop_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if plan.template == null:
		return positions
	for tile: Vector2i in plan.template.shop_stands:
		positions.append(to_global(_tile_centre(tile)))
	return positions


## Where a room-clear reward or treasure appears.
func get_reward_position() -> Vector2:
	if plan.template == null:
		return get_interior_centre()
	return to_global(_tile_centre(plan.template.reward_spawn))


## Converts template tile coordinates to the centre of that tile, in local pixels.
func _tile_centre(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE_SIZE) + Vector2.ONE * TILE_SIZE * 0.5


func _build_wall_ring(open_sides: Array[Vector2i]) -> void:
	var width := INTERIOR_SIZE.x
	var height := INTERIOR_SIZE.y
	var thickness := WALL_THICKNESS

	# Top and bottom span the full width including the corners; the sides fill the gap
	# between them, so the ring is sealed with no overlapping bodies.
	_build_side(
		Vector2i.UP, Vector2i(-thickness, -thickness),
		Vector2i(width + thickness * 2, thickness), open_sides
	)
	_build_side(
		Vector2i.DOWN, Vector2i(-thickness, height),
		Vector2i(width + thickness * 2, thickness), open_sides
	)
	_build_side(
		Vector2i.LEFT, Vector2i(-thickness, 0), Vector2i(thickness, height), open_sides
	)
	_build_side(
		Vector2i.RIGHT, Vector2i(width, 0), Vector2i(thickness, height), open_sides
	)


## Builds one side of the ring, splitting it into two segments around a centred doorway if
## that side has a door. The gap is centred on the interior, so the openings of two adjacent
## rooms always line up.
func _build_side(
	direction: Vector2i, top_left: Vector2i, size: Vector2i, open_sides: Array[Vector2i]
) -> void:
	if direction not in open_sides:
		_add_wall(top_left, size)
		return

	if direction == Vector2i.UP or direction == Vector2i.DOWN:
		var gap_start := INTERIOR_SIZE.x / 2 - DOOR_WIDTH / 2
		var gap_end := gap_start + DOOR_WIDTH
		_add_wall(top_left, Vector2i(gap_start - top_left.x, size.y))
		_add_wall(
			Vector2i(gap_end, top_left.y), Vector2i(top_left.x + size.x - gap_end, size.y)
		)
		return

	var vertical_gap_start := INTERIOR_SIZE.y / 2 - DOOR_WIDTH / 2
	var vertical_gap_end := vertical_gap_start + DOOR_WIDTH
	_add_wall(top_left, Vector2i(size.x, vertical_gap_start - top_left.y))
	_add_wall(
		Vector2i(top_left.x, vertical_gap_end),
		Vector2i(size.x, top_left.y + size.y - vertical_gap_end)
	)


func _add_wall(top_left: Vector2i, size: Vector2i) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var block: WallBlock = WALL_BLOCK.instantiate()
	block.size = size
	block.texture = _wall_texture()
	block.position = Vector2(top_left)
	_walls.add_child(block)


## The theme's wall sheet, or null to leave the authored one alone. One accessor for both
## the perimeter and the obstacles, because a room whose walls and racks were made of
## different materials would look like two rooms.
func _wall_texture() -> Texture2D:
	return theme.wall_texture if theme != null else null


func _build_obstacles() -> void:
	if plan.template == null:
		return
	for tile_rect: Rect2i in plan.template.obstacles:
		var block: WallBlock = WALL_BLOCK.instantiate()
		block.size = tile_rect.size * TILE_SIZE
		block.texture = _wall_texture()
		block.position = Vector2(tile_rect.position * TILE_SIZE)
		_obstacles.add_child(block)


## Lays out this template's cable ducts, if it has any. See `CableDuct` for what they do.
##
## Into the same `Obstacles` container as the wall blocks, and that is deliberate: everything under
## it is solid level geometry the room owns and frees, and `tests/test_floor.gd` already walks that
## container to check the theme reached the geometry. A separate node would be a second place to
## remember. What tells a duct from a wall is its collision layer, which is the only place the
## difference is real.
func _build_ducts() -> void:
	if plan.template == null:
		return
	for tile_rect: Rect2i in plan.template.ducts:
		var duct: CableDuct = CABLE_DUCT.instantiate()
		duct.size = tile_rect.size * TILE_SIZE
		# No `texture` assignment, unlike a wall block. See `CableDuct` for why a duct is never
		# handed the floor's wall sheet.
		duct.position = Vector2(tile_rect.position * TILE_SIZE)
		_obstacles.add_child(duct)


## Lays out this template's throughput zones, if it has any. See `ThermalZone` for what they do and
## `RoomTemplate.thermal_zones` for why they are declared on the template rather than the floor.
##
## Under their own `Thermals` node, for the reason the enemies have one: `set_active` switches it
## off in every room the player is not standing in. A zone is cheap, but ten rooms of zones running
## a physics step and a group lookup each is the same wasted work ten rooms of AI would be — and a
## zone in a room nobody is in would go on venting into an empty room and announcing it.
##
## Drawn above the floor tiles and below anything solid, which is where a painted-on hazard belongs:
## it is furniture that bites, not a hazard spawned into the session the way a compile lane is, and
## it has no business outliving the room.
##
## Placed through `get_tile_block_rect`, which clamps a block into the interior — so a template
## whose zone runs off the edge of the room draws a zone at the edge rather than half outside it.
func _build_thermal_zones() -> void:
	if plan.template == null:
		return
	for tile_rect: Rect2i in plan.template.thermal_zones:
		ThermalZone.spawn(_thermals, get_tile_block_rect(tile_rect.position, tile_rect.size))


## Lays out this template's migration pads, if it has any. See `MigrationPad` for what they do and
## `RoomTemplate.pad_links` for why they are declared on the template rather than the floor.
##
## Both ends are spawned and then joined, rather than each pad resolving its own partner. A pad that
## looked its partner up would need something to look it up *in* — an index, a name, a second pass —
## and every one of those is a way for a link to be half built. Spawning a pair together means the
## only code that can make a pad is code that makes two and joins them.
##
## Under their own `Pads` node, and stopped with the enemies by `set_active` for the reason the
## thermal zones are: a pad asks the scene tree for the player every physics frame, and ten rooms of
## pads asking that in rooms nobody is standing in is the same wasted work ten rooms of AI would be.
##
## Placed through `get_tile_block_rect`, which clamps a block into the interior — so a template
## whose pad runs off the edge of the room gets a pad at the edge rather than one half outside it,
## and never an arrival point in a wall.
func _build_pads() -> void:
	if plan.template == null:
		return
	for index: int in plan.template.pad_links.size():
		var link: MigrationLink = plan.template.pad_links[index]
		if link == null or not link.is_valid():
			continue
		var first := MigrationPad.spawn(
			_pads, get_tile_block_rect(link.a.position, link.a.size), index
		)
		var second := MigrationPad.spawn(
			_pads, get_tile_block_rect(link.b.position, link.b.size), index
		)
		MigrationPad.link(first, second)


## The entry trigger is inset from the interior so it fires only once the player is clearly
## inside, never while they are still in the doorway.
func _build_bounds() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(INTERIOR_SIZE) - Vector2.ONE * ENTRY_INSET * 2.0
	_bounds_shape.shape = shape
	_bounds_shape.position = Vector2(INTERIOR_SIZE) * 0.5
	_bounds.collision_mask = Teams.LAYER_PLAYER


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_entered.emit(self)

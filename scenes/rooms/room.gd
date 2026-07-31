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

@onready var _floor: Sprite2D = %Floor
@onready var _walls: Node2D = %Walls
@onready var _obstacles: Node2D = %Obstacles
@onready var _enemies: Node2D = %Enemies
@onready var _bounds: Area2D = %Bounds
@onready var _bounds_shape: CollisionShape2D = %BoundsShape
@onready var _room_combat: RoomCombat = %RoomCombat

var plan: RoomPlan


## Builds the room's geometry. Must be called after the room is in the tree.
func build(room_plan: RoomPlan) -> void:
	plan = room_plan

	_floor.region_rect = Rect2(Vector2.ZERO, Vector2(INTERIOR_SIZE))
	_build_wall_ring(plan.get_door_directions())
	_build_obstacles()
	_build_bounds()

	_bounds.body_entered.connect(_on_body_entered)


## Fills the template's spawn points with enemies drawn from the floor's pool.
func populate(enemy_scenes: Array[PackedScene], rng: RandomNumberGenerator) -> void:
	if plan.template == null or enemy_scenes.is_empty():
		return

	for tile: Vector2i in plan.template.enemy_spawns:
		var scene: PackedScene = enemy_scenes[rng.randi_range(0, enemy_scenes.size() - 1)]
		var enemy: Node2D = scene.instantiate()
		enemy.position = _tile_centre(tile)
		_enemies.add_child(enemy)

	_room_combat.begin(_enemies)


## Enemies in rooms the player is not standing in must not think, shoot, or chase — both
## because it would be unfair and because ten rooms of active AI is wasted work.
func set_active(active: bool) -> void:
	_enemies.process_mode = (
		Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	)


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
	block.position = Vector2(top_left)
	_walls.add_child(block)


func _build_obstacles() -> void:
	if plan.template == null:
		return
	for tile_rect: Rect2i in plan.template.obstacles:
		var block: WallBlock = WALL_BLOCK.instantiate()
		block.size = tile_rect.size * TILE_SIZE
		block.position = Vector2(tile_rect.position * TILE_SIZE)
		_obstacles.add_child(block)


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

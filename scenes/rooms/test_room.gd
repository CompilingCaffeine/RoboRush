@tool
class_name TestRoom
extends Node2D
## The milestone 1 movement sandbox: a walled rectangle with pillars to slide
## along and corners to dash into.
##
## Larger than the 480x270 viewport on purpose, so camera follow and camera limits
## are actually exercised rather than assumed. The border wall ring is generated
## from `interior_size` so the collision and the camera bounds cannot disagree;
## the interior pillars are placed by hand in test_room.tscn.
##
## This is not a room template. Templates with door locations, spawn points, and
## difficulty scores (spec section 9) arrive with the room system in milestone 3.

const WALL_BLOCK := preload("res://scenes/rooms/wall_block.tscn")

## Grid unit the room is laid out on. Matches the placeholder texture size.
const TILE_SIZE := 16

## Thickness of the border wall ring, in pixels.
const WALL_THICKNESS := TILE_SIZE

## Playable floor area in pixels, measured from this node's origin. The border
## walls sit just outside it.
@export var interior_size := Vector2i(640, 384):
	set = _set_interior_size

@onready var _floor: Sprite2D = $Floor
@onready var _walls: Node2D = $Walls
@onready var _spawn: Marker2D = $PlayerSpawn
@onready var _room_combat: RoomCombat = %RoomCombat
@onready var _enemies: Node2D = %Enemies


func _ready() -> void:
	_rebuild()
	# @tool makes the wall ring previewable in the editor, but non-tool scripts do not
	# run there, so RoomCombat is only a plain Node at edit time and has no begin().
	if Engine.is_editor_hint():
		return
	# Safe here and nowhere earlier: Godot readies children before parents, so every
	# enemy and its HealthComponent is initialised by the time this runs.
	_room_combat.begin(_enemies)


## Where the player should start the run.
func get_spawn_position() -> Vector2:
	return _spawn.global_position


## The room's combat tracker, so the HUD and debug overlay can report progress
## without walking the tree to find it.
func get_room_combat() -> RoomCombat:
	return _room_combat


## The rectangle the camera must not scroll past: the interior plus its wall ring,
## so the player sees the room's edge but never the void beyond it.
func get_camera_bounds() -> Rect2i:
	var ring := Vector2i.ONE * WALL_THICKNESS
	return Rect2i(Vector2i(global_position) - ring, interior_size + ring * 2)


func _set_interior_size(value: Vector2i) -> void:
	interior_size = Vector2i(maxi(value.x, TILE_SIZE), maxi(value.y, TILE_SIZE))
	if is_node_ready():
		_rebuild()


func _rebuild() -> void:
	_floor.region_rect = Rect2(Vector2.ZERO, Vector2(interior_size))
	for existing: Node in _walls.get_children():
		existing.queue_free()
	_build_border()


func _build_border() -> void:
	var width := interior_size.x
	var height := interior_size.y
	var thickness := WALL_THICKNESS

	# Top and bottom run the full width including the corners; the sides fill the
	# gap between them, so the ring is sealed with no overlapping bodies.
	_add_wall(Vector2i(-thickness, -thickness), Vector2i(width + thickness * 2, thickness))
	_add_wall(Vector2i(-thickness, height), Vector2i(width + thickness * 2, thickness))
	_add_wall(Vector2i(-thickness, 0), Vector2i(thickness, height))
	_add_wall(Vector2i(width, 0), Vector2i(thickness, height))


func _add_wall(top_left: Vector2i, wall_size: Vector2i) -> void:
	var block: WallBlock = WALL_BLOCK.instantiate()
	block.size = wall_size
	block.position = Vector2(top_left)
	_walls.add_child(block)

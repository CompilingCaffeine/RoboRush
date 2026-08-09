@tool
class_name WallBlock
extends StaticBody2D
## A rectangular chunk of solid wall sized from one exported value.
##
## Its origin is the top left corner, which makes laying out a room a matter of
## grid coordinates rather than centre-point arithmetic. Setting `size` resizes
## the collision rectangle and the tiled sprite together, so the two can never
## drift apart.
##
## This is scaffolding for the movement sandbox. Real floors will be built from
## handcrafted room templates in milestone 3; a hand-authored TileMap is not
## editable as text, so blocks are the honest choice until the editor is in play.

## Size in pixels. Multiples of the room's tile size keep the texture tiling clean.
@export var size := Vector2i(16, 16):
	set = _set_size

## The tile sheet this block repeats. Assigned from the floor's theme; null keeps whatever
## the scene was authored with, which is what an unthemed floor and every test arena get.
##
## A property with a setter rather than a method, so it can be assigned before the block
## enters the tree the same way `size` can — the room builds a block, sets both, and adds it,
## and neither ordering produces a frame of the wrong texture.
@export var texture: Texture2D:
	set = _set_texture

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	_apply_size()
	_apply_texture()


func _set_size(value: Vector2i) -> void:
	size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
	# Instanced scenes have their exported properties assigned before entering the
	# tree, when the @onready references do not exist yet. _ready() applies the
	# final value in that case.
	if is_node_ready():
		_apply_size()


func _set_texture(value: Texture2D) -> void:
	texture = value
	if is_node_ready():
		_apply_texture()


## Null is deliberately not applied. An unset theme means "keep the authored texture", not
## "show nothing" — a floor that forgot to name a wall sheet should look plain, not invisible.
func _apply_texture() -> void:
	if texture != null:
		_sprite.texture = texture


func _apply_size() -> void:
	var extent := Vector2(size)

	# region_rect larger than the texture tiles it, given texture_repeat is
	# enabled on the sprite (set in wall_block.tscn).
	_sprite.region_rect = Rect2(Vector2.ZERO, extent)

	# A fresh shape per block: a sub-resource in the .tscn would be shared by every
	# instance, so resizing one wall would silently resize them all.
	var rectangle := RectangleShape2D.new()
	rectangle.size = extent
	_shape.shape = rectangle
	_shape.position = extent * 0.5

class_name Door
extends StaticBody2D
## A door filling the passage between two adjacent rooms.
##
## One door serves both rooms rather than each room owning a half. That matters because
## locking is shared: the door between a cleared room and a room the player is fighting in
## must be shut from both sides, and two independent halves would eventually disagree.
##
## Locked doors sit on the world collision layer, so they stop projectiles as well as the
## player. That is deliberate — being able to shoot out of a sealed room would let the player
## clear the next room through the doorway.

const DOOR_TEXTURE := preload("res://art/environments/door_placeholder.png")

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape

var _is_locked := false


## `size` is the full passage: as deep as the two wall rings it spans, and as wide as the
## doorway opening.
func setup(size: Vector2i) -> void:
	var extent := Vector2(size)

	_sprite.texture = DOOR_TEXTURE
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(-extent * 0.5, extent)

	var rectangle := RectangleShape2D.new()
	rectangle.size = extent
	_shape.shape = rectangle

	unlock()


## Collision changes are deferred, the visual change is not.
##
## Doors are locked from inside the room's entry callback, which runs while the physics server
## is flushing queries — mutating a shape or a layer there is refused outright, so the door
## would silently never seal. Deferring means the seal lands at the end of the frame. That is
## safe here because the entry trigger is inset well inside the room (Room.ENTRY_INSET), so the
## player is never in the doorway at the moment it shuts.
func lock() -> void:
	_is_locked = true
	_sprite.visible = true
	_shape.set_deferred("disabled", false)
	set_deferred("collision_layer", Teams.LAYER_WORLD)


func unlock() -> void:
	_is_locked = false
	_sprite.visible = false
	_shape.set_deferred("disabled", true)
	# Cleared entirely rather than only disabling the shape, so a projectile's ray query against
	# LAYER_WORLD cannot find this body at all.
	set_deferred("collision_layer", 0)


func is_locked() -> bool:
	return _is_locked

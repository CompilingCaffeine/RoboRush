class_name Pickup
extends Area2D
## A collectable dropped on the floor.
##
## One scene covers every pickup type; what it does comes from its PickupConfig. Spec section
## 18 lists six eventual types (scrap, repair cell, temporary shield, battery charge, reroll
## token, keycard) and only the first two are needed now, so the shape that matters is "add a
## .tres", not "add a scene".

const BOB_HEIGHT := 1.5
const BOB_HZ := 2.2

## Seconds before the pickup can be collected, so a drop cannot be absorbed by the player
## standing on the spawn point before it is visible.
const ARM_DELAY := 0.12

@export var config: PickupConfig

@onready var _sprite: Sprite2D = $Sprite

var _elapsed := 0.0
var _base_y := 0.0


func _ready() -> void:
	assert(config != null, "Pickup.config is unset: assign a PickupConfig resource.")
	collision_layer = Teams.LAYER_PICKUP
	collision_mask = Teams.LAYER_PLAYER
	_sprite.texture = config.texture
	_base_y = _sprite.position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# A slow bob is the cheapest way to make a 8x8 sprite read as "collectable" rather than
	# as part of the floor.
	_elapsed += delta
	_sprite.position.y = _base_y + sin(_elapsed * TAU * BOB_HZ) * BOB_HEIGHT


func _on_body_entered(body: Node2D) -> void:
	if _elapsed < ARM_DELAY:
		return
	if not config.apply_to(body):
		# Declined — a repair cell on a robot at full integrity stays on the floor for later
		# rather than being wasted.
		return

	EventBus.pickup_collected.emit(config.kind, config.amount, global_position)
	queue_free()

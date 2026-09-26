class_name Pickup
extends Area2D
## A collectable dropped on the floor.
##
## One scene covers every pickup type; what it does comes from its PickupConfig. Spec section
## 18 lists six eventual types (scrap, repair cell, temporary shield, battery charge, reroll
## token, keycard) and only the first two are needed now, so the shape that matters is "add a
## .tres", not "add a scene".

## Every pickup joins this, so Scrap Magnet can find them all without anything holding a
## list of what is currently on the floor.
const GROUP := &"pickup"

const BOB_HEIGHT := 1.5
const BOB_HZ := 2.2

## Seconds before the pickup can be collected, so a drop cannot be absorbed by the player
## standing on the spawn point before it is visible.
const ARM_DELAY := 0.12

@export var config: PickupConfig

@onready var _sprite: Sprite2D = $Sprite

var _elapsed := 0.0
var _base_y := 0.0

## Whether a body has touched this pickup without collecting it: it arrived before the pickup
## armed, or `apply_to` declined it. `body_entered` fires once per arrival, so a body that never
## leaves never asks again — a robot standing on a repair cell it did not need, then hit, would
## not be repaired until it stepped off and back on. While this is set the pickup asks the bodies
## overlapping it every physics frame instead. It stays clear for every pickup that is simply
## walked over, so the common case pays nothing.
var _awaiting_retry := false


func _ready() -> void:
	assert(config != null, "Pickup.config is unset: assign a PickupConfig resource.")
	add_to_group(GROUP)
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


func _physics_process(_delta: float) -> void:
	if not _awaiting_retry:
		return
	var bodies := get_overlapping_bodies()
	if bodies.is_empty():
		# Everything that was refused has walked away. The next arrival is a fresh
		# `body_entered`, so there is nothing left to poll for.
		_awaiting_retry = false
		return
	for body: Node2D in bodies:
		if _try_collect(body):
			return


func _on_body_entered(body: Node2D) -> void:
	_try_collect(body)


## Collects this pickup for `body` if it can. Returns whether it did.
func _try_collect(body: Node2D) -> bool:
	if _elapsed < ARM_DELAY or not config.apply_to(body):
		# Not yet armed, or declined — a repair cell on a robot at full integrity stays on the
		# floor for later rather than being wasted. Either way the answer may change while the
		# body stands here, so keep asking.
		_awaiting_retry = true
		return false

	_awaiting_retry = false
	EventBus.pickup_collected.emit(config.kind, config.amount, global_position)
	queue_free()
	return true

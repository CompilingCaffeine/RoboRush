class_name ItemEffects
extends Node2D
## Item behaviour that is not a projectile field.
##
## Most items are data on a projectile and need no code at all — that is the whole point
## of `ProjectileConfig`. A few hang off events instead: Volatile Kernel fires when an
## enemy dies, and spec section 11's utility modules ("reveal secret rooms", "reroll room
## rewards") will hang off room events the same way.
##
## Those live here rather than in the inventory because they need a world to act on, and
## rather than in each item because an item is a resource with no place in the tree. The
## rule this file keeps is that it reads the *inventory*, never a hardcoded item id: it
## asks "which held items detonate on a kill" and detonates them, so a second on-kill item
## is a `.tres` and nothing else.

var _inventory: ItemInventory
var _owner_body: Node2D


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)


## Scrap Magnet. Pickups are dragged rather than teleported, so the player can see what is
## coming to them and the effect reads as a magnet rather than as loot vanishing.
##
## Driven from here rather than from `Pickup`, so a pickup stays a dumb object that knows
## what it grants and nothing about who is carrying what. The pickups are found by group,
## which means nothing has to keep a list of what is currently on the floor.
func _physics_process(delta: float) -> void:
	if _inventory == null or _owner_body == null:
		return

	var radius := _inventory.get_pickup_magnet_radius()
	if radius <= 0.0:
		return

	var speed := _inventory.get_pickup_magnet_speed()
	var centre := _owner_body.global_position
	for node: Node in get_tree().get_nodes_in_group(Pickup.GROUP):
		var pickup := node as Node2D
		if pickup == null:
			continue
		var offset := centre - pickup.global_position
		if offset.length() > radius:
			continue
		pickup.global_position = pickup.global_position.move_toward(centre, speed * delta)


## Wired by main.gd, which owns scene composition.
func bind_player(player: Player) -> void:
	_owner_body = player
	_inventory = ItemInventory.find_on(player)


## Chained explosions are possible and intended — a blast that kills a second enemy sets
## off that enemy's blast — but the kill that triggered this one is already gone, so each
## detonation is resolved against whoever is still standing.
func _on_enemy_killed(_enemy: Node, position: Vector2) -> void:
	if _inventory == null:
		return
	for item: ItemConfig in _inventory.get_kill_explosions():
		Explosion.detonate(
			self,
			position,
			item.kill_explosion_radius,
			item.kill_explosion_damage,
			Teams.Id.PLAYER,
			_owner_body,
		)

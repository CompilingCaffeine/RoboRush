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

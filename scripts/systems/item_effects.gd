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
	EventBus.player_dash_started.connect(_on_player_dash_started)
	EventBus.room_cleared.connect(_on_room_cleared)


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


## Breakpoint. A dash leaves a status pulse behind it, which turns the dodge the player
## already had into a repositioning tool: you get out, and what you got out of is slower.
##
## Fired on the *start* of the dash and centred on where the robot was standing, not where
## it lands. Dashing away from a pack and slowing it is the intended play; dashing into a
## pack, slowing it and then being inside it is not a reward, and centring on the departure
## point is what makes the first one the natural read.
##
## Enemies are found by group rather than by shape query, which is the convention `Teams`
## already documents: this can be reached from inside a physics callback, and a room holds a
## handful of enemies.
##
## Nothing is emitted for the pulse itself. `explosion_triggered` was the obvious candidate
## and is wrong: it means "a blast went off", and the feedback director answers it with a
## fireball, screen shake, and a detonation — on every dash, for an effect that deals no
## damage. What the player needs to see is *which enemies got slowed*, and
## `StatusEffectController` already draws that on each of them.
func _on_player_dash_started(_direction: Vector2) -> void:
	if _inventory == null or _owner_body == null:
		return
	var pulses := _inventory.get_dash_pulses()
	if pulses.is_empty():
		return

	var origin := _owner_body.global_position
	for item: ItemConfig in pulses:
		for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
			var enemy := node as Node2D
			if enemy == null or origin.distance_to(enemy.global_position) > item.dash_pulse_radius:
				continue
			var status := StatusEffectController.find_on(enemy)
			if status == null:
				continue
			for id: StringName in item.dash_pulse_effects:
				status.apply(id)


## Tech Debt. Clearing a room makes every enemy the player meets afterwards tougher, for the
## rest of the run.
##
## Charged on `room_cleared` rather than on entering a room, so the debt is incurred by the
## thing the player most wants to do. It accrues into `RunManager` rather than being asked of
## the inventory at spawn time, because it has to outlive the room: an enemy in room nine is
## carrying interest from room two, and the alternative — recomputing from "rooms cleared so
## far" — would silently backdate the whole debt onto a player who picked the item up late.
func _on_room_cleared() -> void:
	if _inventory == null:
		return
	var growth := _inventory.get_enemy_health_growth_per_room()
	if growth <= 0.0:
		return
	RunManager.enemy_health_scale += growth

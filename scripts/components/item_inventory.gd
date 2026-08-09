class_name ItemInventory
extends Node
## What an actor is carrying, and the aggregates derived from it.
##
## Deliberately inert. It stores items and answers questions about them; it never
## touches a weapon, a health component, or a sprite. The owning actor reads the
## aggregates and pushes them into its own components, exactly the way it already does
## for movement and dash config — which is what keeps this testable with no scene tree
## and stops "what does an item do" from being spread across whatever the inventory
## happened to reach into.
##
## It is a component rather than run-scoped state because carrying items is a property
## of an actor, not of a run. A second actor that can hold items — a drone, a co-op
## player — gets one of these and needs no other change.

## Emitted after an item is accepted. The owner applies the consequences.
signal item_added(item: ItemConfig)

var _items: Array[ItemConfig] = []


## Returns whether the item was accepted. Duplicates are refused: an item's whole effect
## is described by its resource, and two of the same resource is a balance question
## nobody has answered yet. The floor's pool draws without repetition for the same reason,
## so this is a guard rather than a rule the player will meet.
func add(item: ItemConfig) -> bool:
	if item == null or has(item.id):
		return false
	_items.append(item)
	item_added.emit(item)
	return true


func has(id: StringName) -> bool:
	for item: ItemConfig in _items:
		if item.id == id:
			return true
	return false


## A copy, so a caller iterating the inventory cannot reorder or empty it.
func get_items() -> Array[ItemConfig]:
	return _items.duplicate()


func size() -> int:
	return _items.size()


func count_with_tag(tag: StringName) -> int:
	var total := 0
	for item: ItemConfig in _items:
		if item.has_tag(tag):
			total += 1
	return total


## The stack that every shot is filtered through. Rebuilt rather than mutated, so there
## is no path where an item's effect survives being removed.
func build_modifier_stack() -> ProjectileModifierStack:
	return ProjectileModifierStack.from_items(_items)


## Multiplicative, so two fire-rate items compound instead of one overwriting the other:
## Cooling Fan and Unsafe Overclock together are 1.2 * 1.25, not 1.25.
func get_fire_rate_multiplier() -> float:
	var total := 1.0
	for item: ItemConfig in _items:
		total *= item.fire_rate_scale
	return total


func get_max_integrity_delta() -> float:
	var total := 0.0
	for item: ItemConfig in _items:
		total += item.max_integrity_delta
	return total


func get_dash_charges_delta() -> int:
	var total := 0
	for item: ItemConfig in _items:
		total += item.dash_charges_delta
	return total


## Multiplicative, like the fire rate, so a second cooldown item compounds rather than
## overwriting the first.
func get_dash_cooldown_multiplier() -> float:
	var total := 1.0
	for item: ItemConfig in _items:
		total *= item.dash_cooldown_scale
	return total


## Whether anything held forbids firing on the move. A single item is enough, and a second
## one cannot make it worse — this is a rule, not a quantity.
func requires_stillness_to_fire() -> bool:
	for item: ItemConfig in _items:
		if item.fire_requires_stillness:
			return true
	return false


## Summed growth per room cleared, as a fraction. Read by ItemEffects, which is the only
## thing here that knows what a room is.
func get_enemy_health_growth_per_room() -> float:
	var total := 0.0
	for item: ItemConfig in _items:
		total += item.enemy_health_growth_per_room
	return total


## The furthest any held item reaches for pickups. The best magnet wins rather than the
## magnets summing: two of them should not reach across the room.
func get_pickup_magnet_radius() -> float:
	var best := 0.0
	for item: ItemConfig in _items:
		best = maxf(best, item.pickup_magnet_radius)
	return best


func get_pickup_magnet_speed() -> float:
	var best := 0.0
	for item: ItemConfig in _items:
		if item.pickup_magnet_radius > 0.0:
			best = maxf(best, item.pickup_magnet_speed)
	return best


## Summed, unlike the magnet: two drone items should be two drones.
func get_drone_count() -> int:
	var total := 0
	for item: ItemConfig in _items:
		total += item.drone_count
	return total


## Items that detonate when an enemy dies. Read by ItemEffects rather than acted on here,
## because a blast needs a world and this component deliberately has no idea it is in one.
func get_kill_explosions() -> Array[ItemConfig]:
	var found: Array[ItemConfig] = []
	for item: ItemConfig in _items:
		if item.kill_explosion_radius > 0.0:
			found.append(item)
	return found


## Items that turn a dash into a status pulse. Same shape and same reason as
## `get_kill_explosions`: the list is the question ItemEffects asks, so a second dash item
## needs no code anywhere.
func get_dash_pulses() -> Array[ItemConfig]:
	var found: Array[ItemConfig] = []
	for item: ItemConfig in _items:
		if item.emits_dash_pulse():
			found.append(item)
	return found


## Finds the inventory on an actor without depending on what it is named — the same
## lookup HealthComponent uses, and for the same reason: a pickup asks "can this thing
## hold items?" and must not care how the scene was assembled.
static func find_on(body: Node) -> ItemInventory:
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is ItemInventory:
			return child as ItemInventory
	return null

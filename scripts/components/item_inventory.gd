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


## Returns whether the item was accepted.
##
## An item may be held up to `ItemConfig.max_stacks` times, which is 1 for everything that defines
## a build. Duplicates of those are still refused, and for the original reason: an item's whole
## effect is described by its resource, and a second copy of "projectiles bounce" is a balance
## question nobody has answered. What changed is that the answer is now *per item* rather than
## global — a repeatable chip declares how many of itself a run may hold, and the guard reads that
## number instead of assuming one.
##
## Nothing below this method knows the difference. Every aggregate already sums or multiplies
## across everything held, so two copies of a +damage chip are +2 damage without a line of stacking
## code anywhere: the duplicate guard was the only thing standing in the way.
func add(item: ItemConfig) -> bool:
	if item == null:
		return false
	if count_of(item.id) >= maxi(item.max_stacks, 1):
		return false
	_items.append(item)
	item_added.emit(item)
	return true


func has(id: StringName) -> bool:
	return count_of(id) > 0


## How many copies of `id` are held. One or zero for a unique item; up to its `max_stacks` for a
## repeatable one.
func count_of(id: StringName) -> int:
	var total := 0
	for item: ItemConfig in _items:
		if item.id == id:
			total += 1
	return total


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


## Hits the build can absorb per room. Summed: two shields are two blocked blows.
func get_shield_charges_per_room() -> int:
	var total := 0
	for item: ItemConfig in _items:
		total += item.shield_charges_per_room
	return total


## What the first shot in a room is multiplied by. Multiplied together rather than summed, the same
## way `get_fire_rate_multiplier` composes, so two such items are a product and not a surprise.
func get_first_shot_damage_scale() -> float:
	var scale := 1.0
	for item: ItemConfig in _items:
		scale *= item.first_shot_damage_scale
	return scale


## Items that vent a status burst where an enemy dies. Returned rather than resolved, because
## applying a status needs a world and this component deliberately has none — the same split
## `get_kill_explosions` and `get_dash_pulses` already make.
func get_kill_pulses() -> Array[ItemConfig]:
	var found: Array[ItemConfig] = []
	for item: ItemConfig in _items:
		if item.emits_kill_pulse():
			found.append(item)
	return found


## Items that answer a hit on the player with a blast.
func get_retaliations() -> Array[ItemConfig]:
	var found: Array[ItemConfig] = []
	for item: ItemConfig in _items:
		if item.retaliates():
			found.append(item)
	return found


## Fire rate multiplier for a robot that has been standing still, and how long it must have been
## still to earn it. The bonus is a product; the wait is the *shortest* any held item asks for,
## because a second, quicker item should make the build quicker rather than average out.
func get_stillness_fire_rate_scale() -> float:
	var scale := 1.0
	for item: ItemConfig in _items:
		scale *= item.stillness_fire_rate_scale
	return scale


func get_stillness_seconds() -> float:
	var shortest := 0.0
	for item: ItemConfig in _items:
		if item.stillness_fire_rate_scale > 1.0:
			shortest = item.stillness_seconds if shortest <= 0.0 else minf(shortest, item.stillness_seconds)
	return shortest


## Fire rate multiplier for a robot down to its last points, and the ceiling that counts as "last".
## The threshold is the *highest* any held item names, so an item that triggers earlier triggers.
func get_low_integrity_fire_rate_scale() -> float:
	var scale := 1.0
	for item: ItemConfig in _items:
		scale *= item.low_integrity_fire_rate_scale
	return scale


func get_low_integrity_points() -> float:
	var highest := 0.0
	for item: ItemConfig in _items:
		if item.low_integrity_fire_rate_scale > 1.0:
			highest = maxf(highest, item.low_integrity_points)
	return highest


## Fraction of held scrap paid out per room cleared, and fraction of a room's damage repaid on
## clearing it. Both summed: two of either is twice as much.
func get_scrap_interest_fraction() -> float:
	var total := 0.0
	for item: ItemConfig in _items:
		total += item.scrap_interest_fraction
	return total


func get_room_damage_refund() -> float:
	var total := 0.0
	for item: ItemConfig in _items:
		total += item.room_damage_refund
	return total


## Lethal hits the held items can survive between them. Summed for the reason drones are: two
## failover items are two saves. How many have been *used* is the run's business, not the
## inventory's — see `RunManager.death_saves_spent`.
func get_death_save_charges() -> int:
	var total := 0
	for item: ItemConfig in _items:
		total += item.death_save_charges
	return total


## The longest grace window any held failover item grants. The best rather than the sum, like the
## magnet's speed: two overlapping windows are one window, and it is as long as the better item says.
func get_death_save_grace_seconds() -> float:
	var best := 0.0
	for item: ItemConfig in _items:
		if item.death_save_charges > 0:
			best = maxf(best, item.death_save_grace_seconds)
	return best


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

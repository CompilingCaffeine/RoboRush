class_name ShopRoom
extends Node2D
## The stock of one shop: what is on its stands and what a reroll does to them.
##
## Lives as a child of the shop Room rather than as part of it, because a shop is a thing
## that happens to be *in* a room — the room is still a room, with walls and doors and a
## floor, and it would be built the same way if the shop were a chest instead.
##
## Items are drawn from the same run-scoped pool that room rewards draw from, which is what
## stops the shop from selling something the player already found and stops a floor from
## offering the same item twice. It also means a reroll genuinely costs the player
## something beyond scrap: rerolled items are gone from the pool for the rest of the run.

## Emitted when an exclusive choice is taken. The boss reward is the only user.
signal choice_taken(item: ItemConfig)

const STAND_SCENE := preload("res://scenes/shop/shop_stand.tscn")

var config: ShopConfig

## When true, taking one item closes the others. Spec section 16's boss reward is "choose
## one of three rare items", and a choice you can take all of is not a choice.
var exclusive := false

var _stands: Array[ShopStand] = []
var _rng := RandomNumberGenerator.new()
var _pool: Array[ItemConfig] = []
var _rerolls_used := 0


## Builds the shop. `positions` are in *global* space, because that is what a Room reports
## and because this node sits under a room that is itself offset onto the floor grid.
func stock(
	shop_config: ShopConfig,
	item_pool: Array[ItemConfig],
	positions: Array[Vector2],
	seed_value: int,
) -> void:
	config = shop_config
	_pool = item_pool
	_rng.seed = seed_value

	if config == null or positions.is_empty():
		return

	for index: int in positions.size():
		var stand: ShopStand = STAND_SCENE.instantiate()
		stand.shop = self
		add_child(stand)
		# After add_child: global_position is meaningless until the node is in the tree.
		stand.global_position = positions[index]
		_stands.append(stand)
		_assign_kind(stand, index)

	# A stand's `_ready` fires inside `add_child`, before `_assign_kind` has told it what it
	# is, so every stand draws itself once as an empty item stand. Item stands then redraw
	# when they are stocked, but the repair and reroll stands had nothing to redraw them and
	# kept the "EMPTY" tag until the player's scrap next changed — which, in a shop entered
	# before the run has paid out anything, is never.
	_refresh_all()

	# The HUD is not the only thing that needs to know the player's scrap changed: a stand
	# the player can now afford should say so without them walking away and back.
	RunManager.scrap_changed.connect(_on_scrap_changed)


## Spec section 16's boss reward: a few items, free, and only one of them is yours. Reuses
## the shop's stands because the interaction is identical — walk up, press the key, take the
## thing — and a second almost-identical pedestal would be a second thing to keep working.
func stock_choice(
	shop_config: ShopConfig, items: Array[ItemConfig], positions: Array[Vector2]
) -> void:
	config = shop_config
	exclusive = true

	for index: int in mini(items.size(), positions.size()):
		var stand: ShopStand = STAND_SCENE.instantiate()
		stand.shop = self
		add_child(stand)
		stand.global_position = positions[index]
		_stands.append(stand)
		stand.stock_item(items[index], 0)


## Called by a stand once its item has been handed over.
func on_item_taken(taken: ShopStand) -> void:
	if not exclusive:
		return
	for stand: ShopStand in _stands:
		if stand != taken:
			stand.is_sold = true
			stand.refresh()
	choice_taken.emit(taken.item)


## Replaces every unsold item on the shelves. Sold stands stay sold — a reroll is a second
## chance at what is left, not a way to buy the same item twice.
##
## The items swept off the shelf go back into the run's pool, and the order here is deliberate:
## replacements are drawn *first*, while the outgoing ids are still reserved, so a reroll can
## never hand back the same item it just took away. Releasing before drawing would let a stand
## redraw its own stock, which reads as the reroll having done nothing.
##
## Returning them at all is the fix for a reported soft-lock. Every displayed item used to be
## struck off the twelve-item pool permanently, so three rerolls cost the run six items and
## the boss was left with nothing to offer as a reward — see RunManager.release_item.
func reroll() -> void:
	_rerolls_used += 1

	var returning: Array[StringName] = []
	for stand: ShopStand in _stands:
		if stand.kind != ShopStand.Kind.ITEM or stand.is_sold:
			continue
		var outgoing := stand.item
		_restock(stand)
		# Also covers the dry-pool case, where the stand ends up empty: the item belongs back
		# in the pool either way, so the boss can still offer it.
		if outgoing != null and stand.item != outgoing:
			returning.append(outgoing.id)

	for id: StringName in returning:
		RunManager.release_item(id)

	_refresh_reroll_price()
	_refresh_all()


func get_stands() -> Array[ShopStand]:
	return _stands.duplicate()


func get_rerolls_used() -> int:
	return _rerolls_used


## The first `item_stand_count` positions sell items; then a repair stand, then a reroll
## stand. Driven by how many positions the template declares, so a bigger shop is a
## template edit.
func _assign_kind(stand: ShopStand, index: int) -> void:
	if index < config.item_stand_count:
		_restock(stand)
		return

	if index == config.item_stand_count:
		stand.kind = ShopStand.Kind.HEAL
		stand.price = config.heal_price
		return

	stand.kind = ShopStand.Kind.REROLL
	stand.price = config.reroll_price(_rerolls_used)


func _restock(stand: ShopStand) -> void:
	var drawn := RunManager.draw_item(_pool, _rng)
	stand.stock_item(drawn, config.price_for(drawn))


func _refresh_reroll_price() -> void:
	for stand: ShopStand in _stands:
		if stand.kind == ShopStand.Kind.REROLL:
			stand.price = config.reroll_price(_rerolls_used)


func _refresh_all() -> void:
	for stand: ShopStand in _stands:
		stand.refresh()


func _on_scrap_changed(_total: int) -> void:
	_refresh_all()

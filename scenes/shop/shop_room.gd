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

const STAND_SCENE := preload("res://scenes/shop/shop_stand.tscn")

var config: ShopConfig

var _stands: Array[ShopStand] = []
var _rng := RandomNumberGenerator.new()
var _pool: Array[ItemConfig] = []
var _rerolls_used := 0


## Builds the shop. `positions` are local to this node's parent room.
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
		stand.position = positions[index]
		stand.shop = self
		add_child(stand)
		_stands.append(stand)
		_assign_kind(stand, index)

	# The HUD is not the only thing that needs to know the player's scrap changed: a stand
	# the player can now afford should say so without them walking away and back.
	RunManager.scrap_changed.connect(_on_scrap_changed)


## Replaces every unsold item on the shelves. Sold stands stay sold — a reroll is a second
## chance at what is left, not a way to buy the same item twice.
func reroll() -> void:
	_rerolls_used += 1
	for stand: ShopStand in _stands:
		if stand.kind == ShopStand.Kind.ITEM and not stand.is_sold:
			_restock(stand)
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

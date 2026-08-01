extends TestCase
## Checks for spec section 17's economy.
##
## Two things are being defended here. The prices, because they are stated exactly in the
## spec and a stray inspector edit would silently rebalance the only decision the player
## makes with scrap. And the *refusals* — a shop that takes money and hands over nothing,
## or hands over an item without taking money, is worse than a shop that does not exist.
## Every purchase path is checked for what happens when it should not go through.

const SHOP_CONFIG_PATH := "res://data/settings/shop_config.tres"
const FLOOR_CONFIG_PATH := "res://data/floors/floor_1_help_desk.tres"
const SHOP_ROOM_SCENE := preload("res://scenes/shop/shop_room.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _shop_config: ShopConfig
var _floor_config: FloorConfig

## The live shop under test. Instance fields rather than a returned dictionary, because
## `await` erases a return type to Variant and every use downstream would be untyped.
var _arena: Node2D
var _player: Player
var _shop: ShopRoom


func run() -> void:
	_shop_config = load(SHOP_CONFIG_PATH) as ShopConfig
	_floor_config = load(FLOOR_CONFIG_PATH) as FloorConfig
	if not require(_shop_config, "shop_config.tres loads as a ShopConfig"):
		return
	if not require(_floor_config, "floor_1_help_desk.tres loads as a FloorConfig"):
		return

	_test_prices_match_the_spec()
	_test_reroll_price_climbs()
	_test_the_shop_template_has_stands()

	await _test_buying_an_item()
	await _test_an_item_cannot_be_bought_twice()
	await _test_no_scrap_no_purchase()
	await _test_repairs()
	await _test_reroll_replaces_unsold_stock()
	await _test_the_player_uses_the_nearest_stand()
	await _test_a_floor_cannot_afford_the_whole_shop()
	await _test_stands_land_where_they_were_asked_to()


# --- Prices -------------------------------------------------------------------


## Spec section 17 states these exactly.
func _test_prices_match_the_spec() -> void:
	check(_price_of(ItemConfig.Rarity.COMMON) == 12, "a common item costs 12 scrap")
	check(_price_of(ItemConfig.Rarity.UNCOMMON) == 20, "an uncommon item costs 20 scrap")
	check(_price_of(ItemConfig.Rarity.RARE) == 32, "a rare item costs 32 scrap")
	check(_shop_config.heal_price == 6, "one integrity costs 6 scrap")
	check(_shop_config.reroll_base_price == 4, "the first reroll costs 4 scrap")
	check(_shop_config.reroll_price_step == 2, "and each one after costs 2 more")


func _test_reroll_price_climbs() -> void:
	check(_shop_config.reroll_price(0) == 4, "the first reroll is 4")
	check(_shop_config.reroll_price(1) == 6, "the second is 6")
	check(_shop_config.reroll_price(3) == 10, "the fourth is 10")


func _test_the_shop_template_has_stands() -> void:
	var templates := _floor_config.templates_for(RoomTemplate.Type.SHOP)
	check(not templates.is_empty(), "the floor has an eligible shop template")

	for template: RoomTemplate in templates:
		check(
			template.shop_stands.size() > _shop_config.item_stand_count,
			"%s has room for its items plus a repair stand" % template.id,
		)
		check(
			template.enemy_spawns.is_empty(),
			"%s spawns no enemies — a shop is not a fight" % template.id,
		)


# --- Buying -------------------------------------------------------------------


func _test_buying_an_item() -> void:
	await _make_shop(200)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	var before := RunManager.scrap
	check(stand.interact(_player), "the purchase goes through")
	check(
		_player.get_item_inventory().has(stand.item.id),
		"the item is in the inventory",
	)
	check(RunManager.scrap == before - stand.price, "and the scrap is gone")
	check(stand.is_sold, "the stand reports itself sold")

	check(not stand.interact(_player), "a sold stand sells nothing more")
	check(RunManager.scrap == before - stand.price, "and takes nothing more")
	await _teardown()


## The inventory refuses duplicates, and the shop must notice before taking the money
## rather than after.
func _test_an_item_cannot_be_bought_twice() -> void:
	await _make_shop(200)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	_player.get_item_inventory().add(stand.item)
	var before := RunManager.scrap
	check(not stand.interact(_player), "an item already held cannot be bought")
	check(RunManager.scrap == before, "and costs nothing to be refused")
	await _teardown()


func _test_no_scrap_no_purchase() -> void:
	await _make_shop(0)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	check(not stand.interact(_player), "an empty wallet buys nothing")
	check(
		not _player.get_item_inventory().has(stand.item.id),
		"and the item stays on the shelf",
	)
	check(not stand.is_sold, "which is not the same as being sold")
	check(RunManager.scrap == 0, "and nothing went negative")
	await _teardown()


func _test_repairs() -> void:
	await _make_shop(200)
	var stand := _stand_of_kind(_shop, ShopStand.Kind.HEAL)
	if stand == null:
		fail("the shop has no repair stand")
		await _teardown()
		return

	var health := _player.get_health_component()
	var before := RunManager.scrap

	# Declined at full integrity rather than wasted, exactly as a repair cell on the floor is.
	check(not stand.interact(_player), "an undamaged robot cannot buy repairs")
	check(RunManager.scrap == before, "and is not charged for the refusal")

	health.apply_damage(DamageInfo.new(2.0))
	var damaged := health.current
	check(stand.interact(_player), "a damaged robot can")
	check_near(
		health.current, damaged + _shop_config.heal_amount, "and gets exactly what it paid for"
	)
	check(RunManager.scrap == before - _shop_config.heal_price, "at the listed price")

	check(stand.interact(_player), "repairs are repeatable while the damage lasts")
	await _teardown()


func _test_reroll_replaces_unsold_stock() -> void:
	await _make_shop(400)
	var stands := _item_stands(_shop)
	var reroll := _stand_of_kind(_shop, ShopStand.Kind.REROLL)
	if stands.size() < 2 or reroll == null:
		fail("the shop is not stocked as expected")
		await _teardown()
		return

	# Sell one, so the reroll has both a sold and an unsold stand to treat differently.
	stands[0].interact(_player)
	var sold_item := stands[0].item
	var before_reroll := stands[1].item

	var scrap_before := RunManager.scrap
	check(reroll.interact(_player), "the reroll goes through")
	check(RunManager.scrap == scrap_before - 4, "at the first-use price")
	check(stands[1].item != before_reroll, "an unsold stand gets new stock")
	check(stands[0].item == sold_item, "a sold stand is left alone")
	check(stands[0].is_sold, "and stays sold")

	check(reroll.price == 6, "and the next reroll costs two more")
	check(_shop.get_rerolls_used() == 1, "the shop counted the reroll")
	await _teardown()


## The robot goes looking for what it is standing next to, rather than stands registering
## themselves with it.
func _test_the_player_uses_the_nearest_stand() -> void:
	await _make_shop(200)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	_player.global_position = stand.global_position + Vector2(0.0, 400.0)
	check(not _player.use_nearest_interactable(), "nothing happens from across the room")

	_player.global_position = stand.global_position
	check(_player.use_nearest_interactable(), "standing on it buys it")
	check(_player.get_item_inventory().has(stand.item.id), "and the item arrives")
	await _teardown()


## Spec section 17: "The player should not be able to buy everything." Checked against what
## a floor actually pays out, computed from the floor's own reward numbers rather than a
## figure typed in here — so rebalancing the drops re-runs this argument automatically.
##
## Measured against the *typical* floor rather than the luckiest one. A player who rolls
## maximum scrap in every room should be able to clear the shelves; that is what luck is
## for. What must not happen is the shop being affordable by default, because then it is a
## vending machine rather than a decision.
func _test_a_floor_cannot_afford_the_whole_shop() -> void:
	await _make_shop(0)
	var stock_cost := 0
	for stand: ShopStand in _shop.get_stands():
		stock_cost += stand.price

	var typical := _typical_floor_scrap()
	check(
		stock_cost > typical,
		"the shop's stock (%d) costs more than a typical floor pays out (%d)" % [
			stock_cost, typical,
		],
	)
	await _teardown()


## The scrap an average floor produces: every combat room clearing for the middle of its
## range, and every enemy dropping the middle of its.
func _typical_floor_scrap() -> int:
	var combat_rooms := _floor_config.room_count - 4
	var enemies_per_room := 0.0
	var templates := _floor_config.templates_for(RoomTemplate.Type.COMBAT)
	for template: RoomTemplate in templates:
		enemies_per_room += float(template.enemy_spawns.size())
	if not templates.is_empty():
		enemies_per_room /= float(templates.size())

	var clear_average := (_floor_config.clear_scrap_range.x + _floor_config.clear_scrap_range.y) * 0.5
	var enemy_average := (_floor_config.enemy_scrap_range.x + _floor_config.enemy_scrap_range.y) * 0.5

	var from_clears := float(combat_rooms) * clear_average
	var from_enemies := float(combat_rooms) * enemies_per_room * enemy_average
	var from_treasure := clear_average + 2.0
	return int(from_clears + from_enemies + from_treasure)


## Shops live under a room that is itself offset onto the floor grid, so a stand positioned
## in local space when global was meant lands somewhere else entirely — outside the room,
## in practice. Checked with the shop deliberately off the origin, because at the origin
## local and global agree and the mistake is invisible.
func _test_stands_land_where_they_were_asked_to() -> void:
	RunManager.begin_run(777)
	_arena = Node2D.new()
	add_child(_arena)

	var holder := Node2D.new()
	holder.position = Vector2(1408.0, 704.0)
	_arena.add_child(holder)

	_shop = SHOP_ROOM_SCENE.instantiate()
	holder.add_child(_shop)

	var wanted: Array[Vector2] = [
		holder.global_position + Vector2(30.0, 20.0),
		holder.global_position + Vector2(90.0, 20.0),
		holder.global_position + Vector2(150.0, 20.0),
	]
	_shop.stock(_shop_config, _floor_config.item_pool, wanted, 99)
	await advance_physics(2)

	var stands := _shop.get_stands()
	check(stands.size() == wanted.size(), "a stand per requested position")
	for index: int in mini(stands.size(), wanted.size()):
		check(
			stands[index].global_position.is_equal_approx(wanted[index]),
			"stand %d stands where it was put (at %v, wanted %v)" % [
				index, stands[index].global_position, wanted[index],
			],
		)
	await _teardown()


# --- Fixtures -----------------------------------------------------------------


func _price_of(rarity: ItemConfig.Rarity) -> int:
	var item := ItemConfig.new()
	item.rarity = rarity
	return _shop_config.price_for(item)


## A live shop with a player standing in it and a known amount of scrap.
func _make_shop(scrap: int) -> void:
	RunManager.begin_run(12345)
	RunManager.add_scrap(scrap)

	_arena = Node2D.new()
	add_child(_arena)

	_player = PLAYER_SCENE.instantiate()
	# Parked well away from the stands, so a check has to move it there deliberately.
	_player.position = Vector2(-500.0, -500.0)
	_arena.add_child(_player)

	_shop = SHOP_ROOM_SCENE.instantiate()
	_arena.add_child(_shop)

	var positions: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(60.0, 0.0), Vector2(120.0, 0.0), Vector2(180.0, 0.0),
	]
	_shop.stock(_shop_config, _floor_config.item_pool, positions, 4242)
	await advance_physics(2)


func _teardown() -> void:
	_arena.queue_free()
	await advance_physics(2)


func _item_stands(shop: ShopRoom) -> Array[ShopStand]:
	var found: Array[ShopStand] = []
	for stand: ShopStand in shop.get_stands():
		if stand.kind == ShopStand.Kind.ITEM and stand.item != null:
			found.append(stand)
	return found


func _first_item_stand(shop: ShopRoom) -> ShopStand:
	var stands := _item_stands(shop)
	if stands.is_empty():
		fail("the shop stocked no items")
		return null
	return stands[0]


func _stand_of_kind(shop: ShopRoom, kind: ShopStand.Kind) -> ShopStand:
	for stand: ShopStand in shop.get_stands():
		if stand.kind == kind:
			return stand
	return null

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

## How many stock draws the affordability check samples. Twelve real shops, because what a shelf
## costs is a draw from the item pool and one sample of a distribution is a coin toss, not a check.
const AFFORDABILITY_SEEDS := 12

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
	_test_stand_labels_cannot_overlap()

	await _test_buying_an_item()
	await _test_an_item_cannot_be_bought_twice()
	await _test_no_scrap_no_purchase()
	await _test_repairs()
	await _test_service_stands_say_what_they_sell()
	await _test_reroll_replaces_unsold_stock()
	await _test_the_player_uses_the_nearest_stand()
	await _test_a_stand_asks_for_the_key_when_it_is_in_reach()
	await _test_a_sold_stand_asks_for_nothing()
	await _test_the_shop_signs_itself()
	await _test_a_floor_cannot_afford_the_whole_shop()
	await _test_stands_land_where_they_were_asked_to()
	await _test_rerolling_does_not_consume_the_item_pool()
	await _test_a_saved_shelf_is_put_back_rather_than_drawn()
	await _test_an_empty_choice_creates_no_stands()


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


## Reported from play: the names above the stands overlapped, in the shop and again on the three
## stands the boss's reward stands on, and the shop became unreadable at exactly the moment the
## player was deciding what to spend a floor's scrap on.
##
## Overlap is geometry, so it is checkable, and the three numbers that produce it live in three
## different files — the label's width in ShopStand, the stand tiles in a room template, and
## FloorController.BOSS_REWARD_SPACING. This is the one place they are compared. It also measures the
## real font against the real item pool, so an item named later than this test cannot quietly bring
## the overlap back: the twelfth name is the one that overflowed.
func _test_stand_labels_cannot_overlap() -> void:
	var font := (load("res://data/ui/theme.tres") as Theme).default_font
	if not require(font, "the UI theme has a font to measure with") or font == null:
		return

	var widest := 0.0
	var widest_label := ""
	for item: ItemConfig in _floor_config.get_items():
		# The label is the name and the price together, so it is the pair that has to fit.
		var label := "%s  %d" % [item.display_name.to_upper(), _shop_config.price_for(item)]
		var width := font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, ShopStand.LABEL_FONT_SIZE
		).x
		if width > widest:
			widest = width
			widest_label = label

	# Wider than its slot is survivable — the label wraps — but only up to a point: a name that needs
	# three lines is a name that has grown past what wrapping can hide.
	check(
		widest <= ShopStand.LABEL_WIDTH * float(ShopStand.LABEL_LINES),
		"the longest tag in the pool fits its label in %d lines ('%s' is %.0fpx of %.0fpx)" % [
			ShopStand.LABEL_LINES, widest_label, widest, ShopStand.LABEL_WIDTH,
		],
	)

	for template: RoomTemplate in _floor_config.templates_for(RoomTemplate.Type.SHOP):
		_check_row_fits(template.id, _stand_x_positions(template))

	# The boss reward is laid out in code instead of by a template, centred on the arena's reward
	# tile, so the same two questions are asked of the numbers that produce it.
	for template: RoomTemplate in _floor_config.templates_for(RoomTemplate.Type.BOSS):
		var centre := float(template.reward_spawn.x * Room.TILE_SIZE + Room.TILE_SIZE / 2)
		var row: Array[float] = []
		for index: int in FloorController.BOSS_REWARD_COUNT:
			var offset := (float(index) - float(FloorController.BOSS_REWARD_COUNT - 1) * 0.5)
			row.append(centre + offset * FloorController.BOSS_REWARD_SPACING)
		_check_row_fits("%s reward" % template.id, row)


## Asserts that no two labels in a row of stands can touch, and that none of them is written into a
## wall. Stands on different rows are compared by row only — the shop's fourth stand sits a row below
## the shelf and shares no space with it.
func _check_row_fits(what: String, xs: Array[float]) -> void:
	xs.sort()
	for index: int in xs.size() - 1:
		var gap := xs[index + 1] - xs[index]
		check(
			gap >= ShopStand.LABEL_WIDTH,
			"%s: stands %.0fpx apart clear a %.0fpx label" % [what, gap, ShopStand.LABEL_WIDTH],
		)

	if xs.is_empty():
		return
	var left := xs[0] - ShopStand.LABEL_WIDTH * 0.5
	var right := xs[xs.size() - 1] + ShopStand.LABEL_WIDTH * 0.5
	check(
		left >= 0.0 and right <= float(Room.INTERIOR_SIZE.x),
		"%s: the row's labels stay inside the room (%.0f to %.0f of 0 to %d)" % [
			what, left, right, Room.INTERIOR_SIZE.x,
		],
	)


## Stand tiles grouped into rows, as label-centre x positions in room pixels. Only the widest row is
## returned: it is the one that constrains the others, and rows cannot collide with each other.
func _stand_x_positions(template: RoomTemplate) -> Array[float]:
	var rows: Dictionary[int, Array] = {}
	for tile: Vector2i in template.shop_stands:
		var x := float(tile.x * Room.TILE_SIZE + Room.TILE_SIZE / 2)
		if not rows.has(tile.y):
			rows[tile.y] = []
		rows[tile.y].append(x)

	var widest: Array[float] = []
	for row: int in rows:
		var xs: Array[float] = []
		xs.assign(rows[row])
		if xs.size() > widest.size():
			widest = xs
	return widest


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


## Reported from play: walk into the first shop of a run and the repair and reroll stands are
## both tagged "EMPTY". A stand's `_ready` runs inside `add_child`, before the shop has told it
## which kind it is, so it draws itself once as an item stand holding nothing. Item stands are
## redrawn when they are stocked; the two service stands were only ever redrawn by a scrap
## change, so a shop entered before the run had paid out anything stayed wrong.
##
## The tags are checked rather than the kinds, because the kinds were already right — it was
## only what the player could read that was wrong. Nothing here touches the shop after it is
## stocked, which is the whole condition being pinned: no reroll, no purchase, no scrap.
func _test_service_stands_say_what_they_sell() -> void:
	await _make_shop(200)

	var repair := _stand_of_kind(_shop, ShopStand.Kind.HEAL)
	var reroll := _stand_of_kind(_shop, ShopStand.Kind.REROLL)
	if repair == null or reroll == null:
		fail("the shop is not stocked as expected")
		await _teardown()
		return

	check(
		_tag_of(repair) == "REPAIR  %d" % _shop_config.heal_price,
		"the repair stand is tagged with its price, not 'EMPTY' (reads '%s')" % _tag_of(repair),
	)
	check(
		_tag_of(reroll) == "REROLL  %d" % _shop_config.reroll_price(0),
		"the reroll stand is tagged with its price, not 'EMPTY' (reads '%s')" % _tag_of(reroll),
	)

	for stand: ShopStand in _item_stands(_shop):
		check(
			_tag_of(stand).begins_with(stand.item.display_name.to_upper()),
			"'%s' is tagged with its own name (reads '%s')" % [
				stand.item.display_name, _tag_of(stand),
			],
		)

	await _teardown()


## What the player can actually read above a stand. Reached through the scene rather than
## through ShopStand, which keeps its label private and has no reason to expose it outside
## of this check.
func _tag_of(stand: ShopStand) -> String:
	var label := stand.find_child("Label") as Label
	return label.text if label != null else ""


## What the player can actually read *under* a stand, reached the way `_tag_of` reaches the tag
## above it and for the same reason.
func _prompt_text(stand: ShopStand) -> String:
	var label := stand.find_child("Prompt") as Label
	return label.text if label != null else ""


func _prompt_shown(stand: ShopStand) -> bool:
	var label := stand.find_child("Prompt") as Label
	return label != null and label.visible


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


## Reported by a player who read the prices, understood the shop, and left without buying: nothing
## anywhere said which button bought. The prompt appears under the stand the player has walked up
## to and nowhere else, so what is on screen is exactly what a press would reach.
func _test_a_stand_asks_for_the_key_when_it_is_in_reach() -> void:
	await _make_shop(200)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	await advance_physics(1)
	check(not _prompt_shown(stand), "a stand nobody is standing at asks for nothing")

	_player.global_position = stand.global_position
	await advance_physics(1)
	check(_prompt_shown(stand), "walking up to a stand asks for the key")
	check(
		_prompt_text(stand) == "PRESS %s" % ShopStand.interact_key_label(),
		"and it names the key the interact action is bound to (reads '%s')" % _prompt_text(stand),
	)

	for other: ShopStand in _shop.get_stands():
		if other != stand:
			check(
				not _prompt_shown(other),
				"only the stand in reach asks — the rest of the shop stays quiet",
			)

	_player.global_position = stand.global_position + Vector2(0.0, 400.0)
	await advance_physics(1)
	check(not _prompt_shown(stand), "walking away takes the prompt with it")
	await _teardown()


## The prompt is a promise that the press will land, so it has to go out with the thing it was
## promising. A "PRESS E" under a stand reading SOLD is an instruction the game then refuses.
func _test_a_sold_stand_asks_for_nothing() -> void:
	await _make_shop(200)
	var stand := _first_item_stand(_shop)
	if stand == null:
		await _teardown()
		return

	_player.global_position = stand.global_position
	await advance_physics(1)
	check(_prompt_shown(stand), "the stand asks for the key while it has something to sell")

	check(_player.use_nearest_interactable(), "the press lands")
	check(not _prompt_shown(stand), "and the sold stand stops asking on the same frame")

	await advance_physics(2)
	check(
		not _prompt_shown(stand),
		"still quiet a frame later, with the player standing right on it",
	)
	check(not _player.use_nearest_interactable(), "which is what a second press would do: nothing")
	await _teardown()


## The sign is the half of the instruction that is readable from the door. Without it a player who
## does not know there is a key to press has no reason to walk into range of the stand that would
## have told them.
func _test_the_shop_signs_itself() -> void:
	await _make_shop(200)

	_shop.place_sign(Vector2(90.0, -60.0))
	# `owned` off: the sign is built in code, so it has no owner and the default search would
	# never see it.
	var sign_label := _shop.find_child("Sign", true, false) as Label
	if not require(sign_label, "the shop stands a sign"):
		await _teardown()
		return

	check(
		sign_label.text == "PRESS %s TO BUY" % ShopStand.interact_key_label(),
		"the sign names the same key the stands do (reads '%s')" % sign_label.text,
	)
	check(
		sign_label.global_position.is_equal_approx(
			Vector2(90.0, -60.0) - sign_label.size * 0.5
		),
		"and it is centred where it was asked for, not hung off that point by a corner",
	)
	await _teardown()


## Spec section 17: "The player should not be able to buy everything." Checked against what
## a floor actually pays out, computed from the floor's own reward numbers rather than a
## figure typed in here — so rebalancing the drops re-runs this argument automatically.
##
## Measured against the *typical* floor rather than the luckiest one. A player who rolls
## maximum scrap in every room should be able to clear the shelves; that is what luck is
## for. What must not happen is the shop being affordable by default, because then it is a
## vending machine rather than a decision.
##
## Swept across stock seeds rather than asserted on one, because what the shelves cost is a *draw*:
## the price of a stand is its item's rarity, and which items a shop rolls is exactly as much luck as
## the scrap the floor paid out. This check used to stock one shop on one seed, which made it a
## single sample of that distribution passing or failing by coincidence — adding one item to the pool
## changed which items that seed drew and turned it red without anything about the shop or the
## economy having moved.
##
## The known tail, stated here so nobody rediscovers it as a bug: the cheapest shelf the pool can
## produce is two common items, which comes to 34 against a typical floor's 39. Roughly 4% of
## possible shelves are affordable that way. Whether that should be impossible rather than lucky is a
## price-table decision (`item_prices[COMMON]` at 16 rather than 12 would close it); it is not
## something this suite should decide by quietly averaging it away.
func _test_a_floor_cannot_afford_the_whole_shop() -> void:
	var typical := _typical_floor_scrap()
	var costs: Array[int] = []

	for index: int in AFFORDABILITY_SEEDS:
		# Spread rather than consecutive, so the sample is not one neighbourhood of the sequence.
		await _make_shop(0, 4242 + index * 97)
		var stock_cost := 0
		for stand: ShopStand in _shop.get_stands():
			stock_cost += stand.price
		costs.append(stock_cost)
		await _teardown()

	costs.sort()
	var median := costs[costs.size() / 2]
	var unaffordable := 0
	for cost: int in costs:
		if cost > typical:
			unaffordable += 1

	check(
		median > typical,
		"a typical shop's stock (%d) costs more than a typical floor pays out (%d); cheapest of %d sampled was %d" % [
			median, typical, costs.size(), costs[0],
		],
	)
	check(
		unaffordable * 4 >= costs.size() * 3,
		"and at least three quarters of shops are out of reach (%d of %d were)" % [
			unaffordable, costs.size(),
		],
	)


## The scrap an average floor produces by the time the player could have reached this shop: every
## combat room clearing for the middle of its range, every enemy dropping the middle of its, and
## the treasure room's fixed handful.
##
## The boss's clear reward is the one thing left out, and it is left out because of *when* rather
## than how much — the shop is a dead end off the room graph and the boss arena is behind a gate,
## so a floor's last clear is money the player cannot have spent here.
##
## `FloorEconomy` owns the arithmetic. It used to live inline, and the balance suite grew a second
## copy of it when the economy question became a four-shop one; two suites computing one figure
## from the same fields is how a drop-rate change ends up half-applied. Moving it also corrected
## the treasure term by one: `LootSpawner.spawn_treasure` drops the *top* of the clear range plus
## two rather than the middle of it, so a typical Help Desk pays 39 and not the 38 named below.
func _typical_floor_scrap() -> int:
	return int(FloorEconomy.before_the_boss(_floor_config))


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
	_shop.stock(_shop_config, _floor_config.get_items(), wanted, 99)
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
func _make_shop(scrap: int, stock_seed := 4242) -> void:
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

	_shop.stock(_shop_config, _floor_config.get_items(), _stand_positions(), stock_seed)
	await advance_physics(2)


## Where this suite's stands go. One list rather than one per shop, so a check that builds a second
## shop to compare against the first is comparing shops built the same way.
func _stand_positions() -> Array[Vector2]:
	return [Vector2(0.0, 0.0), Vector2(60.0, 0.0), Vector2(120.0, 0.0), Vector2(180.0, 0.0)]


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


## Reported as a soft-lock, and it was: every item a shop *displayed* was struck off the
## run's shared twelve-item pool for good, so two initial offers plus three rerolls burned
## eight of them. Add three combat-clear rewards and the treasure vault and the pool is dry
## before the boss dies — at which point the boss creates zero reward stands, and victory,
## which only happens when a reward is taken, can never happen.
##
## A reroll is the player saying "show me something else", not "I decline these forever".
## The items it sweeps off the shelf go back.
func _test_rerolling_does_not_consume_the_item_pool() -> void:
	await _make_shop(400)
	var reroll := _stand_of_kind(_shop, ShopStand.Kind.REROLL)
	var displayed := _item_stands(_shop).size()
	if reroll == null or displayed < 2:
		fail("the shop is not stocked as expected")
		await _teardown()
		return

	var after_initial_stock := RunManager.offered_item_ids.size()
	check(
		after_initial_stock == displayed,
		"stocking the shop reserves exactly what it puts on the shelf (%d for %d stands)"
			% [after_initial_stock, displayed],
	)

	for _index: int in 3:
		_shop.reroll()
		await advance_physics(1)

	check(
		RunManager.offered_item_ids.size() == after_initial_stock,
		"three rerolls reserve nothing extra: %d ids held, was %d — anything more and the "
			% [RunManager.offered_item_ids.size(), after_initial_stock]
			+ "pool runs dry before the boss can offer a reward",
	)
	check(
		_item_stands(_shop).size() == displayed,
		"and the shelf is still full after rerolling",
	)

	# The items on display are still reserved, so a reroll cannot show the same pair twice
	# in a row and the floor cannot drop what is sitting in the shop.
	for stand: ShopStand in _item_stands(_shop):
		check(
			stand.item.id in RunManager.offered_item_ids,
			"'%s' is reserved while it is on the shelf" % stand.item.display_name,
		)

	await _teardown()


## The other way a shop can eat the item pool, and this one had no reroll in it at all: it happened
## to anyone who saved and came back.
##
## A floor is rebuilt from its seed when a run is resumed onto it, and rebuilding a shop used to
## mean stocking it — which draws from `RunManager.offered_item_ids`, a ledger the *run* carries
## across the boundary. The items the shop held before the save were still struck off, so the draw
## skipped them and reserved two more: the player came back to a shelf of different things, and the
## pair they had been deciding between were gone from the run without ever having been taken. Every
## resume cost two more.
##
## So the claim is not "the shelf round-trips" but the thing the pool cannot survive: putting a
## saved shelf back reserves *nothing*, because it was all reserved the first time.
func _test_a_saved_shelf_is_put_back_rather_than_drawn() -> void:
	await _make_shop(400)
	var stands := _item_stands(_shop)
	if stands.size() < 2:
		fail("the shop is not stocked as expected")
		await _teardown()
		return

	# A shop with something bought off it and a reroll behind it, so what is being restored is a
	# shelf the player changed rather than the one the seed would have produced anyway.
	check(stands[0].interact(_player), "an item is bought off the shelf")
	_shop.reroll()
	await advance_physics(1)

	var saved := ShopStock.of(_shop)
	var reserved := RunManager.offered_item_ids.size()
	var expected: Array[StringName] = saved.item_ids.duplicate()
	check(expected.size() == _shop_config.item_stand_count, "the shelf records one entry per stand")
	check(&"" in expected, "including the stand that was bought, recorded as holding nothing")

	# A second shop from the same seed and the same pool, given the shelf. Built here rather than
	# through `_make_shop`, because that starts a run — and a run reset would empty the very ledger
	# this is watching.
	var revived: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	_arena.add_child(revived)
	revived.stock(_shop_config, _floor_config.get_items(), _stand_positions(), 4242, saved)
	await advance_physics(1)

	check(
		RunManager.offered_item_ids.size() == reserved,
		"putting a saved shelf back reserves nothing further (%d ids held, was %d)"
			% [RunManager.offered_item_ids.size(), reserved],
	)

	var restored: Array[StringName] = []
	var sold := 0
	for stand: ShopStand in revived.get_stands():
		if stand.kind != ShopStand.Kind.ITEM:
			continue
		restored.append(&"" if stand.item == null else stand.item.id)
		if stand.is_sold:
			sold += 1
	check(restored == expected, "and the shelf comes back as it was left (%s)" % str(restored))
	check(sold == 1, "with the bought stand still sold (%d sold)" % sold)

	var reroll := _stand_of_kind(revived, ShopStand.Kind.REROLL)
	check(
		revived.get_rerolls_used() == 1,
		"the reroll count comes back (%d)" % revived.get_rerolls_used(),
	)
	check(
		reroll != null and reroll.price == _shop_config.reroll_price(1),
		"so the next reroll is priced as the second, not the first (%d)"
			% [reroll.price if reroll != null else -1],
	)

	revived.queue_free()
	await _teardown()


## The mechanism behind the soft-lock, pinned so it cannot come back quietly: a choice with
## nothing in it makes no stands at all, and therefore never emits `choice_taken`. That is why
## FloorController must not treat taking a reward as the only route to victory.
func _test_an_empty_choice_creates_no_stands() -> void:
	await _make_shop(0)
	var choice: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	_arena.add_child(choice)

	var taken := 0
	choice.choice_taken.connect(func(_item: ItemConfig) -> void: taken += 1)

	var nothing: Array[ItemConfig] = []
	choice.stock_choice(_shop_config, nothing, [Vector2.ZERO, Vector2(40.0, 0.0)])
	await advance_physics(2)

	check(choice.get_stands().is_empty(), "an empty choice creates no stands")
	check(taken == 0, "and so can never announce that a choice was taken")

	choice.queue_free()
	await _teardown()

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

## The standing sign, and how wide a box it gets. Wider than a stand's tag because it is one line
## that must not wrap, and narrower than the room so the shop template's corner blocks stay clear
## of it.
const SIGN_TEXT := "PRESS %s TO BUY"
const SIGN_WIDTH := 200.0
const SIGN_HEIGHT := 12.0

var config: ShopConfig

## When true, taking one item closes the others. Spec section 16's boss reward is "choose
## one of three rare items", and a choice you can take all of is not a choice.
var exclusive := false

var _stands: Array[ShopStand] = []

## The stand a press would currently reach, or null when the player is out of range of all of them.
## Held so the prompts are only rewritten when the answer changes, rather than on every frame the
## player stands still in front of a stand.
var _prompted: ShopStand = null
var _rng := RandomNumberGenerator.new()
var _pool: Array[ItemConfig] = []
var _rerolls_used := 0


## Builds the shop. `positions` are in *global* space, because that is what a Room reports
## and because this node sits under a room that is itself offset onto the floor grid.
##
## `saved` is the shelf a resumed run left behind (see `ShopStock`). Given one, the stands are put
## back rather than stocked: the draw is skipped entirely, because drawing is what spends items out
## of the run's pool and the items on this shelf were spent the first time the floor was built.
## Passing nothing stocks the shop the way it always has, and so does a shelf with no stands
## recorded on it: a first arrival, a floor whose shop had nothing to remember, and a checkpoint
## written before shelves were carried all mean the same thing here, which is "draw".
##
## What a resumed shop does not restore is the position of its own generator: `_rng` is re-seeded
## from the floor's seed and nothing consumes from it here, so a reroll bought after a resume draws
## from the front of the sequence rather than from wherever the pre-save rerolls had reached. It
## still draws from the run's pool as it stands, so nothing is duplicated or handed back — the only
## difference is which of the remaining items a later reroll lands on, which is not something a
## player can be surprised by.
func stock(
	shop_config: ShopConfig,
	item_pool: Array[ItemConfig],
	positions: Array[Vector2],
	seed_value: int,
	saved: ShopStock = null,
) -> void:
	config = shop_config
	_pool = item_pool
	_rng.seed = seed_value
	_rerolls_used = saved.rerolls_used if saved != null else 0

	if config == null or positions.is_empty():
		return

	# Resolved once, here, rather than per stand: the pool is the same for every stand and this is
	# the only place that knows both the shelf and the pool it was drawn from.
	var restored: Array[ItemConfig] = []
	if saved != null:
		restored = saved.resolve(_pool)

	for index: int in positions.size():
		var stand: ShopStand = STAND_SCENE.instantiate()
		stand.shop = self
		add_child(stand)
		# After add_child: global_position is meaningless until the node is in the tree.
		stand.global_position = positions[index]
		_stands.append(stand)
		_assign_kind(stand, index, restored)

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


## Stands a sign in the room saying which key buys.
##
## The per-stand prompt is the instruction and this is the invitation: a prompt is only readable
## from inside interact range, which is a place a player who does not know there is anything to
## press has no particular reason to walk to. The sign is what gets them there, and it is why this
## is not simply the same text three times over — it is said once, at the top of the room, and then
## again quietly under whichever stand the player has actually walked up to.
##
## Placed by `FloorController`, which is the only thing that knows the room this shop is standing
## in; a shop built by a test or by the boss reward simply has no sign.
func place_sign(centre: Vector2) -> void:
	# Body text rather than the dim variant. This is the one line in the room a player who has
	# never bought anything has to read, and it is competing with three lit price tags; at
	# `TEXT_DIM` it read as scenery, which is exactly the failure it is here to fix.
	var sign_label := UIPalette.make_label(
		SIGN_TEXT % ShopStand.interact_key_label(), UIPalette.TEXT
	)
	sign_label.name = "Sign"
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.z_index = ShopStand.LABEL_Z_INDEX
	# After `add_child`: a Control's global position, like a Node2D's, is only its local one until
	# there is a parent transform to measure it against. The same ordering `ThermalZone.spawn`
	# documents at length, and the same bug if it is the other way round.
	add_child(sign_label)
	sign_label.size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	sign_label.global_position = centre - Vector2(SIGN_WIDTH, SIGN_HEIGHT) * 0.5


func get_stands() -> Array[ShopStand]:
	return _stands.duplicate()


func get_rerolls_used() -> int:
	return _rerolls_used


## The first `item_stand_count` positions sell items; then a repair stand, then a reroll
## stand. Driven by how many positions the template declares, so a bigger shop is a
## template edit.
##
## `restored` is one entry per item stand of a resumed shop's shelf, and empty for a shop being
## stocked for the first time. A null entry is a stand with nothing left to sell — bought, or
## stocked from a dry pool — which `stock_item` already reads as sold, so the two need no separate
## handling here. A stand the shelf does not reach (a shop that has grown a stand since the file was
## written) is stocked normally rather than left blank.
func _assign_kind(stand: ShopStand, index: int, restored: Array[ItemConfig]) -> void:
	if index < config.item_stand_count:
		if index < restored.size():
			stand.stock_item(restored[index], config.price_for(restored[index]))
		else:
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


## Keeps the key prompt under the stand the player's press would actually reach.
##
## Polled rather than driven by the player, because the player has no idea a shop exists — it goes
## looking for an interactable only on the frame the key is pressed, and a prompt that appeared
## when you pressed the key would be telling you a thing you had just worked out. One group lookup
## and at most four distances per frame, in the one room per floor that has a shop in it.
##
## Physics-timed to match `Player.use_nearest_interactable`, which reads the same positions on the
## same clock. A prompt that resolved on a render frame could name a different stand than the press
## a moment later would.
func _physics_process(_delta: float) -> void:
	var nearest := _stand_in_reach()
	if nearest == _prompted:
		return
	if _prompted != null and is_instance_valid(_prompted):
		_prompted.set_prompt_shown(false)
	_prompted = nearest
	if _prompted != null:
		_prompted.set_prompt_shown(true)


## The stand `Player.use_nearest_interactable` would pick, or null for none in range.
##
## Deliberately the *nearest* stand rather than the nearest one with something left on it, because
## that is the choice the player's own search makes: a sold stand still wins the search and the
## press still does nothing. Showing the prompt on the stand behind it would promise a purchase
## that would not happen. `ShopStand.set_prompt_shown` is what then declines to prompt for a stand
## that has nothing to sell, so the prompt appears exactly when a press would land.
func _stand_in_reach() -> ShopStand:
	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
	if player == null:
		return null

	var best: ShopStand = null
	var best_distance := Player.INTERACT_RANGE
	for stand: ShopStand in _stands:
		var distance := stand.global_position.distance_to(player.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = stand
	return best

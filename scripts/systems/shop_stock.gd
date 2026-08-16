class_name ShopStock
extends RefCounted
## What a floor's shop has on its shelves, in a form a checkpoint can carry.
##
## Everything else a floor is made of is rebuilt from the floor's derived seed, which is why
## `RunCheckpoint` stores a handful of numbers rather than a serialised scene tree. The shop is the
## one thing that seed cannot rebuild. Its stands are stocked by `RunManager.draw_item`, which draws
## against a *run-scoped* ledger — an item handed to a stand is struck off `offered_item_ids` for the
## rest of the run — so re-stocking the same shop from the same seed produces a different shelf: the
## items it held the first time are now spent, and the draw skips them.
##
## Left to do that, every resume onto a floor burned two more unique items that the player never saw
## and can never be offered again, and handed them a shop full of different things than the one they
## walked out of. Recording the shelf is what makes a resumed floor's shop the shop the run left.
##
## One entry per *item* stand, in stand order. The heal stand has nothing to remember — its price is
## the config's and it can be used as often as it is paid for — and the reroll stand's whole state is
## `rerolls_used`, which is what its price is computed from.

## Ids of what each item stand is holding, in stand order. An empty id is a stand with nothing left
## to sell: either the player bought it, or it was stocked from a pool with nothing to give. Those
## two are one state here because they are one state on the stand — both are `is_sold`, and both
## read `SOLD` — and inventing a distinction the game does not draw would be a distinction the
## restore could get wrong.
var item_ids: Array[StringName] = []

## How many times this shop has been rerolled, which is the whole of what the reroll stand's price
## is derived from (`ShopConfig.reroll_price`). A resumed shop that restarted this at zero would
## sell the player their fourth reroll at the price of their first.
var rerolls_used: int = 0


## Reads the shelf off a live shop. A floor with no shop — or one whose template declares no stands
## — records an empty stock, which restores as "there is nothing saved here, stock it normally".
static func of(shop: ShopRoom) -> ShopStock:
	var stock := ShopStock.new()
	if shop == null:
		return stock

	stock.rerolls_used = shop.get_rerolls_used()
	for stand: ShopStand in shop.get_stands():
		if stand.kind != ShopStand.Kind.ITEM:
			continue
		# `is_sold` before the item, because a bought stand still holds the item it sold: reading the
		# id alone would put it back on the shelf for a second purchase.
		stock.item_ids.append(&"" if stand.is_sold or stand.item == null else stand.item.id)
	return stock


## What each stand should be holding, against the pool the floor is stocked from. One entry per
## recorded stand, and `null` for a stand with nothing to sell — which `ShopStand.stock_item` reads
## as sold, exactly as it reads a draw from an exhausted pool.
##
## An id the pool no longer has resolves to null as well, so a stand whose item was deleted from the
## game comes back empty rather than refusing the whole run. `RunCheckpoint.validate` has already
## refused a stock naming an item the floor does not offer, so this is the unreachable case being
## given a sane answer rather than a policy of its own.
func resolve(pool: Array[ItemConfig]) -> Array[ItemConfig]:
	var by_id: Dictionary[StringName, ItemConfig] = {}
	for item: ItemConfig in pool:
		if item != null and not item.id.is_empty():
			by_id[item.id] = item

	var resolved: Array[ItemConfig] = []
	for id: StringName in item_ids:
		resolved.append(by_id.get(id))
	return resolved


func to_dict() -> Dictionary:
	var ids: Array = []
	for id: StringName in item_ids:
		ids.append(String(id))
	return {"items": ids, "rerolls": rerolls_used}


## Reads a shelf out of a save file. Like everything else read back into a checkpoint, this never
## fails: whether the result is playable is `RunCheckpoint.validate`'s question, and it can only ask
## it about values that exist.
static func from_dict(data: Dictionary) -> ShopStock:
	var stock := ShopStock.new()
	stock.rerolls_used = RunStats.read_int(data, "rerolls")

	var raw: Variant = data.get("items")
	if raw is Array:
		for entry: Variant in raw as Array:
			# Anything that is not a string is a stand with nothing on it, rather than a reason to
			# drop the entry: the position in this list *is* which stand it describes, so a skipped
			# entry would shift every stand after it along the shelf.
			stock.item_ids.append(StringName(entry as String) if entry is String else &"")
	return stock

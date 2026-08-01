class_name ShopConfig
extends Resource
## Spec section 17's prices, as data.
##
## Global rather than per floor, because a price the player has learned should not quietly
## change when they walk downstairs. Floor 2 charging more is a decision worth making
## deliberately later, and it will be a second resource rather than a second rule.
##
## Spec section 17 also states the goal these numbers serve: *the player should not be able
## to buy everything*. That is what makes the shop a decision rather than a vending machine,
## and it is asserted in the shop suite against what a floor can actually pay out.

## Price per `ItemConfig.Rarity`, indexed by the enum's own order: common, uncommon, rare,
## prototype, corrupted. Spec section 17 gives the first three. Prototype is dearer than
## rare because it is rarer; corrupted is cheaper than rare because it costs something else
## as well.
@export var item_prices: Array[int] = [12, 20, 32, 40, 28]

## Spec section 17: "Heal 1 integrity: 6 scrap".
@export var heal_price: int = 6
@export var heal_amount: float = 1.0

## Spec section 17: "Reroll shop: 4 scrap, increasing by 2 each use".
@export var reroll_base_price: int = 4
@export var reroll_price_step: int = 2

## How many of a shop's stands sell items. The rest become the heal and reroll stands, in
## that order, so a template with three stand positions gets two items and a heal.
@export var item_stand_count: int = 2


## What an item costs. Falls back to the common price for a rarity with no entry, rather
## than pricing it at zero — a free rare is a worse failure than a mispriced one.
func price_for(item: ItemConfig) -> int:
	if item == null:
		return 0
	var index := int(item.rarity)
	if index < 0 or index >= item_prices.size():
		return item_prices[0] if not item_prices.is_empty() else 0
	return item_prices[index]


## The price of the nth reroll, counted from zero.
func reroll_price(times_used: int) -> int:
	return reroll_base_price + reroll_price_step * maxi(times_used, 0)

class_name DropTable
extends Resource
## How often each rarity is offered, for one kind of offer: a combat clear, a treasure room, a shop.
##
## Roadmap FIX-3. Rarity used to set an item's price and a boss's preference and nothing else, so
## every offer was a uniform draw over whatever the run had not yet been offered — and with more
## rare items in the pool than any other tier, "rare" was the tier a player saw most. A table
## answers that per tier rather than per item: a weight of 10 for rare means one offer in ten is
## rare, however many rare items the pool holds. Adding an item to a tier makes that tier more
## varied, not more frequent.
##
## Only which tier is decided here. Which item within it is still a uniform draw, and what counts
## as a candidate at all (the unique items the run has not been offered, then the repeatable chips)
## is still `RunManager.draw_item`'s. A tier with nothing left in it is skipped and the rest keep
## their proportions, so as a run spends its commons the offers lean rarer on their own.
##
## The boss does not use a table: `BossRewardDraw` has its own policy, rarest first.

## Weight per `ItemConfig.Rarity`, indexed by the enum's own order: common, uncommon, rare,
## prototype, corrupted. Whole numbers, so the draw is integer arithmetic and reproduces exactly on
## every platform; writing them to sum to 100 makes each one a percentage. Zero keeps a tier out of
## this kind of offer while any other tier has something left. `CampaignValidator` checks the shape.
@export var rarity_weights: Array[int] = [1, 1, 1, 1, 1]


## The weight of `rarity` in this table. Zero for a tier the table has no entry for.
func weight_of(rarity: ItemConfig.Rarity) -> int:
	var index := int(rarity)
	if index < 0 or index >= rarity_weights.size():
		return 0
	return maxi(rarity_weights[index], 0)


## One of `candidates`: a tier by weight among the tiers that have a candidate, then an item within
## it uniformly. Null only for an empty list.
##
## Consumes `rng` exactly twice for any non-empty list — the tier, then the item — so the number of
## draws a floor makes does not depend on which tiers happen to be empty. If every tier with a
## candidate weighs zero, the tier roll is still made and then ignored, and the item is drawn from
## all of them: a table must never be the reason an offer comes up empty while items remain.
func pick(candidates: Array[ItemConfig], rng: RandomNumberGenerator) -> ItemConfig:
	if candidates.is_empty():
		return null

	var tiers: Array[Array] = []
	for _rarity: int in ItemConfig.Rarity.size():
		tiers.append([])
	for item: ItemConfig in candidates:
		tiers[int(item.rarity)].append(item)

	var total := 0
	for rarity: int in tiers.size():
		if not tiers[rarity].is_empty():
			total += weight_of(rarity as ItemConfig.Rarity)

	var roll := rng.randi_range(0, maxi(total, 1) - 1)
	var chosen: Array = candidates
	for rarity: int in tiers.size():
		if tiers[rarity].is_empty():
			continue
		roll -= weight_of(rarity as ItemConfig.Rarity)
		if roll < 0:
			chosen = tiers[rarity]
			break

	return chosen[rng.randi_range(0, chosen.size() - 1)]

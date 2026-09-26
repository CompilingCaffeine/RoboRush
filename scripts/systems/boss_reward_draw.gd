class_name BossRewardDraw
extends RefCounted
## Spec section 16's choice of three: rare items by preference, shuffled, and never all bad.
##
## A policy and nothing else: it is handed the pool, what the run has already been offered, and the
## floor's reward stream, and it answers with the items to put on the stands. It spends nothing and
## places nothing. `FloorController` does both, because striking an item off the run and standing it
## up in an arena are the floor's business, and because keeping them out of here is what lets the
## policy be checked without building a floor.
##
## The policy shipped broken in two ways that compounded into one very visible bug. It walked the
## pool in *file order* and took the first three eligible entries, so the choice was not a draw at
## all — every player who reached the first boss was offered the same three items, run after run.
## And "rare or better" is `rarity >= RARE`, which includes CORRUPTED: the shared pool happens to
## begin with Blocking I/O, Tech Debt and Legacy Runtime, which are precisely the three items the
## design calls pure costs. Every first boss in the game handed the player a choice between a
## weapon that will not fire while moving, permanent enemy growth, and a tripled dash cooldown,
## with no way to decline. That is not opt-in pressure, it is a toll.
##
## Both halves are fixed here. The candidates are shuffled with the floor's own seeded RNG, so the
## choice varies by run and is still reproducible from `--seed`. And one slot is reserved for an
## item that gives something back: hindrances remain in the pool and remain offerable, but they can
## no longer occupy the whole set of stands.
##
## Rarity ordering is preserved within each group, so a boss still offers the best the pool has.
## Repeatable chips are last: they are the guarantee that three stands can always be filled, not a
## prize a boss should be handing out while unique items remain.

## How many items a boss offers. Spec section 16: choose one of three.
const COUNT := 3


## The items to offer, best first, at most `count` of them. Fewer only when the pool cannot fill the
## stands, and empty when it has nothing left at all — which the floor answers by winning without a
## prize rather than by standing up nothing.
##
## Unique items already in `offered_ids` are skipped; repeatable ones never are, since being offered
## again is what makes them repeatable. Neither argument is modified.
##
## The order `rng` is consumed in is part of the contract, not an implementation detail: every floor
## seed's reward in `tests/test_determinism.gd` is pinned to it. Five shuffles, always in the order
## below and always all five, empty groups included.
static func draw(
	pool: Array[ItemConfig],
	offered_ids: Array[StringName],
	rng: RandomNumberGenerator,
	count := COUNT,
) -> Array[ItemConfig]:
	var rare_gifts: Array[ItemConfig] = []
	var rare_hindrances: Array[ItemConfig] = []
	var common_gifts: Array[ItemConfig] = []
	var common_hindrances: Array[ItemConfig] = []
	var repeatables: Array[ItemConfig] = []

	for item: ItemConfig in pool:
		if item == null:
			continue
		if item.is_repeatable():
			repeatables.append(item)
			continue
		if item.id in offered_ids:
			continue
		if item.rarity >= ItemConfig.Rarity.RARE:
			if item.is_hindrance():
				rare_hindrances.append(item)
			else:
				rare_gifts.append(item)
		elif item.is_hindrance():
			common_hindrances.append(item)
		else:
			common_gifts.append(item)

	var by_preference: Array[Array] = [rare_gifts, rare_hindrances, common_gifts, common_hindrances, repeatables]
	for group: Array in by_preference:
		shuffle(group, rng)

	# The reserved slot goes first, so that if the pool can only fill one stand it fills it with
	# something worth taking.
	var chosen: Array[ItemConfig] = []
	var beneficial: Array[Array] = [rare_gifts, common_gifts, repeatables]
	for group: Array in beneficial:
		if not group.is_empty() and count > 0:
			chosen.append(group.pop_front())
			break

	for group: Array in by_preference:
		for item: ItemConfig in group:
			if chosen.size() >= count:
				break
			chosen.append(item)

	return chosen


## Fisher-Yates against the given generator, so the result is decided by the floor seed and nothing
## else. `Array.shuffle` would use the global generator, which is seeded from the clock and would make
## one `--seed` stop reproducing the reward it was reported with.
static func shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Variant = items[index]
		items[index] = items[swap]
		items[swap] = held

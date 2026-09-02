class_name FloorEconomy
extends RefCounted
## What a floor pays out in scrap, as arithmetic over its own numbers.
##
## Extracted for the reason `GreyboxCampaign` was: a second suite needed the figure. The shop
## suite asks whether one floor can afford one shop; the balance suite asks whether a four-floor
## run can afford four of them. Those are the same model read at two points, and the way two
## copies of an economy fail is one of them being updated when a drop rate moves.
##
## Every number here is the middle of a range rather than a roll, so nothing it returns is a claim
## about a particular run. It is what a floor pays on average, which is the only figure a price
## table can be argued against — a shop that is affordable on a lucky floor is luck, and a shop
## that is affordable on the average one is a vending machine.
##
## What it deliberately does not model is the player. Scrap Magnet and Compound Interest both
## multiply everything below, and every check written against this measures the build that holds
## neither — the same no-items baseline the rest of the balance suite uses, and for the same
## reason: it is the one build that exists on every run.


## Combat rooms on a floor. The generator's own arithmetic rather than a literal 4 subtracted from
## `room_count`: the start room is placed before `_grow` runs and the three specials are attached
## after it, so a fifth kind of special room moves this figure with it instead of leaving a 4
## behind in two test suites.
static func combat_rooms(config: FloorConfig) -> int:
	if config == null:
		return 0
	return maxi(config.room_count - FloorGenerator.SPECIAL_TYPES.size() - 1, 0)


## Enemies one combat room holds, averaged flat across the templates the floor may draw.
##
## One enemy per spawn point, always: `Room.populate` walks `enemy_spawns` and fills each position
## with a forced scene or a roll from the roster, so a template's spawn count *is* its enemy count.
##
## Flat, and therefore slightly high. `FloorGenerator._capped_by_distance` scales a room's
## difficulty allowance by how far it sits from the start, so the easy templates — which are also
## the emptiest — are drawn more often than the hard ones. Measured over four hundred generated
## floors the campaign runs 21.9 / 21.9 / 22.8 / 23.8 enemies against this model's
## 22.5 / 22.5 / 24.0 / 24.9.
##
## That error is in the strict direction for the check that matters. Overstating income makes "a
## run cannot buy every shelf it is offered" harder to pass, never easier, so a campaign that
## clears the check on this model clears it on the real distribution too. It is the lenient
## direction for affordability, where the margin is a multiple rather than a percent and half an
## enemy a room does not reach.
static func enemies_per_combat_room(config: FloorConfig) -> float:
	if config == null:
		return 0.0
	var templates := config.templates_for(RoomTemplate.Type.COMBAT)
	if templates.is_empty():
		return 0.0
	var total := 0.0
	for template: RoomTemplate in templates:
		total += float(template.enemy_spawns.size())
	return total / float(templates.size())


## Scrap from clear rewards, including the boss room's. `FloorController._on_room_cleared` does
## not ask what kind of room emitted the clear, so the boss arena pays one like any other — which
## is why this is combat rooms plus one and not combat rooms.
static func from_clears(config: FloorConfig) -> float:
	return float(combat_rooms(config) + 1) * clear_average(config)


## Scrap from the bodies. Every spawn point is an enemy and every enemy drops from the floor's
## own range, so this is the one term that moves when a floor is given fuller rooms.
static func from_enemies(config: FloorConfig) -> float:
	return float(combat_rooms(config)) * enemies_per_combat_room(config) * enemy_average(config)


## The treasure room's scrap, which is not a roll. `LootSpawner.spawn_treasure` drops the *top* of
## the clear range plus two, every time, on top of the item. A floor whose treasure room grants no
## item pays an ordinary clear reward there instead, which is a roll.
static func from_treasure(config: FloorConfig) -> float:
	if config == null:
		return 0.0
	if config.treasure_grants_item:
		return float(config.clear_scrap_range.y + 2)
	return clear_average(config)


## Everything a floor pays, start to boss.
static func whole_floor(config: FloorConfig) -> float:
	return from_clears(config) + from_enemies(config) + from_treasure(config)


## What the player is holding when the boss doors open, which is the whole floor less the reward
## for killing the thing behind them.
static func before_the_boss(config: FloorConfig) -> float:
	return whole_floor(config) - clear_average(config)


## What the player is holding when the shelf is stocked.
##
## Half the floor's combat income, because the shop is attached as a dead end off the room graph
## rather than placed at a fixed depth — it is as likely to hang off the second room as the
## seventh, and half is the expectation across seeds. The treasure room and the boss are left out
## on the same reasoning as the ordering they usually have: both are dead ends the player reaches
## late, and counting either would let a shop be paid for by money the player may not have yet.
static func before_the_shop(config: FloorConfig) -> float:
	var combat_clears := float(combat_rooms(config)) * clear_average(config)
	return (combat_clears + from_enemies(config)) * 0.5


## Everything the floor pays after the shop is behind the player: the rest of the fighting, the
## treasure room, and the boss. The counterpart to `before_the_shop`, and the two are the whole
## floor by construction rather than by two subtractions agreeing.
static func after_the_shop(config: FloorConfig) -> float:
	return whole_floor(config) - before_the_shop(config)


static func clear_average(config: FloorConfig) -> float:
	if config == null:
		return 0.0
	return float(config.clear_scrap_range.x + config.clear_scrap_range.y) * 0.5


static func enemy_average(config: FloorConfig) -> float:
	if config == null:
		return 0.0
	return float(config.enemy_scrap_range.x + config.enemy_scrap_range.y) * 0.5

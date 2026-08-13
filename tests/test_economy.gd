extends TestCase
## The six-floor reward economy, simulated rather than reasoned about.
##
## Every claim here is arithmetic over the shipped data, and every one of them was false at some
## point in this project's history without anything failing. A pool too small for the offers a
## campaign asks for does not error — `RunManager.draw_item` returns null, every caller has a
## graceful fallback, and the run quietly stops handing out items. A boss reward drawn in file
## order is not a draw at all, and nothing notices that every player is offered the same three
## things. Both are cheap to compute and expensive to discover by playing.
##
## Simulated across whole campaigns rather than floors in isolation, because the interesting
## failure is cumulative: `RunManager.offered_item_ids` is run-scoped, so the floor that runs the
## pool dry is the one *after* the last one that fits, and a check that stopped at floor two would
## keep passing all the way to the floor it was written to catch.

const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")

## The gameplan asks for at least ten thousand. Each run draws a full campaign's worth of offers,
## so this is roughly half a million draws — a couple of seconds, and worth it: the guarantees
## below are about what *never* happens, and a hundred runs cannot say that.
const SIMULATIONS := 10000

## Seeds for the reward-draw checks. Fewer than the economy sweep because each one builds a real
## offer through `FloorController`, and the property being checked has no long tail.
const REWARD_SEEDS := 400

## How far into the campaign's unique items a run may be when a boss reward is drawn. The last of
## these is past the point where the one-time pool is spent, which is where the guarantee is
## hardest to keep and where the old code would have offered nothing at all.
const DEPLETION_POINTS: Array[int] = [0, 12, 24, 36, 47]

# --- Declared caps for the worst legal build ---------------------------------------------
#
# Tripwires, not design. Nobody has played a six-floor run; these are the numbers that would mean
# the tuning had become nonsense, and they should move to whatever playtesting teaches. The same
# stance `tests/test_balance.gd` takes about every number it checks.

## A player holding every integrity item and every plating chip at full stacks.
const MAX_INTEGRITY := 24.0

## Compounded fire-rate multipliers. Past this the weapon is a hose and the fire-rate items stop
## being a choice.
const MAX_FIRE_RATE_MULTIPLIER := 6.0

## Projectiles that one trigger pull can put in the air, counting splits and drones.
const MAX_PROJECTILES_PER_SHOT := 64

const MAX_DRONES := 4

## The same ceiling as `MAX_FIRE_RATE_MULTIPLIER`, applied to a build that is also *in* every state
## its items pay for — standing still, down to its last point of integrity. Conditional bonuses
## multiply on top of the flat ones, so the cap that matters is the one measured with the conditions
## met: a build that reaches x6 while moving and x14 while parked has not been capped, it has been
## measured in the wrong state.
const MAX_CONDITIONAL_FIRE_RATE_MULTIPLIER := 12.0

## Hits a build may refuse per room. Shields are a rhythm rather than a resource — a room that
## absorbs four hits is a room the player cannot lose.
const MAX_SHIELDS_PER_ROOM := 2

## Enemy health scaling, however much Tech Debt has accrued. Bounded by RunManager.
const MAX_ENEMY_HEALTH_SCALE := 2.5

var _campaign: RunDefinition
var _config: FloorConfig
var _pool: Array[ItemConfig] = []


func run() -> void:
	_campaign = load(CAMPAIGN_PATH) as RunDefinition
	if not require(_campaign, "the campaign loads"):
		return
	_config = _campaign.load_floor(0)
	if not require(_config, "its first floor loads"):
		return
	_pool = _config.get_items()
	if not require(not _pool.is_empty(), "which has an item pool"):
		return

	_test_the_pool_declares_both_reward_classes()
	_test_corrupted_firmware_always_costs_the_player()
	await _test_a_shot_leaves_where_off_by_one_points_it()
	_test_no_offer_comes_up_empty_across_ten_thousand_campaigns()
	_test_the_same_seed_draws_the_same_campaign()
	await _test_every_boss_reward_is_three_choices_with_something_worth_taking()
	await _test_a_beneficial_choice_is_reserved_when_hindrances_dominate()
	await _test_boss_rewards_differ_between_runs()
	_test_stacking_follows_the_declared_policy()
	_test_the_worst_legal_build_stays_inside_its_caps()
	_test_tech_debt_is_bounded()


## The shape of the economy, before anything is simulated against it. A failure here explains every
## failure below it.
func _test_the_pool_declares_both_reward_classes() -> void:
	var uniques := 0
	var repeatables := 0
	var hindrances := 0
	for item: ItemConfig in _pool:
		if item.is_repeatable():
			repeatables += 1
		else:
			uniques += 1
		if item.is_hindrance():
			hindrances += 1

	var budget := CampaignValidator.offers_required(_config) * _campaign.target_floor_count
	check(
		uniques >= budget,
		"the one-time pool covers a %d-floor campaign's %d offers (%d items)"
			% [_campaign.target_floor_count, budget, uniques],
	)
	check(repeatables > 0, "and a repeatable class exists underneath it (%d chips)" % repeatables)
	check(hindrances > 0, "hindrances are still in the pool (%d)" % hindrances)
	check(
		hindrances < uniques - hindrances,
		"but are the minority of what can be offered (%d of %d)" % [hindrances, uniques],
	)

	# The flag and the fields have to agree, or the boss reward's guarantee is guarding a lie.
	for item: ItemConfig in _pool:
		if item.is_hindrance():
			check(
				not item.has_upside(),
				"%s is tagged a hindrance and gives nothing back" % item.id,
			)


## Corrupted firmware is not a discount, it is a wound.
##
## The category used to be a mixed bag: three items that were pure cost, and four that were plainly
## good trades wearing a warning colour — more damage for a slower shot, more pierce for a slower
## weapon. A player learned quickly that red meant "probably take it", which is the opposite of what
## the colour is for.
##
## The rule now is that every one of them costs maximum integrity: whatever else a corrupted item
## does, holding it means dying sooner. Asserted rather than left to authoring convention, because
## the next corrupted item will be written by somebody reading the others, and the others will look
## like bargains again the moment one of them is.
func _test_corrupted_firmware_always_costs_the_player() -> void:
	var corrupted := 0
	for item: ItemConfig in _pool:
		if item.category != ItemConfig.Category.CORRUPTED_FIRMWARE:
			continue
		corrupted += 1
		check(
			item.max_integrity_delta < 0.0,
			"%s is corrupted firmware and costs maximum integrity (%.0f)"
				% [item.id, item.max_integrity_delta],
		)

	check(corrupted >= 5, "the corrupted category is populated (%d items)" % corrupted)

	# And the floor under it: a run carrying every one of them at once must still have a robot to
	# play. `HealthComponent.set_max_health` clamps at one, which is what makes the rule above safe
	# to apply to the whole category rather than to a chosen few.
	var worst := 0.0
	for item: ItemConfig in _pool:
		if item.max_integrity_delta < 0.0:
			worst += item.max_integrity_delta
	var player_config := load("res://data/player/player_config.tres") as PlayerConfig
	if require(player_config, "the player config loads"):
		var health := HealthComponent.new()
		health.set_max_health(player_config.max_integrity + worst)
		check(
			health.max_health >= 1.0,
			"holding every corrupted item at once leaves at least one integrity (%.0f%+.0f)"
				% [player_config.max_integrity, worst],
		)
		health.free()


## Off-By-One does the one thing it says: the shot leaves forty-five degrees off from where it was
## aimed. Driven through the real factory rather than by reading the field back, because the whole
## mechanic is a rotation applied at one call site and a field nothing reads is a field that does
## nothing.
##
## The split check is the interesting half. The offset lives on the projectile config, and splits
## are spawned from their parent's config — so applying it in `spawn_configured` too would bend
## every child again, and a shot that split twice would come out at 135 degrees. Applying it only
## in `spawn` is what keeps "forty-five degrees" true however the shot is composed.
func _test_a_shot_leaves_where_off_by_one_points_it() -> void:
	var item: ItemConfig = null
	for candidate: ItemConfig in _pool:
		if candidate.id == &"off_by_one":
			item = candidate
	if not require(item, "Off-By-One is in the pool"):
		return

	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)
	await advance_physics(1)

	var weapon := load("res://data/weapons/rivet_blaster.tres") as WeaponConfig
	var stack := ProjectileModifierStack.from_items([item] as Array[ItemConfig])

	var straight := ProjectileFactory.spawn(
		container, weapon, Vector2.RIGHT, Vector2.ZERO, Teams.Id.PLAYER, 1.0, null, null, 1
	)
	var bent := ProjectileFactory.spawn(
		container, weapon, Vector2.RIGHT, Vector2.ZERO, Teams.Id.PLAYER, 1.0, null, stack, 1
	)
	if require(straight, "an unmodified shot spawns") and require(bent, "and a modified one"):
		check_near(
			rad_to_deg(Vector2.RIGHT.angle_to(Vector2.RIGHT.rotated(bent.rotation))),
			45.0,
			"the shot leaves forty-five degrees off aim",
			1.0,
		)
		check_near(
			rad_to_deg(Vector2.RIGHT.angle_to(Vector2.RIGHT.rotated(straight.rotation))),
			0.0,
			"while a shot without the item goes where it was aimed",
			1.0,
		)

	# A split child, spawned the way `Projectile` spawns one: from the parent's own config, through
	# `spawn_configured`, which must not rotate it a second time.
	var child_config := (load("res://data/projectiles/rivet.tres") as ProjectileConfig).spawn_copy()
	stack.apply(child_config, 1)
	var child := ProjectileFactory.spawn_configured(
		container, child_config, Vector2.RIGHT, Vector2.ZERO, Teams.Id.PLAYER
	)
	if require(child, "a split child spawns"):
		check_near(
			rad_to_deg(Vector2.RIGHT.angle_to(Vector2.RIGHT.rotated(child.rotation))),
			0.0,
			"and a split child is not bent a second time",
			1.0,
		)

	arena.queue_free()
	await advance_physics(1)


## The headline acceptance criterion: ten thousand complete campaigns, and not one offer that comes
## up empty.
func _test_no_offer_comes_up_empty_across_ten_thousand_campaigns() -> void:
	var per_floor := CampaignValidator.offers_required(_config)
	var offers := per_floor * _campaign.target_floor_count

	var restore := RunManager.offered_item_ids.duplicate()
	var rng := RandomNumberGenerator.new()
	var empty := 0
	var from_chips := 0
	var worst_run := -1

	for run_index: int in SIMULATIONS:
		RunManager.offered_item_ids.clear()
		rng.seed = run_index
		for _offer: int in offers:
			var item := RunManager.draw_item(_pool, rng)
			if item == null:
				empty += 1
				if worst_run < 0:
					worst_run = run_index
			elif item.is_repeatable():
				from_chips += 1

	RunManager.offered_item_ids = restore

	check(
		empty == 0,
		"%d campaigns of %d offers each fill every one (%d empty, first on run %d)"
			% [SIMULATIONS, offers, empty, worst_run],
	)
	# Not a requirement, but the number worth knowing: on a campaign whose unique pool covers the
	# budget exactly, a chip appearing at all means something drew more than the budget assumed.
	check(
		from_chips == 0,
		"and none of them needs a chip to do it (%d did)" % from_chips,
	)


## Determinism, which is what makes the ten thousand above mean anything: a run that fills every
## offer only proves something if the same seed fills the same offers.
func _test_the_same_seed_draws_the_same_campaign() -> void:
	var restore := RunManager.offered_item_ids.duplicate()
	var first := _draw_campaign(20260812)
	var second := _draw_campaign(20260812)
	var other := _draw_campaign(20260813)
	RunManager.offered_item_ids = restore

	check(first == second, "one seed draws the same campaign twice")
	check(first != other, "and a different seed draws a different one")


## Spec section 16's choice of three, and the guarantee that at least one of them is worth taking.
##
## Checked at several depths into the run, because the guarantee is easy to keep while the pool is
## full and is exactly what breaks when it is not. The last depletion point is past the end of the
## one-time pool, where every remaining candidate is a chip.
func _test_every_boss_reward_is_three_choices_with_something_worth_taking() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = _config
	arena.add_child(floor_node)
	await advance_physics(1)

	var restore := RunManager.offered_item_ids.duplicate()
	var short_offers := 0
	var all_bad := 0
	var duplicated := 0

	for spent: int in DEPLETION_POINTS:
		for offset: int in REWARD_SEEDS:
			RunManager.offered_item_ids.clear()
			_spend_uniques(spent)
			floor_node._reward_rng.seed = offset * 7919 + spent

			var reward := floor_node._draw_boss_reward()
			if reward.size() != FloorController.BOSS_REWARD_COUNT:
				short_offers += 1
			var beneficial := 0
			var ids: Dictionary[StringName, bool] = {}
			for item: ItemConfig in reward:
				if not item.is_hindrance():
					beneficial += 1
				if ids.has(item.id):
					duplicated += 1
				ids[item.id] = true
			if beneficial == 0:
				all_bad += 1

	RunManager.offered_item_ids = restore

	var draws := DEPLETION_POINTS.size() * REWARD_SEEDS
	check(
		short_offers == 0,
		"every one of %d boss rewards offers exactly three choices (%d did not)"
			% [draws, short_offers],
	)
	check(
		all_bad == 0,
		"and at least one choice worth taking (%d were all hindrance)" % all_bad,
	)
	check(duplicated == 0, "and never the same item twice on one set of stands (%d did)" % duplicated)

	arena.queue_free()
	await advance_physics(1)


## The reserved slot, tested where it is the only thing doing the work.
##
## Against the shipped pool the guarantee cannot fail: there are three hindrances among fifty-four
## items and a chip is always available, so any ordering produces something worth taking. That was
## measured, by removing the reservation and watching every check above stay green — a guarantee
## nothing can falsify is a comment, not a test.
##
## So the case is built instead: a pool of three rare hindrances and one common gift, with no chips
## to fall back on. Drawn by rarity alone — which is what the code did before, and what it would do
## again if the reservation were dropped — all three stands are hindrances and the player's "choice"
## is which way to be punished. The gift is the lowest-rarity thing in the pool and must still be
## offered.
func _test_a_beneficial_choice_is_reserved_when_hindrances_dominate() -> void:
	var hindrances: Array[ItemConfig] = []
	var gift: ItemConfig = null
	for item: ItemConfig in _pool:
		if item.is_hindrance() and hindrances.size() < 3:
			hindrances.append(item)
		elif gift == null and not item.is_repeatable() and item.rarity < ItemConfig.Rarity.RARE:
			gift = item
	if not require(gift, "the pool has a low-rarity item that is not a hindrance"):
		return
	check(hindrances.size() == 3, "and three hindrances to crowd it out (%d)" % hindrances.size())

	var cruel := ItemPool.new()
	var contents: Array[ItemConfig] = hindrances.duplicate()
	contents.append(gift)
	cruel.items = contents

	var starved := _config.duplicate() as FloorConfig
	starved.item_pool = cruel

	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = starved
	arena.add_child(floor_node)
	await advance_physics(1)

	var restore := RunManager.offered_item_ids.duplicate()
	var all_bad := 0
	for offset: int in REWARD_SEEDS:
		RunManager.offered_item_ids.clear()
		floor_node._reward_rng.seed = offset + 1
		var beneficial := 0
		for item: ItemConfig in floor_node._draw_boss_reward():
			if not item.is_hindrance():
				beneficial += 1
		if beneficial == 0:
			all_bad += 1
	RunManager.offered_item_ids = restore

	check(
		all_bad == 0,
		"a pool of three hindrances and one gift still offers the gift (%d of %d draws did not)"
			% [all_bad, REWARD_SEEDS],
	)

	arena.queue_free()
	await advance_physics(1)


## The other half of the boss-reward bug, and the one a player would actually have noticed: the
## draw walked the pool in file order, so the choice was identical in every run of the game.
func _test_boss_rewards_differ_between_runs() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = _config
	arena.add_child(floor_node)
	await advance_physics(1)

	var restore := RunManager.offered_item_ids.duplicate()
	var seen: Dictionary[String, bool] = {}
	for offset: int in REWARD_SEEDS:
		RunManager.offered_item_ids.clear()
		floor_node._reward_rng.seed = offset + 1
		var ids: PackedStringArray = []
		for item: ItemConfig in floor_node._draw_boss_reward():
			ids.append(str(item.id))
		seen["|".join(ids)] = true
	RunManager.offered_item_ids = restore

	check(
		seen.size() > REWARD_SEEDS / 10,
		"the first boss's choice varies by run (%d distinct offers across %d seeds)"
			% [seen.size(), REWARD_SEEDS],
	)

	arena.queue_free()
	await advance_physics(1)


## Duplicates and stacks, against the declared contract: a unique may be held once, a chip up to
## its own `max_stacks`, and the aggregates grow with the copies.
func _test_stacking_follows_the_declared_policy() -> void:
	var inventory := ItemInventory.new()
	add_child(inventory)

	var unique: ItemConfig = null
	var chip: ItemConfig = null
	for item: ItemConfig in _pool:
		if unique == null and not item.is_repeatable() and item.max_integrity_delta > 0.0:
			unique = item
		if chip == null and item.is_repeatable() and item.max_integrity_delta > 0.0:
			chip = item
	if not require(unique, "the pool has a one-time integrity item") or not require(
		chip, "and a repeatable one"
	):
		inventory.queue_free()
		return

	check(inventory.add(unique), "a unique item is accepted")
	check(not inventory.add(unique), "and refused a second time")
	check(inventory.count_of(unique.id) == 1, "so exactly one is held")

	var accepted := 0
	for _attempt: int in chip.max_stacks + 3:
		if inventory.add(chip):
			accepted += 1
	check(
		accepted == chip.max_stacks,
		"a chip is accepted exactly %d times (%d)" % [chip.max_stacks, accepted],
	)
	check(
		inventory.count_of(chip.id) == chip.max_stacks,
		"and every copy is held",
	)
	check_near(
		inventory.get_max_integrity_delta(),
		unique.max_integrity_delta + chip.max_integrity_delta * chip.max_stacks,
		"the copies stack into the aggregate",
	)

	inventory.queue_free()


## The worst thing a legal run can carry, against the declared ceilings. "Legal" means every item
## in the pool at full stacks — unreachable in practice, and the point: if the ceiling holds there
## it holds everywhere below it.
func _test_the_worst_legal_build_stays_inside_its_caps() -> void:
	var inventory := ItemInventory.new()
	add_child(inventory)
	for item: ItemConfig in _pool:
		for _copy: int in maxi(item.max_stacks, 1):
			inventory.add(item)

	var player_config := load("res://data/player/player_config.tres") as PlayerConfig
	if not require(player_config, "the player config loads, to know what integrity starts at"):
		inventory.queue_free()
		return
	var base_integrity: float = player_config.max_integrity

	check(
		base_integrity + inventory.get_max_integrity_delta() <= MAX_INTEGRITY,
		"the worst build's integrity stays under %.0f (is %.0f)"
			% [MAX_INTEGRITY, base_integrity + inventory.get_max_integrity_delta()],
	)
	check(
		inventory.get_fire_rate_multiplier() <= MAX_FIRE_RATE_MULTIPLIER,
		"its fire rate stays under x%.1f (is x%.2f)"
			% [MAX_FIRE_RATE_MULTIPLIER, inventory.get_fire_rate_multiplier()],
	)
	check(
		inventory.get_drone_count() <= MAX_DRONES,
		"it fields at most %d drones (%d)" % [MAX_DRONES, inventory.get_drone_count()],
	)
	check(
		inventory.get_shield_charges_per_room() <= MAX_SHIELDS_PER_ROOM,
		"it refuses at most %d hits a room (%d)" % [
			MAX_SHIELDS_PER_ROOM, inventory.get_shield_charges_per_room(),
		],
	)

	# Every conditional bonus collected at once, which is the state a player can actually engineer:
	# parked in a doorway on one point of integrity is a build decision, not an accident.
	var conditional := (
		inventory.get_fire_rate_multiplier()
		* inventory.get_stillness_fire_rate_scale()
		* inventory.get_low_integrity_fire_rate_scale()
	)
	check(
		conditional <= MAX_CONDITIONAL_FIRE_RATE_MULTIPLIER,
		"and x%.2f in every state its items pay for, under x%.1f" % [
			conditional, MAX_CONDITIONAL_FIRE_RATE_MULTIPLIER,
		],
	)

	# One trigger pull: the shot itself, each split generation, and one shot per drone.
	var stack := inventory.build_modifier_stack()
	var shot := (load("res://data/weapons/rivet_blaster.tres") as WeaponConfig).projectile.spawn_copy()
	stack.apply(shot, 15)
	var per_shot := (1 + shot.split_count) * (1 + inventory.get_drone_count())
	check(
		per_shot <= MAX_PROJECTILES_PER_SHOT,
		"one shot puts at most %d projectiles in the air (%d)"
			% [MAX_PROJECTILES_PER_SHOT, per_shot],
	)

	inventory.queue_free()


## Tech Debt used to accrue forever. Over a six-floor campaign that is roughly thirty-six combat
## rooms, which took enemies to five times the integrity they were tuned for — a run that stops
## being winnable rather than becoming harder.
func _test_tech_debt_is_bounded() -> void:
	var restore := RunManager.enemy_health_scale
	RunManager.enemy_health_scale = 1.0

	# Every combat room of a six-floor campaign, charged at Tech Debt's own rate.
	for _room: int in 40:
		RunManager.add_enemy_health_growth(0.12)

	check(
		RunManager.enemy_health_scale <= MAX_ENEMY_HEALTH_SCALE,
		"forty rooms of Tech Debt stay under x%.1f (is x%.2f)"
			% [MAX_ENEMY_HEALTH_SCALE, RunManager.enemy_health_scale],
	)
	check(
		RunManager.enemy_health_scale > 1.0,
		"and it still accrues rather than being switched off",
	)

	RunManager.enemy_health_scale = restore


## One campaign's worth of draws, as a comparable list.
func _draw_campaign(seed_value: int) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	RunManager.offered_item_ids.clear()
	var drawn: PackedStringArray = []
	for _offer: int in CampaignValidator.offers_required(_config) * _campaign.target_floor_count:
		var item := RunManager.draw_item(_pool, rng)
		drawn.append(str(item.id) if item != null else "<empty>")
	return drawn


## Marks `count` of the pool's one-time items as already offered, so a reward can be drawn against
## a run that is partway through spending them.
func _spend_uniques(count: int) -> void:
	var spent := 0
	for item: ItemConfig in _pool:
		if spent >= count:
			return
		if not item.is_repeatable():
			RunManager.offered_item_ids.append(item.id)
			spent += 1

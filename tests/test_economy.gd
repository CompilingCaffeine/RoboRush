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
const PLAYER_CONFIG_PATH := "res://data/player/player_config.tres"
const BLASTER_PATH := "res://data/weapons/rivet_blaster.tres"
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
var _campaign_floors: Array[FloorConfig] = []


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
	_test_drop_tables_offer_each_rarity_at_its_weight()
	_test_an_empty_tier_is_skipped_and_the_rest_keep_their_proportions()
	_test_a_drop_table_never_empties_an_offer()
	_test_a_pick_spends_the_stream_the_same_way_whatever_is_left()
	_test_the_first_floor_offers_rare_items_rarely()
	await _test_every_boss_reward_is_three_choices_with_something_worth_taking()
	await _test_a_beneficial_choice_is_reserved_when_hindrances_dominate()
	await _test_boss_rewards_differ_between_runs()
	_test_the_boss_reward_policy_is_pure()
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
	var player_config := load(PLAYER_CONFIG_PATH) as PlayerConfig
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

	var weapon := load(BLASTER_PATH) as WeaponConfig
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
##
## Each floor's offers are drawn the way the floor makes them, each from its own drop table: the
## shop's stands when the floor is built, then the combat clears and the treasure room, then the
## boss's three. A table can only reorder which items a run meets when (see `DropTable.pick`), so
## the guarantee has to hold with them exactly as it did for a uniform draw.
func _test_no_offer_comes_up_empty_across_ten_thousand_campaigns() -> void:
	var offers := 0
	for config: FloorConfig in _floors():
		offers += CampaignValidator.offers_required(config)
	# The finale's boss leaves a trophy rather than three items; see `_draw_offers`.
	offers -= BossRewardDraw.COUNT

	var restore := RunManager.offered_item_ids.duplicate()
	var rng := RandomNumberGenerator.new()
	var empty := 0
	var from_chips := 0
	var worst_run := -1

	for run_index: int in SIMULATIONS:
		RunManager.offered_item_ids.clear()
		rng.seed = run_index
		for item: ItemConfig in _draw_offers(rng):
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
			if reward.size() != BossRewardDraw.COUNT:
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
## `BossRewardDraw` on its own, without a floor: the checks above reach it through a built floor and
## so exercise it only as the floor happens to call it. This holds the contract the floor relies on —
## that the policy spends nothing and is decided by its stream alone — and the two edges a campaign
## rarely reaches: a pool whose uniques are all spent, and a pool with nothing in it.
func _test_the_boss_reward_policy_is_pure() -> void:
	var offered: Array[StringName] = []
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 2024
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 2024
	var first := BossRewardDraw.draw(_pool, offered, first_rng)
	var second := BossRewardDraw.draw(_pool, offered, second_rng)

	check(first.size() == BossRewardDraw.COUNT, "a full pool fills every stand")
	check(first == second, "the same stream draws the same offer")
	check(offered.is_empty(), "and drawing spends nothing: striking items off is the floor's job")
	check(
		first.any(func(item: ItemConfig) -> bool: return not item.is_hindrance()),
		"one of the three is worth taking",
	)

	var every_unique: Array[StringName] = []
	for item: ItemConfig in _pool:
		if not item.is_repeatable():
			every_unique.append(item.id)
	var spent := BossRewardDraw.draw(_pool, every_unique, first_rng)
	check(spent.size() == BossRewardDraw.COUNT, "a run that has seen every unique is still offered three")
	check(spent.all(func(item: ItemConfig) -> bool: return item.is_repeatable()), "and all three are chips")

	var nothing: Array[ItemConfig] = []
	check(BossRewardDraw.draw(nothing, offered, first_rng).is_empty(), "an empty pool offers nothing")


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

	var player_config := load(PLAYER_CONFIG_PATH) as PlayerConfig
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

	# One trigger pull: every projectile of the volley, its echo, each generation of its splits, and
	# the same again from every drone. Copies on a kill and a missed shot's retarget are not here:
	# how many of those there are depends on what is in the room, which is what the runtime caps are
	# for — `test_combat_caps` fires this build to measure them instead.
	var caps := CombatCaps.active()
	var blaster := load(BLASTER_PATH) as WeaponConfig
	var weapon := inventory.build_weapon_modifier_stack().apply(blaster)
	var shot := weapon.projectile.spawn_copy()
	inventory.build_modifier_stack().apply(shot, 15)
	var children := mini(shot.split_count, caps.max_children_per_impact)
	var generations := mini(shot.split_depth, caps.max_split_depth)
	var per_volley := 0
	for generation: int in generations + 1:
		per_volley += int(pow(children, generation))
	var per_shot := (
		maxi(weapon.projectiles_per_shot, 1)
		* (2 if shot.echo_delay > 0.0 else 1)
		* per_volley
		* (1 + mini(inventory.get_drone_count(), caps.max_drones))
	)
	check(
		per_shot <= MAX_PROJECTILES_PER_SHOT,
		"one shot puts at most %d projectiles in the air (%d)"
			% [MAX_PROJECTILES_PER_SHOT, per_shot],
	)

	# Roadmap ENG-10: the runtime caps are a safety net under the pool, not a limit on it. If the
	# worst legal build reaches one, the cap has become part of how an item plays, which is exactly
	# the hard ceiling `DiminishingReturns` was written to avoid.
	check(
		inventory.get_drone_count() <= caps.max_drones,
		"the worst build's %d drones fit under the cap of %d"
			% [inventory.get_drone_count(), caps.max_drones],
	)
	check(
		shot.split_count <= caps.max_children_per_impact,
		"its %d-way split fits under the cap of %d"
			% [shot.split_count, caps.max_children_per_impact],
	)
	check(
		shot.split_depth <= caps.max_split_depth and shot.split_on_kill_count <= caps.max_children_per_impact,
		"and its split depth and copies on a kill fit under theirs",
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
	for item: ItemConfig in _draw_offers(rng):
		drawn.append(str(item.id) if item != null else "<empty>")
	return drawn


## Every offer a whole campaign makes, floor by floor, in the order a floor makes them and from the
## table each kind of offer uses: the shop's stands (stocked when the floor is built), the combat
## clears that drop an item, the treasure room, and the boss's three. One stream for all of them,
## which the game does not do — the point here is the pool and the tables, not the streams. Null
## entries are offers that came up empty.
##
## The last floor's boss offers nothing: it leaves the trophy that ends the run (`BossArena`).
## Drawing three items for it anyway, as `CampaignValidator.offers_required` conservatively counts,
## would have the boss's reserved beneficial slot reach for a chip on runs whose last few unique
## items are hindrances — a reward no player is ever offered.
func _draw_offers(rng: RandomNumberGenerator) -> Array[ItemConfig]:
	var drawn: Array[ItemConfig] = []
	var floors := _floors()
	for index: int in floors.size():
		var config := floors[index]
		var pool := config.get_items()
		if config.shop != null:
			for _stand: int in config.shop.item_stand_count:
				drawn.append(RunManager.draw_item(pool, rng, config.shop.drops))
		for _clear: int in config.item_clear_indices.size():
			drawn.append(RunManager.draw_item(pool, rng, config.clear_drops))
		if config.treasure_grants_item:
			drawn.append(RunManager.draw_item(pool, rng, config.treasure_drops))
		if index == floors.size() - 1:
			continue
		var reward := BossRewardDraw.draw(pool, RunManager.offered_item_ids, rng)
		for item: ItemConfig in reward:
			if not item.is_repeatable():
				RunManager.offered_item_ids.append(item.id)
		drawn.append_array(reward)
		for _missing: int in BossRewardDraw.COUNT - reward.size():
			drawn.append(null)
	return drawn


## The campaign's floors, loaded once.
func _floors() -> Array[FloorConfig]:
	if _campaign_floors.is_empty():
		for index: int in _campaign.size():
			_campaign_floors.append(_campaign.load_floor(index))
	return _campaign_floors


# --- Drop tables (roadmap FIX-3) ------------------------------------------------


## Each shipped table, over the pool's unique items with nothing spent: every tier has candidates,
## so what comes out should be the table's own proportions. Drawn with replacement — the same list
## every time — because the question is what the table does, not what a run's spending does to it.
func _test_drop_tables_offer_each_rarity_at_its_weight() -> void:
	var uniques := _uniques()
	for pair: Array in _shipped_tables():
		var table: DropTable = pair[1]
		var counts := _tier_counts(table, uniques, SIMULATIONS, 1)
		var total := 0
		for weight: int in table.rarity_weights:
			total += weight
		for rarity: int in ItemConfig.Rarity.size():
			var expected := float(table.weight_of(rarity as ItemConfig.Rarity)) / total
			var observed := float(counts[rarity]) / SIMULATIONS
			check(
				absf(observed - expected) <= 0.02,
				"the %s table offers %s %.1f%% of the time (weight %.1f%%)"
				% [pair[0], ItemConfig.Rarity.keys()[rarity], observed * 100.0, expected * 100.0],
			)


## Late in a run a tier runs out. The draw has to skip it rather than hand its share to whichever
## tier happens to sit next to it, or the table would quietly mean something else by floor five.
func _test_an_empty_tier_is_skipped_and_the_rest_keep_their_proportions() -> void:
	var no_rares: Array[ItemConfig] = []
	for item: ItemConfig in _uniques():
		if item.rarity != ItemConfig.Rarity.RARE:
			no_rares.append(item)
	var table: DropTable = _floors()[0].clear_drops
	var counts := _tier_counts(table, no_rares, SIMULATIONS, 2)
	check(counts[ItemConfig.Rarity.RARE] == 0, "a tier with nothing left is never drawn")

	var remaining := 0
	for rarity: int in ItemConfig.Rarity.size():
		if rarity != ItemConfig.Rarity.RARE:
			remaining += table.weight_of(rarity as ItemConfig.Rarity)
	var expected := float(table.weight_of(ItemConfig.Rarity.COMMON)) / remaining
	var observed := float(counts[ItemConfig.Rarity.COMMON]) / SIMULATIONS
	check(
		absf(observed - expected) <= 0.02,
		"and the others keep their proportions (common %.1f%%, expected %.1f%%)"
		% [observed * 100.0, expected * 100.0],
	)


## The pool can be down to a tier the table weighs at zero. The table decides how often, never
## whether: an offer must not come up empty while the run still has items it could make.
func _test_a_drop_table_never_empties_an_offer() -> void:
	var only_corrupted := DropTable.new()
	only_corrupted.rarity_weights = [0, 0, 0, 0, 1] as Array[int]
	var commons: Array[ItemConfig] = []
	for item: ItemConfig in _uniques():
		if item.rarity == ItemConfig.Rarity.COMMON:
			commons.append(item)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var picked := only_corrupted.pick(commons, rng)
	check(
		picked != null and picked.rarity == ItemConfig.Rarity.COMMON,
		"a table weighing every remaining tier at zero still offers one of them",
	)
	check(only_corrupted.pick([] as Array[ItemConfig], rng) == null, "and an empty list gives nothing")


## `DropTable.pick` promises to take exactly two numbers from its stream however many tiers are
## left, so what a floor draws after an offer does not depend on what the run has already spent.
func _test_a_pick_spends_the_stream_the_same_way_whatever_is_left() -> void:
	var table: DropTable = _floors()[0].clear_drops
	var commons: Array[ItemConfig] = []
	for item: ItemConfig in _uniques():
		if item.rarity == ItemConfig.Rarity.COMMON:
			commons.append(item)

	var rng := RandomNumberGenerator.new()
	var after: Array[int] = []
	for candidates: Array[ItemConfig] in [_uniques(), commons]:
		rng.seed = 20260926
		table.pick(candidates, rng)
		after.append(rng.randi())
	check(after[0] == after[1], "a pick from a full pool and from one tier leave the stream in step")


## The complaint FIX-3 answers, measured where a player meets it. With a uniform draw a third of
## the first floor's combat-clear items were rare, because the pool has more rare items than any
## other kind; with the table it is the rarity the table says. The uniform figure is measured too,
## so this cannot pass on a pool that has simply stopped holding many rare items.
func _test_the_first_floor_offers_rare_items_rarely() -> void:
	var config := _floors()[0]
	var runs := 2000
	var weighted := _first_floor_clear_tiers(config.clear_drops, runs)
	var uniform := _first_floor_clear_tiers(null, runs)
	var drops := float(runs * config.item_clear_indices.size())

	var rare := weighted[ItemConfig.Rarity.RARE] / drops
	var uniform_rare := uniform[ItemConfig.Rarity.RARE] / drops
	check(
		uniform_rare > 0.3,
		"calibration: a uniform draw makes %.0f%% of floor-one clear items rare" % (uniform_rare * 100.0),
	)
	check(
		rare < 0.15,
		"with the table, %.0f%% are (weight %d%%)"
		% [rare * 100.0, config.clear_drops.weight_of(ItemConfig.Rarity.RARE)],
	)
	check(
		weighted[ItemConfig.Rarity.COMMON] > weighted[ItemConfig.Rarity.RARE] * 3,
		"and common is the tier a player meets most (%d common against %d rare)"
		% [weighted[ItemConfig.Rarity.COMMON], weighted[ItemConfig.Rarity.RARE]],
	)


## How often each tier comes out of `table` over `draws` picks from `candidates`.
func _tier_counts(
	table: DropTable, candidates: Array[ItemConfig], draws: int, seed_value: int
) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(ItemConfig.Rarity.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _draw: int in draws:
		counts[table.pick(candidates, rng).rarity] += 1
	return counts


## Tiers of the first floor's combat-clear items over `runs` fresh runs, drawn after the shop is
## stocked as they are in the game. `table` null is the old uniform draw.
func _first_floor_clear_tiers(table: DropTable, runs: int) -> Array[int]:
	var config := _floors()[0]
	var restore := RunManager.offered_item_ids.duplicate()
	var counts: Array[int] = []
	counts.resize(ItemConfig.Rarity.size())
	var rng := RandomNumberGenerator.new()
	for run_index: int in runs:
		RunManager.offered_item_ids.clear()
		rng.seed = run_index
		for _stand: int in config.shop.item_stand_count:
			RunManager.draw_item(_pool, rng, config.shop.drops if table != null else null)
		for _clear: int in config.item_clear_indices.size():
			counts[RunManager.draw_item(_pool, rng, table).rarity] += 1
	RunManager.offered_item_ids = restore
	return counts


func _uniques() -> Array[ItemConfig]:
	var uniques: Array[ItemConfig] = []
	for item: ItemConfig in _pool:
		if not item.is_repeatable():
			uniques.append(item)
	return uniques


func _shipped_tables() -> Array[Array]:
	var config := _floors()[0]
	return [
		["combat-clear", config.clear_drops],
		["treasure", config.treasure_drops],
		["shop", config.shop.drops],
	]


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

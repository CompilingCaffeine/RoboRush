extends TestCase
## Checks for the item system: the resources, the modifier stack, the inventory, and the
## projectile behaviours items compose out of.
##
## The checks that matter most are the synergy ones. Spec section 13's whole claim is that
## combinations work without anyone writing them down, and the only way to believe that is
## to fire a real projectile carrying two items' modifiers at once and watch it do both
## things. `_test_ricochet_plus_fork_bomb` is that check: nothing in the game knows those
## two items can co-occur, and the shot still bounces off a wall and then splits on an
## enemy standing behind the shooter.
##
## The other load-bearing check is `_test_every_modifier_key_exists`. Items name
## `ProjectileConfig` fields as strings, which buys "an item is a .tres" at the price of
## "a typo does nothing and says nothing". That check is the price being paid.

const ITEM_DIRECTORY := "res://data/items/"
const RIVET_PATH := "res://data/projectiles/rivet.tres"
const BLASTER_PATH := "res://data/weapons/rivet_blaster.tres"
const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PICKUP_SCENE := preload("res://scenes/pickups/pickup.tscn")

## Every shipped item, by id. Loaded once in run().
var _items: Dictionary[StringName, ItemConfig] = {}


func run() -> void:
	_load_items()

	_test_items_load()
	_test_no_two_items_share_one_effect()
	_test_ids_are_unique()
	_test_every_modifier_key_exists()
	_test_spec_section_12_numbers()
	_test_most_items_change_behaviour()

	_test_stack_applies_one_item()
	_test_stack_leaves_the_source_untouched()
	_test_stack_composes_two_items()
	_test_stack_is_order_independent()
	_test_stack_scales_multiplicatively()
	_test_stack_reports_unknown_keys()
	_test_shot_interval_gates_capacitor_leak()
	_test_the_curve_keeps_a_small_build_whole()
	_test_the_curve_never_pays_a_penalty_back()
	_test_stacked_damage_bends_instead_of_compounding()
	_test_only_damage_is_softened()
	_test_the_worst_legal_build_is_bounded()

	_test_inventory_basics()
	_test_inventory_aggregates()
	_test_inventory_find_on()
	_test_run_manager_draws_without_repeats()
	_test_the_pool_fills_every_offer_of_the_campaign()
	_test_pickup_config_for_item()

	_test_add_appends_to_array_fields()
	_test_two_status_items_compose_on_one_shot()
	_test_spawn_copy_does_not_share_its_status_array()
	await _test_chill_stacks_then_freezes()
	await _test_freeze_cannot_be_chained_indefinitely()
	await _test_resistance_shortens_control_without_removing_it()
	await _test_burn_damages_over_time_and_is_not_resisted()
	await _test_statuses_compose_rather_than_overwrite()

	await _test_player_gains_integrity_and_repairs()
	await _test_player_pays_for_overclock()
	await _test_player_gains_fire_rate_and_dash()
	await _test_player_collects_a_dropped_item()

	await _test_fork_bomb_splits()
	await _test_ricochet_plus_fork_bomb()
	await _test_magnetic_guidance_curves_onto_a_target()
	await _test_return_protocol_comes_back()
	await _test_impact_explosion_catches_a_neighbour()
	await _test_chain_lightning_jumps_twice()
	await _test_volatile_kernel_detonates_on_a_kill()
	await _test_scrap_magnet_pulls_nearby_pickups()
	await _test_scrap_scatter_avoids_geometry()
	await _test_drop_point_inside_geometry_relocates()
	await _test_debug_drone_fires_with_the_player()
	await _test_drone_shots_advance_the_chain_trigger()

	await _test_memory_spike_pierces_one_extra_enemy()
	await _test_core_dump_explodes_on_impact()
	await _test_cold_cache_chills_what_it_hits()
	await _test_hot_reload_burns_on_the_fifth_shot()
	await _test_breakpoint_chills_on_a_dash()

	await _test_failover_survives_one_hit_and_shrinks_the_pool_for_good()
	await _test_tractor_beam_drags_what_it_hits()
	await _test_faraday_cage_absorbs_one_hit_a_room()
	await _test_static_charge_makes_every_source_hurt_more()
	await _test_cache_warmer_pays_for_the_opening_shot_only()
	await _test_garbage_collector_vents_over_a_kill()
	await _test_null_check_finishes_what_it_breaks()
	await _test_mutex_lock_and_adrenal_loop_pay_for_a_state()
	await _test_interrupt_handler_answers_a_hit()
	await _test_compound_interest_and_swap_space_pay_on_a_clear()
	_test_fragmentation_throws_children_wide()
	_test_wide_bus_stops_children_losing_damage()

	_test_the_harmful_three_are_labelled_as_such()
	await _test_blocking_io_forbids_firing_on_the_move()
	await _test_tech_debt_compounds_across_rooms()
	await _test_legacy_runtime_cripples_the_dash_without_removing_it()


# --- Data ---------------------------------------------------------------------


func _load_items() -> void:
	for file_name: String in DirAccess.get_files_at(ITEM_DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		var item := load(ITEM_DIRECTORY + file_name) as ItemConfig
		if item == null:
			fail("%s does not load as an ItemConfig" % file_name)
			continue
		_items[item.id] = item


func _test_items_load() -> void:
	check(_items.size() >= 6, "the floor ships at least milestone 4's six items")

	for id: StringName in _items:
		var item := _items[id]
		check(not item.display_name.is_empty(), "%s has a display name" % id)
		# The player is never told what an item does — that is the point of the pickup banner
		# carrying a name and nothing else. This is the only place a *reader* is told, which is
		# why it is still required: an item with no description is one whose intended effect
		# exists nowhere outside ItemEffects.
		check(not item.description.is_empty(), "%s has a description on record" % id)
		check(item.icon != null, "%s has an icon" % id)
		check(not item.tags.is_empty(), "%s is tagged" % id)


## No two items may *do* the same thing.
##
## Unique ids were already checked, and that turned out to be the weaker half of the question: the
## pool reached fifty-four items containing three pairs that were identical in every mechanical field
## — one pair identical in all twenty, including rarity — and nothing anywhere noticed. A player who
## is offered Debug Drone on floor 2 and its twin on floor 4 has been handed the same reward twice
## under two names, and the run's variety is a count rather than a fact.
##
## The signature is derived from the resource's own script properties rather than from a list typed
## here, so a mechanical field added later is compared automatically. That is the safe direction to
## fail in: a new *cosmetic* field has to be named in `COSMETIC_PROPERTIES` below or this check gets
## slightly stricter, whereas a hand-maintained list of mechanical fields would get quietly weaker
## every time somebody forgot to extend it.
func _test_no_two_items_share_one_effect() -> void:
	var by_signature: Dictionary[String, StringName] = {}
	for id: StringName in _items:
		var signature := _mechanical_signature(_items[id])
		if by_signature.has(signature):
			var twin: StringName = by_signature[signature]
			if [twin, id] in INTERCHANGEABLE_BY_DESIGN or [id, twin] in INTERCHANGEABLE_BY_DESIGN:
				continue
			fail("'%s' and '%s' are the same item under two names: %s" % [twin, id, signature])
			continue
		by_signature[signature] = id

	check(
		by_signature.size() == _items.size() - _allowed_twin_count(),
		"every item in the pool does something no other item does (%d effects across %d items)" % [
			by_signature.size(), _items.size(),
		],
	)


## Everything about an item that does not change what it does. A difference confined to these is two
## names for one item, which is what the check above refuses.
const COSMETIC_PROPERTIES: Array[String] = [
	"id", "display_name", "description", "icon", "accent_color", "pickup_sound",
]

## Pairs of ids allowed to share an effect, as `[a, b]`. Empty, and it should stay that way — an
## entry here is a decision that two rewards may be indistinguishable, and it belongs in review
## rather than in a resource somebody edits at midnight.
const INTERCHANGEABLE_BY_DESIGN: Array[Array] = []


func _allowed_twin_count() -> int:
	var counted := 0
	for pair: Array in INTERCHANGEABLE_BY_DESIGN:
		if _items.has(pair[0]) and _items.has(pair[1]):
			counted += 1
	return counted


## Every script-declared property except the cosmetic ones, as one comparable string. Dictionary keys
## are sorted, so two items authored in a different key order still compare equal — the failure this
## check exists for would otherwise hide behind a `.tres` diff.
func _mechanical_signature(item: ItemConfig) -> String:
	var parts := PackedStringArray()
	for property: Dictionary in item.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var property_name: String = property["name"]
		if property_name in COSMETIC_PROPERTIES:
			continue
		parts.append("%s=%s" % [property_name, _stable_value(item.get(property_name))])
	return " ".join(parts)


func _stable_value(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var pairs := PackedStringArray()
		for key: Variant in keys:
			pairs.append("%s:%s" % [key, (value as Dictionary)[key]])
		return "{%s}" % ",".join(pairs)
	if value is Array:
		var sorted: Array = (value as Array).duplicate()
		sorted.sort()
		return str(sorted)
	return str(value)


func _test_ids_are_unique() -> void:
	var seen: Dictionary[StringName, bool] = {}
	var count := 0
	for file_name: String in DirAccess.get_files_at(ITEM_DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		count += 1
		var item := load(ITEM_DIRECTORY + file_name) as ItemConfig
		if item != null:
			seen[item.id] = true
	# The inventory refuses duplicate ids, so two items sharing one would make the second
	# silently uncollectable.
	check(seen.size() == count, "every item file has a distinct id")


## The guard that makes string-keyed modifiers safe to ship.
func _test_every_modifier_key_exists() -> void:
	for id: StringName in _items:
		var unknown := ProjectileModifierStack.unknown_keys(_items[id])
		check(
			unknown.is_empty(),
			"%s only modifies real ProjectileConfig fields (unknown: %s)" % [
				id, ", ".join(unknown),
			],
		)


## Spec section 12 gives exact numbers for each item. These are the contract with the
## design document, the same way the Rivet Blaster's are.
func _test_spec_section_12_numbers() -> void:
	var ricochet := _require_item(&"ricochet_driver")
	if ricochet != null:
		check_near(
			float(ricochet.projectile_add.get(&"bounce_count", 0.0)),
			1.0,
			"Ricochet Driver adds exactly one bounce",
		)

	var fork := _require_item(&"fork_bomb")
	if fork != null:
		check_near(
			float(fork.projectile_add.get(&"split_count", 0.0)), 2.0, "Fork Bomb splits into two"
		)
		check_near(
			float(fork.projectile_set.get(&"split_damage_scale", 0.0)),
			0.6,
			"Fork Bomb children deal 60 percent damage",
		)

	var leak := _require_item(&"capacitor_leak")
	if leak != null:
		check(leak.shot_interval == 5, "Capacitor Leak triggers on every fifth shot")
		check_near(
			float(leak.projectile_add.get(&"chain_count", 0.0)), 3.0, "Capacitor Leak chains 3 times"
		)
		check_near(
			float(leak.projectile_set.get(&"chain_damage_scale", 0.0)),
			0.7,
			"Capacitor Leak deals 0.7 per jump",
		)

	var fan := _require_item(&"cooling_fan")
	if fan != null:
		check_near(fan.fire_rate_scale, 1.2, "Cooling Fan is +20 percent fire rate")

	var chassis := _require_item(&"reinforced_chassis")
	if chassis != null:
		check_near(chassis.max_integrity_delta, 2.0, "Reinforced Chassis adds two maximum integrity")
		check_near(chassis.heal_on_pickup, 2.0, "Reinforced Chassis repairs two integrity")

	var battery := _require_item(&"backup_battery")
	if battery != null:
		check(battery.dash_charges_delta == 1, "Backup Battery adds one dash charge")

	var overclock := _require_item(&"unsafe_overclock")
	if overclock != null:
		check_near(
			float(overclock.projectile_scale.get(&"damage", 0.0)),
			1.35,
			"Unsafe Overclock is +35 percent damage",
		)
		check_near(overclock.fire_rate_scale, 1.25, "Unsafe Overclock is +25 percent fire rate")
		check_near(
			overclock.max_integrity_delta, -2.0, "Unsafe Overclock costs two maximum integrity"
		)


## Spec section 10: "the majority of memorable items should alter mechanics". Asserted
## rather than trusted, because pure-stat items are the easy ones to add and the pool
## drifts that way on its own.
func _test_most_items_change_behaviour() -> void:
	var behavioural := 0
	for id: StringName in _items:
		if not _items[id].is_stat_only():
			behavioural += 1
	check(
		behavioural * 2 > _items.size(),
		"most items change behaviour rather than numbers (%d of %d)" % [behavioural, _items.size()],
	)


# --- Modifier stack -----------------------------------------------------------


func _test_stack_applies_one_item() -> void:
	var ricochet := _require_item(&"ricochet_driver")
	if ricochet == null:
		return

	var config := _rivet_variant()
	ProjectileModifierStack.from_items([ricochet]).apply(config, 1)

	check(config.bounce_count == 1, "Ricochet Driver raises bounce_count to 1")
	check(config.split_count == 0, "Ricochet Driver leaves split_count alone")
	check_near(config.damage, 1.0, "Ricochet Driver leaves damage alone")


## The most dangerous available mistake: writing item effects into the weapon's shared
## resource, which would make the first shot's bonuses permanent and cumulative.
func _test_stack_leaves_the_source_untouched() -> void:
	var ricochet := _require_item(&"ricochet_driver")
	if ricochet == null:
		return

	var source := load(RIVET_PATH) as ProjectileConfig
	var stack := ProjectileModifierStack.from_items([ricochet])
	for _shot: int in 3:
		stack.apply(source.spawn_copy(), 1)

	check(source.bounce_count == 0, "three modified shots leave the weapon's own config at 0")


## The headline claim of the whole design, at the data level: two items that have never
## heard of each other produce a projectile that does both things.
func _test_stack_composes_two_items() -> void:
	var ricochet := _require_item(&"ricochet_driver")
	var fork := _require_item(&"fork_bomb")
	if ricochet == null or fork == null:
		return

	var config := _rivet_variant()
	ProjectileModifierStack.from_items([ricochet, fork]).apply(config, 1)

	check(config.bounce_count == 1, "the combination keeps Ricochet Driver's bounce")
	check(config.split_count == 2, "the combination keeps Fork Bomb's split")
	check_near(config.split_damage_scale, 0.6, "the combination keeps Fork Bomb's child damage")


func _test_stack_is_order_independent() -> void:
	var first := _require_item(&"magnetic_guidance")
	var second := _require_item(&"unsafe_overclock")
	if first == null or second == null:
		return

	var forwards := _rivet_variant()
	ProjectileModifierStack.from_items([first, second]).apply(forwards, 1)
	var backwards := _rivet_variant()
	ProjectileModifierStack.from_items([second, first]).apply(backwards, 1)

	check_near(forwards.damage, backwards.damage, "pickup order does not change damage")
	check_near(
		forwards.homing_strength, backwards.homing_strength, "pickup order does not change homing"
	)


func _test_stack_scales_multiplicatively() -> void:
	var doubler := ItemConfig.new()
	doubler.id = &"test_doubler"
	doubler.projectile_scale = {&"damage": 2.0}

	var adder := ItemConfig.new()
	adder.id = &"test_adder"
	adder.projectile_add = {&"damage": 1.0}

	var config := _rivet_variant()
	ProjectileModifierStack.from_items([adder, doubler]).apply(config, 1)

	# Adds run before scales regardless of the order the items were listed in, so this is
	# (1 + 1) * 2 and not 1 * 2 + 1.
	check_near(config.damage, 4.0, "adds resolve before scales")


func _test_stack_reports_unknown_keys() -> void:
	var typo := ItemConfig.new()
	typo.id = &"test_typo"
	typo.projectile_add = {&"bonuce_count": 1.0}

	var unknown := ProjectileModifierStack.unknown_keys(typo)
	check(unknown.size() == 1, "a mistyped field name is reported")
	check(
		unknown.size() > 0 and unknown[0] == "bonuce_count", "the report names the offending field"
	)

	# And it must not corrupt anything on the way past.
	var config := _rivet_variant()
	var before := config.bounce_count
	# from_items pushes an error for the typo, which is the point; suppressed so the run
	# output stays readable.
	var stack := ProjectileModifierStack.new()
	stack.apply(config, 1)
	check(config.bounce_count == before, "an unknown field changes nothing")
	check(stack.is_empty(), "an empty stack reports itself empty")


# --- Diminishing returns ------------------------------------------------------
#
# The curve exists because the offer cadence is flat and the enemies are flatter: eight offers a
# floor on every floor, nothing about an enemy that reads the floor number, and a product of a
# dozen scalars against both. By the Data Center that arithmetic reached 52x the damage per second
# the roster was written for, and the last floor of the campaign stopped asking anything.
#
# What these check is not the arithmetic — `DiminishingReturns.soften` is six lines and its
# doc comment contains the table. It is the two promises the curve makes to a player, which are the
# parts a future change could break without noticing: a build the player is still assembling is
# untouched, and a penalty is never quietly refunded.


## The promise a player would actually notice being broken. Everything up to the knee is kept
## whole, so the first fire-rate item is worth exactly what it says on the pickup, and the second
## still compounds with the first.
func _test_the_curve_keeps_a_small_build_whole() -> void:
	for raw: float in [1.0, 1.2, 1.5, 1.0 + DiminishingReturns.KNEE]:
		check_near(
			DiminishingReturns.soften(raw), raw,
			"a %.2fx build is left exactly where it is" % raw,
		)

	# Just past the knee the curve has started, but only just — the two branches meet with matching
	# slopes, so there is no build sitting on a step.
	var past := 1.0 + DiminishingReturns.KNEE + 0.01
	check(
		DiminishingReturns.soften(past) < past
			and DiminishingReturns.soften(past) > past - 0.001,
		"and one hair past it the curve bends rather than steps (%.4f)" % DiminishingReturns.soften(past),
	)

	# Monotonic, which is what "more is always more" means as a check. A build that got worse for
	# taking an item is the failure this whole design is meant to avoid.
	var previous := 0.0
	var backwards := 0
	for step: int in 200:
		var value := DiminishingReturns.soften(1.0 + float(step) * 0.25)
		if value < previous:
			backwards += 1
		previous = value
	check(backwards == 0, "taking more never gives less (%d reversals)" % backwards)


## Burst Buffer charges 20% of its damage for its fire rate and Deprecated API charges 40% of its
## fire rate outright. A curve built to compress benefits must not touch either: softening a
## penalty is refunding part of a price the player agreed to pay, and it would quietly make the
## trade-off items the safest picks in the pool.
func _test_the_curve_never_pays_a_penalty_back() -> void:
	for raw: float in [0.4, 0.6, 0.8, 0.99]:
		check_near(
			DiminishingReturns.soften(raw), raw,
			"a %.2fx penalty is paid in full" % raw,
		)


## The headline: a stack of damage items lands well under their product, while two of them still
## land on it exactly.
##
## Written against synthetic items rather than shipped ones, because this is a check on the rule.
## Retuning Unsafe Overclock should not be able to fail it, and `_test_the_worst_legal_build_is_bounded`
## below is where the shipped numbers are held to account.
func _test_stacked_damage_bends_instead_of_compounding() -> void:
	var doublers: Array[ItemConfig] = []
	for index: int in 6:
		var item := ItemConfig.new()
		item.id = StringName("test_doubler_%d" % index)
		item.projectile_scale = {&"damage": 2.0}
		doublers.append(item)

	# One item, and the curve is not in the way yet: 2.0x is exactly the knee.
	var one := _rivet_variant()
	var base := one.damage
	ProjectileModifierStack.from_items([doublers[0]]).apply(one, 1)
	check_near(one.damage, base * 2.0, "one doubler doubles")

	# Six of them are 64x on paper. What actually reaches the projectile is the ceiling, near enough
	# to it that the last three items are decorations — which is the intended outcome, and the
	# reason the curve is a knee rather than a wall: they are still worth something, just not 32x.
	var many := _rivet_variant()
	ProjectileModifierStack.from_items(doublers).apply(many, 1)
	var ceiling := 1.0 + DiminishingReturns.KNEE + DiminishingReturns.RANGE
	check(
		many.damage < base * ceiling,
		"six doublers stay under the ceiling (%.2fx against %.2fx)" % [many.damage / base, ceiling],
	)
	check(
		many.damage > one.damage,
		"and are still worth more than one (%.2fx against %.2fx)" % [
			many.damage / base, one.damage / base,
		],
	)
	check(
		many.damage < base * 8.0,
		"nowhere near the 64x the raw product would have been (%.2fx)" % (many.damage / base),
	)


## The curve is deliberately narrow — one field — and the narrowness is the part worth pinning.
## Chip Speed stacks five times too, and a projectile that flies 1.76x faster is a feel change
## rather than a floor that stopped being a floor. Softening it would be taking something from the
## player for no reason anybody could name.
func _test_only_damage_is_softened() -> void:
	check(
		ProjectileModifierStack.SOFTENED_SCALE_KEYS.has(&"damage"),
		"damage is on the curve",
	)
	for key: StringName in [&"speed", &"radius", &"chain_damage_scale", &"split_damage_scale"]:
		check(
			not ProjectileModifierStack.SOFTENED_SCALE_KEYS.has(key),
			"'%s' is not" % key,
		)

	var speeders: Array[ItemConfig] = []
	for index: int in 4:
		var item := ItemConfig.new()
		item.id = StringName("test_speeder_%d" % index)
		item.projectile_scale = {&"speed": 2.0}
		speeders.append(item)

	var config := _rivet_variant()
	var base := config.speed
	ProjectileModifierStack.from_items(speeders).apply(config, 1)
	check_near(config.speed, base * 16.0, "four speed items still compound to the full product")


## The shipped numbers, against the ceiling the curve promises. This is the check that notices a
## new item — or a raised `max_stacks` — putting the campaign back where it was.
##
## Built by taking every item in the run pool that helps, at every copy it is allowed, which is a
## build no player will ever hold: the pool is finite and a run is offered a fraction of it. That
## is what makes it the right thing to measure. If the build nobody can assemble is inside the
## ceiling, every build somebody can assemble is too.
func _test_the_worst_legal_build_is_bounded() -> void:
	var pool := load("res://data/pools/run_item_pool.tres") as ItemPool
	if not require(pool, "the run item pool loads"):
		return

	var everything: Array[ItemConfig] = []
	var inventory := ItemInventory.new()
	for item: ItemConfig in pool.items:
		if item == null:
			continue
		for _copy: int in maxi(item.max_stacks, 1):
			everything.append(item)
			inventory.add(item)

	var raw_damage := 1.0
	for item: ItemConfig in everything:
		raw_damage *= float(item.projectile_scale.get(&"damage", 1.0))

	var config := _rivet_variant()
	var base := config.damage
	ProjectileModifierStack.from_items(everything).apply(config, 1)
	var softened := config.damage / base

	var ceiling := 1.0 + DiminishingReturns.KNEE + DiminishingReturns.RANGE
	check(
		softened < ceiling,
		"the whole pool at once is %.2fx damage, under the %.2fx ceiling (raw would be %.1fx)" % [
			softened, ceiling, raw_damage,
		],
	)

	var rate := inventory.get_fire_rate_multiplier()
	check(
		rate < ceiling,
		"and %.2fx fire rate, under the same ceiling (raw would be %.1fx)" % [
			rate, inventory.get_raw_fire_rate_multiplier(),
		],
	)

	# The number the floors are actually built against. Stated as one figure because damage per
	# second is what an enemy's integrity is spent on, and because the pair of ceilings above does
	# not say out loud that they multiply.
	check(
		softened * rate < 12.0,
		"which is %.1fx the damage per second the roster was written for" % (softened * rate),
	)
	inventory.free()


func _test_shot_interval_gates_capacitor_leak() -> void:
	var leak := _require_item(&"capacitor_leak")
	if leak == null:
		return

	var stack := ProjectileModifierStack.from_items([leak])
	for shot: int in [1, 2, 3, 4]:
		var quiet := _rivet_variant()
		stack.apply(quiet, shot)
		check(quiet.chain_count == 0, "shot %d does not chain" % shot)

	for shot: int in [5, 10]:
		var loud := _rivet_variant()
		stack.apply(loud, shot)
		check(loud.chain_count == 3, "shot %d chains" % shot)
		check_near(loud.chain_damage_scale, 0.7, "shot %d chains for 0.7 per jump" % shot)


# --- Inventory ----------------------------------------------------------------


func _test_inventory_basics() -> void:
	var inventory := ItemInventory.new()
	var ricochet := _require_item(&"ricochet_driver")
	if ricochet == null:
		inventory.free()
		return

	var added: Array[ItemConfig] = []
	inventory.item_added.connect(func(item: ItemConfig) -> void: added.append(item))

	check(inventory.add(ricochet), "a new item is accepted")
	check(not inventory.add(ricochet), "the same item is refused a second time")
	check(not inventory.add(null), "null is refused")
	check(inventory.size() == 1, "only the accepted item is held")
	check(added.size() == 1, "item_added fired once")
	check(inventory.has(&"ricochet_driver"), "the item is found by id")
	check(not inventory.has(&"fork_bomb"), "an item that was never collected is not found")
	check(inventory.count_with_tag(&"bounce") == 1, "items are countable by tag")

	inventory.get_items().clear()
	check(inventory.size() == 1, "clearing the returned array does not empty the inventory")
	inventory.free()


func _test_inventory_aggregates() -> void:
	var fan := _require_item(&"cooling_fan")
	var overclock := _require_item(&"unsafe_overclock")
	var chassis := _require_item(&"reinforced_chassis")
	var kernel := _require_item(&"volatile_kernel")
	if fan == null or overclock == null or chassis == null or kernel == null:
		return

	var inventory := ItemInventory.new()
	for item: ItemConfig in [fan, overclock, chassis, kernel]:
		inventory.add(item)

	check_near(
		inventory.get_fire_rate_multiplier(), 1.2 * 1.25, "fire rate items compound rather than win"
	)
	check_near(
		inventory.get_max_integrity_delta(), 0.0, "+2 and -2 maximum integrity cancel out"
	)
	check(inventory.get_kill_explosions().size() == 1, "only Volatile Kernel detonates on a kill")
	check(inventory.build_modifier_stack().size() == 4, "every held item reaches the stack")
	inventory.free()


func _test_inventory_find_on() -> void:
	var body := Node2D.new()
	check(ItemInventory.find_on(body) == null, "find_on returns null for a body with no inventory")
	check(ItemInventory.find_on(null) == null, "find_on tolerates null")

	var inventory := ItemInventory.new()
	# Deliberately not named "Items": lookup is by type, or renaming a node would silently
	# make the player unable to pick anything up.
	inventory.name = "SomethingElse"
	body.add_child(inventory)
	check(ItemInventory.find_on(body) == inventory, "find_on finds the inventory by type")
	body.free()


func _test_run_manager_draws_without_repeats() -> void:
	var pool: Array[ItemConfig] = []
	for id: StringName in _items:
		pool.append(_items[id])

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var previous := RunManager.offered_item_ids.duplicate()
	RunManager.offered_item_ids.clear()

	var uniques := 0
	for id: StringName in _items:
		if not _items[id].is_repeatable():
			uniques += 1

	# Drawn as many times as there are uniques: the declared policy spends every one of those
	# before a repeatable is ever offered.
	var drawn: Array[StringName] = []
	for _index: int in uniques:
		var item := RunManager.draw_item(pool, rng)
		if item != null:
			drawn.append(item.id)

	check(drawn.size() == uniques, "every unique in the pool can be drawn (%d of %d)" % [
		drawn.size(), uniques,
	])
	var seen: Dictionary[StringName, bool] = {}
	for id: StringName in drawn:
		seen[id] = true
	check(seen.size() == drawn.size(), "and none of them is offered twice in one run")

	# Where the old contract ended in null, the new one ends in a chip. The pool no longer runs
	# dry, and that is the whole reason the repeatable class exists: a six-floor campaign asks for
	# more offers than any finite set of one-time items can fill, and an offer that comes up empty
	# is a treasure room containing a repair cell.
	var overflow := RunManager.draw_item(pool, rng)
	if require(overflow, "a pool with its uniques spent still fills an offer"):
		check(overflow.is_repeatable(), "with a repeatable item (%s)" % overflow.id)
		check(
			RunManager.draw_item(pool, rng) != null,
			"and goes on filling them indefinitely",
		)

	RunManager.begin_run(1)
	var after_restart := RunManager.draw_item(pool, rng)
	if require(after_restart, "a new run draws again"):
		check(not after_restart.is_repeatable(), "and the whole unique pool is available again")

	# Autoload state is process-wide; leave it as it was found.
	RunManager.offered_item_ids = previous


## The Development plan's acceptance criterion: "The item pool can always fill every planned
## offer, including the final three choices." It was false until Development got its own six
## items, and it failed *silently* — `draw_item` returns null on an exhausted pool, and every
## caller has a graceful fallback, so a starved run drops repair cells into treasure rooms and
## puts fewer than three stands in front of the last boss rather than erroring.
##
## Counted the way a run actually spends the pool: clear rewards, then two shop stands, then
## the treasure, then three boss choices, per floor, against one shared reservation list.
##
## Every floor the campaign declares, rather than the two that exist — the pool is spent
## cumulatively, so the floor that runs it dry is the one after the last one that fits, and a
## check that stopped at floor 2 would keep passing all the way to the floor it was written to
## catch. `CampaignValidator` makes the same count from the data alone; this one spends the pool
## through `RunManager.draw_item`, which is the code that actually has to come up with an item.
func _test_the_pool_fills_every_offer_of_the_campaign() -> void:
	var campaign := load("res://data/runs/main_campaign.tres") as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260808
	var restore := RunManager.offered_item_ids.duplicate()
	RunManager.offered_item_ids.clear()

	var empty_offers := 0
	var filled := 0
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		for _offer: int in CampaignValidator.offers_required(config):
			if RunManager.draw_item(config.get_items(), rng) == null:
				empty_offers += 1
			else:
				filled += 1

	RunManager.offered_item_ids = restore
	check(
		empty_offers == 0,
		"a %d-floor run fills all %d item offers (%d came up empty)" % [
			campaign.size(), filled + empty_offers, empty_offers,
		],
	)


func _test_pickup_config_for_item() -> void:
	var fork := _require_item(&"fork_bomb")
	if fork == null:
		return

	var config := PickupConfig.for_item(fork)
	check(config.kind == PickupConfig.Kind.ITEM, "an item pickup is of the ITEM kind")
	check(config.item == fork, "the pickup carries the item")
	check(config.texture == fork.icon, "the pickup is drawn as the item's icon")

	var body := Node2D.new()
	check(not config.apply_to(body), "a body with no inventory declines the item")

	var inventory := ItemInventory.new()
	body.add_child(inventory)
	check(config.apply_to(body), "a body with an inventory takes the item")
	check(inventory.has(&"fork_bomb"), "the item landed in the inventory")
	check(not config.apply_to(body), "the same item is not taken twice")
	body.free()


# --- Player integration -------------------------------------------------------


func _test_player_gains_integrity_and_repairs() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var health := player.get_health_component()
	health.apply_damage(DamageInfo.new(3.0))
	var before := health.current

	var chassis := _require_item(&"reinforced_chassis")
	if chassis != null:
		player.get_item_inventory().add(chassis)
		check_near(health.max_health, 8.0, "Reinforced Chassis raises the maximum from 6 to 8")
		check_near(health.current, before + 2.0, "Reinforced Chassis repairs two points")

	await _teardown(arena)


func _test_player_pays_for_overclock() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var health := player.get_health_component()
	var weapon := player.get_weapon_controller()
	var overclock := _require_item(&"unsafe_overclock")
	if overclock != null:
		player.get_item_inventory().add(overclock)
		check_near(health.max_health, 4.0, "Unsafe Overclock drops the maximum from 6 to 4")
		check_near(health.current, 4.0, "integrity above the new maximum is clamped down")
		check(weapon.get_fire_interval() < 0.25, "Unsafe Overclock fires faster than base")
		check(weapon.modifiers != null, "the weapon received a modifier stack")

	await _teardown(arena)


func _test_player_gains_fire_rate_and_dash() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var weapon := player.get_weapon_controller()
	var dash := player.get_dash_controller()
	var base_interval := weapon.get_fire_interval()
	var base_charges := dash.get_max_charges()

	var collected: Array[ItemConfig] = []
	var handler := func(item: ItemConfig) -> void: collected.append(item)
	EventBus.item_collected.connect(handler)

	var fan := _require_item(&"cooling_fan")
	var battery := _require_item(&"backup_battery")
	if fan != null and battery != null:
		player.get_item_inventory().add(fan)
		player.get_item_inventory().add(battery)

		check_near(
			weapon.get_fire_interval(), base_interval / 1.2, "Cooling Fan shortens the fire interval"
		)
		check(dash.get_max_charges() == base_charges + 1, "Backup Battery raises the dash ceiling")
		check(dash.charges_available == base_charges + 1, "the new dash charge is ready immediately")
		check(collected.size() == 2, "both pickups reached the EventBus")

	EventBus.item_collected.disconnect(handler)
	await _teardown(arena)


## The whole path, through a real Area2D: a pickup on the floor, the robot walking into
## it, and the item ending up in the inventory.
func _test_player_collects_a_dropped_item() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	var ricochet := _require_item(&"ricochet_driver")
	if ricochet == null:
		await _teardown(arena)
		return

	var pickup: Pickup = PICKUP_SCENE.instantiate()
	pickup.config = PickupConfig.for_item(ricochet)
	pickup.position = Vector2(60.0, 0.0)
	arena.add_child(pickup)

	# Past the arming delay first: a pickup that could be absorbed on its spawn frame would
	# be collected before the player ever saw it.
	await advance_physics(12)
	check(is_instance_valid(pickup), "the pickup is still on the floor before the robot reaches it")

	player.global_position = pickup.global_position
	await advance_physics(4)

	check(player.get_item_inventory().has(&"ricochet_driver"), "walking into the pickup collects it")
	check(not is_instance_valid(pickup), "a collected pickup removes itself")
	await _teardown(arena)


# --- Projectile behaviour: real projectiles through real physics ---------------


func _test_fork_bomb_splits() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(100.0, 0.0))
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var config := _config_with([&"fork_bomb"])
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(30)

	check(spawned[0] == 3, "Fork Bomb turns one projectile into a parent and two children")
	check_near(
		bot.get_health_component().current, 2.0, "the parent still deals its own full damage"
	)

	var children := _live_projectiles(arena)
	check(not children.is_empty(), "the children exist as real projectiles")
	if not children.is_empty():
		check_near(children[0].config.damage, 0.6, "children deal 60 percent damage")
		check(children[0].config.split_count == 0, "children cannot split again")

	await _teardown(arena)


## Spec section 13's worked example, end to end. Nothing in the game knows Ricochet Driver
## and Fork Bomb can be held together: the enemy stands *behind* the shooter, so it can
## only be hit by a projectile that bounced, and the split children can only exist if that
## same projectile also carried Fork Bomb.
func _test_ricochet_plus_fork_bomb() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(100.0, -40.0), Vector2i(16, 80))
	var behind := _add_bot(arena, Vector2(-70.0, 0.0))
	await advance_physics(2)

	var bounces := [0]
	var bounce_handler := func(_point: Vector2, _normal: Vector2) -> void: bounces[0] += 1
	EventBus.projectile_bounced.connect(bounce_handler)

	var spawned := _count_spawns(arena)
	var config := _config_with([&"ricochet_driver", &"fork_bomb"])
	check(config.bounce_count == 1, "the composed shot carries the bounce")
	check(config.split_count == 2, "the composed shot carries the split")

	# Fired away from the enemy, at the wall.
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(60)

	check(bounces[0] == 1, "the shot bounced off the wall exactly once")
	check_near(
		behind.get_health_component().current,
		2.0,
		"the rebounding shot hit the enemy behind the shooter",
	)
	check(spawned[0] == 3, "and then split into two children on that hit")

	EventBus.projectile_bounced.disconnect(bounce_handler)
	await _teardown(arena)


func _test_magnetic_guidance_curves_onto_a_target() -> void:
	# Control first: the same shot with no homing must miss, or the check below proves
	# nothing about the item.
	var control := _make_arena()
	var missed_bot := _add_bot(control, Vector2(110.0, 26.0))
	await advance_physics(2)
	_fire_at(control, Vector2.ZERO, Vector2.RIGHT, _rivet_variant())
	await advance_physics(40)
	check_near(
		missed_bot.get_health_component().current, 3.0, "an unguided shot misses an off-axis enemy"
	)
	await _teardown(control)

	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(110.0, 26.0))
	await advance_physics(2)
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _config_with([&"magnetic_guidance"]))
	await advance_physics(40)
	check_near(
		bot.get_health_component().current, 2.0, "Magnetic Guidance curves the same shot onto it"
	)
	await _teardown(arena)


## Return Protocol's reversal is exact: the shot travels out for its lifetime and back for
## the same lifetime, so it sweeps the lane it missed in and dies where it started.
func _test_return_protocol_comes_back() -> void:
	var arena := _make_arena()
	await advance_physics(2)

	var config := _config_with([&"return_protocol"])
	config.lifetime = 0.25
	check(config.return_enabled, "Return Protocol switches the reversal on")

	var projectile := _fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(16)

	var survived := is_instance_valid(projectile)
	check(survived, "the shot survives the end of its first lifetime")
	if not survived:
		await _teardown(arena)
		return

	var turnaround := projectile.global_position.x
	check(turnaround > 60.0, "it travelled out before reversing")

	# Placed after the shot has already passed, so only a projectile travelling back can
	# possibly reach it.
	var bot := _add_bot(arena, Vector2(50.0, 0.0))
	await advance_physics(12)

	check_near(
		bot.get_health_component().current, 2.0, "the returning shot hit on the way back"
	)
	await _teardown(arena)


func _test_impact_explosion_catches_a_neighbour() -> void:
	var arena := _make_arena()
	var struck := _add_bot(arena, Vector2(100.0, 0.0))
	var neighbour := _add_bot(arena, Vector2(130.0, 0.0))
	var distant := _add_bot(arena, Vector2(230.0, 0.0))
	await advance_physics(2)

	var config := _rivet_variant()
	config.explosion_radius = 44.0

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(30)

	check_near(
		struck.get_health_component().current,
		2.0,
		"the enemy hit directly takes the shot but not its own blast",
	)
	check_near(neighbour.get_health_component().current, 2.0, "the blast catches the neighbour")
	check_near(
		distant.get_health_component().current, 3.0, "the blast does not reach past its radius"
	)
	await _teardown(arena)


func _test_chain_lightning_jumps_twice() -> void:
	var arena := _make_arena()
	var struck := _add_bot(arena, Vector2(100.0, 0.0))
	var second := _add_bot(arena, Vector2(145.0, 0.0))
	var third := _add_bot(arena, Vector2(190.0, 0.0))
	await advance_physics(2)

	var jumps := [0]
	var handler := func(_from: Vector2, _to: Vector2) -> void: jumps[0] += 1
	EventBus.chain_jumped.connect(handler)

	# The item's own numbers, applied on the shot the item actually fires on.
	var leak := _require_item(&"capacitor_leak")
	var config := _rivet_variant()
	if leak != null:
		ProjectileModifierStack.from_items([leak]).apply(config, 5)

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(30)

	check(jumps[0] == 2, "the discharge jumped to both reachable enemies")
	check_near(struck.get_health_component().current, 2.0, "the direct hit is not also a jump")
	check_near(second.get_health_component().current, 3.0 - 0.7, "the first jump dealt 0.7")
	check_near(third.get_health_component().current, 3.0 - 0.7, "the chain carried on to the third")

	EventBus.chain_jumped.disconnect(handler)
	await _teardown(arena)


func _test_volatile_kernel_detonates_on_a_kill() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	var effects := ItemEffects.new()
	arena.add_child(effects)
	effects.bind_player(player)

	var doomed := _add_bot(arena, Vector2(200.0, 0.0))
	var neighbour := _add_bot(arena, Vector2(226.0, 0.0))
	var distant := _add_bot(arena, Vector2(300.0, 0.0))
	await advance_physics(2)

	var kernel := _require_item(&"volatile_kernel")
	if kernel == null:
		await _teardown(arena)
		return
	player.get_item_inventory().add(kernel)

	doomed.get_health_component().apply_damage(DamageInfo.new(99.0))
	await advance_physics(2)

	check_near(
		neighbour.get_health_component().current, 2.0, "the corpse's blast damages what stood beside it"
	)
	check_near(
		distant.get_health_component().current, 3.0, "and does not reach an enemy across the room"
	)
	await _teardown(arena)


func _test_scrap_magnet_pulls_nearby_pickups() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	var magnet := _require_item(&"scrap_magnet")
	if magnet == null:
		await _teardown(arena)
		return

	var effects := ItemEffects.new()
	arena.add_child(effects)
	effects.bind_player(player)

	var near := _add_pickup(arena, player.global_position + Vector2(50.0, 0.0))
	var far := _add_pickup(arena, player.global_position + Vector2(240.0, 0.0))
	await advance_physics(2)

	var near_before := near.global_position.distance_to(player.global_position)
	var far_before := far.global_position.distance_to(player.global_position)

	player.get_item_inventory().add(magnet)
	await advance_physics(10)

	check(
		near.global_position.distance_to(player.global_position) < near_before - 5.0,
		"a pickup inside the magnet's reach is pulled in",
	)
	check_near(
		far.global_position.distance_to(player.global_position),
		far_before,
		"one outside it is left alone",
		1.0,
	)
	await _teardown(arena)


## Reported: a kill near a corner could drop scrap that scattered into the wall it died
## against, which the player could never reach — not even with Scrap Magnet, since the pull is
## gated by the player's own distance and a player's body cannot stand inside a wall either.
## Placing four death points hard against a single block's corners, where an unchecked +/-9px
## scatter (`LootSpawner.SCATTER`) would cross into it on a fair fraction of draws, is what
## makes this a check on the rejection logic rather than a check that mostly passes by luck.
func _test_scrap_scatter_avoids_geometry() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(100.0, 100.0), Vector2i(32, 32))
	await advance_physics(1)

	var spawner := LootSpawner.new()
	arena.add_child(spawner)
	spawner._rng.seed = 4242

	for corner: Vector2 in [
		Vector2(95.0, 95.0), Vector2(137.0, 95.0), Vector2(95.0, 137.0), Vector2(137.0, 137.0),
	]:
		spawner._spawn_scrap(corner, 20)
	await advance_physics(2)

	var pickups := arena.get_tree().get_nodes_in_group(Pickup.GROUP)
	check(pickups.size() > 0, "scrap actually spawned")
	var embedded := 0
	for node: Node in pickups:
		if _is_solid_at((node as Pickup).global_position):
			embedded += 1
	check(embedded == 0, "no scrap landed inside the wall (%d of %d did)" % [embedded, pickups.size()])

	await _teardown(arena)


## Reported: a drop point *inside* an obstacle — an enemy knocked into a corner dying with its
## origin embedded, or a reward point's fixed offset poking into an authored block — fell
## through every scatter attempt and landed the pickup at the blocked point verbatim, and the
## no-scatter item path never checked at all. Both must relocate to the nearest clear point.
## The drop point is the dead centre of a 32px block, so every +/-9px scatter candidate is
## blocked too and only the relocation path can produce a reachable pickup.
func _test_drop_point_inside_geometry_relocates() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(100.0, 100.0), Vector2i(32, 32))
	await advance_physics(1)

	var spawner := LootSpawner.new()
	arena.add_child(spawner)
	spawner._rng.seed = 4242

	var inside := Vector2(116.0, 116.0)
	spawner._spawn_scrap(inside, 10)
	# The scatter=false route items take — previously returned the blocked point unchecked.
	spawner._spawn(LootSpawner.REPAIR_CELL_CONFIG, inside, false)
	await advance_physics(2)

	var pickups := arena.get_tree().get_nodes_in_group(Pickup.GROUP)
	check(pickups.size() == 11, "every pickup spawned (%d of 11)" % pickups.size())
	var embedded := 0
	for node: Node in pickups:
		if _is_solid_at((node as Pickup).global_position):
			embedded += 1
	check(embedded == 0, "no pickup stayed inside the block (%d of %d did)" % [embedded, pickups.size()])

	await _teardown(arena)


## Same query PopUpDrone tests itself against — real physics geometry, not the room template.
func _is_solid_at(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = Teams.LAYER_WORLD
	query.collide_with_areas = false
	return not get_viewport().world_2d.direct_space_state.intersect_point(query, 1).is_empty()


func _test_debug_drone_fires_with_the_player() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	var drone_item := _require_item(&"debug_drone")
	if drone_item == null:
		await _teardown(arena)
		return
	await advance_physics(2)

	var weapon := player.get_weapon_controller()

	# Baseline: one trigger pull is one projectile and one shot on the counter.
	var solo := _count_spawns(arena)
	_pull_trigger(weapon, player)
	await advance_physics(2)
	check(solo[0] == 1, "without a drone, one pull fires one projectile")
	check(weapon.get_shots_fired() == 1, "and counts one shot")

	player.get_item_inventory().add(drone_item)
	await advance_physics(2)
	check(_count_drones(player) == 1, "Debug Drone adds exactly one drone")

	var escorted := _count_spawns(arena)
	_pull_trigger(weapon, player)
	await advance_physics(2)

	check(escorted[0] == 2, "with a drone, one pull fires two projectiles")
	check(
		weapon.get_shots_fired() == 3,
		"and both advance one shared counter (got %d)" % weapon.get_shots_fired(),
	)
	await _teardown(arena)


## Spec section 13 names exactly one *explicit* synergy: drone shots must count toward
## Capacitor Leak's fifth-shot trigger. Measured rather than asserted — the chain arrives
## after five shots either way, so with a drone doubling the rate it must arrive after
## three trigger pulls instead of five.
func _test_drone_shots_advance_the_chain_trigger() -> void:
	var without := await _pulls_until_a_chaining_shot([&"capacitor_leak"])
	var with_drone := await _pulls_until_a_chaining_shot([&"capacitor_leak", &"debug_drone"])

	check(without == 5, "alone, the chain arrives on the fifth trigger pull (got %d)" % without)
	check(
		with_drone == 3,
		"with a drone, it arrives on the third — drone shots count (got %d)" % with_drone,
	)


## Fires until a projectile carrying a chain is spawned, and returns how many trigger pulls
## that took. Returns 0 if it never happens.
func _pulls_until_a_chaining_shot(ids: Array[StringName]) -> int:
	var arena := _make_arena()
	var player := _add_player(arena)
	for id: StringName in ids:
		var item := _require_item(id)
		if item != null:
			player.get_item_inventory().add(item)
	await advance_physics(2)

	var chained := [0]
	var container := arena.get_node("Projectiles")
	container.child_entered_tree.connect(func(child: Node) -> void:
		var projectile := child as Projectile
		if projectile != null and projectile.config.chain_count > 0 and chained[0] == 0:
			chained[0] = -1)

	var weapon := player.get_weapon_controller()
	var pulls := 0
	for _pull: int in 12:
		pulls += 1
		_pull_trigger(weapon, player)
		# A full fire interval between pulls, because that is the rate the game actually
		# fires at and the drone has a cooldown of its own. Firing faster than the weapon
		# can makes the drone skip shots, which is a property of the test rather than of
		# the game.
		await advance_physics(16)
		if chained[0] == -1:
			await _teardown(arena)
			return pulls

	await _teardown(arena)
	return 0


# --- Fixtures -----------------------------------------------------------------


## One trigger pull, off cooldown. Goes through the weapon rather than through input so the
## check is about firing rather than about key handling.
func _pull_trigger(weapon: WeaponController, player: Player) -> void:
	weapon.step(10.0)
	weapon.try_fire(player.global_position, Vector2.RIGHT)


func _count_drones(player: Player) -> int:
	var total := 0
	for child: Node in player.get_children():
		if child is PlayerDrone:
			total += 1
	return total


# --- Status effects -----------------------------------------------------------
#
# The system Cold Cache and Hot Reload are the reason for. Two rules from the Development
# plan are what these checks are actually defending: statuses must compose rather than
# overwrite, and resistance must shorten control effects rather than make the items that
# apply them do nothing.


## `projectile_add` on an array field appends. This is the mechanism the two status items
## compose through, and it is worth checking directly because the alternative — using
## `projectile_set` — looks identical in a `.tres` and silently keeps only one of them.
func _test_add_appends_to_array_fields() -> void:
	var existing: Array[StringName] = [&"existing"]
	var addition: Array[StringName] = [&"added"]
	var expected: Array[StringName] = [&"existing", &"added"]

	var config := _rivet_variant()
	config.status_effects = existing

	var item := ItemConfig.new()
	item.projectile_add = {&"status_effects": addition}
	ProjectileModifierStack.from_items([item]).apply(config, 1)

	check(
		config.status_effects == expected,
		"adding to an array field appends rather than replacing (got %s)" % [config.status_effects],
	)


func _test_two_status_items_compose_on_one_shot() -> void:
	var cold := _require_item(&"cold_cache")
	var hot := _require_item(&"hot_reload")
	if cold == null or hot == null:
		return

	# Shot five, so Hot Reload's every-fifth gate is open and both items contribute.
	var both := _config_with([&"cold_cache", &"hot_reload"] as Array[StringName])
	var fifth := _rivet_variant()
	ProjectileModifierStack.from_items([cold, hot]).apply(fifth, 5)
	check(
		StatusEffectController.CHILL in fifth.status_effects
			and StatusEffectController.BURN in fifth.status_effects,
		"a fifth shot with both items carries both statuses (got %s)" % [fifth.status_effects],
	)

	# Shot four: Cold Cache is unconditional, Hot Reload is not.
	var chill_only: Array[StringName] = [StatusEffectController.CHILL]
	check(
		both.status_effects == chill_only,
		"a shot outside the fifth carries only the unconditional one (got %s)" % [both.status_effects],
	)


## `duplicate()` is shallow, so every "copy" of a projectile config used to share one array
## object. Items append to `status_effects`, which means the weapon's own resource would have
## grown by an entry per shot and a Cold Cache run would have been applying dozens of stacked
## chills within a room — while the source `.tres` on disk stayed innocent.
func _test_spawn_copy_does_not_share_its_status_array() -> void:
	var source := load(RIVET_PATH) as ProjectileConfig
	var before := source.status_effects.size()

	var first := source.spawn_copy()
	first.status_effects.append(&"chill")
	var second := source.spawn_copy()

	check(source.status_effects.size() == before, "appending to a copy leaves the source alone")
	check(second.status_effects.is_empty(), "and the next copy does not inherit it")


func _test_chill_stacks_then_freezes() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2.ZERO)
	await advance_physics(2)

	var status := bot.get_status_controller()
	if not require(status, "the enemy has a status controller"):
		await _teardown(arena)
		return

	var definition: Dictionary = StatusEffectController.DEFINITIONS[StatusEffectController.CHILL]
	var to_freeze := int(definition["max_stacks"])

	for _stack: int in to_freeze - 1:
		status.apply(StatusEffectController.CHILL)
	var slowed := status.get_speed_scale()
	check(slowed < 1.0 and slowed > 0.0, "chill slows without stopping (scale %.2f)" % slowed)
	check(
		status.get_stacks(StatusEffectController.CHILL) == to_freeze - 1,
		"and accumulates one stack per hit",
	)

	status.apply(StatusEffectController.CHILL)
	check(status.is_frozen(), "the last chill freezes the target outright")
	check(
		not status.has_effect(StatusEffectController.CHILL),
		"and spends the chill stacks rather than carrying both",
	)
	await _teardown(arena)


## Cold Cache chills on *every* hit and the starting weapon fires four times a second, so
## without an immunity window one item removes a target from the fight permanently. The
## window is what keeps it a strong item rather than an off switch.
func _test_freeze_cannot_be_chained_indefinitely() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2.ZERO)
	await advance_physics(2)
	var status := bot.get_status_controller()

	status.apply(StatusEffectController.FREEZE)
	check(status.is_frozen(), "the target freezes")

	var definition: Dictionary = StatusEffectController.DEFINITIONS[StatusEffectController.FREEZE]
	var frames := int(float(definition["seconds"]) * Engine.physics_ticks_per_second) + 4
	await advance_physics(frames)
	check(not status.is_frozen(), "and thaws on its own")

	check(
		not status.apply(StatusEffectController.FREEZE),
		"a freeze arriving immediately after is refused",
	)
	check(not status.is_frozen(), "so the target actually gets to move")

	# Chill must keep working during the window, or the item stops doing anything at all
	# rather than merely stopping the lock.
	check(status.apply(StatusEffectController.CHILL), "but chill still lands during it")
	await _teardown(arena)


## The Development plan is explicit that boss resistance "should shorten control effects
## rather than make those items do nothing", which is two assertions, not one.
func _test_resistance_shortens_control_without_removing_it() -> void:
	var plain := StatusEffectController.new()
	var resistant := StatusEffectController.new()
	resistant.control_resistance = 0.65
	add_child(plain)
	add_child(resistant)
	await advance_physics(1)

	plain.apply(StatusEffectController.FREEZE)
	resistant.apply(StatusEffectController.FREEZE)

	var plain_left := plain.get_seconds_left(StatusEffectController.FREEZE)
	var resistant_left := resistant.get_seconds_left(StatusEffectController.FREEZE)
	check(resistant_left < plain_left, "resistance shortens the freeze (%.2fs against %.2fs)" % [
		resistant_left, plain_left,
	])
	check(resistant.is_frozen(), "but the freeze still happens")

	# The floor is what makes that true at the extreme, so it is checked at the extreme.
	var immovable := StatusEffectController.new()
	immovable.control_resistance = 1.0
	add_child(immovable)
	await advance_physics(1)
	immovable.apply(StatusEffectController.FREEZE)
	check(
		immovable.get_seconds_left(StatusEffectController.FREEZE)
			>= StatusEffectController.MIN_CONTROL_SECONDS,
		"even total resistance leaves a real, if brief, window",
	)

	plain.queue_free()
	resistant.queue_free()
	immovable.queue_free()
	await advance_physics(2)


func _test_burn_damages_over_time_and_is_not_resisted() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2.ZERO)
	await advance_physics(2)

	var status := bot.get_status_controller()
	var health := bot.get_health_component()
	var before := health.current

	status.apply(StatusEffectController.BURN)
	var definition: Dictionary = StatusEffectController.DEFINITIONS[StatusEffectController.BURN]
	await advance_physics(int(float(definition["tick_seconds"]) * Engine.physics_ticks_per_second) + 4)

	check(health.current < before, "burning costs integrity over time (%.2f -> %.2f)" % [
		before, health.current,
	])
	check(
		is_equal_approx(status.get_speed_scale(), 1.0),
		"and does not slow the target — burn is damage, not control",
	)

	# Resistance is for control effects only; shortening a burn would make one number mean
	# two different things depending on which item the player brought.
	var resistant := StatusEffectController.new()
	resistant.control_resistance = 1.0
	add_child(resistant)
	await advance_physics(1)
	resistant.apply(StatusEffectController.BURN)
	check_near(
		resistant.get_seconds_left(StatusEffectController.BURN),
		float(definition["seconds"]),
		"a fully resistant target still burns for the full duration",
		0.1,
	)
	resistant.queue_free()
	await _teardown(arena)


func _test_statuses_compose_rather_than_overwrite() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2.ZERO)
	await advance_physics(2)
	var status := bot.get_status_controller()

	status.apply(StatusEffectController.CHILL)
	status.apply(StatusEffectController.BURN)

	check(
		status.has_effect(StatusEffectController.CHILL)
			and status.has_effect(StatusEffectController.BURN),
		"an enemy can be chilled and burning at once",
	)
	check(
		status.get_speed_scale() < 1.0,
		"the chill still slows it while the burn runs (%.2f)" % status.get_speed_scale(),
	)

	# And the slow is the product across sources rather than the worst single one, which is
	# what stops a second slow item from being worth nothing.
	var single := status.get_speed_scale()
	status.apply(StatusEffectController.CHILL)
	check(status.get_speed_scale() < single, "a second chill compounds rather than replacing")
	await _teardown(arena)


# --- Development's six items ---------------------------------------------------


func _test_memory_spike_pierces_one_extra_enemy() -> void:
	var arena := _make_arena()
	var near := _add_bot(arena, Vector2(60.0, 0.0))
	var far := _add_bot(arena, Vector2(110.0, 0.0))
	await advance_physics(2)

	var near_before := near.get_health_component().current
	var far_before := far.get_health_component().current

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _config_with([&"memory_spike"] as Array[StringName]))
	await advance_physics(20)

	check(near.get_health_component().current < near_before, "the first enemy is hit")
	check(
		far.get_health_component().current < far_before,
		"and the shot carries on into the one behind it",
	)
	await _teardown(arena)


func _test_core_dump_explodes_on_impact() -> void:
	var arena := _make_arena()
	var struck := _add_bot(arena, Vector2(60.0, 0.0))
	# Beside the target rather than behind it, so what kills it can only be the blast.
	var neighbour := _add_bot(arena, Vector2(60.0, 20.0))
	await advance_physics(2)

	var neighbour_before := neighbour.get_health_component().current
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _config_with([&"core_dump"] as Array[StringName]))
	await advance_physics(20)

	check(struck.get_health_component().current < 3.0, "the shot hits what it was aimed at")
	check(
		neighbour.get_health_component().current < neighbour_before,
		"and the blast catches the enemy beside it",
	)
	await _teardown(arena)


func _test_cold_cache_chills_what_it_hits() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(60.0, 0.0))
	await advance_physics(2)

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _config_with([&"cold_cache"] as Array[StringName]))
	await advance_physics(20)

	var status := bot.get_status_controller()
	check(status.has_effect(StatusEffectController.CHILL), "a Cold Cache hit chills the target")
	check(status.get_speed_scale() < 1.0, "which actually slows it")
	await _teardown(arena)


func _test_hot_reload_burns_on_the_fifth_shot() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(60.0, 0.0))
	await advance_physics(2)

	var hot := _require_item(&"hot_reload")
	if hot == null:
		await _teardown(arena)
		return
	var stack := ProjectileModifierStack.from_items([hot])

	var fourth := _rivet_variant()
	stack.apply(fourth, 4)
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, fourth)
	await advance_physics(20)
	check(
		not bot.get_status_controller().has_effect(StatusEffectController.BURN),
		"a fourth shot does not burn",
	)

	var fifth := _rivet_variant()
	stack.apply(fifth, 5)
	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, fifth)
	await advance_physics(20)
	check(
		bot.get_status_controller().has_effect(StatusEffectController.BURN),
		"the fifth one does",
	)
	await _teardown(arena)


## Breakpoint is the only one of the six whose effect is not carried by a projectile, so it
## is the only one that can be broken by the dash signal changing shape.
func _test_breakpoint_chills_on_a_dash() -> void:
	var arena := _make_arena()
	var effects := ItemEffects.new()
	arena.add_child(effects)

	var player := _add_player(arena)
	player.global_position = Vector2.ZERO
	var inventory := ItemInventory.find_on(player)
	var item := _require_item(&"breakpoint")
	if item == null or inventory == null:
		await _teardown(arena)
		return
	inventory.add(item)
	effects.bind_player(player)

	var near := _add_bot(arena, Vector2(40.0, 0.0))
	var far := _add_bot(arena, Vector2(item.dash_pulse_radius + 60.0, 0.0))
	await advance_physics(2)

	EventBus.player_dash_started.emit(Vector2.RIGHT)
	await advance_physics(2)

	check(
		near.get_status_controller().has_effect(StatusEffectController.CHILL),
		"dashing chills an enemy inside the pulse",
	)
	check(
		not far.get_status_controller().has_effect(StatusEffectController.CHILL),
		"and leaves one outside it alone",
	)
	await _teardown(arena)


# --- The three that are purely a cost ------------------------------------------
#
# Blocking I/O, Tech Debt, and Legacy Runtime are the first items in the pool with no upside
# at all. They sit in the full pool — shop stands and boss choices included — so an offer the
# player should refuse is what makes the offers they accept a decision.


## The player is never shown a description, so rarity, category, and the accent colour are
## the entire warning. An item that hurts and looks like a reward is a lie the pickup banner
## cannot correct.
func _test_the_harmful_three_are_labelled_as_such() -> void:
	for id: StringName in [&"blocking_io", &"tech_debt", &"legacy_runtime"]:
		var item := _require_item(id)
		if item == null:
			continue
		check(item.rarity == ItemConfig.Rarity.CORRUPTED, "%s is flagged corrupted" % id)
		check(
			item.category == ItemConfig.Category.CORRUPTED_FIRMWARE,
			"%s is categorised as corrupted firmware" % id,
		)
		check(item.has_tag(&"hindrance"), "%s is tagged as a hindrance" % id)
		check(
			item.fire_rate_scale <= 1.0
				and item.max_integrity_delta <= 0.0
				and item.heal_on_pickup <= 0.0
				and item.drone_count <= 0
				and item.projectile_scale.is_empty()
				and item.projectile_add.is_empty(),
			"%s grants nothing — it is a cost, not a trade" % id,
		)


func _test_blocking_io_forbids_firing_on_the_move() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	# Moving, with nothing held: the ordinary robot fires on the move.
	player.velocity = Vector2(Player.STILLNESS_SPEED + 60.0, 0.0)
	check(player._can_fire_while_moving(), "without the item, moving does not block the weapon")

	var inventory := ItemInventory.find_on(player)
	var item := _require_item(&"blocking_io")
	if item == null or inventory == null:
		await _teardown(arena)
		return
	inventory.add(item)
	await advance_physics(1)

	check(not player._can_fire_while_moving(), "with it held, a moving robot cannot fire")

	player.velocity = Vector2.ZERO
	check(player._can_fire_while_moving(), "and a stopped one can")

	# The threshold exists so the deceleration tail is not a permanent jam; a robot barely
	# drifting has stopped as far as the player is concerned.
	player.velocity = Vector2(Player.STILLNESS_SPEED * 0.5, 0.0)
	check(player._can_fire_while_moving(), "a robot coasting to a halt counts as stopped")
	await _teardown(arena)


## The debt has to survive the room it was incurred in, apply to enemies spawned later, and
## reach Recursion's fragments — which size themselves *after* spawning and would otherwise
## be a debt-free enemy farmed out of a debt-scaled one.
func _test_tech_debt_compounds_across_rooms() -> void:
	var restore := RunManager.enemy_health_scale
	RunManager.enemy_health_scale = 1.0

	var arena := _make_arena()
	var effects := ItemEffects.new()
	arena.add_child(effects)
	var player := _add_player(arena)
	var inventory := ItemInventory.find_on(player)
	var item := _require_item(&"tech_debt")
	if item == null or inventory == null:
		RunManager.enemy_health_scale = restore
		await _teardown(arena)
		return
	inventory.add(item)
	effects.bind_player(player)
	await advance_physics(2)

	var baseline := _add_bot(arena, Vector2(200.0, 0.0))
	await advance_physics(2)
	var plain_health := baseline.get_health_component().max_health

	EventBus.room_cleared.emit()
	EventBus.room_cleared.emit()
	await advance_physics(1)

	check_near(
		RunManager.enemy_health_scale,
		1.0 + item.enemy_health_growth_per_room * 2.0,
		"two cleared rooms accrue two rooms' worth of debt",
	)

	var later := _add_bot(arena, Vector2(240.0, 0.0))
	await advance_physics(2)
	check(
		later.get_health_component().max_health > plain_health,
		"an enemy met after the debt is tougher (%.2f against %.2f)" % [
			later.get_health_component().max_health, plain_health,
		],
	)

	# The enemy already standing there keeps the pool it was built with. Retroactively
	# healing live enemies mid-room would be a different and much stranger item.
	check_near(
		baseline.get_health_component().max_health,
		plain_health,
		"and one already in the room is untouched",
	)

	RunManager.enemy_health_scale = restore
	await _teardown(arena)


func _test_legacy_runtime_cripples_the_dash_without_removing_it() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var dash: DashController = player.get_node("%Dash")
	var base_cooldown := dash.get_cooldown()
	var base_charges := dash.get_max_charges()

	var inventory := ItemInventory.find_on(player)
	var item := _require_item(&"legacy_runtime")
	var battery := _require_item(&"backup_battery")
	if item == null or battery == null or inventory == null:
		await _teardown(arena)
		return

	inventory.add(item)
	await advance_physics(1)
	check_near(
		dash.get_cooldown(),
		base_cooldown * item.dash_cooldown_scale,
		"the dash cooldown is multiplied",
	)

	# The floor is the point. Base charges are one, so a naive −1 would leave a robot that
	# can never dash — a different game, not a harder one.
	check(
		dash.get_max_charges() >= 1,
		"but the robot can still dash at all (%d charges)" % dash.get_max_charges(),
	)
	check_near(float(dash.get_max_charges()), float(base_charges), "the last charge is protected")

	# Held alongside Backup Battery, the −1 finally has something to take.
	inventory.add(battery)
	await advance_physics(1)
	check(
		dash.get_max_charges() == base_charges,
		"and with a Backup Battery held it cancels that charge instead (%d)" % dash.get_max_charges(),
	)
	await _teardown(arena)


# --- Fixtures -----------------------------------------------------------------


func _add_pickup(arena: Node2D, at: Vector2) -> Pickup:
	var pickup: Pickup = PICKUP_SCENE.instantiate()
	pickup.config = load("res://data/pickups/scrap.tres") as PickupConfig
	pickup.position = at
	arena.add_child(pickup)
	return pickup


## Tractor Beam: the pool's first *pull*. Nothing new had to be built for it — knockback is applied
## as `direction × amount`, so a negative amount reverses the shove — and that is exactly why it is
## worth a check: the behaviour is emergent from a sign, and a well-meaning `absf()` anywhere on the
## knockback path would silently turn the item back into a shove.
##
## Also checks the classifier. An item whose whole effect is a negative number on a projectile field
## reads as a pure cost to the sign test, which is what `ItemConfig.BENEFIT_KEYS` exists to correct.
func _test_tractor_beam_drags_what_it_hits() -> void:
	var beam := _require_item(&"tractor_beam")
	if beam == null:
		return

	check(beam.has_upside(), "Tractor Beam reads as a benefit despite being a negative number")
	check(not beam.is_hindrance(), "and is not tagged as a hindrance")

	var shot := _rivet_variant()
	var base_knockback := shot.knockback
	ProjectileModifierStack.from_items([beam]).apply(shot, 1)
	check(
		shot.knockback < 0.0,
		"a rivet carrying it pulls rather than shoves (%.0f from %.0f)" % [
			shot.knockback, base_knockback,
		],
	)

	# And the engine really does read that sign as a direction, on a real body.
	var arena := _make_arena()
	var bot: Enemy = TICKET_BOT_SCENE.instantiate()
	bot.position = Vector2.ZERO
	arena.add_child(bot)
	await advance_physics(2)

	var health := HealthComponent.find_on(bot)
	if require(health, "the bot has a health component"):
		# Fired rightwards: a shove would push it further right, a pull drags it back left.
		health.apply_damage(DamageInfo.new(0.5, null, Vector2.RIGHT, shot.knockback))
		check(bot._knockback.x < 0.0, "and the bot is dragged back along the shot (%.0f)" % bot._knockback.x)

	await _teardown(arena)


## Fragmentation: the same splits, thrown wide instead of forward. An enabler — it adds no children
## of its own, so it is worthless alone and reshapes whatever the build already had.
##
## The arc lands short of a full circle on purpose, and this check is where that is held.
## `Projectile._spawn_splits` fans children across `-arc/2 … +arc/2`, so at 360 the first and last
## child leave in the *same* direction — a "burst" that stacks two shots on one heading. Every split
## total the pool can reach has to produce distinct headings.
##
## Written as a *scale* rather than as a `projectile_set` for the reason Wide Bus is: Race Condition
## already assigns this exact field to pull its splits into a 28 degree cone, and two items assigning
## one field is a result that depends on pickup order. Multiplying instead composes — a cone that
## tight, thrown wide, is a wide cone — and the order-independence check below is the one that would
## have caught the collision.
func _test_fragmentation_throws_children_wide() -> void:
	var burst := _require_item(&"fragmentation")
	var fork := _require_item(&"fork_bomb")
	if burst == null or fork == null:
		return

	# A synthetic item rather than a shipped one, because the invariant is about *any* item that
	# assigns this field, and the shipped item that used to do it has since been replaced. A check
	# that could only be written while one particular `.tres` existed is a check that quietly stops
	# testing anything the day that resource is retired.
	var cone := ItemConfig.new()
	cone.id = &"test_cone"
	cone.projectile_set = {&"split_spread_degrees": 28.0}

	check(burst.projectile_add.is_empty(), "Fragmentation adds no children of its own")

	var forwards := _rivet_variant()
	ProjectileModifierStack.from_items([cone, burst]).apply(forwards, 1)
	var backwards := _rivet_variant()
	ProjectileModifierStack.from_items([burst, cone]).apply(backwards, 1)
	check_near(
		forwards.split_spread_degrees, backwards.split_spread_degrees,
		"it composes with Race Condition's cone whichever arrived first", 0.001,
	)
	check(
		forwards.split_spread_degrees > cone.projectile_set[&"split_spread_degrees"],
		"widening a tight cone leaves it wider than it was (%.0f from %.0f)" % [
			forwards.split_spread_degrees, cone.projectile_set[&"split_spread_degrees"],
		],
	)

	var shot := _rivet_variant()
	ProjectileModifierStack.from_items([fork, burst]).apply(shot, 1)
	check(
		shot.split_count == fork.projectile_add[&"split_count"],
		"it leaves the split count to whatever made the splits (%d)" % shot.split_count,
	)
	check(
		shot.split_spread_degrees > 180.0 and shot.split_spread_degrees < 360.0,
		"and throws them wide without closing the circle (%.0f degrees)" % shot.split_spread_degrees,
	)

	# The headings the game will actually produce, computed the way the projectile does.
	for count: int in range(2, 8):
		var headings: Dictionary[int, bool] = {}
		var arc := shot.split_spread_degrees
		for index: int in count:
			var offset := -arc * 0.5 + arc * (float(index) / float(count - 1))
			headings[roundi(fposmod(offset, 360.0))] = true
		check(
			headings.size() == count,
			"%d children leave on %d distinct headings" % [count, headings.size()],
		)


## Wide Bus: the pool's first item that does nothing at all by itself. Split children keep 60% of
## their parent's damage and chain jumps 70%; this cancels both, and only matters to a build that
## already splits or chains.
##
## Written as a *scale* rather than as a `projectile_set`, which is the whole reason it is safe: Fork
## Bomb and Capacitor Leak both *assign* those same two fields, and two items assigning one field
## would make the result depend on pickup order. Sets are applied before scales, so this multiplies
## whatever they set and the answer is the same either way round — which is what the check below
## pins.
func _test_wide_bus_stops_children_losing_damage() -> void:
	var bus := _require_item(&"wide_bus")
	var fork := _require_item(&"fork_bomb")
	var leak := _require_item(&"capacitor_leak")
	if bus == null or fork == null or leak == null:
		return

	check(bus.is_stat_only(), "Wide Bus changes numbers rather than turning anything on")

	var forwards := _rivet_variant()
	ProjectileModifierStack.from_items([fork, leak, bus]).apply(forwards, 1)
	check_near(
		forwards.split_damage_scale, 1.0,
		"split children hit as hard as their parent", 0.02,
	)
	check_near(
		forwards.chain_damage_scale, 1.0,
		"and so does every chain jump", 0.02,
	)

	var backwards := _rivet_variant()
	ProjectileModifierStack.from_items([bus, leak, fork]).apply(backwards, 1)
	check_near(
		backwards.split_damage_scale, forwards.split_damage_scale,
		"and pickup order does not change either", 0.001,
	)
	check_near(
		backwards.chain_damage_scale, forwards.chain_damage_scale,
		"whichever item arrived first", 0.001,
	)

	# Worthless alone is a claim about the item, so it is checked rather than asserted in prose.
	var lonely := _rivet_variant()
	ProjectileModifierStack.from_items([bus]).apply(lonely, 1)
	check(lonely.split_count == 0 and lonely.chain_count == 0, "on its own it splits and chains nothing")


## Faraday Cage. A charge, not a window: one hit is refused whatever it was, and the next one lands.
func _test_faraday_cage_absorbs_one_hit_a_room() -> void:
	var cage := _require_item(&"faraday_cage")
	if cage == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var health := player.get_health_component()
	player.get_item_inventory().add(cage)
	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 0)
	check(player.get_shield_charges() == 1, "entering a room banks a shield charge")

	# The same entry also opens the doorway grace window, and a hit refused by that window never
	# reaches the absorber — so the charge would still be sitting there and this test would be
	# measuring the wrong refusal. Waited out rather than worked around, because the ordering is
	# real: a shot that catches the player on the threshold costs them neither integrity nor a
	# shield charge, which is the right answer to both questions.
	await _skip_room_entry_grace(player)

	var absorbed: Array[int] = []
	var on_absorbed := func(_at: Vector2, left: int) -> void: absorbed.append(left)
	EventBus.player_shield_absorbed.connect(on_absorbed)

	var full := health.current
	# Large, to prove the shield refuses the hit rather than trimming it.
	check(not health.apply_damage(DamageInfo.new(4.0)), "an absorbed hit reports that nothing landed")
	check_near(health.current, full, "and costs no integrity")
	check(absorbed.size() == 1 and absorbed[0] == 0, "the charge is spent and announced")

	# The post-hit invulnerability window never opened, because no hit landed — so the next one is
	# live immediately, which is what makes a shield a charge rather than a second of safety.
	check(health.apply_damage(DamageInfo.new(1.0)), "the next hit lands")
	check_near(health.current, full - 1.0, "and costs its integrity")

	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 1)
	check(player.get_shield_charges() == 1, "the next room refills it")

	EventBus.player_shield_absorbed.disconnect(on_absorbed)
	await _teardown(arena)


## Static Charge. The pool's first amplifier: it makes damage the player has not dealt yet worth
## more, so it pays out for every other source in the room rather than only for the shot carrying it.
func _test_static_charge_makes_every_source_hurt_more() -> void:
	var charge := _require_item(&"static_charge")
	if charge == null:
		return
	var expected: Array[StringName] = [StatusEffectController.SHOCK]
	check(
		charge.projectile_add.get(&"status_effects") == expected,
		"Static Charge applies shock and nothing else",
	)

	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(200.0, 0.0))
	await advance_physics(2)

	var health := bot.get_health_component()
	var status := StatusEffectController.find_on(bot)
	if not require(status, "the bot can carry a status"):
		await _teardown(arena)
		return

	check_near(status.get_damage_taken_scale(), 1.0, "an unshocked target takes damage as written")
	status.apply(StatusEffectController.SHOCK)

	var per_stack := float(StatusEffectController.DEFINITIONS[StatusEffectController.SHOCK]["damage_taken_per_stack"])
	check_near(status.get_damage_taken_scale(), 1.0 + per_stack, "one stack amplifies by its share")

	# Through the ordinary damage path, because the point is that *everything* hurts more — a burn
	# tick and a compile lane are amplified as surely as the shot that applied the shock.
	var before := health.current
	var info := DamageInfo.new(1.0)
	health.apply_damage(info)
	check_near(before - health.current, 1.0 + per_stack, "and a plain one-point hit lands amplified")
	check_near(info.amount, 1.0 + per_stack, "with the event reporting what actually landed")

	status.apply(StatusEffectController.SHOCK)
	check_near(
		status.get_damage_taken_scale(), 1.0 + per_stack * 2.0,
		"and a second stack is worth as much as the first",
	)

	await _teardown(arena)


## Cache Warmer. Worth exactly one shot per room, which is the whole of what makes it a decision
## about how the player walks through a door.
func _test_cache_warmer_pays_for_the_opening_shot_only() -> void:
	var warmer := _require_item(&"cache_warmer")
	if warmer == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	check_near(player.opening_shot_damage_scale(), 1.0, "an empty build multiplies nothing")
	player.get_item_inventory().add(warmer)
	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 0)
	check_near(
		player.opening_shot_damage_scale(), warmer.first_shot_damage_scale,
		"the first shot of a room carries the bonus",
	)

	# Firing is what spends it — the flag the game clears is the one this reads.
	player._room_opening_shot = false
	check_near(player.opening_shot_damage_scale(), 1.0, "and every shot after it is ordinary")

	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 1)
	check_near(
		player.opening_shot_damage_scale(), warmer.first_shot_damage_scale,
		"walking into the next room re-arms it",
	)
	await _teardown(arena)


## Garbage Collector. On-kill control rather than on-kill damage: the same trigger Volatile Kernel
## uses, answering with a status, which is what makes it a different item rather than a smaller one.
func _test_garbage_collector_vents_over_a_kill() -> void:
	var collector := _require_item(&"garbage_collector")
	if collector == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	var effects := ItemEffects.new()
	arena.add_child(effects)
	effects.bind_player(player)

	var neighbour := _add_bot(arena, Vector2(200.0, 0.0))
	var distant := _add_bot(arena, Vector2(400.0, 0.0))
	await advance_physics(2)
	player.get_item_inventory().add(collector)

	# The kill itself is not simulated: what is being checked is what the *death* does to the
	# bystanders, and `enemy_killed` is the event the item hangs off.
	EventBus.enemy_killed.emit(null, Vector2(210.0, 0.0))
	await advance_physics(1)

	var near_status := StatusEffectController.find_on(neighbour)
	var far_status := StatusEffectController.find_on(distant)
	if require(near_status, "the neighbour can carry a status") and require(far_status, "so can the distant one"):
		check(near_status.has_effect(StatusEffectController.CHILL), "what stood beside the kill is chilled")
		check(not far_status.has_effect(StatusEffectController.CHILL), "and what stood across the room is not")

	await _teardown(arena)


## Null Check. A threshold rather than a damage number, so it keeps meaning the same thing on a floor
## where Tech Debt has multiplied every pool.
func _test_null_check_finishes_what_it_breaks() -> void:
	var executioner := _require_item(&"null_check")
	if executioner == null:
		return

	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(200.0, 0.0))
	await advance_physics(2)

	var health := bot.get_health_component()
	var threshold: float = executioner.projectile_set[&"execute_threshold"]

	# Left just above the line: an ordinary graze must not kill, or the item is "shots kill things".
	health.apply_damage(DamageInfo.new(health.max_health * (1.0 - threshold) - 0.2))
	check(health.is_alive(), "a target above the threshold survives the graze")

	# Enough to cross the line and nowhere near enough to kill: 0.25 off a pool of 3 leaves 0.55,
	# which is under a fifth. What finishes the bot is the threshold, not the damage.
	var shot := (load(RIVET_PATH) as ProjectileConfig).spawn_copy()
	shot.damage = 0.25
	shot.execute_threshold = threshold
	shot.speed = 600.0
	ProjectileFactory.spawn_configured(
		arena.get_node("Projectiles"), shot, Vector2.RIGHT, Vector2(150.0, 0.0), Teams.Id.PLAYER
	)
	await advance_physics(12)

	check(
		not is_instance_valid(bot) or not bot.get_health_component().is_alive(),
		"and a scratch that takes it under the threshold finishes it outright",
	)
	await _teardown(arena)


## Mutex Lock and Adrenal Loop. Both pay for a *state* rather than for being held, so both are
## checked the same way: the bonus arrives when the condition does and leaves when it goes.
func _test_mutex_lock_and_adrenal_loop_pay_for_a_state() -> void:
	var lock := _require_item(&"mutex_lock")
	var loop := _require_item(&"adrenal_loop")
	if lock == null or loop == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var weapon := player.get_weapon_controller()
	var base := weapon.fire_rate_multiplier

	player.get_item_inventory().add(lock)
	player.velocity = Vector2.ZERO
	await advance_physics(1)
	check_near(weapon.fire_rate_multiplier, base, "the bonus is not paid the instant the robot stops")

	# Long enough to have earned it. The player is parked, so nothing moves it.
	await advance_physics(int(lock.stillness_seconds * 60.0) + 4)
	check_near(
		weapon.fire_rate_multiplier, base * lock.stillness_fire_rate_scale,
		"standing still for long enough locks in the faster cycle",
	)

	player.velocity = Vector2(200.0, 0.0)
	await advance_physics(2)
	check_near(weapon.fire_rate_multiplier, base, "and moving gives it straight back")

	# Adrenal Loop, on the same weapon: a state the player would rather not be in.
	player.get_item_inventory().add(loop)
	var health := player.get_health_component()
	health.apply_damage(DamageInfo.new(health.current - loop.low_integrity_points))
	await advance_physics(2)
	check_near(
		weapon.fire_rate_multiplier, base * loop.low_integrity_fire_rate_scale,
		"down to its last point the weapon speeds up",
	)

	health.heal(health.max_health)
	await advance_physics(2)
	check_near(weapon.fire_rate_multiplier, base, "and repairing it hands the bonus back")

	await _teardown(arena)


## Interrupt Handler. The pool's first reactive payoff: everything else defensive reduces what a hit
## costs, this one makes the hit cost the room something.
func _test_interrupt_handler_answers_a_hit() -> void:
	var handler := _require_item(&"interrupt_handler")
	if handler == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	var effects := ItemEffects.new()
	arena.add_child(effects)
	effects.bind_player(player)

	var close := _add_bot(arena, player.global_position + Vector2(30.0, 0.0))
	var far := _add_bot(arena, player.global_position + Vector2(300.0, 0.0))
	await advance_physics(2)
	player.get_item_inventory().add(handler)

	var close_before := close.get_health_component().current
	var far_before := far.get_health_component().current

	player.get_health_component().apply_damage(DamageInfo.new(1.0))
	await advance_physics(2)

	check(
		close.get_health_component().current < close_before,
		"being hit blasts what is standing over the robot",
	)
	check_near(far.get_health_component().current, far_before, "and reaches nothing across the room")
	await _teardown(arena)


## Compound Interest and Swap Space. Both pay out on a cleared room, which is the event this project
## already treats as the unit of progress.
func _test_compound_interest_and_swap_space_pay_on_a_clear() -> void:
	var interest := _require_item(&"compound_interest")
	var swap := _require_item(&"swap_space")
	if interest == null or swap == null:
		return

	var arena := _make_arena()
	var player := _add_player(arena)
	var effects := ItemEffects.new()
	arena.add_child(effects)
	effects.bind_player(player)
	await advance_physics(2)

	GameManager.start_run()
	RunManager.begin_run(4242)
	RunManager.add_scrap(100)
	player.get_item_inventory().add(interest)
	player.get_item_inventory().add(swap)

	var health := player.get_health_component()
	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 0)
	# Past the doorway window, or the room costs nothing and there is nothing for Swap Space to
	# refund a share of. See `_skip_room_entry_grace`.
	await _skip_room_entry_grace(player)
	health.apply_damage(DamageInfo.new(2.0))
	var hurt := health.current

	EventBus.room_cleared.emit()
	await advance_physics(1)

	check(
		RunManager.scrap == 100 + int(100.0 * interest.scrap_interest_fraction),
		"clearing a room pays interest on what is held (%d)" % RunManager.scrap,
	)
	check_near(
		health.current, hurt + 2.0 * swap.room_damage_refund,
		"and returns its share of what the room cost",
	)

	# The ledger is per room, not per run: a second clear with no damage behind it pays nothing.
	var settled := health.current
	EventBus.room_entered.emit(RoomTemplate.Type.COMBAT, 1)
	EventBus.room_cleared.emit()
	await advance_physics(1)
	check_near(health.current, settled, "a room that cost nothing refunds nothing")

	RunManager.begin_run(1)
	await _teardown(arena)


## Failover: one lethal hit survived per run, paid for with the integrity pool itself.
##
## Four claims, and the middle two are the ones the design exists for:
##
## - The hit is survived once, at one point of integrity, with a grace window.
## - The collapsed ceiling **survives collecting another item**. `Player._apply_item_stats`
##   recomputes the maximum from the config and the inventory on every pickup, so a penalty written
##   onto the health component would be refunded by the next reward stand — which is why the debt
##   lives on `RunManager` instead.
## - The ceiling can be **rebuilt** from there: base plus the item's ceiling, minus the debt.
## - The next lethal hit, once the grace has run out, really does end the run.
func _test_failover_survives_one_hit_and_shrinks_the_pool_for_good() -> void:
	var failover := _require_item(&"failover")
	var chassis := _require_item(&"reinforced_chassis")
	var fan := _require_item(&"cooling_fan")
	if failover == null or chassis == null or fan == null:
		return

	check(failover.has_upside(), "Failover reads as an item worth taking")
	check(not failover.is_stat_only(), "and as a behaviour rather than a number")

	# A fresh run, so the penalty starts at zero — and, at the end, so the next check in this file
	# does not inherit a five-point integrity debt.
	GameManager.start_run()
	RunManager.begin_run(8675309)

	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var health := player.get_health_component()
	var base_max := health.max_health
	check_near(base_max, 6.0, "the robot starts on six integrity")

	var averted: Array[Vector2] = []
	var deaths := [0]
	var on_averted := func(at: Vector2) -> void: averted.append(at)
	var on_died := func() -> void: deaths[0] += 1
	EventBus.player_death_averted.connect(on_averted)
	EventBus.player_died.connect(on_died)

	player.get_item_inventory().add(failover)
	check_near(health.max_health, base_max, "holding Failover changes nothing on its own")
	check(
		player.get_item_inventory().get_death_save_charges() == 1,
		"and arms exactly one save",
	)

	health.apply_damage(DamageInfo.new(99.0, null, Vector2.RIGHT))

	check(health.is_alive(), "a lethal hit does not end a run holding Failover")
	check(deaths[0] == 0, "and nothing reports the player dead")
	check(averted.size() == 1, "the save is announced once (%d)" % averted.size())
	check_near(health.max_health, 1.0, "maximum integrity collapses to a single point")
	check_near(health.current, 1.0, "and the robot is left on all of it")
	check(RunManager.death_saves_spent == 1, "the run records the save as spent")
	check_near(RunManager.max_integrity_penalty, 5.0, "and charges the five points it cost")
	check(health.is_invulnerable(), "a grace window covers the rest of the volley")

	# The refund bug, pinned: any item at all recomputes the ceiling.
	player.get_item_inventory().add(fan)
	check_near(health.max_health, 1.0, "collecting an unrelated item does not hand the pool back")

	player.get_item_inventory().add(chassis)
	check_near(
		health.max_health, 3.0,
		"a +2 ceiling item rebuilds the pool from one point to three, not back to eight",
	)
	check_near(health.current, 3.0, "and its repair fills the rebuilt pool")

	# Past the grace, and now it is fatal: one save per run, not one per hit.
	health.step(failover.death_save_grace_seconds + 1.0)
	health.apply_damage(DamageInfo.new(99.0, null, Vector2.RIGHT))
	check(not health.is_alive(), "the next lethal hit ends the run")
	check(deaths[0] == 1, "and reports the death exactly once")
	check(averted.size() == 1, "with no second save")

	EventBus.player_death_averted.disconnect(on_averted)
	EventBus.player_died.disconnect(on_died)
	await _teardown(arena)

	# Dying put the game into GAME_OVER, which pauses the tree, and files the run. Both are undone
	# here so the checks after this one still get frames and a clean run.
	GameManager.start_run()
	RunManager.begin_run(1)


func _require_item(id: StringName) -> ItemConfig:
	var item: ItemConfig = _items.get(id)
	if item == null:
		fail("item '%s' is missing from data/items/" % id)
	return item


## A fresh world per integration check, including its own projectile container, so no
## check can be polluted by another's leftovers.
func _make_arena() -> Node2D:
	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)
	return arena


func _teardown(arena: Node2D) -> void:
	arena.queue_free()
	# Two frames: one for the free to be processed, one for physics to settle before
	# the next check registers its own bodies.
	await advance_physics(2)


## Counts every projectile ever added to the arena, rather than the ones alive at the end.
## Splits are deferred and short-lived, so a snapshot count is a race; this is not.
func _count_spawns(arena: Node2D) -> Array:
	var total := [0]
	var container := arena.get_node("Projectiles")
	container.child_entered_tree.connect(func(_child: Node) -> void: total[0] += 1)
	return total


func _live_projectiles(arena: Node2D) -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child: Node in arena.get_node("Projectiles").get_children():
		if child is Projectile:
			found.append(child as Projectile)
	return found


func _add_bot(arena: Node2D, at: Vector2) -> TicketBot:
	var bot: TicketBot = TICKET_BOT_SCENE.instantiate()
	bot.position = at
	arena.add_child(bot)
	return bot


func _add_player(arena: Node2D) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	# Well away from the bots the projectile checks use, so nothing shoots back.
	player.position = Vector2(-400.0, -400.0)
	arena.add_child(player)
	return player


## Waits out the immunity a room entry grants, so a check about something *else* refusing a hit is
## not quietly reading the doorway window instead.
##
## Needed by every test that announces a room and then damages the player in the same breath, which
## is the shape of half the item suite. The alternative was to have those tests damage the player
## before entering the room, and that is worse: it would move them off the sequence a real run
## produces to keep an assertion convenient.
##
## See `PlayerConfig.room_entry_grace`, and `TestFloor._test_walking_into_a_room_buys_a_moment_of_grace`
## for the window itself being checked rather than waited out.
func _skip_room_entry_grace(player: Player) -> void:
	await advance_physics(int(player.config.room_entry_grace * 60.0) + 4)


func _add_wall(arena: Node2D, at: Vector2, size: Vector2i) -> void:
	var wall: WallBlock = WALL_BLOCK_SCENE.instantiate()
	wall.size = size
	wall.position = at
	arena.add_child(wall)


## A standalone rivet config so a check can mutate it without touching the cached resource
## that other checks assert against.
func _rivet_variant() -> ProjectileConfig:
	var source := load(RIVET_PATH) as ProjectileConfig
	return source.spawn_copy()


## A rivet as it would leave the muzzle of a robot carrying the named items.
func _config_with(ids: Array[StringName]) -> ProjectileConfig:
	var held: Array[ItemConfig] = []
	for id: StringName in ids:
		var item := _require_item(id)
		if item != null:
			held.append(item)

	var config := _rivet_variant()
	ProjectileModifierStack.from_items(held).apply(config, 1)
	return config


func _fire_at(
	arena: Node2D,
	origin: Vector2,
	direction: Vector2,
	projectile_config: ProjectileConfig,
	team := Teams.Id.PLAYER,
) -> Projectile:
	var shooter := Node2D.new()
	arena.add_child(shooter)
	return ProjectileFactory.spawn_configured(
		shooter, projectile_config, direction, origin, team, shooter
	)

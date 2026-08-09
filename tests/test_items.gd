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

	_test_inventory_basics()
	_test_inventory_aggregates()
	_test_inventory_find_on()
	_test_run_manager_draws_without_repeats()
	_test_the_pool_fills_every_offer_of_a_two_floor_run()
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
	await _test_debug_drone_fires_with_the_player()
	await _test_drone_shots_advance_the_chain_trigger()

	await _test_memory_spike_pierces_one_extra_enemy()
	await _test_core_dump_explodes_on_impact()
	await _test_cold_cache_chills_what_it_hits()
	await _test_hot_reload_burns_on_the_fifth_shot()
	await _test_breakpoint_chills_on_a_dash()

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

	var drawn: Array[StringName] = []
	for _index: int in pool.size():
		var item := RunManager.draw_item(pool, rng)
		if item != null:
			drawn.append(item.id)

	check(drawn.size() == pool.size(), "the pool can be drawn down completely")
	var unique: Dictionary[StringName, bool] = {}
	for id: StringName in drawn:
		unique[id] = true
	check(unique.size() == drawn.size(), "no item is offered twice in one run")
	check(RunManager.draw_item(pool, rng) == null, "an exhausted pool draws nothing")

	RunManager.begin_run(1)
	check(
		RunManager.draw_item(pool, rng) != null, "a new run makes the whole pool available again"
	)

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
func _test_the_pool_fills_every_offer_of_a_two_floor_run() -> void:
	var first := load("res://data/floors/floor_1_help_desk.tres") as FloorConfig
	if not require(first, "floor 1 loads"):
		return
	if not require(first.next_floor, "floor 1 chains to a second floor"):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260808
	var restore := RunManager.offered_item_ids.duplicate()
	RunManager.offered_item_ids.clear()

	var empty_offers := 0
	var filled := 0
	for config: FloorConfig in [first, first.next_floor]:
		var offers := config.item_clear_indices.size() + config.shop.item_stand_count + 3
		if config.treasure_grants_item:
			offers += 1
		for _offer: int in offers:
			if RunManager.draw_item(config.item_pool, rng) == null:
				empty_offers += 1
			else:
				filled += 1

	RunManager.offered_item_ids = restore
	check(
		empty_offers == 0,
		"a two-floor run fills all %d item offers (%d came up empty)" % [
			filled + empty_offers, empty_offers,
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

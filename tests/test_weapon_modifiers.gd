extends TestCase
## Checks for weapon modifiers on items, roadmap SYS-1: `WeaponModifierStack`, the pattern fields it
## reaches on `WeaponConfig`, and the charged trigger.
##
## No shipped item uses any of this yet, so every item here is made in code. That is the point of
## the checks: when the first multi-shot or charge item lands as a `.tres`, the machinery it names
## has already been fired, and the only thing left to test is the item's own numbers.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ITEM_DIRECTORY := "res://data/items/"
const BLASTER_PATH := "res://data/weapons/rivet_blaster.tres"


func run() -> void:
	_test_no_shipped_item_names_a_missing_weapon_field()
	_test_the_stack_sets_then_adds_then_scales()
	_test_the_stack_leaves_the_weapon_alone_when_nothing_changes_it()
	_test_pickup_order_does_not_matter()
	_test_refused_and_misspelt_fields_are_reported()
	_test_weapon_items_are_classified()

	await _test_parallel_shots_straddle_the_aim_line()
	await _test_rear_shots_alternate()
	await _test_a_charge_fires_on_release_harder_the_longer_it_was_held()
	await _test_a_release_during_the_cooldown_fires_when_it_ends()
	await _test_the_robot_charges_from_the_fire_button()
	await _test_blocking_io_forbids_charging_on_the_move()
	await _test_the_drone_fires_the_same_pattern()
	await _test_an_emptied_build_restores_the_shipped_weapon()


# --- The stack ----------------------------------------------------------------------------


func _test_no_shipped_item_names_a_missing_weapon_field() -> void:
	for file_name: String in DirAccess.get_files_at(ITEM_DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		var item := load(ITEM_DIRECTORY + file_name) as ItemConfig
		if item == null:
			continue
		var unknown := WeaponModifierStack.unknown_keys(item)
		check(unknown.is_empty(), "%s names only real weapon fields (unknown: %s)"
			% [item.id, ", ".join(unknown)])


func _test_the_stack_sets_then_adds_then_scales() -> void:
	var twin := _item(&"twin")
	twin.weapon_add = {&"projectiles_per_shot": 1, &"spread_degrees": 10.0}
	var fan := _item(&"fan")
	fan.weapon_set = {&"projectiles_per_shot": 2, &"lateral_offset": 4.0}
	fan.weapon_scale = {&"spread_degrees": 2.0}

	var base := _blaster()
	var weapon := WeaponModifierStack.from_items([twin, fan]).apply(base)
	check(weapon != base, "a modified weapon is a new resource")
	check(base.projectiles_per_shot == 1, "and the shipped one is untouched")
	check(weapon.projectiles_per_shot == 3, "a set of two plus an add of one is three (%d)"
		% weapon.projectiles_per_shot)
	check_near(weapon.spread_degrees, 20.0, "an add of ten, doubled, is twenty degrees")
	check_near(weapon.lateral_offset, 4.0, "the set lateral offset arrives")
	check(weapon.projectile == base.projectile, "the projectile is the same resource, not a copy")


func _test_the_stack_leaves_the_weapon_alone_when_nothing_changes_it() -> void:
	var plain := _item(&"plain")
	plain.fire_rate_scale = 1.2
	var base := _blaster()
	check(
		WeaponModifierStack.from_items([plain]).apply(base) == base,
		"a build with no weapon modifiers fires the shipped weapon itself",
	)
	check(WeaponModifierStack.from_items([plain]).is_empty(), "and its stack is empty")


func _test_pickup_order_does_not_matter() -> void:
	var one := _item(&"one")
	one.weapon_set = {&"projectiles_per_shot": 2}
	var two := _item(&"two")
	two.weapon_add = {&"projectiles_per_shot": 1}
	two.weapon_scale = {&"muzzle_offset": 1.5}
	var three := _item(&"three")
	three.weapon_scale = {&"muzzle_offset": 2.0}

	var forward := WeaponModifierStack.from_items([one, two, three]).apply(_blaster())
	var backward := WeaponModifierStack.from_items([three, two, one]).apply(_blaster())
	check(
		forward.projectiles_per_shot == backward.projectiles_per_shot
			and is_equal_approx(forward.muzzle_offset, backward.muzzle_offset),
		"the same items in either order build the same weapon",
	)


func _test_refused_and_misspelt_fields_are_reported() -> void:
	var item := _item(&"wrong")
	item.weapon_scale = {&"shots_per_second": 2.0}
	item.weapon_add = {&"projectiles_per_shoot": 1}
	var unknown := WeaponModifierStack.unknown_keys(item)
	check("shots_per_second" in unknown, "the fire rate is refused as a weapon field")
	check("projectiles_per_shoot" in unknown, "a misspelt field is reported")
	check(
		not WeaponModifierStack.refusal(&"shots_per_second").is_empty(),
		"and the refusal says why",
	)
	check(WeaponModifierStack.refusal(&"projectiles_per_shot").is_empty(), "a real field is not refused")

	# Refused means refused at runtime too, not only reported: the weapon keeps its fire rate.
	var weapon := WeaponModifierStack.from_items([item]).apply(_blaster())
	check_near(weapon.shots_per_second, _blaster().shots_per_second, "the fire rate is not scaled")


func _test_weapon_items_are_classified() -> void:
	var more := _item(&"more")
	more.weapon_add = {&"projectiles_per_shot": 1, &"spread_degrees": 12.0}
	check(more.has_upside(), "an item adding a projectile is worth something")
	check(not more.is_stat_only(), "and changes behaviour, not only numbers")

	var shaky := _item(&"shaky")
	shaky.weapon_add = {&"spread_degrees": 20.0}
	check(not shaky.has_upside(), "an item that only adds spread is a pure cost")

	var bigger := _item(&"bigger")
	bigger.weapon_scale = {&"charge_max_scale": 1.5}
	check(bigger.has_upside(), "a scaled-up charge is worth something")
	check(bigger.is_stat_only(), "and is a number, for the reason a projectile scale is")


# --- The pattern ---------------------------------------------------------------------------


func _test_parallel_shots_straddle_the_aim_line() -> void:
	var arena := _make_arena()
	var weapon := _weapon_in(arena, func(config: WeaponConfig) -> void:
		config.projectiles_per_shot = 2
		config.lateral_offset = 8.0
	)
	await advance_physics(2)

	weapon.try_fire(Vector2.ZERO, Vector2.RIGHT)
	var shots := _live_projectiles(arena)
	check(shots.size() == 2, "two projectiles per shot leave together")
	if shots.size() == 2:
		var ys := [shots[0].global_position.y, shots[1].global_position.y]
		ys.sort()
		check_near(ys[0], -4.0, "one leaves four pixels to one side of the aim line")
		check_near(ys[1], 4.0, "and the other four to the other")
		check(
			shots[0].rotation == shots[1].rotation,
			"and with no spread they fly parallel rather than fanning",
		)
	await _teardown(arena)


func _test_rear_shots_alternate() -> void:
	var arena := _make_arena()
	var weapon := _weapon_in(arena, func(config: WeaponConfig) -> void:
		config.alternate_rear = true
	)
	await advance_physics(2)

	var directions: Array[float] = []
	for _shot: int in 4:
		weapon.step(10.0)
		weapon.try_fire(Vector2.ZERO, Vector2.RIGHT)
		var shots := _live_projectiles(arena)
		directions.append(signf(Vector2.RIGHT.rotated(shots[-1].rotation).x))
	var alternating: Array[float] = [1.0, -1.0, 1.0, -1.0]
	check(directions == alternating, "shots alternate forwards and backwards (%s)" % [directions])
	check(
		weapon.get_last_request() == Vector2.RIGHT,
		"and the weapon remembers the direction it was asked for, not the one it turned to",
	)
	await _teardown(arena)


func _test_a_charge_fires_on_release_harder_the_longer_it_was_held() -> void:
	var arena := _make_arena()
	var weapon := _weapon_in(arena, func(config: WeaponConfig) -> void:
		config.fire_mode = WeaponConfig.FireMode.CHARGE
		config.charge_seconds = 1.0
		config.charge_max_scale = 4.0
		config.charge_radius_scale = 2.0
	)
	await advance_physics(2)
	var base_damage := weapon.config.projectile.damage
	var base_radius := weapon.config.projectile.radius

	for pair: Array in [[0.0, 1.0, 1.0], [0.5, 2.5, 1.5], [1.0, 4.0, 2.0], [3.0, 4.0, 2.0]]:
		var held: float = pair[0]
		weapon.step(10.0)
		check(not weapon.hold_trigger(Vector2.ZERO, Vector2.RIGHT), "holding a charge fires nothing")
		weapon.step(held)
		var before := _live_projectiles(arena).size()
		check(weapon.release_trigger(Vector2.ZERO, Vector2.RIGHT), "releasing it fires")
		var shots := _live_projectiles(arena)
		check(shots.size() == before + 1, "one projectile per release")
		if shots.size() == before + 1:
			var shot := shots[-1]
			check_near(shot.config.damage, base_damage * float(pair[1]),
				"held %.1fs: %.1fx damage" % [held, pair[1]])
			check_near(shot.config.radius, base_radius * float(pair[2]),
				"held %.1fs: %.1fx radius" % [held, pair[2]])
		check(not weapon.is_charging(), "and the charge is spent")
	await _teardown(arena)


func _test_a_release_during_the_cooldown_fires_when_it_ends() -> void:
	var arena := _make_arena()
	var weapon := _weapon_in(arena, func(config: WeaponConfig) -> void:
		config.fire_mode = WeaponConfig.FireMode.CHARGE
		config.shots_per_second = 2.0
	)
	await advance_physics(2)

	weapon.step(10.0)
	weapon.hold_trigger(Vector2.ZERO, Vector2.RIGHT)
	weapon.release_trigger(Vector2.ZERO, Vector2.RIGHT)
	weapon.hold_trigger(Vector2.ZERO, Vector2.RIGHT)
	weapon.step(0.1)
	check(
		not weapon.release_trigger(Vector2.ZERO, Vector2.RIGHT),
		"a second release inside the half-second cooldown does not fire yet",
	)
	check(weapon.is_charging(), "and keeps its charge")
	weapon.step(0.5)
	check(weapon.release_trigger(Vector2.ZERO, Vector2.RIGHT), "it fires once the cooldown ends")
	check(_live_projectiles(arena).size() == 2, "two releases, two shots, none lost")
	await _teardown(arena)


## The whole path from the fire button, through an item that switches the trigger to charging, to
## a harder shot. Nothing is fired while the button is down; the shot leaves on the frame it comes
## up.
func _test_the_robot_charges_from_the_fire_button() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var charger := _item(&"charger")
	charger.weapon_set = {
		&"fire_mode": WeaponConfig.FireMode.CHARGE,
		&"charge_seconds": 0.5,
		&"charge_max_scale": 3.0,
	}
	player.get_item_inventory().add(charger)
	check(
		player.get_weapon_controller().config.fire_mode == WeaponConfig.FireMode.CHARGE,
		"the item switches the robot's trigger to charging",
	)

	var spawned := _count_spawns(arena)
	Input.action_press(&"shoot_right")
	await advance_physics(40)
	check(spawned[0] == 0, "holding fire charges without shooting")
	Input.action_release(&"shoot_right")
	await advance_physics(2)
	check(spawned[0] == 1, "releasing it fires one shot")
	var shots := _live_projectiles(arena)
	if shots.size() == 1:
		check_near(
			shots[0].config.damage,
			player.get_weapon_controller().config.projectile.damage * 3.0,
			"at full charge after two-thirds of a second held",
		)
	await _teardown(arena)


## Blocking I/O forbids firing on the move, and a charge carried through a move and let go the
## moment the robot stops would be exactly that shot, one frame late. So moving drops the charge.
func _test_blocking_io_forbids_charging_on_the_move() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var charger := _item(&"charger")
	charger.weapon_set = {&"fire_mode": WeaponConfig.FireMode.CHARGE}
	var blocking := _item(&"blocking")
	blocking.fire_requires_stillness = true
	player.get_item_inventory().add(charger)
	player.get_item_inventory().add(blocking)

	var spawned := _count_spawns(arena)
	Input.action_press(&"shoot_right")
	await advance_physics(20)
	Input.action_press(&"move_down")
	await advance_physics(10)
	Input.action_release(&"shoot_right")
	await advance_physics(5)
	Input.action_release(&"move_down")
	await advance_physics(40)

	check(spawned[0] == 0, "a charge built, carried through a move and released fires nothing")
	check(not player.get_weapon_controller().is_charging(), "because moving dropped it")
	Input.action_release(&"move_down")
	await _teardown(arena)


func _test_the_drone_fires_the_same_pattern() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var drone := ItemConfig.new()
	drone.id = &"test_drone"
	drone.drone_count = 1
	var twin := _item(&"twin")
	twin.weapon_add = {&"projectiles_per_shot": 1}
	twin.weapon_set = {&"alternate_rear": true}
	player.get_item_inventory().add(drone)
	player.get_item_inventory().add(twin)
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var weapon := player.get_weapon_controller()
	weapon.step(10.0)
	weapon.try_fire(player.global_position, Vector2.RIGHT)
	await advance_physics(1)
	check(spawned[0] == 4, "the robot's two and the drone's two leave on one pull (%d)" % spawned[0])

	# The second pull is the rear shot for both. Had the drone been handed the direction the robot
	# turned to, it would have turned it round again and fired forwards. The drone's weapon keeps its
	# own cooldown, so the pull waits for it the way held fire would.
	await advance_physics(20)
	var facing: Array[float] = []
	weapon.step(10.0)
	weapon.try_fire(player.global_position, Vector2.RIGHT)
	check(spawned[0] == 8, "the second pull fires all four again (%d in all)" % spawned[0])
	for shot: Projectile in _live_projectiles(arena).slice(-4):
		facing.append(signf(Vector2.RIGHT.rotated(shot.rotation).x))
	var backwards: Array[float] = [-1.0, -1.0, -1.0, -1.0]
	check(facing == backwards, "and on the rear shot all four face backwards (%s)" % [facing])
	await _teardown(arena)


func _test_an_emptied_build_restores_the_shipped_weapon() -> void:
	var arena := _make_arena()
	var player := _add_player(arena)
	await advance_physics(2)

	var shipped := player.get_weapon_controller().config
	var twin := _item(&"twin")
	twin.weapon_add = {&"projectiles_per_shot": 1}
	player.get_item_inventory().add(twin)
	check(player.get_weapon_controller().config != shipped, "an item replaces the weapon with a copy")

	player.restore_build([] as Array[ItemConfig], 3.0)
	check(
		player.get_weapon_controller().config == shipped,
		"and a build without it goes back to the shipped weapon, not a copy of the copy",
	)
	await _teardown(arena)


# --- Helpers -------------------------------------------------------------------------------


func _item(id: StringName) -> ItemConfig:
	var item := ItemConfig.new()
	item.id = id
	item.display_name = String(id)
	return item


func _blaster() -> WeaponConfig:
	return load(BLASTER_PATH) as WeaponConfig


func _make_arena() -> Node2D:
	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)
	return arena


func _teardown(arena: Node2D) -> void:
	Input.action_release(&"shoot_right")
	arena.queue_free()
	await advance_physics(2)


## A player weapon of its own in the arena, built from the Rivet Blaster with `change` applied.
func _weapon_in(arena: Node2D, change: Callable) -> WeaponController:
	var config := _blaster().duplicate() as WeaponConfig
	change.call(config)
	var weapon := WeaponController.new()
	arena.add_child(weapon)
	weapon.setup(config, Teams.Id.PLAYER)
	return weapon


func _add_player(arena: Node2D) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(-400.0, -400.0)
	arena.add_child(player)
	return player


func _count_spawns(arena: Node2D) -> Array:
	var total := [0]
	arena.get_node("Projectiles").child_entered_tree.connect(
		func(_child: Node) -> void: total[0] += 1
	)
	return total


func _live_projectiles(arena: Node2D) -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child: Node in arena.get_node("Projectiles").get_children():
		if child is Projectile and not (child as Projectile).is_spent():
			found.append(child as Projectile)
	return found

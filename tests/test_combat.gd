extends TestCase
## Checks for the combat data model and the components built on it.
##
## HealthComponent, WeaponController, and ProjectileConfig are what every item in
## milestones 4 and 5 composes over, so a silent regression here would surface as
## "items feel wrong" rather than as an error.
##
## Two checks carry more weight than the rest. test_spawn_copy_is_independent guards the
## most dangerous available mistake — sharing one config between projectiles, which
## would let the first shot spend a weapon's bounces permanently. The integration
## checks fire real projectiles through real physics, because pierce, bounce, and
## friendly fire are exactly the behaviours that unit-test cleanly and still break in
## the game.

const RIVET_PATH := "res://data/projectiles/rivet.tres"
const BLASTER_PATH := "res://data/weapons/rivet_blaster.tres"
const TICKET_BOT_CONFIG_PATH := "res://data/enemies/ticket_bot.tres"
const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")


func run() -> void:
	_test_rivet_matches_spec()
	_test_blaster_matches_spec()
	_test_enemy_config_loads()
	_test_spawn_copy_is_independent()
	_test_team_layers_are_mutually_exclusive()
	_test_health_basics()
	_test_health_invulnerability()
	_test_health_dies_once()
	_test_health_find_on()
	_test_weapon_cooldown_and_multiplier()
	_test_spread_pattern_is_centred()
	await _test_weapon_spawns_projectile()
	await _test_projectile_damages_enemy()
	await _test_enemy_shot_cannot_hurt_an_enemy()
	await _test_projectile_stops_at_a_wall()
	await _test_projectile_bounces_when_configured()
	await _test_projectile_pierces_when_configured()
	await _test_room_combat_reports_cleared_once()


# --- Data ---------------------------------------------------------------------


## Spec section 7 gives exact Rivet Blaster numbers. These are the contract with the
## design document, so a stray inspector edit cannot silently rebalance the game.
func _test_rivet_matches_spec() -> void:
	var rivet := load(RIVET_PATH) as ProjectileConfig
	if not require(rivet, "rivet.tres loads as a ProjectileConfig"):
		return
	check_near(rivet.damage, 1.0, "rivet damage is 1")
	check_near(rivet.speed, 420.0, "rivet speed is 420 px/s")
	check_near(rivet.lifetime, 1.4, "rivet lifetime is 1.4s")
	check(rivet.pierce_count == 0, "rivet pierce is 0")
	check(rivet.bounce_count == 0, "rivet bounce is 0")
	check(rivet.texture != null, "rivet has a texture assigned")


func _test_blaster_matches_spec() -> void:
	var blaster := load(BLASTER_PATH) as WeaponConfig
	if not require(blaster, "rivet_blaster.tres loads as a WeaponConfig"):
		return
	check_near(blaster.shots_per_second, 4.0, "blaster fires 4 shots per second")
	check_near(blaster.get_fire_interval(), 0.25, "blaster fire interval is 0.25s")
	check_near(blaster.spread_degrees, 0.0, "blaster spread is 0 degrees")
	check(blaster.projectile != null, "blaster has a projectile assigned")


func _test_enemy_config_loads() -> void:
	var bot := load(TICKET_BOT_CONFIG_PATH) as EnemyConfig
	if not require(bot, "ticket_bot.tres loads as an EnemyConfig"):
		return
	check(bot.weapon != null, "ticket bot has a weapon assigned")
	check(bot.max_health > 0.0, "ticket bot has positive health")
	check(bot.preferred_range > 0.0, "ticket bot has a preferred range")


func _test_spawn_copy_is_independent() -> void:
	var base := load(RIVET_PATH) as ProjectileConfig
	if not require(base, "rivet.tres loads for the copy check"):
		return
	base.bounce_count = 3

	var first := base.spawn_copy()
	var second := base.spawn_copy()
	first.bounce_count -= 1
	first.damage = 99.0

	check(first != second, "spawn_copy returns a distinct instance each call")
	check(second.bounce_count == 3, "spending one copy's bounces leaves the other intact")
	check(base.bounce_count == 3, "spending a copy's bounces leaves the source intact")
	check_near(base.damage, 1.0, "editing a copy's damage leaves the source intact")

	# Resource loads are cached process-wide; do not leak state into later checks.
	base.bounce_count = 0


func _test_team_layers_are_mutually_exclusive() -> void:
	check(
		Teams.projectile_layer(Teams.Id.PLAYER) != Teams.projectile_layer(Teams.Id.ENEMY),
		"the two teams' projectiles use different layers",
	)
	check(
		Teams.opposing_body_layer(Teams.Id.PLAYER) == Teams.LAYER_ENEMY,
		"player projectiles target enemy bodies",
	)
	check(
		Teams.opposing_body_layer(Teams.Id.ENEMY) == Teams.LAYER_PLAYER,
		"enemy projectiles target the player's body",
	)
	check(
		Teams.opposing_body_layer(Teams.Id.PLAYER) & Teams.LAYER_PLAYER == 0,
		"player projectiles cannot collide with the player",
	)
	check(
		Teams.opposing_body_layer(Teams.Id.ENEMY) & Teams.LAYER_ENEMY == 0,
		"enemy projectiles cannot collide with other enemies",
	)


# --- Components ---------------------------------------------------------------


func _test_health_basics() -> void:
	var health := HealthComponent.new()
	health.configure(6.0, 0.0)

	check_near(health.current, 6.0, "configure refills to the new maximum")
	check(health.is_alive(), "a configured component is alive")
	check(health.apply_damage(DamageInfo.new(1.0)), "damage lands")
	check_near(health.current, 5.0, "one point of damage removes one point")

	health.heal(10.0)
	check_near(health.current, 6.0, "healing cannot exceed the maximum")
	check(not health.apply_damage(DamageInfo.new(0.0)), "zero damage is declined")
	check_near(health.get_ratio(), 1.0, "ratio is 1.0 at full health")
	health.free()


func _test_health_invulnerability() -> void:
	var health := HealthComponent.new()
	health.configure(6.0, 0.8)

	check(health.apply_damage(DamageInfo.new(1.0)), "the first hit lands")
	check(health.is_invulnerable(), "landing a hit opens the invulnerability window")
	check(
		not health.apply_damage(DamageInfo.new(1.0)),
		"a second hit is declined while invulnerable",
	)
	check_near(health.current, 5.0, "the declined hit removed nothing")

	for _frame: int in ceili(0.8 * 60.0) + 1:
		health.step(1.0 / 60.0)
	check(not health.is_invulnerable(), "invulnerability expires")
	check(health.apply_damage(DamageInfo.new(1.0)), "damage lands again once it expires")
	check_near(health.current, 4.0, "the landed hit removed one point")
	health.free()


func _test_health_dies_once() -> void:
	var health := HealthComponent.new()
	health.configure(2.0, 0.0)

	var deaths := [0]
	health.died.connect(func() -> void: deaths[0] += 1)

	health.apply_damage(DamageInfo.new(5.0))
	check_near(health.current, 0.0, "overkill clamps to zero rather than going negative")
	check(not health.is_alive(), "the component reports dead")
	check(deaths[0] == 1, "died is emitted once")

	check(not health.apply_damage(DamageInfo.new(1.0)), "a corpse declines further damage")
	check(deaths[0] == 1, "died is not emitted a second time")

	health.heal(1.0)
	check_near(health.current, 0.0, "a corpse cannot be healed")
	health.free()


func _test_health_find_on() -> void:
	var body := Node2D.new()
	check(HealthComponent.find_on(body) == null, "find_on returns null for an indestructible body")
	check(HealthComponent.find_on(null) == null, "find_on tolerates null")

	var health := HealthComponent.new()
	# Deliberately not named "Health": lookup must be by type, or renaming a node
	# would silently make its owner invulnerable.
	health.name = "SomethingElse"
	body.add_child(health)
	check(HealthComponent.find_on(body) == health, "find_on finds the component by type")
	body.free()


func _test_weapon_cooldown_and_multiplier() -> void:
	var config := load(BLASTER_PATH) as WeaponConfig
	if not require(config, "rivet_blaster.tres loads for the cooldown check"):
		return

	var weapon := WeaponController.new()
	weapon.setup(config, Teams.Id.PLAYER)
	check(weapon.can_fire(), "a fresh weapon can fire")
	check_near(weapon.get_fire_interval(), 0.25, "fire interval matches the config")

	# Cooling Fan is +20% fire rate, which must shorten the interval, not lengthen it.
	weapon.fire_rate_multiplier = 1.2
	check_near(weapon.get_fire_interval(), 0.25 / 1.2, "a fire rate multiplier shortens the interval")
	check(
		weapon.get_fire_interval() < config.get_fire_interval(),
		"+20% fire rate fires faster than base",
	)

	# Must not divide by zero and freeze the weapon forever.
	weapon.fire_rate_multiplier = 0.0
	check(weapon.get_fire_interval() > 0.0, "a zero fire rate multiplier is clamped")
	weapon.free()


## Asserted through the arc's symmetry: the outer projectiles of a spread must sit
## equal and opposite around the aim direction.
func _test_spread_pattern_is_centred() -> void:
	var config := WeaponConfig.new()
	config.projectiles_per_shot = 3
	config.spread_degrees = 30.0

	var weapon := WeaponController.new()
	weapon.setup(config, Teams.Id.PLAYER)

	var aim := Vector2.RIGHT
	check_near(rad_to_deg(weapon._pattern_direction(aim, 0).angle()), -15.0, "first shot at -15 degrees")
	check_near(rad_to_deg(weapon._pattern_direction(aim, 1).angle()), 0.0, "middle shot follows the aim")
	check_near(rad_to_deg(weapon._pattern_direction(aim, 2).angle()), 15.0, "last shot at +15 degrees")

	config.spread_degrees = 0.0
	check(weapon._pattern_direction(aim, 0) == aim, "zero spread leaves the aim untouched")
	weapon.free()


# --- Integration: real projectiles through real physics ------------------------


func _test_weapon_spawns_projectile() -> void:
	var arena := _make_arena()
	var config := load(BLASTER_PATH) as WeaponConfig
	if not require(config, "rivet_blaster.tres loads for the spawn check"):
		arena.queue_free()
		return

	var weapon := WeaponController.new()
	arena.add_child(weapon)
	weapon.setup(config, Teams.Id.PLAYER)

	check(weapon.try_fire(Vector2.ZERO, Vector2.RIGHT), "try_fire succeeds when off cooldown")
	check(not weapon.try_fire(Vector2.ZERO, Vector2.RIGHT), "a second shot is refused on cooldown")
	check(weapon.get_shots_fired() == 1, "only the successful shot was counted")

	var container := arena.get_node("Projectiles")
	check(container.get_child_count() == 1, "exactly one projectile was spawned")

	var projectile := container.get_child(0) as Projectile
	if require(projectile, "the spawned node is a Projectile"):
		check(
			projectile.collision_layer == Teams.projectile_layer(Teams.Id.PLAYER),
			"the projectile is on the player projectile layer",
		)
		check(
			projectile.collision_mask == Teams.LAYER_ENEMY,
			"the projectile only looks for enemy bodies",
		)
		check_near(projectile.config.speed, 420.0, "the projectile took the config's speed")

	# The weapon's own cooldown must expire on its own clock.
	weapon.step(0.25)
	check(weapon.can_fire(), "the weapon can fire again after its interval")
	await _teardown(arena)


func _test_projectile_damages_enemy() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(100.0, 0.0))
	await advance_physics(2)

	var health := bot.get_health_component()
	var starting := health.current

	var damaged := [0]
	var handler := func(_e: Node, _i: DamageInfo, _r: float) -> void: damaged[0] += 1
	EventBus.enemy_damaged.connect(handler)

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _rivet_variant())
	await advance_physics(30)

	check_near(health.current, starting - 1.0, "a rivet removes one integrity from the bot")
	check(damaged[0] == 1, "enemy_damaged was emitted exactly once")
	check(
		arena.get_node("Projectiles").get_child_count() == 0,
		"a non-piercing projectile is consumed by the hit",
	)

	EventBus.enemy_damaged.disconnect(handler)
	await _teardown(arena)


## Friendly fire must be impossible by construction. An enemy-team projectile fired
## straight through an enemy must do nothing at all.
func _test_enemy_shot_cannot_hurt_an_enemy() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(100.0, 0.0))
	await advance_physics(2)

	var health := bot.get_health_component()
	var starting := health.current

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _rivet_variant(), Teams.Id.ENEMY)
	await advance_physics(30)

	check_near(health.current, starting, "an enemy projectile does not damage an enemy")
	await _teardown(arena)


func _test_projectile_stops_at_a_wall() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(100.0, -40.0), Vector2i(16, 80))
	await advance_physics(2)

	var projectile := _fire_at(arena, Vector2.ZERO, Vector2.RIGHT, _rivet_variant())
	await advance_physics(30)

	check(not is_instance_valid(projectile), "a projectile is consumed by a wall")
	await _teardown(arena)


func _test_projectile_bounces_when_configured() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(100.0, -40.0), Vector2i(16, 80))
	await advance_physics(2)

	# Ricochet Driver's entire implementation: raise bounce_count by one.
	var config := _rivet_variant()
	config.bounce_count = 1

	var projectile := _fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(35)

	if require(
		projectile if is_instance_valid(projectile) else null,
		"a bouncing projectile survives the wall",
	):
		check(
			projectile.global_position.x < 0.0,
			"the bounced projectile travelled back past its origin",
		)
	await _teardown(arena)


func _test_projectile_pierces_when_configured() -> void:
	var arena := _make_arena()
	var near_bot := _add_bot(arena, Vector2(60.0, 0.0))
	var far_bot := _add_bot(arena, Vector2(130.0, 0.0))
	await advance_physics(2)

	var config := _rivet_variant()
	config.pierce_count = 1

	_fire_at(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(35)

	check_near(
		near_bot.get_health_component().current, 2.0, "the piercing shot damaged the near bot"
	)
	check_near(
		far_bot.get_health_component().current, 2.0, "the piercing shot carried on to the far bot"
	)
	await _teardown(arena)


func _test_room_combat_reports_cleared_once() -> void:
	var arena := _make_arena()
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	arena.add_child(enemies)

	var healths: Array[HealthComponent] = []
	for index: int in 2:
		var stand_in := Node2D.new()
		var health := HealthComponent.new()
		health.max_health = 1.0
		stand_in.add_child(health)
		enemies.add_child(stand_in)
		healths.append(health)

	var combat := RoomCombat.new()
	arena.add_child(combat)
	combat.begin(enemies)

	var local := [0]
	var global := [0]
	combat.cleared.connect(func() -> void: local[0] += 1)
	var handler := func() -> void: global[0] += 1
	EventBus.room_cleared.connect(handler)

	check(combat.get_initial_count() == 2, "both enemies were registered")
	check(not combat.is_cleared(), "the room is not clear while enemies live")

	healths[0].apply_damage(DamageInfo.new(1.0))
	check(not combat.is_cleared(), "the room is not clear after only one death")
	check(combat.get_alive_count() == 1, "the survivor is still counted")

	healths[1].apply_damage(DamageInfo.new(1.0))
	check(combat.is_cleared(), "the room reports clear once the last enemy dies")
	check(local[0] == 1, "the local cleared signal fired once")
	check(global[0] == 1, "room_cleared reached the EventBus once")

	EventBus.room_cleared.disconnect(handler)
	await _teardown(arena)


# --- Fixtures -----------------------------------------------------------------


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


func _add_bot(arena: Node2D, at: Vector2) -> TicketBot:
	var bot: TicketBot = TICKET_BOT_SCENE.instantiate()
	bot.position = at
	arena.add_child(bot)
	return bot


func _add_wall(arena: Node2D, at: Vector2, size: Vector2i) -> void:
	var wall: WallBlock = WALL_BLOCK_SCENE.instantiate()
	wall.size = size
	wall.position = at
	arena.add_child(wall)


## A standalone rivet config so a check can mutate pierce/bounce without touching the
## cached resource that other checks assert against.
func _rivet_variant() -> ProjectileConfig:
	var source := load(RIVET_PATH) as ProjectileConfig
	return source.spawn_copy()


func _fire_at(
	arena: Node2D,
	origin: Vector2,
	direction: Vector2,
	projectile_config: ProjectileConfig,
	team := Teams.Id.PLAYER,
) -> Projectile:
	var weapon_config := WeaponConfig.new()
	weapon_config.projectile = projectile_config
	weapon_config.muzzle_offset = 0.0

	var shooter := Node2D.new()
	arena.add_child(shooter)
	return ProjectileFactory.spawn(shooter, weapon_config, direction, origin, team)

extends TestCase
## Checks for spec section 15's four enemies.
##
## Each enemy exists to pose one movement problem, so each check here asks whether that
## problem is actually being posed — not whether the script ran. The Pop Up Drone must
## actually appear somewhere else, and not on top of the player or inside a wall. The
## Memory Leech must actually stop before it charges, and must not steer once it has
## committed. The Firewall Node's beams must actually stop at walls, because a hazard that
## sweeps through geometry is one the player cannot reason about.
##
## Enemies are driven with a lightweight stand-in for the player — a Node2D in the player
## group with a HealthComponent — rather than the real robot. Everything an enemy asks of
## the player is "where is it" and "hurt it", and a stand-in answers both without dragging
## a camera and an input component into every check.

const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const POP_UP_DRONE_SCENE := preload("res://scenes/enemies/pop_up_drone.tscn")
const MEMORY_LEECH_SCENE := preload("res://scenes/enemies/memory_leech.tscn")
const FIREWALL_NODE_SCENE := preload("res://scenes/enemies/firewall_node.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

const DRONE_CONFIG := "res://data/enemies/pop_up_drone.tres"
const LEECH_CONFIG := "res://data/enemies/memory_leech.tres"
const FIREWALL_CONFIG := "res://data/enemies/firewall_node.tres"


func run() -> void:
	_test_configs_load_as_their_own_types()
	_test_the_roster_is_four_distinct_problems()

	await _test_every_enemy_shares_the_lifecycle()
	await _test_ticket_bot_keeps_its_range()
	await _test_drone_relocates_away_from_the_player()
	await _test_drone_stays_inside_its_room()
	await _test_drone_fires_a_spread()
	await _test_leech_stops_before_it_charges()
	await _test_leech_does_not_steer_mid_charge()
	await _test_leech_deals_contact_damage()
	await _test_firewall_node_holds_still_and_sweeps()
	await _test_firewall_beams_stop_at_walls()
	await _test_knockback_decays_instead_of_growing()
	await _test_knockback_stays_out_of_the_steering_velocity()
	await _test_full_resistance_means_immovable()


# --- Data ---------------------------------------------------------------------


func _test_configs_load_as_their_own_types() -> void:
	var drone := load(DRONE_CONFIG) as PopUpDroneConfig
	if require(drone, "pop_up_drone.tres loads as a PopUpDroneConfig"):
		check(drone.weapon != null, "the drone has a weapon")
		check(
			drone.weapon.projectiles_per_shot == 3,
			"spec section 15's three shot spread is the weapon's pattern, not code",
		)
		check(drone.weapon.spread_degrees > 0.0, "the spread is actually spread")

	var leech := load(LEECH_CONFIG) as MemoryLeechConfig
	if require(leech, "memory_leech.tres loads as a MemoryLeechConfig"):
		check(leech.contact_damage > 0.0, "the leech deals contact damage")
		check(leech.charge_speed > leech.move_speed, "its charge outruns its chase")
		check(leech.weapon == null, "it has no weapon — contact is its whole attack")

	var firewall := load(FIREWALL_CONFIG) as FirewallNodeConfig
	if require(firewall, "firewall_node.tres loads as a FirewallNodeConfig"):
		check(firewall.beam_count >= 2, "the node projects at least two beams")
		check(is_zero_approx(firewall.move_speed), "the node never moves")
		check(firewall.max_health > 4.0, "it is durable, being the one that cannot flee")


## Spec section 15 asks for four enemies that each create a *different* movement problem.
## Four enemies with the same statistics would technically satisfy the count.
func _test_the_roster_is_four_distinct_problems() -> void:
	var configs: Array[EnemyConfig] = [
		load("res://data/enemies/ticket_bot.tres") as EnemyConfig,
		load(DRONE_CONFIG) as EnemyConfig,
		load(LEECH_CONFIG) as EnemyConfig,
		load(FIREWALL_CONFIG) as EnemyConfig,
	]

	var names: Dictionary[String, bool] = {}
	var healths: Dictionary[float, bool] = {}
	for config: EnemyConfig in configs:
		if config == null:
			fail("an enemy config failed to load")
			return
		names[config.display_name] = true
		healths[config.max_health] = true

	check(names.size() == 4, "all four enemies are named distinctly")
	check(healths.size() == 4, "all four have different durability")
	check(
		configs[2].contact_damage > 0.0 and configs[0].contact_damage <= 0.0,
		"only the melee enemy deals contact damage",
	)


# --- Shared lifecycle ---------------------------------------------------------


## The base class exists so no enemy can quietly stop doing these. An enemy that failed to
## announce its own death would leave rooms permanently uncleared, and the only symptom
## would be a door that never opens.
func _test_every_enemy_shares_the_lifecycle() -> void:
	for scene: PackedScene in [
		TICKET_BOT_SCENE, POP_UP_DRONE_SCENE, MEMORY_LEECH_SCENE, FIREWALL_NODE_SCENE
	]:
		var arena := _make_arena()
		var enemy := _add_enemy(arena, scene, Vector2(60.0, 0.0))
		await advance_physics(2)

		var label := enemy.config.display_name
		check(enemy.is_in_group(Teams.GROUP_ENEMY), "%s is in the enemy group" % label)
		check(
			enemy.collision_layer == Teams.body_layer(Teams.Id.ENEMY),
			"%s is on the enemy body layer" % label,
		)
		check(enemy.get_health_component() != null, "%s has a health component" % label)
		check_near(
			enemy.get_health_component().max_health,
			enemy.config.max_health,
			"%s took its durability from its config" % label,
		)

		var killed := [0]
		var handler := func(_e: Node, _p: Vector2) -> void: killed[0] += 1
		EventBus.enemy_killed.connect(handler)
		enemy.get_health_component().apply_damage(DamageInfo.new(999.0))
		await advance_physics(2)
		check(killed[0] == 1, "%s announces its own death exactly once" % label)
		EventBus.enemy_killed.disconnect(handler)

		await _teardown(arena)


func _test_ticket_bot_keeps_its_range() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	# Well beyond its preferred range, so it must close.
	var bot := _add_enemy(arena, TICKET_BOT_SCENE, Vector2(320.0, 0.0)) as TicketBot
	await advance_physics(2)

	var starting := bot.global_position.distance_to(target.global_position)
	await advance_physics(90)
	var settled := bot.global_position.distance_to(target.global_position)

	check(settled < starting, "the bot closes on a distant player")
	check(
		settled > bot.config.preferred_range - bot.config.range_tolerance * 2.0,
		"but stops short rather than walking into the player's face",
	)
	await _teardown(arena)


# --- Pop Up Drone -------------------------------------------------------------


func _test_drone_relocates_away_from_the_player() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var drone := _add_enemy(
		arena, POP_UP_DRONE_SCENE, Vector2(140.0, 0.0), _quick_drone()
	) as PopUpDrone
	await advance_physics(2)

	var seen: Array[Vector2] = [drone.global_position]
	var tuning := drone.config as PopUpDroneConfig
	var too_close := 0

	for _cycle: int in 8:
		await advance_physics(24)
		var here := drone.global_position
		if here.distance_to(target.global_position) < tuning.min_teleport_distance - 1.0:
			too_close += 1
		if here != seen[seen.size() - 1]:
			seen.append(here)

	check(seen.size() >= 4, "the drone actually relocates, repeatedly")
	check(too_close == 0, "and never materialises inside the player's guard")
	check(
		is_zero_approx(drone.velocity.length()),
		"it teleports rather than flying — it is never in motion",
	)
	await _teardown(arena)


## Placement is a physics query against real geometry, so this is checked in a real room
## rather than against the template's obstacle list.
func _test_drone_stays_inside_its_room() -> void:
	var arena := _make_arena()
	var room := _add_room(arena)
	if room == null:
		await _teardown(arena)
		return

	_add_target(arena, room.get_interior_centre())
	var drone: PopUpDrone = POP_UP_DRONE_SCENE.instantiate()
	drone.config = _quick_drone()
	drone.position = Vector2(40.0, 40.0)
	room.get_node("%Enemies").add_child(drone)
	await advance_physics(2)

	var interior := room.get_interior_rect()
	var outside := 0
	var inside_geometry := 0

	for _cycle: int in 10:
		await advance_physics(24)
		if not interior.has_point(drone.global_position):
			outside += 1
		if _is_solid_at(drone.global_position):
			inside_geometry += 1

	check(outside == 0, "the drone never appears outside the room")
	check(inside_geometry == 0, "and never appears inside a wall or an obstacle")
	await _teardown(arena)


func _test_drone_fires_a_spread() -> void:
	var arena := _make_arena()
	_add_target(arena, Vector2.ZERO)
	var drone := _add_enemy(
		arena, POP_UP_DRONE_SCENE, Vector2(140.0, 0.0), _quick_drone()
	) as PopUpDrone
	await advance_physics(2)

	var container := arena.get_node("Projectiles")
	var spawned := [0]
	container.child_entered_tree.connect(func(_c: Node) -> void: spawned[0] += 1)

	await advance_physics(60)

	check(spawned[0] > 0, "the drone fires after it arrives")
	check(spawned[0] % 3 == 0, "and fires three at a time (got %d)" % spawned[0])
	await _teardown(arena)


# --- Memory Leech -------------------------------------------------------------


func _test_leech_stops_before_it_charges() -> void:
	var arena := _make_arena()
	_add_target(arena, Vector2.ZERO)
	var leech := _add_enemy(arena, MEMORY_LEECH_SCENE, Vector2(90.0, 0.0)) as MemoryLeech
	await advance_physics(4)

	check(
		leech.get_phase() == MemoryLeech.Phase.WINDING_UP,
		"the leech commits the moment the player is in range",
	)

	# The windup is the tell, and a tell you cannot see is not a tell.
	var moved_during_windup := 0.0
	var before := leech.global_position
	while leech.get_phase() == MemoryLeech.Phase.WINDING_UP:
		await advance_physics(1)
		moved_during_windup = maxf(moved_during_windup, before.distance_to(leech.global_position))

	check(moved_during_windup < 8.0, "it holds still while winding up")
	check(leech.get_phase() == MemoryLeech.Phase.CHARGING, "then charges")

	await advance_physics(10)
	var tuning := leech.config as MemoryLeechConfig
	check(
		leech.velocity.length() > tuning.move_speed,
		"and the charge is faster than its chase (got %.0f, chase is %.0f)" % [
			leech.velocity.length(), tuning.move_speed,
		],
	)
	await _teardown(arena)


## The charge is dodgeable precisely because it does not follow. A homing charge would be
## the same enemy with none of the interest.
func _test_leech_does_not_steer_mid_charge() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var leech := _add_enemy(arena, MEMORY_LEECH_SCENE, Vector2(90.0, 0.0)) as MemoryLeech
	await advance_physics(4)

	while leech.get_phase() == MemoryLeech.Phase.WINDING_UP:
		await advance_physics(1)

	# Sampled a few frames in, not on the first frame of the charge: the leech is still
	# at a standstill the instant the windup ends, and the direction of a zero vector is
	# not a heading.
	await advance_physics(5)
	var heading := leech.velocity.normalized()

	# Step out of the way, exactly as a player would.
	target.global_position = Vector2(90.0, 220.0)
	await advance_physics(8)

	check(
		leech.velocity.normalized().dot(heading) > 0.95,
		"the charge holds its original direction after the player moves",
	)
	await _teardown(arena)


func _test_leech_deals_contact_damage() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var health := HealthComponent.find_on(target)
	var starting := health.current

	_add_enemy(arena, MEMORY_LEECH_SCENE, Vector2(40.0, 0.0))
	await advance_physics(70)

	check(health.current < starting, "touching the leech costs integrity")

	# And it is a series of hits, not a drain: the interval must actually gate.
	var after_first := health.current
	await advance_physics(6)
	check_near(health.current, after_first, "contact damage is on a cooldown, not per frame")
	await _teardown(arena)


# --- Firewall Node ------------------------------------------------------------


func _test_firewall_node_holds_still_and_sweeps() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2(34.0, 0.0))
	var health := HealthComponent.find_on(target)
	# Settled before the node exists: a body added this frame is not in the physics space
	# until the next step, and a node that starts sweeping first would cast its rays into
	# an empty world. See the wall check below, which this caught.
	await advance_physics(2)
	var node := _add_enemy(arena, FIREWALL_NODE_SCENE, Vector2.ZERO, _fast_firewall()) as FirewallNode
	await advance_physics(2)

	var placed := node.global_position
	var first_angle := node.get_beam_angle()
	check(node.get_beam_count() == 3, "the node built its beams from config")

	await advance_physics(40)

	check(node.global_position.distance_to(placed) < 0.5, "the node does not move")
	check(not is_equal_approx(node.get_beam_angle(), first_angle), "the beams rotate")
	check(health.current < 3.0, "a player standing in the sweep is hit")

	await _teardown(arena)


## A beam that swept through a wall would deny space the player is actually standing
## safely in, which is the opposite of what this enemy is for.
func _test_firewall_beams_stop_at_walls() -> void:
	var arena := _make_arena()
	_add_wall(arena, Vector2(14.0, -40.0), Vector2i(10, 80))
	var target := _add_target(arena, Vector2(40.0, 0.0))
	var health := HealthComponent.find_on(target)
	# The wall must be in the physics space before anything casts a ray at it. Without
	# these frames the node's first sweep sees no wall at all, and whether that first
	# frame happened to point a beam at the player decided whether this check passed.
	await advance_physics(2)
	_add_enemy(arena, FIREWALL_NODE_SCENE, Vector2.ZERO, _fast_firewall())

	# Long enough for every beam to sweep the sheltered player several times over.
	await advance_physics(120)

	check_near(health.current, 3.0, "a player behind a wall is never hit by a beam")
	await _teardown(arena)


# --- Fixtures -----------------------------------------------------------------


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
	await advance_physics(2)


## Everything an enemy asks of the player: a position, a group membership, and something
## to damage.
func _add_target(arena: Node2D, at: Vector2) -> Node2D:
	var target := Node2D.new()
	target.position = at
	target.add_to_group(Teams.GROUP_PLAYER)
	var health := HealthComponent.new()
	health.max_health = 3.0
	target.add_child(health)
	arena.add_child(target)
	health.configure(3.0, 0.0)
	return target


func _add_enemy(
	arena: Node2D, scene: PackedScene, at: Vector2, override: EnemyConfig = null
) -> Enemy:
	var enemy: Enemy = scene.instantiate()
	if override != null:
		enemy.config = override
	enemy.position = at
	arena.add_child(enemy)
	return enemy


func _add_wall(arena: Node2D, at: Vector2, size: Vector2i) -> void:
	var wall: WallBlock = WALL_BLOCK_SCENE.instantiate()
	wall.size = size
	wall.position = at
	arena.add_child(wall)


func _add_room(arena: Node2D) -> Room:
	var template := load("res://data/rooms/combat_open.tres") as RoomTemplate
	if not require(template, "combat_open.tres loads for the room fixture"):
		return null
	var plan := RoomPlan.new(0, Vector2i.ZERO, RoomTemplate.Type.COMBAT)
	plan.template = template
	var room: Room = ROOM_SCENE.instantiate()
	arena.add_child(room)
	room.build(plan)
	return room


func _is_solid_at(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = Teams.LAYER_WORLD
	query.collide_with_areas = false
	return not get_viewport().world_2d.direct_space_state.intersect_point(query, 1).is_empty()


## The shipped drone relocates every 2.6 seconds, which is right in the game and far too
## slow to watch eight times in a test.
func _quick_drone() -> PopUpDroneConfig:
	var tuning := (load(DRONE_CONFIG) as PopUpDroneConfig).duplicate() as PopUpDroneConfig
	tuning.teleport_interval = 0.12
	tuning.arrival_fade = 0.04
	tuning.arrival_pause = 0.1
	return tuning


## Likewise the node's sweep: at the shipped speed one beam passes a given point every
## two and a half seconds.
func _fast_firewall() -> FirewallNodeConfig:
	var tuning := (load(FIREWALL_CONFIG) as FirewallNodeConfig).duplicate() as FirewallNodeConfig
	tuning.beam_rotation_speed = 9.0
	tuning.beam_interval = 0.1
	return tuning


## Reported: enemy knockback was "repeatedly added to velocity and initially grows instead of
## decaying". It was `velocity += _knockback` every frame, and because `velocity` persists the
## same impulse was re-applied for every frame it took to decay — a 55 px/s rivet peaked at
## 90 px/s three frames in, growing before it fell away.
##
## The check is the shape of the motion rather than a magic number: after one hit, each frame's
## displacement must be no larger than the one before it. That is what "decays" means, and it is
## false for any model that re-adds the impulse.
func _test_knockback_decays_instead_of_growing() -> void:
	var arena := _make_arena()
	# A Ticket Bot with no player in the arena: its _act returns zero without a target, so it
	# steers nowhere and anything that moves it is knockback. The Firewall Node would have been
	# the obvious pick and is the wrong one — it is bolted down at knockback_resistance 1.0, so
	# the first version of this check measured a shove that content correctly refuses to apply.
	var enemy := _add_enemy(arena, TICKET_BOT_SCENE, Vector2(200.0, 200.0))
	await advance_physics(2)

	var origin := enemy.global_position
	# Real damage, not zero: HealthComponent declines a hit of 0 outright, so a knockback
	# attached to one never reaches _on_damaged at all.
	enemy.get_node("%Health").apply_damage(
		DamageInfo.new(1.0, null, Vector2.RIGHT, 120.0)
	)

	var steps: Array[float] = []
	var last := enemy.global_position
	for _frame: int in 12:
		await advance_physics(1)
		steps.append(enemy.global_position.distance_to(last))
		last = enemy.global_position

	check(steps[0] > 0.0, "the enemy is actually shoved (%.2f px on the first frame)" % steps[0])

	var worst_growth := 0.0
	var grew_at := -1
	for index: int in range(1, steps.size()):
		var growth := steps[index] - steps[index - 1]
		if growth > worst_growth:
			worst_growth = growth
			grew_at = index
	check(
		worst_growth <= 0.01,
		"the shove only ever slows down; frame %d moved %.2f px more than the one before it"
			% [grew_at, worst_growth],
	)

	check(
		enemy.global_position.x > origin.x,
		"and it was pushed the way the damage travelled",
	)
	check(
		steps[steps.size() - 1] <= 0.01,
		"the shove has ended by the twelfth frame (%.2f px)" % steps[steps.size() - 1],
	)

	await _teardown(arena)


## The other half of the same fix: `velocity` is the enemy's own steering and must never carry
## the shove, or the acceleration model spends the next frames fighting it.
func _test_knockback_stays_out_of_the_steering_velocity() -> void:
	var arena := _make_arena()
	var enemy := _add_enemy(arena, TICKET_BOT_SCENE, Vector2(200.0, 200.0))
	await advance_physics(2)

	enemy.get_node("%Health").apply_damage(
		DamageInfo.new(1.0, null, Vector2.RIGHT, 120.0)
	)
	await advance_physics(1)

	check(
		enemy.velocity.is_zero_approx(),
		"a stationary enemy's velocity is still zero while it is being shoved (got %s)"
			% enemy.velocity,
	)

	await _teardown(arena)


## The property that made the first draft of the check above measure nothing, and worth pinning
## in its own right: an enemy authored as immovable stays where it is. Both stationary enemies
## on Floor 1 are knockback_resistance 1.0, and a rivet must not slide a bolted-down emitter
## across the room.
func _test_full_resistance_means_immovable() -> void:
	var arena := _make_arena()
	var enemy := _add_enemy(arena, FIREWALL_NODE_SCENE, Vector2(200.0, 200.0))
	await advance_physics(2)

	check_near(
		enemy.config.knockback_resistance, 1.0, "the Firewall Node is authored as immovable"
	)
	var origin := enemy.global_position
	enemy.get_node("%Health").apply_damage(DamageInfo.new(1.0, null, Vector2.RIGHT, 200.0))
	await advance_physics(10)

	check(
		enemy.global_position.distance_to(origin) <= 0.01,
		"a fully resistant enemy is not shoved (moved %.2f px)"
			% enemy.global_position.distance_to(origin),
	)

	await _teardown(arena)

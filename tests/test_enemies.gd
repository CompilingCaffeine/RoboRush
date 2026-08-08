extends TestCase
## Checks for the enemy roster: spec section 15's original four, and the five Development
## added on top of them.
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
const CODE_RUNNER_SCENE := preload("res://scenes/enemies/code_runner.tscn")
const COMPILER_SCENE := preload("res://scenes/enemies/compiler.tscn")
const NULL_POINTER_SCENE := preload("res://scenes/enemies/null_pointer.tscn")
const DEADLOCK_SCENE := preload("res://scenes/enemies/deadlock.tscn")
const RECURSION_SCENE := preload("res://scenes/enemies/recursion.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

const DRONE_CONFIG := "res://data/enemies/pop_up_drone.tres"
const LEECH_CONFIG := "res://data/enemies/memory_leech.tres"
const FIREWALL_CONFIG := "res://data/enemies/firewall_node.tres"
const CODE_RUNNER_CONFIG := "res://data/enemies/code_runner.tres"
const COMPILER_CONFIG := "res://data/enemies/compiler.tres"
const NULL_POINTER_CONFIG := "res://data/enemies/null_pointer.tres"
const DEADLOCK_CONFIG := "res://data/enemies/deadlock.tres"
const RECURSION_CONFIG := "res://data/enemies/recursion.tres"


func run() -> void:
	_test_configs_load_as_their_own_types()
	_test_the_roster_is_nine_distinct_problems()

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
	await _test_code_runner_strafes_while_firing()
	await _test_compiler_paints_lanes()
	await _test_null_pointer_marks_where_the_player_is()
	await _test_null_pointer_does_not_follow_the_player()
	await _test_deadlock_warns_before_it_drains()
	await _test_deadlock_is_broken_by_cover()
	await _test_deadlock_is_broken_by_distance()
	await _test_recursion_splits_into_fragments()
	await _test_recursion_fragments_do_not_split_again()
	await _test_a_room_is_not_clear_while_fragments_live()
	await _test_every_hurt_flash_is_actually_wired()
	await _test_a_tinted_enemy_keeps_its_colour()
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

	var runner := load(CODE_RUNNER_CONFIG) as CodeRunnerConfig
	if require(runner, "code_runner.tres loads as a CodeRunnerConfig"):
		check(runner.weapon != null, "the runner has a weapon — firing while moving is its whole point")
		check(runner.direction_hold_seconds > 0.0, "it commits to a strafe direction for a real duration")

	var compiler := load(COMPILER_CONFIG) as CompilerConfig
	if require(compiler, "compiler.tres loads as a CompilerConfig"):
		check(is_zero_approx(compiler.move_speed), "the compiler never moves — the lane is its attack")
		check(compiler.lane_telegraph_seconds > 0.0, "its lane telegraphs for a real duration")

	var null_pointer := load(NULL_POINTER_CONFIG) as NullPointerConfig
	if require(null_pointer, "null_pointer.tres loads as a NullPointerConfig"):
		check(
			null_pointer.mark_telegraph_seconds > 0.0,
			"its patch telegraphs for a real duration — a hazard placed under the player with no warning has no answer",
		)
		check(null_pointer.mark_tiles >= 3, "the patch is big enough to read as a deliberate square")
		check(
			null_pointer.contact_damage <= 0.0,
			"it never touches the player — the patch is its whole attack",
		)

	var deadlock := load(DEADLOCK_CONFIG) as DeadlockConfig
	if require(deadlock, "deadlock.tres loads as a DeadlockConfig"):
		check(deadlock.acquire_seconds > 0.0, "the tether is harmless for a readable window first")
		check(
			deadlock.tether_range > deadlock.preferred_range,
			"it holds station inside its own reach (%.0f held against %.0f reach), so the player has to *move* to break it rather than getting the break for free"
				% [deadlock.preferred_range, deadlock.tether_range],
		)
		check(
			deadlock.reacquire_delay > 0.0,
			"reaching cover buys real time rather than one frame",
		)

	var recursion := load(RECURSION_CONFIG) as RecursionConfig
	if require(recursion, "recursion.tres loads as a RecursionConfig"):
		check(recursion.fragment_count >= 2, "a split actually produces a crowd")
		check(recursion.max_generation >= 1, "the enemy the floor spawns can split at all")
		check(
			recursion.fragment_health < recursion.max_health,
			"a fragment is cheaper to remove than the body it came from",
		)
		check(
			recursion.fragment_speed_scale > 1.0,
			"fragments are faster than the parent — that is the cost of the kill",
		)
		# The whole family has to stay inside a sane time-to-kill, and the parent's pool is
		# only part of that bill.
		var family := recursion.max_health + recursion.fragment_count * recursion.fragment_health
		check(
			family <= 8.0,
			"the whole family costs %.1f integrity to clear, which is one tough enemy rather than three"
				% family,
		)


## Spec section 15 asks for enemies that each create a *different* movement problem. Nine
## enemies with the same statistics would technically satisfy the count.
func _test_the_roster_is_nine_distinct_problems() -> void:
	var configs: Array[EnemyConfig] = [
		load("res://data/enemies/ticket_bot.tres") as EnemyConfig,
		load(DRONE_CONFIG) as EnemyConfig,
		load(LEECH_CONFIG) as EnemyConfig,
		load(FIREWALL_CONFIG) as EnemyConfig,
		load(CODE_RUNNER_CONFIG) as EnemyConfig,
		load(COMPILER_CONFIG) as EnemyConfig,
		load(NULL_POINTER_CONFIG) as EnemyConfig,
		load(DEADLOCK_CONFIG) as EnemyConfig,
		load(RECURSION_CONFIG) as EnemyConfig,
	]

	var names: Dictionary[String, bool] = {}
	var healths: Dictionary[float, bool] = {}
	for config: EnemyConfig in configs:
		if config == null:
			fail("an enemy config failed to load")
			return
		names[config.display_name] = true
		healths[config.max_health] = true

	check(names.size() == configs.size(), "all nine enemies are named distinctly")
	check(
		healths.size() == configs.size(),
		"all nine have different durability (%d distinct values across %d enemies)"
			% [healths.size(), configs.size()],
	)

	# Was "only the melee enemy deals contact damage", which stopped being the rule when
	# Recursion joined the roster as a second body that hurts to touch. The rule underneath
	# it survives and is the one worth keeping: touching the player is only ever an attack
	# for something that can actually reach them, so a stationary or range-holding enemy
	# must never have it — otherwise the player is punished for approaching a target that
	# gave them no reason to expect it.
	for config: EnemyConfig in configs:
		if config.contact_damage <= 0.0:
			continue
		check(
			config.move_speed > 0.0 and is_zero_approx(config.preferred_range),
			"%s deals contact damage, so it must be one that closes on the player" % config.display_name,
		)


# --- Shared lifecycle ---------------------------------------------------------


## The base class exists so no enemy can quietly stop doing these. An enemy that failed to
## announce its own death would leave rooms permanently uncleared, and the only symptom
## would be a door that never opens.
func _test_every_enemy_shares_the_lifecycle() -> void:
	for scene: PackedScene in [
		TICKET_BOT_SCENE, POP_UP_DRONE_SCENE, MEMORY_LEECH_SCENE, FIREWALL_NODE_SCENE,
		CODE_RUNNER_SCENE, COMPILER_SCENE, NULL_POINTER_SCENE, DEADLOCK_SCENE, RECURSION_SCENE,
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


# --- Code Runner ----------------------------------------------------------------


## README's Floor 2 plan: "Strafes across sight lines and fires while moving." Both halves
## are checked together — a runner that fired without moving, or moved without firing,
## would not be posing the problem it exists for.
func _test_code_runner_strafes_while_firing() -> void:
	var arena := _make_arena()
	_add_target(arena, Vector2.ZERO)
	var runner := _add_enemy(arena, CODE_RUNNER_SCENE, Vector2(110.0, 0.0)) as CodeRunner
	await advance_physics(2)

	var container := arena.get_node("Projectiles")
	var spawned := [0]
	container.child_entered_tree.connect(func(_c: Node) -> void: spawned[0] += 1)

	# The target sits due west of the runner's start, so the tangential (strafe) component
	# of its movement is purely along Y — sampling Y over time is what proves it strafes
	# rather than just closing straight in and holding.
	var lateral: Array[float] = [runner.global_position.y]
	for _cycle: int in 20:
		await advance_physics(6)
		lateral.append(runner.global_position.y)

	var min_y := lateral[0]
	var max_y := lateral[0]
	for y: float in lateral:
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)

	check(spawned[0] > 0, "the runner fires")
	check(
		max_y - min_y > 20.0,
		"and its lateral position actually changes over time (spread %.1f px) — it strafes rather than holding still"
			% (max_y - min_y),
	)
	await _teardown(arena)


# --- Compiler ---------------------------------------------------------------------


## README's Floor 2 plan: "Paints one row or column, telegraphs it, then sends a fast pulse
## through the lane." CompileLane's own telegraph/strike/hit-detection correctness is
## covered in tests/test_combat.gd; this only checks that the Compiler actually produces one.
func _test_compiler_paints_lanes() -> void:
	var arena := _make_arena()
	var room := _add_room(arena)
	if room == null:
		await _teardown(arena)
		return

	var compiler: Compiler = COMPILER_SCENE.instantiate()
	compiler.config = _quick_compiler()
	compiler.position = Vector2(40.0, 40.0)
	room.get_node("%Enemies").add_child(compiler)
	await advance_physics(2)

	var container := arena.get_node("Projectiles")
	var lanes := [0]
	container.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is CompileLane:
				lanes[0] += 1
	)

	await advance_physics(30)

	check(lanes[0] > 0, "the Compiler actually paints a lane")
	await _teardown(arena)


# --- Null Pointer -----------------------------------------------------------------


## The enemy's whole claim is that the patch lands where the player *is*. Checked against
## the rect the lane reports as it executes, rather than against the lane's own fields, so
## what is measured is the geometry that actually resolved damage.
func _test_null_pointer_marks_where_the_player_is() -> void:
	var arena := _make_arena()
	var room := _add_room(arena)
	if room == null:
		await _teardown(arena)
		return

	var here := room.get_interior_centre()
	var target := _add_target(arena, here)
	var pointer: NullPointer = NULL_POINTER_SCENE.instantiate()
	pointer.config = _quick_null_pointer()
	# Placed away from the player so the patch is visibly sent rather than dropped underfoot,
	# and inside the room so `find_room` resolves and the patch snaps to the tile grid.
	pointer.global_position = here + Vector2(90.0, 0.0)
	room.get_node("%Enemies").add_child(pointer)
	await advance_physics(2)

	var executed: Array[Rect2] = []
	var handler := func(rect: Rect2) -> void: executed.append(rect)
	EventBus.compile_lane_executed.connect(handler)
	await advance_physics(40)
	EventBus.compile_lane_executed.disconnect(handler)

	var struck := not executed.is_empty()
	check(struck, "the Null Pointer actually executes a patch")
	if not struck:
		await _teardown(arena)
		return

	var covering := 0
	for rect: Rect2 in executed:
		if rect.grow(CompileLane.PLAYER_RADIUS).has_point(target.global_position):
			covering += 1
	check(
		covering == executed.size(),
		"every patch it executed covered the standing player (%d of %d)"
			% [covering, executed.size()],
	)
	await _teardown(arena)


## The other half, and the half that makes it fair: it commits at the moment of marking and
## never re-aims. A patch that tracked the player would be a hazard with no answer at all,
## which is the failure mode this floor's whole warning language exists to avoid.
##
## Deliberately the mirror of `_test_leech_does_not_steer_mid_charge` — same fairness rule,
## different verb.
func _test_null_pointer_does_not_follow_the_player() -> void:
	var arena := _make_arena()
	var room := _add_room(arena)
	if room == null:
		await _teardown(arena)
		return

	var origin := room.get_interior_centre()
	var target := _add_target(arena, origin)
	var pointer: NullPointer = NULL_POINTER_SCENE.instantiate()
	pointer.config = _quick_null_pointer()
	pointer.global_position = origin + Vector2(90.0, 0.0)
	room.get_node("%Enemies").add_child(pointer)
	await advance_physics(2)

	var executed: Array[Rect2] = []
	var handler := func(rect: Rect2) -> void: executed.append(rect)
	EventBus.compile_lane_executed.connect(handler)

	# Wait for a patch to be marked, then bolt. The quick config telegraphs for 0.25s, which
	# is several physics frames of running away before it can possibly resolve.
	while pointer.get_seconds_to_next_mark() > 0.02:
		await advance_physics(1)
	await advance_physics(2)
	var fled := origin + Vector2(0.0, 70.0)
	target.global_position = fled

	await advance_physics(24)
	EventBus.compile_lane_executed.disconnect(handler)

	var struck := not executed.is_empty()
	check(struck, "a patch resolved while the player was running")
	if not struck:
		await _teardown(arena)
		return

	var chased := 0
	for rect: Rect2 in executed:
		if rect.grow(CompileLane.PLAYER_RADIUS).has_point(fled):
			chased += 1
	check(
		chased == 0,
		"no patch followed the player to where they ran (%d of %d did)" % [chased, executed.size()],
	)
	await _teardown(arena)


# --- Deadlock ---------------------------------------------------------------------


## The tether has to be readable before it is expensive, or "break line of sight" is advice
## the player receives after already paying for it.
func _test_deadlock_warns_before_it_drains() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var health := HealthComponent.find_on(target)
	var lock := _add_enemy(arena, DEADLOCK_SCENE, Vector2(150.0, 0.0)) as Deadlock
	var tuning := lock.config as DeadlockConfig
	await advance_physics(2)

	# Comfortably inside the acquire window, so nothing should have landed yet.
	var warning_frames := int(tuning.acquire_seconds * Engine.physics_ticks_per_second * 0.6)
	await advance_physics(warning_frames)
	check(lock.get_state() == Deadlock.State.ACQUIRING, "it locks on when it can see the player")
	check_near(health.current, 3.0, "and costs nothing at all while it is still amber")

	# Then well past it, plus a drain interval.
	await advance_physics(
		int((tuning.acquire_seconds + tuning.drain_interval) * Engine.physics_ticks_per_second)
	)
	check(lock.get_state() == Deadlock.State.DRAINING, "the tether goes red once the window closes")
	check(health.current < 3.0, "and then it actually drains (%.2f left)" % health.current)
	await _teardown(arena)


## The answer the enemy exists to teach. A wall between the two of them must cut the line,
## and cutting it must be worth more than a single frame.
func _test_deadlock_is_broken_by_cover() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var health := HealthComponent.find_on(target)
	var lock := _add_enemy(arena, DEADLOCK_SCENE, Vector2(150.0, 0.0)) as Deadlock
	var tuning := lock.config as DeadlockConfig
	await advance_physics(2)

	# Let it get all the way to draining first, so what is measured is a tether being cut
	# rather than one that never formed.
	await advance_physics(
		int((tuning.acquire_seconds + tuning.drain_interval) * Engine.physics_ticks_per_second) + 4
	)
	var draining := lock.get_state() == Deadlock.State.DRAINING
	check(draining, "the tether is live before cover arrives")
	if not draining:
		await _teardown(arena)
		return

	_add_wall(arena, Vector2(75.0, 0.0), Vector2i(16, 64))
	await advance_physics(4)
	check(not lock.is_tethered(), "a wall between them cuts the tether")

	var sheltered := health.current
	# Long enough for several drain ticks, had any of them been able to land.
	await advance_physics(int(tuning.drain_interval * Engine.physics_ticks_per_second) * 3)
	check_near(
		health.current, sheltered, "and a player behind cover is never drained again", 0.001
	)
	await _teardown(arena)


## The second answer, and the one that has to exist because the floor generator cannot
## promise the room it lands in has cover worth the name.
func _test_deadlock_is_broken_by_distance() -> void:
	var arena := _make_arena()
	var target := _add_target(arena, Vector2.ZERO)
	var lock := _add_enemy(arena, DEADLOCK_SCENE, Vector2(150.0, 0.0)) as Deadlock
	var tuning := lock.config as DeadlockConfig
	await advance_physics(int(tuning.acquire_seconds * Engine.physics_ticks_per_second) + 4)

	var tethered := lock.is_tethered()
	check(tethered, "the tether is live before the player runs")
	if not tethered:
		await _teardown(arena)
		return

	# Teleported rather than walked, so the check is about the range rule and not about
	# whether a test can outpace a 40 px/s enemy.
	target.global_position = lock.global_position + Vector2(tuning.tether_range + 40.0, 0.0)
	await advance_physics(4)
	check(not lock.is_tethered(), "outranging it snaps the tether too")
	await _teardown(arena)


# --- Recursion --------------------------------------------------------------------


func _test_recursion_splits_into_fragments() -> void:
	var arena := _make_arena()
	var container := Node2D.new()
	arena.add_child(container)
	_add_target(arena, Vector2.ZERO)

	var parent: Recursion = RECURSION_SCENE.instantiate()
	parent.position = Vector2(120.0, 0.0)
	container.add_child(parent)
	await advance_physics(2)

	var tuning := parent.config as RecursionConfig
	parent.get_health_component().apply_damage(DamageInfo.new(999.0))
	# Two frames: fragments are added deferred, because a split happens inside a damage
	# callback with the physics server mid-flush.
	await advance_physics(2)

	var fragments := _living_recursions(container)
	check(
		fragments.size() == tuning.fragment_count,
		"killing a Recursion leaves %d fragments behind (expected %d)"
			% [fragments.size(), tuning.fragment_count],
	)
	for fragment: Recursion in fragments:
		check(fragment.get_generation() == 1, "a fragment knows it is second generation")
		check_near(
			fragment.get_health_component().max_health,
			tuning.fragment_health,
			"a fragment is sized from fragment_health, not from the parent's pool",
		)

	# Reported on review: the spread angle was rolled once per fragment rather than once per
	# split, so two fragments were independently placed and regularly overlapped into what
	# reads as one body — which quietly undoes the whole mechanic, since the player cannot
	# choose when to kill a thing they cannot see is two things.
	if fragments.size() == 2:
		var apart := fragments[0].global_position.distance_to(fragments[1].global_position)
		check(
			apart > tuning.fragment_spread,
			"the two fragments are separated rather than stacked (%.1f px apart)" % apart,
		)
	await _teardown(arena)


## Reported as the thing that would make this enemy unshippable: without a generation cap a
## room's enemy count doubles on every kill and never terminates. The cap is the only thing
## between one Recursion and a room that cannot be cleared, so it is checked directly rather
## than inferred from the config field.
func _test_recursion_fragments_do_not_split_again() -> void:
	var arena := _make_arena()
	var container := Node2D.new()
	arena.add_child(container)
	_add_target(arena, Vector2.ZERO)

	var parent: Recursion = RECURSION_SCENE.instantiate()
	parent.position = Vector2(120.0, 0.0)
	container.add_child(parent)
	await advance_physics(2)

	parent.get_health_component().apply_damage(DamageInfo.new(999.0))
	await advance_physics(2)

	var fragments := _living_recursions(container)
	var split := not fragments.is_empty()
	check(split, "there are fragments to kill")
	if not split:
		await _teardown(arena)
		return

	for fragment: Recursion in fragments:
		check(not fragment.can_split(), "a fragment reports that it is the end of the line")
		fragment.get_health_component().apply_damage(DamageInfo.new(999.0))
	await advance_physics(2)

	check(
		_living_recursions(container).is_empty(),
		"killing the fragments ends it — %d third-generation bodies appeared"
			% _living_recursions(container).size(),
	)
	await _teardown(arena)


## The bug this enemy would otherwise have shipped with: `RoomCombat` decrements on death, so
## a Recursion that split *after* announcing its own death would drop the room's alive count
## to zero for a frame, unlock the doors, and hand the player a cleared room with two
## fragments still chasing them.
func _test_a_room_is_not_clear_while_fragments_live() -> void:
	var arena := _make_arena()
	var room := _add_room(arena)
	if room == null:
		await _teardown(arena)
		return
	_add_target(arena, room.get_interior_centre())

	var enemies := room.get_node("%Enemies")
	var parent: Recursion = RECURSION_SCENE.instantiate()
	parent.position = Vector2(60.0, 60.0)
	enemies.add_child(parent)
	await advance_physics(2)

	var combat := room.get_room_combat()
	combat.begin(enemies)

	var cleared := [0]
	combat.cleared.connect(func() -> void: cleared[0] += 1)

	parent.get_health_component().apply_damage(DamageInfo.new(999.0))
	await advance_physics(4)

	check(cleared[0] == 0, "the room does not report itself clear the moment the parent dies")
	check(
		combat.get_alive_count() == 2,
		"the two fragments are counted as live enemies (alive = %d)" % combat.get_alive_count(),
	)

	for fragment: Recursion in _living_recursions(enemies):
		fragment.get_health_component().apply_damage(DamageInfo.new(999.0))
	await advance_physics(4)

	check(cleared[0] == 1, "and it clears exactly once, when the last fragment is gone")
	await _teardown(arena)


# --- Presentation -----------------------------------------------------------------


## Found while building Development's roster, and the more serious of the two: `HurtFlash`
## declared `@export var target: CanvasItem` and every scene assigned it
## `NodePath("../Sprite")`, which never resolved. `flash()` returns early on a null target,
## so being shot has produced no flash anywhere in the game since the component was written
## — every enemy, both bosses' parts, and the boss terminal — and nothing said so.
##
## The wiring is asserted separately from the behaviour precisely because that is the half
## that was broken. A test that only checked "the colour changes and comes back" would have
## been satisfied by a component doing nothing at all, twice.
func _test_every_hurt_flash_is_actually_wired() -> void:
	for scene: PackedScene in [
		TICKET_BOT_SCENE, POP_UP_DRONE_SCENE, MEMORY_LEECH_SCENE, FIREWALL_NODE_SCENE,
		CODE_RUNNER_SCENE, COMPILER_SCENE, NULL_POINTER_SCENE, DEADLOCK_SCENE, RECURSION_SCENE,
	]:
		var arena := _make_arena()
		var enemy := _add_enemy(arena, scene, Vector2(60.0, 0.0))
		await advance_physics(2)

		var flash := enemy.get_node("%HurtFlash") as HurtFlash
		check(
			flash.get_target() != null,
			"%s's hurt flash resolved its sprite" % enemy.config.display_name,
		)
		await _teardown(arena)


## The other half: both `HurtFlash` and `Enemy.tint_toward` restored `modulate` to pure
## white, which was invisible for as long as every enemy that could be shot had an untinted
## sprite. Code Runner and Compiler are told apart from the rest of their floor by tint, so
## the first rivet to land on either one would have bleached it for the remainder of the
## fight — as soon as the flash above started working at all.
##
## Checked on the shipped Code Runner rather than on a fixture, because the property that
## broke is "the enemies in the game keep their colours", and a fixture with a colour
## invented by the test would have passed the whole time.
func _test_a_tinted_enemy_keeps_its_colour() -> void:
	var arena := _make_arena()
	var runner := _add_enemy(arena, CODE_RUNNER_SCENE, Vector2(100.0, 0.0))
	await advance_physics(2)

	var sprite := runner.get_node("%Sprite") as Sprite2D
	var before := sprite.modulate
	var tinted := not before.is_equal_approx(Color.WHITE)
	check(tinted, "the Code Runner is tinted to begin with")
	if not tinted:
		await _teardown(arena)
		return

	runner.get_health_component().apply_damage(DamageInfo.new(1.0))
	check(sprite.modulate != before, "being hit visibly flashes it")

	# Past the flash, which runs on the frame clock rather than the physics one.
	for _frame: int in 20:
		await get_tree().process_frame
	await advance_physics(2)

	check(
		sprite.modulate.is_equal_approx(before),
		"and it returns to its own colour rather than to white (%s, was %s)"
			% [sprite.modulate, before],
	)
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


## The shipped Compiler waits 3.2 seconds between lanes, which is right in the game and far
## too slow to watch in a test.
func _quick_compiler() -> CompilerConfig:
	var tuning := (load(COMPILER_CONFIG) as CompilerConfig).duplicate() as CompilerConfig
	tuning.lane_interval = 0.05
	return tuning


## Likewise the Null Pointer's 2.4 seconds between patches. The telegraph is shortened too
## but deliberately left several physics frames long, because "the patch does not re-aim
## after it is marked" is only a meaningful thing to check if there is a window to re-aim in.
func _quick_null_pointer() -> NullPointerConfig:
	var tuning := (load(NULL_POINTER_CONFIG) as NullPointerConfig).duplicate() as NullPointerConfig
	tuning.mark_interval = 0.35
	tuning.mark_telegraph_seconds = 0.25
	tuning.mark_strike_seconds = 0.05
	# Stationary for the duration: these checks are about where the patch lands, and an
	# enemy drifting to hold its range moves the answer while they are being measured.
	tuning.move_speed = 0.0
	return tuning


## Every living Recursion under a container, parent and fragments alike. Filters out the
## bodies that are mid-`queue_free`, which are still children for the rest of the frame they
## died in and would otherwise be counted as survivors.
func _living_recursions(container: Node) -> Array[Recursion]:
	var found: Array[Recursion] = []
	for child: Node in container.get_children():
		var recursion := child as Recursion
		if recursion != null and not recursion.is_queued_for_deletion():
			found.append(recursion)
	return found


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

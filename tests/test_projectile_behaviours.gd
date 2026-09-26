extends TestCase
## Checks for the projectile behaviours of roadmap SYS-2: every new `ProjectileConfig` field fired on
## a real projectile, and each one composed with something that already existed.
##
## No shipped item uses these yet, so every shot here is a rivet with fields set in code. What is
## being defended is the design rule the rest of the item suite defends: a behaviour is a field,
## the projectile reads it, and two fields compose without either knowing about the other. Where a
## check could pass for the wrong reason — a shot that would have hit anyway — a control shot fired
## without the field comes first and must miss.

const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")
const RIVET_PATH := "res://data/projectiles/rivet.tres"
const BLASTER_PATH := "res://data/weapons/rivet_blaster.tres"
const FLOOR_SESSION_SCENE := preload("res://scenes/floors/floor_session.tscn")


func run() -> void:
	_test_new_fields_are_neutral_by_default()
	_test_new_fields_are_classified()

	await _test_speed_ramps_up_and_down()
	await _test_damage_ramps_and_carries_into_the_blast()
	await _test_a_growing_shot_reaches_what_a_plain_one_misses()
	await _test_an_orbit_circles_the_shooter_then_flies_out()
	await _test_an_orbit_hits_what_stands_behind_the_shooter()
	await _test_a_pause_re_aims_past_what_it_pierced()
	await _test_a_missed_shot_fires_once_more_at_the_nearest_enemy()
	await _test_a_returning_shot_retargets_only_after_its_return()
	await _test_a_shot_that_hit_something_does_not_retarget()
	await _test_a_killing_shot_continues_as_copies()
	await _test_copies_stop_at_the_cap()
	await _test_a_critical_hit_is_harder_and_says_so()
	await _test_the_status_bonus_reads_statuses_already_there()
	await _test_an_echo_follows_the_shot_and_keeps_its_modifiers()
	await _test_an_echo_is_dropped_with_its_room()
	await _test_an_aura_hurts_what_is_near_and_nothing_further()
	await _test_a_trail_leaves_hazards_that_apply_their_status()
	await _test_hazards_stop_at_the_cap()
	CombatCaps.use(null)


# --- Data ----------------------------------------------------------------------------------


## Every shipped projectile flies exactly as it did before these fields existed. A default that
## did something would change every weapon in the game at once.
func _test_new_fields_are_neutral_by_default() -> void:
	var config := ProjectileConfig.new()
	check_near(config.speed_over_life, 1.0, "speed does not ramp by default")
	check_near(config.damage_over_life, 1.0, "damage does not ramp by default")
	check_near(config.radius_over_distance, 1.0, "the shot does not grow by default")
	check_near(config.orbit_turns, 0.0, "nothing orbits by default")
	check_near(config.pause_and_retarget_seconds, 0.0, "nothing pauses by default")
	check(not config.expire_retarget_shot, "nothing retargets on expiry by default")
	check_near(config.echo_delay, 0.0, "nothing echoes by default")
	check_near(config.crit_chance, 0.0, "nothing crits by default")
	check_near(config.bonus_vs_status, 0.0, "no status bonus by default")
	check_near(config.aura_damage_scale, 0.0, "no aura by default")
	check_near(config.trail_hazard_interval, 0.0, "no trail by default")
	check(config.split_on_kill_count == 0, "no copies on a kill by default")
	check(config.split_depth == 1, "splits are one generation by default")


func _test_new_fields_are_classified() -> void:
	var mine := ItemConfig.new()
	mine.projectile_add = {&"speed_over_life": -1.0}
	check(mine.has_upside(), "a shot that slows to a halt as a mine is worth something")

	var crits := ItemConfig.new()
	crits.projectile_add = {&"crit_chance": 0.12}
	check(crits.has_upside(), "a crit chance is worth something")
	check(not crits.is_stat_only(), "and is a behaviour, because it is an add")


# --- Flight --------------------------------------------------------------------------------


func _test_speed_ramps_up_and_down() -> void:
	var arena := _make_arena()
	await advance_physics(2)

	var fast := _rivet()
	fast.speed = 120.0
	fast.speed_over_life = 2.0
	fast.over_life_seconds = 0.1
	var shot := _fire(arena, Vector2.ZERO, Vector2.RIGHT, fast)
	await advance_physics(20)
	var before := shot.global_position.x
	await advance_physics(1)
	check_near(shot.global_position.x - before, 4.0, "a doubled 120px/s shot flies 4px a frame")

	var mine := _rivet()
	mine.speed = 120.0
	mine.lifetime = 2.0
	mine.speed_over_life = 0.0
	mine.over_life_seconds = 0.1
	var hanging := _fire(arena, Vector2(0.0, 40.0), Vector2.RIGHT, mine)
	await advance_physics(20)
	var resting := hanging.global_position
	await advance_physics(20)
	check(is_instance_valid(hanging), "a shot slowed to a halt waits rather than dying")
	check(
		is_instance_valid(hanging) and hanging.global_position.is_equal_approx(resting),
		"and does not move while it waits",
	)
	await _teardown(arena)


## The ramp arrives in a tenth of a second and the hit comes half a second later, so the shot
## lands at exactly twice its damage — and the blast it sets off, worked out from the same number,
## hits the neighbour twice as hard too.
func _test_damage_ramps_and_carries_into_the_blast() -> void:
	var arena := _make_arena()
	var struck := _add_bot(arena, Vector2(210.0, 0.0))
	var neighbour := _add_bot(arena, Vector2(224.0, 0.0))
	await advance_physics(2)

	var config := _rivet()
	config.damage_over_life = 2.0
	config.over_life_seconds = 0.1
	config.explosion_radius = 30.0
	_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(45)

	check_near(_health(struck), 1.0, "the ramped shot hits for two")
	check_near(_health(neighbour), 1.0, "and its blast hits the neighbour for two as well")
	await _teardown(arena)


func _test_a_growing_shot_reaches_what_a_plain_one_misses() -> void:
	var control := _make_arena()
	var missed := _add_bot(control, Vector2(320.0, 10.0))
	await advance_physics(2)
	_fire(control, Vector2.ZERO, Vector2.RIGHT, _rivet())
	await advance_physics(50)
	check_near(_health(missed), 3.0, "a plain rivet passes an enemy ten pixels off its line")
	await _teardown(control)

	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(320.0, 10.0))
	await advance_physics(2)
	var config := _rivet()
	config.radius_over_distance = 3.0
	var shot := _fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(40)
	if is_instance_valid(shot):
		check_near(
			(shot.get_node("Shape").shape as CircleShape2D).radius,
			config.radius * 3.0,
			"past the growth distance the collision circle is three times the size",
		)
	await advance_physics(20)
	check_near(_health(bot), 2.0, "and the grown shot reaches the enemy the plain one missed")
	await _teardown(arena)


## A shot released after whole turns flies down the line it was aimed. Its lifetime is shorter than
## the orbit takes, so it is only still flying afterwards if circling did not spend it.
func _test_an_orbit_circles_the_shooter_then_flies_out() -> void:
	var arena := _make_arena()
	var shooter := Node2D.new()
	arena.add_child(shooter)
	await advance_physics(2)

	var config := _rivet()
	config.orbit_turns = 1.0
	config.orbit_radius = 22.0
	config.lifetime = 0.2
	var shot := ProjectileFactory.spawn_configured(
		shooter, config, Vector2.RIGHT, Vector2.ZERO, Teams.Id.PLAYER, shooter
	)
	await advance_physics(8)
	check_near(
		shot.global_position.length(), 22.0, "partway round, the shot is on its circle", 0.5
	)
	check(shot.global_position.y > 1.0, "and has moved off the line it was aimed along")

	shooter.position = Vector2(0.0, 50.0)
	await advance_physics(2)
	check_near(
		shot.global_position.distance_to(shooter.global_position),
		22.0,
		"a shooter that moves carries its orbit with it",
		0.5,
	)
	shooter.position = Vector2.ZERO

	await advance_physics(20)
	check(is_instance_valid(shot), "circling did not spend its lifetime")
	if is_instance_valid(shot):
		check(shot.global_position.x > 30.0, "released, it flies out to the right")
		check_near(shot.global_position.y, 0.0, "down the line it was aimed", 2.0)
	await _teardown(arena)


func _test_an_orbit_hits_what_stands_behind_the_shooter() -> void:
	var arena := _make_arena()
	var shooter := Node2D.new()
	arena.add_child(shooter)
	var behind := _add_bot(arena, Vector2(-22.0, 0.0))
	await advance_physics(2)

	var config := _rivet()
	config.orbit_turns = 1.0
	ProjectileFactory.spawn_configured(
		shooter, config, Vector2.RIGHT, Vector2.ZERO, Teams.Id.PLAYER, shooter
	)
	await advance_physics(30)
	check_near(_health(behind), 2.0, "a shot fired forwards hits the enemy behind on its way round")
	await _teardown(arena)


## Composed with pierce: the shot passes through the first enemy, stops, and re-aims — at the
## other enemy, not back at the one it has already been through, although that one is nearer.
func _test_a_pause_re_aims_past_what_it_pierced() -> void:
	var control := _make_arena()
	var off_line := _add_bot(control, Vector2(60.0, 80.0))
	await advance_physics(2)
	_fire(control, Vector2.ZERO, Vector2.RIGHT, _rivet())
	await advance_physics(40)
	check_near(_health(off_line), 3.0, "a shot that never pauses flies past the enemy off its line")
	await _teardown(control)

	var arena := _make_arena()
	var pierced := _add_bot(arena, Vector2(40.0, 0.0))
	var target := _add_bot(arena, Vector2(60.0, 80.0))
	await advance_physics(2)

	var config := _rivet()
	config.pierce_count = 1
	config.pause_after_seconds = 0.15
	config.pause_and_retarget_seconds = 0.15
	var shot := _fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(12)
	var held := shot.global_position
	await advance_physics(4)
	check(shot.global_position.is_equal_approx(held), "mid-flight, the shot stops")
	await advance_physics(40)

	check_near(_health(pierced), 2.0, "it pierced the first enemy once")
	check_near(_health(target), 2.0, "and re-aimed at the other one")
	await _teardown(arena)


## The shot flies straight up past an enemy standing to the side of where it will run out. The new
## shot is this one again, with the same short lifetime, so the enemy stands within that reach.
func _test_a_missed_shot_fires_once_more_at_the_nearest_enemy() -> void:
	for flag: bool in [false, true]:
		var arena := _make_arena()
		var bot := _add_bot(arena, Vector2(60.0, -84.0))
		await advance_physics(2)

		var spawned := _count_spawns(arena)
		var config := _rivet()
		config.lifetime = 0.2
		config.expire_retarget_shot = flag
		_fire(arena, Vector2.ZERO, Vector2.UP, config)
		await advance_physics(50)

		if flag:
			check(spawned[0] == 2, "a missed shot fires one more (%d)" % spawned[0])
			check_near(_health(bot), 2.0, "at the nearest enemy, which it hits")
		else:
			check(spawned[0] == 1, "without the field, a missed shot is just gone")
			check_near(_health(bot), 3.0, "and the enemy is untouched")
		await _teardown(arena)


## Return Protocol and Tail Call compose in the order a player would expect: the shot comes back
## first, and only a shot that has missed both ways fires again.
func _test_a_returning_shot_retargets_only_after_its_return() -> void:
	var arena := _make_arena()
	var bot := _add_bot(arena, Vector2(60.0, 0.0))
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var config := _rivet()
	config.lifetime = 0.2
	config.return_enabled = true
	config.expire_retarget_shot = true
	_fire(arena, Vector2.ZERO, Vector2.UP, config)
	await advance_physics(16)
	check(spawned[0] == 1, "at the end of its outward flight the shot turns back, firing nothing")
	await advance_physics(50)
	check(spawned[0] == 2, "and fires once it has missed on the way back too")
	check_near(_health(bot), 2.0, "at the enemy")
	await _teardown(arena)


func _test_a_shot_that_hit_something_does_not_retarget() -> void:
	var arena := _make_arena()
	var pierced := _add_bot(arena, Vector2(40.0, 0.0))
	var elsewhere := _add_bot(arena, Vector2(0.0, 100.0))
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var config := _rivet()
	config.pierce_count = 1
	config.lifetime = 0.3
	config.expire_retarget_shot = true
	_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(50)

	check_near(_health(pierced), 2.0, "the shot hit on its way")
	check(spawned[0] == 1, "so its expiry is not a miss, and nothing more is fired")
	check_near(_health(elsewhere), 3.0, "and nothing reaches the other enemy")
	await _teardown(arena)


func _test_a_killing_shot_continues_as_copies() -> void:
	for lethal: bool in [false, true]:
		var arena := _make_arena()
		_add_bot(arena, Vector2(100.0, 0.0))
		await advance_physics(2)

		var spawned := _count_spawns(arena)
		var config := _rivet()
		config.damage = 5.0 if lethal else 1.0
		config.pierce_count = 1
		config.split_on_kill_count = 2
		var shot := _fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
		await advance_physics(20)

		if lethal:
			check(spawned[0] == 3, "a killing hit continues as two copies (%d)" % spawned[0])
			check(is_instance_valid(shot), "and a piercing shot carries on beside them")
			var copies := _live_projectiles(arena).filter(
				func(each: Projectile) -> bool: return each != shot
			)
			var none_duplicate := true
			for copy: Projectile in copies:
				none_duplicate = none_duplicate and copy.config.split_on_kill_count == 0
			check(none_duplicate and copies.size() == 2, "and the copies do not copy again")
		else:
			check(spawned[0] == 1, "a hit that does not kill makes no copies")
		await _teardown(arena)


func _test_copies_stop_at_the_cap() -> void:
	CombatCaps.use(null)
	var arena := _make_arena()
	_add_bot(arena, Vector2(100.0, 0.0))
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var config := _rivet()
	config.damage = 5.0
	config.split_on_kill_count = 30
	_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(20)

	var cap := CombatCaps.active().max_children_per_impact
	check(spawned[0] == 1 + cap, "thirty copies asked for, %d made (%d)" % [cap, spawned[0] - 1])
	await _teardown(arena)


# --- Hits ----------------------------------------------------------------------------------


func _test_a_critical_hit_is_harder_and_says_so() -> void:
	for chance: float in [0.0, 1.0]:
		var arena := _make_arena()
		var bot := _add_bot(arena, Vector2(100.0, 0.0))
		await advance_physics(2)

		var flagged := [false]
		bot.get_health_component().damaged.connect(
			func(info: DamageInfo, _remaining: float) -> void: flagged[0] = info.is_critical
		)
		var config := _rivet()
		config.crit_chance = chance
		config.crit_scale = 2.5
		_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
		await advance_physics(20)

		if chance > 0.0:
			check_near(_health(bot), 0.5, "a certain critical hits for two and a half")
			check(flagged[0], "and is marked critical, for the damage number")
		else:
			check_near(_health(bot), 2.0, "no chance, no critical")
			check(not flagged[0], "and nothing marked")
		await _teardown(arena)


func _test_the_status_bonus_reads_statuses_already_there() -> void:
	for case: Array in [
		["an enemy already chilled", true, [] as Array[StringName], 1.5],
		["an enemy carrying nothing", false, [] as Array[StringName], 2.0],
		["an enemy chilled by this very shot", false, [&"chill"] as Array[StringName], 2.0],
	]:
		var arena := _make_arena()
		var bot := _add_bot(arena, Vector2(100.0, 0.0))
		await advance_physics(2)
		if case[1]:
			StatusEffectController.find_on(bot).apply(&"chill")

		var config := _rivet()
		config.bonus_vs_status = 0.5
		config.status_effects = case[2]
		_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
		await advance_physics(20)
		check_near(_health(bot), case[3], "the status bonus against %s" % case[0])
		await _teardown(arena)


## Echoes come from `ProjectileFactory.spawn`, the weapon's path, so this fires through it. The
## echo is the shot again — splitting included — at half the damage, and it does not echo itself.
func _test_an_echo_follows_the_shot_and_keeps_its_modifiers() -> void:
	var arena := _make_arena()
	var spawner := Node2D.new()
	arena.add_child(spawner)
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	ProjectileFactory.spawn(spawner, _echoing_weapon(), Vector2.UP, Vector2.ZERO, Teams.Id.PLAYER)
	await advance_physics(2)
	check(spawned[0] == 1, "the shot leaves alone")
	await advance_physics(8)
	check(spawned[0] == 2, "and its echo follows a tenth of a second later")
	await advance_physics(20)
	check(spawned[0] == 2, "and the echo does not echo")

	var shots := _live_projectiles(arena)
	if shots.size() == 2:
		var echo := shots[1]
		check_near(echo.config.damage, shots[0].config.damage * 0.5, "the echo hits for half")
		check(echo.config.split_count == 2, "and splits like the shot it echoes")
		check_near(echo.config.echo_delay, 0.0, "and carries no echo of its own")
	await _teardown(arena)


## Two ways a room ends before its echo is due: taken out of the tree, and a floor closed at a
## transition while its node waits to be freed. Either way the echo is dropped rather than fired
## into a room that is no longer the one being played.
func _test_an_echo_is_dropped_with_its_room() -> void:
	var arena := _make_arena()
	var spawner := Node2D.new()
	arena.add_child(spawner)
	await advance_physics(2)

	ProjectileFactory.spawn(spawner, _echoing_weapon(), Vector2.UP, Vector2.ZERO, Teams.Id.PLAYER)
	remove_child(arena)
	await advance_physics(12)
	add_child(arena)
	check(
		arena.get_node("Projectiles").get_child_count() == 1,
		"an echo due while its room is out of the tree is dropped, not fired into it later",
	)
	await _teardown(arena)

	var session: FloorSession = FLOOR_SESSION_SCENE.instantiate()
	add_child(session)
	var inside := Node2D.new()
	session.projectiles.add_child(inside)
	await advance_physics(2)

	var before := session.projectiles.get_child_count()
	ProjectileFactory.spawn(inside, _echoing_weapon(), Vector2.UP, Vector2.ZERO, Teams.Id.PLAYER)
	session.close()
	await advance_physics(12)
	check(
		session.projectiles.get_child_count() == before + 1,
		"an echo due after its floor has closed is dropped too",
	)
	session.free()
	await advance_physics(2)

## A slow shot parked between two enemies: the near one is inside its aura and the far one is not.
## Four ticks in its one second of life, at half the rivet's damage each.
func _test_an_aura_hurts_what_is_near_and_nothing_further() -> void:
	var arena := _make_arena()
	var near := _add_bot(arena, Vector2(0.0, 25.0))
	var far := _add_bot(arena, Vector2(0.0, -60.0))
	await advance_physics(2)

	var config := _rivet()
	config.speed = 1.0
	config.lifetime = 1.0
	config.aura_damage_scale = 0.5
	config.aura_radius = 30.0
	_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(70)

	check_near(_health(near), 1.0, "the enemy inside the aura takes four half-damage ticks")
	check_near(_health(far), 3.0, "the enemy outside it takes nothing")
	await _teardown(arena)


func _test_a_trail_leaves_hazards_that_apply_their_status() -> void:
	for pair: Array in [[20.0, true], [40.0, false]]:
		var arena := _make_arena()
		var bot := _add_bot(arena, Vector2(100.0, pair[0]))
		await advance_physics(2)

		var config := _rivet()
		config.trail_hazard_interval = 0.05
		config.trail_hazard_effect = &"chill"
		config.trail_hazard_radius = 24.0
		config.trail_hazard_seconds = 1.0
		_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
		await advance_physics(20)

		var status := StatusEffectController.find_on(bot)
		check_near(_health(bot), 3.0, "%dpx off the line, the shot itself misses" % pair[0])
		if pair[1]:
			check(status.has_effect(&"chill"), "but a patch it left behind chills the enemy")
			check(HazardPatch.live_player_count() > 0, "and the patches are still there")
		else:
			check(not status.has_any_effect(), "and at %dpx no patch reaches either" % pair[0])
		await _teardown(arena)


func _test_hazards_stop_at_the_cap() -> void:
	var caps := CombatCaps.active().duplicate() as CombatCaps
	caps.max_player_hazards = 3
	CombatCaps.use(caps)
	var arena := _make_arena()
	await advance_physics(2)

	var config := _rivet()
	config.trail_hazard_interval = 0.02
	config.trail_hazard_effect = &"burn"
	config.trail_hazard_seconds = 5.0
	_fire(arena, Vector2.ZERO, Vector2.RIGHT, config)
	await advance_physics(30)

	var standing := 0
	for child: Node in arena.get_node("Projectiles").get_children():
		if child is HazardPatch and not child.is_queued_for_deletion():
			standing += 1
	check(standing == 3, "a trail against a cap of three leaves three patches (%d)" % standing)
	await _teardown(arena)
	CombatCaps.use(null)


# --- Helpers -------------------------------------------------------------------------------


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


func _add_bot(arena: Node2D, at: Vector2) -> TicketBot:
	var bot: TicketBot = TICKET_BOT_SCENE.instantiate()
	bot.position = at
	arena.add_child(bot)
	return bot


## Zero for an enemy that has died and been freed, so a check expecting it alive fails rather than
## stopping the suite on a freed reference.
##
## A `Variant` rather than a `TicketBot`, because a typed parameter refuses a freed object before
## the body can ask whether it is one.
func _health(bot: Variant) -> float:
	if not is_instance_valid(bot):
		return 0.0
	return (bot as TicketBot).get_health_component().current


func _count_spawns(arena: Node2D) -> Array:
	var total := [0]
	arena.get_node("Projectiles").child_entered_tree.connect(
		func(child: Node) -> void:
			if child is Projectile:
				total[0] += 1
	)
	return total


func _live_projectiles(arena: Node2D) -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child: Node in arena.get_node("Projectiles").get_children():
		if child is Projectile and not (child as Projectile).is_spent():
			found.append(child as Projectile)
	return found


func _rivet() -> ProjectileConfig:
	return (load(RIVET_PATH) as ProjectileConfig).spawn_copy()


## The Rivet Blaster firing a rivet that splits in two and echoes a tenth of a second later.
func _echoing_weapon() -> WeaponConfig:
	var weapon := (load(BLASTER_PATH) as WeaponConfig).duplicate() as WeaponConfig
	var rivet := _rivet()
	rivet.split_count = 2
	rivet.echo_delay = 0.1
	rivet.echo_damage_scale = 0.5
	weapon.projectile = rivet
	return weapon


func _fire(
	arena: Node2D, origin: Vector2, direction: Vector2, config: ProjectileConfig
) -> Projectile:
	var shooter := Node2D.new()
	arena.add_child(shooter)
	return ProjectileFactory.spawn_configured(
		shooter, config, direction, origin, Teams.Id.PLAYER, shooter
	)

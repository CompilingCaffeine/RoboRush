extends TestCase
## Checks for `CombatCaps`, roadmap ENG-10: the ceilings the game enforces while it runs, on top of
## the ones `test_economy` holds the item data to.
##
## Every check that needs a cap to bind installs a small one through `CombatCaps.use` and puts the
## shipped resource back afterwards. The shipped numbers are far above anything a shipped build
## reaches, which is the point of them and the reason no check here can reach them in a few frames.

const TICKET_BOT_SCENE := preload("res://scenes/enemies/ticket_bot.tscn")
const WALL_BLOCK_SCENE := preload("res://scenes/rooms/wall_block.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLOOR_SESSION_SCENE := preload("res://scenes/floors/floor_session.tscn")
const RIVET_PATH := "res://data/projectiles/rivet.tres"
const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"

## Frames the worst build fires for. Five seconds is several full cycles of shots, splits and
## blasts reaching the walls and dying, so the peak it records is the steady state, not a ramp.
const WORST_BUILD_FRAMES := 300


func run() -> void:
	_test_the_shipped_caps_load()
	await _test_the_cap_retires_the_oldest_shot()
	await _test_a_piercing_shot_outlasts_the_cap()
	await _test_enemy_shots_are_not_counted()
	await _test_split_depth_stops_at_the_cap()
	await _test_one_impact_spawns_at_most_the_cap()
	await _test_blasts_over_the_budget_land_next_frame()
	await _test_a_held_blast_is_dropped_with_its_room()
	await _test_drones_stop_at_the_cap()
	await _test_the_worst_legal_build_never_reaches_a_cap()
	CombatCaps.use(null)


func _test_the_shipped_caps_load() -> void:
	CombatCaps.use(null)
	var caps := CombatCaps.active()
	if not require(caps, "the shipped combat caps load"):
		return
	check(
		caps.resource_path == CombatCaps.SHIPPED_PATH,
		"with nothing installed, the caps in force are the shipped resource",
	)
	for property: String in [
		"max_player_projectiles",
		"max_split_depth",
		"max_children_per_impact",
		"max_drones",
		"max_player_hazards",
		"max_explosions_per_frame",
	]:
		check(int(caps.get(property)) >= 1, "%s is at least one (%d)" % [property, caps.get(property)])


# --- Live player projectiles -----------------------------------------------------------


func _test_the_cap_retires_the_oldest_shot() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_player_projectiles = 4)
	var arena := _make_arena()
	await advance_physics(2)

	var shots: Array[Projectile] = []
	for index: int in 6:
		shots.append(_fire(arena, Vector2(0.0, index * 10.0), _lingering()))
	await advance_physics(2)

	check(ProjectileFactory.live_player_count() == 4, "six shots against a cap of four leave four")
	check(
		not is_instance_valid(shots[0]) and not is_instance_valid(shots[1]),
		"the two oldest are the ones retired",
	)
	var newest_kept := true
	for index: int in range(2, 6):
		newest_kept = newest_kept and is_instance_valid(shots[index])
	check(newest_kept, "and the four newest are still flying")

	await _teardown(arena)
	CombatCaps.use(null)


func _test_a_piercing_shot_outlasts_the_cap() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_player_projectiles = 3)
	var arena := _make_arena()
	await advance_physics(2)

	var piercing := _lingering()
	piercing.pierce_count = 2
	var oldest := _fire(arena, Vector2.ZERO, piercing)
	var plain: Array[Projectile] = []
	for index: int in 3:
		plain.append(_fire(arena, Vector2(0.0, 10.0 + index * 10.0), _lingering()))
	await advance_physics(2)

	check(is_instance_valid(oldest), "the oldest shot survives the cap because it pierces")
	check(not is_instance_valid(plain[0]), "the oldest shot that does not pierce goes instead")
	check(ProjectileFactory.live_player_count() == 3, "and the count stays at the cap")

	await _teardown(arena)
	CombatCaps.use(null)


## The cap is on the player's build. Enemy patterns are authored, and a limit on them would be a
## limit on a boss somebody designed.
func _test_enemy_shots_are_not_counted() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_player_projectiles = 2)
	var arena := _make_arena()
	await advance_physics(2)

	for index: int in 5:
		_fire(arena, Vector2(0.0, index * 10.0), _lingering(), Teams.Id.ENEMY)
	await advance_physics(2)

	check(_live_projectiles(arena).size() == 5, "five enemy shots all fly under a player cap of two")
	check(ProjectileFactory.live_player_count() == 0, "and none of them counts against it")

	await _teardown(arena)
	CombatCaps.use(null)


# --- Splits ------------------------------------------------------------------------------------


## A shot fired across a narrow box splits on each wall it reaches. With three generations asked
## for and two allowed, the grandchildren are the last: 1 + 2 + 4 spawns rather than 1 + 2 + 4 + 8.
func _test_split_depth_stops_at_the_cap() -> void:
	for pair: Array in [[3, 15], [2, 7], [1, 3]]:
		var allowed: int = pair[0]
		var expected: int = pair[1]
		_install(func(caps: CombatCaps) -> void: caps.max_split_depth = allowed)
		var arena := _make_arena()
		_add_narrow_box(arena)
		await advance_physics(2)

		var spawned := _count_spawns(arena)
		var config := _rivet()
		config.split_count = 2
		config.split_depth = 3
		_fire(arena, Vector2(60.0, 0.0), config)
		await advance_physics(90)

		check(
			spawned[0] == expected,
			"three generations asked for, %d allowed: %d shots in all (got %d)"
				% [allowed, expected, spawned[0]],
		)
		await _teardown(arena)
	CombatCaps.use(null)


func _test_one_impact_spawns_at_most_the_cap() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_children_per_impact = 5)
	var arena := _make_arena()
	_add_bot(arena, Vector2(100.0, 0.0))
	await advance_physics(2)

	var spawned := _count_spawns(arena)
	var config := _rivet()
	config.split_count = 12
	_fire(arena, Vector2.ZERO, config)
	await advance_physics(30)

	check(spawned[0] == 6, "a twelve-way split against a cap of five is the parent and five (got %d)"
		% spawned[0])

	await _teardown(arena)
	CombatCaps.use(null)


# --- Explosions ----------------------------------------------------------------------------


func _test_blasts_over_the_budget_land_next_frame() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_explosions_per_frame = 3)
	var arena := _make_arena()
	var bots: Array[TicketBot] = []
	for index: int in 5:
		bots.append(_add_bot(arena, Vector2(index * 80.0, 0.0)))
	await advance_physics(2)

	var blasts := [0]
	var on_blast := func(_centre: Vector2, _radius: float) -> void: blasts[0] += 1
	EventBus.explosion_triggered.connect(on_blast)

	for bot: TicketBot in bots:
		Explosion.detonate(arena, bot.global_position, 12.0, 1.0, Teams.Id.PLAYER)
	check(blasts[0] == 3, "five blasts in one frame against a budget of three resolve three")
	check(Explosion.queued_count() == 2, "and hold the other two")
	check_near(_health_of(bots[4]), 3.0, "a held blast has not landed yet")

	await advance_physics(1)
	check(blasts[0] == 5, "the held two resolve on the next frame")
	check(Explosion.queued_count() == 0, "leaving nothing held")
	var all_hit := true
	for bot: TicketBot in bots:
		all_hit = all_hit and is_equal_approx(_health_of(bot), 2.0)
	check(all_hit, "and every blast landed exactly once")

	EventBus.explosion_triggered.disconnect(on_blast)
	await _teardown(arena)
	CombatCaps.use(null)


## A blast held past the end of a room's life has nowhere to land. Resolving it anyway would put it
## in whatever stands at those coordinates now. Three ways a room ends: freed outright, taken out of
## the tree, and a floor closed at a transition while its node waits to be freed.
func _test_a_held_blast_is_dropped_with_its_room() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_explosions_per_frame = 1)
	var blasts := [0]
	var on_blast := func(_centre: Vector2, _radius: float) -> void: blasts[0] += 1
	EventBus.explosion_triggered.connect(on_blast)

	for ending: String in ["freed", "removed", "closed"]:
		var host: Node2D
		var source: Node2D
		if ending == "closed":
			var session: FloorSession = FLOOR_SESSION_SCENE.instantiate()
			add_child(session)
			host = session
			source = Node2D.new()
			session.projectiles.add_child(source)
		else:
			host = _make_arena()
			source = host
		await advance_physics(2)

		blasts[0] = 0
		Explosion.detonate(source, Vector2.ZERO, 12.0, 1.0, Teams.Id.PLAYER)
		Explosion.detonate(source, Vector2.ZERO, 12.0, 1.0, Teams.Id.PLAYER)
		check(Explosion.queued_count() == 1, "%s: the second blast in the frame is held" % ending)
		match ending:
			"freed":
				host.free()
			"removed":
				remove_child(host)
			"closed":
				(host as FloorSession).close()
		await advance_physics(2)

		check(blasts[0] == 1, "%s: and dropped rather than resolved" % ending)
		check(Explosion.queued_count() == 0, "%s: leaving nothing held" % ending)
		if is_instance_valid(host):
			host.free()

	EventBus.explosion_triggered.disconnect(on_blast)
	CombatCaps.use(null)


# --- Drones -------------------------------------------------------------------------------


func _test_drones_stop_at_the_cap() -> void:
	_install(func(caps: CombatCaps) -> void: caps.max_drones = 2)
	var arena := _make_arena()
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(-400.0, -400.0)
	arena.add_child(player)
	await advance_physics(2)

	var swarm := ItemConfig.new()
	swarm.id = &"test_drone_swarm"
	swarm.drone_count = 6
	player.get_item_inventory().add(swarm)
	await advance_physics(2)

	check(_count_drones(player) == 2, "six drones asked for against a cap of two field two")

	await _teardown(arena)
	CombatCaps.use(null)


# --- The shipped pool against the shipped caps ------------------------------------------------


## The caps a formula over the item data cannot bound, measured instead. Every helpful item in every
## floor's pool at its most stacks, standing still on its last point of integrity so every
## conditional fire-rate bonus is paid, firing into the wall of a closed room: the most shots and
## the most blasts the pool can put in the air at once. `test_economy` holds the same build under
## the caps it can work out from the data.
##
## The measured peaks, when the caps were set, were 45 live shots and far fewer blasts than the
## budget. A cap this build reaches is a cap that has started to decide how an item plays.
func _test_the_worst_legal_build_never_reaches_a_cap() -> void:
	CombatCaps.use(null)
	var caps := CombatCaps.active()
	var arena := _make_arena()
	for spec: Array in [
		[Vector2(-16.0, -16.0), Vector2i(448, 16)],
		[Vector2(-16.0, 192.0), Vector2i(448, 16)],
		[Vector2(-16.0, 0.0), Vector2i(16, 192)],
		[Vector2(416.0, 0.0), Vector2i(16, 192)],
	]:
		var wall: WallBlock = WALL_BLOCK_SCENE.instantiate()
		wall.size = spec[1]
		wall.position = spec[0]
		arena.add_child(wall)
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(208.0, 96.0)
	arena.add_child(player)
	await advance_physics(2)

	var build := _worst_legal_build()
	if not require(not build.is_empty(), "the campaign's pools load"):
		await _teardown(arena)
		return
	player.restore_build(build, 1.0)
	player.get_health_component().grant_quiet_invulnerability(3600.0)

	var blasts := [0]
	var on_blast := func(_centre: Vector2, _radius: float) -> void: blasts[0] += 1
	EventBus.explosion_triggered.connect(on_blast)

	var peak_shots := 0
	var peak_blasts := 0
	var held := 0
	Input.action_press(&"shoot_right")
	for _frame: int in WORST_BUILD_FRAMES:
		blasts[0] = 0
		await advance_physics(1)
		peak_shots = maxi(peak_shots, ProjectileFactory.live_player_count())
		peak_blasts = maxi(peak_blasts, blasts[0])
		held = maxi(held, Explosion.queued_count())
	Input.action_release(&"shoot_right")
	EventBus.explosion_triggered.disconnect(on_blast)

	check(
		player.get_weapon_controller().get_shots_fired() > 60,
		"the build fired throughout (%d shots)" % player.get_weapon_controller().get_shots_fired(),
	)
	check(
		peak_shots < caps.max_player_projectiles,
		"the worst legal build peaks at %d live shots, under the cap of %d"
			% [peak_shots, caps.max_player_projectiles],
	)
	check(
		peak_blasts < caps.max_explosions_per_frame and held == 0,
		"and at %d blasts in a frame, under the budget of %d, with none ever held"
			% [peak_blasts, caps.max_explosions_per_frame],
	)
	await _teardown(arena)


## Every helpful item any floor offers, at its most stacks. Hindrances are left out: they are what a
## player refuses, and Blocking I/O would stop the build firing at all.
func _worst_legal_build() -> Array[ItemConfig]:
	var build: Array[ItemConfig] = []
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if campaign == null:
		return build
	var seen: Dictionary[StringName, bool] = {}
	for index: int in campaign.floors.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		for item: ItemConfig in config.get_items():
			if item == null or item.is_hindrance() or seen.has(item.id):
				continue
			seen[item.id] = true
			for _copy: int in maxi(item.max_stacks, 1):
				build.append(item)
	return build


# --- Helpers -------------------------------------------------------------------------------


## Installs a copy of the shipped caps with `change` applied, so a check names only the one cap it
## is about and every other stays at its shipped value.
func _install(change: Callable) -> void:
	CombatCaps.use(null)
	var caps := CombatCaps.active().duplicate() as CombatCaps
	change.call(caps)
	CombatCaps.use(caps)


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


## Walls 120px apart and far taller than any fan of children can climb, so every generation of a
## split crosses to the opposite wall and meets it head on.
func _add_narrow_box(arena: Node2D) -> void:
	for spec: Array in [
		[Vector2(-16.0, -240.0), Vector2i(16, 480)],
		[Vector2(120.0, -240.0), Vector2i(16, 480)],
	]:
		var wall: WallBlock = WALL_BLOCK_SCENE.instantiate()
		wall.size = spec[1]
		wall.position = spec[0]
		arena.add_child(wall)


func _add_bot(arena: Node2D, at: Vector2) -> TicketBot:
	var bot: TicketBot = TICKET_BOT_SCENE.instantiate()
	bot.position = at
	arena.add_child(bot)
	return bot


func _health_of(bot: TicketBot) -> float:
	return bot.get_health_component().current


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


func _count_drones(player: Player) -> int:
	var total := 0
	for child: Node in player.get_children():
		if child is PlayerDrone:
			total += 1
	return total


func _rivet() -> ProjectileConfig:
	return (load(RIVET_PATH) as ProjectileConfig).spawn_copy()


## A slow, long-lived rivet that will still be in the air when the check looks.
func _lingering() -> ProjectileConfig:
	var config := _rivet()
	config.speed = 1.0
	config.lifetime = 30.0
	return config


func _fire(
	arena: Node2D, origin: Vector2, config: ProjectileConfig, team := Teams.Id.PLAYER
) -> Projectile:
	var shooter := Node2D.new()
	arena.add_child(shooter)
	return ProjectileFactory.spawn_configured(shooter, config, Vector2.RIGHT, origin, team, shooter)

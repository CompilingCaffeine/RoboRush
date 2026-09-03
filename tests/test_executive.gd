extends TestCase
## Executive Systems: composition, advanced encounter, carried build, and the small viewport.

const CAMPAIGN := preload("res://data/runs/main_campaign.tres")
const FLOOR := preload("res://scenes/floors/floor.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
const BOSS := preload("res://scenes/bosses/executive_override.tscn")
const HUD := preload("res://scenes/ui/combat_hud.tscn")
const SUMMARY := preload("res://scenes/ui/run_summary.tscn")
const ARENA := Rect2(0, 0, 416, 192)


func run() -> void:
	_test_compositions_and_distribution()
	await _test_executive_patterns_and_committed_danger()
	await _test_every_boundary_can_resume_to_executive_systems()
	await _test_maximum_build_fits_the_viewport()


func _test_compositions_and_distribution() -> void:
	var config := CAMPAIGN.load_floor(4)
	check(config.id == &"executive_systems", "the fifth floor is Executive Systems")
	check(config.boss_pool.size() == 1 and config.boss_pool[0].id == &"executive_override",
		"the advanced rematch is an explicit fifth encounter")
	for index: int in 4:
		for encounter: BossEncounter in CAMPAIGN.load_floor(index).boss_pool:
			check(encounter.id != &"executive_override", "the advanced tier cannot reach a starting build")
	var total := 0
	var drawn: Dictionary[StringName, int] = {}
	var coordinated := 0
	for offset: int in 400:
		var layout := FloorGenerator.generate(config, CAMPAIGN.floor_seed_for(7001 + offset * 37, 4))
		check(layout != null and layout.rooms.size() == 10, "Executive layout %d has all ten rooms" % offset)
		if layout == null:
			continue
		var support := false
		for plan: RoomPlan in layout.rooms:
			if plan.type != RoomTemplate.Type.COMBAT:
				continue
			total += plan.template.enemy_spawns.size()
			drawn[plan.template.id] = drawn.get(plan.template.id, 0) + 1
			for forced: PackedScene in plan.template.forced_enemies:
				support = support or forced.resource_path.ends_with("load_balancer.tscn")
		if support:
			coordinated += 1
	var mean := float(total) / 400.0
	print("    Executive Systems: %.2f enemies/floor, support on %d/400 floors; income model %.2f scrap" % [
		mean, coordinated, FloorEconomy.whole_floor(config)])
	check(mean >= 28.0 and mean <= 33.0, "mature compositions average 28-33 enemies (%.2f)" % mean)
	check(coordinated >= 390, "coordination is encountered on nearly every generated floor (%d/400)" % coordinated)
	for template: RoomTemplate in config.combat_templates:
		check(drawn.get(template.id, 0) > 0, "%s reaches a player" % template.id)
		# A pad must never land in solid geometry or directly on a heat zone.
		for link: MigrationLink in template.pad_links:
			for end: Rect2i in [link.a, link.b]:
				for solid: Rect2i in template.obstacles + template.ducts + template.thermal_zones:
					check(not end.intersects(solid), "%s has a clear, cold pad landing" % template.id)


func _test_executive_patterns_and_committed_danger() -> void:
	GameManager.start_run()
	RunManager.begin_run(991, CAMPAIGN)
	var arena := Node2D.new()
	add_child(arena)
	var projectiles := Node2D.new()
	projectiles.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(projectiles)
	var player: Player = PLAYER.instantiate()
	arena.add_child(player)
	player.position = Vector2(208, 155)
	var boss: ExecutiveOverride = BOSS.instantiate()
	arena.add_child(boss)
	boss.begin(ARENA)
	boss.set_physics_process(false)
	boss._player = player
	check(boss.get_health() == boss.config.max_health, "Executive Override starts with its real pool")
	check(boss.config.id == CAMPAIGN.load_floor(4).boss_pool[0].id, "boss credit and encounter identity agree")
	var longest_lane := boss.config.lane_stagger_seconds + boss.config.lane_telegraph_seconds + boss.config.lane_strike_seconds
	for phase: RuntimeError.Phase in [RuntimeError.Phase.SINGLE_LANE, RuntimeError.Phase.STAGGERED_LANES, RuntimeError.Phase.CHECKERBOARD]:
		check(boss._interval_for(phase) > longest_lane, "phase %d resolves both lanes before another command" % phase)
		check(boss._attacks_for(phase).size() >= 3, "phase %d has an authored advanced rotation" % phase)
	check(boss.config.ring_gap >= 3 and boss.config.wall_gap >= 3, "the advanced patterns keep traversable gaps")
	# Route actual hits through the receiver, including the phase changes and death signal.
	HealthComponent.find_on(boss.get_part()).apply_damage(DamageInfo.new(55.0, player))
	check(boss.get_phase() == RuntimeError.Phase.STAGGERED_LANES, "damage advances the executive's second phase")
	HealthComponent.find_on(boss.get_part()).apply_damage(DamageInfo.new(55.0, player))
	check(boss.get_phase() == RuntimeError.Phase.CHECKERBOARD, "damage advances its final phase")
	# A lane deliberately over the stationary player: the killing blow cannot cancel it.
	boss._spawn_lane(Rect2(player.position - Vector2(16, 16), Vector2(32, 32)))
	await advance_physics(2)
	var before := player.get_health_component().current
	check(projectiles.get_child_count() > 0, "the executive commits a visible lane")
	HealthComponent.find_on(boss.get_part()).apply_damage(DamageInfo.new(55.0, player))
	check(boss.get_health() == 0.0, "its real health reaches zero")
	boss.set_physics_process(true)
	await advance_physics(80)
	check(player.get_health_component().current < before, "its committed lane still damages after death")
	await advance_physics(140)
	check(projectiles.get_child_count() == 0, "the dead executive schedules no further attack")
	arena.queue_free()
	await advance_physics(2)


func _test_every_boundary_can_resume_to_executive_systems() -> void:
	var arena := Node2D.new()
	add_child(arena)
	GameManager.start_run()
	RunManager.begin_run(314159, CAMPAIGN)
	var player: Player = PLAYER.instantiate()
	arena.add_child(player)
	var items := _maximum_build()
	player.restore_build(items, 6.0)
	RunManager.add_scrap(57)
	RunManager.add_enemy_health_growth(0.3)
	var floor_node := _new_floor(arena, 0)
	check(floor_node.build(player, CAMPAIGN.floor_seed_for(314159, 0)), "the carried-build run starts")
	var checkpoints: Array[RunCheckpoint] = []
	for boundary: int in 4:
		await _descend(floor_node)
		var checkpoint := RunCheckpoint.from_dict(JSON.parse_string(JSON.stringify(SaveManager.get_checkpoint().to_dict())))
		check(checkpoint.validate(CAMPAIGN).is_empty(), "boundary %d serializes a valid mature build" % (boundary + 1))
		check(checkpoint.item_ids.size() == items.size(), "boundary %d preserves every stack" % (boundary + 1))
		checkpoints.append(checkpoint)
	var fingerprint := floor_node.get_content_fingerprint()
	var final_shop := ShopStock.of(floor_node._shop).to_dict()
	var final_bosses := RunManager.fought_boss_ids.duplicate()
	floor_node.queue_free()
	await advance_physics(2)
	for checkpoint: RunCheckpoint in checkpoints:
		RunManager.restore_run(checkpoint, CAMPAIGN)
		player.restore_build(checkpoint.resolve_items(CAMPAIGN.load_floor_by_id(checkpoint.floor_id)), checkpoint.integrity)
		floor_node = _new_floor(arena, checkpoint.floor_number - 1)
		floor_node.resume_floor_progress([], [], 0, checkpoint.floor_shop)
		check(floor_node.build(player, RunManager.floor_seed), "resume after floor %d builds" % (checkpoint.floor_number - 1))
		await advance_physics(2)
		while floor_node.floor_index < 4:
			await _descend(floor_node)
		check(floor_node.get_content_fingerprint() == fingerprint, "every resume reaches the same Executive Systems content")
		check(ShopStock.of(floor_node._shop).to_dict() == final_shop, "the fifth shop is reproduced")
		check(RunManager.fought_boss_ids == final_bosses, "the five encounters are reproduced")
		check(RunManager.scrap == 57, "the carried purse survives all resumes")
		check_near(RunManager.enemy_health_scale, 1.3, "enemy scaling survives all resumes")
		check(player.get_item_inventory().size() == items.size(), "the maximum build still has every stack")
		floor_node.queue_free()
		await advance_physics(2)
	arena.queue_free()
	RunManager.end_run(false)
	await advance_physics(2)


func _test_maximum_build_fits_the_viewport() -> void:
	GameManager.start_run()
	RunManager.begin_run(314159, CAMPAIGN)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 270)
	add_child(viewport)
	var player: Player = PLAYER.instantiate()
	viewport.add_child(player)
	player.restore_build(_maximum_build(), 6.0)
	var hud: CombatHUD = HUD.instantiate()
	viewport.add_child(hud)
	hud.bind_player(player)
	RunManager.begin_floor(5, &"executive_systems", 314159, "Executive Systems")
	RunManager.add_scrap(999999)
	var summary: RunSummary = SUMMARY.instantiate()
	viewport.add_child(summary)
	summary.set_process(false)
	summary._peeking = true
	RunManager.stats.items_collected = PackedStringArray()
	for item: ItemConfig in _maximum_build():
		RunManager.stats.items_collected.append(item.display_name)
	RunManager.stats.cause_of_death = "Executive Override"
	summary._refresh()
	await advance_physics(4)
	var bar := hud.get_node("%ItemBar") as HBoxContainer
	check(bar.get_child_count() == CombatHUD.VISIBLE_ITEM_TYPES + 1, "the HUD has a bounded icon row and an overflow count")
	check(bar.get_global_rect().end.x < (hud.get_node("%TopLabel") as Label).get_global_rect().position.x,
		"the maximum build does not overlap the floor/scrap readout")
	check((summary.get_node("%BuildGrid") as GridContainer).get_child_count() == CAMPAIGN.load_floor(4).get_items().size(),
		"the summary shows every item type exactly once")
	var outside: PackedStringArray = []
	_check_controls_inside(summary, Rect2(0, 0, 480, 270), outside)
	check(outside.is_empty(), "the complete summary fits 480x270: %s" % ", ".join(outside))
	# The game-over form has buttons and the longest plausible cause label.
	GameManager.end_run()
	summary._refresh()
	await advance_physics(3)
	outside.clear()
	_check_controls_inside(summary, Rect2(0, 0, 480, 270), outside)
	check(outside.is_empty(), "the ending and its buttons fit 480x270: %s" % ", ".join(outside))
	GameManager.start_run()
	viewport.queue_free()
	await advance_physics(2)


func _maximum_build() -> Array[ItemConfig]:
	var items: Array[ItemConfig] = []
	for item: ItemConfig in CAMPAIGN.load_floor(4).get_items():
		for stack: int in maxi(item.max_stacks, 1):
			items.append(item)
	return items


func _new_floor(parent: Node, index: int) -> FloorController:
	var floor_node: FloorController = FLOOR.instantiate()
	floor_node.campaign = CAMPAIGN
	floor_node.config = CAMPAIGN.load_floor(index)
	parent.add_child(floor_node)
	return floor_node


func _descend(floor_node: FloorController) -> void:
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			var stand_in := Node.new()
			floor_node._on_boss_defeated(stand_in, floor_node.get_room(plan.id))
			stand_in.free()
			break
	await advance_physics(1)
	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	await advance_physics(4)


func _check_controls_inside(node: Node, bounds: Rect2, outside: PackedStringArray) -> void:
	if node is Control and (node as Control).is_visible_in_tree():
		var rect := (node as Control).get_global_rect()
		if not bounds.encloses(rect) and rect.has_area():
			outside.append(String(node.name))
	for child: Node in node.get_children():
		_check_controls_inside(child, bounds, outside)

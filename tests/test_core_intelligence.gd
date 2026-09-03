extends TestCase
## The authored finale: content distribution, readable synthesis, checkpoint boundary and victory.

const CAMPAIGN := preload("res://data/runs/main_campaign.tres")
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOSS_SCENE := preload("res://scenes/bosses/core_intelligence.tscn")
const SUMMARY_SCENE := preload("res://scenes/ui/run_summary.tscn")
const ARENA := Rect2(0, 0, 416, 192)


func run() -> void:
	_test_content_and_distribution()
	await _test_final_boss_synthesizes_committed_hazards()
	await _test_fifth_boundary_resumes_the_finale()
	await _test_sixth_reward_is_the_only_victory()


func _test_content_and_distribution() -> void:
	check(CAMPAIGN.size() == 6, "the shipped campaign has all six floors")
	check(CAMPAIGN.require_complete, "the shipped campaign treats missing content as fatal")
	check(CAMPAIGN.content_version == 5, "the finale moves checkpoints to content version 5")
	var report := CampaignValidator.validate(CAMPAIGN)
	check(report.is_valid(), "the completed campaign validates:\n%s" % report.describe())
	check(report.warnings.is_empty(), "the completed campaign has no provisional warnings")

	var config := CAMPAIGN.load_floor(5)
	if not require(config, "the sixth floor loads"):
		return
	check(config.id == &"core_intelligence", "the sixth floor has the stable finale id")
	check(config.boss_pool.size() == 1 and config.boss_pool[0].id == &"core_intelligence",
		"the finale has one explicit final encounter")
	for index: int in 5:
		for encounter: BossEncounter in CAMPAIGN.load_floor(index).boss_pool:
			check(encounter.id != &"core_intelligence", "the final encounter cannot be drawn early")

	var total_enemies := 0
	var coordinated := 0
	var drawn: Dictionary[StringName, int] = {}
	for offset: int in 400:
		var layout := FloorGenerator.generate(config, CAMPAIGN.floor_seed_for(8803 + offset * 41, 5))
		check(layout != null and layout.rooms.size() == 10, "Core layout %d has all ten rooms" % offset)
		if layout == null:
			continue
		var has_support := false
		for plan: RoomPlan in layout.rooms:
			if plan.type != RoomTemplate.Type.COMBAT:
				continue
			total_enemies += plan.template.enemy_spawns.size()
			drawn[plan.template.id] = drawn.get(plan.template.id, 0) + 1
			for forced: PackedScene in plan.template.forced_enemies:
				has_support = has_support or forced.resource_path.ends_with("load_balancer.tscn")
		if has_support:
			coordinated += 1
	var mean := float(total_enemies) / 400.0
	print("    Core Intelligence: %.2f enemies/floor, coordination on %d/400; income model %.2f scrap" % [
		mean, coordinated, FloorEconomy.whole_floor(config),
	])
	check(mean >= 34.0 and mean <= 40.0, "finale compositions average 34-40 enemies (%.2f)" % mean)
	check(coordinated >= 280, "coordination pressure reaches a clear majority of finales (%d/400)" % coordinated)
	for template: RoomTemplate in config.combat_templates:
		check(drawn.get(template.id, 0) > 0, "%s reaches a player" % template.id)
		for link: MigrationLink in template.pad_links:
			for end: Rect2i in [link.a, link.b]:
				for solid: Rect2i in template.obstacles + template.ducts + template.thermal_zones:
					check(not end.intersects(solid), "%s has a clear, cold pad landing" % template.id)


func _test_final_boss_synthesizes_committed_hazards() -> void:
	GameManager.start_run()
	RunManager.begin_run(606, CAMPAIGN)
	var arena := Node2D.new()
	add_child(arena)
	var hazards := Node2D.new()
	hazards.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(hazards)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	player.position = ARENA.get_center()
	var boss: CoreIntelligence = BOSS_SCENE.instantiate()
	arena.add_child(boss)
	boss.begin(ARENA)
	boss.set_physics_process(false)
	boss._player = player
	check(boss.config is CoreIntelligenceConfig, "the final boss carries finale-specific tuning")
	check(boss.get_health() == 190.0, "the final health bar starts at its real pool")
	for phase: RuntimeError.Phase in [RuntimeError.Phase.SINGLE_LANE, RuntimeError.Phase.STAGGERED_LANES, RuntimeError.Phase.CHECKERBOARD]:
		var attacks := boss._attacks_for(phase)
		check(attacks.size() == 3, "phase %d has one authored three-command rotation" % phase)
		check(CoreIntelligence.ATTACK_VENTS in attacks, "phase %d retains the thermal synthesis" % phase)

	boss._fire_vents()
	check(hazards.get_child_count() == 3, "one inference paints exactly three driven zones")
	var rects: Array[Rect2] = []
	for child: Node in hazards.get_children():
		check(child is ThermalZone and (child as ThermalZone).is_driven(), "every painted zone owns its warning clock")
		if child is ThermalZone:
			var rect := (child as ThermalZone).get_rect()
			rects.append(rect)
			check(ARENA.encloses(rect), "every final-boss zone stays inside the arena")
	for left: int in rects.size():
		for right: int in range(left + 1, rects.size()):
			check(not rects[left].intersects(rects[right]), "the three zones never stack damage")

	var health := HealthComponent.find_on(boss.get_part())
	health.apply_damage(DamageInfo.new(70.0, player))
	check(boss.get_phase() == RuntimeError.Phase.STAGGERED_LANES, "damage reaches the second inference phase")
	health.apply_damage(DamageInfo.new(70.0, player))
	check(boss.get_phase() == RuntimeError.Phase.CHECKERBOARD, "damage reaches the final inference phase")
	var before := player.get_health_component().current
	health.apply_damage(DamageInfo.new(60.0, player))
	check(boss.get_health() == 0.0, "the final boss dies through the ordinary damage receiver")
	boss.set_physics_process(true)
	await advance_physics(112)
	check(player.get_health_component().current < before, "a thermal warning committed before death still resolves")
	await advance_physics(20)
	check(hazards.get_child_count() == 0, "committed zones clean themselves after resolving")
	arena.queue_free()
	RunManager.end_run(false)
	await advance_physics(2)


func _test_fifth_boundary_resumes_the_finale() -> void:
	GameManager.start_run()
	RunManager.begin_run(271828, CAMPAIGN)
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	var floor_node := _new_floor(arena, 0)
	check(floor_node.build(player, CAMPAIGN.floor_seed_for(271828, 0)), "the six-floor run starts")
	for boundary: int in 5:
		await _claim_boss_reward(floor_node)
		check(floor_node.floor_index == boundary + 1, "boundary %d advances exactly one floor" % (boundary + 1))
	check(floor_node.config.id == &"core_intelligence", "the fifth boundary lands in the finale")
	var checkpoint := RunCheckpoint.from_dict(JSON.parse_string(JSON.stringify(SaveManager.get_checkpoint().to_dict())))
	check(checkpoint.validate(CAMPAIGN).is_empty(), "the finale boundary checkpoint survives JSON")
	check(checkpoint.content_version == 5 and checkpoint.floor_number == 6, "the checkpoint names version 5 floor 6")
	var fingerprint := floor_node.get_content_fingerprint()
	floor_node.queue_free()
	await advance_physics(2)
	RunManager.restore_run(checkpoint, CAMPAIGN)
	floor_node = _new_floor(arena, 5)
	floor_node.resume_floor_progress([], [], 0, checkpoint.floor_shop)
	check(floor_node.build(player, RunManager.floor_seed), "the serialized finale resumes")
	check(floor_node.get_content_fingerprint() == fingerprint, "resume reproduces the same final floor")
	floor_node.queue_free()
	arena.queue_free()
	RunManager.end_run(false)
	await advance_physics(2)


func _test_sixth_reward_is_the_only_victory() -> void:
	GameManager.start_run()
	RunManager.begin_run(161803, CAMPAIGN)
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	var floor_node := _new_floor(arena, 0)
	check(floor_node.build(player, CAMPAIGN.floor_seed_for(161803, 0)), "the victory probe starts")
	for boundary: int in 5:
		await _claim_boss_reward(floor_node)
		check(GameManager.state != GameManager.State.VICTORY, "reward %d does not end the run early" % (boundary + 1))
	await _claim_boss_reward(floor_node)
	check(GameManager.state == GameManager.State.VICTORY, "the sixth boss reward wins the completed campaign")
	var summary: RunSummary = SUMMARY_SCENE.instantiate()
	arena.add_child(summary)
	summary._refresh()
	check((summary.get_node("%Title") as Label).text == "SYSTEM RESTORED", "victory names the campaign's final outcome")
	check(RunManager.fought_boss_ids.size() == 6, "the winning run records six encounters")
	var unique: Dictionary[StringName, bool] = {}
	for id: StringName in RunManager.fought_boss_ids:
		unique[id] = true
	check(unique.size() == 6 and unique.has(&"core_intelligence"), "victory includes six distinct bosses and the finale")
	floor_node.queue_free()
	arena.queue_free()
	GameManager.start_run()
	RunManager.end_run(false)
	await advance_physics(2)


func _new_floor(parent: Node, index: int) -> FloorController:
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.campaign = CAMPAIGN
	floor_node.config = CAMPAIGN.load_floor(index)
	parent.add_child(floor_node)
	return floor_node


func _claim_boss_reward(floor_node: FloorController) -> void:
	var boss_room: Room = null
	for room: Room in floor_node._rooms.values():
		if room.plan.type == RoomTemplate.Type.BOSS:
			boss_room = room
			break
	if boss_room == null:
		fail("floor %d has no boss room" % floor_node.config.floor_number)
		return
	var stand_in := Node.new()
	floor_node._on_boss_defeated(stand_in, boss_room)
	stand_in.free()
	await advance_physics(1)
	floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	await advance_physics(4)

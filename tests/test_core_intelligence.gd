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
	await _test_the_finale_wears_every_boss_before_it()
	await _test_the_scrap_kings_mask_refunds_until_its_terminals_are_down()
	await _test_cascade_failures_mask_speaks_the_floors_own_warnings()
	await _test_the_orchestrators_mask_gates_damage_and_can_be_denied()
	await _test_the_last_mask_takes_everything_off()
	await _test_the_whole_fight_runs()
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
	# Held here as well as in `CampaignValidator`, which now refuses this outright: the rule is what
	# the campaign is *for*, and a test that only trusted the validator would pass on a validator
	# whose check had been commented out.
	var finale := config.boss_pool[0]
	for index: int in 5:
		for encounter: BossEncounter in CAMPAIGN.load_floor(index).boss_pool:
			check(encounter.id != &"core_intelligence", "the final encounter cannot be drawn early")

	# One banner per mask. The masks are what the HUD announces as phases, so a mask added without a
	# line to go with it would enter in silence — and the player would meet the Orchestrator's seal
	# with nothing on screen saying what it is.
	check(
		finale.phase_banners.size() == CoreIntelligence.Mask.size(),
		"the finale announces every one of its %d masks (%d banners)"
			% [CoreIntelligence.Mask.size(), finale.phase_banners.size()],
	)
	for banner: String in finale.phase_banners:
		check(not banner.is_empty(), "and none of the masks arrives unannounced")

	# The finale is the longest fight in the campaign before any of its rules are applied, and it
	# has two that make it longer still: a refund and a seal. Compared against every other boss's
	# pool rather than against a number written here, so a rebalanced predecessor moves this too.
	var finale_pool := (load("res://data/bosses/core_intelligence.tres") as RuntimeErrorConfig).max_health
	for path: String in [
		"res://data/bosses/merge_conflict.tres",
		"res://data/bosses/runtime_error.tres",
		"res://data/bosses/cascade_failure.tres",
		"res://data/bosses/orchestrator.tres",
		"res://data/bosses/executive_override.tres",
	]:
		var other: Resource = load(path)
		check(
			finale_pool > other.max_health,
			"the finale outlasts %s (%.0f against %.0f)"
				% [path.get_file(), finale_pool, other.max_health],
		)

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


## The claim the whole fight rests on: the finale is the five bosses before it, worn in the order
## the campaign taught them, out of one pool. Checked as a ladder — a mask per slice, each with its
## own face, its own footprint, and its own rotation — and checked for the thing a mask ladder gets
## wrong, which is furniture from one mask left standing in the next one's fight.
func _test_the_finale_wears_every_boss_before_it() -> void:
	var fight := _open_fight(707)
	var boss: CoreIntelligence = fight["boss"]
	var tuning := boss.config as CoreIntelligenceConfig
	if not require(tuning, "the final boss carries finale-specific tuning"):
		await _close_fight(fight)
		return

	check(boss.get_health() == 300.0, "the final bar starts at its real pool")
	check(boss.get_mask() == CoreIntelligence.Mask.SCRAP_KING, "the fight opens wearing Floor 1")

	# One mask per slice of the pool, and the boundaries are the config's rather than this test's.
	var ladder: Array[Array] = [
		[CoreIntelligence.Mask.SCRAP_KING, 1.0],
		[CoreIntelligence.Mask.RUNTIME_ERROR, tuning.runtime_mask_at],
		[CoreIntelligence.Mask.CASCADE, tuning.cascade_mask_at],
		[CoreIntelligence.Mask.ORCHESTRATOR, tuning.orchestrator_mask_at],
		[CoreIntelligence.Mask.CORE, tuning.core_mask_at],
	]
	var seen: Dictionary[int, bool] = {}
	var vocabulary: Dictionary[int, bool] = {}
	for rung: Array in ladder:
		var mask: CoreIntelligence.Mask = rung[0]
		_drive_to_mask(boss, mask)
		check(boss.get_mask() == mask, "the pool at %.0f%% is wearing mask %d" % [rung[1] * 100.0, mask])
		var attacks := boss._attacks_for(boss.get_phase())
		check(attacks.size() >= 3, "mask %d fights out of an authored rotation" % mask)
		for attack: int in attacks:
			vocabulary[attack] = true
		var texture := boss.get_part().get_sprite().texture
		check(not seen.has(texture.get_rid().get_id()), "mask %d wears a face no other mask does" % mask)
		seen[texture.get_rid().get_id()] = true
		check_near(
			boss.get_part().contact_radius,
			boss._radius_for(mask),
			"mask %d is the size of the boss it is quoting" % mask,
		)
		# And the circle a projectile finds moved with it. Checked separately from the contact
		# radius above because they are two different things that must never disagree: what hurts
		# to stand in, and what the player can hit.
		var circle := (boss.get_part().get_node("Shape") as CollisionShape2D).shape as CircleShape2D
		check_near(circle.radius, boss._radius_for(mask), "and is that size to shoot at, too")
		if mask != CoreIntelligence.Mask.SCRAP_KING:
			check(boss.get_clone() == null, "mask %d fights with one body" % mask)
			check(boss.get_terminal_count() == 0, "and no terminals left standing" % [])
	check(seen.size() == ladder.size(), "five masks, five faces")

	# The rule that makes the parade happen at all. A build near the damage ceiling empties a
	# 300-integrity pool in about seven seconds, so a mask is held for one rotation of its own
	# attacks and damage is floored at its boundary until then — The Scrap King's device, five
	# times over. Checked on a fresh fight, because the ladder above has already been walked down.
	await _close_fight(fight)
	fight = _open_fight(717)
	boss = fight["boss"]
	var hold := boss._hold_seconds()
	check(hold > 0.0, "a mask is worn for a measurable rotation (%.1fs)" % hold)
	for terminal: BossTerminal in boss._terminals.duplicate():
		terminal.get_health_component().apply_damage(DamageInfo.new(999.0))
	_hit(boss.get_part(), 999.0)
	check(
		not boss._is_dead,
		"one shot big enough to end the fight cannot end it during the first mask",
	)
	check(
		boss.get_mask() == CoreIntelligence.Mask.SCRAP_KING,
		"and cannot skip past the mask it was dealt in",
	)
	check_near(
		boss.get_health_ratio(),
		tuning.runtime_mask_at,
		"the pool is floored at the mask's own boundary rather than at a cap of its own",
	)
	boss._step_mask_hold(hold)
	check(
		boss.get_mask() == CoreIntelligence.Mask.RUNTIME_ERROR,
		"and the moment the rotation is done, the damage that was waiting moves the mask on",
	)
	# The last mask has no floor, because a fight that is ending should end.
	_drive_to_mask(boss, CoreIntelligence.Mask.CORE)
	_hit(boss.get_part(), 999.0)
	check(boss._is_dead, "nothing holds the last mask above zero")

	# Collected on the way down rather than in a second pass: the ladder only goes one way, which
	# is the point of it. Between them the five rotations name every attack borrowed from a
	# predecessor — a mask that quoted nobody would be a mask that did not need to exist.
	for borrowed: int in [
		CoreIntelligence.ATTACK_MARKERS,
		CoreIntelligence.ATTACK_VENTS,
		CoreIntelligence.ATTACK_AIMED_VENTS,
		CoreIntelligence.ATTACK_VENT_WALL,
		CoreIntelligence.ATTACK_MIGRATE,
	]:
		check(vocabulary.has(borrowed), "the fight uses borrowed attack %d somewhere" % borrowed)

	await _close_fight(fight)


## Floor 1's puzzle, quoted: two bodies out of one pool, four terminals, and most of the damage
## refunded until they are down. The answer has to still be the answer the player learned there —
## stop shooting the boss, go break a terminal — so what is checked is the *cost* of ignoring it.
func _test_the_scrap_kings_mask_refunds_until_its_terminals_are_down() -> void:
	var fight := _open_fight(808)
	var boss: CoreIntelligence = fight["boss"]
	var tuning := boss.config as CoreIntelligenceConfig
	if not require(tuning, "the finale's tuning loads"):
		await _close_fight(fight)
		return

	check(boss.get_terminal_count() == tuning.terminal_count, "the first mask raises four terminals")
	check(boss.is_synchronised(), "and reports the copies as synchronised while they stand")
	var clone := boss.get_clone()
	if not require(clone != null, "the first mask fights with two bodies"):
		await _close_fight(fight)
		return
	check(
		clone.global_position != boss.get_part().global_position,
		"the second body is somewhere other than the first",
	)

	# One pool between the two, which is what makes two bodies a fight rather than two fights.
	var before := boss.get_health()
	_hit(clone, 20.0)
	var refunded := before - boss.get_health()
	check_near(
		refunded,
		20.0 * (1.0 - tuning.synchronised_refund),
		"a hit on the clone costs the shared pool a quarter of itself while synchronised",
	)

	for terminal: BossTerminal in boss._terminals.duplicate():
		terminal.get_health_component().apply_damage(DamageInfo.new(999.0))
	await advance_physics(2)
	check(boss.get_terminal_count() == 0, "the terminals can be broken")
	check(not boss.is_synchronised(), "and breaking them desynchronises the copies")

	before = boss.get_health()
	_hit(boss.get_part(), 20.0)
	check_near(
		before - boss.get_health(), 20.0, "after which every point of damage reaches the pool"
	)

	# The King's falling markers, which is the one attack in the fight that arrives from a
	# direction rather than from a body.
	var hazards: Node2D = fight["hazards"]
	_clear(hazards)
	boss._fire_markers()
	await advance_physics(1)
	check(
		hazards.get_child_count() == tuning.marker_count,
		"one volley drops %d markers (dropped %d)" % [tuning.marker_count, hazards.get_child_count()],
	)
	await _close_fight(fight)


## Floor 3's language, spoken by the finale: driven throughput zones and nothing else. Three
## patterns, all of which have to leave the arena survivable — the triad that never stacks, the
## pincer that charges for standing still and for holding a heading, and the wall with a door.
func _test_cascade_failures_mask_speaks_the_floors_own_warnings() -> void:
	var fight := _open_fight(909)
	var boss: CoreIntelligence = fight["boss"]
	var player: Player = fight["player"]
	var hazards: Node2D = fight["hazards"]
	var tuning := boss.config as CoreIntelligenceConfig
	if not require(tuning, "the finale's tuning loads"):
		await _close_fight(fight)
		return
	_drive_to_mask(boss, CoreIntelligence.Mask.CASCADE)

	var rotation := boss._attacks_for(boss.get_phase())
	for thermal: int in [
		CoreIntelligence.ATTACK_VENTS,
		CoreIntelligence.ATTACK_AIMED_VENTS,
		CoreIntelligence.ATTACK_VENT_WALL,
	]:
		check(thermal in rotation, "the Data Center's mask fights with attack %d" % thermal)

	_clear(hazards)
	boss._fire_vents()
	var triad := _zones(hazards)
	check(triad.size() == tuning.vent_count, "one inference paints exactly three driven zones")
	for zone: ThermalZone in triad:
		check(zone.is_driven(), "every painted zone owns its warning clock")
		check(ARENA.encloses(zone.get_rect()), "and stays inside the arena")
	for left: int in triad.size():
		for right: int in range(left + 1, triad.size()):
			check(
				not triad[left].get_rect().intersects(triad[right].get_rect()),
				"the three zones never stack damage",
			)

	# The pincer. A robot with a heading is charged for keeping it: the lead patch is ahead of
	# them, in the direction they are travelling, and is not the patch under their feet.
	_clear(hazards)
	player.velocity = Vector2(160.0, 0.0)
	boss._fire_aimed_vents()
	var pincer := _zones(hazards)
	if require(pincer.size() == 2, "the pincer is two patches"):
		var aimed := pincer[0].get_rect().get_center()
		var led := pincer[1].get_rect().get_center()
		check_near(aimed.y, player.global_position.y, "one patch lands where the robot is")
		check(led.x > aimed.x, "and the other ahead of where it is going (%.0f vs %.0f)" % [led.x, aimed.x])

	# A robot with no velocity leads nowhere, which Floor 3 treats as the point rather than as an
	# edge case: standing still is one mistake and is answered by one square.
	_clear(hazards)
	player.velocity = Vector2.ZERO
	boss._fire_aimed_vents()
	var still := _zones(hazards)
	if require(still.size() == 2, "the pincer still fires at a stationary robot"):
		check(
			still[0].get_rect().get_center().is_equal_approx(still[1].get_rect().get_center()),
			"and both patches converge on the square it is standing in",
		)

	# The wall, and the door in it. The door is where the *boss* is, so the way out is toward the
	# thing firing at you — and it is one door rather than none, or the wall is not survivable.
	_clear(hazards)
	boss._fire_vent_wall()
	var wall := _zones(hazards)
	check(
		wall.size() == tuning.vent_wall_count - 1,
		"a wall is %d patches and one door (painted %d)" % [tuning.vent_wall_count - 1, wall.size()],
	)
	# The door is on the boss's own line, so crossing the wall means moving toward the thing
	# firing at you. The wall itself is laid between the two, which is what makes it a wall rather
	# than a line the robot steps off in whichever direction it was already going.
	var body := boss.get_part().global_position
	var between := (body.y + player.global_position.y) * 0.5
	for zone: ThermalZone in wall:
		var rect := zone.get_rect()
		check(
			body.x < rect.position.x or body.x >= rect.end.x,
			"no patch is laid over the door the boss is standing on",
		)
		check(
			rect.position.y <= between and rect.end.y >= between,
			"and every patch stands between the robot and the boss",
		)
		check(ARENA.encloses(rect), "and stays inside the arena")
	await _close_fight(fight)


## Floor 4's rule, quoted with this fight's own materials: the floor discharges, the boss migrates,
## and damage counts only in the window after it lands. The denial is the turn on top — stand where
## it wanted to go and it cannot, which holds it open far longer.
func _test_the_orchestrators_mask_gates_damage_and_can_be_denied() -> void:
	var fight := _open_fight(1010)
	var boss: CoreIntelligence = fight["boss"]
	var player: Player = fight["player"]
	var hazards: Node2D = fight["hazards"]
	var tuning := boss.config as CoreIntelligenceConfig
	if not require(tuning, "the finale's tuning loads"):
		await _close_fight(fight)
		return
	_drive_to_mask(boss, CoreIntelligence.Mask.ORCHESTRATOR)

	check(boss.is_open(), "the mask arrives already landed, rather than sealed on arrival")
	# And is held long enough that the window it arrives with cannot be the whole of it: a build
	# that emptied the slice on arrival would otherwise leave before the first migration resolved,
	# having seen the seal and none of what it is for.
	check(
		boss._hold_seconds() > tuning.open_seconds + tuning.migrate_telegraph_seconds,
		"and is worn for at least one whole migration cycle (%.1fs)" % boss._hold_seconds(),
	)
	boss._step_open_window(tuning.open_seconds + 0.1)
	check(not boss.is_open(), "and seals when the window runs out")

	var before := boss.get_health()
	_hit(boss.get_part(), 30.0)
	check(boss.get_health() == before, "a sealed boss discards damage entirely")

	# The discharge: every cell of the arena grid except the two plates, painted in the compile
	# lane's own amber-then-red so the warning is one the player has read since Floor 2.
	_clear(hazards)
	player.global_position = ARENA.position + Vector2(40.0, 40.0)
	boss._begin_migration()
	var lanes := _lanes(hazards)
	var safe := boss.get_safe_cells()
	check(safe.size() == 2, "a migration leaves two plates live")
	check(safe[0] != safe[1], "and they are two different cells")
	check(
		lanes.size() == boss.get_cell_count() - 2,
		"every other cell discharges (%d lanes of %d cells)" % [lanes.size(), boss.get_cell_count()],
	)
	for cell: int in safe:
		var plate := boss.get_cell_rect(cell)
		for lane: CompileLane in lanes:
			check(not lane.get_rect().intersects(plate), "no lane is painted over a live plate")
	var target := boss.get_cell_rect(safe[0]).get_center()
	var nearer := boss.get_cell_rect(safe[1]).get_center()
	check(
		target.distance_to(player.global_position) > nearer.distance_to(player.global_position),
		"the destination is the ground the robot is least able to reach",
	)
	check(
		not boss.get_cell_rect(safe[1]).has_point(player.global_position),
		"and the other plate is somewhere the robot has to step to",
	)

	# Resolved with the robot elsewhere: the load moves, and the landing opens a short window.
	boss._step_migration(tuning.migrate_telegraph_seconds + 0.1)
	check(boss.is_open(), "landing opens the boss")
	check_near(
		boss.get_part().global_position.distance_to(target),
		0.0,
		"and the body is standing on the ground it named",
	)
	check_near(boss._open_left, tuning.open_seconds, "for the ordinary landing window")

	# Resolved with the robot standing on it: the load has nowhere to go, so the boss stays where
	# it is and is open for substantially longer.
	boss._step_open_window(tuning.open_seconds + 0.1)
	_clear(hazards)
	boss._begin_migration()
	var denied_at := boss.get_cell_rect(boss.get_safe_cells()[0]).get_center()
	var stood := boss.get_part().global_position
	player.global_position = denied_at
	boss._step_migration(tuning.migrate_telegraph_seconds + 0.1)
	check(boss.is_open(), "denying the migration opens it too")
	check_near(
		boss.get_part().global_position.distance_to(stood), 0.0, "and the boss does not move"
	)
	check(
		boss._open_left > tuning.open_seconds,
		"and the window it holds open is the longer one (%.1fs against %.1fs)"
			% [boss._open_left, tuning.open_seconds],
	)
	await _close_fight(fight)


## The end of the ladder. The last mask takes everything off — no terminals, no clone, no seal —
## because a fight that is ending should end, and it fights out of one command borrowed from each
## of the four faces it has already worn.
##
## The post-death contract is checked here rather than in its own test because this is the mask the
## boss dies in, and it is the campaign's rule held where it costs the most: a warning already
## given still resolves in an arena the player has apparently just won.
func _test_the_last_mask_takes_everything_off() -> void:
	var fight := _open_fight(1111)
	var boss: CoreIntelligence = fight["boss"]
	var player: Player = fight["player"]
	var hazards: Node2D = fight["hazards"]
	_drive_to_mask(boss, CoreIntelligence.Mask.CORE)

	check(boss.get_terminal_count() == 0, "the last mask has no terminals to hide behind")
	check(boss.get_clone() == null, "and one body")
	check(boss.is_open(), "and never seals")
	var before := boss.get_health()
	_hit(boss.get_part(), 10.0)
	check_near(before - boss.get_health(), 10.0, "every point of damage counts in the last mask")

	var rotation := boss._attacks_for(boss.get_phase())
	check(
		CoreIntelligence.ATTACK_MARKERS in rotation and CoreIntelligence.ATTACK_AIMED_VENTS in rotation,
		"the last rotation quotes the masks it has taken off",
	)
	check(
		CoreIntelligence.ATTACK_MIGRATE not in rotation,
		"but never seals itself again — a fight that is ending should end",
	)
	check(
		boss._interval_for(boss.get_phase()) < (boss.config as CoreIntelligenceConfig).scrap_interval,
		"and it comes faster than anything the fight opened with",
	)

	# Committed, then killed. The zones the boss announced go on to fill, vent, and cost the player
	# a point in an arena they have apparently just won.
	_clear(hazards)
	boss._player = player
	boss._fire_vents()
	_hit(boss.get_part(), 999.0)
	check(boss.get_health() == 0.0, "the final boss dies through the ordinary damage receiver")
	check(boss.get_terminal_count() == 0 and boss.get_clone() == null, "and leaves nothing standing")
	var health := player.get_health_component().current
	boss.set_physics_process(true)
	await advance_physics(112)
	check(player.get_health_component().current < health, "a warning committed before death still resolves")
	await advance_physics(20)
	check(hazards.get_child_count() == 0, "committed zones clean themselves after resolving")
	await _close_fight(fight)


## The fight, driven rather than stepped: physics on, a robot in the arena, and damage arriving the
## way a player's does until the boss is dead. Every other check in this file measures one mask
## while the clock is stopped, which is precisely what a five-mask fight can pass while still
## falling over the first time it is actually run — a mask change happens inside a damage callback,
## with the physics server mid-flush, and this project has met that error five times.
##
## So this one asserts almost nothing about *what* happens and everything about the fight surviving
## it: every mask reached in order, the boss dead at the end of it, and nothing of the masks left
## standing in the arena afterwards.
func _test_the_whole_fight_runs() -> void:
	var fight := _open_fight(1212)
	var boss: CoreIntelligence = fight["boss"]
	var player: Player = fight["player"]
	# The observer is immune, for `tests/profile_executive.gd`'s reason: this check is about the
	# fight surviving being run, and a robot standing still in the middle of it for half a minute
	# would decide the question by dying rather than by anything the boss did.
	player.get_health_component().add_immunity_source(func() -> bool: return true)
	boss.set_physics_process(true)

	var worn: Array[int] = [boss.get_mask()]
	var frames := 0
	while not boss._is_dead and frames < 5400:
		frames += 4
		await advance_physics(4)
		# The terminals and the landing window are the fight's two answers, and a run that never
		# gave either would stall here rather than testing anything: break what is standing, and
		# push damage in only while it counts.
		for terminal: BossTerminal in boss._terminals.duplicate():
			terminal.get_health_component().apply_damage(DamageInfo.new(999.0))
		if boss.is_open() and is_instance_valid(boss.get_part()):
			_hit(boss.get_part(), 3.0)
		if boss.get_mask() != worn[worn.size() - 1]:
			worn.append(boss.get_mask())

	print("    Core Intelligence: the driven fight took %.1fs against 45 dps" % (frames / 60.0))
	check(boss._is_dead, "the fight finishes inside 90 seconds of driven play (%d frames)" % frames)
	check(
		worn == [
			CoreIntelligence.Mask.SCRAP_KING,
			CoreIntelligence.Mask.RUNTIME_ERROR,
			CoreIntelligence.Mask.CASCADE,
			CoreIntelligence.Mask.ORCHESTRATOR,
			CoreIntelligence.Mask.CORE,
		],
		"and wears all five masks, in the order the campaign taught them (%s)" % [worn],
	)
	check(boss.get_clone() == null and boss.get_terminal_count() == 0, "and leaves nothing standing")

	# Everything the fight painted resolves and cleans itself up, with nothing left attacking from
	# beyond the grave.
	await advance_physics(240)
	check(
		(fight["hazards"] as Node).get_child_count() == 0,
		"and every hazard it committed has resolved (%d left)"
			% (fight["hazards"] as Node).get_child_count(),
	)
	await _close_fight(fight)


# --- Fight harness ----------------------------------------------------------------


## One boss, one robot, and somewhere for hazards to be parented. Physics is off: every check here
## drives the fight a step at a time, because a boss left running would be answering its own attack
## clock in the middle of a measurement.
func _open_fight(seed_value: int) -> Dictionary:
	GameManager.start_run()
	RunManager.begin_run(seed_value, CAMPAIGN)
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
	return {"arena": arena, "hazards": hazards, "player": player, "boss": boss}


func _close_fight(fight: Dictionary) -> void:
	(fight["arena"] as Node).queue_free()
	RunManager.end_run(false)
	await advance_physics(2)


## Damages the boss until it is wearing the mask asked for. Dealt through a body rather than
## written into the pool, so the ladder is crossed the way a player crosses it — including the
## first mask's refund, which is why the terminals come down first.
func _drive_to_mask(boss: CoreIntelligence, mask: CoreIntelligence.Mask) -> void:
	for terminal: BossTerminal in boss._terminals.duplicate():
		terminal.get_health_component().apply_damage(DamageInfo.new(999.0))
	var guard := 0
	while boss.get_mask() < mask and guard < 200:
		guard += 1
		if not boss.is_open():
			boss._open_for(1.0)
		_hit(boss.get_part(), 5.0)
		# A mask is held for one rotation of its own attacks before it may be left, and the clock
		# these checks run under is stopped. Released explicitly rather than waited out: the suite
		# is not going to sit through five rotations to ask what colour the fourth mask is.
		boss._step_mask_hold(boss._hold_seconds())
	check(boss.get_mask() == mask, "the fight reaches mask %d" % mask)


func _hit(part: BossPart, amount: float) -> void:
	HealthComponent.find_on(part).apply_damage(DamageInfo.new(amount))


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _zones(container: Node) -> Array[ThermalZone]:
	var found: Array[ThermalZone] = []
	for child: Node in container.get_children():
		if child is ThermalZone:
			found.append(child as ThermalZone)
	return found


func _lanes(container: Node) -> Array[CompileLane]:
	var found: Array[CompileLane] = []
	for child: Node in container.get_children():
		if child is CompileLane:
			found.append(child as CompileLane)
	return found


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
	# The last floor's boss stands over a trophy rather than over three stands (see `Trophy`), so
	# what is claimed here depends on which floor this is. Claiming the wrong one would descend a
	# floor that has nothing on it to take.
	if floor_node._trophy != null:
		floor_node._trophy.claim()
	else:
		floor_node._on_boss_reward_taken(floor_node.config.get_items()[0])
	await advance_physics(4)

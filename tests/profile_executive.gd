extends Node
## Reproducible carried-build diagnostic. Runs the real Main scene, all combat rooms and
## bosses on all six floors, with every beneficial item at its legal stack ceiling.
## The observer is immune so measurements cannot stop on player death. Enemy health,
## weapon cadence, projectile modifiers, AI, effects and rendering retain shipped values.
## Run without --headless to measure rendering; --fixed-fps makes a fast CPU/lifecycle probe.
## This scene is excluded from normal exports by the existing tests/* filter.

const MAIN := preload("res://main.tscn")
const CAMPAIGN := preload("res://data/runs/main_campaign.tres")

var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _frame_ms: Array[float] = []
var _transitions: Array[float] = []
var _peak_projectiles := 0
var _peak_hostiles := 0
var _nodes_after_runs: Array[int] = []
var _memory_after_runs: Array[int] = []
var _failures: PackedStringArray = []
var _sampling := false
var _last_frame := 0
var _floor: FloorController
var _player: Player
var _cycles := 3
var _snapshots := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-cycles="):
			_cycles = maxi(arg.get_slice("=", 1).to_int(), 1)
		if arg == "--snapshots":
			_snapshots = true
	SaveManager.persistence_enabled = false
	SaveManager.initialize()
	SaveManager.settings = GameSettings.new()
	SaveManager.best = BestRunStats.new()
	SaveManager.apply_settings()
	var orphan_start := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle: int in _cycles:
		var game := MAIN.instantiate()
		add_child(game)
		_floor = game.get_node("%Floor") as FloorController
		_player = game.get_node("%Player") as Player
		var build: Array[ItemConfig] = []
		for item: ItemConfig in CAMPAIGN.load_floor(4).get_items():
			if item.is_hindrance():
				continue
			for stack: int in maxi(item.max_stacks, 1):
				build.append(item)
		_player.restore_build(build, 1.0)
		_player.get_health_component()._quiet_invulnerable_left = 10000.0
		(game.get_node("%CombatHUD") as CombatHUD).bind_player(_player)
		await _frames(3)
		for index: int in CAMPAIGN.size():
			if _floor.floor_index != index:
				_failures.append("expected floor %d, reached %d" % [index + 1, _floor.floor_index + 1])
				break
			var rooms: Array[Room] = []
			var boss_room: Room
			for plan: RoomPlan in _floor.layout.rooms:
				if plan.type == RoomTemplate.Type.COMBAT:
					rooms.append(_floor.get_room(plan.id))
				elif plan.type == RoomTemplate.Type.BOSS:
					boss_room = _floor.get_room(plan.id)
			for room: Room in rooms:
				_enter(room)
				_sampling = true
				await _fight(90)
				# Clear any survivor through the real damage path after the measurement.
				for enemy: Node in room.get_node("Enemies").get_children():
					var health := HealthComponent.find_on(enemy)
					if health != null:
						health.apply_damage(DamageInfo.new(9999.0, _player))
				await _frames(3)
				_sampling = false
				if _snapshots and cycle == 0 and index == 5 and room == rooms[0]:
					await _snapshot("/tmp/roborush-core-room.png")
			_enter(boss_room)
			await _frames(3)
			_sampling = true
			await _fight(180)
			# Exercise actual receiver/phase/death code until the reward appears. This is
			# an endurance probe, not an estimate of human completion time.
			for frame: int in 900:
				if not _floor.get_pending_boss_reward_ids().is_empty():
					break
				if frame % 30 == 0 and is_instance_valid(_floor._boss):
					for part: BossPart in _parts(_floor._boss):
						if is_instance_valid(part):
							part.took_damage.emit(DamageInfo.new(9999.0, _player))
				await _fight(1)
			_sampling = false
			if _floor.get_pending_boss_reward_ids().size() != 3:
				_failures.append("floor %d failed to offer three rewards" % (index + 1))
				break
			var session := _floor.get_session()
			var before := Time.get_ticks_usec()
			_floor._on_boss_reward_taken(_floor.config.get_items()[0])
			await get_tree().process_frame
			if index < CAMPAIGN.size() - 1:
				_transitions.append((Time.get_ticks_usec() - before) / 1000.0)
			await _frames(3)
			if index < CAMPAIGN.size() - 1 and is_instance_valid(session):
				_failures.append("old session survived floor %d" % (index + 1))
			print("Campaign profile: cycle %d/%d, floor %d complete" % [cycle + 1, _cycles, index + 1])
		if not GameManager.is_run_over():
			_failures.append("the campaign did not reach an ending")
		if _snapshots and cycle == 0:
			await _snapshot("/tmp/roborush-core-summary.png")
		GameManager.start_run()
		game.queue_free()
		_floor = null
		_player = null
		await _frames(120)
		_nodes_after_runs.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		_memory_after_runs.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	var orphan_growth := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphan_start
	if orphan_growth > 0:
		_failures.append("%d orphan nodes" % orphan_growth)
	if _nodes_after_runs[-1] > _nodes_after_runs[0]:
		_failures.append("node count grows between runs")
	var report := {
		"engine": Engine.get_version_info().string,
		"display": DisplayServer.get_name(), "cycles": _cycles, "samples": _frame_ms.size(),
		"process_p95_ms": _percentile(_process_ms, 0.95),
		"physics_p95_ms": _percentile(_physics_ms, 0.95),
		"frame_p95_ms": _percentile(_frame_ms, 0.95), "frame_p99_ms": _percentile(_frame_ms, 0.99),
		"transition_p95_ms": _percentile(_transitions, 0.95),
		"peak_projectiles": _peak_projectiles, "peak_hostiles": _peak_hostiles,
		"nodes_after_runs": _nodes_after_runs, "static_bytes_after_runs": _memory_after_runs,
		"orphan_growth": orphan_growth, "failures": Array(_failures),
	}
	print("CAMPAIGN_PROFILE " + JSON.stringify(report))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _sampling and _last_frame > 0 and is_instance_valid(_floor):
		var projectiles := _floor.get_session().projectiles.get_child_count()
		var hostiles := HostileRegistry.count(Teams.Id.ENEMY)
		_peak_projectiles = maxi(_peak_projectiles, projectiles)
		_peak_hostiles = maxi(_peak_hostiles, hostiles)
		if projectiles > 0 or hostiles > 0:
			_frame_ms.append((now - _last_frame) / 1000.0)
			_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_last_frame = now


func _enter(room: Room) -> void:
	_player.global_position = room.get_interior_centre() + Vector2(0, 45)
	_floor._enter_room(room.plan.id)
	_player.frame_room(_floor.get_view_rect_for(room), true)


func _fight(frames: int) -> void:
	for frame: int in frames:
		await get_tree().physics_frame
		var target := Targeting.nearest_hostile(_player, _player.global_position, 500.0, Teams.Id.PLAYER)
		var direction := _player.global_position.direction_to(target.global_position) if target != null else Vector2.RIGHT
		_player.get_weapon_controller().try_fire(_player.global_position, direction)


func _parts(boss: Boss) -> Array[BossPart]:
	if boss.has_method("get_parts"):
		return boss.get_parts()
	var part: BossPart = boss.get_part()
	return [part] if part != null else [] as Array[BossPart]


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _snapshot(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[mini(int(ceil(ordered.size() * fraction)) - 1, ordered.size() - 1)]

class_name CoreIntelligence
extends RuntimeError
## The final exam: compile lanes, projectile formations, and driven throughput zones in authored
## rotations. It adds no hidden rule and never overlaps commands randomly.

const CORE_TEXTURE := preload("res://art/bosses/core_intelligence.png")
const CORE_TINT := Color(0.82, 0.9, 1.2)
const ATTACK_VENTS := 6


func begin(arena: Rect2) -> void:
	super.begin(arena)
	(_part.get_node("%Sprite") as Sprite2D).texture = CORE_TEXTURE
	_restore_tint()


func _restore_tint() -> void:
	if is_instance_valid(_part):
		_part.set_tint(CORE_TINT)


func _attacks_for(phase: Phase) -> Array[int]:
	match phase:
		Phase.SINGLE_LANE:
			return [Attack.LANE, Attack.SPREAD, ATTACK_VENTS]
		Phase.STAGGERED_LANES:
			return [Attack.TWIN_LANES, Attack.RING, ATTACK_VENTS]
		_:
			return [Attack.CHECKERBOARD, Attack.WALL, ATTACK_VENTS]


func _needs_windup(attack: Attack) -> bool:
	if int(attack) == ATTACK_VENTS:
		# A driven ThermalZone is its own cold-to-violet warning.
		return false
	return super._needs_windup(attack)


func _execute(attack: Attack) -> void:
	if int(attack) != ATTACK_VENTS:
		super._execute(attack)
		return
	_fire_vents()
	_attack_left = _interval_for(_phase)
	_flash_left = 0.12
	if is_instance_valid(_part):
		_part.set_tint(_warning_tint(ThermalZone.HOT_COLOR))


func _fire_vents() -> void:
	var core_config := config as CoreIntelligenceConfig
	if core_config == null or _player == null:
		return
	var size := Vector2(core_config.vent_size_tiles * Room.TILE_SIZE)
	var centre := _arena.get_center()
	var player_at := _player.global_position
	# Point into the larger half of the arena on each axis. Unlike mirroring, this stays separated
	# when the player is exactly in the centre, so one warning can never resolve as three hits.
	var direction := Vector2(1.0 if player_at.x <= centre.x else -1.0, 1.0 if player_at.y <= centre.y else -1.0)
	var candidates: Array[Vector2] = [
		player_at,
		player_at + Vector2(6.0 * Room.TILE_SIZE * direction.x, 0.0),
		player_at + Vector2(0.0, 4.0 * Room.TILE_SIZE * direction.y),
	]
	for index: int in mini(core_config.vent_count, candidates.size()):
		var wanted := candidates[index] - size * 0.5
		var top_left := Vector2(
			clampf(wanted.x, _arena.position.x, _arena.end.x - size.x),
			clampf(wanted.y, _arena.position.y, _arena.end.y - size.y),
		)
		ThermalZone.spawn_vent(self, Rect2(top_left, size), core_config.vent_seconds)

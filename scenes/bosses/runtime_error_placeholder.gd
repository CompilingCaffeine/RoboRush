class_name RuntimeErrorPlaceholder
extends Boss
## Floor 2's boss, greybox version.
##
## A single-phase stand-in for the finished "Runtime Error" fight described in README's
## Floor 2 plan (three phases of compile-lane telegraphs). This exists so the floor-2 seam,
## its reward loop, and a completable run can be played before that fight is built — one
## body, one aimed-spread attack, a real health pool, no terminals, no feint.
##
## Structurally a trimmed `MergeConflict`: same part/drift/telegraph/spawn machinery, minus
## everything that exists only to serve its three phases.

const PART_SCENE := preload("res://scenes/bosses/boss_part.tscn")

## Placeholder tint so the greybox boss doesn't read as a recolour-free Scrap King while it
## borrows that boss's body sprite. Cool blue-violet, matching the "Development" palette
## described in README (real art is step 5's job, not this one's).
const TINT := Color(0.55, 0.62, 1.0, 1.0)

@export var config: SimpleBossConfig

var _health := 0.0
var _is_dead := false
var _part: BossPart
var _arena: Rect2
var _player: Node2D
var _attack_left := 0.0
var _telegraph_left := 0.0


func _ready() -> void:
	assert(config != null, "RuntimeErrorPlaceholder.config is unset: assign a SimpleBossConfig.")
	_health = config.max_health
	_attack_left = config.attack_interval


func begin(arena: Rect2) -> void:
	_arena = arena
	_part = PART_SCENE.instantiate()
	add_child(_part)
	# After add_child, always — see MergeConflict._spawn_part for why.
	_part.global_position = arena.get_center()
	_part.set_tint(TINT)
	_part.took_damage.connect(_on_part_damaged)
	EventBus.boss_phase_changed.emit(1)
	_announce_health()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_player = _find_player()
	_step_drift(delta)
	_step_attacks(delta)


func get_health_ratio() -> float:
	return _health / maxf(config.max_health, 0.001)


func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead:
		return
	_health = maxf(_health - info.amount, 0.0)
	EventBus.enemy_damaged.emit(self, DamageInfo.new(info.amount, info.source), _health)
	_announce_health()
	if _health <= 0.0:
		_die()


func _die() -> void:
	_is_dead = true
	var where := _part.global_position if is_instance_valid(_part) else global_position
	if is_instance_valid(_part):
		_part.queue_free()
	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


## Same formula as `MergeConflict._step_drift`, one body instead of up to two.
func _step_drift(delta: float) -> void:
	if _player == null or not is_instance_valid(_part):
		return
	var target := _player.global_position + Vector2(0.0, -70.0)
	_part.global_position = _part.global_position.move_toward(target, config.move_speed * delta)
	_part.global_position = _part.global_position.clamp(_arena.position, _arena.end)


func _step_attacks(delta: float) -> void:
	if not is_instance_valid(_part):
		return
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		var charge := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
		_part.set_tint(TINT.lerp(Color(2.2, 2.0, 2.0), charge))
		if _telegraph_left <= 0.0:
			_fire()
		return

	_attack_left -= delta
	if _attack_left <= 0.0:
		_telegraph_left = config.telegraph_seconds


func _fire() -> void:
	var origin := _part.global_position
	var aim := _aim_from(origin)
	var arc := deg_to_rad(config.spread_degrees)
	var count := maxi(config.spread_count, 1)
	for index: int in count:
		var offset := 0.0 if count == 1 else -arc * 0.5 + arc * (float(index) / float(count - 1))
		_spawn(config.shot, origin, aim.rotated(offset))
	_attack_left = config.attack_interval
	_part.set_tint(TINT)


func _spawn(shot: ProjectileConfig, origin: Vector2, direction: Vector2) -> void:
	if shot == null:
		return
	# Deferred — see MergeConflict._spawn for why (attacks can fire from inside a damage
	# callback when a hit pushes health to zero the same frame).
	ProjectileFactory.spawn_configured(
		self, shot.spawn_copy(), direction, origin, Teams.Id.ENEMY, self, [], true
	)


func _aim_from(origin: Vector2) -> Vector2:
	if _player == null:
		return Vector2.DOWN
	var offset := _player.global_position - origin
	return offset.normalized() if not offset.is_zero_approx() else Vector2.DOWN


func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D

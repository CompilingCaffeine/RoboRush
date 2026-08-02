class_name MergeConflict
extends Node2D
## Spec section 16's Floor 1 boss: a corrupted integration machine that splits into
## incompatible versions of itself and then merges them back together wrong.
##
## The controller owns the fight; the bodies the player shoots at are `BossPart`s that
## forward their hits here. That split is what lets phase two put two bodies in the arena
## without giving the boss two health pools — spec section 16 describes it *duplicating*,
## and two copies of one thing share what it has left.
##
## The three phases are one machine at different settings rather than three
## implementations. Every attack in the fight is a method that fires the same two
## projectile colours in a different arrangement; a phase is a list of which arrangements
## are in rotation and how fast they come. That is why phase three's four named attacks
## cost four small methods rather than a second boss.
##
## The terminals are the fight's one idea. While any survives, damage is partly refunded,
## so the phase-two answer is not "aim better" — it is "stop shooting the boss".

const PART_SCENE := preload("res://scenes/bosses/boss_part.tscn")
const TERMINAL_SCENE := preload("res://scenes/bosses/boss_terminal.tscn")

const RED := Color(1.0, 0.42, 0.42, 1.0)
const GREEN := Color(0.42, 1.0, 0.62, 1.0)

## How far inside the arena walls the boss keeps itself and its terminals.
const ARENA_INSET := 42.0

## Extra scale the merged form takes in phase three, per spec section 16's "larger
## unstable form".
const MERGED_SCALE := 1.45

enum Phase {
	## One body, alternating red and green patterns.
	ALTERNATING = 1,
	## Two bodies, one of each colour, healing each other through the terminals.
	DUPLICATED = 2,
	## One larger body, four attacks in rotation.
	MERGED = 3,
}

@export var config: BossConfig

var _phase := Phase.ALTERNATING
var _health := 0.0
var _is_dead := false

var _primary: BossPart
var _clone: BossPart
var _terminals: Array[BossTerminal] = []

## Terminals still standing, counted from the moment the phase begins rather than from the
## moment their nodes exist. The bodies are added a frame late (see `_enter_duplicated`),
## and a refund that lapsed for that frame would be a refund the player did not earn.
var _terminals_remaining := 0

var _arena: Rect2
var _player: Node2D
var _attack_left := 0.0
var _telegraph_left := 0.0
var _attack_index := 0

## Locked in when a charge begins. Like the Memory Leech's, it does not steer.
var _charge_direction := Vector2.ZERO
var _charge_left := 0.0
var _charge_hit_player := false


func _ready() -> void:
	assert(config != null, "MergeConflict.config is unset: assign a BossConfig resource.")
	_health = config.max_health
	_attack_left = config.phase_one_interval


## Called by the floor once the boss is in the arena it will fight in.
func begin(arena: Rect2) -> void:
	_arena = arena.grow(-ARENA_INSET)
	_primary = _spawn_part(_arena.get_center() + Vector2(0.0, -20.0), RED)
	_announce_health()
	EventBus.boss_phase_changed.emit(int(_phase))


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_player = _find_player()
	_step_charge(delta)
	_step_drift(delta)
	_step_attacks(delta)


# --- State --------------------------------------------------------------------


func get_phase() -> Phase:
	return _phase


func get_health() -> float:
	return _health


func get_health_ratio() -> float:
	return _health / maxf(config.max_health, 0.001)


func get_terminal_count() -> int:
	return _terminals_remaining


## True while the two versions are still synchronised, which is what makes damage partly
## refund. False once every terminal is down, or whenever there is only one body.
func is_synchronised() -> bool:
	return _phase == Phase.DUPLICATED and get_terminal_count() > 0


## The bodies still standing. Either may already be freed — the clone dies first by design,
## and both are gone for the frame between the killing blow and the boss freeing itself.
##
## The candidates are deliberately untyped. Binding a freed instance to a `BossPart` loop
## variable makes Godot validate it *before* the loop body can check it, which spams
## "attempted to set an invalid (previously freed?) object instance" on every call — a
## message the player must never see (spec section 31.10) and one that buried real errors in
## the test output until it was found.
func get_parts() -> Array[BossPart]:
	var parts: Array[BossPart] = []
	for candidate: Variant in [_primary, _clone]:
		if is_instance_valid(candidate):
			parts.append(candidate as BossPart)
	return parts


# --- Damage -------------------------------------------------------------------


## Every hit on either body arrives here, so there is exactly one place that decides what a
## hit is worth and exactly one place the fight can end.
func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead:
		return

	var dealt := info.amount
	if is_synchronised():
		# Spec section 16: damage to one version partially heals the other. Expressed as a
		# refund because there is one pool — the effect the player sees is the same, and it
		# stops being true the moment they break the last terminal.
		dealt *= 1.0 - config.desync_heal_fraction

	_health = maxf(_health - dealt, 0.0)
	EventBus.enemy_damaged.emit(self, DamageInfo.new(dealt, info.source), _health)
	_announce_health()

	if _health <= 0.0:
		_die()
		return

	_advance_phase()


func _advance_phase() -> void:
	var ratio := get_health_ratio()
	if _phase == Phase.ALTERNATING and ratio <= config.duplicate_at:
		_enter_duplicated()
	elif _phase == Phase.DUPLICATED and ratio <= config.merge_at:
		_enter_merged()


## The phase itself changes immediately; the bodies it brings arrive next frame.
##
## A phase change is reached from a projectile's hit callback, and registering a new body's
## collision shape while the physics server is flushing queries is refused outright — the
## fifth time this project has met that trap. Splitting it this way keeps every piece of
## *state* the fight depends on correct within the frame the threshold was crossed, and
## defers only the part Godot will not accept yet.
func _enter_duplicated() -> void:
	_phase = Phase.DUPLICATED
	_terminals_remaining = config.terminal_count
	_primary.set_tint(RED)
	_attack_left = config.phase_two_interval
	EventBus.boss_phase_changed.emit(int(_phase))
	_build_duplicate.call_deferred()


## Guarded, because a frame is long enough for the fight to have moved on: a large enough
## hit can merge or end it before this runs, and a clone appearing afterwards would be a
## second body nothing is tracking.
func _build_duplicate() -> void:
	if _is_dead or _phase != Phase.DUPLICATED or not is_instance_valid(_primary):
		return
	_clone = _spawn_part(_mirror_of(_primary.global_position), GREEN)
	_spawn_terminals()


func _enter_merged() -> void:
	_phase = Phase.MERGED
	if is_instance_valid(_clone):
		_clone.queue_free()
		_clone = null
	# Spec section 16: the two versions merge incorrectly into a larger unstable form.
	_primary.scale = Vector2.ONE * MERGED_SCALE
	_primary.set_tint(Color(1.0, 0.75, 0.55, 1.0))
	_clear_terminals()
	_attack_left = config.phase_three_interval
	EventBus.boss_phase_changed.emit(int(_phase))


func _die() -> void:
	_is_dead = true
	var where := _primary.global_position if is_instance_valid(_primary) else global_position
	for part: BossPart in get_parts():
		part.queue_free()
	_clear_terminals()

	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


# --- Attacks ------------------------------------------------------------------


## One clock for the whole fight: wait, telegraph, fire, repeat. Which attack fires is the
## only thing a phase changes.
func _step_attacks(delta: float) -> void:
	if _charge_left > 0.0:
		return

	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		var charge := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
		for part: BossPart in get_parts():
			part.set_tint(Color.WHITE.lerp(Color(2.2, 2.0, 2.0), charge))
		if _telegraph_left <= 0.0:
			_fire()
		return

	_attack_left -= delta
	if _attack_left <= 0.0:
		_telegraph_left = config.telegraph_seconds


func _fire() -> void:
	match _phase:
		Phase.ALTERNATING:
			# Alternating red and green patterns, exactly as spec section 16 puts it.
			if _attack_index % 2 == 0:
				_fire_ring(_primary.global_position, config.red_shot)
			else:
				_fire_spread(_primary.global_position, config.green_shot)
			_attack_left = config.phase_one_interval
		Phase.DUPLICATED:
			# One version uses red attacks, the other green.
			_fire_spread(_primary.global_position, config.red_shot)
			if is_instance_valid(_clone):
				_fire_ring(_clone.global_position, config.green_shot)
			_attack_left = config.phase_two_interval
		Phase.MERGED:
			_fire_merged_attack()
			_attack_left = config.phase_three_interval

	_attack_index += 1
	_restore_tint()


## Spec section 16's four phase-three attacks, in rotation so the player sees all of them.
func _fire_merged_attack() -> void:
	match _attack_index % 4:
		0:
			_fire_ring(_primary.global_position, config.red_shot, config.ring_count + 4)
		1:
			_begin_charge()
		2:
			_fire_wall()
		_:
			_fire_falling_markers()


## An expanding ring: every projectile leaves at once, evenly spaced.
func _fire_ring(origin: Vector2, shot: ProjectileConfig, count := -1) -> void:
	var total := count if count > 0 else config.ring_count
	for index: int in total:
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(total))
		_spawn(shot, origin, direction)


func _fire_spread(origin: Vector2, shot: ProjectileConfig) -> void:
	var aim := _aim_from(origin)
	var arc := deg_to_rad(config.spread_degrees)
	var count := maxi(config.spread_count, 1)
	for index: int in count:
		var offset := 0.0 if count == 1 else -arc * 0.5 + arc * (float(index) / float(count - 1))
		_spawn(shot, origin, aim.rotated(offset))


## A wall of projectiles crossing the arena with one gap in it. The gap is placed where the
## player is standing *now*, which is what makes it a wall they must move through rather
## than a wall that happens to miss them.
func _fire_wall() -> void:
	var count := maxi(config.wall_count, 3)
	var gap_start := _gap_index(count)
	var top := _arena.position.y
	var height := _arena.size.y
	var from_left := _primary.global_position.x < _arena.get_center().x
	var x := _arena.position.x if from_left else _arena.end.x

	for index: int in count:
		if index >= gap_start and index < gap_start + config.wall_gap:
			continue
		var y := top + height * float(index) / float(count - 1)
		_spawn(config.green_shot, Vector2(x, y), Vector2.RIGHT if from_left else Vector2.LEFT)


## Falling conflict markers: projectiles dropped from the ceiling across the arena.
func _fire_falling_markers() -> void:
	var count := maxi(config.wall_count - 4, 3)
	for index: int in count:
		var x := _arena.position.x + _arena.size.x * float(index) / float(count - 1)
		_spawn(config.red_shot, Vector2(x, _arena.position.y), Vector2.DOWN)


func _begin_charge() -> void:
	_charge_direction = _aim_from(_primary.global_position)
	_charge_left = config.charge_seconds
	_charge_hit_player = false


## The charge is the only attack that damages by contact, and it hits once. A charge that
## ground the player down for every frame of overlap would be unreadable.
func _step_charge(delta: float) -> void:
	if _charge_left <= 0.0:
		return
	_charge_left -= delta
	_primary.global_position += _charge_direction * config.charge_speed * delta
	_clamp_to_arena(_primary)

	if _charge_hit_player or _player == null:
		return
	if _primary.global_position.distance_to(_player.global_position) > config.charge_radius:
		return

	var health := HealthComponent.find_on(_player)
	if health == null:
		return
	if health.apply_damage(DamageInfo.new(config.charge_damage, self, _charge_direction, 200.0)):
		_charge_hit_player = true


# --- Movement -----------------------------------------------------------------


## Slow drift toward a point offset from the player, so the boss repositions without ever
## becoming a chaser. It is the arena that threatens the player, not the boss's footspeed.
func _step_drift(delta: float) -> void:
	if _charge_left > 0.0 or _player == null:
		return
	for part: BossPart in get_parts():
		var target := _player.global_position + Vector2(0.0, -70.0)
		if part == _clone:
			target = _mirror_of(target)
		part.global_position = part.global_position.move_toward(target, config.move_speed * delta)
		_clamp_to_arena(part)


func _clamp_to_arena(part: BossPart) -> void:
	part.global_position = part.global_position.clamp(_arena.position, _arena.end)


func _mirror_of(point: Vector2) -> Vector2:
	var centre := _arena.get_center()
	return Vector2(centre.x * 2.0 - point.x, point.y)


# --- Construction -------------------------------------------------------------


func _spawn_part(at: Vector2, tint: Color) -> BossPart:
	var part: BossPart = PART_SCENE.instantiate()
	add_child(part)
	# After add_child, always. `global_position` on a node with no parent is just its local
	# position, so setting it first lands the part at that offset *from this controller* —
	# which is itself offset onto the floor grid, putting the boss outside its own arena.
	part.global_position = at
	part.set_tint(tint)
	part.took_damage.connect(_on_part_damaged)
	return part


## Four terminals, one per corner of the arena. Corners because they are the furthest thing
## from wherever the boss is, so breaking one always means leaving the fight.
func _spawn_terminals() -> void:
	var corners: Array[Vector2] = [
		_arena.position,
		Vector2(_arena.end.x, _arena.position.y),
		Vector2(_arena.position.x, _arena.end.y),
		_arena.end,
	]
	for index: int in mini(config.terminal_count, corners.size()):
		var terminal: BossTerminal = TERMINAL_SCENE.instantiate()
		add_child(terminal)
		terminal.global_position = corners[index]
		terminal.configure(config.terminal_health)
		terminal.destroyed.connect(_on_terminal_destroyed)
		_terminals.append(terminal)


## Dropped from the list the instant it dies, rather than left for `is_instance_valid` to
## notice next frame. `queue_free` lands at the end of the frame, and a terminal that went
## on protecting the boss after the player destroyed it is a refund they already paid for.
func _on_terminal_destroyed(terminal: BossTerminal) -> void:
	_terminals.erase(terminal)
	_terminals_remaining = maxi(_terminals_remaining - 1, 0)
	_announce_health()


func _clear_terminals() -> void:
	for terminal: BossTerminal in _terminals:
		if is_instance_valid(terminal):
			terminal.queue_free()
	_terminals.clear()
	_terminals_remaining = 0


func _spawn(shot: ProjectileConfig, origin: Vector2, direction: Vector2) -> void:
	if shot == null:
		return
	# Deferred, because an attack can be triggered from inside a damage callback when a hit
	# pushes the boss over a phase threshold.
	ProjectileFactory.spawn_configured(
		self, shot.spawn_copy(), direction, origin, Teams.Id.ENEMY, self, [], true
	)


func _restore_tint() -> void:
	if is_instance_valid(_primary):
		_primary.set_tint(RED if _phase != Phase.MERGED else Color(1.0, 0.75, 0.55, 1.0))
	if is_instance_valid(_clone):
		_clone.set_tint(GREEN)


func _aim_from(origin: Vector2) -> Vector2:
	if _player == null:
		return Vector2.DOWN
	var offset := _player.global_position - origin
	return offset.normalized() if not offset.is_zero_approx() else Vector2.DOWN


## Where the gap in a wall goes: level with the player, clamped so it is always a real gap
## inside the wall rather than a shorter wall.
func _gap_index(count: int) -> int:
	if _player == null:
		return count / 2
	var progress := clampf(
		(_player.global_position.y - _arena.position.y) / maxf(_arena.size.y, 1.0), 0.0, 1.0
	)
	return clampi(int(progress * float(count)) - config.wall_gap / 2, 0, count - config.wall_gap)


func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D

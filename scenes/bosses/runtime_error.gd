class_name RuntimeError
extends Boss
## README's Floor 2 boss, **Runtime Error**: the process the Development floor has been failing
## to compile, finally running.
##
## Where The Scrap King asks the player to *notice* something — that shooting it is pointless
## until the terminals are down — this one asks them to **predict**, which README names as the
## whole floor's job. Every attack in it announces where it will happen before it happens, and
## the fight is won by being somewhere else. So there is no puzzle here and nothing hidden:
## README is explicit that it "remains damageable through all three phases", and it is. No
## refund, no damage scaling, no terminals.
##
## It also does not play dead. The Scrap King's feigned death is a trick that works exactly
## once per player, and a second boss doing it would be a boss the player is already waiting
## for. This one's bar reports the real pool and only reaches zero when the fight is over —
## see `get_health_ratio`, which is the honest counterpart to `MergeConflict`'s deliberately
## lying `get_phase_health_ratio`.
##
## The three phases are README's, in order:
##
## 1. One compile lane at a time, alternating with aimed spreads.
## 2. Two staggered lanes, alternating with projectile rings that have visible gaps.
## 3. Alternating checkerboard execution zones and projectile walls with a traversable opening.
##
## Every hazard it paints is a `CompileLane`, the same class the Compiler enemy uses, so
## README's "the boss must use the same amber-then-red warning language as the Compiler" is
## satisfied by construction rather than by two implementations agreeing on a colour. The body
## borrows those same two colours for its own windup (see `_step_attacks`).
##
## The pairs above are authored and strictly alternating rather than randomly combined, which
## is what README asks for: "Randomly combining attacks is allowed only after authored
## combinations prove they cannot erase every safe route." Six patterns, each of which leaves a
## reachable safe answer on its own, and no two of them ever overlap in time — the interval is
## longer than any pattern takes to resolve.

const PART_SCENE := preload("res://scenes/bosses/runtime_error_part.tscn")

## README's Development palette: "cyan and violet machinery, amber warnings, red execution
## errors." The body is the machinery. The warnings and the errors are `CompileLane`'s own two
## colours, taken from it rather than restated here, so the boss cannot drift out of step with
## the lanes it paints.
const BODY_TINT := Color(0.62, 0.52, 1.0, 1.0)

## What the warning colours are multiplied by before being used as a sprite `modulate`.
## `CompileLane` draws flat rectangles, where a full-value colour reads as bright; a modulate
## at or below one only ever darkens the sprite it multiplies, so the same colour applied the
## same way would read as the body going *dim* to announce an attack. See `_warning_tint`.
const WARNING_GAIN := 2.0

## How far inside the arena walls the body keeps itself. Its lanes are deliberately not inset —
## see `begin`.
const ARENA_INSET := 42.0

## How long the body stays red after an attack leaves it.
const STRIKE_FLASH_SECONDS := 0.12

## How far apart, in lane slots, phase two holds its two staggered lanes. At least two, so that
## leaving the first never means stepping into the second.
const MIN_LANE_SLOT_SEPARATION := 2

## Where the sway starts: the middle of its sweep, so the fight opens with the body directly
## above the player and moving, rather than parked at one end of its travel.
const START_SWAY_PHASE := 0.0

enum Phase {
	## One lane at a time, alternating with aimed spreads.
	SINGLE_LANE = 1,
	## Two staggered lanes, alternating with gapped rings.
	STAGGERED_LANES = 2,
	## Checkerboard execution zones, alternating with walls.
	CHECKERBOARD = 3,
}

## Every pattern the fight contains. Named individually rather than folded into the phases
## because `_needs_windup` has to ask what a pattern *is* — whether it warns for itself or
## needs the body to warn for it — and that is a property of the attack, not of the phase it
## happens to appear in.
enum Attack { LANE, SPREAD, TWIN_LANES, RING, CHECKERBOARD, WALL }

@export var config: RuntimeErrorConfig

var _phase := Phase.SINGLE_LANE
var _health := 0.0
var _is_dead := false
var _part: BossPart

## The room interior, used for every lane, checkerboard, and wall. Not inset: a hazard that
## stopped short of the walls would leave a strip of permanently safe floor around the edge of
## the arena, which is the one thing a pattern fight cannot afford.
var _arena: Rect2

## Where the body is allowed to drift, which *is* inset — a boss standing in the wall is a
## boss half of whose sprite the player cannot see.
var _body_bounds: Rect2

var _player: Node2D
var _attack_left := 0.0
var _telegraph_left := 0.0
var _flash_left := 0.0
var _attack_index := 0

## The attack a body windup is currently counting down to. Only meaningful while
## `_telegraph_left` is positive.
var _pending_attack := Attack.SPREAD

## Phase two's second lane, waiting out its stagger. A single pending lane rather than a queue
## because a single one is all the fight ever has: the checkerboard paints its cells together,
## and only the twin lanes are separated in time.
var _staggered_lane_rect := Rect2()
var _staggered_lane_left := 0.0

## Which parity of the checkerboard lights up next, flipped after every board so that standing
## still is never the answer twice running.
var _checker_parity := 0

## Where the body currently sits in its side-to-side sweep, in radians. See `_step_drift`.
var _sway_phase := START_SWAY_PHASE


func _ready() -> void:
	assert(config != null, "RuntimeError.config is unset: assign a RuntimeErrorConfig.")
	_health = config.max_health
	_attack_left = _interval_for(_phase)


## Called by the floor once the boss is in the arena it will fight in.
func begin(arena: Rect2) -> void:
	_arena = arena
	_body_bounds = arena.grow(-ARENA_INSET)

	_part = PART_SCENE.instantiate()
	add_child(_part)
	# After add_child, always — `global_position` on a parentless node is just its local
	# position, which would land the body at that offset from this controller rather than in
	# the arena. See `MergeConflict._spawn_part`, which paid for this lesson first.
	_part.global_position = _body_bounds.get_center()
	_part.set_tint(BODY_TINT)
	_part.took_damage.connect(_on_part_damaged)

	EventBus.boss_phase_changed.emit(int(_phase))
	_announce_health()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_player = _find_player()
	_step_staggered_lane(delta)
	_step_flash(delta)
	_step_drift(delta)
	_step_attacks(delta)


# --- State --------------------------------------------------------------------


func get_phase() -> Phase:
	return _phase


func get_health() -> float:
	return _health


## The real pool, and what the bar is given. Unlike The Scrap King, this boss's bar does not
## lie: it falls once, monotonically, and reaching zero means the fight is over.
func get_health_ratio() -> float:
	return _health / maxf(config.max_health, 0.001)


## The one body, or null once it is gone. Singular by design — nothing in this fight
## duplicates, so there is no pool to share and no reason for the plural `get_parts` The Scrap
## King needs.
func get_part() -> BossPart:
	return _part if is_instance_valid(_part) else null


# --- Damage -------------------------------------------------------------------


## Every hit arrives here, so there is exactly one place the fight can end. Nothing modifies
## `info.amount` on the way in: README's "remains damageable through all three phases" is the
## whole of this method's policy, and the absence of a multiplier here is that promise.
func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead:
		return

	_health = maxf(_health - info.amount, 0.0)
	EventBus.enemy_damaged.emit(self, DamageInfo.new(info.amount, info.source), _health)
	_announce_health()

	if _health <= 0.0:
		_die()
		return
	_advance_phase()


## Phases are derived from the health that is left rather than stepped one at a time, so a hit
## large enough to cross two thresholds at once lands in the phase it actually earned. The
## Scrap King floors damage at each boundary instead, because a build strong enough to skip a
## phase would skip the feigned death that is the point of that fight. This one has no trick to
## protect: a player who deletes two thirds of the pool in one shot has simply won that much of
## the fight.
func _advance_phase() -> void:
	var next := _phase_for_ratio(get_health_ratio())
	if next != _phase:
		_enter_phase(next)


func _phase_for_ratio(ratio: float) -> Phase:
	if ratio > config.phase_two_at:
		return Phase.SINGLE_LANE
	if ratio > config.phase_three_at:
		return Phase.STAGGERED_LANES
	return Phase.CHECKERBOARD


func _enter_phase(next: Phase) -> void:
	_phase = next
	# Reset, so every phase opens on the lane pattern it is named for rather than on whichever
	# half of the rotation the last one happened to stop at. The new idea goes first.
	_attack_index = 0
	_attack_left = _interval_for(next)
	# Whatever it was winding up is abandoned. A spread fired out of a boss that changed phase
	# mid-telegraph is an attack the player watched it announce and then not perform.
	_telegraph_left = 0.0
	_restore_tint()
	EventBus.boss_phase_changed.emit(int(_phase))


## The line between what survives this boss and what does not is drawn here, and it is the same
## line the whole game draws: **committed attacks resolve, uncommitted ones never happen.**
##
## A lane already painted is left alone. It goes on to strike into an arena the player has
## apparently just won, and it can kill them there — `CompileLane`'s own rule, that a warning
## already given should still cost something to ignore, does not stop applying because the thing
## that gave the warning is dead. Projectiles already in flight are left for the same reason.
##
## A lane that was never painted is dropped instead: `_staggered_lane_left` is a scheduled second
## half that the player has had no warning of, and an unannounced hazard appearing in a won arena
## is the opposite of everything this fight does.
##
## Nothing else is scheduled once this returns, and two independent things see to that: `_is_dead`
## stops `_physics_process` before the attack clock runs at all, and freeing `_part` makes
## `_step_attacks` return on its own. Belt and braces, worth knowing about rather than tidying:
## removing either one alone changes no behaviour and passes every test, which is exactly the kind
## of edit that looks free and leaves the next boss — one that keeps its body for a death
## animation — attacking from beyond the grave. `tests/test_post_boss.gd` asserts the outcome
## rather than either mechanism, so it fails when the last one goes.
func _die() -> void:
	_is_dead = true
	_staggered_lane_left = 0.0

	var where := _part.global_position if is_instance_valid(_part) else global_position
	if is_instance_valid(_part):
		_part.queue_free()

	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


# --- Attack clock -------------------------------------------------------------


## One clock for the whole fight: wait, warn, execute, repeat. The phase decides only which
## patterns are in rotation and how fast they come.
func _step_attacks(delta: float) -> void:
	if not is_instance_valid(_part):
		return

	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		var charge := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
		_part.set_tint(BODY_TINT.lerp(_warning_tint(CompileLane.AMBER), charge))
		if _telegraph_left <= 0.0:
			_execute(_pending_attack)
		return

	_attack_left -= delta
	if _attack_left <= 0.0:
		_begin_attack(_next_attack())


func _begin_attack(attack: Attack) -> void:
	if not _needs_windup(attack):
		_execute(attack)
		return
	_pending_attack = attack
	_telegraph_left = config.telegraph_seconds


## True for the attacks that have no warning of their own. Projectiles leave the instant they
## are fired, so for those the body is what has to go amber first. The lane attacks are
## excluded because a `CompileLane` *is* a telegraph — a windup in front of one would only
## delay the warning the player is meant to read.
func _needs_windup(attack: Attack) -> bool:
	return attack == Attack.SPREAD or attack == Attack.RING or attack == Attack.WALL


func _execute(attack: Attack) -> void:
	match attack:
		Attack.LANE:
			_fire_lane()
		Attack.SPREAD:
			_fire_spread()
		Attack.TWIN_LANES:
			_fire_staggered_lanes()
		Attack.RING:
			_fire_ring()
		Attack.CHECKERBOARD:
			_fire_checkerboard()
		Attack.WALL:
			_fire_wall()

	_attack_left = _interval_for(_phase)
	# Red for an attack that just happened, amber for one that was just *announced* — the same
	# distinction the lanes draw, so the body never contradicts the floor.
	_flash_left = STRIKE_FLASH_SECONDS
	if is_instance_valid(_part):
		_part.set_tint(
			_warning_tint(CompileLane.RED if _needs_windup(attack) else CompileLane.AMBER)
		)


## Strictly alternating within the phase, and authored rather than drawn at random — README
## permits random combinations only once authored ones have proved they cannot erase every safe
## route, and nothing has been played yet that could prove it.
func _next_attack() -> Attack:
	var pair := _attacks_for(_phase)
	var attack: Attack = pair[_attack_index % pair.size()]
	_attack_index += 1
	return attack


## `Array[int]` rather than `Array[Attack]`: GDScript's typed arrays do not take an enum as
## their element type, and enum values are ints.
func _attacks_for(phase: Phase) -> Array[int]:
	var pair: Array[int] = [Attack.CHECKERBOARD, Attack.WALL]
	match phase:
		Phase.SINGLE_LANE:
			pair = [Attack.LANE, Attack.SPREAD]
		Phase.STAGGERED_LANES:
			pair = [Attack.TWIN_LANES, Attack.RING]
	return pair


func _interval_for(phase: Phase) -> float:
	match phase:
		Phase.SINGLE_LANE:
			return config.phase_one_interval
		Phase.STAGGERED_LANES:
			return config.phase_two_interval
		_:
			return config.phase_three_interval


func _step_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_restore_tint()


func _restore_tint() -> void:
	if is_instance_valid(_part):
		_part.set_tint(BODY_TINT)


## `CompileLane`'s colours, scaled to survive being used as a `modulate`. See `WARNING_GAIN`.
## Alpha is pinned rather than scaled with the rest — multiplying it too would push the sprite
## past opaque, which is not a brighter sprite, only an unpredictable one.
func _warning_tint(base: Color) -> Color:
	return Color(base.r * WARNING_GAIN, base.g * WARNING_GAIN, base.b * WARNING_GAIN, 1.0)


# --- Lane patterns ------------------------------------------------------------


## Phase one. One lane, on the row or column the player is standing in.
##
## Aimed rather than random, which is the difference between this and the Compiler that taught
## the player to read it: the Compiler paints somewhere, and half the time it does not concern
## you. This one is always yours, so it always has to be answered — which is the prediction
## README says the whole floor is for. One lane of six leaves five clear.
func _fire_lane() -> void:
	var is_row := randf() < 0.5
	_spawn_lane(_lane_rect(is_row, _player_slot(is_row)))


## Phase two, and README's "two staggered lanes". Staggered in *time*, not merely in place: the
## second is painted `lane_stagger_seconds` after the first, so the two never strike on the
## same frame and the answer is always "leave the first, then leave the second" rather than one
## position that has to survive both at once.
##
## They are also held `MIN_LANE_SLOT_SEPARATION` slots apart, so the step out of the first is
## never a step into the second — and because the second appears while the first is still
## telegraphing, the player is never asked to move twice on one warning.
func _fire_staggered_lanes() -> void:
	var is_row := randf() < 0.5
	var first := _player_slot(is_row)
	var second := _distant_slot(first, _slot_count(is_row))

	_spawn_lane(_lane_rect(is_row, first))
	_staggered_lane_rect = _lane_rect(is_row, second)
	_staggered_lane_left = maxf(config.lane_stagger_seconds, 0.001)


func _step_staggered_lane(delta: float) -> void:
	if _staggered_lane_left <= 0.0:
		return
	_staggered_lane_left -= delta
	if _staggered_lane_left <= 0.0:
		_staggered_lane_left = 0.0
		_spawn_lane(_staggered_lane_rect)


## Phase three, and README's "checkerboard execution zones" — the fairest pattern in the fight,
## by construction rather than by tuning. In a checkerboard every cell that lights up shares
## all four of its edges with cells that do not, so the answer to any board is one step across
## the nearest boundary, and it exists no matter where the player is standing when it appears.
##
## The parity flips afterwards, so the board that follows is the exact negative of this one and
## the player who found a safe cell has to leave it again.
func _fire_checkerboard() -> void:
	var cols := maxi(config.checker_cols, 2)
	var rows := maxi(config.checker_rows, 2)
	var cell := Vector2(_arena.size.x / float(cols), _arena.size.y / float(rows))

	for column: int in cols:
		for row: int in rows:
			if (column + row) % 2 != _checker_parity:
				continue
			_spawn_lane(Rect2(_arena.position + Vector2(float(column), float(row)) * cell, cell))

	_checker_parity = 1 - _checker_parity


func _spawn_lane(rect: Rect2) -> void:
	CompileLane.spawn(
		self, rect, config.lane_damage, config.lane_telegraph_seconds, config.lane_strike_seconds
	)


# --- Lane geometry ------------------------------------------------------------


## One lane's thickness in pixels. Read off `Room.TILE_SIZE` rather than restated, so a lane
## the boss paints lines up with the tiles the room is drawn from exactly as the Compiler's do.
func _lane_thickness() -> float:
	return float(maxi(config.lane_thickness_tiles, 1) * Room.TILE_SIZE)


## How many whole lanes of the given orientation the arena divides into. `is_row` means a lane
## that spans the arena's width and is indexed down its height.
func _slot_count(is_row: bool) -> int:
	var span := _arena.size.y if is_row else _arena.size.x
	return maxi(int(span / _lane_thickness()), 1)


func _lane_rect(is_row: bool, slot: int) -> Rect2:
	var thickness := _lane_thickness()
	var index := float(clampi(slot, 0, _slot_count(is_row) - 1))
	if is_row:
		return Rect2(
			Vector2(_arena.position.x, _arena.position.y + index * thickness),
			Vector2(_arena.size.x, thickness),
		)
	return Rect2(
		Vector2(_arena.position.x + index * thickness, _arena.position.y),
		Vector2(thickness, _arena.size.y),
	)


## The slot the player is standing in. Falls back to the middle of the arena with no player to
## find, so a lane is still a lane rather than a division by an absent position.
func _player_slot(is_row: bool) -> int:
	var slots := _slot_count(is_row)
	if _player == null:
		return slots / 2
	var offset := (
		_player.global_position.y - _arena.position.y if is_row
		else _player.global_position.x - _arena.position.x
	)
	return clampi(int(offset / _lane_thickness()), 0, slots - 1)


## A slot at least `MIN_LANE_SLOT_SEPARATION` away from `from`. Falls back to the furthest slot
## that exists when the arena is too small to honour the separation, which keeps the pair as far
## apart as the geometry allows rather than silently stacking them on top of each other.
func _distant_slot(from: int, slots: int) -> int:
	var candidates: Array[int] = []
	for slot: int in slots:
		if absi(slot - from) >= MIN_LANE_SLOT_SEPARATION:
			candidates.append(slot)
	if candidates.is_empty():
		return 0 if from > slots / 2 else slots - 1
	return candidates[randi() % candidates.size()]


# --- Projectile patterns ------------------------------------------------------


func _fire_spread() -> void:
	var origin := _part.global_position
	var aim := _aim_from(origin)
	var arc := deg_to_rad(config.spread_degrees)
	var count := maxi(config.spread_count, 1)
	for index: int in count:
		var offset := 0.0 if count == 1 else -arc * 0.5 + arc * (float(index) / float(count - 1))
		_spawn(origin, aim.rotated(offset))


## README's "projectile rings that have visible gaps". The gap is a run of adjacent spokes left
## out, rotated to a random bearing rather than placed relative to the player: a gap that always
## opened where they already stood would be a ring that never asked them to move, and one that
## always opened opposite them would be a ring whose answer they could not reach in time.
func _fire_ring() -> void:
	var count := maxi(config.ring_count, 4)
	var gap := clampi(config.ring_gap, 1, count - 2)
	var gap_start := randi() % count
	var origin := _part.global_position

	for index: int in count:
		# Modular, because a gap beginning near the end of the ring wraps around to its start.
		if (index - gap_start + count) % count < gap:
			continue
		_spawn(origin, Vector2.RIGHT.rotated(TAU * float(index) / float(count)))


## README's "projectile walls with a traversable opening". Launched from the edge *furthest*
## from the player, so the wall has the width of the room to cross before it arrives, and the
## opening is placed level with them as it leaves — the answer is to hold a line rather than to
## find one under time pressure.
##
## Spans the full interior rather than `_body_bounds`: a wall that stopped short of the walls
## would leave a clear lane of floor at each end, and an opening nobody needs to use.
func _fire_wall() -> void:
	var count := maxi(config.wall_count, 3)
	var gap := clampi(config.wall_gap, 1, count - 2)
	var gap_start := _wall_gap_index(count, gap)
	var from_left := _player != null and _player.global_position.x >= _arena.get_center().x
	var x := _arena.position.x if from_left else _arena.end.x

	for index: int in count:
		if index >= gap_start and index < gap_start + gap:
			continue
		var y := _arena.position.y + _arena.size.y * float(index) / float(count - 1)
		_spawn(Vector2(x, y), Vector2.RIGHT if from_left else Vector2.LEFT)


## Where the opening goes: level with the player, clamped so it is always a hole inside the
## wall rather than a wall that is simply shorter at one end.
func _wall_gap_index(count: int, gap: int) -> int:
	if _player == null:
		return (count - gap) / 2
	var progress := clampf(
		(_player.global_position.y - _arena.position.y) / maxf(_arena.size.y, 1.0), 0.0, 1.0
	)
	return clampi(int(progress * float(count)) - gap / 2, 0, count - gap)


func _spawn(origin: Vector2, direction: Vector2) -> void:
	if config.shot == null:
		return
	# Deferred, the same call every other spawner in this project makes and for the same
	# reason: registering a new body while the physics server is flushing queries is refused
	# outright, and this project has met that error often enough not to test its luck.
	ProjectileFactory.spawn_configured(
		self, config.shot.spawn_copy(), direction, origin, Teams.Id.ENEMY, self, [], true
	)


# --- Movement -----------------------------------------------------------------


## The body holds station above the player and slides continuously from side to side, which is
## the other half of making it hard to hit — a small target that held still would only be hard
## to hit *once*, until the player settled their aim on it.
##
## A sway rather than a chase or a random walk. A chase closes, and this fight is not won or lost
## at contact range; a random walk is unreadable, and an unreadable boss is an unfair one in a
## fight built entirely on things being readable. A sine is the motion a player can learn to lead
## and still has to keep leading, because it never stops and never repeats where it turns.
##
## Clamped to `_body_bounds` at the end, as everything here is. The clamp only bites when the
## player pins themselves against a wall, and it flattens the sway rather than distorting it —
## which is why this is a sway and not the orbit it started as: an orbit wide enough to matter
## does not fit in a 192-pixel-tall arena, and clamping one collapses it onto the player.
func _step_drift(delta: float) -> void:
	if _player == null or not is_instance_valid(_part):
		return
	# Chill and freeze slow the sway itself as well as the travel, so a frozen boss stops
	# where it is rather than continuing to trace its sine and snapping across the arena the
	# instant it thaws.
	var status_scale := _part.get_status_speed_scale()
	_sway_phase = fposmod(_sway_phase + config.sway_speed * status_scale * delta, TAU)
	var target := _player.global_position + Vector2(
		sin(_sway_phase) * config.sway_amplitude, -config.drift_height
	)
	_part.global_position = _part.global_position.move_toward(
		target, config.move_speed * status_scale * delta
	)
	_part.global_position = _part.global_position.clamp(_body_bounds.position, _body_bounds.end)


# --- Helpers ------------------------------------------------------------------


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

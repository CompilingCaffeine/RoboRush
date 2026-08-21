class_name Orchestrator
extends Boss
## Cloud Operations' boss: one instance that will not stay in one place, and cannot be killed by
## being shot.
##
## Named for the thing that decides where a workload runs, not for what it does — the move it makes
## is a failover, and the game already has an *item* called Failover (a death save). Two things with
## one name would collide in a run's records and put the same word in the HUD for a boss banner and
## a pickup banner, which is the specific confusion `BossEncounter` was created to stop.
##
## The three bosses before this ask the player to **notice** (The Scrap King), to **predict**
## (Runtime Error), and to **keep moving** (Cascade Failure). This one asks them to **be somewhere
## first** — which is the only thing Cloud Operations has been teaching since its start room, and it
## asks in the floor's own words. The boss migrates. That is the same verb the player has spent nine
## rooms performing on the pads, done by the thing they are fighting.
##
## ## Damage does not kill it
##
## The live instance absorbs `pool_per_generation` and then **fails over**: it names a plate, lights
## it, counts down, and moves there — with its pool refilled. Left alone that loop runs forever, and
## no amount of damage per second shortens it by a single second. What damage buys is not progress
## but *events*: it is how the player forces a failover to happen, and a failover is the only thing
## in the fight that can be turned into progress.
##
## The turn is positional. **Stand on the plate it is migrating to and the failover is denied** —
## the load has nowhere to go, the boss loses a generation, and it is stunned and open for
## `denial_stun_seconds`. Three denials and it is done. Miss, and it arrives, heals, and the loop
## starts again exactly where it was.
##
## So the fight is a race with a starting gun the player fires themselves. Shoot to force the
## announcement, read which plate, get there before it does. That is a puzzle with an answer, which
## is what this project's bosses are: The Scrap King's terminals and Merge Conflict's desync are the
## same shape of demand, and each one is a fight the player's build cannot buy their way out of.
##
## ## Why it cannot be beaten by damage, and why that is not unfair
##
## The worst legal build in this game does about 9.4 times the damage per second the enemies are
## written for (`DiminishingReturns`). Every boss before this one is, in the end, a health bar, and a
## build near that ceiling deletes them — which is a fine reward for a good run and a poor final
## exam. Scoring this fight in denials makes it the one boss whose length is set by the player's
## reading of it rather than by their inventory, and it does that *without* a damage cap, an immunity
## phase, or any of the usual apparatus that reads as the game refusing to let you win.
##
## A strong build is still strongly rewarded: it fills the pool faster, so it gets more failovers per
## minute, so it gets more chances to deny one. It shortens the fight by being given more of it. What
## it cannot do is skip the reading.
##
## ## What the player is told, and when
##
## Everything, and early. The plates are drawn from the first frame, so their positions are never
## news. The target lights and ramps for `telegraph_seconds` before anything happens, in the same
## climbing-brightness language `ThermalZone` and `CompileLane` both use — the third floor spent nine
## rooms teaching that a brightening rectangle is a countdown, and this fight is the fourth floor
## cashing that in. Nothing here is random that the player has to react to: the target plate is
## chosen the moment the pool empties and never changes after it is announced.
##
## ## Not a floor-number conditional anywhere
##
## Worth saying because it is the gate this floor exists to pass. This boss is listed in a
## `boss_pool` like the other three, drawn by the same `_draw_boss_encounter`, and it is eligible on
## every floor — a run can meet it on the Help Desk. It reads nothing about which floor it is on. Its
## plates are its own, drawn by this script rather than taken from the room, so it does not require
## the arena to have pads in it and does not break in an arena that has none.

const PART_SCENE := preload("res://scenes/bosses/orchestrator_core.tscn")

## Keeps the body and the plates off the walls, so neither is ever half outside the arena.
const ARENA_INSET := 26.0

## The player's chassis radius, for deciding whether they are standing on a plate. The same five
## pixels `ThermalZone` uses, and — unlike `MigrationPad`, which deliberately does not add it — it
## *is* added here. A pad is a route and should not move a robot that has not committed; a denial is
## a reward and should be granted to a robot that is clearly there.
const PLAYER_RADIUS := 5.0

## The plate colours: idle, and fully lit at the moment a failover lands.
##
## The same spring green `MigrationPad` draws itself in, because it is the same idea and the player
## has been reading it all floor. What differs is which way the brightness runs. A pad is an offer
## and sits quiet; a plate under an incoming failover climbs, and by the language of three floors a
## climbing rectangle is a countdown.
const PLATE_COLOR := Color(0.35, 0.92, 0.58)
const PLATE_IDLE_ALPHA := 0.18
const PLATE_HOT_ALPHA := 0.85

## How bright the plate the boss is currently standing on sits. Between idle and hot, so "this is
## where it is" and "this is where it is going" are never confusable at a glance.
const PLATE_LIVE_ALPHA := 0.42

enum Phase { NOMINAL, DEGRADED, LAST_INSTANCE }

@export var config: OrchestratorConfig

## The live body. One, always — see the class doc. Freed only on death.
var _part: BossPart

## Damage taken since the last failover, against `pool_per_generation`.
var _pool := 0.0

## Generations left. Reaching zero is the end of the fight.
var _generations := 0

## Which plate the boss is standing on, and which one it is migrating to. `-1` for no target, which
## is also how "not currently telegraphing" is expressed — there is no separate flag, because two
## pieces of state saying the same thing is two pieces of state that can disagree.
var _plate := 0
var _target := -1

## Seconds left on the telegraph, and on the stun a denial buys.
var _telegraph_left := 0.0
var _stun_left := 0.0

var _volley_left := 0.0
var _is_dead := false
var _phase := Phase.NOMINAL

var _arena: Rect2
var _body_bounds: Rect2
var _plates: Array[Vector2] = []
var _player: Node2D


func _ready() -> void:
	assert(config != null, "Orchestrator.config is unset: assign an OrchestratorConfig.")
	_generations = config.generations
	_pool = 0.0


func begin(arena: Rect2) -> void:
	_arena = arena
	_body_bounds = arena.grow(-ARENA_INSET)
	_plates = _plate_positions()

	_part = PART_SCENE.instantiate()
	add_child(_part)
	# After `add_child`, always. `global_position` on a parentless node is only its local position,
	# which would put the body at that offset from this controller instead of in the arena — the
	# lesson `MergeConflict._spawn_part` paid for and `ThermalZone.spawn` paid for again.
	_part.global_position = _plates[_plate]
	_part.took_damage.connect(_on_part_damaged)

	# A full interval before the first volley, so the opening second of the fight is the boss
	# standing there being looked at. Every boss in this game gets that beat.
	_volley_left = config.volley_interval

	EventBus.boss_phase_changed.emit(int(_phase))
	_announce_health()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_player = _find_player()

	_stun_left = maxf(_stun_left - delta, 0.0)
	if _stun_left > 0.0:
		# Stunned: no volleys, no telegraph progress, nothing. The window a denial buys has to be
		# unambiguously a window, or denying one stops being worth the run across the room.
		queue_redraw()
		return

	_step_failover(delta)
	_step_volleys(delta)
	queue_redraw()


# --- State --------------------------------------------------------------------


func get_phase() -> Phase:
	return _phase


## Generations left, from `config.generations` down to zero. The fight's real progress bar.
func get_generations_left() -> int:
	return _generations


## What the HUD's boss bar shows: generations left, with the current pool filling the segment in
## between so a player pushing toward the next failover can see it coming.
##
## Deliberately not "health", because there is none — see the class doc. The bar still has to move
## under fire or the fight reads as broken, so what it reports is progress toward the next *event*
## rather than toward death.
func get_health_ratio() -> float:
	if config.generations <= 0:
		return 0.0
	var pool_ratio := clampf(_pool / maxf(config.pool_per_generation, 0.001), 0.0, 1.0)
	var whole := float(_generations - 1) + (1.0 - pool_ratio)
	return clampf(whole / float(config.generations), 0.0, 1.0)


## Which plate the boss is standing on.
func get_plate() -> int:
	return _plate


## Which plate it is migrating to, or -1 when it is not migrating.
func get_target_plate() -> int:
	return _target


## Where each plate is, in global coordinates. For the suite and for anything that wants to draw one.
func get_plate_positions() -> Array[Vector2]:
	return _plates.duplicate()


## The square a plate covers, in global coordinates.
func get_plate_rect(index: int) -> Rect2:
	if index < 0 or index >= _plates.size():
		return Rect2()
	var side := config.plate_size
	return Rect2(_plates[index] - Vector2(side, side) * 0.5, Vector2(side, side))


func is_telegraphing() -> bool:
	return _target >= 0


func is_stunned() -> bool:
	return _stun_left > 0.0


func get_parts() -> Array[BossPart]:
	var out: Array[BossPart] = []
	if is_instance_valid(_part):
		out.append(_part)
	return out


# --- The failover -------------------------------------------------------------


## Damage fills the pool and nothing else. When it is full the boss commits to a plate.
##
## Committing here rather than when the telegraph ends is the whole of the fight being fair: the
## target is decided *before* the player is told, and cannot change after. A boss that re-picked on
## resolution would make the run across the room pointless, and would do it invisibly.
func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead:
		return
	_pool += info.amount
	_announce_health()
	if _pool < config.pool_per_generation or is_telegraphing():
		return
	_begin_failover()


func _begin_failover() -> void:
	_pool = config.pool_per_generation
	_target = _next_plate()
	_telegraph_left = config.telegraph_seconds
	# Faster fire from the moment it is announced, so crossing the room costs something.
	_volley_left = minf(_volley_left, config.telegraph_volley_interval)


func _step_failover(delta: float) -> void:
	if not is_telegraphing():
		return
	_telegraph_left -= delta
	if _telegraph_left > 0.0:
		return

	var denied := _player_is_on(_target)
	var plate := _target
	_target = -1
	_telegraph_left = 0.0

	if denied:
		_deny(plate)
	else:
		_migrate(plate)


## The player was standing on the destination. The load has nowhere to go.
func _deny(_plate_index: int) -> void:
	_generations -= 1
	_pool = 0.0
	_stun_left = config.denial_stun_seconds
	_announce_health()
	AudioManager.play_sfx(&"boss_phase")

	if _generations <= 0:
		_die()
		return

	_advance_phase()


## Nobody was there. It arrives, and the pool it had filled is gone.
func _migrate(plate_index: int) -> void:
	_plate = plate_index
	_pool = 0.0
	if is_instance_valid(_part):
		_part.global_position = _plates[_plate]
	_announce_health()
	AudioManager.play_sfx(&"migrate", 0.04)


## Which plate to fail over to: any but the one it is on.
##
## Deliberately deterministic — the next plate round the ring, not a random one. The fight is a race
## to a destination, and a race the player can learn the shape of is a race worth running twice. A
## random target would make the same fight a coin toss about how far they had to go.
func _next_plate() -> int:
	if _plates.size() <= 1:
		return _plate
	return (_plate + 1) % _plates.size()


func _player_is_on(plate_index: int) -> bool:
	if _player == null:
		return false
	return get_plate_rect(plate_index).grow(PLAYER_RADIUS).has_point(_player.global_position)


func _advance_phase() -> void:
	var next := Phase.NOMINAL
	if _generations == 1:
		next = Phase.LAST_INSTANCE
	elif _generations < config.generations:
		next = Phase.DEGRADED
	if next == _phase:
		return
	_phase = next
	EventBus.boss_phase_changed.emit(int(_phase))


# --- Attacks ------------------------------------------------------------------


func _step_volleys(delta: float) -> void:
	_volley_left -= delta
	if _volley_left > 0.0:
		return
	_volley_left = config.telegraph_volley_interval if is_telegraphing() else config.volley_interval
	_fire_spread()


func _fire_spread() -> void:
	if _player == null or config.shot == null or not is_instance_valid(_part):
		return
	var origin := _part.global_position
	var aim := (_player.global_position - origin).normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT

	var count := maxi(config.spread_count, 1)
	var spread := deg_to_rad(config.spread_degrees)
	var step := spread / float(count) if count > 1 else 0.0
	var start := -spread * 0.5 + step * 0.5
	for index: int in count:
		_spawn(origin, aim.rotated(start + step * float(index)))


func _spawn(origin: Vector2, direction: Vector2) -> void:
	# Deferred, the call every spawner in this project makes: registering a body while the physics
	# server is flushing queries is refused outright.
	ProjectileFactory.spawn_configured(
		self, config.shot.spawn_copy(), direction, origin, Teams.Id.ENEMY, self, [], true
	)


# --- Geometry -----------------------------------------------------------------


## The plates, spread evenly around the arena's centre.
##
## Laid out on an ellipse matched to the arena's own proportions rather than a circle, because a
## 416x192 room is more than twice as wide as it is tall and a circle inside it wastes the width —
## which is the width the player has to cross. `CascadeFailure` places its ring the same way for the
## same reason.
##
## The first plate is at the top, so the layout is the same every fight and a returning player knows
## where the three of them are before the first one lights.
func _plate_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var centre := _body_bounds.get_center()
	var radius := _body_bounds.size * 0.5 * config.plate_radius
	var count := maxi(config.plate_count, 1)
	for index: int in count:
		var angle := -PI * 0.5 + TAU * float(index) / float(count)
		out.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return out


func _die() -> void:
	_is_dead = true
	_target = -1
	var where := _body_bounds.get_center()
	if is_instance_valid(_part):
		where = _part.global_position
		_part.queue_free()
	_part = null
	# `_physics_process` returns on `_is_dead`, so without this the last lit plate would stay
	# painted on an arena with no boss in it — the same reason `CascadeFailure._die` redraws.
	queue_redraw()
	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D


func _draw() -> void:
	if _plates.is_empty():
		return
	for index: int in _plates.size():
		var rect := get_plate_rect(index)
		# Drawn in local space: this node sits at the arena's origin only by accident of the scene
		# it was added to, so every plate rect is converted rather than assumed.
		var local := Rect2(rect.position - global_position, rect.size)

		var alpha := PLATE_IDLE_ALPHA
		if index == _target:
			# The countdown. Ramps from idle to hot across the telegraph, so the plate is brightest
			# on the frame the failover lands — the same direction of travel as a thermal zone
			# filling, which is the language this floor's player already reads.
			var progress := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
			alpha = lerpf(PLATE_IDLE_ALPHA, PLATE_HOT_ALPHA, progress)
		elif index == _plate:
			alpha = PLATE_LIVE_ALPHA

		draw_rect(local, Color(PLATE_COLOR.r, PLATE_COLOR.g, PLATE_COLOR.b, alpha * 0.5))
		draw_rect(local, Color(PLATE_COLOR.r, PLATE_COLOR.g, PLATE_COLOR.b, alpha), false, 1.0)

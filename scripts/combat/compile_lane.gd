class_name CompileLane
extends Node2D
## The shared telegraph-then-strike hazard behind Floor 2's "compile lane": a rectangle that
## fades in amber, waits long enough to read, then flashes red and checks for the player
## once. Deliberately built to take a plain `Rect2` rather than a row/column index, so the
## Compiler enemy and the eventual Runtime Error boss (a single lane, staggered lanes, then
## checkerboard zones across its three phases) can each describe their own geometry and still
## share this one implementation instead of three.
##
## Damage/overlap follows Firewall Node's convention, not `Targeting`'s: every existing
## enemy-attack-hits-player check in this project finds the player directly and measures the
## exact geometry that was drawn, because `Targeting`'s group-walk is built for the *player's*
## weapon finding *enemies*, not the other way round, and there is only ever one player to
## find.
##
## Parented to the floor's projectile container rather than to whatever spawned it, so a lane
## already telegraphing still resolves even if the enemy or boss that queued it dies in the
## meantime — a warning already given should still cost something to ignore.

enum State { TELEGRAPH, STRIKE }

## Telegraph ramps this in from zero alpha; strike is a flat flash at full alpha.
const AMBER := Color(0.95, 0.72, 0.24)
const RED := Color(1.0, 0.42, 0.42)
const STRIKE_ALPHA := 0.85

## The player's collision radius, from player.tscn. Duplicated rather than read off the
## player, same call Firewall Node already made for the identical reason (see its own
## PLAYER_RADIUS) — grown onto the lane's rect so the player's body, not just its exact
## centre point, decides whether they were caught.
const PLAYER_RADIUS := 5.0

var _size := Vector2.ZERO
var _damage := 0.0
var _telegraph_seconds := 0.0
var _telegraph_left := 0.0
var _strike_left := 0.0
var _state := State.TELEGRAPH


## Spawns and configures a lane at `rect`. `spawner` is only used to find the floor's
## projectile container (see class doc for why the lane isn't parented to it directly) —
## falls back to the current scene so a test arena with no registered container still works,
## the same fallback `ProjectileFactory` uses.
static func spawn(
	spawner: Node, rect: Rect2, damage: float, telegraph_seconds: float, strike_seconds: float
) -> CompileLane:
	if not spawner.is_inside_tree():
		return null
	var tree := spawner.get_tree()
	var container := tree.get_first_node_in_group(ProjectileFactory.CONTAINER_GROUP)
	if container == null:
		container = tree.current_scene

	var lane := CompileLane.new()
	lane.global_position = rect.position
	lane._size = rect.size
	lane._damage = damage
	lane._telegraph_seconds = maxf(telegraph_seconds, 0.001)
	lane._telegraph_left = lane._telegraph_seconds
	lane._strike_left = maxf(strike_seconds, 0.001)
	container.add_child(lane)
	return lane


## Physics-timed rather than `_process`-timed, unlike the purely cosmetic `ChainZap`: this
## node's timer decides real damage, and every other timing-driven combat system in this
## project (`MergeConflict`, `Enemy`, `HealthComponent`) runs on the physics clock so it
## stays in lockstep with the rest of the fixed-timestep simulation.
func _physics_process(delta: float) -> void:
	match _state:
		State.TELEGRAPH:
			_telegraph_left -= delta
			if _telegraph_left <= 0.0:
				_enter_strike()
			else:
				queue_redraw()
		State.STRIKE:
			_strike_left -= delta
			if _strike_left <= 0.0:
				queue_free()


func _enter_strike() -> void:
	_state = State.STRIKE
	queue_redraw()
	# Unconditional, same shape as `explosion_triggered`: damage is already resolved below
	# by the time anything reacts to this, so presentation never has to ask what happened.
	EventBus.compile_lane_executed.emit(Rect2(global_position, _size))
	_strike_player()


func _strike_player() -> void:
	if _damage <= 0.0:
		return
	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
	if player == null:
		return

	var local_rect := Rect2(Vector2.ZERO, _size).grow(PLAYER_RADIUS)
	if not local_rect.has_point(to_local(player.global_position)):
		return

	var health := HealthComponent.find_on(player)
	if health == null:
		return

	var offset := player.global_position - (global_position + _size * 0.5)
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	health.apply_damage(DamageInfo.new(_damage, self, direction))


func _draw() -> void:
	var charge := 1.0 - clampf(_telegraph_left / _telegraph_seconds, 0.0, 1.0)
	var color := AMBER if _state == State.TELEGRAPH else RED
	var alpha := charge * 0.55 if _state == State.TELEGRAPH else STRIKE_ALPHA
	draw_rect(Rect2(Vector2.ZERO, _size), Color(color.r, color.g, color.b, alpha))

class_name Deadlock
extends Enemy
## The one enemy on the floor that cannot be answered by aiming, and the only one whose
## answer is a *place* rather than a direction.
##
## It locks a tether onto the player the moment it can see them, holds it amber for
## `acquire_seconds`, and then bleeds integrity for as long as the line survives. There are
## exactly two ways to cut it — put something solid between the two of you, or get further
## away than `tether_range` — and the room decides which is cheaper. That is the whole
## enemy: it converts the obstacles Development's rooms are already full of from scenery
## into the thing you are running towards.
##
## Two answers rather than one on purpose. Cover alone would make this enemy unfair in the
## rooms with the thinnest pillars and trivial in the rooms built around a server ring, and
## a floor generator that picks templates cannot promise which room it lands in. Distance is
## the answer that always exists; cover is the answer that is quicker when the room offers
## it.
##
## It speaks the floor's warning language rather than one of its own: `CompileLane.AMBER`
## while it is acquiring, `CompileLane.RED` once it is draining, taken from that class
## directly so amber-means-warning and red-means-happening cannot drift apart between the
## enemy that paints rectangles and the enemy that draws a line.

enum State {
	## No line. Closing on the player, or waiting out `reacquire_delay`.
	SEARCHING,
	## Line drawn, amber, harmless. The player's window.
	ACQUIRING,
	## Line red, ticking down integrity.
	DRAINING,
}

## The robot's collision radius, from player.tscn. Duplicated for the reason Firewall Node
## and CompileLane both duplicate it — see `FirewallNode.PLAYER_RADIUS`.
const PLAYER_RADIUS := 5.0

## Colour the body brightens toward while it holds a live tether, so the source of the line
## is never ambiguous in a room with two of them.
const LOCKED_TINT := Color(1.8, 0.9, 0.9)

var _tuning: DeadlockConfig
var _state := State.SEARCHING

## Counts up inside ACQUIRING, and counts down between drain ticks inside DRAINING.
var _state_time := 0.0

## Seconds left before it may lock on again. Only nonzero in SEARCHING.
var _lockout := 0.0

@onready var _tether: Line2D = %Tether


func _on_ready() -> void:
	_tuning = config as DeadlockConfig
	assert(_tuning != null, "Deadlock.config must be a DeadlockConfig.")
	_tether.width = _tuning.tether_width
	_clear_tether()


func _act(delta: float) -> Vector2:
	match _state:
		State.SEARCHING:
			_lockout = maxf(_lockout - delta, 0.0)
			if _lockout <= 0.0 and _can_hold_tether():
				_state = State.ACQUIRING
				_state_time = 0.0
		State.ACQUIRING:
			if not _can_hold_tether():
				_break_tether()
			else:
				_state_time += delta
				if _state_time >= _tuning.acquire_seconds:
					_state = State.DRAINING
					# Zero rather than a full interval: the first tick lands as the line
					# turns red, so going red and being hurt are one readable event.
					_state_time = 0.0
		State.DRAINING:
			if not _can_hold_tether():
				_break_tether()
			else:
				_state_time -= delta
				if _state_time <= 0.0:
					_drain()
					_state_time = _tuning.drain_interval

	_draw_tether()
	return _approach()


func get_state() -> State:
	return _state


func is_tethered() -> bool:
	return _state != State.SEARCHING


## Whether the line could exist right now: a living player, close enough, and nothing solid
## in between. Asked every frame in every tethered state rather than only on acquisition,
## because "the line breaks the moment either condition stops holding" is the promise the
## player is being asked to act on.
func _can_hold_tether() -> bool:
	if _player == null:
		return false
	if global_position.distance_to(_player.global_position) > _tuning.tether_range:
		return false
	return has_line_of_sight(_player.global_position)


func _break_tether() -> void:
	_state = State.SEARCHING
	_state_time = 0.0
	_lockout = _tuning.reacquire_delay


func _drain() -> void:
	if _player == null:
		return
	var health := HealthComponent.find_on(_player)
	if health == null:
		return
	var offset := _player.global_position - global_position
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	# No knockback: being shoved along the tether would push the player either straight into
	# cover or straight out of range, and the point is that they choose.
	health.apply_damage(DamageInfo.new(_tuning.drain_damage, self, direction, 0.0))


## Draws exactly the line that `_can_hold_tether` just validated — it ends at the player
## because it only exists when nothing is in the way, so there is no case where a tether is
## drawn through a wall and no reach to clip.
func _draw_tether() -> void:
	if _state == State.SEARCHING or _player == null:
		_clear_tether()
		return

	_tether.points = PackedVector2Array([Vector2.ZERO, to_local(_player.global_position)])

	if _state == State.ACQUIRING:
		# Ramps in over the acquire window, so the tether is faintest at the moment it is
		# cheapest to break and unmissable by the moment it is not.
		var charge := clampf(_state_time / maxf(_tuning.acquire_seconds, 0.001), 0.0, 1.0)
		_tether.default_color = Color(
			CompileLane.AMBER.r, CompileLane.AMBER.g, CompileLane.AMBER.b, 0.25 + 0.6 * charge
		)
		tint_toward(LOCKED_TINT, charge * 0.5)
		return

	_tether.default_color = Color(
		CompileLane.RED.r, CompileLane.RED.g, CompileLane.RED.b, CompileLane.STRIKE_ALPHA
	)
	tint_toward(LOCKED_TINT, 1.0)


func _clear_tether() -> void:
	_tether.points = PackedVector2Array()
	tint_toward(LOCKED_TINT, 0.0)


## Closes to `preferred_range` and holds there. It never rushes: an enemy whose attack is a
## deadline should be somewhere the player can get away from, and one that chased at speed
## would make the distance answer impossible and leave only cover.
func _approach() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	var offset := _player.global_position - global_position
	var distance := offset.length()
	if is_zero_approx(distance):
		return Vector2.ZERO
	var heading := offset / distance

	if distance > config.preferred_range + config.range_tolerance:
		return heading * config.move_speed
	if distance < config.preferred_range - config.range_tolerance:
		return -heading * config.move_speed
	return Vector2.ZERO

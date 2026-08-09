class_name DashController
extends Node
## Owns dash state: the active dash window, charges, recharge timing, and the
## invulnerability window.
##
## Holds no opinion about how a dash looks or who is dashing. It reports state via
## local signals; the owning actor decides whether to rebroadcast on the EventBus.
## Like MotionController it never touches the tree, so it is testable headless.

## Emitted the moment a dash begins. `direction` is normalised.
signal dash_started(direction: Vector2)

## Emitted when the dash movement window closes.
signal dash_ended()

## Floor for dash_duration when deriving speed, so a misconfigured resource
## cannot divide by zero.
const MIN_DASH_DURATION := 0.001

## True while the dash is actively moving the body.
var is_dashing := false

## Direction of the current or most recent dash.
var direction := Vector2.RIGHT

## Charges ready to spend right now.
var charges_available := 0

var _config: PlayerConfig
var _max_charges := 1
var _dash_time_left := 0.0
var _recharge_time_left := 0.0
var _invulnerable_time_left := 0.0

## Item-driven multiplier on `PlayerConfig.dash_cooldown`. One until something changes it.
var _cooldown_scale := 1.0


func setup(config: PlayerConfig) -> void:
	_config = config
	_max_charges = maxi(config.dash_charges, 1)
	charges_available = _max_charges


## Advances all dash timers. Call once per physics frame, before try_start, so a
## dash beginning this frame gets its full duration.
func step(delta: float) -> void:
	_invulnerable_time_left = maxf(_invulnerable_time_left - delta, 0.0)

	if is_dashing:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			_dash_time_left = 0.0
			is_dashing = false
			dash_ended.emit()

	_tick_recharge(delta)


## Spends a charge and begins a dash. `requested_direction` may be zero, in which
## case the previous dash direction is reused. Returns false if no dash was
## possible, leaving all state untouched.
func try_start(requested_direction: Vector2) -> bool:
	if not can_dash():
		return false

	if not requested_direction.is_zero_approx():
		direction = requested_direction.normalized()

	charges_available -= 1
	is_dashing = true
	_dash_time_left = _config.dash_duration
	_invulnerable_time_left = _config.dash_invulnerability

	# Only kick off the recharge clock if it is not already running, so spending a
	# second charge mid-cooldown does not restart the first charge's timer.
	if _recharge_time_left <= 0.0:
		_recharge_time_left = get_cooldown()

	dash_started.emit(direction)
	return true


## Sets the item-granted charges on top of the config's own, replacing whatever the last
## call set rather than accumulating.
##
## This used to be `add_charges`, called once per pickup, which was fine for as long as
## every item that touched dash charges *granted* one. Legacy Runtime takes one away, and an
## incremental applier cannot express that safely: the player's total would depend on the
## order items arrived and on how many times the owner happened to reapply them. Recomputing
## from the whole inventory is what `Player._apply_item_stats` already promises in its own
## doc comment; dash charges were the one aggregate not keeping that promise.
##
## Floored at one. A robot that cannot dash at all is not a hindrance, it is a different and
## much worse game — so Legacy Runtime's −1 costs a Backup Battery its charge and otherwise
## costs nothing, and the cooldown is where that item does its real damage.
func set_bonus_charges(bonus: int) -> void:
	var previous := _max_charges
	_max_charges = maxi(_config.dash_charges + bonus, 1)
	# A raised ceiling hands the new charge over immediately, so Backup Battery is usable
	# the moment it is picked up rather than after a cooldown the player did not cause.
	var gained := maxi(_max_charges - previous, 0)
	charges_available = clampi(charges_available + gained, 0, _max_charges)


## Multiplies the configured cooldown. Legacy Runtime's whole effect.
func set_cooldown_scale(scale: float) -> void:
	_cooldown_scale = maxf(scale, 0.01)


func get_cooldown() -> float:
	return _config.dash_cooldown * _cooldown_scale


func can_dash() -> bool:
	return not is_dashing and charges_available > 0


func is_invulnerable() -> bool:
	return _invulnerable_time_left > 0.0


## Pixels per second needed to cover dash_distance within dash_duration.
func get_speed() -> float:
	return _config.dash_distance / maxf(_config.dash_duration, MIN_DASH_DURATION)


## Velocity to apply for this physics frame, for a caller that multiplies by `delta`.
##
## The dash window almost never divides evenly into frames, so the last frame has less
## than a full step of dash left in it. Moving at full speed anyway overshoots by up to
## one frame of travel — the configured 70px dash covered 75px at 60Hz and 83px at 30Hz,
## and how far you dashed depended on the refresh rate. Scaling the final frame by the
## fraction of it the dash actually occupies makes the distance exact and frame-rate
## independent. Call after step(), which is what leaves `_dash_time_left` holding the
## travel still owed before this frame moves.
func get_frame_velocity(delta: float) -> Vector2:
	if not is_dashing or delta <= 0.0:
		return Vector2.ZERO
	return direction * get_speed() * (minf(delta, _dash_time_left) / delta)


func get_max_charges() -> int:
	return _max_charges


## Seconds until the next charge refills; zero when charges are already full.
func get_recharge_remaining() -> float:
	return _recharge_time_left


func _tick_recharge(delta: float) -> void:
	if charges_available >= _max_charges:
		_recharge_time_left = 0.0
		return

	_recharge_time_left -= delta
	if _recharge_time_left > 0.0:
		return

	charges_available += 1
	if charges_available < _max_charges:
		# Carry the overshoot (a negative value) into the next charge so refills
		# stay evenly paced instead of drifting by up to one frame each time.
		_recharge_time_left = get_cooldown() + _recharge_time_left
	else:
		_recharge_time_left = 0.0

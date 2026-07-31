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
		_recharge_time_left = _config.dash_cooldown

	dash_started.emit(direction)
	return true


func can_dash() -> bool:
	return not is_dashing and charges_available > 0


func is_invulnerable() -> bool:
	return _invulnerable_time_left > 0.0


## Pixels per second needed to cover dash_distance within dash_duration.
func get_speed() -> float:
	return _config.dash_distance / maxf(_config.dash_duration, MIN_DASH_DURATION)


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
		_recharge_time_left = _config.dash_cooldown + _recharge_time_left
	else:
		_recharge_time_left = 0.0

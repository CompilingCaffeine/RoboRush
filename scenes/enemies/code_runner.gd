class_name CodeRunner
extends Enemy
## README's Floor 2 plan: "Strafes across sight lines and fires while moving, forcing
## sustained tracking."
##
## The one enemy in the game that fires while its own velocity is nonzero. Ticket Bot holds
## still to fire; Pop Up Drone is stationary the whole time it is visible; this has no
## stop-to-fire gating at all — whenever the weapon is off cooldown and it can see the
## player, it fires, whatever the strafe is doing that frame. `WeaponController.try_fire`
## never reads the caller's velocity, so nothing about firing needed to change; only the
## movement is new.

var _tuning: CodeRunnerConfig
var _strafe_sign := 1.0
var _direction_left := 0.0


func _on_ready() -> void:
	_tuning = config as CodeRunnerConfig
	assert(_tuning != null, "CodeRunner.config must be a CodeRunnerConfig.")
	_direction_left = _tuning.direction_hold_seconds
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0


func _act(delta: float) -> Vector2:
	_update_fire()
	return _update_movement(delta)


## Opportunistic rather than telegraphed: the point of this enemy is that the player never
## gets a windup to wait out, only a moving target to track.
func _update_fire() -> void:
	if _player == null or _weapon == null or not _weapon.can_fire():
		return
	if not has_line_of_sight(_player.global_position):
		return
	_weapon.try_fire(global_position, (_player.global_position - global_position).normalized())


func _update_movement(delta: float) -> Vector2:
	_direction_left -= delta
	if _direction_left <= 0.0:
		_strafe_sign = -_strafe_sign
		_direction_left = _tuning.direction_hold_seconds

	if _player == null:
		return Vector2.ZERO

	var offset := _player.global_position - global_position
	var distance := offset.length()
	if is_zero_approx(distance):
		return Vector2.ZERO
	var heading := offset / distance

	# Radial term holds range the same way Ticket Bot's _act does; the tangential term,
	# perpendicular to the aim line, is the entire reason this enemy exists.
	var radial := Vector2.ZERO
	if distance > config.preferred_range + config.range_tolerance:
		radial = heading
	elif distance < config.preferred_range - config.range_tolerance:
		radial = -heading

	var desired := radial + heading.orthogonal() * _strafe_sign
	if desired.is_zero_approx():
		return Vector2.ZERO
	return desired.normalized() * config.move_speed

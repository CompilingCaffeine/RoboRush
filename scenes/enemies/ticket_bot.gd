class_name TicketBot
extends Enemy
## Spec section 15: "Moves toward the player and fires slow single shots."
##
## Its purpose is basic pressure and teaching the player to read a telegraph, so its
## one behaviour is range-keeping. It closes to `preferred_range` and holds there,
## which is what stops a shooting enemy from simply walking into the player's face and
## turning a ranged threat into a melee one.
##
## Uses the same WeaponController and HealthComponent as the player. Nothing here
## knows how projectiles work.

## Colour the sprite brightens toward as the shot charges.
const CHARGE_TINT := Color(1.8, 1.1, 1.1)

var _telegraph_left := 0.0


func _on_ready() -> void:
	_telegraph_left = config.telegraph_seconds


## Advance when too far, back off when too close, hold inside the tolerance band.
func _act(delta: float) -> Vector2:
	_update_attack(delta)
	_update_tint()

	if _player == null:
		return Vector2.ZERO

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	if is_zero_approx(distance):
		return Vector2.ZERO

	var heading := to_player / distance
	if distance > config.preferred_range + config.range_tolerance:
		return heading * config.move_speed
	if distance < config.preferred_range - config.range_tolerance:
		return -heading * config.move_speed
	return Vector2.ZERO


## The telegraph only runs while the weapon is actually off cooldown, so the windup
## the player learns to read is always immediately followed by a shot.
func _update_attack(delta: float) -> void:
	if _player == null or not has_line_of_sight(_player.global_position):
		_telegraph_left = config.telegraph_seconds
		return

	if not _weapon.can_fire():
		_telegraph_left = config.telegraph_seconds
		return

	_telegraph_left -= delta
	if _telegraph_left > 0.0:
		return

	var aim := (_player.global_position - global_position).normalized()
	_weapon.try_fire(global_position, aim)
	_telegraph_left = config.telegraph_seconds


func _update_tint() -> void:
	var charge := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
	tint_toward(CHARGE_TINT, charge * 0.8)

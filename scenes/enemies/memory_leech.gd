class_name MemoryLeech
extends Enemy
## Spec section 15: "Moves quickly toward the player, stops briefly before charging, and
## deals contact damage."
##
## Its purpose is to force movement, and the way it does that is by *committing*. It picks
## a direction while standing still, and then it goes there whatever the player does — so
## the player is being asked to read an intention and step out of it, rather than to
## outrun something that steers. A leech that homed during its charge would be unfair; a
## leech that never charged would be furniture.
##
## The contact damage is `contact_damage` on its config and is resolved by the base class,
## because "touching the player hurts" is not a Memory Leech idea — it is a property any
## enemy may have.

## Colour it brightens toward while committing to a charge. The only warning the player
## gets, so it is the strongest tint in the game.
const WINDUP_TINT := Color(2.2, 1.0, 2.2)

enum Phase {
	## Closing on the player at ordinary speed.
	CHASING,
	## Stopped, committing to a direction.
	WINDING_UP,
	## Committed and moving.
	CHARGING,
	## Slow and vulnerable.
	RECOVERING,
}

var _tuning: MemoryLeechConfig
var _phase := Phase.CHASING
var _phase_left := 0.0

## Locked in at the end of the windup. The charge does not steer.
var _charge_direction := Vector2.RIGHT


func _on_ready() -> void:
	_tuning = config as MemoryLeechConfig
	assert(_tuning != null, "MemoryLeech.config must be a MemoryLeechConfig.")


func _act(delta: float) -> Vector2:
	_phase_left -= delta

	match _phase:
		Phase.CHASING:
			return _chase()
		Phase.WINDING_UP:
			var charge := 1.0 - clampf(_phase_left / maxf(_tuning.windup_seconds, 0.001), 0.0, 1.0)
			tint_toward(WINDUP_TINT, charge)
			if _phase_left <= 0.0:
				_enter(Phase.CHARGING, _tuning.charge_seconds)
			# Deliberately still: the stop is what makes the charge readable.
			return Vector2.ZERO
		Phase.CHARGING:
			if _phase_left <= 0.0:
				tint_toward(WINDUP_TINT, 0.0)
				_enter(Phase.RECOVERING, _tuning.recover_seconds)
				return Vector2.ZERO
			return _charge_direction * _tuning.charge_speed
		Phase.RECOVERING:
			if _phase_left <= 0.0:
				_enter(Phase.CHASING, 0.0)
			return Vector2.ZERO

	return Vector2.ZERO


func get_phase() -> Phase:
	return _phase


func _enter(phase: Phase, seconds: float) -> void:
	_phase = phase
	_phase_left = seconds


## Runs at the player, and commits the moment it is close enough. Line of sight is
## required to start a charge but not to chase, so it will follow the player around a
## pillar rather than winding up at a wall.
func _chase() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	var offset := _player.global_position - global_position
	var distance := offset.length()
	if is_zero_approx(distance):
		return Vector2.ZERO

	var heading := offset / distance
	if distance <= _tuning.charge_trigger_range and has_line_of_sight(_player.global_position):
		_charge_direction = heading
		_enter(Phase.WINDING_UP, _tuning.windup_seconds)
		return Vector2.ZERO

	return heading * config.move_speed

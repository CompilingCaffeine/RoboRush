class_name PlayerInput
extends Node
## Translates named input actions into movement and aim intent.
##
## Nothing else in the player reads Input directly. That keeps rebinding, gamepad
## handling, and input buffering in one place, and satisfies spec section 5:
## input goes through named actions, never hard coded keys.
##
## The component is intentionally ignorant of the scene tree — the caller supplies
## the player's position and the cursor's world position — so it can be driven
## from a test without a viewport.

## Right stick magnitude required to take aim control away from the mouse. Above
## the action deadzone so a resting stick never fights the cursor.
const GAMEPAD_AIM_THRESHOLD := 0.25

## Normalised movement intent. Zero when no direction is held.
var move_vector := Vector2.ZERO

## Normalised aim direction. Never zero: it holds its last value when the player
## has neither moved the mouse nor pushed the right stick.
var aim_direction := Vector2.RIGHT

## True while the right stick is driving the aim instead of the cursor.
var is_aiming_with_gamepad := false

var _config: PlayerConfig
var _dash_buffer_left := 0.0


func setup(config: PlayerConfig) -> void:
	_config = config


## Reads this frame's input. `origin` and `cursor_world_position` must both be in
## world space; the caller owns the viewport/camera maths.
func poll(delta: float, origin: Vector2, cursor_world_position: Vector2) -> void:
	# get_vector already normalises, which handles the diagonal-speed requirement
	# from spec section 6.1 without a special case.
	move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_update_aim(origin, cursor_world_position)

	_dash_buffer_left = maxf(_dash_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed("dash"):
		_dash_buffer_left = _config.dash_input_buffer


## True while a recent dash press is still waiting to be honoured.
func has_dash_request() -> bool:
	return _dash_buffer_left > 0.0


## Clears the queued dash press. Call this only once the dash actually starts, so
## a press made with no charges available survives until one refills.
func consume_dash_request() -> void:
	_dash_buffer_left = 0.0


func _update_aim(origin: Vector2, cursor_world_position: Vector2) -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() >= GAMEPAD_AIM_THRESHOLD:
		is_aiming_with_gamepad = true
		aim_direction = stick.normalized()
		return

	is_aiming_with_gamepad = false
	var to_cursor := cursor_world_position - origin
	# Standing exactly on the cursor would otherwise zero the aim and snap the
	# cannon to a default angle.
	if not to_cursor.is_zero_approx():
		aim_direction = to_cursor.normalized()

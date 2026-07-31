class_name MotionController
extends Node
## Accelerates a velocity toward the requested movement direction.
##
## Pure maths on purpose: it takes a velocity in and returns a velocity out,
## touching neither the body nor the tree, so movement feel can be verified in a
## headless test (see tests/test_player_movement.gd).

var _config: PlayerConfig


func setup(config: PlayerConfig) -> void:
	_config = config


## Returns next frame's velocity. `move_input` is expected to be normalised or
## zero; its length scales the target speed, so analogue sticks work unchanged.
func step(velocity: Vector2, move_input: Vector2, delta: float) -> Vector2:
	var target := move_input * _config.move_speed
	# Two separate rates rather than one: releasing the stick brakes harder than
	# pushing it accelerates, which is what makes the robot read as "precise"
	# instead of "slippery" (spec section 6.2).
	var rate := _config.acceleration if not move_input.is_zero_approx() else _config.deceleration
	return velocity.move_toward(target, rate * delta)

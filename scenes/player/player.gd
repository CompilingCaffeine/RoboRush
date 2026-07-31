class_name Player
extends CharacterBody2D
## The obsolete maintenance robot.
##
## This script is deliberately thin: it reads intent from PlayerInput, asks
## MotionController or DashController for a velocity, moves the body, and hands
## presentation state to PlayerVisuals. Behaviour that could belong to a component
## should go in one, so weapons, integrity, and item hooks can be added in later
## milestones without this file growing into a manager.
##
## Actor scripts live beside their scene (scenes/player/) while reusable
## components live in scripts/components/ — a scene owns its root script, and
## scripts/ holds the pieces that scenes compose.

@export var config: PlayerConfig

@onready var _input: PlayerInput = %Input
@onready var _motion: MotionController = %Motion
@onready var _dash: DashController = %Dash
@onready var _visuals: PlayerVisuals = %Visuals
@onready var _camera: Camera2D = %Camera


func _ready() -> void:
	assert(config != null, "Player.config is unset: assign a PlayerConfig resource.")
	_input.setup(config)
	_motion.setup(config)
	_dash.setup(config)
	_dash.dash_started.connect(_on_dash_started)
	_dash.dash_ended.connect(_on_dash_ended)


func _physics_process(delta: float) -> void:
	_input.poll(delta, global_position, get_global_mouse_position())

	_dash.step(delta)
	if _input.has_dash_request() and _dash.can_dash():
		_input.consume_dash_request()
		_dash.try_start(_resolve_dash_direction())

	if _dash.is_dashing:
		velocity = _dash.direction * _dash.get_speed()
	else:
		velocity = _motion.step(velocity, _input.move_vector, delta)

	# move_and_slide with a circular shape slides along walls rather than sticking
	# to them, which covers spec section 6.6 (never trap the player in geometry).
	move_and_slide()

	_visuals.update_visuals(_input.aim_direction, _dash.is_invulnerable(), delta)


## Constrains the camera to a room's bounds so the void outside never shows.
func set_camera_limits(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	# Smoothing otherwise drifts in from wherever the camera was last frame.
	_camera.reset_smoothing()


## Read-only component access for the debug overlay. Gameplay systems should
## prefer signals over reaching in here.
func get_dash_controller() -> DashController:
	return _dash


func get_input_component() -> PlayerInput:
	return _input


## Dash follows the held movement direction so it never fights the player's
## intent; with no movement held it follows the aim, letting a stationary player
## reposition deliberately (spec section 6.3 and 6.4).
func _resolve_dash_direction() -> Vector2:
	if not _input.move_vector.is_zero_approx():
		return _input.move_vector.normalized()
	return _input.aim_direction


func _on_dash_started(direction: Vector2) -> void:
	_visuals.play_dash_squash()
	EventBus.player_dash_started.emit(direction)


func _on_dash_ended() -> void:
	# Dash speed is far above move_speed; without this the robot coasts out of
	# every dash and control feels mushy on landing.
	velocity = velocity.limit_length(config.move_speed)
	EventBus.player_dash_ended.emit()

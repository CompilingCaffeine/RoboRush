class_name PlayerInput
extends Node
## Translates named input actions into movement, aim, and fire intent.
##
## Nothing else in the player reads Input directly. That keeps rebinding, gamepad
## handling, and input buffering in one place, and satisfies spec section 5: input goes
## through named actions, never hard coded keys.
##
## Movement and shooting are fully independent, which is the whole point of the
## arrangement: WASD moves, the arrow keys aim and fire. Holding a shoot direction both
## points the cannon and pulls the trigger, so there is no separate fire button and no
## aim state to lose track of. Release every arrow and firing stops.
##
## Arrow keys are deliberately *not* read with Input.get_vector. That sums opposing
## actions, so holding Right and pressing Left cancels to zero and the player has to
## release Right before the robot will shoot left — which feels broken under pressure.
## Instead the held arrows are tracked in press order and, per axis, the most recently
## pressed one wins. Pressing the opposite arrow therefore reverses fire on the same
## frame, and perpendicular arrows still combine into a diagonal.
##
## The right stick uses its own aim_stick_* actions and keeps its analogue precision;
## quantising it to the eight directions a keyboard can express would be a pointless
## downgrade.
##
## The mouse is the third way to aim, while `mouse_aim` is on: the cannon follows the pointer
## once the pointer moves, and holding the left button fires towards it. The pointer is the
## only direction that is not also a trigger, so it is the only one with a fire button. The
## stick and the arrows win whenever they are in use, and the pointer takes the aim back the
## next time it moves or fires — whichever the player touched last is what they are aiming with.
##
## The component touches nothing outside the Input singleton — no viewport, no camera,
## no tree — so it can be driven directly from a test. Where the pointer is in the world is
## the viewport's and the camera's business, so `Player` works it out and hands it over
## (`point_at`).

## Arrow actions and the direction each one means, in a fixed order.
const SHOOT_DIRECTIONS: Dictionary[StringName, Vector2] = {
	&"shoot_up": Vector2.UP,
	&"shoot_down": Vector2.DOWN,
	&"shoot_left": Vector2.LEFT,
	&"shoot_right": Vector2.RIGHT,
}

## Right stick deflection required before it takes over from the arrow keys.
const STICK_TAKEOVER := 0.25

## How close to the robot, in world pixels, the pointer can be before it stops giving a
## direction. Inside this the robot's own sprite is under the pointer, and a direction taken
## from a pixel or two of offset swings wildly as the robot moves. The aim stays where it was.
const POINTER_DEADZONE := 6.0

## Normalised movement intent. Zero when no direction is held.
var move_vector := Vector2.ZERO

## Normalised shooting intent. Zero when the player is not shooting.
var shoot_vector := Vector2.ZERO

## Normalised aim direction. Never zero: it holds the last direction shot so the cannon
## stays where the player left it instead of snapping back to a default angle.
var aim_direction := Vector2.RIGHT

## Whether the mouse aims and fires. The player's setting (`GameSettings.mouse_aim`), set by
## `Player` before each poll. Off, the pointer and its button are ignored entirely.
var mouse_aim := false

var _config: PlayerConfig
var _dash_buffer_left := 0.0

## Buffered the same way a dash is, and for the same reason: the player presses E as they
## arrive at a shop stand, not once they have finished arriving.
var _interact_buffer_left := 0.0

## Arrow actions currently held, oldest first. Order is what makes the newest press win.
var _held_shoot_actions: Array[StringName] = []

## Last poll's pressed state per arrow, used to detect the rising edge.
var _previously_held: Dictionary[StringName, bool] = {}

## The pointer relative to the robot, in world pixels, and where it was on screen. See `point_at`.
var _pointer_offset := Vector2.ZERO
var _pointer_screen := Vector2.ZERO
var _has_pointer := false

## Whether the pointer is what the player is aiming with: it moved or fired more recently than
## the arrows or the stick were used.
var _pointer_has_aim := false


func setup(config: PlayerConfig) -> void:
	_config = config


## Reads this frame's input.
func poll(delta: float) -> void:
	# get_vector is right for movement: opposing keys cancelling is correct there, and it
	# normalises, handling the diagonal-speed requirement from spec section 6.1.
	move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	_track_held_arrows()
	shoot_vector = _resolve_shoot_vector()
	if not shoot_vector.is_zero_approx():
		_pointer_has_aim = false
	else:
		shoot_vector = _resolve_pointer_shot()

	if not shoot_vector.is_zero_approx():
		aim_direction = shoot_vector.normalized()
	elif _pointer_has_aim and _pointer_offset.length() >= POINTER_DEADZONE:
		aim_direction = _pointer_offset.normalized()

	_dash_buffer_left = maxf(_dash_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed("dash"):
		_dash_buffer_left = _config.dash_input_buffer

	_interact_buffer_left = maxf(_interact_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed("interact"):
		_interact_buffer_left = _config.dash_input_buffer


## Where the pointer is, for mouse aim: `offset` is the pointer relative to the robot in world
## pixels, and `screen_position` is where it is on screen. Set before each poll while `mouse_aim`
## is on.
##
## The screen position is only used to tell whether the mouse moved. The offset alone cannot say:
## it changes whenever the robot moves or the camera pans, with the mouse sitting still on the
## desk. A pointer that has not moved since the first sample has not taken the aim, so a mouse
## nobody is touching never turns the cannon away from where the arrows left it.
func point_at(screen_position: Vector2, offset: Vector2) -> void:
	if _has_pointer and not screen_position.is_equal_approx(_pointer_screen):
		_pointer_has_aim = true
	_pointer_screen = screen_position
	_pointer_offset = offset
	_has_pointer = true


## Firing is exactly "a shoot direction is held" — an arrow, the stick, or the pointer's button
## with mouse aim on. Releasing it stops the weapon on the next frame.
func is_firing() -> bool:
	return not shoot_vector.is_zero_approx()


## True while a recent dash press is still waiting to be honoured.
func has_dash_request() -> bool:
	return _dash_buffer_left > 0.0


## Clears the queued dash press. Call this only once the dash actually starts, so a
## press made with no charges available survives until one refills.
func consume_dash_request() -> void:
	_dash_buffer_left = 0.0


## True while a recent interact press is still waiting to be honoured.
func has_interact_request() -> bool:
	return _interact_buffer_left > 0.0


## Clears the queued press. Called whether or not there was anything to interact with, so
## a press aimed at nothing cannot buy the next thing the player walks past.
func consume_interact_request() -> void:
	_interact_buffer_left = 0.0


## Drops any queued intent. Used on death so a buffered dash cannot fire from a corpse
## and a held arrow key cannot keep shooting.
func clear() -> void:
	move_vector = Vector2.ZERO
	shoot_vector = Vector2.ZERO
	_held_shoot_actions.clear()
	_previously_held.clear()
	_pointer_has_aim = false
	_has_pointer = false
	_dash_buffer_left = 0.0
	_interact_buffer_left = 0.0


## Maintains the held-arrow list in press order: a newly pressed arrow is moved to the
## end, a released one is removed.
##
## The rising edge is computed here against the previous poll rather than taken from
## Input.is_action_just_pressed, which is tied to Godot's process/physics frame counters
## and reports nothing when a press and a poll land in the same frame. Doing it this way
## makes the ordering depend only on this component's own state, so it behaves identically
## at any polling cadence.
func _track_held_arrows() -> void:
	for action: StringName in SHOOT_DIRECTIONS:
		var pressed := Input.is_action_pressed(action)
		var was_pressed: bool = _previously_held.get(action, false)

		if pressed and not was_pressed:
			# Erase first, so re-pressing an already-held arrow still promotes it.
			_held_shoot_actions.erase(action)
			_held_shoot_actions.append(action)
		elif not pressed:
			_held_shoot_actions.erase(action)

		_previously_held[action] = pressed


## The right stick wins while deflected; otherwise each axis takes its most recently
## pressed arrow. Resolving the axes separately is what lets Up and Right combine into a
## diagonal while Left overrides Right.
func _resolve_shoot_vector() -> Vector2:
	var stick := Input.get_vector(
		"aim_stick_left", "aim_stick_right", "aim_stick_up", "aim_stick_down"
	)
	if stick.length() >= STICK_TAKEOVER:
		return stick.normalized()

	var horizontal := _newest_held(&"shoot_left", &"shoot_right")
	var vertical := _newest_held(&"shoot_up", &"shoot_down")
	# Vector2.ZERO.normalized() is ZERO, so "nothing held" needs no special case.
	return (horizontal + vertical).normalized()


## Towards the pointer while its button is held, with mouse aim on; zero otherwise. A pointer
## resting on the robot fires the way the cannon already faces rather than not at all: the player
## asked to shoot, and the press should not be lost to where the cursor happened to be.
func _resolve_pointer_shot() -> Vector2:
	if not mouse_aim:
		_pointer_has_aim = false
		return Vector2.ZERO
	if not Input.is_action_pressed(&"shoot_pointer"):
		return Vector2.ZERO
	_pointer_has_aim = true
	if _pointer_offset.length() < POINTER_DEADZONE:
		return aim_direction
	return _pointer_offset.normalized()


## Returns whichever of two opposing arrows was pressed most recently and is still held,
## or zero if neither is.
func _newest_held(first: StringName, second: StringName) -> Vector2:
	var first_index := _held_shoot_actions.find(first)
	var second_index := _held_shoot_actions.find(second)
	if first_index < 0 and second_index < 0:
		return Vector2.ZERO
	return SHOOT_DIRECTIONS[first] if first_index > second_index else SHOOT_DIRECTIONS[second]

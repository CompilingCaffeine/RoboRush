extends TestCase
## Gamepad support: the action map, and the code paths a controller actually drives.
##
## This suite exists because of an honest limitation. No controller was available, and through
## milestone 5 the README said simply "gamepad is untested" — which was true and useless. What
## can be done without a device is most of what matters: Godot will happily accept synthesized
## `InputEventJoypadButton` and `InputEventJoypadMotion` events, so every binding and every
## code path behind it can be exercised for real.
##
## What this does NOT prove: that a particular controller reports the axes and buttons Godot's
## abstraction claims, that the deadzones feel right in the hand, or that the right stick is
## comfortable to aim with. Those need a person and a device. The claim here is narrower and
## checkable: every action a gamepad player needs is bound to something, and the game responds
## to it.

## The actions spec section 5 requires a controller to reach, and what each is bound to.
## Written out rather than derived from the input map, because the point is to check the map
## against the spec rather than against itself.
const REQUIRED_GAMEPAD_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"aim_stick_up",
	&"aim_stick_down",
	&"aim_stick_left",
	&"aim_stick_right",
	&"dash",
	&"interact",
	&"pause",
	&"restart",
	&"run_stats",
	&"use_active_item",
]

## Godot's built-in menu actions. The pause and settings screens are navigated with these, so
## a gamepad player who cannot reach them cannot change a setting or resume a run.
const MENU_ACTIONS: Array[StringName] = [
	&"ui_up",
	&"ui_down",
	&"ui_left",
	&"ui_right",
	&"ui_accept",
	&"ui_cancel",
]

var _input: PlayerInput


func run() -> void:
	_input = PlayerInput.new()
	_input.setup(load("res://data/player/player_config.tres"))
	add_child(_input)

	_test_every_required_action_has_a_gamepad_binding()
	_test_menu_actions_are_reachable_from_a_gamepad()
	_test_no_action_is_bound_to_nothing()
	await _test_left_stick_moves()
	await _test_right_stick_aims()
	await _test_right_stick_ignores_drift_below_the_takeover()
	await _test_face_button_requests_a_dash()
	await _test_a_released_stick_stops_firing()

	_teardown()


func _teardown() -> void:
	_release_all()
	_input.queue_free()


func _test_every_required_action_has_a_gamepad_binding() -> void:
	for action: StringName in REQUIRED_GAMEPAD_ACTIONS:
		check(InputMap.has_action(action), "action '%s' exists" % action)
		if not InputMap.has_action(action):
			continue
		var has_joypad := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad = true
		check(has_joypad, "action '%s' is reachable from a gamepad" % action)


func _test_menu_actions_are_reachable_from_a_gamepad() -> void:
	for action: StringName in MENU_ACTIONS:
		check(InputMap.has_action(action), "menu action '%s' exists" % action)
		if not InputMap.has_action(action):
			continue
		var has_joypad := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad = true
		check(has_joypad, "menu action '%s' is reachable from a gamepad" % action)


## A binding list that is empty is an action nobody can trigger on any device. Cheap to check
## and exactly the kind of thing a regenerated input map can silently drop.
func _test_no_action_is_bound_to_nothing() -> void:
	for action: StringName in REQUIRED_GAMEPAD_ACTIONS:
		if InputMap.has_action(action):
			check(
				not InputMap.action_get_events(action).is_empty(),
				"action '%s' is bound to at least one event" % action,
			)


func _test_left_stick_moves() -> void:
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(
		_input.move_vector.x > 0.5,
		"pushing the left stick right moves right (got %s)" % _input.move_vector,
	)

	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(
		_input.move_vector.y < -0.5,
		"pushing the left stick up moves up (got %s)" % _input.move_vector,
	)

	_release_all()
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(_input.move_vector.is_zero_approx(), "a centred left stick means no movement")


## The one gamepad behaviour that is not a straight rebinding: the right stick both aims and
## fires, and it has to beat the arrow keys while it is deflected.
func _test_right_stick_aims() -> void:
	_axis(JOY_AXIS_RIGHT_X, -1.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)

	check(_input.is_firing(), "deflecting the right stick fires the weapon")
	check(
		_input.shoot_vector.x < -0.5,
		"the right stick aims where it is pushed (got %s)" % _input.shoot_vector,
	)
	check_near(
		_input.shoot_vector.length(), 1.0, "the resolved shoot vector stays normalised", 0.01
	)

	# Diagonals must survive: an analogue stick that snapped to four directions would be a
	# downgrade from the keyboard rather than an alternative to it.
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(
		_input.shoot_vector.x < -0.2 and _input.shoot_vector.y < -0.2,
		"the right stick aims diagonally (got %s)" % _input.shoot_vector,
	)

	_release_all()
	await advance_physics(1)
	_input.poll(1.0 / 60.0)


## Sticks do not return exactly to centre. A worn controller resting at 0.1 must not make the
## robot fire continuously, and must not override the arrow keys either.
func _test_right_stick_ignores_drift_below_the_takeover() -> void:
	var drift := PlayerInput.STICK_TAKEOVER * 0.5
	_axis(JOY_AXIS_RIGHT_X, drift)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(
		not _input.is_firing(),
		"a right stick resting inside the takeover threshold does not fire (%s)"
			% _input.shoot_vector,
	)

	_release_all()
	await advance_physics(1)
	_input.poll(1.0 / 60.0)


func _test_face_button_requests_a_dash() -> void:
	_button(JOY_BUTTON_A, true)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(_input.has_dash_request(), "the south face button requests a dash")

	_input.consume_dash_request()
	_button(JOY_BUTTON_A, false)

	_button(JOY_BUTTON_X, true)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(_input.has_interact_request(), "the west face button requests an interaction")

	_input.consume_interact_request()
	_release_all()
	await advance_physics(1)


## Releasing the stick has to stop the weapon, because there is no fire button to let go of.
## If this ever failed, a gamepad player would fire continuously for the rest of the run.
func _test_a_released_stick_stops_firing() -> void:
	_axis(JOY_AXIS_RIGHT_Y, 1.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(_input.is_firing(), "the weapon fires while the stick is held")

	var aim_while_firing := _input.aim_direction

	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await advance_physics(1)
	_input.poll(1.0 / 60.0)
	check(not _input.is_firing(), "centring the stick stops the weapon")
	check(
		_input.aim_direction.is_equal_approx(aim_while_firing),
		"the cannon stays where it was aimed rather than snapping back",
	)


# --- Synthetic device --------------------------------------------------------------


## Godot tracks joypad axes as absolute positions, so setting one to 0.0 is how a stick is
## released — there is no separate "up" event as there is for a button.
func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## Leaves the virtual controller at rest. Called between checks and on the way out, because
## Input state is global and a stick left deflected would follow this suite into the next one.
func _release_all() -> void:
	for axis: JoyAxis in [
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y,
		JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT,
	]:
		_axis(axis, 0.0)
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]:
		_button(button, false)
	Input.flush_buffered_events()

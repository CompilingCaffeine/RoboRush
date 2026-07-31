extends TestCase
## Checks the arrow-key shooting scheme.
##
## Movement and shooting must stay completely independent — that independence is the
## entire reason for putting shooting on its own four keys, and it is the thing most
## likely to break silently if the two ever get read from one vector.
##
## Drives the real Input singleton through the real named actions, so what is asserted
## here is what the game actually reads.

const CONFIG_PATH := "res://data/player/player_config.tres"

const MOVE_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const SHOOT_ACTIONS := ["shoot_up", "shoot_down", "shoot_left", "shoot_right"]
const STICK_ACTIONS := ["aim_stick_up", "aim_stick_down", "aim_stick_left", "aim_stick_right"]

var _input: PlayerInput


func run() -> void:
	var config := load(CONFIG_PATH) as PlayerConfig
	if not require(config, "player_config.tres loads for the input checks"):
		return

	_input = PlayerInput.new()
	add_child(_input)
	_input.setup(config)

	_test_actions_exist()
	_test_shooting_sets_aim_and_fires()
	_test_opposite_arrow_reverses_instantly()
	_test_releasing_the_newer_arrow_restores_the_older()
	_test_aim_is_held_after_release()
	_test_diagonal_shooting_is_normalised()
	_test_movement_and_shooting_are_independent()
	_test_clear_stops_everything()

	_release_all()
	_input.free()


func _test_actions_exist() -> void:
	for action: String in SHOOT_ACTIONS:
		check(InputMap.has_action(action), "the '%s' action is defined" % action)
	for action: String in STICK_ACTIONS:
		check(InputMap.has_action(action), "the '%s' action is defined" % action)

	# Nothing may fire the weapon except a shoot direction, so there must be no fire
	# button left anywhere in the map.
	check(not InputMap.has_action("fire_primary"), "there is no separate fire action")

	# Arrow actions must be keyboard-only; a joypad binding here would quantise the
	# right stick to eight directions.
	for action: String in SHOOT_ACTIONS:
		var joypad_bindings := 0
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion or event is InputEventJoypadButton:
				joypad_bindings += 1
		check(joypad_bindings == 0, "'%s' is bound to the keyboard only" % action)


func _test_shooting_sets_aim_and_fires() -> void:
	_press("shoot_right")
	_input.poll(0.0)

	check(_input.is_firing(), "holding an arrow key fires without a separate button")
	check(_input.shoot_vector.is_equal_approx(Vector2.RIGHT), "shoot_right gives a rightward vector")
	check(
		_input.aim_direction.is_equal_approx(Vector2.RIGHT),
		"the aim follows the shoot direction",
	)
	_release_all()


## The whole reason the arrows are not read with Input.get_vector. Pressing the opposite
## arrow while the first is still held must reverse fire immediately, not cancel to zero
## and wait for the player to let go.
func _test_opposite_arrow_reverses_instantly() -> void:
	_press("shoot_right")
	_input.poll(0.0)
	check(_input.shoot_vector.is_equal_approx(Vector2.RIGHT), "shooting right to begin with")

	# Right is deliberately NOT released — this is the case get_vector gets wrong.
	_press("shoot_left")
	_input.poll(0.0)

	check(
		_input.shoot_vector.is_equal_approx(Vector2.LEFT),
		"pressing left while right is held fires left on the same frame",
	)
	check(_input.is_firing(), "firing does not stop while reversing")
	check(_input.aim_direction.is_equal_approx(Vector2.LEFT), "the aim reverses too")
	_release_all()

	# The same must hold on the vertical axis.
	_press("shoot_up")
	_input.poll(0.0)
	_press("shoot_down")
	_input.poll(0.0)
	check(
		_input.shoot_vector.is_equal_approx(Vector2.DOWN),
		"pressing down while up is held fires down",
	)
	_release_all()


## Letting go of the newer arrow should fall back to the one still under a finger,
## rather than stopping fire until the player re-presses.
func _test_releasing_the_newer_arrow_restores_the_older() -> void:
	_press("shoot_right")
	_input.poll(0.0)
	_press("shoot_left")
	_input.poll(0.0)
	check(_input.shoot_vector.is_equal_approx(Vector2.LEFT), "reversed to left")

	Input.action_release("shoot_left")
	_input.poll(0.0)

	check(
		_input.shoot_vector.is_equal_approx(Vector2.RIGHT),
		"releasing left resumes firing right, which is still held",
	)
	check(_input.is_firing(), "firing continues on the still-held arrow")
	_release_all()


## The cannon must stay where the player left it rather than snapping to a default.
func _test_aim_is_held_after_release() -> void:
	_press("shoot_up")
	_input.poll(0.0)
	check(_input.aim_direction.is_equal_approx(Vector2.UP), "aiming up registers")

	_release_all()
	_input.poll(0.0)

	check(not _input.is_firing(), "releasing the key stops the firing")
	check(_input.shoot_vector.is_zero_approx(), "the shoot vector clears on release")
	check(_input.aim_direction.is_equal_approx(Vector2.UP), "the aim direction is retained")


func _test_diagonal_shooting_is_normalised() -> void:
	_press("shoot_up")
	_press("shoot_right")
	_input.poll(0.0)

	check_near(_input.shoot_vector.length(), 1.0, "diagonal shooting is normalised")
	check_near(
		rad_to_deg(_input.aim_direction.angle()), -45.0, "up and right aims at -45 degrees"
	)
	_release_all()


## The point of the scheme: shooting one way while running the other.
func _test_movement_and_shooting_are_independent() -> void:
	_press("move_right")
	_press("shoot_left")
	_input.poll(0.0)

	check(_input.move_vector.is_equal_approx(Vector2.RIGHT), "movement reads the WASD vector")
	check(_input.shoot_vector.is_equal_approx(Vector2.LEFT), "shooting reads the arrow vector")
	check(
		_input.aim_direction.is_equal_approx(Vector2.LEFT),
		"running one way while shooting the other aims backwards",
	)
	_release_all()


func _test_clear_stops_everything() -> void:
	_press("move_left")
	_press("shoot_down")
	_input.poll(0.0)
	check(_input.is_firing(), "firing before the clear")

	_input.clear()
	check(_input.move_vector.is_zero_approx(), "clear zeroes movement")
	check(_input.shoot_vector.is_zero_approx(), "clear zeroes shooting")
	check(not _input.is_firing(), "a corpse does not keep firing from a held key")
	_release_all()


func _press(action: String) -> void:
	Input.action_press(action)


## Synthetic action state is process-global, so it must never leak into another suite.
## Polled once afterwards so the held-arrow list is emptied, not just the Input state.
func _release_all() -> void:
	for action: String in MOVE_ACTIONS + SHOOT_ACTIONS + STICK_ACTIONS:
		Input.action_release(action)
	_input.poll(0.0)

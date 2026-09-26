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
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const MOVE_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const SHOOT_ACTIONS := ["shoot_up", "shoot_down", "shoot_left", "shoot_right"]
const STICK_ACTIONS := ["aim_stick_up", "aim_stick_down", "aim_stick_left", "aim_stick_right"]
const POINTER_ACTIONS := ["shoot_pointer"]

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
	_test_the_mouse_does_nothing_with_mouse_aim_off()
	_test_the_pointer_button_fires_towards_the_pointer()
	_test_a_pointer_nobody_moves_takes_no_aim()
	_test_the_arrows_win_over_the_pointer()
	_test_a_pointer_on_the_robot_fires_the_way_it_faces()

	_input.mouse_aim = false
	_release_all()
	_input.free()

	await _test_the_pointer_is_read_through_the_camera_and_the_stretch()


func _test_actions_exist() -> void:
	for action: String in SHOOT_ACTIONS:
		check(InputMap.has_action(action), "the '%s' action is defined" % action)
	for action: String in STICK_ACTIONS:
		check(InputMap.has_action(action), "the '%s' action is defined" % action)

	# Nothing may fire the weapon except a shoot direction, so there must be no fire
	# button left anywhere in the map. The mouse's button is the one exception, and only
	# because the pointer is a direction that cannot pull a trigger by itself: it must stay
	# on the mouse, or it becomes the fire button this scheme does not have.
	check(not InputMap.has_action("fire_primary"), "there is no separate fire action")
	check(InputMap.has_action("shoot_pointer"), "the 'shoot_pointer' action is defined")
	for event: InputEvent in InputMap.action_get_events("shoot_pointer"):
		check(
			event is InputEventMouseButton,
			"'shoot_pointer' is bound to the mouse only (found %s)" % event.get_class(),
		)

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


# --- Mouse aim (roadmap FIX-7) -------------------------------------------------


## The setting's off position has to mean off: a player who turned it off because their trackpad
## fires the cannon must not be fired by their trackpad.
func _test_the_mouse_does_nothing_with_mouse_aim_off() -> void:
	_input.mouse_aim = false
	_aim_with_arrow("shoot_left")
	_input.point_at(Vector2(10.0, 10.0), Vector2(0.0, 50.0))
	_input.point_at(Vector2(90.0, 90.0), Vector2(0.0, 50.0))
	_press("shoot_pointer")
	_input.poll(0.0)

	check(not _input.is_firing(), "with mouse aim off, the mouse button does not fire")
	check(
		_input.aim_direction.is_equal_approx(Vector2.LEFT),
		"and moving the pointer does not turn the cannon (aim %v)" % _input.aim_direction,
	)
	_release_all()


func _test_the_pointer_button_fires_towards_the_pointer() -> void:
	_input.mouse_aim = true
	_input.point_at(Vector2(200.0, 100.0), Vector2(30.0, -40.0))
	_press("shoot_pointer")
	_input.poll(0.0)

	var towards := Vector2(0.6, -0.8)
	check(_input.is_firing(), "holding the mouse button fires with mouse aim on")
	check(
		_input.shoot_vector.is_equal_approx(towards),
		"towards the pointer (%v, got %v)" % [towards, _input.shoot_vector],
	)
	check(_input.aim_direction.is_equal_approx(towards), "and the cannon faces it")

	Input.action_release("shoot_pointer")
	_input.poll(0.0)
	check(not _input.is_firing(), "letting go of the button stops firing")
	check(_input.aim_direction.is_equal_approx(towards), "and the cannon stays on the pointer")
	_release_all()


## The reason the screen position is handed over at all. The offset changes whenever the robot
## moves or the camera pans, so it cannot say whether the player touched the mouse; a cannon that
## followed it would swing towards a mouse lying untouched on the desk.
func _test_a_pointer_nobody_moves_takes_no_aim() -> void:
	_input.mouse_aim = true
	_input.clear()
	_aim_with_arrow("shoot_left")

	_input.point_at(Vector2(200.0, 100.0), Vector2(0.0, 50.0))
	_input.poll(0.0)
	_input.point_at(Vector2(200.0, 100.0), Vector2(40.0, 50.0))
	_input.poll(0.0)
	check(
		_input.aim_direction.is_equal_approx(Vector2.LEFT),
		"a pointer that has not moved leaves the aim where the arrows put it (aim %v)"
		% _input.aim_direction,
	)

	_input.point_at(Vector2(210.0, 100.0), Vector2(0.0, 50.0))
	_input.poll(0.0)
	check(
		_input.aim_direction.is_equal_approx(Vector2.DOWN),
		"moving it takes the aim, without firing (aim %v)" % _input.aim_direction,
	)
	check(not _input.is_firing(), "and moving the pointer alone does not fire")

	_input.point_at(Vector2(210.0, 100.0), Vector2(50.0, 0.0))
	_input.poll(0.0)
	check(
		_input.aim_direction.is_equal_approx(Vector2.RIGHT),
		"once it has the aim, the cannon stays on it as the robot moves under a still pointer",
	)
	_release_all()


## Whichever the player touched last is what they are aiming with.
func _test_the_arrows_win_over_the_pointer() -> void:
	_input.mouse_aim = true
	_input.clear()
	_input.point_at(Vector2(0.0, 0.0), Vector2(0.0, 50.0))
	_input.point_at(Vector2(5.0, 0.0), Vector2(0.0, 50.0))
	_press("shoot_pointer")
	_press("shoot_up")
	_input.poll(0.0)
	check(
		_input.shoot_vector.is_equal_approx(Vector2.UP),
		"a held arrow fires its own way over a held mouse button (%v)" % _input.shoot_vector,
	)

	Input.action_release("shoot_pointer")
	Input.action_release("shoot_up")
	_input.poll(0.0)
	_input.point_at(Vector2(5.0, 0.0), Vector2(0.0, 50.0))
	_input.poll(0.0)
	check(
		_input.aim_direction.is_equal_approx(Vector2.UP),
		"and after the arrow the pointer has to move again to take the aim back",
	)
	_release_all()


## A player who clicks with the cursor on their own robot asked to shoot. Firing nowhere would
## lose the press; firing along a direction taken from a pixel of offset would spray.
func _test_a_pointer_on_the_robot_fires_the_way_it_faces() -> void:
	_input.mouse_aim = true
	_input.clear()
	_aim_with_arrow("shoot_left")
	_input.point_at(Vector2(0.0, 0.0), Vector2(1.0, 2.0))
	_press("shoot_pointer")
	_input.poll(0.0)
	check(_input.is_firing(), "a click on the robot still fires")
	check(
		_input.shoot_vector.is_equal_approx(Vector2.LEFT),
		"along the way the cannon already faces (%v)" % _input.shoot_vector,
	)
	_release_all()


## The half of mouse aim the checks above cannot reach, because they hand the component its offset
## directly. The pointer is on the screen and the robot is in the world, and between them are the
## room's camera and the viewport's 3x stretch (1440x810 onto 480x270). The robot stands off-centre
## in a room framed away from the origin, so a pointer read in screen pixels, in viewport pixels, or
## without the camera would each aim somewhere else.
func _test_the_pointer_is_read_through_the_camera_and_the_stretch() -> void:
	var saved := SaveManager.settings.mouse_aim
	SaveManager.settings.mouse_aim = true
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	player.global_position = Vector2(1000.0, 600.0)
	var view_size := Vector2i(get_viewport().get_visible_rect().size)
	player.frame_room(Rect2i(Vector2i(900, 540), view_size), true)
	await advance_physics(2)

	check(
		not get_viewport().get_final_transform().is_equal_approx(Transform2D.IDENTITY),
		"the viewport is stretched onto the window, or this check is not testing the stretch",
	)
	for target: Vector2 in [Vector2(0.0, -40.0), Vector2(40.0, 0.0), Vector2(-30.0, 40.0)]:
		_move_pointer_to(player.global_position + target)
		await advance_physics(2)
		var aim := player.get_input_component().aim_direction
		check(
			aim.is_equal_approx(target.normalized()),
			"a pointer at %v from the robot aims at it (aim %v)" % [target, aim],
		)

	SaveManager.settings.mouse_aim = saved
	arena.queue_free()
	await advance_physics(1)


## Moves the mouse to a point in the world, the way the platform would: as a motion event in window
## pixels, which the engine carries back through the stretch to the viewport.
func _move_pointer_to(world: Vector2) -> void:
	var viewport := get_viewport()
	var on_screen := viewport.get_final_transform() * (viewport.get_canvas_transform() * world)
	var event := InputEventMouseMotion.new()
	event.position = on_screen
	event.global_position = on_screen
	Input.parse_input_event(event)


## Aims with an arrow and lets go, leaving the cannon facing that way.
func _aim_with_arrow(action: String) -> void:
	_press(action)
	_input.poll(0.0)
	Input.action_release(action)
	_input.poll(0.0)


func _press(action: String) -> void:
	Input.action_press(action)


## Synthetic action state is process-global, so it must never leak into another suite.
## Polled once afterwards so the held-arrow list is emptied, not just the Input state.
func _release_all() -> void:
	for action: String in MOVE_ACTIONS + SHOOT_ACTIONS + STICK_ACTIONS + POINTER_ACTIONS:
		Input.action_release(action)
	_input.poll(0.0)

extends TestCase
## Modal behaviour for the pause menu and the panels it opens.
##
## Every check here is about one rule: while a panel is up, nothing behind it may act. That
## rule was broken twice in milestone 6 in two different ways, and both were reported rather
## than caught — once for the keyboard, where the button that opened a panel kept focus and
## answered the d-pad, and once for the mouse, where the panels were `MOUSE_FILTER_IGNORE` and
## clicks landed on Abandon Run and Quit underneath.
##
## The mouse checks push real `InputEventMouseButton`s through the viewport at the coordinates
## of the button being protected, rather than asserting a `mouse_filter` value. Asserting the
## property would only restate the fix; pushing a click asks the question the player asks.

const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

var _layer: CanvasLayer
var _pause: PauseMenu


func run() -> void:
	await _test_quit_is_offered_only_where_it_works()
	await _test_a_click_actually_reaches_a_button()
	await _test_a_click_through_settings_cannot_reach_the_menu()
	await _test_a_click_through_the_controls_card_cannot_reach_the_menu()
	await _test_the_controls_card_still_dismisses_on_a_click()
	await _test_hovering_through_a_panel_cannot_steal_focus()


# --- Checks -------------------------------------------------------------------


## Neither menu may offer a button `SceneRouter` would refuse to honour.
##
## The browser playtest reported QUIT as "locking out" the game, and it was doing exactly what it
## was written to do: `get_tree().quit()` ends the main loop, and in a tab there is nothing behind
## the game to return to, so the last frame stays on the canvas with the engine gone. A menu that
## still answers the mouse and does nothing is worse than a menu with one fewer entry.
##
## Stated as an equality rather than as "the web has no QUIT", so that it says something on every
## platform the suite runs on: here it pins that a desktop build *does* still offer it, which is the
## half a careless `if OS.has_feature("web")` would break. `can_quit` is asked rather than the
## platform, so the button and the router can never disagree about which build this is.
func _test_quit_is_offered_only_where_it_works() -> void:
	var expected := SceneRouter.can_quit()

	await _open_pause_menu()
	check(
		(_button_named(PauseMenu.QUIT_LABEL) != null) == expected,
		"the pause menu offers QUIT exactly when quitting works (can_quit=%s)" % expected,
	)
	await _teardown()

	var menu: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await advance_physics(1)
	var found := false
	for child: Node in (menu.get_node("%Buttons") as Node).get_children():
		var button := child as Button
		if button != null and MainMenu.QUIT_LABEL in button.text:
			found = true
	check(
		found == expected,
		"the main menu offers QUIT exactly when quitting works (can_quit=%s)" % expected,
	)
	menu.queue_free()
	await advance_physics(1)


## Calibration, and the most important check in the file. Every other mouse check here asserts
## that a click did *not* land, which is exactly what a harness that cannot deliver clicks at
## all would also report. This one asserts a click *does* land when nothing is in the way, so
## the negatives below are known to mean something.
func _test_a_click_actually_reaches_a_button() -> void:
	await _open_pause_menu()
	var target := _button_named("QUIT")
	if not require(target, "the pause menu has a QUIT button"):
		await _teardown()
		return

	var counter := _isolate(target)

	await _click(target.get_global_rect().get_center())

	check(
		counter.call() == 1,
		"with no panel open, a click on QUIT presses it (%d presses)" % counter.call(),
	)

	await _teardown()


func _test_a_click_through_settings_cannot_reach_the_menu() -> void:
	await _open_pause_menu()
	var guarded := _button_named("ABANDON RUN")
	if not require(guarded, "the pause menu has an ABANDON RUN button to protect"):
		await _teardown()
		return

	var counter := _isolate(guarded)

	_pause.get_node("SettingsMenu").open()
	await advance_physics(2)

	await _click(guarded.get_global_rect().get_center())

	check(
		counter.call() == 0,
		"clicking where ABANDON RUN sits does nothing while settings is open (%d presses)"
			% counter.call(),
	)
	check(GameManager.state == GameManager.State.PAUSED, "and the run is still paused, not left")

	await _teardown()


func _test_a_click_through_the_controls_card_cannot_reach_the_menu() -> void:
	await _open_pause_menu()
	var guarded := _button_named("QUIT")
	if not require(guarded, "the pause menu has a QUIT button to protect"):
		await _teardown()
		return

	var counter := _isolate(guarded)

	var card: ControlsCard = _pause.get_node("ControlsCard")
	card.open()
	await advance_physics(2)

	# Deliberately the worst case: QUIT would end the process outright.
	await _click(guarded.get_global_rect().get_center())

	check(counter.call() == 0, "clicking where QUIT sits does nothing while the card is up")

	await _teardown()


## The card's own promise, which the blocking fix could easily have broken: it says "press any
## button", and a Control that consumes a click never offers it to `_unhandled_input`.
func _test_the_controls_card_still_dismisses_on_a_click() -> void:
	await _open_pause_menu()
	var card: ControlsCard = _pause.get_node("ControlsCard")
	card.open()
	await advance_physics(2)
	check(card.visible, "the card is up")

	await _click(Vector2(240.0, 135.0))

	check(not card.visible, "clicking anywhere dismisses the card")

	await _teardown()


## The keyboard half of the same rule, kept honest here as well: the mouse must not put focus
## back on a button the player cannot see. Hovering used to call grab_focus directly.
func _test_hovering_through_a_panel_cannot_steal_focus() -> void:
	await _open_pause_menu()
	var guarded := _button_named("RESUME")
	if not require(guarded, "the pause menu has a RESUME button"):
		await _teardown()
		return

	# Calibration first: hovering must genuinely move focus when nothing is in the way, or
	# the negative below would hold for a hover that never landed.
	await _hover(guarded.get_global_rect().get_center())
	check(guarded.has_focus(), "with no panel open, hovering a button focuses it")

	_pause.get_node("SettingsMenu").open()
	await advance_physics(2)
	check(
		not guarded.has_focus(),
		"opening settings takes focus off the button that opened it",
	)

	await _hover(guarded.get_global_rect().get_center())

	check(
		not guarded.has_focus(),
		"and hovering where that button sits does not hand focus back to it",
	)

	await _teardown()


# --- Harness ------------------------------------------------------------------


func _open_pause_menu() -> void:
	# A CanvasLayer, because that is how the game hosts these and Control coordinates inside a
	# layer are what the mouse picking uses.
	_layer = CanvasLayer.new()
	add_child(_layer)
	_pause = PAUSE_MENU_SCENE.instantiate()
	_layer.add_child(_pause)
	await advance_physics(1)

	GameManager.start_run()
	GameManager.pause_game()
	await advance_physics(2)


func _teardown() -> void:
	GameManager.resume_game()
	get_viewport().gui_release_focus()
	_layer.queue_free()
	await advance_physics(1)


## Cuts a button loose from what it actually does and counts presses instead.
##
## Not optional hygiene. The first version of this suite clicked QUIT for its calibration
## check, which really did call SceneRouter.quit_game and killed the test runner mid-run — with
## exit code 0, so the whole thing looked green while three suites never ran at all. A test
## that can end the process is a test that can hide every failure after it.
func _isolate(button: Button) -> Callable:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	var count := [0]
	button.pressed.connect(func() -> void: count[0] += 1)
	return func() -> int: return count[0]


func _button_named(label: String) -> Button:
	for child: Node in (_pause.get_node("Buttons") as Node).get_children():
		var button := child as Button
		# The focused button's text carries a "> " marker, so compare on what is inside it.
		if button != null and button.text.strip_edges().trim_prefix("> ").strip_edges() == label:
			return button
	return null


## A press and a release at one point, pushed through the viewport so Godot's own GUI picking
## decides what receives it — which is the thing under test.
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		# in_local_coords, because `at` comes from a Control's global_rect and is therefore
		# already in the 480x270 GUI space. Pushed as screen coordinates it would be run
		# through the stretch transform and land three times too far out, missing everything
		# — which is exactly what the calibration check caught.
		get_viewport().push_input(event, true)
	await advance_physics(2)


func _hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)
	await advance_physics(2)

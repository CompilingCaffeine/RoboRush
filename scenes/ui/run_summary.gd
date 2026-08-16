class_name RunSummary
extends Control
## The run's statistics, shown on game over, on victory, and on demand.
##
## One screen rather than three, because they are the same information every time and the
## only thing that differs is the headline and what the player can do next. A separate
## "game over screen" and "statistics screen" would be two things to keep in step showing the
## same numbers.
##
## It no longer answers for the paused state — `PauseMenu` does, and does it with buttons
## rather than the line of keypresses this screen used to print. What is left here is the two
## endings and the mid-run peek.
##
## Runs with PROCESS_MODE_ALWAYS: both endings pause the tree, and a summary screen that
## stopped updating the moment it appeared would be a black rectangle.
##
## Spec section 23 warns against input leaking between UI and gameplay. The buttons exist only
## while the run is over — and the run being over is exactly when nothing is listening for
## gameplay input — and focus is released whenever the screen is dismissed, because `ui_accept`
## includes Space and Space is dash.

const FONT_SIZE := UIPalette.FONT_SIZE
const TITLE_FONT_SIZE := UIPalette.FONT_SIZE_HEADING

const BACKDROP := Color(0.02, 0.03, 0.05, 0.86)

## Appended to a statistic this run turned into a personal best. A marked row is the whole
## reason `BestRunStats.absorb` reports what it beat rather than just recording it.
const RECORD_MARK := " *"

## See `MainMenu.QUIT_LABEL`: removed by label in the browser build, where quitting strands the
## player on a dead canvas. This screen is the one that mattered most — it is where a browser
## player was most likely to press it, because a run that has just ended is when leaving the game
## is the obvious thing to do. RETRY and MENU are both still here, so nothing is lost by dropping it.
const QUIT_LABEL := "QUIT"

const BUTTONS: Array = [
	["RETRY", "_on_retry_pressed"],
	["MENU", "_on_menu_pressed"],
	[QUIT_LABEL, "_on_quit_pressed"],
]

const FOCUS_MARKER := ">"
const FOCUS_PADDING := " "

@onready var _backdrop: ColorRect = %Backdrop
@onready var _title: Label = %Title
@onready var _grid: GridContainer = %Grid
@onready var _hint: Label = %Hint
@onready var _buttons: HBoxContainer = %Buttons

## True while the player is holding the statistics key during play. Kept apart from the game
## state so releasing the key cannot dismiss a game over screen.
var _peeking := false

## Guards the ending sound and the focus grab, both of which must happen once when the run
## ends rather than on every refresh.
var _announced := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop.color = BACKDROP
	UIPalette.style(_title, UIPalette.WARN, TITLE_FONT_SIZE)
	UIPalette.style(_hint, UIPalette.TEXT_FAINT, FONT_SIZE)
	visible = false
	_build_buttons()
	GameManager.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	# Polled rather than driven by _input, because this is a peek: it is held, not toggled,
	# and a release that arrives while the tree is paused would otherwise be missed.
	var wants_peek := GameManager.is_playing() and Input.is_action_pressed("run_stats")
	if wants_peek == _peeking:
		return
	_peeking = wants_peek
	_refresh()


func _build_buttons() -> void:
	var entries := BUTTONS.duplicate()
	if not SceneRouter.can_quit():
		entries = entries.filter(func(entry: Array) -> bool: return entry[0] != QUIT_LABEL)

	for entry: Array in entries:
		var button := Button.new()
		button.text = FOCUS_PADDING + (entry[0] as String)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(Callable(self, entry[1] as String))
		button.focus_entered.connect(_on_button_focused.bind(button, entry[0] as String))
		button.focus_exited.connect(_on_button_unfocused.bind(button, entry[0] as String))
		button.mouse_entered.connect(button.grab_focus)
		_buttons.add_child(button)


func _on_button_focused(button: Button, label: String) -> void:
	button.text = FOCUS_MARKER + label
	AudioManager.play_sfx(&"ui_move")


func _on_button_unfocused(button: Button, label: String) -> void:
	button.text = FOCUS_PADDING + label


func _on_state_changed(_state: GameManager.State) -> void:
	_refresh()


func _refresh() -> void:
	var over := GameManager.is_run_over()
	var should_show := _peeking or over
	visible = should_show
	# The buttons are the difference between the ending and the peek: during play the run is
	# still happening and there is nothing to choose.
	_buttons.visible = over

	if not should_show:
		_announced = false
		get_viewport().gui_release_focus()
		return

	match GameManager.state:
		GameManager.State.GAME_OVER:
			_set_title("SYSTEM FAILURE", UIPalette.DANGER)
			_hint.text = "R RESTART"
		GameManager.State.VICTORY:
			_set_title("FLOOR CLEARED", UIPalette.ACCENT)
			_hint.text = "R RUN AGAIN"
		_:
			_set_title("DIAGNOSTICS", UIPalette.WARN)
			_hint.text = "RELEASE TAB TO CLOSE"

	_build_rows(RunManager.stats.describe())

	if over and not _announced:
		_announced = true
		AudioManager.play_sfx(
			&"victory" if GameManager.state == GameManager.State.VICTORY else &"game_over"
		)
		if _buttons.get_child_count() > 0:
			(_buttons.get_child(0) as Button).grab_focus()


func _set_title(text: String, color: Color) -> void:
	_title.text = text
	UIPalette.style(_title, color, TITLE_FONT_SIZE)


## Rebuilt rather than updated in place. The row *set* changes — a cause of death appears only
## once there is one — and rebuilding a dozen labels on a screen that is already paused costs
## nothing worth optimising.
func _build_rows(rows: Array) -> void:
	for existing: Node in _grid.get_children():
		_grid.remove_child(existing)
		existing.queue_free()

	var records := RunManager.records_beaten
	var any_record := false

	for row: Array in rows:
		var is_record: bool = GameManager.is_run_over() and (row[0] as String) in records
		any_record = any_record or is_record

		_grid.add_child(UIPalette.make_label(row[0] as String, UIPalette.TEXT_DIM, FONT_SIZE))
		_grid.add_child(
			UIPalette.make_label(
				(row[1] as String) + (RECORD_MARK if is_record else ""),
				UIPalette.ACCENT if is_record else UIPalette.TEXT,
				FONT_SIZE,
			)
		)

	if any_record:
		_grid.add_child(UIPalette.make_label("", UIPalette.TEXT_FAINT, FONT_SIZE))
		_grid.add_child(UIPalette.make_label("* PERSONAL BEST", UIPalette.ACCENT, FONT_SIZE))


func _on_retry_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameManager.restart_run()


func _on_menu_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	GameManager.leave_run()


## No sound: quitting takes effect at the end of this frame, so a click here would be cut off
## before it was audible — and a stream still playing at teardown leaks it.
func _on_quit_pressed() -> void:
	SceneRouter.quit_game()

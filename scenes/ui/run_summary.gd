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
## One line differs by more than its wording: the global rank under the statistics, which only a
## victory has and only a browser build can show. See `_refresh_rank` — it is also the only thing
## on this screen that is not known the moment the screen appears.
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
@onready var _rank: Label = %Rank
@onready var _build_title: Label = %BuildTitle
@onready var _build_grid: GridContainer = %BuildGrid

## True while the player is holding the statistics key during play. Kept apart from the game
## state so releasing the key cannot dismiss a game over screen.
var _peeking := false

## Guards the ending sound and the focus grab, both of which must happen once when the run
## ends rather than on every refresh.
var _announced := false

## Bumped whenever the rank line stops being about the run it was fetched for — the screen is
## dismissed, or a second run ends. The board is read over the network and the player can press
## RETRY while that is in flight; without this, the answer would arrive and be written onto the
## next run's summary.
var _rank_generation := 0


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

	# Taken down for the peek as well as for the dismissal. A line about where a finished run left
	# the player on the global board has no meaning halfway through the next one, and leaving the
	# previous ending's rank on screen during a mid-run glance would be stating it about this run.
	if not over:
		_hide_rank()

	if not should_show:
		_announced = false
		get_viewport().gui_release_focus()
		return

	match GameManager.state:
		GameManager.State.GAME_OVER:
			_set_title("SYSTEM FAILURE", UIPalette.DANGER)
			_hint.text = "R RESTART"
		GameManager.State.VICTORY:
			_set_title("SYSTEM RESTORED", UIPalette.ACCENT)
			_hint.text = "R RUN AGAIN"
		_:
			_set_title("DIAGNOSTICS", UIPalette.WARN)
			_hint.text = "RELEASE TAB TO CLOSE"

	_build_rows(RunManager.stats.describe())
	_build_inventory()

	if over and not _announced:
		_announced = true
		AudioManager.play_sfx(
			&"victory" if GameManager.state == GameManager.State.VICTORY else &"game_over"
		)
		if _buttons.get_child_count() > 0:
			(_buttons.get_child(0) as Button).grab_focus()
		_refresh_rank()


## Where this run leaves the player on the global board, under the statistics.
##
## Only on a victory, and only where there is a board. The board ranks finishes (see
## `Leaderboard`), so a line about it on a death is a line about a competition the run never
## entered — and off the web there is no board at all, which is what `Leaderboard.is_offered`
## answers.
##
## Fetched rather than taken from `Leaderboard.score_posted`, which carries a rank of its own. That
## signal only fires when a time was actually written, so a player winning a second time slightly
## slower than their first would see nothing — and "you are still seventh" is the true answer to
## the question they are looking at this line to ask. Reading the board covers both endings with
## one path.
##
## The line starts as the honest intermediate rather than blank. A rank that appears two seconds
## into a screen the player is already reading is a rank they have looked past.
func _refresh_rank() -> void:
	# Cancels any fetch still in flight for a previous ending before starting this one.
	_rank_generation += 1
	var generation := _rank_generation

	var on_the_board := (
		GameManager.state == GameManager.State.VICTORY and Leaderboard.is_offered()
	)
	_rank.visible = on_the_board
	if not on_the_board:
		return

	_set_rank("POSTING YOUR TIME...", UIPalette.TEXT_FAINT)

	var standing: Dictionary = await Leaderboard.fetch_standing()
	if generation != _rank_generation:
		return

	if not standing.get("success", false):
		# Whatever went wrong, `Leaderboard` has already put it in the player's language, and none
		# of it costs them anything: the record is saved, and the board gets it by the next launch.
		_set_rank(str(standing.get("message", "")), UIPalette.TEXT_DIM)
		return

	var rank := int(standing.get("rank", 0))
	if rank <= 0:
		# On the board, but the platform did not say where on it. Saying that is better than
		# inventing a position or pretending the time never went up.
		_set_rank("TIME POSTED", UIPalette.ACCENT)
		return

	_set_rank("GLOBAL RANK  #%d" % rank, UIPalette.ACCENT)


func _set_rank(text: String, color: Color) -> void:
	_rank.text = text
	_rank.visible = not text.is_empty()
	UIPalette.style(_rank, color)


func _hide_rank() -> void:
	_rank_generation += 1
	_rank.visible = false


## Puts the keyboard back on this screen's first button. Called when something that was covering
## it goes away — today that is the victory card, which releases focus on the way up so that
## `ui_accept` cannot press RETRY through it, and has to give it back on the way down. Ignored
## unless the buttons are actually on screen, so it cannot focus a hidden panel mid-run.
func focus_buttons() -> void:
	if visible and _buttons.visible and _buttons.get_child_count() > 0:
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
		# RunStats retains the complete text for reports; an unbroken list of every item
		# cannot fit the game viewport. The adjacent grid represents that build instead.
		if row[0] == "BUILD":
			continue
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


func _build_inventory() -> void:
	for child: Node in _build_grid.get_children():
		_build_grid.remove_child(child)
		child.queue_free()
	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Player
	var inventory := player.get_item_inventory() if player != null else null
	_build_title.text = "BUILD  //  %d ITEMS" % (inventory.size() if inventory != null else 0)
	UIPalette.style(_build_title, UIPalette.WARN, FONT_SIZE)
	if inventory == null:
		return
	var seen: Dictionary[StringName, bool] = {}
	for item: ItemConfig in inventory.get_items():
		if seen.has(item.id):
			continue
		seen[item.id] = true
		var count := inventory.count_of(item.id)
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(20, 10)
		cell.add_theme_constant_override("separation", 1)
		cell.tooltip_text = item.display_name + (" x%d" % count if count > 1 else "")
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(8, 8)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		if count > 1:
			cell.add_child(UIPalette.make_label(str(count), UIPalette.TEXT, FONT_SIZE))
		_build_grid.add_child(cell)


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

class_name RunSummary
extends Control
## The run's statistics, shown on game over, on victory, on pause, and on demand.
##
## One screen rather than four, because they are the same information every time and the
## only thing that differs is the headline and what the player can do next. A separate
## "game over screen" and "statistics screen" would be two things to keep in step showing
## the same numbers.
##
## Runs with PROCESS_MODE_ALWAYS: three of the four ways to reach it pause the tree, and a
## summary screen that stopped updating the moment it appeared would be a black rectangle.
##
## Spec section 23 warns against input leaking between UI and gameplay. Nothing here reads
## input at all except the statistics peek, which is a held key with no side effect —
## everything else is driven by GameManager's state, so there is exactly one place that
## decides whether the player is playing.

const FONT_SIZE := 8
const TITLE_FONT_SIZE := 16

const BACKDROP := Color(0.02, 0.03, 0.05, 0.82)
const TITLE_DEAD := Color("ff6b5a")
const TITLE_WON := Color("58f0c8")
const TITLE_NEUTRAL := Color("f2a13c")
const LABEL_COLOR := Color("7c8a99")
const VALUE_COLOR := Color("d8e2ec")
const HINT_COLOR := Color("6d7a8c")

@onready var _backdrop: ColorRect = %Backdrop
@onready var _title: Label = %Title
@onready var _grid: GridContainer = %Grid
@onready var _hint: Label = %Hint

## True while the player is holding the statistics key during play. Kept apart from the
## game state so releasing the key cannot dismiss a game over screen.
var _peeking := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop.color = BACKDROP
	_style(_title, TITLE_NEUTRAL, TITLE_FONT_SIZE)
	_style(_hint, HINT_COLOR, FONT_SIZE)
	visible = false
	GameManager.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	# Polled rather than driven by _input, because this is a peek: it is held, not toggled,
	# and a release that arrives while the tree is paused would otherwise be missed.
	var wants_peek := GameManager.is_playing() and Input.is_action_pressed("run_stats")
	if wants_peek == _peeking:
		return
	_peeking = wants_peek
	_refresh()


func _on_state_changed(_state: GameManager.State) -> void:
	_refresh()


func _refresh() -> void:
	var state := GameManager.state
	var should_show := _peeking or state != GameManager.State.RUN
	visible = should_show
	if not should_show:
		return

	match state:
		GameManager.State.GAME_OVER:
			_set_title("SYSTEM FAILURE", TITLE_DEAD)
			_hint.text = "PRESS R TO REBOOT"
		GameManager.State.VICTORY:
			_set_title("FLOOR CLEARED", TITLE_WON)
			_hint.text = "PRESS R TO RUN AGAIN"
		GameManager.State.PAUSED:
			_set_title("PAUSED", TITLE_NEUTRAL)
			_hint.text = "ESC RESUME    R ABANDON RUN"
		_:
			_set_title("DIAGNOSTICS", TITLE_NEUTRAL)
			_hint.text = "RELEASE TAB TO CLOSE"

	_build_rows(RunManager.stats.describe())


func _set_title(text: String, color: Color) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", color)


## Rebuilt rather than updated in place. The row *set* changes — a cause of death appears
## only once there is one — and rebuilding a dozen labels on a screen that is already
## paused costs nothing worth optimising.
func _build_rows(rows: Array) -> void:
	for existing: Node in _grid.get_children():
		_grid.remove_child(existing)
		existing.queue_free()

	for row: Array in rows:
		var label := Label.new()
		label.text = row[0]
		_style(label, LABEL_COLOR, FONT_SIZE)
		_grid.add_child(label)

		var value := Label.new()
		value.text = row[1]
		_style(value, VALUE_COLOR, FONT_SIZE)
		_grid.add_child(value)


func _style(label: Label, color: Color, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

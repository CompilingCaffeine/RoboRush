class_name ControlsCard
extends Control
## What the buttons do. Spec section 31.11: "controls are explained in game".
##
## The single most load-bearing screen for milestone 6's success condition — a new player
## understanding the game without a developer next to them — because Robo Rush does not fire
## where the mouse is. Holding an arrow key aims *and* fires, and nothing on screen would ever
## teach that. Everything else here is a courtesy; that one line is the reason the card exists.
##
## Shown automatically the first time the game is launched, and from a menu after that. The
## "first time" is `SaveManager.tutorial_completed`, which is what spec section 24 means by
## tutorial completion — there is no tutorial to complete, only this to have read.
##
## The rows are data rather than a scene full of labels so that a control and its explanation
## cannot drift apart: `README.md`'s table and this were already two copies of the same
## information before this file existed, and this is the copy the player sees.

signal closed

## Label, keyboard binding, gamepad binding. Ordered by what a player needs first.
const ROWS: Array = [
	["MOVE", "WASD", "LEFT STICK"],
	["AIM AND FIRE", "ARROW KEYS", "RIGHT STICK"],
	["DASH", "SPACE", "A"],
	["BUY / TAKE", "E", "X"],
	["DIAGNOSTICS", "TAB (HOLD)", "L1 (HOLD)"],
	["PAUSE", "ESCAPE", "START"],
	["RESTART", "R", "Y"],
]

## The one thing a player cannot work out by pressing keys, because the game never stops them
## to say it. Kept to two lines: a wall of text on the first screen is a wall of text nobody
## reads.
const EXPLANATION := """THERE IS NO FIRE BUTTON. HOLD AN ARROW TO
AIM AND FIRE. MOVING AND SHOOTING ARE
INDEPENDENT -- RUN ONE WAY, FIRE THE OTHER."""

@onready var _grid: GridContainer = %Grid
@onready var _explanation: Label = %Explanation
@onready var _hint: Label = %Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	UIPalette.style(_explanation, UIPalette.WARN)
	_explanation.text = EXPLANATION
	UIPalette.style(_hint, UIPalette.TEXT_FAINT)
	_hint.text = "PRESS ANY BUTTON TO CONTINUE"

	_build_grid()


func open() -> void:
	# Re-anchored on the way up, because the rect this was born with may be nothing at all.
	#
	# The browser build lays the menu out once before the canvas has told the engine how big it is,
	# and a Control that is hidden when its parent later gets its real size does not re-anchor —
	# visible siblings do, which is why the menu behind this card looks perfectly normal. Shown
	# as-is, a full-screen modal is a zero-size box in the top-left corner with its panel spilling
	# off two edges of the screen. That is what a first-time player in a browser saw: the one card
	# the game asks them to read, half of it off-screen.
	#
	# No desktop build has ever done it, and no test could have caught it — a desktop window is the
	# size it claims to be from the first frame, and a headless run has no canvas to wait for. It
	# took a screenshot of the real export in a real browser.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	# See SettingsMenu.open: a focused button behind a modal panel still answers the d-pad.
	get_viewport().gui_release_focus()
	# Reading the card is the whole of "tutorial completion": it is the only thing the game
	# ever asks a first-time player to look at, so having looked at it is the flag.
	SaveManager.mark_tutorial_completed()


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_sfx(&"ui_back")
	closed.emit()


## Dismissed by anything, on purpose. A card that says "press any button" and then insists on
## one particular button is worse than no card. Every event is consumed while it is up, so
## nothing behind it can act on the keypress that dismissed it.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var is_press := (
		(event is InputEventKey and event.is_pressed() and not event.is_echo())
		or (event is InputEventJoypadButton and event.is_pressed())
	)
	if is_press:
		close()
	get_viewport().set_input_as_handled()


## Mouse clicks arrive here rather than in `_unhandled_input`, because the root blocks the
## mouse to stop clicks reaching the menu underneath — and a Control that consumes a click has
## already handled it by the time unhandled input is offered. Without this, "press any button"
## would quietly stop being true for the mouse.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		close()
		accept_event()


func _build_grid() -> void:
	_grid.add_child(UIPalette.make_label("ACTION", UIPalette.TEXT_FAINT))
	_grid.add_child(UIPalette.make_label("KEYBOARD", UIPalette.TEXT_FAINT))
	_grid.add_child(UIPalette.make_label("GAMEPAD", UIPalette.TEXT_FAINT))

	for row: Array in ROWS:
		_grid.add_child(UIPalette.make_label(row[0], UIPalette.TEXT_DIM))
		_grid.add_child(UIPalette.make_label(row[1], UIPalette.TEXT))
		_grid.add_child(UIPalette.make_label(row[2], UIPalette.TEXT))

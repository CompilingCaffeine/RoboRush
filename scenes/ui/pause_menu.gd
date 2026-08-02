class_name PauseMenu
extends Control
## What Escape does mid-run. Spec section 23's Paused state, given something to show.
##
## Pausing used to put the statistics screen up with the line "ESC RESUME    R ABANDON RUN",
## which is a game explaining itself in keypresses — the thing milestone 6 exists to stop.
## The statistics are still a key away during play (hold Tab); pausing is now for the four
## things a player pauses to do.
##
## Driven entirely by `GameManager.state`, so there is exactly one place that decides whether
## the game is paused and this is not it. Pressing Escape here does not resume: it falls
## through to `GameManager`, which owns the toggle. Two things that can both unpause the game
## is how you end up with a menu that closes but leaves the tree frozen.
##
## Releases keyboard focus on the way out, which is not a detail. `ui_accept` includes Space,
## and Space is dash — a button left focused behind a dismissed menu means every dash also
## presses it. That is precisely the input leak spec section 23 warns about.

const BUTTONS: Array = [
	["RESUME", "_on_resume_pressed"],
	["SETTINGS", "_on_settings_pressed"],
	["CONTROLS", "_on_controls_pressed"],
	["ABANDON RUN", "_on_abandon_pressed"],
	["QUIT", "_on_quit_pressed"],
]

const FOCUS_MARKER := "> "
const FOCUS_PADDING := "  "

@onready var _buttons: VBoxContainer = %Buttons
@onready var _progress: Label = %Progress
@onready var _settings: SettingsMenu = %SettingsMenu
@onready var _controls: ControlsCard = %ControlsCard


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UIPalette.style(_progress, UIPalette.TEXT_DIM)

	_build_buttons()
	_settings.closed.connect(_focus_first)
	_controls.closed.connect(_focus_first)
	GameManager.state_changed.connect(_on_state_changed)


func _build_buttons() -> void:
	for entry: Array in BUTTONS:
		var button := Button.new()
		button.text = FOCUS_PADDING + (entry[0] as String)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(Callable(self, entry[1] as String))
		button.focus_entered.connect(_on_button_focused.bind(button, entry[0] as String))
		button.focus_exited.connect(_on_button_unfocused.bind(button, entry[0] as String))
		button.mouse_entered.connect(button.grab_focus)
		_buttons.add_child(button)


func _on_state_changed(state: GameManager.State) -> void:
	var should_show := state == GameManager.State.PAUSED
	if should_show == visible:
		return

	visible = should_show
	if should_show:
		_refresh_progress()
		_focus_first()
		return

	# Anything opened over the pause menu closes with it, or it would reappear over the game
	# the next time the player paused.
	_settings.visible = false
	_controls.visible = false
	get_viewport().gui_release_focus()


func _focus_first() -> void:
	if _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Button).grab_focus()


func _on_button_focused(button: Button, label: String) -> void:
	button.text = FOCUS_MARKER + label
	AudioManager.play_sfx(&"ui_move")


func _on_button_unfocused(button: Button, label: String) -> void:
	button.text = FOCUS_PADDING + label


## One line, because a paused player wants to know where they are, not to study a report.
func _refresh_progress() -> void:
	_progress.text = "%s    %s    SCRAP %d    ROOMS %d" % [
		RunManager.floor_name.to_upper(),
		RunStats.format_duration(RunManager.stats.duration),
		RunManager.scrap,
		RunManager.rooms_cleared,
	]


func _on_resume_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	GameManager.resume_game()


func _on_settings_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	_settings.open()


func _on_controls_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	_controls.open()


func _on_abandon_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	GameManager.leave_run()


## No sound: quitting takes effect at the end of this frame, so a click here would be cut off
## before it was audible — and a stream still playing at teardown leaks it.
func _on_quit_pressed() -> void:
	SceneRouter.quit_game()

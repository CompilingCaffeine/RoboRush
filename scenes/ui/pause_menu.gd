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

## See `MainMenu.QUIT_LABEL`: removed by label in the browser build, where quitting strands the
## player on a dead canvas. ABANDON RUN is the way out of a run either way.
const QUIT_LABEL := "QUIT"

## Directly above ABANDON RUN, because the two of them are the same decision answered differently:
## both leave the run for the title screen, and the only thing that distinguishes them is whether
## the run is still there afterwards. Adjacent, a player reads them as a pair and picks; separated,
## ABANDON RUN is just the only way out they can see.
##
## "EXIT" rather than "QUIT" deliberately. On a desktop this menu also carries QUIT, which closes
## the game, and two entries that both begin with the same verb and do very different things is how
## somebody loses a run to a misread. This one exits the *run*, to the title screen, which is where
## CONTINUE will be waiting.
const SAVE_LABEL := "SAVE AND EXIT"

const BUTTONS: Array = [
	["RESUME", "_on_resume_pressed"],
	["SETTINGS", "_on_settings_pressed"],
	["CONTROLS", "_on_controls_pressed"],
	[SAVE_LABEL, "_on_save_pressed"],
	["ABANDON RUN", "_on_abandon_pressed"],
	[QUIT_LABEL, "_on_quit_pressed"],
]

## What the entry says when the save did not happen, and how long it says it for.
##
## There is no matching "SAVED", because a save that worked does not need one: the menu is gone and
## the title screen is showing CONTINUE with the floor and the clock on it, which is a better answer
## than a word on a button nobody is looking at any more. This is only for the case where the run
## stays exactly where it was and the player has to be told why.
const SAVE_FAILED_LABEL := "COULD NOT SAVE"
const SAVE_FAILED_NOTICE_SECONDS := 2.0

## Emitted when the player asks for the run to be written down. Answered by whoever built this
## screen — `main.gd`, which owns the floor and is the only thing that can reach the room state a
## mid-floor save has to record; it reports back through `report_saved`. The menu deliberately
## cannot save by itself: a pause screen that reached across the tree for the floor controller
## would be a pause screen that has to be kept in step with how floors are built.
signal save_requested

const FOCUS_MARKER := "> "
const FOCUS_PADDING := "  "

@onready var _buttons: VBoxContainer = %Buttons
@onready var _progress: Label = %Progress
@onready var _settings: SettingsMenu = %SettingsMenu
@onready var _controls: ControlsCard = %ControlsCard

## Held so the acknowledgement can be written onto the entry the player pressed, rather than into a
## status line somewhere else on the screen that they have no reason to be looking at.
var _save_button: Button = null

## What the save entry currently says. The focus handlers repaint the button from this rather than
## from `SAVE_LABEL`, so moving the selection on and off a button that reads SAVED does not quietly
## put it back to SAVE GAME while the player is still looking at it.
var _save_text := SAVE_LABEL


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UIPalette.style(_progress, UIPalette.TEXT_DIM)

	_build_buttons()
	_settings.closed.connect(_focus_first)
	_controls.closed.connect(_focus_first)
	GameManager.state_changed.connect(_on_state_changed)


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
		if entry[0] == SAVE_LABEL:
			_save_button = button


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
	button.text = FOCUS_MARKER + _current_label(button, label)
	AudioManager.play_sfx(&"ui_move")


func _on_button_unfocused(button: Button, label: String) -> void:
	button.text = FOCUS_PADDING + _current_label(button, label)


## What a button should say right now. Every entry but one says what it has always said; the save
## entry says whatever the last press left on it, so that focus moving over it does not wipe the
## acknowledgement the player pressed it to see.
func _current_label(button: Button, label: String) -> String:
	return _save_text if button == _save_button else label


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


## Writes the run down and leaves for the title screen.
##
## Only asks, here. Whoever built this screen owns the floor, and the floor is the only thing that
## knows which of its rooms are already done — so the answer comes back through `report_saved`, and
## the leaving happens there, once there is something to leave behind.
func _on_save_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	save_requested.emit()


## The answer to `save_requested`, from whoever built this screen.
##
## Leaves only on success. A failed save that walked out anyway would be the single worst thing this
## button could do — the run gone and nothing written down, in response to the press that was
## supposed to protect it — so a refusal keeps the player exactly where they were, still paused,
## still in the run, and says so on the button they pressed.
func report_saved(succeeded: bool) -> void:
	if succeeded:
		GameManager.suspend_run()
		return

	if _save_button == null or not is_instance_valid(_save_button):
		return
	_save_text = SAVE_FAILED_LABEL
	_repaint_save_button()

	# `process_always`, because the tree is paused — this is the pause menu — and a timer that
	# waited for an unpaused frame would never come back. `ignore_time_scale` for the same class of
	# reason: pausing during a hit pause leaves `Engine.time_scale` at a fraction, and the notice
	# would sit there for half a minute.
	await get_tree().create_timer(SAVE_FAILED_NOTICE_SECONDS, true, false, true).timeout

	_save_text = SAVE_LABEL
	_repaint_save_button()


func _repaint_save_button() -> void:
	if _save_button == null or not is_instance_valid(_save_button):
		return
	var focused := _save_button.has_focus()
	_save_button.text = (FOCUS_MARKER if focused else FOCUS_PADDING) + _save_text


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

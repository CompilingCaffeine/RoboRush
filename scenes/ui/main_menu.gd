class_name MainMenu
extends Control
## The title screen, and the game's entry point. Spec section 23's Main Menu.
##
## Before this, launching Robo Rush dropped the player straight into a room with no title, no
## settings, and no explanation of a firing scheme that has no fire button. Milestone 6's
## success condition is a new player understanding the game without being told, and this is
## where that is either true or false.
##
## Owns the two panels that are reachable from both here and the pause menu — settings and the
## controls card — by instancing the same scenes the pause menu instances. Neither knows where
## it was opened from, which is what lets them be opened from anywhere.

const BUTTONS: Array = [
	["START RUN", "_on_start_pressed"],
	["CONTROLS", "_on_controls_pressed"],
	["SETTINGS", "_on_settings_pressed"],
	["QUIT", "_on_quit_pressed"],
]

## Where the entry that continues a saved run goes, and what it says. First, above START RUN,
## because a player who has a run waiting is here to get back to it — and because the alternative
## is a menu whose first entry silently throws that run away.
##
## Only present when there is a run to continue. A permanent, greyed-out CONTINUE would tell a
## first-time player that the game has a feature they are locked out of, which is the opposite of
## what it means.
const CONTINUE_INDEX := 0
const CONTINUE_LABEL := "CONTINUE"

## Marks the focused entry. The theme also draws a focus border; this is here because the
## settings list marks its selection the same way, and one game should have one idiom for
## "you are here".
const FOCUS_MARKER := "> "
const FOCUS_PADDING := "  "

@onready var _buttons: VBoxContainer = %Buttons
@onready var _records_upper: Label = %RecordsUpper
@onready var _records_lower: Label = %RecordsLower
@onready var _tagline: Label = %Tagline
@onready var _settings: SettingsMenu = %SettingsMenu
@onready var _controls: ControlsCard = %ControlsCard


func _ready() -> void:
	# The router sets this on every other path into the menu; a cold launch arrives here
	# without passing through it, because this is the project's main scene.
	GameManager.enter_main_menu()

	# Everything below reads the save, and the manager no longer loads itself — the bootstrap
	# scene does it, once it knows whether there is a cloud save to wait for. This is the floor
	# under that: any way into the menu that skipped the bootstrap (the editor's "run current
	# scene", a tool, a future entry point) gets a loaded manager rather than a menu full of
	# defaults that also refuses to save. Idempotent, so the normal path pays nothing.
	SaveManager.initialize()

	UIPalette.style(_tagline, UIPalette.TEXT_DIM)
	_tagline.text = "SHIFT ONE  //  HELP DESK  //  NO OVERTIME AUTHORISED"

	AudioManager.play_music(&"menu")

	_build_buttons()
	_refresh_records()

	_settings.closed.connect(_on_panel_closed)
	_controls.closed.connect(_on_panel_closed)

	# A first-time player is shown the controls before anything else, because the firing
	# scheme is the one thing they cannot discover by pressing keys. Everyone else gets the
	# menu, and can open the card from it.
	if not SaveManager.tutorial_completed:
		_controls.open()
	else:
		_focus_first()


func _build_buttons() -> void:
	var entries := BUTTONS.duplicate()
	# The label carries the floor and the elapsed time, because "CONTINUE" alone does not say
	# *what*: a player coming back the next day needs to recognise the run before they commit to
	# it, and the alternative is loading it to find out.
	#
	# Offered on the checkpoint merely existing. Whether it can be played is decided against the
	# campaign, which this screen deliberately does not load — see `main.gd._resolve_checkpoint`,
	# which refuses an unplayable one and puts the player back here without it.
	if SaveManager.has_checkpoint():
		var checkpoint := SaveManager.get_checkpoint()
		entries.insert(CONTINUE_INDEX, [
			"%s  %s" % [CONTINUE_LABEL, checkpoint.describe()], "_on_continue_pressed",
		])

	for entry: Array in entries:
		var button := Button.new()
		button.text = FOCUS_PADDING + (entry[0] as String)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(Callable(self, entry[1] as String))
		button.focus_entered.connect(_on_button_focused.bind(button, entry[0] as String))
		button.focus_exited.connect(_on_button_unfocused.bind(button, entry[0] as String))
		# Hovering moves focus rather than merely highlighting, so the mouse and the gamepad
		# can never disagree about which entry is selected.
		button.mouse_entered.connect(button.grab_focus)
		_buttons.add_child(button)


func _focus_first() -> void:
	if _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Button).grab_focus()


func _on_button_focused(button: Button, label: String) -> void:
	button.text = FOCUS_MARKER + label
	AudioManager.play_sfx(&"ui_move")


func _on_button_unfocused(button: Button, label: String) -> void:
	button.text = FOCUS_PADDING + label


## Two lines rather than a panel: a table of personal bests is what a player glances at on
## the way past, not something they sit and read. Hidden entirely until there is a run to
## report, because a column of zeroes tells a new player only that they are new.
func _refresh_records() -> void:
	var best := SaveManager.best
	var has_history := best.has_history()
	_records_upper.visible = has_history
	_records_lower.visible = has_history
	if not has_history:
		return

	UIPalette.style(_records_upper, UIPalette.TEXT_FAINT)
	UIPalette.style(_records_lower, UIPalette.TEXT_FAINT)

	var best_time := (
		RunStats.format_duration(best.fastest_victory) if best.fastest_victory > 0.0 else "--:--"
	)
	_records_upper.text = "RUNS %d    VICTORIES %d    BEST TIME %s" % [
		best.runs_started, best.runs_won, best_time,
	]
	_records_lower.text = "MOST ROOMS %d    MOST SCRAP %d    HIGHEST HIT %.1f" % [
		best.most_rooms_cleared, best.most_scrap_collected, best.highest_hit,
	]


## Focus is returned deliberately when a panel closes. A menu whose keyboard focus is nowhere
## looks identical to one that has stopped responding.
func _on_panel_closed() -> void:
	_refresh_records()
	_focus_first()


func _on_continue_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	SceneRouter.resume_run()


## Starts a fresh run, and throws away a saved one if there was one. No confirmation: the entry
## below CONTINUE says START RUN, the saved run is named on the entry above it, and a title screen
## that asks "are you sure?" for its most-pressed button is a worse trade than the rare misclick.
## The checkpoint is cleared by `RunManager.begin_run`, which is the one place a new run begins.
func _on_start_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	SceneRouter.start_run()


func _on_controls_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	_controls.open()


func _on_settings_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	_settings.open()


## No sound: quitting takes effect at the end of this frame, so a click here would be cut off
## before it was audible — and a stream still playing at teardown leaks it.
func _on_quit_pressed() -> void:
	SceneRouter.quit_game()

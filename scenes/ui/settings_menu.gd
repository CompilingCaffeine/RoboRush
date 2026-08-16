class_name SettingsMenu
extends Control
## Spec section 21's eight settings, as a screen.
##
## One panel, instanced by both the title screen and the pause menu, because the settings a
## player wants to change mid-run are the same eight they wanted to change before it. Drawn
## *over* whichever screen opened it and returning there when dismissed, which is why
## settings is not one of `GameManager`'s states: there is no "where do I go back to" to get
## wrong.
##
## Rows are declared rather than laid out. Eight settings hand-built would be eight near
## identical blocks of code, and the ninth would be the one that forgets to save. Here a
## setting is a label, a kind, and a pair of callables, and everything else — the bar, the
## navigation, the persistence — is shared.
##
## Navigation is a list, not a set of focusable widgets. Godot's sliders and check boxes are
## built for a mouse at desktop resolution, and at 480x270 they look like they belong to a
## different program. A list where up and down choose and left and right adjust is also the
## scheme a gamepad expects (spec section 5), so there is one interaction to learn and it
## works on both.

## Emitted when the player dismisses the panel. Whoever opened it decides what that means.
signal closed

enum Kind {
	## A 0..maximum value, adjusted with left and right.
	RANGE,
	## On or off, flipped with left, right, or accept.
	TOGGLE,
	## A row that does something when accepted. Only "back" is one.
	ACTION,
}

## Cells in the bar drawn beside a RANGE row. Ten is enough to see a change of one step and
## few enough to read without counting.
const BAR_CELLS := 10

const BAR_FILLED := "#"
const BAR_EMPTY := "-"

## Volumes step by a tenth, intensities by a quarter. Intensities are coarser because the
## difference between 100% and 110% screen shake is not a thing anyone can perceive, and a
## setting whose steps do nothing visible feels broken.
const VOLUME_STEP := 0.1
const INTENSITY_STEP := 0.25

## How wide the name column is, in characters. Fixed so the bars line up into a column, which
## is most of what makes a settings screen look designed rather than assembled.
const NAME_COLUMNS := 16

@onready var _rows_box: VBoxContainer = %Rows
@onready var _hint: Label = %Hint

var _rows: Array[Dictionary] = []
var _row_labels: Array[Label] = []
var _selected := 0


func _ready() -> void:
	# The pause menu opens this while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UIPalette.style(_hint, UIPalette.TEXT_FAINT)
	_hint.text = "UP DOWN SELECT    LEFT RIGHT ADJUST    ESC BACK"
	_build_rows()


func open() -> void:
	# See ControlsCard.open: a modal hidden while the browser was still deciding how big the canvas
	# is keeps an empty rect, and opens as a sliver in the corner until it is told to fill its
	# parent again.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	_selected = 0
	_refresh()
	# The button that opened this panel still holds keyboard focus, and Godot's focus
	# navigation runs before `_unhandled_input` — so without this the first press of down
	# moves the *hidden* menu's selection and never reaches the panel. Found by driving the
	# menus with synthetic keys: the second row was being adjusted while the first was
	# highlighted.
	get_viewport().gui_release_focus()


func close() -> void:
	visible = false
	# Committed on the way out as well as on every change. The debounced write means a player
	# who changes one setting and quits within half a second would otherwise lose it.
	SaveManager.save_game()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if _is_pressed(event, "ui_cancel") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return

	if _is_pressed(event, "ui_down") or event.is_action_pressed("move_down"):
		_move_selection(1)
	elif _is_pressed(event, "ui_up") or event.is_action_pressed("move_up"):
		_move_selection(-1)
	elif _is_pressed(event, "ui_right") or event.is_action_pressed("move_right"):
		_adjust(1)
	elif _is_pressed(event, "ui_left") or event.is_action_pressed("move_left"):
		_adjust(-1)
	elif _is_pressed(event, "ui_accept"):
		_activate()
	else:
		return

	# Anything the panel recognised stops here. This is the whole of spec section 23's "do not
	# allow input to leak between UI and gameplay states": while this is up, it eats the keys
	# it uses and the game below never sees them.
	get_viewport().set_input_as_handled()


## Menu actions accept the arrow keys and the d-pad through Godot's built-in `ui_*` actions,
## and WASD through the game's own movement actions. Both because a player who has just spent
## ten minutes moving with WASD should not have to work out that menus are different.
func _is_pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


## Declares the eight settings from spec section 21, in the order a player looks for them:
## the ones they will change first at the top.
##
## Every closure re-reads `SaveManager.settings` rather than capturing it, because loading a
## save replaces that object wholesale — a captured reference would edit the settings the
## game had at boot and silently stop affecting anything.
func _build_rows() -> void:
	_rows = [
		_range_row("MASTER VOLUME", GameSettings.VOLUME_MAX, VOLUME_STEP,
			func() -> float: return SaveManager.settings.master_volume,
			func(value: float) -> void: SaveManager.settings.master_volume = value),
		_range_row("MUSIC VOLUME", GameSettings.VOLUME_MAX, VOLUME_STEP,
			func() -> float: return SaveManager.settings.music_volume,
			func(value: float) -> void: SaveManager.settings.music_volume = value),
		_range_row("EFFECTS VOLUME", GameSettings.VOLUME_MAX, VOLUME_STEP,
			func() -> float: return SaveManager.settings.sfx_volume,
			func(value: float) -> void: SaveManager.settings.sfx_volume = value),
		_range_row("SCREEN SHAKE", GameSettings.INTENSITY_MAX, INTENSITY_STEP,
			func() -> float: return SaveManager.settings.screen_shake,
			func(value: float) -> void: SaveManager.settings.screen_shake = value),
		_range_row("FLASH INTENSITY", GameSettings.INTENSITY_MAX, INTENSITY_STEP,
			func() -> float: return SaveManager.settings.flash_intensity,
			func(value: float) -> void: SaveManager.settings.flash_intensity = value),
		_toggle_row("DAMAGE NUMBERS",
			func() -> bool: return SaveManager.settings.damage_numbers,
			func(value: bool) -> void: SaveManager.settings.damage_numbers = value),
		_toggle_row("CRT FILTER",
			func() -> bool: return SaveManager.settings.crt_enabled,
			func(value: bool) -> void: SaveManager.settings.crt_enabled = value),
		_toggle_row("FULLSCREEN",
			func() -> bool: return SaveManager.settings.fullscreen,
			func(value: bool) -> void: SaveManager.settings.fullscreen = value),
		{"label": "BACK", "kind": Kind.ACTION},
	]

	for _row: Dictionary in _rows:
		var label := UIPalette.make_label("", UIPalette.TEXT)
		_rows_box.add_child(label)
		_row_labels.append(label)


func _range_row(
	label: String, maximum: float, step: float, getter: Callable, setter: Callable
) -> Dictionary:
	return {
		"label": label,
		"kind": Kind.RANGE,
		"max": maximum,
		"step": step,
		"get": getter,
		"set": setter,
	}


func _toggle_row(label: String, getter: Callable, setter: Callable) -> Dictionary:
	return {"label": label, "kind": Kind.TOGGLE, "get": getter, "set": setter}


func _move_selection(delta: int) -> void:
	# Wraps, because a list of nine that stops at both ends makes the player travel the whole
	# way back to reach "back".
	_selected = wrapi(_selected + delta, 0, _rows.size())
	_refresh()
	AudioManager.play_sfx(&"ui_move")


func _adjust(direction: int) -> void:
	var row := _rows[_selected]
	match row["kind"] as Kind:
		Kind.RANGE:
			var step: float = row["step"] * direction
			var maximum: float = row["max"]
			var current: float = row["get"].call()
			var updated := snappedf(clampf(current + step, 0.0, maximum), row["step"])
			if is_equal_approx(updated, current):
				return
			row["set"].call(updated)
		Kind.TOGGLE:
			row["set"].call(not row["get"].call())
		Kind.ACTION:
			return

	SaveManager.commit_settings()
	_refresh()
	AudioManager.play_sfx(&"ui_move")


func _activate() -> void:
	var row := _rows[_selected]
	match row["kind"] as Kind:
		Kind.ACTION:
			AudioManager.play_sfx(&"ui_confirm")
			close()
		Kind.TOGGLE:
			_adjust(1)
		Kind.RANGE:
			# Accept on a slider does nothing rather than jumping to an end. A player pressing
			# it is confirming, not asking for maximum volume.
			pass


func _refresh() -> void:
	for index: int in _rows.size():
		var row := _rows[index]
		var chosen := index == _selected
		var label := _row_labels[index]
		label.text = "%s %s" % ["> " if chosen else "  ", _describe(row)]
		UIPalette.style(label, UIPalette.ACCENT if chosen else UIPalette.TEXT_DIM)


func _describe(row: Dictionary) -> String:
	var label: String = row["label"]
	match row["kind"] as Kind:
		Kind.ACTION:
			return label
		Kind.TOGGLE:
			return "%s %s" % [label.rpad(NAME_COLUMNS), "ON" if row["get"].call() else "OFF"]
		_:
			var value: float = row["get"].call()
			var maximum: float = row["max"]
			var filled := int(roundf(value / maximum * BAR_CELLS))
			var bar := BAR_FILLED.repeat(filled) + BAR_EMPTY.repeat(BAR_CELLS - filled)
			return "%s [%s] %3d%%" % [label.rpad(NAME_COLUMNS), bar, int(roundf(value * 100.0))]

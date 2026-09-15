class_name LeaderboardPanel
extends Control
## The global board of fastest victories, as a screen.
##
## Read-only, and deliberately so. Everything that decides what reaches the board lives in
## `Leaderboard`; this asks for a page and draws it. It cannot post, retry, or fail in a way that
## costs the player anything, which is what lets it be opened and closed without ceremony.
##
## Three things it has to get right, and they are all about honesty rather than layout:
##
## - A board that has not answered yet must not look like a board with nobody on it. An empty grid
##   under a title is indistinguishable from "you are the only player", and that is a lie the game
##   would be telling on every slow connection.
## - A player who is not signed in is told what would let them compete, not that something broke.
##   Nothing did.
## - A player outside the top ten is still shown their own row. `Leaderboard.fetch_top` fetches it
##   separately for exactly this, because a board that cannot tell somebody where they stand is a
##   board they look at once.

signal closed

## Columns are laid out by padding rather than by a GridContainer, because the font is a bitmap
## face and the three parts of a row have to line up as a *column* of text — which a grid sized to
## its widest cell does only by accident.
const RANK_COLUMNS := 3
const NAME_COLUMNS := 16

## The longest name the board will draw before it is cut short. A display name is whatever somebody
## typed on another website; unbounded, one of them turns every row below it into a different
## layout.
const NAME_LIMIT := NAME_COLUMNS - 1
const ELLIPSIS := "."

## Drawn between the top of the board and the player's own row when they are not in it. A gap alone
## reads as a rendering fault; a line reads as "the board continues".
const BREAK := "..."

@onready var _rows: VBoxContainer = %Rows
@onready var _status: Label = %Status
@onready var _hint: Label = %Hint

## Bumped every time the panel is opened or closed. A fetch is a network round trip and the player
## can close the panel during it; the reply that arrives afterwards belongs to a screen that is no
## longer there, and drawing it would repopulate a hidden panel — or a reopened one, with the
## previous visit's board.
var _generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UIPalette.style(_hint, UIPalette.TEXT_FAINT)
	_hint.text = "ESC BACK"
	Leaderboard.status_changed.connect(_on_status_changed)


func open() -> void:
	# See `ControlsCard.open`: a modal hidden while the browser was still deciding how big the
	# canvas is keeps an empty rect, and opens as a sliver in the corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	# See `SettingsMenu.open`: the button that opened this still holds focus, and Godot's focus
	# navigation runs before `_unhandled_input`.
	get_viewport().gui_release_focus()
	_generation += 1
	_refresh(_generation)


func close() -> void:
	if not visible:
		return
	visible = false
	_generation += 1
	AudioManager.play_sfx(&"ui_back")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Dismissed by back or by accept. There is nothing to choose on this screen, so insisting on one
	# particular key would only be a rule to learn.
	if (
		(InputMap.has_action("ui_cancel") and event.is_action_pressed("ui_cancel"))
		or event.is_action_pressed("pause")
		or (InputMap.has_action("ui_accept") and event.is_action_pressed("ui_accept"))
	):
		close()
	get_viewport().set_input_as_handled()


## See `ControlsCard._gui_input`: the root blocks the mouse so clicks cannot reach the menu
## underneath, which means a click never becomes unhandled input.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		close()
		accept_event()


## Asks for a page and draws whatever comes back.
##
## `generation` is the panel's generation at the moment the request went out. Anything that does not
## match by the time it returns is a reply to a question nobody is still asking.
func _refresh(generation: int) -> void:
	_clear()
	_set_status("LOADING BOARD...", UIPalette.TEXT_FAINT)

	var page: Dictionary = await Leaderboard.fetch_top()
	if generation != _generation:
		return

	if not page.get("success", false):
		# `Leaderboard` already knows why — signed out, never connected, refused — and says so in
		# the player's language. Repeating the platform's message here would put a network error in
		# front of somebody who only wanted to see a list of times.
		_set_status(Leaderboard.status_text(), UIPalette.TEXT_DIM)
		return

	var entries: Array = page.get("entries", [])
	if entries.is_empty():
		_set_status("NOBODY HAS FINISHED THE CAMPAIGN YET", UIPalette.WARN)
		return

	_set_status("", UIPalette.TEXT_FAINT)
	for entry: Variant in entries:
		_add_row(entry as Dictionary)

	var you: Dictionary = page.get("you", {})
	if not you.is_empty():
		_rows.add_child(UIPalette.make_label(BREAK, UIPalette.TEXT_FAINT))
		_add_row(you)


func _add_row(entry: Dictionary) -> void:
	var rank := int(entry.get("rank", 0))
	var line := "%s %s %s" % [
		# A rank the platform did not send is left blank rather than printed as zero: a row numbered
		# zero looks like a bug, and a blank one looks like what it is.
		(str(rank) if rank > 0 else "").lpad(RANK_COLUMNS),
		_fit(str(entry.get("name", ""))).rpad(NAME_COLUMNS),
		Leaderboard.format_score(int(entry.get("score_ms", 0))),
	]
	# The player's own row in the accent colour, which is the colour this game uses everywhere else
	# for "this one is yours".
	var is_you: bool = entry.get("is_you", false) == true
	_rows.add_child(UIPalette.make_label(line, UIPalette.ACCENT if is_you else UIPalette.TEXT_DIM))


func _fit(name: String) -> String:
	if name.length() <= NAME_COLUMNS:
		return name
	return name.substr(0, NAME_LIMIT) + ELLIPSIS


func _clear() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	UIPalette.style(_status, color)


## Redrawn when the coordinator's state changes underneath an open panel — a time that finishes
## posting while the player is looking at the board moves them up it, and a board still showing the
## page from before is a board that is wrong.
func _on_status_changed(status: Leaderboard.Status) -> void:
	if visible and status == Leaderboard.Status.READY:
		_generation += 1
		_refresh(_generation)

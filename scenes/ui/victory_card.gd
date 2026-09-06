class_name VictoryCard
extends Control
## The end of the campaign, said out loud. Shown once, over everything, when the trophy is taken.
##
## Before this the reward for sixty rooms and six bosses was the same grey statistics panel a
## death produces, with a different two-word headline at the top of it — "SYSTEM RESTORED" where
## a loss says "SYSTEM FAILURE". Both are true and neither is a celebration, and the screen that
## follows the hardest thing in the game should not be the screen that follows the easiest way to
## lose it.
##
## So the summary is still there and still unchanged; this goes in front of it for as long as the
## player wants to look at it. It is dismissed by any button, exactly as `ControlsCard` is, and for
## the same reason: a screen that says "press any button" and then insists on one particular button
## is worse than no screen. Behind it the summary is already built, already focused, and waiting.
##
## Runs with PROCESS_MODE_ALWAYS. Victory pauses the tree, so a card that stopped with it would be
## a still image of a trophy over a frozen game — no confetti, no shine, no way to dismiss it.

## Emitted when the player has dismissed it, so whoever put it up can hand focus back to the
## screen underneath. `main.gd` is the only listener, and does exactly that.
signal closed

const TITLE := "YOU WIN!"

## Two lines, and both of them about the run rather than about the game. The first is what the
## player did; the second is what they now have, which is the thing the title screen will be
## holding the next time they open it.
const MESSAGE := """CORE INTELLIGENCE IS DOWN AND THE BUILDING IS YOURS.
SIX FLOORS, SIX BOSSES, ONE OBSOLETE MAINTENANCE ROBOT."""

const HINT := "PRESS ANY BUTTON"

## How far the trophy swells and shrinks, as a fraction of its size, and how fast. The same
## slow breath the trophy has on the arena floor (see `Trophy.SHINE_HZ`), so the object the
## player picked up and the object on this screen read as the same object.
const TROPHY_PULSE := 0.08
const TROPHY_HZ := 0.55

## The confetti. Drawn rather than instanced: sixty-four nodes with scripts on them, created at
## the one moment the engine is already tearing a floor down and pausing the tree, buys nothing
## over sixty-four rectangles in an array.
const CONFETTI_COUNT := 64
const CONFETTI_MIN_SIZE := 3.0
const CONFETTI_MAX_SIZE := 7.0
const CONFETTI_MIN_FALL := 26.0
const CONFETTI_MAX_FALL := 78.0
const CONFETTI_DRIFT := 18.0

## How fast a piece rocks from side to side, in cycles per second. Randomised per piece within
## this range, because confetti that all swings in phase is a curtain rather than confetti.
const CONFETTI_SWAY_MIN := 0.4
const CONFETTI_SWAY_MAX := 1.1

## Paper colours: the interface's own three, plus the trophy's gold. Nothing new is introduced for
## one screen — see `UIPalette`, which is where the game's colours live and why.
const CONFETTI_COLORS: Array[Color] = [
	UIPalette.ACCENT,
	UIPalette.WARN,
	Color("ffd23c"),
	UIPalette.TEXT,
]

## Nearly opaque, and drawn here rather than by a ColorRect behind the confetti. A Control paints
## itself before its children, so a backdrop that was a child node was a backdrop *over* the paper —
## which is what made the first version's confetti look like dust. Painting both in `_draw`, in
## order, puts the paper in front of the ground and still behind every label.
##
## Opaque, unlike every other panel in the game. The statistics screen underneath is a wall of
## numbers under a heading that also says the run was won, and even a few percent of it showing
## through reads as a rendering fault rather than as a layer. It is a celebration; it gets the
## whole screen.
const BACKDROP := Color(0.02, 0.03, 0.05, 1.0)

@onready var _title: Label = %Title
@onready var _trophy: TextureRect = %Trophy
@onready var _message: Label = %Message
@onready var _hint: Label = %Hint

var _elapsed := 0.0

## One entry per piece of paper: position, fall speed, sway phase and rate, half-size, colour.
## A plain array of dictionaries rather than a class, because nothing outside this file ever sees
## one and the whole of their behaviour is the six lines in `_process`.
var _confetti: Array[Dictionary] = []

## Its own generator, seeded from the clock. Deliberately *not* the run's RNG: this is the one
## thing on screen that has no business being reproducible, and drawing from a run stream here
## would make the confetti a reason a `--seed` stopped reproducing a run.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)

	UIPalette.style(_title, UIPalette.ACCENT, UIPalette.FONT_SIZE_TITLE)
	_title.text = TITLE
	UIPalette.style(_message, UIPalette.TEXT_DIM)
	_message.text = MESSAGE
	UIPalette.style(_hint, UIPalette.TEXT_FAINT)
	_hint.text = HINT
	_trophy.pivot_offset = _trophy.custom_minimum_size * 0.5

	_rng.randomize()
	GameManager.state_changed.connect(_on_state_changed)


func open() -> void:
	if visible:
		return
	# Re-anchored on the way up, for the reason `ControlsCard.open` gives at length: a Control that
	# was hidden while its parent learned its real size never re-anchored, and in the browser build
	# that is a full-screen modal drawn as a zero-size box in the corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	set_process(true)
	_elapsed = 0.0
	_scatter_confetti()

	# Deferred, and this is the whole of why: `RunSummary` answers the same state change by
	# grabbing focus for its RETRY button, and the two handlers run in tree order in the same
	# frame. Releasing focus inline would be undone by whichever of them happens to run second,
	# leaving a focused button under a modal — where `ui_accept` is Space, Space is dash, and a
	# player mashing to read the next screen would restart the run they just won. A deferred call
	# is flushed after every handler in the frame, whatever order they ran in.
	_release_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	AudioManager.play_sfx(&"ui_confirm")
	closed.emit()


func _release_focus() -> void:
	if visible and is_inside_tree():
		get_viewport().gui_release_focus()


## Only the win. A loss has its own screen and always has; this one exists because that screen was
## being asked to do two opposite jobs.
func _on_state_changed(state: GameManager.State) -> void:
	if state == GameManager.State.VICTORY:
		open()
	elif visible:
		# A new run started underneath it — RETRY, or a restart from anywhere. Closed rather than
		# left up, because nothing else would ever take it down.
		close()


func _process(delta: float) -> void:
	_elapsed += delta

	var pulse := 1.0 + sin(_elapsed * TAU * TROPHY_HZ) * TROPHY_PULSE
	_trophy.scale = Vector2(pulse, pulse)

	for piece: Dictionary in _confetti:
		# Read, moved, written back, rather than assigned through the dictionary in place: a
		# Vector2 in a Dictionary is a value, and mutating a copy of it is the kind of line that
		# looks like it works and animates nothing.
		var position: Vector2 = piece["position"]
		var sway: float = piece["sway"]
		position.y += float(piece["fall"]) * delta
		position.x += sin(_elapsed * TAU * sway + float(piece["phase"])) * CONFETTI_DRIFT * delta
		if position.y > size.y + CONFETTI_MAX_SIZE:
			# Recycled off the top rather than removed, so the celebration lasts as long as the
			# player looks at it. A finite burst runs out while they are still reading.
			position = Vector2(_rng.randf() * size.x, -CONFETTI_MAX_SIZE)
		piece["position"] = position
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	for piece: Dictionary in _confetti:
		var extent: float = piece["size"]
		var corner: Vector2 = (piece["position"] as Vector2) - Vector2(extent, extent) * 0.5
		draw_rect(Rect2(corner, Vector2(extent, extent * 0.6)), piece["color"])


## Fills the screen at the moment the card opens, rather than dropping everything from the top
## edge. A celebration that begins with an empty screen and fills over two seconds is a
## celebration the player has already stopped watching.
func _scatter_confetti() -> void:
	_confetti.clear()
	for index: int in CONFETTI_COUNT:
		_confetti.append({
			"position": Vector2(_rng.randf() * size.x, _rng.randf() * size.y),
			"fall": _rng.randf_range(CONFETTI_MIN_FALL, CONFETTI_MAX_FALL),
			"sway": _rng.randf_range(CONFETTI_SWAY_MIN, CONFETTI_SWAY_MAX),
			"phase": _rng.randf() * TAU,
			"size": _rng.randf_range(CONFETTI_MIN_SIZE, CONFETTI_MAX_SIZE),
			"color": CONFETTI_COLORS[_rng.randi() % CONFETTI_COLORS.size()],
		})


## Dismissed by anything, and every event is consumed while it is up so nothing behind it acts on
## the press that dismissed it. Copied in shape from `ControlsCard`, which is the game's other
## full-screen modal, so the two are dismissed the same way.
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


## Mouse clicks arrive here rather than in `_unhandled_input`: this Control blocks the mouse so
## clicks cannot reach the summary's buttons underneath, and a Control that consumes a click has
## already handled it by the time unhandled input is offered.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		close()
		accept_event()

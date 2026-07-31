class_name DebugHUD
extends Control
## Milestone 1 diagnostics overlay: position, velocity, speed, aim, and dash state
## (spec section 32.10), plus a short control reminder.
##
## Values are polled from the player each frame rather than pushed over signals —
## every one of them changes on every tick, so polling is both simpler and cheaper
## than a signal per value. Dash *events* do arrive over the EventBus, which keeps
## the overlay decoupled from the player's component subtree and exercises that
## path while it is still cheap to get wrong.
##
## Rows are built in code as label pairs in a GridContainer. Godot ships no
## monospace font, so column alignment comes from the layout rather than from
## padding strings that a proportional font would misalign anyway.

const FONT_SIZE := 8
const TITLE_COLOR := Color("f2a13c")
const NAME_COLOR := Color("7c8a99")
const VALUE_COLOR := Color("58f0c8")
const HINT_COLOR := Color("6d7a8c")

@onready var _grid: GridContainer = %Grid
@onready var _title: Label = %Title
@onready var _hint: Label = %Hint

var _player: Player
var _values: Dictionary[String, Label] = {}
var _dash_count := 0
var _last_dash_direction := Vector2.ZERO


func _ready() -> void:
	_style_label(_title, TITLE_COLOR)
	_style_label(_hint, HINT_COLOR)
	_title.text = "ROBO RUSH // DIAGNOSTICS"
	_hint.text = "WASD MOVE   MOUSE AIM   SPACE DASH   F1 HIDE"

	for row_name: String in ["FPS", "POS", "VEL", "SPEED", "MOVE IN", "AIM", "DASH", "RECHARGE", "DASHES"]:
		_values[row_name] = _add_row(row_name)

	EventBus.player_dash_started.connect(_on_player_dash_started)


func _process(_delta: float) -> void:
	if not visible or _player == null:
		return
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_hud"):
		visible = not visible
		get_viewport().set_input_as_handled()


func bind_player(player: Player) -> void:
	_player = player


func _refresh() -> void:
	var dash := _player.get_dash_controller()
	var player_input := _player.get_input_component()
	# Named to avoid shadowing Control.position / this node's own properties.
	var player_position := _player.global_position
	var player_velocity := _player.velocity

	_set_value("FPS", "%d" % Engine.get_frames_per_second())
	_set_value("POS", "%.0f, %.0f" % [player_position.x, player_position.y])
	_set_value("VEL", "%+.0f, %+.0f" % [player_velocity.x, player_velocity.y])
	_set_value("SPEED", "%.0f px/s" % player_velocity.length())
	_set_value("MOVE IN", "%+.2f, %+.2f" % [
		player_input.move_vector.x, player_input.move_vector.y,
	])
	_set_value("AIM", "%d deg  %s" % [
		roundi(rad_to_deg(player_input.aim_direction.angle())),
		"PAD" if player_input.is_aiming_with_gamepad else "MOUSE",
	])
	_set_value("DASH", "%s  %d/%d%s" % [
		"ACTIVE" if dash.is_dashing else "READY" if dash.can_dash() else "SPENT",
		dash.charges_available,
		dash.get_max_charges(),
		"  INVULN" if dash.is_invulnerable() else "",
	])
	_set_value("RECHARGE", "%.2fs" % dash.get_recharge_remaining())
	_set_value("DASHES", "%d  last %+.1f, %+.1f" % [
		_dash_count, _last_dash_direction.x, _last_dash_direction.y,
	])


func _set_value(row_name: String, value: String) -> void:
	_values[row_name].text = value


func _add_row(row_name: String) -> Label:
	var name_label := Label.new()
	name_label.text = row_name
	_style_label(name_label, NAME_COLOR)
	_grid.add_child(name_label)

	var value_label := Label.new()
	_style_label(value_label, VALUE_COLOR)
	_grid.add_child(value_label)
	return value_label


func _style_label(label: Label, color: Color) -> void:
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)


func _on_player_dash_started(direction: Vector2) -> void:
	_dash_count += 1
	_last_dash_direction = direction

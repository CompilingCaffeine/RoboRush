class_name DebugHUD
extends Control
## Developer diagnostics overlay: movement, dash, aim, combat, and room state.
##
## Values are polled from the player each frame rather than pushed over signals —
## every one of them changes on every tick, so polling is both simpler and cheaper
## than a signal per value. Dash *events* do arrive over the EventBus, which keeps the
## overlay decoupled from the player's component subtree.
##
## Rows are built in code as label pairs in a GridContainer. Godot ships no monospace
## font, so column alignment comes from the layout rather than from padding strings
## that a proportional font would misalign anyway.

const FONT_SIZE := 8
const TITLE_COLOR := Color("f2a13c")
const NAME_COLOR := Color("7c8a99")
const VALUE_COLOR := Color("58f0c8")
const HINT_COLOR := Color("6d7a8c")

const ROWS: Array[String] = [
	"FPS",
	"POS",
	"VEL",
	"SPEED",
	"MOVE IN",
	"AIM",
	"SHOOT IN",
	"DASH",
	"RECHARGE",
	"INTEGRITY",
	"WEAPON",
	"SHOTS",
	"ENEMIES",
	"ROOM",
	"FLOOR",
]

@onready var _grid: GridContainer = %Grid
@onready var _title: Label = %Title
@onready var _hint: Label = %Hint

var _player: Player
var _floor: FloorController
var _values: Dictionary[String, Label] = {}
var _dash_count := 0
var _last_dash_direction := Vector2.ZERO


func _ready() -> void:
	_style_label(_title, TITLE_COLOR)
	_style_label(_hint, HINT_COLOR)
	_title.text = "ROBO RUSH // DIAGNOSTICS"
	_hint.text = "WASD MOVE   ARROWS SHOOT   SPACE DASH   F1 HIDE"

	for row_name: String in ROWS:
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


func bind_floor(floor_controller: FloorController) -> void:
	_floor = floor_controller


func _refresh() -> void:
	var dash := _player.get_dash_controller()
	var player_input := _player.get_input_component()
	var health := _player.get_health_component()
	var weapon := _player.get_weapon_controller()
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
		"FIRING" if player_input.is_firing() else "held",
	])
	_set_value("SHOOT IN", "%+.2f, %+.2f" % [
		player_input.shoot_vector.x, player_input.shoot_vector.y,
	])
	_set_value("DASH", "%s  %d/%d%s" % [
		"ACTIVE" if dash.is_dashing else "READY" if dash.can_dash() else "SPENT",
		dash.charges_available,
		dash.get_max_charges(),
		"  INVULN" if dash.is_invulnerable() else "",
	])
	_set_value("RECHARGE", "%.2fs" % dash.get_recharge_remaining())
	_set_value("INTEGRITY", "%.1f/%.0f%s" % [
		health.current,
		health.max_health,
		"  INVULN" if health.is_invulnerable() else "",
	])
	_set_value("WEAPON", "%s  %s" % [
		weapon.config.display_name if weapon.config != null else "none",
		"READY" if weapon.can_fire() else "%.2fs" % weapon.get_cooldown_remaining(),
	])
	_set_value("SHOTS", "%d  dashes %d  last %+.1f, %+.1f" % [
		weapon.get_shots_fired(), _dash_count,
		_last_dash_direction.x, _last_dash_direction.y,
	])
	_set_value("ENEMIES", _describe_enemies())
	_set_value("ROOM", _describe_room())
	_set_value("FLOOR", "%s  seed %d  scrap %d" % [
		RunManager.floor_name, RunManager.floor_seed, RunManager.scrap,
	])


func _describe_enemies() -> String:
	var room := _floor.get_current_room() if _floor != null else null
	if room == null:
		return "no room"
	var combat := room.get_room_combat()
	return "%d/%d alive%s" % [
		combat.get_alive_count(),
		combat.get_initial_count(),
		"  CLEARED" if combat.is_cleared() else "",
	]


func _describe_room() -> String:
	if _floor == null or _floor.layout == null:
		return "no floor"
	var room := _floor.get_current_room()
	if room == null:
		return "outside"
	return "#%d %s cell %v  %d/%d visited" % [
		room.plan.id,
		RoomTemplate.Type.keys()[room.plan.type],
		room.plan.cell,
		_floor.visited.size(),
		_floor.layout.rooms.size(),
	]


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

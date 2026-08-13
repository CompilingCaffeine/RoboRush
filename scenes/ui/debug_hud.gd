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
	"HOSTILES",
	"LOAD",
	"TARGETING",
	"ROOM",
	"FLOOR",
	"SEED",
	"CONTENT",
	"ITEMS",
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
	# Hidden until asked for. It was visible by default through milestone 5, which was right
	# while the only person launching the game was the one writing it and wrong the moment
	# anyone else does: it covers a third of a 480x270 screen, and a new player has no idea
	# it is an overlay rather than the game. F1 brings it back.
	visible = false

	_style_label(_title, TITLE_COLOR)
	_style_label(_hint, HINT_COLOR)
	_title.text = "ROBO RUSH // DIAGNOSTICS"
	_hint.text = "WASD MOVE   ARROWS SHOOT   SPACE DASH   F1 HIDE"

	for row_name: String in ROWS:
		_values[row_name] = _add_row(row_name)

	EventBus.player_dash_started.connect(_on_player_dash_started)


func _process(_delta: float) -> void:
	# Targeting only counts itself while somebody is watching, and this is the only watcher.
	Targeting.instrumented = visible
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
	_set_value("HOSTILES", _describe_hostiles())
	_set_value("LOAD", _describe_load())
	_set_value("TARGETING", _describe_targeting())
	_set_value("ROOM", _describe_room())
	_set_value("FLOOR", "%s  %d  scrap %d" % [
		RunManager.floor_name, RunManager.floor_number, RunManager.scrap,
	])
	_set_value("SEED", _describe_seeds())
	_set_value("CONTENT", _describe_content())
	_set_value("ITEMS", _describe_items())


## What the targeting registry is holding: the bodies a shot can currently find, against every body
## that has registered. The gap between them is the floor asleep in the other nine rooms, and it is
## the whole point of the registry — a large gap costs nothing, where it used to cost every query.
func _describe_hostiles() -> String:
	return "%d awake  %d known" % [
		HostileRegistry.count(Teams.Id.ENEMY), HostileRegistry.known_count(),
	]


## Frame cost and what is standing in the world producing it. Process and physics are separated
## because the scaling plan budgets them separately, and nodes and memory are here because the
## failure they catch — a floor boundary leaking a room's worth of objects — is invisible in a frame
## time until it is far too late.
func _describe_load() -> String:
	return "%.1f+%.1fms  %d nodes  %dMB" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		get_tree().get_node_count(),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
	]


## Target selection, per frame: how many shots asked and what it cost them. The counters are only
## collected while this overlay is up — see `Targeting.instrumented` — so reading them is free for
## everybody who is not looking at them.
func _describe_targeting() -> String:
	var queries := Targeting.queries
	var usec := Targeting.query_usec
	Targeting.reset_instrumentation()
	return "%d queries  %.2fms" % [queries, float(usec) / 1000.0]


## The two numbers a reproducible bug report needs, in the order they matter: the run's seed, which
## is what `--seed=` takes, and this floor's, which is what it derives to.
##
## Both, rather than only the floor's. The floor seed used to be the only one shown, and by floor
## three it was three `hash()` steps away from anything a player could type back in — a number that
## looked reproducible and was not. It is still worth showing next to the run seed, because it is
## what the floor's own streams come from and what a generation bug is filed against.
func _describe_seeds() -> String:
	return "run %d  floor %d" % [RunManager.get_run_seed(), RunManager.floor_seed]


## Which content this floor's seed was spent on: the campaign, its version, and a fingerprint of
## this floor in particular (see `RunManifest`). Turns a screenshot into something reproducible — the
## same seed on a different content build is a different floor, and this is the line that says so.
func _describe_content() -> String:
	var campaign := String(RunManager.get_campaign_id())
	var fingerprint := _floor.get_content_fingerprint() if _floor != null else ""
	return "%s v%d  %s" % [
		campaign if not campaign.is_empty() else "no campaign",
		RunManager.get_content_version(),
		fingerprint if not fingerprint.is_empty() else "-".repeat(RunManifest.FINGERPRINT_DIGITS),
	]


## Ids rather than display names, because the id is what a bug report needs to reproduce a
## build and what the item's `.tres` is called on disk.
func _describe_items() -> String:
	var inventory := _player.get_item_inventory()
	if inventory.size() == 0:
		return "none"
	var ids := PackedStringArray()
	for item: ItemConfig in inventory.get_items():
		ids.append(String(item.id))
	return ", ".join(ids)


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

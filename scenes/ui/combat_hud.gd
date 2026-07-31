class_name CombatHUD
extends Control
## The player-facing readout: integrity, dash charges, current weapon, and status
## banners.
##
## Styled as a malfunctioning industrial operating system per spec section 20, but
## legibility wins every argument with the aesthetic — section 21 is explicit that
## gameplay information stays readable.
##
## Pips rather than a bar, because integrity is a small whole number the player counts
## under pressure. "Three left" must be readable at a glance without measuring a bar.
## They are built in code from the player's actual maximum so items that change it
## (Reinforced Chassis, Unsafe Overclock) need no HUD changes.

const PIP_SIZE := Vector2(5, 8)
const PIP_SEPARATION := 1
const FONT_SIZE := 8

const INTEGRITY_FULL := Color("58f0c8")
const INTEGRITY_LOW := Color("ff6b5a")
const INTEGRITY_EMPTY := Color("1e2a36")
const DASH_READY := Color("f2a13c")
const DASH_SPENT := Color("342a1a")
const LABEL_COLOR := Color("7c8a99")
const BANNER_CLEAR := Color("58f0c8")
const BANNER_DEAD := Color("ff6b5a")

## Integrity at or below this pulses, as the low-health warning from spec section 22.
const LOW_INTEGRITY_THRESHOLD := 1.0
const LOW_INTEGRITY_PULSE_HZ := 3.0

## How long a transient banner stays up. The death banner ignores this.
const BANNER_SECONDS := 2.0

@onready var _integrity_label: Label = %IntegrityLabel
@onready var _integrity_pips: HBoxContainer = %IntegrityPips
@onready var _dash_label: Label = %DashLabel
@onready var _dash_pips: HBoxContainer = %DashPips
@onready var _weapon_label: Label = %WeaponLabel
@onready var _banner: Label = %Banner
@onready var _top_label: Label = %TopLabel

var _player: Player
var _banner_left := 0.0
var _banner_is_permanent := false
var _pulse_time := 0.0


func _ready() -> void:
	for label: Label in [_integrity_label, _dash_label, _weapon_label, _top_label]:
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", LABEL_COLOR)
	_banner.add_theme_font_size_override("font_size", FONT_SIZE)
	_banner.visible = false

	_integrity_label.text = "INTEGRITY"
	_dash_label.text = "DASH"

	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.player_died.connect(_on_player_died)
	# Scrap and floor progress are pushed rather than polled: unlike integrity they change
	# rarely, so a signal is both cheaper and easier to reason about than a per-frame read.
	RunManager.scrap_changed.connect(_on_run_state_changed.unbind(1))
	RunManager.rooms_cleared_changed.connect(_on_run_state_changed.unbind(1))
	_refresh_top_label()


func bind_player(player: Player) -> void:
	_player = player
	var health := player.get_health_component()
	var weapon := player.get_weapon_controller()

	_build_pips(_integrity_pips, ceili(health.max_health))
	_build_pips(_dash_pips, player.get_dash_controller().get_max_charges())

	_weapon_label.text = weapon.config.display_name.to_upper() if weapon.config != null else "NO WEAPON"


func _process(delta: float) -> void:
	_pulse_time += delta
	_update_banner(delta)
	if _player == null:
		return
	_update_integrity()
	_update_dash()


func _update_integrity() -> void:
	var health := _player.get_health_component()
	# Ceiling, so a robot on 0.4 integrity still shows one pip: it is alive, and the
	# HUD must not claim otherwise.
	var filled := ceili(health.current)
	var is_low := health.current <= LOW_INTEGRITY_THRESHOLD and health.current > 0.0

	var live_color := INTEGRITY_FULL
	if is_low:
		var pulse := 0.5 + 0.5 * sin(_pulse_time * TAU * LOW_INTEGRITY_PULSE_HZ)
		live_color = INTEGRITY_FULL.lerp(INTEGRITY_LOW, pulse)

	for index: int in _integrity_pips.get_child_count():
		var pip := _integrity_pips.get_child(index) as ColorRect
		pip.color = live_color if index < filled else INTEGRITY_EMPTY


func _update_dash() -> void:
	var dash := _player.get_dash_controller()
	for index: int in _dash_pips.get_child_count():
		var pip := _dash_pips.get_child(index) as ColorRect
		pip.color = DASH_READY if index < dash.charges_available else DASH_SPENT


func _on_run_state_changed() -> void:
	_refresh_top_label()


## Floor name, scrap, and rooms cleared on one line in the bottom-right of the HUD strip.
##
## It began at the top-left, over the room's wall tiles, and was unreadable against them —
## spec section 21 puts legibility above the aesthetic. The strip below the room is the only
## screen space that is not playable floor, so all persistent readouts live there.
func _refresh_top_label() -> void:
	_top_label.text = "%s  //  SCRAP %d  //  ROOMS %d" % [
		RunManager.floor_name.to_upper(), RunManager.scrap, RunManager.rooms_cleared,
	]


func _update_banner(delta: float) -> void:
	if _banner_is_permanent or _banner_left <= 0.0:
		return
	_banner_left -= delta
	if _banner_left <= 0.0:
		_banner.visible = false


func _show_banner(text: String, color: Color, permanent := false) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner_is_permanent = permanent
	_banner_left = BANNER_SECONDS


func _build_pips(container: HBoxContainer, count: int) -> void:
	for existing: Node in container.get_children():
		existing.queue_free()
	container.add_theme_constant_override("separation", PIP_SEPARATION)
	for _index: int in maxi(count, 0):
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.color = INTEGRITY_EMPTY
		container.add_child(pip)


func _on_room_cleared() -> void:
	_show_banner("SECTOR CLEAR", BANNER_CLEAR)


func _on_player_died() -> void:
	_show_banner("SYSTEM FAILURE    PRESS R TO REBOOT", BANNER_DEAD, true)

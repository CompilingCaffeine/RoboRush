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
## They are built in code from the player's actual maximum and rebuilt whenever an item
## moves that maximum, so Reinforced Chassis and Unsafe Overclock need no HUD code.
##
## Items get two readouts, because they answer two different questions. The banner names
## the item and what it does, once, when it is picked up — the only time the game ever
## explains an item. The bar along the bottom is the standing answer to "what am I
## running", which is the question the player asks before deciding whether the next
## treasure room is worth the walk.

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
const BANNER_ITEM := Color("f2a13c")

## Gap between item icons in the bar, in pixels.
const ITEM_SEPARATION := 2

## Integrity at or below this pulses, as the low-health warning from spec section 22.
const LOW_INTEGRITY_THRESHOLD := 1.0
const LOW_INTEGRITY_PULSE_HZ := 3.0

## How long a banner stays up. Every banner is transient now that the end of a run has a
## screen of its own.
const BANNER_SECONDS := 2.0

@onready var _integrity_label: Label = %IntegrityLabel
@onready var _integrity_pips: HBoxContainer = %IntegrityPips
@onready var _dash_label: Label = %DashLabel
@onready var _dash_pips: HBoxContainer = %DashPips
@onready var _weapon_label: Label = %WeaponLabel
@onready var _banner: Label = %Banner
@onready var _top_label: Label = %TopLabel
@onready var _item_bar: HBoxContainer = %ItemBar

var _player: Player
var _banner_left := 0.0
var _pulse_time := 0.0


func _ready() -> void:
	for label: Label in [_integrity_label, _dash_label, _weapon_label, _top_label]:
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", LABEL_COLOR)
	_banner.add_theme_font_size_override("font_size", FONT_SIZE)
	_banner.visible = false

	_integrity_label.text = "INTEGRITY"
	_dash_label.text = "DASH"

	_item_bar.add_theme_constant_override("separation", ITEM_SEPARATION)

	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.item_collected.connect(_on_item_collected)
	# Scrap and floor progress are pushed rather than polled: unlike integrity they change
	# rarely, so a signal is both cheaper and easier to reason about than a per-frame read.
	RunManager.scrap_changed.connect(_on_run_state_changed.unbind(1))
	RunManager.rooms_cleared_changed.connect(_on_run_state_changed.unbind(1))
	_refresh_top_label()


func bind_player(player: Player) -> void:
	_player = player
	var weapon := player.get_weapon_controller()
	_weapon_label.text = weapon.config.display_name.to_upper() if weapon.config != null else "NO WEAPON"
	_rebuild_capacity_pips()


## Integrity and dash pips are counts, not bars, so their *number* changes when an item
## changes a maximum. Rebuilt from the components rather than tracked, so Reinforced
## Chassis and Unsafe Overclock need no HUD code of their own — and neither will the next
## item that moves either ceiling.
func _rebuild_capacity_pips() -> void:
	if _player == null:
		return
	_build_pips(_integrity_pips, ceili(_player.get_health_component().max_health))
	_build_pips(_dash_pips, _player.get_dash_controller().get_max_charges())


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
	if _banner_left <= 0.0:
		return
	_banner_left -= delta
	if _banner_left <= 0.0:
		_banner.visible = false


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner_left = BANNER_SECONDS


func _build_pips(container: HBoxContainer, count: int) -> void:
	for existing: Node in container.get_children():
		# Removed as well as freed. queue_free alone leaves the node in the container until
		# the end of the frame, so rebuilding a 6-pip row as an 8-pip row would draw all
		# fourteen for one frame — visible, and read as the item granting eight.
		container.remove_child(existing)
		existing.queue_free()
	container.add_theme_constant_override("separation", PIP_SEPARATION)
	for _index: int in maxi(count, 0):
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.color = INTEGRITY_EMPTY
		container.add_child(pip)


func _on_room_cleared() -> void:
	_show_banner("SECTOR CLEAR", BANNER_CLEAR)


## Name and effect together, because an item the player cannot read is an item they cannot
## build around — and the description is the only place the game ever states what the thing
## does. One line rather than two: the banner sits over playable floor, and a two-line
## banner hides enemies during the seconds after a room clears.
func _on_item_collected(item: ItemConfig) -> void:
	_show_banner("%s  //  %s" % [item.display_name.to_upper(), item.description.to_upper()], BANNER_ITEM)
	_rebuild_capacity_pips()
	_add_item_icon(item)


## Items accumulate left to right in the order they were found, which is the order the
## player remembers them in. No icon for an item without one, rather than a blank slot that
## reads as a bug.
func _add_item_icon(item: ItemConfig) -> void:
	if item.icon == null:
		return
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.tooltip_text = "%s: %s" % [item.display_name, item.description]
	icon.custom_minimum_size = item.icon.get_size()
	_item_bar.add_child(icon)

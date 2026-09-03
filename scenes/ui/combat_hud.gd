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
## Items get two readouts, and neither of them explains anything. The banner names the item once,
## when it is picked up; the bar along the bottom is the standing answer to "what am I running",
## which is the question the player asks before deciding whether the next treasure room is worth the
## walk. What each item *does* is never stated on screen — an item that has to be read about is an
## item the player never noticed working.

## The floor boss's name and defeat banner, as the player reads them. Bound at runtime via
## `bind_boss()` rather than fixed here, since a second floor has a different boss — see
## `FloorController.boss_encountered` and `FloorConfig.boss_display_name`. Defaults are
## generic placeholders that should never actually reach the screen: `bind_boss()` runs
## before the boss room is enterable.
var _boss_name := "THE BOSS"
var _boss_defeat_banner := "THE BOSS IS DEFEATED"

## What this floor's boss announces as each phase begins, indexed from phase one. Empty until
## `bind_boss` runs, and legitimately empty for a boss with nothing to say — see
## `FloorConfig.boss_phase_banners` for why this is data and not the constants it used to be.
var _boss_phase_banners: Array[String] = []

## Merge Conflict's own feigned-death epitaph — distinct from the bound `_boss_defeat_banner`
## above, which is the *real* defeat banner and varies per floor. This one is specific to
## Merge Conflict's phase-one feint (see `_on_boss_feigned_defeat`) and never fires for a
## boss that doesn't emit `boss_feigned_defeat`, so it stays a constant rather than data.
const BOSS_DEFEAT_BANNER := "THE KING IS DEAD"

## The other feigned death, at the end of phase two, where what falls is the two duplicated versions
## and not the King himself — the phase that opened as "TWO CLAIMANTS" cannot end as a dead king.
## Phase one's feint and the real defeat both keep BOSS_DEFEAT_BANNER: the first of those is the
## King going down, and so is the last.
const CLAIMANTS_DEFEAT_BANNER := "THE CLAIMANTS ARE DEAD"

const PIP_SIZE := Vector2(5, 8)
const PIP_SEPARATION := 1
const FONT_SIZE := UIPalette.FONT_SIZE

const INTEGRITY_FULL := UIPalette.ACCENT
const INTEGRITY_LOW := UIPalette.DANGER
const DASH_READY := UIPalette.WARN
const LABEL_COLOR := UIPalette.TEXT_DIM
const BANNER_CLEAR := UIPalette.ACCENT
const BANNER_ITEM := UIPalette.WARN
const BANNER_BOSS := UIPalette.DANGER
const BOSS_BAR_FILL := UIPalette.DANGER

## The "spent" half of a pip row. Not in UIPalette because these are the only two colours in
## the game that exist to be *ignored* — a dark tint of their lit counterpart, dim enough to
## count against but never bright enough to read as full.
const INTEGRITY_EMPTY := Color("1e2a36")
const DASH_SPENT := Color("342a1a")
const BOSS_BAR_BACK := Color("2a1a1e")

## Gap between item icons in the bar, in pixels.
const ITEM_SEPARATION := 2
const VISIBLE_ITEM_TYPES := 12

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
@onready var _boss_bar: Control = %BossBar
@onready var _boss_fill: ColorRect = %BossFill
@onready var _boss_label: Label = %BossLabel
@onready var _backing: ColorRect = %Backing
@onready var _backing_edge: ColorRect = %BackingEdge
@onready var _boss_backing: ColorRect = %BossBacking

var _player: Player
var _banner_left := 0.0
var _pulse_time := 0.0

## The phase the boss is currently in, which is the phase a feigned death is ending — the feint
## runs before the change, so this still reads 2 while the two claimants are falling. One is the
## right default: a HUD that connected after the fight announced its first phase is still watching
## phase one.
var _boss_phase := 1


func _ready() -> void:
	for label: Label in [_integrity_label, _dash_label, _weapon_label, _top_label]:
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", LABEL_COLOR)
	_banner.add_theme_font_size_override("font_size", FONT_SIZE)
	_banner.visible = false

	_integrity_label.text = "INTEGRITY"
	_dash_label.text = "DASH"

	_item_bar.add_theme_constant_override("separation", ITEM_SEPARATION)

	# The readouts sit over whatever the camera happens to be framing below the room, which
	# through milestone 5 was "usually black, sometimes a wall". Spec section 21 does not
	# leave legibility to luck, so the strip is now an opaque bar with a lit edge — the
	# bezel of the machine the interface is pretending to be.
	_backing.color = UIPalette.VOID
	_backing_edge.color = UIPalette.PANEL_BORDER
	_boss_backing.color = UIPalette.VOID

	_boss_bar.visible = false
	_boss_fill.color = BOSS_BAR_FILL
	(_boss_bar.get_node("Back") as ColorRect).color = BOSS_BAR_BACK
	_boss_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_boss_label.add_theme_color_override("font_color", LABEL_COLOR)

	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_feigned_defeat.connect(_on_boss_feigned_defeat)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	# Scrap and floor progress are pushed rather than polled: unlike integrity they change
	# rarely, so a signal is both cheaper and easier to reason about than a per-frame read.
	RunManager.scrap_changed.connect(_on_run_state_changed.unbind(1))
	RunManager.rooms_cleared_changed.connect(_on_run_state_changed.unbind(1))
	_refresh_top_label()


## Called once per floor, before its boss room is reachable — see
## `FloorController.boss_encountered`.
func bind_boss(display_name: String, defeat_banner: String, phase_banners: Array[String]) -> void:
	_boss_name = display_name
	_boss_defeat_banner = defeat_banner
	_boss_phase_banners = phase_banners


## Called as each floor begins, from main.gd. The floor's *name* already lives in the persistent
## strip along the bottom; this is the one moment it is worth interrupting for, because "which
## level am I on" is a question a player asks exactly once per floor and then never again.
##
## Deliberately the number and not the name. The name is on screen continuously two lines below,
## and a banner that repeated it would be the only banner in the game that told the player
## something they were already looking at.
func announce_floor(number: int) -> void:
	# A floor begins with no boss on screen. The bar is normally already down — the defeat that
	# ended the floor before took it down — but "normally" is exactly what left it up for the
	# whole of Development the one time that floor's boss was spawned early (see
	# `FloorController._on_player_entered_room`). The bar belongs to a fight in progress, and
	# the two moments a floor begins are the two moments there cannot be one.
	_hide_boss_bar()
	_show_banner("LEVEL %d" % number, BANNER_CLEAR)

	# The strip along the bottom carries the floor's name, and this is the moment that name
	# changes. It is pushed rather than polled (see `_ready`), and the only things that pushed it
	# were scrap and cleared rooms — so the name went on saying `HELP DESK` after a descent until
	# the player happened to pick up a coin on the floor below. Reported by a browser run of the
	# resumed-game path, where the wrong name was the *default* one rather than merely the
	# previous floor's, and so never corrected itself at all.
	#
	# Here rather than in `RunManager.begin_floor`, because this is called at every moment a floor
	# begins — a run opening on one, a descent, and a resume — and by the time it runs the run
	# already knows the new floor's name.
	_refresh_top_label()


func bind_player(player: Player) -> void:
	_player = player
	var weapon := player.get_weapon_controller()
	_weapon_label.text = weapon.config.display_name.to_upper() if weapon.config != null else "NO WEAPON"
	_rebuild_capacity_pips()
	_rebuild_item_bar()


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


## Floor name above scrap and rooms cleared, in the bottom-right of the HUD strip.
##
## It began at the top-left, over the room's wall tiles, and was unreadable against them —
## spec section 21 puts legibility above the aesthetic. The strip below the room is the only
## screen space that is not playable floor, so all persistent readouts live there.
func _refresh_top_label() -> void:
	_top_label.text = "%s\nSCRAP %d  //  ROOMS %d" % [
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


## Spec section 21 lists boss health as a HUD element. Along the top, where it cannot be
## confused with the player's own integrity along the bottom, and only while there is a boss.
func _on_boss_health_changed(ratio: float) -> void:
	_boss_bar.visible = ratio > 0.0
	_boss_fill.anchor_right = clampf(ratio, 0.0, 1.0)


## Emptied as well as hidden, so the bar cannot be shown again holding the last fight's fill for
## the frame before its first health reading arrives.
func _hide_boss_bar() -> void:
	_boss_bar.visible = false
	_boss_fill.anchor_right = 0.0


## No phase number anywhere on screen, deliberately. "PHASE 1" tells the player there are more
## coming, and The Scrap King's bar is built to convince them there are none left — see
## MergeConflict._begin_feint. What a phase gets instead is a name, which says what changed
## without saying how much is left.
##
## Which name comes from the floor, not from here. Every boss emits this signal, so a line
## written for one of them fires for all of them: Runtime Error reached phase two and the HUD
## announced "LONG LIVE THE KING" over a boss with no claim to the title and no phase two of the
## King's to be in. A boss with nothing to say now says nothing, which is the correct amount for
## a fight whose phases announce themselves by changing what is on the floor.
func _on_boss_phase_changed(phase: int) -> void:
	_boss_phase = phase
	_boss_label.text = _boss_name

	var index := phase - 1
	if index < 0 or index >= _boss_phase_banners.size():
		return
	var banner := _boss_phase_banners[index]
	if not banner.is_empty():
		_show_banner(banner, BANNER_BOSS)


## The one place the HUD lies to the player: the same words and the same colour as a real victory,
## minus the reward line they would go looking for and not find. The bar has already emptied itself
## through `_on_boss_health_changed`, which is what hides it.
##
## Which words depends on what just fell. Phase one's feint is the King, so it gets the King's own
## epitaph and the player who believes it is believing something the fight will then take back.
## Phase two's is the two claimants, which are not the King and cannot be announced as him.
func _on_boss_feigned_defeat(_boss: Node, _at: Vector2) -> void:
	var epitaph := CLAIMANTS_DEFEAT_BANNER if _boss_phase == 2 else BOSS_DEFEAT_BANNER
	_show_banner(epitaph, BANNER_CLEAR)


func _on_boss_defeated(_boss: Node) -> void:
	_hide_boss_bar()
	_show_banner("%s  //  CHOOSE ONE REWARD" % _boss_defeat_banner, BANNER_CLEAR)


## The name and nothing else. The item's effect is deliberately not stated anywhere on screen: what
## a piece of salvaged hardware does is for the player to notice in the next room, not to read in a
## banner. Naming it still matters — a nameless pickup cannot be recognised, talked about, or
## remembered as the thing that made the last run work.
##
## `ItemConfig.description` is still authored for every item; it is a design note now, not copy.
func _on_item_collected(item: ItemConfig) -> void:
	_show_banner(item.display_name.to_upper(), BANNER_ITEM)
	_rebuild_capacity_pips()
	_rebuild_item_bar()


## Rebuilt from the inventory on binding and pickup, so resumed runs and stacked chips agree.
## Twelve distinct types fit beside the floor readout at 480x270; older types are counted by
## the overflow marker and remain visible in the summary's complete inventory grid.
## Tooltips name items and stack counts, preserving the game's discovery-based item effects.
func _rebuild_item_bar() -> void:
	for existing: Node in _item_bar.get_children():
		# Removed as well as freed, exactly as `_build_pips` does: `queue_free` alone leaves the
		# node in the container until the end of the frame, so a rebuild would draw both rows for
		# one frame.
		_item_bar.remove_child(existing)
		existing.queue_free()
	if _player == null:
		return
	var items: Array[ItemConfig] = []
	var seen: Dictionary[StringName, bool] = {}
	for item: ItemConfig in _player.get_item_inventory().get_items():
		if item.icon != null and not seen.has(item.id):
			seen[item.id] = true
			items.append(item)
	# Keep the newest types visible. The full build and stack counts are on the Tab summary.
	var hidden := maxi(items.size() - VISIBLE_ITEM_TYPES, 0)
	for item: ItemConfig in items.slice(hidden):
		_add_item_icon(item)
	if hidden > 0:
		var overflow := UIPalette.make_label("+%d" % hidden, LABEL_COLOR, FONT_SIZE)
		overflow.tooltip_text = "Hold Tab / L1 for the full build"
		_item_bar.add_child(overflow)


func _add_item_icon(item: ItemConfig) -> void:
	if item.icon == null:
		return
	var icon := TextureRect.new()
	icon.texture = item.icon
	var count := _player.get_item_inventory().count_of(item.id) if _player != null else 1
	icon.tooltip_text = item.display_name + (" x%d" % count if count > 1 else "")
	icon.custom_minimum_size = item.icon.get_size()
	_item_bar.add_child(icon)

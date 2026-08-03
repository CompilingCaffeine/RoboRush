class_name ShopStand
extends Node2D
## One thing for sale, standing on the shop floor.
##
## A stand is the whole shop. There is no shop mode, no menu, and no state to leave: the
## player walks up and presses the interact key they already have, which is why spec
## section 23's "do not allow input to leak between UI and gameplay states" needs nothing
## enforcing here — there is no second state for it to leak across.
##
## Stands advertise themselves permanently rather than on approach. A price the player can
## only read by standing on it cannot be planned around, and planning is the entire point of
## an economy that cannot afford everything.

## Every stand joins this so the player can find what it is standing next to without
## anything holding a list of what is currently for sale.
const GROUP := &"interactable"

const LABEL_FONT_SIZE := 8

## How wide a stand's label is allowed to be, and therefore the closest two stands may ever be
## placed. Both the shop template's stand tiles and FloorController.BOSS_REWARD_SPACING are set from
## this, and tests/test_shop.gd measures the whole item pool against it.
##
## The number is what a 26-tile room can afford: three labels plus gutters plus a margin off each
## wall inside 416 pixels. The shipped pool's longest tag is "REINFORCED CHASSIS  40" at 132 pixels
## of six-pixel characters, which is wider than that, so it wraps to a second line — a two-line tag
## is legible and a tag written across the one beside it is not. Widening this instead is not
## available: three 132-pixel labels do not fit in the room at all.
const LABEL_WIDTH := 120.0

## How far the label's baseline sits above the stand. It grows upward from here, so wrapping a long
## name never pushes text down over the stand it belongs to.
const LABEL_BOTTOM := -14.0
const LABEL_LINES := 2

## Draws the tag over room scenery rather than under it. Below the HUD, which lives on its own
## CanvasLayer and is unaffected either way.
const LABEL_Z_INDEX := 10
const AFFORDABLE := Color("f2a13c")
const TOO_EXPENSIVE := Color("6d7a8c")
const SOLD := Color("3c4654")

enum Kind {
	## Hands over an item. Once.
	ITEM,
	## Repairs integrity. Repeatable while the player can pay.
	HEAL,
	## Replaces every unsold item in this shop. Repeatable, and dearer each time.
	REROLL,
}

@onready var _icon: Sprite2D = %Icon
@onready var _label: Label = %Label

var kind := Kind.ITEM
var item: ItemConfig
var price := 0
var is_sold := false

## The shop this stand belongs to, so a reroll can reach its siblings.
var shop: ShopRoom


func _ready() -> void:
	add_to_group(GROUP)
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_size_label()
	refresh()


## The label's box, from code rather than from the scene, because `LABEL_WIDTH` is also what decides
## how far apart the stands stand — two numbers that have to agree should be one number.
func _size_label() -> void:
	_label.offset_left = -LABEL_WIDTH * 0.5
	_label.offset_right = LABEL_WIDTH * 0.5
	_label.offset_bottom = LABEL_BOTTOM
	_label.offset_top = LABEL_BOTTOM - float(LABEL_FONT_SIZE * LABEL_LINES + 4)
	# Wrapped and bottom-aligned: a name too long for its slot costs a line above the stand rather
	# than running into the stand next to it.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Above the room. A tag is as wide as the label, and the room's scenery sits wherever the
	# template put it: the shop's corner blocks were drawn over the first two letters of
	# "REINFORCED CHASSIS", which reads as a shorter item rather than as an obscured one.
	_label.z_index = LABEL_Z_INDEX


## Called by the shop when anything changes — a purchase, a reroll, or the player's scrap
## going up. Cheap enough to call on every scrap change, and that is what keeps the price
## colour honest without polling.
func refresh() -> void:
	_icon.texture = item.icon if kind == Kind.ITEM and item != null else null
	_icon.visible = _icon.texture != null

	if is_sold:
		_label.text = "SOLD"
		_label.add_theme_color_override("font_color", SOLD)
		return

	# A free choice shows no price at all: "0" reads as broken, not as a gift.
	_label.text = _describe() if price <= 0 else "%s  %d" % [_describe(), price]
	_label.add_theme_color_override(
		"font_color", AFFORDABLE if RunManager.scrap >= price else TOO_EXPENSIVE
	)


## Attempts the purchase. Returns false when it did not happen — no scrap, already sold, or
## nothing to sell — so the caller can play a refusal without deciding why.
func interact(player: Player) -> bool:
	if is_sold or player == null:
		return false

	match kind:
		Kind.ITEM:
			return _buy_item(player)
		Kind.HEAL:
			return _buy_heal(player)
		Kind.REROLL:
			return _buy_reroll()
	return false


## Replaces what this stand sells. Used when the shop is stocked and again on a reroll.
func stock_item(new_item: ItemConfig, new_price: int) -> void:
	kind = Kind.ITEM
	item = new_item
	price = new_price
	is_sold = new_item == null
	if is_inside_tree():
		refresh()


func _buy_item(player: Player) -> bool:
	var inventory := player.get_item_inventory()
	if item == null or inventory == null or inventory.has(item.id):
		return false
	# A free stand takes no payment. `try_spend_scrap` refuses a zero charge — correctly,
	# since spending nothing is not a transaction — so the boss reward would have been
	# unclaimable if the purchase were gated on it.
	if price > 0 and not RunManager.try_spend_scrap(price):
		return false

	# Spent first, then handed over: a failed add after a successful spend would take the
	# player's scrap and give them nothing.
	if not inventory.add(item):
		if price > 0:
			RunManager.add_scrap(price)
		return false

	is_sold = true
	refresh()
	EventBus.purchase_made.emit(price)
	if shop != null:
		shop.on_item_taken(self)
	return true


func _buy_heal(player: Player) -> bool:
	var health := player.get_health_component()
	# Refused rather than wasted, exactly as a repair cell on the floor is.
	if health == null or health.is_approx_full() or not health.is_alive():
		return false
	if not RunManager.try_spend_scrap(price):
		return false
	health.heal(_heal_amount())
	EventBus.purchase_made.emit(price)
	return true


func _buy_reroll() -> bool:
	if shop == null or not RunManager.try_spend_scrap(price):
		return false
	shop.reroll()
	EventBus.purchase_made.emit(price)
	return true


func _heal_amount() -> float:
	return shop.config.heal_amount if shop != null and shop.config != null else 1.0


func _describe() -> String:
	match kind:
		Kind.ITEM:
			return item.display_name.to_upper() if item != null else "EMPTY"
		Kind.HEAL:
			return "REPAIR"
		Kind.REROLL:
			return "REROLL"
	return ""

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
	refresh()


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
	if not RunManager.try_spend_scrap(price):
		return false

	# Spent first, then handed over: a failed add after a successful spend would take the
	# player's scrap and give them nothing.
	if not inventory.add(item):
		RunManager.add_scrap(price)
		return false

	is_sold = true
	refresh()
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
	return true


func _buy_reroll() -> bool:
	if shop == null or not RunManager.try_spend_scrap(price):
		return false
	shop.reroll()
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

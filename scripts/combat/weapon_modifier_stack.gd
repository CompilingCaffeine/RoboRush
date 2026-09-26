class_name WeaponModifierStack
extends RefCounted
## Applies every held item's weapon modifiers to a copy of a weapon. Roadmap SYS-1.
##
## The weapon's half of what `ProjectileModifierStack` does for a shot. Items used to reach a
## weapon only through `fire_rate_scale`, so how many projectiles a shot fires, across what arc and
## in which direction were the weapon's alone. Now an item names a `WeaponConfig` field in
## `weapon_set`, `weapon_add` or `weapon_scale`, and a shotgun, a pair of parallel rivets or a
## backward shot is a `.tres`.
##
## It runs when the inventory changes, not per shot: a weapon's pattern has no per-shot state for an
## item to vary, so `ItemConfig.shot_interval` does not apply here, and `CampaignValidator` refuses an
## item that asks for both. The order is the projectile stack's — all sets, then all adds, then all
## scales, across every item — so the result does not depend on pickup order.
##
## A few fields are refused outright, each for a reason in `REFUSED_KEYS`.

## Fields an item may not touch, and why. Reported by `unknown_keys` like a typo, because an item
## naming one of them is wrong in the same way: it will not do what its author meant.
const REFUSED_KEYS: Dictionary[StringName, String] = {
	&"shots_per_second": "fire rate goes through fire_rate_scale, which is on the diminishing-returns curve",
	&"projectile": "a projectile is changed through the projectile modifiers, not replaced",
	&"display_name": "the HUD names the weapon, not the item",
}

## Every field `WeaponConfig` declares that an item may modify.
static var _known_properties: Dictionary[StringName, bool] = _collect_known_properties()

var _items: Array[ItemConfig] = []


## Builds a stack from the items an actor is holding. Nulls are skipped, and items with no weapon
## modifiers are left out, so an empty stack is the common case and costs nothing.
static func from_items(items: Array[ItemConfig]) -> WeaponModifierStack:
	var stack := WeaponModifierStack.new()
	for item: ItemConfig in items:
		if item == null or not item.modifies_weapon():
			continue
		stack._items.append(item)
		for key: String in unknown_keys(item):
			push_error("Item '%s' modifies weapon field '%s', which it cannot." % [item.id, key])
	return stack


## Every weapon field an item names that does not exist or is refused. Empty for a correct item.
static func unknown_keys(item: ItemConfig) -> PackedStringArray:
	var unknown := PackedStringArray()
	if item == null:
		return unknown
	for source: Dictionary in [item.weapon_set, item.weapon_add, item.weapon_scale]:
		for key: Variant in source:
			if not _known_properties.has(StringName(key)):
				unknown.append(String(key))
	return unknown


## Why `key` may not be modified, or an empty string if it may.
static func refusal(key: StringName) -> String:
	return REFUSED_KEYS.get(key, "")


func is_empty() -> bool:
	return _items.is_empty()


## `base` with every held item's weapon modifiers applied, as a new resource. `base` itself when
## nothing held modifies a weapon, so an unmodified robot fires the shipped resource and never a
## copy of it.
func apply(base: WeaponConfig) -> WeaponConfig:
	if base == null or _items.is_empty():
		return base

	var weapon := base.duplicate() as WeaponConfig
	for item: ItemConfig in _items:
		FieldModifiers.assign(weapon, item.weapon_set, _known_properties)
	for item: ItemConfig in _items:
		FieldModifiers.add(weapon, item.weapon_add, _known_properties)

	var factors: Dictionary[StringName, float] = {}
	for item: ItemConfig in _items:
		for key: Variant in item.weapon_scale:
			var name := StringName(key)
			if _known_properties.has(name):
				factors[name] = factors.get(name, 1.0) * float(item.weapon_scale[key])
	FieldModifiers.scale(weapon, factors)
	return weapon


## Script-declared fields only, less the refused ones. The projectile stack accepts every property
## a resource has, engine ones included; a weapon has fewer fields worth reaching and a shorter list
## is a better guard.
static func _collect_known_properties() -> Dictionary[StringName, bool]:
	var names: Dictionary[StringName, bool] = {}
	for entry: Dictionary in WeaponConfig.new().get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := StringName(entry["name"])
		if not REFUSED_KEYS.has(name):
			names[name] = true
	return names

class_name ProjectileModifierStack
extends RefCounted
## Applies every held item's projectile modifiers to one shot's config.
##
## Spec section 14 lists this as a component and forbids `if has_item_a and has_item_b`.
## There is no such conditional here because there is no item-specific code at all: the
## stack reads field names out of `ItemConfig` and writes them into a `ProjectileConfig`
## copy. Adding an item is adding a `.tres`.
##
## It runs inside `ProjectileFactory.spawn`, between `spawn_copy()` and instantiation,
## because that copy is the only place a modification can be per-shot rather than
## permanent — writing into the weapon's shared resource would make the first shot's
## bonuses stick forever.
##
## Order is all sets, then all adds, then all scales, across every item — not each item
## in turn. Adds and scales are order-independent among themselves, so this makes the
## result independent of pickup order, which is the property that stops "I found them in
## the wrong sequence" from being a real bug report. A set is the one operation that can
## conflict, and two items assigning the same field different values is a content
## decision, not something code can resolve.

## Names of every property `ProjectileConfig` actually has. Built once. Anything else an
## item names is a typo, and a typo that silently does nothing is the failure mode this
## whole design is most exposed to.
static var _known_properties: Dictionary[StringName, bool] = _collect_known_properties()

## Scaled fields whose combined multiplier is run through `DiminishingReturns.soften` before it
## reaches the config. See that class for why this list is one entry long and what the other
## candidates were measured against.
##
## A set rather than a flag on `ItemConfig`, because whether a stat compounds into a trivial floor
## is a property of the *stat*, not of the item that touches it. An item declaring its own
## softening would let two items disagree about the same field, and the field is what the curve is
## a statement about.
const SOFTENED_SCALE_KEYS: Dictionary[StringName, bool] = {
	&"damage": true,
}

var _items: Array[ItemConfig] = []


## Builds a stack from the items an actor is holding. Nulls are skipped rather than
## crashing, because a half-filled pool array in the inspector should not take the game
## down.
static func from_items(items: Array[ItemConfig]) -> ProjectileModifierStack:
	var stack := ProjectileModifierStack.new()
	for item: ItemConfig in items:
		if item == null:
			continue
		stack._items.append(item)
		for key: String in unknown_keys(item):
			push_error("Item '%s' modifies '%s', which ProjectileConfig does not have." % [
				item.id, key,
			])
	return stack


## Every property name an item names that does not exist. Empty for a correct item; the
## item suite asserts that for all shipped items.
static func unknown_keys(item: ItemConfig) -> PackedStringArray:
	var unknown := PackedStringArray()
	if item == null:
		return unknown
	for source: Dictionary in [item.projectile_set, item.projectile_add, item.projectile_scale]:
		for key: Variant in source:
			if not _known_properties.has(StringName(key)):
				unknown.append(String(key))
	return unknown


func is_empty() -> bool:
	return _items.is_empty()


func size() -> int:
	return _items.size()


## Modifies `config` in place. `shot_index` is the weapon's lifetime shot count, which is
## what lets an item apply only every Nth shot.
func apply(config: ProjectileConfig, shot_index := 0) -> void:
	if config == null:
		return

	for item: ItemConfig in _items:
		if item.applies_on_shot(shot_index):
			_assign(config, item.projectile_set)
	for item: ItemConfig in _items:
		if item.applies_on_shot(shot_index):
			_add(config, item.projectile_add)
	_scale(config, _collect_scales(shot_index))


## The combined multiplier for every scaled field, gathered across the whole stack before any of it
## reaches the config.
##
## Gathered rather than applied item by item, which is the change diminishing returns required: a
## curve on "how much damage has this build stacked" cannot be evaluated one item at a time, because
## each item after the first would be softened against a knee the ones before it had already spent.
## Softening the product once is also the only version that keeps the result independent of pickup
## order, which the class doc promises and `_test_stack_is_order_independent` checks.
##
## The product is identical to what the old per-item loop produced for every unsoftened field, with
## one difference worth naming: an integer field scaled by two items is now rounded once at the end
## rather than after each item. Rounding twice was never intended — it is the reason `_add` rounds
## rather than truncates — and no shipped item scales an integer field at all.
func _collect_scales(shot_index: int) -> Dictionary[StringName, float]:
	var scales: Dictionary[StringName, float] = {}
	for item: ItemConfig in _items:
		if not item.applies_on_shot(shot_index):
			continue
		for key: Variant in item.projectile_scale:
			var name := StringName(key)
			if not _known_properties.has(name):
				continue
			scales[name] = scales.get(name, 1.0) * float(item.projectile_scale[key])

	for name: StringName in SOFTENED_SCALE_KEYS:
		if scales.has(name):
			scales[name] = DiminishingReturns.soften(scales[name])

	return scales


func _assign(config: ProjectileConfig, values: Dictionary) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if _known_properties.has(name):
			config.set(name, values[key])


## Integer fields are rounded rather than truncated, so an item adding 1.0 to a bounce
## count can never land on 0 through float representation.
##
## Adding to an *array* field appends to it, which is the only reading of "add" that makes
## sense for `status_effects` and the reason Cold Cache and Hot Reload compose. Assigning
## through `projectile_set` would have been the obvious route and is wrong: a set is the one
## operation two items can genuinely conflict over, so two status items would have silently
## resolved to whichever the stack reached last, and the player would have had one of them
## do nothing with no way to tell which.
func _add(config: ProjectileConfig, values: Dictionary) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if not _known_properties.has(name):
			continue
		var current: Variant = config.get(name)
		if current is Array:
			var combined: Array = (current as Array).duplicate()
			var addition: Variant = values[key]
			# A bare value is treated as a one-element list, so an item adding a single
			# status does not have to be written as an array in the inspector.
			if addition is Array:
				combined.append_array(addition as Array)
			else:
				combined.append(addition)
			config.set(name, combined)
		elif current is int:
			config.set(name, roundi(float(current) + float(values[key])))
		else:
			config.set(name, float(current) + float(values[key]))


## Writes the combined multipliers `_collect_scales` gathered. Keys are already known to exist and
## already softened where they had to be, so this is only the write.
func _scale(config: ProjectileConfig, values: Dictionary[StringName, float]) -> void:
	for name: StringName in values:
		var current: Variant = config.get(name)
		if current is int:
			config.set(name, roundi(float(current) * values[name]))
		else:
			config.set(name, float(current) * values[name])


static func _collect_known_properties() -> Dictionary[StringName, bool]:
	var names: Dictionary[StringName, bool] = {}
	for entry: Dictionary in ProjectileConfig.new().get_property_list():
		names[StringName(entry["name"])] = true
	return names

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
	for item: ItemConfig in _items:
		if item.applies_on_shot(shot_index):
			_scale(config, item.projectile_scale)


func _assign(config: ProjectileConfig, values: Dictionary) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if _known_properties.has(name):
			config.set(name, values[key])


## Integer fields are rounded rather than truncated, so an item adding 1.0 to a bounce
## count can never land on 0 through float representation.
func _add(config: ProjectileConfig, values: Dictionary) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if not _known_properties.has(name):
			continue
		var current: Variant = config.get(name)
		if current is int:
			config.set(name, roundi(float(current) + float(values[key])))
		else:
			config.set(name, float(current) + float(values[key]))


func _scale(config: ProjectileConfig, values: Dictionary) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if not _known_properties.has(name):
			continue
		var current: Variant = config.get(name)
		if current is int:
			config.set(name, roundi(float(current) * float(values[key])))
		else:
			config.set(name, float(current) * float(values[key]))


static func _collect_known_properties() -> Dictionary[StringName, bool]:
	var names: Dictionary[StringName, bool] = {}
	for entry: Dictionary in ProjectileConfig.new().get_property_list():
		names[StringName(entry["name"])] = true
	return names

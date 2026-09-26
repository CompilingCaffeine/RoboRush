class_name FieldModifiers
extends RefCounted
## The arithmetic an item's modifier dictionaries do to a resource, by property name.
##
## Shared by `ProjectileModifierStack` and `WeaponModifierStack`, which differ in which resource they
## touch, when they run, and which fields they allow — and must not differ in what "add" or "scale"
## means. One rule for rounding an integer, one reading of adding to a list: two copies of this
## would be two answers the day one of them was fixed.


## The names of every property `instance` declares. Anything an item names outside this set is a
## typo, and a typo that silently does nothing is the failure this whole design is most exposed to.
static func known_properties(instance: Object) -> Dictionary[StringName, bool]:
	var names: Dictionary[StringName, bool] = {}
	for entry: Dictionary in instance.get_property_list():
		names[StringName(entry["name"])] = true
	return names


## Writes each value outright. For behaviours that are switched on rather than accumulated
## (`return_enabled`) or configured once (`chain_radius`).
static func assign(target: Object, values: Dictionary, known: Dictionary[StringName, bool]) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if known.has(name):
			target.set(name, values[key])


## Adds each value to the current one.
##
## Integer fields are rounded rather than truncated, so an item adding 1.0 to a bounce count can never
## land on 0 through float representation.
##
## Adding to an *array* field appends to it, which is the only reading of "add" that makes sense for
## `status_effects` and the reason Cold Cache and Hot Reload compose. Assigning through a set would
## have been the obvious route and is wrong: a set is the one operation two items can genuinely
## conflict over, so two status items would have silently resolved to whichever the stack reached
## last, and the player would have had one of them do nothing with no way to tell which.
static func add(target: Object, values: Dictionary, known: Dictionary[StringName, bool]) -> void:
	for key: Variant in values:
		var name := StringName(key)
		if not known.has(name):
			continue
		var current: Variant = target.get(name)
		if current is Array:
			var combined: Array = (current as Array).duplicate()
			var addition: Variant = values[key]
			# A bare value is treated as a one-element list, so an item adding a single status does
			# not have to be written as an array in the inspector.
			if addition is Array:
				combined.append_array(addition as Array)
			else:
				combined.append(addition)
			target.set(name, combined)
		elif current is int:
			target.set(name, roundi(float(current) + float(values[key])))
		else:
			target.set(name, float(current) + float(values[key]))


## Multiplies each field by its combined factor. The keys are already known to exist: a caller
## gathers the factors across every item first, because a curve on a product cannot be evaluated
## one item at a time — see `ProjectileModifierStack._collect_scales`.
static func scale(target: Object, factors: Dictionary[StringName, float]) -> void:
	for name: StringName in factors:
		var current: Variant = target.get(name)
		if current is int:
			target.set(name, roundi(float(current) * factors[name]))
		else:
			target.set(name, float(current) * factors[name])

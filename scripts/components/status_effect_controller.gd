class_name StatusEffectController
extends Node2D
## Timed conditions on one actor: chilled, frozen, burning.
##
## Spec section 14 has listed this since milestone 4 and `ProjectileConfig.status_effects`
## has been declared and unread for just as long, because nothing needed it. Cold Cache and
## Hot Reload are the first two callers, which is when it earns its place.
##
## Two rules from the Development plan shape everything here.
##
## **Statuses compose rather than overwrite.** Every effect is tracked independently and the
## movement penalty is the *product* of what each one asks for, so a burning enemy that is
## also chilled is both, and neither item cancels the other. This is the same reason
## `ProjectileModifierStack` sorts by operation rather than by item: the moment two effects
## argue about who owns a field, pickup order becomes a bug report.
##
## **Resistance shortens control effects rather than nullifying them.** A boss with
## `control_resistance = 0.65` is frozen for a third as long as an enemy is, not immune —
## an item that reads "briefly freezes the target" and does *nothing at all* in the fight
## the player bought it for is worse than one that was never offered. Resistance is applied
## only to the effects that take control away; damage over time is not resisted, because
## shortening a burn and shortening a freeze are not the same promise.
##
## It is a `Node2D` rather than a plain `Node` so it can draw its own indicator. The
## alternative was tinting the parent's sprite, which is already contested property: every
## enemy telegraph and `HurtFlash` both write `modulate`, and a third writer is how a
## telegraph ends up invisible. A ring drawn around the body composes with all of them by
## not touching them.

## Emitted when an effect is applied or restacked. `stacks` is the count after the change.
signal effect_applied(id: StringName, stacks: int)

signal effect_expired(id: StringName)

const CHILL := &"chill"
const FREEZE := &"freeze"
const BURN := &"burn"

## What each effect is. A dictionary rather than a resource per effect because there are
## three of them and they are rules, not content — nothing about the game gets better if a
## designer can author a fourth without also writing the code that makes it mean something.
##
## - `seconds`: duration one application grants. Restacking refreshes it.
## - `max_stacks`: ceiling on intensity.
## - `slow_per_stack`: fraction of movement removed per stack. Above zero makes it a
##   *control* effect, which is what `control_resistance` shortens.
## - `damage_per_tick` / `tick_seconds`: damage over time. Ticked rather than applied per
##   frame so a burn reads as a series of hits and does not fire `damaged` sixty times a
##   second, which would strobe the hurt flash into a solid colour.
## - `escalates_to`: on reaching `max_stacks`, the stacks are spent and this is applied
##   instead. Chill into freeze is the only user, and it is what makes Cold Cache's
##   "repeated hits chill, then briefly freeze" one effect the player can see building.
const DEFINITIONS := {
	CHILL: {
		"seconds": 2.0,
		"max_stacks": 4,
		"slow_per_stack": 0.15,
		"damage_per_tick": 0.0,
		"tick_seconds": 0.0,
		"escalates_to": FREEZE,
		"color": Color(0.42, 0.78, 0.98),
	},
	FREEZE: {
		"seconds": 0.8,
		"max_stacks": 1,
		"slow_per_stack": 1.0,
		"damage_per_tick": 0.0,
		"tick_seconds": 0.0,
		"escalates_to": &"",
		"color": Color(0.72, 0.94, 1.0),
	},
	BURN: {
		"seconds": 3.0,
		"max_stacks": 3,
		"slow_per_stack": 0.0,
		"damage_per_tick": 0.15,
		"tick_seconds": 0.5,
		"escalates_to": &"",
		"color": Color(1.0, 0.55, 0.22),
	},
}

## Seconds a target cannot be frozen again after a freeze ends. Chill still accumulates
## during it, so the item keeps working — what the window prevents is the degenerate loop.
## Cold Cache chills on *every* hit, the starting weapon fires four times a second, and four
## hits is a freeze: without this, one item removes a single target from the fight
## permanently, which is not a build, it is an off switch.
const FREEZE_IMMUNITY_SECONDS := 2.2

## The shortest a resisted control effect may become. This is the floor that turns
## resistance into "briefer" rather than "never", and it is the whole difference between a
## boss being resistant and an item being dead weight.
const MIN_CONTROL_SECONDS := 0.15

## Radius of the drawn indicator ring.
@export var indicator_radius: float = 9.0

## 0.0 takes full-length control effects, 1.0 clamps every one of them to
## `MIN_CONTROL_SECONDS`. Bosses set this; ordinary enemies leave it at zero.
@export_range(0.0, 1.0) var control_resistance: float = 0.0

## id -> {"stacks": int, "seconds_left": float, "tick_left": float}
var _active: Dictionary[StringName, Dictionary] = {}

var _freeze_lockout := 0.0

var _health: HealthComponent


func _ready() -> void:
	_health = HealthComponent.find_on(get_parent())


func _physics_process(delta: float) -> void:
	_freeze_lockout = maxf(_freeze_lockout - delta, 0.0)
	if _active.is_empty():
		return

	var expired: Array[StringName] = []
	for id: StringName in _active:
		var state: Dictionary = _active[id]
		state["seconds_left"] = float(state["seconds_left"]) - delta
		_step_damage(id, state, delta)
		if float(state["seconds_left"]) <= 0.0:
			expired.append(id)

	for id: StringName in expired:
		_active.erase(id)
		if id == FREEZE:
			_freeze_lockout = FREEZE_IMMUNITY_SECONDS
		effect_expired.emit(id)

	queue_redraw()


## Applies one stack of `id`. Returns whether anything changed — false for an unknown
## effect, or for a freeze arriving during its immunity window.
func apply(id: StringName) -> bool:
	var definition: Dictionary = DEFINITIONS.get(id, {})
	if definition.is_empty():
		push_error("StatusEffectController: unknown status effect '%s'." % id)
		return false

	if id == FREEZE and _freeze_lockout > 0.0:
		return false

	var seconds := _resisted_seconds(definition)
	if seconds <= 0.0:
		return false

	var state: Dictionary = _active.get(id, {"stacks": 0, "seconds_left": 0.0, "tick_left": 0.0})
	var stacks := mini(int(state["stacks"]) + 1, int(definition["max_stacks"]))

	# Escalation spends the stacks rather than adding to them, so the player sees the chill
	# build and then *become* something else instead of quietly carrying both.
	var escalation := StringName(definition["escalates_to"])
	if stacks >= int(definition["max_stacks"]) and not escalation.is_empty():
		_active.erase(id)
		effect_expired.emit(id)
		queue_redraw()
		return apply(escalation)

	state["stacks"] = stacks
	# Refreshed to full rather than extended, so a long fight cannot bank an hour of burn.
	state["seconds_left"] = seconds
	if not state.has("tick_left") or float(state["tick_left"]) <= 0.0:
		state["tick_left"] = float(definition["tick_seconds"])
	_active[id] = state

	effect_applied.emit(id, stacks)
	queue_redraw()
	return true


## The factor this actor's movement is multiplied by. 1.0 is unimpeded, 0.0 is held still.
##
## A product across effects rather than the worst single one: two independent slows should
## compound the way two fire-rate items do, and taking the minimum would mean the second one
## a player picks up does nothing.
func get_speed_scale() -> float:
	var scale := 1.0
	for id: StringName in _active:
		var definition: Dictionary = DEFINITIONS[id]
		var per_stack := float(definition["slow_per_stack"])
		if per_stack <= 0.0:
			continue
		var stacks := int(_active[id]["stacks"])
		scale *= clampf(1.0 - per_stack * float(stacks), 0.0, 1.0)
	return scale


func has_effect(id: StringName) -> bool:
	return _active.has(id)


func get_stacks(id: StringName) -> int:
	return int(_active[id]["stacks"]) if _active.has(id) else 0


func get_seconds_left(id: StringName) -> float:
	return float(_active[id]["seconds_left"]) if _active.has(id) else 0.0


func is_frozen() -> bool:
	return is_zero_approx(get_speed_scale())


func clear() -> void:
	_active.clear()
	_freeze_lockout = 0.0
	queue_redraw()


## Finds the controller on an actor without depending on what it is named — the same lookup
## `HealthComponent` and `ItemInventory` use, and for the same reason: a projectile asks
## "can this thing be burned?" and must not care how the scene was assembled. Returns null
## for anything that cannot, which is how walls and pickups opt out by saying nothing.
static func find_on(body: Node) -> StatusEffectController:
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is StatusEffectController:
			return child as StatusEffectController
	return null


## Control effects are shortened by resistance and floored; damage effects are not touched.
## Shortening a burn would make resistance mean two different things depending on which item
## the player happened to bring.
func _resisted_seconds(definition: Dictionary) -> float:
	var seconds := float(definition["seconds"])
	if float(definition["slow_per_stack"]) <= 0.0:
		return seconds
	return maxf(seconds * (1.0 - control_resistance), MIN_CONTROL_SECONDS)


func _step_damage(id: StringName, state: Dictionary, delta: float) -> void:
	var definition: Dictionary = DEFINITIONS[id]
	var per_tick := float(definition["damage_per_tick"])
	if per_tick <= 0.0 or _health == null:
		return

	state["tick_left"] = float(state["tick_left"]) - delta
	if float(state["tick_left"]) > 0.0:
		return
	state["tick_left"] = float(definition["tick_seconds"])

	# No direction and no knockback: a burn is not a shove, and giving it one would push
	# enemies around from a source that is not anywhere.
	_health.apply_damage(
		DamageInfo.new(per_tick * float(state["stacks"]), self, Vector2.ZERO, 0.0)
	)


## One arc per active effect, splitting the ring between them. Literal composition: a target
## that is both chilled and burning wears half a cyan ring and half an orange one, so what
## the player sees is the same statement the maths is making.
func _draw() -> void:
	if _active.is_empty():
		return

	var ids: Array[StringName] = _active.keys()
	var span := TAU / float(ids.size())
	for index: int in ids.size():
		var definition: Dictionary = DEFINITIONS[ids[index]]
		var color: Color = definition["color"]
		var fade := clampf(get_seconds_left(ids[index]) / maxf(float(definition["seconds"]), 0.001), 0.25, 1.0)
		draw_arc(
			Vector2.ZERO,
			indicator_radius,
			span * float(index),
			span * float(index + 1),
			10,
			Color(color.r, color.g, color.b, fade),
			1.5,
			false
		)

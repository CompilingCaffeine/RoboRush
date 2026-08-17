class_name HealthComponent
extends Node
## Integrity for anything that can be destroyed.
##
## The same component runs on the player and on every enemy, so damage is symmetric
## by construction: a projectile does not care what it hit, only whether the thing
## it hit has one of these.
##
## Health is float even though the player's integrity is described in whole points,
## because items deal fractions of a hit (Fork Bomb children at 60%, chain lightning
## at 0.7). The HUD rounds for display; the maths stays exact.

## Emitted only when damage actually lands — invulnerable and fatal-to-a-corpse hits
## do not fire it.
signal damaged(info: DamageInfo, remaining: float)

signal healed(amount: float, remaining: float)

## Emitted once, on the transition to zero. Never fires twice.
signal died()

## The lowest a maximum may be driven to. One point rather than zero, so nothing that lowers the
## ceiling — an item on pickup, a spent death save — can be lethal by arithmetic. It is also the
## value a death save leaves the pool at, and those are deliberately the same number: "as small as
## integrity is allowed to get" is one fact, and stating it twice is how the two come to disagree.
const MINIMUM_MAX_HEALTH := 1.0

@export var max_health: float = 3.0

## Seconds of immunity granted after a hit lands. Zero for enemies, so rapid fire
## reads as rapid damage.
@export var invulnerability_seconds: float = 0.0

var current: float

## Called when a hit would leave nothing. It may put integrity back, and whether it did is the whole
## of how a death is averted — there is no boolean to disagree with the number. A guard that changes
## nothing lets the blow stand, which is the right default: better a death the player can see than an
## invulnerable robot sitting at zero.
##
## A callable the owner sets, for the same reason `add_immunity_source` is one: the player's death
## save is an item effect, and this component runs on every enemy in the game. It must not learn the
## word "item" to support one. Unset on everything except the player, where `Player` supplies it.
var death_guard := Callable()

## Consulted before a hit lands. Returning true swallows it whole: no integrity is lost, no
## `damaged` is emitted, and `apply_damage` reports that nothing landed.
##
## Distinct from an immunity source, and the distinction is the mechanic. Immunity is a *window* —
## everything during a dash misses. An absorber is a *charge*: it is spent on one hit, whatever the
## hit was, which is what makes Faraday Cage's shield readable as one blocked blow rather than as a
## second of safety.
var damage_absorber := Callable()

## Multipliers on incoming damage, asked rather than stored — the same shape as `_immunity_sources`
## and for the same reason. A shocked enemy takes more from everything, and the thing that knows it
## is shocked is its `StatusEffectController`, which registers itself here rather than this component
## learning what a status is.
var _damage_scale_sources: Array[Callable] = []

var _invulnerable_left := 0.0
var _is_dead := false

## Immunity granted by something other than this component. The dash owns its own window,
## and copying that window into a second timer here is how the two came to disagree — the
## robot flashed as invulnerable while damage went straight through. Asking the owner
## instead means there is exactly one dash window and both the visuals and the damage path
## read it.
var _immunity_sources: Array[Callable] = []


func _ready() -> void:
	current = max_health


func _physics_process(delta: float) -> void:
	step(delta)


## Separate from _physics_process so the timing can be driven directly from a test.
func step(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


## Applies new limits and refills. Used by the player, whose maximum comes from
## PlayerConfig rather than from this component's inspector defaults.
##
## Clears any window still running, for the same reason it clears `_is_dead`: this is the component
## being given a life, not adjusted mid-one. A caller that asks for zero seconds of invulnerability
## and gets a window left over from before it asked has been told something untrue — which is what
## happened the moment a second thing besides a hit could open one, and is why the timer is named
## here rather than left to expire on its own.
func configure(new_max_health: float, new_invulnerability: float) -> void:
	max_health = new_max_health
	invulnerability_seconds = new_invulnerability
	current = new_max_health
	_invulnerable_left = 0.0
	_is_dead = false


## Returns whether the damage landed. Declining silently (dead, invulnerable, or
## zero damage) means callers never have to check first.
func apply_damage(info: DamageInfo) -> bool:
	if _is_dead or is_invulnerable() or info.amount <= 0.0:
		return false

	# Before the amount is even scaled: an absorbed hit did not happen, and a shield that swallowed
	# a shot the target was weak to should not report a bigger blocked number.
	if damage_absorber.is_valid() and damage_absorber.call(info):
		return false

	# The scaled amount is written back onto the event rather than kept local, because everything
	# downstream reads `info.amount` as "what this hit did" — the run's damage statistics, the
	# damage numbers that float off the target, the feedback director. A shocked enemy that visibly
	# takes 35% more while the HUD reports the unscaled figure is a bug report about the item.
	info.amount *= get_damage_scale()

	current = maxf(current - info.amount, 0.0)

	# Before `damaged` is emitted, not after, and this ordering is load-bearing. Everything
	# listening to that signal reads `remaining <= 0.0` as "this was the killing blow":
	# `RunManager` writes the cause of death from it and the feedback director plays the
	# low-integrity warning off it. Averting the death afterwards would leave the run filed with a
	# cause of death it survived.
	if current <= 0.0 and death_guard.is_valid():
		death_guard.call()

	if invulnerability_seconds > 0.0:
		_invulnerable_left = invulnerability_seconds
	damaged.emit(info, current)

	# Guarded by _is_dead rather than by `current <= 0`, so a killing blow that
	# arrives in the same frame as another cannot emit died() twice.
	if current <= 0.0:
		_is_dead = true
		died.emit()
	return true


## Changes the maximum without refilling, for items that move the ceiling.
##
## Current integrity is clamped down when the maximum drops (Unsafe Overclock) and left
## exactly where it was when the maximum rises — Reinforced Chassis heals through
## `heal()` as a separate, declared effect, so gaining maximum integrity is never a
## silent full repair. The floor of one point means no item can be lethal on pickup.
func set_max_health(new_max: float) -> void:
	max_health = maxf(new_max, MINIMUM_MAX_HEALTH)
	current = minf(current, max_health)


## Grants immunity for `seconds` from something other than a hit landing. Two callers, and both are
## about a moment the player could not have played around: the death save's grace window, because
## surviving a lethal blow and then being killed by the next shot in the same volley is not a save
## but a delay, and `Player._on_room_entered`, because a room's enemies wake on the frame the player
## crosses its threshold.
##
## Extends rather than replaces, so a grace window cannot shorten the ordinary post-hit immunity —
## which is what makes it safe for two of these to overlap without either knowing about the other.
func grant_invulnerability(seconds: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, seconds)


## Puts integrity back where a saved run left it. Not `heal`, and deliberately not built out of
## it: healing is an event the game reacts to — a repair sound, a flash, a statistic — and a
## resumed run did not repair anything, it merely continued.
##
## Silent for the same reason. Nothing needs telling: the HUD reads integrity every frame rather
## than tracking it from signals, so a restored value is on screen the next frame without any
## listener having to be lied to about a repair that did not happen.
##
## Clamped into the pool that exists *now*, which is what makes the order in `Player.restore_build`
## matter: the items come back first so the ceiling is the one the build earned, and only then is
## the integrity written into it.
func restore(amount: float) -> void:
	current = clampf(amount, 0.0, max_health)
	_is_dead = current <= 0.0


func heal(amount: float) -> void:
	if amount <= 0.0 or _is_dead or is_approx_full():
		return
	current = minf(current + amount, max_health)
	healed.emit(amount, current)


## Registers something else that can grant immunity — a dash, and later an emergency
## barrier or a defence module. A list rather than one slot so a second source never has to
## argue with the first about who owns it.
func add_immunity_source(source: Callable) -> void:
	if source.is_valid() and source not in _immunity_sources:
		_immunity_sources.append(source)


## Registers something that multiplies incoming damage — a status effect, and later armour or a
## weakness. A list rather than one slot so a second source never has to argue with the first.
func add_damage_scale_source(source: Callable) -> void:
	if source.is_valid() and source not in _damage_scale_sources:
		_damage_scale_sources.append(source)


## The product of every registered multiplier. A product rather than the largest, for the reason
## `StatusEffectController.get_speed_scale` is one: two independent effects should compound, and
## taking the maximum would make the second one the player applied do nothing.
func get_damage_scale() -> float:
	var scale := 1.0
	for source: Callable in _damage_scale_sources:
		if source.is_valid():
			scale *= float(source.call())
	return scale


func is_invulnerable() -> bool:
	if _invulnerable_left > 0.0:
		return true
	for source: Callable in _immunity_sources:
		if source.is_valid() and source.call():
			return true
	return false


func is_alive() -> bool:
	return not _is_dead


func is_approx_full() -> bool:
	return is_equal_approx(current, max_health)


## Fraction remaining, for health bars.
func get_ratio() -> float:
	return current / maxf(max_health, 0.001)


## Finds the health component on a body without depending on what it is named.
## Returns null for anything indestructible, which is how projectiles tell a wall
## from an enemy.
static func find_on(body: Node) -> HealthComponent:
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is HealthComponent:
			return child as HealthComponent
	return null

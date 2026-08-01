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

@export var max_health: float = 3.0

## Seconds of immunity granted after a hit lands. Zero for enemies, so rapid fire
## reads as rapid damage.
@export var invulnerability_seconds: float = 0.0

var current: float

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
func configure(new_max_health: float, new_invulnerability: float) -> void:
	max_health = new_max_health
	invulnerability_seconds = new_invulnerability
	current = new_max_health
	_is_dead = false


## Returns whether the damage landed. Declining silently (dead, invulnerable, or
## zero damage) means callers never have to check first.
func apply_damage(info: DamageInfo) -> bool:
	if _is_dead or is_invulnerable() or info.amount <= 0.0:
		return false

	current = maxf(current - info.amount, 0.0)
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
	max_health = maxf(new_max, 1.0)
	current = minf(current, max_health)


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

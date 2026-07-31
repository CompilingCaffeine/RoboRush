class_name WeaponConfig
extends Resource
## A weapon as data: how often it fires, in what arrangement, and what it fires.
##
## `projectiles_per_shot` and `spread_degrees` are the entire fire pattern for now.
## Spec section 14 lists FirePattern as its own component, and that is the right
## shape once weapon cores exist (charge shots, saw launchers, beam emitters cannot
## be expressed as "n projectiles in an arc"). Until there is a second pattern to
## support, a dedicated resource would be an abstraction with one implementation.

@export var display_name: String = "Unnamed Weapon"

## What this weapon fires. The projectile owns all its own behaviour.
@export var projectile: ProjectileConfig

@export_group("Timing")

## Shots per second before fire-rate modifiers.
@export var shots_per_second: float = 4.0

@export_group("Pattern")

@export var projectiles_per_shot: int = 1

## Total arc the shot is spread across. Spread is centred on the aim direction.
@export var spread_degrees: float = 0.0

## Distance from the shooter's origin that projectiles appear, so they clear the
## shooter's own body instead of spawning inside it.
@export var muzzle_offset: float = 9.0

@export_group("Feedback")

## Sound id passed to AudioManager on each shot.
@export var fire_sound: StringName = &"fire"

## Screen shake trauma added per shot. Keep near zero for rapid-fire weapons —
## spec section 7 is explicit that screen shake must not be overused.
@export var screen_shake: float = 0.0


## Seconds between shots at the base fire rate.
func get_fire_interval() -> float:
	return 1.0 / maxf(shots_per_second, 0.01)

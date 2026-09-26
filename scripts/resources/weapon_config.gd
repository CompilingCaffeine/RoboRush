class_name WeaponConfig
extends Resource
## A weapon as data: how often it fires, in what arrangement, and what it fires.
##
## The pattern fields below are the whole fire pattern: how many projectiles, across what arc, how
## far apart, which way, and whether the trigger fires on the press or on the release. Spec section
## 14 lists FirePattern as its own component, and that is the right shape once weapon cores exist
## that cannot be expressed as "n projectiles in an arc" — a beam, a saw. Until there is a second
## kind of pattern to support, a dedicated resource would be an abstraction with one implementation.
##
## Items reach these fields by name through `WeaponModifierStack` (roadmap SYS-1), the same way
## they reach a projectile's through `ProjectileModifierStack`, so no field here knows which item
## adjusts it.

enum FireMode {
	## Fires while the trigger is held, as fast as the fire rate allows.
	AUTO,
	## Builds a charge while the trigger is held and fires once on release, harder the longer it was
	## held. See `charge_seconds`.
	CHARGE,
}

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

## Sideways distance between neighbouring projectiles of one shot, in pixels, centred on the aim
## line. Zero stacks them on one line, which is right for a fan and wrong for parallel shots: two
## rivets with no spread and no offset are one rivet drawn twice.
@export var lateral_offset: float = 0.0

## Every other shot leaves backwards. Counted per weapon rather than on the shared shot counter, so a
## drone alternates on its own shots instead of taking every backward shot the robot does not.
@export var alternate_rear: bool = false

## Distance from the shooter's origin that projectiles appear, so they clear the
## shooter's own body instead of spawning inside it.
@export var muzzle_offset: float = 9.0

@export_group("Charge")

@export var fire_mode: FireMode = FireMode.AUTO

## Seconds of holding that reach a full charge. Holding longer adds nothing.
@export var charge_seconds: float = 1.0

## Damage multiplier at full charge, reached linearly from 1.0 at no charge. A tap still fires, at
## ordinary strength.
@export var charge_max_scale: float = 1.0

## Radius multiplier at full charge, on the same line as the damage.
@export var charge_radius_scale: float = 1.0

@export_group("Feedback")

## Sound id passed to AudioManager on each shot.
@export var fire_sound: StringName = &"fire"

## Screen shake trauma added per shot. Keep near zero for rapid-fire weapons —
## spec section 7 is explicit that screen shake must not be overused.
@export var screen_shake: float = 0.0


## Seconds between shots at the base fire rate.
func get_fire_interval() -> float:
	return 1.0 / maxf(shots_per_second, 0.01)

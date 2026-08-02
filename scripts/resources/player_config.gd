class_name PlayerConfig
extends Resource
## Every tunable number that defines how the maintenance robot feels to control.
##
## Kept in a Resource rather than as constants in the player script so values can
## be tweaked live in the inspector while playing, and so alternate tunings (a
## test build, a future second character) are just another .tres file.
##
## Defaults come from spec section 6. Change them here, not in code.

@export_group("Movement")

## Top speed under normal movement, in pixels per second.
@export var move_speed: float = 160.0

## Pixels per second squared applied while a movement direction is held.
@export var acceleration: float = 1400.0

## Pixels per second squared applied when movement input is released. Higher than
## acceleration on purpose: stopping should feel crisper than starting.
@export var deceleration: float = 1800.0

@export_group("Dash")

## Distance a single dash travels, in pixels. Combined with dash_duration this
## determines dash speed, so the dash always covers the same ground.
@export var dash_distance: float = 70.0

## How long the dash movement lasts, in seconds.
@export var dash_duration: float = 0.14

## Seconds to refill one dash charge.
@export var dash_cooldown: float = 1.1

## Seconds of invulnerability granted at the start of a dash. Shorter than the
## dash itself, so dashing through an attack is a timing win rather than a
## free escape.
@export var dash_invulnerability: float = 0.10

## Dash charges available at full. Items may raise this later (Backup Battery).
@export var dash_charges: int = 1

## How long a dash press stays queued when it cannot be honoured yet, so a press
## landing a few frames early still fires instead of being silently dropped.
@export var dash_input_buffer: float = 0.12

@export_group("Integrity")

## Starting and maximum integrity points (health).
@export var max_integrity: int = 6

## Seconds of invulnerability granted after taking damage. Unused until combat
## exists, but it belongs with the rest of the survivability tuning.
## How fast a shove from damage bleeds off, in pixels per second squared. Separate from
## `deceleration`, which is how hard the robot brakes under its own power: at 1800 a 130 px/s
## contact shove would be gone in 0.07 seconds and move the player about five pixels, which is
## indistinguishable from not being knocked back at all.
@export var knockback_decay: float = 700.0

@export var damage_invulnerability: float = 0.8

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

## How fast a shove from damage bleeds off, in pixels per second squared. Separate from
## `deceleration`, which is how hard the robot brakes under its own power: at 1800 a 130 px/s
## contact shove would be gone in 0.07 seconds and move the player about five pixels, which is
## indistinguishable from not being knocked back at all.
@export var knockback_decay: float = 700.0

## Seconds of invulnerability granted after taking damage.
@export var damage_invulnerability: float = 0.8

## Seconds of invulnerability granted for walking through a door, before the room the player has
## just entered is allowed to charge them anything.
##
## Beta testers named this one: a room's enemies wake on the frame the player crosses its threshold
## (`FloorController._enter_room` calls `Room.set_active` and then announces the entry), so a shot
## already lined up on the doorway lands before the player has seen the room they are in. That is a
## point of integrity spent on nothing the player could have done, which is the definition of the
## hit they were complaining about.
##
## 0.6 seconds is about 96 pixels at walking speed — six tiles, comfortably past the doorway and
## into a position the player chose. Deliberately shorter than `damage_invulnerability`, so entering
## a room is never safer than being hit, and short enough that it cannot be used to walk through a
## fight: the doors of an uncleared room lock behind the player, so there is no way to spend it
## twice on the same room.
@export var room_entry_grace: float = 0.6

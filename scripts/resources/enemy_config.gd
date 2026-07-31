class_name EnemyConfig
extends Resource
## Tuning for one enemy type.
##
## Spec section 15: each enemy has a recognisable silhouette and *one* clear
## behaviour, and enemies exist to create movement problems. These fields describe
## the movement problem; the enemy script decides how to pose it.

@export var display_name: String = "Unnamed Unit"

@export_group("Durability")

@export var max_health: float = 3.0

## 0.0 takes full knockback, 1.0 is immovable.
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0

@export_group("Movement")

@export var move_speed: float = 55.0
@export var acceleration: float = 420.0
@export var deceleration: float = 600.0

## Distance the enemy tries to hold from the player. It advances when further away
## and backs off when closer, which is what stops a shooting enemy from simply
## walking into the player's face.
@export var preferred_range: float = 96.0

## Dead zone around preferred_range where the enemy holds position instead of
## jittering back and forth across the threshold.
@export var range_tolerance: float = 20.0

@export_group("Combat")

@export var weapon: WeaponConfig

## Contact damage per hit. Zero for enemies that only shoot.
@export var contact_damage: float = 0.0

## Seconds the enemy telegraphs before firing. Spec section 15 wants readable
## attacks, and an unannounced shot from an approaching enemy is not readable.
@export var telegraph_seconds: float = 0.35

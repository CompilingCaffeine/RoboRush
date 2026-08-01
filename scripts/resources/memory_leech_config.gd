class_name MemoryLeechConfig
extends EnemyConfig
## Tuning specific to the Memory Leech.
##
## The charge is the whole enemy. Spec section 15 gives it one job — force movement — and
## it does that by being the only thing in the game that commits to a direction *before*
## it moves, so the player is being asked to read an intention rather than to outrun a
## chaser.

## How close the leech must be before it stops and commits to a charge.
@export var charge_trigger_range: float = 118.0

## The pause before charging. This is the tell, and it is deliberately long enough to
## dodge: the leech is dangerous because it is fast, not because it is unfair.
@export var windup_seconds: float = 0.42

## Speed during the charge. Well above `move_speed` — the charge must outrun the player.
@export var charge_speed: float = 265.0

@export var charge_seconds: float = 0.3

## Seconds spent slow and harmless after a charge, which is the window the player kills it
## in. Without a recovery the leech is a permanent blender.
@export var recover_seconds: float = 0.65

class_name CoreIntelligenceConfig
extends RuntimeErrorConfig
## Finale tuning layered on Runtime Error's proven lane and projectile vocabulary.
## Core Intelligence adds only one verb: it can drive familiar throughput zones on its own clock.

@export_group("Driven throughput")

## A little longer than a room zone's occupancy ramp. The player has already learned the colour,
## but a boss-placed zone appears under pressure and deserves a complete readable rise.
@export var vent_seconds: float = 1.7

## Large enough to dislodge a firing position, small enough that three never erase the arena.
@export var vent_size_tiles := Vector2i(4, 3)

## The player's current position and two orthogonal follow-ups toward the room's open side. All are
## announced together and leave most of the 26x12-tile arena untouched.
@export var vent_count: int = 3

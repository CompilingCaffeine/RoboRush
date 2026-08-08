class_name NullPointerConfig
extends EnemyConfig
## Tuning specific to the Null Pointer.
##
## The Compiler asks "is that stripe of the room safe?"; this asks "are you still standing
## where you were a second ago?". Both are compile lanes, so the two compose without
## teaching the player a second warning language — the difference is entirely in where the
## rectangle is chosen, which is why the only new knobs here are about the patch and its
## timing, and everything about drifting at range is inherited unchanged.

## Seconds between one patch resolving and the next being marked.
@export var mark_interval: float = 2.4

## How long the patch telegraphs before it executes. Shorter than the Compiler's lane
## because the answer is smaller: a Compiler lane spans the room and asks the player to
## leave a stripe, this asks them to leave a square they are standing in the middle of.
@export var mark_telegraph_seconds: float = 0.65

## How long the executed patch stays lit. Cosmetic — the damage check happens once, at the
## instant the strike begins, inside `CompileLane`.
@export var mark_strike_seconds: float = 0.2

@export var mark_damage: float = 1.0

## Side length of the patch, in room tiles. Three is the smallest size that still reads as
## a deliberate square at this resolution rather than as a stray pixel, and it leaves the
## player's own tile ringed by an escape in all eight directions.
##
## How far it hovers from the player is `preferred_range` on `EnemyConfig`, not a knob of
## its own — "hold this distance" is not a Null Pointer idea.
@export var mark_tiles: int = 3

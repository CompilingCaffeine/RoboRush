class_name CodeRunnerConfig
extends EnemyConfig
## Tuning specific to the Code Runner.
##
## Reuses `move_speed`/`preferred_range`/`range_tolerance`/`weapon` from `EnemyConfig`
## unchanged — the only genuinely new knob is how long it commits to one strafe direction
## before reversing.

## Seconds before the strafe direction flips. Too short reads as jittering in place; too
## long reads as orbiting rather than strafing.
@export var direction_hold_seconds: float = 1.4


## The rung above, for the floors that have already taught the strafe — see `HotPathRunner`. Here
## rather than in a resource of its own, the way `RecursionConfig` holds the elder rung: a hot path
## is a Code Runner that leaves something behind, not a different enemy.

## Seconds between patches. Roughly what it takes the runner to cross its own body twice at
## `move_speed`, so the trail reads as a line of stepping stones rather than as a wall — the ground
## it denies has gaps in it by construction.
@export var trail_interval: float = 0.85

## How large a patch is, in tiles. Two, matched to the width of the body that dropped it: what the
## trail costs the player is the strafe line, not the room.
@export var trail_tiles: int = 2

## How long a patch telegraphs before it strikes. Longer than the Compiler's, because it appears
## *under* a player who is tracking a moving target rather than out in front of them, and the eye
## that is following the runner has to be given time to notice the floor.
@export var trail_telegraph_seconds: float = 0.9

@export var trail_strike_seconds: float = 0.25

@export var trail_damage: float = 1.0

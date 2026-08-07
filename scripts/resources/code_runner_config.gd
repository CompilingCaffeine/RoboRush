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

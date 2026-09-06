class_name CompilerConfig
extends EnemyConfig
## Tuning specific to the Compiler.
##
## Where Firewall Node controls space continuously, this controls it in bursts: paint a
## lane, let it read, execute, then nothing until the next one. The gap between lanes is the
## entire difficulty knob — everything else about the hazard itself lives on `CompileLane`.

## Seconds between one lane finishing and the next one being painted.
@export var lane_interval: float = 3.2

## How long a lane telegraphs (amber, growing) before it strikes. Long enough to read and
## step out of it — this is the number that makes the mechanic fair.
##
## Was 1.1 and is now 0.8, deliberately shorter than the Runtime Error boss's 0.9. That
## inversion looks backwards and is not: the boss paints two staggered lanes and whole
## checkerboards, so its warnings cover far more of the room and need longer to *read*,
## while a single Compiler lane is one stripe you either are or are not standing in.
## Escaping is never the constraint at either number — a 16px lane needs about 13px of
## sideways travel and the robot moves 160px/s, so the whole cost is noticing.
@export var lane_telegraph_seconds: float = 0.8

## How long the strike itself stays lit (red) before the lane clears. The damage check
## happens once, at the moment the strike begins — this is purely how long it stays visible.
@export var lane_strike_seconds: float = 0.25

@export var lane_damage: float = 1.0


## The rung above, for the floors that have already taught this enemy — see `OptimizingCompiler`.
## Written here as what changes rather than as a second resource, for `RecursionConfig`'s reason:
## an optimizing pass is a Compiler with one more idea, and two files would be two answers to what
## a Compiler is.

## How long the second pass telegraphs. Shorter than the first, because it is not asking the player
## to notice a lane — they are already moving out of one — it is asking them not to stop.
##
## Not shorter than they can answer: leaving a lane costs about 13 pixels of travel at 160 px/s, so
## the floor under this number is under a tenth of a second and the value below is five times that.
@export var second_pass_telegraph_seconds: float = 0.55

## Seconds after the first lane *strikes* before the second one is painted. Zero chains them
## directly, which is the version worth shipping: the pause between the two is the moment the
## player would use to stop moving.
@export var second_pass_delay: float = 0.0

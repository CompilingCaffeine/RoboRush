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
## cross the room away from it — this is the number that makes the mechanic fair.
@export var lane_telegraph_seconds: float = 1.1

## How long the strike itself stays lit (red) before the lane clears. The damage check
## happens once, at the moment the strike begins — this is purely how long it stays visible.
@export var lane_strike_seconds: float = 0.25

@export var lane_damage: float = 1.0

class_name DeadlockConfig
extends EnemyConfig
## Tuning specific to the Deadlock.
##
## Every other enemy in the game is answered by moving *somewhere*; this one is answered by
## moving somewhere *specific*, so the numbers that matter are the two that define what
## "specific" means — how long the player has before the tether starts costing them
## (`acquire_seconds`) and how far they would have to run if they chose distance over cover
## (`tether_range`).

## Seconds the tether holds, amber and harmless, before it starts draining. The whole
## warning: long enough to notice a line has appeared and pick which way to break it.
@export var acquire_seconds: float = 0.9

## Integrity per tick once the tether goes red. Deliberately a fraction — this enemy is a
## deadline, not a burst, and a player who reaches cover late should have paid for the
## delay rather than lost a whole point to it.
@export var drain_damage: float = 0.5

## Seconds between drain ticks.
@export var drain_interval: float = 0.85

## How far the tether reaches. Beyond this it snaps, which is the second of the two answers
## and the one that keeps this enemy fair in a room with no cover worth the name: outrunning
## it always works, it is just slower than stepping behind a server rack.
@export var tether_range: float = 190.0

## Seconds after a tether breaks before it may lock on again. This is what makes ducking
## behind cover *worth* something — without it the drain resumes the instant the player
## leans back out, and breaking line of sight buys a single frame.
@export var reacquire_delay: float = 0.6

## Thickness of the drawn tether. What is drawn is exactly what is checked, the same
## contract Firewall Node's beams hold.
@export var tether_width: float = 2.0

class_name FirewallNodeConfig
extends EnemyConfig
## Tuning specific to the Firewall Node.
##
## Spec section 15 gives it the one job no other enemy has: control space. It never moves
## and never chases, so everything below is about the shape of the area it denies.

## How many beams radiate from the node, evenly spaced around it. Two makes a line, three
## makes a room hard to cross, four makes it nearly impossible — this is the difficulty
## knob for this enemy.
@export var beam_count: int = 3

## Maximum beam reach. Beams are cut short by walls, so this is a ceiling rather than a
## length.
@export var beam_length: float = 132.0

## Radians per second the whole fan rotates. Slow enough to walk around, fast enough that
## standing still is not a plan.
@export var beam_rotation_speed: float = 0.85

## Half-width of the damaging region either side of a beam's centre line, in pixels. The
## drawn line is this wide too, so what hurts is exactly what is visible.
@export var beam_half_width: float = 2.5

@export var beam_damage: float = 1.0

## Seconds before a beam can hit the same target again. Shorter than the player's own
## damage invulnerability would do nothing, so this is really "how long you may stand in
## a beam before it counts again".
@export var beam_interval: float = 0.85

@export var beam_color: Color = Color(1.0, 0.42, 0.28, 0.85)

## Beam brightness oscillation, so a stationary hazard still reads as live.
@export var beam_pulse_hz: float = 3.0


## The rung above, for the floors that have already taught this enemy — see `RedundantFirewall`.
## In this resource rather than one of its own, the way the Recursion family's elder rung is: a
## redundant node is a Firewall Node that picks up load, not a different enemy.

## Beams gained each time the node takes over for something that has died in its room. One, so the
## escalation is countable while it is happening — the player can see the fan gain a spoke and know
## what caused it.
@export var failover_beams: int = 1

## The most beams it may ever have. Six leaves a sixty-degree gap in the fan, which is a real
## rotating opening at the edge of its reach and no opening at all next to the body. That is the
## intended shape: a node at its cap does not deny the room, it denies its own circle, and the room
## is 416 pixels wide against a 132-pixel beam.
@export var failover_max_beams: int = 6

## How much faster the fan turns per failover. Small and compounding: three steps is a quarter
## faster, which reads as spinning up rather than as a different enemy.
@export var failover_rotation_scale: float = 1.08

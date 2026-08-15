class_name LoadBalancerConfig
extends EnemyConfig
## Tuning specific to the Load Balancer.
##
## Every field below describes one thing: the plate. It is the enemy's armour on the side it
## faces and the only place its contact damage lands, so the numbers here decide both how hard
## it is to hurt and how dangerous it is to be near — which is deliberate, because those are the
## same decision for this enemy and splitting them into two sets of knobs would let them drift
## into disagreeing about which way it is pointing.

## How wide the plate is, in degrees, centred on whatever it is facing.
##
## The gap left over is not the answer to this enemy and is not meant to look like one: the plate
## tracks, so the open arc is behind you as soon as you stand in it. What decides the fight is
## `plate_turn_speed` against how fast the player can circle. This only sets how much of a head
## start out-turning it needs before shots start landing.
@export var plate_arc_degrees: float = 150.0

## Radians per second the plate turns toward the player, by the shorter way round.
##
## The whole enemy is this number against `v / r` — the player's angular speed, which rises as
## they close. At 160 px/s the robot out-turns 1.5 rad/s inside about 105 pixels and cannot
## outside it, so the answer to a Load Balancer is to get close and stay moving, and the price of
## being close is the plate itself. That is the trade the enemy exists to offer.
##
## Scaled by any status on the enemy, so a chill slows the tracking as well as the walk. That is
## the one thing a player can do to it from in front — see `LoadBalancer._absorb`.
@export var plate_turn_speed: float = 1.5

## How far out the plate is drawn, in pixels. Comfortably outside the 7-pixel body so the arc
## reads as a thing bolted to the front rather than as a highlight on the sprite.
@export var plate_radius: float = 11.0

## Plate line width, in pixels.
@export var plate_thickness: float = 3.0

## The plate at rest, and while it is being hit.
##
## Near-white rather than anything on the teal-to-red ramp. This floor's throughput zones own that
## gradient, and an enemy whose armour glowed somewhere along it would be a second thing on screen
## claiming to mean heat. The same call the floor's tiles already make — see `ThermalZone` and the
## Data Center palette in `tools/generate_art.py`.
@export var plate_color: Color = Color(0.76, 0.85, 0.90, 0.95)
@export var plate_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Seconds the plate stays lit after swallowing a hit.
##
## The only feedback a blocked shot produces — no hurt flash fires, because nothing was damaged —
## and it has to be enough on its own, or the first Load Balancer a player meets reads as an enemy
## their weapon has stopped working on.
@export var plate_flash_seconds: float = 0.14

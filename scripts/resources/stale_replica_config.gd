class_name StaleReplicaConfig
extends EnemyConfig
## Tuning specific to the Stale Replica.
##
## The enemy is two numbers — how far behind it runs, and how fast it can run — and everything
## else here is how it is drawn. Both of those numbers are answers to the same question, which is
## the only question the player ever asks about it: *can it reach me if I keep going?*

## How far behind the player it walks, in seconds.
##
## This is the whole margin the player is given, and it wants to be long enough to be a distance
## rather than a delay — at 160 px/s a second of lag is 160 pixels, most of the width of a room's
## half. Much shorter and the replica reads as an ordinary chaser that happens to steer badly;
## much longer and it is never in the same part of the room as the fight.
@export var delay_seconds: float = 1.1

## How close to its target it has to get before it counts as arrived and stops.
##
## Without it, a replica that has caught its target oscillates across it — the point it is walking
## to moves a few pixels per frame, and a body that accelerates cannot sit exactly on a moving
## point. Standing still while its target creeps away is the honest picture of what it is doing.
@export var arrive_radius: float = 4.0

## The path it is about to walk, drawn behind it.
##
## Low alpha on purpose. This is a telegraph, not a hazard: it says where the replica is going,
## and the player already knows, because they walked it. Anything brighter would be a third thing
## competing for attention in a room that already has heat on the floor.
@export var trail_color: Color = Color(0.76, 0.85, 0.90, 0.22)

@export var trail_width: float = 1.0

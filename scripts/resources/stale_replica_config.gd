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


## The rung above, for the floors that have already taught this enemy — see `LaggingReplica`. In
## this resource rather than one of its own, the way the Recursion family's elder rung is: an echo
## is a replica that also lagged the player's *fire*, not a different enemy.

## What an echo fires. Its own projectile rather than the player's weapon, and that is the whole of
## the fairness argument: what is replayed is where and when they fired, never how hard. The worst
## legal build does about nine times the damage the enemies are written for, and a replica that
## returned that would be a build killing itself rather than an enemy asking a question.
@export var echo_shot: ProjectileConfig

## The fastest an echo can follow another one. A player holding the trigger fires far quicker than
## this, and the shots in between are simply not replayed: this enemy repeats a *rhythm*, and a
## rhythm at fifteen rounds a second is a wall. It also bounds what the replica can have queued —
## `delay_seconds` divided by this, and no more.
@export var echo_min_interval: float = 0.45

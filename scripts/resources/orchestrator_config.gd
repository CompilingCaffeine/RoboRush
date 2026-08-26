class_name OrchestratorConfig
extends Resource
## Cloud Operations' boss, as data. See `Orchestrator` for the fight.

## Stable identifier, for the reason `ItemConfig.id` must not change once it ships.
@export var id: StringName = &"orchestrator"

@export var display_name: String = "Orchestrator"

@export_group("Plates")

## How many plates the boss can be standing on. Three, and the number is the fight rather than a
## setting: two would make the destination knowable without reading anything, and four puts a plate
## far enough from the others that the run to deny it is decided by where the player already was
## rather than by how fast they moved.
@export var plate_count: int = 3

## How far out from the arena's centre the plates sit, as a fraction of the arena's half-extent.
## Under one so the plates stay clear of the walls, and high enough that crossing between them is a
## real distance in a 416x192 room.
@export_range(0.1, 1.0) var plate_radius: float = 0.72

## The side of a plate's square, in pixels. Matched to the two-tile plates the floor's rooms use, so
## a player who has learned what a pad looks like recognises one here.
@export var plate_size: float = 32.0

@export_group("Durability")

## Damage the live instance absorbs before it commits to a failover.
##
## This is not the boss's health. Nothing here can be killed by damage: the pool fills, the boss
## migrates, and the pool resets. What damage buys is *events* — see `Orchestrator` on why the fight is
## scored in denials rather than in hit points.
@export var pool_per_generation: float = 34.0

## How many generations the boss has. Each one is a denied failover, and three denials is the whole
## fight.
@export var generations: int = 3

@export_group("Failover")

## How long the boss telegraphs a failover before it resolves.
##
## The single most important number in the fight, because it is the player's entire budget for
## crossing the arena to deny it. Long enough that a player anywhere in the room can reach any plate
## — a 416-pixel room at the player's walking speed, plus the pads the arena has in its corners —
## and short enough that arriving is a scramble rather than a stroll.
@export var telegraph_seconds: float = 1.9

## How long the boss is stunned and open after a denied failover. The reward, and the only window in
## the fight where damage is free.
@export var denial_stun_seconds: float = 1.6

@export_group("Attacks")

## The spread the live instance fires at the player.
@export var shot: ProjectileConfig

## Seconds between volleys while the boss is settled on a plate.
@export var volley_interval: float = 1.5

## Seconds between volleys while a failover is telegraphing.
##
## Faster than `volley_interval`, deliberately: the telegraph is the window the player has to run
## across the room, so it has to cost something to use. A boss that went quiet while announcing its
## one weakness would be handing the fight over.
@export var telegraph_volley_interval: float = 0.7

@export var spread_count: int = 3
@export var spread_degrees: float = 34.0

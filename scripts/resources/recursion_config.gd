class_name RecursionConfig
extends EnemyConfig
## Tuning specific to Recursion.
##
## One config describes the whole family, not just the enemy the room spawns. A fragment is
## the same scene with a different `generation`, so its numbers are expressed here as what
## changes on the way down rather than as a second resource that could quietly disagree
## with this one about what a Recursion is.

## How many fragments a split produces. Two is the number the sprite promises — a single
## smaller square visible inside the body — and any more turns one kill into a crowd.
@export var fragment_count: int = 2

## Generations that may split. 1 means the spawned enemy splits once and its fragments do
## not, which is the only setting that keeps a room's enemy count bounded by arithmetic the
## player can do while looking at it.
@export var max_generation: int = 1

## A fragment's integrity, flat rather than a fraction of the parent's, so the fragments
## stay a fixed, known cost to clean up however the parent is later tuned.
@export var fragment_health: float = 1.5

## Fragments move faster than the parent. This is the pressure the mechanic exists to
## create: killing it converts one slow problem into two quick ones, so *when* you kill it
## is a real decision rather than "as soon as possible".
@export var fragment_speed_scale: float = 1.6

## Fragment contact damage. Lower than the parent's — two bodies that each hit as hard as
## the one they came from would make splitting a punishment rather than a trade.
@export var fragment_contact_damage: float = 0.5

## Visual and physical scale of a fragment, applied to both the sprite and the collision
## shape so the thing the player shoots at is the size it looks.
@export var fragment_scale: float = 0.6

## How far from the parent's death position fragments appear. Far enough apart to be two
## targets, close enough to read as having come out of one body.
@export var fragment_spread: float = 11.0

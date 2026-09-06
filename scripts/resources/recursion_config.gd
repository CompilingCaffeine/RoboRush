class_name RecursionConfig
extends EnemyConfig
## Tuning specific to Recursion.
##
## One config describes the whole family, not just the enemy the room spawns. A fragment is
## the same scene with a different `generation`, so its numbers are expressed here as what
## changes on the way down rather than as a second resource that could quietly disagree
## with this one about what a Recursion is.
##
## The family has three rungs, and this one resource holds all three: an `ElderRecursion`,
## which the floors that have already taught Recursion put in their harder rooms; the
## Recursion the elder breaks into, which is exactly the enemy a first floor spawns; and the
## fragments that come out of that. The elder's numbers are written here as *what changes on
## the way up* for the same reason the fragment's are written as what changes on the way
## down: a second resource for the elder would be a second answer to "what is a Recursion",
## and the first thing to drift out of step would be the middle rung the two share.

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


## How far the elder's own integrity is above the Recursion it breaks into. Not a multiple of
## `max_health`: the elder is one body the player must commit to killing before it becomes two,
## and what that commitment costs should be stated rather than derived from a number tuned for a
## different job.
##
## The whole family from one elder is `elder_health` plus two Recursions plus four fragments,
## which is the arithmetic `tests/test_enemies.gd` holds against a room's budget — one elder is
## seven bodies before it is finished, and that is the point of it.
@export var elder_health: float = 9.0

## Visual and physical scale of an elder, applied to sprite and collision circle together, the
## same way `fragment_scale` is. Half again as wide as a Recursion: large enough to read as the
## thing the others came out of, small enough to still fit the gaps in a compile lane.
@export var elder_scale: float = 1.5

## What the elder's bulk costs it in speed. Below one, and deliberately so — the elder is the
## slow, unavoidable half of the decision it poses, and a big body that also kept pace with the
## player would leave the player no room to choose *when* to open it.
@export var elder_speed_scale: float = 0.75

## What touching an elder costs. Above the Recursion's, because it is a much larger circle to
## avoid and because a player who walks into one has walked into something they could see from
## across the room.
@export var elder_contact_damage: float = 1.5

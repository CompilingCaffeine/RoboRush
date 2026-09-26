class_name EnemySpawn
extends Resource
## One entry in a floor's enemy roster: what may appear, how often, and how early.
##
## Weighted and gated rather than a uniform pick from a list of scenes. A uniform pick
## produces a room of three Firewall Nodes — a wall of beams in the second room of a run —
## as readily as anything else, and a floor with no difficulty curve is ten copies of the
## same fight.
##
## Both knobs are here rather than in the generator because "which enemies belong on this
## floor" is content, not algorithm. Floor 2 is a different roster, not different code.

@export var scene: PackedScene

## Relative likelihood against the other eligible entries. 2.0 is twice as common as 1.0.
@export var weight: float = 1.0

## The lowest `RoomTemplate.difficulty` this enemy may appear in. This is the ramp: the
## easy templates near the start of a floor draw from a smaller, gentler roster, and the
## hard ones open up the rest. The other thing `RoomTemplate.difficulty` decides is how far
## from the start a template may be placed (`FloorGenerator._capped_by_distance`).
@export var min_difficulty: int = 1


func is_eligible(difficulty: int) -> bool:
	return scene != null and difficulty >= min_difficulty

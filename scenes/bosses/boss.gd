class_name Boss
extends Node2D
## What every floor's boss controller has in common: nothing but the one call
## `FloorController` needs to make once the player is sealed in the boss room.
##
## Deliberately thin. `MergeConflict` and any boss after it own their own phases, attacks,
## and health entirely — this exists only so `FloorController` can hold `_boss` as one type
## regardless of which floor's boss scene got instantiated.

## Called once, when the player enters the boss room. `arena` is the room's interior rect.
func begin(_arena: Rect2) -> void:
	push_error("%s: begin() not implemented" % get_script().get_global_name())

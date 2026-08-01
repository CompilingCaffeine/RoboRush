class_name RoomTemplate
extends Resource
## One handcrafted room layout, as data.
##
## Spec section 9: rooms are assembled from handcrafted templates, then *selected*
## procedurally. That split is deliberate and worth preserving — generating room interiors
## algorithmically produces spaces that are technically valid and never interesting, while
## generating the *graph* of which rooms appear where produces variety without giving up
## authored encounters.
##
## Every room in the game is the same size. That is what lets the floor lay rooms out on a
## simple grid where one cell is one room, which in turn makes "rooms must not overlap"
## (section 9.4) true by construction rather than something to check for.
##
## Coordinates here are in *tiles*, measured from the interior's top-left corner, so a
## template stays readable as a grid and does not have to know the pixel size of anything.

enum Type {
	START,
	COMBAT,
	ELITE_COMBAT,
	TREASURE,
	SHOP,
	CHALLENGE,
	BOSS,
	SECRET,
	TRANSITION,
}

@export var id: StringName = &"unnamed_room"

@export var type: Type = Type.COMBAT

@export_group("Layout")

## Solid blocks inside the room, in tile coordinates. Position is the top-left tile, size
## is in tiles.
@export var obstacles: Array[Rect2i] = []

## Where enemies appear, in tile coordinates. The count is the encounter: a template with
## five spawn points is a harder room than one with two, which is why there is no separate
## "enemy count" knob for the generator to get wrong.
@export var enemy_spawns: Array[Vector2i] = []

## Where a room-clear reward or treasure appears, in tile coordinates.
@export var reward_spawn := Vector2i(13, 6)

## Where shop stands go, in tile coordinates. Only read for SHOP rooms. How many there are
## is the shop's size: the first few sell items, then a repair stand, then a reroll stand.
@export var shop_stands: Array[Vector2i] = []

@export_group("Selection")

## Rough difficulty, for weighting which rooms appear on which floor.
@export var difficulty: int = 1

## Floors this template may appear on. Tags let a floor pull themed rooms without listing
## every template by name.
@export var floor_tags: Array[StringName] = []

@export var min_floor: int = 1
@export var max_floor: int = 6


## Whether this template is eligible for a given floor.
func is_eligible(floor_number: int, tags: Array[StringName]) -> bool:
	if floor_number < min_floor or floor_number > max_floor:
		return false
	if floor_tags.is_empty() or tags.is_empty():
		return true
	for tag: StringName in floor_tags:
		if tag in tags:
			return true
	return false

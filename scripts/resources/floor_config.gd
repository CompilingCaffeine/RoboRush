class_name FloorConfig
extends Resource
## One floor of the megacorporation, as data. Spec section 8's Floor 1: Help Desk.
##
## Holds what the floor is made of, not how it is assembled — FloorGenerator owns the
## graph, this owns the parts list. Adding Floor 2 should be a new .tres, not new code.

@export var display_name: String = "Help Desk"

@export var floor_number: int = 1

## Tags used to filter which room templates may appear here.
@export var floor_tags: Array[StringName] = [&"help_desk"]

@export_group("Rooms")

## Total rooms including the start and the treasure room. Spec section 9 suggests a start,
## four to six combat rooms, and a treasure room for the first prototype.
@export var room_count: int = 7

@export var start_templates: Array[RoomTemplate] = []
@export var combat_templates: Array[RoomTemplate] = []
@export var treasure_templates: Array[RoomTemplate] = []

@export_group("Population")

## Enemies that may appear on this floor. One is chosen per spawn point in the template.
@export var enemy_scenes: Array[PackedScene] = []

@export_group("Rewards")

## Scrap dropped when a combat room is cleared, as an inclusive range.
@export var clear_scrap_range := Vector2i(2, 4)

## Scrap dropped by each enemy killed.
@export var enemy_scrap_range := Vector2i(1, 2)


## Templates eligible for a room type on this floor. Returns an empty array if none match,
## which the generator reports rather than silently producing an empty room.
func templates_for(type: RoomTemplate.Type) -> Array[RoomTemplate]:
	var pool: Array[RoomTemplate] = []
	match type:
		RoomTemplate.Type.START:
			pool = start_templates
		RoomTemplate.Type.TREASURE:
			pool = treasure_templates
		_:
			pool = combat_templates

	var eligible: Array[RoomTemplate] = []
	for template: RoomTemplate in pool:
		if template != null and template.is_eligible(floor_number, floor_tags):
			eligible.append(template)
	return eligible

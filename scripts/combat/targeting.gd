class_name Targeting
extends RefCounted
## Finds the hostile bodies near a point.
##
## Homing, explosions, and chain lightning all need the same answer, and all three ask
## for it from places a physics shape query is awkward: an explosion is resolved inside
## an Area2D's `body_entered`, while the physics server is flushing. Walking a scene-tree
## group is legal from anywhere and, at a handful of enemies per room, cheaper than the
## query it replaces.
##
## Everything returned is alive. A dying enemy is freed a frame or two after its health
## reaches zero, so "is in the tree" is not the same question as "is a target", and
## chaining into a corpse would waste jumps the player paid for.

## Returns the hostile bodies within `radius` of `centre`, nearest first.
static func hostiles_near(
	source: Node,
	centre: Vector2,
	radius: float,
	team: Teams.Id,
	excluded: Array[Node] = [],
) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if source == null or not source.is_inside_tree() or radius <= 0.0:
		return found

	var group := Teams.body_group(Teams.opposing(team))
	var radius_squared := radius * radius

	for node: Node in source.get_tree().get_nodes_in_group(group):
		var body := node as Node2D
		if body == null or body in excluded:
			continue
		if body.global_position.distance_squared_to(centre) > radius_squared:
			continue
		var health := HealthComponent.find_on(body)
		if health == null or not health.is_alive():
			continue
		found.append(body)

	found.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.global_position.distance_squared_to(centre)
				< b.global_position.distance_squared_to(centre)
			)
	)
	return found


## The closest hostile body within `radius`, or null.
static func nearest_hostile(
	source: Node,
	centre: Vector2,
	radius: float,
	team: Teams.Id,
	excluded: Array[Node] = [],
) -> Node2D:
	var found := hostiles_near(source, centre, radius, team, excluded)
	return found[0] if not found.is_empty() else null

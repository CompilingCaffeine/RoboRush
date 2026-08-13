class_name Targeting
extends RefCounted
## Finds the hostile bodies near a point.
##
## Homing, explosions, and chain lightning all need the same answer, and all three ask for it from
## places a physics shape query is awkward: an explosion is resolved inside an Area2D's
## `body_entered`, while the physics server is flushing.
##
## The answer comes from `HostileRegistry` rather than from a group walk. That is the whole of this
## file's performance story, and the reason is arithmetic: a floor holds ten rooms of enemies, one
## room is awake, and a homing projectile asks this question every physics frame. Walking the group
## meant every shot in flight paid for every enemy on the floor — an ancestor walk to test
## `can_process`, a child walk to find a health component, and a sort at the end. The registry has
## already answered all of that, so what is left here is distance arithmetic over a handful of live
## bodies.
##
## **Nothing here sorts.** `hostiles_near` returns whatever order the registry holds, because no
## caller wants order: an explosion damages everything it reaches, and chain lightning asks for the
## nearest one at a time. Sorting to satisfy a caller that then ignores the order is the most
## expensive way to compute nothing, and it was being done once per homing projectile per frame. A
## caller that genuinely needs order should sort the result and say why.
##
## What is left is a shootability test and a distance test per awake body, per query. If that ever
## needs to be cheaper the next lever is caching the filtered set per physics frame, since every shot
## in flight filters the same set identically — deliberately not done yet, because it would let a
## body that died this frame stay targetable until the next one, and the current cost is comfortably
## inside its budget.

## Counters for the debug overlay, filled only while `instrumented` is set. Off by default and
## checked before the clock is read, because the whole point of this file is that it runs several
## hundred times a frame and a timing call in that path would be measuring the measurement.
static var instrumented := false
static var queries := 0
static var query_usec := 0


## Zeroes the counters. Called by whatever is displaying them, once a frame.
static func reset_instrumentation() -> void:
	queries = 0
	query_usec = 0

## The hostile bodies within `radius` of `centre`, in no particular order.
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

	var started := Time.get_ticks_usec() if instrumented else 0
	var radius_squared := radius * radius
	for entry: HostileRegistry.Entry in HostileRegistry.awake(Teams.opposing(team)):
		if not entry.is_shootable() or entry.body in excluded:
			continue
		if entry.body.global_position.distance_squared_to(centre) > radius_squared:
			continue
		found.append(entry.body)

	if instrumented:
		queries += 1
		query_usec += Time.get_ticks_usec() - started
	return found


## The closest hostile body within `radius`, or null.
##
## A single pass keeping the best so far, rather than collecting everything in range and sorting it.
## For the case that matters — one homing projectile wanting one target — the sort was the dominant
## cost and every comparison in it was thrown away.
static func nearest_hostile(
	source: Node,
	centre: Vector2,
	radius: float,
	team: Teams.Id,
	excluded: Array[Node] = [],
) -> Node2D:
	if source == null or not source.is_inside_tree() or radius <= 0.0:
		return null

	var started := Time.get_ticks_usec() if instrumented else 0
	var nearest: Node2D = null
	var nearest_distance := radius * radius
	for entry: HostileRegistry.Entry in HostileRegistry.awake(Teams.opposing(team)):
		if not entry.is_shootable() or entry.body in excluded:
			continue
		var distance := entry.body.global_position.distance_squared_to(centre)
		if distance > nearest_distance:
			continue
		nearest_distance = distance
		nearest = entry.body

	if instrumented:
		queries += 1
		query_usec += Time.get_ticks_usec() - started
	return nearest

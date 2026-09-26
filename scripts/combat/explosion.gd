class_name Explosion
extends RefCounted
## One blast: damage every hostile body within a radius, once.
##
## A static function rather than a scene because an explosion has no lifetime — the
## damage is instantaneous and the fireball belongs to FeedbackDirector, which is why
## nothing here loads a particle or plays a sound. It only announces that a blast
## happened at a place with a size.
##
## Two callers, which is the reason this is not inlined into either: a projectile with
## `explosion_radius` detonates on impact, and Volatile Kernel detonates on every enemy
## death. Both must behave identically, including "cannot hurt its own team" — which is
## free here, because the radius search only ever returns the opposing team.

## Damage tag carried on the DamageInfo, so armour and resistances can filter for blasts
## without knowing what caused this one.
const TAG := &"explosion"

## Knockback at the centre of the blast, falling off to zero at the edge.
const KNOCKBACK := 130.0

## The physics frame `_resolved_this_frame` counts for.
static var _budget_frame := -1

## Blasts resolved so far in `_budget_frame`, against `CombatCaps.max_explosions_per_frame`.
static var _resolved_this_frame := 0

## Blasts over the budget, waiting for the next physics frame, oldest first. Each is a Dictionary of
## the arguments `detonate` was given, with the nodes held weakly: a projectile that exploded on
## impact is freed at the end of its frame, and its blast still has to land on the next one.
static var _queued: Array[Dictionary] = []


## Applies the blast and returns how many bodies it hit, or 0 for a blast over this frame's budget,
## which is resolved on the next frame instead — see `CombatCaps.max_explosions_per_frame`.
## `attributed_to` is credited with the damage; `excluded` skips bodies already damaged by whatever
## caused the blast, so a direct hit is not also caught by its own explosion.
##
## `within` is the room the blast went off in, as a global rect, and nothing outside it is caught
## however close it is. Two rooms' interiors are 32px apart and a blast is routinely wider than
## that, so without it the radius is the only thing deciding whether a wall stops a detonation —
## which it is not qualified to do. Empty means "no room", which is a test arena and nothing else.
static func detonate(
	source: Node,
	centre: Vector2,
	radius: float,
	damage: float,
	team: Teams.Id,
	attributed_to: Node = null,
	excluded: Array[Node] = [],
	within := Rect2(),
) -> int:
	if radius <= 0.0:
		return 0

	if not _take_budget():
		_queue(source, centre, radius, damage, team, attributed_to, excluded, within)
		return 0

	EventBus.explosion_triggered.emit(centre, radius)
	if damage <= 0.0:
		return 0

	var hits := 0
	for body: Node2D in Targeting.hostiles_near(source, centre, radius, team, excluded, within):
		var health := HealthComponent.find_on(body)
		if health == null:
			continue
		var offset := body.global_position - centre
		var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
		var falloff := 1.0 - clampf(offset.length() / radius, 0.0, 1.0)
		var info := DamageInfo.new(
			damage, attributed_to, direction, KNOCKBACK * falloff, false, [TAG] as Array[StringName]
		)
		if health.apply_damage(info):
			hits += 1
	return hits


## Blasts waiting for a later frame. For the checks that hold the budget.
static func queued_count() -> int:
	return _queued.size()


## Spends one blast of this physics frame's budget, or reports there is none left.
static func _take_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_resolved_this_frame = 0
	if _resolved_this_frame >= maxi(CombatCaps.active().max_explosions_per_frame, 1):
		return false
	_resolved_this_frame += 1
	return true


## Holds a blast for the next physics frame.
##
## Anchored to the floor the blast went off on rather than to `source`: the source is usually the
## projectile that exploded, and it is gone by the next frame. An anchor that has left the tree, or a
## floor that has been released, drops the blast — it was meant for a room that no longer exists,
## and resolving it would put it in whatever now stands at those coordinates.
static func _queue(
	source: Node,
	centre: Vector2,
	radius: float,
	damage: float,
	team: Teams.Id,
	attributed_to: Node,
	excluded: Array[Node],
	within: Rect2,
) -> void:
	var anchor := _anchor_for(source)
	if anchor == null:
		return
	var tree := anchor.get_tree()

	var held: Array[WeakRef] = []
	for body: Node in excluded:
		if is_instance_valid(body):
			held.append(weakref(body))
	_queued.append({
		"anchor": weakref(anchor),
		"centre": centre,
		"radius": radius,
		"damage": damage,
		"team": team,
		"attributed_to": weakref(attributed_to) if attributed_to != null else null,
		"excluded": held,
		"within": within,
	})
	if not tree.physics_frame.is_connected(_resolve_queued):
		tree.physics_frame.connect(_resolve_queued, CONNECT_ONE_SHOT)


## The node a held blast is resolved against: the floor `source` stands in, or for a source outside
## every floor — `ItemEffects`, which lives beside the floor rather than in it — the projectile
## container of the floor that is still open. The current scene for a test arena with neither.
static func _anchor_for(source: Node) -> Node:
	if source == null or not source.is_inside_tree():
		return null
	var own := FloorSession.owning(source)
	if own != null:
		return own
	var tree := source.get_tree()
	for container: Node in tree.get_nodes_in_group(ProjectileFactory.CONTAINER_GROUP):
		var session := FloorSession.owning(container)
		if session == null or session.is_open():
			return container
	return tree.current_scene


## Resolves what the last frame could not, in the order it was asked for. Anything this frame's
## budget cannot hold either goes back on the queue, which reconnects itself.
static func _resolve_queued() -> void:
	var waiting := _queued
	_queued = []
	for entry: Dictionary in waiting:
		var anchor := (entry["anchor"] as WeakRef).get_ref() as Node
		if anchor == null or not anchor.is_inside_tree():
			continue
		var session := FloorSession.owning(anchor)
		if session != null and not session.is_open():
			continue

		var attributed: Node = null
		if entry["attributed_to"] != null:
			attributed = (entry["attributed_to"] as WeakRef).get_ref() as Node
		var excluded: Array[Node] = []
		for held: WeakRef in entry["excluded"]:
			var body := held.get_ref() as Node
			if body != null:
				excluded.append(body)

		detonate(
			anchor,
			entry["centre"],
			entry["radius"],
			entry["damage"],
			entry["team"],
			attributed,
			excluded,
			entry["within"],
		)

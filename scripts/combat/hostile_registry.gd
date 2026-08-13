class_name HostileRegistry
extends RefCounted
## Who is currently shootable, per team.
##
## Homing, explosions and chain lightning all ask the same question several hundred times a second,
## and until now every one of those asks walked the whole `enemy` group and inspected each member:
## an ancestor walk for `can_process()`, a child walk for `HealthComponent.find_on`, then a sort. A
## floor holds ten rooms of enemies and only one room is ever awake, so the great majority of that
## work was spent rejecting bodies in rooms the player had not reached. Measured, it is the whole of
## why 100 homing projectiles cost about 3.95 ms a frame while 100 plain ones cost 0.43.
##
## So the answer is maintained instead of recomputed. Actors say when they wake and when they sleep,
## which happens a handful of times per floor, and a query then walks only what is actually awake.
## A dormant room costs nothing at all rather than costing a little on every shot.
##
## **Static state, deliberately, and this is the one place in the project that has any.** The
## alternative is an autoload, and an autoload is a node — reachable only from inside the tree,
## while `Targeting` is static and is called from physics callbacks that have no node to hand. What
## makes it safe is that nothing here is *authoritative*: it is a cache of the tree's own shape,
## every entry is rechecked for validity when read, and `clear` exists for the harness. If it were
## ever wrong the failure would be a missed target, not a corrupted run.
##
## What counts as shootable is deliberately narrow, and it is the same question a projectile asks:
##
## - **In the tree and awake.** A body in a room the player has not entered is pulled out of the
##   physics space by Godot itself, so nothing can hit it and nothing should aim at it.
## - **On its team's collision layer.** This is what makes a boss playing dead untargetable. See
##   `BossPart.set_inert`: the part stays in the group, stays alive and keeps processing while it is
##   invisible, so the old group walk happily returned it — homing shots curved toward a body the
##   player could not see and chain lightning spent jumps on it.
## - **Alive.** A dying body is freed a frame or two after its integrity hits zero, so "still in the
##   tree" and "still a target" are different questions.

## One registered body and the health component that answers for it. Held together so a query never
## has to walk a body's children to find out whether it is still alive — that lookup, repeated per
## projectile per frame, was a measurable share of the cost this class exists to remove.
class Entry extends RefCounted:
	var body: CollisionObject2D
	var health: HealthComponent
	var team: Teams.Id

	func is_shootable() -> bool:
		return (
			is_instance_valid(body)
			and body.collision_layer != 0
			and health != null
			and health.is_alive()
		)


## Every body that has registered and not yet left the tree, by instance id. Kept apart from the
## awake set so a body that falls asleep and wakes again does not have to be handed its health
## component a second time — the notification that wakes it does not know what a health component is.
static var _known: Dictionary[int, Entry] = {}

## Handed back for a team nothing has registered under, so callers can walk the result without a null
## check and without this allocating an empty array per query.
static var EMPTY: Array = []

## The awake bodies of each team, as `Teams.Id` -> `Array[Entry]`. An array rather than a set because
## it is walked far more often than it is written, and a handful of entries walk faster than any
## dictionary is hashed.
static var _awake: Dictionary[int, Array] = {}


## Records a body as a live target of `team`. Called from `_ready`, once the actor's own health
## component exists.
static func register(body: CollisionObject2D, team: Teams.Id, health: HealthComponent) -> void:
	if body == null:
		return
	var entry := Entry.new()
	entry.body = body
	entry.health = health
	entry.team = team
	_known[body.get_instance_id()] = entry
	if body.can_process():
		_wake(entry)


## The notification hook every registered actor forwards to. Three of Godot's notifications are the
## whole lifecycle:
##
## - `PAUSED` / `UNPAUSED` are delivered when a node's *effective* processing changes, including when
##   an ancestor is disabled — which is exactly how a room puts its enemies to sleep
##   (`Room.set_active`). Verified rather than assumed: a child hears both when its parent's
##   `process_mode` moves, and `can_process()` already reads correctly inside the handler.
## - `EXIT_TREE` covers every way a body leaves, including being freed with its room at a floor
##   boundary. It is the only cleanup path, which is what keeps this from accumulating dead entries
##   across a six-floor run.
static func note(what: int, body: CollisionObject2D) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	var entry: Entry = _known.get(id)
	if entry == null:
		return

	match what:
		Node.NOTIFICATION_UNPAUSED:
			_wake(entry)
		Node.NOTIFICATION_PAUSED:
			_sleep(entry)
		Node.NOTIFICATION_EXIT_TREE:
			_sleep(entry)
			_known.erase(id)


## Every awake entry of `team`, shootable or not, as the registry's own array.
##
## Returned by reference and not copied, which is the difference between this being an optimisation
## and being a slower way to do the same thing. Targeting is called a hundred-odd times a frame, and
## building a filtered copy per call cost more than the filtering it saved — measured against the
## group walk it replaced, on 8 awake enemies with 100 asleep: 3.1x faster while copying, 4.2x
## returning the array itself. `tests/test_performance.gd` prints both halves of that on every run.
##
## Callers must therefore test `Entry.is_shootable()` themselves as they walk it, and must not hold
## on to the array. Both are true of every caller: `Targeting` walks it once inside one function and
## keeps nothing.
static func awake(team: Teams.Id) -> Array:
	return _awake.get(int(team), EMPTY)


## The awake *and shootable* entries of `team`, as a fresh array, with freed bodies pruned out of the
## registry as they are found.
##
## The pruning draws a distinction that conflating cost me a bug: a **freed** body is dropped for
## good, while one that is merely not shootable *right now* — a boss part off its collision layer
## between phases, a body in the frame between losing its last integrity and being freed — is skipped
## and left where it is. Dropping the second kind meant a boss that played dead could never be
## targeted again once it got up.
##
## Only the suite and the debug overlay call this; the hot path uses `awake` above.
static func shootable(team: Teams.Id) -> Array:
	var entries: Array = _awake.get(int(team), EMPTY)
	var live: Array = []
	var kept: Array = []
	var freed := false

	for entry: Entry in entries:
		if not is_instance_valid(entry.body):
			freed = true
			continue
		kept.append(entry)
		if entry.is_shootable():
			live.append(entry)

	if freed:
		_awake[int(team)] = kept
	return live


## How many bodies of `team` are currently shootable. For the debug overlay and for the suite that
## proves dormant rooms cost nothing.
static func count(team: Teams.Id) -> int:
	return shootable(team).size()


## How many bodies have registered and not yet left the tree, awake or not. Only the suite reads
## this, to tell "the registry forgot a body" apart from "the body is asleep".
static func known_count() -> int:
	return _known.size()


## Forgets everything. For the harness between suites; the game never needs it, because a body that
## leaves the tree takes its entry with it.
static func clear() -> void:
	_known.clear()
	_awake.clear()


static func _wake(entry: Entry) -> void:
	var team := int(entry.team)
	if not _awake.has(team):
		_awake[team] = []
	if entry not in _awake[team]:
		_awake[team].append(entry)


static func _sleep(entry: Entry) -> void:
	var team := int(entry.team)
	if _awake.has(team):
		_awake[team].erase(entry)

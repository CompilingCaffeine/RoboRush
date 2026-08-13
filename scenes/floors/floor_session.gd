class_name FloorSession
extends Node2D
## Everything one floor owns, and nothing that outlives it.
##
## The floor used to have no such boundary. `FloorController` freed its rooms and its doors and
## called that a teardown, while the loot spawner and the projectile container sat beside them in
## `floor.tscn` and were never touched — so every pickup lying on the ground, every projectile in
## flight, and every compile lane mid-telegraph followed the player down the stairs. A
## five-transition probe measured it exactly: one pickup and one projectile carried over per
## boundary, with the room count staying honest the whole time, which is what made it invisible.
##
## Freeing more things in `_teardown` would have fixed that list and not the problem. The problem
## is that the list exists — that "what dies with a floor" was a set of nodes somebody had to
## remember, and every hazard added later starts out forgotten. Here it is a *place*: anything
## parented into this node dies with the floor because it is standing inside it, and anything that
## must survive is parented somewhere else. The player, the HUDs, the feedback director, and the
## run state are all outside, which is why they cross the boundary without anything carrying them.
##
## The second half is deferred work. Loot drops and split projectiles are added on the next idle
## frame, because Godot refuses to register a new collision shape while the physics server is
## flushing — so a floor can be torn down between a spawn being *asked for* and it *happening*.
## Deleting the current children cannot stop that; the spawn is not a child yet. `add_deferred`
## is what stops it: the session holds the pending node itself, and `close` frees anything still
## queued rather than letting it land in a floor it was never meant for.

## Which floor this is, counted from the first one built. Deferred work is checked against the
## session it belongs to rather than against this number — a freed session cannot answer — but it
## makes "the same session was reused" and "a new one was opened" distinguishable in a test and in
## a debug overlay, which a boolean could not.
var generation := 0

@onready var rooms: Node2D = %Rooms
@onready var doors: Node2D = %Doors
@onready var loot: LootSpawner = %LootSpawner
@onready var projectiles: Node2D = %Projectiles

## Nodes asked for but not yet added. Held so `close` can free them: a node that never reached the
## tree is not freed by anything else, and the deferred call that would have added it is dropped
## silently once this session is gone.
var _pending: Array[Node] = []

## False from the moment a transition commits. Everything below refuses work rather than doing it
## late, because "late" here means "on the next floor".
var _open := true


## The session `node` is standing in, or null for a node outside any floor — a test arena, or a
## probe. Callers treat null as "no generation to check against" and fall back to spawning
## directly, which is what keeps a bare `LootSpawner.new()` in a test scene working.
static func owning(node: Node) -> FloorSession:
	var current := node
	while current != null:
		var session := current as FloorSession
		if session != null:
			return session
		current = current.get_parent()
	return null


func is_open() -> bool:
	return _open


## Adds `child` under `parent` on the next idle frame, or frees it if this floor is gone by then.
##
## The session takes ownership of `child` immediately, before it is anywhere near the tree. That
## is the whole point: `parent.add_child.call_deferred(child)` hands the node to a call that Godot
## will silently drop if the parent has been freed, and the node it was going to add is then owned
## by nobody and freed by nothing.
func add_deferred(parent: Node, child: Node) -> void:
	if not _open:
		child.queue_free()
		return
	_pending.append(child)
	_attach.call_deferred(parent, child)


func _attach(parent: Node, child: Node) -> void:
	_pending.erase(child)
	if not is_instance_valid(child):
		return
	if not _open or not is_instance_valid(parent) or not parent.is_inside_tree():
		child.queue_free()
		return
	parent.add_child(child)


## Stops this session accepting work and releases what it was still holding. Called the moment a
## transition commits, *before* the node is freed — a queued spawn has to be refused while there
## is still something to refuse it.
##
## Idempotent, because the alternative is every caller having to know whether it is the first.
func close() -> void:
	if not _open:
		return
	_open = false

	# Before the pending sweep: the spawner is what turns an enemy death into more pending work,
	# and both sessions are briefly connected to the same EventBus signal while the old one waits
	# to be freed.
	if loot != null:
		loot.close()

	for child: Node in _pending:
		if is_instance_valid(child):
			child.queue_free()
	_pending.clear()


## How many spawns are queued and not yet landed. For tests and diagnostics: the interesting
## number is that it is zero after a boundary, which is the state the old code could not reach
## because it had nowhere to count.
func pending_count() -> int:
	return _pending.size()

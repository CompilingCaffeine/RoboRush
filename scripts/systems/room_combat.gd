class_name RoomCombat
extends Node
## Watches a room's enemies and reports when the room is clear.
##
## Tracks HealthComponent.died rather than enemies leaving the tree, which matters for
## correctness: nodes also leave the tree when the scene is torn down on restart, and
## that would fire a spurious room-cleared the moment the player pressed R.
##
## The room calls begin() from its own _ready rather than this node finding the
## enemies itself. Godot readies children before parents, so by the time the room is
## ready every enemy and every HealthComponent underneath it is fully initialised —
## no frame of waiting and no inspector-assigned node path to resolve.
##
## Milestone 3 extends this with locked doors, spawn points, and wave scheduling.
## Today it counts.

signal cleared()

var _alive := 0
var _initial_count := 0
var _is_cleared := false
var _has_begun := false


## Starts tracking every enemy currently under `enemies_container`.
func begin(enemies_container: Node) -> void:
	if _has_begun:
		return
	_has_begun = true
	if enemies_container == null:
		push_warning("RoomCombat.begin() received no container; nothing tracked.")
		return
	for enemy: Node in enemies_container.get_children():
		track(enemy)


## Registers an enemy that appeared after the room started. Milestone 3's spawner
## calls this.
func track(enemy: Node) -> void:
	var health := HealthComponent.find_on(enemy)
	if health == null:
		push_warning("RoomCombat: '%s' has no HealthComponent and cannot be tracked." % enemy.name)
		return
	_alive += 1
	_initial_count += 1
	health.died.connect(_on_enemy_died)


func is_cleared() -> bool:
	return _is_cleared


func get_alive_count() -> int:
	return _alive


func get_initial_count() -> int:
	return _initial_count


func _on_enemy_died() -> void:
	_alive -= 1
	# A room that never had enemies is not "cleared" — it was never in combat.
	if _alive > 0 or _is_cleared or _initial_count == 0:
		return
	_is_cleared = true
	cleared.emit()
	EventBus.room_cleared.emit()

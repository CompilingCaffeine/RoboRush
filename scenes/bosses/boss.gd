class_name Boss
extends Node2D
## Shared boss lifecycle: health accessors, cached player lookup, and terminal management.
## Individual fights retain their own phases, attacks, arena behavior, and config resources.

const TERMINAL_SCENE := preload("res://scenes/bosses/boss_terminal.tscn")

var _health := 0.0

var _is_dead := false

## Cached player, refreshed after a restart or free.
var _player: Node2D


## Called once, when the player enters the boss room. `arena` is the room's interior rect.
func begin(_arena: Rect2) -> void:
	push_error("%s: begin() not implemented" % get_script().get_global_name())


## Overridden by each fight to return its config's maximum health.
func get_max_health() -> float:
	push_error("%s: get_max_health() not implemented" % get_script().get_global_name())
	return 0.0


func get_health() -> float:
	return _health


## Actual health ratio, protected from invalid zero-health configs.
func get_health_ratio() -> float:
	return _health / maxf(get_max_health(), 0.001)


## Virtual so fights may announce a display value different from their actual health.
func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D


## Builds terminals at the four corners of `bounds` and wires their destruction back to the fight.
func make_corner_terminals(
	bounds: Rect2, count: int, health: float, on_destroyed: Callable
) -> Array[BossTerminal]:
	var terminals: Array[BossTerminal] = []
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y),
		bounds.end,
	]
	for index: int in mini(maxi(count, 0), corners.size()):
		var terminal: BossTerminal = TERMINAL_SCENE.instantiate()
		add_child(terminal)
		terminal.global_position = corners[index]
		terminal.configure(health)
		terminal.destroyed.connect(on_destroyed)
		terminals.append(terminal)
	return terminals


func clear_terminals(terminals: Array[BossTerminal]) -> void:
	for terminal: BossTerminal in terminals:
		if is_instance_valid(terminal):
			terminal.queue_free()
	terminals.clear()

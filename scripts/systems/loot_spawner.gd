class_name LootSpawner
extends Node2D
## Drops pickups when enemies die and when rooms are cleared.
##
## Pickups are parented here rather than to the room they dropped in, because a pickup is a
## world object at a world position — nothing about it needs to know which room it is standing
## in, and parenting per room would mean rooms had to stay alive purely to hold loot.
##
## Spec section 17: scrap drops from enemies and from room rewards. Both paths land here so
## the floor's drop rates are one file to tune.

const PICKUP_SCENE := preload("res://scenes/pickups/pickup.tscn")
const SCRAP_CONFIG := preload("res://data/pickups/scrap.tres")
const REPAIR_CELL_CONFIG := preload("res://data/pickups/repair_cell.tres")

## How far scrap scatters from where it dropped, so a pile of it is countable.
const SCATTER := 9.0

var _config: FloorConfig
var _rng := RandomNumberGenerator.new()


func setup(config: FloorConfig, seed_value: int) -> void:
	_config = config
	_rng.seed = seed_value
	EventBus.enemy_killed.connect(_on_enemy_killed)


## Called by the floor when a combat room is cleared. The reward is the payoff for the fight,
## so it is deliberately larger than the trickle from individual kills.
func spawn_room_reward(position: Vector2, include_repair_cell: bool) -> void:
	var amount := _rng.randi_range(_config.clear_scrap_range.x, _config.clear_scrap_range.y)
	_spawn_scrap(position, amount)
	if include_repair_cell:
		_spawn(REPAIR_CELL_CONFIG, position + Vector2(0.0, -14.0))


## Drops the contents of a treasure room. Items arrive in milestone 4; until then a treasure
## room pays out in integrity and scrap so the detour is still worth taking.
func spawn_treasure(position: Vector2) -> void:
	_spawn(REPAIR_CELL_CONFIG, position)
	_spawn_scrap(position + Vector2(0.0, 14.0), _config.clear_scrap_range.y + 2)


func _on_enemy_killed(enemy: Node, position: Vector2) -> void:
	var amount := _rng.randi_range(_config.enemy_scrap_range.x, _config.enemy_scrap_range.y)
	# The enemy could carry its own drop rate later; for now the floor sets it, and the node is
	# read only for the position it was killed at.
	if not is_instance_valid(enemy):
		return
	_spawn_scrap(position, amount)


func _spawn_scrap(position: Vector2, count: int) -> void:
	for _index: int in maxi(count, 0):
		_spawn(SCRAP_CONFIG, position)


## Added deferred, because loot drops from inside a damage callback: an enemy dies while the
## physics server is flushing queries, and registering a new Area2D's shape at that moment is
## refused outright, which would mean kills silently dropped nothing.
func _spawn(config: PickupConfig, position: Vector2) -> void:
	var pickup: Pickup = PICKUP_SCENE.instantiate()
	pickup.config = config
	pickup.position = position + Vector2(
		_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER)
	)
	add_child.call_deferred(pickup)

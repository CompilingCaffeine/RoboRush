class_name LootSpawner
extends Node2D
## Drops pickups when enemies die and when rooms are cleared.
##
## Pickups are parented here rather than to the room they dropped in, because a pickup is a
## world object at a world position — nothing about it needs to know which room it is standing
## in, and parenting per room would mean rooms had to stay alive purely to hold loot.
##
## Spec section 17: scrap drops from enemies and from room rewards. Both paths land here so
## the floor's drop rates are one file to tune. Items go through the same path — an item is a
## `Pickup` with a `PickupConfig` built at drop time, not a scene of its own.

const PICKUP_SCENE := preload("res://scenes/pickups/pickup.tscn")
const SCRAP_CONFIG := preload("res://data/pickups/scrap.tres")
const REPAIR_CELL_CONFIG := preload("res://data/pickups/repair_cell.tres")

## How far scrap scatters from where it dropped, so a pile of it is countable.
const SCATTER := 9.0

## How many scattered offsets to try before giving up and dropping the pickup exactly where
## it died instead of taking a chance on the last one. Mirrors PopUpDrone._pick_destination:
## retry against real geometry, then fall back to a position already known to be clear.
const SCATTER_ATTEMPTS := 6

var _config: FloorConfig
var _rng := RandomNumberGenerator.new()


func setup(config: FloorConfig, seed_value: int) -> void:
	_config = config
	_rng.seed = seed_value
	# Guarded because a floor advance calls setup() again on this same node: an unguarded
	# connect would stack a second EventBus.enemy_killed listener and quietly double every
	# scrap drop from the second floor onward.
	if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)


## Called by the floor when a combat room is cleared. The reward is the payoff for the fight,
## so it is deliberately larger than the trickle from individual kills.
func spawn_room_reward(position: Vector2, include_repair_cell: bool) -> void:
	var amount := _rng.randi_range(_config.clear_scrap_range.x, _config.clear_scrap_range.y)
	_spawn_scrap(position, amount)
	if include_repair_cell:
		_spawn(REPAIR_CELL_CONFIG, position + Vector2(0.0, -14.0))


## Drops the contents of a treasure room: the floor's item, plus scrap. The repair cell that
## stood in for the item in milestone 3 is gone — a treasure room whose payout is an item and
## a handful of scrap is worth the detour on its own.
func spawn_treasure(position: Vector2) -> ItemConfig:
	var item := spawn_item(position)
	if item == null:
		# Pool exhausted. Better a repair cell than an empty vault the player walked to.
		_spawn(REPAIR_CELL_CONFIG, position)
	_spawn_scrap(position + Vector2(0.0, 14.0), _config.clear_scrap_range.y + 2)
	return item


## Draws one item from the floor's pool and drops it. Returns null when the pool has nothing
## left to offer this run.
func spawn_item(position: Vector2) -> ItemConfig:
	var item := RunManager.draw_item(_config.get_items(), _rng)
	if item == null:
		return null
	_spawn(PickupConfig.for_item(item), position, false)
	return item


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
##
## `scatter` is off for items. Scrap scatters so a pile of it is countable; an item is a
## single object the player walks to deliberately, and nudging it off the reward point only
## makes it harder to find.
func _spawn(config: PickupConfig, position: Vector2, scatter := true) -> void:
	var pickup: Pickup = PICKUP_SCENE.instantiate()
	pickup.config = config
	pickup.position = _resolve_position(position, scatter)
	add_child.call_deferred(pickup)


## Scatter lands most drops in the open, but an unchecked offset can just as easily land one
## inside the wall or obstacle the origin point was sitting next to — an enemy dying pinned in
## a corner is common, and the scatter radius is well within reach of both of that corner's
## faces. A pickup is an Area2D, so nothing physically stops it from spawning embedded in solid
## geometry the way a living body would; once it has, the player's own body can never approach
## close enough to collect it, and the Scrap Magnet's pull never engages either — it is gated by
## the player's distance, not blocked by walls, so it silently never starts.
##
## Retried against real physics geometry rather than the room template, so obstacles the
## template does not know about are covered too (see PopUpDrone._is_blocked, the same check).
## Falling back to the unscattered `position` after exhausting the attempts is safe because
## that point is always somewhere already clear of geometry — an enemy's collision-safe death
## position, or an authored room reward point.
func _resolve_position(position: Vector2, scatter: bool) -> Vector2:
	if not scatter:
		return position
	for _attempt: int in SCATTER_ATTEMPTS:
		var candidate := position + Vector2(
			_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER)
		)
		if not _is_blocked(candidate):
			return candidate
	return position


func _is_blocked(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = Teams.LAYER_WORLD
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()

class_name LootSpawner
extends Node2D
## Drops pickups when enemies die and when rooms are cleared.
##
## Pickups are parented here rather than to the room they dropped in, because a pickup is a
## world object at a world position — nothing about it needs to know which room it is standing
## in, and parenting per room would mean rooms had to stay alive purely to hold loot.
##
## This node lives inside the floor's `FloorSession`, which is what makes "a pickup belongs to the
## floor it dropped on" true by parentage rather than by anybody remembering to sweep. It used to
## sit beside the session's contents instead of inside them, and the result was that every
## uncollected scrap and repair cell on a floor arrived on the next one.
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
## retry against real geometry, then fall back to the unscattered point — which is itself
## verified and relocated if blocked, see _resolve_position.
const SCATTER_ATTEMPTS := 6

## Ring search used when the drop point itself sits inside geometry: step outward this far per
## ring, testing this many evenly spaced directions per ring, nearest ring first. 8px steps out
## to 64px clears every authored obstacle a drop point can realistically end up inside — the
## widest template blocks are a few tiles (TILE_SIZE is 16), and a blocked point is at worst
## half a block's width from open floor.
const CLEAR_SEARCH_STEP := 8.0
const CLEAR_SEARCH_RINGS := 8
const CLEAR_SEARCH_DIRECTIONS := 8

var _config: FloorConfig
var _rng := RandomNumberGenerator.new()


## `seed_value` is the floor's *loot stream* — `RunRng.stream_seed(floor_seed, RunRng.LOOT)`, passed
## in by `FloorController` rather than derived here so that a bare spawner in a test arena can be
## given any seed at all. What matters is that it is nobody else's stream: scrap amounts, scatter
## offsets and item draws move only when loot itself changes, not when a boss pool grows.
func setup(config: FloorConfig, seed_value: int) -> void:
	_config = config
	_rng.seed = seed_value
	# Guarded because nothing stops setup() being called twice on one spawner. It used to be the
	# ordinary case — one spawner lived in `floor.tscn` and was re-set-up on every descent, and an
	# unguarded connect quietly doubled every scrap drop from the second floor onward. A spawner
	# now belongs to one `FloorSession` and dies with it, so the guard is defence rather than the
	# mechanism, and `close` is what takes the connection down before the next floor's is made.
	if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)


## Stops this spawner reacting to anything. Called by `FloorSession.close` at the moment a
## transition commits.
##
## Disconnected then rather than left to the node being freed, because `queue_free` is not
## immediate: the old spawner and the new one are both connected to `EventBus.enemy_killed` for
## the rest of the frame in which a floor is released, and an enemy dying in that window would
## drop its scrap twice — once into a floor that is being thrown away.
func close() -> void:
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


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
## Deferred through the session rather than through `add_child.call_deferred`, because the gap
## this opens is exactly a floor boundary wide. An enemy killed by a projectile still in flight
## when the player takes the boss reward asks for a pickup on the floor being left and gets it on
## the floor being entered — which is one of the two objects the five-transition probe caught
## crossing every boundary. `FloorSession.add_deferred` refuses the late arrival and frees it;
## `add_child.call_deferred` could not, because at that moment the pickup is not a child of
## anything and the deferred call is silently dropped along with the node it would have added.
##
## The fallback keeps a bare `LootSpawner.new()` in a test arena working: no session means no
## generation to be stale against, and the ordinary deferral is correct.
##
## `scatter` is off for items. Scrap scatters so a pile of it is countable; an item is a
## single object the player walks to deliberately, and nudging it off the reward point only
## makes it harder to find.
func _spawn(config: PickupConfig, position: Vector2, scatter := true) -> void:
	var pickup: Pickup = PICKUP_SCENE.instantiate()
	pickup.config = config
	pickup.position = _resolve_position(position, scatter)

	var session := FloorSession.owning(self)
	if session != null:
		session.add_deferred(self, pickup)
	else:
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
##
## The requested `position` itself is not trusted either: an enemy can die knocked into a wall
## corner with its origin inside the block, and the fixed offsets callers add to reward points
## (the repair cell's -14y nudge, the floor's item offset) can poke into an authored obstacle.
## Any point that fails the geometry check — the no-scatter point included — is relocated to
## the nearest clear spot instead of being dropped where the player can never reach it.
func _resolve_position(position: Vector2, scatter: bool) -> Vector2:
	if scatter:
		for _attempt: int in SCATTER_ATTEMPTS:
			var candidate := position + Vector2(
				_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER)
			)
			if not _is_blocked(candidate):
				return candidate
	if not _is_blocked(position):
		return position
	return _nearest_clear_position(position)


## Walks outward in rings from a blocked origin and returns the first clear point, so the
## result is the nearest open floor in search order. Deterministic — no RNG draw — so taking
## this path does not shift the seeded scatter sequence of later drops. Returns the origin
## unchanged when every ring is blocked too: at that point there is no sensible nearby answer,
## and teleporting the pickup somewhere distant would be worse than the bug being fixed.
func _nearest_clear_position(origin: Vector2) -> Vector2:
	for ring: int in range(1, CLEAR_SEARCH_RINGS + 1):
		var radius := ring * CLEAR_SEARCH_STEP
		for index: int in CLEAR_SEARCH_DIRECTIONS:
			var direction := Vector2.from_angle(TAU * index / CLEAR_SEARCH_DIRECTIONS)
			var candidate := origin + direction * radius
			if not _is_blocked(candidate):
				return candidate
	return origin


func _is_blocked(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = Teams.LAYER_WORLD
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()

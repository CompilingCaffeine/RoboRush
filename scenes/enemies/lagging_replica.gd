class_name LaggingReplica
extends StaleReplica
## The Stale Replica one rung up: it lags the player's **fire** as well as their route. Every shot
## they take is repeated `delay_seconds` later, from the spot they fired it, in the direction they
## fired it — and by then they are somewhere else, which is exactly the point.
##
## The Stale Replica charges for standing still. This charges for the other half of the same habit,
## and it is the half a good player keeps: the robot can fire while walking, so the answer to a
## chaser you cannot dodge is to walk backwards and shoot it, which is the one thing this floor's
## replica cannot punish. Now the ground you fired from is a place your own shot comes out of. Keep
## going and every echo lands behind you. Stop to line one up, or turn back to finish it, and you
## are standing where you last pulled the trigger.
##
## **What is replayed is a rhythm, not a weapon.** The echo is this enemy's own projectile — see
## `StaleReplicaConfig.echo_shot` — because the player's is worth up to nine times what the enemies
## are written for, and a replica that returned that would be a build killing itself. It repeats
## *where and when*, which is the only part of a shot this enemy has any business knowing.
##
## It also means the enemy can be starved. A player who holds fire is a player with nothing coming
## back, which is a real decision to hand somebody on the last two floors of the campaign: your own
## aggression is the ammunition, and you can choose not to load it.
##
## Everything else is inherited whole — the route, the trail it draws, the arrive radius, and the
## fact that it needs no navigation because the path it walks is a path the player has already
## walked.
##
## Killing it silences what it has not fired yet, which is the campaign's rule rather than an
## exception to it: an echo in the queue is a shot nothing on screen has announced, and **committed
## attacks resolve, uncommitted ones never happen**. A shot already in the air is not touched.

## Echoes waiting to be fired, oldest first. Three parallel arrays rather than an array of objects:
## every entry has the same delay, so the queue is sorted by construction and the only entry ever
## inspected is the front one.
var _origins: PackedVector2Array = []
var _directions: PackedVector2Array = []
var _delays: PackedFloat32Array = []

## Time since the last shot that was actually recorded. Starts high so the first shot of a fight is
## always echoed rather than swallowed by a cooldown nothing has used yet.
var _since_recorded := 999.0


func _on_ready() -> void:
	super()
	EventBus.shot_fired.connect(_on_shot_fired_anywhere)


func _act(delta: float) -> Vector2:
	_since_recorded += delta
	_step_echoes(delta)
	return super(delta)


## How many echoes are waiting. Bounded by `delay_seconds / echo_min_interval` by construction, and
## public because that bound is the promise this enemy makes about how much it can ever return.
func get_queued_echo_count() -> int:
	return _delays.size()


## Records a shot the player took. Enemy fire is ignored, including this replica's own echoes —
## which is what stops a room with two of these in it from echoing each other into a crossfire that
## has nothing to do with the player.
func _on_shot_fired_anywhere(team: int, muzzle: Vector2, direction: Vector2) -> void:
	if team != Teams.Id.PLAYER or is_dead():
		return
	# A signal reaches every replica on the floor, including the ones in rooms the player has not
	# opened yet — `Room.set_active` stops those thinking, and it does not stop them listening. A
	# replica that recorded through a closed door would greet the player with an echo of a shot they
	# fired two rooms ago, out of a piece of floor they have never stood on.
	if not can_process():
		return
	if _since_recorded < maxf(_tuning.echo_min_interval, 0.0):
		return
	_since_recorded = 0.0
	_origins.append(muzzle)
	_directions.append(direction)
	_delays.append(maxf(_tuning.delay_seconds, 0.0))


## Fires everything whose lag has run out. A `while` rather than an `if`: a frame long enough to
## mature two echoes should fire two, not hold one over to the next frame where it would arrive
## later than the enemy promised.
func _step_echoes(delta: float) -> void:
	for index: int in _delays.size():
		_delays[index] -= delta
	while not _delays.is_empty() and _delays[0] <= 0.0:
		_fire_echo(_origins[0], _directions[0])
		_origins.remove_at(0)
		_directions.remove_at(0)
		_delays.remove_at(0)


## One echo, from where the shot was taken. Announced on the EventBus the way every other enemy
## announces its fire, so the muzzle flash that marks it is the same one the rest of the game
## draws — an echo appearing out of empty floor with no flash reads as a bug rather than as a shot.
func _fire_echo(origin: Vector2, direction: Vector2) -> void:
	var shot := _tuning.echo_shot
	if shot == null or direction.is_zero_approx():
		return
	ProjectileFactory.spawn_configured(
		self, shot.spawn_copy(), direction.normalized(), origin, Teams.Id.ENEMY, self, [], true
	)
	EventBus.shot_fired.emit(Teams.Id.ENEMY, origin, direction.normalized())

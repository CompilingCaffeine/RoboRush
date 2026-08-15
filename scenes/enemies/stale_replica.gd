class_name StaleReplica
extends Enemy
## The Data Center's replication lag, walking: it chases where the player *was*, not where they
## are, and it gets there by retracing the exact route they took.
##
## Every other chaser in the game steers at the player — the Memory Leech commits to a direction
## and goes, Recursion simply closes. This one is the only enemy whose target is in the past, and
## that single change turns the fight it poses upside down. It cannot be dodged, because it is not
## coming at you; it can only be outrun, and only forwards. Keep going and it never arrives. Stop,
## and the position it is walking to catches up with the one you are standing in. Turn back, and
## you walk into it.
##
## That is the Data Center's own lesson in a body, which is why it belongs to this floor: the
## throughput zones under it charge for standing still and firing, and this charges for standing
## still at all. What the pair asks for is one habit and not two — keep moving, and keep moving
## *onward*.
##
## **It needs no navigation of any kind**, and that is not an optimisation, it is why the design
## works. The path it walks is a path the player has already walked, so it is clear of walls, clear
## of racks and inside the room by construction. A chaser that steered at the player has to be
## given something to do about the pillar in between; this one never meets a pillar the player did
## not already go around. Floor 3's rooms are the most cluttered in the game and it needed nothing
## for them.
##
## It is also the only enemy in the game that is fought over the shoulder. It is behind you by
## definition, so shooting it means running one way and firing the other — which the robot can do,
## and which nothing before this floor has ever asked it to.

## Seconds between samples of the player's position. Thirty a second rather than one per physics
## frame: the path is a route to walk, not a recording, and a sample every 5 pixels of travel
## describes the same route as a sample every 2.5 for half the buffer.
##
## Fixed rather than derived from the frame delta, so the length of the trail is the same number of
## seconds on a machine running at 30 as on one running at 144. A slow frame costs one sample and
## coarsens the path; nothing about the enemy changes.
const SAMPLE_SECONDS := 1.0 / 30.0

var _tuning: StaleReplicaConfig

## Where the player has been, oldest first, trimmed to `delay_seconds` of history. Element zero is
## what this enemy is walking to, and the whole array is the route it will take to get there — so
## the thing it chases and the thing it draws are one piece of state and cannot disagree.
var _trail: PackedVector2Array = []

var _sample_left := 0.0

@onready var _trail_line: Line2D = %Trail


func _on_ready() -> void:
	_tuning = config as StaleReplicaConfig
	assert(_tuning != null, "StaleReplica.config must be a StaleReplicaConfig.")
	_trail_line.default_color = _tuning.trail_color
	_trail_line.width = _tuning.trail_width


func _act(delta: float) -> Vector2:
	_step_trail(delta)
	_draw_trail()

	if not has_target():
		return Vector2.ZERO
	var offset := get_target() - global_position
	if offset.length() <= _tuning.arrive_radius:
		return Vector2.ZERO
	return offset.normalized() * config.move_speed


## Whether it has seen the player at all yet. False for exactly one sample after it wakes.
func has_target() -> bool:
	return not _trail.is_empty()


## Where it is walking to: the player's position `delay_seconds` ago.
##
## Its own position when it has never seen the player, which reads as "stand still" everywhere it
## is used. Deliberately *not* the player's current position: those are opposite answers, and one
## of them is this enemy. A fallback to "chase them directly" would turn a replica that lost sight
## of the player for a frame into an ordinary chaser, which is the one thing it must never be.
func get_target() -> Vector2:
	return _trail[0] if has_target() else global_position


## How many samples of history it holds at most. Public because it is what `delay_seconds` actually
## means once the sampling rate is applied, and a test asserting the lag should measure the number
## the enemy uses rather than recompute it.
func get_sample_capacity() -> int:
	return maxi(int(_tuning.delay_seconds / SAMPLE_SECONDS), 1)


## Records the player's position on the sample clock and drops anything older than the delay.
##
## Nothing is recorded while there is no player to record — a replica in a room the robot has died
## in holds the last route it saw rather than filling its buffer with the position of nothing. It
## walks that route out and then stands where the player last was, which is the correct picture of
## what a stale replica is.
func _step_trail(delta: float) -> void:
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	_sample_left = SAMPLE_SECONDS

	if _player == null:
		return
	_trail.append(_player.global_position)
	# One at a time, because one is how many were added. A `while` here would be a loop that can
	# only ever run once, written as though it might not.
	if _trail.size() > get_sample_capacity():
		_trail.remove_at(0)


## Draws the route it is about to take. Local coordinates, because a `Line2D` child draws in the
## enemy's own frame and the trail is recorded in the world's.
func _draw_trail() -> void:
	var points := PackedVector2Array()
	points.resize(_trail.size())
	for index: int in _trail.size():
		points[index] = to_local(_trail[index])
	_trail_line.points = points

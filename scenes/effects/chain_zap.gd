class_name ChainZap
extends Line2D
## The visible arc of one chain lightning jump.
##
## Drawn as a jagged polyline rather than a straight one because a straight line between
## two enemies reads as a laser, and the deflections are what make three jumps in three
## frames legible as three separate events.
##
## Frees itself on a timer like every other one-shot effect in the game. No tween: at 0.11
## seconds the fade is four frames, and a Tween node to run four frames of alpha is more
## machinery than the effect is.

## How long the arc stays on screen. Short enough not to overlap the next jump, long
## enough to be seen at 60fps.
const SECONDS := 0.11

## How far each intermediate point is pushed off the straight line, in pixels.
const JAGGEDNESS := 4.0

## Points between the two ends. Three gives a recognisable zigzag; more turns into noise
## at this scale.
const SEGMENTS := 4

var _left := SECONDS


## Lays the arc between two world points. Called after the node is in the tree, because
## `top_level` positioning needs a parent.
func strike(from: Vector2, to: Vector2) -> void:
	top_level = true
	global_position = Vector2.ZERO
	rotation = 0.0

	var perpendicular := (to - from).normalized().orthogonal()
	clear_points()
	add_point(from)
	for index: int in range(1, SEGMENTS):
		var along := from.lerp(to, float(index) / float(SEGMENTS))
		add_point(along + perpendicular * randf_range(-JAGGEDNESS, JAGGEDNESS))
	add_point(to)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	modulate.a = _left / SECONDS

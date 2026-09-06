class_name HotPathRunner
extends CodeRunner
## A Code Runner that leaves its path on the floor: every `trail_interval` it drops a patch of
## compile lane where it is standing, which telegraphs and strikes behind it.
##
## The Code Runner's sentence is "track me while I move". It is the only enemy that fires with a
## nonzero velocity, and the answer a player learns is to follow it with the reticle and walk with
## it — matching its strafe, because a target you are moving alongside is a target that stops
## moving relative to you. This is the floor charging for that habit. The ground the runner has just
## left is the ground the player is walking onto, so tracking it now costs the one thing tracking it
## used to be free of: where you are standing.
##
## The trail is patches rather than a continuous line, and the interval is what makes that true: it
## drops one about every time it crosses its own width, so what is denied is a row of stepping
## stones with gaps between them. A solid wall behind a moving enemy would be a fence that grows
## across the room, and a room with two of these in it would eventually have no floor in it at all.
##
## Everything about it is `CompileLane` — the same amber-then-red the player has read since the
## second floor, the same telegraph, the same one-shot strike. It teaches nothing new; it takes
## something away.

## Counts down to the next patch. Started full so the runner has to actually travel before it
## leaves anything, rather than dropping one under itself on the frame it wakes up.
var _trail_left := 0.0


func _on_ready() -> void:
	super()
	_trail_left = _tuning.trail_interval


func _act(delta: float) -> Vector2:
	_step_trail(delta)
	return super(delta)


func _step_trail(delta: float) -> void:
	_trail_left -= delta
	if _trail_left > 0.0:
		return
	_trail_left = maxf(_tuning.trail_interval, 0.05)
	_drop_patch()


## One patch, on the tile the runner is standing on, sized and clamped by the room the way every
## other authored hazard on this floor is — a patch half outside the room would be a hazard drawn
## in a wall.
func _drop_patch() -> void:
	var room := find_room()
	if room == null:
		return
	var span := maxi(_tuning.trail_tiles, 1)
	var centre := room.get_tile_at(global_position)
	var rect := room.get_tile_block_rect(centre - Vector2i.ONE * (span / 2), Vector2i.ONE * span)
	CompileLane.spawn(
		self,
		rect,
		_tuning.trail_damage,
		_tuning.trail_telegraph_seconds,
		_tuning.trail_strike_seconds,
	)

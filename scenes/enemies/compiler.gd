class_name Compiler
extends Enemy
## README's Floor 2 plan: "Paints one row or column, telegraphs it, then sends a fast pulse
## through the lane."
##
## Stationary, like Firewall Node — the lane is the attack, not a projectile weapon, so
## there is no `%Weapon` node. Where Firewall Node asks "where are you allowed to stand"
## continuously, this asks it in bursts: a lane is drawn, waits long enough to read,
## executes once, and the room is safe again until the next one.

var _tuning: CompilerConfig
var _cooldown := 0.0


func _on_ready() -> void:
	_tuning = config as CompilerConfig
	assert(_tuning != null, "Compiler.config must be a CompilerConfig.")
	_cooldown = _tuning.lane_interval


func _act(delta: float) -> Vector2:
	_cooldown -= delta
	if _cooldown <= 0.0:
		_paint_lane()
		_cooldown = _tuning.lane_interval
	# Stationary is the entire point, same as Firewall Node.
	return Vector2.ZERO


## A row half the time, a column the other half — README asks for "one row or column," not
## a preference between them.
##
## The orientation and the slot are drawn here rather than inside a rect helper so that both are
## *known* by the time the lane is spawned: `OptimizingCompiler` answers its first lane with the
## perpendicular one through the same point, and it cannot do that from a `Rect2` alone.
func _paint_lane() -> void:
	var room := find_room()
	if room == null:
		return
	var is_row := randf() < 0.5
	var slots := Room.INTERIOR_TILES.y if is_row else Room.INTERIOR_TILES.x
	var slot := randi_range(0, slots - 1)
	spawn_lane(room, is_row, slot, _tuning.lane_telegraph_seconds)
	_on_lane_painted(room, is_row, slot)


## Paints one lane, with everything about it but the telegraph taken from this enemy's own tuning.
## The telegraph is a parameter because it is the one thing a second pass changes — see
## `OptimizingCompiler`.
func spawn_lane(room: Room, is_row: bool, slot: int, telegraph_seconds: float) -> void:
	var rect := room.get_row_rect(slot) if is_row else room.get_column_rect(slot)
	CompileLane.spawn(
		self, rect, _tuning.lane_damage, telegraph_seconds, _tuning.lane_strike_seconds
	)


## Called with what was just painted. Nothing here — a Compiler paints a lane and waits. The hook
## exists so the rung above it can answer its own lane without reimplementing the clock, the
## room lookup, or the draw.
func _on_lane_painted(_room: Room, _is_row: bool, _slot: int) -> void:
	pass

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


func _paint_lane() -> void:
	var room := find_room()
	if room == null:
		return
	CompileLane.spawn(
		self,
		_random_lane_rect(room),
		_tuning.lane_damage,
		_tuning.lane_telegraph_seconds,
		_tuning.lane_strike_seconds,
	)


## A row half the time, a column the other half — README asks for "one row or column," not
## a preference between them.
func _random_lane_rect(room: Room) -> Rect2:
	if randf() < 0.5:
		return room.get_row_rect(randi_range(0, Room.INTERIOR_TILES.y - 1))
	return room.get_column_rect(randi_range(0, Room.INTERIOR_TILES.x - 1))

class_name ExecutiveOverride
extends RuntimeError
## An authored Runtime Error rematch for a mature build, with its own encounter identity.
## The attack vocabulary, warnings, safe gaps, damage path and post-death ownership are inherited.
## The escalation is a longer order of familiar commands, not simultaneous random patterns.

const EXECUTIVE_TEXTURE := preload("res://art/bosses/executive_override.png")
const EXECUTIVE_TINT := Color(1.0, 0.92, 0.78)


func begin(arena: Rect2) -> void:
	super.begin(arena)
	(_part.get_node("%Sprite") as Sprite2D).texture = EXECUTIVE_TEXTURE
	_restore_tint()


func _restore_tint() -> void:
	if is_instance_valid(_part):
		_part.set_tint(EXECUTIVE_TINT)


func _attacks_for(phase: Phase) -> Array[int]:
	match phase:
		Phase.SINGLE_LANE:
			return [Attack.TWIN_LANES, Attack.SPREAD, Attack.RING]
		Phase.STAGGERED_LANES:
			return [Attack.CHECKERBOARD, Attack.SPREAD, Attack.TWIN_LANES, Attack.RING]
		_:
			return [Attack.CHECKERBOARD, Attack.WALL, Attack.TWIN_LANES, Attack.RING]

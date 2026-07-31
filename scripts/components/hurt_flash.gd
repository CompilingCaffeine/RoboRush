class_name HurtFlash
extends Node
## Flashes a sprite bright for a few frames when its owner is hit.
##
## Owns `target.modulate` only while flashing, and reports that through
## is_flashing() so an owner that also tints its sprite (the Ticket Bot's attack
## telegraph) can yield rather than fight over the same property.

@export var target: CanvasItem

@export var flash_seconds: float = 0.09

## Multiplied by FeedbackConfig.flash_intensity, so the accessibility setting reaches
## every flash without any effect hardcoding its own strength.
@export var flash_color: Color = Color(2.6, 2.6, 2.8, 1.0)

var _time_left := 0.0


func _ready() -> void:
	set_process(false)


func flash() -> void:
	if target == null:
		return
	_time_left = flash_seconds
	target.modulate = _scaled_color()
	set_process(true)


func is_flashing() -> bool:
	return _time_left > 0.0


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		return
	_time_left = 0.0
	target.modulate = Color.WHITE
	set_process(false)


func _scaled_color() -> Color:
	var intensity := GameManager.feedback.flash_intensity
	return Color.WHITE.lerp(flash_color, clampf(intensity, 0.0, 2.0))

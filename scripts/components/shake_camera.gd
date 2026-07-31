class_name ShakeCamera
extends Camera2D
## The player's camera, with trauma-based screen shake.
##
## Trauma accumulates from impacts and decays continuously; the offset is scaled by
## trauma *squared*, so small hits are nearly invisible while a boss slam is not.
## That curve is the reason spec section 7's "do not overuse screen shake" is
## achievable — callers can add trauma liberally for small events without the screen
## turning to soup.
##
## MAX_OFFSET is in pixels of a 480x270 frame, so it is deliberately tiny. The
## viewport stretch mode snaps the offset to whole pixels, which reads as a hard
## arcade jolt rather than a smooth wobble.

const MAX_OFFSET := Vector2(5.0, 3.5)

## Trauma lost per second. Tuned so a single hit's shake is over in ~0.25s.
const TRAUMA_DECAY := 4.0

var _trauma := 0.0


func _ready() -> void:
	set_process(false)


## `amount` is in trauma units where 1.0 is the strongest shake in the game.
## Squaring means 0.3 trauma produces 9% of maximum offset, not 30%.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	var scaled := amount * GameManager.feedback.screen_shake_scale
	if scaled <= 0.0:
		return
	_trauma = clampf(_trauma + scaled, 0.0, 1.0)
	set_process(true)


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		set_process(false)
		return

	var strength := _trauma * _trauma
	offset = Vector2(
		randf_range(-1.0, 1.0) * MAX_OFFSET.x * strength,
		randf_range(-1.0, 1.0) * MAX_OFFSET.y * strength,
	)


## Cancels shake immediately. Used on death and restart so the frame settles.
func clear_shake() -> void:
	_trauma = 0.0
	offset = Vector2.ZERO
	set_process(false)

class_name DamageNumber
extends Node2D
## A damage readout that rises and fades.
##
## Spec section 7 requires a damage number toggle, so FeedbackDirector checks
## FeedbackConfig before spawning these — this scene assumes it was wanted.

const RISE_PIXELS := 20.0
const DURATION := 0.5

## Horizontal scatter so simultaneous hits do not stack into an unreadable pile.
const SCATTER := 5.0

const NORMAL_COLOR := Color("ffe6a0")
const CRITICAL_COLOR := Color("ff9a5a")

@onready var _label: Label = $Label

var _elapsed := 0.0
var _origin := Vector2.ZERO
var _drift := Vector2.ZERO


func _ready() -> void:
	_origin = position
	_drift = Vector2(randf_range(-SCATTER, SCATTER), 0.0)


## Whole numbers render without a decimal; fractional damage (chain lightning at 0.7,
## Fork Bomb children at 60%) keeps one place so the maths stays legible.
func show_damage(amount: float, is_critical: bool) -> void:
	var rounded := roundf(amount)
	_label.text = "%d" % int(rounded) if is_equal_approx(amount, rounded) else "%.1f" % amount
	_label.add_theme_color_override(
		"font_color", CRITICAL_COLOR if is_critical else NORMAL_COLOR
	)
	if is_critical:
		_label.text += "!"


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)

	# Ease-out rise: fast off the target, then hanging, which reads better than a
	# constant climb.
	position = _origin + _drift * progress + Vector2.UP * RISE_PIXELS * sqrt(progress)
	# Hold full opacity for the first half so the number is actually readable.
	modulate.a = 1.0 - maxf((progress - 0.5) * 2.0, 0.0)

	if progress >= 1.0:
		queue_free()

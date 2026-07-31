class_name OneShotBurst
extends CPUParticles2D
## A particle burst that emits once and then removes itself.
##
## CPU particles rather than GPU: the counts here are tiny, the GL Compatibility
## renderer handles them without a compute pass, and it keeps the web export (spec
## section 31.12) straightforward.

## Extra grace beyond `lifetime` before freeing, so the last particle is not cut off.
const CLEANUP_GRACE := 0.15


func _ready() -> void:
	emitting = true
	await get_tree().create_timer(lifetime + CLEANUP_GRACE).timeout
	queue_free()


## Tints the burst to match whatever caused it, so a weapon's impacts read as that
## weapon's colour.
func set_tint(tint: Color) -> void:
	color = Color(tint.r, tint.g, tint.b, 1.0)


## Points the emission cone away from a surface.
func aim_along(normal: Vector2) -> void:
	if normal.is_zero_approx():
		return
	direction = normal

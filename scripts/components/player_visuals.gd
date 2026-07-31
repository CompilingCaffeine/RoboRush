class_name PlayerVisuals
extends Node2D
## Presentation for the player: aim rotation, dash squash, invulnerability flash.
##
## Holds no gameplay state and is never read by gameplay code, which keeps spec
## section 26.9 (separate gameplay logic from presentation) honest — deleting this
## script would change how the robot looks, not how it plays.

## Flash cycles per second while invulnerable.
const FLASH_HZ := 12.0

## Tint applied on the bright half of the invulnerability flash.
const FLASH_TINT := Color(1.7, 1.8, 2.0, 1.0)

## Tint applied on the dim half.
const FLASH_TINT_DIM := Color(1.0, 1.0, 1.0, 0.45)

## Non-uniform scale punched in at the start of a dash, then eased back out.
const DASH_SQUASH := Vector2(1.3, 0.75)

## How quickly the dash squash returns to rest, in units per second.
const SQUASH_RECOVERY := 7.0

@onready var _body: Sprite2D = $Body
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _cannon: Sprite2D = $AimPivot/Cannon

var _flash_time := 0.0


## Call once per frame with the player's current presentation-relevant state.
func update_visuals(aim_direction: Vector2, is_invulnerable: bool, delta: float) -> void:
	_update_aim(aim_direction)
	_update_flash(is_invulnerable, delta)
	_body.scale = _body.scale.move_toward(Vector2.ONE, SQUASH_RECOVERY * delta)


## Punches the squash in. Driven by the dash signal rather than polled, so the
## effect fires exactly once per dash.
func play_dash_squash() -> void:
	_body.scale = DASH_SQUASH


func _update_aim(aim_direction: Vector2) -> void:
	_aim_pivot.rotation = aim_direction.angle()
	# The cannon sprite is drawn pointing right; mirroring it when aiming left
	# stops the highlight and muzzle from ending up upside down.
	_cannon.flip_v = aim_direction.x < 0.0


func _update_flash(is_invulnerable: bool, delta: float) -> void:
	if not is_invulnerable:
		_flash_time = 0.0
		_body.modulate = Color.WHITE
		return

	# Accumulating only while invulnerable means every flash starts on the bright
	# half, so even a single-frame window is visible.
	_flash_time += delta
	var on_bright_half := fmod(_flash_time * FLASH_HZ, 1.0) < 0.5
	_body.modulate = FLASH_TINT if on_bright_half else FLASH_TINT_DIM

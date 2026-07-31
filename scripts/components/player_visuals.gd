class_name PlayerVisuals
extends Node2D
## Presentation for the player: aim rotation, dash squash, invulnerability flash,
## muzzle flash, and the death slump.
##
## Holds no gameplay state and is never read by gameplay code, which keeps spec
## section 26.9 (separate gameplay logic from presentation) honest — deleting this
## script would change how the robot looks, not how it plays.

## Flash cycles per second while invulnerable.
const FLASH_HZ := 12.0

## Tint applied on the bright half of the invulnerability flash, before
## FeedbackConfig.flash_intensity scales it.
const FLASH_TINT := Color(1.7, 1.8, 2.0, 1.0)

## Tint applied on the dim half.
const FLASH_TINT_DIM := Color(1.0, 1.0, 1.0, 0.45)

## Non-uniform scale punched in at the start of a dash, then eased back out.
const DASH_SQUASH := Vector2(1.3, 0.75)

## How quickly the dash squash returns to rest, in units per second.
const SQUASH_RECOVERY := 7.0

## Seconds the muzzle flash stays visible. Shorter than one frame at 4 shots/sec, so
## it reads as a flash rather than a lamp.
const MUZZLE_FLASH_SECONDS := 0.045

## Tint held after death.
const DEAD_TINT := Color(0.45, 0.42, 0.5, 1.0)

@onready var _body: Sprite2D = $Body
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _cannon: Sprite2D = $AimPivot/Cannon
@onready var _muzzle_flash: Sprite2D = $AimPivot/MuzzleFlash

var _flash_time := 0.0
var _muzzle_flash_left := 0.0
var _is_dead := false


func _ready() -> void:
	_muzzle_flash.visible = false


## Call once per frame with the player's current presentation-relevant state.
func update_visuals(aim_direction: Vector2, is_invulnerable: bool, delta: float) -> void:
	if _is_dead:
		return
	_update_aim(aim_direction)
	_update_flash(is_invulnerable, delta)
	_update_muzzle_flash(delta)
	_body.scale = _body.scale.move_toward(Vector2.ONE, SQUASH_RECOVERY * delta)


## Punched in from the dash signal rather than polled, so it fires exactly once.
func play_dash_squash() -> void:
	_body.scale = DASH_SQUASH


func play_muzzle_flash() -> void:
	_muzzle_flash_left = MUZZLE_FLASH_SECONDS
	_muzzle_flash.visible = true
	# Random roll makes a repeating 8x8 sprite look like four different flashes.
	_muzzle_flash.rotation = randf_range(-PI, PI)


## Locks the robot into a dimmed, un-flashing state. Called once on death so the
## per-frame updates cannot overwrite it.
func play_death() -> void:
	_is_dead = true
	_muzzle_flash.visible = false
	_body.modulate = DEAD_TINT
	_body.scale = Vector2(1.25, 0.7)
	_cannon.modulate = DEAD_TINT


func _update_aim(aim_direction: Vector2) -> void:
	_aim_pivot.rotation = aim_direction.angle()
	# The cannon sprite is drawn pointing right; mirroring it when aiming left stops
	# the highlight and muzzle from ending up upside down.
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
	var intensity := clampf(GameManager.feedback.flash_intensity, 0.0, 2.0)
	var bright := Color.WHITE.lerp(FLASH_TINT, intensity)
	var dim := Color.WHITE.lerp(FLASH_TINT_DIM, intensity)
	_body.modulate = bright if on_bright_half else dim


func _update_muzzle_flash(delta: float) -> void:
	if _muzzle_flash_left <= 0.0:
		return
	_muzzle_flash_left -= delta
	if _muzzle_flash_left <= 0.0:
		_muzzle_flash.visible = false

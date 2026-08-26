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

## Item id -> the sprite it bolts to the robot. Spec section 20 asks for the player sprite to
## visibly change for major items "where practical", and names these three among its examples.
##
## Three rather than twelve, deliberately. An eleven-pixel-tall robot has room for a few
## silhouette changes before it stops being a robot, so the ones that made it are the items
## that change how the player *is* rather than what their bullets do — armour, cooling,
## capacity. Ricochet Driver changes a great deal and shows nothing, which is the right
## trade: the cannon's accent tint already says "something is different".
const ATTACHMENTS := {
	&"reinforced_chassis": "Armour",
	&"cooling_fan": "Fan",
	&"backup_battery": "Battery",
}

## Revolutions per second of the cooling fan, once one is fitted. Spec section 20 lists
## "cooling fan spins" as an example, and a fan that does not turn reads as a sticker.
const FAN_SPIN_HZ := 1.6

## Frames between dash afterimages. Every frame is a smear rather than a trail, and the dash
## is only about eight frames long — every other one gives four ghosts, which is enough to
## show the path without the robot appearing to have been duplicated.
const AFTER_IMAGE_INTERVAL := 2

## How long one afterimage takes to fade out, and how solid it starts.
const AFTER_IMAGE_SECONDS := 0.22
const AFTER_IMAGE_ALPHA := 0.45

## Afterimages are tinted towards the dash's own colour rather than left grey, so the trail
## reads as the dash rather than as the robot failing to redraw.
const AFTER_IMAGE_TINT := Color(0.55, 0.95, 1.0)

@onready var _body: Sprite2D = $Body
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _cannon: Sprite2D = $AimPivot/Cannon
@onready var _muzzle_flash: Sprite2D = $AimPivot/MuzzleFlash
@onready var _fan: Sprite2D = %Fan

var _flash_time := 0.0
var _muzzle_flash_left := 0.0
var _is_dead := false
var _accent := Color.WHITE
var _is_dashing := false
var _frames_since_after_image := 0


func _ready() -> void:
	_muzzle_flash.visible = false
	EventBus.player_dash_started.connect(_on_dash_started)
	EventBus.player_dash_ended.connect(_on_dash_ended)
	# Read off the bus rather than pushed by the inventory, for the same reason the particle
	# bursts are: picking something up should not require the thing that picks it up to know
	# what the robot looks like.
	EventBus.item_collected.connect(_on_item_collected)


## Call once per frame with the player's current presentation-relevant state.
##
## `flash` is whether the robot should *show* immunity rather than whether it has any: the
## window a doorway grants is deliberately silent, and `Player.should_flash` is where that is
## decided. This file is handed the answer because a sprite has no business knowing what a
## doorway is.
func update_visuals(aim_direction: Vector2, flash: bool, delta: float) -> void:
	if _is_dead:
		return
	_update_aim(aim_direction)
	_update_flash(flash, delta)
	_update_muzzle_flash(delta)
	_body.scale = _body.scale.move_toward(Vector2.ONE, SQUASH_RECOVERY * delta)
	if _fan.visible:
		_fan.rotation += TAU * FAN_SPIN_HZ * delta
	_update_after_images()


## The dash was the one thing the robot does that had no visual weight — it moved fast and
## arrived, and at 480x270 that is a teleport. A short trail of fading copies is the cheapest
## way to say "it travelled", and it doubles as the readout for the invulnerability window.
func _update_after_images() -> void:
	if not _is_dashing:
		return
	_frames_since_after_image += 1
	if _frames_since_after_image < AFTER_IMAGE_INTERVAL:
		return
	_frames_since_after_image = 0
	_spawn_after_image()


func _spawn_after_image() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = _body.texture
	# top_level so the ghost stays where the robot *was*. Without it every copy would ride
	# along with the player and the trail would be a single flickering sprite.
	ghost.top_level = true
	add_child(ghost)
	ghost.global_position = _body.global_position
	ghost.scale = _body.scale
	ghost.modulate = Color(
		AFTER_IMAGE_TINT.r, AFTER_IMAGE_TINT.g, AFTER_IMAGE_TINT.b, AFTER_IMAGE_ALPHA
	)

	var fade := ghost.create_tween()
	fade.tween_property(ghost, "modulate:a", 0.0, AFTER_IMAGE_SECONDS)
	fade.tween_callback(ghost.queue_free)


func _on_dash_started(_direction: Vector2) -> void:
	_is_dashing = true
	# Reset rather than left running, so the first ghost lands on the frame the dash starts
	# instead of up to two frames into it.
	_frames_since_after_image = AFTER_IMAGE_INTERVAL


func _on_dash_ended() -> void:
	_is_dashing = false


## Punched in from the dash signal rather than polled, so it fires exactly once.
func play_dash_squash() -> void:
	_body.scale = DASH_SQUASH


func play_muzzle_flash() -> void:
	_muzzle_flash_left = MUZZLE_FLASH_SECONDS
	_muzzle_flash.visible = true
	# Random roll makes a repeating 8x8 sprite look like four different flashes.
	_muzzle_flash.rotation = randf_range(-PI, PI)


## Tints the cannon to the colour of the item just collected.
##
## Spec section 20 asks for visible changes from major items, and the cannon is the part
## of an eleven-pixel robot with room to say anything: it is the largest single-colour
## area and it is already the part the player watches. One accent rather than a stack of
## them, because a robot tinted by six items at once is a robot tinted brown.
func set_accent(color: Color) -> void:
	_accent = color
	if not _is_dead:
		_cannon.modulate = _accent


## Bolts on the sprite an item brings, if it brings one. Unknown ids are the normal case —
## nine of the twelve items change nothing here — so a miss is silent rather than a warning.
func _on_item_collected(item: ItemConfig) -> void:
	if item == null or not ATTACHMENTS.has(item.id):
		return
	var attachment := get_node_or_null(NodePath(ATTACHMENTS[item.id])) as Sprite2D
	if attachment != null:
		attachment.visible = true


## Locks the robot into a dimmed, un-flashing state. Called once on death so the
## per-frame updates cannot overwrite it.
func play_death() -> void:
	_is_dead = true
	_muzzle_flash.visible = false
	_body.modulate = DEAD_TINT
	_body.scale = Vector2(1.25, 0.7)
	_cannon.modulate = DEAD_TINT
	# The attachments die with the robot: a glowing battery on a slumped wreck reads as the
	# game having failed to notice, and the fan is stopped by _is_dead cutting the update.
	for node_name: String in ATTACHMENTS.values():
		var attachment := get_node_or_null(NodePath(node_name)) as Sprite2D
		if attachment != null:
			attachment.modulate = DEAD_TINT


func _update_aim(aim_direction: Vector2) -> void:
	_aim_pivot.rotation = aim_direction.angle()
	# The cannon sprite is drawn pointing right; mirroring it when aiming left stops
	# the highlight and muzzle from ending up upside down.
	_cannon.flip_v = aim_direction.x < 0.0


func _update_flash(flash: bool, delta: float) -> void:
	if not flash:
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

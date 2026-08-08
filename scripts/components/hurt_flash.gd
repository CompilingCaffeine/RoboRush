class_name HurtFlash
extends Node
## Flashes a sprite bright for a few frames when its owner is hit.
##
## Owns `target.modulate` only while flashing, and reports that through
## is_flashing() so an owner that also tints its sprite (the Ticket Bot's attack
## telegraph) can yield rather than fight over the same property.
##
## What it restores afterwards is the target's *own* colour, captured once at ready, not
## white. Restoring white was correct for as long as every enemy that could be shot had an
## untinted sprite, and stopped being correct the moment Floor 2 started distinguishing
## enemies by tint: a Compiler is cyan until the first rivet lands and plain white for the
## rest of the fight, which reads as the enemy changing state when nothing has.

## Path to the sprite this flashes, relative to this node.
##
## A `NodePath` resolved here rather than an `@export var target: CanvasItem`, which is what
## it was and which never worked. Every scene in the project assigns this the way the editor
## serialises a node reference — `NodePath("../Sprite")` — and a hand-authored scene does not
## carry the extra state Godot needs to turn that back into a node on load, so `target` was
## null on all eleven users: every enemy, both bosses' parts, and the boss terminal. Nothing
## failed loudly, because `flash()` returns early on a null target. Being shot has simply
## never flashed anything, for as long as this component has existed.
##
## Resolving a path this component owns cannot half-succeed the same way, and it keeps the
## scenes' existing `NodePath("../Sprite")` lines meaning exactly what they appear to mean.
@export var target_path: NodePath = ^"../Sprite"

@export var flash_seconds: float = 0.09

## Multiplied by FeedbackConfig.flash_intensity, so the accessibility setting reaches
## every flash without any effect hardcoding its own strength.
@export var flash_color: Color = Color(2.6, 2.6, 2.8, 1.0)

var _time_left := 0.0

## The sprite being flashed, resolved once from `target_path`.
var _target: CanvasItem

## The colour the target rests at between flashes.
var _resting := Color.WHITE


func _ready() -> void:
	_target = get_node_or_null(target_path) as CanvasItem
	if _target == null:
		push_warning("HurtFlash on '%s': '%s' is not a CanvasItem." % [
			get_parent().name if get_parent() != null else name, target_path,
		])
	else:
		_resting = _target.modulate
	set_process(false)


## The sprite this flashes, or null when the path did not resolve. Exposed so a test can
## assert the wiring is live rather than only that nothing crashed — the previous version of
## this component passed every test in the project while doing nothing at all.
func get_target() -> CanvasItem:
	return _target


func flash() -> void:
	if _target == null:
		return
	_time_left = flash_seconds
	var flash_to := _scaled_color()
	# Alpha is left alone in both directions — here and in the restore below — so a Pop Up
	# Drone shot while it is fading in keeps fading rather than snapping to fully opaque.
	_target.modulate = Color(flash_to.r, flash_to.g, flash_to.b, _target.modulate.a)
	set_process(true)


func is_flashing() -> bool:
	return _time_left > 0.0


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		return
	_time_left = 0.0
	_target.modulate = Color(_resting.r, _resting.g, _resting.b, _target.modulate.a)
	set_process(false)


func _scaled_color() -> Color:
	var intensity := GameManager.feedback.flash_intensity
	return Color.WHITE.lerp(flash_color, clampf(intensity, 0.0, 2.0))

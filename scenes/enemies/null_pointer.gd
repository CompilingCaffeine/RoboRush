class_name NullPointer
extends Enemy
## Development's answer to a player who has learned to stand in the one safe corner and
## shoot: it dereferences the address you are at. Every few seconds it marks a small square
## of floor *centred on wherever the player is standing at that moment*, and a beat later
## that square executes.
##
## The Compiler and this are deliberately the same hazard asked two different ways. Compiler
## picks a stripe of the room and asks "is that where you are?" — the answer is somewhere
## else in the room, and the player has a whole room of it. This picks the player and asks
## "are you still there?" — the answer is one step in any direction, and the only way to be
## wrong is to not move at all. Neither ever removes the player's escape, which is what lets
## them be in the same room together; two enemies that each deleted a region would not be.
##
## It commits at the moment of marking and never re-aims, for the Memory Leech's reason: a
## patch that followed the player would be a hazard with no answer, and the whole floor is
## built on warnings that can be read and acted on.
##
## Everything visible is a `CompileLane`, the same class the Compiler and the Runtime Error
## boss paint with, so the amber-then-red language is shared by construction rather than by
## three scripts agreeing on a colour.

## Colour it brightens toward while a patch of its own is telegraphing, so the player can
## tell which body sent the square under their feet. Amber, matching the patch — the tint
## and the warning are the same event.
const MARK_TINT := Color(2.0, 1.5, 0.7)

var _tuning: NullPointerConfig
var _cooldown := 0.0

## Seconds of telegraph left on the patch this enemy most recently sent, used only to drive
## the tint. The lane owns its own real timing and resolves with or without us.
var _tint_left := 0.0


func _on_ready() -> void:
	_tuning = config as NullPointerConfig
	assert(_tuning != null, "NullPointer.config must be a NullPointerConfig.")
	# Staggered so two in one room do not mark in lockstep, which would read as one hazard
	# rather than two — Firewall Node spreads its starting angle for the same reason.
	_cooldown = randf_range(_tuning.mark_interval * 0.5, _tuning.mark_interval)


func _act(delta: float) -> Vector2:
	_step_tint(delta)

	_cooldown -= delta
	if _cooldown <= 0.0:
		_mark()
		_cooldown = _tuning.mark_interval

	return _hold_range()


func get_seconds_to_next_mark() -> float:
	return _cooldown


## Sends a patch to where the player is standing right now. Requires line of sight for the
## base class's stated reason — an enemy acting through a wall reads as a bug — and simply
## waits out another interval when it has none, rather than marking a square the player
## cannot see arrive.
func _mark() -> void:
	if _player == null or not has_line_of_sight(_player.global_position):
		return

	CompileLane.spawn(
		self,
		_patch_rect(_player.global_position),
		_tuning.mark_damage,
		_tuning.mark_telegraph_seconds,
		_tuning.mark_strike_seconds,
	)
	_tint_left = _tuning.mark_telegraph_seconds


## The patch, snapped to the room's tile grid so it lines up with the Compiler's lanes and
## the boss's checkerboards instead of sitting at a half-tile offset next to them. With no
## room — a test arena — it falls back to an unsnapped square around the point, so the
## behaviour is still exercisable in isolation.
func _patch_rect(at: Vector2) -> Rect2:
	var span := maxi(_tuning.mark_tiles, 1)
	var room := find_room()
	if room == null:
		var size := Vector2.ONE * span * Room.TILE_SIZE
		return Rect2(at - size * 0.5, size)

	# Integer division on purpose: an odd span centres on the player's own tile, and an even
	# one leans to the tile they are standing in rather than straddling ambiguously.
	var centre := room.get_tile_at(at)
	return room.get_tile_block_rect(centre - Vector2i.ONE * (span / 2), Vector2i.ONE * span)


func _step_tint(delta: float) -> void:
	if _tint_left <= 0.0:
		return
	_tint_left = maxf(_tint_left - delta, 0.0)
	var charge := _tint_left / maxf(_tuning.mark_telegraph_seconds, 0.001)
	tint_toward(MARK_TINT, charge)


## Holds `preferred_range`, the same radial term Ticket Bot and Code Runner use. There is no
## tangential term here on purpose: a target that also strafed would make this enemy hard to
## shoot *and* hard to stand still near, and only one of those is its job.
func _hold_range() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	var offset := _player.global_position - global_position
	var distance := offset.length()
	if is_zero_approx(distance):
		return Vector2.ZERO
	var heading := offset / distance

	if distance > config.preferred_range + config.range_tolerance:
		return heading * config.move_speed
	if distance < config.preferred_range - config.range_tolerance:
		return -heading * config.move_speed
	return Vector2.ZERO

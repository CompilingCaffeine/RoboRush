class_name LoadBalancer
extends Enemy
## The Data Center's shielded body: it puts a plate between itself and you, and the plate turns.
##
## Every other enemy in the game decides whether your damage lands by *when* you fire — a windup
## to wait out, a lane to leave, a body to hit while it strafes. This one decides it by **where you
## are standing**, which is the only question this floor asks about anything. Shots that arrive
## through the plate are swallowed whole. Shots that arrive anywhere else are ordinary hits.
##
## The plate is not a puzzle and it is not a timer. It tracks the player at a fixed angular rate,
## so the fight is one comparison the player can feel without being told it: their own angular
## speed, `v / r`, against `plate_turn_speed`. That rises as they close, which makes the answer to
## a Load Balancer "get inside about a hundred pixels and keep going round" — and the price of
## being that close is that the plate is also the only part of it that hurts to touch. Its armour
## and its ram are one object, pointing one way, and the player reads both off the same arc.
##
## **Why it is beaten by moving rather than by aiming.** Floor 3 charges the player for standing
## still and firing; an enemy that could be answered by planting your feet and out-damaging it
## would be an enemy that argued with the floor it is standing on. This one cannot be. A player
## who never moves does nothing to it at all, however good their aim, and a player who circles it
## does not have to aim especially well. The floor's habit is the whole solution.
##
## Its one weakness from in front is not damage. `Projectile` applies status effects directly to
## the body it hit rather than through `apply_damage`, so a chill lands on the plate even though
## the shot does not — and the plate's turn is scaled by that chill. Slowing the thing you are
## trying to out-turn is a real answer, it costs an item to have, and it is nothing the plate has
## to know about: it falls out of the two systems already behaving as they do.

## Line segments the plate's arc is drawn from. Enough that a 150-degree arc reads as a curve at
## this scale and not so many that it reads as smooth — the rest of the game is drawn in whole
## pixels, and a perfectly smooth arc would be the one antialiased thing on screen.
const PLATE_SEGMENTS := 20

var _tuning: LoadBalancerConfig

## Which way the plate points, in radians. The enemy's entire state.
var _facing := 0.0

var _plate_flash_left := 0.0


func _on_ready() -> void:
	_tuning = config as LoadBalancerConfig
	assert(_tuning != null, "LoadBalancer.config must be a LoadBalancerConfig.")
	# Random rather than aimed at the player, so a room with two of them does not present two
	# plates turning in lockstep, and so the first one a player meets is as likely to be showing
	# its back as its front — the enemy's rule is easier to learn from a shot that landed.
	_facing = randf() * TAU

	# Registered on the receiver rather than resolved in `_on_damaged`, because a blocked shot must
	# not be damage that happened and was then undone: no integrity lost, no `damaged` emitted, no
	# hurt flash, and nothing in the run's statistics. `HealthComponent.damage_absorber` is exactly
	# that contract, written for the player's Faraday Cage and not owed to it.
	var health := get_health_component()
	if health != null:
		health.damage_absorber = _absorb

	# So the plate is on screen from the first frame rather than from the first frame it turns.
	queue_redraw()


func _act(delta: float) -> Vector2:
	_step_plate(delta)

	if _player == null:
		return Vector2.ZERO
	var offset := _player.global_position - global_position
	if offset.is_zero_approx():
		return Vector2.ZERO
	# It closes, and that is all its movement is. A range-keeper with a shield would be a wall the
	# player could never get inside, and inside is where the fight is.
	return offset.normalized() * config.move_speed


## Whether the plate currently covers `bearing`, a direction measured out from this body.
##
## Public because it is what the enemy *is*, and both of the things it decides — a shot swallowed,
## a touch that hurts — are worth being able to ask about from a test without reproducing the
## angle arithmetic that would then be free to disagree with this one.
func plate_covers(bearing: Vector2) -> bool:
	if bearing.is_zero_approx():
		return false
	var half := deg_to_rad(_tuning.plate_arc_degrees) * 0.5
	return absf(angle_difference(_facing, bearing.angle())) <= half


func get_facing() -> float:
	return _facing


## Contact damage only through the plate. The base class owns the cooldown, the radius, the
## knockback and finding the player's integrity; this is the one sentence that makes this enemy
## different from every other body that hurts to touch.
func _may_deal_contact_damage() -> bool:
	if _player == null:
		return false
	return plate_covers(_player.global_position - global_position)


## Turns the plate toward the player and runs down the hit flash.
##
## Scaled by the enemy's own status, like `RuntimeError`'s sway and for the same reason: a frozen
## body that went on tracking at full rate would be frozen in the one way that did not matter.
func _step_plate(delta: float) -> void:
	var previous := _facing
	if _player != null:
		var offset := _player.global_position - global_position
		if not offset.is_zero_approx():
			_facing = _turn_toward(
				_facing, offset.angle(), _tuning.plate_turn_speed * get_status_speed_scale() * delta
			)

	var was_flashing := _plate_flash_left > 0.0
	_plate_flash_left = maxf(_plate_flash_left - delta, 0.0)

	# Redrawn only when the arc would actually differ. A room of Load Balancers standing at rest
	# is otherwise a redraw each per frame for a picture that has not changed.
	if not is_equal_approx(previous, _facing) or was_flashing:
		queue_redraw()


## `from` moved toward `to` by at most `step`, the shorter way round. `angle_difference` is what
## makes it the shorter way — the naive subtraction takes the long way round exactly once per
## revolution, which would show up as the plate spinning the wrong way past due north.
func _turn_toward(from: float, to: float, step: float) -> float:
	var delta_angle := angle_difference(from, to)
	return from + clampf(delta_angle, -step, step)


## Swallows a hit that arrived through the plate. See `HealthComponent.damage_absorber` for what
## returning true costs the shot.
##
## Judged on the direction the damage was *travelling*, not on where its source was standing. That
## is the honest question — what the plate was struck by is what arrived at it — and it makes the
## one item in the pool that answers this enemy without moving do so by construction: a Ricochet
## Driver shot that comes back off the far wall arrives from behind and lands, because it really
## did arrive from behind.
##
## A hit with no direction is never blocked. Burn, and a blast the player set off around it, did
## not come from anywhere; a plate cannot be in front of nowhere.
func _absorb(info: DamageInfo) -> bool:
	if info.direction.is_zero_approx() or not plate_covers(-info.direction):
		return false
	_plate_flash_left = _tuning.plate_flash_seconds
	queue_redraw()
	return true


## Drawn here rather than as a child node so it sits *under* the sprite: a CanvasItem draws itself
## before its children, and a plate over the body would hide the thing the player is trying to
## shoot. It is drawn outside the body's radius, so what is visible is the whole of what blocks.
func _draw() -> void:
	var charge := 0.0
	if _tuning.plate_flash_seconds > 0.0:
		charge = clampf(_plate_flash_left / _tuning.plate_flash_seconds, 0.0, 1.0)
	var tint := _tuning.plate_color.lerp(_tuning.plate_flash_color, charge)
	var half := deg_to_rad(_tuning.plate_arc_degrees) * 0.5
	draw_arc(
		Vector2.ZERO,
		_tuning.plate_radius,
		_facing - half,
		_facing + half,
		PLATE_SEGMENTS,
		tint,
		_tuning.plate_thickness,
		false,
	)

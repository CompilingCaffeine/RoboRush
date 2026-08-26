class_name PopUpDrone
extends Enemy
## Spec section 15: "Teleports to room edges, pauses, then fires a three shot spread."
##
## Its purpose is to force aim changes and spatial awareness, which means the interesting
## moment is not the shot — it is the half second after it arrives, when the player has to
## find it again and decide whether to shoot it or move. Everything here serves that
## window: it appears somewhere new, it is unmistakably visible while it fades in, and it
## announces the shot before taking it.
##
## The three-shot spread is `projectiles_per_shot` and `spread_degrees` on its weapon, so
## there is no firing code here at all. Changing it to a five shot spread is a `.tres` edit.

## Colour it brightens toward while winding up.
const CHARGE_TINT := Color(2.0, 1.2, 1.2)

enum Phase {
	## Sitting still, waiting to relocate.
	HOLDING,
	## Just arrived, fading in.
	ARRIVING,
	## Fully visible and about to fire.
	WINDING_UP,
}

var _tuning: PopUpDroneConfig
var _phase := Phase.HOLDING
var _phase_left := 0.0


func _on_ready() -> void:
	_tuning = config as PopUpDroneConfig
	assert(_tuning != null, "PopUpDrone.config must be a PopUpDroneConfig.")
	_phase_left = _tuning.teleport_interval


## Never moves under its own power — it is somewhere, and then it is somewhere else.
func _act(delta: float) -> Vector2:
	_phase_left -= delta

	match _phase:
		Phase.HOLDING:
			if _phase_left <= 0.0:
				_relocate()
		Phase.ARRIVING:
			# Fade rather than a hard cut, so the player's eye is drawn to where it went.
			var progress := 1.0 - clampf(_phase_left / maxf(_tuning.arrival_fade, 0.001), 0.0, 1.0)
			_sprite.modulate.a = progress
			if _phase_left <= 0.0:
				_sprite.modulate.a = 1.0
				_enter(Phase.WINDING_UP, _tuning.arrival_pause)
		Phase.WINDING_UP:
			var charge := 1.0 - clampf(_phase_left / maxf(_tuning.arrival_pause, 0.001), 0.0, 1.0)
			tint_toward(CHARGE_TINT, charge)
			if _phase_left <= 0.0:
				_fire()

	return Vector2.ZERO


func get_phase() -> Phase:
	return _phase


func _enter(phase: Phase, seconds: float) -> void:
	_phase = phase
	_phase_left = seconds


## Picks a point near the room's edge that is clear of geometry and not on top of the
## player, and goes there. Failing to find one leaves the drone where it is and tries
## again next cycle, which is the right answer for a room so cluttered there is nowhere to
## stand — better a predictable drone than one inside a wall.
func _relocate() -> void:
	var destination := _pick_destination()
	if destination.is_equal_approx(global_position):
		_enter(Phase.HOLDING, _tuning.teleport_interval)
		return

	global_position = destination
	velocity = Vector2.ZERO
	_sprite.modulate.a = 0.0
	_enter(Phase.ARRIVING, _tuning.arrival_fade)


## Returns where to go, or the drone's own position when nothing was acceptable — "stay
## put" is a legitimate destination, and expressing it that way keeps this returning a
## Vector2 rather than something nullable that every caller has to unwrap.
func _pick_destination() -> Vector2:
	var room := find_room()
	var player_position := _player.global_position if _player != null else global_position

	for _attempt: int in maxi(_tuning.placement_attempts, 1):
		var candidate := _random_edge_point(room)
		if candidate.distance_to(player_position) < _tuning.min_teleport_distance:
			continue
		if candidate.distance_to(global_position) < _tuning.edge_inset:
			continue
		if _is_blocked(candidate):
			continue
		return candidate
	return global_position


## A point on the inset perimeter of the room. With no room — a test arena — it falls back
## to a ring around where it spawned, so the behaviour is still exercisable in isolation.
func _random_edge_point(room: Room) -> Vector2:
	if room == null:
		return global_position + Vector2.RIGHT.rotated(randf() * TAU) * _tuning.min_teleport_distance

	var interior := room.get_interior_rect()
	var inset := _tuning.edge_inset
	var left := interior.position.x + inset
	var right := interior.end.x - inset
	var top := interior.position.y + inset
	var bottom := interior.end.y - inset
	if right <= left or bottom <= top:
		return room.get_interior_centre()

	# Walk a random distance around the perimeter, so corners are no more likely than edges.
	var width := right - left
	var height := bottom - top
	var along := randf() * (width + height) * 2.0
	if along < width:
		return Vector2(left + along, top)
	along -= width
	if along < height:
		return Vector2(right, top + along)
	along -= height
	if along < width:
		return Vector2(right - along, bottom)
	return Vector2(left, bottom - (along - width))


## Queried against level geometry rather than against the room's template, so obstacles
## the template does not know about (a boss arena's terminals, later) block it too.
func _is_blocked(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = Teams.body_mask()
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


func _fire() -> void:
	if _player != null and _weapon.can_fire():
		_weapon.try_fire(global_position, (_player.global_position - global_position).normalized())
	tint_toward(CHARGE_TINT, 0.0)
	_enter(Phase.HOLDING, _tuning.teleport_interval)

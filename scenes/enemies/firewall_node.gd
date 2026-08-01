class_name FirewallNode
extends Enemy
## Spec section 15: "Remains stationary and projects rotating hazard beams."
##
## Its purpose is to control space, and it is the only enemy in the game that threatens
## the player without ever approaching them. Everything else asks "can you kill this before
## it reaches you"; this asks "where are you allowed to stand".
##
## The beams are the enemy. They are built from `beam_count` at runtime rather than
## authored into the scene, so a two-beam node and a four-beam node are one `.tres` apart
## — and what damages the player is measured against the same line that is drawn, so there
## is no invisible hazard and no decorative beam that turns out to be harmless.
##
## Beams stop at walls. A hazard that sweeps through solid geometry reads as a bug, and a
## node tucked behind a pillar should be a node that controls less space.

## The robot's collision radius, from player.tscn. Duplicated here rather than read off the
## player, because the alternative is reaching into another actor's collision shape every
## frame to recover a number that has not changed since milestone 1.
const PLAYER_RADIUS := 5.0

var _tuning: FirewallNodeConfig
var _beams: Array[Line2D] = []
var _angle := 0.0
var _hit_cooldown := 0.0
var _pulse_time := 0.0


func _on_ready() -> void:
	_tuning = config as FirewallNodeConfig
	assert(_tuning != null, "FirewallNode.config must be a FirewallNodeConfig.")
	# Spread the starting angle so a room with two nodes does not have them sweeping in
	# lockstep, which would read as one hazard rather than two.
	_angle = randf() * TAU
	_build_beams()


func _act(delta: float) -> Vector2:
	_angle = fmod(_angle + _tuning.beam_rotation_speed * delta, TAU)
	_pulse_time += delta
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)

	var reach := _update_beams()
	_damage_player_in_beams(reach)

	# Stationary is the entire point.
	return Vector2.ZERO


func get_beam_count() -> int:
	return _beams.size()


func get_beam_angle() -> float:
	return _angle


## Rebuilds each beam's geometry and returns the endpoint of each, in global space, so the
## damage check measures exactly the line that was drawn.
func _update_beams() -> Array[Vector2]:
	var ends: Array[Vector2] = []
	var step := TAU / float(maxi(_beams.size(), 1))
	var alpha := 0.65 + 0.35 * absf(sin(_pulse_time * PI * _tuning.beam_pulse_hz))

	for index: int in _beams.size():
		var direction := Vector2.RIGHT.rotated(_angle + step * index)
		var reach := _reach_along(direction)
		var beam := _beams[index]
		beam.points = PackedVector2Array([Vector2.ZERO, direction * reach])
		beam.modulate.a = alpha
		ends.append(global_position + direction * reach)

	return ends


## Casts against level geometry so a beam ends at the wall it meets.
func _reach_along(direction: Vector2) -> float:
	var target := global_position + direction * _tuning.beam_length
	var query := PhysicsRayQueryParameters2D.create(global_position, target, Teams.LAYER_WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _tuning.beam_length
	return global_position.distance_to(hit["position"] as Vector2)


## One cooldown for the whole node rather than one per beam, so walking through the centre
## of the fan is one hit rather than three simultaneous ones.
func _damage_player_in_beams(ends: Array[Vector2]) -> void:
	if _player == null or _hit_cooldown > 0.0:
		return

	var health := HealthComponent.find_on(_player)
	if health == null:
		return

	for end_point: Vector2 in ends:
		var closest := Geometry2D.get_closest_point_to_segment(
			_player.global_position, global_position, end_point
		)
		if _player.global_position.distance_to(closest) > _tuning.beam_half_width + PLAYER_RADIUS:
			continue

		var offset := _player.global_position - global_position
		var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
		if health.apply_damage(
			DamageInfo.new(_tuning.beam_damage, self, direction, config.contact_knockback)
		):
			_hit_cooldown = _tuning.beam_interval
		return



func _build_beams() -> void:
	for _index: int in maxi(_tuning.beam_count, 1):
		var beam := Line2D.new()
		beam.width = _tuning.beam_half_width * 2.0
		beam.default_color = _tuning.beam_color
		beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
		beam.end_cap_mode = Line2D.LINE_CAP_ROUND
		beam.antialiased = false
		# Behind the node's own sprite, so the core stays readable as the thing to shoot.
		beam.z_index = -1
		add_child(beam)
		_beams.append(beam)

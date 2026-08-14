extends TestCase
## Floor 3's throughput zones: what heats them, what does not, and what a vent costs.
##
## The mechanic is one number — a zone's heat — and the whole design is which things are allowed to
## move it. Every check here is really a check on that list, because the list is where the design
## lives: charge for the wrong thing and the floor becomes a tax on the player's build instead of a
## lesson about standing still. See `ThermalZone` for the argument; this is the part that fails if
## somebody later "simplifies" heat to accrue per shot.

const ZONE_SIZE := Vector2(64.0, 48.0)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

## Long enough to fill a zone from cold with a margin: `SECONDS_TO_VENT` at 60Hz, plus a few frames
## for the vent itself to resolve.
var _frames_to_vent := int(ThermalZone.SECONDS_TO_VENT * 60.0) + 6


func run() -> void:
	await _test_standing_still_and_firing_heats_a_zone()
	await _test_moving_while_firing_does_not()
	await _test_firing_outside_the_zone_does_not()
	await _test_standing_still_without_firing_does_not()
	await _test_a_vent_costs_integrity_and_then_relents()
	await _test_a_zone_cools_when_left_alone()
	await _test_a_template_builds_its_zones_inside_the_room()
	await _test_zones_stop_with_the_room_they_are_in()


## The one thing that must heat a zone.
func _test_standing_still_and_firing_heats_a_zone() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	await _fire_for(6, player)

	check(zone.get_heat() > 0.0, "standing still and firing inside a zone heats it (%.2f)" % zone.get_heat())
	_close(arena)
	await advance_physics(1)


## Moving is the whole answer, and it has to be a *complete* answer: a player who keeps moving pays
## nothing at any fire rate. This is the check that stops the mechanic becoming a tax on Cooling Fan
## and Unsafe Overclock.
func _test_moving_while_firing_does_not() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	for _frame: int in 30:
		# Set every frame: `move_and_slide` consumes it, so a velocity written once reads as
		# stationary again on the next frame.
		player.velocity = Vector2(Player.STILLNESS_SPEED * 6.0, 0.0)
		EventBus.shot_fired.emit(Teams.Id.PLAYER, player.global_position, Vector2.RIGHT)
		await get_tree().physics_frame

	check(
		is_zero_approx(zone.get_heat()),
		"firing while moving does not heat a zone at all (%.3f)" % zone.get_heat(),
	)
	_close(arena)
	await advance_physics(1)


func _test_firing_outside_the_zone_does_not() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	# Well clear of the zone, including the player-radius margin the zone grows.
	player.global_position = _zone_centre(zone) + Vector2(ZONE_SIZE.x * 2.0, 0.0)
	await _fire_for(30, player)

	check(
		is_zero_approx(zone.get_heat()),
		"a zone is not heated by shots fired somewhere else (%.3f)" % zone.get_heat(),
	)
	_close(arena)
	await advance_physics(1)


## Occupancy alone must cost nothing. A zone that charged for being stood in would punish a player
## for being in the room rather than for a habit.
func _test_standing_still_without_firing_does_not() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	await advance_physics(40)

	check(
		is_zero_approx(zone.get_heat()),
		"standing in a zone without firing is free (%.3f)" % zone.get_heat(),
	)
	_close(arena)
	await advance_physics(1)


## The payoff, and the grace that follows it. Without the cooldown a player at full heat would be
## hit again before they could cross the zone's edge, which is a hazard that cannot be answered.
func _test_a_vent_costs_integrity_and_then_relents() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]
	var health := player.get_health_component()

	var vents: Array[Rect2] = []
	var probe := func(rect: Rect2) -> void: vents.append(rect)
	EventBus.thermal_zone_vented.connect(probe)

	player.global_position = _zone_centre(zone)
	var before := health.current
	await _fire_for(_frames_to_vent, player)

	check(vents.size() >= 1, "sustained stationary fire vents the zone (%d vents)" % vents.size())
	check(
		health.current < before,
		"and the vent costs integrity (%.1f, was %.1f)" % [health.current, before],
	)
	check_near(
		before - health.current, ThermalZone.VENT_DAMAGE,
		"exactly one vent's worth of damage", 0.01
	)
	check(is_zero_approx(zone.get_heat()), "the zone is cold again after venting")

	# The cooldown: still standing there, still firing, and it must not immediately refill.
	await _fire_for(int(ThermalZone.VENT_COOLDOWN * 60.0) - 10, player)
	check(
		is_zero_approx(zone.get_heat()),
		"a vented zone will not reheat until its cooldown has passed (%.3f)" % zone.get_heat(),
	)

	EventBus.thermal_zone_vented.disconnect(probe)
	_close(arena)
	await advance_physics(1)


func _test_a_zone_cools_when_left_alone() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	await _fire_for(20, player)
	var loaded := zone.get_heat()
	check(loaded > 0.0, "the zone has heat to lose")
	if loaded <= 0.0:
		_close(arena)
		await advance_physics(1)
		return

	# Past `FIRING_MEMORY` before measuring. Inside that window the player still counts as firing —
	# which is the point of the window, so a slow weapon does not make heat stutter between shots —
	# and a check that measured sooner would be asserting that the memory does not exist.
	await advance_physics(int(ThermalZone.FIRING_MEMORY * 60.0) + 25)
	check(zone.get_heat() < loaded, "a zone left alone cools (%.2f from %.2f)" % [zone.get_heat(), loaded])

	# Cooling is faster than heating, so walking away is always a complete answer.
	check(
		ThermalZone.COOL_SECONDS < ThermalZone.SECONDS_TO_VENT,
		"and cools faster than it heats, so leaving always works",
	)
	_close(arena)
	await advance_physics(1)


## The data path: a template declares zones in tile coordinates and the room builds them, with no
## floor number anywhere in it.
func _test_a_template_builds_its_zones_inside_the_room() -> void:
	var template := RoomTemplate.new()
	template.id = &"__test_thermal"
	template.type = RoomTemplate.Type.COMBAT
	# The second runs deliberately off the edge, which `get_tile_block_rect` clamps: a template with
	# a bad zone should draw a zone at the edge rather than half outside the room.
	template.thermal_zones = [Rect2i(4, 3, 6, 4), Rect2i(24, 10, 8, 6)]

	var room: Room = ROOM_SCENE.instantiate()
	add_child(room)
	room.build(RoomPlan.new(0, Vector2i.ZERO, RoomTemplate.Type.COMBAT))
	room.plan.template = template
	# Rebuilt now that the plan has a template, which is the order the floor uses in reverse; the
	# zones are what this is checking, and they are built from the template.
	room._build_thermal_zones()
	await advance_physics(1)

	var zones: Array[ThermalZone] = []
	for child: Node in room.get_node("%Thermals").get_children():
		if child is ThermalZone:
			zones.append(child as ThermalZone)

	check(zones.size() == 2, "a template's two zones are built (%d were)" % zones.size())
	var interior := room.get_interior_rect()
	for zone: ThermalZone in zones:
		check(
			interior.encloses(Rect2(zone.global_position, ZONE_SIZE * 0.0 + _size_of(zone))),
			"and lands inside the room's interior",
		)

	room.queue_free()
	await advance_physics(1)


## A zone in a room the player is not in must not tick. Ten rooms of zones is the same wasted work
## ten rooms of AI would be, and a vent announced into an empty room is worse than wasted.
func _test_zones_stop_with_the_room_they_are_in() -> void:
	var template := RoomTemplate.new()
	template.id = &"__test_thermal_active"
	template.thermal_zones = [Rect2i(4, 3, 6, 4)]

	var room: Room = ROOM_SCENE.instantiate()
	add_child(room)
	room.build(RoomPlan.new(0, Vector2i.ZERO, RoomTemplate.Type.COMBAT))
	room.plan.template = template
	room._build_thermal_zones()
	await advance_physics(1)

	var thermals := room.get_node("%Thermals") as Node2D
	room.set_active(false)
	check(
		thermals.process_mode == Node.PROCESS_MODE_DISABLED,
		"an inactive room's zones are switched off with its enemies",
	)
	room.set_active(true)
	check(
		thermals.process_mode == Node.PROCESS_MODE_INHERIT,
		"and switched back on when the player walks in",
	)

	room.queue_free()
	await advance_physics(1)


# --- Harness --------------------------------------------------------------------


## A bare zone and a player, with no room around either. The mechanic is about a rectangle and a
## robot; a floor would only add things that could explain a result some other way.
func _open_arena() -> Dictionary:
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)
	var zone := ThermalZone.spawn(arena, Rect2(Vector2(400.0, 400.0), ZONE_SIZE))
	await advance_physics(1)
	return {"arena": arena, "player": player, "zone": zone}


func _close(arena: Dictionary) -> void:
	(arena["arena"] as Node2D).queue_free()


## Holds the player still and reports a shot every frame, which is what the zone listens for. The
## position is reasserted each frame because the player is a physics body and would otherwise drift
## on whatever velocity the last frame left behind.
func _fire_for(frames: int, player: Player) -> void:
	var origin := player.global_position
	for _frame: int in frames:
		player.global_position = origin
		player.velocity = Vector2.ZERO
		EventBus.shot_fired.emit(Teams.Id.PLAYER, origin, Vector2.RIGHT)
		await get_tree().physics_frame


func _zone_centre(zone: ThermalZone) -> Vector2:
	return zone.global_position + _size_of(zone) * 0.5


func _size_of(zone: ThermalZone) -> Vector2:
	return zone._size

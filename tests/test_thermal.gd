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
	await _test_a_driven_zone_fills_on_its_own_clock()
	await _test_a_driven_zone_vents_once_and_goes()
	await _test_driving_changes_the_cause_and_not_the_language()
	_test_the_data_center_templates_are_authored_sanely()


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
##
## **The room is built somewhere other than the origin, and that is the entire point of this check.**
## It used to build at cell zero, and at cell zero this test could not fail: `ThermalZone.spawn`
## assigned `global_position` to a node that had not been parented yet — which is only ever its
## *local* position — so every zone was placed at its room's offset twice over, and twice zero is
## zero. Every arena in this suite sat at the origin, so nothing anywhere caught it.
##
## What it cost is the whole of the Data Center. A room at cell (2, 1) sits at (896, 224), and its
## floor patches were being built at (1808, 464) — most of a screen away, inside whichever room
## happened to be standing there. The zones were still drawn, so the floor looked like it had them;
## the rooms authored to teach the mechanic did not have them. Floor 3's signature idea had never
## once appeared in the rooms written for it.
##
## So the cell below is not incidental and must not be tidied back to zero. A placement test run at
## the origin is a placement test that cannot fail.
func _test_a_template_builds_its_zones_inside_the_room() -> void:
	var template := RoomTemplate.new()
	template.id = &"__test_thermal"
	template.type = RoomTemplate.Type.COMBAT
	# The second runs deliberately off the edge, which `get_tile_block_rect` clamps: a template with
	# a bad zone should draw a zone at the edge rather than half outside the room.
	template.thermal_zones = [Rect2i(4, 3, 6, 4), Rect2i(24, 10, 8, 6)]

	var plan := RoomPlan.new(0, Vector2i(2, 1), RoomTemplate.Type.COMBAT)
	var room: Room = ROOM_SCENE.instantiate()
	add_child(room)
	# Where the floor would put a room in that cell. `FloorController` positions rooms on the grid
	# before it builds them, and building at the origin is what hid the bug above.
	room.global_position = Vector2(plan.cell * Room.OUTER_SIZE)
	room.build(plan)
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


## The Data Center's own templates, checked as content rather than as code.
##
## A `.tres` with a typo in it does not fail to load — it loads with the mistyped property missing,
## and the first symptom is a room that generates without the thing it was authored for. These are
## the assertions that turn that into a failed check: the file parses, it is the type it claims, its
## zones are inside the room, and the rooms that are supposed to teach the mechanic actually carry
## it.
func _test_the_data_center_templates_are_authored_sanely() -> void:
	# id, expected type, and whether the room is meant to have zones in it.
	var expected: Array = [
		["data_cold_aisle", RoomTemplate.Type.START, false],
		["data_intake_row", RoomTemplate.Type.COMBAT, true],
		["data_hot_aisle", RoomTemplate.Type.COMBAT, true],
		["data_chiller_bank", RoomTemplate.Type.COMBAT, true],
		["data_grid_floor", RoomTemplate.Type.COMBAT, true],
		["data_busway", RoomTemplate.Type.COMBAT, true],
		["data_hot_containment", RoomTemplate.Type.COMBAT, true],
		["data_tape_library", RoomTemplate.Type.COMBAT, true],
		["data_cache_vault", RoomTemplate.Type.TREASURE, true],
		["data_core_arena", RoomTemplate.Type.BOSS, true],
	]

	var teaching_zones := 0
	var mastery_zones := 0
	for entry: Array in expected:
		var id: String = entry[0]
		var template := load("res://data/rooms/%s.tres" % id) as RoomTemplate
		if not require(template, "%s loads as a RoomTemplate" % id):
			continue

		check(template.id == StringName(id), "%s carries its own id" % id)
		check(template.type == entry[1], "%s is the room type it is used as" % id)
		check(
			(not template.thermal_zones.is_empty()) == bool(entry[2]),
			"%s %s throughput zones" % [id, "has" if entry[2] else "has no"],
		)
		check(
			template.min_floor == 3 and template.max_floor == 3,
			"%s is eligible on floor 3 and nowhere else" % id,
		)
		check(
			&"data_center" in template.floor_tags,
			"%s is tagged for the floor that uses it" % id,
		)

		# Every zone has to describe real ground. `get_tile_block_rect` clamps at build time, so an
		# off-edge zone is silently corrected in play — which is exactly why it is worth catching in
		# the file, where it is still a mistake somebody can fix.
		for zone: Rect2i in template.thermal_zones:
			check(
				zone.position.x >= 0 and zone.position.y >= 0
					and zone.end.x <= Room.INTERIOR_TILES.x and zone.end.y <= Room.INTERIOR_TILES.y,
				# `%s` rather than `%v`: `%v` takes vector types only, and a `Rect2i` is not one of
				# them. The message is built whether or not the check fails, so the wrong verb here
				# was eighteen engine errors in every green run — one per zone on the floor.
				"%s's zone %s fits inside the room without being clamped" % [id, zone],
			)

		# No enemy may be authored standing inside a zone. The floor charges for a habit the player
		# chooses; starting them mid-fight on hot ground would charge them for arriving.
		for spawn: Vector2i in template.enemy_spawns:
			for zone: Rect2i in template.thermal_zones:
				check(
					not zone.has_point(spawn),
					"%s does not start an enemy inside a zone (%v)" % [id, spawn],
				)

		if id == "data_intake_row":
			teaching_zones = template.thermal_zones.size()
		elif id == "data_grid_floor":
			mastery_zones = template.thermal_zones.size()

	# The teaching order, asserted rather than assumed: the room that introduces the mechanic shows
	# one zone, and the room that tests mastery shows several. A later edit that gave the teaching
	# room three zones would be teaching two things at once, which is the failure this floor's room
	# progression exists to avoid.
	check(teaching_zones == 1, "the teaching room shows exactly one zone (%d)" % teaching_zones)
	check(
		mastery_zones > teaching_zones,
		"and the mastery room shows more than it (%d)" % mastery_zones,
	)


# --- Driven zones ----------------------------------------------------------------
#
# The Cascade Failure boss puts zones on the floor that heat by themselves. Everything above this
# line is about the floor's own zones, where the player is the cause; everything below is about the
# one place in the game where they are not — and about the fact that nothing else changes.


## A driven zone ignores the player entirely: it fills whether they are there or not, whether they
## are firing or not, and whether they are moving or not.
##
## Three separate assertions rather than one, because "ignores the player" is three of the rules the
## room's zones live by, and a build that accidentally kept one of them would produce a boss whose
## hazards sometimes did not happen.
func _test_a_driven_zone_fills_on_its_own_clock() -> void:
	var arena := _open_session_arena()
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	# Nowhere near it, and not firing.
	player.global_position = Vector2(-500.0, -500.0)

	var zone := ThermalZone.spawn_vent(arena, Rect2(Vector2(400.0, 400.0), ZONE_SIZE), 0.5)
	if not require(zone, "a driven zone spawns"):
		arena.queue_free()
		await advance_physics(1)
		return

	check(zone.is_driven(), "and says it is driven")
	check(is_zero_approx(zone.get_heat()), "starting cold, so it can be walked out of")

	await advance_physics(15)
	check(
		zone.get_heat() > 0.3,
		"it heats with nobody in it and nobody firing (%.2f)" % zone.get_heat(),
	)

	arena.queue_free()
	await advance_physics(1)


## It vents once, costs what any vent costs, and frees itself — which is what stops the boss paving
## the arena, and is checked as a fact about the node rather than as a number in the boss's config.
func _test_a_driven_zone_vents_once_and_goes() -> void:
	var arena := _open_session_arena()
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)

	var rect := Rect2(Vector2(400.0, 400.0), ZONE_SIZE)
	var zone := ThermalZone.spawn_vent(arena, rect, 0.3)
	if not require(zone, "a driven zone spawns"):
		arena.queue_free()
		await advance_physics(1)
		return

	player.global_position = rect.position + rect.size * 0.5
	var health := player.get_health_component()
	var before := health.current

	var vents: Array[Rect2] = []
	var probe := func(vented: Rect2) -> void: vents.append(vented)
	EventBus.thermal_zone_vented.connect(probe)

	for _frame: int in 60:
		player.velocity = Vector2.ZERO
		player.global_position = rect.position + rect.size * 0.5
		await get_tree().physics_frame

	EventBus.thermal_zone_vented.disconnect(probe)

	check(vents.size() == 1, "a driven zone vents exactly once (%d)" % vents.size())
	check_near(
		before - health.current, ThermalZone.VENT_DAMAGE,
		"and costs one vent's worth of integrity, the same as any other", 0.01
	)
	check(not is_instance_valid(zone), "then frees itself, so the arena recovers on its own")

	arena.queue_free()
	await advance_physics(1)


## The claim the boss is built on: the colour means the same thing in its arena as it does in every
## room before it. Only the cause differs.
##
## Measured as the heat both kinds of zone are showing at the same fraction of their fill, which is
## the only thing the player can actually see. A driven zone that raced through the amber part of
## the ramp would be a hazard whose warning the floor had spent nine rooms teaching them to misread.
func _test_driving_changes_the_cause_and_not_the_language() -> void:
	var arena := _open_session_arena()
	var driven := ThermalZone.spawn_vent(arena, Rect2(Vector2.ZERO, ZONE_SIZE), 1.0)
	if not require(driven, "a driven zone spawns"):
		arena.queue_free()
		await advance_physics(1)
		return

	# Half of its one-second fill.
	await advance_physics(30)
	check(
		absf(driven.get_heat() - 0.5) < 0.1,
		"a driven zone is halfway up the ramp halfway through its fill (%.2f)" % driven.get_heat(),
	)
	check(
		driven.get_rect() == Rect2(Vector2.ZERO, ZONE_SIZE),
		"and covers exactly the ground it was given",
	)

	arena.queue_free()
	await advance_physics(1)


# --- Harness --------------------------------------------------------------------


## An arena that owns its own projectile container.
##
## `spawn_vent` parents into that container the way `CompileLane` does, so a hazard already climbing
## outlives the boss that started it — and falls back to the *current scene* where there is none.
## In a suite the current scene is the test runner, so an arena without a container does not take
## its zones with it when it is freed: they go on heating into the next check and vent there. Which
## is exactly what happened, and is the reason this helper exists rather than three plain Node2Ds.
func _open_session_arena() -> Node2D:
	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)
	return arena


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

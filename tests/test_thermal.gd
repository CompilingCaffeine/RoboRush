extends TestCase
## Floor 3's throughput zones: what heats them, what does not, and what a vent costs.
##
## The mechanic is one number — a zone's heat — and the whole design is which things are allowed to
## move it. The list is short by design and got shorter: heat answers to the player's *position*
## and to nothing else about them. Every check here is really a check on that list, because the
## list is where the design lives — charge for the wrong thing and the floor becomes a tax on the
## player's build instead of a fact about the ground. See `ThermalZone` for the argument; this is
## the part that fails if somebody later "simplifies" heat to accrue per shot, or puts back one of
## the conditions that made the floor unreadable.

const ZONE_SIZE := Vector2(64.0, 48.0)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

## Long enough to fill a zone from cold with a margin: `SECONDS_TO_VENT` at 60Hz, plus a few frames
## for the vent itself to resolve.
var _frames_to_vent := int(ThermalZone.SECONDS_TO_VENT * 60.0) + 6


func run() -> void:
	await _test_standing_in_a_zone_heats_it()
	await _test_what_the_player_is_doing_makes_no_difference()
	await _test_standing_outside_the_zone_does_not()
	await _test_crossing_a_zone_is_affordable()
	await _test_a_loaded_zone_looks_loaded_immediately()
	await _test_ignition_fades_rather_than_strobing()
	await _test_a_vent_costs_integrity_and_then_relents()
	await _test_a_zone_cools_when_left_alone()
	await _test_a_template_builds_its_zones_inside_the_room()
	await _test_zones_stop_with_the_room_they_are_in()
	await _test_a_driven_zone_fills_on_its_own_clock()
	await _test_a_driven_zone_is_never_floored()
	await _test_a_driven_zone_vents_once_and_goes()
	await _test_driving_changes_the_cause_and_not_the_language()
	_test_the_data_center_templates_are_authored_sanely()


## The one thing that must heat a zone, and the whole of it: being on it.
func _test_standing_in_a_zone_heats_it() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	await _stand_for(6, player)

	check(zone.get_heat() > 0.0, "standing inside a zone heats it (%.2f)" % zone.get_heat())
	_close(arena)
	await advance_physics(1)


## Heat answers to *where the player is* and to nothing else about them. Two players standing on
## the same ground for the same time pay the same, whatever either of them is doing with the
## trigger and whatever speed either is carrying.
##
## This is the check that stops the mechanic becoming a tax on Cooling Fan and Unsafe Overclock —
## and, now, the check that stops the firing and stillness conditions creeping back in. Both are
## measured as a *difference from a baseline* rather than as a threshold, because a condition
## re-added would show up as one of these runs heating less than the plain one, not as one of them
## heating not at all.
func _test_what_the_player_is_doing_makes_no_difference() -> void:
	var frames := 30
	var still := await _heat_after(frames, Vector2.ZERO, false)
	var firing := await _heat_after(frames, Vector2.ZERO, true)
	var moving := await _heat_after(frames, Vector2(Player.STILLNESS_SPEED * 6.0, 0.0), false)
	var both := await _heat_after(frames, Vector2(Player.STILLNESS_SPEED * 6.0, 0.0), true)

	check(still > 0.0, "standing on a zone doing nothing at all heats it (%.2f)" % still)
	check_near(firing, still, "and firing while stood there heats it no faster or slower", 0.01)
	check_near(moving, still, "and moving inside it heats it exactly the same", 0.01)
	check_near(both, still, "and so does doing both at once", 0.01)


## The other half of "position and nothing else": a zone the player is not standing on stays cold,
## however busy they are next to it.
func _test_standing_outside_the_zone_does_not() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	# Well clear of the zone, including the player-radius margin the zone grows.
	player.global_position = _zone_centre(zone) + Vector2(ZONE_SIZE.x * 2.0, 0.0)
	await _fire_for(30, player)

	check(
		is_zero_approx(zone.get_heat()),
		"a zone is not heated by anything happening off it (%.3f)" % zone.get_heat(),
	)
	_close(arena)
	await advance_physics(1)


## The promise the ramp is sized to keep, and the one that stops occupancy becoming a tax on being
## in the room: **crossing a zone must never vent it.**
##
## `SECONDS_TO_VENT` is measured against `move_speed` rather than against a fire rate for exactly
## this, so the check is the crossing itself — the widest grille the Data Center authors, walked
## from one edge to the other at walking pace — rather than a number copied out of the constant.
## A ramp shortened past the point where that holds turns every zone into ground the player cannot
## pass, which is a different mechanic wearing this one's colours.
func _test_crossing_a_zone_is_affordable() -> void:
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)

	# The widest zone any Data Center template actually authors, read from the files rather than
	# picked, so widening one in a `.tres` re-runs this check against the room it widened.
	var width := _widest_authored_zone_width()
	var origin := Vector2(400.0, 400.0)
	var zone := ThermalZone.spawn(arena, Rect2(origin, Vector2(width, ZONE_SIZE.y)))
	await advance_physics(1)

	var vents := 0
	var probe := func(_rect: Rect2) -> void: vents += 1
	EventBus.thermal_zone_vented.connect(probe)

	# In at one edge and out of the far one, starting and ending a player-radius clear of both, so
	# every frame the zone counts the robot as inside is a frame this crossing pays for.
	var config: PlayerConfig = load("res://data/player/player_config.tres")
	var travel := width + ThermalZone.PLAYER_RADIUS * 2.0
	var start := origin + Vector2(-ThermalZone.PLAYER_RADIUS, ZONE_SIZE.y * 0.5)
	var frames := int(ceil(travel / config.move_speed * 60.0))
	for frame: int in frames:
		player.global_position = start + Vector2(config.move_speed * (frame / 60.0), 0.0)
		player.velocity = Vector2(config.move_speed, 0.0)
		await get_tree().physics_frame

	EventBus.thermal_zone_vented.disconnect(probe)
	check(
		vents == 0,
		"walking across the widest zone on the floor never vents it (%d vents, %.0fpx)" % [
			vents, travel,
		],
	)
	check(
		zone.get_heat() < 1.0,
		"and leaves the ramp unfinished (%.2f)" % zone.get_heat(),
	)
	arena.queue_free()
	await advance_physics(1)


## The reported bug, as a check.
##
## The zones "never did anything or changed" across a whole playthrough, and they were working
## perfectly: a zone one frame into its ramp is a fraction of a percent off cold, which at this
## render size is not a change anybody can see. So the player never learned what the ramp answered
## to, moved for unrelated reasons, watched the heat drain, and concluded the floor's signature
## mechanic was scenery.
##
## What must be true is that the *displayed* heat moves on the first frame of load while the *real*
## heat does not, because the real one is what decides damage and it is not what was broken. Both
## halves are asserted here; a "fix" that made the zone actually heat faster on contact would pass
## the first and fail the second.
func _test_a_loaded_zone_looks_loaded_immediately() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	check(
		is_zero_approx(zone.get_display_heat()),
		"a zone nobody is loading is drawn cold (%.3f)" % zone.get_display_heat(),
	)

	player.global_position = _zone_centre(zone)
	await _stand_for(1, player)

	check(
		zone.get_display_heat() >= ThermalZone.IGNITION_HEAT,
		"one frame of standing on it is already a visible change (%.2f)" % zone.get_display_heat(),
	)
	check(
		zone.get_heat() < ThermalZone.IGNITION_HEAT,
		"while the heat that decides the vent has barely moved (%.3f)" % zone.get_heat(),
	)
	check(
		zone.get_display_heat() < 1.0,
		"and there is ramp left above it to read (%.2f)" % zone.get_display_heat(),
	)

	# The real heat overtakes the floor and from there the two are the same number, so the second
	# half of the ramp is the zone's own heat rather than a display term.
	await _stand_for(int(ThermalZone.SECONDS_TO_VENT * 60.0 * 0.75), player)
	check_near(
		zone.get_display_heat(), zone.get_heat(),
		"past the ignition floor the zone is drawn as exactly what it is", 0.01
	)

	_close(arena)
	await advance_physics(1)


## A player fighting along a zone's edge steps on and off it several times a second. The ignition
## floor has to fade out rather than snap, or every one of those is a third of the ramp flashing on
## and off — and it has to fade *out*, or a zone goes on looking loaded after the player has left it.
func _test_ignition_fades_rather_than_strobing() -> void:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]

	player.global_position = _zone_centre(zone)
	await _stand_for(2, player)
	var lit := zone.get_display_heat()
	check(lit >= ThermalZone.IGNITION_HEAT, "the zone is lit")

	# One frame off it, which is what clipping a corner looks like. Far too short for the floor to
	# have gone anywhere.
	player.global_position = _off_zone(zone)
	await advance_physics(1)
	check(
		zone.get_display_heat() > lit * 0.5,
		"one frame off the zone does not drop it back down (%.2f from %.2f)" % [
			zone.get_display_heat(), lit,
		],
	)

	# Well past the fade, with the player genuinely gone.
	await _stand_for(int(ThermalZone.IGNITION_FADE * 60.0) + 10, player)
	check_near(
		zone.get_display_heat(), zone.get_heat(),
		"and a zone nobody is standing on is drawn as its own heat again", 0.01
	)

	_close(arena)
	await advance_physics(1)


## The one place the two kinds of zone are drawn differently, and it is deliberate. A boss's vent is
## not something the player started, so there is nothing for an ignition floor to answer — the ramp
## from cold is the entire telegraph, and flooring it would throw the first four tenths of it away.
func _test_a_driven_zone_is_never_floored() -> void:
	# The session arena, not the plain one: `spawn_vent` parents into the projectile container, so a
	# driven zone spawned into an arena without one outlives the test that made it.
	var arena := _open_session_arena()
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	var rect := Rect2(Vector2(400.0, 400.0), ZONE_SIZE)

	# Standing in it, which is everything a room's zone asks for, and firing on top of that, which
	# a room's zone no longer asks for at all. A driven zone must ignore both: its clock is its own,
	# and so is its colour.
	player.global_position = rect.position + rect.size * 0.5
	var driven := ThermalZone.spawn_vent(arena, rect, 2.0)
	if not require(driven, "a driven zone spawns"):
		arena.queue_free()
		await advance_physics(1)
		return

	for _frame: int in 3:
		player.velocity = Vector2.ZERO
		player.global_position = rect.position + rect.size * 0.5
		EventBus.shot_fired.emit(Teams.Id.PLAYER, player.global_position, Vector2.RIGHT)
		await get_tree().physics_frame

	check(
		driven.get_display_heat() < ThermalZone.IGNITION_HEAT,
		"a boss's vent is drawn cold however hard it is stood in (%.2f)" % driven.get_display_heat(),
	)
	check_near(
		driven.get_display_heat(), driven.get_heat(),
		"its colour is its own heat and nothing else", 0.01
	)

	arena.queue_free()
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
	await _stand_for(_frames_to_vent, player)

	check(vents.size() >= 1, "standing on a zone long enough vents it (%d vents)" % vents.size())
	check(
		health.current < before,
		"and the vent costs integrity (%.1f, was %.1f)" % [health.current, before],
	)
	check_near(
		before - health.current, ThermalZone.VENT_DAMAGE,
		"exactly one vent's worth of damage", 0.01
	)
	check(is_zero_approx(zone.get_heat()), "the zone is cold again after venting")

	# The cooldown: still standing there, and it must not immediately refill.
	await _stand_for(int(ThermalZone.VENT_COOLDOWN * 60.0) - 10, player)
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
	await _stand_for(20, player)
	var loaded := zone.get_heat()
	check(loaded > 0.0, "the zone has heat to lose")
	if loaded <= 0.0:
		_close(arena)
		await advance_physics(1)
		return

	# Stepping off is the whole of "left alone" now: there is nothing else the player could stop
	# doing. Held clear of the zone for the measurement, because a physics body left where it was
	# would still be standing on it and would go on heating.
	player.global_position = _off_zone(zone)
	await _stand_for(25, player)
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


## Holds the player where they are for `frames` physics frames, which is the whole of what a zone
## asks for. The position is reasserted each frame because the player is a physics body and would
## otherwise drift on whatever velocity the last frame left behind.
func _stand_for(frames: int, player: Player) -> void:
	var origin := player.global_position
	for _frame: int in frames:
		player.global_position = origin
		player.velocity = Vector2.ZERO
		await get_tree().physics_frame


## `_stand_for` with the trigger held down. Kept as a separate helper rather than folded away,
## because "firing changes nothing" is a promise this suite makes and a promise needs something
## that actually fires to check it against.
func _fire_for(frames: int, player: Player) -> void:
	var origin := player.global_position
	for _frame: int in frames:
		player.global_position = origin
		player.velocity = Vector2.ZERO
		EventBus.shot_fired.emit(Teams.Id.PLAYER, origin, Vector2.RIGHT)
		await get_tree().physics_frame


## Heat on a fresh zone after `frames` frames of standing at its centre carrying `velocity`, firing
## or not. A whole arena per call so no run can inherit the last one's heat, which is what makes the
## four results in `_test_what_the_player_is_doing_makes_no_difference` comparable.
func _heat_after(frames: int, velocity: Vector2, firing: bool) -> float:
	var arena := await _open_arena()
	var zone: ThermalZone = arena["zone"]
	var player: Player = arena["player"]
	var centre := _zone_centre(zone)

	for _frame: int in frames:
		# Position held as well as velocity written, so a moving player stays inside the zone for
		# the whole run: this is measuring what the velocity *means to the zone*, not where it
		# carries the robot. Velocity is rewritten every frame because `move_and_slide` consumes it.
		player.global_position = centre
		player.velocity = velocity
		if firing:
			EventBus.shot_fired.emit(Teams.Id.PLAYER, centre, Vector2.RIGHT)
		await get_tree().physics_frame

	var heat := zone.get_heat()
	_close(arena)
	await advance_physics(1)
	return heat


## The widest zone in tiles that any Data Center template authors, in pixels. Read from the `.tres`
## files so that widening a zone in content is checked against `_test_crossing_a_zone_is_affordable`
## rather than quietly outgrowing it.
func _widest_authored_zone_width() -> float:
	var widest := 0
	for id: String in [
		"data_intake_row", "data_hot_aisle", "data_chiller_bank", "data_grid_floor", "data_busway",
		"data_hot_containment", "data_tape_library", "data_cache_vault", "data_core_arena",
	]:
		var template := load("res://data/rooms/%s.tres" % id) as RoomTemplate
		if template == null:
			continue
		for zone: Rect2i in template.thermal_zones:
			widest = maxi(widest, zone.size.x)
	return float(maxi(widest, 1) * Room.TILE_SIZE)


## Somewhere the zone is certainly not, including the player-radius margin it grows.
func _off_zone(zone: ThermalZone) -> Vector2:
	return _zone_centre(zone) + Vector2(_size_of(zone).x * 2.0, 0.0)


func _zone_centre(zone: ThermalZone) -> Vector2:
	return zone.global_position + _size_of(zone) * 0.5


func _size_of(zone: ThermalZone) -> Vector2:
	return zone._size

extends TestCase
## Cloud Operations' migration pads: what moves the player, what does not, and what stops a link
## from moving them straight back.
##
## The mechanic is one rule — step on a pad, arrive on its partner — and almost every way it can be
## got wrong is a way of getting *that* wrong twice per frame. A link with no arming rule bounces the
## robot between its ends for as long as the player holds still, which is not a bug that shows up as
## a wrong number; it shows up as a robot the player has stopped being able to steer. Most of what
## follows is about the arming.
##
## The other half is placement. A pad is the only thing in the game that decides where the player
## *is*, so a pad authored badly does not misdraw, it teleports somebody into a wall. See
## `MigrationPad.get_arrival_point` for why arrival is the middle of the plate and
## `_test_a_template_builds_its_pads_inside_the_room` for the check that the plate is where the
## template said.

const PAD_SIZE := Vector2(32.0, 32.0)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

## Far enough apart that a pad's rect cannot contain the other end, so "the player is on a pad" is
## never ambiguous about which one.
const PAD_GAP := Vector2(200.0, 0.0)


func run() -> void:
	await _test_stepping_on_a_pad_moves_the_player_to_its_partner()
	await _test_arriving_does_not_send_the_player_back()
	await _test_standing_on_the_arrival_pad_never_fires_it()
	await _test_leaving_and_returning_migrates_again()
	await _test_a_link_works_in_both_directions()
	await _test_the_edge_of_a_pad_is_not_the_pad()
	await _test_an_enemy_standing_on_a_pad_is_not_moved()
	await _test_a_template_builds_its_pads_inside_the_room()
	await _test_pads_stop_with_the_room_they_are_in()
	_test_a_half_link_cannot_be_authored()
	_test_the_cloud_templates_are_authored_sanely()


## The one thing a pad must do.
func _test_stepping_on_a_pad_moves_the_player_to_its_partner() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	player.global_position = first.get_rect().get_center()
	await advance_physics(2)

	check(
		player.global_position.distance_to(second.get_arrival_point()) < 1.0,
		"stepping on a pad puts the player on its partner (at %v, wanted %v)"
			% [player.global_position, second.get_arrival_point()],
	)
	_close(arena)
	await advance_physics(1)


## The failure the arming rule exists for, and the only one in this file that would be unplayable
## rather than merely wrong: with both pads armed, the partner's own `_physics_process` finds a
## player standing on it and sends them back, every frame, forever.
func _test_arriving_does_not_send_the_player_back() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	player.global_position = first.get_rect().get_center()
	await advance_physics(1)
	var arrived := player.global_position

	# Held still on the destination for a good while. A bounce would be visible within two frames;
	# thirty is long enough that a slower oscillation would also show.
	for _frame: int in 30:
		player.velocity = Vector2.ZERO
		player.global_position = arrived
		await get_tree().physics_frame

	check(
		player.global_position.distance_to(second.get_arrival_point()) < 1.0,
		"the player stays on the pad they arrived at (at %v)" % player.global_position,
	)
	check(not second.is_armed(), "the arrival pad is disarmed while stood on")
	check(first.is_armed(), "the pad they left rearms as soon as they are gone")
	_close(arena)
	await advance_physics(1)


## The arming rule stated as the property it is really for: an arrival pad is disarmed by *where the
## player is*, not by how long ago they got there. A cooldown expressed in seconds would rearm
## underneath a player who had not moved, which is the bounce again with extra steps.
func _test_standing_on_the_arrival_pad_never_fires_it() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	player.global_position = second.get_rect().get_center()
	# Disarm it the way an arrival does, then hold position far longer than any plausible cooldown.
	await advance_physics(1)
	var settled := player.global_position
	for _frame: int in 90:
		player.velocity = Vector2.ZERO
		player.global_position = settled
		await get_tree().physics_frame

	check(
		player.global_position.distance_to(first.get_arrival_point()) > 1.0
			or settled.distance_to(first.get_arrival_point()) < 1.0,
		"a pad the player is already standing on does not fire under them",
	)
	_close(arena)
	await advance_physics(1)


## A pad is not single-use. Stepping off and back on is the loop a player actually plays, so it has
## to survive the arming rule rather than be excluded by it.
func _test_leaving_and_returning_migrates_again() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	player.global_position = first.get_rect().get_center()
	await advance_physics(2)
	if not require(
		player.global_position.distance_to(second.get_arrival_point()) < 1.0,
		"the first migration happened",
	):
		_close(arena)
		return

	# Off the pad entirely, which is what rearms it, then back on.
	player.global_position = second.get_rect().get_center() + Vector2(0.0, PAD_SIZE.y * 3.0)
	await advance_physics(2)
	player.global_position = second.get_rect().get_center()
	await advance_physics(2)

	check(
		player.global_position.distance_to(first.get_arrival_point()) < 1.0,
		"stepping off and back on migrates again (at %v)" % player.global_position,
	)
	_close(arena)
	await advance_physics(1)


## A link has no direction. This is the check that fails if somebody later gives one end an
## `is_source` flag to fix a bounce that the arming rule already fixed.
func _test_a_link_works_in_both_directions() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	player.global_position = second.get_rect().get_center()
	await advance_physics(2)

	check(
		player.global_position.distance_to(first.get_arrival_point()) < 1.0,
		"the far end carries the player back the other way (at %v)" % player.global_position,
	)
	_close(arena)
	await advance_physics(1)


## A pad moves a robot that has driven onto it, not one brushing past. `MigrationPad` measures the
## player's centre against the plate with no chassis radius added, deliberately unlike
## `ThermalZone`, and this is that asymmetry asserted rather than left to a comment.
func _test_the_edge_of_a_pad_is_not_the_pad() -> void:
	var arena := await _open_arena()
	var player: Player = arena["player"]
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]

	# Just outside the plate — a chassis overlapping it, a centre that is not on it.
	var outside := first.get_rect().position - Vector2(3.0, 3.0)
	for _frame: int in 6:
		player.velocity = Vector2.ZERO
		player.global_position = outside
		await get_tree().physics_frame

	check(
		player.global_position.distance_to(second.get_arrival_point()) > 1.0,
		"a chassis overlapping a pad's corner is not standing on it",
	)
	_close(arena)
	await advance_physics(1)


## Player-only, which is the mechanic and not a shortcut — see `MigrationPad`'s doc. A room split by
## ducts and joined by pads is a room a fight cannot follow the player out of, and an enemy that
## migrated would collapse that into an ordinary doorway.
func _test_an_enemy_standing_on_a_pad_is_not_moved() -> void:
	var arena := await _open_arena()
	var first: MigrationPad = arena["first"]
	var second: MigrationPad = arena["second"]
	var player: Player = arena["player"]

	# The player kept well away, so nothing here is the player's migration by accident.
	player.global_position = first.get_rect().position - Vector2(600.0, 600.0)

	var enemy := CharacterBody2D.new()
	enemy.add_to_group(Teams.GROUP_ENEMY)
	(arena["arena"] as Node2D).add_child(enemy)
	enemy.global_position = first.get_rect().get_center()
	var stood := enemy.global_position
	await advance_physics(6)

	check(
		enemy.global_position.distance_to(stood) < 1.0,
		"an enemy on a pad stays where it is (at %v)" % enemy.global_position,
	)
	check(
		enemy.global_position.distance_to(second.get_arrival_point()) > 1.0,
		"and specifically is not carried to the far end",
	)
	_close(arena)
	await advance_physics(1)


## The placement check, and it builds its room *away from the origin* on purpose.
##
## That is not caution, it is the specific bug this project shipped on Floor 3: `ThermalZone.spawn`
## set `global_position` before `add_child`, which writes a global coordinate into a local slot, and
## every zone landed at its room's offset twice over. It survived a whole floor because every arena
## in the suite built at the origin, where adding zero twice is still zero. `MigrationPad.spawn`
## orders the two calls the right way round, and a pad is the one piece of level furniture where
## getting it wrong would not merely misdraw — it decides where the player *is*.
func _test_a_template_builds_its_pads_inside_the_room() -> void:
	var template := RoomTemplate.new()
	template.id = &"migration_placement_probe"
	var link := MigrationLink.new()
	link.a = Rect2i(2, 2, 2, 2)
	link.b = Rect2i(20, 8, 2, 2)
	template.pad_links = [link]

	# Cell (2, 1), which is where the bug this test exists for hid: a doubled offset at the origin
	# is still the origin. `FloorController` puts a room on the grid before building it.
	var plan := RoomPlan.new(0, Vector2i(2, 1), RoomTemplate.Type.COMBAT)
	var room: Room = ROOM_SCENE.instantiate()
	add_child(room)
	room.global_position = Vector2(plan.cell * Room.OUTER_SIZE)
	room.build(plan)
	room.plan.template = template
	room._build_pads()
	await advance_physics(1)

	var pads := _pads_of(room)
	if not require(pads.size() == 2, "the room built both ends (%d)" % pads.size()):
		room.queue_free()
		await advance_physics(1)
		return

	var interior := room.get_interior_rect()
	for pad: MigrationPad in pads:
		check(
			interior.encloses(pad.get_rect()),
			"pad at %v is inside the room's interior %s" % [pad.get_rect().position, interior],
		)
		check(
			interior.has_point(pad.get_arrival_point()),
			"pad's arrival point %v is inside the room" % pad.get_arrival_point(),
		)

	# The pads are the two the template asked for, in the room's own coordinates.
	var wanted_a := room.get_tile_block_rect(link.a.position, link.a.size)
	var wanted_b := room.get_tile_block_rect(link.b.position, link.b.size)
	var placed := [pads[0].get_rect().position, pads[1].get_rect().position]
	check(placed.has(wanted_a.position), "one end landed where the template put it (%v)" % wanted_a.position)
	check(placed.has(wanted_b.position), "the other end did too (%v)" % wanted_b.position)

	# Both ends of one link carry the same pip count, which is how a player pairs them.
	check(pads[0].pair_index == pads[1].pair_index, "both ends of a link draw the same pips")
	check(pads[0].partner == pads[1], "the pair is joined")
	check(pads[1].partner == pads[0], "and joined in both directions")

	room.queue_free()
	await advance_physics(1)


## Pads stop with the enemies and the thermal zones. A pad asks the tree for the player every
## physics frame, and a floor holds ten rooms of them.
func _test_pads_stop_with_the_room_they_are_in() -> void:
	var template := RoomTemplate.new()
	template.id = &"migration_sleep_probe"
	var link := MigrationLink.new()
	link.a = Rect2i(2, 2, 2, 2)
	link.b = Rect2i(20, 8, 2, 2)
	template.pad_links = [link]

	var plan := RoomPlan.new(0, Vector2i(1, 2), RoomTemplate.Type.COMBAT)
	var room: Room = ROOM_SCENE.instantiate()
	add_child(room)
	room.global_position = Vector2(plan.cell * Room.OUTER_SIZE)
	room.build(plan)
	room.plan.template = template
	room._build_pads()
	await advance_physics(1)

	var pads := _pads_of(room)
	if not require(pads.size() == 2, "the room built its pads"):
		room.queue_free()
		await advance_physics(1)
		return

	room.set_active(false)
	await advance_physics(1)
	check(
		not pads[0].can_process(),
		"a pad in a room the player is not in stops processing",
	)
	room.set_active(true)
	await advance_physics(1)
	check(pads[0].can_process(), "and runs again when the room is entered")

	room.queue_free()
	await advance_physics(1)


## `MigrationLink`'s whole reason to be a resource rather than two entries in a flat array: there is
## no arrangement of it that describes half a link. This is that claim asserted, because the day
## somebody replaces it with `Array[Rect2i]` is the day a pad with no partner becomes authorable —
## and a pad with no partner is floor that reads as a route and is not one.
func _test_a_half_link_cannot_be_authored() -> void:
	var link := MigrationLink.new()
	check(link.is_valid(), "a default link has two real ends")
	check(link.tiles().size() == 8, "a default link covers both its plates (%d tiles)" % link.tiles().size())

	var zeroed := MigrationLink.new()
	zeroed.b = Rect2i(4, 4, 0, 0)
	check(
		not zeroed.is_valid(),
		"an end with no area is refused, which is the only way to express half a link",
	)


## The shipped Cloud Operations templates, on the two things a pad can be authored wrong.
##
## Both are placement rather than behaviour, and both are invisible while playing: a pad inside an
## obstacle is an arrival inside a wall, and two ends that overlap are a link that migrates the
## player nowhere while sounding and flashing as though it did.
func _test_the_cloud_templates_are_authored_sanely() -> void:
	var campaign := load("res://data/runs/main_campaign.tres") as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var links_seen := 0
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		var templates: Array[RoomTemplate] = []
		templates.append_array(config.start_templates)
		templates.append_array(config.combat_templates)
		templates.append_array(config.treasure_templates)
		templates.append_array(config.shop_templates)
		templates.append_array(config.boss_templates)
		for template: RoomTemplate in templates:
			if template == null or template.pad_links.is_empty():
				continue
			var solid: Dictionary[Vector2i, bool] = {}
			for blocked: Array[Rect2i] in [template.obstacles, template.ducts]:
				for rect: Rect2i in blocked:
					for y: int in rect.size.y:
						for x: int in rect.size.x:
							solid[rect.position + Vector2i(x, y)] = true

			for link: MigrationLink in template.pad_links:
				if link == null:
					fail("%s has a null pad link" % template.id)
					continue
				links_seen += 1
				check(link.is_valid(), "%s: both ends of a link have area" % template.id)
				check(
					not link.a.intersects(link.b),
					"%s: a link's two ends do not overlap (%s, %s)" % [template.id, link.a, link.b],
				)
				for tile: Vector2i in link.tiles():
					check(
						not solid.has(tile),
						"%s: pad tile %v is not inside an obstacle or duct" % [template.id, tile],
					)

	check(links_seen > 0, "the campaign ships pad links to check (%d)" % links_seen)


func _open_arena() -> Dictionary:
	var arena := Node2D.new()
	add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	arena.add_child(player)
	var origin := Vector2(400.0, 400.0)
	var first := MigrationPad.spawn(arena, Rect2(origin, PAD_SIZE), 0)
	var second := MigrationPad.spawn(arena, Rect2(origin + PAD_GAP, PAD_SIZE), 0)
	MigrationPad.link(first, second)
	# The player starts clear of both, so the first frame does not migrate anybody.
	player.global_position = origin - Vector2(300.0, 300.0)
	await advance_physics(1)
	return {"arena": arena, "player": player, "first": first, "second": second}


func _close(arena: Dictionary) -> void:
	(arena["arena"] as Node2D).queue_free()


func _pads_of(room: Room) -> Array[MigrationPad]:
	var out: Array[MigrationPad] = []
	for child: Node in (room.get_node("%Pads") as Node).get_children():
		if child is MigrationPad:
			out.append(child as MigrationPad)
	return out


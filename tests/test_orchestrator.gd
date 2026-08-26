extends TestCase
## Cloud Operations' boss: what damage does, what it does not do, and the one thing that does.
##
## The fight's whole shape is that **damage cannot kill it**. The pool fills, the boss fails over to
## another plate, the pool resets, and that loop runs forever at any damage per second — the only
## thing that ends it is the player standing on the plate it is migrating to. That makes this suite
## unlike the other three boss suites in one way worth stating: most of what follows asserts things
## the fight refuses to do. A change that turned the pool into a health bar would make the boss
## easier, would look like a simplification in a diff, and would delete the entire fight. Six of the
## checks below exist to fail on it.
##
## The other half is the telegraph, which is the player's only information and their whole budget.
## The target is chosen when the pool empties and must not move afterwards — a boss that re-picked on
## resolution would make the run across the arena pointless and would do it invisibly, which is the
## one failure mode nobody could report.

const BOSS_SCENE := preload("res://scenes/bosses/orchestrator.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const BOSS_CONFIG_PATH := "res://data/bosses/orchestrator.tres"
const ENCOUNTER_PATH := "res://data/bosses/orchestrator_encounter.tres"
const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"

## The arena every boss in this project is measured in: one room's interior.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## The telegraph the suite runs at, wound down from the shipped 1.9s so a failover resolves in a
## handful of frames rather than in two real seconds. Everything timed is derived from this rather
## than given its own number, for the reason `test_cascade_failure` winds its vent clocks by one
## ratio: what the fight's fairness rests on is the *relationships* between these durations, and a
## suite that shortened one of them alone would be measuring a fight nobody plays.
const TEST_TELEGRAPH := 0.2

var _config: OrchestratorConfig
var _arena_node: Node2D
var _boss: Orchestrator
var _player: Player
var _defeated := 0


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as OrchestratorConfig
	if not require(_config, "orchestrator.tres loads as an OrchestratorConfig"):
		return

	_test_the_encounter_is_complete()
	_test_the_config_is_coherent()
	await _test_damage_fills_the_pool_and_does_not_kill()
	await _test_a_full_pool_commits_to_a_named_plate()
	await _test_the_target_does_not_move_once_announced()
	await _test_an_undenied_failover_moves_the_boss_and_resets_the_pool()
	await _test_standing_on_the_target_denies_the_failover()
	await _test_a_denial_stuns_it()
	await _test_three_denials_end_the_fight()
	await _test_no_amount_of_damage_alone_can_kill_it()
	await _test_the_plates_are_inside_the_arena_and_distinct()
	await _test_it_needs_nothing_from_the_room_it_is_in()
	_test_every_floor_can_draw_it()


## The four pieces of text the HUD says on this boss's behalf, and the scene it names.
func _test_the_encounter_is_complete() -> void:
	var encounter := load(ENCOUNTER_PATH) as BossEncounter
	if not require(encounter, "orchestrator_encounter.tres loads as a BossEncounter"):
		return
	check(encounter.is_valid(), "the encounter is valid")
	check(encounter.id == &"orchestrator", "its id is 'orchestrator' (%s)" % encounter.id)
	# The name is not `failover`, and that is deliberate rather than incidental: the game ships an
	# *item* with that id (a death save), and two things sharing one would collide in a run's records
	# and put the same word in the HUD for a boss banner and a pickup banner.
	var item := load("res://data/items/failover.tres") as ItemConfig
	if item != null:
		check(
			encounter.id != item.id,
			"and does not collide with the Failover item's id ('%s')" % item.id,
		)
	check(
		encounter.phase_banners.size() == _config.generations,
		"it announces one banner per generation (%d for %d)"
			% [encounter.phase_banners.size(), _config.generations],
	)


## The shipped numbers, on the relationships the fight rests on rather than on their values.
func _test_the_config_is_coherent() -> void:
	check(_config.generations >= 2, "there is more than one generation to take (%d)" % _config.generations)
	check(_config.plate_count >= 3, "and at least three plates (%d)" % _config.plate_count)
	check(
		_config.plate_count > 2,
		"more than two plates, so the destination is something to read rather than the only "
			+ "other one",
	)
	check(_config.pool_per_generation > 0.0, "the pool is a real amount of damage")
	check(_config.telegraph_seconds > 0.0, "the telegraph is a real window")
	# The one inequality in the fight. A telegraph that fired faster than the boss's own volleys
	# would be a countdown the player could not act inside of.
	check(
		_config.telegraph_seconds > _config.telegraph_volley_interval,
		"and is longer than the volley interval it fires at (%.2f > %.2f)"
			% [_config.telegraph_seconds, _config.telegraph_volley_interval],
	)
	check(
		_config.telegraph_volley_interval < _config.volley_interval,
		"announcing a failover costs the player more fire, not less (%.2f < %.2f)"
			% [_config.telegraph_volley_interval, _config.volley_interval],
	)


## Damage goes into the pool. Nothing else.
func _test_damage_fills_the_pool_and_does_not_kill() -> void:
	await _open(Vector2(40.0, 40.0))

	var before := _boss.get_health_ratio()
	_hurt(_config.pool_per_generation * 0.5)
	await advance_physics(1)

	check(_boss.get_health_ratio() < before, "damage moves the bar (%.3f)" % _boss.get_health_ratio())
	check(
		_boss.get_generations_left() == _config.generations,
		"and takes no generation on its own (%d left)" % _boss.get_generations_left(),
	)
	check(not _boss.is_telegraphing(), "and half a pool announces nothing")
	check(_defeated == 0, "and nothing is dead")
	await _close()


## Filling the pool is what forces the fight forward.
func _test_a_full_pool_commits_to_a_named_plate() -> void:
	await _open(Vector2(40.0, 40.0))

	var standing := _boss.get_plate()
	_hurt(_config.pool_per_generation)
	await advance_physics(1)

	check(_boss.is_telegraphing(), "a full pool commits to a failover")
	check(
		_boss.get_target_plate() != standing,
		"to a plate it is not already on (target %d, standing %d)"
			% [_boss.get_target_plate(), standing],
	)
	check(
		_boss.get_target_plate() >= 0 and _boss.get_target_plate() < _config.plate_count,
		"and to a plate that exists (%d)" % _boss.get_target_plate(),
	)
	check(
		_boss.get_plate() == standing,
		"and has not moved yet — the telegraph comes first",
	)
	await _close()


## The target is decided when the pool empties, not when the telegraph ends. This is the check that
## fails if somebody later re-picks on resolution, which would make the run across the room
## pointless without changing anything a player could see.
func _test_the_target_does_not_move_once_announced() -> void:
	await _open(Vector2(40.0, 40.0))

	_hurt(_config.pool_per_generation)
	await advance_physics(1)
	var announced := _boss.get_target_plate()
	if not require(announced >= 0, "a failover was announced"):
		await _close()
		return

	# More damage during the telegraph, which is exactly what a player does — they are shooting it
	# while running.
	for _step: int in 4:
		_hurt(_config.pool_per_generation)
		await advance_physics(1)
		check(
			_boss.get_target_plate() == announced,
			"the target stays %d under further damage (is %d)"
				% [announced, _boss.get_target_plate()],
		)
	await _close()


## Nobody there: it arrives, and the damage that forced it is gone.
func _test_an_undenied_failover_moves_the_boss_and_resets_the_pool() -> void:
	await _open(Vector2(40.0, 40.0))

	_hurt(_config.pool_per_generation)
	await advance_physics(1)
	var target := _boss.get_target_plate()
	var generations := _boss.get_generations_left()
	if not require(target >= 0, "a failover was announced"):
		await _close()
		return

	# The player is parked in a corner, deliberately nowhere near any plate.
	await _resolve_telegraph()

	check(_boss.get_plate() == target, "an undenied failover arrives at its target (%d)" % _boss.get_plate())
	check(not _boss.is_telegraphing(), "and stops telegraphing")
	check(
		_boss.get_generations_left() == generations,
		"and costs no generation (%d left)" % _boss.get_generations_left(),
	)
	check(not _boss.is_stunned(), "and leaves it open to nothing")
	check(_defeated == 0, "and nothing is dead")

	var body := _boss.get_parts()
	if not body.is_empty():
		check(
			body[0].global_position.distance_to(_boss.get_plate_positions()[target]) < 1.0,
			"and the body is actually on the plate it moved to",
		)
	await _close()


## The fight. Stand where it is going and the load has nowhere to go.
func _test_standing_on_the_target_denies_the_failover() -> void:
	await _open(Vector2(40.0, 40.0))

	_hurt(_config.pool_per_generation)
	await advance_physics(1)
	var target := _boss.get_target_plate()
	var standing := _boss.get_plate()
	var generations := _boss.get_generations_left()
	if not require(target >= 0, "a failover was announced"):
		await _close()
		return

	_stand_on(target)
	await _resolve_telegraph()

	check(
		_boss.get_generations_left() == generations - 1,
		"standing on the destination takes a generation (%d -> %d)"
			% [generations, _boss.get_generations_left()],
	)
	check(_boss.get_plate() == standing, "and the boss does not move (%d)" % _boss.get_plate())
	check(not _boss.is_telegraphing(), "and the failover is over")
	await _close()


## The reward for the run across the room, and the only window in the fight where damage is free.
func _test_a_denial_stuns_it() -> void:
	await _open(Vector2(40.0, 40.0))

	_hurt(_config.pool_per_generation)
	await advance_physics(1)
	var target := _boss.get_target_plate()
	if not require(target >= 0, "a failover was announced"):
		await _close()
		return
	_stand_on(target)
	await _resolve_telegraph()

	if not require(_boss.is_stunned(), "a denial stuns it"):
		await _close()
		return

	# Damage during the stun must still land — the window is the point of denying one.
	var before := _boss.get_health_ratio()
	_hurt(_config.pool_per_generation * 0.4)
	await advance_physics(1)
	check(_boss.get_health_ratio() < before, "and damage during the stun still counts")
	# ...but it must not announce a new failover while stunned, or the window is not a window.
	check(not _boss.is_telegraphing(), "and it cannot start a new failover while stunned")
	await _close()


## Three denials, and that is the fight.
func _test_three_denials_end_the_fight() -> void:
	await _open(Vector2(40.0, 40.0))

	var denied := 0
	for _attempt: int in _config.generations:
		if _boss == null or _defeated > 0:
			break
		_hurt(_config.pool_per_generation)
		await advance_physics(1)
		var target := _boss.get_target_plate()
		if target < 0:
			continue
		_stand_on(target)
		await _resolve_telegraph()
		denied += 1
		# Out of the stun before the next push, so each denial is its own event.
		await advance_physics(int(_config.denial_stun_seconds * 60.0) + 2)

	check(
		denied == _config.generations,
		"%d denials were available and taken (%d)" % [_config.generations, denied],
	)
	check(_defeated == 1, "the boss is defeated, exactly once (%d)" % _defeated)
	await _close()


## The claim the whole fight rests on, asserted directly: no quantity of damage kills it.
##
## Twenty pools' worth, which is far past what the worst legal build in the game does in the time
## this takes. Every one of those hits forces a failover the player is not there to deny, so the
## boss simply walks the ring — which is the correct behaviour and reads as a bug to anybody who
## has not read the fight. That is why it is written down here.
func _test_no_amount_of_damage_alone_can_kill_it() -> void:
	await _open(Vector2(40.0, 40.0))

	for _step: int in 20:
		_hurt(_config.pool_per_generation)
		await _resolve_telegraph()

	check(_defeated == 0, "twenty pools of damage kill nothing (%d deaths)" % _defeated)
	check(
		_boss.get_generations_left() == _config.generations,
		"and take no generation (%d left)" % _boss.get_generations_left(),
	)
	check(_boss != null and is_instance_valid(_boss), "the boss is still standing")
	await _close()


## The plates are its own, and they are somewhere legal.
func _test_the_plates_are_inside_the_arena_and_distinct() -> void:
	await _open(Vector2(40.0, 40.0))

	var plates := _boss.get_plate_positions()
	check(plates.size() == _config.plate_count, "it lays out %d plates (%d)" % [_config.plate_count, plates.size()])
	for index: int in plates.size():
		check(ARENA.has_point(plates[index]), "plate %d is inside the arena (%v)" % [index, plates[index]])
		check(
			ARENA.encloses(_boss.get_plate_rect(index)),
			"and its whole square is (%s)" % _boss.get_plate_rect(index),
		)
	# Distinct, and far enough apart that standing on one is never standing on another — otherwise a
	# denial could be granted for being in the wrong place.
	for a: int in plates.size():
		for b: int in plates.size():
			if a >= b:
				continue
			check(
				not _boss.get_plate_rect(a).intersects(_boss.get_plate_rect(b)),
				"plates %d and %d do not overlap" % [a, b],
			)
	await _close()


## It brings its own floor. The boss is eligible on every floor in the campaign, including three that
## have never heard of a migration pad, so the fight must not need the arena to contain one.
func _test_it_needs_nothing_from_the_room_it_is_in() -> void:
	await _open(Vector2(40.0, 40.0))
	# The arena this suite builds has no room, no template, and therefore no pads at all — which is
	# the condition being asserted. If the fight needed one, everything above would already have
	# failed, so what this adds is the statement of *why* those pass.
	check(
		_boss.get_plate_positions().size() == _config.plate_count,
		"the boss supplies its own plates in an arena with no pads in it",
	)
	# And it fights: a boss that quietly did nothing without pads would satisfy the check above.
	_hurt(_config.pool_per_generation)
	await advance_physics(1)
	check(_boss.is_telegraphing(), "and runs its failover loop there")
	await _close()


## Every floor lists it, which is what stops the campaign's last fight being the same fight every
## run. With the Orchestrator confined to floor 4, four floors needing four distinct bosses would
## have exactly one legal dealing — the Data Center's note about Cascade Failure, one floor later.
func _test_every_floor_can_draw_it() -> void:
	var campaign := load(CAMPAIGN_PATH) as RunDefinition
	if not require(campaign, "the campaign loads"):
		return

	var listing := 0
	for index: int in campaign.size():
		var config := campaign.load_floor(index)
		if config == null:
			continue
		var found := false
		for encounter: BossEncounter in config.boss_pool:
			if encounter != null and encounter.id == &"orchestrator":
				found = true
		if found:
			listing += 1
		check(found, "floor %d can draw the Orchestrator" % (index + 1))
	check(listing == campaign.size(), "every floor can (%d of %d)" % [listing, campaign.size()])


# --- Harness ------------------------------------------------------------------


func _open(player_offset: Vector2) -> void:
	_defeated = 0
	_arena_node = Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	_arena_node.add_child(container)
	add_child(_arena_node)

	_player = PLAYER_SCENE.instantiate()
	_player.position = ARENA.position + player_offset
	_arena_node.add_child(_player)

	_boss = BOSS_SCENE.instantiate()
	var fast: OrchestratorConfig = _config.duplicate()
	# One ratio, applied to everything timed. See TEST_TELEGRAPH.
	var winding := TEST_TELEGRAPH / maxf(_config.telegraph_seconds, 0.001)
	fast.telegraph_seconds = TEST_TELEGRAPH
	fast.denial_stun_seconds = _config.denial_stun_seconds * winding
	fast.volley_interval = _config.volley_interval * winding
	fast.telegraph_volley_interval = _config.telegraph_volley_interval * winding
	_boss.config = fast
	_arena_node.add_child(_boss)

	EventBus.boss_defeated.connect(_on_defeated)
	await advance_physics(1)
	_boss.begin(ARENA)
	await advance_physics(1)


func _close() -> void:
	if EventBus.boss_defeated.is_connected(_on_defeated):
		EventBus.boss_defeated.disconnect(_on_defeated)
	_arena_node.queue_free()
	_boss = null
	_player = null
	await advance_physics(2)


func _on_defeated(_boss_node: Node) -> void:
	_defeated += 1


## Damages the boss the way a projectile does: through its part, which forwards it.
func _hurt(amount: float) -> void:
	var parts := _boss.get_parts()
	if not parts.is_empty():
		parts[0].took_damage.emit(DamageInfo.new(amount))


## Parks the player in the middle of a plate, held there against physics for a frame so the
## resolution finds them on it.
func _stand_on(plate: int) -> void:
	_player.velocity = Vector2.ZERO
	_player.global_position = _boss.get_plate_positions()[plate]


## Runs the clock past a telegraph, holding the player wherever they were put.
func _resolve_telegraph() -> void:
	var held := _player.global_position
	for _frame: int in int(TEST_TELEGRAPH * 60.0) + 4:
		_player.velocity = Vector2.ZERO
		_player.global_position = held
		await get_tree().physics_frame

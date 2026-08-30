extends TestCase
## Cloud Operations' boss: when damage counts, what the floor costs, and whether the room it leaves
## you can still be crossed.
##
## The fight is a four-beat cycle — sealed, telegraph, discharge, open — and this suite is organised
## around the two claims that make it a fight rather than a wait.
##
## **Damage counts only in the window.** Shots at a sealed boss are discarded outright, not banked,
## and the bar reports an honest pool that only falls. Those are three separate things a later change
## could quietly break in three different directions, so they are asserted separately rather than
## through one "it took damage" check.
##
## **Every migration is answerable.** The discharge costs a point to anything off a live plate, and
## the live set shrinks from five plates to three to two as the fight escalates. That makes the
## geometry load-bearing: if the surviving plates ever cluster on one side of a 416x192 room, a
## player in the far corner takes a hit they could not have avoided. `_test_every_migration_can_be
## _answered_from_anywhere` recomputes the worst case over every boss plate and every rotation, from
## the shipped numbers, and is the check most worth keeping if anyone ever trims this file.
##
## This suite replaced one that asserted the opposite fight: six of its checks existed to fail if
## anybody turned a damage pool into a health bar, because the boss it measured could not be killed
## by damage at all. That fight is gone — see `Orchestrator` for why, and for the two faults that
## took it out — so those checks are gone with it rather than being weakened into passing.

const BOSS_SCENE := preload("res://scenes/bosses/orchestrator.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const BOSS_CONFIG_PATH := "res://data/bosses/orchestrator.tres"
const ENCOUNTER_PATH := "res://data/bosses/orchestrator_encounter.tres"
const CAMPAIGN_PATH := "res://data/runs/main_campaign.tres"

## The arena every boss in this project is measured in: one room's interior.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## The robot's walking speed, from `data/player/player.tres`. Duplicated here because the geometry
## check below is arithmetic about *this* number against the telegraph, and reading it out of the
## resource would make a check about the fight's fairness silently follow a change to the player.
const PLAYER_SPEED := 160.0

## The telegraph the suite runs at, wound down from the shipped 1.9s so a migration resolves in a
## handful of frames rather than in two real seconds. Everything timed is derived from this rather
## than given its own number, for the reason `test_cascade_failure` winds its vent clocks by one
## ratio: what the fight rests on is the *relationships* between these durations, and a suite that
## shortened one of them alone would be measuring a fight nobody plays.
const TEST_TELEGRAPH := 0.2

var _config: OrchestratorConfig
var _arena_node: Node2D
var _boss: Orchestrator
var _player: Player
var _defeated := 0
var _phases: Array[int] = []


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as OrchestratorConfig
	if not require(_config, "orchestrator.tres loads as an OrchestratorConfig"):
		return

	_test_the_encounter_is_complete()
	_test_the_config_is_coherent()
	_test_every_migration_can_be_answered_from_anywhere()
	await _test_a_sealed_boss_discards_damage()
	await _test_the_window_after_landing_takes_damage()
	await _test_the_bar_is_an_honest_pool()
	await _test_it_announces_a_migration_and_does_not_move_yet()
	await _test_the_target_does_not_move_once_announced()
	await _test_the_target_is_the_live_plate_furthest_from_the_player()
	await _test_the_live_set_never_holds_the_plate_it_stands_on()
	await _test_standing_off_every_plate_costs_a_point()
	await _test_standing_on_any_live_plate_costs_nothing()
	await _test_denying_a_migration_keeps_it_put_and_opens_it_longer()
	await _test_a_denial_is_never_also_a_hit()
	await _test_damage_kills_it()
	await _test_the_floor_shrinks_as_the_fight_goes()
	await _test_every_phase_is_announced()
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
		encounter.phase_banners.size() == 3,
		"it announces one banner per phase (%d for 3)" % encounter.phase_banners.size(),
	)


## The shipped numbers, on the relationships the fight rests on rather than on their values.
func _test_the_config_is_coherent() -> void:
	check(_config.max_health > 0.0, "there is a real pool to empty (%.0f)" % _config.max_health)
	check(
		_config.phase_two_at > _config.phase_three_at,
		"the phases are in order (%.2f > %.2f)" % [_config.phase_two_at, _config.phase_three_at],
	)
	check(_config.plate_count >= 4, "there are enough plates to take some away (%d)" % _config.plate_count)
	check(
		_config.live_plates_by_phase.size() == 3,
		"and a live count for each phase (%d)" % _config.live_plates_by_phase.size(),
	)

	# The escalation runs one way. A phase that gave ground back would undo the only thing that
	# changes across this fight.
	var previous := _config.plate_count
	for phase: int in _config.live_plates_by_phase.size():
		var live := _config.live_plates_by_phase[phase]
		check(
			live >= 2,
			"phase %d leaves more than one plate, so shelter is never a single square (%d)"
				% [phase + 1, live],
		)
		check(
			live < _config.plate_count,
			"and never every plate — the one it is standing on is never shelter (%d of %d)"
				% [live, _config.plate_count],
		)
		check(live <= previous, "and no phase gives ground back (%d after %d)" % [live, previous])
		previous = live

	# The denial is worth the run, and that is the entire reward for making it.
	check(
		_config.denial_open_seconds > _config.cold_start_seconds,
		"a denied migration opens it for longer than a completed one (%.2f > %.2f)"
			% [_config.denial_open_seconds, _config.cold_start_seconds],
	)
	# The one inequality the telegraph must keep against the boss's own fire. A countdown shorter
	# than the volleys under it is a countdown the player cannot act inside of.
	check(
		_config.telegraph_seconds > _config.telegraph_volley_interval,
		"the telegraph is longer than the volley interval it fires at (%.2f > %.2f)"
			% [_config.telegraph_seconds, _config.telegraph_volley_interval],
	)
	check(
		_config.telegraph_volley_interval < _config.volley_interval,
		"announcing a migration costs the player more fire, not less (%.2f < %.2f)"
			% [_config.telegraph_volley_interval, _config.volley_interval],
	)
	check(_config.off_plate_damage > 0.0, "being off a plate costs something (%.1f)" % _config.off_plate_damage)
	# Asserted here because the harness below deliberately strips it — see `_open_fight`. Without
	# this check, a shipped config that lost its projectile would leave every integrity measurement
	# in this suite passing and the boss firing blanks.
	check(_config.shot != null, "and the live instance has something to fire")


## **The check this fight cannot ship without.** Every migration has to be answerable from wherever
## the player is standing when it is announced.
##
## The discharge costs a point to anything off a live plate, and the live set shrinks to two plates
## in the last phase. So the fight's fairness is a geometry claim: the furthest any point in the
## arena sits from the nearest live plate, over every plate the boss could be on and every rotation
## of the live set, must be crossable inside the telegraph at the robot's walking speed.
##
## Recomputed here from `plate_count`, `plate_radius`, `plate_size` and `live_plates_by_phase` rather
## than asserted as a remembered number, because the point is to catch the *next* change to any of
## them. Doubling the plates is what made the shrink possible at all — three plates cannot lose one
## without the survivors sometimes sitting on the same side of the room — and nothing stops somebody
## taking them back down.
##
## Walking speed only: the dash is deliberately left out of the budget, so the margin this reports is
## the margin a player who never dashes has.
func _test_every_migration_can_be_answered_from_anywhere() -> void:
	var boss: Orchestrator = BOSS_SCENE.instantiate()
	boss.config = _config
	add_child(boss)
	boss.begin(ARENA)
	await advance_physics(1)

	var plates := boss.get_plate_positions()
	# Half a plate plus the robot's own radius: the distance a player must close to be *on* it.
	var reach := _config.plate_size * 0.5 + Orchestrator.PLAYER_RADIUS
	var budget := _config.telegraph_seconds * PLAYER_SPEED

	for phase: int in _config.live_plates_by_phase.size():
		var live_count: int = _config.live_plates_by_phase[phase]
		var worst := 0.0
		# Every plate the boss could be standing on, against every rotation of the live set. The
		# fight picks one of these each cycle and the player does not choose which.
		for standing: int in plates.size():
			for rotation: int in plates.size() - 1:
				var live := _live_set(plates.size(), standing, live_count, rotation)
				check(
					live.size() == live_count,
					"phase %d lights %d distinct plates (%s)" % [phase + 1, live_count, live],
				)
				worst = maxf(worst, _furthest_from_shelter(plates, live, reach))

		var seconds := worst / PLAYER_SPEED
		check(
			worst <= budget,
			"phase %d: the worst point in the arena is %.0fpx from shelter, %.2fs of a %.2fs "
				% [phase + 1, worst, seconds, _config.telegraph_seconds]
				+ "telegraph",
		)
		# And with room to spare, because the player is also dodging a volley every 0.7 seconds
		# while they run. A migration that is answerable only by a player who started moving on the
		# first frame and took a perfectly straight line is not answerable.
		check(
			worst <= budget * 0.85,
			"phase %d keeps a real margin, not a frame-perfect one (%.0fpx of %.0fpx)"
				% [phase + 1, worst, budget],
		)

	boss.queue_free()
	await advance_physics(2)


## Shots at a sealed boss do nothing, and are not saved up to do something later.
##
## Banking would be the worse failure of the two and the harder to see: the bar would sit still under
## fire exactly as it does now, and then move at a moment the player could not connect to anything
## they did. So the pool is checked after the damage *and* after the window opens.
func _test_a_sealed_boss_discards_damage() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	if not require(not _boss.is_open(), "the fight opens with the boss sealed"):
		await _close()
		return

	var before := _boss.get_health()
	_hurt(_config.max_health * 0.5)
	await advance_physics(1)
	check(
		is_equal_approx(_boss.get_health(), before),
		"damage to a sealed boss does nothing (%.1f, was %.1f)" % [_boss.get_health(), before],
	)
	check(_defeated == 0, "and half a pool of it kills nothing")

	# And it was not banked. Reaching the window must not suddenly apply what was thrown at the
	# closed body.
	await _reach_open_window()
	check(
		is_equal_approx(_boss.get_health(), before),
		"and it is not banked against the window that follows (%.1f)" % _boss.get_health(),
	)
	await _close()


## The window after it lands is the only place damage lands, and it is a real amount of it.
func _test_the_window_after_landing_takes_damage() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	await _reach_open_window()

	if not require(_boss.is_open(), "the boss opens after it lands"):
		await _close()
		return

	var before := _boss.get_health()
	_hurt(_config.max_health * 0.25)
	await advance_physics(1)
	check(
		_boss.get_health() < before,
		"damage in the window counts (%.1f, was %.1f)" % [_boss.get_health(), before],
	)
	check(
		is_equal_approx(_boss.get_health(), before - _config.max_health * 0.25),
		"and counts in full, undivided and uncapped (%.1f)" % _boss.get_health(),
	)
	await _close()


## The bar reports the pool, falls only, and never reports anything else.
##
## The fight this replaced spent its most-watched UI element on a number that went back up — it
## folded a damage pool into a segment between generations, so an undenied failover, which cost the
## boss nothing, restored a third of the bar. A bar that refills under fire is the universal sign for
## a heal, and it was reported in exactly those words. There is nothing left to fold in, and this is
## the check that keeps it that way.
func _test_the_bar_is_an_honest_pool() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	check(
		is_equal_approx(_boss.get_health_ratio(), 1.0),
		"the bar opens full (%.3f)" % _boss.get_health_ratio(),
	)

	var highest := _boss.get_health_ratio()
	var lowest := highest
	# Three whole cycles, with a quarter-pool of damage taken in each window. Long enough that a bar
	# reporting anything cyclical — a pool, a timer, a plate count — would visibly rise somewhere.
	for _cycle: int in 3:
		await _reach_open_window()
		_hurt(_config.max_health * 0.2)
		await advance_physics(1)
		var ratio := _boss.get_health_ratio()
		check(ratio <= highest + 0.001, "the bar never rises (%.3f after %.3f)" % [ratio, highest])
		highest = maxf(highest, ratio)
		lowest = minf(lowest, ratio)
		check(
			is_equal_approx(ratio, _boss.get_health() / _config.max_health),
			"and reports the pool and nothing else (%.3f)" % ratio,
		)

	check(lowest < 0.5, "and it moved a long way under fire (%.3f)" % lowest)
	await _close()


## A migration is announced before it happens, and the boss has not moved when it is.
func _test_it_announces_a_migration_and_does_not_move_yet() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	var standing := _boss.get_plate()
	await _reach_telegraph()

	check(_boss.is_telegraphing(), "the dwell ends in an announced migration")
	check(
		_boss.get_target_plate() != standing,
		"to a plate it is not already on (target %d, standing %d)"
			% [_boss.get_target_plate(), standing],
	)
	check(
		_boss.is_plate_live(_boss.get_target_plate()),
		"and to one that is live (%d in %s)" % [_boss.get_target_plate(), _boss.get_live_plates()],
	)
	check(_boss.get_plate() == standing, "and has not moved yet — the telegraph comes first")
	check(not _boss.is_open(), "and it is sealed while it announces")
	await _close()


## The target is decided when the telegraph starts, not when it ends. This is the check that fails if
## somebody later re-picks on resolution, which would make the run across the room pointless without
## changing anything a player could see.
func _test_the_target_does_not_move_once_announced() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	await _reach_telegraph()

	var announced := _boss.get_target_plate()
	if not require(announced >= 0, "a migration was announced"):
		await _close()
		return

	# The player runs during the telegraph, which is the whole point of it — and running is exactly
	# what would re-trigger a target chosen by distance if it were being chosen every frame.
	for step: int in 4:
		_player.global_position = _boss.get_plate_positions()[step % _boss.get_plate_positions().size()]
		await advance_physics(1)
		if not _boss.is_telegraphing():
			break
		check(
			_boss.get_target_plate() == announced,
			"the target stays %d while the player moves (is %d)"
				% [announced, _boss.get_target_plate()],
		)
	await _close()


## The destination is the live plate furthest from the player.
##
## This is what makes the race real, and it is the fix for how the previous fight died: its target
## was `(current + 1)` and a denial did not move the boss, so a player standing on the next plate
## round the ring denied every failover without moving once. Any rule that ignores where the player
## is can be camped; this one cannot.
func _test_the_target_is_the_live_plate_furthest_from_the_player() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	# Parked on a plate, so "furthest" has an unambiguous answer to check against.
	var plates := _boss.get_plate_positions()
	_player.global_position = plates[0]
	await _reach_telegraph()

	var target := _boss.get_target_plate()
	if not require(target >= 0, "a migration was announced"):
		await _close()
		return

	var live := _boss.get_live_plates()
	var here := _player.global_position
	var furthest := live[0]
	for index: int in live:
		if here.distance_to(plates[index]) > here.distance_to(plates[furthest]):
			furthest = index
	check(
		target == furthest,
		"it names the live plate furthest from the robot (%d, furthest of %s)" % [target, live],
	)
	# And that is not simply the only option it had.
	check(live.size() >= 2, "with more than one to choose between (%d live)" % live.size())
	await _close()


## The plate the boss is standing on is never shelter, in any phase.
##
## "Every plate but the one it is on" is the rule the fight opens with, and it is what makes the
## shrink later on legible as a departure from something. It is also what stops the last phase
## collapsing: with two live plates and the boss's own among them, one of the two shelters would cost
## a point to stand on (`BossPart` charges for contact) and the choice the phase is built around
## would not exist.
func _test_the_live_set_never_holds_the_plate_it_stands_on() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	for _cycle: int in 4:
		var standing := _boss.get_plate()
		var live := _boss.get_live_plates()
		check(
			not live.has(standing),
			"the plate it is standing on (%d) is not shelter (%s)" % [standing, live],
		)
		check(not live.is_empty(), "and there is shelter somewhere (%s)" % [live])
		await _reach_open_window()
	await _close()


## The demand, stated once: be on a plate when it lands.
func _test_standing_off_every_plate_costs_a_point() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	await _reach_telegraph()

	# A corner, which is never a plate — the ellipse the plates sit on is inset from the walls.
	var corner := ARENA.position + Vector2(12.0, 12.0)
	if not require(
		not _boss.is_on_safe_ground(corner), "the corner is not shelter"
	):
		await _close()
		return

	var before := _integrity()
	await _resolve_telegraph_at(corner)
	check(
		_integrity() < before,
		"resolving off every plate costs a point (%d, was %d)" % [_integrity(), before],
	)
	await _close()


## And the other half, which is the half that makes it a rule rather than a tax: any live plate is
## enough. The player does not have to reach the *destination* to survive, only shelter.
func _test_standing_on_any_live_plate_costs_nothing() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	await _reach_telegraph()

	var target := _boss.get_target_plate()
	var live := _boss.get_live_plates()
	var shelter := -1
	for index: int in live:
		if index != target:
			shelter = index
			break
	if not require(shelter >= 0, "there is a live plate that is not the destination (%s)" % [live]):
		await _close()
		return

	var before := _integrity()
	await _resolve_telegraph_at(_boss.get_plate_positions()[shelter])
	check(
		_integrity() == before,
		"a live plate that is not the destination still shelters (%d)" % _integrity(),
	)
	check(
		_boss.get_plate() == target,
		"and the migration completed, undenied (%d)" % _boss.get_plate(),
	)
	await _close()


## The turn on top of the rule: the destination denies, keeps it where it is, and pays in window.
func _test_denying_a_migration_keeps_it_put_and_opens_it_longer() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	await _reach_telegraph()

	var target := _boss.get_target_plate()
	var standing := _boss.get_plate()
	if not require(target >= 0, "a migration was announced"):
		await _close()
		return

	await _resolve_telegraph_at(_boss.get_plate_positions()[target])

	check(_boss.get_plate() == standing, "a denied migration leaves it where it was (%d)" % _boss.get_plate())
	check(not _boss.is_telegraphing(), "and the migration is over")
	if not require(_boss.is_open(), "and it is open"):
		await _close()
		return

	# The reward, measured rather than asserted from the config: the window a denial buys has to
	# outlast the one a completed migration buys, or the run across the room bought nothing.
	var winding := TEST_TELEGRAPH / maxf(_config.telegraph_seconds, 0.001)
	var cold := _config.cold_start_seconds * winding
	var frames := int(cold * 60.0) + 2
	for _frame: int in frames:
		await get_tree().physics_frame
	check(
		_boss.is_open(),
		"and stays open past the length of a cold start (%.2fs of wound-down time)" % cold,
	)
	await _close()


## A denied migration is never also a hit.
##
## The destination is always a live plate, so a player standing on it is by construction sheltered —
## but the discharge and the denial are decided in the same function, and an ordering change could
## make the fight charge a point for its own best outcome. Asserted directly, because it is the kind
## of bug that reads as a tuning complaint ("denying feels bad") rather than as a defect.
func _test_a_denial_is_never_also_a_hit() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	for _cycle: int in 3:
		await _reach_telegraph()
		var target := _boss.get_target_plate()
		if target < 0:
			break
		check(
			_boss.is_plate_live(target),
			"the destination is live, so standing on it is shelter (%d)" % target,
		)
		var before := _integrity()
		await _resolve_telegraph_at(_boss.get_plate_positions()[target])
		check(_integrity() == before, "denying cost no integrity (%d)" % _integrity())
		await _leave_open_window()
	await _close()


## Damage kills it, which is the claim the whole rework rests on. The fight it replaced could not be
## killed by any quantity of damage at all.
func _test_damage_kills_it() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	# Windows only. Anything else would be measuring the gate rather than the pool.
	for _cycle: int in 12:
		if _defeated > 0 or _boss == null or not is_instance_valid(_boss):
			break
		await _reach_open_window()
		_hurt(_config.max_health * 0.34)
		await advance_physics(1)

	check(_defeated == 1, "the boss is defeated, exactly once (%d)" % _defeated)
	await _close()


## The escalation, and the only thing in the fight that changes between phases: there is less floor.
func _test_the_floor_shrinks_as_the_fight_goes() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	await _reach_open_window()
	var nominal := _boss.get_live_plates().size()
	check(
		nominal == _config.live_plates_by_phase[0],
		"phase 1 lights %d plates (%d)" % [_config.live_plates_by_phase[0], nominal],
	)

	# Down to the second phase, then the third, taking the damage in windows the way a player does.
	await _drive_health_to(_config.phase_two_at - 0.05)
	check(
		_boss.get_phase() == Orchestrator.Phase.DEGRADED,
		"crossing %.2f reaches phase 2 (phase %d)" % [_config.phase_two_at, _boss.get_phase()],
	)
	await _reach_open_window()
	var degraded := _boss.get_live_plates().size()
	check(
		degraded == _config.live_plates_by_phase[1],
		"and lights %d (%d)" % [_config.live_plates_by_phase[1], degraded],
	)

	await _drive_health_to(_config.phase_three_at - 0.05)
	check(
		_boss.get_phase() == Orchestrator.Phase.LAST_INSTANCE,
		"crossing %.2f reaches phase 3 (phase %d)" % [_config.phase_three_at, _boss.get_phase()],
	)
	await _reach_open_window()
	var last := _boss.get_live_plates().size()
	check(
		last == _config.live_plates_by_phase[2],
		"and lights %d (%d)" % [_config.live_plates_by_phase[2], last],
	)
	check(degraded < nominal and last < degraded, "the floor only ever shrinks (%d, %d, %d)" % [nominal, degraded, last])
	await _close()


## Every phase reaches the player, on the phase it belongs to.
##
## Both consumers index off the *number*: `CombatHUD` shows `phase_banners[phase - 1]` and
## `FeedbackDirector` gives a phase of 1 nothing, on the shared understanding that phase one is the
## fight starting. This boss shipped once emitting 0, 1, 2 — the first phase change announced
## nothing, the second showed the first's line, and the third was unreachable — so the numbering is
## pinned here rather than trusted to the enum.
func _test_every_phase_is_announced() -> void:
	var encounter := load(ENCOUNTER_PATH) as BossEncounter
	if not require(encounter, "the encounter loads"):
		return
	check(
		not encounter.phase_banners[0].is_empty(),
		"the fight states its rule on the phase it opens on, before it asks anything",
	)

	_phases = []
	EventBus.boss_phase_changed.connect(_on_phase_changed)
	await _open_fight(Vector2(40.0, 40.0))
	check(
		_phases.size() == 1 and _phases[0] == 1,
		"the fight opens on phase 1, like every other boss (%s)" % [_phases],
	)

	await _drive_health_to(_config.phase_two_at - 0.05)
	await _drive_health_to(_config.phase_three_at - 0.05)
	EventBus.boss_phase_changed.disconnect(_on_phase_changed)

	var expected: Array[int] = [1, 2, 3]
	if not require(_phases == expected, "and steps 1, 2, 3 (%s)" % [_phases]):
		await _close()
		return

	for index: int in [1, 2]:
		var phase: int = _phases[index]
		check(
			phase > 1,
			"phase change %d is not mistaken for the fight starting, so it gets its sting (%d)"
				% [index, phase],
		)
		check(
			not encounter.phase_banners[phase - 1].is_empty(),
			"and the HUD has something to say for it ('%s')" % encounter.phase_banners[phase - 1],
		)
	check(
		encounter.phase_banners[1] != encounter.phase_banners[2],
		"the two escalations say different things",
	)
	await _close()


## The plates are its own, and they are somewhere legal.
func _test_the_plates_are_inside_the_arena_and_distinct() -> void:
	await _open_fight(Vector2(40.0, 40.0))

	var plates := _boss.get_plate_positions()
	check(plates.size() == _config.plate_count, "it lays out %d plates (%d)" % [_config.plate_count, plates.size()])
	for index: int in plates.size():
		check(ARENA.has_point(plates[index]), "plate %d is inside the arena (%v)" % [index, plates[index]])
		check(
			ARENA.encloses(_boss.get_plate_rect(index)),
			"and its whole square is (%s)" % _boss.get_plate_rect(index),
		)
	# Distinct, and far enough apart that standing on one is never standing on another — otherwise
	# shelter could be granted for being in the wrong place. Grown by the robot's radius, which is
	# the rect the fight actually tests against.
	for a: int in plates.size():
		for b: int in plates.size():
			if a >= b:
				continue
			check(
				not _boss.get_plate_rect(a).grow(Orchestrator.PLAYER_RADIUS).intersects(
					_boss.get_plate_rect(b).grow(Orchestrator.PLAYER_RADIUS)
				),
				"plates %d and %d cannot both hold the robot at once" % [a, b],
			)
	await _close()


## It brings its own floor. The boss is eligible on every floor in the campaign, including three that
## have never heard of a migration pad, so the fight must not need the arena to contain one.
func _test_it_needs_nothing_from_the_room_it_is_in() -> void:
	await _open_fight(Vector2(40.0, 40.0))
	# The arena this suite builds has no room, no template, and therefore no pads at all — which is
	# the condition being asserted. If the fight needed one, everything above would already have
	# failed, so what this adds is the statement of *why* those pass.
	check(
		_boss.get_plate_positions().size() == _config.plate_count,
		"the boss supplies its own plates in an arena with no pads in it",
	)
	# And it fights: a boss that quietly did nothing without pads would satisfy the check above.
	await _reach_telegraph()
	check(_boss.is_telegraphing(), "and runs its migration loop there")
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


# --- Geometry, reimplemented ---------------------------------------------------


## `Orchestrator._refresh_live_plates`, restated here rather than called.
##
## Deliberately a second implementation. The check it feeds is about whether the *rule* leaves a
## crossable room, and reading the answer out of the object under test would turn it into a check
## that the boss agrees with itself. This one is written from the description in the class doc:
## every plate but the boss's, in ring order, strided evenly, rotated.
func _live_set(count: int, standing: int, live_count: int, rotation: int) -> PackedInt32Array:
	var candidates: PackedInt32Array = PackedInt32Array()
	for step: int in count - 1:
		candidates.append((standing + 1 + step) % count)
	var span := candidates.size()
	var wanted := clampi(live_count, 1, span)
	var live: PackedInt32Array = PackedInt32Array()
	for slot: int in wanted:
		live.append(candidates[(rotation + slot * span / wanted) % span])
	return live


## The furthest any point in the arena sits from the nearest plate in `live`, as a distance the
## robot has to walk.
##
## Sampled on a two-pixel grid over the whole interior rather than reasoned about analytically: the
## worst point is a corner in some configurations and a mid-wall in others, and a closed form for
## "furthest point from the nearest of an arbitrary subset of six ellipse points" is a worse thing to
## maintain than a loop.
func _furthest_from_shelter(
	plates: Array[Vector2], live: PackedInt32Array, reach: float
) -> float:
	var worst := 0.0
	var x := ARENA.position.x
	while x <= ARENA.end.x:
		var y := ARENA.position.y
		while y <= ARENA.end.y:
			var here := Vector2(x, y)
			var nearest := INF
			for index: int in live:
				var plate := plates[index]
				# To the edge of the plate's square, not to its centre: the robot only has to reach
				# the square. Measured per axis because the plate is a rect.
				var dx := maxf(absf(here.x - plate.x) - reach, 0.0)
				var dy := maxf(absf(here.y - plate.y) - reach, 0.0)
				nearest = minf(nearest, Vector2(dx, dy).length())
			worst = maxf(worst, nearest)
			y += 2.0
		x += 2.0
	return worst


# --- Harness ------------------------------------------------------------------


func _open_fight(player_offset: Vector2) -> void:
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
	fast.dwell_seconds = _config.dwell_seconds * winding
	fast.cold_start_seconds = _config.cold_start_seconds * winding
	fast.denial_open_seconds = _config.denial_open_seconds * winding
	fast.volley_interval = _config.volley_interval * winding
	fast.telegraph_volley_interval = _config.telegraph_volley_interval * winding
	# **No projectiles.** Half of this suite measures integrity to decide whether the *floor* charged
	# the player, and the boss fires a spread at them every 0.7 seconds of telegraph — at a robot the
	# harness is holding still on a plate, which is a robot that cannot dodge. Left in, a volley hit
	# and a discharge hit are the same number, so "standing off a plate costs a point" would pass on
	# a fight that had stopped discharging entirely, and "denying is never also a hit" would fail on
	# a fight that was working. The volleys are real and are pinned by the config checks above; what
	# this suite is for is the rule they are fired underneath.
	fast.shot = null
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


func _on_phase_changed(phase: int) -> void:
	_phases.append(phase)


## Damages the boss the way a projectile does: through its part, which forwards it.
func _hurt(amount: float) -> void:
	var parts := _boss.get_parts()
	if not parts.is_empty():
		parts[0].took_damage.emit(DamageInfo.new(amount))


func _integrity() -> int:
	return _player.get_health_component().current as int


## Runs the clock until a migration is announced, holding the player wherever they are.
##
## A frame budget rather than `while`, so a fight that stopped cycling fails the check that follows
## instead of hanging the suite.
func _reach_telegraph() -> void:
	var held := _player.global_position
	for _frame: int in _budget():
		if _boss == null or not is_instance_valid(_boss) or _boss.is_telegraphing():
			return
		_hold(held)
		await get_tree().physics_frame


## Runs the clock until the boss is open to damage, parking the player on shelter so the discharge
## on the way does not cost integrity the caller was not expecting.
func _reach_open_window() -> void:
	for _frame: int in _budget():
		if _boss == null or not is_instance_valid(_boss) or _boss.is_open():
			return
		# Re-read every frame: the live set rotates, and a plate that was shelter last cycle is not
		# necessarily shelter this one.
		var live := _boss.get_live_plates()
		if not live.is_empty():
			_hold(_boss.get_plate_positions()[live[0]])
		await get_tree().physics_frame


## Runs the clock until the boss has sealed again, so the next cycle is its own event.
func _leave_open_window() -> void:
	for _frame: int in _budget():
		if _boss == null or not is_instance_valid(_boss) or not _boss.is_open():
			return
		var live := _boss.get_live_plates()
		if not live.is_empty():
			_hold(_boss.get_plate_positions()[live[0]])
		await get_tree().physics_frame


## Resolves the migration currently being telegraphed with the player held at `where`.
##
## Held every frame rather than assigned once, because `move_and_slide` runs on the robot whatever
## the test wants and a player that had drifted a few pixels off a plate would turn a denial into a
## miss.
func _resolve_telegraph_at(where: Vector2) -> void:
	for _frame: int in _budget():
		if _boss == null or not is_instance_valid(_boss) or not _boss.is_telegraphing():
			return
		_hold(where)
		await get_tree().physics_frame
	_hold(where)


## Damages it in windows until the bar is at or below `ratio`, the way a player reaches a phase.
func _drive_health_to(ratio: float) -> void:
	for _cycle: int in 12:
		if _boss == null or not is_instance_valid(_boss) or _boss.get_health_ratio() <= ratio:
			return
		await _reach_open_window()
		if _boss == null or not is_instance_valid(_boss):
			return
		var over := _boss.get_health() - ratio * _config.max_health
		_hurt(maxf(over, 0.1))
		await advance_physics(1)


func _hold(where: Vector2) -> void:
	_player.velocity = Vector2.ZERO
	_player.global_position = where


## Frames enough for any single beat of the cycle to finish, plus slack. Every clock is wound to the
## same ratio, so the longest of them is the bound.
func _budget() -> int:
	var longest := maxf(
		maxf(_boss.config.dwell_seconds, _boss.config.telegraph_seconds),
		maxf(_boss.config.cold_start_seconds, _boss.config.denial_open_seconds),
	)
	return int(longest * 60.0) + 12

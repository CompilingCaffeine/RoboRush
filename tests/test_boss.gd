extends TestCase
## Checks for spec section 16's Floor 1 boss, The Scrap King.
##
## Everything in code still spells it `merge_conflict` — the class, the scene, the config id — which
## was its name before it was renamed and is deliberately left alone (see MergeConflict's header).
##
## A boss is the one fight in the game the player cannot avoid, so the checks here are
## about the fight being *winnable and honest* rather than about it looking right. Three
## things carry the weight: the phases trip at the health fractions the spec names, the
## synchronisation rule actually costs the player damage until they break the terminals,
## and the fight ends exactly once no matter how it is hit.
##
## The boss is damaged through its parts rather than by reaching into its health, because
## the parts are the only thing a projectile can hit and the forwarding between them is
## precisely what could break.
##
## The fight also lies to the player: its bar reports the phase rather than the pool, and each phase
## ends with the boss playing dead for a couple of seconds. That is a deliberate deception of the
## *player*, so it has to be an undeceived certainty here — the checks below pin that the bar really
## does empty and refill, that the feigned death costs the player nothing except the wait, and that
## the fight still ends exactly once when it finally does end.

const BOSS_SCENE := preload("res://scenes/bosses/merge_conflict.tscn")
const BOSS_CONFIG_PATH := "res://data/bosses/merge_conflict.tres"
const FLOOR_1_CONFIG_PATH := "res://data/floors/floor_1_help_desk.tres"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))
const RIVET_PATH := "res://data/projectiles/rivet.tres"

## What the feigned death is shortened to for the tests. The shipped two seconds are tuned for a
## player's patience and the music fade, and every phase end here would wait them out in real time —
## which is a suite that takes half a minute longer to make exactly the same assertions. The shipped
## value is checked as a value, in `_test_config_matches_the_spec`; what these tests exercise is
## that the beat happens, blocks damage, and ends in the next phase, and 0.2s does that faithfully.
const TEST_FEINT_SECONDS := 0.2

var _config: BossConfig
var _arena: Node2D
var _boss: MergeConflict


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as BossConfig
	if not require(_config, "merge_conflict.tres loads as a BossConfig"):
		return

	_test_config_matches_the_spec()
	_test_the_hud_calls_it_by_its_name()

	await _test_the_boss_starts_alone_and_alternating()
	await _test_duplicates_at_seventy_percent()
	await _test_synchronised_damage_is_refunded()
	await _test_breaking_terminals_stops_the_refund()
	await _test_merges_at_thirty_five_percent()
	await _test_the_merged_form_takes_reduced_damage()
	await _test_the_fight_ends_once()
	await _test_the_boss_actually_attacks()
	await _test_health_is_announced()
	await _test_the_bar_empties_and_refills_for_every_phase()
	await _test_playing_dead_is_not_a_free_hit()
	await _test_no_single_hit_skips_a_phase()
	await _test_the_boss_fights_inside_its_arena()
	await _test_real_projectiles_drive_the_whole_fight()


func _test_config_matches_the_spec() -> void:
	check_near(_config.duplicate_at, 0.7, "the boss duplicates at 70 percent")
	check_near(_config.merge_at, 0.35, "and merges at 35 percent")
	check(_config.terminal_count == 4, "there are four synchronization terminals")
	check(_config.red_shot != null and _config.green_shot != null, "it has both versions to fire")
	check(
		_config.desync_heal_fraction > 0.0,
		"damage to one version partially heals the other while they are synchronised",
	)
	check(_config.wall_gap > 0, "its projectile walls have a gap to run through")
	check(
		_config.feigned_death_seconds > 0.0,
		"it spends a moment playing dead at the end of each phase",
	)
	# The music going quiet is most of what sells the fake death, and a feint shorter than the
	# crossfade would end before the boss theme finished leaving.
	check(
		_config.feigned_death_seconds >= AudioManager.MUSIC_FADE_SECONDS,
		"for long enough that the music actually goes quiet (%.1fs against a %.1fs fade)" % [
			_config.feigned_death_seconds, AudioManager.MUSIC_FADE_SECONDS,
		],
	)


## The boss's name exists in two places — its own `BossConfig` and its `BossEncounter`, which
## is what the HUD is actually bound to (see `FloorController.boss_encountered`) — because
## nothing hands the HUD a `BossConfig` directly. Two copies of a name is exactly the
## arrangement that ends with a boss bar labelled with the name the boss used to have, so the
## two are checked against each other here. Casing aside: the HUD shouts, the resource does not.
func _test_the_hud_calls_it_by_its_name() -> void:
	var floor_config: FloorConfig = load(FLOOR_1_CONFIG_PATH) as FloorConfig
	if not require(floor_config, "floor_1_help_desk.tres loads as a FloorConfig"):
		return
	var encounter := _find_encounter(floor_config, &"merge_conflict")
	if not require(encounter, "the Help Desk's boss pool offers Merge Conflict"):
		return
	check(
		encounter.display_name == _config.display_name.to_upper(),
		"the boss bar says '%s' and the boss is called '%s'" % [
			encounter.display_name, _config.display_name,
		],
	)
	check(
		not _config.display_name.is_empty() and _config.display_name != "Unnamed Boss",
		"and it is a name someone chose",
	)
	# Phase two is two rival copies, and the King is not among them. The fake death that ends that
	# phase used to borrow the King's own epitaph, which told the player something the fight then
	# contradicted: he was still standing, and it was the claimants who fell.
	check(
		CombatHUD.CLAIMANTS_DEFEAT_BANNER != CombatHUD.BOSS_DEFEAT_BANNER,
		"phase two's fake death is not announced as the King's",
	)


## Phase one: one body, alternating patterns, and no terminals to break yet.
func _test_the_boss_starts_alone_and_alternating() -> void:
	await _begin()
	check(_boss.get_phase() == MergeConflict.Phase.ALTERNATING, "it starts in phase one")
	check(_boss.get_parts().size() == 1, "as a single body")
	check(_boss.get_terminal_count() == 0, "with no terminals yet")
	check(not _boss.is_synchronised(), "and nothing to synchronise with")
	check_near(_boss.get_health_ratio(), 1.0, "at full health")
	check_near(_boss.get_phase_health_ratio(), 1.0, "showing a full bar")
	check(not _boss.is_feigning_defeat(), "and fighting rather than playing dead")
	await _teardown()


func _test_duplicates_at_seventy_percent() -> void:
	await _begin()

	# Just short of the threshold: still one body.
	_hurt(_config.max_health * 0.25)
	check(_boss.get_parts().size() == 1, "above 70 percent it stays single")

	_hurt(_config.max_health * 0.1)
	# Crossing the threshold does not start the next phase — it starts the feigned death that
	# hides it, and the phase the player thinks was the whole fight is still the current one.
	check(_boss.is_feigning_defeat(), "crossing 70 percent makes it play dead")
	check(_boss.get_phase() == MergeConflict.Phase.ALTERNATING, "with the phase not yet changed")
	check_near(_boss.get_phase_health_ratio(), 0.0, "and an empty bar")
	check(_boss.get_parts().size() == 1, "and no second body given away early")

	await _wait_out_the_feint()
	check(
		_boss.get_phase() == MergeConflict.Phase.DUPLICATED,
		"and then it duplicates rather than dying",
	)
	check(_boss.get_terminal_count() == 4, "with its four terminals")
	check(_boss.is_synchronised(), "so the two are in sync from the moment they split")
	check(_boss.get_parts().size() == 2, "and the second body has arrived")
	check_near(_boss.get_phase_health_ratio(), 1.0, "on a bar that has refilled")
	await _teardown()


## The rule that makes phase two a puzzle rather than a longer phase one.
func _test_synchronised_damage_is_refunded() -> void:
	await _begin()
	await _end_the_phase()
	var synchronised := _boss.is_synchronised()
	check(synchronised, "the boss reached its synchronised phase")
	if not synchronised:
		await _teardown()
		return

	var before := _boss.get_health()
	_hurt(10.0)
	var lost := before - _boss.get_health()

	check(lost < 10.0, "ten damage costs the boss less than ten while synchronised")
	check_near(
		lost, 10.0 * (1.0 - _config.desync_heal_fraction), "and costs exactly the un-refunded part"
	)
	await _teardown()


func _test_breaking_terminals_stops_the_refund() -> void:
	await _begin()
	await _end_the_phase()
	var synchronised := _boss.is_synchronised()
	check(synchronised, "the boss reached its synchronised phase")
	if not synchronised:
		await _teardown()
		return

	_destroy_all_terminals()
	await advance_physics(2)

	check(_boss.get_terminal_count() == 0, "every terminal is down")
	check(
		_boss.get_parts().size() == 2,
		"the two versions are still standing — it is the sync that broke, not a body",
	)
	check(not _boss.is_synchronised(), "so the versions are no longer in sync")

	var before := _boss.get_health()
	_hurt(10.0)
	check_near(before - _boss.get_health(), 10.0, "and damage lands in full again")
	await _teardown()


func _test_merges_at_thirty_five_percent() -> void:
	await _begin()
	await _destroy_terminals_after_duplication()

	_hurt(_config.max_health * 10.0)
	check(_boss.is_feigning_defeat(), "crossing 35 percent plays dead a second time")
	check(_boss.get_phase() == MergeConflict.Phase.DUPLICATED, "still in the phase it is ending")

	await _wait_out_the_feint()
	check(_boss.get_phase() == MergeConflict.Phase.MERGED, "and then merges")
	check(_boss.get_health() > 0.0, "and is still alive to fight in it")
	check(_boss.get_parts().size() == 1, "back into one larger body")
	check(_boss.get_terminal_count() == 0, "with the terminals gone")
	await _teardown()


## Phase three's health, expressed as the rule that produces it. Phases two and three are handed
## the same 35 percent of the pool, but only phase two also charges the player four terminals — so
## at full damage the last phase of the fight was its shortest, ending in half the time the phase
## before it took. `merged_damage_scale` is what closes that gap without moving spec section 16's
## thresholds, and it is checked here as a rule as well as in tests/test_balance.gd as a number: a
## config field that nothing applies would satisfy the arithmetic and not the fight.
func _test_the_merged_form_takes_reduced_damage() -> void:
	await _begin()
	await _reach_the_last_phase()
	var merged := _boss.get_phase() == MergeConflict.Phase.MERGED
	check(merged, "the boss reached its merged phase")
	if not merged:
		await _teardown()
		return

	check(not _boss.is_synchronised(), "with nothing left to synchronise with")

	var before := _boss.get_health()
	_hurt(10.0)
	var lost := before - _boss.get_health()

	check(lost < 10.0, "ten damage costs the merged form less than ten")
	check_near(
		lost,
		10.0 * _config.merged_damage_scale,
		"scaled by exactly merged_damage_scale, not by the phase-two refund",
	)
	check(
		_config.merged_damage_scale < 1.0,
		"which is a reduction rather than a field left at its ceiling",
	)
	await _teardown()


## A boss that announced its defeat twice would show the victory screen, hide it, and show
## it again — and would count as two bosses in the run statistics.
func _test_the_fight_ends_once() -> void:
	await _begin()
	await _reach_the_last_phase()

	var defeats := [0]
	var handler := func(_boss_node: Node) -> void: defeats[0] += 1
	EventBus.boss_defeated.connect(handler)

	# Overkill, twice, through a part that no longer exists after the first blow.
	var parts := _boss.get_parts()
	_hurt(_config.max_health * 4.0)
	await advance_physics(2)
	for part: BossPart in parts:
		if is_instance_valid(part):
			part.took_damage.emit(DamageInfo.new(50.0))

	check(defeats[0] == 1, "the boss is defeated exactly once")
	check_near(_boss.get_health(), 0.0, "and has no health left")
	check(_boss.get_parts().is_empty(), "and leaves no bodies behind")

	EventBus.boss_defeated.disconnect(handler)
	await _teardown()


## Every phase must actually produce projectiles. A phase that telegraphed and then fired
## nothing would look like the boss thinking.
func _test_the_boss_actually_attacks() -> void:
	await _begin()
	var container := _arena.get_node("Projectiles")

	var fired := [0]
	container.child_entered_tree.connect(func(_child: Node) -> void: fired[0] += 1)

	# Long enough for several attack cycles at the shipped interval.
	await advance_physics(300)
	check(fired[0] > 0, "phase one fires (spawned %d)" % fired[0])

	var after_phase_one: int = fired[0]
	await _reach_the_last_phase()
	check(_boss.get_phase() == MergeConflict.Phase.MERGED, "the boss reached its last phase")

	await advance_physics(400)
	check(fired[0] > after_phase_one, "and phase three fires too")
	await _teardown()


func _test_health_is_announced() -> void:
	await _begin()
	var ratios: Array[float] = []
	var handler := func(ratio: float) -> void: ratios.append(ratio)
	EventBus.boss_health_changed.connect(handler)

	_hurt(_config.max_health * 0.2)
	check(not ratios.is_empty(), "damage announces the boss's health for the HUD bar")
	check(ratios[ratios.size() - 1] < 1.0, "and the announced ratio has gone down")

	EventBus.boss_health_changed.disconnect(handler)
	await _teardown()


## The fight's deliberate deception, from the side the player sees it: the bar empties completely
## three times and refills twice. It is worth pinning as a test rather than trusting to the phase
## arithmetic, because a bar that stopped reaching zero would not break anything — it would just
## quietly turn the fight back into an ordinary three-phase boss and nobody would get an error.
func _test_the_bar_empties_and_refills_for_every_phase() -> void:
	await _begin()

	var ratios: Array[float] = []
	var handler := func(ratio: float) -> void: ratios.append(ratio)
	EventBus.boss_health_changed.connect(handler)

	_hurt(_config.max_health * 10.0)
	check_near(_last(ratios), 0.0, "phase one ends on an empty bar")
	await _wait_out_the_feint()
	check_near(_last(ratios), 1.0, "and phase two opens on a full one")

	_destroy_all_terminals()
	await advance_physics(2)
	_hurt(_config.max_health * 10.0)
	check_near(_last(ratios), 0.0, "phase two ends on an empty bar too")
	await _wait_out_the_feint()
	check_near(_last(ratios), 1.0, "and phase three opens on a full one")

	var defeats := [0]
	var defeat_handler := func(_boss_node: Node) -> void: defeats[0] += 1
	EventBus.boss_defeated.connect(defeat_handler)

	_hurt(_config.max_health * 10.0)
	check_near(_last(ratios), 0.0, "and the third empty bar is the real one")
	check(defeats[0] == 1, "which is the only one that ends the fight")

	EventBus.boss_defeated.disconnect(defeat_handler)
	EventBus.boss_health_changed.disconnect(handler)
	await _teardown()


## Playing dead is a beat, not an opening. A boss that could be damaged while inert would let a
## player who kept firing skip the phase they were being set up for, and a boss whose bodies were
## merely invisible would have them shooting a target they cannot see.
func _test_playing_dead_is_not_a_free_hit() -> void:
	await _begin()
	var container := _arena.get_node("Projectiles")

	_hurt(_config.max_health * 10.0)
	var health := _boss.get_health()
	var parts := _boss.get_parts()
	check(_boss.is_feigning_defeat(), "the boss is playing dead")
	for part: BossPart in parts:
		check(not part.visible, "its body is gone from the arena")
		check(part.collision_layer == 0, "and is not there to be shot at either")

	var defeats := [0]
	var handler := func(_boss_node: Node) -> void: defeats[0] += 1
	EventBus.boss_defeated.connect(handler)

	var fired_before := container.get_child_count()
	for _hit: int in 5:
		_hurt(_config.max_health)
	await advance_physics(int(_feint_seconds() * 30.0))

	check_near(_boss.get_health(), health, "damage dealt to it while inert does not land")
	check(defeats[0] == 0, "and cannot end a fight that has two phases left")
	check(
		container.get_child_count() <= fired_before,
		"and it fires nothing back while it is pretending to be dead",
	)

	EventBus.boss_defeated.disconnect(handler)
	await _teardown()


## The clamp that keeps the deception intact for every build. Health stops at the end of the phase
## the damage was dealt in, so no single hit — however large the run has made it — can skip a phase
## and the feigned death that ends it.
func _test_no_single_hit_skips_a_phase() -> void:
	await _begin()

	_hurt(_config.max_health * 10.0)
	check(_boss.get_health() > 0.0, "a hit for ten times the pool does not end the fight")
	check_near(_boss.get_health_ratio(), _config.duplicate_at, "it stops where phase one does")
	check(_boss.is_feigning_defeat(), "and plays dead there like any other phase end")

	await _wait_out_the_feint()
	check(_boss.get_phase() == MergeConflict.Phase.DUPLICATED, "then carries on into phase two")
	await _teardown()


func _last(values: Array[float]) -> float:
	return values[values.size() - 1] if not values.is_empty() else -1.0


## The boss is a child of the room it fights in, and that room is offset onto the floor
## grid. A body positioned in local space when global was meant fights outside its own
## arena, with its terminals somewhere in the wall. Checked with the controller off the
## origin, because at the origin the mistake is invisible.
func _test_the_boss_fights_inside_its_arena() -> void:
	RunManager.begin_run(555)
	_arena = Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	_arena.add_child(container)
	add_child(_arena)

	var holder := Node2D.new()
	holder.position = Vector2(1408.0, 704.0)
	_arena.add_child(holder)

	var arena_rect := Rect2(holder.global_position, ARENA.size)
	_boss = _new_boss()
	holder.add_child(_boss)
	_boss.begin(arena_rect)
	await advance_physics(2)

	for part: BossPart in _boss.get_parts():
		check(
			arena_rect.has_point(part.global_position),
			# %s, not %v: the position is a vector but the arena is a Rect2, and %v rejects it.
			"the boss stands inside its arena (at %v, arena %s)" % [
				part.global_position, arena_rect,
			],
		)

	_hurt(_config.max_health * 10.0)
	await _wait_out_the_feint()

	var terminals := 0
	for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var terminal := node as BossTerminal
		if terminal == null or not is_instance_valid(terminal):
			continue
		terminals += 1
		check(
			arena_rect.has_point(terminal.global_position),
			"a terminal stands inside the arena (at %v)" % terminal.global_position,
		)
	check(terminals == 4, "all four terminals were placed")
	await _teardown()


## The fight driven the way the game drives it: real projectiles, real collision, real hit
## callbacks. Every other check here damages the boss by emitting `took_damage` directly,
## which is a faithful test of the forwarding and a blind spot for everything upstream of
## it — a phase change is reached from inside a projectile's hit callback, and Godot
## refuses to register a new body's collision shape while the physics server is flushing
## queries. A clone spawned there exists but cannot be shot, and nothing that emits
## `took_damage` by hand would ever notice.
func _test_real_projectiles_drive_the_whole_fight() -> void:
	await _begin()

	# One real hit, big enough to cross the duplication threshold from inside the callback.
	_shoot(_boss.get_parts()[0], _config.max_health * 0.4)
	await advance_physics(12)
	await _wait_out_the_feint()

	check(_boss.get_phase() == MergeConflict.Phase.DUPLICATED, "a real hit duplicates the boss")
	check(_boss.get_parts().size() == 2, "and the second version arrives")
	check(_boss.get_terminal_count() == 4, "along with its terminals")

	# The clone must be shootable. If its collision shape failed to register, this passes
	# straight through it and the boss takes nothing.
	var before := _boss.get_health()
	_shoot(_boss.get_parts()[1], 5.0)
	await advance_physics(12)
	check(_boss.get_health() < before, "the duplicated version can actually be shot")

	# So must the terminals, or the fight has no answer.
	var terminal := _find_terminal()
	check(terminal != null, "a terminal is in the world to shoot")
	if terminal != null:
		var terminal_health := terminal.get_health_component().current
		_shoot(terminal, 2.0)
		await advance_physics(12)
		check(
			terminal.get_health_component().current < terminal_health,
			"and the terminals can be shot too",
		)

	await _teardown()


## Fires a real player projectile into `target` from just outside it.
func _shoot(target: Node2D, damage: float) -> void:
	var config := (load(RIVET_PATH) as ProjectileConfig).spawn_copy()
	config.damage = damage
	var origin := target.global_position - Vector2(40.0, 0.0)
	var shooter := Node2D.new()
	_arena.add_child(shooter)
	ProjectileFactory.spawn_configured(
		shooter, config, Vector2.RIGHT, origin, Teams.Id.PLAYER, shooter
	)


func _find_terminal() -> BossTerminal:
	for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var terminal := node as BossTerminal
		if terminal != null and is_instance_valid(terminal):
			return terminal
	return null


# --- Fixtures -----------------------------------------------------------------


## A boss configured like the shipped one except for a shortened feigned death. Duplicated rather
## than edited: `config` is an ExtResource shared by every instance the process loads, and shortening
## the original would leave the real fight two seconds shorter for whatever ran after this suite.
func _new_boss() -> MergeConflict:
	var boss: MergeConflict = BOSS_SCENE.instantiate()
	var fast: BossConfig = _config.duplicate()
	fast.feigned_death_seconds = TEST_FEINT_SECONDS
	boss.config = fast
	return boss


func _begin() -> void:
	RunManager.begin_run(31337)
	_arena = Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	_arena.add_child(container)
	add_child(_arena)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = ARENA.get_center() + Vector2(0.0, 60.0)
	# The boss is being tested, not the robot's survival.
	_arena.add_child(player)
	player.get_health_component().configure(9999.0, 0.0)

	_boss = _new_boss()
	_arena.add_child(_boss)
	_boss.begin(ARENA)
	await advance_physics(2)


func _teardown() -> void:
	_arena.queue_free()
	await advance_physics(2)


## Ends the phase the boss is in and waits out the feigned death that follows, leaving it fighting
## in the next phase with whatever bodies that phase brings.
##
## Hitting it for ten times its pool rather than for a measured amount, because the boss floors its
## own health at the phase boundary: overkill is absorbed there, so "more than it can survive"
## always lands exactly at the end of the current phase. That also covers the synchronised phase,
## which refunds three quarters of everything it is dealt.
func _end_the_phase() -> void:
	_hurt(_config.max_health * 10.0)
	await _wait_out_the_feint()


## The feigned death, plus a few frames for the bodies and terminals the next phase adds a frame
## after it begins. Read off the boss's own config rather than the shipped one, since `_new_boss`
## shortens it.
func _wait_out_the_feint() -> void:
	await advance_physics(int(_feint_seconds() * 60.0) + 6)


func _feint_seconds() -> float:
	return _boss.config.feigned_death_seconds


## Into phase three, the only phase whose empty bar means anything.
func _reach_the_last_phase() -> void:
	await _destroy_terminals_after_duplication()
	await _end_the_phase()


## Damages the boss the way a projectile does: through a part, which forwards it.
func _hurt(amount: float) -> void:
	var parts := _boss.get_parts()
	if parts.is_empty():
		return
	parts[0].took_damage.emit(DamageInfo.new(amount))


## Takes the boss into phase two and immediately breaks every terminal, so later checks are
## measuring the phase rather than the refund.
func _destroy_terminals_after_duplication() -> void:
	await _end_the_phase()
	_destroy_all_terminals()
	await advance_physics(2)


func _destroy_all_terminals() -> void:
	for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var terminal := node as BossTerminal
		if terminal != null and is_instance_valid(terminal):
			terminal.get_health_component().apply_damage(DamageInfo.new(999.0))


## Looks up one boss in a floor's pool by id. Shared shape with test_runtime_error.gd's own
## copy: since either boss may guard either floor, "this floor's boss" is no longer a single
## value a test can read, and asking for a specific one by id is what replaces it.
func _find_encounter(floor_config: FloorConfig, id: StringName) -> BossEncounter:
	for entry: BossEncounter in floor_config.boss_pool:
		if entry != null and entry.id == id:
			return entry
	return null

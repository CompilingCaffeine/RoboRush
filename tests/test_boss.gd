extends TestCase
## Checks for spec section 16's Merge Conflict.
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

const BOSS_SCENE := preload("res://scenes/bosses/merge_conflict.tscn")
const BOSS_CONFIG_PATH := "res://data/bosses/merge_conflict.tres"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

var _config: BossConfig
var _arena: Node2D
var _boss: MergeConflict


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as BossConfig
	if not require(_config, "merge_conflict.tres loads as a BossConfig"):
		return

	_test_config_matches_the_spec()

	await _test_the_boss_starts_alone_and_alternating()
	await _test_duplicates_at_seventy_percent()
	await _test_synchronised_damage_is_refunded()
	await _test_breaking_terminals_stops_the_refund()
	await _test_merges_at_thirty_five_percent()
	await _test_the_fight_ends_once()
	await _test_the_boss_actually_attacks()
	await _test_health_is_announced()


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


## Phase one: one body, alternating patterns, and no terminals to break yet.
func _test_the_boss_starts_alone_and_alternating() -> void:
	await _begin()
	check(_boss.get_phase() == MergeConflict.Phase.ALTERNATING, "it starts in phase one")
	check(_boss.get_parts().size() == 1, "as a single body")
	check(_boss.get_terminal_count() == 0, "with no terminals yet")
	check(not _boss.is_synchronised(), "and nothing to synchronise with")
	check_near(_boss.get_health_ratio(), 1.0, "at full health")
	await _teardown()


func _test_duplicates_at_seventy_percent() -> void:
	await _begin()

	# Just short of the threshold: still one body.
	_hurt(_config.max_health * 0.25)
	check(_boss.get_parts().size() == 1, "above 70 percent it stays single")

	_hurt(_config.max_health * 0.1)
	check(
		_boss.get_phase() == MergeConflict.Phase.DUPLICATED,
		"crossing 70 percent duplicates it",
	)
	check(_boss.get_parts().size() == 2, "into two versions")
	check(_boss.get_terminal_count() == 4, "and four terminals appear with them")
	check(_boss.is_synchronised(), "which are keeping the two in sync")
	await _teardown()


## The rule that makes phase two a puzzle rather than a longer phase one.
func _test_synchronised_damage_is_refunded() -> void:
	await _begin()
	_hurt(_config.max_health * 0.35)
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
	_hurt(_config.max_health * 0.35)
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

	_hurt_to_ratio(0.2)
	check(_boss.get_phase() == MergeConflict.Phase.MERGED, "crossing 35 percent merges it")
	check(_boss.get_health() > 0.0, "and is still alive to fight in it")
	check(_boss.get_parts().size() == 1, "back into one larger body")
	check(_boss.get_terminal_count() == 0, "with the terminals gone")
	await _teardown()


## A boss that announced its defeat twice would show the victory screen, hide it, and show
## it again — and would count as two bosses in the run statistics.
func _test_the_fight_ends_once() -> void:
	await _begin()
	await _destroy_terminals_after_duplication()

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
	await _destroy_terminals_after_duplication()
	_hurt_to_ratio(0.2)
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


# --- Fixtures -----------------------------------------------------------------


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

	_boss = BOSS_SCENE.instantiate()
	_arena.add_child(_boss)
	_boss.begin(ARENA)
	await advance_physics(2)


func _teardown() -> void:
	_arena.queue_free()
	await advance_physics(2)


## Damages the boss down to a given fraction of its maximum, computed from where it
## actually is. A fixed amount risks asking for more than the boss has left and killing it
## when the check wanted a phase change. Assumes the terminals are down, because a
## synchronised boss only takes part of what it is dealt.
func _hurt_to_ratio(ratio: float) -> void:
	var needed := _boss.get_health() - _config.max_health * ratio
	if needed > 0.0:
		_hurt(needed)


## Damages the boss the way a projectile does: through a part, which forwards it.
func _hurt(amount: float) -> void:
	var parts := _boss.get_parts()
	if parts.is_empty():
		return
	parts[0].took_damage.emit(DamageInfo.new(amount))


## Takes the boss into phase two and immediately breaks every terminal, so later checks are
## measuring the phase rather than the refund.
func _destroy_terminals_after_duplication() -> void:
	_hurt(_config.max_health * 0.35)
	_destroy_all_terminals()
	await advance_physics(2)


func _destroy_all_terminals() -> void:
	for node: Node in get_tree().get_nodes_in_group(Teams.GROUP_ENEMY):
		var terminal := node as BossTerminal
		if terminal != null and is_instance_valid(terminal):
			terminal.get_health_component().apply_damage(DamageInfo.new(999.0))

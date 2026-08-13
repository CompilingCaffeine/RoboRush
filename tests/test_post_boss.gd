extends TestCase
## The post-boss danger contract, which is a *feature* and reads like a bug.
##
## Killing a boss does not make the arena safe. A projectile already in flight goes on crossing it;
## a compile lane already painted goes on to strike. Either can damage or kill the player while the
## reward stands unclaimed a few pixels away, and if one does, the run is lost — no prize, no
## descent, no victory. The fight ends when the arena is quiet, not when the health bar empties.
##
## This suite exists because that behaviour is indistinguishable from a defect from the outside,
## and because the fix somebody will reach for is one line: clear the hazards when `boss_defeated`
## fires, or make the player briefly immune. Either would be accepted in silence by every other
## suite in this project. Here they fail.
##
## The rule has two halves, and both are asserted below, because only holding one of them is worse
## than holding neither:
##
## - **Committed attacks resolve.** Fired, painted, telegraphed — it happens, boss or no boss.
## - **Uncommitted attacks never happen.** A dead boss starts no new telegraph and no new attack.
##   An unannounced hazard appearing in an arena the player has just won is not danger, it is a
##   cheat.
##
## And the boundary the danger stops at: a hazard may outlive the boss, but not the floor. Claiming
## the reward releases the session and takes every unresolved hazard with it.

const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MERGE_CONFLICT_SCENE := preload("res://scenes/bosses/merge_conflict.tscn")
const RUNTIME_ERROR_SCENE := preload("res://scenes/bosses/runtime_error.tscn")

const MERGE_CONFLICT_CONFIG := "res://data/bosses/merge_conflict.tres"
const RUNTIME_ERROR_CONFIG := "res://data/bosses/runtime_error.tres"
const RIVET_CONFIG := "res://data/projectiles/rivet.tres"

## A bare arena for the two boss checks, matching the one their own suites fight in.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## Shortened clocks, so a boss attacks inside a test rather than inside a minute. Same values
## `tests/test_runtime_error.gd` uses, for the same reason.
const FAST_INTERVAL := 0.3
const FAST_WINDUP := 0.1
const FAST_LANE_TELEGRAPH := 0.2
const FAST_LANE_STRIKE := 0.05
const FAST_LANE_STAGGER := 0.15

## Long enough that a boss with a 0.3s clock would have attacked several times over.
const FRAMES_AFTER_DEATH := 90

## The player's integrity for the checks about being hurt. Low enough that one lane is lethal where
## the check wants a death, high enough to survive where it wants a survivor — set per check.
const LETHAL_DAMAGE := 99.0

var _arena: Node2D
var _floor: FloorController
var _player: Player


func run() -> void:
	await _test_a_shot_fired_before_death_still_hits()
	await _test_a_lane_painted_before_death_still_strikes()
	await _test_a_dead_boss_starts_nothing_new(MERGE_CONFLICT_SCENE, MERGE_CONFLICT_CONFIG, "The Scrap King")
	await _test_a_dead_boss_starts_nothing_new(RUNTIME_ERROR_SCENE, RUNTIME_ERROR_CONFIG, "Runtime Error")
	await _test_a_post_boss_death_beats_the_reward()
	await _test_surviving_the_hazard_still_progresses()
	await _test_no_live_hazard_crosses_the_boundary()


## The headline case. A shot committed before the killing blow reaches the player afterwards and
## takes integrity off them, in a room whose boss is already dead and whose reward is already up.
func _test_a_shot_fired_before_death_still_hits() -> void:
	if not await _open_boss_room(2024):
		return

	var before := _player.get_health_component().current
	var shot := _commit_shot_at_player()
	_defeat_the_boss()
	await advance_physics(1)

	check(
		is_instance_valid(shot),
		"a shot already in flight is not swept up when the boss dies",
	)
	check(
		_reward_stands_present(),
		"and the reward is up, so this is the window the contract is about",
	)

	# Long enough for a stationary shot sitting on the player to resolve against them.
	await advance_physics(20)
	check(
		_player.get_health_component().current < before,
		"the dead boss's shot still costs the player integrity (%.1f -> %.1f)"
			% [before, _player.get_health_component().current],
	)

	await _close()


## The same claim for the other kind of hazard, and the one with a warning attached: a lane the
## player was shown and chose to stand in resolves whether or not the thing that painted it is
## still alive.
func _test_a_lane_painted_before_death_still_strikes() -> void:
	if not await _open_boss_room(1789):
		return

	var before := _player.get_health_component().current
	var lane := _paint_lane_over_player(1.0, 0.2)
	_defeat_the_boss()
	await advance_physics(1)

	check(is_instance_valid(lane), "a lane already painted survives the boss that painted it")

	# Past the telegraph and into the strike.
	await advance_physics(40)
	check(
		_player.get_health_component().current < before,
		"and still strikes the player afterwards (%.1f -> %.1f)"
			% [before, _player.get_health_component().current],
	)

	await _close()


## The other half of the rule, for each boss in the game. A corpse announces nothing.
##
## Asserted against a *measured* attack rather than against silence: the check first waits for the
## boss to produce a hazard, so "nothing appeared after it died" cannot pass because the boss was
## never attacking in the first place.
##
## It asserts the outcome, not the mechanism, and that is deliberate — both bosses currently stop
## twice over. `_is_dead` short-circuits `_physics_process`, and freeing the body makes the attack
## clock return on its own. Removing either one alone leaves this suite green, which was measured
## rather than assumed; removing both makes it fail loudly (ten hazards over ninety frames, when it
## was tried). A check written against one of the two flags would have passed a boss that kept its
## body for a death animation, which is the shape the next boss is most likely to take.
func _test_a_dead_boss_starts_nothing_new(
	scene: PackedScene, config_path: String, name_of: String
) -> void:
	var arena := Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	arena.add_child(container)
	add_child(arena)

	GameManager.start_run()
	RunManager.begin_run(4242)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = ARENA.get_center() + Vector2(0.0, 60.0)
	arena.add_child(player)
	# The boss is being observed, not fought; a dead player would stop the clock this measures.
	player.get_health_component().configure(9999.0, 0.0)

	var boss: Boss = scene.instantiate()
	boss.config = _hastened(load(config_path))
	arena.add_child(boss)
	boss.begin(ARENA)
	await advance_physics(2)

	# Wait for it to actually attack, so the silence below means something.
	var attacked := false
	for _frame: int in 180:
		await get_tree().physics_frame
		if _hazards_in(container) > 0:
			attacked = true
			break
	check(attacked, "%s attacks while it is alive" % name_of)

	_kill(boss)
	await advance_physics(1)
	# Everything it had already committed is allowed to resolve; the count that matters is what
	# appears from *here*, so the slate is cleared rather than the total compared.
	for child: Node in container.get_children():
		child.free()

	await advance_physics(FRAMES_AFTER_DEATH)
	check(
		_hazards_in(container) == 0,
		"%s starts nothing new once dead (%d hazards appeared over %d frames)"
			% [name_of, _hazards_in(container), FRAMES_AFTER_DEATH],
	)

	GameManager.start_run()
	arena.queue_free()
	await advance_physics(2)


## The state race, and the reason `_finish_floor` checks whether the run is already over.
##
## A lane resolving and a reward being claimed can land in the same frame, in either order, and
## both descent and victory are *deferred* — a deferred call is flushed by the tree whether or not
## the tree is paused, so game-over does not stop a descent that was already scheduled. Without the
## guard this produced a summary screen with the next floor quietly building underneath it.
func _test_a_post_boss_death_beats_the_reward() -> void:
	if not await _open_boss_room(1301):
		return

	var floor_before := _floor.config.floor_number
	var session_before := _floor.get_session()
	var items_before := _player.get_item_inventory().size()
	var wins_before := SaveManager.best.runs_won

	_defeat_the_boss()
	await advance_physics(1)
	check(_reward_stands_present(), "the reward is standing unclaimed")

	# A lane committed before the boss died, resolving lethally after it.
	_paint_lane_over_player(LETHAL_DAMAGE, 0.05)
	await advance_physics(30)
	check(_player.is_dead(), "the lingering lane kills the player")
	check(GameManager.state == GameManager.State.GAME_OVER, "which ends the run in failure")

	# And now the claim that lost the race, driven directly because a paused tree will not deliver
	# the interact the player would have pressed.
	_floor._on_boss_reward_taken(_floor.config.get_items()[0])
	await advance_physics(6)

	check(
		GameManager.state == GameManager.State.GAME_OVER,
		"the loss stands: the run does not become a victory",
	)
	check(
		_floor.config.floor_number == floor_before,
		"and does not descend (still floor %d)" % _floor.config.floor_number,
	)
	check(
		_floor.get_session() == session_before,
		"the floor the player died on is not replaced",
	)
	check(
		_player.get_item_inventory().size() == items_before,
		"and no reward is granted",
	)
	check(
		SaveManager.best.runs_won == wins_before,
		"no victory is filed",
	)

	await _close()


## The same window, survived. The hazard is the same hazard; only the damage differs, so a failure
## here separates "the guard is too eager" from "the guard works".
func _test_surviving_the_hazard_still_progresses() -> void:
	if not await _open_boss_room(1302):
		return

	var floor_before := _floor.config.floor_number
	_defeat_the_boss()
	await advance_physics(1)

	_paint_lane_over_player(1.0, 0.05)
	await advance_physics(30)
	check(not _player.is_dead(), "the player survives a lane that is not lethal")
	check(GameManager.state == GameManager.State.RUN, "and the run is still running")

	_floor._on_boss_reward_taken(_floor.config.get_items()[0])
	await advance_physics(6)

	check(
		_floor.config.floor_number == floor_before + 1,
		"claiming the reward descends normally (floor %d)" % _floor.config.floor_number,
	)

	await _close()


## Where the danger stops. A hazard may outlive the boss; it must not outlive the floor.
##
## The lane here is given a telegraph long enough that it is still unresolved when the reward is
## taken, which is the only interesting case — one that had already struck would be gone anyway.
func _test_no_live_hazard_crosses_the_boundary() -> void:
	if not await _open_boss_room(1303):
		return

	_defeat_the_boss()
	await advance_physics(1)

	var lane := _paint_lane_over_player(LETHAL_DAMAGE, 60.0)
	var shot := _commit_shot_at_player()
	check(
		is_instance_valid(lane) and is_instance_valid(shot),
		"an unresolved lane and shot are live when the reward is taken",
	)

	_floor._on_boss_reward_taken(_floor.config.get_items()[0])
	await advance_physics(6)

	check(not is_instance_valid(lane), "the lane does not follow the player down the stairs")
	check(not is_instance_valid(shot), "nor does the shot")
	check(not _player.is_dead(), "and the lethal lane cannot strike on the next floor")
	check(GameManager.state == GameManager.State.RUN, "which is still running")

	await _close()


# --- Fixtures -----------------------------------------------------------------


## Opens a floor and stands the player in its boss arena, without waking the boss.
##
## The boss is not spawned on purpose. Every check here is about what the *floor* does once a boss
## is dead, and a live boss would add its own attacks to the hazards being counted. Defeat is driven
## through `_on_boss_defeated` directly, the way every other floor-advance check in this project
## does it; the two checks that need a real boss build their own arena.
func _open_boss_room(seed_value: int) -> bool:
	_arena = Node2D.new()
	add_child(_arena)
	_floor = FLOOR_SCENE.instantiate()
	_arena.add_child(_floor)
	_player = PLAYER_SCENE.instantiate()
	_arena.add_child(_player)

	GameManager.start_run()
	RunManager.begin_run(seed_value)
	if not _floor.build(_player, seed_value):
		fail("the floor must build to check what happens on it after a boss dies")
		return false

	var boss_room := _boss_room()
	if boss_room == null:
		fail("the floor has no boss room")
		return false

	_player.global_position = boss_room.get_interior_rect().get_center()
	# No invulnerability window: these checks measure whether a hazard lands, and a grace period
	# would make that depend on how many frames the check happened to advance.
	_player.get_health_component().configure(3.0, 0.0)
	await advance_physics(2)
	return true


## Kills the boss the way the floor hears about it, with a stand-in for the body — freed rather
## than dropped, because `Node` is not reference counted.
func _defeat_the_boss() -> void:
	var stand_in := Node.new()
	_floor._on_boss_defeated(stand_in, _boss_room())
	stand_in.free()


## An enemy shot sitting on the player: committed, stationary, and unable to expire before the
## check is done with it. Stationary because a moving shot's arrival depends on frame counts, and
## this is a check about ownership rather than about ballistics.
func _commit_shot_at_player() -> Projectile:
	var shot := (load(RIVET_CONFIG) as ProjectileConfig).spawn_copy()
	shot.speed = 0.0
	shot.lifetime = 600.0
	return ProjectileFactory.spawn_configured(
		_floor.get_session().projectiles,
		shot,
		Vector2.RIGHT,
		_player.global_position,
		Teams.Id.ENEMY,
	)


## A lane covering the player, as a boss would have painted it a moment before dying.
func _paint_lane_over_player(damage: float, telegraph: float) -> CompileLane:
	var size := Vector2(48.0, 48.0)
	return CompileLane.spawn(
		_floor, Rect2(_player.global_position - size * 0.5, size), damage, telegraph, 0.2
	)


func _reward_stands_present() -> bool:
	for node: Node in _boss_room().get_children():
		if node is ShopRoom:
			return true
	return false


func _boss_room() -> Room:
	for plan: RoomPlan in _floor.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			return _floor.get_room(plan.id)
	return null


## Projectiles and lanes, which is what "a hazard" means for the purposes of this suite.
func _hazards_in(container: Node) -> int:
	var found := 0
	for child: Node in container.get_children():
		if child is Projectile or child is CompileLane:
			found += 1
	return found


## A copy of a boss's tuning with its clocks shortened. Duplicated rather than edited: `config` is
## an ExtResource shared by every instance the process loads, and shortening the original would
## leave the real fight faster for whatever ran after this suite.
func _hastened(source: Resource) -> Resource:
	var fast := source.duplicate()
	for pair: Array in [
		["phase_one_interval", FAST_INTERVAL],
		["phase_two_interval", FAST_INTERVAL],
		["phase_three_interval", FAST_INTERVAL],
		["telegraph_seconds", FAST_WINDUP],
		["lane_telegraph_seconds", FAST_LANE_TELEGRAPH],
		["lane_strike_seconds", FAST_LANE_STRIKE],
		["lane_stagger_seconds", FAST_LANE_STAGGER],
	]:
		if pair[0] in fast:
			fast.set(pair[0], pair[1])
	return fast


## Damage past any plausible pool, delivered the way the fight delivers it, so the boss's own
## death path runs rather than a flag being set behind its back.
func _kill(boss: Boss) -> void:
	for part: BossPart in _parts_of(boss):
		part.took_damage.emit(DamageInfo.new(9999.0))


## Both bosses expose their bodies, under different names: The Scrap King can have two, Runtime
## Error only ever has one.
func _parts_of(boss: Boss) -> Array[BossPart]:
	if boss.has_method("get_parts"):
		return boss.get_parts()
	var single: BossPart = boss.get_part()
	return [single] if single != null else [] as Array[BossPart]


## Leaves the tree unpaused and the arena gone. A check that ends in GAME_OVER would otherwise
## freeze every suite that runs after this one.
func _close() -> void:
	GameManager.start_run()
	_arena.queue_free()
	_arena = null
	_floor = null
	_player = null
	await advance_physics(2)

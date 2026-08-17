extends TestCase
## Checks for README's Floor 2 boss, Runtime Error.
##
## The Scrap King's suite is about a fight that deceives the player, so it pins the deception.
## This one is the opposite fight and the checks follow: Runtime Error hides nothing, and what
## is worth proving is that it stays honest. README promises it "remains damageable through all
## three phases", so damage is measured in each of them and expected to land in full. Its bar
## is the real pool rather than the phase, so it is expected to fall and never refill.
##
## The heavier half of this suite is the acceptance criterion README states for the whole floor:
## "Compile lanes and boss patterns always telegraph a reachable safe answer." That is not a
## property of any one method — it falls out of the geometry of six separate patterns — so it is
## checked the way the player experiences it: run the fight, catch every lane at the moment it
## executes, and assert there was somewhere to stand. A boss that painted a board with no gap in
## it would break nothing and throw no error; it would simply be unfair, and only a test that
## measures the floor it leaves clear would notice.
##
## The boss is damaged through its part rather than by reaching into its health, because the
## part is the only thing a projectile can hit and the forwarding between them is precisely what
## could break.

const BOSS_SCENE := preload("res://scenes/bosses/runtime_error.tscn")
const FLOOR_SCENE := preload("res://scenes/floors/floor.tscn")

## The Scrap King's body, loaded only to be measured against. This suite never fights it.
const KING_PART_SCENE := preload("res://scenes/bosses/boss_part.tscn")

## How far the sprite is allowed to reach past the hitbox, in pixels. Runtime Error sheds four
## small shards off the faces of its core diamond, and those are deliberately outside what can be
## hit — the one honest way for a silhouette to be bigger than its body is for the extra part to
## be visibly detached from it.
const SHARD_ALLOWANCE := 4.0
const BOSS_CONFIG_PATH := "res://data/bosses/runtime_error.tres"
const FLOOR_2_CONFIG_PATH := "res://data/floors/floor_2_development.tres"
const COMPILER_CONFIG_PATH := "res://data/enemies/compiler.tres"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RIVET_PATH := "res://data/projectiles/rivet.tres"

## The room interior a boss arena actually is: 26x12 tiles. The lane geometry divides this
## exactly, and checking it against anything else would prove the division rather than the boss.
const ARENA := Rect2(Vector2.ZERO, Vector2(416.0, 192.0))

## What the fight is compressed to for the tests. The shipped timings are tuned for a player's
## reading speed, and a suite that waited them out would spend most of a minute proving things
## a tenth of that proves just as well. The shipped values are checked as values, in
## `_test_config_matches_the_plan`; these only have to preserve the *ordering* the patterns
## depend on — a lane still telegraphs before it strikes, and the stagger is still shorter than
## the telegraph it interrupts.
const TEST_INTERVAL := 0.3
const TEST_WINDUP := 0.1
const TEST_LANE_TELEGRAPH := 0.2
const TEST_LANE_STRIKE := 0.05
const TEST_LANE_STAGGER := 0.15

## How finely the arena is sampled when asking whether a pattern left anywhere to stand.
## Smaller than the player, so a gap it could fit through cannot fall between two samples.
const SAFETY_SAMPLE_STEP := 4.0

var _config: RuntimeErrorConfig
var _arena: Node2D
var _boss: RuntimeError

## Every lane strike since `_watch_lanes`, and the physics frame each one landed on. Two
## parallel arrays rather than an array of dictionaries because every reader below wants one or
## the other, never a record of both.
var _lane_rects: Array[Rect2] = []
var _lane_frames: Array[int] = []
var _lane_watcher := Callable()


func run() -> void:
	_config = load(BOSS_CONFIG_PATH) as RuntimeErrorConfig
	if not require(_config, "runtime_error.tres loads as a RuntimeErrorConfig"):
		return

	_test_config_matches_the_plan()
	_test_it_speaks_the_compilers_warning_language()
	_test_the_hud_calls_it_by_its_name()
	_test_every_floor_can_draw_every_boss()

	await _test_it_starts_in_its_first_phase()
	await _test_it_is_a_smaller_target_than_the_first_boss()
	await _test_it_never_stops_moving_and_never_closes()
	await _test_it_is_damageable_in_every_phase()
	await _test_the_phases_change_at_their_thresholds()
	await _test_one_huge_hit_lands_in_the_phase_it_earned()
	await _test_the_bar_falls_and_never_refills()
	await _test_the_fight_ends_once()
	await _test_every_phase_acts()
	await _test_the_first_phase_paints_one_lane_at_a_time()
	await _test_the_second_phases_lanes_are_staggered_in_time()
	await _test_the_third_phase_paints_alternating_checkerboards()
	await _test_every_pattern_leaves_somewhere_to_stand()
	await _test_the_boss_fights_inside_its_arena()
	await _test_real_projectiles_drive_the_whole_fight()
	await _test_the_floor_spawns_it_in_a_real_boss_room()


# --- Configuration ------------------------------------------------------------


func _test_config_matches_the_plan() -> void:
	check(
		_config.phase_two_at > _config.phase_three_at,
		"the phase thresholds are in order (%.2f then %.2f)" % [
			_config.phase_two_at, _config.phase_three_at,
		],
	)
	check(
		_config.phase_two_at < 1.0 and _config.phase_three_at > 0.0,
		"and both are inside the pool, so all three phases are reachable",
	)
	check(_config.shot != null, "it has something to fire")
	# README: "projectile rings that have visible gaps" and "projectile walls with a traversable
	# opening". A ring or wall with no gap is a pattern with no answer.
	check(_config.ring_gap > 0 and _config.ring_gap < _config.ring_count, "its rings have a gap")
	check(_config.wall_gap > 0 and _config.wall_gap < _config.wall_count, "its walls have an opening")
	check(
		_config.checker_cols >= 2 and _config.checker_rows >= 2,
		"its checkerboard is a board rather than a stripe",
	)
	check(
		_config.lane_stagger_seconds > 0.0,
		"phase two's two lanes are staggered rather than simultaneous",
	)
	# The stagger has to land inside the first lane's telegraph. Longer, and the second lane
	# would appear only after the first had already struck, which is two lanes in a row rather
	# than the staggered pair README asks for.
	check(
		_config.lane_stagger_seconds < _config.lane_telegraph_seconds,
		"and the second appears while the first is still telegraphing (%.2fs into %.2fs)" % [
			_config.lane_stagger_seconds, _config.lane_telegraph_seconds,
		],
	)
	# The number that makes the whole mechanic fair, checked as distance rather than as time:
	# the player covers this much floor while a lane is amber, and the thickest thing they ever
	# have to leave is one checkerboard cell.
	var player_config: PlayerConfig = load("res://data/player/player_config.tres")
	if require(player_config, "the player config loads"):
		var reach := player_config.move_speed * _config.lane_telegraph_seconds
		var cell_height := ARENA.size.y / float(_config.checker_rows)
		check(
			reach > cell_height,
			"a lane's telegraph is long enough to walk out of the deepest pattern "
				+ "(%.0f pixels of travel against a %.0f-pixel cell)" % [reach, cell_height],
		)


## README: "The boss must use the same amber-then-red warning language as the Compiler." The
## strongest form of that is what the code already does — both paint `CompileLane`s, so the
## colours cannot disagree — but the *timings* are separate fields and could drift into a boss
## whose lanes flash past faster than the enemy that taught the player to read them.
func _test_it_speaks_the_compilers_warning_language() -> void:
	var compiler: CompilerConfig = load(COMPILER_CONFIG_PATH) as CompilerConfig
	if not require(compiler, "the Compiler's config loads"):
		return
	check(
		_config.lane_telegraph_seconds >= compiler.lane_telegraph_seconds * 0.75,
		"the boss's lanes telegraph on the same order as the Compiler's (%.2fs against %.2fs)" % [
			_config.lane_telegraph_seconds, compiler.lane_telegraph_seconds,
		],
	)
	check(
		is_equal_approx(_config.lane_damage, compiler.lane_damage),
		"and a lane costs what a lane costs, whoever painted it",
	)


## The boss's name exists in two places — its own resource and its `BossEncounter`, which is
## what the HUD is actually bound to — because nothing hands the HUD a config directly. The
## same guard test_boss.gd puts on The Scrap King, for the same reason: two copies of a name is
## the arrangement that ends with a boss bar labelled with the name the boss used to have.
func _test_the_hud_calls_it_by_its_name() -> void:
	var floor_config: FloorConfig = load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(floor_config, "floor_2_development.tres loads as a FloorConfig"):
		return
	var encounter := _find_encounter(floor_config, &"runtime_error")
	if not require(encounter, "Development's boss pool offers Runtime Error"):
		return
	check(
		encounter.display_name == _config.display_name.to_upper(),
		"the boss bar says '%s' and the boss is called '%s'" % [
			encounter.display_name, _config.display_name,
		],
	)
	check(
		encounter.scene != null and encounter.scene.resource_path == BOSS_SCENE.resource_path,
		"and it points at this boss rather than the greybox it replaced",
	)


## Any boss may guard any floor. Checked from Runtime Error's suite because it is the boss that
## kept gaining floors — it was Development's and nothing else's, then the Help Desk's too, and now
## the Data Center's as well.
##
## Stated as "every floor names every boss" rather than as three separate memberships, because the
## property the campaign actually wants is that the pools are *identical*: a boss missing from one
## floor is a fight that only appears at one depth, which is the state this replaced. The three ids
## are spelled out rather than derived from a pool, so dropping a boss from every floor at once
## fails here instead of trivially passing.
func _test_every_floor_can_draw_every_boss() -> void:
	var floors: Array = [
		[load("res://data/floors/floor_1_help_desk.tres"), "the Help Desk"],
		[load(FLOOR_2_CONFIG_PATH), "Development"],
		[load("res://data/floors/floor_3_data_center.tres"), "the Data Center"],
	]

	for pair: Array in floors:
		var config: FloorConfig = pair[0] as FloorConfig
		if not require(config, "%s's config loads" % pair[1]):
			continue
		check(
			config.boss_pool.size() >= 3,
			"%s can draw any of them (%d in its pool)" % [pair[1], config.boss_pool.size()],
		)
		for id: StringName in [&"merge_conflict", &"runtime_error", &"cascade_failure"]:
			check(
				_find_encounter(config, id) != null,
				"%s can draw '%s'" % [pair[1], id],
			)


func _find_encounter(floor_config: FloorConfig, id: StringName) -> BossEncounter:
	for entry: BossEncounter in floor_config.boss_pool:
		if entry != null and entry.id == id:
			return entry
	return null


# --- The fight ----------------------------------------------------------------


func _test_it_starts_in_its_first_phase() -> void:
	await _begin()
	check(_boss.get_phase() == RuntimeError.Phase.SINGLE_LANE, "it starts in phase one")
	check(_boss.get_part() != null, "with a body to shoot at")
	check_near(_boss.get_health_ratio(), 1.0, "at full health")
	await _teardown()


## Small is a mechanic here, not a look, so it is checked as a number. The body is its own scene
## with its own hitbox precisely so this can differ from The Scrap King's, and a change that
## quietly pointed it back at the shared `boss_part.tscn` would restore the King's 14-pixel
## radius and the King's sprite without breaking anything else.
func _test_it_is_a_smaller_target_than_the_first_boss() -> void:
	await _begin()
	var part := _boss.get_part()
	if not require(part, "the boss has a body"):
		await _teardown()
		return

	# Read off the node paths rather than through `get_sprite()`/`%Sprite`: the King's body is
	# instantiated to be measured, never added to a tree, so its `@onready` members are still
	# null. Everything needed is pulled out and the instance freed before a single check runs,
	# so a failing assertion cannot leak it.
	var king: BossPart = KING_PART_SCENE.instantiate()
	var mine := (part.get_node("Shape") as CollisionShape2D).shape as CircleShape2D
	var theirs := (king.get_node("Shape") as CollisionShape2D).shape as CircleShape2D
	var texture := (part.get_node("Sprite") as Sprite2D).texture
	var king_texture := (king.get_node("Sprite") as Sprite2D).texture
	king.free()

	if require(mine and theirs, "both bosses' bodies are circles"):
		check(
			mine.radius < theirs.radius,
			"Runtime Error is a smaller target than The Scrap King (%.0f against %.0f)" % [
				mine.radius, theirs.radius,
			],
		)
		# The claim the change was made for, as area rather than radius, since area is what a
		# player's aim actually contends with.
		check(
			mine.radius * mine.radius <= theirs.radius * theirs.radius * 0.5,
			"and at most half the area to hit (%.0f%% of it)" % [
				100.0 * (mine.radius * mine.radius) / (theirs.radius * theirs.radius),
			],
		)

	# Its own sprite as well as its own hitbox: the two are the same change, and a body wearing
	# the King's art would be a second Scrap King whatever its collision shape said.
	if require(texture and king_texture, "both bodies have a sprite"):
		check(
			texture.resource_path != king_texture.resource_path,
			"and it does not wear the first boss's art (%s)" % texture.resource_path.get_file(),
		)
		# A sprite larger than the body it stands for is the complaint boss_part.tscn's own
		# comment records: shots the player swears they hit. Half the sprite's width is the
		# furthest any of it reaches from the centre.
		check(
			texture.get_width() * 0.5 <= mine.radius + SHARD_ALLOWANCE,
			"whose art does not overhang its hitbox by more than the shards it sheds "
				+ "(%d-pixel sprite, %.0f-pixel radius)" % [texture.get_width(), mine.radius],
		)

	await _teardown()


## The other half of "hard to hit": a small target that held still would be hard to hit exactly
## once. Two claims, and they pull against each other — it has to keep moving, and it must not
## use that movement to close on the player, because this fight is not fought at contact range.
func _test_it_never_stops_moving_and_never_closes() -> void:
	await _begin()
	var part := _boss.get_part()
	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
	if not require(part and player, "there is a body and a player"):
		await _teardown()
		return

	# Let it reach its station first, so what is measured is the sway and not the opening
	# approach from the middle of the arena.
	await advance_physics(60)

	var travelled := 0.0
	var closest := INF
	var last := part.global_position
	var swept_left := false
	var swept_right := false

	# A full sweep at the shipped rate, and then some.
	for _frame: int in int(TAU / _config.sway_speed * 60.0) + 30:
		await advance_physics(1)
		if not is_instance_valid(part):
			break
		travelled += part.global_position.distance_to(last)
		last = part.global_position
		closest = minf(closest, part.global_position.distance_to(player.global_position))
		var offset := part.global_position.x - player.global_position.x
		swept_left = swept_left or offset < -_config.sway_amplitude * 0.5
		swept_right = swept_right or offset > _config.sway_amplitude * 0.5

	check(travelled > _config.sway_amplitude * 2.0, "it never stops moving (%.0f pixels)" % travelled)
	check(swept_left and swept_right, "and sweeps to both sides of the player rather than one")
	# Never closes: the drift height is the distance it holds, and it may not spend the fight
	# converging on the player the way a chaser would.
	check(
		closest > _config.drift_height * 0.5,
		"and never closes on the player (nearest approach %.0f pixels)" % closest,
	)
	await _teardown()


## README: "It remains damageable through all three phases." There is no refund, no scaling and
## no window where hits stop counting, and this is that promise measured — in every phase,
## against the same ten damage, expecting all ten of it. The Scrap King's equivalent checks are
## the exact opposite, which is the point: these are two different kinds of fight.
func _test_it_is_damageable_in_every_phase() -> void:
	await _begin()

	for phase: RuntimeError.Phase in [
		RuntimeError.Phase.SINGLE_LANE,
		RuntimeError.Phase.STAGGERED_LANES,
		RuntimeError.Phase.CHECKERBOARD,
	]:
		await _drive_to(phase)
		if _boss.get_phase() != phase:
			fail("the boss reached phase %d" % int(phase))
			continue
		var before := _boss.get_health()
		_hurt(10.0)
		check_near(
			before - _boss.get_health(), 10.0, "ten damage costs it ten in phase %d" % int(phase)
		)

	await _teardown()


func _test_the_phases_change_at_their_thresholds() -> void:
	await _begin()

	# Just short of the first threshold.
	_hurt(_config.max_health * (1.0 - _config.phase_two_at) * 0.5)
	check(
		_boss.get_phase() == RuntimeError.Phase.SINGLE_LANE,
		"above the first threshold it stays in phase one",
	)

	await _drive_to(RuntimeError.Phase.STAGGERED_LANES)
	check(_boss.get_phase() == RuntimeError.Phase.STAGGERED_LANES, "crossing it enters phase two")
	check(_boss.get_health() > 0.0, "with the fight still going")

	await _drive_to(RuntimeError.Phase.CHECKERBOARD)
	check(_boss.get_phase() == RuntimeError.Phase.CHECKERBOARD, "and the second enters phase three")
	check(_boss.get_health() > 0.0, "still alive to fight in it")
	await _teardown()


## The Scrap King floors its health at each phase boundary so that no build can skip the feigned
## death that is the point of that fight. This boss has no trick to protect, so it does the
## honest thing instead: a hit that crosses two thresholds lands in the phase it earned. Worth
## pinning because the phase is derived from the ratio rather than stepped one at a time, and a
## stepped implementation would look identical until exactly this hit.
func _test_one_huge_hit_lands_in_the_phase_it_earned() -> void:
	await _begin()
	# Just past the *second* threshold in one blow, which is also past the first: the damage that
	# lands exactly on it, plus one, so the check is about the phase rather than about a boundary.
	_hurt(_config.max_health * (1.0 - _config.phase_three_at) + 1.0)
	check(
		_boss.get_phase() == RuntimeError.Phase.CHECKERBOARD,
		"one hit past both thresholds arrives in the last phase rather than the next one",
	)
	check(_boss.get_health() > 0.0, "and has not ended the fight")
	await _teardown()


## The honest bar, which is this fight's answer to The Scrap King's lying one. Its bar empties
## three times and refills twice; this one falls once. Worth a test rather than trusting the
## arithmetic, because a bar that refilled would break nothing — it would simply tell the player
## the fight had restarted, and nobody would get an error.
func _test_the_bar_falls_and_never_refills() -> void:
	await _begin()

	var ratios: Array[float] = []
	var handler := func(ratio: float) -> void: ratios.append(ratio)
	EventBus.boss_health_changed.connect(handler)

	for _step: int in 8:
		_hurt(_config.max_health * 0.15)
		await advance_physics(2)

	EventBus.boss_health_changed.disconnect(handler)

	if not require(ratios.size() > 1, "the bar was announced more than once"):
		await _teardown()
		return

	var rose := false
	for index: int in range(1, ratios.size()):
		if ratios[index] > ratios[index - 1] + 0.001:
			rose = true
	check(not rose, "the bar never refills across the whole fight")
	check_near(ratios[ratios.size() - 1], 0.0, "and the one time it empties, the fight is over")
	await _teardown()


func _test_the_fight_ends_once() -> void:
	await _begin()
	await _drive_to(RuntimeError.Phase.CHECKERBOARD)

	var defeats := [0]
	var handler := func(_boss_node: Node) -> void: defeats[0] += 1
	EventBus.boss_defeated.connect(handler)

	# Overkill, twice, through a part that no longer exists after the first blow.
	var part := _boss.get_part()
	_hurt(_config.max_health * 4.0)
	await advance_physics(2)
	if is_instance_valid(part):
		part.took_damage.emit(DamageInfo.new(50.0))
	await advance_physics(2)

	check(defeats[0] == 1, "the boss is defeated exactly once")
	check_near(_boss.get_health(), 0.0, "and has no health left")
	check(_boss.get_part() == null, "and leaves no body behind")

	EventBus.boss_defeated.disconnect(handler)
	await _teardown()


## Every phase alternates a lane pattern with a projectile pattern, so every phase has to produce
## both — that is what "alternating" claims, and a phase that quietly only ever fired one half of
## its rotation would still look busy. A phase producing nothing at all would look like the boss
## thinking, and none of the checks above would notice either.
func _test_every_phase_acts() -> void:
	await _begin()
	var container := _arena.get_node("Projectiles")

	for phase: RuntimeError.Phase in [
		RuntimeError.Phase.SINGLE_LANE,
		RuntimeError.Phase.STAGGERED_LANES,
		RuntimeError.Phase.CHECKERBOARD,
	]:
		await _drive_to(phase)
		var lanes := [0]
		var projectiles := [0]
		var handler := func(child: Node) -> void:
			if child is CompileLane:
				lanes[0] += 1
			else:
				projectiles[0] += 1
		container.child_entered_tree.connect(handler)
		# Long enough for both halves of the phase's rotation to come round several times.
		await advance_physics(_frames(TEST_INTERVAL * 8.0))
		container.child_entered_tree.disconnect(handler)

		check(lanes[0] > 0, "phase %d paints lanes (%d)" % [int(phase), lanes[0]])
		check(
			projectiles[0] > 0,
			"and phase %d fires projectiles too, so it really alternates (%d)" % [
				int(phase), projectiles[0],
			],
		)

	await _teardown()


# --- Lane patterns ------------------------------------------------------------


## README's phase one: "One compile lane at a time." One is the assertion — a phase one that
## painted two would be phase two arriving early, and the player would meet the harder pattern
## before the lesson that prepares them for it.
func _test_the_first_phase_paints_one_lane_at_a_time() -> void:
	await _begin()
	_watch_lanes()
	await advance_physics(_frames(TEST_INTERVAL * 6.0))
	_unwatch_lanes()

	var groups := _lanes_by_frame()
	if not require(not groups.is_empty(), "phase one painted a lane"):
		await _teardown()
		return
	for frame: int in groups:
		check(
			groups[frame].size() == 1,
			"phase one strikes one lane at a time (%d struck together)" % groups[frame].size(),
		)
	await _teardown()


## README's phase two: "Two staggered lanes." Staggered is a claim about *time*, so it is
## checked in time: no two lanes may ever strike on the same frame, and more than one must strike
## over the window. Two lanes painted together would be a pattern the player has to survive from
## one position rather than one they walk out of twice, which is a different and much harder
## attack wearing this one's name.
func _test_the_second_phases_lanes_are_staggered_in_time() -> void:
	await _begin()
	await _drive_to(RuntimeError.Phase.STAGGERED_LANES)

	_watch_lanes()
	await advance_physics(_frames(TEST_INTERVAL * 8.0))
	_unwatch_lanes()

	var groups := _lanes_by_frame()
	if not require(_lane_rects.size() >= 2, "phase two painted more than one lane"):
		await _teardown()
		return
	var simultaneous := 0
	for frame: int in groups:
		if groups[frame].size() > 1:
			simultaneous += 1
	check(simultaneous == 0, "no two of phase two's lanes ever strike on the same frame")
	await _teardown()


## README's phase three: "Alternating checkerboard execution zones." Both halves matter. A board
## must arrive as a board — many cells at once, which is what makes it a board rather than a
## lane — and consecutive boards must be different, or the answer to the second one is to stand
## still, and the pattern stops asking anything.
func _test_the_third_phase_paints_alternating_checkerboards() -> void:
	await _begin()
	await _drive_to(RuntimeError.Phase.CHECKERBOARD)

	_watch_lanes()
	await advance_physics(_frames(TEST_INTERVAL * 10.0))
	_unwatch_lanes()

	var boards: Array[Array] = []
	var groups := _lanes_by_frame()
	var frames := groups.keys()
	frames.sort()
	for frame: int in frames:
		if groups[frame].size() > 1:
			boards.append(groups[frame])

	if not require(boards.size() >= 2, "phase three painted at least two boards"):
		await _teardown()
		return

	var expected := _config.checker_cols * _config.checker_rows / 2
	check(
		boards[0].size() == expected,
		"a board lights half its cells at once (%d of %d)" % [
			boards[0].size(), _config.checker_cols * _config.checker_rows,
		],
	)
	# The parity flip, expressed as what the player would see: no cell of one board is a cell of
	# the next. A board that repeated would share all of them.
	var repeated := 0
	for rect: Rect2 in boards[1]:
		for previous: Rect2 in boards[0]:
			if rect.position.is_equal_approx(previous.position):
				repeated += 1
	check(repeated == 0, "and the board that follows it is its negative, not a repeat")
	await _teardown()


## README's acceptance criterion for the whole floor: "Compile lanes and boss patterns always
## telegraph a reachable safe answer." Checked across every phase at once, because the property
## belongs to the fight rather than to any one pattern — six patterns, each of which has to leave
## somewhere to stand, and the only way to be sure is to look at what they actually painted.
##
## Measured against the rectangle `CompileLane` really tests, grown by the player's radius: a gap
## exactly as wide as the player is a gap they do not fit through.
func _test_every_pattern_leaves_somewhere_to_stand() -> void:
	await _begin()
	_watch_lanes()

	# Through all three phases, staying in each long enough for both its patterns to come round
	# several times.
	await advance_physics(_frames(TEST_INTERVAL * 6.0))
	await _drive_to(RuntimeError.Phase.STAGGERED_LANES)
	await advance_physics(_frames(TEST_INTERVAL * 8.0))
	await _drive_to(RuntimeError.Phase.CHECKERBOARD)
	await advance_physics(_frames(TEST_INTERVAL * 10.0))

	_unwatch_lanes()

	var groups := _lanes_by_frame()
	if not require(groups.size() >= 3, "the fight painted lanes in all three phases"):
		await _teardown()
		return

	var unanswerable := 0
	for frame: int in groups:
		if not _safe_point_exists(groups[frame]):
			unanswerable += 1
	check(
		unanswerable == 0,
		"every one of the %d patterns painted left somewhere to stand" % groups.size(),
	)
	await _teardown()


# --- Placement and plumbing ---------------------------------------------------


## The boss is a child of the room it fights in, and that room is offset onto the floor grid. A
## body positioned in local space when global was meant fights outside its own arena, and its
## lanes would be painted across a strip of floor the player is not standing on. Checked with
## the controller off the origin, because at the origin the mistake is invisible.
func _test_the_boss_fights_inside_its_arena() -> void:
	RunManager.begin_run(777)
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

	var part := _boss.get_part()
	if require(part, "the boss has a body"):
		check(
			arena_rect.has_point(part.global_position),
			# %s, not %v: the position is a vector but the arena is a Rect2, and %v rejects it.
			"the boss stands inside its arena (at %v, arena %s)" % [part.global_position, arena_rect],
		)

	_watch_lanes()
	await advance_physics(_frames(TEST_INTERVAL * 4.0))
	_unwatch_lanes()

	if require(not _lane_rects.is_empty(), "and painted a lane there"):
		var outside := 0
		for rect: Rect2 in _lane_rects:
			if not arena_rect.intersects(rect):
				outside += 1
		check(outside == 0, "every lane it painted is inside that arena too")

	await _teardown()


## The fight driven the way the game drives it: real projectiles, real collision, real hit
## callbacks. Every other check here damages the boss by emitting `took_damage` directly, which
## is a faithful test of the forwarding and a blind spot for everything upstream of it.
func _test_real_projectiles_drive_the_whole_fight() -> void:
	await _begin()

	var part := _boss.get_part()
	if not require(part, "the boss has a body to shoot"):
		await _teardown()
		return

	var before := _boss.get_health()
	_shoot(part, 5.0)
	await advance_physics(12)
	check(_boss.get_health() < before, "a real projectile damages the boss")

	# Across a phase change, which is the moment a boss is most likely to stop being shootable:
	# the phase is entered from inside the projectile's own hit callback.
	_hurt(_config.max_health * (1.0 - _config.phase_two_at))
	await advance_physics(4)
	check(_boss.get_phase() == RuntimeError.Phase.STAGGERED_LANES, "and it reaches the next phase")

	var after_change := _boss.get_health()
	_shoot(_boss.get_part(), 5.0)
	await advance_physics(12)
	check(_boss.get_health() < after_change, "where it is still there to be shot")

	await _teardown()


## The boss as the game actually produces it, rather than as this suite builds it: a real
## Development floor, a real generated boss room, and `FloorController` doing the spawning. Every
## other check here hands the boss a `Rect2` and a container of its own, which is a faithful test
## of the fight and a blind spot for the seam around it — the arena it is really given is a room
## offset onto the floor grid, its lanes are parented to a container it has to find in the tree,
## and it is added a frame late from inside an Area2D callback. None of that is exercised by an
## arena built to suit it.
##
## Run on the shipped config rather than the compressed one, since the point is the floor's own
## wiring: what is asserted is that the boss arrives, and that what it paints lands in the room
## the player is sealed into rather than somewhere on the grid beside it.
func _test_the_floor_spawns_it_in_a_real_boss_room() -> void:
	var shipped: FloorConfig = load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(shipped, "the Development floor config loads"):
		return

	# Either boss can guard either floor now, so the shipped config would spawn whichever the
	# seed drew and this check would pass or fail by coin flip. The pool is narrowed to Runtime
	# Error on a *duplicate*, leaving everything else about the floor shipped — the point of
	# this check is the floor's wiring around a boss, not which boss it happened to pick.
	var floor_config := shipped.duplicate() as FloorConfig
	var only_runtime_error: Array[BossEncounter] = []
	var wanted := _find_encounter(shipped, &"runtime_error")
	if not require(wanted, "Runtime Error is in Development's boss pool"):
		return
	only_runtime_error.append(wanted)
	floor_config.boss_pool = only_runtime_error

	var arena := Node2D.new()
	add_child(arena)
	var floor_node: FloorController = FLOOR_SCENE.instantiate()
	floor_node.config = floor_config
	arena.add_child(floor_node)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	await advance_physics(1)

	GameManager.start_run()
	RunManager.begin_run(4242)
	if not require(floor_node.build(player, 4242), "the Development floor builds"):
		arena.queue_free()
		await advance_physics(1)
		return

	var boss_room: Room = null
	for plan: RoomPlan in floor_node.layout.rooms:
		if plan.type == RoomTemplate.Type.BOSS:
			boss_room = floor_node.get_room(plan.id)
	if not require(boss_room, "it generated a boss room"):
		arena.queue_free()
		await advance_physics(1)
		return

	# The player walks in, which is the only thing that wakes a boss. Teleporting is what a
	# doorway amounts to here: the room's entry Area2D reports the body on the next physics step.
	player.get_health_component().configure(9999.0, 0.0)
	player.global_position = boss_room.get_interior_centre()
	_watch_lanes()
	await advance_physics(4)

	check(
		floor_node.current_room_id == boss_room.plan.id,
		"walking in registers the player as being in the boss room",
	)

	var boss: RuntimeError = null
	for child: Node in boss_room.get_children():
		if child is RuntimeError:
			boss = child
	if not require(boss, "the floor spawned Runtime Error into it"):
		_unwatch_lanes()
		arena.queue_free()
		await advance_physics(1)
		return

	check(boss.get_part() != null, "with a body to shoot at")
	var interior := boss_room.get_interior_rect()
	check(
		interior.has_point(boss.get_part().global_position),
		"standing inside the room rather than beside it on the grid",
	)

	# Long enough for the shipped interval plus the shipped lane telegraph, so a real lane has
	# time to be painted and to execute.
	await advance_physics(
		_frames(_config.phase_one_interval + _config.lane_telegraph_seconds + 0.5)
	)
	_unwatch_lanes()

	if require(not _lane_rects.is_empty(), "and it paints lanes on a real floor"):
		var strayed := 0
		for rect: Rect2 in _lane_rects:
			if not interior.encloses(rect):
				strayed += 1
		check(strayed == 0, "every one of them inside the room the player is sealed into")

	arena.queue_free()
	await advance_physics(1)


# --- Lane observation ---------------------------------------------------------


## Lanes are watched through `EventBus.compile_lane_executed` rather than by walking the
## projectile container, because that signal carries the rectangle the lane actually struck —
## the same geometry `CompileLane` measured the player against. Anything read off the node
## instead would be this suite's opinion of where the lane was.
func _watch_lanes() -> void:
	_lane_rects.clear()
	_lane_frames.clear()
	_lane_watcher = func(rect: Rect2) -> void:
		_lane_rects.append(rect)
		_lane_frames.append(Engine.get_physics_frames())
	EventBus.compile_lane_executed.connect(_lane_watcher)


func _unwatch_lanes() -> void:
	if _lane_watcher.is_valid() and EventBus.compile_lane_executed.is_connected(_lane_watcher):
		EventBus.compile_lane_executed.disconnect(_lane_watcher)
	_lane_watcher = Callable()


## The observed lanes grouped by the frame they struck on. One group is one *pattern* as the
## player meets it: everything that has to be answered from a single position.
func _lanes_by_frame() -> Dictionary[int, Array]:
	var groups: Dictionary[int, Array] = {}
	for index: int in _lane_rects.size():
		var frame := _lane_frames[index]
		if not groups.has(frame):
			groups[frame] = []
		groups[frame].append(_lane_rects[index])
	return groups


## Whether anywhere in the arena is outside every one of `rects`. Sampled rather than solved,
## because the patterns are axis-aligned rectangles over a small arena and a sample finer than
## the player cannot miss a gap the player could use.
func _safe_point_exists(rects: Array) -> bool:
	var grown: Array[Rect2] = []
	for rect: Rect2 in rects:
		grown.append(rect.grow(CompileLane.PLAYER_RADIUS))

	var y := ARENA.position.y
	while y <= ARENA.end.y:
		var x := ARENA.position.x
		while x <= ARENA.end.x:
			var point := Vector2(x, y)
			var caught := false
			for rect: Rect2 in grown:
				if rect.has_point(point):
					caught = true
					break
			if not caught:
				return true
			x += SAFETY_SAMPLE_STEP
		y += SAFETY_SAMPLE_STEP
	return false


# --- Fixtures -----------------------------------------------------------------


## A boss configured like the shipped one except for compressed timings. Duplicated rather than
## edited: `config` is an ExtResource shared by every instance the process loads, and editing the
## original would leave the real fight compressed for whatever ran after this suite.
func _new_boss() -> RuntimeError:
	var boss: RuntimeError = BOSS_SCENE.instantiate()
	var fast: RuntimeErrorConfig = _config.duplicate()
	fast.phase_one_interval = TEST_INTERVAL
	fast.phase_two_interval = TEST_INTERVAL
	fast.phase_three_interval = TEST_INTERVAL
	fast.telegraph_seconds = TEST_WINDUP
	fast.lane_telegraph_seconds = TEST_LANE_TELEGRAPH
	fast.lane_strike_seconds = TEST_LANE_STRIKE
	fast.lane_stagger_seconds = TEST_LANE_STAGGER
	boss.config = fast
	return boss


func _begin() -> void:
	RunManager.begin_run(24601)
	_arena = Node2D.new()
	var container := Node2D.new()
	container.name = "Projectiles"
	container.add_to_group(ProjectileFactory.CONTAINER_GROUP)
	_arena.add_child(container)
	add_child(_arena)

	var player: Player = PLAYER_SCENE.instantiate()
	player.position = ARENA.get_center() + Vector2(0.0, 60.0)
	# The boss is being tested, not the robot's survival — and this fight paints damage across
	# most of the arena on purpose.
	_arena.add_child(player)
	player.get_health_component().configure(9999.0, 0.0)

	_boss = _new_boss()
	_arena.add_child(_boss)
	_boss.begin(ARENA)
	await advance_physics(2)


func _teardown() -> void:
	_unwatch_lanes()
	_arena.queue_free()
	await advance_physics(2)


## Damages the boss until it is in `phase`, then lets the phase settle. Damage is computed from
## the threshold rather than guessed, so this still works if the thresholds move.
func _drive_to(phase: RuntimeError.Phase) -> void:
	var target := 1.0
	match phase:
		RuntimeError.Phase.STAGGERED_LANES:
			# Halfway into the phase, so the checks that follow are not sitting on a boundary.
			target = (_config.phase_two_at + _config.phase_three_at) * 0.5
		RuntimeError.Phase.CHECKERBOARD:
			target = _config.phase_three_at * 0.5
		_:
			return

	var wanted := _config.max_health * target
	if _boss.get_health() > wanted:
		_hurt(_boss.get_health() - wanted)
	await advance_physics(2)


## Damages the boss the way a projectile does: through its part, which forwards it.
func _hurt(amount: float) -> void:
	var part := _boss.get_part()
	if part != null:
		part.took_damage.emit(DamageInfo.new(amount))


## Fires a real player projectile into `target` from just outside it.
func _shoot(target: Node2D, damage: float) -> void:
	if target == null:
		return
	var config := (load(RIVET_PATH) as ProjectileConfig).spawn_copy()
	config.damage = damage
	var origin := target.global_position - Vector2(40.0, 0.0)
	var shooter := Node2D.new()
	_arena.add_child(shooter)
	ProjectileFactory.spawn_configured(
		shooter, config, Vector2.RIGHT, origin, Teams.Id.PLAYER, shooter
	)


## Physics frames covering `seconds`, plus a couple so a boundary lands inside the window rather
## than exactly on its edge.
func _frames(seconds: float) -> int:
	return int(seconds * 60.0) + 2

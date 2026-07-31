extends SceneTree
## Headless checks for the movement and dash maths that define how the robot feels.
##
## Run from the project root:
##
##     godot --headless --script res://tests/test_player_movement.gd
##
## Exits non-zero if any check fails, so it can gate a commit or a build.
##
## MotionController and DashController take a config in and return values out,
## touching neither the tree nor a physics body — that is exactly why they were
## split out of the player, and it is what makes this file possible. A plain
## assert runner is used rather than a test plugin (spec section 33.6: avoid
## plugins unless clearly justified).

const CONFIG_PATH := "res://data/player/player_config.tres"

## Fixed physics step the checks simulate against.
const FRAME := 1.0 / 60.0

var _failures: PackedStringArray = []
var _checks := 0


func _initialize() -> void:
	var config := load(CONFIG_PATH) as PlayerConfig
	if config == null:
		printerr("FAIL  could not load %s as a PlayerConfig" % CONFIG_PATH)
		quit(1)
		return

	_test_config_defaults(config)
	_test_motion_reaches_top_speed(config)
	_test_diagonal_movement_is_not_faster(config)
	_test_releasing_input_stops_the_robot(config)
	_test_dash_covers_its_configured_distance(config)
	_test_dash_lifecycle(config)
	_test_dash_recharge(config)
	_test_dash_reuses_direction_when_none_requested(config)

	_report()


# --- Checks -------------------------------------------------------------------


func _test_config_defaults(config: PlayerConfig) -> void:
	# Guards against the .tres silently losing properties during a refactor.
	_check_near(config.move_speed, 160.0, "config move_speed matches the spec")
	_check_near(config.dash_distance, 70.0, "config dash_distance matches the spec")
	_check_near(config.dash_duration, 0.14, "config dash_duration matches the spec")
	_check(config.max_integrity == 6, "config max_integrity matches the spec")


func _test_motion_reaches_top_speed(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.ZERO
	var peak := 0.0
	for _frame in 60:
		velocity = motion.step(velocity, Vector2.RIGHT, FRAME)
		peak = maxf(peak, velocity.length())

	_check_near(velocity.length(), config.move_speed, "holding a direction reaches move_speed")
	_check(peak <= config.move_speed + 0.01, "acceleration never overshoots move_speed")
	motion.free()


func _test_diagonal_movement_is_not_faster(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.ZERO
	for _frame in 60:
		velocity = motion.step(velocity, Vector2(1.0, 1.0).normalized(), FRAME)

	_check_near(velocity.length(), config.move_speed, "diagonal movement tops out at move_speed")
	motion.free()


func _test_releasing_input_stops_the_robot(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.RIGHT * config.move_speed
	# One extra frame past the theoretical braking time to absorb the discrete step.
	var frames := ceili(config.move_speed / config.deceleration / FRAME) + 1
	for _frame in frames:
		velocity = motion.step(velocity, Vector2.ZERO, FRAME)

	_check(velocity.is_zero_approx(), "releasing input brings the robot to a full stop")
	motion.free()


func _test_dash_covers_its_configured_distance(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)

	_check_near(
		dash.get_speed() * config.dash_duration,
		config.dash_distance,
		"dash speed times duration equals dash_distance",
	)
	dash.free()


func _test_dash_lifecycle(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)

	_check(dash.can_dash(), "a dash is available at full charges")
	_check(dash.try_start(Vector2.UP), "try_start succeeds while a charge is held")
	_check(dash.is_dashing, "the dash becomes active")
	_check(dash.direction == Vector2.UP, "the dash takes the requested direction")
	_check(dash.charges_available == 0, "the dash spends a charge")
	_check(not dash.try_start(Vector2.DOWN), "a second dash is refused mid-dash")
	_check(dash.is_invulnerable(), "the dash opens an invulnerability window")

	# The window must close before the dash does, so dashing through an attack is
	# a timing win rather than blanket immunity (spec section 6).
	_advance(dash, config.dash_invulnerability + FRAME)
	_check(not dash.is_invulnerable(), "invulnerability expires before the dash ends")
	_check(dash.is_dashing, "the dash outlives its invulnerability window")

	var ended := [false]
	dash.dash_ended.connect(func() -> void: ended[0] = true)
	_advance(dash, config.dash_duration)
	_check(not dash.is_dashing, "the dash ends after dash_duration")
	_check(ended[0], "dash_ended is emitted exactly when the dash ends")
	dash.free()


func _test_dash_recharge(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)
	dash.try_start(Vector2.RIGHT)
	_advance(dash, config.dash_duration)

	_check(dash.charges_available == 0, "the charge stays spent before the cooldown elapses")
	_check(dash.get_recharge_remaining() > 0.0, "the recharge timer runs while a charge is missing")
	_check(not dash.can_dash(), "no dash is available while spent")

	_advance(dash, config.dash_cooldown)
	_check(dash.charges_available == 1, "the charge refills after dash_cooldown")
	_check_near(dash.get_recharge_remaining(), 0.0, "the recharge timer clears at full charges")
	_check(dash.can_dash(), "a dash is available again once recharged")
	dash.free()


func _test_dash_reuses_direction_when_none_requested(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)
	dash.try_start(Vector2.LEFT)
	_advance(dash, config.dash_duration + config.dash_cooldown)

	dash.try_start(Vector2.ZERO)
	_check(dash.direction == Vector2.LEFT, "a zero direction reuses the previous dash direction")
	dash.free()


# --- Harness ------------------------------------------------------------------


## Steps the dash controller forward by at least `seconds`, in whole frames.
func _advance(dash: DashController, seconds: float) -> void:
	for _frame in ceili(seconds / FRAME):
		dash.step(FRAME)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _check_near(actual: float, expected: float, description: String, tolerance := 0.01) -> void:
	_checks += 1
	if absf(actual - expected) > tolerance:
		_failures.append("%s (got %s, expected %s)" % [description, actual, expected])


func _report() -> void:
	if _failures.is_empty():
		print("PASS  %d checks" % _checks)
		quit(0)
		return

	printerr("FAIL  %d of %d checks failed:" % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - %s" % failure)
	quit(1)

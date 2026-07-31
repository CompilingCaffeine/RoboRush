extends TestCase
## Checks for the movement and dash maths that define how the robot feels.
##
## MotionController and DashController take a config in and return values out, touching
## neither the tree nor a physics body — that is exactly why they were split out of the
## player, and it is what makes these assertions possible without a running game.

const CONFIG_PATH := "res://data/player/player_config.tres"

## Fixed physics step the checks simulate against.
const FRAME := 1.0 / 60.0


func run() -> void:
	var config := load(CONFIG_PATH) as PlayerConfig
	if not require(config, "player_config.tres loads as a PlayerConfig"):
		return

	_test_config_defaults(config)
	_test_motion_reaches_top_speed(config)
	_test_diagonal_movement_is_not_faster(config)
	_test_releasing_input_stops_the_robot(config)
	_test_dash_covers_its_configured_distance(config)
	_test_dash_lifecycle(config)
	_test_dash_recharge(config)
	_test_dash_reuses_direction_when_none_requested(config)


func _test_config_defaults(config: PlayerConfig) -> void:
	# Guards against the .tres silently losing properties during a refactor.
	check_near(config.move_speed, 160.0, "config move_speed matches the spec")
	check_near(config.dash_distance, 70.0, "config dash_distance matches the spec")
	check_near(config.dash_duration, 0.14, "config dash_duration matches the spec")
	check(config.max_integrity == 6, "config max_integrity matches the spec")


func _test_motion_reaches_top_speed(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.ZERO
	var peak := 0.0
	for _frame: int in 60:
		velocity = motion.step(velocity, Vector2.RIGHT, FRAME)
		peak = maxf(peak, velocity.length())

	check_near(velocity.length(), config.move_speed, "holding a direction reaches move_speed")
	check(peak <= config.move_speed + 0.01, "acceleration never overshoots move_speed")
	motion.free()


func _test_diagonal_movement_is_not_faster(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.ZERO
	for _frame: int in 60:
		velocity = motion.step(velocity, Vector2(1.0, 1.0).normalized(), FRAME)

	check_near(velocity.length(), config.move_speed, "diagonal movement tops out at move_speed")
	motion.free()


func _test_releasing_input_stops_the_robot(config: PlayerConfig) -> void:
	var motion := MotionController.new()
	motion.setup(config)

	var velocity := Vector2.RIGHT * config.move_speed
	# One extra frame past the theoretical braking time to absorb the discrete step.
	var frames := ceili(config.move_speed / config.deceleration / FRAME) + 1
	for _frame: int in frames:
		velocity = motion.step(velocity, Vector2.ZERO, FRAME)

	check(velocity.is_zero_approx(), "releasing input brings the robot to a full stop")
	motion.free()


func _test_dash_covers_its_configured_distance(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)

	check_near(
		dash.get_speed() * config.dash_duration,
		config.dash_distance,
		"dash speed times duration equals dash_distance",
	)
	dash.free()


func _test_dash_lifecycle(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)

	check(dash.can_dash(), "a dash is available at full charges")
	check(dash.try_start(Vector2.UP), "try_start succeeds while a charge is held")
	check(dash.is_dashing, "the dash becomes active")
	check(dash.direction == Vector2.UP, "the dash takes the requested direction")
	check(dash.charges_available == 0, "the dash spends a charge")
	check(not dash.try_start(Vector2.DOWN), "a second dash is refused mid-dash")
	check(dash.is_invulnerable(), "the dash opens an invulnerability window")

	# The window must close before the dash does, so dashing through an attack is a
	# timing win rather than blanket immunity (spec section 6).
	_advance(dash, config.dash_invulnerability + FRAME)
	check(not dash.is_invulnerable(), "invulnerability expires before the dash ends")
	check(dash.is_dashing, "the dash outlives its invulnerability window")

	var ended := [false]
	dash.dash_ended.connect(func() -> void: ended[0] = true)
	_advance(dash, config.dash_duration)
	check(not dash.is_dashing, "the dash ends after dash_duration")
	check(ended[0], "dash_ended is emitted exactly when the dash ends")
	dash.free()


func _test_dash_recharge(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)
	dash.try_start(Vector2.RIGHT)
	_advance(dash, config.dash_duration)

	check(dash.charges_available == 0, "the charge stays spent before the cooldown elapses")
	check(dash.get_recharge_remaining() > 0.0, "the recharge timer runs while a charge is missing")
	check(not dash.can_dash(), "no dash is available while spent")

	_advance(dash, config.dash_cooldown)
	check(dash.charges_available == 1, "the charge refills after dash_cooldown")
	check_near(dash.get_recharge_remaining(), 0.0, "the recharge timer clears at full charges")
	check(dash.can_dash(), "a dash is available again once recharged")
	dash.free()


func _test_dash_reuses_direction_when_none_requested(config: PlayerConfig) -> void:
	var dash := DashController.new()
	dash.setup(config)
	dash.try_start(Vector2.LEFT)
	_advance(dash, config.dash_duration + config.dash_cooldown)

	dash.try_start(Vector2.ZERO)
	check(dash.direction == Vector2.LEFT, "a zero direction reuses the previous dash direction")
	dash.free()


## Steps the dash controller forward by at least `seconds`, in whole simulated frames.
func _advance(dash: DashController, seconds: float) -> void:
	for _frame: int in ceili(seconds / FRAME):
		dash.step(FRAME)

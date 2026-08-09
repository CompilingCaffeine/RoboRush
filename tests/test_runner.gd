extends Node
## Runs every TestCase child, aggregates the results, and exits with a status code.
##
##     godot --headless --fixed-fps 60 res://tests/test_runner.tscn
##
## `--fixed-fps` is not decoration. The suites assert against real physics frames, and the
## engine paces those frames in real time, so the run spends essentially all of its wall clock
## asleep: 7137 frames at 60Hz is 119 seconds during which nothing computes. The flag pins the
## delta at 1/60 — every frame-counting assertion keeps exactly the meaning it had — and drops
## the pacing. The same 1496 checks take under two seconds with it and two minutes without.
##
## Exits 0 only if at least one suite ran, every suite ran at least one check, and no
## check failed. The "at least one check" rule is deliberate: a suite that crashes
## before asserting anything must be a failure, not a silent pass.

## How long any one suite may take. Per suite rather than per run, so the budget does not
## depend on how many suites precede it, and a slow host does not decide which of them get to
## run at all.
##
## Checked in `_process` rather than after `await suite.run()`, because the failure it exists
## for cannot be caught there: a suite awaiting something that never arrives never returns
## control, so a check placed after the await is a check that never executes. That was the
## whole of what the previous whole-run budget could do — notice, once a suite had already
## finished, that the suites collectively took too long — and it is not what the comment on it
## claimed.
##
## An await that never resolves still yields to the engine, which is what gives `_process` a
## frame to notice. A suite that spins in a loop without awaiting freezes the engine outright,
## and nothing inside the process can catch that — only a timeout in whatever launched it.
const SUITE_TIMEOUT_SECONDS := 60.0

## Set once the run has reported. Anything that ends the process before then is a failure,
## however cleanly it did it — see _exit_tree.
var _finished := false

## The suite currently inside `run()`, and when it runs out of time. Empty between suites, so
## the watchdog has nothing to accuse while the runner itself is between jobs.
var _running_suite := ""
var _suite_deadline := 0


func _ready() -> void:
	# The watchdog has to tick while the tree is paused. GameManager pauses on victory and on
	# game over, and suites drive both — test_floor restarts the run after winning precisely so
	# the suites after it still get frames. A watchdog that stopped with the tree would sleep
	# through exactly the states most likely to strand a suite.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The suites begin and end real runs, which would otherwise fold made-up statistics into
	# the save file of whoever is running the tests — and, worse, make the tests pass or fail
	# differently depending on what that file already said.
	SaveManager.persistence_enabled = false
	SaveManager.settings = GameSettings.new()
	SaveManager.best = BestRunStats.new()
	SaveManager.apply_settings()

	var start := Time.get_ticks_msec()
	var suites: Array[TestCase] = []
	var failures: PackedStringArray = []

	for child: Node in get_children():
		if child is TestCase:
			suites.append(child as TestCase)
			continue
		# A suite whose script fails to compile is attached to its node as nothing at all,
		# so it silently stops being a TestCase and the run reports PASS with that entire
		# suite missing. Every child of this node is declared in the scene precisely
		# because it is meant to run.
		failures.append("%s did not load as a TestCase (compile error in its script?)" % child.name)

	if suites.is_empty():
		printerr("FAIL  test_runner has no TestCase children.")
		get_tree().quit(1)
		return

	var total_checks := 0

	for suite: TestCase in suites:
		_running_suite = suite.name
		_suite_deadline = Time.get_ticks_msec() + int(SUITE_TIMEOUT_SECONDS * 1000.0)
		await suite.run()
		_running_suite = ""
		total_checks += suite.checks

		if suite.checks == 0:
			failures.append("%s: ran no checks (did it crash before asserting?)" % suite.name)
		for failure: String in suite.failures:
			failures.append("%s: %s" % [suite.name, failure])

		print("  %-22s %3d checks, %d failed" % [
			suite.name, suite.checks, suite.failures.size(),
		])

	var elapsed := (Time.get_ticks_msec() - start) / 1000.0
	_finished = true
	if failures.is_empty():
		print("PASS  %d suites, %d checks in %.1fs" % [suites.size(), total_checks, elapsed])
		_warn_if_paced(elapsed)
		get_tree().quit(0)
		return

	printerr("FAIL  %d problems across %d checks:" % [failures.size(), total_checks])
	for failure: String in failures:
		printerr("  - %s" % failure)
	_warn_if_paced(elapsed)
	get_tree().quit(1)


## The watchdog. See SUITE_TIMEOUT_SECONDS for why it lives here and not after the await.
func _process(_delta: float) -> void:
	if _finished or _running_suite.is_empty() or Time.get_ticks_msec() <= _suite_deadline:
		return
	_finished = true
	printerr(
		"FAIL  %s exceeded %.0fs and was stopped. A suite that stops making progress is "
		% [_running_suite, SUITE_TIMEOUT_SECONDS]
		+ "usually awaiting a signal that no longer fires."
	)
	get_tree().quit(1)


## The usage line above is only useful to somebody reading this file. This is for everybody
## else: the flag is worth two orders of magnitude, and the run most in need of being told is
## the one that has just spent two minutes not being told.
func _warn_if_paced(elapsed: float) -> void:
	if elapsed < 10.0:
		return
	print(
		"      (most of those %.0fs was real-time pacing, not work — rerun with " % elapsed
		+ "`--fixed-fps 60` for the same checks in under two seconds.)"
	)


## Catches the run being ended by something other than this function.
##
## A suite once clicked a real QUIT button, which called SceneRouter.quit_game and stopped the
## process with exit code 0 — three suites never ran, nothing was reported, and the shell saw
## success. A test harness that can exit silently is worse than no harness, because every
## failure after the exit point becomes invisible.
func _exit_tree() -> void:
	if _finished:
		return
	printerr(
		"FAIL  the run ended before reporting. Something quit the tree — a suite that "
		+ "pressed a button wired to SceneRouter.quit_game is the way this has happened."
	)
	# Best effort: a later quit() may not override an exit code already set by whoever ended
	# the run, so the message above is the part that must not be missed.
	get_tree().quit(1)

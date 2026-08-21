extends Node
## Runs every TestCase child, aggregates the results, and exits with a status code.
##
##     godot --headless --fixed-fps 60 res://tests/test_runner.tscn
##
## `--fixed-fps` is required, not decoration. The suites assert against real physics frames, and
## the engine paces those frames in real time, so the run spends essentially all of its wall clock
## asleep — thousands of frames at 60Hz, during which nothing computes. The flag pins the delta at
## 1/60 — every frame-counting assertion keeps exactly the meaning it had — and drops the pacing.
## The same 3278 checks take under sixteen seconds with it, and without it never finish at all:
## `SUITE_TIMEOUT_SECONDS` trips partway through and reports a healthy suite as a hang. That is
## why omitting the flag is a broken run rather than a slow one, and why the watchdog says so.
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

## Orphan nodes the suite is allowed to end with, in total.
##
## An orphan is a Node that exists and is in no tree: allocated with `Node.new()` and neither
## added to anything nor freed. Godot reports them at exit as "N ObjectDB instances were leaked",
## which is the least actionable diagnostic in the project — a number with no owner, no type, and
## no way to tell a suite's litter from a real leak in the game.
##
## Zero is the target and the only defensible number. It is written as a constant rather than
## asserted inline so that raising it is a visible decision in a diff, rather than something that
## drifts upward one forgotten `Node.new()` at a time.
const ORPHAN_ALLOWANCE := 0

## Set once the run has reported. Anything that ends the process before then is a failure,
## however cleanly it did it — see _exit_tree.
var _finished := false

## The suite currently inside `run()`, and when it runs out of time. Empty between suites, so
## the watchdog has nothing to accuse while the runner itself is between jobs.
var _running_suite := ""
var _suite_deadline := 0

## When the run started, in milliseconds and in physics frames. Members rather than locals in
## `_ready` because the watchdog needs them: comparing the two says whether the engine is sleeping
## between frames, which is the difference between a suite that is stuck and a suite that is merely
## being paced in real time. See `_is_real_time_paced`.
var _start_msec := 0
var _start_frames := 0


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

	# Stands in for the bootstrap scene, which the suites do not go through: the manager no
	# longer loads in `_ready`, and every write is refused until it has. Writes are already off
	# by the line above, so this loads without being able to put anything back.
	SaveManager.initialize()

	SaveManager.settings = GameSettings.new()
	SaveManager.best = BestRunStats.new()
	SaveManager.apply_settings()

	_start_msec = Time.get_ticks_msec()
	_start_frames = Engine.get_physics_frames()
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

	var orphans_before_run := _orphan_count()

	for suite: TestCase in suites:
		var orphans_before := _orphan_count()
		_running_suite = suite.name
		_suite_deadline = Time.get_ticks_msec() + int(SUITE_TIMEOUT_SECONDS * 1000.0)
		await suite.run()
		_running_suite = ""
		total_checks += suite.checks

		# One frame before counting. `queue_free` is honoured at the end of a frame, so a suite that
		# tidied up correctly still looks like it litters if it is measured the instant it returns.
		await get_tree().process_frame
		var orphaned := _orphan_count() - orphans_before

		if suite.checks == 0:
			failures.append("%s: ran no checks (did it crash before asserting?)" % suite.name)
		for failure: String in suite.failures:
			failures.append("%s: %s" % [suite.name, failure])

		print("  %-22s %3d checks, %d failed%s" % [
			suite.name, suite.checks, suite.failures.size(),
			", %+d orphans" % orphaned if orphaned != 0 else "",
		])

	# Counted across the whole run rather than summed from the per-suite deltas, so a suite that
	# cleans up after a *previous* suite's mess cannot cancel it out in the total.
	var orphaned_total := _orphan_count() - orphans_before_run
	if orphaned_total > ORPHAN_ALLOWANCE:
		failures.append(
			("%d orphan nodes are left at the end of the run, over the allowance of %d. "
			% [orphaned_total, ORPHAN_ALLOWANCE])
			+ "The per-suite counts above say which suites made them; each is a `Node.new()` that "
			+ "was neither added to a tree nor freed."
		)

	var elapsed := (Time.get_ticks_msec() - _start_msec) / 1000.0
	var frames := Engine.get_physics_frames() - _start_frames
	_finished = true
	if failures.is_empty():
		print("PASS  %d suites, %d checks in %.1fs" % [suites.size(), total_checks, elapsed])
		_warn_if_paced(elapsed, frames)
		get_tree().quit(0)
		return

	printerr("FAIL  %d problems across %d checks:" % [failures.size(), total_checks])
	for failure: String in failures:
		printerr("  - %s" % failure)
	_warn_if_paced(elapsed, frames)
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
	# The other reason, and the more likely one when the whole suite is healthy: the run was never
	# given `--fixed-fps`, so it is being paced in real time and a suite that computes for two
	# seconds sits here for two minutes. Saying only "it stopped making progress" sends the reader
	# looking for a hung await in a suite that does not have one — which is exactly the wrong
	# place, and there is no way to tell from the message that it is.
	if _is_real_time_paced():
		printerr(
			"      This run is being paced in real time, which is on its own enough to cause "
			+ "the above: rerun with `--fixed-fps 60` before believing the suite is stuck."
		)
	get_tree().quit(1)


## Nodes that exist and are in no tree. The engine tracks this already; the suite's only job is to
## read it at the right moments, which is what turns "125 instances were leaked" at exit into a
## number beside the name of the suite that made them.
func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


## The usage line above is only useful to somebody reading this file. This is for everybody
## else: the flag is worth two orders of magnitude, and the run most in need of being told is
## the one that has just spent two minutes not being told.
##
## What it must not do is say it to a run that already passed the flag. It did, for as long as it
## decided from the wall clock alone — the suite grew past the ten-second threshold and every
## correct run started being told to fix itself. That is worse than saying nothing, because the
## reader who follows the advice, sees the time not move, and concludes the flag does nothing is
## the reader who then runs without it and gets a passing suite reported as a hang.
##
## So it measures the claim rather than inferring it. `--fixed-fps` stops the engine sleeping
## between frames, and nothing else here does: at real-time pacing the run simulates one physics
## frame per tick of the clock, and with the flag it simulates as many as the CPU can compute.
## Comparing frames against seconds tells those apart directly, whatever the suite's size or the
## host's speed, neither of which this function should have an opinion about.
func _warn_if_paced(elapsed: float, frames: int) -> void:
	if elapsed < 10.0 or not _is_real_time_paced():
		return
	print(
		"      (most of those %.0fs was real-time pacing, not work: %d physics frames at %.0f/s. "
		% [elapsed, frames, float(frames) / maxf(elapsed, 0.001)]
		+ "Rerun with `--fixed-fps 60` to spend the time computing instead of sleeping.)"
	)


## Whether the engine is sleeping between frames — that is, whether this run was started without
## `--fixed-fps`. True is the slow, default case.
##
## Measured rather than read off the command line, because `OS.get_cmdline_args()` does not report
## engine flags: `--headless` and `--fixed-fps` are both consumed before a script can see them, so
## asking whether the flag was passed is not a question this process can answer. Asking what the
## flag *does* is. It stops the engine waiting out the remainder of each frame, and nothing else
## here does, so a paced run advances one physics frame per tick of the wall clock and an unpaced
## one advances as fast as the CPU manages — a ratio, not a duration, which is what keeps this
## independent of how large the suite has grown and how quick the host is.
func _is_real_time_paced() -> bool:
	var elapsed := (Time.get_ticks_msec() - _start_msec) / 1000.0
	var frames := Engine.get_physics_frames() - _start_frames
	if elapsed < 1.0 or frames <= 0:
		return false  # Too early to tell, and nothing is worth saying about a run this short.

	# Well clear of 1.0, so a host slow enough to miss its own tick rate is not accused of pacing,
	# and far below the hundredfold the flag actually buys.
	const PACED_RATIO := 1.5

	return float(frames) / elapsed <= float(Engine.physics_ticks_per_second) * PACED_RATIO


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

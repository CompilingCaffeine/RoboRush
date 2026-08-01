extends Node
## Runs every TestCase child, aggregates the results, and exits with a status code.
##
##     godot --headless res://tests/test_runner.tscn
##
## Exits 0 only if at least one suite ran, every suite ran at least one check, and no
## check failed. The "at least one check" rule is deliberate: a suite that crashes
## before asserting anything must be a failure, not a silent pass.

## Guards against a suite that awaits something that never arrives.
const TIMEOUT_SECONDS := 120.0


func _ready() -> void:
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
	var timeout := Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)

	for suite: TestCase in suites:
		await suite.run()
		total_checks += suite.checks

		if suite.checks == 0:
			failures.append("%s: ran no checks (did it crash before asserting?)" % suite.name)
		for failure: String in suite.failures:
			failures.append("%s: %s" % [suite.name, failure])

		print("  %-22s %3d checks, %d failed" % [
			suite.name, suite.checks, suite.failures.size(),
		])

		if Time.get_ticks_msec() > timeout:
			failures.append("run exceeded %.0fs; remaining suites skipped" % TIMEOUT_SECONDS)
			break

	var elapsed := (Time.get_ticks_msec() - start) / 1000.0
	if failures.is_empty():
		print("PASS  %d suites, %d checks in %.1fs" % [suites.size(), total_checks, elapsed])
		get_tree().quit(0)
		return

	printerr("FAIL  %d problems across %d checks:" % [failures.size(), total_checks])
	for failure: String in failures:
		printerr("  - %s" % failure)
	get_tree().quit(1)

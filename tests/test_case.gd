class_name TestCase
extends Node
## Base class for a test suite.
##
## Suites are Nodes run inside a live scene tree rather than under `--script`, for one
## concrete reason discovered the hard way: `--script` does not register autoloads, so
## any class referencing EventBus fails to compile, `SomeClass.new()` returns null, and
## every assertion in that suite quietly does nothing while the run still reports PASS.
## Running in a real tree also means physics, signals, and node lifecycles behave as
## they do in the game, so integration behaviour can be asserted rather than mocked.
##
## Deliberately a hand-rolled harness rather than a test plugin (spec section 33.6).

var failures: PackedStringArray = []
var checks := 0


## Overridden by each suite. May await, since the runner awaits it.
func run() -> void:
	fail("%s does not implement run()" % name)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func check_near(actual: float, expected: float, description: String, tolerance := 0.01) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s (got %s, expected %s)" % [description, actual, expected])


## Records an unconditional failure. Used where a suite cannot continue — a resource
## that will not load, a class that will not instantiate — so the cause is reported
## instead of the remaining assertions silently disappearing.
func fail(description: String) -> void:
	checks += 1
	failures.append(description)


## Asserts a value is present, and returns whether it was. Lets a suite bail out of a
## section while still recording why.
func require(value: Variant, description: String) -> bool:
	var present := value != null
	check(present, description)
	return present


## Advances the real physics clock. Suites that exercise projectiles or movement need
## actual frames, not simulated deltas.
func advance_physics(frames: int) -> void:
	for _frame: int in frames:
		await get_tree().physics_frame

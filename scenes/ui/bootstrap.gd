class_name Bootstrap
extends Control
## The project's main scene, and the only thing allowed to decide when the game may read a save.
##
## Everything the menu shows on its first frame comes out of `SaveManager` — the records, the
## unlocks, whether the tutorial card is due, whether Continue is offered. On a desktop that was
## free: the save is a local file, and reading it is a function call. In a browser it is not. The
## player's progress lives on Wavedash, arrives over the network, and belongs to whichever account
## is signed in — none of which is known at the instant the game starts.
##
## So the menu is no longer the first scene. This is, and it exists to buy exactly one thing:
## somewhere to wait. It waits for the platform, or for a bounded moment it decides is long
## enough, initializes persistence, and only then hands over. A menu built before that has already
## told the player they have no records, and no later arrival un-tells them.
##
## The waiting is bounded on purpose. A player whose network is broken, who is signed out, or who
## is running the desktop build must still reach the menu — a game that hangs on a boot screen is
## worse than one that quietly plays offline. Every path out of here ends at the menu; the only
## difference is whether the save came from the cloud or the disk.
##
## `WavedashSDK.init()` also dismisses the Wavedash loading overlay, which is why the in-game
## status text below matters: without it, the moment between the overlay disappearing and the menu
## appearing is a blank screen the player has no explanation for.

## How long the platform gets to connect before this gives up and plays local-only.
##
## Long enough to cover a slow first connection, short enough that a player on a broken network is
## not staring at a status line wondering whether the game is dead. A timeout here is not an error:
## it is the decision to stop waiting, and the game is fully playable after it.
const CONNECT_TIMEOUT_SECONDS := 8.0

## Shown only when the local and cloud saves have genuinely diverged, which most players will
## never see. Preloaded anyway: the alternative is loading a scene from disk at the one moment the
## game is already waiting on a network round trip.
const SAVE_CONFLICT_CARD := preload("res://scenes/ui/save_conflict_card.tscn")

## What the platform is asked for at startup. Empty because the defaults are what this game wants:
## the SDK signals readiness for events itself unless `deferEvents` is set, and nothing here needs
## to defer them — the game has no lobbies, no invites, and nothing to set up before they arrive.
const SDK_CONFIG := {}

## The track the menu opens with (`main_menu.gd`), which this scene starts rendering so that the
## menu does not open in silence. The music is synthesised in the game, a few milliseconds a frame,
## and the boot is mostly waiting: frames are what it has to spare. Named here rather than read
## from the menu's script, because reading it from there would compile that script before this
## scene's first frame, and the first frame is the one thing this scene must not delay.
const MENU_MUSIC := &"menu"

## The stages of a boot, in order, as the ready line reports them. `load` is the page opening to the
## engine starting — the download and the WebAssembly compile — and exists only in a browser.
## `engine` is the engine starting to this scene: its own setup, every autoload, and this scene.
## `connect` is everything from here until the platform answers or is given up on, and `save` is
## reconciling and reading the save.
const STAGES: Array[StringName] = [&"load", &"engine", &"connect", &"save"]

## How many times this build has initialized the platform, which must never exceed one. The SDK's
## `init` is a once-per-page-load operation — it hands the host page a callback receiver and
## mutates the JavaScript-side engine instance — so a second call is not a harmless repeat but a
## second receiver over the first.
##
## Static because a scene reload would reset an instance variable and re-enter the door it is
## holding shut. A count rather than a flag because "exactly once" is the rule, and a flag can
## only ever assert "at least once" to anything checking from outside.
static var _sdk_init_calls := 0

## Emitted when persistence is ready and the menu is about to be shown, with whether the game
## ended up running against a live Wavedash session. The scene change follows immediately, so
## anything listening for this is listening for "boot finished", not for a chance to intervene.
signal finished(online: bool)

## Set false by the suite. The last act of a successful boot is a scene change, and a scene change
## inside the test runner would replace the runner itself — mid-run, with the results in it.
var navigation_enabled := true

## Milliseconds each of `STAGES` took, filled in as the boot gets through them. A browser playtest
## is a URL and its console, so how long a boot took on somebody else's machine and connection is
## only ever known if the game says so; this is what the ready line says it from.
var timings: Dictionary[StringName, int] = {}

## The menu, loaded while the platform is connecting. Held until the scene change, which then finds
## it already in the resource cache.
var _menu_scene: PackedScene

## When the stage in progress began, in engine milliseconds.
var _stage_started_msec := 0

@onready var _status: Label = %Status

func _ready() -> void:
	# The engine's clock started with the engine, so the time on it now is the `engine` stage.
	_stage_started_msec = Time.get_ticks_msec()
	timings[&"engine"] = _stage_started_msec

	# The status line has to be on screen before anything is waited for, not after: the whole
	# point of it is the seconds spent waiting.
	_set_status("CONNECTING...")
	await get_tree().process_frame

	_init_platform()

	# The rest of the boot's own work, done while the platform answers rather than after it, so
	# that it overlaps the network round trip instead of being added to it. A frame later, because
	# the frame awaited above resumes this before it is drawn, not after: work here would hold up
	# the very status line it is meant to happen behind. Measured, that was 20 ms later on screen in
	# a browser on a fast machine, and 65 ms on one four times slower.
	await get_tree().process_frame
	# Rendered a few milliseconds a frame from here, it is ready when the menu opens rather than a
	# second or more after. See `MENU_MUSIC`.
	AudioManager.prepare_music(MENU_MUSIC)
	# The menu is the largest thing left to load before the player sees anything new: about 75 ms
	# in a browser on a fast machine and 290 ms on one four times slower, all of which used to be
	# spent after the wait, when it was the only thing the player was waiting for. Off the web there
	# is nothing to overlap, and the load costs what it always did, just earlier.
	_menu_scene = load(SceneRouter.MAIN_MENU_SCENE) as PackedScene
	var online := await _wait_for_platform()
	_end_stage(&"connect")

	_set_status("SYNCING SAVE..." if online else "LOADING SAVE...")

	# Before the line below, not after. Reconciliation may replace the save file outright, and the
	# only moment that is free is this one: nothing has read the old save yet, so nothing has to be
	# told it changed. It settles every case it can by itself and asks the player only when both
	# copies have genuinely moved on — which is what the card below is for.
	CloudSaveCoordinator.conflict_detected.connect(_on_conflict_detected)
	await CloudSaveCoordinator.reconcile()
	CloudSaveCoordinator.conflict_detected.disconnect(_on_conflict_detected)

	_set_status("LOADING SAVE...")

	# The one call that turns "there is a save file somewhere" into "the game may read it".
	SaveManager.initialize()
	if not SaveManager.is_initialized():
		await SaveManager.initialized
	_end_stage(&"save")
	# What the engine's clock cannot see: the time before it started. The page's clock can.
	var page_age := _page_age_msec()
	if page_age >= 0:
		timings[&"load"] = maxi(0, page_age - Time.get_ticks_msec())

	# The one line this build prints whether or not it is a debug build, and the only one. A hosted
	# playtest is a URL, and the browser console is the only instrument a tester has: this says
	# which build answered and whether it is running against an account or a disk, which are the
	# two questions every "my save did not come back" report turns out to hinge on.
	#
	# It is also what the browser smoke test waits for. Printed here, after persistence is ready
	# and immediately before the menu, it is the narrowest available statement of "the game
	# booted" — the engine started, the pack loaded, the autoloads ran, the platform answered or
	# timed out, and the save is readable.
	#
	# Whether `user://` survives a reload is on the line for the same reason. In a browser that is
	# not a property of the game but of the page it was given: storage partitioning, a third-party
	# cookie setting, or an embed the host sandboxed can all leave the engine with a filesystem that
	# looks completely normal and is thrown away when the tab closes. That failure is invisible from
	# inside the game and indistinguishable, to a tester, from the game not saving — so it is stated
	# here rather than guessed at afterwards.
	#
	# And how long it all took, stage by stage, because "it takes a while to load" is the other
	# report a hosted build gets, and the stages have different fixes: the download is the size
	# of the build and how it is served, the engine is the engine and the scripts, and the connect
	# and the save are the platform and the network.
	var id := build_id()
	print("Robo Rush %s ready: %s, %s, %s" % [
		id if not id.is_empty() else "dev",
		"cloud save" if online else "local save",
		"user:// persists" if OS.is_userfs_persistent() else "user:// IS NOT PERSISTENT",
		describe_timings(timings),
	])

	finished.emit(online)
	if navigation_enabled:
		SceneRouter.go_to_main_menu()


## Which build this is, as written into the project settings by tools/ci/build_web.sh at export
## time. Empty for anything run from source, which has no build id and should not pretend to.
##
## Static because the menu asks the same question to put it on screen, and one reading of a setting
## is easier to keep honest than two.
static func build_id() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## A boot's timings as the ready line states them: the whole of it, then each stage that has a
## time, in seconds — "2.9 s after the page opened (load 1.6, engine 0.7, connect 0.4, save 0.2)".
## The stages are contiguous, so they add up to the whole.
static func describe_timings(stage_msec: Dictionary[StringName, int]) -> String:
	var parts := PackedStringArray()
	var total := 0
	for stage: StringName in STAGES:
		if stage_msec.has(stage):
			parts.append("%s %.1f" % [stage, stage_msec[stage] / 1000.0])
			total += stage_msec[stage]
	return "%.1f s after %s (%s)" % [
		total / 1000.0,
		"the page opened" if stage_msec.has(&"load") else "launch",
		", ".join(parts),
	]


## Brings up the platform. Returns at once; `_wait_for_platform` is the waiting.
func _init_platform() -> void:
	if _sdk_init_calls == 0:
		_sdk_init_calls += 1
		# Called on every platform, though it only does anything in a browser: the SDK guards its
		# own web-only internals, and one unconditional call is one fewer path to be wrong about.
		WavedashSDK.init(SDK_CONFIG)


## Waits, briefly, to hear back from the platform. Returns whether the game is running against a
## live Wavedash session — false means local-only, which is a normal outcome rather than a failure.
func _wait_for_platform() -> bool:
	# Nothing to wait for off the web. There is no host page, no session, and no overlay to
	# dismiss, so a desktop launch would otherwise spend the timeout below staring at a status
	# line to learn what the platform already knows.
	if not OS.has_feature("web"):
		_log("native build: local-only persistence")
		return false

	var deadline := Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	while not WavedashConnection.is_connected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	if not WavedashConnection.is_connected:
		# Not an error the player can act on, and not one worth a dialog (spec section 31.10).
		_log("backend did not connect within %.0fs: local-only persistence" % CONNECT_TIMEOUT_SECONDS)
		return false

	# Connected, but a session is not an account. Wavedash cloud storage is per signed-in player,
	# so a signed-out visitor gets the same local-only treatment as a broken network — the game
	# works, and nothing of theirs is uploaded anywhere it could not be read back from.
	var user_id := WavedashConnection.player_id()
	if user_id.is_empty():
		_log("connected but signed out: local-only persistence")
		return false

	_log("connected as %s" % user_id)
	return true

## The one thing in the whole sync path a player has to decide. Both copies changed since they
## last agreed, there is no way to tell which is derived from the other, and merging them would
## invent a save neither device ever had. So it is put in front of them, with enough of each to
## recognise their own afternoon, and the copy they do not pick is archived rather than dropped.
func _on_conflict_detected(local: Dictionary, cloud: Dictionary) -> void:
	_set_status("TWO SAVES FOUND")
	var card: SaveConflictCard = SAVE_CONFLICT_CARD.instantiate()
	add_child(card)
	card.present(local, cloud)

	var choice: CloudSaveCoordinator.Resolution = await card.chosen
	card.queue_free()

	_set_status("SYNCING SAVE...")
	CloudSaveCoordinator.resolve_conflict(choice)


func _set_status(text: String) -> void:
	_status.text = text


## Records how long the stage in progress took, and starts the next one.
func _end_stage(stage: StringName) -> void:
	var now := Time.get_ticks_msec()
	timings[stage] = now - _stage_started_msec
	_stage_started_msec = now


## How long ago the page the engine runs in was opened, in milliseconds, or -1 where there is no
## page to ask.
static func _page_age_msec() -> int:
	if not OS.has_feature("web"):
		return -1
	var age: Variant = JavaScriptBridge.eval("performance.now()")
	return int(age) if age is float or age is int else -1


## Debug builds only. The export is a player's browser tab, and a status line is the only thing
## they should be told about any of this.
func _log(message: String) -> void:
	if OS.is_debug_build():
		print("Bootstrap: ", message)

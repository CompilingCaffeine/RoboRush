extends TestCase
## The startup gate. Phase 3 of the Wavedash implementation.
##
## The bootstrap exists to make one ordering true on every platform: nothing reads the save until
## the save has been loaded. That ordering is invisible when it works and silent when it breaks —
## a menu built a few frames early shows a player no records, no unlocks and no Continue, and
## looks exactly like a player who has none. So it is asserted here rather than noticed later.
##
## These run on a desktop build, which is the local-only path: no host page, no session, no
## account. That is worth testing in its own right — the browser is where the cloud save lives,
## but the desktop build has to keep working, and the fallback it takes is the same one a browser
## takes when the network is broken or the player is signed out.
##
## What cannot be checked from here is the web path itself: `WavedashSDK.init` only does anything
## inside a browser, and a headless suite has no host page to answer it. Phase 5's fake platform
## adapter is what makes that testable; until it exists, the single-initialization rule is checked
## through the guard that enforces it rather than by counting calls into the SDK.

const BOOTSTRAP_SCENE := preload("res://scenes/ui/bootstrap.tscn")

var _boot: Bootstrap


func run() -> void:
	await _test_boot_finishes_offline_on_a_desktop_build()
	await _test_the_save_is_loaded_before_the_menu_is_reached()
	await _test_the_platform_is_initialized_only_once()


func _teardown() -> void:
	if _boot != null and is_instance_valid(_boot):
		_boot.queue_free()
	_boot = null
	# The suites after this one expect the manager the runner set up, loaded and writable.
	SaveManager.initialize()
	# Let the freed boot scene actually leave the tree before the next one is added.
	await get_tree().process_frame


## The desktop build has no platform to wait for, and must not spend the connection timeout
## finding that out. A boot that took eight seconds to reach the menu would be a regression
## nobody would report as a bug — they would report the game as slow to start.
func _test_boot_finishes_offline_on_a_desktop_build() -> void:
	var online := await _boot_and_wait()

	check(not online, "a desktop build boots local-only rather than waiting for a session")
	check(_boot != null, "and the boot scene survived to finish")

	await _teardown()


## The whole reason this scene exists. `finished` is emitted immediately before the menu is
## shown, so the state of the manager at that moment is the state the menu will be built from.
func _test_the_save_is_loaded_before_the_menu_is_reached() -> void:
	# Back to how a freshly-launched game arrives: nothing loaded, every write refused.
	SaveManager._initialized = false
	check(not SaveManager.is_initialized(), "the manager starts unloaded, as it does on launch")

	var initialized_at_finish := [false]
	var boot := BOOTSTRAP_SCENE.instantiate() as Bootstrap
	boot.navigation_enabled = false
	boot.finished.connect(func(_online: bool) -> void:
		initialized_at_finish[0] = SaveManager.is_initialized()
	)
	_boot = boot
	add_child(boot)

	await _wait_for_finish(boot)

	check(
		initialized_at_finish[0],
		"the save is loaded before the boot hands over to the menu",
	)

	await _teardown()


## `init` hands the host page a callback receiver and mutates the JavaScript-side engine
## instance. Doing that twice is not a duplicate of a harmless call; it is a second receiver
## over the first. The guard is static precisely so a reloaded scene cannot get past it.
func _test_the_platform_is_initialized_only_once() -> void:
	Bootstrap._sdk_init_calls = 0

	await _boot_and_wait()
	check(
		Bootstrap._sdk_init_calls == 1,
		"booting initializes the platform (%d calls)" % Bootstrap._sdk_init_calls,
	)
	await _teardown()

	# A second boot — a scene reload, a return to the boot scene — must find the door shut.
	await _boot_and_wait()
	check(
		Bootstrap._sdk_init_calls == 1,
		"and a second boot does not initialize it again (%d calls)" % Bootstrap._sdk_init_calls,
	)

	await _teardown()


# --- Helpers ------------------------------------------------------------------


## Runs a boot to completion and returns whether it reported an online session.
func _boot_and_wait() -> bool:
	var boot := BOOTSTRAP_SCENE.instantiate() as Bootstrap
	# Without this the boot's last act replaces the running scene — which is this suite.
	boot.navigation_enabled = false
	_boot = boot
	add_child(boot)
	return await _wait_for_finish(boot)


## Waits for a boot to finish, with a ceiling well under the suite watchdog's so a boot that
## never finishes is reported as this check failing rather than as the runner giving up.
func _wait_for_finish(boot: Bootstrap) -> bool:
	var result := [false, false]
	boot.finished.connect(func(online: bool) -> void:
		result[0] = true
		result[1] = online
	)

	var deadline := Time.get_ticks_msec() + 5000
	while not result[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	check(result[0], "the boot finished rather than hanging on the connecting screen")
	return result[1]

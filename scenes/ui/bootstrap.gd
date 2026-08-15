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

## What the platform is asked for at startup. Empty because the defaults are what this game wants:
## the SDK signals readiness for events itself unless `deferEvents` is set, and nothing here needs
## to defer them — the game has no lobbies, no invites, and nothing to set up before they arrive.
const SDK_CONFIG := {}

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

@onready var _status: Label = %Status

## Set by the platform's own signal. A field rather than a local so that the wait below is a plain
## loop over a fact, rather than a race between an `await` and a timer that may already have fired.
var _backend_connected := false


func _ready() -> void:
	# The status line has to be on screen before anything is waited for, not after: the whole
	# point of it is the seconds spent waiting.
	_set_status("CONNECTING...")
	await get_tree().process_frame

	var online := await _connect_to_platform()

	_set_status("SYNCING SAVE..." if online else "LOADING SAVE...")

	# The one call that turns "there is a save file somewhere" into "the game may read it". Phase 4
	# puts cloud reconciliation in front of this line; until then, online or not, the save is local.
	SaveManager.initialize()
	if not SaveManager.is_initialized():
		await SaveManager.initialized

	finished.emit(online)
	if navigation_enabled:
		SceneRouter.go_to_main_menu()


## Brings up the platform and waits, briefly, to hear back from it. Returns whether the game is
## running against a live Wavedash session — false means local-only, which is a normal outcome
## rather than a failure.
func _connect_to_platform() -> bool:
	# Connected before `init`, not after. The backend can answer immediately, and a listener
	# attached afterwards would miss the one event it exists to hear.
	if not WavedashSDK.backend_connected.is_connected(_on_backend_connected):
		WavedashSDK.backend_connected.connect(_on_backend_connected)

	if _sdk_init_calls == 0:
		_sdk_init_calls += 1
		# Called on every platform, though it only does anything in a browser: the SDK guards its
		# own web-only internals, and one unconditional call is one fewer path to be wrong about.
		WavedashSDK.init(SDK_CONFIG)

	# Nothing to wait for off the web. There is no host page, no session, and no overlay to
	# dismiss, so a desktop launch would otherwise spend the timeout below staring at a status
	# line to learn what the platform already knows.
	if not OS.has_feature("web"):
		_log("native build: local-only persistence")
		return false

	var deadline := Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	while not _backend_connected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	if not _backend_connected:
		# Not an error the player can act on, and not one worth a dialog (spec section 31.10).
		_log("backend did not connect within %.0fs: local-only persistence" % CONNECT_TIMEOUT_SECONDS)
		return false

	# Connected, but a session is not an account. Wavedash cloud storage is per signed-in player,
	# so a signed-out visitor gets the same local-only treatment as a broken network — the game
	# works, and nothing of theirs is uploaded anywhere it could not be read back from.
	var user_id := WavedashSDK.get_user_id()
	if user_id.is_empty():
		_log("connected but signed out: local-only persistence")
		return false

	_log("connected as %s" % user_id)
	return true


func _on_backend_connected(_payload: Variant) -> void:
	_backend_connected = true


func _set_status(text: String) -> void:
	_status.text = text


## Debug builds only. The export is a player's browser tab, and a status line is the only thing
## they should be told about any of this.
func _log(message: String) -> void:
	if OS.is_debug_build():
		print("Bootstrap: ", message)

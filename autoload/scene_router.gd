extends Node
## The only thing that changes scenes. Spec section 26's suggested SceneRouter.
##
## There are exactly two scenes — the menu and the game — and three ways to move between
## them, which is not much of a router. It exists anyway because the *invariants* are the
## awkward part, not the switching: a scene change that leaves the tree paused shows a frozen
## game, and one that leaves `Engine.time_scale` where a hit pause left it shows a game
## running at six percent speed. Both have happened. Having one function that always resets
## both is cheaper than remembering to, at every call site, forever.
##
## Deliberately knows nothing about *why* a scene is being changed. `GameManager` owns what
## state the game is in; this owns what is loaded. Keeping those apart is what stops the
## router from growing into the giant manager spec section 26 forbids.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://main.tscn"


## Leaves whatever is running and shows the menu. Ends any run in progress, because a run
## the player has walked away from is over.
func go_to_main_menu() -> void:
	GameManager.enter_main_menu()
	_change_scene(MAIN_MENU_SCENE)


## Whether the game scene about to be built should continue the saved run rather than begin a
## new one. A flag rather than an argument to the scene, because a scene cannot be handed one:
## `change_scene_to_file` builds it later, and `main.gd` is the thing that has to ask.
##
## Consumed by whoever reads it, so it cannot survive into a run that did not ask for it. That is
## the failure this shape exists to prevent — a resume request left set would silently turn the
## *next* "START RUN" into a continue.
var _resume_requested := false


## Starts a fresh run. Also the restart path: reloading and starting are the same operation
## once the run's state lives in autoloads rather than in the scene.
func start_run() -> void:
	_resume_requested = false
	# Before the scene change, not after: main.gd reads the state as it builds, and a frame
	# spent in the previous run's GAME_OVER would pause the tree under the new floor.
	GameManager.start_run()
	_change_scene(GAME_SCENE)


## Continues the run in the save file, from the floor it was left at. The same scene and the same
## state change as `start_run` — the only difference is the flag, because the difference between
## the two runs is entirely in what `main.gd` puts into `RunManager` before the floor is built.
func resume_run() -> void:
	_resume_requested = true
	GameManager.start_run()
	_change_scene(GAME_SCENE)


## Whether this scene was asked to continue a saved run. Answers true at most once per request.
func consume_resume_request() -> bool:
	var requested := _resume_requested
	_resume_requested = false
	return requested


## Whether this build has anywhere to quit *to*, and therefore whether a menu should offer it.
##
## A browser tab is not a window the game owns. `get_tree().quit()` there does exactly what it
## says — it ends the main loop — but nothing closes afterwards, because a page cannot close
## itself. What the player is left with is the last frame the game drew, still on screen, with
## the engine behind it gone: a menu that looks completely normal and answers nothing. That is
## precisely how it was reported from the first browser playtest, as the game "locking out" on
## QUIT, and it is not something the button can be made to do better. So the browser build does
## not offer it, and the menus below it are complete without it — ABANDON RUN already returns to
## the title screen, and leaving the game is what closing the tab is for.
static func can_quit() -> bool:
	return not OS.has_feature("web")


## Ends the process. `get_tree().quit()` takes effect at the end of the current frame, which
## has two consequences worth stating: SaveManager still gets its shutdown notification and
## flushes any pending write, and there is no time for a sound. Callers deliberately do not
## play one — a 100 ms blip started on the frame the window closes is inaudible, and leaving
## it playing at teardown leaked the stream (see AudioManager.stop_all).
##
## Refuses on the web rather than trusting every caller to have checked `can_quit`. The menus do
## check — they do not build the button at all — but this is the function that strands a player,
## and a guard at the thing that causes the damage outlives whichever menu forgets.
func quit_game() -> void:
	if not can_quit():
		push_warning("SceneRouter: refusing to quit; a browser tab has nothing to quit to.")
		return
	_restore_time()
	AudioManager.stop_all()
	get_tree().quit()


func _change_scene(path: String) -> void:
	_restore_time()
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		# Nothing useful to tell the player here (spec section 31.10) and nowhere to send
		# them: the scene they are on is still running, so leaving them on it is the least
		# broken outcome.
		push_error("SceneRouter: could not load %s (%s)." % [path, error_string(error)])


## Undoes anything a paused or slowed-down game left behind. `Engine.time_scale` is global
## and survives a scene change, so a run abandoned during a hit pause would otherwise hand
## the menu a sixteen-times-slow fade.
func _restore_time() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false

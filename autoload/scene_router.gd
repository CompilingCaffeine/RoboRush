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


## Starts a fresh run. Also the restart path: reloading and starting are the same operation
## once the run's state lives in autoloads rather than in the scene.
func start_run() -> void:
	# Before the scene change, not after: main.gd reads the state as it builds, and a frame
	# spent in the previous run's GAME_OVER would pause the tree under the new floor.
	GameManager.start_run()
	_change_scene(GAME_SCENE)


func quit_game() -> void:
	_restore_time()
	# Not quit() directly: SaveManager flushes a pending write on the quit notification, and
	# the tree needs a frame to deliver it.
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

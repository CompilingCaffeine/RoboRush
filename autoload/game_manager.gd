extends Node
## Narrowly scoped global services: feedback tuning, hit pause, and what state the game is in.
##
## Explicitly not a god object. Spec section 26 permits autoload services but forbids
## giant managers, so the test for anything proposed here is: does it have no sensible
## owner in the scene tree, and does more than one unrelated system need it? Feedback
## tuning qualifies (every effect reads it). Hit pause qualifies (it manipulates
## Engine.time_scale, which is global by nature). Game state qualifies (the tree's paused
## flag is global, and the HUD, the player, and the summary screen all need to agree about
## it). Room logic does not, and lives in RoomCombat instead.
##
## Spec section 23 lists twelve states. Four exist, because four are reachable: the rest
## are menus and transitions that have nothing to show yet, and a state you cannot enter is
## a state nobody can debug. The shop is deliberately not one of them — it is a room the
## player walks into, not a mode the game enters, which means no state to leak input across.

const FEEDBACK_CONFIG_PATH := "res://data/settings/feedback_config.tres"

enum State {
	## Normal play.
	RUN,
	## Play suspended by the player. The tree is paused.
	PAUSED,
	## The run ended in failure. The tree is paused and the summary is up.
	GAME_OVER,
	## The run ended in success. Same, with a different headline.
	VICTORY,
}

signal state_changed(state: State)

## Intensity settings shared by every effect in the game.
var feedback: FeedbackConfig

var state := State.RUN

var _hit_pause_active := false


func _ready() -> void:
	# Must keep processing while time_scale is near zero and while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_feedback_config()
	EventBus.player_died.connect(_on_player_died)


## True while the player has any business moving or shooting.
func is_playing() -> bool:
	return state == State.RUN


## True once the run is over, either way. What the restart prompt keys off.
func is_run_over() -> bool:
	return state == State.GAME_OVER or state == State.VICTORY


## Puts the game into play. Called when a run begins, including after a restart — the
## scene reload rebuilds the world but this node survives it, so without this a second run
## would inherit the first one's ending.
func start_run() -> void:
	_set_state(State.RUN)


func pause_game() -> void:
	if state != State.RUN:
		return
	_set_state(State.PAUSED)


func resume_game() -> void:
	if state != State.PAUSED:
		return
	_set_state(State.RUN)


## Ends the run in failure. Idempotent, because the player can be killed by two things in
## the same frame and a run should only end once.
func end_run() -> void:
	if is_run_over():
		return
	_set_state(State.GAME_OVER)


## Ends the run in success. Spec section 23's Run Victory.
func win_run() -> void:
	if is_run_over():
		return
	_set_state(State.VICTORY)


## Briefly crushes time scale to sell a major impact (spec section 7). Ignored for
## ordinary hits — FeedbackDirector calls this only on kills and player damage.
## Re-entrant calls are dropped rather than stacking, which would otherwise let two
## simultaneous kills freeze the game for twice as long.
func hit_pause() -> void:
	if not feedback.hit_pause_enabled or _hit_pause_active:
		return

	_hit_pause_active = true
	Engine.time_scale = feedback.hit_pause_time_scale
	# ignore_time_scale, or the pause would last hit_pause_seconds of *scaled* time
	# and the game would appear to lock up for a second and a half.
	await get_tree().create_timer(feedback.hit_pause_seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_pause_active = false


## Restarts the current scene. Spec section 31.8: losing must immediately permit a
## new run.
func restart_run() -> void:
	Engine.time_scale = 1.0
	_hit_pause_active = false
	start_run()
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if is_run_over():
		if event.is_action_pressed("restart"):
			restart_run()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if state == State.PAUSED:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


## The tree's paused flag and the run clock are both derived from the state rather than set
## alongside it, so there is no path where the game is showing a summary screen and still
## counting the run's duration.
func _set_state(new_state: State) -> void:
	state = new_state
	get_tree().paused = state != State.RUN
	RunManager.set_timing(state == State.RUN)
	if is_run_over():
		RunManager.end_run()
	state_changed.emit(state)


func _on_player_died() -> void:
	end_run()


## A missing or broken settings resource must never take the game down — spec section
## 31.10 forbids placeholder error messages reaching the player.
func _load_feedback_config() -> void:
	feedback = load(FEEDBACK_CONFIG_PATH) as FeedbackConfig
	if feedback != null:
		return
	push_warning("GameManager: could not load %s; using defaults." % FEEDBACK_CONFIG_PATH)
	feedback = FeedbackConfig.new()

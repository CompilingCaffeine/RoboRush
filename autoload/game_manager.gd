extends Node
## Narrowly scoped global services: feedback tuning, hit pause, and run restart.
##
## Explicitly not a god object. Spec section 26 permits autoload services but forbids
## giant managers, so the test for anything proposed here is: does it have no sensible
## owner in the scene tree, and does more than one unrelated system need it? Feedback
## tuning qualifies (every effect reads it). Hit pause qualifies (it manipulates
## Engine.time_scale, which is global by nature). Room logic does not, and lives in
## RoomCombat instead.
##
## The full game state machine from spec section 23 lands here in milestone 5, when
## there are menus and a run to manage. Today there is one state worth tracking.

const FEEDBACK_CONFIG_PATH := "res://data/settings/feedback_config.tres"

## Intensity settings shared by every effect in the game.
var feedback: FeedbackConfig

## True between the player's death and the next restart.
var is_player_dead := false

var _hit_pause_active := false


func _ready() -> void:
	# Must keep processing while time_scale is near zero and, later, while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_feedback_config()
	EventBus.player_died.connect(_on_player_died)


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
## new run. A real run lifecycle replaces this in milestone 5.
func restart_run() -> void:
	Engine.time_scale = 1.0
	_hit_pause_active = false
	is_player_dead = false
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if is_player_dead and event.is_action_pressed("restart"):
		restart_run()


func _on_player_died() -> void:
	is_player_dead = true


## A missing or broken settings resource must never take the game down — spec section
## 31.10 forbids placeholder error messages reaching the player.
func _load_feedback_config() -> void:
	feedback = load(FEEDBACK_CONFIG_PATH) as FeedbackConfig
	if feedback != null:
		return
	push_warning("GameManager: could not load %s; using defaults." % FEEDBACK_CONFIG_PATH)
	feedback = FeedbackConfig.new()

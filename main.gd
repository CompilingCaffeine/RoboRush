extends Node2D
## Milestone 2 entry point.
##
## Composition only: it places the player in the room, fits the camera to that room,
## and hands the HUDs and the feedback director the references they need. Nothing here
## knows how movement, shooting, or damage work — this file exists so no scene has to
## reach across the tree to find its collaborators.
##
## When floor generation arrives (milestone 3) this is where RunManager and SceneRouter
## take over.

@onready var _room: TestRoom = %TestRoom
@onready var _player: Player = %Player
@onready var _feedback: FeedbackDirector = %FeedbackDirector
@onready var _combat_hud: CombatHUD = %CombatHUD
@onready var _debug_hud: DebugHUD = %DebugHUD


func _ready() -> void:
	_player.global_position = _room.get_spawn_position()
	# After positioning, so the camera snaps to the spawn instead of easing in.
	_player.set_camera_limits(_room.get_camera_bounds())

	_feedback.setup(_player.get_camera())
	_combat_hud.bind_player(_player)
	_debug_hud.bind_player(_player)
	_debug_hud.bind_room_combat(_room.get_room_combat())

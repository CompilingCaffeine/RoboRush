extends Node2D
## Milestone 1 entry point.
##
## Composition only: it drops the player into the test room, fits the camera to
## that room, and hands the overlay a player reference. Nothing here knows how
## movement or dashing work.
##
## When floor generation arrives (milestone 3) this is where the RunManager and
## SceneRouter autoloads take over — this script exists so the sandbox has a seam
## in the right place rather than the player scene hardcoding its own spawn.

@onready var _room: TestRoom = %TestRoom
@onready var _player: Player = %Player
@onready var _debug_hud: DebugHUD = %DebugHUD


func _ready() -> void:
	_player.global_position = _room.get_spawn_position()
	# After positioning, so the camera snaps to the spawn instead of easing in.
	_player.set_camera_limits(_room.get_camera_bounds())
	_debug_hud.bind_player(_player)

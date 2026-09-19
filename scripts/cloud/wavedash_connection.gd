extends Node
## Shared view of the Wavedash connection used by cloud saves, leaderboards, and bootstrap.

signal changed(connected: bool)

var is_connected := false


func _ready() -> void:
	WavedashSDK.backend_connected.connect(func(_payload: Variant) -> void: _set_connected(true))
	WavedashSDK.backend_disconnected.connect(func(_payload: Variant) -> void: _set_connected(false))
	WavedashSDK.backend_reconnecting.connect(func(_payload: Variant) -> void: _set_connected(false))


func is_available() -> bool:
	return OS.has_feature("web") and is_connected and not player_id().is_empty()


func player_id() -> String:
	return WavedashSDK.get_user_id()


func _set_connected(value: bool) -> void:
	if is_connected == value:
		return
	is_connected = value
	changed.emit(is_connected)

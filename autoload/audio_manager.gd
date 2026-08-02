extends Node
## Pooled one-shot sound playback.
##
## A dumb service on purpose: it knows how to make a noise, not when to. The mapping
## from gameplay events to sounds lives in FeedbackDirector, so there is exactly one
## file to read when asking "why did it make that sound".
##
## Players are pooled and reused round-robin. Creating an AudioStreamPlayer per shot
## would churn nodes at four allocations a second, and the pool doubles as a natural
## voice cap: the oldest sound is cut rather than fifty overlapping copies summing
## into clipping.

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const POOL_SIZE := 16

const LIBRARY := {
	&"fire": "res://audio/sfx/fire.wav",
	&"enemy_hit": "res://audio/sfx/enemy_hit.wav",
	&"enemy_death": "res://audio/sfx/enemy_death.wav",
	&"player_hurt": "res://audio/sfx/player_hurt.wav",
	&"dash": "res://audio/sfx/dash.wav",
	&"room_clear": "res://audio/sfx/room_clear.wav",
	&"low_integrity": "res://audio/sfx/low_integrity.wav",
	&"pickup": "res://audio/sfx/pickup.wav",
	&"door": "res://audio/sfx/door.wav",
	&"item_pickup": "res://audio/sfx/item_pickup.wav",
	&"explosion": "res://audio/sfx/explosion.wav",
	&"zap": "res://audio/sfx/zap.wav",
	&"ui_move": "res://audio/sfx/ui_move.wav",
	&"ui_confirm": "res://audio/sfx/ui_confirm.wav",
	&"ui_back": "res://audio/sfx/ui_back.wav",
	&"purchase": "res://audio/sfx/purchase.wav",
	&"boss_phase": "res://audio/sfx/boss_phase.wav",
	&"victory": "res://audio/sfx/victory.wav",
	&"game_over": "res://audio/sfx/game_over.wav",
}

var _streams: Dictionary[StringName, AudioStream] = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_index := 0


func _ready() -> void:
	# Sound must keep playing through a hit pause and, later, through a pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_library()
	_build_pool()


## Plays a sound by id. `pitch_variation` randomises pitch by +/- that fraction,
## which is what stops a repeated sound becoming fatiguing (spec section 22).
func play_sfx(id: StringName, pitch_variation := 0.0, volume_db := 0.0) -> void:
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		push_warning("AudioManager: unknown sound id '%s'." % id)
		return

	var player := _pool[_next_index]
	_next_index = (_next_index + 1) % _pool.size()

	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func set_bus_volume_db(bus: StringName, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, volume_db)


## Creates the SFX and Music buses if the bus layout is missing or was replaced.
## Volume settings (spec section 21) target these by name, so a missing bus would
## silently make those settings do nothing.
func _ensure_buses() -> void:
	for bus: StringName in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")


func _load_library() -> void:
	for id: StringName in LIBRARY:
		var stream := load(LIBRARY[id]) as AudioStream
		if stream == null:
			push_warning("AudioManager: failed to load '%s'." % LIBRARY[id])
			continue
		_streams[id] = stream


func _build_pool() -> void:
	for _index: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_pool.append(player)

extends Node
## Pooled one-shot sound playback, and the music.
##
## A dumb service on purpose: it knows how to make a noise, not when to. The mapping
## from gameplay events to sounds lives in FeedbackDirector, so there is exactly one
## file to read when asking "why did it make that sound". Music is the same deal —
## `play_music` takes a track id and nothing here knows what a boss is.
##
## Players are pooled and reused round-robin. Creating an AudioStreamPlayer per shot
## would churn nodes at four allocations a second, and the pool doubles as a natural
## voice cap: the oldest sound is cut rather than fifty overlapping copies summing
## into clipping.
##
## Music gets two players rather than one, which is the whole reason it is not just
## `play_sfx` with a loop flag. Cutting from the explore loop to the boss loop is jarring
## in a way that has nothing to do with the tracks and everything to do with the cut, and
## a crossfade needs both playing at once for a moment.

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const POOL_SIZE := 16

## Godot's floor for an inaudible player. Anything lower is the same silence.
const SILENT_DB := -80.0

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

## Spec section 22: chiptune, industrial percussion, fast arcade loops. One track per
## situation the player can be in for minutes at a time, all three in A minor so a crossfade
## between any two is a key change nobody notices.
const MUSIC_LIBRARY := {
	&"menu": "res://audio/music/menu.wav",
	&"explore": "res://audio/music/explore.wav",
	&"boss": "res://audio/music/boss.wav",
}

## Seconds to crossfade between tracks. Long enough not to read as a cut, short enough that
## walking into the boss room feels like it caused something.
const MUSIC_FADE_SECONDS := 1.2

var _streams: Dictionary[StringName, AudioStream] = {}
var _music_streams: Dictionary[StringName, AudioStream] = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_index := 0

## Two music players, crossfaded between. `_music_active` indexes whichever is fading *in*.
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id: StringName = &""

## 0..1 progress of the current crossfade. Reaches 1 and stays there between changes.
var _fade := 1.0


func _ready() -> void:
	# Sound must keep playing through a hit pause and through the pause menu — a game whose
	# music stops when paused sounds like it crashed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_library()
	_build_pool()
	_build_music_players()


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


## Crossfades to `id`, or does nothing if it is already the track that is playing. The
## no-op case is the important one: this is called on every room entry, and restarting the
## explore loop each time the player walks through a door would be worse than no music.
func play_music(id: StringName) -> void:
	if id == _music_id:
		return
	var stream: AudioStream = _music_streams.get(id)
	if stream == null:
		push_warning("AudioManager: unknown music id '%s'." % id)
		return

	_music_id = id
	_music_active = 1 - _music_active
	_fade = 0.0

	var incoming := _music[_music_active]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()


## Fades the music out and leaves it out. Called when a run ends: the victory fanfare and the
## power-down both need the room to themselves.
func stop_music() -> void:
	if _music_id.is_empty():
		return
	_music_id = &""
	_fade = 0.0
	# Swapping to the other player with nothing loaded makes the outgoing track fade out
	# through exactly the same code path as a normal change, rather than a second one.
	_music_active = 1 - _music_active
	_music[_music_active].stop()


## Both music players are driven every frame rather than by a Tween, because a fade that is
## interrupted by another fade has to pick up from wherever it got to. A tween would have to
## be killed and replaced, and the killed one occasionally lands its final value afterwards.
func _process(delta: float) -> void:
	if _fade >= 1.0:
		return
	_fade = minf(_fade + delta / MUSIC_FADE_SECONDS, 1.0)

	for index: int in _music.size():
		var player := _music[index]
		var gain := _fade if index == _music_active else 1.0 - _fade
		player.volume_db = linear_to_db(gain) if gain > 0.001 else SILENT_DB
		if gain <= 0.001 and player.playing and index != _music_active:
			player.stop()


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

	for id: StringName in MUSIC_LIBRARY:
		var stream := load(MUSIC_LIBRARY[id]) as AudioStream
		if stream == null:
			push_warning("AudioManager: failed to load '%s'." % MUSIC_LIBRARY[id])
			continue
		# Set here rather than trusted from the .import file. A loop flag lost in a reimport
		# turns a twenty-second loop into twenty seconds of music followed by silence, which
		# is the kind of bug that gets reported as "the music is broken sometimes".
		var wav := stream as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = 0
		_music_streams[id] = stream


func _build_music_players() -> void:
	for _index: int in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = SILENT_DB
		add_child(player)
		_music.append(player)


func _build_pool() -> void:
	for _index: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_pool.append(player)

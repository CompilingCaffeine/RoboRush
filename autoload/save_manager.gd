extends Node
## Everything that outlives a run, on disk. Spec section 24.
##
## Four kinds of thing live here and they are all persistent by the same test: closing the
## game must not lose them. Settings, what the player has unlocked, which bosses they have
## beaten, and their best statistics. A run in progress is explicitly *not* saved (spec
## section 24), which is why `RunManager` has no idea this node exists.
##
## Applying settings is here too, and that is a deliberate coupling rather than an accident.
## A setting that is stored in one place and applied in another drifts: someone adds a
## slider, wires it to the mixer, and forgets the load path, so it works all session and
## resets on restart. Here there is exactly one function that turns `GameSettings` into
## observable behaviour, and both the loader and the settings screen call it.
##
## Nothing in the game reads the save file directly. Gameplay asks this node, this node owns
## the format, and the format is versioned so that changing it later is a migration rather
## than an apology.

const SAVE_PATH := "user://save.json"

## Written next to the real file and renamed over it. A crash during a write then costs the
## temporary file rather than the player's records — the save is small enough that the
## careful version is free, and losing a save to a power cut is the kind of bug that is only
## ever reported once, by someone who has stopped playing.
const SAVE_TEMP_PATH := "user://save.json.tmp"

const SAVE_VERSION := 1

## Seconds of quiet before a requested save is actually written. A settings slider emits a
## value every frame it is dragged; without this, one drag is sixty file writes.
const SAVE_DEBOUNCE_SECONDS := 0.5

## Seconds before a failed write is attempted again. Far longer than the debounce on purpose: a
## write that just failed will probably still fail a frame later, and the point is to survive a
## transient condition rather than to hammer a full disk sixty times a second.
const SAVE_RETRY_SECONDS := 5.0

signal settings_changed(settings: GameSettings)

var settings := GameSettings.new()
var best := BestRunStats.new()

## Every item the player has ever picked up. Spec section 24 calls this "unlocked items";
## nothing gates the item pool on it yet, so today it is a discovery log rather than a
## gate. It is recorded now because a gate added later cannot retroactively know what
## someone already found.
var unlocked_items: Array[StringName] = []

## Ids of bosses that have been destroyed at least once.
var bosses_defeated: Array[StringName] = []

## Spec section 24. Set once the player has been through the controls card, so it is shown
## automatically to a first-time player and never again after that.
var tutorial_completed := false

## Set false by the test runner. The suite exercises the real manager, and a test must never
## overwrite the save file of whoever is running it.
var persistence_enabled := true

var _dirty := false
var _save_countdown := 0.0

## Consecutive failed writes. Only the first one warns: a disk that stays full would otherwise
## fill the log with the same line every five seconds for the rest of the session.
var _failed_writes := 0

## Where the save lives. Variables rather than constants *only* so the suite can point them at
## something disposable — nothing in the game ever reassigns them, and a test that wrote to the
## real path would clobber the save file of whoever ran it.
var _save_path := SAVE_PATH
var _temp_path := SAVE_TEMP_PATH


func _ready() -> void:
	# Settings must keep applying while the tree is paused: the settings screen is reachable
	# from the pause menu, and a volume slider that only worked while unpaused would look
	# broken in the one place it is used.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.boss_defeated.connect(_on_boss_defeated)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_countdown -= delta
	if _save_countdown <= 0.0:
		save_game()


func _notification(what: int) -> void:
	# Quitting is the one moment a pending debounced save must not be lost. Both
	# notifications are handled because they do not both arrive: closing the window sends the
	# first, `get_tree().quit()` only the second.
	var is_shutdown := what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	if is_shutdown and _dirty:
		save_game()


# --- Settings -----------------------------------------------------------------


## Pushes `settings` into everything that obeys it: the mixer, the window, the feedback
## tuning every effect reads, and whatever is listening for the rest. Safe to call as often
## as a slider moves.
func apply_settings() -> void:
	AudioManager.set_bus_volume_db(&"Master", GameSettings.volume_to_db(settings.master_volume))
	AudioManager.set_bus_volume_db(&"Music", GameSettings.volume_to_db(settings.music_volume))
	AudioManager.set_bus_volume_db(&"SFX", GameSettings.volume_to_db(settings.sfx_volume))

	_apply_fullscreen()

	# The three player-facing fields of FeedbackConfig are overwritten from the save; the
	# rest of that resource (hit pause) stays authored content. This is the only place the
	# two meet, so "which of these is the player allowed to change?" has one answer.
	var feedback := GameManager.feedback
	if feedback != null:
		feedback.screen_shake_scale = settings.screen_shake
		feedback.flash_intensity = settings.flash_intensity
		feedback.damage_numbers_enabled = settings.damage_numbers

	settings_changed.emit(settings)


## Applies and schedules a write. What the settings screen calls after changing anything.
func commit_settings() -> void:
	apply_settings()
	request_save()


func _apply_fullscreen() -> void:
	# Headless has a dummy display server that reports a window it does not have. Asking it
	# to go fullscreen is harmless but noisy, and the tests run headless.
	if DisplayServer.get_name() == "headless":
		return
	var mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if settings.fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


# --- Progress -----------------------------------------------------------------


## Called when a run begins. Counted here rather than in `RunManager` because the count is
## a lifetime statistic, and `RunManager` is by definition the thing that forgets.
func record_run_started() -> void:
	best.runs_started += 1
	request_save()


## Folds a finished run into the records. Returns the labels that were beaten so the summary
## screen can mark them.
func record_run_finished(stats: RunStats, won: bool) -> PackedStringArray:
	var beaten := best.absorb(stats, won)
	request_save()
	return beaten


func record_boss_defeated(id: StringName) -> void:
	if id.is_empty() or id in bosses_defeated:
		return
	bosses_defeated.append(id)
	request_save()


func has_defeated_boss(id: StringName) -> bool:
	return id in bosses_defeated


func mark_tutorial_completed() -> void:
	if tutorial_completed:
		return
	tutorial_completed = true
	request_save()


## Read off the EventBus rather than reported by the boss, so no gameplay script has to know
## that a save file exists — the same rule that keeps enemies from spawning their own
## particles.
##
## `config` is fetched fully dynamically — no static type, and `id` read via `get()` rather
## than a typed member access — because `Boss` gives every boss a shared *behaviour* base but
## deliberately no shared config type: `MergeConflict` carries a `BossConfig`, `RuntimeError` a
## `RuntimeErrorConfig`, and they are siblings, not one a subclass of the other. A
## statically-typed `var config: BossConfig` here crashed the instant a second boss with its own
## config resource existed — this is that fix.
func _on_boss_defeated(boss: Node) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var config: Variant = boss.get("config")
	if config == null:
		return
	var id: Variant = config.get("id")
	if id is StringName:
		record_boss_defeated(id)


func _on_item_collected(item: ItemConfig) -> void:
	if item == null or item.id.is_empty() or item.id in unlocked_items:
		return
	unlocked_items.append(item.id)
	request_save()


# --- Persistence --------------------------------------------------------------


## Marks the save dirty. The write happens a moment later, or immediately on quit.
func request_save() -> void:
	_dirty = true
	_save_countdown = SAVE_DEBOUNCE_SECONDS


## Writes the save, or leaves it pending and tries again later.
##
## `_dirty` is cleared only once a write has actually landed. It used to be cleared on the first
## line of this function, before the write was even attempted, so a single transient failure — a
## full disk, a file held open by something else, a rename losing a race — silently stopped the
## game saving for the rest of the session: `_process` only retries while dirty, and so does the
## flush on quit. Everything after that point was lost with nothing but a warning nobody reads.
##
## The naive repair is worse than the bug: leaving `_dirty` set with the countdown already
## expired makes `_process` call this every single frame. Hence the backoff.
func save_game() -> void:
	if not persistence_enabled:
		# Not a failure. The suite runs with writes off, and there is nothing left pending.
		_dirty = false
		return

	var failure := _write_save_file()
	if not failure.is_empty():
		_failed_writes += 1
		_save_countdown = SAVE_RETRY_SECONDS
		if _failed_writes == 1:
			# A save that cannot be written is worth a log line and nothing else. The player is
			# mid-run and there is nothing useful to tell them (spec section 31.10).
			push_warning("SaveManager: %s. Retrying in %.0fs." % [failure, SAVE_RETRY_SECONDS])
		return

	if _failed_writes > 0:
		print("SaveManager: save recovered after %d failed attempt(s)." % _failed_writes)
	_dirty = false
	_failed_writes = 0


## Returns an empty string on success, or a description of what went wrong.
##
## Written to a temporary file and renamed over the real one, so a crash mid-write costs the
## temporary rather than the player's records.
func _write_save_file() -> String:
	var payload := {
		"save_version": SAVE_VERSION,
		"settings": settings.to_dict(),
		"unlocks": _to_string_array(unlocked_items),
		"bosses_defeated": _to_string_array(bosses_defeated),
		"statistics": best.to_dict(),
		"tutorial_completed": tutorial_completed,
	}

	var file := FileAccess.open(_temp_path, FileAccess.WRITE)
	if file == null:
		return "could not write %s (%s)" % [
			_temp_path, error_string(FileAccess.get_open_error())
		]
	file.store_string(JSON.stringify(payload, "  "))
	file.close()

	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_temp_path),
		ProjectSettings.globalize_path(_save_path),
	)
	if error != OK:
		return "could not replace %s (%s)" % [_save_path, error_string(error)]

	return ""


## Reads the save file if there is one, then applies whatever came back. A first run, a
## deleted file, and a corrupt file all take the same path: defaults, applied, no complaint
## the player can see.
func load_game() -> void:
	var data := _read_save_file()
	settings = GameSettings.from_dict(_sub_dictionary(data, "settings"))
	best = BestRunStats.from_dict(_sub_dictionary(data, "statistics"))
	unlocked_items = _to_name_array(data.get("unlocks"))
	bosses_defeated = _to_name_array(data.get("bosses_defeated"))
	tutorial_completed = data.get("tutorial_completed") == true
	apply_settings()


func _read_save_file() -> Dictionary:
	if not FileAccess.file_exists(_save_path):
		return {}

	var text := FileAccess.get_file_as_string(_save_path)
	if text.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveManager: %s is not valid JSON; starting from defaults." % _save_path)
		return {}

	return _migrate(parsed)


## Brings an older file up to the current shape.
##
## There is nothing to migrate yet — version 1 is the first version — so this exists as the
## place a migration goes rather than as one. It is written now because the alternative is
## discovering at version 2 that the loader assumed the current shape everywhere.
##
## A file from a *newer* build is not rejected. Every reader in `GameSettings` and
## `BestRunStats` already ignores what it does not recognise, so a player who rolls back a
## version loses the fields that version never had rather than their whole save.
func _migrate(data: Dictionary) -> Dictionary:
	var raw_version: Variant = data.get("save_version")
	var version := int(raw_version) if raw_version is float or raw_version is int else 0
	if version > SAVE_VERSION:
		push_warning(
			"SaveManager: %s was written by a newer build (version %d); reading what is recognised."
			% [_save_path, version]
		)
	return data


func _sub_dictionary(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key)
	return value if value is Dictionary else {}


## JSON has no StringName, so ids come back as strings. Anything that is not a string is
## dropped rather than coerced — a number in the unlock list is corruption, not an id.
func _to_name_array(value: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if not (value is Array):
		return names
	for entry: Variant in value:
		if entry is String and not (entry as String).is_empty():
			names.append(StringName(entry))
	return names


func _to_string_array(names: Array[StringName]) -> Array:
	var strings: Array = []
	for name_value: StringName in names:
		strings.append(String(name_value))
	return strings

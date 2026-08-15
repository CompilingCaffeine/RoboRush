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
##
## Since version 2 a *run in progress* lives here too, as a `RunCheckpoint` written at floor
## boundaries. That reverses spec section 24 deliberately, and only for the six-floor campaign:
## the spec's "runs are not saved" was written for a ten-room run that could be replayed in six
## minutes, and a sixty-room run cannot. See `RunCheckpoint` for what is stored and why the
## boundary is the only safe moment to store it.
##
## Loading is explicit rather than automatic: `initialize` does it, and until it has, this node
## holds defaults and refuses to write. `_ready` used to load, which was fine while the only
## source of a save was a local file that could be read synchronously. The browser build's save
## arrives over the network, so *something* has to be allowed to take time before the game reads
## a record — and a node that has already loaded defaults cannot be told to wait. The bootstrap
## scene owns that decision now; see `scenes/ui/bootstrap.gd`.

const SAVE_PATH := "user://save.json"

## Written next to the real file and renamed over it. A crash during a write then costs the
## temporary file rather than the player's records — the save is small enough that the
## careful version is free, and losing a save to a power cut is the kind of bug that is only
## ever reported once, by someone who has stopped playing.
const SAVE_TEMP_PATH := "user://save.json.tmp"

## The previous save, kept as it is replaced. The rename above makes a *torn* file impossible;
## it does nothing about a file that was written whole and is wrong — a bad migration, a disk
## that returned zeroes, an edit made with a text editor. One generation back is the difference
## between "your records are gone" and "your records are one run out of date", and it costs a
## copy of a four-kilobyte file per save.
const SAVE_BACKUP_PATH := "user://save.json.bak"

## Where a primary that could not be read is moved before anything replaces it. Never read by
## the game — it exists so that a player whose save failed to load still has the bytes, and so a
## bug report can carry them. One slot, overwritten: the interesting file is the one that just
## broke, and a growing pile of them in `user://` is its own problem.
const SAVE_CORRUPT_PATH := "user://save.json.corrupt"

const SAVE_VERSION := 2

## The most a save file may be. A save with a run checkpoint in it is about four kilobytes and
## nothing in the format grows with play except the per-floor records, which are capped at six.
## Anything approaching this ceiling is a file that has been appended to or filled with junk, and
## refusing to parse it is cheaper than finding out what it parses into.
const MAX_SAVE_BYTES := 256 * 1024

## Seconds of quiet before a requested save is actually written. A settings slider emits a
## value every frame it is dragged; without this, one drag is sixty file writes.
const SAVE_DEBOUNCE_SECONDS := 0.5

## Seconds before a failed write is attempted again. Far longer than the debounce on purpose: a
## write that just failed will probably still fail a frame later, and the point is to survive a
## transient condition rather than to hammer a full disk sixty times a second.
const SAVE_RETRY_SECONDS := 5.0

signal settings_changed(settings: GameSettings)

## Emitted once, when the persistent state below has been loaded and applied. Consumers that may
## start either side of that moment must check `is_initialized()` first: a signal already emitted
## is a signal that never arrives, and a menu awaiting it would hang on the second visit.
signal initialized

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

## The run the player can go back to, or null. Written at a floor boundary and cleared by every
## way a run can end. Private with accessors because the two operations that may touch it —
## storing one and clearing it — both have to reach the disk immediately, and a field anyone
## could assign would make "the file says one thing and the manager another" reachable.
var _checkpoint: RunCheckpoint = null

## Set when the file on disk was written by a build newer than this one. Every write is refused
## while it is true: the newer build recorded fields this one does not know about, and writing
## our idea of the save over it would delete them silently. Failing closed loses this session's
## settings changes; the alternative loses the player's run.
var _writes_refused := false

## Set when the save in use was recovered from the backup or an orphaned temporary rather than
## read from the primary. It costs the run in progress, and only the run — see `_read_checkpoint`.
var _recovered := false

## Whether the state above came from disk rather than from the defaults it was declared with.
## Every write is refused while it is false — see `save_game`.
var _initialized := false

## So that refusing a write before initialization costs one log line rather than one per caller.
var _warned_early_write := false

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
var _backup_path := SAVE_BACKUP_PATH
var _corrupt_path := SAVE_CORRUPT_PATH


func _ready() -> void:
	# Settings must keep applying while the tree is paused: the settings screen is reachable
	# from the pause menu, and a volume slider that only worked while unpaused would look
	# broken in the one place it is used.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.boss_defeated.connect(_on_boss_defeated)


## Loads the save and announces that it is safe to read. Called once, by the bootstrap scene,
## after it has settled whatever it can about cloud state.
##
## Idempotent because the alternative is a second load discarding whatever the session has
## changed since the first — a bootstrap that retried, or a second entry into the boot scene,
## would silently roll the player back rather than fail visibly.
##
## `_initialized` is set *before* the load, not after: `load_game` writes back a save it had to
## recover, and that write has to be allowed to happen.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	load_game()
	initialized.emit()


## Whether `initialize` has run. Read by anything that can start before the save exists.
func is_initialized() -> bool:
	return _initialized


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


# --- Run checkpoint -----------------------------------------------------------


## The run the player left, or null. Whether it can actually be *played* is a separate question
## — see `RunCheckpoint.validate`, which needs the campaign this node deliberately knows nothing
## about.
func get_checkpoint() -> RunCheckpoint:
	return _checkpoint


func has_checkpoint() -> bool:
	return _checkpoint != null


## Records the run at a floor boundary and writes it out now rather than in half a second.
##
## The debounce exists for settings sliders, which emit sixty times a drag. A checkpoint is the
## opposite case: it happens once a floor, and the entire reason it exists is the session ending
## unexpectedly — a crash or a closed lid inside the debounce window would lose exactly the thing
## being saved.
func store_checkpoint(checkpoint: RunCheckpoint) -> void:
	_checkpoint = checkpoint
	_dirty = true
	save_game()


## Forgets the run in progress. Called on every ending: victory, destruction, abandoning to the
## title screen, and starting a new run.
##
## Written out immediately for the same reason as storing one, mirrored: a checkpoint that
## outlived the run it belonged to would offer the player a run they had already finished, and
## "continue" would hand back the scrap, the build, and the boss they had just lost with.
##
## Does nothing when there is no checkpoint, so the four callers can all call it unconditionally
## rather than each deciding whether there is anything to clear.
func clear_checkpoint() -> void:
	if _checkpoint == null:
		return
	_checkpoint = null
	_dirty = true
	save_game()


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

	if not _initialized:
		# Refused rather than left pending, and refused rather than queued. Before `initialize`
		# every field this writes holds the default it was declared with, so the file this would
		# produce is a *new* save — written over the real one, which is the exact way a slow cloud
		# fetch turns into a wiped profile. Queuing would be worse than refusing: the write would
		# land later carrying the same defaults, having overwritten what the load just brought in.
		_dirty = false
		if not _warned_early_write:
			_warned_early_write = true
			push_warning("SaveManager: refusing to save before initialize(); nothing is loaded yet.")
		return

	if _writes_refused:
		# Not retryable, so it is not left pending: the file will still have been written by a
		# newer build in five seconds' time, and a pending write would only mean `_process` came
		# back here every five seconds for the rest of the session. Warned once by `_migrate`,
		# where the reason is known.
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
## Three steps, and each one is a failure this has actually had:
##
##   1. **Write the temporary file.** A crash here costs the temporary and nothing else.
##   2. **Copy the current save aside.** One generation of backup, taken from a file that has
##      already been proved readable — copying an unreadable primary over a good backup would
##      turn one broken file into two.
##   3. **Rename over the real file.** Atomic on every platform this ships to, which is what
##      makes a torn save impossible rather than unlikely.
func _write_save_file() -> String:
	var payload := {
		"save_version": SAVE_VERSION,
		"settings": settings.to_dict(),
		"unlocks": _to_string_array(unlocked_items),
		"bosses_defeated": _to_string_array(bosses_defeated),
		"statistics": best.to_dict(),
		"tutorial_completed": tutorial_completed,
		# Present and null rather than absent when there is no run, so "this build does not write
		# checkpoints" and "this player has no run in progress" are distinguishable in a file
		# somebody is looking at to work out why a run did not come back.
		"checkpoint": _checkpoint.to_dict() if _checkpoint != null else null,
	}

	var file := FileAccess.open(_temp_path, FileAccess.WRITE)
	if file == null:
		return "could not write %s (%s)" % [
			_temp_path, error_string(FileAccess.get_open_error())
		]
	file.store_string(JSON.stringify(payload, "  "))
	file.close()

	_back_up_current_save()

	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_temp_path),
		ProjectSettings.globalize_path(_save_path),
	)
	if error != OK:
		return "could not replace %s (%s)" % [_save_path, error_string(error)]

	_flush_web_filesystem()
	return ""


## Keeps the save that is about to be replaced, if it is worth keeping.
##
## Deliberately silent about its own failures. A backup that cannot be made is not a reason to
## fail the write that is about to succeed — the player keeps their current save either way, and
## the alternative is a full disk turning "no spare copy" into "no save at all".
func _back_up_current_save() -> void:
	if not FileAccess.file_exists(_save_path):
		return
	# Only a file that reads as a save. The backup exists to be the thing to fall back to, and a
	# backup made from a corrupt primary is a second copy of the corruption — which is precisely
	# the failure it is supposed to survive.
	if _parse_save_file(_save_path).is_empty():
		return
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(_save_path),
		ProjectSettings.globalize_path(_backup_path),
	)


## On the Web, `user://` is an IndexedDB image that the browser writes back asynchronously. A
## player who closes the tab straight after a boundary would otherwise lose the checkpoint that
## the game had already reported as written — the file is in the in-memory filesystem and never
## reaches the database. Godot syncs on its own schedule; this asks for it now, which is what
## makes "the save landed" mean the same thing in a browser as it does on a desktop.
##
## A no-op everywhere else, and guarded rather than merely relied upon to be one.
func _flush_web_filesystem() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()


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
	_checkpoint = _read_checkpoint(data)
	apply_settings()

	# A recovered save is written back to the primary immediately, so a session that recovers and
	# then crashes does not have to recover again from the same fallback — and, more importantly, so
	# the next launch reads an ordinary save rather than one that still contains the run
	# `_read_checkpoint` has just refused. Written from this node's state rather than copied from
	# the fallback file, which is what makes those two the same thing.
	if _recovered and not _writes_refused:
		_dirty = true
		save_game()


## Finds the best readable save among the files that could be one, in the order they are worth
## trusting.
##
## The primary first, obviously. Then the backup, which is a file this node wrote and then proved
## readable, so it is the known-good fallback. Then the temporary file, last and only if nothing
## else survived: an orphaned temporary is either a complete write whose rename lost a race — in
## which case it is the newest state there is — or a half-written file from a crash, and there is
## no way to tell those apart beyond it parsing. Newest-but-unproven is worth having when the
## alternative is starting from defaults, and worth nothing when a proven file exists.
##
## Whatever is adopted from a fallback is written back to the primary immediately, so the next
## launch is an ordinary one rather than another recovery.
func _read_save_file() -> Dictionary:
	# Decided by the file about to be read, not inherited. `load_game` is called again whenever the
	# manager is pointed somewhere else, and a session frozen by a future-version file it no longer
	# has any reason to protect would refuse writes for good.
	_writes_refused = false
	_recovered = false

	var primary := _parse_save_file(_save_path)
	if not primary.is_empty():
		# A temporary file left beside a readable save is debris from a write that failed after the
		# file was written: keeping it would make the *next* recovery adopt a state older than the
		# save it is recovering from.
		_discard_file(_temp_path)
		return _migrate(primary, _save_path)

	var had_primary := FileAccess.file_exists(_save_path)
	for path: String in [_backup_path, _temp_path]:
		var recovered := _parse_save_file(path)
		if recovered.is_empty():
			continue

		_recovered = true
		push_warning(
			"SaveManager: %s could not be read; recovered from %s." % [_save_path, path]
		)
		# Moved aside rather than deleted or overwritten. It is the only evidence of what went
		# wrong, and a player who has just lost a save is owed the bytes at least.
		if had_primary:
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(_save_path),
				ProjectSettings.globalize_path(_corrupt_path),
			)
		return _migrate(recovered, path)

	if had_primary:
		push_warning(
			"SaveManager: %s could not be read and there is no usable backup; starting from defaults."
			% _save_path
		)
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_save_path),
			ProjectSettings.globalize_path(_corrupt_path),
		)
	_discard_file(_temp_path)
	return {}


## A save file's contents, or an empty dictionary if it is missing, empty, oversized, not JSON,
## or JSON that is not an object. Every one of those is a file that cannot be read, and the
## caller's job is to try the next candidate rather than to tell them apart.
func _parse_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	# Checked before the bytes are read rather than after: the point of a ceiling is not to
	# validate a large file, it is to never hold one.
	var length := file.get_length()
	if length == 0 or length > MAX_SAVE_BYTES:
		if length > MAX_SAVE_BYTES:
			push_warning("SaveManager: %s is %d bytes and cannot be a save file." % [path, length])
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Brings an older file up to the current shape, and decides what to do about a newer one.
##
## Version 1 had no run checkpoint. Nothing else about the format changed, so migrating a version
## 1 file is reading it: every field it has is still a field, and the checkpoint it lacks reads
## as "no run in progress", which is exactly what a version 1 player had.
##
## A file from a *newer* build is read for what is recognised and then **frozen**. Every reader
## here already ignores fields it does not know, so a player who rolls back a build can still see
## their settings and records — but writing this build's idea of the save back over it would
## delete whatever the newer build had added, silently and permanently. Refusing every subsequent
## write is the only one of the three options in the plan (refuse, preserve unknown fields, back
## up and migrate) that cannot lose data it does not understand.
func _migrate(data: Dictionary, path: String) -> Dictionary:
	var raw_version: Variant = data.get("save_version")
	var version := int(raw_version) if raw_version is float or raw_version is int else 0
	if version > SAVE_VERSION:
		_writes_refused = true
		push_warning(
			("SaveManager: %s was written by a newer build (version %d, this build writes %d). "
			% [path, version, SAVE_VERSION])
			+ "Reading what is recognised; nothing will be saved this session, so that build's "
			+ "data is not overwritten."
		)
	return data


## The run in progress, or null. Structural checks only: whether the run is *playable* depends on
## the campaign, which this node has no business loading — see `RunCheckpoint.validate`, called by
## whoever is about to resume.
##
## A checkpoint from a newer build is ignored rather than read. The rest of the save survives a
## rollback because every reader skips what it does not recognise, but a run is not a collection
## of independent fields: half a checkpoint is a run missing state the newer build was relying on,
## and resuming it would be worse than not offering it.
##
## A *recovered* save gives up its run too, and this is the sharper of the two rules. The backup is
## by definition one generation old, so its checkpoint may describe a run that has since been won,
## lost, or abandoned — and resuming a finished run would hand back its scrap, its build, and its
## boss credit, then file a second result for it. Records and settings being one save out of date
## is an inconvenience; a run counted twice is a lifetime record the player cannot repair. So a
## recovery keeps everything that only moves forward and refuses the one thing that does not.
func _read_checkpoint(data: Dictionary) -> RunCheckpoint:
	if _writes_refused or _recovered:
		return null
	var raw: Variant = data.get("checkpoint")
	return RunCheckpoint.from_dict(raw as Dictionary) if raw is Dictionary else null


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

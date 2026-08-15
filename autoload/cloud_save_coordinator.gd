extends Node
## Keeps the local save and the Wavedash copy of it in agreement, without ever letting the cloud
## be the reason a player loses progress. Phase 4 of the Wavedash implementation.
##
## The rule this is built around: **local saving is authoritative and this node is a follower.**
## `SaveManager` writes files and announces them; this uploads what it is told about. A network
## that is down, an account that is signed out, a platform that answers with nonsense — none of
## them may fail a local write, re-dirty it, delay it, or change what it contains. The worst a
## broken cloud is allowed to do is leave the game exactly as good as a game with no cloud.
##
## The other rule is that nothing is ever merged. A save is adopted whole or not at all. Merging
## fields across two divergent saves produces a third save that neither device ever had — one with
## this device's unlocks and the other's checkpoint, describing a run that never happened. When
## the two sides have genuinely diverged the player is asked, and the copy they did not choose is
## archived rather than deleted.
##
## ### Why the cloud copy lives at its own path
##
## The platform's file API is a *sync*: `download(path)` fetches the remote object stored under
## `path` and writes it into the local file at `path`. The remote key and the local destination
## are the same string. So `user://save.json` is never used as a remote key — if it were, every
## download would land directly on the canonical save, and validation would happen after the
## damage. Instead the cloud copy is `user://cloud/save.json`, which is both the staging file and
## the remote key. Downloads land in staging by construction rather than by remembering to.
##
## ### What this cannot do
##
## Wavedash exposes an ETag but documents no conditional upload, so there is no compare-and-swap:
## two devices writing at the same instant can still have one overwrite the other, and no amount
## of care here changes that. What is detectable is the ordinary case — divergence noticed at
## startup — and that is what the table below is for.

## Where the cloud copy is staged, and the key it is stored under remotely. Never
## `user://save.json`; see the class comment.
const REMOTE_SAVE_PATH := "user://cloud/save.json"

## What this node remembers between sessions: the hash of the bytes both sides last agreed on, the
## last ETag the platform mentioned, and whose account that agreement was with. Local-only — it
## describes this device's relationship with the cloud, and is worthless on any other device.
const SYNC_STATE_PATH := "user://cloud/sync_state.json"

## Where a save that lost a conflict goes. Kept rather than deleted: the losing copy is somebody's
## afternoon, and a player who picks wrong at four in the morning has something to be pointed at.
const ARCHIVE_DIR := "user://cloud/archive"

## The largest cloud file that will be looked at, matching `SaveManager.MAX_SAVE_BYTES`. A real
## save is about four kilobytes. Anything near this ceiling is a file that has been appended to or
## filled with junk, and refusing to parse it is cheaper than finding out what it parses into.
const MAX_SAVE_BYTES := 256 * 1024

## How long to wait before retrying a failed upload, in seconds, and how many attempts there are.
## Bounded on purpose: past the end of this list the save is simply pending, and the next commit
## or the next launch will carry it. A queue that retries forever is a queue that spends a
## player's battery describing a network that is not coming back.
const UPLOAD_BACKOFF_SECONDS: Array[float] = [2.0, 5.0, 15.0]

enum Status {
	## No cloud in play: desktop, signed out, offline, or the platform could not be reached.
	LOCAL_ONLY,
	## Working out what the cloud has, at startup.
	SYNCING,
	## An upload is in flight.
	SAVING,
	## The platform has confirmed it holds the current save.
	SYNCED,
	## Written locally, not yet in the cloud. The state a closed tab leaves behind.
	PENDING,
}

## Which copy the player chose when the two had diverged.
enum Resolution {
	KEEP_LOCAL,
	TAKE_CLOUD,
}

signal status_changed(status: Status)

## Emitted when the two sides have diverged and only the player can settle it. The payloads
## describe each candidate well enough to choose between them. Whoever listens must answer with
## `resolve_conflict`; startup waits for that answer.
signal conflict_detected(local: Dictionary, cloud: Dictionary)

## Internal handshake for the wait above.
signal _conflict_resolved(resolution: Resolution)

## Swapped for a fake by the suite. Everything platform-shaped lives behind it.
var backend: CloudBackend = null

var _status: Status = Status.LOCAL_ONLY

## The hash of the newest committed local save, and the hash the cloud is known to hold. When they
## differ there is work to do; when they agree there is not. Coalescing falls out of comparing
## them rather than out of a queue: five commits during one upload leave one hash to catch up to,
## not five uploads to perform.
var _latest_hash := ""
var _synced_hash := ""

## One upload at a time. A second commit during an upload updates `_latest_hash` and returns —
## the loop already running notices and goes round again.
var _uploading := false

## Set while startup reconciliation is in flight, so a save committed during it cannot race the
## decision being made about which save is authoritative.
var _reconciling := false

## Paths, as variables only so the suite can point them at something disposable. Nothing in the
## game reassigns them, and a test that used the real ones would fight the save file of whoever
## ran it. Same reasoning as `SaveManager`.
var _remote_path := REMOTE_SAVE_PATH
var _sync_state_path := SYNC_STATE_PATH
var _archive_dir := ARCHIVE_DIR


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if backend == null:
		backend = WavedashCloudBackend.new()

	# Deferred because this node is registered ahead of `SaveManager` — it has to exist before the
	# bootstrap can call `reconcile`, and the bootstrap runs before anything loads a save. Autoloads
	# are added one at a time, so the manager is not there yet when this line runs; it is by the end
	# of the frame. Connecting on a deferred call makes the binding independent of the order in
	# `project.godot` rather than quietly dependent on it.
	_bind_save_manager.call_deferred()


func _bind_save_manager() -> void:
	if not SaveManager.local_save_committed.is_connected(_on_local_save_committed):
		SaveManager.local_save_committed.connect(_on_local_save_committed)


# --- Startup reconciliation ---------------------------------------------------


## Settles which save is authoritative, before anything is allowed to read one.
##
## Called by the bootstrap between connecting to the platform and initializing `SaveManager`, which
## is the only window in which adopting a different save is free: nothing has read the old one yet,
## so nothing has to be told it changed.
##
## Returns when the question is settled, however it was settled. Every failure path ends in
## local-only, which is a working game with a local save — not an error the player has to act on.
func reconcile() -> void:
	if _reconciling:
		return
	_reconciling = true
	_set_status(Status.SYNCING)

	await _reconcile_inner()

	_reconciling = false
	# A save committed while the decision was being made still has to reach the cloud.
	if _status != Status.LOCAL_ONLY and _latest_hash != "" and _latest_hash != _synced_hash:
		_start_upload()


func _reconcile_inner() -> void:
	if backend == null or not backend.is_available():
		_set_status(Status.LOCAL_ONLY)
		return

	var save_path := SaveManager.save_file_path()
	var local_hash := _hash_of(save_path)
	_latest_hash = local_hash

	# Whose agreement this is. A base recorded against another account describes a relationship
	# this player was never part of, and using it would let one account's save be treated as the
	# common ancestor of another's — the fastest possible way to hand somebody else's progress to
	# the wrong person, or to overwrite theirs.
	var state := _read_sync_state()
	var base_hash := ""
	if state.get("player_id", "") == backend.player_id():
		base_hash = str(state.get("hash", ""))

	var probe := await backend.exists(_remote_path)
	if not probe.get("success", false):
		# The question could not be answered. Not knowing what is up there is exactly the state in
		# which uploading is dangerous: this device would be writing over a remote save it has
		# never seen, on the strength of a network error.
		_log("could not reach cloud storage (%s): local-only" % probe.get("message", ""))
		_set_status(Status.LOCAL_ONLY)
		return

	if not probe.get("present", false):
		if local_hash.is_empty():
			# Nothing anywhere. Defaults, and the first committed save will populate the cloud.
			_set_status(Status.SYNCED)
			_write_sync_state("", probe.get("etag", ""))
			return
		_log("no cloud save yet: uploading this device's")
		await _upload_now(local_hash, probe.get("etag", ""))
		return

	var download := await backend.download(_remote_path)
	if not download.get("success", false):
		_log("cloud save could not be downloaded (%s): local-only" % download.get("message", ""))
		_set_status(Status.LOCAL_ONLY)
		return

	var candidate := _inspect_staged_file()
	if not candidate.get("ok", false):
		await _handle_unusable_cloud_save(candidate, local_hash, download.get("etag", ""))
		return

	var cloud_hash: String = candidate["hash"]

	if cloud_hash == local_hash:
		_synced_hash = local_hash
		_write_sync_state(local_hash, download.get("etag", ""))
		_set_status(Status.SYNCED)
		return

	if local_hash.is_empty():
		_log("no local save: adopting the cloud's")
		_adopt_cloud(download.get("etag", ""))
		return

	if base_hash.is_empty():
		# First sync on this device, or a base belonging to another account. Two different saves
		# and no way to tell which is derived from which: the one thing that must not happen here
		# is a guess.
		await _resolve_divergence(local_hash, candidate, download.get("etag", ""))
		return

	if local_hash == base_hash:
		_log("cloud moved on and this device did not: adopting the cloud's")
		_adopt_cloud(download.get("etag", ""))
		return

	if cloud_hash == base_hash:
		_log("this device moved on and the cloud did not: uploading")
		await _upload_now(local_hash, download.get("etag", ""))
		return

	await _resolve_divergence(local_hash, candidate, download.get("etag", ""))


## A cloud file that exists but cannot be adopted. Two very different cases, and conflating them
## would be a data-loss bug in one direction or the other.
func _handle_unusable_cloud_save(candidate: Dictionary, local_hash: String, etag: String) -> void:
	var reason: String = candidate.get("reason", "unusable")

	if candidate.get("future_version", false):
		# Written by a newer build. Not corrupt — richer than this build understands. Adopting it
		# would drop the fields this build cannot represent, and uploading over it would do the
		# same thing to the copy the newer build is still using. So: touch nothing, play locally.
		push_warning(
			"CloudSaveCoordinator: the cloud save was written by a newer build (%s). "
			% reason + "Playing from the local save and leaving the cloud copy alone."
		)
		_set_status(Status.LOCAL_ONLY)
		return

	# Junk: unparseable, oversized, or not a save at all. Nothing of the player's is in it, so
	# replacing it costs nothing — but it is archived first, because "nothing of the player's is
	# in it" is a judgement this code is making about a file it could not read.
	_log("cloud save is unusable (%s): archiving it and uploading this device's" % reason)
	_archive(_remote_path, "cloud")
	if local_hash.is_empty():
		_set_status(Status.LOCAL_ONLY)
		return
	await _upload_now(local_hash, etag)


## Both sides changed since they last agreed. The player decides; nothing is overwritten until
## they do, and the copy they reject is archived rather than dropped.
func _resolve_divergence(local_hash: String, candidate: Dictionary, etag: String) -> void:
	var local_info := _describe_save_file(SaveManager.save_file_path())
	var cloud_info: Dictionary = candidate.get("summary", {})

	if conflict_detected.get_connections().is_empty():
		# Nobody is listening, so nobody can answer, and waiting would hang the boot screen
		# forever. Keeping the local save is the choice that loses nothing: this device's save
		# stays, the cloud's is archived here and still in the cloud, and the player is not
		# silently handed a save they did not ask for.
		push_warning(
			"CloudSaveCoordinator: local and cloud saves diverged with nothing able to ask the "
			+ "player. Keeping the local save; the cloud copy is archived."
		)
		_archive(_remote_path, "cloud")
		await _upload_now(local_hash, etag)
		return

	# Deferred, so that the wait below is already in place when the question is asked. A listener
	# that answers immediately — a test, or a UI that had the answer cached — would otherwise reply
	# to a question nobody was listening for yet, and this would wait for a second answer that
	# never comes. Emitting first and awaiting second reads naturally and deadlocks.
	conflict_detected.emit.call_deferred(local_info, cloud_info)
	var resolution: Resolution = await _conflict_resolved

	if resolution == Resolution.TAKE_CLOUD:
		_archive(SaveManager.save_file_path(), "local")
		_adopt_cloud(etag)
		return

	_archive(_remote_path, "cloud")
	await _upload_now(local_hash, etag)


## Answers the question `conflict_detected` asked.
func resolve_conflict(resolution: Resolution) -> void:
	_conflict_resolved.emit(resolution)


## Replaces the local save with the staged cloud one, atomically, then records that the two agree.
##
## Atomic for the same reason `SaveManager` writes through a temporary file: the moment between
## "the old save is gone" and "the new one is complete" must not be a moment anything can crash
## in. Renaming a validated copy has no such moment.
func _adopt_cloud(etag: String) -> void:
	var save_path := SaveManager.save_file_path()
	var staging := save_path + ".cloud"

	var error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(_remote_path),
		ProjectSettings.globalize_path(staging),
	)
	if error != OK:
		push_warning("CloudSaveCoordinator: could not stage the cloud save (%s)." % error_string(error))
		_set_status(Status.LOCAL_ONLY)
		return

	error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(staging),
		ProjectSettings.globalize_path(save_path),
	)
	if error != OK:
		push_warning("CloudSaveCoordinator: could not adopt the cloud save (%s)." % error_string(error))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))
		_set_status(Status.LOCAL_ONLY)
		return

	var adopted := _hash_of(save_path)
	_latest_hash = adopted
	_synced_hash = adopted
	_write_sync_state(adopted, etag)
	_set_status(Status.SYNCED)


# --- Uploading ----------------------------------------------------------------


## Every committed save arrives here. Cheap on purpose: it records what the newest save is and
## gets out of the way, because it runs on the same frame as a write the player is waiting on.
func _on_local_save_committed(_path: String, content_hash: String) -> void:
	_latest_hash = content_hash

	if _reconciling:
		# Reconciliation is still deciding which save wins. It uploads whatever is newest when it
		# finishes, so starting a second upload here would be racing the decision.
		return

	if backend == null or not backend.is_available():
		_set_status(Status.PENDING if _status != Status.LOCAL_ONLY else Status.LOCAL_ONLY)
		return

	_start_upload()


func _start_upload() -> void:
	if _uploading:
		# Coalesced. The loop below re-reads `_latest_hash` every pass, so the newest save is the
		# one that ends up in the cloud regardless of how many arrived while it was busy.
		return
	_upload_loop(UPLOAD_BACKOFF_SECONDS.size())


## Uploads until the cloud holds the newest save, or until the retries run out.
##
## `max_retries` is an argument because startup passes zero. The backoff is there to survive a
## network blip during play, where nobody is waiting; at boot the player is looking at a status
## screen, and twenty-two seconds of patient retrying is indistinguishable from a hung game. A
## save that does not make it up during boot is pending, which the next commit resolves.
func _upload_loop(max_retries: int) -> void:
	_uploading = true

	var attempt := 0
	while _latest_hash != _synced_hash and _latest_hash != "":
		var target := _latest_hash
		_set_status(Status.SAVING)

		if not _stage_local_save():
			_set_status(Status.PENDING)
			break

		var result: Dictionary = await backend.upload(_remote_path)
		if result.get("success", false):
			_synced_hash = target
			_write_sync_state(target, result.get("etag", ""))
			attempt = 0
			# Not necessarily done: a save committed during that upload leaves `_latest_hash`
			# ahead of what was just sent, and the loop goes round for it.
			if _latest_hash == target:
				_set_status(Status.SYNCED)
			continue

		if attempt >= max_retries:
			_log("giving up on this upload (%s); the save is on disk and will retry"
				% result.get("message", ""))
			_set_status(Status.PENDING)
			break

		var delay: float = UPLOAD_BACKOFF_SECONDS[attempt]
		attempt += 1
		_set_status(Status.PENDING)
		await get_tree().create_timer(delay).timeout

	_uploading = false


## Runs an upload to completion from a caller that wants to wait for it. Used by reconciliation,
## which must not hand over to the menu with the cloud in a state it has not accounted for.
func _upload_now(target_hash: String, _etag: String) -> void:
	_latest_hash = target_hash
	if _uploading:
		return
	await _upload_loop(0)


## Copies the committed save into the staging file, which is what actually gets uploaded.
##
## A copy rather than uploading `user://save.json` directly, because that path is deliberately not
## a remote key — see the class comment. It also means an upload in flight is reading a snapshot,
## so a save committed halfway through cannot change the bytes underneath it.
func _stage_local_save() -> bool:
	var save_path := SaveManager.save_file_path()
	if not FileAccess.file_exists(save_path):
		return false
	if not _ensure_directory(_remote_path.get_base_dir()):
		return false
	var error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(save_path),
		ProjectSettings.globalize_path(_remote_path),
	)
	if error != OK:
		push_warning("CloudSaveCoordinator: could not stage the save for upload (%s)." % error_string(error))
		return false
	return true


# --- Inspecting candidates ----------------------------------------------------


## Decides whether the freshly downloaded file is something this build may adopt.
##
## Returns `{ok, reason, future_version, hash, summary}`. The three failure modes are kept apart
## because they deserve opposite responses: junk may be replaced, a future save must be left
## completely alone, and a valid save is a candidate.
func _inspect_staged_file() -> Dictionary:
	if not FileAccess.file_exists(_remote_path):
		return _rejected("the download reported success but left no file")

	var file := FileAccess.open(_remote_path, FileAccess.READ)
	if file == null:
		return _rejected("could not be opened (%s)" % error_string(FileAccess.get_open_error()))

	var size := file.get_length()
	file.close()
	if size > MAX_SAVE_BYTES:
		# Checked before parsing, not after: the point is to not hand a parser a file of unknown
		# provenance and unbounded size.
		return _rejected("%d bytes, over the %d-byte ceiling" % [size, MAX_SAVE_BYTES])

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_remote_path))
	if parsed is not Dictionary:
		return _rejected("is not a JSON object")

	var data := parsed as Dictionary
	var version: Variant = data.get("save_version")
	if version is not float and version is not int:
		return _rejected("has no save version")
	if int(version) > SaveManager.SAVE_VERSION:
		return _rejected(
			"version %d, newer than this build's %d" % [int(version), SaveManager.SAVE_VERSION],
			true,
		)

	return {
		"ok": true,
		"reason": "",
		"future_version": false,
		"hash": _hash_of(_remote_path),
		"summary": _summarize(data),
	}


func _rejected(reason: String, future := false) -> Dictionary:
	return {"ok": false, "reason": reason, "future_version": future, "hash": "", "summary": {}}


## Enough of a save to choose between two of them, without the chooser having to understand the
## format. Deliberately not the whole file: a player picking between two saves needs to recognise
## one of them, not audit it.
func _summarize(data: Dictionary) -> Dictionary:
	var statistics: Variant = data.get("statistics")
	var checkpoint: Variant = data.get("checkpoint")
	var summary := {
		"runs_started": 0,
		"bosses_defeated": 0,
		"has_checkpoint": checkpoint is Dictionary,
		# `RunCheckpoint` counts floors from one, the way the HUD says them out loud, so this is
		# the number the player saw rather than one adjusted on the way to being shown.
		"checkpoint_floor": 0,
	}
	if statistics is Dictionary:
		summary["runs_started"] = int((statistics as Dictionary).get("runs_started", 0))
	var bosses: Variant = data.get("bosses_defeated")
	if bosses is Array:
		summary["bosses_defeated"] = (bosses as Array).size()
	if checkpoint is Dictionary:
		summary["checkpoint_floor"] = int((checkpoint as Dictionary).get("floor_number", 0))
	return summary


func _describe_save_file(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		return {}
	return _summarize(parsed as Dictionary)


# --- Bookkeeping --------------------------------------------------------------


func _read_sync_state() -> Dictionary:
	if not FileAccess.file_exists(_sync_state_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sync_state_path))
	if parsed is not Dictionary:
		return {}
	return parsed as Dictionary


## Records what the two sides now agree on. Written after the platform has confirmed, never
## before: a base recorded for an upload that failed would make the next launch believe the cloud
## holds something it does not, and quietly skip the upload that would have fixed it.
func _write_sync_state(content_hash: String, etag: String) -> void:
	if not _ensure_directory(_sync_state_path.get_base_dir()):
		return
	var file := FileAccess.open(_sync_state_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"hash": content_hash,
		"etag": etag,
		"player_id": backend.player_id() if backend != null else "",
	}, "  "))
	file.close()


## Keeps a copy of a save that is about to be replaced or rejected.
func _archive(path: String, label: String) -> void:
	if not FileAccess.file_exists(path):
		return
	if not _ensure_directory(_archive_dir):
		return
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path("%s/%s-%s.json" % [_archive_dir, stamp, label]),
	)


func _ensure_directory(path: String) -> bool:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return true
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("CloudSaveCoordinator: could not create %s (%s)." % [path, error_string(error)])
		return false
	return true


func _hash_of(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


# --- Status -------------------------------------------------------------------


func status() -> Status:
	return _status


## What to put in front of the player. `Cloud synced` is never claimed on optimism: it is only
## reachable from a platform call that came back successful.
func status_text() -> String:
	match _status:
		Status.SYNCING:
			return "SYNCING SAVE..."
		Status.SAVING:
			return "SAVING..."
		Status.SYNCED:
			return "CLOUD SYNCED"
		Status.PENDING:
			return "SAVED LOCALLY - CLOUD PENDING"
		_:
			return "SAVED LOCALLY"


func _set_status(new_status: Status) -> void:
	if _status == new_status:
		return
	_status = new_status
	status_changed.emit(_status)


func _log(message: String) -> void:
	if OS.is_debug_build():
		print("CloudSaveCoordinator: ", message)

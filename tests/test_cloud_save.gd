extends TestCase
## Cloud saving. Phase 4 and 5 of the Wavedash implementation.
##
## Every check here is a way a player could lose progress, written down. That is the entire theme:
## none of these are about the happy path working, because the happy path is the one case that
## gets exercised by hand every time anyone opens the game. What does not get exercised by hand is
## a corrupt download, a signed-out session, an upload that fails once, a save that is newer than
## the build reading it, or two devices that both moved on — and each of those, done wrong, is
## somebody's afternoon deleted by a program that thought it was helping.
##
## The cloud is `FakeCloudBackend`, which is the only way most of the above can be produced on
## demand. Nothing here touches Wavedash, the network, or the real save file: the manager and the
## coordinator are pointed at a disposable directory for the duration and put back afterwards.

const SANDBOX := "user://test_only_cloud"
const REMOTE := SANDBOX + "/cloud/save.json"

var _fake: FakeCloudBackend

## Everything borrowed from the live autoloads, put back in `_teardown`. The suites that follow
## share both of them.
var _real_backend: CloudBackend
var _real_save_path: String
var _real_temp_path: String
var _real_backup_path: String
var _real_corrupt_path: String
var _real_remote_path: String
var _real_sync_path: String
var _real_archive_dir: String
var _real_persistence: bool
var _real_initialized: bool


func run() -> void:
	await _test_an_unavailable_cloud_is_never_called()
	await _test_a_first_launch_uploads_the_local_save()
	await _test_a_cloud_save_with_nothing_local_is_adopted()
	await _test_identical_saves_change_nothing()
	await _test_the_cloud_wins_when_only_the_cloud_moved()
	await _test_the_device_wins_when_only_the_device_moved()
	await _test_divergence_asks_the_player()
	await _test_divergence_can_keep_the_local_save()
	await _test_an_unreadable_cloud_save_cannot_replace_a_good_one()
	await _test_an_oversized_cloud_save_cannot_replace_a_good_one()
	await _test_a_newer_save_is_left_completely_alone()
	await _test_a_failed_download_never_uploads_unknown_state()
	await _test_an_unanswerable_cloud_is_not_an_empty_one()
	await _test_commits_are_single_flight_and_land_the_newest()
	await _test_a_failed_upload_retries_and_sends_one_version()
	await _test_a_failed_local_write_never_reaches_the_cloud()
	await _test_an_immediate_checkpoint_save_uploads_at_once()

	_teardown()


# --- Reconciliation -----------------------------------------------------------


## The desktop build, a signed-out browser, a dead network. Not merely "does not crash": it must
## not call the platform at all, because a call whose failure is indistinguishable from "the cloud
## is empty" is the first step towards uploading over a save that was there all along.
func _test_an_unavailable_cloud_is_never_called() -> void:
	_setup()
	_write_local_save(3)
	_fake.available = false

	await CloudSaveCoordinator.reconcile()

	check(
		CloudSaveCoordinator.status() == CloudSaveCoordinator.Status.LOCAL_ONLY,
		"an unavailable cloud leaves the game local-only",
	)
	check(
		_fake.exist_checks == 0 and _fake.downloads == 0 and _fake.uploads == 0,
		"and nothing is asked of the platform at all",
	)
	check(_local_runs() == 3, "the local save is untouched")


func _test_a_first_launch_uploads_the_local_save() -> void:
	_setup()
	_write_local_save(7)

	await CloudSaveCoordinator.reconcile()

	check(_fake.uploads == 1, "an empty cloud gets this device's save (%d uploads)" % _fake.uploads)
	check(_remote_runs() == 7, "and it is the save that was on disk")
	check(
		CloudSaveCoordinator.status() == CloudSaveCoordinator.Status.SYNCED,
		"which counts as synced, because the platform confirmed it",
	)


func _test_a_cloud_save_with_nothing_local_is_adopted() -> void:
	_setup()
	_set_remote_save(11)

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 11, "a new device adopts the cloud save")
	check(_fake.uploads == 0, "without uploading anything over it")


func _test_identical_saves_change_nothing() -> void:
	_setup()
	_write_local_save(4)
	_set_remote_save(4)

	await CloudSaveCoordinator.reconcile()

	check(_fake.uploads == 0, "two identical saves need no upload")
	check(_local_runs() == 4, "and no adoption")
	check(
		CloudSaveCoordinator.status() == CloudSaveCoordinator.Status.SYNCED,
		"they are simply in sync",
	)


## The ordinary cross-device case, and the one the whole Build A to Build B gate rests on: this
## device is exactly where the last sync left it, the cloud has moved on, so the cloud is right.
func _test_the_cloud_wins_when_only_the_cloud_moved() -> void:
	_setup()
	_write_local_save(2)
	_record_sync_base(_local_hash())
	_set_remote_save(9)

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 9, "a cloud save that moved on is adopted")
	check(_fake.uploads == 0, "and this device's older copy is not pushed over it")


func _test_the_device_wins_when_only_the_device_moved() -> void:
	_setup()
	_set_remote_save(2)
	_write_local_save(5)
	_record_sync_base(_remote_hash())

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 5, "a device that moved on keeps its save")
	check(_remote_runs() == 5, "and sends it to the cloud")


## Both moved. There is no correct answer available to the program, and the failure mode of
## guessing is silent: the player finds out an hour later that their afternoon is gone.
func _test_divergence_asks_the_player() -> void:
	_setup()
	_write_local_save(5)
	_record_sync_base("a-hash-neither-side-has-now")
	_set_remote_save(9)

	var asked := [0]
	var answer := func(_local: Dictionary, _cloud: Dictionary) -> void:
		asked[0] += 1
		CloudSaveCoordinator.resolve_conflict(CloudSaveCoordinator.Resolution.TAKE_CLOUD)
	CloudSaveCoordinator.conflict_detected.connect(answer)

	await CloudSaveCoordinator.reconcile()
	CloudSaveCoordinator.conflict_detected.disconnect(answer)

	check(asked[0] == 1, "divergence asks, exactly once (%d)" % asked[0])
	check(_local_runs() == 9, "and the answer is obeyed")
	check(
		_archive_contains("-local.json"),
		"the copy that lost is archived rather than deleted",
	)


func _test_divergence_can_keep_the_local_save() -> void:
	_setup()
	_write_local_save(5)
	_record_sync_base("a-hash-neither-side-has-now")
	_set_remote_save(9)

	var answer := func(_local: Dictionary, _cloud: Dictionary) -> void:
		CloudSaveCoordinator.resolve_conflict(CloudSaveCoordinator.Resolution.KEEP_LOCAL)
	CloudSaveCoordinator.conflict_detected.connect(answer)

	await CloudSaveCoordinator.reconcile()
	CloudSaveCoordinator.conflict_detected.disconnect(answer)

	check(_local_runs() == 5, "keeping this device's save keeps it")
	check(_remote_runs() == 5, "and replaces the cloud's with it")
	check(
		_archive_contains("-cloud.json"),
		"with the cloud's copy archived first",
	)


# --- Refusing bad candidates --------------------------------------------------


func _test_an_unreadable_cloud_save_cannot_replace_a_good_one() -> void:
	_setup()
	_write_local_save(6)
	_fake.set_remote_content(REMOTE, "{ this is not json")

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 6, "a corrupt cloud save cannot overwrite a good local one")
	check(
		_archive_contains("-cloud.json"),
		"it is quarantined instead",
	)
	check(_remote_runs() == 6, "and the good save replaces it in the cloud")


func _test_an_oversized_cloud_save_cannot_replace_a_good_one() -> void:
	_setup()
	_write_local_save(6)
	# Valid JSON, and far too large to be a save. Refused on size before it is ever parsed.
	var padding := "x".repeat(CloudSaveCoordinator.MAX_SAVE_BYTES + 1)
	_fake.set_remote_content(REMOTE, JSON.stringify({"save_version": 2, "padding": padding}))

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 6, "an oversized cloud save cannot overwrite a good local one")


## A save from a build newer than this one. Not corrupt — richer. Adopting it would drop the
## fields this build cannot represent, and uploading over it would do the same to the copy the
## newer build is still using, so the only safe move is to touch nothing.
func _test_a_newer_save_is_left_completely_alone() -> void:
	_setup()
	_write_local_save(6)
	_fake.set_remote_content(REMOTE, JSON.stringify({
		"save_version": SaveManager.SAVE_VERSION + 5,
		"statistics": {"runs_started": 99},
	}))

	await CloudSaveCoordinator.reconcile()

	check(_local_runs() == 6, "a future save is not adopted into an older build")
	check(_fake.uploads == 0, "and is not overwritten by one either")
	check(
		CloudSaveCoordinator.status() == CloudSaveCoordinator.Status.LOCAL_ONLY,
		"the session simply plays locally",
	)


func _test_a_failed_download_never_uploads_unknown_state() -> void:
	_setup()
	_write_local_save(6)
	_set_remote_save(9)
	_fake.download_failures = 99

	await CloudSaveCoordinator.reconcile()

	check(_fake.uploads == 0, "a download that failed is not a licence to upload over the cloud")
	check(_local_runs() == 6, "the local save is left alone")
	check(_remote_runs() == 9, "and so is the cloud's")


## "I could not ask" is not "there is nothing there". Treating the two the same is how a network
## blip on a new device turns into a first upload over an existing save.
func _test_an_unanswerable_cloud_is_not_an_empty_one() -> void:
	_setup()
	_write_local_save(6)
	_set_remote_save(9)
	_fake.exists_failures = 99

	await CloudSaveCoordinator.reconcile()

	check(_fake.uploads == 0, "an unanswerable cloud is not treated as an empty one")
	check(_remote_runs() == 9, "so nothing is written over what is up there")


# --- Uploading ----------------------------------------------------------------


## Saves arrive faster than uploads complete. What must not happen is one upload per save, or —
## much worse — the newest save losing a race to an older one that started first.
func _test_commits_are_single_flight_and_land_the_newest() -> void:
	_setup()
	_write_local_save(1)
	await CloudSaveCoordinator.reconcile()
	var uploads_after_boot := _fake.uploads

	for runs: int in [2, 3, 4]:
		_write_local_save(runs)
		_announce_commit()

	await _wait_for_idle()

	check(_remote_runs() == 4, "the newest save is the one that ends up in the cloud")
	check(
		_fake.uploads - uploads_after_boot <= 3,
		"three rapid saves do not become more than three uploads (%d)"
			% (_fake.uploads - uploads_after_boot),
	)
	check(
		_fake.uploaded_hashes[_fake.uploaded_hashes.size() - 1] == _local_hash(),
		"and what the cloud holds is byte-for-byte what is on disk",
	)


func _test_a_failed_upload_retries_and_sends_one_version() -> void:
	_setup()
	_write_local_save(1)
	await CloudSaveCoordinator.reconcile()

	_fake.upload_failures = 1
	_write_local_save(8)
	_announce_commit()

	await _wait_for_idle()

	check(_remote_runs() == 8, "an upload that failed once still lands")
	check(
		CloudSaveCoordinator.status() == CloudSaveCoordinator.Status.SYNCED,
		"and only then is the save called synced",
	)


## The rule that keeps a broken disk from becoming a broken cloud: nothing is announced, and so
## nothing is uploaded, until the bytes are actually on disk.
func _test_a_failed_local_write_never_reaches_the_cloud() -> void:
	_setup()
	_write_local_save(1)
	await CloudSaveCoordinator.reconcile()
	var uploads_before := _fake.uploads

	# A directory where the temporary file has to go, exactly as a full disk or a permissions
	# problem would present.
	var blocker := ProjectSettings.globalize_path(SaveManager._temp_path)
	DirAccess.remove_absolute(blocker)
	DirAccess.make_dir_absolute(blocker)

	SaveManager.request_save()
	SaveManager.save_game()
	await _wait_for_idle()

	check(SaveManager._dirty, "the failed write is still pending, as it always was")
	check(_fake.uploads == uploads_before, "and nothing was uploaded for a save that never landed")

	DirAccess.remove_absolute(blocker)
	SaveManager._dirty = false
	SaveManager._failed_writes = 0


## Floor boundaries bypass the debounce and write immediately, because the session ending
## unexpectedly is the whole reason they exist. The upload has to inherit that urgency: a
## checkpoint sitting in a queue when the tab closes is a checkpoint that never happened.
func _test_an_immediate_checkpoint_save_uploads_at_once() -> void:
	_setup()
	_write_local_save(1)
	await CloudSaveCoordinator.reconcile()
	var uploads_before := _fake.uploads

	var checkpoint := RunCheckpoint.new()
	checkpoint.floor_number = 3
	checkpoint.run_seed = 12345
	SaveManager.store_checkpoint(checkpoint)

	await _wait_for_idle()

	check(
		_fake.uploads > uploads_before,
		"storing a checkpoint uploads it rather than waiting for the next save",
	)
	var landed: Variant = JSON.parse_string(_fake.files.get(REMOTE, ""))
	check(
		landed is Dictionary and (landed as Dictionary).get("checkpoint") != null,
		"and what landed contains the checkpoint",
	)

	SaveManager.clear_checkpoint()
	await _wait_for_idle()


# --- Fixture ------------------------------------------------------------------


## Points both autoloads at a disposable directory with a fake cloud behind them, and clears
## everything either of them remembers from the previous check.
func _setup() -> void:
	if _real_save_path.is_empty():
		_real_backend = CloudSaveCoordinator.backend
		_real_save_path = SaveManager._save_path
		_real_temp_path = SaveManager._temp_path
		_real_backup_path = SaveManager._backup_path
		_real_corrupt_path = SaveManager._corrupt_path
		_real_remote_path = CloudSaveCoordinator._remote_path
		_real_sync_path = CloudSaveCoordinator._sync_state_path
		_real_archive_dir = CloudSaveCoordinator._archive_dir
		_real_persistence = SaveManager.persistence_enabled
		_real_initialized = SaveManager._initialized

	_wipe(SANDBOX)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SANDBOX + "/cloud"))

	SaveManager._save_path = SANDBOX + "/save.json"
	SaveManager._temp_path = SANDBOX + "/save.json.tmp"
	SaveManager._backup_path = SANDBOX + "/save.json.bak"
	SaveManager._corrupt_path = SANDBOX + "/save.json.corrupt"
	SaveManager.persistence_enabled = true
	# Writes are refused before initialization, and these checks are all about writes.
	SaveManager._initialized = true
	SaveManager._dirty = false
	# A suite earlier in the run reads a save written by a newer build, which freezes writes for
	# the rest of the session by design. A cold launch does not start that way, and these checks
	# are about a manager that can write.
	SaveManager._writes_refused = false

	CloudSaveCoordinator._remote_path = REMOTE
	CloudSaveCoordinator._sync_state_path = SANDBOX + "/cloud/sync_state.json"
	CloudSaveCoordinator._archive_dir = SANDBOX + "/cloud/archive"
	CloudSaveCoordinator._latest_hash = ""
	CloudSaveCoordinator._synced_hash = ""
	CloudSaveCoordinator._uploading = false
	CloudSaveCoordinator._reconciling = false
	CloudSaveCoordinator._status = CloudSaveCoordinator.Status.LOCAL_ONLY

	_fake = FakeCloudBackend.new()
	CloudSaveCoordinator.backend = _fake


func _teardown() -> void:
	CloudSaveCoordinator.backend = _real_backend
	CloudSaveCoordinator._remote_path = _real_remote_path
	CloudSaveCoordinator._sync_state_path = _real_sync_path
	CloudSaveCoordinator._archive_dir = _real_archive_dir
	CloudSaveCoordinator._latest_hash = ""
	CloudSaveCoordinator._synced_hash = ""
	CloudSaveCoordinator._status = CloudSaveCoordinator.Status.LOCAL_ONLY

	SaveManager._save_path = _real_save_path
	SaveManager._temp_path = _real_temp_path
	SaveManager._backup_path = _real_backup_path
	SaveManager._corrupt_path = _real_corrupt_path
	SaveManager.persistence_enabled = _real_persistence
	SaveManager._initialized = _real_initialized
	SaveManager._dirty = false

	_wipe(SANDBOX)


## A save file with a recognisable number in it, written directly rather than through the manager
## so that each check controls exactly what both sides hold.
func _write_local_save(runs_started: int) -> void:
	var file := FileAccess.open(SaveManager._save_path, FileAccess.WRITE)
	file.store_string(_save_json(runs_started))
	file.close()


func _set_remote_save(runs_started: int) -> void:
	_fake.set_remote_content(REMOTE, _save_json(runs_started))


func _save_json(runs_started: int) -> String:
	return JSON.stringify({
		"save_version": SaveManager.SAVE_VERSION,
		"settings": {},
		"unlocks": [],
		"bosses_defeated": [],
		"statistics": {"runs_started": runs_started},
		"tutorial_completed": true,
		"checkpoint": null,
	}, "  ")


## Stands in for `SaveManager` announcing a write it has just made. Used where the point of the
## check is what the coordinator does with a commit, not how the file got there.
func _announce_commit() -> void:
	SaveManager.local_save_committed.emit(SaveManager._save_path, _local_hash())


## Puts a last-agreed hash in the sidecar, which is how a test says "these two were in sync, and
## then one of them changed".
func _record_sync_base(content_hash: String) -> void:
	var file := FileAccess.open(CloudSaveCoordinator._sync_state_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"hash": content_hash,
		"etag": "",
		"player_id": _fake.player_id(),
	}))
	file.close()


func _runs_in(text: String) -> int:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return -1
	var statistics: Variant = (parsed as Dictionary).get("statistics")
	if statistics is not Dictionary:
		return -1
	return int((statistics as Dictionary).get("runs_started", -1))


func _local_runs() -> int:
	if not FileAccess.file_exists(SaveManager._save_path):
		return -1
	return _runs_in(FileAccess.get_file_as_string(SaveManager._save_path))


func _remote_runs() -> int:
	return _runs_in(_fake.files.get(REMOTE, ""))


func _local_hash() -> String:
	if not FileAccess.file_exists(SaveManager._save_path):
		return ""
	return FileAccess.get_sha256(SaveManager._save_path)


## The hash the cloud's copy would have once downloaded, computed the same way the coordinator
## computes it: over the bytes, not over a parsed structure.
func _remote_hash() -> String:
	var scratch := SANDBOX + "/hash_probe.json"
	var file := FileAccess.open(scratch, FileAccess.WRITE)
	file.store_string(_fake.files.get(REMOTE, ""))
	file.close()
	var hash := FileAccess.get_sha256(scratch)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	return hash


## Whether a copy of the given kind was kept. The archive is the difference between "the game
## chose for you" and "the game chose for you and threw the other one away".
func _archive_contains(suffix: String) -> bool:
	var dir := ProjectSettings.globalize_path(CloudSaveCoordinator._archive_dir)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	for name: String in DirAccess.get_files_at(dir):
		if name.ends_with(suffix):
			return true
	return false


## Waits until the coordinator has nothing in flight. Bounded so that a coordinator which never
## settles fails this check rather than hanging the suite.
func _wait_for_idle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while CloudSaveCoordinator._uploading and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# One more frame so anything the loop kicked off on its way out has run.
	await get_tree().process_frame
	check(not CloudSaveCoordinator._uploading, "the coordinator settled rather than spinning")


func _wipe(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for name: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(name))
	for name: String in DirAccess.get_directories_at(absolute):
		_wipe(path.path_join(name))
	DirAccess.remove_absolute(absolute)

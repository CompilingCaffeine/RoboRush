class_name CloudBackend
extends RefCounted
## What the game is allowed to know about cloud storage.
##
## Everything behind this class is a browser: a host page, a JavaScript bridge, a signed-in
## account, a network. None of that exists in a headless test run, and the parts of cloud saving
## most worth testing — a download that fails, a save that arrives corrupt, two devices that
## diverged, an upload that succeeds on its third attempt — are precisely the ones that cannot be
## produced on demand against a real backend.
##
## So the coordinator never touches `WavedashSDK`. It talks to this, and the suite hands it a fake
## (see `tests/fakes/fake_cloud_backend.gd`) that can be told to fail on command. The real one is
## thin enough to read in one sitting, which is the other half of the bargain: whatever is not
## covered by tests has to be small enough to be obviously correct.
##
## Every call answers with the same shape, because a caller that has to remember which failure
## style each method uses will eventually forget:
##
##     { "success": bool, "message": String, "etag": String }
##
## `success` is the only field that decides anything. `message` is for logs. `etag` is whatever the
## platform said about the version of the file it just handled, or empty when it said nothing.
##
## Paths are `user://` paths, and are both the local file *and* the key it is stored under
## remotely — the platform's file API syncs a path to itself. That is why the save is uploaded
## from a staging copy rather than from `user://save.json` directly: a remote key that is also the
## canonical save file is a remote key that can overwrite it.


## Whether there is a cloud to talk to at all. False on desktop, false in a browser before the
## backend connects, false when nobody is signed in.
func is_available() -> bool:
	return false


## The signed-in player's id, or empty. This is the cloud-save namespace: two ids are two separate
## sets of files, and a change of id invalidates everything this game remembers about what it last
## synchronized.
func player_id() -> String:
	return ""


## Whether the remote copy of `path` exists, as `{success, present, message, etag}`.
##
## `success` false means the question could not be answered, which is emphatically not the same
## answer as "no" — treating an unreachable network as an empty cloud is how a first upload
## overwrites a save that was there all along. Callers must check `success` before `present`.
func exists(path: String) -> Dictionary:
	var result := _unsupported("exists")
	result["present"] = false
	return result


## Fetches the remote copy of `path` into the local file at `path`, replacing it.
func download(path: String) -> Dictionary:
	return _unsupported("download")


## Sends the local file at `path` to the remote copy of `path`.
func upload(path: String) -> Dictionary:
	return _unsupported("upload")


func _unsupported(method: String) -> Dictionary:
	return {
		"success": false,
		"message": "%s: no cloud backend on this platform" % method,
		"etag": "",
	}

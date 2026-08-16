class_name FakeCloudBackend
extends CloudBackend
## A cloud that does whatever the test needs it to.
##
## The behaviour worth testing in cloud saving is almost entirely failure: a download that times
## out, a file that arrives corrupt, an upload that succeeds on the third try, two devices that
## edited the same save. None of that can be arranged against a real backend, and a suite that
## waits for a real one is a suite that fails when the network does.
##
## So this holds the "cloud" in a string. Tests set what is up there, say how the next call should
## fail, and count what was asked of it.

## The remote store, keyed by path exactly as the platform keys it.
var files: Dictionary = {}

## What `is_available` answers. The suite runs on a desktop, where the real backend is always
## unavailable, so this is what makes the online paths reachable at all.
var available := true
var user_id := "player-one"

## How many of the next calls of each kind should fail before one succeeds. Set to 1 for a blip,
## to a large number for an outage.
var download_failures := 0
var upload_failures := 0
var exists_failures := 0

## What was asked of it, so a test can assert single-flight and coalescing rather than infer them.
var uploads := 0
var downloads := 0
var exist_checks := 0

## Every hash this backend was ever handed, newest last. The evidence for "the newest save
## eventually reached the cloud" and for "it was not uploaded five times".
var uploaded_hashes: PackedStringArray = []

## An ETag that changes with the content, as a real store's would.
var etag := "etag-0"


func is_available() -> bool:
	return available and not user_id.is_empty()


func player_id() -> String:
	return user_id


func exists(path: String) -> Dictionary:
	exist_checks += 1
	if exists_failures > 0:
		exists_failures -= 1
		return {"success": false, "present": false, "message": "fake: exists failed", "etag": ""}
	return {
		"success": true,
		"present": files.has(path),
		"message": "",
		"etag": etag,
	}


func download(path: String) -> Dictionary:
	downloads += 1
	if download_failures > 0:
		download_failures -= 1
		return {"success": false, "message": "fake: download failed", "etag": ""}
	if not files.has(path):
		return {"success": false, "message": "fake: no such remote file", "etag": ""}

	# The real backend downloads a remote object *into* the local file at the same path. Writing
	# the file is therefore part of what a download is, not an extra the test arranges.
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "message": "fake: could not write the downloaded file", "etag": ""}
	file.store_string(files[path])
	file.close()
	return {"success": true, "message": "", "etag": etag}


func upload(path: String) -> Dictionary:
	uploads += 1
	if upload_failures > 0:
		upload_failures -= 1
		return {"success": false, "message": "fake: upload failed", "etag": ""}
	if not FileAccess.file_exists(path):
		return {"success": false, "message": "fake: nothing local to upload", "etag": ""}

	files[path] = FileAccess.get_file_as_string(path)
	uploaded_hashes.append(FileAccess.get_sha256(path))
	etag = "etag-%d" % uploads
	return {"success": true, "message": "", "etag": etag}


## Puts a save in the "cloud" without going through an upload, which is how a test arranges what
## another device left behind.
func set_remote_content(path: String, content: String) -> void:
	files[path] = content

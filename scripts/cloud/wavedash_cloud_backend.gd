class_name WavedashCloudBackend
extends CloudBackend
## The real backend: `CloudBackend` spoken to Wavedash.
##
## Kept deliberately thin. It converts, it does not decide — no retries, no validation, no policy
## about what a failure means. All of that lives in the coordinator, where the suite can reach it.
## What is left here is the part no test can cover, so the less of it there is, the better.
##
## The SDK's file calls are awaitable and answer `{success, data, message}`. They also emit a
## signal carrying the same dictionary; this uses the return value rather than the signal, because
## a signal is shared by every caller and a return value belongs to the call that made it.

func is_available() -> bool:
	return WavedashConnection.is_available()


func player_id() -> String:
	return WavedashConnection.player_id()


func exists(path: String) -> Dictionary:
	if not is_available():
		return super.exists(path)
	var raw: Variant = await WavedashSDK.remote_file_exists(path)
	var result := _normalize(raw, "exists")
	# The answer itself, which `_normalize` deliberately does not carry: only this call has a
	# meaningful `data`, and only when the call succeeded at all.
	result["present"] = result["success"] and raw is Dictionary and (raw as Dictionary).get("data") == true
	return result


func download(path: String) -> Dictionary:
	if not is_available():
		return _unsupported("download")
	return _normalize(await WavedashSDK.download_remote_file(path), "download")


func upload(path: String) -> Dictionary:
	if not is_available():
		return _unsupported("upload")
	return _normalize(await WavedashSDK.upload_remote_file(path), "upload")


## Turns whatever came back into the one shape the coordinator understands.
##
## Defensive about the payload on purpose. The SDK documents `{success, data, message}` and is
## documented as exposing ETag metadata, but where the tag appears in a response is not something
## this repository can verify without a live host page — so the tag is looked for in the places it
## could reasonably be and treated as absent otherwise. An absent tag costs nothing here: the
## coordinator compares content hashes it computes itself, and uses the tag only as a hint it
## records alongside them.
func _normalize(result: Variant, method: String) -> Dictionary:
	if result is not Dictionary:
		return {
			"success": false,
			"message": "%s: unrecognised response from the platform" % method,
			"etag": "",
		}

	var payload := result as Dictionary
	var message: Variant = payload.get("message", "")
	return {
		"success": payload.get("success") == true,
		"message": str(message) if message != null else "",
		"etag": _read_etag(payload.get("data")),
	}


func _read_etag(data: Variant) -> String:
	if data is not Dictionary:
		return ""
	var metadata := data as Dictionary
	for key: String in ["etag", "eTag", "ETag"]:
		if metadata.has(key) and metadata[key] != null:
			return str(metadata[key])
	return ""

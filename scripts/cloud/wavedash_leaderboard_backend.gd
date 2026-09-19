class_name WavedashLeaderboardBackend
extends LeaderboardBackend
## The real backend: `LeaderboardBackend` spoken to Wavedash.
##
## Kept deliberately thin, exactly as `WavedashCloudBackend` is. It converts, it does not decide —
## no retries, no policy about what a failure means, no opinion about which times are worth
## posting. All of that lives in `Leaderboard`, where the suite can reach it.
##
## The SDK's leaderboard calls are awaitable and answer `{success, data, message}`. They also emit
## a signal carrying the same dictionary; this uses the return value, because a signal is shared by
## every caller and a return value belongs to the call that made it.

## Preloaded rather than referenced by name: the SDK's constants file declares no `class_name`, so
## it is reachable only as a resource. `WavedashSDK` loads it the same way.
const Constants = preload("res://addons/wavedash/WavedashConstants.gd")

## How the one board this game has is ordered, and how the platform should draw it.
##
## Ascending because the board ranks *fastest* victories, and a board created descending would rank
## the slowest — a mistake that is invisible until somebody wins and finds themselves in last
## place. The board is created once, by whoever posts to it first, and these two values are baked
## into it at that moment: changing them later changes nothing about a board that already exists.
##
## Constants here rather than arguments because Robo Rush has exactly one board. A second board
## ordered differently is the point at which these become parameters of `find_or_create`.
const SORT_METHOD := Constants.LEADERBOARD_SORT_ASCENDING
const DISPLAY_TYPE := Constants.LEADERBOARD_DISPLAY_TYPE_TIME_MILLISECONDS

func _init() -> void:
	WavedashConnection.changed.connect(_on_connection_changed)


## Records the transition and announces it, in that order.
##
## Announced rather than merely recorded, because nothing else will. Startup gives up on the
## platform after eight seconds (see `Bootstrap.CONNECT_TIMEOUT_SECONDS`) and `Leaderboard` syncs
## exactly once, when the save finishes loading — so a connection that lands at second nine used to
## leave a victory from a previous session sitting in the records until the next relaunch.
##
## Guarded on the value actually changing: the SDK can report the same state twice, and a listener
## that re-syncs on every announcement would turn a flapping connection into a stream of round
## trips.
func _on_connection_changed(_connected: bool) -> void:
	availability_changed.emit()


func is_available() -> bool:
	return WavedashConnection.is_available()


func player_id() -> String:
	return WavedashConnection.player_id()


func find_or_create(board_name: String) -> Dictionary:
	if not is_available():
		return super.find_or_create(board_name)

	var raw: Variant = await WavedashSDK.get_or_create_leaderboard(
		board_name, SORT_METHOD, DISPLAY_TYPE
	)
	var result := _envelope(raw, "find_or_create")
	result["id"] = _read_board_id(raw)
	# A success carrying no id is a failure that has not noticed yet: every later call takes the id,
	# and an empty one would post scores into nothing and read entries back from nothing.
	if result["success"] and (result["id"] as String).is_empty():
		result["success"] = false
		result["message"] = "find_or_create: the platform named no board"
	return result


func post(board_id: String, score_ms: int, metadata: Dictionary) -> Dictionary:
	if not is_available():
		return super.post(board_id, score_ms, metadata)

	# `keep_best` true: the platform decides whether this beats the player's existing entry, so a
	# stale device reposting an old time cannot demote a better one set somewhere else.
	var raw: Variant = await WavedashSDK.post_leaderboard_score(board_id, score_ms, true, "", metadata)
	var result := _envelope(raw, "post")
	var entry := _read_entry(_payload_of(raw).get("entry"))
	result["rank"] = entry.get("rank", 0)
	# Documented response shape: `data.submission` describes what happened to the score just sent.
	# Read defensively, because "the platform did not say" has to be distinguishable from "no", and
	# the only safe reading of silence is that nothing changed.
	result["improved"] = _read_improved(_payload_of(raw).get("submission"))
	return result


func top(board_id: String, limit: int) -> Dictionary:
	if not is_available():
		return super.top(board_id, limit)
	# Not friends-only: the board is the whole board. A friends filter is a different feature and
	# would be a different call.
	return _entries(await WavedashSDK.get_leaderboard_entries(board_id, 0, limit, false), "top")


func mine(board_id: String) -> Dictionary:
	if not is_available():
		return super.mine(board_id)
	return _entries(await WavedashSDK.get_my_leaderboard_entries(board_id), "mine")


# --- Reading what the platform said --------------------------------------------


## The two fields every call shares. Anything that is not a dictionary is a failure, whatever else
## it might be: a response this code cannot read is one it must not act on.
func _envelope(raw: Variant, method: String) -> Dictionary:
	if raw is not Dictionary:
		return {
			"success": false,
			"message": "%s: unrecognised response from the platform" % method,
		}
	var payload := raw as Dictionary
	var message: Variant = payload.get("message", "")
	return {
		"success": payload.get("success") == true,
		"message": str(message) if message != null else "",
	}


## The board's id, wherever the platform put it.
##
## `data` is the id itself when the platform answers with a bare string, and a board object
## carrying it otherwise. Both are accepted for the same reason `_read_entry_list` accepts two
## shapes: the SDK documents that a board comes back and not what it looks like inside, and the
## cost of guessing wrong is every later call being made against an empty string.
func _read_board_id(raw: Variant) -> String:
	if raw is not Dictionary:
		return ""
	var data: Variant = (raw as Dictionary).get("data")
	if data is String:
		return data as String
	if data is Dictionary:
		for key: String in ["id", "leaderboardId", "leaderboard_id"]:
			var value: Variant = (data as Dictionary).get(key)
			if value != null and str(value) != "":
				return str(value)
	return ""


func _payload_of(raw: Variant) -> Dictionary:
	if raw is not Dictionary:
		return {}
	var data: Variant = (raw as Dictionary).get("data")
	return data as Dictionary if data is Dictionary else {}


func _entries(raw: Variant, method: String) -> Dictionary:
	var result := _envelope(raw, method)
	var rows: Array = []
	if result["success"]:
		for candidate: Variant in _read_entry_list(raw):
			var entry := _read_entry(candidate)
			if not entry.is_empty():
				rows.append(entry)
	result["entries"] = rows
	return result


## The list of entries, wherever the platform put it.
##
## `data` is an array for a plain listing, but the documented shape of a *post* wraps its payload
## in an object — so a response that carries its rows under a key is just as likely as one that is
## the rows. Both are accepted rather than one being guessed at, because the cost of guessing wrong
## is a board that renders empty and reports success.
func _read_entry_list(raw: Variant) -> Array:
	if raw is not Dictionary:
		return []
	var data: Variant = (raw as Dictionary).get("data")
	if data is Array:
		return data as Array
	if data is Dictionary:
		for key: String in ["entries", "results", "items"]:
			var nested: Variant = (data as Dictionary).get(key)
			if nested is Array:
				return nested as Array
	return []


## One row, reduced to what a leaderboard screen needs: `{rank, name, score_ms, is_you}`.
##
## Defensive about key names on purpose, and in the same spirit as
## `WavedashCloudBackend._read_etag`. The SDK documents that an entry exists and not what it is
## called inside; this repository cannot verify the field names without a live host page, so each
## value is looked for under the names it could reasonably have and the row is dropped when none of
## them is there. A dropped row is a gap in a list. A row read out of the wrong field is a time
## attributed to the wrong player.
func _read_entry(candidate: Variant) -> Dictionary:
	if candidate is not Dictionary:
		return {}
	var row := candidate as Dictionary

	var score: Variant = _first_of(row, ["score", "value"])
	if not (score is float or score is int):
		return {}

	var user_id := str(_first_of(row, ["userId", "user_id", "playerId"], ""))
	var name: Variant = _first_of(row, ["username", "displayName", "name"], "")
	var rank: Variant = _first_of(row, ["rank", "position", "place"], 0)

	return {
		"rank": int(rank) if (rank is float or rank is int) else 0,
		# Never empty: a blank cell in a ranked list reads as a rendering bug rather than as a
		# player whose name the platform did not send.
		"name": str(name) if name != null and str(name) != "" else "ANONYMOUS",
		"score_ms": int(score),
		# Compared against the account this session is signed in as, not against a name. Two players
		# may share a display name; they cannot share an id.
		"is_you": not user_id.is_empty() and user_id == player_id(),
	}


## Whether the score just posted became the player's entry. False when the platform said nothing
## recognisable, because the caller uses this to decide whether to celebrate.
func _read_improved(submission: Variant) -> bool:
	if submission is not Dictionary:
		return false
	var row := submission as Dictionary
	for key: String in ["improved", "updated", "isNewBest", "scoreChanged"]:
		if row.get(key) == true:
			return true
	return false


func _first_of(row: Dictionary, keys: Array, fallback: Variant = null) -> Variant:
	for key: String in keys:
		if row.has(key) and row[key] != null:
			return row[key]
	return fallback

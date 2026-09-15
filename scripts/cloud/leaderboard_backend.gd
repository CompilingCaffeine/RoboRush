class_name LeaderboardBackend
extends RefCounted
## What the game is allowed to know about the leaderboard.
##
## The same bargain `CloudBackend` makes, for the same reason. Behind this there is a host page, a
## signed-in account, a network, and a board full of other people's times — none of which exists in
## a headless test run, and none of which can be told to fail on demand. The interesting cases are
## all failures: a board that cannot be reached, a post that succeeds on its second attempt, an
## account that is signed out, a platform that answers with a shape nobody expected.
##
## So `Leaderboard` never touches `WavedashSDK`. It talks to this, and the suite hands it a fake
## (see `tests/fakes/fake_leaderboard_backend.gd`). The real implementation converts and does not
## decide, which keeps the part no test can reach small enough to read in one sitting.
##
## Every call answers with the same envelope, because a caller that has to remember which failure
## style each method uses will eventually forget:
##
##     { "success": bool, "message": String, ... }
##
## `success` is the only field that decides anything; `message` is for logs. The rest is per call
## and documented on each.
##
## Scores are whole milliseconds. The platform stores an integer and is told to display it as a
## time, so the unit is fixed here rather than at each call site — a board that received seconds
## from one place and milliseconds from another would rank them against each other and be wrong in
## a way no error ever reports.


## Whether there is a board to talk to at all. False on desktop, false in a browser before the
## backend connects, false when nobody is signed in — a leaderboard entry belongs to an account,
## and an anonymous visitor has nowhere to put one.
func is_available() -> bool:
	return false


## The signed-in player's id, or empty. Used only to recognise the player's own row in a page of
## somebody else's times; this never posts on behalf of an id it was handed.
func player_id() -> String:
	return ""


## Resolves `board_name` to the platform's id for it, creating the board if this is the first time
## anyone has posted to it. Answers `{success, message, id}`.
##
## Separate from posting because the id is what every other call takes, and resolving it once per
## session is one round trip instead of one per operation.
func find_or_create(board_name: String) -> Dictionary:
	var result := _unsupported("find_or_create")
	result["id"] = ""
	return result


## Posts `score_ms` to the board, keeping the player's existing entry when it is already better.
##
## `metadata` rides along with the score it was submitted with — see
## `WavedashSDK.post_leaderboard_score`, which is explicit that a rejected score leaves the
## existing entry and its metadata untouched.
##
## Answers `{success, message, rank, improved}`, where `rank` is the entry's place afterwards, or
## zero when the platform did not say, and `improved` is whether this score replaced the old one.
func post(board_id: String, score_ms: int, metadata: Dictionary) -> Dictionary:
	var result := _unsupported("post")
	result["rank"] = 0
	result["improved"] = false
	return result


## Reads `limit` entries from the top of the board. Answers `{success, message, entries}`, where
## each entry is `{rank, name, score_ms, is_you}` — see `WavedashLeaderboardBackend._read_entry`
## for how a platform response becomes that.
func top(board_id: String, limit: int) -> Dictionary:
	var result := _unsupported("top")
	result["entries"] = []
	return result


## The player's own entry, as a one-element `entries` array, or an empty one when they have never
## posted. Answers the same shape `top` does.
##
## This is what makes a first launch on a new device correct: the board, not this device, is the
## authority on whether a time was ever posted, and a record that never left the machine it was set
## on is the one thing a leaderboard exists to prevent.
func mine(board_id: String) -> Dictionary:
	var result := _unsupported("mine")
	result["entries"] = []
	return result


func _unsupported(method: String) -> Dictionary:
	return {
		"success": false,
		"message": "%s: no leaderboard backend on this platform" % method,
	}

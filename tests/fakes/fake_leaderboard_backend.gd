class_name FakeLeaderboardBackend
extends LeaderboardBackend
## A leaderboard that does whatever the test needs it to.
##
## The same bargain `FakeCloudBackend` makes. What is worth testing about a leaderboard is almost
## entirely failure — a board that will not resolve, a post that succeeds on its third attempt, a
## session that is signed out, a platform that answers with a shape nobody expected — and none of
## that can be arranged against a live service.
##
## So the board is a dictionary of scores. Tests say what is on it, how the next call should fail,
## and count what was asked of it. It also keeps `keep_best` honestly: a worse time posted over a
## better one is discarded here exactly as the platform discards it, because "a stale device cannot
## demote a record set somewhere else" is a rule this suite has to be able to check.

const BOARD_ID := "board-fastest-victory"

var available := true
var user_id := "player-one"

## The board's contents: user id to milliseconds, and user id to display name.
var scores: Dictionary[String, int] = {}
var names: Dictionary[String, String] = {}

## How many of the next calls of each kind should fail before one succeeds. Set to 1 for a blip, to
## a large number for an outage.
var find_failures := 0
var post_failures := 0
var top_failures := 0
var mine_failures := 0

## What was asked of it, so a test can assert single-flight and coalescing rather than infer them.
var finds := 0
var posts := 0
var top_reads := 0
var mine_reads := 0

## Every score this backend was ever handed, oldest first, whether or not it was kept. The evidence
## for "the fastest time eventually reached the board" and for "it was not posted five times".
var posted_scores: Array[int] = []

## The metadata that arrived with the last accepted score.
var last_metadata: Dictionary = {}

## The board name the game asked for, so a test can check what it is filed under without knowing
## how the name is built.
var requested_name := ""

## Frames each call waits before answering. Zero — the default — answers in the same frame it was
## asked, which is what most checks want. A non-zero value is how a test arranges the one thing an
## instant backend cannot produce: a second victory finished while the first is still in flight,
## which is the whole of what single-flight and coalescing are about.
var latency_frames := 0


func _latency() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for _frame: int in latency_frames:
		await tree.process_frame


func is_available() -> bool:
	return available and not user_id.is_empty()


func player_id() -> String:
	return user_id


func find_or_create(board_name: String) -> Dictionary:
	await _latency()
	finds += 1
	requested_name = board_name
	if find_failures > 0:
		find_failures -= 1
		return {"success": false, "message": "fake: the board could not be resolved", "id": ""}
	return {"success": true, "message": "", "id": BOARD_ID}


func post(board_id: String, score_ms: int, metadata: Dictionary) -> Dictionary:
	await _latency()
	posts += 1
	posted_scores.append(score_ms)
	if post_failures > 0:
		post_failures -= 1
		return {"success": false, "message": "fake: post failed", "rank": 0, "improved": false}
	if board_id != BOARD_ID:
		return {"success": false, "message": "fake: no such board", "rank": 0, "improved": false}

	# `keep_best` on an ascending board: only a faster time replaces the entry, and a rejected one
	# leaves the existing entry and its metadata untouched.
	var held: int = scores.get(user_id, 0)
	var improved := held == 0 or score_ms < held
	if improved:
		scores[user_id] = score_ms
		last_metadata = metadata.duplicate()

	return {
		"success": true,
		"message": "",
		"rank": _rank_of(user_id),
		"improved": improved,
	}


func top(board_id: String, limit: int) -> Dictionary:
	await _latency()
	top_reads += 1
	if top_failures > 0:
		top_failures -= 1
		return {"success": false, "message": "fake: the board could not be read", "entries": []}
	if board_id != BOARD_ID:
		return {"success": false, "message": "fake: no such board", "entries": []}
	return {"success": true, "message": "", "entries": _ranked().slice(0, limit)}


func mine(board_id: String) -> Dictionary:
	await _latency()
	mine_reads += 1
	if mine_failures > 0:
		mine_failures -= 1
		return {"success": false, "message": "fake: this player's entry could not be read", "entries": []}
	if board_id != BOARD_ID or not scores.has(user_id):
		return {"success": true, "message": "", "entries": []}
	for entry: Dictionary in _ranked():
		if entry["is_you"]:
			return {"success": true, "message": "", "entries": [entry]}
	return {"success": true, "message": "", "entries": []}


## Puts a time on the board without going through a post, which is how a test arranges what
## somebody else — or this player on another device — already did.
func set_entry(id: String, display_name: String, score_ms: int) -> void:
	scores[id] = score_ms
	names[id] = display_name


## The board in order, fastest first, ranked from one.
func _ranked() -> Array:
	var ids: Array = scores.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return scores[a] < scores[b])
	var rows: Array = []
	for index: int in ids.size():
		var id: String = ids[index]
		rows.append({
			"rank": index + 1,
			"name": names.get(id, id),
			"score_ms": scores[id],
			"is_you": id == user_id,
		})
	return rows


## Computed rather than looked up in `_ranked`, so two players sharing a display name cannot be
## mistaken for each other.
func _rank_of(id: String) -> int:
	if not scores.has(id):
		return 0
	var rank := 1
	for other: String in scores:
		if scores[other] < scores[id]:
			rank += 1
	return rank

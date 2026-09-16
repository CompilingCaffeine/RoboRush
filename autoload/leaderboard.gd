extends Node
## The global board of fastest victories, and everything that decides what reaches it.
##
## One board, one number: how long a *won* run took, in milliseconds, ascending. Losses are not on
## it. A roguelite run that ends on floor two is not a slow victory, and a board that ranked those
## together would put every genuine finish below every failure — so the rule is enforced here,
## once, rather than at each place a run can end.
##
## The rule this is built around, and it is `CloudSaveCoordinator`'s rule restated: **the local
## record is authoritative and the board is a mirror of it.** `BestRunStats.fastest_victory` is
## what the player's own screens read, it is saved with the rest of their progress, and nothing
## here can change it. A network that is down, an account that is signed out, a platform that
## answers with nonsense — none of them may lose a personal best, delay a run ending, or put
## anything on a screen the player has to dismiss. The worst a broken board is allowed to do is
## leave the game exactly as good as a game with no board.
##
## That is also what makes the queue free. A victory that could not be posted is not written to a
## pending-submissions file and retried from it: it is already saved, in the records, as the
## player's fastest victory, and `sync()` re-offers it until the board accepts it — at the start of
## every session, and again the moment a board that was not there arrives. The record *is* the
## queue, so there is no second copy of it to fall out of step with the first.
##
## The platform is behind `LeaderboardBackend` — never `WavedashSDK` directly — because every case
## worth testing here is a failure, and failures cannot be ordered from a live service. See
## `tests/fakes/fake_leaderboard_backend.gd`.

## The campaign the board is for, loaded only for its id and content version. Cheap: a
## `RunDefinition` names its floors by path and loads none of them.
const CAMPAIGN := preload("res://data/runs/main_campaign.tres")

## How long `fetch_standing` waits for an in-flight post before answering with whatever the board
## already says.
const SETTLE_TIMEOUT_SECONDS := 6.0

## How many rows the panel asks for. Ten is what fits above the player's own row at this game's
## resolution, and a leaderboard nobody can read at a glance is a wall of names.
const TOP_ENTRIES := 10

enum Status {
	## No board in play: desktop, signed out, or the platform never connected. Not an error.
	OFFLINE,
	## Working out which board this is.
	LOADING,
	## The board is known and nothing is in flight.
	READY,
	## A time is being posted.
	POSTING,
	## There is a victory on record that the board has not accepted yet. The next launch re-offers
	## it; nothing is lost in the meantime.
	PENDING,
	## The platform is there and refused. Distinct from OFFLINE because it is worth saying out
	## loud: OFFLINE is a game played without a board, this is a board that should have answered.
	UNREACHABLE,
}

signal status_changed(status: Status)

## A time reached the board. `rank` is where it landed, or zero when the platform did not say, and
## `improved` is whether it replaced the player's previous entry.
signal score_posted(rank: int, improved: bool)

## Swapped for a fake by the suite. Everything platform-shaped lives behind it.
##
## Assigned through a setter so that the availability listener follows the backend rather than
## staying bolted to whichever instance `_ready` happened to build. The suite replaces this *after*
## `_ready` has run, and a listener left on the object that was replaced is a listener that never
## fires again — which would make the one behaviour below untestable in exactly the suite written
## to test it.
var backend: LeaderboardBackend = null:
	set(value):
		if backend == value:
			return
		if backend != null and backend.availability_changed.is_connected(_on_availability_changed):
			backend.availability_changed.disconnect(_on_availability_changed)
		backend = value
		if backend != null:
			backend.availability_changed.connect(_on_availability_changed)

## How long to wait before retrying a failed post, and how many attempts there are. Bounded for the
## same reason the save coordinator's is: past the end of this list the time is simply pending, and
## the next victory or the next launch carries it. A queue that retries forever is a queue that
## spends a player's battery describing a network that is not coming back.
##
## A variable rather than a constant only so the suite can shrink it. Nothing in the game assigns
## it, and a test that waited out the real delays would spend twenty-two seconds proving that a
## retry happens.
var post_backoff_seconds: Array[float] = [2.0, 5.0, 15.0]

## What `is_offered` answers, decided once at startup. A variable rather than the platform check
## written inline, because the two screens it gates — the menu entry and the summary's rank line —
## exist only in a browser, and a headless suite that cannot turn it on is a suite that can never
## look at either of them. Nothing in the game assigns it.
var offered := OS.has_feature("web")

var _status: Status = Status.OFFLINE

## The platform's id for the board, once resolved. Empty means "not yet", which is the state every
## call below checks before doing anything.
var _board_id := ""

## The fastest victory this device knows about, and the fastest the board is known to hold for this
## player. Both in milliseconds; zero means "none". When the first is better than the second there
## is work to do, and when it is not there is none — which is where coalescing comes from, rather
## than from a queue: three victories during one post leave one number to catch up to, not three
## posts to perform.
var _best_ms := 0
var _posted_ms := 0

## One post at a time. A victory arriving during a post updates `_best_ms` and returns; the loop
## already running re-reads it and goes round again.
var _posting := false

## Set while `sync` is in flight, so a victory finished during startup cannot race it.
var _syncing := false

## Whether a sync has ever got as far as a resolved board this session.
##
## Not the same question as `_board_resolved`, and the difference is the point: resolving is what
## `_post_pending` does on its own, while syncing is the only thing that re-offers a record set in
## an *earlier* session. A session that booted signed out has done the first and not the second.
var _synced := false

## How many consecutive attempts have failed, reset by a success and by a new personal best — a
## record set after the retries ran out deserves its own budget rather than inheriting an
## exhausted one.
var _attempt := 0

## What the winning run was, for the entry's metadata. Empty at startup, when the time being
## re-offered is a record from a previous session and the run behind it is no longer anywhere: the
## records keep the number, not the seed that produced it.
var _run_metadata: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if backend == null:
		backend = WavedashLeaderboardBackend.new()
	# Deferred for the reason `CloudSaveCoordinator` defers the same binding: autoloads are added
	# one at a time, and `SaveManager` may not be in the tree yet. Binding on a deferred call makes
	# this independent of the order in `project.godot` rather than quietly dependent on it.
	_bind_save_manager.call_deferred()


func _bind_save_manager() -> void:
	if not SaveManager.initialized.is_connected(_on_save_initialized):
		SaveManager.initialized.connect(_on_save_initialized)
	# The signal has already gone if the bootstrap got there first — an autoload binding a moment
	# late must not be the difference between a record reaching the board and never leaving the
	# machine it was set on.
	if SaveManager.is_initialized():
		_on_save_initialized()


## The board's name, which is also its identity: `get_or_create` resolves a name to a board and
## creates one the first time nobody has.
##
## The campaign's content version is part of it, deliberately. A content bump means a seed no
## longer builds the run it used to — the version exists to say exactly that — and a route that is
## thirty seconds shorter after a floor is rebalanced is not a better run than the one before it.
## Ranking those against each other would quietly make the board a record of which build somebody
## played. So each content version gets its own board, which is what a speedrun category is, and
## the old one keeps its times rather than being overwritten by a game that has moved on.
static func board_name() -> String:
	return "%s_fastest_victory_v%d" % [CAMPAIGN.id, CAMPAIGN.content_version]


## Whether the game should offer a leaderboard at all, in the same spirit as `SceneRouter.can_quit`
## and for the same reason: an entry that can only ever say "not here" is a door the menu should
## not draw.
##
## Web only. Off the web there is no host page, no account, and no board — and a desktop player
## choosing LEADERBOARD would be told about a feature of a different build of the game. In a
## browser it is offered whether or not anyone is signed in, because *there* the answer is
## something the player can act on.
func is_offered() -> bool:
	return offered


# --- Submitting ---------------------------------------------------------------


## Offers a finished run to the board. Called by `RunManager.end_run`, for every ending.
##
## Takes the run rather than a number so that the two decisions it makes — whether this counts, and
## what the entry should say about itself — are made where the board's rules live. `RunManager`
## announces that a run ended; what a leaderboard does about it is not its business.
##
## Returns immediately. Posting happens in the background, because the caller is the last line of a
## run ending and the player is waiting on a summary screen.
func submit_run(stats: RunStats, won: bool) -> void:
	if not won or stats == null:
		return

	var run_ms := _milliseconds(stats.duration)
	# A victory the clock says took no time is a broken clock, not a world record. Filing it would
	# put an unbeatable row at the top of an ascending board that nothing could ever displace.
	if run_ms <= 0:
		return
	if _best_ms > 0 and run_ms >= _best_ms:
		return

	_best_ms = run_ms
	_attempt = 0
	_run_metadata = {
		# What the run can be reproduced from, and the whole reason a fast time is checkable rather
		# than merely impressive. See `RunStats`: a seed alone does not identify a run.
		"seed": stats.run_seed,
		"content": stats.content_version,
		"build": Bootstrap.build_id(),
		# The shape of the run behind the number, for anyone reading the board and wondering how.
		"rooms": stats.rooms_cleared,
		"items": stats.items_collected.size(),
	}
	_post_pending()


## Re-offers whatever the records hold, and learns what the board already has for this player.
##
## Called once per session, when `SaveManager` finishes loading. This is what makes a fresh install
## on a second machine correct: the board, not this device, is the authority on whether a time was
## ever posted — and a personal best that never left the machine it was set on is the one thing a
## leaderboard exists to prevent.
func sync() -> void:
	if _syncing:
		return
	_syncing = true
	await _sync_inner()
	_syncing = false


func _sync_inner() -> void:
	if not _online():
		_set_status(Status.OFFLINE)
		return

	_set_status(Status.LOADING)
	if not await _resolve_board():
		return

	# The records are the queue. Whatever the player's fastest victory is, it is a candidate every
	# session until the board confirms it holds it.
	var local := _milliseconds(SaveManager.best.fastest_victory)
	if local > 0 and (_best_ms == 0 or local < _best_ms):
		_best_ms = local

	var mine: Dictionary = await backend.mine(_board_id)
	if mine.get("success", false):
		var rows: Array = mine.get("entries", [])
		if not rows.is_empty():
			# Only ever downwards, for the reason the post loop takes the same minimum: a sync can
			# now run at any point in a session, so this read can be a stale one taken before a post
			# that has since landed. Believing it would put `_posted_ms` back up at the board's old
			# entry and send the same time again.
			var held := int((rows[0] as Dictionary).get("score_ms", 0))
			_posted_ms = held if _posted_ms == 0 else mini(_posted_ms, held)
	else:
		# The question could not be answered, which is not the same as "the board has nothing".
		# Leaving `_posted_ms` alone and posting anyway is the safe half of that: `keep_best` means
		# the platform discards a time it already beats, so the cost of being wrong here is one
		# redundant call, and the cost of assuming the board is empty would be nothing at all —
		# which is worse, because it is silent.
		_log("could not read this player's entry (%s)" % mine.get("message", ""))

	_synced = true
	_set_status(Status.READY)
	await _post_pending()


## Posts until the board holds the record, or until the retries run out.
##
## Single-flight and self-coalescing: the loop re-reads `_best_ms` every pass, so a victory that
## lands mid-post is the one that ends up on the board regardless of how many arrived while it was
## busy.
func _post_pending() -> void:
	if _posting:
		return
	if not _online() or not _has_unposted():
		_settle_status()
		return

	# Claimed before the board is resolved, not after. Resolving is itself a round trip, and a
	# second victory arriving during it would otherwise pass the guard above and start a second
	# loop — which is the one thing single-flight exists to prevent.
	_posting = true
	# Resolved here as well as in `sync`, because a session can come online after startup gave up
	# waiting for it. Without this, a player whose connection arrived late would win the campaign
	# against a reachable board and post nothing until the next launch.
	if _board_resolved() or await _resolve_board():
		while _online() and _has_unposted():
			_set_status(Status.POSTING)
			var target := _best_ms
			var result: Dictionary = await backend.post(_board_id, target, _run_metadata)

			if result.get("success", false):
				# Only ever downwards. A board that answered with a worse time than the one just
				# accepted — a stale read, another device's older entry — must not make this
				# device believe its record is already up there.
				_posted_ms = target if _posted_ms == 0 else mini(_posted_ms, target)
				_attempt = 0
				score_posted.emit(int(result.get("rank", 0)), result.get("improved", false) == true)
				continue

			_attempt += 1
			if _attempt > post_backoff_seconds.size():
				_log("giving up on this post (%s); the record is saved and the next launch re-offers it"
					% result.get("message", ""))
				break

			_set_status(Status.PENDING)
			await get_tree().create_timer(post_backoff_seconds[_attempt - 1]).timeout

	_posting = false
	_settle_status()


# --- Reading ------------------------------------------------------------------


## The top of the board, as `{success, message, entries, you}`.
##
## `entries` are `{rank, name, score_ms, is_you}`, best first. `you` is the player's own entry when
## it is not already among them, or an empty dictionary — so a screen can show where the player
## stands without paging through the board to find them.
func fetch_top(limit := TOP_ENTRIES) -> Dictionary:
	if not _online():
		return {"success": false, "message": "offline", "entries": [], "you": {}}
	# Signing in has no signal behind it — `is_available` simply starts answering yes — so the
	# screen the player opens to ask where they stand is also where the game notices they can now be
	# on the board at all. Once per session, and only when the platform is there to answer: without
	# it, a player who signed in after the page loaded has a record that waits for a relaunch.
	if not _synced:
		await sync()
	if not _board_resolved() and not await _resolve_board():
		return {"success": false, "message": "the board could not be reached", "entries": [], "you": {}}

	var page: Dictionary = await backend.top(_board_id, limit)
	var entries: Array = page.get("entries", []) if page.get("success", false) else []
	var result := {
		"success": page.get("success", false),
		"message": page.get("message", ""),
		"entries": entries,
		"you": {},
	}
	if not result["success"]:
		_set_status(Status.UNREACHABLE)
		return result

	_settle_status()
	for entry: Variant in entries:
		if (entry as Dictionary).get("is_you", false):
			return result

	# Not in the page, so fetched separately. A player outside the top ten is the common case, and
	# a board that cannot tell them their own rank is a board they look at once.
	var mine: Dictionary = await backend.mine(_board_id)
	if mine.get("success", false):
		var rows: Array = mine.get("entries", [])
		if not rows.is_empty():
			result["you"] = rows[0]
	return result


## Where the player stands on the board, as `{success, message, rank, score_ms}`.
##
## Waits for anything still in flight before reading. A rank read while this run's victory is still
## being posted is the rank from *before* it, which is the one number the player stayed on the
## screen to watch change.
##
## A `success` of false carries a `message` already written for the player, because every way this
## can fail is a way that costs them nothing: the record is saved either way, and the board has it
## by the next launch at the latest.
func fetch_standing() -> Dictionary:
	if not _online():
		return _no_standing(status_text())

	await _settle()
	if not _board_resolved() and not await _resolve_board():
		return _no_standing(status_text())

	var mine: Dictionary = await backend.mine(_board_id)
	if not mine.get("success", false):
		_set_status(Status.UNREACHABLE)
		return _no_standing(status_text())

	var rows: Array = mine.get("entries", [])
	if rows.is_empty():
		# Online, on a board, and not on it. A post that could not be made is the usual reason and
		# `status_text` already says so; when it has nothing to say, this is the plain fact.
		var pending := status_text()
		return _no_standing(pending if not pending.is_empty() else "NOT ON THE BOARD YET")

	var entry := rows[0] as Dictionary
	return {
		"success": true,
		"message": "",
		"rank": int(entry.get("rank", 0)),
		"score_ms": int(entry.get("score_ms", 0)),
	}


func _no_standing(message: String) -> Dictionary:
	return {"success": false, "message": message, "rank": 0, "score_ms": 0}


## Waits until nothing is in flight, or until waiting stops being reasonable.
##
## Bounded because the retry backoff can hold a post open for twenty-two seconds while a player
## sits in front of a summary screen. Past this they are shown where they stood, which is true,
## rather than a line that never resolves.
func _settle() -> void:
	var deadline := Time.get_ticks_msec() + int(SETTLE_TIMEOUT_SECONDS * 1000.0)
	while (_posting or _syncing) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Formats a board score the way `RunStats` formats a duration, so a time on the leaderboard and
## the same time on the summary screen are recognisably the same number.
static func format_score(score_ms: int) -> String:
	return RunStats.format_duration(float(score_ms) / 1000.0)


# --- Plumbing -----------------------------------------------------------------


## The platform came back, or went away. Only the first is worth acting on.
##
## A board that has gone needs nothing from here: the record is saved, `_settle_status` already
## says so, and a sync against a backend that is not there is a round trip that cannot succeed.
## A board that has *arrived* is the case this exists for — startup gives up after eight seconds
## (`Bootstrap.CONNECT_TIMEOUT_SECONDS`) and syncs once, so without this a connection that lands a
## moment later leaves a victory from an earlier session in the records until the next relaunch.
##
## Not awaited, for the same reason `_on_save_initialized` does not await: this is a signal handler
## and `sync` is already single-flight.
func _on_availability_changed() -> void:
	if not _online():
		_settle_status()
		return
	sync()


func _on_save_initialized() -> void:
	# Not awaited. This runs during the bootstrap, one line before the menu is built, and a board
	# is not worth a frame of the player's time — let alone a network round trip of it.
	sync()


## Resolves the board's name to the platform's id for it, once per session. Returns whether there
## is a board to talk to afterwards.
func _resolve_board() -> bool:
	if _board_resolved():
		return true
	var result: Dictionary = await backend.find_or_create(board_name())
	if not result.get("success", false):
		_log("could not resolve the board (%s)" % result.get("message", ""))
		_set_status(Status.UNREACHABLE)
		return false
	_board_id = str(result.get("id", ""))
	return _board_resolved()


func _board_resolved() -> bool:
	return not _board_id.is_empty()


func _online() -> bool:
	return backend != null and backend.is_available()


func _has_unposted() -> bool:
	return _best_ms > 0 and (_posted_ms == 0 or _best_ms < _posted_ms)


## Where the status lands when nothing is in flight. Kept in one place because every path out of a
## post ends here, and five call sites each deciding what "done" looks like is five chances to
## leave the panel claiming it is still working.
func _settle_status() -> void:
	if not _online():
		_set_status(Status.OFFLINE)
	elif not _board_resolved():
		_set_status(Status.UNREACHABLE)
	elif _has_unposted():
		_set_status(Status.PENDING)
	else:
		_set_status(Status.READY)


## Seconds to whole milliseconds. Refuses anything that is not a real, positive duration: a run
## length is read from a save file in some paths, and JSON can hold an infinity.
static func _milliseconds(seconds: float) -> int:
	if not is_finite(seconds) or seconds <= 0.0:
		return 0
	return int(roundf(seconds * 1000.0))


func status() -> Status:
	return _status


## What to put in front of the player, and never more than they need. A signed-out browser is not
## told the platform failed, because it did not.
func status_text() -> String:
	match _status:
		Status.LOADING:
			return "LOADING BOARD..."
		Status.POSTING:
			return "POSTING YOUR TIME..."
		Status.READY:
			return ""
		Status.PENDING:
			return "YOUR TIME IS SAVED - NOT YET POSTED"
		Status.UNREACHABLE:
			return "THE BOARD COULD NOT BE REACHED"
		_:
			return "SIGN IN ON WAVEDASH TO COMPETE"


func _set_status(new_status: Status) -> void:
	if _status == new_status:
		return
	_status = new_status
	status_changed.emit(_status)


func _log(message: String) -> void:
	if OS.is_debug_build():
		print("Leaderboard: ", message)

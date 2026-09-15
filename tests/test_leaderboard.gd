extends TestCase
## The global board of fastest victories.
##
## Every check here is a way the board could be wrong, written down, and they fall into two groups.
##
## The first is what must never reach it: a loss, a run that took no time, a slower time posted
## over a faster one. An ascending board is unusual in that its failures are permanent — a bogus
## zero at the top cannot be beaten by anybody, ever, and no later correct behaviour displaces it.
##
## The second is what must never be lost. A personal best is saved in the player's records whether
## or not the network was working, and the promise this suite holds `Leaderboard` to is that the
## record itself is the queue: a victory that could not be posted is re-offered on the next launch
## rather than written to a pending file that can fall out of step with the records it duplicates.
##
## The board is `FakeLeaderboardBackend`, because every interesting case above is a failure and
## failures cannot be ordered from a live service. Nothing here touches Wavedash or the network.

const BOARD := FakeLeaderboardBackend.BOARD_ID

## Short enough that a suite exercising the retry path does not spend twenty-two seconds on it, long
## enough to still be a wait rather than a busy loop.
const TEST_BACKOFF: Array[float] = [0.05, 0.05, 0.05]

var _fake: FakeLeaderboardBackend

## Borrowed from the live autoload and put back in `_teardown`; the suites that follow share it.
var _real_backend: LeaderboardBackend
var _real_backoff: Array[float]
var _real_best: BestRunStats
var _real_offered: bool
var _borrowed := false


func run() -> void:
	await _test_the_real_backend_loads_and_is_inert_off_the_web()
	await _test_an_unavailable_board_is_never_called()
	await _test_a_loss_is_never_posted()
	await _test_a_run_that_took_no_time_is_never_posted()
	await _test_a_victory_reaches_the_board()
	await _test_the_entry_says_which_run_set_it()
	await _test_a_slower_victory_is_not_posted()
	await _test_a_faster_victory_replaces_it()
	await _test_a_board_that_will_not_resolve_posts_nothing()
	await _test_a_failed_post_retries_and_lands()
	await _test_retries_are_bounded_and_the_record_survives()
	await _test_the_record_is_the_queue()
	await _test_a_stale_device_cannot_demote_a_better_time()
	await _test_posts_are_single_flight_and_the_fastest_lands()
	await _test_the_board_is_named_for_the_campaign_content()
	await _test_an_unreadable_board_is_not_an_empty_one()
	await _test_a_player_outside_the_page_is_still_shown_their_rank()
	await _test_a_late_connection_can_still_post()

	await _test_the_panel_draws_the_board()
	await _test_the_panel_marks_the_player_own_row()
	await _test_the_panel_does_not_draw_a_failure_as_an_empty_board()
	await _test_the_panel_tells_a_signed_out_player_what_to_do()

	await _test_the_standing_waits_for_the_post_in_flight()
	await _test_the_standing_reports_a_pending_post_rather_than_a_rank()
	await _test_the_summary_shows_the_rank_after_a_victory()
	await _test_the_summary_shows_no_rank_after_a_loss()
	await _test_the_summary_shows_no_rank_where_there_is_no_board()

	_teardown()


# --- The real backend ---------------------------------------------------------


## The only check in this suite that touches the real backend, and it exists because of what the
## rest of the suite cannot see.
##
## Driving a fake is what makes outages and corrupt replies reachable at all — but it also means a
## real backend that does not compile passes every check in this file and fails the moment somebody
## launches the game. That happened once, to a helper that was called and never written: the suite
## was green, the desktop build could not construct its own backend, and the browser build would
## have shipped without a board.
##
## So this constructs the real one and asks it what a desktop launch asks. It must load, report
## itself unavailable, and answer in the shape the coordinator expects rather than reaching for a
## host page that is not there.
func _test_the_real_backend_loads_and_is_inert_off_the_web() -> void:
	var real := WavedashLeaderboardBackend.new()
	check(not real.is_available(), "the real backend reports itself unavailable off the web")

	var board: Dictionary = await real.find_or_create(Leaderboard.board_name())
	check(
		not board.get("success", true) and str(board.get("id", "")).is_empty(),
		"resolves no board",
	)

	var posted: Dictionary = await real.post("board", 60000, {})
	check(not posted.get("success", true), "posts nothing")

	var page: Dictionary = await real.top("board", 10)
	check(
		not page.get("success", true) and (page.get("entries", []) as Array).is_empty(),
		"and reads no entries",
	)


# --- What must never reach the board ------------------------------------------


## The desktop build, a signed-out browser, a dead network. Not merely "does not crash": the
## platform must not be called at all, because every call costs a round trip on a screen the player
## is waiting on, and a leaderboard is the least important thing in the game.
func _test_an_unavailable_board_is_never_called() -> void:
	_setup()
	_fake.available = false

	await Leaderboard.sync()
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(
		Leaderboard.status() == Leaderboard.Status.OFFLINE,
		"an unavailable board leaves the game offline",
	)
	check(
		_fake.finds == 0 and _fake.posts == 0 and _fake.mine_reads == 0,
		"and nothing is asked of the platform at all",
	)


## The rule the whole board rests on. A roguelite run that ended on floor two took four minutes, and
## on an ascending board four minutes beats every genuine finish there will ever be.
func _test_a_loss_is_never_posted() -> void:
	_setup()
	await Leaderboard.sync()

	Leaderboard.submit_run(_victory(240.0), false)
	await _wait_for_idle()

	check(_fake.posts == 0, "a run that was lost is not a fast victory (%d posts)" % _fake.posts)


## A clock that reports zero is broken, and a zero at the top of an ascending board is a row nothing
## can ever displace. Refused rather than clamped: there is no honest number to clamp it to.
func _test_a_run_that_took_no_time_is_never_posted() -> void:
	_setup()
	await Leaderboard.sync()

	Leaderboard.submit_run(_victory(0.0), true)
	Leaderboard.submit_run(_victory(-5.0), true)
	Leaderboard.submit_run(_victory(INF), true)
	await _wait_for_idle()

	check(_fake.posts == 0, "a victory with no duration is refused (%d posts)" % _fake.posts)


# --- What must reach it -------------------------------------------------------


func _test_a_victory_reaches_the_board() -> void:
	_setup()
	await Leaderboard.sync()

	Leaderboard.submit_run(_victory(1122.5), true)
	await _wait_for_idle()

	check(_fake.posts == 1, "a victory is posted once (%d)" % _fake.posts)
	check(
		_fake.scores.get(_fake.user_id, 0) == 1122500,
		"as whole milliseconds (%d)" % _fake.scores.get(_fake.user_id, 0),
	)
	check(Leaderboard.status() == Leaderboard.Status.READY, "and the board settles as ready")


## A fast time is only interesting if it can be checked. `RunStats` is explicit that a seed alone
## does not identify a run — the content version it was drawn against does too — so an entry that
## cannot name both is a record nobody can reproduce or dispute.
func _test_the_entry_says_which_run_set_it() -> void:
	_setup()
	await Leaderboard.sync()

	var stats := _victory(900.0)
	stats.run_seed = 4242
	stats.content_version = 7
	Leaderboard.submit_run(stats, true)
	await _wait_for_idle()

	check(int(_fake.last_metadata.get("seed", 0)) == 4242, "the entry carries the run's seed")
	check(
		int(_fake.last_metadata.get("content", 0)) == 7,
		"and the content version it was drawn against",
	)


func _test_a_slower_victory_is_not_posted() -> void:
	_setup()
	await Leaderboard.sync()
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()
	var posts_after_best := _fake.posts

	Leaderboard.submit_run(_victory(900.0), true)
	await _wait_for_idle()

	check(
		_fake.posts == posts_after_best,
		"a slower victory is not sent at all (%d extra posts)" % (_fake.posts - posts_after_best),
	)
	check(_fake.scores[_fake.user_id] == 600000, "and the board still holds the faster one")


func _test_a_faster_victory_replaces_it() -> void:
	_setup()
	await Leaderboard.sync()
	Leaderboard.submit_run(_victory(900.0), true)
	await _wait_for_idle()

	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(_fake.scores[_fake.user_id] == 600000, "a faster victory takes the entry")


# --- Failure ------------------------------------------------------------------


## A board that cannot be resolved has no id, and every later call takes one. The failure has to
## stop here rather than further in, where a post would be sent to an empty string.
func _test_a_board_that_will_not_resolve_posts_nothing() -> void:
	_setup()
	_fake.find_failures = 99

	await Leaderboard.sync()
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(_fake.posts == 0, "nothing is posted to a board that was never resolved")
	check(
		Leaderboard.status() == Leaderboard.Status.UNREACHABLE,
		"and the platform being there and refusing is said out loud",
	)


func _test_a_failed_post_retries_and_lands() -> void:
	_setup()
	await Leaderboard.sync()

	_fake.post_failures = 1
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(_fake.scores.get(_fake.user_id, 0) == 600000, "a post that failed once still lands")
	check(
		Leaderboard.status() == Leaderboard.Status.READY,
		"and only then is the board called ready",
	)


## The retries are bounded on purpose. What matters is what is true afterwards: the player's record
## is untouched, the game says so rather than claiming success, and the time is still a candidate.
func _test_retries_are_bounded_and_the_record_survives() -> void:
	_setup()
	await Leaderboard.sync()

	_fake.post_failures = 99
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(
		_fake.posts == TEST_BACKOFF.size() + 1,
		"an outage is tried and then given up on (%d posts)" % _fake.posts,
	)
	check(
		Leaderboard.status() == Leaderboard.Status.PENDING,
		"the game says the time is saved but not posted",
	)
	check(not _fake.scores.has(_fake.user_id), "and nothing false is on the board")


## The promise the design rests on: there is no pending-submissions file, because the record in the
## save *is* the queue. A victory won during an outage reaches the board on the next launch, from
## the records, with nothing else having remembered it.
func _test_the_record_is_the_queue() -> void:
	_setup()
	_fake.available = false

	# A victory won with no board to post it to. All that survives it is the record.
	Leaderboard.submit_run(_victory(750.0), true)
	await _wait_for_idle()
	check(_fake.posts == 0, "an offline victory posts nothing at the time")
	SaveManager.best.absorb(_victory(750.0), true)

	# The next session: a fresh coordinator with no memory of that run, and a board again.
	_reset_coordinator()
	_fake.available = true
	await Leaderboard.sync()
	await _wait_for_idle()

	check(
		_fake.scores.get(_fake.user_id, 0) == 750000,
		"the next launch re-offers the record and it lands",
	)


## Two devices, one account. The older one has a worse time in its local records and will offer it
## every session; the platform's `keep_best` is what refuses it, and this is the check that the game
## relies on that rather than overwriting.
func _test_a_stale_device_cannot_demote_a_better_time() -> void:
	_setup()
	_fake.set_entry(_fake.user_id, "YOU", 500000)
	SaveManager.best.absorb(_victory(900.0), true)

	await Leaderboard.sync()
	await _wait_for_idle()

	check(
		_fake.scores[_fake.user_id] == 500000,
		"a worse local record does not replace a better entry (%d)" % _fake.scores[_fake.user_id],
	)
	check(_fake.posts == 0, "and is not even offered, because the board was read first")


## Three victories in the time one post takes. The loop re-reads the best every pass, so what ends
## up on the board is the fastest of them rather than whichever finished last.
func _test_posts_are_single_flight_and_the_fastest_lands() -> void:
	_setup()
	await Leaderboard.sync()
	_fake.latency_frames = 2

	Leaderboard.submit_run(_victory(900.0), true)
	Leaderboard.submit_run(_victory(600.0), true)
	Leaderboard.submit_run(_victory(300.0), true)
	await _wait_for_idle()

	check(_fake.scores.get(_fake.user_id, 0) == 300000, "the fastest of the three is on the board")
	check(
		_fake.posts <= 3,
		"and three victories did not become more than three posts (%d)" % _fake.posts,
	)
	check(
		_fake.posted_scores[_fake.posted_scores.size() - 1] == 300000,
		"the last thing sent is the best thing known",
	)


## A content bump means a seed no longer builds the run it used to, so times set before it are not
## comparable with times set after. Each version gets its own board — which is what a speedrun
## category is — and this is the check that the name actually carries it.
func _test_the_board_is_named_for_the_campaign_content() -> void:
	_setup()
	await Leaderboard.sync()

	var campaign := Leaderboard.CAMPAIGN
	check(
		_fake.requested_name.contains("v%d" % campaign.content_version),
		"the board is named for the content version (%s)" % _fake.requested_name,
	)
	check(
		_fake.requested_name.contains(String(campaign.id)),
		"and for the campaign it belongs to",
	)


## Startup waits eight seconds for the platform and then gives up, which is deliberate — a game
## that hangs on a boot screen is worse than one that quietly plays offline. But a connection that
## arrives at second nine is a reachable board, and a player who then wins the campaign must not
## have to relaunch for their time to count.
func _test_a_late_connection_can_still_post() -> void:
	_setup()
	_fake.available = false
	await Leaderboard.sync()
	check(Leaderboard.status() == Leaderboard.Status.OFFLINE, "startup gave up on the platform")

	_fake.available = true
	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()

	check(
		_fake.scores.get(_fake.user_id, 0) == 600000,
		"a victory after a late connection resolves the board and lands",
	)


# --- Reading ------------------------------------------------------------------


## A board that could not be read must not be drawn as a board with nobody on it. They look
## identical on screen, and one of them is a lie the game would tell on every slow connection.
func _test_an_unreadable_board_is_not_an_empty_one() -> void:
	_setup()
	await Leaderboard.sync()
	_fake.top_failures = 1

	var page: Dictionary = await Leaderboard.fetch_top()

	check(not page.get("success", true), "a board that could not be read reports failure")
	check((page.get("entries", []) as Array).is_empty(), "rather than an empty list of times")


func _test_a_player_outside_the_page_is_still_shown_their_rank() -> void:
	_setup()
	for index: int in 12:
		_fake.set_entry("rival-%d" % index, "RIVAL %d" % index, 100000 + index * 1000)
	_fake.set_entry(_fake.user_id, "YOU", 900000)
	await Leaderboard.sync()

	var page: Dictionary = await Leaderboard.fetch_top(10)

	var entries: Array = page.get("entries", [])
	check(entries.size() == 10, "the page is the size it was asked for (%d)" % entries.size())
	var you: Dictionary = page.get("you", {})
	check(not you.is_empty(), "a player outside it is still fetched")
	check(int(you.get("rank", 0)) == 13, "with their real rank (%d)" % int(you.get("rank", 0)))
	check(you.get("is_you", false), "and marked as theirs")


# --- The screen ---------------------------------------------------------------
##
## The menu only offers LEADERBOARD in a browser (see `Leaderboard.is_offered`), so nothing in a
## headless run reaches this panel by pressing keys. It is driven directly instead, because the
## claim it makes — that a board which failed to load never looks like a board with nobody on it —
## is exactly the kind that is true in the code and false on screen.


func _test_the_panel_draws_the_board() -> void:
	_setup()
	_fake.set_entry("rival-a", "HEXWRENCH", 1122000)
	_fake.set_entry("rival-b", "NULLPTR", 1147000)
	await Leaderboard.sync()

	var panel := await _open_panel()

	check(_panel_rows(panel).size() == 2, "both times are drawn (%d rows)" % _panel_rows(panel).size())
	check(
		_panel_rows(panel)[0].contains("HEXWRENCH") and _panel_rows(panel)[0].contains("18:42"),
		"fastest first, with its time formatted as the summary screen formats one (%s)"
			% _panel_rows(panel)[0],
	)
	check(not panel._status.visible, "and no status line covers a board that loaded")
	_close_panel(panel)


## A row in the accent colour is how the rest of this game says "this one is yours", and a board of
## twenty strangers with no way to find yourself in it is a board nobody reads twice.
func _test_the_panel_marks_the_player_own_row() -> void:
	_setup()
	_fake.set_entry("rival-a", "HEXWRENCH", 1122000)
	_fake.set_entry(_fake.user_id, "YOU", 1500000)
	await Leaderboard.sync()

	var panel := await _open_panel()

	var mine_marked := false
	for label: Label in panel._rows.get_children():
		if label.text.contains("YOU"):
			mine_marked = label.get_theme_color("font_color") == UIPalette.ACCENT
	check(mine_marked, "the player's own row is drawn in the accent colour")
	_close_panel(panel)


## The check this panel exists to survive. An empty grid under a title and a board that has not
## answered are the same picture, and one of them is a lie the game would tell on every slow
## connection.
func _test_the_panel_does_not_draw_a_failure_as_an_empty_board() -> void:
	_setup()
	await Leaderboard.sync()
	_fake.top_failures = 99

	var panel := await _open_panel()

	check(_panel_rows(panel).is_empty(), "a board that could not be read draws no rows")
	check(panel._status.visible, "and says so rather than showing an empty list")
	check(
		panel._status.text != "NOBODY HAS FINISHED THE CAMPAIGN YET",
		"and does not claim the board is empty (%s)" % panel._status.text,
	)
	_close_panel(panel)


## Not signed in is not an error. Nothing broke, and the player is told the one thing that would
## put them on the board rather than a message about the platform.
func _test_the_panel_tells_a_signed_out_player_what_to_do() -> void:
	_setup()
	_fake.user_id = ""
	await Leaderboard.sync()

	var panel := await _open_panel()

	check(_panel_rows(panel).is_empty(), "a signed-out player is shown no board")
	check(
		panel._status.text == Leaderboard.status_text(),
		"and the panel says what the coordinator says (%s)" % panel._status.text,
	)
	_close_panel(panel)


# --- The rank on the run summary ----------------------------------------------


## A rank read while the run's own victory is still going up is the rank from before it — which is
## the one number the player stayed on the summary screen to watch change.
func _test_the_standing_waits_for_the_post_in_flight() -> void:
	_setup()
	_fake.set_entry("rival-a", "HEXWRENCH", 100000)
	await Leaderboard.sync()
	_fake.latency_frames = 3

	Leaderboard.submit_run(_victory(50.0), true)
	var standing: Dictionary = await Leaderboard.fetch_standing()

	check(standing.get("success", false), "the standing comes back")
	check(
		int(standing.get("rank", 0)) == 1,
		"and counts the post that was still in flight (%d)" % int(standing.get("rank", 0)),
	)


## A time that never reached the board is not a rank, and must not be drawn as one. What the screen
## gets instead is the sentence the coordinator already wrote for the player.
func _test_the_standing_reports_a_pending_post_rather_than_a_rank() -> void:
	_setup()
	await Leaderboard.sync()
	_fake.post_failures = 99

	Leaderboard.submit_run(_victory(600.0), true)
	await _wait_for_idle()
	var standing: Dictionary = await Leaderboard.fetch_standing()

	check(not standing.get("success", true), "a time that never landed is not a rank")
	check(int(standing.get("rank", 0)) == 0, "and carries no position")
	check(
		str(standing.get("message", "")) == Leaderboard.status_text(),
		"the screen is handed what the coordinator says (%s)" % standing.get("message", ""),
	)


func _test_the_summary_shows_the_rank_after_a_victory() -> void:
	_setup()
	Leaderboard.offered = true
	for index: int in 6:
		_fake.set_entry("rival-%d" % index, "RIVAL %d" % index, 100000 + index * 1000)
	_fake.set_entry(_fake.user_id, "YOU", 1122000)
	await Leaderboard.sync()

	var summary := await _open_summary(true)

	check(summary._rank.visible, "a victory shows the rank line")
	check(
		summary._rank.text == "GLOBAL RANK  #7",
		"with the player's place on the board (%s)" % summary._rank.text,
	)
	await _close_summary(summary)


## The board ranks finishes. A line about it on a death is a line about a competition the run never
## entered — and the summary is one screen serving both endings, so this is the check that the two
## did not quietly become the same.
func _test_the_summary_shows_no_rank_after_a_loss() -> void:
	_setup()
	Leaderboard.offered = true
	_fake.set_entry(_fake.user_id, "YOU", 1122000)
	await Leaderboard.sync()

	var summary := await _open_summary(false)

	check(not summary._rank.visible, "a death shows no rank line")
	await _close_summary(summary)


func _test_the_summary_shows_no_rank_where_there_is_no_board() -> void:
	_setup()
	Leaderboard.offered = false
	_fake.set_entry(_fake.user_id, "YOU", 1122000)
	await Leaderboard.sync()

	var summary := await _open_summary(true)

	check(
		not summary._rank.visible,
		"a build with no board shows no rank line, even on a victory",
	)
	await _close_summary(summary)


# --- Harness ------------------------------------------------------------------


func _setup() -> void:
	if not _borrowed:
		_borrowed = true
		_real_backend = Leaderboard.backend
		_real_backoff = Leaderboard.post_backoff_seconds
		_real_best = SaveManager.best
		_real_offered = Leaderboard.offered

	# A records object of this suite's own. `sync` re-offers whatever the player's fastest victory
	# is, and running that against whoever happens to have played on this machine would make these
	# checks depend on a save file.
	SaveManager.best = BestRunStats.new()

	# Off by default. The checks that want the screens a browser build has turn it on themselves,
	# and the rest should be looking at a coordinator, not at what a menu decided to draw.
	Leaderboard.offered = false

	_fake = FakeLeaderboardBackend.new()
	Leaderboard.backend = _fake
	Leaderboard.post_backoff_seconds = TEST_BACKOFF.duplicate()
	_reset_coordinator()


## Puts the coordinator back in the state a cold launch starts in, without reloading the autoload.
## Also how `_test_the_record_is_the_queue` gets its second session.
func _reset_coordinator() -> void:
	Leaderboard._board_id = ""
	Leaderboard._best_ms = 0
	Leaderboard._posted_ms = 0
	Leaderboard._posting = false
	Leaderboard._syncing = false
	Leaderboard._attempt = 0
	Leaderboard._run_metadata = {}
	Leaderboard._status = Leaderboard.Status.OFFLINE


func _teardown() -> void:
	if not _borrowed:
		return
	Leaderboard.backend = _real_backend
	Leaderboard.post_backoff_seconds = _real_backoff
	SaveManager.best = _real_best
	Leaderboard.offered = _real_offered
	_reset_coordinator()


## A finished, won run of `seconds`. Only the fields the board reads are filled in; everything else
## is a default, because a statistic the leaderboard does not look at is one this suite should not
## be able to break.
func _victory(seconds: float) -> RunStats:
	var stats := RunStats.new()
	stats.duration = seconds
	stats.run_seed = 1
	stats.content_version = Leaderboard.CAMPAIGN.content_version
	stats.rooms_cleared = 60
	return stats


## Opens a panel and waits for the fetch behind it to land. Two frames rather than one: `open`
## starts a coroutine, and the reply it is waiting on is itself a coroutine.
func _open_panel() -> LeaderboardPanel:
	var panel: LeaderboardPanel = load("res://scenes/ui/leaderboard_panel.tscn").instantiate()
	add_child(panel)
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	return panel


func _close_panel(panel: LeaderboardPanel) -> void:
	panel.queue_free()


## The text of each drawn row, minus the separator the panel puts above an out-of-page entry.
func _panel_rows(panel: LeaderboardPanel) -> PackedStringArray:
	var lines := PackedStringArray()
	for label: Label in panel._rows.get_children():
		if label.text != LeaderboardPanel.BREAK:
			lines.append(label.text)
	return lines


## Instances a summary and ends a run under it, the way `tests/test_menus.gd` drives the same
## screen. The extra frames are the rank fetch, which is two coroutines deep and cannot have
## answered on the frame the ending was announced.
func _open_summary(won: bool) -> RunSummary:
	var summary: RunSummary = load("res://scenes/ui/run_summary.tscn").instantiate()
	add_child(summary)
	if won:
		GameManager.win_run()
	else:
		GameManager.end_run()
	await advance_physics(2)
	await get_tree().process_frame
	await get_tree().process_frame
	return summary


func _close_summary(summary: RunSummary) -> void:
	GameManager.start_run()
	summary.queue_free()
	await advance_physics(1)


func _wait_for_idle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (Leaderboard._posting or Leaderboard._syncing) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# One more frame so anything the loop kicked off on its way out has run.
	await get_tree().process_frame
	check(not Leaderboard._posting, "the coordinator settled rather than spinning")

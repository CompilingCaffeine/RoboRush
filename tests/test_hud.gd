extends TestCase
## Checks for the banners `CombatHUD` puts on screen.
##
## This suite exists because of a bug that shipped: every boss emits `boss_phase_changed`, and
## the HUD answered it with lines written for The Scrap King — so Runtime Error reached its
## second phase and the player was told "LONG LIVE THE KING" over a boss with no claim to the
## title. Nothing failed. Nothing errored. The HUD simply said the wrong thing, which is a class
## of bug that only a test reading the banner can catch, and there was no such test.
##
## So what is checked here is not that banners exist but that the *right boss's words* reach the
## screen, and that a boss with nothing to say gets silence rather than somebody else's lines.
## Both floors' shipped data is driven through the real HUD, because the point is the wiring
## between `FloorConfig` and the label, and a test that asserted on the resource alone would
## have passed happily while the HUD ignored it.

const HUD_SCENE := preload("res://scenes/ui/combat_hud.tscn")
const KING_ENCOUNTER_PATH := "res://data/bosses/scrap_king_encounter.tres"
const ERROR_ENCOUNTER_PATH := "res://data/bosses/runtime_error_encounter.tres"

var _hud: CombatHUD
var _banner: Label


func run() -> void:
	await _test_the_king_still_announces_his_own_phases()
	await _test_a_boss_with_nothing_to_say_says_nothing()
	await _test_no_boss_borrows_another_bosss_lines()
	await _test_each_level_announces_itself()


## The half of the fix that is easy to break by fixing the other half: moving these lines out of
## the HUD and into floor data must not have dropped them on the way.
func _test_the_king_still_announces_his_own_phases() -> void:
	var encounter := await _bind_boss(KING_ENCOUNTER_PATH)
	if encounter == null:
		return

	for phase: int in [2, 3]:
		_clear_banner()
		EventBus.boss_phase_changed.emit(phase)
		check(
			_banner.visible and not _banner.text.is_empty(),
			"The Scrap King announces phase %d" % phase,
		)
		check(
			_banner.text == encounter.phase_banners[phase - 1],
			"in the words its own encounter gives it ('%s')" % _banner.text,
		)

	# Phase one opens the fight and has nothing to announce — the boss arriving is the
	# announcement. Its entry in the array is deliberately empty rather than absent.
	_clear_banner()
	EventBus.boss_phase_changed.emit(1)
	check(not _banner.visible, "and phase one arrives without a banner")

	await _teardown()


## The bug itself, pinned. Runtime Error emits exactly the same signal from exactly the same
## phases; what has to differ is what the HUD does about it.
func _test_a_boss_with_nothing_to_say_says_nothing() -> void:
	var encounter := await _bind_boss(ERROR_ENCOUNTER_PATH)
	if encounter == null:
		return

	check(
		encounter.phase_banners.is_empty(),
		"Runtime Error is given no phase lines to say",
	)
	for phase: int in [1, 2, 3]:
		_clear_banner()
		EventBus.boss_phase_changed.emit(phase)
		check(
			not _banner.visible,
			"and Runtime Error reaching phase %d puts nothing on screen" % phase,
		)

	# The bar's label is the one thing a phase change must still update, whatever the boss.
	EventBus.boss_phase_changed.emit(2)
	check(
		(_hud.get_node("%BossLabel") as Label).text == encounter.display_name,
		"though the boss bar is still labelled with the boss's own name",
	)
	await _teardown()


## The general form of the same mistake, checked against the data rather than the HUD: no boss
## may be given a line that names a different boss.
##
## This used to be phrased per *floor* — "Development's boss lines do not crown it" — and that
## phrasing died with the assumption behind it. Either boss can now guard either floor, so a
## line naming the wrong boss is not a floor's mistake to make; the lines belong to the
## encounter, and this is where they are checked.
func _test_no_boss_borrows_another_bosss_lines() -> void:
	var king: BossEncounter = load(KING_ENCOUNTER_PATH) as BossEncounter
	var error: BossEncounter = load(ERROR_ENCOUNTER_PATH) as BossEncounter
	if not require(king and error, "both boss encounters load"):
		return

	for banner: String in error.phase_banners + [error.defeat_banner]:
		check(
			not banner.to_upper().contains("KING"),
			"Runtime Error's lines do not crown it ('%s')" % banner,
		)
	for banner: String in king.phase_banners + [king.defeat_banner]:
		check(
			not banner.to_upper().contains("RUNTIME"),
			"and The Scrap King's do not name the other boss ('%s')" % banner,
		)


## The floor number, announced as the floor begins. `main.gd` calls this at startup and again on
## every descent, which are the only two ways a floor ever starts.
func _test_each_level_announces_itself() -> void:
	await _make_hud()

	for number: int in [1, 2]:
		_clear_banner()
		_hud.announce_floor(number)
		check(_banner.visible, "level %d announces itself" % number)
		check(_banner.text == "LEVEL %d" % number, "as '%s'" % _banner.text)

	# It is a banner, not a permanent readout: the floor name in the strip along the bottom is
	# the standing answer, and this is the interruption. A banner that never left would cover
	# playable floor for the rest of the run.
	_clear_banner()
	_hud.announce_floor(2)
	await advance_physics(int(CombatHUD.BANNER_SECONDS * 60.0) + 8)
	check(not _banner.visible, "and gets out of the way again")

	await _teardown()


# --- Fixtures -----------------------------------------------------------------


func _make_hud() -> void:
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	await advance_physics(1)
	_banner = _hud.get_node("%Banner") as Label


## A live HUD bound to a boss's shipped identity, exactly as `FloorController` binds it.
## Returns the encounter so the checks can assert against the same data the HUD was given,
## rather than against a copy of the strings written out again here — a test that restates the
## words it is checking passes when both are wrong together.
func _bind_boss(path: String) -> BossEncounter:
	var encounter: BossEncounter = load(path) as BossEncounter
	if not require(encounter, "%s loads as a BossEncounter" % path):
		return null
	await _make_hud()
	_hud.bind_boss(encounter.display_name, encounter.defeat_banner, encounter.phase_banners)
	return encounter


## Hides the banner without waiting out its timer, so each check reads a banner this check
## caused rather than one left over from the previous one.
func _clear_banner() -> void:
	_banner.visible = false
	_banner.text = ""


func _teardown() -> void:
	# Freed rather than left standing: the HUD connects itself to several EventBus signals in
	# `_ready`, and a second one still listening would answer every later suite's boss events.
	_hud.queue_free()
	_hud = null
	_banner = null
	await advance_physics(2)

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
const FLOOR_1_CONFIG_PATH := "res://data/floors/floor_1_help_desk.tres"
const FLOOR_2_CONFIG_PATH := "res://data/floors/floor_2_development.tres"

var _hud: CombatHUD
var _banner: Label


func run() -> void:
	await _test_the_king_still_announces_his_own_phases()
	await _test_a_boss_with_nothing_to_say_says_nothing()
	await _test_no_floor_borrows_another_floors_boss_lines()
	await _test_each_level_announces_itself()


## The half of the fix that is easy to break by fixing the other half: moving these lines out of
## the HUD and into floor data must not have dropped them on the way.
func _test_the_king_still_announces_his_own_phases() -> void:
	var config := await _bind_floor(FLOOR_1_CONFIG_PATH)
	if config == null:
		return

	for phase: int in [2, 3]:
		_clear_banner()
		EventBus.boss_phase_changed.emit(phase)
		check(
			_banner.visible and not _banner.text.is_empty(),
			"The Scrap King announces phase %d" % phase,
		)
		check(
			_banner.text == config.boss_phase_banners[phase - 1],
			"in the words its own floor gives it ('%s')" % _banner.text,
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
	var config := await _bind_floor(FLOOR_2_CONFIG_PATH)
	if config == null:
		return

	check(
		config.boss_phase_banners.is_empty(),
		"Development gives its boss no phase lines to say",
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
		(_hud.get_node("%BossLabel") as Label).text == config.boss_display_name,
		"though the boss bar is still labelled with the boss's own name",
	)
	await _teardown()


## The general form of the same mistake, checked against the data rather than the HUD: no floor
## may hand its boss a line naming a different floor's boss. Cheap now, and the check that keeps
## being true when a third floor is added by somebody copying the second floor's resource.
func _test_no_floor_borrows_another_floors_boss_lines() -> void:
	var floor_one: FloorConfig = load(FLOOR_1_CONFIG_PATH) as FloorConfig
	var floor_two: FloorConfig = load(FLOOR_2_CONFIG_PATH) as FloorConfig
	if not require(floor_one and floor_two, "both floor configs load"):
		return

	for banner: String in floor_two.boss_phase_banners:
		check(
			not banner.contains("KING"),
			"Development's boss lines do not crown it ('%s')" % banner,
		)
	for banner: String in floor_one.boss_phase_banners:
		check(
			not banner.to_upper().contains("RUNTIME"),
			"and Help Desk's do not name the next floor's boss ('%s')" % banner,
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


## A live HUD bound to a floor's shipped boss identity, exactly as `FloorController` binds it.
## Returns the config so the checks can assert against the same data the HUD was given, rather
## than against a copy of the strings written out again here — a test that restates the words it
## is checking passes when both are wrong together.
func _bind_floor(path: String) -> FloorConfig:
	var config: FloorConfig = load(path) as FloorConfig
	if not require(config, "%s loads as a FloorConfig" % path):
		return null
	await _make_hud()
	_hud.bind_boss(
		config.boss_display_name, config.boss_defeat_banner, config.boss_phase_banners
	)
	return config


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

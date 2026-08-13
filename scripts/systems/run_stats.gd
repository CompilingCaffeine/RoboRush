class_name RunStats
extends RefCounted
## Everything spec section 25 asks a run to remember.
##
## Split out of RunManager rather than piling onto it, because these are two different
## kinds of run state: `scrap` is read by gameplay and changes what the player can do,
## while everything here is *only* ever read by the summary screen. Keeping them apart
## means the summary can be rebuilt without touching anything that affects play, and
## RunManager stays a place you can read in one sitting.
##
## Plain fields plus one `describe()`. The screen that shows these should not have to know
## how to format a duration, and nothing else should have to know the display order.

## Seconds of actual play. Time spent paused or on the summary screen is not run duration.
var duration: float = 0.0

## What this run can be reproduced from: its seed, the campaign it was played against, and that
## campaign's content version. All three, because none of them is enough alone — a seed builds a
## different floor 3 after floor 3 is edited, and the version is the only thing that says so.
##
## Filled in by `RunManager.begin_run`. Kept here rather than only on RunManager because these
## travel with the run's *record*: a summary screen showing a seed nobody can type back in, or a
## filed result that cannot say which content produced it, is a statistic that answers nothing.
var run_seed: int = 0
var campaign_id: StringName = &""
var content_version: int = 1

var rooms_cleared: int = 0
var enemies_defeated: int = 0
var bosses_defeated: int = 0

## How far the run got, counted in floors reached rather than cleared — a player destroyed in floor
## 5's first room got to floor 5. The headline number of a six-floor campaign, and the one the
## per-floor records below are the detail of.
var deepest_floor: int = 0

## One record per floor entered, in order, the last of which is the floor the run is on. See
## `FloorRecord`: a run's totals cannot say which floor cost the eleven minutes or which one ended
## it, and those are the two questions six floors of pacing are tuned against.
var floors: Array[FloorRecord] = []

var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var scrap_collected: int = 0

var items_collected: PackedStringArray = []

## Largest single hit the player has landed. The number a build is remembered by.
var highest_hit: float = 0.0

## Rooms cleared consecutively without taking damage, and the best such run. Measured in
## rooms rather than seconds because a room is the unit the player experiences.
var current_clean_streak: int = 0
var longest_clean_streak: int = 0

## Shots fired per weapon, so "favourite weapon" is measured rather than assumed. With one
## weapon in the game this is a foregone conclusion; it is here so that stops being true
## for free when weapon cores arrive.
var shots_by_weapon: Dictionary[String, int] = {}

## What landed the killing blow, or empty while the player is alive.
var cause_of_death: String = ""


## Opens a record for a floor the run has just entered.
##
## Re-entering the floor already open is ignored rather than opening a second record. Nothing in the
## game does that today — a floor is entered once — but the cost of being wrong is a run that reports
## seven floors for a six-floor campaign, and the check is one comparison.
func begin_floor(number: int, id: StringName, seed_value: int) -> void:
	var open := current_floor()
	if open != null:
		if open.floor_number == number and open.floor_id == id:
			return
		# A floor left without an outcome is a floor whose exit nobody reported. Closing it as a
		# descent is the only honest reading — the run is standing on a later floor, so it left this
		# one alive — and it keeps the records a complete list rather than a list with a hole.
		open.close(FloorRecord.Outcome.DESCENDED, duration, rooms_cleared)

	floors.append(FloorRecord.opened(number, id, seed_value, duration, rooms_cleared))
	deepest_floor = maxi(deepest_floor, number)


## Notes which boss guards the floor being played. Ignored when no floor is open, which is every
## test arena that draws a boss without a run around it.
func record_floor_boss(boss_id: StringName) -> void:
	var open := current_floor()
	if open != null:
		open.boss_id = boss_id


## Closes the open floor's record. Safe to call when there is nothing open or when it is already
## closed — the events that end a floor are not exclusive, and the first one to arrive wins.
func finish_floor(outcome: FloorRecord.Outcome) -> void:
	var open := current_floor()
	if open != null:
		open.close(outcome, duration, rooms_cleared)


## The floor being played, or null if the run has not entered one or has finished.
func current_floor() -> FloorRecord:
	if floors.is_empty():
		return null
	var last := floors[floors.size() - 1]
	return last if last.is_open() else null


## Every floor of the run, one per line. For a log, a bug report, or a test failure message — not
## for the summary screen, which shows the run rather than debugs it.
func describe_floors() -> String:
	if floors.is_empty():
		return "no floor entered"
	var lines: PackedStringArray = []
	for record: FloorRecord in floors:
		lines.append(record.describe())
	return "\n".join(lines)


func record_shot(weapon_name: String) -> void:
	shots_by_weapon[weapon_name] = shots_by_weapon.get(weapon_name, 0) + 1


func record_damage_dealt(amount: float) -> void:
	damage_dealt += amount
	highest_hit = maxf(highest_hit, amount)


## Taking a hit ends the streak wherever it had got to.
func record_damage_taken(amount: float) -> void:
	damage_taken += amount
	current_clean_streak = 0


func record_room_cleared() -> void:
	rooms_cleared += 1
	current_clean_streak += 1
	longest_clean_streak = maxi(longest_clean_streak, current_clean_streak)


func get_favourite_weapon() -> String:
	var best := ""
	var best_shots := 0
	for weapon_name: String in shots_by_weapon:
		if shots_by_weapon[weapon_name] > best_shots:
			best_shots = shots_by_weapon[weapon_name]
			best = weapon_name
	return best if not best.is_empty() else "none"


## Ordered label/value pairs for the summary screen. Ordered by what a player actually
## wants to know first — how far they got, then how well they fought, then the trivia.
func describe() -> Array:
	var rows: Array = [
		["TIME", format_duration(duration)],
		["DEEPEST FLOOR", str(maxi(deepest_floor, 1))],
		["ROOMS CLEARED", str(rooms_cleared)],
		["ENEMIES DEFEATED", str(enemies_defeated)],
		["BOSSES DEFEATED", str(bosses_defeated)],
		["SCRAP COLLECTED", str(scrap_collected)],
		["ITEMS", str(items_collected.size())],
		["DAMAGE DEALT", "%.0f" % damage_dealt],
		["DAMAGE TAKEN", "%.0f" % damage_taken],
		["HIGHEST HIT", "%.1f" % highest_hit],
		["CLEAN STREAK", "%d rooms" % longest_clean_streak],
		["WEAPON", get_favourite_weapon().to_upper()],
	]
	if not cause_of_death.is_empty():
		rows.append(["DESTROYED BY", cause_of_death.to_upper()])
	if not items_collected.is_empty():
		rows.append(["BUILD", ", ".join(items_collected).to_upper()])
	# Last, because it is the one row that is not about how the run went. It is here at all so that
	# "that run generated a floor I could not get out of" is a reproducible report rather than a
	# story: the seed on the screen is the seed `--seed=` takes, and the version is what says the
	# content has not moved under it since.
	rows.append(["SEED", "%d  v%d" % [run_seed, content_version]])
	return rows


static func format_duration(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

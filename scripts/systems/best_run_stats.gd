class_name BestRunStats
extends RefCounted
## The best a player has ever done, across every run. Spec section 24's "best run statistics".
##
## The counterpart to `RunStats`: that one is thrown away when a run ends, this one is what
## survives it. Kept as its own object rather than as fields on `SaveManager` so that the rule
## for "is this a record?" lives next to the records — `absorb` is the only place that decides,
## and the summary screen can ask for a comparison without knowing how any of it is measured.
##
## Only bests worth chasing are here. "Damage taken" has no best worth showing (the record is
## always zero on a run that ended in the first room), and a statistic nobody would try to beat
## is clutter on a screen that has to stay readable.

## Fastest *victory*, in seconds. Zero until the floor has been cleared once — a fast loss is
## not a fast run, and treating it as one would make the record unbeatable.
var fastest_victory: float = 0.0

var most_rooms_cleared: int = 0
var most_enemies_defeated: int = 0
var most_scrap_collected: int = 0
var highest_hit: float = 0.0
var longest_clean_streak: int = 0

var runs_started: int = 0
var runs_won: int = 0


## Folds a finished run into the record. `won` is passed in rather than inferred from the
## stats, because "the boss died" and "the run was won" are the same thing today and will not
## be once there is a second floor.
##
## Returns the labels of whatever was beaten, so the summary screen can say "NEW RECORD" next
## to the line that earned it instead of the player having to remember their old number.
func absorb(stats: RunStats, won: bool) -> PackedStringArray:
	var beaten := PackedStringArray()

	if stats.rooms_cleared > most_rooms_cleared:
		most_rooms_cleared = stats.rooms_cleared
		beaten.append("ROOMS CLEARED")
	if stats.enemies_defeated > most_enemies_defeated:
		most_enemies_defeated = stats.enemies_defeated
		beaten.append("ENEMIES DEFEATED")
	if stats.scrap_collected > most_scrap_collected:
		most_scrap_collected = stats.scrap_collected
		beaten.append("SCRAP COLLECTED")
	if stats.highest_hit > highest_hit:
		highest_hit = stats.highest_hit
		beaten.append("HIGHEST HIT")
	if stats.longest_clean_streak > longest_clean_streak:
		longest_clean_streak = stats.longest_clean_streak
		beaten.append("CLEAN STREAK")

	if won:
		runs_won += 1
		# Lower is better here, and zero means "never done it" rather than "did it instantly".
		if fastest_victory <= 0.0 or stats.duration < fastest_victory:
			fastest_victory = stats.duration
			beaten.append("TIME")

	return beaten


## True once the player has any history at all. The main menu hides the records panel until
## this is true, because a wall of zeroes tells a new player nothing except that they are new.
func has_history() -> bool:
	return runs_started > 0


## Ordered label/value pairs, matching `RunStats.describe()` so the two can be shown side by
## side without either screen knowing how the other formats a number.
func describe() -> Array:
	var rows: Array = [
		["RUNS", str(runs_started)],
		["VICTORIES", str(runs_won)],
		["BEST TIME", RunStats.format_duration(fastest_victory) if fastest_victory > 0.0 else "--:--"],
		["MOST ROOMS", str(most_rooms_cleared)],
		["MOST ENEMIES", str(most_enemies_defeated)],
		["MOST SCRAP", str(most_scrap_collected)],
		["HIGHEST HIT", "%.1f" % highest_hit],
		["CLEAN STREAK", "%d rooms" % longest_clean_streak],
	]
	return rows


func to_dict() -> Dictionary:
	return {
		"fastest_victory": fastest_victory,
		"most_rooms_cleared": most_rooms_cleared,
		"most_enemies_defeated": most_enemies_defeated,
		"most_scrap_collected": most_scrap_collected,
		"highest_hit": highest_hit,
		"longest_clean_streak": longest_clean_streak,
		"runs_started": runs_started,
		"runs_won": runs_won,
	}


## Same forgiveness as `GameSettings.from_dict`: a missing or malformed field costs one
## record, not the file.
static func from_dict(data: Dictionary) -> BestRunStats:
	var best := BestRunStats.new()
	best.fastest_victory = _read_number(data, "fastest_victory")
	best.most_rooms_cleared = int(_read_number(data, "most_rooms_cleared"))
	best.most_enemies_defeated = int(_read_number(data, "most_enemies_defeated"))
	best.most_scrap_collected = int(_read_number(data, "most_scrap_collected"))
	best.highest_hit = _read_number(data, "highest_hit")
	best.longest_clean_streak = int(_read_number(data, "longest_clean_streak"))
	best.runs_started = int(_read_number(data, "runs_started"))
	best.runs_won = int(_read_number(data, "runs_won"))
	return best


## Records are all non-negative counts and durations, so one reader covers every field. A
## negative value in the file is treated as absent rather than trusted: it can only come from
## hand-editing, and a negative best would make every real result look like a record.
static func _read_number(data: Dictionary, key: String) -> float:
	var value: Variant = data.get(key)
	if not (value is float or value is int):
		return 0.0
	return maxf(float(value), 0.0)

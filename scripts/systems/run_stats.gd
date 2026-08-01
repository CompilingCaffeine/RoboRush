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

var rooms_cleared: int = 0
var enemies_defeated: int = 0
var bosses_defeated: int = 0

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
	return rows


static func format_duration(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

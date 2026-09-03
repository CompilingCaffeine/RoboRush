class_name GreyboxCampaign
extends RefCounted
## A campaign of any length, built out of copies of a real floor, for suites that need more floors
## than the game currently has.
##
## The shipped campaign lists two floors, which is one boundary — and one boundary cannot show the
## failures that boundaries actually have. Those are all *accumulation*: a leaked room graph, a
## projectile container that answers for two floors, a seed derived from the floor before it. Each
## looks like a working game once and like a bug five times.
##
## Copies of real content rather than `FloorConfig.new()`, so a descent through it exercises rooms,
## enemies, loot and a boss rather than an empty graph. The one thing that has to change is
## eligibility: a floor's templates declare the last floor they may appear on, and the Help Desk's
## stop at 2 — so floors 3 and beyond would have nothing to build from and the generator would
## rightly refuse them.
##
## Written to `user://` rather than held in memory, because a campaign resolves its floors by
## *path* (see `FloorEntry`) and an in-memory `FloorConfig` would skip the load that is part of
## what a descent is being tested for.
##
## Extracted from `tests/test_floor.gd` when a second and third suite needed it. Every consumer
## shares one definition of "a six-floor campaign", so a floor that stops being buildable breaks
## them together rather than one at a time.

const SOURCE_FLOOR_PATH := "res://data/floors/floor_1_help_desk.tres"
const DIRECTORY := "user://test_greybox_campaign"

## Files written so far, so they can all be removed at the end of a run. Instance state rather than
## static, so two suites cannot delete each other's floors mid-test.
var _written: PackedStringArray = []

## Why the last build failed, or empty. Read by the caller so the failure is reported against its
## own suite rather than pushed as an engine error nobody attributes.
var error := ""


## A campaign of `count` floors, or null if it could not be written.
##
## `mutate` is called with each floor's config and index before it is saved, for the suites that
## need one floor to be deliberately broken.
func build(count: int, mutate := Callable()) -> RunDefinition:
	error = ""
	var source := load(SOURCE_FLOOR_PATH) as FloorConfig
	if source == null:
		error = "%s must load to build a greybox campaign from" % SOURCE_FLOOR_PATH
		return null
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		DirAccess.make_dir_recursive_absolute(DIRECTORY)

	var floors: Array[FloorEntry] = []
	for index: int in count:
		# Shallow, so every property below is *reassigned* rather than edited in place: the arrays
		# are shared with the shipped resource, and mutating one here would rewrite the Help Desk
		# for every suite that runs after this one.
		var config := source.duplicate() as FloorConfig
		config.id = StringName("greybox_%d" % (index + 1))
		config.floor_number = index + 1
		# Synthetic tiers keep lifecycle probes valid after the real boss draw became strict.
		# The scene is reused intentionally here; no synthetic encounter enters shipped data.
		var encounter := source.boss_pool[0].duplicate() as BossEncounter
		encounter.id = StringName("greybox_boss_%d" % (index + 1))
		config.boss_pool = [encounter]
		config.start_templates = _reaching_floor(source.start_templates, count)
		config.combat_templates = _reaching_floor(source.combat_templates, count)
		config.treasure_templates = _reaching_floor(source.treasure_templates, count)
		config.shop_templates = _reaching_floor(source.shop_templates, count)
		config.boss_templates = _reaching_floor(source.boss_templates, count)
		if mutate.is_valid():
			mutate.call(config, index)

		var path := "%s/floor_%d_of_%d.tres" % [DIRECTORY, index + 1, count]
		if ResourceSaver.save(config, path) != OK:
			error = "could not write the greybox floor %s" % path
			return null
		if not _written.has(path):
			_written.append(path)

		var entry := FloorEntry.new()
		entry.id = config.id
		entry.config_path = path
		floors.append(entry)

	var campaign := RunDefinition.new()
	campaign.id = &"greybox"
	campaign.floors = floors
	campaign.target_floor_count = count
	return campaign


## Removes every floor written so far. Left behind, they would be read by the next run of the suite
## from a build that had since changed what a floor looks like.
func clean_up() -> void:
	for path: String in _written:
		DirAccess.remove_absolute(path)
	_written.clear()
	DirAccess.remove_absolute(DIRECTORY)


## Copies of `templates` that stay eligible all the way to `last_floor`.
func _reaching_floor(templates: Array[RoomTemplate], last_floor: int) -> Array[RoomTemplate]:
	var raised: Array[RoomTemplate] = []
	for template: RoomTemplate in templates:
		var copy := template.duplicate() as RoomTemplate
		copy.max_floor = last_floor
		raised.append(copy)
	return raised

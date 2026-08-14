class_name RunCheckpoint
extends RefCounted
## A run, frozen at a floor boundary, in a form that can be written to disk and read back.
##
## Spec section 24 said a run in progress is never saved, and that was the right call for a
## ten-room run: there was nothing to lose that could not be replayed in six minutes. Six
## ten-room floors is a different promise — a sixty-room run interrupted at floor five by a
## closed laptop is an hour the player does not get back, and "do not close the laptop" is not a
## design.
##
## **Only at a floor boundary.** The checkpoint is written after a descent has committed, when
## the run is standing at the start of a new floor with nothing in flight: no projectile, no
## painted lane, no half-cleared room, no boss mid-phase. That is the one moment in a run whose
## whole state is a handful of numbers, and it is why this class is a list of fields rather than
## a serialiser for the scene tree. Everything a floor owns is rebuilt from the floor's derived
## seed, exactly as a fresh arrival would build it (`RunDefinition.floor_seed_for`), so what has
## to be stored is only what the *run* carries across the boundary.
##
## **What is deliberately not here.** Where the player was standing, which rooms they had
## visited, what the minimap had drawn, how much of the floor was cleared: all floor-local, all
## discarded with the session that owned them, and all rebuilt by resuming onto the top of the
## floor. A resume puts the player at the start of the floor they had just reached, not at the
## pixel they stood on.
##
## **Weapons.** There is one weapon and no way to change it, so there is nothing to record. When
## weapon cores arrive, the held core's stable id belongs in this file beside the items — and
## `RunStats.shots_by_weapon`, which is already carried, is what makes the counters agree after a
## restore rather than restarting from zero.
##
## Everything read back is treated as hostile. A save file is data from outside the program: it
## can be hand-edited, truncated by a crash, or written by a build that has since been changed.
## `validate` is what stands between that and gameplay, and it refuses the whole checkpoint
## rather than repairing fields — a run resumed from a file that was *almost* right is a run
## whose bugs cannot be reproduced from its seed.

## Ceilings for every collection and number a file can carry, so a hand-edited or corrupt save
## cannot make the loader allocate or loop against a number of its own choosing. Each one is far
## above anything a real run reaches and far below anything that costs a frame: they are refusals,
## not tuning.
const MAX_ID_LENGTH := 64
const MAX_ITEMS := 128
const MAX_OFFERED_ITEMS := 512
const MAX_BOSSES := 64
const MAX_FLOOR_RECORDS := 64
const MAX_SCRAP := 999_999
const MAX_ROOMS_CLEARED := 10_000
const MAX_INTEGRITY := 999.0
const MAX_DEATH_SAVES := 64

## Twenty-four hours. A run that claims to have taken longer than a day is a corrupt duration
## rather than a patient player, and a run's records are folded into lifetime bests on the way
## out — an absurd duration would set a "best time" nothing could ever beat.
const MAX_DURATION_SECONDS := 86_400.0

## Which campaign this run is playing, and the content version it was played against. Both,
## because neither identifies a run alone: the same seed builds a different floor 3 once floor 3
## is edited, and only the version says so. A checkpoint whose version no longer matches the
## campaign is refused rather than resumed into content it was not drawn against.
var campaign_id: StringName = &""
var content_version: int = 1

## The floor the run is standing at the top of — the one a resume rebuilds. Stable id, and the
## number is carried alongside it only so a refusal can say "floor 4" in its diagnostics and so
## the menu can offer the run by name without loading the campaign's content.
var floor_id: StringName = &""
var floor_number: int = 1

## The run's one immutable seed. Every floor's layout, boss, roster, shop and loot is derived
## from this plus a stable name, so storing it is what makes a resumed run continue to be the
## same run rather than a new one with the old inventory.
var run_seed: int = 0

var scrap: int = 0
var rooms_cleared: int = 0

## The player's integrity at the boundary, and the two run-scoped values that decide what its
## ceiling is: see `RunManager.max_integrity_penalty` and `RunManager.death_saves_spent`. All
## three are needed. Restoring the items alone would hand back a robot repaired to full and
## refund every death save it had spent.
var integrity: float = 0.0
var max_integrity_penalty: float = 0.0
var death_saves_spent: int = 0

## What has accrued against the run's enemies. See `RunManager.enemy_health_scale`.
var enemy_health_scale: float = 1.0

## The build, in pickup order. Order is carried rather than sorted because the last item with an
## accent colour is the one the robot is painted in, and a resumed run that changed colour would
## be the game visibly forgetting something.
var item_ids: Array[StringName] = []

## What the run has already spent from the item pool, and which bosses it has already fought.
## Both are what stop a resumed run re-offering a build-defining item or re-running a fight —
## the acceptance criterion that a restore cannot duplicate a reward or boss credit is mostly
## these two arrays.
var offered_item_ids: Array[StringName] = []
var fought_boss_ids: Array[StringName] = []

## The run's statistics, including one record per floor entered. Carried whole rather than
## restarted, because a resumed run files exactly one result at the end and that result has to
## describe the whole run — a checkpoint that reset the statistics would report a six-floor
## victory as having cleared ten rooms.
var stats := RunStats.new()


## Takes a checkpoint of the run as it stands. Called at a floor boundary and nowhere else; see
## the class comment for why nowhere else is safe.
static func capture(
	campaign: RunDefinition, floor_config: FloorConfig, player_integrity: float,
	held_items: Array[ItemConfig]
) -> RunCheckpoint:
	var checkpoint := RunCheckpoint.new()
	checkpoint.campaign_id = campaign.id
	checkpoint.content_version = campaign.content_version
	checkpoint.floor_id = floor_config.id
	checkpoint.floor_number = floor_config.floor_number
	checkpoint.run_seed = RunManager.get_run_seed()
	checkpoint.scrap = RunManager.scrap
	checkpoint.rooms_cleared = RunManager.rooms_cleared
	checkpoint.integrity = player_integrity
	checkpoint.max_integrity_penalty = RunManager.max_integrity_penalty
	checkpoint.death_saves_spent = RunManager.death_saves_spent
	checkpoint.enemy_health_scale = RunManager.enemy_health_scale
	checkpoint.offered_item_ids = RunManager.offered_item_ids.duplicate()
	checkpoint.fought_boss_ids = RunManager.fought_boss_ids.duplicate()
	# A copy, not the live object. The checkpoint outlives this call — `SaveManager` holds it as
	# the active one until the run ends — and a reference would keep quietly absorbing the rest of
	# the run, so what was written to disk and what the object said would drift apart the moment
	# the player cleared another room.
	checkpoint.stats = RunStats.from_dict(RunManager.stats.to_dict())

	for item: ItemConfig in held_items:
		if item != null:
			checkpoint.item_ids.append(item.id)

	return checkpoint


func to_dict() -> Dictionary:
	return {
		"campaign_id": String(campaign_id),
		"content_version": content_version,
		"floor_id": String(floor_id),
		"floor_number": floor_number,
		"run_seed": run_seed,
		"scrap": scrap,
		"rooms_cleared": rooms_cleared,
		"integrity": integrity,
		"max_integrity_penalty": max_integrity_penalty,
		"death_saves_spent": death_saves_spent,
		"enemy_health_scale": enemy_health_scale,
		"items": _names_to_strings(item_ids),
		"offered_items": _names_to_strings(offered_item_ids),
		"fought_bosses": _names_to_strings(fought_boss_ids),
		"stats": stats.to_dict(),
	}


## Reads a checkpoint out of a save file. Never fails: every field comes back as its declared
## type or as that type's zero, and whether the *result* is playable is `validate`'s question.
## Splitting those apart is what lets a refusal name the field that was wrong instead of
## reporting that JSON parsing went badly somewhere.
static func from_dict(data: Dictionary) -> RunCheckpoint:
	var checkpoint := RunCheckpoint.new()
	checkpoint.campaign_id = RunStats.read_name(data, "campaign_id")
	checkpoint.content_version = RunStats.read_int(data, "content_version")
	checkpoint.floor_id = RunStats.read_name(data, "floor_id")
	checkpoint.floor_number = RunStats.read_int(data, "floor_number")
	checkpoint.run_seed = RunStats.read_int(data, "run_seed")
	checkpoint.scrap = RunStats.read_int(data, "scrap")
	checkpoint.rooms_cleared = RunStats.read_int(data, "rooms_cleared")
	checkpoint.integrity = RunStats.read_float(data, "integrity")
	checkpoint.max_integrity_penalty = RunStats.read_float(data, "max_integrity_penalty")
	checkpoint.death_saves_spent = RunStats.read_int(data, "death_saves_spent")
	checkpoint.enemy_health_scale = RunStats.read_float(data, "enemy_health_scale")
	checkpoint.item_ids = _strings_to_names(data.get("items"))
	checkpoint.offered_item_ids = _strings_to_names(data.get("offered_items"))
	checkpoint.fought_boss_ids = _strings_to_names(data.get("fought_bosses"))

	var raw_stats: Variant = data.get("stats")
	checkpoint.stats = RunStats.from_dict(raw_stats as Dictionary if raw_stats is Dictionary else {})
	return checkpoint


## Every reason this checkpoint cannot be played, or an empty list if there is none.
##
## A list rather than a boolean because the caller logs them: a refused resume that says only
## "invalid" leaves a player with a run they cannot continue and a developer with nothing to go
## on, and both of those are worse than the corruption that caused it.
##
## Loads the floor being resumed onto, which a resume is about to load anyway (Godot's resource
## cache makes the second call free). That floor's item pool is the catalogue every held and
## offered item id is checked against — the campaign shares one pool across its floors, and an id
## that is not in it is either an item that has been deleted from the game or a hand-edit.
func validate(campaign: RunDefinition) -> PackedStringArray:
	var problems: PackedStringArray = []
	if campaign == null:
		problems.append("there is no campaign to check against")
		return problems

	_validate_identity(problems, campaign)
	_validate_numbers(problems)
	_validate_collections(problems)

	var floor_config := campaign.load_floor_by_id(floor_id)
	if floor_config == null:
		# Already reported by `_validate_identity` as an unknown floor id; the load failing for any
		# other reason is a broken campaign rather than a broken save, and the run cannot start
		# either way.
		if campaign.index_of(floor_id) >= 0:
			problems.append("floor '%s' is in the campaign but its content would not load" % floor_id)
		return problems

	if floor_config.floor_number != floor_number:
		problems.append(
			"floor '%s' is floor %d, but the checkpoint calls it floor %d"
			% [floor_id, floor_config.floor_number, floor_number]
		)
	_validate_items(problems, floor_config)
	return problems


## The items this checkpoint says the player is carrying, resolved against the floor's pool.
## Anything unresolvable is dropped rather than reported here — `validate` is what refuses a
## checkpoint, and this is only ever called on one that passed it.
func resolve_items(floor_config: FloorConfig) -> Array[ItemConfig]:
	var catalogue := _item_catalogue(floor_config)
	var resolved: Array[ItemConfig] = []
	for id: StringName in item_ids:
		var item: ItemConfig = catalogue.get(id)
		if item != null:
			resolved.append(item)
	return resolved


## One line for the menu entry that offers the run back. Deliberately says how far in it is
## rather than how long ago it was written: "floor 4, eighteen minutes" is what a player
## recognises their own run by.
func describe() -> String:
	return "FLOOR %d  //  %s" % [floor_number, RunStats.format_duration(stats.duration)]


func _validate_identity(problems: PackedStringArray, campaign: RunDefinition) -> void:
	if campaign_id != campaign.id:
		problems.append(
			"it was recorded against campaign '%s', not '%s'" % [campaign_id, campaign.id]
		)
	if content_version != campaign.content_version:
		# Refused rather than played, and this is the case most likely to look like an
		# over-reaction. It is not: the seed is what rebuilds the floor, the content is what the
		# seed is spent on, and a campaign edited since the checkpoint was written would rebuild a
		# floor the run never played — different rooms, possibly a different boss — while claiming
		# to be the same run. A lost checkpoint after a content update is a cost; a run that
		# silently stops being reproducible is a bug nobody can file.
		problems.append(
			"it was recorded against content version %d, and the campaign is now version %d"
			% [content_version, campaign.content_version]
		)
	if campaign.index_of(floor_id) < 0:
		problems.append("campaign '%s' has no floor '%s'" % [campaign.id, floor_id])

	if stats.run_seed != run_seed:
		problems.append("its statistics record seed %d, not %d" % [stats.run_seed, run_seed])
	if stats.campaign_id != campaign_id:
		problems.append("its statistics record campaign '%s', not '%s'" % [stats.campaign_id, campaign_id])
	if stats.rooms_cleared != rooms_cleared:
		problems.append(
			"it has cleared %d rooms and its statistics say %d" % [rooms_cleared, stats.rooms_cleared]
		)

	# The invariant that makes this a *boundary* checkpoint. It is written just after a floor was
	# opened, so the last record is that floor's and it is still open. A closed last record means
	# the file was written somewhere else in the run's life, and nothing downstream is prepared for
	# that: the floor would be entered a second time and recorded twice.
	var open_floor := stats.current_floor()
	if open_floor == null:
		problems.append("its statistics have no floor open, so it was not taken at a boundary")
	elif open_floor.floor_id != floor_id:
		problems.append(
			"its open floor record is '%s' and the checkpoint is on '%s'"
			% [open_floor.floor_id, floor_id]
		)


func _validate_numbers(problems: PackedStringArray) -> void:
	if run_seed < 0:
		problems.append("its seed is negative (%d)" % run_seed)
	if floor_number < 1:
		problems.append("its floor number is %d" % floor_number)
	# Zero integrity is a destroyed robot, and a run that ended is not a run to resume.
	if integrity <= 0.0 or integrity > MAX_INTEGRITY:
		problems.append("its integrity is %.2f" % integrity)
	if max_integrity_penalty < 0.0 or max_integrity_penalty > MAX_INTEGRITY:
		problems.append("its integrity penalty is %.2f" % max_integrity_penalty)
	if scrap < 0 or scrap > MAX_SCRAP:
		problems.append("its scrap is %d" % scrap)
	if rooms_cleared < 0 or rooms_cleared > MAX_ROOMS_CLEARED:
		problems.append("its cleared-room count is %d" % rooms_cleared)
	if death_saves_spent < 0 or death_saves_spent > MAX_DEATH_SAVES:
		problems.append("its spent death saves are %d" % death_saves_spent)
	# Below one is an impossible discount rather than a small penalty, and the ceiling is the one
	# `RunManager` enforces — a file claiming more has been hand-edited past the cap that exists to
	# keep a six-floor run winnable.
	if enemy_health_scale < 1.0 or enemy_health_scale > RunManager.MAX_ENEMY_HEALTH_SCALE:
		problems.append("its enemy health scale is %.2f" % enemy_health_scale)
	if stats.duration < 0.0 or stats.duration > MAX_DURATION_SECONDS:
		problems.append("its duration is %.0f seconds" % stats.duration)


func _validate_collections(problems: PackedStringArray) -> void:
	_validate_id_list(problems, item_ids, "held items", MAX_ITEMS)
	_validate_id_list(problems, offered_item_ids, "offered items", MAX_OFFERED_ITEMS)
	_validate_id_list(problems, fought_boss_ids, "fought bosses", MAX_BOSSES)

	if stats.floors.size() > MAX_FLOOR_RECORDS:
		problems.append("it holds %d floor records" % stats.floors.size())

	# The offered list is a set — `RunManager.draw_item` appends an id once and `release_item`
	# removes it — and a duplicate in it would be an item struck off the run twice.
	var seen_offers: Dictionary[StringName, bool] = {}
	for id: StringName in offered_item_ids:
		if seen_offers.has(id):
			problems.append("item '%s' appears twice in its offered list" % id)
			break
		seen_offers[id] = true

	# One distinct boss per floor is the campaign policy, and `FloorController._draw_boss_encounter`
	# refuses to repeat one. A duplicate here is a file that has been edited.
	var seen_bosses: Dictionary[StringName, bool] = {}
	for id: StringName in fought_boss_ids:
		if seen_bosses.has(id):
			problems.append("boss '%s' appears twice in its fought list" % id)
			break
		seen_bosses[id] = true


func _validate_id_list(
	problems: PackedStringArray, ids: Array[StringName], label: String, limit: int
) -> void:
	if ids.size() > limit:
		problems.append("it holds %d %s, over the limit of %d" % [ids.size(), label, limit])
	for id: StringName in ids:
		if id.is_empty():
			problems.append("its %s include an empty id" % label)
			return
		if String(id).length() > MAX_ID_LENGTH:
			problems.append("its %s include an id of %d characters" % [label, String(id).length()])
			return


## Every held and offered item has to name something the game still has, and the build has to be
## one the inventory would actually have accepted: `ItemInventory.add` refuses a copy beyond an
## item's `max_stacks`, so a file holding four of a unique is a file that was edited.
func _validate_items(problems: PackedStringArray, floor_config: FloorConfig) -> void:
	var catalogue := _item_catalogue(floor_config)

	var counts: Dictionary[StringName, int] = {}
	for id: StringName in item_ids:
		var item: ItemConfig = catalogue.get(id)
		if item == null:
			problems.append("it holds item '%s', which floor '%s' does not offer" % [id, floor_id])
			continue
		counts[id] = counts.get(id, 0) + 1
		if counts[id] > maxi(item.max_stacks, 1):
			problems.append(
				"it holds %d of '%s', which stacks %d times" % [counts[id], id, maxi(item.max_stacks, 1)]
			)

	for id: StringName in offered_item_ids:
		if not catalogue.has(id):
			problems.append("it has spent item '%s', which floor '%s' does not offer" % [id, floor_id])


func _item_catalogue(floor_config: FloorConfig) -> Dictionary[StringName, ItemConfig]:
	var catalogue: Dictionary[StringName, ItemConfig] = {}
	if floor_config == null or floor_config.item_pool == null:
		return catalogue
	for item: ItemConfig in floor_config.item_pool.items:
		if item != null and not item.id.is_empty():
			catalogue[item.id] = item
	return catalogue


func _names_to_strings(names: Array[StringName]) -> Array:
	var strings: Array = []
	for id: StringName in names:
		strings.append(String(id))
	return strings


static func _strings_to_names(value: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if not (value is Array):
		return names
	for entry: Variant in value as Array:
		if entry is String:
			names.append(StringName(entry))
	return names

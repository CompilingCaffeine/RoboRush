class_name RunManifest
extends RefCounted
## What a run seed will actually build, in one table.
##
## A seed on its own does not identify a run. The content it was drawn against does too: the same
## `--seed=971330958` builds a different floor 3 the day somebody adds a combat template to it, and
## nothing about the seed says so. `RunDefinition.content_version` is the coarse answer to that — it
## is bumped when a change stops old seeds reproducing — and it is only as honest as whoever
## remembered to bump it.
##
## The manifest is the fine answer. Each floor is reduced to a fingerprint of the content generation
## will actually spend its seed on: the eligible templates, the boss pool, the item pool, the room
## count, the theme's tracks. Two builds that agree on a floor's fingerprint will build the same
## floor from the same seed; two that do not, will not, and the fingerprint says which floor changed
## without anybody diffing six resources by hand.
##
## Three things use it. A bug report can carry `--manifest` output alongside the seed, so a floor
## that no longer reproduces is a content change rather than a mystery. `--floor=4` can be checked
## against a real arrival — the acceptance criterion for the debug shortcut is that both routes agree
## on floor 4's seed *and* its content, and the fingerprint is the only compact way to state the
## second half. And the debug overlay can show the current floor's fingerprint, which is what turns a
## screenshot into something reproducible.
##
## `build` loads every floor in the campaign, which is exactly what the floor catalog exists to
## avoid during play (see `FloorEntry`). That is fine and deliberate: this is a debugging tool, run
## at boot behind a flag or from a test, never during a descent. Per-floor callers that already hold
## a `FloorConfig` should use `row_for` and load nothing.

## How many hex digits a fingerprint is written as. Eight is the whole 32-bit mixer output — short
## enough to read out over a bug report, wide enough that two different floors colliding is not
## something anybody will meet.
const FINGERPRINT_DIGITS := 8


## Every floor of `campaign`, in order, as it would be built by a run opening on `run_seed`.
static func build(campaign: RunDefinition, run_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if campaign == null:
		return rows
	for index: int in campaign.size():
		rows.append(floor_row(campaign, run_seed, index))
	return rows


## One floor of `campaign`. Loads that floor's content and nothing else.
##
## A row for a floor the campaign does not contain, or whose content will not load, is still a row —
## with an empty fingerprint and whatever the campaign could tell us. A manifest that refused to
## describe a broken campaign would be useless for the case it is most wanted in.
static func floor_row(campaign: RunDefinition, run_seed: int, index: int) -> Dictionary:
	var entry := campaign.entry_at(index) if campaign != null else null
	if entry == null:
		return {
			"index": index,
			"floor_number": index + 1,
			"id": &"",
			"path": "",
			"seed": 0,
			"streams": {} as Dictionary[StringName, int],
			"fingerprint": "",
		}

	var seed_value := campaign.floor_seed_for(run_seed, index)
	var row := row_for(entry.load_config(), index, entry.id, seed_value)
	row["path"] = entry.config_path
	return row


## One floor from content already in hand, so a caller holding a `FloorConfig` — the floor
## controller does — describes itself without loading anything.
##
## `floor_id` is passed in rather than read off the config because the campaign's id for a floor is
## the authoritative one; `CampaignValidator` refuses a campaign where the two disagree, and a
## manifest built from the wrong half would agree with itself while describing the wrong floor.
static func row_for(
	config: FloorConfig, index: int, floor_id: StringName, seed_value: int
) -> Dictionary:
	var row: Dictionary = {
		"index": index,
		"floor_number": config.floor_number if config != null else index + 1,
		"id": floor_id,
		"path": "",
		"seed": seed_value,
		"streams": RunRng.stream_seeds(seed_value),
		"rooms": config.room_count if config != null else 0,
		"bosses": _boss_ids(config),
		"items": config.get_items().size() if config != null else 0,
		"fingerprint": _fingerprint_of(config, floor_id, seed_value),
	}
	return row


## One value for the whole campaign as seen from `run_seed`: every floor's fingerprint folded
## together. What two builds compare when the question is "are we running the same campaign at all".
static func fingerprint(campaign: RunDefinition, run_seed: int) -> String:
	if campaign == null:
		return ""
	var value := RunRng.DIGEST_START
	value = RunRng.fold_text(value, campaign.id)
	value = RunRng.fold_int(value, campaign.content_version)
	for row: Dictionary in build(campaign, run_seed):
		value = RunRng.fold_text(value, row["fingerprint"])
	return _hex(RunRng.seal(value))


## The whole manifest as text, one floor per line, for a log or a test failure message.
static func describe(campaign: RunDefinition, run_seed: int) -> String:
	if campaign == null:
		return "no campaign"

	var lines: PackedStringArray = ["campaign '%s' v%d  seed %d  manifest %s" % [
		campaign.id, campaign.content_version, run_seed, fingerprint(campaign, run_seed),
	]]
	for row: Dictionary in build(campaign, run_seed):
		lines.append(describe_row(row))
	return "\n".join(lines)


## One floor as text. Deliberately fixed-width in its leading columns so six of them read as a
## table in a terminal that has no idea it is printing one.
static func describe_row(row: Dictionary) -> String:
	var bosses: Array[StringName] = row.get("bosses", [] as Array[StringName])
	var names := PackedStringArray()
	for boss_id: StringName in bosses:
		names.append(String(boss_id))

	# Dashes rather than a blank for a floor that would not load, so a broken row is visibly a
	# broken row instead of a column that looks like it wrapped.
	var digest: String = row.get("fingerprint", "")
	if digest.is_empty():
		digest = "-".repeat(FINGERPRINT_DIGITS)

	return "  floor %d  %-16s seed %-11d %s  %d rooms  %d items  boss %s" % [
		row.get("floor_number", 0),
		row.get("id", &""),
		row.get("seed", 0),
		digest,
		row.get("rooms", 0),
		row.get("items", 0),
		"/".join(names) if names.size() > 0 else "none",
	]


static func _boss_ids(config: FloorConfig) -> Array[StringName]:
	var ids: Array[StringName] = []
	if config == null:
		return ids
	for encounter: BossEncounter in config.boss_pool:
		if encounter != null:
			ids.append(encounter.id)
	return ids


## Folds everything about a floor that changes what its seed builds, in the order the floor declares
## it. Declared order rather than sorted, because order is not cosmetic here: the generator draws
## `pool[rng.randi_range(...)]`, so swapping two templates in a `.tres` changes which one a seed
## picks. A fingerprint that ignored order would call two builds identical while they generated
## different floors, which is the one thing it must never do.
##
## The seed is folded in too, so a row identifies "this floor from this seed" rather than "this
## floor". Comparing two routes to floor 4 is comparing both halves at once, which is what the
## direct-start criterion actually asks for.
static func _fingerprint_of(config: FloorConfig, floor_id: StringName, seed_value: int) -> String:
	if config == null:
		return ""

	var value := RunRng.fold_text(RunRng.DIGEST_START, floor_id)
	value = RunRng.fold_int(value, seed_value)
	value = RunRng.fold_int(value, config.floor_number)
	value = RunRng.fold_int(value, config.room_count)
	value = RunRng.fold_int(value, 1 if config.treasure_grants_item else 0)
	value = RunRng.fold_int(value, config.clear_scrap_range.x)
	value = RunRng.fold_int(value, config.clear_scrap_range.y)
	value = RunRng.fold_int(value, config.enemy_scrap_range.x)
	value = RunRng.fold_int(value, config.enemy_scrap_range.y)

	for clear_index: int in config.item_clear_indices:
		value = RunRng.fold_int(value, clear_index)
	for tag: StringName in config.floor_tags:
		value = RunRng.fold_text(value, tag)

	# Eligible templates rather than every authored one: eligibility is floor-number and tag
	# dependent, so the set this floor can actually draw from is the set that decides its layout.
	for type: RoomTemplate.Type in RoomTemplate.Type.values():
		value = RunRng.fold_int(value, type)
		for template: RoomTemplate in config.templates_for(type):
			value = RunRng.fold_text(value, template.id)
			value = RunRng.fold_int(value, template.difficulty)

	for encounter: BossEncounter in config.boss_pool:
		if encounter != null:
			value = RunRng.fold_text(value, encounter.id)

	for spawn: EnemySpawn in config.enemy_spawns:
		if spawn == null:
			continue
		value = RunRng.fold_text(value, spawn.scene.resource_path if spawn.scene != null else &"")
		value = RunRng.fold_int(value, roundi(spawn.weight * 1000.0))
		value = RunRng.fold_int(value, spawn.min_difficulty)

	for item: ItemConfig in config.get_items():
		if item != null:
			value = RunRng.fold_text(value, item.id)

	if config.shop != null:
		value = RunRng.fold_int(value, config.shop.item_stand_count)
	if config.theme != null:
		value = RunRng.fold_text(value, config.theme.explore_music)
		value = RunRng.fold_text(value, config.theme.boss_music)

	return _hex(RunRng.seal(value))


static func _hex(value: int) -> String:
	return String.num_int64(value, 16).lpad(FINGERPRINT_DIGITS, "0")

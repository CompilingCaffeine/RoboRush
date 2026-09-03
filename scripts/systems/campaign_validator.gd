class_name CampaignValidator
extends RefCounted
## Checks a `RunDefinition` and everything it names, before a run starts.
##
## Separate from `RunDefinition` for the reason `FloorGenerator` is separate from `FloorConfig`:
## one describes the campaign, the other decides whether it is playable. Keeping the rules out of
## the resource means the rules can be strict without a half-authored floor becoming impossible
## to open in the editor.
##
## Everything this checks is something that currently fails *silently* or fails too late.
## `FloorGenerator` already refuses a floor with no eligible template — but it refuses it at the
## moment the player descends into it, after the floor they were on has been torn down, which
## turns a content typo into a run that ends in an empty world. A pool too small to fill the
## offers a campaign asks for does not error at all: `RunManager.draw_item` returns null, every
## caller has a graceful fallback, and the run just quietly stops handing out items. Both are
## cheap to detect from the data alone, and neither is discoverable by playing until the specific
## floor and the specific seed line up.
##
## Two severities, and the split is deliberate. An **error** is content that cannot be played:
## the run must not start. A **warning** is content that will play and is probably not what
## anybody meant — a campaign three floors short of the length it declares, or four floors
## sharing two bosses. Warnings are what let the campaign be validated strictly while it is
## still being written, instead of the validator being switched off until the last floor lands.

## The outcome of validating one campaign: what is fatal, what is merely suspicious, and enough
## detail in each line to fix it without opening the resource to guess which floor was meant.
class Report extends RefCounted:
	## Content that cannot be played. A run must not start while this is non-empty.
	var errors: PackedStringArray = []

	## Content that plays but is probably unintended.
	var warnings: PackedStringArray = []

	func is_valid() -> bool:
		return errors.is_empty()

	func error(message: String) -> void:
		errors.append(message)

	func warn(message: String) -> void:
		warnings.append(message)

	## Every line, one per row, errors first. For a log or a test failure message.
	func describe() -> String:
		var lines: PackedStringArray = []
		for message: String in errors:
			lines.append("ERROR   %s" % message)
		for message: String in warnings:
			lines.append("WARNING %s" % message)
		return "\n".join(lines) if not lines.is_empty() else "campaign is valid"


## Room types every floor must be able to fill. Ordered as the player meets them, so a floor
## missing several reports them in an order that reads like a floor.
const REQUIRED_ROOM_TYPES: Array[RoomTemplate.Type] = [
	RoomTemplate.Type.START,
	RoomTemplate.Type.COMBAT,
	RoomTemplate.Type.TREASURE,
	RoomTemplate.Type.SHOP,
	RoomTemplate.Type.BOSS,
]


## Validates `campaign` and everything it names. Never returns null, and never pushes anything
## itself — reporting is the caller's business, because the same check runs at boot (where it
## belongs in the log) and in the suite (where it belongs in a failure message).
static func validate(campaign: RunDefinition) -> Report:
	var report := Report.new()
	if campaign == null:
		report.error("no campaign resource: nothing declares which floors a run is made of.")
		return report

	if campaign.id.is_empty():
		report.error("the campaign has no id.")
	if campaign.floors.is_empty():
		report.error("the campaign declares no floors.")
		return report

	_validate_length(report, campaign)

	# Indexed alongside `campaign.floors`, with a null wherever a floor could not be loaded, so
	# the campaign-wide checks below can still see which floors *did* resolve without every one
	# of them re-deriving the mapping from list position to floor.
	var configs: Array[FloorConfig] = []
	configs.resize(campaign.floors.size())

	var ids_seen: Dictionary[StringName, int] = {}
	var paths_seen: Dictionary[String, int] = {}

	for index: int in campaign.floors.size():
		var entry := campaign.floors[index]
		var where := "floor %d" % (index + 1)

		if entry == null:
			report.error("%s has no entry: the campaign has a hole in it at position %d."
				% [where, index])
			continue
		if entry.id.is_empty():
			report.error("%s has no id." % where)
		elif ids_seen.has(entry.id):
			report.error("%s reuses the floor id '%s', already used by floor %d."
				% [where, entry.id, ids_seen[entry.id] + 1])
		else:
			ids_seen[entry.id] = index

		if entry.config_path.is_empty():
			report.error("%s ('%s') names no config path." % [where, entry.id])
			continue
		if not ResourceLoader.exists(entry.config_path):
			report.error("%s ('%s') points at %s, which does not exist."
				% [where, entry.id, entry.config_path])
			continue
		if paths_seen.has(entry.config_path):
			report.error("%s ('%s') is the same content as floor %d (%s)."
				% [where, entry.id, paths_seen[entry.config_path] + 1, entry.config_path])
		else:
			paths_seen[entry.config_path] = index

		var config := entry.load_config()
		if config == null:
			report.error("%s ('%s') points at %s, which is not a FloorConfig."
				% [where, entry.id, entry.config_path])
			continue

		configs[index] = config
		_validate_floor(report, index, entry, config)

	_validate_reward_capacity(report, configs)
	_validate_boss_supply(report, configs)
	return report


## How many item offers one floor promises to fill, counted the way `FloorController` actually
## spends them: the combat clears that drop an item, the treasure room, the shop's item stands,
## and the boss's choice of three. The one number the shared pool has to be big enough for.
static func offers_required(config: FloorConfig) -> int:
	if config == null:
		return 0
	var offers := config.item_clear_indices.size() + FloorController.BOSS_REWARD_COUNT
	if config.treasure_grants_item:
		offers += 1
	if config.shop != null:
		offers += maxi(config.shop.item_stand_count, 0)
	return offers


## How long the campaign is against how long it says it will be.
##
## Overshooting is always an error — a seventh floor in a six-floor campaign is a floor somebody
## added without deciding it was there. Falling short is a warning until `require_complete` says
## otherwise, which is what lets a two-floor campaign that intends to be six be validated as
## strictly as a finished one without refusing to start.
static func _validate_length(report: Report, campaign: RunDefinition) -> void:
	var declared := campaign.floors.size()
	var target := campaign.target_floor_count
	if declared == target:
		return

	if declared > target:
		report.error("the campaign lists %d floors but targets %d." % [declared, target])
		return

	# Named without the campaign's own id, here and everywhere below: the caller reporting these
	# already knows which campaign it validated, and saying so twice is how the boot log ends up
	# reading "Campaign 'main_campaign': campaign 'main_campaign' lists...".
	var message := "the campaign lists %d of its %d floors; floors %d-%d are missing." % [
		declared, target, declared + 1, target,
	]
	if target - declared == 1:
		message = "the campaign lists %d of its %d floors; floor %d is missing." % [
			declared, target, target,
		]
	if campaign.require_complete:
		report.error(message)
	else:
		report.warn(message)


static func _validate_floor(
	report: Report, index: int, entry: FloorEntry, config: FloorConfig
) -> void:
	var where := "floor %d ('%s')" % [index + 1, entry.id]

	if config.id != entry.id:
		report.error("%s is listed under that id but calls itself '%s'." % [where, config.id])
	if config.floor_number != index + 1:
		report.error("%s sits at position %d but reports floor_number %d."
			% [where, index + 1, config.floor_number])

	_validate_floor_rooms(report, where, config)
	_validate_floor_population(report, where, config)
	_validate_floor_rewards(report, where, config)
	_validate_floor_presentation(report, where, config)


static func _validate_floor_rooms(report: Report, where: String, config: FloorConfig) -> void:
	# The generator's own floor, asked for rather than restated: a start, a boss, a treasure, and
	# a shop. Restating it as a literal here is how the two drift apart the day a fifth special
	# room is added.
	var minimum := FloorGenerator.SPECIAL_TYPES.size() + 1
	if config.room_count < minimum:
		report.error("%s asks for %d rooms; the generator needs at least %d."
			% [where, config.room_count, minimum])

	for type: RoomTemplate.Type in REQUIRED_ROOM_TYPES:
		if config.templates_for(type).is_empty():
			report.error(
				("%s has no eligible %s template. A template is eligible when the floor's number "
				+ "is within its min_floor/max_floor and it shares one of the floor's tags.")
				% [where, RoomTemplate.Type.keys()[type]]
			)


static func _validate_floor_population(report: Report, where: String, config: FloorConfig) -> void:
	if config.enemy_spawns.is_empty():
		report.error("%s has no enemy roster." % where)
		return

	var scenes := 0
	for spawn: EnemySpawn in config.enemy_spawns:
		if spawn == null or spawn.scene == null:
			report.error("%s has a roster entry with no scene." % where)
			continue
		if spawn.weight <= 0.0:
			report.warn("%s rosters an enemy at weight %.2f, so it can never be drawn."
				% [where, spawn.weight])
		scenes += 1
	if scenes == 0:
		return

	# Every difficulty the floor's own combat templates actually use has to have something that
	# may spawn in it. A roster that starts at difficulty 2 on a floor whose easiest room is
	# difficulty 1 produces an empty combat room, which reads as a bug in the generator and is a
	# bug in the roster.
	var difficulties: Dictionary[int, bool] = {}
	for template: RoomTemplate in config.templates_for(RoomTemplate.Type.COMBAT):
		difficulties[template.difficulty] = true
	for difficulty: int in difficulties:
		var eligible := false
		for spawn: EnemySpawn in config.enemy_spawns:
			if spawn != null and spawn.is_eligible(difficulty) and spawn.weight > 0.0:
				eligible = true
				break
		if not eligible:
			report.error("%s has no enemy that may spawn in a difficulty-%d room, and has one."
				% [where, difficulty])


static func _validate_floor_rewards(report: Report, where: String, config: FloorConfig) -> void:
	if config.shop == null:
		report.error("%s has no shop prices." % where)
	elif config.shop.item_prices.is_empty():
		report.error("%s has a shop with no prices, so everything in it is free." % where)

	if config.item_pool == null or config.item_pool.items.is_empty():
		report.error("%s has no item pool." % where)
	else:
		var item_ids: Dictionary[StringName, bool] = {}
		for item: ItemConfig in config.item_pool.items:
			if item == null:
				report.error("%s has a null entry in its item pool." % where)
				continue
			if item_ids.has(item.id):
				# Ids are how a run remembers what it has already offered, so a duplicate is an
				# item that vanishes from the pool the first time either copy is drawn.
				report.error("%s's item pool holds two items with the id '%s'." % [where, item.id])
			item_ids[item.id] = true

	for pair: Array in [
		["clear_scrap_range", config.clear_scrap_range],
		["enemy_scrap_range", config.enemy_scrap_range],
	]:
		var range_value: Vector2i = pair[1]
		if range_value.x < 0 or range_value.y < range_value.x:
			report.error("%s has an inverted or negative %s (%s)." % [where, pair[0], range_value])

	# Item drops are keyed to which combat clear it is, and a floor only has so many combat rooms
	# — the rest of its room count is the start room and the three special rooms. An index past
	# that is an item the floor promises and never hands over.
	var combat_rooms := config.room_count - FloorGenerator.SPECIAL_TYPES.size() - 1
	var seen: Dictionary[int, bool] = {}
	for clear_index: int in config.item_clear_indices:
		if clear_index < 1:
			report.error("%s drops an item on clear %d; clears are counted from one."
				% [where, clear_index])
		elif clear_index > combat_rooms:
			report.error("%s drops an item on clear %d but has only %d combat rooms."
				% [where, clear_index, combat_rooms])
		if seen.has(clear_index):
			report.error("%s lists clear %d twice; the second one never drops."
				% [where, clear_index])
		seen[clear_index] = true


static func _validate_floor_presentation(report: Report, where: String, config: FloorConfig) -> void:
	if config.boss_pool.is_empty():
		report.error("%s has no boss." % where)
	else:
		var pool_ids: Dictionary[StringName, bool] = {}
		for encounter: BossEncounter in config.boss_pool:
			if encounter == null or not encounter.is_valid():
				report.error("%s has a boss pool entry with no scene." % where)
				continue
			if encounter.id.is_empty():
				report.error("%s has a boss with no id." % where)
			elif pool_ids.has(encounter.id):
				report.error("%s lists the boss '%s' twice." % [where, encounter.id])
			pool_ids[encounter.id] = true

	if config.theme == null:
		# Not an error: `FloorConfig.theme` is documented as optional so a greybox floor renders
		# before it has a look. It is still worth saying out loud, because the symptom is a floor
		# that silently wears the floor before it.
		report.warn("%s has no theme, so it renders and sounds like the default." % where)
		return

	for pair: Array in [
		["explore_music", config.theme.explore_music],
		["boss_music", config.theme.boss_music],
	]:
		var track: StringName = pair[1]
		if track.is_empty():
			report.error("%s's theme names no %s." % [where, pair[0]])
		elif not AudioManager.MUSIC_LIBRARY.has(track):
			report.error("%s's theme asks for the %s track '%s', which is not in the library."
				% [where, pair[0], track])


## Whether the campaign has enough items to fill every offer it promises.
##
## Simulated floor by floor against one shared reservation list, because that is how a run spends
## the pool: `RunManager.offered_item_ids` is run-scoped, so an item handed out on floor 1 is gone
## for floor 5. Checking each floor against the pool in isolation would pass a six-floor campaign
## that runs dry after floor 2 — which is exactly the state the campaign is in.
##
## Fatal rather than a warning. An unfilled offer is a treasure room with a repair cell in it and
## a boss offering two choices instead of three, and nothing in the game reports it.
static func _validate_reward_capacity(report: Report, configs: Array[FloorConfig]) -> void:
	var spent: Dictionary[StringName, bool] = {}
	for index: int in configs.size():
		var config := configs[index]
		if config == null or config.item_pool == null:
			continue

		# Repeatables are never spent — that is what makes them repeatable — so they are counted
		# as a floor under the economy rather than as stock. A pool holding even one of them can
		# always fill an offer, which turns "the run hands out nothing" into "the run hands out
		# something smaller", and only the first of those is fatal.
		var uniques_left: Array[StringName] = []
		var repeatables := 0
		for item: ItemConfig in config.item_pool.items:
			if item == null:
				continue
			if item.is_repeatable():
				repeatables += 1
			elif not spent.has(item.id):
				uniques_left.append(item.id)

		var needed := offers_required(config)
		var shortfall := needed - uniques_left.size()
		if shortfall > 0:
			if repeatables > 0:
				report.warn(
					("floor %d fills %d of its %d offers from repeatable items: the campaign's "
					+ "one-time items are spent by the time a run reaches it.")
					% [index + 1, shortfall, needed]
				)
			else:
				report.error(
					("floor %d promises %d item offers but only %d unspent items are left in its "
					+ "pool by the time a run reaches it, and the pool has no repeatable item to "
					+ "fall back on, so %d offers come up empty.")
					% [index + 1, needed, uniques_left.size(), shortfall]
				)

		for offset: int in mini(needed, uniques_left.size()):
			spent[uniques_left[offset]] = true


## Whether every floor can be given a boss of its own.
##
## The campaign policy is one distinct boss per floor, so this is an error rather than a warning.
## It used to be a warning, because `FloorController._draw_boss_encounter` fell back to the whole
## pool once everything had been fought and a short supply therefore still played — it just
## repeated fights without anybody having decided to. That fallback is gone: a floor with nothing
## unfought left to draw now refuses, so a campaign that cannot supply six distinct bosses is a
## campaign that breaks at floor 3, and it must not start.
##
## Counting distinct bosses is not sufficient, and the difference matters as soon as floors have
## curated pools. Six bosses across six floors can still strand a floor whose own pool holds only
## bosses that earlier floors must take. The real question is whether a *perfect matching* exists
## between floors and bosses, which is Hall's condition: every set of floors must, between them,
## name at least as many distinct bosses as there are floors in the set. Checked over every subset,
## which is 63 of them for six floors and free.
static func _validate_boss_supply(report: Report, configs: Array[FloorConfig]) -> void:
	var pools: Array[Dictionary] = []
	var indices: Array[int] = []
	for index: int in configs.size():
		var config := configs[index]
		if config == null:
			continue
		var ids: Dictionary[StringName, bool] = {}
		for encounter: BossEncounter in config.boss_pool:
			if encounter != null and encounter.is_valid() and not encounter.id.is_empty():
				ids[encounter.id] = true
		pools.append(ids)
		indices.append(index)

	if pools.is_empty():
		return

	# Too many subsets to enumerate is a campaign far longer than six floors; the per-floor checks
	# have already reported anything structural, and an exponential sweep is not worth running.
	if pools.size() > 16:
		return

	for mask: int in range(1, 1 << pools.size()):
		var union: Dictionary[StringName, bool] = {}
		var members: Array[int] = []
		for slot: int in pools.size():
			if mask & (1 << slot) == 0:
				continue
			members.append(indices[slot] + 1)
			for boss_id: StringName in pools[slot]:
				union[boss_id] = true

		if union.size() >= members.size():
			continue

		# Reported at the first shortfall rather than for all 63 subsets: the smallest failing set
		# is the one that names the actual problem, and every superset of it fails too.
		var floors_named := "floor %d" % members[0] if members.size() == 1 else "floors %s" % str(members)
		report.error(
			("%s can draw from only %d distinct bosses between them, so they cannot each be "
			+ "given one of their own. The campaign needs a distinct boss per floor.")
			% [floors_named, union.size()]
		)
		return

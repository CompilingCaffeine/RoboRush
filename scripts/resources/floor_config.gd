class_name FloorConfig
extends Resource
## One floor of the megacorporation, as data. Spec section 8's Floor 1: Help Desk.
##
## Holds what the floor is made of, not how it is assembled — FloorGenerator owns the
## graph, this owns the parts list. Adding Floor 2 should be a new .tres, not new code.
##
## What it deliberately does not hold is where it sits in the run. A floor used to name the floor
## after it, which made the run's order a chain that could only be read by walking it; that order
## is now `RunDefinition`, and a floor knows only its own id and number. Nothing here should ever
## answer "what comes next" again — a floor that knew would be a second campaign order, and the
## way two orders fail is one of them being edited.

## Stable identifier, and the name every other piece of data refers to this floor by: the
## campaign lists it (`FloorEntry.id`), `--floor=` accepts it, and a checkpoint or a run result
## records it. Must never change once it ships, for the reason `ItemConfig.id` must not — unlike
## `display_name`, which is free to be reworded, and unlike `floor_number`, which is a position
## and moves when a floor is inserted before this one.
@export var id: StringName = &"unnamed_floor"

@export var display_name: String = "Help Desk"

## Where this floor sits in the run, counted from one. A statement of position that
## `CampaignValidator` holds to the campaign's own order — it is read by content eligibility
## (`RoomTemplate.min_floor`/`max_floor`) and shown to the player, and a floor whose number
## disagreed with where it actually is would draw the wrong rooms under the right banner.
@export var floor_number: int = 1

## Tags used to filter which room templates may appear here.
@export var floor_tags: Array[StringName] = [&"help_desk"]

## How this floor looks and sounds. Null falls back to the textures authored into
## `room.tscn` and `wall_block.tscn` and to the shared `explore`/`boss` tracks, so a floor
## built without one still renders — which is what keeps a test arena and a greybox floor
## from needing a theme before they need a look.
@export var theme: FloorTheme

@export_group("Rooms")

## Total rooms including the start and the treasure room. Spec section 9 suggests a start,
## four to six combat rooms, and a treasure room for the first prototype.
@export var room_count: int = 7

@export var start_templates: Array[RoomTemplate] = []
@export var combat_templates: Array[RoomTemplate] = []
@export var treasure_templates: Array[RoomTemplate] = []
@export var shop_templates: Array[RoomTemplate] = []
@export var boss_templates: Array[RoomTemplate] = []

@export_group("Boss")

## Which bosses this floor's boss room may spawn. One is drawn per floor, avoiding any this
## run has already fought — see `FloorController._draw_boss_encounter`.
##
## A pool rather than a single boss, and a `BossEncounter` rather than four parallel fields,
## because either boss can now guard either floor. Four fields cannot be shuffled together,
## and the failure mode of them drifting apart is a bug this project has already shipped once:
## the HUD announcing The Scrap King's lines over the second floor's boss.
##
## Every floor listing the same two entries is deliberate. It is what makes "either boss could
## be on either level" true, and a floor that wants a fixed boss still says so by naming one
## entry.
@export var boss_pool: Array[BossEncounter] = []

@export_group("Population")

## Enemies that may appear on this floor, with their weights and how early they unlock.
## One is chosen per spawn point in the template.
@export var enemy_spawns: Array[EnemySpawn] = []

@export_group("Rewards")

## Scrap dropped when a combat room is cleared, as an inclusive range.
@export var clear_scrap_range := Vector2i(2, 4)

## Scrap dropped by each enemy killed.
@export var enemy_scrap_range := Vector2i(1, 2)

@export_group("Shop")

## Spec section 17's prices. Shared across floors, so this points at one resource rather
## than restating the numbers.
@export var shop: ShopConfig

@export_group("Items")

## Items that may drop on this floor. Drawn without repetition within a run.
##
## A shared `ItemPool` rather than a per-floor array. It was per-floor, and the result was
## that Development's nine items could only ever be found on Development — the Help Desk's
## pool listed the original twelve and nothing else, so half the game's items were invisible
## for the whole first floor. Pointing every floor at one pool is what makes "any item can
## drop on any level" true by construction rather than by two lists agreeing.
##
## Floors may still differ here. Nothing stops a later floor naming a pool of its own; what
## is gone is the *accident* of differing because two lists were edited at different times.
@export var item_pool: ItemPool

## Which combat-room clears drop an item, counted from one. `[1, 3, 5]` means the first,
## third, and fifth room the player clears.
##
## A list rather than "every Nth clear" because the interesting number is not the interval,
## it is *how many items a run hands out and how early the first one lands* — and both of
## those are legible here and invisible in a modulo.
@export var item_clear_indices: Array[int] = [2, 5]

## Whether the treasure room hands over an item. Spec section 9 says a treasure room
## contains one; this exists so a floor built around a shop instead can say otherwise.
@export var treasure_grants_item: bool = true


## Picks one enemy scene for a room of the given difficulty, or null when the roster has
## nothing that early. Weighted, so a floor can lean on its signature enemy without
## excluding the rest.
func pick_enemy(difficulty: int, rng: RandomNumberGenerator) -> PackedScene:
	var eligible: Array[EnemySpawn] = []
	var total := 0.0
	for spawn: EnemySpawn in enemy_spawns:
		if spawn != null and spawn.is_eligible(difficulty) and spawn.weight > 0.0:
			eligible.append(spawn)
			total += spawn.weight

	if eligible.is_empty():
		return null

	var roll := rng.randf() * total
	for spawn: EnemySpawn in eligible:
		roll -= spawn.weight
		if roll <= 0.0:
			return spawn.scene
	# Float error only; the last eligible entry is the correct answer.
	return eligible[eligible.size() - 1].scene


## Templates eligible for a room type on this floor. Returns an empty array if none match,
## which the generator reports rather than silently producing an empty room.
func templates_for(type: RoomTemplate.Type) -> Array[RoomTemplate]:
	var pool: Array[RoomTemplate] = []
	match type:
		RoomTemplate.Type.START:
			pool = start_templates
		RoomTemplate.Type.TREASURE:
			pool = treasure_templates
		RoomTemplate.Type.SHOP:
			pool = shop_templates
		RoomTemplate.Type.BOSS:
			pool = boss_templates
		_:
			pool = combat_templates

	var eligible: Array[RoomTemplate] = []
	for template: RoomTemplate in pool:
		if template != null and template.is_eligible(floor_number, floor_tags):
			eligible.append(template)
	return eligible


## The items this floor may offer. Empty for a floor with no pool assigned, which every
## caller already handles — `RunManager.draw_item` returns null on an empty candidate list and
## the loot spawner falls back to a repair cell.
func get_items() -> Array[ItemConfig]:
	return item_pool.items if item_pool != null else [] as Array[ItemConfig]

class_name FloorConfig
extends Resource
## One floor of the megacorporation, as data. Spec section 8's Floor 1: Help Desk.
##
## Holds what the floor is made of, not how it is assembled — FloorGenerator owns the
## graph, this owns the parts list. Adding Floor 2 should be a new .tres, not new code.

@export var display_name: String = "Help Desk"

@export var floor_number: int = 1

## Tags used to filter which room templates may appear here.
@export var floor_tags: Array[StringName] = [&"help_desk"]

## The floor to load when this floor's boss is defeated. Null means this is the run's last
## floor — defeating its boss wins the run. A chain of these is the run's floor order, so
## adding a floor is a new .tres with this field pointed at it, not new code.
@export var next_floor: FloorConfig

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

## Which boss this floor's boss room spawns. A `Boss` scene, instantiated by
## `FloorController` the same way any other floor-specific content is.
@export var boss_scene: PackedScene

## As the HUD shows it. Not read off the boss's own resource — nothing hands the HUD a
## reference to one, and a name is cheaper to keep in step with data than to plumb a
## cross-scene reference for.
@export var boss_display_name: String = ""

## Shown when the boss falls, alongside the reward choice.
@export var boss_defeat_banner: String = ""

## What the HUD announces as each of the boss's phases begins, indexed from phase one: element
## 0 is phase one's banner, element 1 is phase two's, and so on. An empty string means that
## phase is entered in silence, and an empty array means the boss never announces a phase at all.
##
## Data rather than the constants the HUD used to hold, because those constants were The Scrap
## King's lines — "LONG LIVE THE KING", "THE KING REASSEMBLES" — fired on a signal every boss
## emits. The second floor's boss reached phase two and the HUD crowned it. A boss's own words
## belong to that boss, and the only place the HUD already learns which boss it is looking at is
## here, beside its name and its epitaph.
@export var boss_phase_banners: Array[String] = []

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
@export var item_pool: Array[ItemConfig] = []

## Which combat-room clears drop an item, counted from one. `[1, 3, 5]` means the first,
## third, and fifth room the player clears.
##
## A list rather than "every Nth clear" because the interesting number is not the interval,
## it is *how many items a run hands out and how early the first one lands* — and both of
## those are legible here and invisible in a modulo.
@export var item_clear_indices: Array[int] = [1, 3, 5]

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

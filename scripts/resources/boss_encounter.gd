class_name BossEncounter
extends Resource
## One boss, and everything the rest of the game needs to know about it: the scene to
## instantiate and the three pieces of text the HUD says on its behalf.
##
## These four fields lived on `FloorConfig` as `boss_scene`, `boss_display_name`,
## `boss_defeat_banner`, and `boss_phase_banners`, which was right for as long as a floor had
## exactly one boss. It stopped being right the moment either boss could guard either floor:
## four parallel fields cannot be shuffled together, and the failure mode of getting it wrong
## is the specific bug this project already hit once — the HUD announcing "LONG LIVE THE KING"
## over a boss with no claim to the title. Bundling them means a floor draws *a boss*, not
## four values it has to keep in step.
##
## The boss's own tuning stays on its own resource (`BossConfig`, `RuntimeErrorConfig`). This
## is the identity the HUD reads; that is the fight.

## Stable identifier, used to remember which bosses a run has already fought. Must never
## change once it ships, for the reason `ItemConfig.id` must not.
@export var id: StringName = &"unnamed_boss"

@export var scene: PackedScene

## As the HUD shows it. Not read off the boss's own resource — nothing hands the HUD a
## reference to one, and a name is cheaper to keep in step with data than to plumb a
## cross-scene reference for.
@export var display_name: String = ""

## Shown when the boss falls, alongside the reward choice.
@export var defeat_banner: String = ""

## What the HUD announces as each of this boss's phases begins, indexed from phase one. An
## empty string means that phase is entered in silence; an empty array means this boss never
## announces a phase at all.
@export var phase_banners: Array[String] = []


## Throughput zones this boss brings into whatever arena it is fought in, in tile coordinates.
## Same shape and same meaning as `RoomTemplate.thermal_zones` — see `ThermalZone` — and built
## into the room by `FloorController._add_boss` at the moment the boss is stood up.
##
## **A hazard belongs to whichever of the two authored the fight it is part of.** A floor's
## signature mechanic lives on that floor's templates, which is what keeps the Data Center's
## grilles out of the Help Desk and out of the generator. But Cascade Failure's four corner zones
## were never the Data Center's idea about its rooms; they were the fight's own arithmetic, and
## they only ever lived on `data_core_arena` because that was the one arena the fight could
## happen in. The moment either boss could guard either floor, that stopped being true and the
## fight quietly lost a quarter of its difficulty on three floors out of four — the corners of a
## plain `boss_arena` are cold ground the ring cannot reach, and cold ground the ring cannot reach
## is where a player stands to win a fight about not standing still.
##
## Declared here rather than on the boss's own scene for the reason the room owns its zones at
## all: a zone is furniture, laid out in the room's tile grid, built and freed with the room. A
## boss that spawned its own would have to know the arena's coordinates, and would take its floor
## back with it when it died.
##
## Empty for every boss that does not want any, which is three of the five.
@export var arena_thermal_zones: Array[Rect2i] = []


func is_valid() -> bool:
	return scene != null

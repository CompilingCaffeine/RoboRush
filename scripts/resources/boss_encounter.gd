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


func is_valid() -> bool:
	return scene != null

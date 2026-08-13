class_name FloorEntry
extends Resource
## One floor's place in a campaign: a stable id and the path to its content.
##
## A *path* rather than a `FloorConfig` reference, and that is the whole reason this class
## exists. The floor order used to be a chain of direct references (`FloorConfig.next_floor`),
## which meant loading the Help Desk also loaded Development — every room template, theme,
## texture, enemy scene, and boss scene of a floor the player might not reach for ten minutes.
## Two floors made that a rounding error. Six make it the whole campaign resident in memory
## before the first room is drawn, which is exactly what a floor catalog is for avoiding.
##
## Id and path together rather than either alone. The id is what seeds, checkpoints, save files,
## run statistics, and `--floor=` arguments name a floor by, and it has to survive the .tres being
## moved or renamed; the path is only how that id is resolved today. Keeping them in one resource
## rather than in two parallel arrays is the same call `BossEncounter` makes one level down, for
## the same reason: parallel arrays are two things to keep in step and one to forget, and the
## symptom of forgetting is a floor loading somebody else's content under its own name.

## Stable identifier. Must never change once it ships, for the reason `ItemConfig.id` and
## `BossEncounter.id` must not: it is what other data refers to this floor *as*.
@export var id: StringName = &"unnamed_floor"

## Where the `FloorConfig` for this floor lives.
@export_file("*.tres") var config_path: String = ""


## The floor's content, or null if the path is unset, missing, or holds something else.
##
## Godot's own resource cache makes the repeat call cheap, so this deliberately keeps no cache
## of its own — a second cache would be a second thing to invalidate, and the one place that
## would show is a floor edited between runs still serving its old content.
func load_config() -> FloorConfig:
	if config_path.is_empty() or not ResourceLoader.exists(config_path):
		return null
	return load(config_path) as FloorConfig

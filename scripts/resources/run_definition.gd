class_name RunDefinition
extends Resource
## The campaign: which floors a run is made of, in order.
##
## One ordered list rather than a chain of `FloorConfig.next_floor` links, because a linked list
## is a floor order that can only be read by walking it. Nothing could ask "what is floor 4?"
## without loading floors 1 through 3, nothing could say how long a run was without following it
## to the end, and nothing could notice that floor 5 pointed back at floor 2 until a run was
## already looping. All three are answers this file gives by indexing an array.
##
## The floors are named by id and path (see `FloorEntry`), not held as references, so the
## campaign describes six floors while only the current one is in memory. `load_floor` is a
## synchronous `load()` today, which is honest for two floors and will not stay honest for six:
## the transition budget is where a floor's textures and enemy scenes get paid for, and
## preloading the *next* floor during play is the fix. That belongs with the rest of the
## performance work rather than here, but this is the seam it will happen at.
##
## The last floor in the list is the run's last floor. That is the single rule deciding victory,
## replacing "the floor whose `next_floor` happens to be null" — which was the same fact stored
## in six places, five of which had to be right by hand.

## Stable identifier for this campaign, so a save file or a run result can say which one it was
## recorded against. It will matter the first time there is a second campaign; it costs nothing
## to have been stable from the start, and cannot be made stable retroactively.
@export var id: StringName = &"unnamed_campaign"

@export var display_name: String = ""

## Bumped whenever the campaign's content changes in a way that stops an old seed reproducing
## the same run. A seed alone does not identify a run — the content it was drawn against does
## too — so anything promising reproducibility (a checkpoint, a shared seed, a bug report) has
## to record this alongside it.
@export var content_version: int = 1

## The floors, in the order they are played. Index 0 is floor 1.
@export var floors: Array[FloorEntry] = []

@export_group("Completeness")

## How many floors this campaign has when it is finished. Declared rather than inferred from
## `floors.size()`, which would make "the finale is missing" indistinguishable from "the campaign
## is two floors long and that is correct" — and the whole point of validating a campaign before
## play is telling those two apart.
@export var target_floor_count: int = 6

## Whether falling short of `target_floor_count` is an error rather than a warning. False while
## floors are being authored, so an incomplete campaign still plays and still reports what is
## missing. True once the campaign is meant to be complete, which turns "the finale never got
## written" from something a player discovers into something a build refuses to start with.
@export var require_complete: bool = false


func size() -> int:
	return floors.size()


## Whether `index` names a floor in this campaign. The bounds check every other lookup here
## makes, given a name so callers can ask before they take.
func has_floor(index: int) -> bool:
	return index >= 0 and index < floors.size() and floors[index] != null


func entry_at(index: int) -> FloorEntry:
	return floors[index] if has_floor(index) else null


## The stable id of the floor at `index`, or the empty name if there is no such floor.
func floor_id_at(index: int) -> StringName:
	var entry := entry_at(index)
	return entry.id if entry != null else &""


## Where in the run a floor sits, or -1 if this campaign does not contain it. The inverse of
## `floor_id_at`, and the only supported way to turn a floor back into a position — a
## `FloorConfig` does not know where it is, deliberately, because a floor that knew its own
## index would be a second campaign order to keep in step with this one.
func index_of(floor_id: StringName) -> int:
	for index: int in floors.size():
		var entry := floors[index]
		if entry != null and entry.id == floor_id:
			return index
	return -1


## Whether beating the floor at `index` wins the run.
##
## An index this campaign does not contain answers true, which is the case worth spelling out: a
## controller running a floor the campaign has never heard of holds index -1, and "is there a
## floor after -1" is *yes* — floor 1. Answering that literally would send a test arena's boss
## into the opening floor of the campaign rather than ending the run.
func is_terminal(index: int) -> bool:
	return not has_floor(index) or not has_floor(index + 1)


## The content of the floor at `index`, or null if there is no such floor or its path is broken.
## Callers report the null rather than presenting an empty world; `CampaignValidator` is what
## makes it never happen in a shipped campaign.
func load_floor(index: int) -> FloorConfig:
	var entry := entry_at(index)
	return entry.load_config() if entry != null else null


func load_floor_by_id(floor_id: StringName) -> FloorConfig:
	return load_floor(index_of(floor_id))


## The seed the floor at `index` is generated from in a run that opened on `run_seed`.
##
## Derived from the run seed, this campaign's content version, and the floor's *stable id* — see
## `RunRng.floor_seed`. Three properties follow from that, and none of them held while a floor's
## seed was `hash()` of the floor before it:
##
## - **A floor is itself.** Floor 4's seed does not depend on floors 1-3 having been generated
##   first, so `--floor=4` and a real arrival build the same floor 4, and editing floor 3 does not
##   move floor 4's layout.
## - **Order is not identity.** Inserting a floor, or reordering two, leaves every other floor's
##   seed alone. The chain moved all of them.
## - **A seed means one thing.** The content version is folded in, so a campaign edit that stops
##   old seeds reproducing produces different seeds rather than the same seed quietly building
##   something else.
##
## An index this campaign does not contain derives from the empty id, which is deterministic and
## meaningless — a test arena's controller holds index -1, and it never descends.
func floor_seed_for(run_seed: int, index: int) -> int:
	return RunRng.floor_seed(run_seed, content_version, floor_id_at(index))

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


## Whether a background load has been asked for and not yet collected. Instance state on a resource,
## which is unusual and is fine here: it is never exported, never saved, and describes a request in
## flight rather than anything about the floor.
var _preload_requested := false


## The floor's content, or null if the path is unset, missing, or holds something else.
##
## Collects a background load if one was asked for, and blocks until it finishes — which is the
## whole design. A floor is *needed* at the moment the player claims a boss reward, and by then it
## has usually had the entire previous floor to arrive; if it has not, waiting here is exactly what
## the synchronous load did before, so preloading can only make a transition faster and never
## slower.
##
## Godot's own resource cache makes the repeat call cheap, so this deliberately keeps no cache of
## its own — a second cache would be a second thing to invalidate, and the one place that would
## show is a floor edited between runs still serving its old content.
func load_config() -> FloorConfig:
	if config_path.is_empty() or not ResourceLoader.exists(config_path):
		_preload_requested = false
		return null

	if _preload_requested:
		_preload_requested = false
		# A failed or unknown request falls through to the plain load rather than reporting nothing:
		# the request is an optimisation, and losing it must not lose the floor.
		if ResourceLoader.load_threaded_get_status(config_path) != ResourceLoader.THREAD_LOAD_FAILED:
			var loaded := ResourceLoader.load_threaded_get(config_path) as FloorConfig
			if loaded != null:
				return loaded

	return load(config_path) as FloorConfig


## Starts loading this floor in the background, so the next one is in memory before the player asks
## for it.
##
## The reason to do this at all is the transition budget: `load()` pulls in the floor's templates,
## tile sheets, enemy scenes and boss scene, and doing that at the instant the reward is taken puts
## all of it inside the one frame the player is watching. Doing it while they fight the previous
## floor costs nothing they can see.
##
## Only ever *one* floor ahead. Requesting the whole campaign would put six floors of textures in
## memory to save the same milliseconds, which is the thing `FloorEntry` exists to avoid.
func request_preload() -> void:
	if _preload_requested or config_path.is_empty() or not ResourceLoader.exists(config_path):
		return
	if ResourceLoader.load_threaded_request(config_path) == OK:
		_preload_requested = true


## Collects an outstanding background load and throws the result away.
##
## Godot has no way to *cancel* a threaded request — collecting it is the only way to close one — and
## an uncollected request is a live object at exit. Measured, not assumed: quitting a run while the
## next floor was still requested turned a clean shutdown into "1 ObjectDB instance was leaked at
## exit", which is precisely the background noise that makes exit-leak output useless as a signal.
##
## Called when the floor controller leaves the tree, which covers quitting, restarting, and going
## back to the menu. It blocks until the load finishes, and by then it almost always has.
func discard_preload() -> void:
	if not _preload_requested:
		return
	_preload_requested = false
	if ResourceLoader.load_threaded_get_status(config_path) != ResourceLoader.THREAD_LOAD_FAILED:
		ResourceLoader.load_threaded_get(config_path)


## Whether a background load is outstanding. For the suite, and for a debug overlay that wants to
## show whether the next floor is ready.
func is_preloading() -> bool:
	return _preload_requested

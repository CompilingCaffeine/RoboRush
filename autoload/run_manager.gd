extends Node
## State belonging to the current run: currency, progress, and the seed.
##
## Separate from GameManager on purpose. GameManager holds things that outlive a run (feedback
## settings, hit pause, restart); this holds things that are *reset* by a new run. Keeping them
## apart means "what should a restart clear?" has an obvious answer instead of being a list
## someone has to remember to update.
##
## Spec section 24 is explicit that a run in progress is not saved, so nothing here is
## persisted. Run statistics (section 25) will extend this in milestone 5.

## Emitted when scrap changes, so the HUD does not have to poll a number that rarely moves.
signal scrap_changed(total: int)

## Emitted when a room is cleared for the first time, for run statistics later.
signal rooms_cleared_changed(total: int)

var scrap: int = 0
var floor_number: int = 1
var floor_name: String = "Help Desk"
var rooms_cleared: int = 0

## The seed the current floor was generated from. Kept so a layout can be reproduced when
## something goes wrong in it.
var floor_seed: int = 0

## Ids of every item this run has already put on the floor. Tracked here rather than on the
## inventory because an item counts as spent the moment it *drops*: the player may walk past
## it, and offering it again in the next room would turn "I chose not to take that" into "the
## game did not notice".
var offered_item_ids: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_cleared.connect(_on_room_cleared)


## Clears everything run-scoped. Called at the start of a run, not on entering a floor.
func begin_run(seed_value: int) -> void:
	scrap = 0
	rooms_cleared = 0
	floor_number = 1
	floor_seed = seed_value
	offered_item_ids.clear()
	scrap_changed.emit(scrap)
	rooms_cleared_changed.emit(rooms_cleared)


## Picks an item from `pool` that this run has not offered yet, and records it. Returns null
## once the pool is exhausted, which the caller treats as "drop nothing" rather than as an
## error: a floor generous enough to run a pool dry is a tuning problem, not a crash.
func draw_item(pool: Array[ItemConfig], rng: RandomNumberGenerator) -> ItemConfig:
	var candidates: Array[ItemConfig] = []
	for item: ItemConfig in pool:
		if item != null and item.id not in offered_item_ids:
			candidates.append(item)
	if candidates.is_empty():
		return null

	var drawn := candidates[rng.randi_range(0, candidates.size() - 1)]
	offered_item_ids.append(drawn.id)
	return drawn


func add_scrap(amount: int) -> void:
	if amount == 0:
		return
	scrap = maxi(scrap + amount, 0)
	scrap_changed.emit(scrap)


## Returns whether the purchase went through. Shops in milestone 5 are the caller.
func try_spend_scrap(amount: int) -> bool:
	if amount <= 0 or scrap < amount:
		return false
	scrap -= amount
	scrap_changed.emit(scrap)
	return true


func _on_room_cleared() -> void:
	rooms_cleared += 1
	rooms_cleared_changed.emit(rooms_cleared)

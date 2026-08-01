extends Node
## State belonging to the current run: currency, progress, the seed, and the statistics.
##
## Separate from GameManager on purpose. GameManager holds things that outlive a run (feedback
## settings, hit pause, what state the game is in); this holds things that are *reset* by a new
## run. Keeping them apart means "what should a restart clear?" has an obvious answer instead of
## being a list someone has to remember to update.
##
## Spec section 24 is explicit that a run in progress is not saved, so nothing here is
## persisted. Spec section 25's statistics live in `stats`, and this node is where the EventBus
## is translated into them — a RefCounted cannot sit in the tree and listen for itself.

## Emitted when scrap changes, so the HUD does not have to poll a number that rarely moves.
signal scrap_changed(total: int)

## Emitted when a room is cleared for the first time.
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

## Spec section 25. Replaced wholesale on a new run rather than reset field by field, so a
## statistic added later cannot be forgotten in the reset.
var stats := RunStats.new()

## Counts up only while the game is actually being played, which is what makes the duration
## on the summary screen a measure of the run rather than of how long the window was open.
var _is_timing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.shot_fired.connect(_on_shot_fired)
	EventBus.boss_defeated.connect(_on_boss_defeated)


func _process(delta: float) -> void:
	if _is_timing:
		stats.duration += delta


## Clears everything run-scoped. Called at the start of a run, not on entering a floor.
func begin_run(seed_value: int) -> void:
	scrap = 0
	rooms_cleared = 0
	floor_number = 1
	floor_seed = seed_value
	offered_item_ids.clear()
	stats = RunStats.new()
	_is_timing = true
	scrap_changed.emit(scrap)
	rooms_cleared_changed.emit(rooms_cleared)


## Stops the clock. Called when the run ends, whichever way it ended.
func end_run() -> void:
	_is_timing = false


## Pauses the clock without ending the run.
func set_timing(timing: bool) -> void:
	_is_timing = timing


func add_scrap(amount: int) -> void:
	if amount == 0:
		return
	scrap = maxi(scrap + amount, 0)
	if amount > 0:
		stats.scrap_collected += amount
	scrap_changed.emit(scrap)


## Returns whether the purchase went through. The shop is the caller.
func try_spend_scrap(amount: int) -> bool:
	if amount <= 0 or scrap < amount:
		return false
	scrap -= amount
	scrap_changed.emit(scrap)
	return true


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


func _on_room_cleared() -> void:
	rooms_cleared += 1
	stats.record_room_cleared()
	rooms_cleared_changed.emit(rooms_cleared)


func _on_enemy_damaged(_enemy: Node, info: DamageInfo, _remaining: float) -> void:
	stats.record_damage_dealt(info.amount)


func _on_enemy_killed(_enemy: Node, _position: Vector2) -> void:
	stats.enemies_defeated += 1


## The fatal blow is the one that leaves nothing, which is also the only time the source is
## worth recording. Named from the source's own display name where it has one, so the summary
## says "Memory Leech" rather than naming a node.
func _on_player_damaged(info: DamageInfo, remaining: float) -> void:
	stats.record_damage_taken(info.amount)
	if remaining <= 0.0:
		stats.cause_of_death = _describe_source(info.source)


func _on_item_collected(item: ItemConfig) -> void:
	stats.items_collected.append(item.display_name)


func _on_shot_fired(team: int, _muzzle: Vector2, _direction: Vector2) -> void:
	if team != Teams.Id.PLAYER:
		return
	stats.record_shot(_player_weapon_name())


func _on_boss_defeated(_boss: Node) -> void:
	stats.bosses_defeated += 1


## Read off the player rather than tracked, because the weapon is the player's property and
## a copy here would be one more thing to keep in step when weapon cores arrive.
func _player_weapon_name() -> String:
	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Player
	if player == null:
		return "unknown"
	var weapon := player.get_weapon_controller()
	return weapon.config.display_name if weapon != null and weapon.config != null else "unknown"


func _describe_source(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return "unknown"
	var enemy := source as Enemy
	if enemy != null and enemy.config != null:
		return enemy.config.display_name
	return source.name

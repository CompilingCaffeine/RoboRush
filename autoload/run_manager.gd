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
##
## The run's *result* does outlive it. Beginning and ending a run are the two moments the
## lifetime record changes, and they are both here rather than in SaveManager because this is
## the node that knows when a run actually starts — `GameManager.start_run` is also called by
## a restart, one scene reload before the run it is restarting into.

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

## Multiplier on every enemy's maximum integrity, for the rest of the run. One unless
## something has accrued against it — Tech Debt is the only thing that does, adding to it on
## every room cleared.
##
## Run-scoped rather than carried on the item, because the debt has to outlive the room it
## was incurred in and apply to enemies the inventory will never meet. It is deliberately not
## applied to bosses: a boss pool is already tuned to the minute, and compounding it with a
## penalty the player accepted eight rooms earlier would end runs at the door rather than in
## the fight.
var enemy_health_scale: float = 1.0

## Ids of every boss this run has already been sent to fight. Run-scoped for exactly the
## reason `offered_item_ids` is: a floor drawing its boss cannot see what the previous floor
## drew, and a two-floor run that rolled The Scrap King twice would be a run missing a boss.
##
## Recorded when the boss is *drawn*, not when it is defeated — a player who dies to the first
## boss ends the run there, so the distinction never shows, and drawing is the only moment the
## floor is deciding anything.
var fought_boss_ids: Array[StringName] = []

## Spec section 25. Replaced wholesale on a new run rather than reset field by field, so a
## statistic added later cannot be forgotten in the reset.
var stats := RunStats.new()

## Labels of the lifetime records this run beat, filled in when it ends. The summary screen
## marks these rows rather than working it out itself, because by the time it is shown the
## record has already been overwritten with this run's number.
var records_beaten: PackedStringArray = []

## Counts up only while the game is actually being played, which is what makes the duration
## on the summary screen a measure of the run rather than of how long the window was open.
var _is_timing := false

## False only while a run is open. Starts true because the game boots to a menu, and "no run
## has started" and "the run is already filed" want the same answer from `end_run`.
var _is_finished := true


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
	enemy_health_scale = 1.0
	fought_boss_ids.clear()
	stats = RunStats.new()
	records_beaten = []
	_is_timing = true
	_is_finished = false
	SaveManager.record_run_started()
	scrap_changed.emit(scrap)
	rooms_cleared_changed.emit(rooms_cleared)


## Stops the clock and files the result. Called when the run ends, whichever way it ended.
##
## Guarded by its own flag rather than by the clock: `GameManager` stops the clock before it
## announces the ending, and a run counted twice would corrupt a record the player cannot
## repair.
func end_run(won: bool) -> void:
	if _is_finished:
		return
	_is_finished = true
	_is_timing = false
	records_beaten = SaveManager.record_run_finished(stats, won)


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


## Returns an item to the pool so it can be offered again. The counterpart to `draw_item`'s
## reservation, and it has exactly one caller: a shop reroll.
##
## The distinction it draws is the whole point. "Offered" means the player had their chance
## and passed, which is right for an item lying on the floor of a room they walked out of. It
## is wrong for an item swept off a shelf by a reroll — that is the player asking to see
## something else, not declining this thing forever.
##
## Getting that wrong was a soft-lock. Two shop offers plus three rerolls struck eight of the
## twelve items off the run for good; add three combat-clear rewards and the treasure vault
## and the pool was dry before the boss died. The boss then had nothing to offer, created zero
## reward stands, and since victory only happened when a reward was taken, the run could not
## be won.
func release_item(id: StringName) -> void:
	offered_item_ids.erase(id)


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

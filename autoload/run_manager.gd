extends Node
## State belonging to the current run: currency, progress, the seed, and the statistics.
##
## Separate from GameManager on purpose. GameManager holds things that outlive a run (feedback
## settings, hit pause, what state the game is in); this holds things that are *reset* by a new
## run. Keeping them apart means "what should a restart clear?" has an obvious answer instead of
## being a list someone has to remember to update.
##
## Spec section 24 said a run in progress is never saved. That held while a run was one ten-room
## floor and stopped holding at six: an hour-long campaign interrupted at floor five is an hour
## the player does not get back. A run is now written out *at floor boundaries only* — see
## `RunCheckpoint` for what that means and `checkpoint_floor` below for the one place it happens.
## Nothing else here is persisted, and nothing is written mid-floor.
##
## Spec section 25's statistics live in `stats`, and this node is where the EventBus is
## translated into them — a RefCounted cannot sit in the tree and listen for itself.
##
## The run's *result* does outlive it. Beginning and ending a run are the two moments the
## lifetime record changes, and they are both here rather than in SaveManager because this is
## the node that knows when a run actually starts — `GameManager.start_run` is also called by
## a restart, one scene reload before the run it is restarting into.

## This node's own state, split by what a floor boundary does to it.
##
## Written down rather than left to be inferred, because the field nobody classified is exactly the
## one that breaks. A descent has to leave one set alone and replace the other, and getting it the
## wrong way round produces symptoms that look like anything but a missing decision: a run that
## keeps the previous floor's name on the HUD, or one that loses its scrap on the third descent, or
## a floor generated from a seed the manifest does not agree with.
##
## The three lists are checked against `get_property_list` in `tests/test_gate.gd`, so *every*
## script variable here has to appear in exactly one of them. Adding a field without deciding which
## it is fails the suite rather than the player, which is the whole reason to declare them at all.
##
## Everything a descent must leave exactly as it found it. Run-wide is not the same as permanent —
## these change constantly while a floor is being played. What they must never do is change
## *because* the player went downstairs.
const RUN_WIDE_FIELDS: Array[StringName] = [
	&"scrap",
	&"rooms_cleared",
	&"_run_seed",
	&"_campaign_id",
	&"_content_version",
	&"enemy_health_scale",
	&"max_integrity_penalty",
	&"death_saves_spent",
	&"stats",
	&"records_beaten",
	&"_is_timing",
	&"_is_finished",
]

## Run-wide as well, and preserved in the sense that a ledger is preserved: a descent may **append**
## to these and must never lose an entry.
##
## Kept apart from the list above rather than folded into it, because the two are different promises
## and only one of them is "unchanged". Opening a floor genuinely writes to both of these before the
## player has done anything: `FloorController.build` draws the floor's boss, and stocking its offers
## reserves the items they will be. A rule that demanded these come out of a boundary untouched
## would be a rule the game has to break on every descent, and a rule that is broken on purpose
## stops being checked.
##
## Losing an entry, on the other hand, is the failure worth catching, and it is silent: a run that
## forgot which bosses it had fought would repeat one, and a run that forgot which items it had
## offered would hand the player a second copy of something it had already spent.
const RUN_LEDGER_FIELDS: Array[StringName] = [
	&"offered_item_ids",
	&"fought_boss_ids",
]

## Everything a descent must replace with the floor being entered. All three are written in one
## place, by `begin_floor`, for the reason that method's own doc gives.
const FLOOR_LOCAL_FIELDS: Array[StringName] = [
	&"floor_number",
	&"floor_name",
	&"floor_seed",
]

## Emitted when scrap changes, so the HUD does not have to poll a number that rarely moves.
signal scrap_changed(total: int)

## Emitted when a room is cleared for the first time.
signal rooms_cleared_changed(total: int)

var scrap: int = 0
var floor_number: int = 1
var floor_name: String = "Help Desk"
var rooms_cleared: int = 0

## The seed the current floor was generated from — derived from the run seed and the floor's stable
## id, so it can be re-derived rather than remembered. Kept because it is what the floor's own named
## streams come from (`RunRng.stream_seed`) and what the debug overlay shows.
var floor_seed: int = 0

## The one seed a run has, reachable only through `get_run_seed`. Everything random and reproducible
## in the run — every floor's layout, boss, roster, shop stock and loot — is derived from this value
## plus a stable name (see `RunRng`).
##
## Private with a getter rather than a public field, which is the only way GDScript makes a value
## genuinely read-only. It matters here more than it looks. `floor_seed` used to be the only seed
## anybody held, each floor's being `hash()` of the last, so the run's seed was a *variable*: by
## floor three the number the debug overlay printed was three transformations removed from the one a
## player would have to type back in, and anything that advanced it early moved every floor after it.
## One value, set by `begin_run` and by nothing else, is what makes "this run is `--seed=971330958`"
## a sentence that stays true for the whole run.
var _run_seed: int = 0

## Which campaign this run is playing, and which version of its content. Recorded rather than
## derived, because a seed alone does not identify a run: the same seed builds a different floor 3
## once that floor is edited, and only the version says so.
var _campaign_id: StringName = &""
var _content_version: int = 1

## Ids of every item this run has already put on the floor. Tracked here rather than on the
## inventory because an item counts as spent the moment it *drops*: the player may walk past
## it, and offering it again in the next room would turn "I chose not to take that" into "the
## game did not notice".
var offered_item_ids: Array[StringName] = []

## The most a run's enemies may be scaled to, however much has accrued against them.
##
## Tech Debt charges 0.12 per room cleared and used to charge it forever. That was survivable
## while a run was one ten-room floor: six combat rooms is +0.72, and enemies ended the run at
## under twice their printed integrity. A six-floor campaign is roughly thirty-six combat rooms,
## which is +4.32 — enemies with five times the health they were tuned for, a time-to-kill nothing
## in `tests/test_balance.gd` was ever checked against, and a run that stops being winnable
## somewhere around floor four rather than becoming harder.
##
## A ceiling rather than a smaller per-room charge, because the item's whole idea is that the debt
## compounds while you keep clearing rooms; slowing it down would blunt that on floor one to
## survive floor five. Capping it keeps the early pressure exactly as authored and stops the late
## run being decided by a choice made twenty rooms ago.
##
## The number is a tripwire, not a tuned value — the same stance `tests/test_balance.gd` takes
## about every number it checks. Nobody has played a six-floor run; when somebody has, this should
## move to whatever that taught them.
const MAX_ENEMY_HEALTH_SCALE := 2.5

## Multiplier on every enemy's maximum integrity, for the rest of the run. One unless
## something has accrued against it — Tech Debt is the only thing that does, adding to it on
## every room cleared. Bounded by `MAX_ENEMY_HEALTH_SCALE`.
##
## Run-scoped rather than carried on the item, because the debt has to outlive the room it
## was incurred in and apply to enemies the inventory will never meet. It is deliberately not
## applied to bosses: a boss pool is already tuned to the minute, and compounding it with a
## penalty the player accepted eight rooms earlier would end runs at the door rather than in
## the fight.
var enemy_health_scale: float = 1.0

## Maximum integrity this run has permanently lost, subtracted by `Player._apply_item_stats` from
## the ceiling the config and the inventory would otherwise give. Zero for a run that has not spent
## a death save.
##
## Run-scoped rather than held on the health component, and for the same reason `enemy_health_scale`
## is: `_apply_item_stats` recomputes the maximum from `PlayerConfig` plus the inventory on every
## pickup, so a value written straight onto the component is erased by the next item the player
## collects — the penalty would silently refund itself at the next reward stand. It also has to cross
## a floor boundary, and the run is the thing that does.
##
## Stored as a *debt* rather than as a clamp so the pool can be rebuilt. Failover drops the ceiling
## to one point by charging the difference; a Reinforced Chassis found afterwards raises the ceiling
## from one to three, because the +2 is added to the config's base and only then is the debt taken
## off. "Extra fragile until you rebuild" is that subtraction and nothing else.
var max_integrity_penalty: float = 0.0

## Death saves this run has already spent, against the total its items grant. Counted here rather
## than on the inventory because the *charges* are a property of the items held and the *spending* is
## a property of the run: dropping and re-collecting a failover item must not hand back a save.
var death_saves_spent: int = 0

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
##
## Set by `suspend_run` too, which is not an ending. What the flag really means is "this run is
## closed here and must not be filed again", and a run put down to be picked up later wants that
## for a different reason: the trip back to the title screen would otherwise file it as abandoned.
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


## Clears everything run-scoped and fixes the run's identity. Called at the start of a run, not on
## entering a floor.
##
## The campaign is optional so that a suite driving one floor in an arena can still start a run
## without inventing a campaign to do it. What it costs is only reproduction bookkeeping: such a run
## records no campaign id, and its floor seeds are whatever its caller passed to `build`.
func begin_run(seed_value: int, campaign: RunDefinition = null) -> void:
	scrap = 0
	rooms_cleared = 0
	floor_number = 1
	_run_seed = seed_value
	_campaign_id = campaign.id if campaign != null else &""
	_content_version = campaign.content_version if campaign != null else 1
	floor_seed = seed_value
	offered_item_ids.clear()
	enemy_health_scale = 1.0
	max_integrity_penalty = 0.0
	death_saves_spent = 0
	fought_boss_ids.clear()
	stats = RunStats.new()
	stats.run_seed = _run_seed
	stats.campaign_id = _campaign_id
	stats.content_version = _content_version
	records_beaten = []
	_is_timing = true
	_is_finished = false
	SaveManager.record_run_started()
	# A new run is one of the four ways a checkpoint stops being valid, and it is the one that is
	# easy to miss: restarting from the summary screen never passes through `end_run` a second
	# time, so without this the abandoned run would still be offered on the title screen.
	SaveManager.clear_checkpoint()
	scrap_changed.emit(scrap)
	rooms_cleared_changed.emit(rooms_cleared)


## Puts a saved run back. The counterpart to `begin_run`, and it sets exactly the same fields —
## which is the point of them being in one function each rather than assigned wherever they are
## needed.
##
## What it does *not* do is count a run started. A resumed run is the same run: counting it again
## would inflate the lifetime total by one per interruption, and a player who saves and quits
## between every floor would end a campaign having "started" six runs.
##
## The player is not touched here. Integrity and the build belong to the robot, and the robot is
## restored by whoever owns it — see `main.gd`. This node restores the run.
func restore_run(checkpoint: RunCheckpoint, campaign: RunDefinition) -> void:
	scrap = checkpoint.scrap
	rooms_cleared = checkpoint.rooms_cleared
	floor_number = checkpoint.floor_number
	_run_seed = checkpoint.run_seed
	_campaign_id = campaign.id
	_content_version = campaign.content_version
	floor_seed = campaign.floor_seed_for(checkpoint.run_seed, campaign.index_of(checkpoint.floor_id))
	offered_item_ids = checkpoint.offered_item_ids.duplicate()
	enemy_health_scale = checkpoint.enemy_health_scale
	max_integrity_penalty = checkpoint.max_integrity_penalty
	death_saves_spent = checkpoint.death_saves_spent
	fought_boss_ids = checkpoint.fought_boss_ids.duplicate()
	# A copy, like the two arrays above it. `SaveManager` goes on holding the checkpoint after a
	# resume — it is still the run to come back to until the next boundary replaces it — and the
	# live statistics object shared with it would keep absorbing the floor being played. The next
	# ordinary save would then write a checkpoint whose statistics had advanced past the boundary
	# its own counters describe, which is a file this build refuses to load: `RunCheckpoint.validate`
	# checks those two against each other precisely because they cannot disagree honestly.
	stats = RunStats.from_dict(checkpoint.stats.to_dict())
	records_beaten = []
	_is_timing = true
	_is_finished = false
	scrap_changed.emit(scrap)
	rooms_cleared_changed.emit(rooms_cleared)


## Takes a checkpoint of the run and hands it to `SaveManager` to keep. Called at a floor
## boundary, once the descent has committed and the new floor is open.
##
## Refuses a run that has ended, which is the race `FloorController._finish_floor` documents: a
## hazard committed before the boss died can kill the player in the same frame the reward is
## claimed. The descent is already refused in that case; this is the same guard one level down,
## because a checkpoint written for a run that lost would offer the player their death back.
func checkpoint_floor(campaign: RunDefinition, floor_config: FloorConfig, player: Player) -> void:
	if not _can_checkpoint(campaign, floor_config, player):
		return

	var health := player.get_health_component()
	var inventory := player.get_item_inventory()
	SaveManager.store_checkpoint(
		RunCheckpoint.capture(campaign, floor_config, health.current, inventory.get_items())
	)


## Checkpoints the run where it stands, floor progress and all. What the pause menu's SAVE GAME
## does, through `FloorController.save_run_now` — which is the only thing that knows which rooms
## have been cleared.
##
## Every refusal `checkpoint_floor` makes is made here too, and for the same reasons, which is why
## the guard is shared rather than written twice. Returns whether a checkpoint was written: a run
## that has already ended cannot be saved, and the menu says so rather than claiming otherwise.
func checkpoint_here(
	campaign: RunDefinition, floor_config: FloorConfig, player: Player,
	cleared_rooms: Array[int], visited_rooms: Array[int], clears: int
) -> bool:
	if not _can_checkpoint(campaign, floor_config, player):
		return false

	var health := player.get_health_component()
	var inventory := player.get_item_inventory()
	var checkpoint := RunCheckpoint.capture(
		campaign, floor_config, health.current, inventory.get_items()
	)
	checkpoint.record_floor_progress(cleared_rooms, visited_rooms, clears)
	SaveManager.store_checkpoint(checkpoint)
	return true


## Whether there is a run here worth writing down. Shared by both checkpoint paths so that the
## boundary and the pause menu cannot come to different conclusions about the same run — a save
## button that worked one frame after the automatic checkpoint had refused would write exactly the
## checkpoint that refusal exists to prevent.
##
## The dead-player case is the one that matters: a hazard committed before the boss died can kill
## the player in the same frame the reward is claimed, and a checkpoint written then would offer
## the player their own death back the next time they pressed CONTINUE.
func _can_checkpoint(
	campaign: RunDefinition, floor_config: FloorConfig, player: Player
) -> bool:
	if _is_finished or GameManager.is_run_over() or campaign == null or floor_config == null:
		return false
	if player == null or not is_instance_valid(player) or player.is_dead():
		return false
	return player.get_health_component() != null and player.get_item_inventory() != null


## The run's seed. See `_run_seed` for why this is a function rather than a field.
func get_run_seed() -> int:
	return _run_seed


func get_campaign_id() -> StringName:
	return _campaign_id


func get_content_version() -> int:
	return _content_version


## Records that the run is now standing on a floor, and which one. Called by `FloorController` as it
## opens a session — for the floor a run opens on and for every floor it descends into.
##
## The three fields the HUD reads and the statistics' per-floor record are filled in one place on
## purpose. They were three separate assignments at the controller's call site, which is three
## chances for a floor to be announced under the previous floor's name or seed.
func begin_floor(number: int, id: StringName, seed_value: int, display: String) -> void:
	floor_number = number
	floor_name = display
	floor_seed = seed_value
	stats.begin_floor(number, id, seed_value)


## Notes which boss the current floor drew. Separate from `begin_floor` because the draw needs the
## floor's seeded streams, which only exist once the floor is opening.
func record_floor_boss(boss_id: StringName) -> void:
	stats.record_floor_boss(boss_id)


## Which boss the floor being played has already drawn, or empty if it has not drawn one.
##
## The counterpart to `record_floor_boss`, and it exists for the one caller that has to ask: a floor
## being *re-opened* — which is what a resume is — must take back the boss the run already drew for
## it rather than draw a second one. See `FloorController._draw_boss_encounter`.
##
## The open floor record is the right place to ask because it is the run's own memory of the floor it
## is standing on: it survives a checkpoint (`FloorRecord.to_dict` carries `boss_id`), and
## `RunStats.begin_floor` keeps it rather than opening a second record when the same floor is entered
## again. A run that has no floor open — a test arena, a menu — has drawn nothing, and says so.
func current_floor_boss_id() -> StringName:
	var open := stats.current_floor()
	return open.boss_id if open != null else &""


## Closes the current floor's record with how it ended. Descending is the controller's business;
## every other outcome arrives through `end_run`.
func finish_floor(outcome: FloorRecord.Outcome) -> void:
	stats.finish_floor(outcome)


## Stops the clock and files the result. Called when the run ends, whichever way it ended.
##
## Guarded by its own flag rather than by the clock: `GameManager` stops the clock before it
## announces the ending, and a run counted twice would corrupt a record the player cannot
## repair.
##
## `abandoned` separates walking out to the title screen from being destroyed. Both are filed as
## losses — the player still cleared those rooms, and a personal best lost to using the menu would
## read as the game forgetting rather than as a rule — but the floor they happened on should say
## which it was, because "floor 5 killed nine players in a row" and "nine players quit on floor 5"
## are different problems with the same total.
func end_run(won: bool, abandoned := false) -> void:
	if _is_finished:
		return
	_is_finished = true
	_is_timing = false
	finish_floor(
		FloorRecord.Outcome.WON if won
		else FloorRecord.Outcome.ABANDONED if abandoned
		else FloorRecord.Outcome.LOST
	)
	# Three of the four endings a checkpoint has to survive — won, lost, abandoned — arrive here,
	# and they arrive here *whichever* of them it was, which is why the clearing is here rather
	# than at each ending's own call site. The fourth is `begin_run`.
	SaveManager.clear_checkpoint()
	records_beaten = SaveManager.record_run_finished(stats, won)


## Puts the run down without ending it. What SAVE AND EXIT does, once the checkpoint is written.
##
## Three things `end_run` does that this must not. It must not `finish_floor`, because the run is
## still standing on that floor and will be back on it. It must not `clear_checkpoint`, because the
## checkpoint is the entire point of having pressed the button. And it must not
## `record_run_finished`, because the run is not finished — folding it into the lifetime bests here
## would file a loss every time the player took a break, and a run interrupted five times would be
## five abandoned runs in a record they cannot repair.
##
## What it shares with `end_run` is the flag, and that is deliberate rather than convenient. Leaving
## for the title screen goes through `GameManager._set_state`, which ends any open run — and it is
## reached twice, once from the router and once from the menu's own `_ready`. Setting `_is_finished`
## here is what makes both of those the no-op they need to be, rather than the thing that quietly
## deletes the save the player just asked for.
func suspend_run() -> void:
	if _is_finished:
		return
	_is_finished = true
	_is_timing = false


## Pauses the clock without ending the run.
func set_timing(timing: bool) -> void:
	_is_timing = timing


## Charges `amount` against the run's enemy scaling, up to the ceiling. Routed through here rather
## than added to the field directly so there is one place the bound is applied and one place to
## read to find out that there is one.
func add_enemy_health_growth(amount: float) -> void:
	if amount <= 0.0:
		return
	enemy_health_scale = minf(enemy_health_scale + amount, MAX_ENEMY_HEALTH_SCALE)


## Spends one death save and charges what surviving cost: everything above one point of maximum
## integrity, for the rest of the run.
##
## `from_max` is the ceiling at the moment of the save, so a second save later charges only what the
## player had rebuilt since the first — the debt accumulates rather than being recomputed, and two
## saves can never credit the player with integrity they never had.
func spend_death_save(from_max: float, floor_value: float) -> void:
	death_saves_spent += 1
	max_integrity_penalty += maxf(from_max - floor_value, 0.0)


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


## Picks an item from `pool` for one offer, and records it if it was a one-time one.
##
## The declared order, and the whole of the six-floor reward policy:
##
##   1. **Uniques the run has not seen.** Build-defining items, offered once each. These carry the
##      intended experience and are drawn until there are none left.
##   2. **Repeatables.** Stackable chips, offered as often as needed. They are the reason an offer
##      can no longer come up empty.
##
## Uniques first rather than mixed, because a run that has not exhausted them should never be
## handed a +1 chip in place of a mechanic it has not met yet. The chips are a floor under the
## economy, not a dilution of it — on a campaign whose offer budget the unique pool covers, a
## player may never see one, and that is the intended shape.
##
## Still returns null for a pool with neither, which every caller treats as "drop nothing". That is
## now a content bug rather than a tuning one — `CampaignValidator` refuses a campaign whose pool
## cannot fill its offers — but the graceful fallback stays, because a crash in front of the player
## is worse than a repair cell.
func draw_item(pool: Array[ItemConfig], rng: RandomNumberGenerator) -> ItemConfig:
	var unique_candidates: Array[ItemConfig] = []
	var repeatable_candidates: Array[ItemConfig] = []
	for item: ItemConfig in pool:
		if item == null:
			continue
		if item.is_repeatable():
			repeatable_candidates.append(item)
		elif item.id not in offered_item_ids:
			unique_candidates.append(item)

	var candidates := unique_candidates if not unique_candidates.is_empty() else repeatable_candidates
	if candidates.is_empty():
		return null

	var drawn := candidates[rng.randi_range(0, candidates.size() - 1)]
	# Only uniques are spent. Recording a chip would strike it off the run the first time it was
	# offered, which is the opposite of what makes it a chip.
	if not drawn.is_repeatable():
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

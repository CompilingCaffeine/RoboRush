class_name FloorController
extends Node2D
## Owns a floor's lifecycle: opens it from a generated layout, and ends it — by descending into the
## campaign's next floor, or by winning the run — when its boss's prize is claimed.
##
## Every room is instantiated up front and laid out on the grid, the way a room-based shooter
## has always done it: the player walks through a doorway into the next room rather than
## triggering a scene load, so there is no transition to hide and no state to serialise. Rooms
## the player is not in have their enemies disabled, so ten rooms of AI is not ten rooms of
## work.
##
## What happens *on* a floor lives in the floor's session, beside its rooms, and ends with it:
## `RoomLoop` is spec section 4's loop — enter a room, doors lock, enemies are live, kill them,
## doors unlock, a reward drops — and `BossArena` is the fight at the end of it. This node opens
## them, wires them together, and decides what their outcomes mean for the run. It is also the
## floor's face to everything outside it: the HUD, the minimap and `main.gd` ask it, not them.

## Emitted when the player enters a room for any reason, including re-entering a cleared one.
signal room_entered(plan: RoomPlan)

## Emitted after this controller has torn down and rebuilt itself for a new floor. Plain
## signal, not EventBus: only main.gd needs it, and main.gd already owns this node directly —
## the same reasoning that keeps `room_entered` a plain signal too.
signal floor_advanced(config: FloorConfig)

## This floor's look and sound, emitted at the *top* of `build()` — before any room exists and
## before the player is placed.
##
## Separate from `floor_advanced`, which fires after the build, because presentation has to be
## in place before the floor starts announcing itself. Placing the player in the start room
## emits `room_entered`, which starts the music; a theme applied after that plays the previous
## floor's explore loop over the new floor's opening room and only corrects itself at the next
## door. Two signals rather than one moved earlier, because everything else listening to
## `floor_advanced` genuinely does want the finished floor.
signal floor_theme_changed(theme: FloorTheme)

## Emitted once the boss is in its arena, carrying this floor's boss identity — plain signal
## for the same reason `floor_advanced` is: only main.gd needs it, to hand the HUD a name it
## has no other way to learn (see `BossEncounter.display_name`).
##
## `is_final` is the one thing here that is not the boss's own: it says what the fight leaves behind
## rather than who is in it, because the last floor's boss stands over a trophy and every other
## floor's stands over three items to choose between. The HUD is what tells the player which, and
## the campaign order is the only thing that knows — see `is_final_floor`.
signal boss_encountered(
	display_name: String, defeat_banner: String, phase_banners: Array[String], is_final: bool
)

const SESSION_SCENE := preload("res://scenes/floors/floor_session.tscn")

## How far below the top of the screen a room's outer wall sits. The remaining space at the
## bottom is the HUD strip, so the HUD never covers playable floor.
const ROOM_TOP_MARGIN := 4

@export var config: FloorConfig

## The run's floor order. Assigned in the scene rather than pushed in by `main.gd`, so a
## controller instantiated on its own — which is how every suite that drives a descent builds one
## — knows what floor comes next without a caller having to remember to wire it.
@export var campaign: RunDefinition

var layout: FloorLayout

## The room the player is in, by id — see `RoomLoop`. -1 while no floor is open.
var current_room_id: int:
	get:
		return _loop.current_room_id if _loop != null else -1

## Where `config` sits in `campaign`, resolved in `build()`. -1 for content the campaign does not
## contain, which a run treats as its last floor rather than descending into whatever is at index
## zero — a test arena is a floor with no floor after it, not a floor that loops to the start.
var floor_index := -1

## Room ids the player has been inside on this floor, for the minimap — see `RoomLoop`. Empty while
## no floor is open.
var visited: Dictionary[int, bool]:
	get:
		return _loop.visited if _loop != null else _NO_VISITS

const _NO_VISITS: Dictionary[int, bool] = {}

var _player: Player

## One generator per subsystem, each seeded from this floor's seed and its own name (see `RunRng`).
##
## This was one `RandomNumberGenerator` shared by all four, which made them one stream separated
## only by how many numbers had already been taken. Drawing the boss consumed a number, so
## populating the rooms started one number later; adding a single draw anywhere — one more shuffle,
## one extra placement retry — silently changed every later subsystem's results. "The same seed
## reproduces the same run" was therefore true only until the next commit touched an unrelated
## system, which is the weakest possible version of the promise.
##
## Separate generators cannot do that to each other. The boss draw can consume ten numbers or none
## and the shop still stocks itself identically.
var _boss_rng := RandomNumberGenerator.new()
var _encounter_rng := RandomNumberGenerator.new()
var _shop_rng := RandomNumberGenerator.new()
var _reward_rng := RandomNumberGenerator.new()

## A fingerprint of the content this floor was built from, alongside the seed it was built with —
## see `RunManifest`. Computed once per floor rather than on demand, because the debug overlay reads
## it every frame and it cannot change while a floor is standing.
var _content_fingerprint := ""

## This floor's shop, or null for a floor whose layout has no shop room or whose template declares
## no stands. Held because it is the only thing that can say what is on its shelves when a
## checkpoint is written, and because nothing else on the floor can be asked for it: the shop is a
## child of a room, and finding it by walking the tree would be a second answer to a question this
## node already knows the answer to.
var _shop: ShopRoom

## This floor's room loop: which room the player is in, what they have seen and cleared, and what a
## clear pays. Lives in the session and ends with it; null before the first `build`.
var _loop: RoomLoop

## This floor's boss fight: the arena, the boss once summoned, and the prize it leaves. Lives in the
## session and ends with it; null before the first `build`, and on a floor with no boss room.
var _arena: BossArena

## Which boss guards this floor, drawn once in `build()`.
var _boss_encounter: BossEncounter

## This floor's disposable half: its rooms, doors, loot, projectiles, and hazards. Replaced
## wholesale at every boundary — see `_open_session` and `_release_session`.
var _session: FloorSession

## Counts sessions opened, and is what deferred floor-local work is checked against. Kept on the
## controller rather than the session because the session it belongs to is the thing being freed,
## and a token has to outlive what it invalidates.
var _generation := 0

## What a resumed run had already done on the floor the next `build` opens, or null for a floor
## being opened fresh. Consumed by that `build` and then forgotten: it applies to exactly one floor —
## the one being resumed onto — and a descent from it must open the next floor untouched.
var _resume: FloorProgress = null


## Tells the next `build` how much of the floor it is about to open was already done, so a run
## resumed from a save comes back to the rooms it had cleared, the shelf it left in the shop, and a
## boss's prize it left unclaimed, rather than to a floor that has forgotten them. See
## `RunCheckpoint.floor_progress` for reading one out of a save.
##
## The shop is carried by every checkpoint rather than only by a mid-floor one — see `ShopStock` for
## why a shop is not floor *progress* even though it is floor-local. The boss's offer is the one piece
## of floor state whose loss is not merely unfair but final — see `get_pending_boss_reward_ids`.
func resume_floor_progress(progress: FloorProgress) -> void:
	_resume = progress


## How far the run has got through this floor, as a save would record it. Null while no floor is open.
func capture_progress() -> FloorProgress:
	if _loop == null:
		return null
	var progress := FloorProgress.new()
	progress.cleared_room_ids = _loop.cleared_room_ids()
	progress.visited_room_ids = _loop.visited_room_ids()
	progress.clears = _loop.clears
	progress.shop = ShopStock.of(_shop)
	progress.boss_reward_ids = get_pending_boss_reward_ids()
	return progress


## Writes a checkpoint of the run exactly where it stands, including this floor's progress.
##
## The pause menu's SAVE GAME. Everything the automatic boundary checkpoint records is recorded the
## same way — this adds only the floor-local part, which is what makes a save taken in the middle
## of a floor resume honestly instead of paying the floor's rewards out twice.
##
## Answers whether a checkpoint was actually written, because the menu says so on screen and a
## button that reports "saved" when the run was already over would be lying about the one thing the
## player pressed it to find out.
func save_run_now() -> bool:
	if _player == null or not is_instance_valid(_player) or campaign == null or _loop == null:
		return false
	return RunManager.checkpoint_here(campaign, config, _player, capture_progress())


func build(player: Player, seed_value: int) -> bool:
	assert(config != null, "FloorController.config is unset: assign a FloorConfig resource.")

	# Generated before anything is created or emitted, because generation is the only step here
	# that can fail. A build that fails now has changed nothing — it used to have already
	# announced the new floor's theme, so a refused floor took the music with it.
	var generated := FloorGenerator.generate(config, RunRng.stream_seed(seed_value, RunRng.LAYOUT))
	if generated == null:
		return false

	_player = player
	_open_session(generated, seed_value)
	return true


## Brings a floor into existence from a layout that has already been generated.
##
## Split from `build` so a descent can generate the destination *before* giving up the floor the
## player is standing on. Everything below this point succeeds: it instantiates and wires, and
## nothing in it can decide the floor was impossible.
func _open_session(generated: FloorLayout, seed_value: int) -> void:
	layout = generated
	_seed_streams(seed_value)
	# Resolved from the floor's own id rather than tracked across the descent, so the two ways a
	# floor can begin — a run opening on it, and a descent rebuilding into it — cannot disagree
	# about where in the run it is.
	floor_index = campaign.index_of(config.id) if campaign != null else -1
	# Fingerprinted under the campaign's id for this position where there is one, so this agrees with
	# `RunManifest.floor_row` by construction rather than by the two ids happening to match — which
	# `CampaignValidator` insists on, but a controller in a test arena has no campaign to insist.
	var manifest_id := campaign.floor_id_at(floor_index) if floor_index >= 0 else config.id
	_content_fingerprint = RunManifest.row_for(
		config, floor_index, manifest_id, seed_value
	)["fingerprint"]
	floor_theme_changed.emit(config.theme)

	_generation += 1
	_session = SESSION_SCENE.instantiate()
	_session.generation = _generation
	add_child(_session)

	_session.loot.setup(config, RunRng.stream_seed(seed_value, RunRng.LOOT))
	RunManager.begin_floor(config.floor_number, config.id, seed_value, config.display_name)

	# Drawn here rather than when the player reaches the arena, so it is decided by the floor's
	# seed alone. Drawing it on arrival would make which boss you fight depend on how the RNG
	# had been consumed getting there, and one `--seed` would stop reproducing the whole run.
	_boss_encounter = _draw_boss_encounter()
	# Only when there is one to record. A floor that could not be given a boss must not *erase* the
	# one this floor's record already names — that record is what a resume reads to take the boss
	# back (`_draw_boss_encounter`), and overwriting it with an empty id would turn a floor that
	# failed to draw once into a floor that can never draw again.
	if _boss_encounter != null:
		RunManager.record_floor_boss(_boss_encounter.id)

	# Taken before the rooms are built, because building them is what has to know, and dropped in the
	# same breath: this describes the floor being opened right now, and a descent out of it must not
	# arrive on the next floor carrying the last one's cleared rooms.
	var progress := _resume if _resume != null else FloorProgress.new()
	_resume = null

	_loop = RoomLoop.new()
	_loop.name = "RoomLoop"
	_session.add_child(_loop)
	_loop.setup(config, _player, _session.loot, get_view_rect_for, progress)
	_loop.room_entered.connect(room_entered.emit)

	_build_floor(progress.shop)
	_open_arena(progress.boss_reward_ids)
	_loop.place_player_at_start(layout.get_start_room().id)

	# The next floor starts loading now, while the player has this one to fight through. By the time
	# they claim the boss reward it is usually already in memory, which takes the whole cost of a
	# floor's templates, tile sheets and enemy scenes out of the one frame the transition happens in.
	if campaign != null and floor_index >= 0:
		campaign.preload_floor(floor_index + 1)


## Stands up this floor's boss fight in its arena (see `BossArena`), and puts back the prize a
## resumed run left standing unclaimed there, if it left one. `resumed_reward` is empty for every
## other floor opening, which is nearly all of them.
func _open_arena(resumed_reward: Array[StringName]) -> void:
	var arenas := layout.find_by_type(RoomTemplate.Type.BOSS)
	if arenas.is_empty():
		return
	var plan: RoomPlan = arenas[0]
	_arena = BossArena.new()
	_arena.name = "BossArena"
	_session.add_child(_arena)
	_arena.setup(
		_loop.get_room(plan.id), _boss_encounter, config.shop, is_final_floor(), _draw_boss_reward,
		config.floor_number,
	)
	_arena.encountered.connect(boss_encountered.emit)
	_arena.defeated.connect(_loop.open_after_boss)
	_arena.finished.connect(_finish_floor)
	_loop.boss_room_entered.connect(_arena.summon)
	_arena.restore_prize(resumed_reward, config.get_items(), is_room_cleared(plan.id))


## Points every subsystem's generator at its own stream of this floor's seed.
##
## The layout's stream is not here: `FloorGenerator` is handed a seed and makes its own generator,
## because generation happens *before* a session is opened — it is the one step of a descent that
## may fail, and it has to fail while the player is still standing on the floor they have.
func _seed_streams(seed_value: int) -> void:
	_boss_rng.seed = RunRng.stream_seed(seed_value, RunRng.BOSS)
	_encounter_rng.seed = RunRng.stream_seed(seed_value, RunRng.ENCOUNTER)
	_shop_rng.seed = RunRng.stream_seed(seed_value, RunRng.SHOP)
	_reward_rng.seed = RunRng.stream_seed(seed_value, RunRng.REWARD)


## A fingerprint of this floor's content and seed. What a bug report carries so that "floor 3 does
## not generate like that any more" can be answered with "the content changed" — see `RunManifest`.
func get_content_fingerprint() -> String:
	return _content_fingerprint


## The run is over, or the scene is being reloaded, or the game is quitting — all of which reach
## here, and any of which can happen while the next floor is still loading in the background. An
## uncollected request outlives the process; see `FloorEntry.discard_preload`.
func _exit_tree() -> void:
	if campaign != null:
		campaign.discard_preloads()


## This floor's session. Null before the first `build`; a different node after every boundary.
func get_session() -> FloorSession:
	return _session


## Which boss guards this floor. Null before `build()` has run.
func get_boss_encounter() -> BossEncounter:
	return _boss_encounter


## Draws this floor's boss (see `BossEncounterDraw` for the policy) and credits the run with it.
func _draw_boss_encounter() -> BossEncounter:
	var entry := BossEncounterDraw.draw(
		config.boss_pool,
		RunManager.fought_boss_ids,
		RunManager.current_floor_boss_id(),
		_boss_rng,
		"%d ('%s')" % [config.floor_number, config.id],
	)
	return _claim_boss(entry) if entry != null else null


## Records that the run has met `entry`, and hands it back so the draw above reads as one
## expression.
##
## Appended only if it is not already there. The two paths that can hand this a boss the run has
## already fought — a floor taking its own boss back, and an exhausted pool repeating one — would
## otherwise write a second copy of the same id, and a duplicate in that list is a checkpoint this
## build refuses to load: `RunCheckpoint._validate_collections` treats it as a boss credited twice,
## which is exactly what it would be if anything else had produced it.
func _claim_boss(entry: BossEncounter) -> BossEncounter:
	if entry.id not in RunManager.fought_boss_ids:
		RunManager.fought_boss_ids.append(entry.id)
	return entry


## This floor's boss fight. Null before the first `build`; a different node after every boundary.
func get_boss_arena() -> BossArena:
	return _arena


## This floor's room loop. Null before the first `build`; a different node after every boundary.
func get_room_loop() -> RoomLoop:
	return _loop


## This floor's doors by room. A new set after every boundary.
func get_doors() -> FloorDoors:
	return _loop.get_doors() if _loop != null else FloorDoors.new()


func get_room(id: int) -> Room:
	return _loop.get_room(id) if _loop != null else null


func get_current_room() -> Room:
	return _loop.get_current_room() if _loop != null else null


func is_room_cleared(id: int) -> bool:
	return _loop != null and _loop.is_room_cleared(id)


## The 480x270 view rectangle that frames a room. Horizontally centred; vertically pushed up
## so the HUD strip along the bottom does not cover the room.
func get_view_rect_for(room: Room) -> Rect2i:
	var view_size := Vector2i(get_viewport_rect().size)
	var outer := room.get_outer_rect()
	return Rect2i(
		Vector2i(outer.position.x - (view_size.x - outer.size.x) / 2, outer.position.y - ROOM_TOP_MARGIN),
		view_size
	)


## Puts this floor's rooms, doors and shop into the session — see `FloorBuilder`, which does the
## building — and hands the rooms and doors to the room loop. `resumed_shop` is the shelf a resumed
## run left in this floor's shop, or null for a floor being opened for the first time.
func _build_floor(resumed_shop: ShopStock = null) -> void:
	var builder := FloorBuilder.new()
	builder.build_rooms(
		_session, layout, config, _encounter_rng, _shop_rng, _loop.cleared_set(), resumed_shop
	)
	_shop = builder.shop
	_loop.attach(builder.rooms, builder.build_doors(_session, layout))


## Whether this is the floor the campaign ends on, and therefore the floor whose boss stands over a
## trophy rather than over three stands. The same question `_finish_floor` asks to decide between
## winning and descending, asked once and by one name so the two answers cannot disagree — a floor
## that offered a trophy and then descended, or offered hardware and then won, would be worse than
## either mistake on its own.
##
## Content with no campaign — a test arena, a floor opened on its own — is terminal, exactly as it
## is for `_finish_floor`: a floor with nothing after it is the last one.
func is_final_floor() -> bool:
	return campaign == null or campaign.is_terminal(floor_index)


## What the boss's offer is holding, for a checkpoint taken while it is standing unclaimed — see
## `BossArena.pending_reward_ids`. Empty when there is no arena.
func get_pending_boss_reward_ids() -> Array[StringName]:
	return _arena.pending_reward_ids() if _arena != null else [] as Array[StringName]


## Winning the run and advancing to the next floor are the same event from the boss's point of
## view — "this floor is done" — so both call sites funnel through here rather than deciding for
## themselves. There are two ways in and only two, and both are the player choosing to leave: a
## stand emptied of its item, and a trophy picked up off the floor. Being the last floor the
## *campaign* lists is what makes a floor the run's last one; it used to be having no
## `next_floor`, which was the same fact restated once per floor.
func _finish_floor() -> void:
	# The loss wins the race. A hazard committed before the boss died is allowed to kill the player
	# while the reward stands unclaimed — that is the feature, not a defect — but a run that has
	# already ended must not then descend, win, or hand anything over.
	#
	# It is a genuine race and not a theoretical one. `choice_taken` and a compile lane's strike
	# can land in the same frame, in either order, and both paths below are deferred: a deferred
	# call is flushed by the tree whether or not the tree is paused, so `GameManager.end_run`
	# setting `paused` does not stop a descent that was already scheduled. The run would be filed
	# as a loss, the summary would be on screen, and the next floor would quietly build underneath
	# it.
	#
	# Checked here rather than at the moment of death because death is not the only way in: the
	# empty-pool path in `BossArena.resolve_defeat` reaches this too.
	if GameManager.is_run_over():
		return

	if is_final_floor():
		GameManager.win_run.call_deferred()
		return

	# The destination's seed comes from the *run's* seed and the destination's own id, not from
	# transforming the seed of the floor being left. That is what makes floor 4 the same floor 4
	# whether a run fought through floors 1-3 or `--floor=4` jumped to it — see
	# `RunDefinition.floor_seed_for`. Chaining made a floor's layout a function of every floor
	# before it, so editing floor 2 quietly relaid floors 3 to 6.
	_advance_to_next_floor.call_deferred(
		floor_index + 1, campaign.floor_seed_for(RunManager.get_run_seed(), floor_index + 1)
	)


## Replaces this controller's floor with the campaign's next one. Deferred by the caller because
## this runs from inside a pickup's physics callback (the boss reward stand), and this project has
## hit "touching physics bodies while the server is flushing queries is refused outright" enough
## times already (see `BossArena._add_boss`, `LootSpawner`) that rebuilding synchronously in that same
## callback is not worth risking again.
##
## A transaction, in the order that makes it one:
##
##   1. **Preflight.** Load the destination and generate its layout. Both can fail, and both fail
##      here — while the floor the player is standing on is still whole and still theirs.
##   2. **Commit.** Close the old session so nothing queued against it can still land, take it out
##      of the tree so it stops answering as the projectile container, and release it.
##   3. **Open.** Build the new session from the layout preflight already produced.
##
## The old order was teardown-then-build, which meant a destination that would not generate left
## the run in `RUN` with no floor at all: no rooms, no doors, a player standing in a void, and no
## way to reach a menu. Nothing about that state was recoverable, and it was reachable by a typo
## in a `.tres`.
func _advance_to_next_floor(next_index: int, seed_value: int) -> void:
	# Re-checked rather than inherited from `_finish_floor`, because everything between the two is
	# a frame the run can end in — and a lane painted before the boss died is precisely the thing
	# that resolves in it.
	if GameManager.is_run_over():
		return

	var next_config := campaign.load_floor(next_index)
	if next_config == null:
		push_error(
			"FloorController: floor %d ('%s') would not load; staying on floor %d."
			% [next_index + 1, campaign.floor_id_at(next_index), config.floor_number]
		)
		return

	var generated := FloorGenerator.generate(
		next_config, RunRng.stream_seed(seed_value, RunRng.LAYOUT)
	)
	if generated == null:
		# Same stance as main.gd's own build() call: a content bug, not something to hide behind a
		# blank screen. The difference from before is that the player is still on a playable floor
		# while it is reported.
		push_error(
			"FloorController: floor %d generation failed; staying on floor %d."
			% [next_config.floor_number, config.floor_number]
		)
		return

	_release_session()
	# Filed after the commit is certain and before the new floor opens, so a floor's record closes
	# exactly once and in the order it happened. A preflight that failed above returns with the
	# record still open, because the run is still on this floor.
	RunManager.finish_floor(FloorRecord.Outcome.DESCENDED)
	config = next_config
	_open_session(generated, seed_value)
	# Written here, at the one moment in a run when nothing is in flight: the old floor is
	# released, the new one is built and empty, and the run's whole state is a handful of numbers.
	# Anywhere earlier and the checkpoint would describe a floor that is being torn down; anywhere
	# later and it would have to describe a fight in progress. See `RunCheckpoint`.
	RunManager.checkpoint_floor(
		campaign, config, _player, ShopStock.of(_shop), get_pending_boss_reward_ids()
	)
	floor_advanced.emit(config)


## Ends the current floor: everything it owned is freed, and everything the *run* owns is left
## alone.
##
## The whole floor goes at once, because the whole floor is one node. This used to be a list —
## free the rooms, free the doors — and the list was the bug: the loot spawner and the projectile
## container were not on it, so pickups and shots crossed every boundary, and any hazard added
## later would have started out equally forgotten. There is nothing to enumerate now; a thing dies
## with the floor if it was parented inside the session, and that is a decision made where it is
## spawned rather than remembered here.
##
## Order matters, and each step is load-bearing:
##
## - **Close first.** A spawn already queued against this floor has to be refused while there is
##   still a session to refuse it. After the node is freed, the deferred call is dropped silently
##   and the node it would have added is owned by nothing.
## - **Remove from the tree before freeing.** `queue_free` does not take effect until the end of
##   the frame, and `SceneTree.get_first_node_in_group` only sees nodes that are *in* the tree —
##   so a session left parented while the next one is built is a second answer to "where do
##   projectiles go", and it is the one that answers first.
##
## The floor-local half of the run — what the minimap has seen, which room the player is in, how
## many rooms they have cleared *here* — is the room loop's, and goes with it. `RunManager`'s
## cumulative totals are deliberately untouched — that split is what a boundary is.
func _release_session() -> void:
	# The boss fight lives in the session, and takes itself down as the session leaves the tree —
	# including a boss summoned in this frame and not yet added. See `BossArena._exit_tree`.
	if _session != null:
		_session.close()
		remove_child(_session)
		_session.queue_free()
		_session = null

	# The shop, the room loop and the boss's arena die with the session that owns them, so what is
	# dropped here is only this node's references. Stale ones would have the next floor's checkpoint
	# recording the shelves and cleared rooms of the floor the run has left.
	_shop = null
	_loop = null
	_arena = null
	layout = null
	_boss_encounter = null


## Draws the boss's offer (see `BossRewardDraw` for the policy) and spends it: every unique item
## on the stands is struck off the run the moment it is offered, which is what stops the next floor
## offering it again. A chip is never struck off — being offered again is what makes it a chip.
##
## Spent here rather than when the player chooses, because the two items left on the stands were
## still *offered*: the player saw them and passed, exactly as they do an item left lying in a room.
func _draw_boss_reward() -> Array[ItemConfig]:
	var chosen := BossRewardDraw.draw(config.get_items(), RunManager.offered_item_ids, _reward_rng)
	for item: ItemConfig in chosen:
		if not item.is_repeatable():
			RunManager.offered_item_ids.append(item.id)
	return chosen

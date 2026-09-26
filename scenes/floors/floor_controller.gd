class_name FloorController
extends Node2D
## Builds a floor from a generated layout and runs the room loop.
##
## Every room is instantiated up front and laid out on the grid, the way a room-based shooter
## has always done it: the player walks through a doorway into the next room rather than
## triggering a scene load, so there is no transition to hide and no state to serialise. Rooms
## the player is not in have their enemies disabled, so ten rooms of AI is not ten rooms of
## work.
##
## The room loop from spec section 4 lives in `_on_player_entered_room` and
## `_on_room_cleared`: enter a room, doors lock, enemies are live, kill them, doors unlock, a
## reward drops. Everything else here is composition.

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

## Where an item drops relative to the reward point, so it does not land underneath the
## scrap that drops alongside it.
const ITEM_REWARD_OFFSET := Vector2(0.0, -18.0)

@export var config: FloorConfig

## The run's floor order. Assigned in the scene rather than pushed in by `main.gd`, so a
## controller instantiated on its own — which is how every suite that drives a descent builds one
## — knows what floor comes next without a caller having to remember to wire it.
@export var campaign: RunDefinition

var layout: FloorLayout
var current_room_id := -1

## Where `config` sits in `campaign`, resolved in `build()`. -1 for content the campaign does not
## contain, which a run treats as its last floor rather than descending into whatever is at index
## zero — a test arena is a floor with no floor after it, not a floor that loops to the start.
var floor_index := -1

## Room ids the player has been inside, for the minimap.
var visited: Dictionary[int, bool] = {}

var _rooms: Dictionary[int, Room] = {}
## This floor's doors by room. Replaced with each floor, like the rooms themselves.
var _doors := FloorDoors.new()
var _cleared: Dictionary[int, bool] = {}
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

## Combat rooms cleared on this floor, counted here rather than read from RunManager. The
## floor is notified through the room's own `cleared` signal, which fires before the
## EventBus one that RunManager counts — so reading that counter here would silently be
## reading the number from *before* this clear.
var _clears := 0

## This floor's shop, or null for a floor whose layout has no shop room or whose template declares
## no stands. Held because it is the only thing that can say what is on its shelves when a
## checkpoint is written, and because nothing else on the floor can be asked for it: the shop is a
## child of a room, and finding it by walking the tree would be a second answer to a question this
## node already knows the answer to.
var _shop: ShopRoom

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

## Generates and builds the floor. Returns false if generation failed, so the caller can
## report it rather than presenting an empty world.
## Floor-local progress a resumed run is bringing back with it, consumed by the next `build` and
## then forgotten. A field rather than an argument because it applies to exactly one floor — the
## one being resumed onto — and a descent from it must open the next floor untouched. Cleared in
## `_open_session` for that reason, not here.
var _resume_cleared: Array[int] = []
var _resume_visited: Array[int] = []
var _resume_clears := 0

## The shelf the resumed run left in this floor's shop, consumed by the same `build` and forgotten
## the same way. Null rather than an empty stock for "there is nothing saved here", because an empty
## `ShopStock` is a real answer — a floor whose shop has no stands — and the two must not be
## confused: one stocks the shop from the pool and the other deliberately does not.
var _resume_shop: ShopStock = null

## The boss's offer the resumed run left standing unclaimed, by item id, and empty for every
## checkpoint that was not taken in that window. Consumed by the same `build`.
var _resume_boss_reward: Array[StringName] = []


## Tells the next `build` how much of the floor it is about to open was already done, so a run
## resumed from a mid-floor save comes back to the rooms it had cleared rather than to a floor that
## has forgotten them. See `RunCheckpoint.floor_cleared_room_ids`.
##
## `shop` is that floor's shelf, and it is carried by every checkpoint rather than only by a
## mid-floor one — see `ShopStock` for why a shop is not floor *progress* even though it is
## floor-local. `boss_reward` is the offer left standing over a dead boss, which is the one piece of
## floor state whose loss is not merely unfair but final — see `get_pending_boss_reward_ids`.
func resume_floor_progress(
	cleared: Array[int], visited: Array[int], clears: int, shop: ShopStock = null,
	boss_reward: Array[StringName] = []
) -> void:
	_resume_cleared = cleared.duplicate()
	_resume_visited = visited.duplicate()
	_resume_clears = clears
	_resume_shop = shop
	_resume_boss_reward = boss_reward.duplicate()


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
	if _player == null or not is_instance_valid(_player) or campaign == null:
		return false
	var cleared: Array[int] = []
	for id: int in _cleared:
		if _cleared[id]:
			cleared.append(id)
	var visited_ids: Array[int] = []
	for id: int in visited:
		if visited[id]:
			visited_ids.append(id)
	return RunManager.checkpoint_here(
		campaign, config, _player, ShopStock.of(_shop), get_pending_boss_reward_ids(),
		cleared, visited_ids, _clears
	)


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

	# Taken before the rooms are built, because `_build_floor` is what has to know, and
	# emptied in the same breath: this describes the floor being opened right now, and a descent
	# out of it must not arrive on the next floor carrying the last one's cleared rooms.
	var resumed_cleared := _resume_cleared
	var resumed_visited := _resume_visited
	var resumed_shop := _resume_shop
	var resumed_reward := _resume_boss_reward
	_clears = _resume_clears
	_resume_cleared = []
	_resume_visited = []
	_resume_clears = 0
	_resume_shop = null
	_resume_boss_reward = []
	for id: int in resumed_cleared:
		_cleared[id] = true
	for id: int in resumed_visited:
		visited[id] = true

	_build_floor(resumed_shop)
	_open_arena(resumed_reward)
	_place_player_in_start_room()

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
		_rooms[plan.id], _boss_encounter, config.shop, is_final_floor(), _draw_boss_reward,
		config.floor_number,
	)
	_arena.encountered.connect(boss_encountered.emit)
	_arena.defeated.connect(_on_boss_defeated)
	_arena.finished.connect(_finish_floor)
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


## This floor's doors by room. A new set after every boundary.
func get_doors() -> FloorDoors:
	return _doors


func get_room(id: int) -> Room:
	return _rooms.get(id)


func get_current_room() -> Room:
	return _rooms.get(current_room_id)


func is_room_cleared(id: int) -> bool:
	return _cleared.get(id, false)


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
## building. `resumed_shop` is the shelf a resumed run left in this floor's shop, or null for a floor
## being opened for the first time. Threaded down from `_open_session` rather than read off a field,
## because a field would have to stay set across the build — one more thing that has to be cleared
## at exactly the right moment.
func _build_floor(resumed_shop: ShopStock = null) -> void:
	var builder := FloorBuilder.new()
	builder.build_rooms(
		_session, layout, config, _encounter_rng, _shop_rng, _cleared, resumed_shop,
		_on_player_entered_room, _on_room_cleared,
	)
	_rooms = builder.rooms
	_shop = builder.shop
	_doors = builder.build_doors(_session, layout)


func _place_player_in_start_room() -> void:
	var start := layout.get_start_room()
	var room := _rooms[start.id]
	_player.global_position = room.get_interior_centre()
	_player.frame_room(get_view_rect_for(room), true)
	# The entry Area2D will not fire for a body already inside it at spawn, so the start room
	# is entered explicitly.
	_enter_room(start.id)


## The trigger is not taken at its word, because a descent can make it lie. `build()` puts the
## new floor's rooms into the world before `_place_player_in_start_room` moves the player off
## the old floor's coordinates, so the new room that lands on the spot the player took the boss
## reward from registers an overlap the moment it is added. Godot delivers that `body_entered`
## on the next physics flush — after the start room was entered explicitly, which is what let it
## win — and the room it names is a room the player has never been in.
##
## Cosmetic for a combat room, which is re-entered properly a moment later. Not cosmetic for the
## boss room: `_enter_room` spawns the boss, so Development opened with its boss already awake in
## an empty arena and its health bar on screen for the whole floor. Room ids are assigned in a
## fixed order (`FloorGenerator.SPECIAL_TYPES`), so the boss is id 7 on every ten-room floor and
## the two floors' boss rooms landing on the same cell is all it takes.
##
## Asking where the player actually is costs one rect test and never rejects a real entry: the
## entry Area2D is inset from the interior this is testing against, so a player far enough in to
## trip the trigger is comfortably inside the rect.
func _on_player_entered_room(room: Room) -> void:
	if room.plan.id == current_room_id:
		return
	if _player == null or not room.get_interior_rect().has_point(_player.global_position):
		return
	_enter_room(room.plan.id)


func _enter_room(id: int) -> void:
	var previous_id := current_room_id
	current_room_id = id
	visited[id] = true

	var room := _rooms[id]
	# Not snapped: the camera pans across the doorway, which shows the player where they came
	# from and reads as one continuous space rather than a cut.
	_player.frame_room(get_view_rect_for(room), false)

	if previous_id >= 0 and previous_id != id:
		_rooms[previous_id].set_active(false)
	room.set_active(true)

	# Not for an arena a resumed run had already won. Without the clearing check a player who saved
	# after killing the boss and before taking the reward would walk back into a second one — and
	# `fought_boss_ids` would deny them the credit for it, so it would be a fight for nothing.
	if room.plan.type == RoomTemplate.Type.BOSS and _arena != null and not is_room_cleared(id):
		_arena.summon()

	if _needs_clearing(id):
		_doors.set_locked(id, true)
	else:
		_doors.set_locked(id, false)
		_award_first_visit(id)

	EventBus.room_entered.emit(room.plan.type, room.plan.id)
	room_entered.emit(room.plan)


## A room needs clearing if something in it is still alive and it has not already been
## cleared, which is also exactly when its doors should be shut. The boss counts: sealing
## the player in with it is the point of a boss room.
func _needs_clearing(id: int) -> bool:
	if is_room_cleared(id):
		return false
	if _rooms[id].plan.type == RoomTemplate.Type.BOSS:
		# Not "is the boss alive": the boss is added a frame late (see below), and a boss
		# room whose doors stayed open for that frame is a boss room the player can walk
		# straight back out of. A boss room is sealed until it is cleared, full stop.
		return true
	return _rooms[id].has_living_enemies()


## The boss has fallen: the arena is cleared and its doors open, before the prize goes up. See
## `BossArena` for why nothing else is made safe at this moment.
func _on_boss_defeated(room_id: int) -> void:
	_cleared[room_id] = true
	_doors.set_locked(room_id, false)


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

	if campaign == null or campaign.is_terminal(floor_index):
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
## The counters below are the floor-local half of the run: what the minimap has seen, which room
## the player is in, how many rooms they have cleared *here*. `RunManager`'s cumulative totals are
## deliberately untouched — that split is what a boundary is.
func _release_session() -> void:
	# The boss fight lives in the session, and takes itself down as the session leaves the tree —
	# including a boss summoned in this frame and not yet added. See `BossArena._exit_tree`.
	if _session != null:
		_session.close()
		remove_child(_session)
		_session.queue_free()
		_session = null

	# The shop and the boss's arena die with the session that owns them, so what is dropped here is
	# only this node's references. Stale ones would have the next floor's checkpoint recording the
	# shelves of the floor the run has left.
	_shop = null
	_arena = null

	_rooms.clear()
	_doors = FloorDoors.new()
	_cleared.clear()
	visited.clear()
	layout = null
	current_room_id = -1
	_clears = 0
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


func _on_room_cleared(id: int) -> void:
	_cleared[id] = true
	_doors.set_locked(id, false)
	_clears += 1

	var room := _rooms[id]
	# Every third room clear (see `FloorConfig.repair_every_clears`) also drops a repair cell, so
	# integrity is recoverable without making it so plentiful that damage stops mattering.
	#
	# Counted from `_clears` above, not from `RunManager.rooms_cleared`. RoomCombat emits its
	# local `cleared` signal — which is what brought us here — *before* the EventBus one that
	# RunManager counts, so that value is still one behind while this runs. Reading it dropped
	# repair cells on clears 1 and 4 instead of 3 and 6: the first arriving while the player
	# was still at full integrity and could not use it. The line below already used `_clears`,
	# so two counters for one idea sat next to each other, one of them wrong.
	_session.loot.spawn_room_reward(room.get_reward_position(), config.clear_drops_repair(_clears))

	# Items are the reason to keep fighting rather than to run for the exit, so most of a
	# floor's items come from clearing rooms rather than from the one treasure vault.
	if config.clear_drops_item(_clears):
		_session.loot.spawn_item(room.get_reward_position() + ITEM_REWARD_OFFSET)


## Payout for walking into a room that needs no fighting. The treasure room is the reason to
## explore a dead end rather than heading straight on.
func _award_first_visit(id: int) -> void:
	if _cleared.get(id, false):
		return
	_cleared[id] = true

	var room := _rooms[id]
	if room.plan.type != RoomTemplate.Type.TREASURE:
		return
	if config.treasure_grants_item:
		_session.loot.spawn_treasure(room.get_reward_position())
	else:
		_session.loot.spawn_room_reward(room.get_reward_position(), true)

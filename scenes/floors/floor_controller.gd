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
## has no other way to learn (see `FloorConfig.boss_display_name`).
signal boss_encountered(display_name: String, defeat_banner: String, phase_banners: Array[String])

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const DOOR_SCENE := preload("res://scenes/rooms/door.tscn")
const SHOP_ROOM_SCENE := preload("res://scenes/shop/shop_room.tscn")
const SESSION_SCENE := preload("res://scenes/floors/floor_session.tscn")

## How many rare items the boss offers, and where they stand relative to the reward point.
## Spec section 16: choose one of three.
const BOSS_REWARD_COUNT := 3

## Wide enough for the stands' labels, which is the only thing that decides it: at the 56 pixels this
## used to be, three item names written above three stands 56 pixels apart overlapped into something
## unreadable, and the reward the fight is for was the one choice in the run the player could not
## read. `ShopStand.LABEL_WIDTH` plus a gutter, and tests/test_shop.gd holds the two together.
const BOSS_REWARD_SPACING := 128.0

## How far below the top of the screen a room's outer wall sits. The remaining space at the
## bottom is the HUD strip, so the HUD never covers playable floor.
const ROOM_TOP_MARGIN := 4

## Where an item drops relative to the reward point, so it does not land underneath the
## scrap that drops alongside it.
const ITEM_REWARD_OFFSET := Vector2(0.0, -18.0)

## How many room clears between repair cells. Named rather than inlined because it is the one
## number deciding how recoverable a bad run is — over a ten-room floor the difference between
## 3 and 2 is an extra integrity point, which is a sixth of the player's whole pool.
const REPAIR_EVERY_CLEARS := 3

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
var _doors_by_room: Dictionary[int, Array] = {}
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

## The boss, once the player has walked into its arena. Null until then — a boss that
## existed from the moment the floor was built would be a boss firing at an empty room.
var _boss: Boss

## Which boss guards this floor, drawn once in `build()`.
var _boss_encounter: BossEncounter

## This floor's disposable half: its rooms, doors, loot, projectiles, and hazards. Replaced
## wholesale at every boundary — see `_open_session` and `_release_session`.
var _session: FloorSession

## Counts sessions opened, and is what deferred floor-local work is checked against. Kept on the
## controller rather than the session because the session it belongs to is the thing being freed,
## and a token has to outlive what it invalidates.
var _generation := 0

## The bound `EventBus.boss_defeated` handler, held so it can be taken back down. A bound callable
## cannot be reconstructed for `is_connected` — `_on_boss_defeated.bind(room)` makes a different
## Callable every time it is written — so the one that was connected is the one that has to be
## kept. Without it a floor released before its boss died leaves a connection pointing at a room
## that no longer exists.
var _boss_defeated_handler := Callable()


## Generates and builds the floor. Returns false if generation failed, so the caller can
## report it rather than presenting an empty world.
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
	RunManager.record_floor_boss(_boss_encounter.id if _boss_encounter != null else &"")

	_instantiate_rooms()
	_instantiate_doors()
	_place_player_in_start_room()

	# The next floor starts loading now, while the player has this one to fight through. By the time
	# they claim the boss reward it is usually already in memory, which takes the whole cost of a
	# floor's templates, tile sheets and enemy scenes out of the one frame the transition happens in.
	if campaign != null and floor_index >= 0:
		campaign.preload_floor(floor_index + 1)


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


## Picks this floor's boss from its pool. Never one the run has already fought.
##
## The campaign policy is one distinct boss per floor, so a repeat is not a degraded outcome to
## fall back on — it is a content error, and this is where it becomes visible instead of silent.
##
## It used to fall back to the whole pool once everything had been fought, on the reasoning that a
## repeated boss is a better run than a boss-less one. That reasoning was sound while there were
## two floors and two bosses, because the fallback was unreachable. At six floors it stops being a
## safety net and becomes the actual behaviour: floors 3, 4, 5 and 6 would each quietly re-run a
## fight the player had already won, and nothing anywhere would say so. A player cannot tell an
## intended rematch from an exhausted pool, and neither could the log.
##
## Refusing instead is safe because the failure cannot reach a player: `CampaignValidator` proves
## before the run starts that every floor can be given a boss of its own, so an empty draw here
## means the campaign was never validated. Loud and once, rather than quiet and four times.
func _draw_boss_encounter() -> BossEncounter:
	var unfought: Array[BossEncounter] = []
	for entry: BossEncounter in config.boss_pool:
		if entry == null or not entry.is_valid():
			continue
		if entry.id not in RunManager.fought_boss_ids:
			unfought.append(entry)

	if unfought.is_empty():
		push_error(
			("FloorController: floor %d ('%s') has no boss the run has not already fought. "
			+ "The campaign must give every floor a boss of its own — see CampaignValidator.")
			% [config.floor_number, config.id]
		)
		return null

	var drawn := unfought[_boss_rng.randi_range(0, unfought.size() - 1)]
	RunManager.fought_boss_ids.append(drawn.id)
	return drawn


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


func _instantiate_rooms() -> void:
	for plan: RoomPlan in layout.rooms:
		var room: Room = ROOM_SCENE.instantiate()
		# Grid cell to world: the room's interior origin sits one wall inside its cell.
		room.position = Vector2(plan.cell * Room.OUTER_SIZE + Vector2i.ONE * Room.WALL_THICKNESS)
		_session.rooms.add_child(room)

		room.build(plan, config.theme)
		if plan.type == RoomTemplate.Type.COMBAT:
			room.populate(config, _encounter_rng)
		elif plan.type == RoomTemplate.Type.SHOP:
			_stock_shop(room)
		room.set_active(false)
		room.player_entered.connect(_on_player_entered_room)
		room.get_room_combat().cleared.connect(_on_room_cleared.bind(plan.id))
		_rooms[plan.id] = room


## Builds the shop's stands. Stocked at floor build time rather than on entry, so the
## items it holds are drawn from the pool before any room reward can take them — a shop
## whose stock depended on when the player happened to walk in would be a shop that got
## worse the longer they explored.
##
## The shop is handed one number from this floor's shop stream and seeds itself from it, rather
## than sharing a generator: the room it stands in is instantiated among nine others, and a shop
## reading from the stream the rooms are populated from would restock itself every time an enemy
## placement changed.
func _stock_shop(room: Room) -> void:
	var positions := room.get_shop_positions()
	if config.shop == null or positions.is_empty():
		return
	var shop: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	room.add_child(shop)
	shop.stock(config.shop, config.get_items(), positions, _shop_rng.randi())


## One door per link, filling the passage between two rooms. Each link is visited once — the
## adjacency is symmetric, so iterating every room's doors would build each door twice.
func _instantiate_doors() -> void:
	for plan: RoomPlan in layout.rooms:
		for direction: Vector2i in plan.doors:
			var neighbour_id: int = plan.doors[direction]
			if neighbour_id < plan.id:
				continue

			var horizontal := direction.x != 0
			var passage := (
				Vector2i(Room.WALL_THICKNESS * 2, Room.DOOR_WIDTH) if horizontal
				else Vector2i(Room.DOOR_WIDTH, Room.WALL_THICKNESS * 2)
			)

			var door: Door = DOOR_SCENE.instantiate()
			_session.doors.add_child(door)
			door.global_position = _door_centre(plan, direction)
			door.setup(passage)

			for id: int in [plan.id, neighbour_id]:
				if not _doors_by_room.has(id):
					_doors_by_room[id] = []
				_doors_by_room[id].append(door)


## The midpoint of the shared boundary between a room's cell and its neighbour's.
func _door_centre(plan: RoomPlan, direction: Vector2i) -> Vector2:
	var outer_centre := Vector2(plan.cell * Room.OUTER_SIZE) + Vector2(Room.OUTER_SIZE) * 0.5
	return outer_centre + Vector2(direction) * Vector2(Room.OUTER_SIZE) * 0.5


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

	if room.plan.type == RoomTemplate.Type.BOSS and _boss == null:
		_spawn_boss(room)

	if _needs_clearing(id):
		_set_doors_locked(id, true)
	else:
		_set_doors_locked(id, false)
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


## Wakes the boss when the player walks in. The arena it is handed is the room's interior,
## so the boss lays out its terminals and clamps its own movement without ever asking what
## room it is in.
func _spawn_boss(room: Room) -> void:
	if _boss_encounter == null or not _boss_encounter.is_valid():
		push_error("FloorController: floor %d has no usable boss." % config.floor_number)
		return
	_boss = _boss_encounter.scene.instantiate()
	boss_encountered.emit(
		_boss_encounter.display_name,
		_boss_encounter.defeat_banner,
		_boss_encounter.phase_banners,
	)
	# One-shot: a boss is defeated exactly once per floor, and this controller now outlives a
	# single floor. Without it, the next floor's boss spawn would stack a second connection,
	# and its death would also invoke the handler still bound to this (by-then-freed) room.
	#
	# Held rather than only connected, because one-shot only covers the boss that *dies*. A floor
	# abandoned with its boss alive — a restart, a death, a campaign edit — leaves this pointing at
	# a room that is about to be freed, and `_release_session` is what takes it back down.
	_boss_defeated_handler = _on_boss_defeated.bind(room)
	EventBus.boss_defeated.connect(_boss_defeated_handler, CONNECT_ONE_SHOT)
	# Deferred, for the fourth time in this project and the same reason every time: rooms
	# are entered through an Area2D trigger, and registering the boss's collision bodies
	# while the physics server is flushing queries is refused outright.
	_add_boss.call_deferred(room, _generation)


## `generation` is the floor this boss was summoned for. A boss walked into on the same frame a
## floor is released would otherwise be added to a room from the floor being left — and the boss
## is the one deferred spawn whose arrival is loud, since it brings a health bar and an arena with
## it. The instance is freed rather than dropped: it was created in `_spawn_boss` and, unparented,
## nothing else would ever free it.
func _add_boss(room: Room, generation: int) -> void:
	if not is_instance_valid(_boss):
		return
	if generation != _generation or not is_instance_valid(room) or not room.is_inside_tree():
		_boss.queue_free()
		_boss = null
		return
	room.add_child(_boss)
	_boss.begin(room.get_interior_rect())


## Spec section 16's reward: three rare items on stands, and taking one closes the others.
## Winning the run waits on that choice rather than on the killing blow, so the player is
## never shown a victory screen with an unclaimed prize behind it.
##
## **Nothing is made safe here, and that is deliberate.** No projectile is cleared, no compile lane
## is cancelled, and the player is granted no immunity. An attack that was fired or painted before
## the boss died goes on to resolve, and it can damage or kill the player while the reward is
## standing there — the fight is over when the arena is, not when the health bar empties. A player
## who empties the pool and walks into the prize through their own last volley has earned the
## death.
##
## The reason to say this out loud is that it looks exactly like a bug from the outside, and the
## obvious fix — sweep the hazards when `boss_defeated` fires — is one line and would be silently
## accepted by every test in this project that predates `tests/test_post_boss.gd`. That suite
## exists to make the removal fail loudly. What a dead boss must not do is start anything *new*;
## both bosses enforce that themselves by refusing to run their attack clock once dead.
##
## `_finish_floor` is where the other half lives: the hazards stay live, but if one of them kills
## the player first, the loss wins.
func _on_boss_defeated(_boss_node: Node, room: Room) -> void:
	_cleared[room.plan.id] = true
	_set_doors_locked(room.plan.id, false)

	var items := _draw_boss_reward()
	if items.is_empty():
		# Nothing left in the pool to offer. Winning must not depend on there being a prize:
		# an empty choice creates zero stands, `choice_taken` never fires, and the run would
		# sit in a cleared arena with a dead boss and no victory — which is exactly how this
		# was reported. The boss is dead and the floor is done, so the run is won.
		#
		# Deferred, for the sixth time in this project and the same reason every time: this
		# runs inside the boss's damage callback, and winning pauses the tree. Pausing the
		# scene tree while the physics server is flushing leaked nineteen objects and four
		# audio streams — measured, by taking this path with a deliberately emptied pool. The
		# ordinary reward path is already outside the callback, which is why it never showed
		# this.
		push_warning("FloorController: no items left for the boss reward; winning without one.")
		_finish_floor()
		return

	var reward: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	room.add_child(reward)
	reward.choice_taken.connect(_on_boss_reward_taken)
	reward.stock_choice(config.shop, items, _boss_reward_positions(room))


func _on_boss_reward_taken(_item: ItemConfig) -> void:
	_finish_floor()


## Winning the run and advancing to the next floor are the same event from the boss's point of
## view — "this floor is done" — so both call sites funnel through here rather than deciding for
## themselves. Being the last floor the *campaign* lists is what makes a floor the run's last one;
## it used to be having no `next_floor`, which was the same fact restated once per floor.
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
	# empty-pool path in `_on_boss_defeated` reaches this too.
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
## times already (see `_add_boss`, `LootSpawner`) that rebuilding synchronously in that same
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
	if _boss_defeated_handler.is_valid():
		if EventBus.boss_defeated.is_connected(_boss_defeated_handler):
			EventBus.boss_defeated.disconnect(_boss_defeated_handler)
		_boss_defeated_handler = Callable()

	# Only reachable when the floor ends between the boss being summoned and the deferred add
	# landing. Unparented, it is owned by nothing and freed by nothing.
	if is_instance_valid(_boss) and _boss.get_parent() == null:
		_boss.queue_free()
	_boss = null

	if _session != null:
		_session.close()
		remove_child(_session)
		_session.queue_free()
		_session = null

	_rooms.clear()
	_doors_by_room.clear()
	_cleared.clear()
	visited.clear()
	layout = null
	current_room_id = -1
	_clears = 0
	_boss_encounter = null


## Spec section 16's choice of three: rare items by preference, shuffled, and never all bad.
##
## This method shipped broken in two ways that compounded into one very visible bug. It walked the
## pool in *file order* and took the first three eligible entries, so the choice was not a draw at
## all — every player who reached the first boss was offered the same three items, run after run.
## And "rare or better" is `rarity >= RARE`, which includes CORRUPTED: the shared pool happens to
## begin with Blocking I/O, Tech Debt and Legacy Runtime, which are precisely the three items the
## design calls pure costs. Every first boss in the game handed the player a choice between a
## weapon that will not fire while moving, permanent enemy growth, and a tripled dash cooldown,
## with no way to decline. That is not opt-in pressure, it is a toll.
##
## Both halves are fixed here. The candidates are shuffled with the floor's own seeded RNG, so the
## choice varies by run and is still reproducible from `--seed`. And one slot is reserved for an
## item that gives something back: hindrances remain in the pool and remain offerable, but they can
## no longer occupy the whole set of stands.
##
## Rarity ordering is preserved within each group, so a boss still offers the best the pool has.
## Repeatable chips are last: they are the guarantee that three stands can always be filled, not a
## prize a boss should be handing out while unique items remain.
func _draw_boss_reward() -> Array[ItemConfig]:
	var rare_gifts: Array[ItemConfig] = []
	var rare_hindrances: Array[ItemConfig] = []
	var common_gifts: Array[ItemConfig] = []
	var common_hindrances: Array[ItemConfig] = []
	var repeatables: Array[ItemConfig] = []

	for item: ItemConfig in config.get_items():
		if item == null:
			continue
		if item.is_repeatable():
			repeatables.append(item)
			continue
		if item.id in RunManager.offered_item_ids:
			continue
		if item.rarity >= ItemConfig.Rarity.RARE:
			if item.is_hindrance():
				rare_hindrances.append(item)
			else:
				rare_gifts.append(item)
		elif item.is_hindrance():
			common_hindrances.append(item)
		else:
			common_gifts.append(item)

	for group: Array in [rare_gifts, rare_hindrances, common_gifts, common_hindrances, repeatables]:
		_shuffle(group)

	# The reserved slot goes first, so that if the pool can only fill one stand it fills it with
	# something worth taking.
	var chosen: Array[ItemConfig] = []
	var beneficial: Array[Array] = [rare_gifts, common_gifts, repeatables]
	for group: Array in beneficial:
		if not group.is_empty():
			_take_reward(chosen, group[0])
			group.remove_at(0)
			break

	for group: Array in [rare_gifts, rare_hindrances, common_gifts, common_hindrances, repeatables]:
		for item: ItemConfig in group:
			if chosen.size() >= BOSS_REWARD_COUNT:
				break
			_take_reward(chosen, item)

	return chosen


## Adds `item` to the offer and spends it, unless it is a chip — a repeatable is never struck off
## the run, which is the whole of what makes it repeatable.
func _take_reward(chosen: Array[ItemConfig], item: ItemConfig) -> void:
	chosen.append(item)
	if not item.is_repeatable():
		RunManager.offered_item_ids.append(item.id)


## Fisher-Yates against this floor's own RNG, so the boss's choice is decided by the floor seed and
## nothing else. `Array.shuffle` would use the global generator, which is seeded from the clock and
## would make one `--seed` stop reproducing the reward it was reported with.
func _shuffle(items: Array) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var swap := _reward_rng.randi_range(0, index)
		var held: Variant = items[index]
		items[index] = items[swap]
		items[swap] = held


func _boss_reward_positions(room: Room) -> Array[Vector2]:
	var centre := room.get_reward_position()
	var positions: Array[Vector2] = []
	for index: int in BOSS_REWARD_COUNT:
		var offset := (float(index) - float(BOSS_REWARD_COUNT - 1) * 0.5) * BOSS_REWARD_SPACING
		positions.append(centre + Vector2(offset, 0.0))
	return positions


func _on_room_cleared(id: int) -> void:
	_cleared[id] = true
	_set_doors_locked(id, false)
	_clears += 1

	var room := _rooms[id]
	# Every third room clear also drops a repair cell, so integrity is recoverable without
	# making it so plentiful that damage stops mattering.
	#
	# Counted from `_clears` above, not from `RunManager.rooms_cleared`. RoomCombat emits its
	# local `cleared` signal — which is what brought us here — *before* the EventBus one that
	# RunManager counts, so that value is still one behind while this runs. Reading it dropped
	# repair cells on clears 1 and 4 instead of 3 and 6: the first arriving while the player
	# was still at full integrity and could not use it. The line below already used `_clears`,
	# so two counters for one idea sat next to each other, one of them wrong.
	var include_repair := _clears % REPAIR_EVERY_CLEARS == 0
	_session.loot.spawn_room_reward(room.get_reward_position(), include_repair)

	# Items are the reason to keep fighting rather than to run for the exit, so most of a
	# floor's items come from clearing rooms rather than from the one treasure vault.
	if _clears in config.item_clear_indices:
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


## Only reports a change when a door actually moved, so re-entering a cleared room does not
## replay the door sound every time.
func _set_doors_locked(id: int, locked: bool) -> void:
	var changed := false
	for door: Door in _doors_by_room.get(id, []):
		if door.is_locked() == locked:
			continue
		if locked:
			door.lock()
		else:
			door.unlock()
		changed = true

	if changed:
		EventBus.doors_changed.emit(locked)

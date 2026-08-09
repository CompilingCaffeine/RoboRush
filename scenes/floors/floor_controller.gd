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

var layout: FloorLayout
var current_room_id := -1

## Room ids the player has been inside, for the minimap.
var visited: Dictionary[int, bool] = {}

var _rooms: Dictionary[int, Room] = {}
var _doors_by_room: Dictionary[int, Array] = {}
var _cleared: Dictionary[int, bool] = {}
var _player: Player
var _rng := RandomNumberGenerator.new()

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

@onready var _rooms_container: Node2D = %Rooms
@onready var _doors_container: Node2D = %Doors
@onready var _loot: LootSpawner = %LootSpawner


## Generates and builds the floor. Returns false if generation failed, so the caller can
## report it rather than presenting an empty world.
func build(player: Player, seed_value: int) -> bool:
	assert(config != null, "FloorController.config is unset: assign a FloorConfig resource.")
	_player = player
	_rng.seed = seed_value
	floor_theme_changed.emit(config.theme)

	layout = FloorGenerator.generate(config, seed_value)
	if layout == null:
		return false

	_loot.setup(config, seed_value)
	RunManager.floor_number = config.floor_number
	RunManager.floor_name = config.display_name
	RunManager.floor_seed = seed_value

	# Drawn here rather than when the player reaches the arena, so it is decided by the floor's
	# seed alone. Drawing it on arrival would make which boss you fight depend on how the RNG
	# had been consumed getting there, and one `--seed` would stop reproducing the whole run.
	_boss_encounter = _draw_boss_encounter()

	_instantiate_rooms()
	_instantiate_doors()
	_place_player_in_start_room()
	return true


## Which boss guards this floor. Null before `build()` has run.
func get_boss_encounter() -> BossEncounter:
	return _boss_encounter


## Picks this floor's boss from its pool, preferring one the run has not fought yet.
##
## The preference is what turns two independent rolls into a shuffle: with two bosses and two
## floors, whichever the Help Desk draws, Development is left with the other. Falling back to
## the full pool when everything has been fought — rather than returning null — is what keeps a
## hypothetical third floor working: a repeated boss is a worse run than a boss-less one is a
## broken one.
func _draw_boss_encounter() -> BossEncounter:
	var unfought: Array[BossEncounter] = []
	var all: Array[BossEncounter] = []
	for entry: BossEncounter in config.boss_pool:
		if entry == null or not entry.is_valid():
			continue
		all.append(entry)
		if entry.id not in RunManager.fought_boss_ids:
			unfought.append(entry)

	var candidates := unfought if not unfought.is_empty() else all
	if candidates.is_empty():
		return null

	var drawn := candidates[_rng.randi_range(0, candidates.size() - 1)]
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
		_rooms_container.add_child(room)

		room.build(plan, config.theme)
		if plan.type == RoomTemplate.Type.COMBAT:
			room.populate(config, _rng)
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
func _stock_shop(room: Room) -> void:
	var positions := room.get_shop_positions()
	if config.shop == null or positions.is_empty():
		return
	var shop: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	room.add_child(shop)
	shop.stock(config.shop, config.get_items(), positions, _rng.randi())


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
			_doors_container.add_child(door)
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


func _on_player_entered_room(room: Room) -> void:
	if room.plan.id == current_room_id:
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
	EventBus.boss_defeated.connect(_on_boss_defeated.bind(room), CONNECT_ONE_SHOT)
	# Deferred, for the fourth time in this project and the same reason every time: rooms
	# are entered through an Area2D trigger, and registering the boss's collision bodies
	# while the physics server is flushing queries is refused outright.
	_add_boss.call_deferred(room)


func _add_boss(room: Room) -> void:
	if not is_instance_valid(_boss) or not is_instance_valid(room):
		return
	room.add_child(_boss)
	_boss.begin(room.get_interior_rect())


## Spec section 16's reward: three rare items on stands, and taking one closes the others.
## Winning the run waits on that choice rather than on the killing blow, so the player is
## never shown a victory screen with an unclaimed prize behind it.
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
## view — "this floor is done" — so both call sites funnel through here rather than deciding
## for themselves. `config.next_floor == null` is what makes a floor the run's last one.
func _finish_floor() -> void:
	if config.next_floor == null:
		GameManager.win_run.call_deferred()
		return
	_advance_to_next_floor.call_deferred(config.next_floor, _derive_next_seed(RunManager.floor_seed))


## Tears down the current floor and rebuilds this same controller from `next_config`. Deferred
## by the caller because this runs from inside a pickup's physics callback (the boss reward
## stand), and this project has hit "touching physics bodies while the server is flushing
## queries is refused outright" enough times already (see `_add_boss`, `LootSpawner`) that
## rebuilding synchronously in that same callback is not worth risking again.
func _advance_to_next_floor(next_config: FloorConfig, seed_value: int) -> void:
	_teardown()
	config = next_config
	if not build(_player, seed_value):
		# Same stance as main.gd's own build() call: a content bug, not something to hide
		# behind a blank screen.
		push_error("FloorController: floor generation failed advancing to floor %d." % next_config.floor_number)
		return
	floor_advanced.emit(config)


## Clears every piece of the floor that `build()` creates, so it can be called a second time.
## Rooms and doors are freed rather than reused: a `Room` carries its own combat/spawn state,
## and rebuilding it from scratch is simpler than resetting it in place. Freeing is safe here
## because every signal a `Room`/`RoomCombat` connects is local to its own subtree — nothing
## outlives it that needs disconnecting first.
func _teardown() -> void:
	for room: Room in _rooms.values():
		room.queue_free()
	for doors: Array in _doors_by_room.values():
		for door: Door in doors:
			if is_instance_valid(door):
				door.queue_free()
	_rooms.clear()
	_doors_by_room.clear()
	_cleared.clear()
	visited.clear()
	current_room_id = -1
	_clears = 0
	_boss = null


## Deterministic from the floor it follows, so a run is still fully reproducible from its
## opening seed, but decorrelated from it rather than an obvious "plus one" — a floor's seed
## should not read as a function of the last one when compared in the debug overlay.
func _derive_next_seed(seed_value: int) -> int:
	return absi(hash(seed_value))


## Rare items by preference, because that is what spec section 16 promises. Falls back to
## whatever the pool has left rather than offering fewer than three — a floor generous
## enough to have exhausted its rares has earned the choice anyway.
func _draw_boss_reward() -> Array[ItemConfig]:
	var rares: Array[ItemConfig] = []
	var rest: Array[ItemConfig] = []
	for item: ItemConfig in config.get_items():
		if item == null or item.id in RunManager.offered_item_ids:
			continue
		if item.rarity >= ItemConfig.Rarity.RARE:
			rares.append(item)
		else:
			rest.append(item)

	var chosen: Array[ItemConfig] = []
	for pool: Array in [rares, rest]:
		for item: ItemConfig in pool:
			if chosen.size() >= BOSS_REWARD_COUNT:
				break
			chosen.append(item)
			RunManager.offered_item_ids.append(item.id)
	return chosen


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
	_loot.spawn_room_reward(room.get_reward_position(), include_repair)

	# Items are the reason to keep fighting rather than to run for the exit, so most of a
	# floor's items come from clearing rooms rather than from the one treasure vault.
	if _clears in config.item_clear_indices:
		_loot.spawn_item(room.get_reward_position() + ITEM_REWARD_OFFSET)


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
		_loot.spawn_treasure(room.get_reward_position())
	else:
		_loot.spawn_room_reward(room.get_reward_position(), true)


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
